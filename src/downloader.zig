const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const crypto = std.crypto;

/// Maximum size of downloaded content (100MB)
const MAX_DOWNLOAD_SIZE = 100 * 1024 * 1024;

/// Result of a package download operation
pub const DownloadResult = struct {
    url: []const u8,
    hash: []const u8,
    cache_path: []const u8,

    pub fn deinit(self: *DownloadResult, allocator: Allocator) void {
        allocator.free(self.url);
        allocator.free(self.hash);
        allocator.free(self.cache_path);
    }
};

/// Sanitizes a package reference for use as a filename
fn sanitizePackageRef(allocator: Allocator, package_ref: []const u8) ![]const u8 {
    var result = try allocator.alloc(u8, package_ref.len);
    for (package_ref, 0..) |char, i| {
        result[i] = if (char == '/') '_' else char;
    }
    return result;
}

/// Resolves a package reference (e.g. "mitchellh/libxev") to a GitHub URL
pub fn resolveGitHubUrl(allocator: Allocator, package_ref: []const u8) ![]const u8 {
    // Check if it's a GitHub reference (username/repo format)
    const slash_index = std.mem.indexOf(u8, package_ref, "/");
    if (slash_index == null) {
        return error.InvalidPackageReference;
    }

    // Try to detect the default branch by testing common ones
    const branches = [_][]const u8{ "main", "master" };

    for (branches) |branch| {
        const test_url = try std.fmt.allocPrint(allocator, "https://github.com/{s}/archive/refs/heads/{s}.tar.gz", .{ package_ref, branch });

        // Test if this URL works with a quick HEAD request
        if (testUrlExists(allocator, test_url)) {
            return test_url;
        } else {
            allocator.free(test_url);
        }
    }

    // Fallback to main if detection fails
    return std.fmt.allocPrint(allocator, "https://github.com/{s}/archive/refs/heads/main.tar.gz", .{package_ref});
}

/// Test if a URL exists using a HEAD request
fn testUrlExists(allocator: Allocator, url: []const u8) bool {
    const argv = [_][]const u8{
        "curl",
        "-I", // HEAD request only
        "-L", // Follow redirects
        "-s", // Silent mode
        "--fail", // Fail silently on HTTP errors
        "--max-time", "10", // 10 second timeout
        url,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    if (child.spawn()) {
        const term = child.wait() catch return false;
        switch (term) {
            .Exited => |code| return code == 0,
            else => return false,
        }
    } else |_| {
        return false;
    }
}

/// Downloads a package tarball from a URL, saves it to cache, and calculates its SHA256 hash
/// Includes performance monitoring and smart caching
pub fn downloadAndHashPackage(allocator: Allocator, package_ref: []const u8) !DownloadResult {
    // Create cache directory if it doesn't exist
    try ensureCacheDir(allocator);

    // Resolve GitHub URL
    const url = try resolveGitHubUrl(allocator, package_ref);
    errdefer allocator.free(url);

    // Generate a unique cache path for this package
    const sanitized_ref = try sanitizePackageRef(allocator, package_ref);
    defer allocator.free(sanitized_ref);
    const cache_path = try std.fmt.allocPrint(allocator, ".zion/cache/{s}.tar.gz", .{sanitized_ref});
    errdefer allocator.free(cache_path);

    // Check if we already have this cached
    const cached_file_exists = blk: {
        fs.cwd().access(cache_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                break :blk false;
            }
            return err;
        };
        break :blk true;
    };

    if (!cached_file_exists) {
        // Download the tarball with performance monitoring
        const start_time = std.time.milliTimestamp();

        try downloadWithCurlImproved(allocator, url, cache_path);

        const end_time = std.time.milliTimestamp();
        const download_time = end_time - start_time;

        // Get file size for speed calculation
        const file = try fs.cwd().openFile(cache_path, .{});
        defer file.close();
        const file_size = try file.getEndPos();

        if (download_time > 0) {
            const speed_mbps = (@as(f64, @floatFromInt(file_size)) / 1024.0 / 1024.0) / (@as(f64, @floatFromInt(download_time)) / 1000.0);
            std.debug.print("📊 Download speed: {d:.1} MB/s\n", .{speed_mbps});
        }
    } else {
        std.debug.print("💾 Using cached package: {s}\n", .{cache_path});
    }

    // Calculate SHA256 hash of the downloaded file
    const hash = try calculateFileHash(allocator, cache_path);
    errdefer allocator.free(hash);

    return DownloadResult{
        .url = url,
        .hash = hash,
        .cache_path = cache_path,
    };
}

/// Ensures the .zion/cache directory exists
pub fn ensureCacheDir(_: Allocator) !void {
    const cwd = fs.cwd();

    // Create .zion directory if it doesn't exist
    cwd.makeDir(".zion") catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    // Create .zion/cache directory if it doesn't exist
    cwd.makeDir(".zion/cache") catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
}

/// Downloads a file from a URL to a local path
pub fn downloadFile(allocator: Allocator, url: []const u8, output_path: []const u8) !void {
    std.debug.print("Downloading {s}...\n", .{url});

    // Use curl instead of std.http due to API changes
    return downloadWithCurl(allocator, url, output_path);
}

/// Calculates SHA256 hash of a file
pub fn calculateFileHash(allocator: Allocator, file_path: []const u8) ![]const u8 {
    const cwd = fs.cwd();
    const file = try cwd.openFile(file_path, .{});
    defer file.close();

    std.debug.print("Calculating SHA256 hash for {s}...\n", .{file_path});

    // Calculate the hash
    var hash = crypto.hash.sha2.Sha256.init(.{});
    var buffer: [8192]u8 = undefined;

    while (true) {
        const bytes_read = try file.readAll(buffer[0..]);
        if (bytes_read == 0) break;
        hash.update(buffer[0..bytes_read]);
    }

    // Get the digest
    var digest: [crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hash.final(&digest);

    // Convert the digest to hexadecimal
    const hex_digest = try allocator.alloc(u8, digest.len * 2);
    _ = try std.fmt.bufPrint(hex_digest, "{s}", .{std.fmt.fmtSliceHexLower(&digest)});

    std.debug.print("Hash: {s}\n", .{hex_digest});
    return hex_digest;
}

/// Option to use curl instead of std.http, using a subprocess
/// This implementation is a fallback in case std.http has issues
pub fn downloadWithCurl(allocator: Allocator, url: []const u8, output_path: []const u8) !void {
    std.debug.print("Downloading with curl: {s}...\n", .{url});

    const argv = [_][]const u8{
        "curl",
        "-L", // Follow redirects
        "-o",
        output_path,
        url,
    };

    // Create the child process
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Wait for the process to complete
    const term = try child.wait();

    // Read output
    const stderr = if (child.stderr) |stderr_pipe|
        try stderr_pipe.reader().readAllAlloc(allocator, 10 * 1024 * 1024)
    else
        try allocator.dupe(u8, "No error output available");
    defer allocator.free(stderr);

    // Check exit code - success is 0
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("curl failed with exit code {d}: {s}\n", .{ code, stderr });
                return error.DownloadFailed;
            }
        },
        else => {
            std.debug.print("curl terminated abnormally: {s}\n", .{stderr});
            return error.DownloadFailed;
        },
    }

    std.debug.print("Download completed successfully\n", .{});
}

/// Improved curl-based downloader with better error handling and validation
pub fn downloadWithCurlImproved(allocator: Allocator, url: []const u8, output_path: []const u8) !void {
    std.debug.print("Downloading {s}...\n", .{url});

    // Ensure output directory exists
    if (fs.path.dirname(output_path)) |dir| {
        try fs.cwd().makePath(dir);
    }

    const argv = [_][]const u8{
        "curl",
        "-L", // Follow redirects
        "-f", // Fail on HTTP errors
        "--retry", "3", // Retry on failure
        "--retry-delay", "2", // Delay between retries
        "--max-time", "300", // 5 minute timeout
        "-o",         output_path,
        url,
    };

    // Create the child process
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Wait for the process to complete
    const term = try child.wait();

    // Read stderr for error messages
    const stderr = if (child.stderr) |stderr_pipe|
        try stderr_pipe.reader().readAllAlloc(allocator, 10 * 1024 * 1024)
    else
        try allocator.dupe(u8, "No error output available");
    defer allocator.free(stderr);

    // Check exit code - success is 0
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("curl failed with exit code {d}: {s}\n", .{ code, stderr });
                // Try wget as fallback
                return downloadWithWget(allocator, url, output_path);
            }
        },
        else => {
            std.debug.print("curl terminated abnormally: {s}\n", .{stderr});
            return error.DownloadFailed;
        },
    }

    // Verify the file was actually created and has content
    const file = fs.cwd().openFile(output_path, .{}) catch {
        std.debug.print("Downloaded file not found: {s}\n", .{output_path});
        return error.DownloadFailed;
    };
    defer file.close();

    const file_size = try file.getEndPos();
    if (file_size == 0) {
        std.debug.print("Downloaded file is empty: {s}\n", .{output_path});
        return error.DownloadFailed;
    }

    std.debug.print("Successfully downloaded {d} bytes\n", .{file_size});
}

/// Fallback downloader using wget (if curl fails)
pub fn downloadWithWget(allocator: Allocator, url: []const u8, output_path: []const u8) !void {
    std.debug.print("Trying wget for {s}...\n", .{url});

    const argv = [_][]const u8{
        "wget",
        "-O",
        output_path,
        "--timeout=300",
        "--tries=3",
        url,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("wget also failed with exit code {d}\n", .{code});
                return error.DownloadFailed;
            }
        },
        else => {
            return error.DownloadFailed;
        },
    }
}

/// Smart downloader that tries curl first, then wget as fallback
pub fn downloadSmart(allocator: Allocator, url: []const u8, output_path: []const u8) !void {
    downloadWithCurlImproved(allocator, url, output_path) catch |err| {
        std.debug.print("curl failed, trying wget...\n", .{});
        return downloadWithWget(allocator, url, output_path) catch {
            return err;
        };
    };
}
