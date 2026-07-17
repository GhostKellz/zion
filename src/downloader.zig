const std = @import("std");
const Allocator = std.mem.Allocator;
const crypto = std.crypto;
const Dir = std.Io.Dir;
const Io = std.Io;
const zion_root = @import("root.zig");
const github = @import("github.zig");

/// Maximum size of downloaded content (100MB)
const MAX_DOWNLOAD_SIZE = 100 * 1024 * 1024;

pub fn validateDownloadUrl(url: []const u8) !void {
    const uri = std.Uri.parse(url) catch return error.InvalidDownloadUrl;
    if (uri.user != null or uri.password != null) return error.CredentialsInUrl;
    const host_component = uri.host orelse return error.InvalidDownloadUrl;
    const host = switch (host_component) {
        .raw => |value| value,
        .percent_encoded => |value| if (std.mem.indexOfScalar(u8, value, '%') == null) value else return error.InvalidDownloadUrl,
    };
    if (std.mem.eql(u8, uri.scheme, "https")) return;
    if (!std.mem.eql(u8, uri.scheme, "http")) return error.InsecureDownloadUrl;
    if (!std.mem.eql(u8, host, "localhost") and !std.mem.eql(u8, host, "127.0.0.1") and !std.mem.eql(u8, host, "[::1]")) {
        return error.InsecureDownloadUrl;
    }
}

/// Result of a package download operation
pub const DownloadResult = struct {
    url: []const u8,
    hash: []const u8,
    cache_path: []const u8,

    pub fn deinit(self: *const DownloadResult, allocator: Allocator) void {
        allocator.free(self.url);
        allocator.free(self.hash);
        allocator.free(self.cache_path);
    }
};

pub fn cachePathForUrl(allocator: Allocator, package_name: []const u8, url: []const u8) ![]const u8 {
    var url_hash: [crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(url, &url_hash, .{});
    const url_hash_hex = std.fmt.bytesToHex(url_hash[0..8], .lower);

    const sanitized_name = try sanitizePackageRef(allocator, package_name);
    defer allocator.free(sanitized_name);

    return std.fmt.allocPrint(allocator, ".zion/cache/{s}-{s}.tar.gz", .{ sanitized_name, url_hash_hex });
}

/// Sanitizes a package reference for use as a filename
fn sanitizePackageRef(allocator: Allocator, package_ref: []const u8) ![]const u8 {
    var result = try allocator.alloc(u8, package_ref.len);
    for (package_ref, 0..) |char, i| {
        result[i] = if (char == '/') '_' else char;
    }
    return result;
}

/// Resolves a package reference (e.g. "mitchellh/libxev") to a GitHub URL using the GitHub API
pub fn resolveGitHubUrl(allocator: Allocator, package_ref: []const u8) ![]const u8 {
    // Check if it's a GitHub reference (username/repo format)
    const slash_index = std.mem.indexOf(u8, package_ref, "/");
    if (slash_index == null) {
        return error.InvalidPackageReference;
    }

    // Try to get the latest version from GitHub API
    if (github.getLatestVersion(allocator, package_ref)) |latest_version_const| {
        var latest_version = latest_version_const;
        defer latest_version.deinit(allocator);
        return allocator.dupe(u8, latest_version.url);
    } else |err| {
        // Fallback to main branch if no releases/tags found
        switch (err) {
            error.NoVersionsFound => {
                std.debug.print("📝 No releases or tags found, using main branch\n", .{});
            },
            else => {
                std.debug.print("⚠️  GitHub API error ({}), falling back to main branch\n", .{err});
            },
        }
        return std.fmt.allocPrint(allocator, "https://github.com/{s}/archive/refs/heads/main.tar.gz", .{package_ref});
    }
}

/// Test if a URL exists using a HEAD request
fn testUrlExists(_: Allocator, url: []const u8) bool {
    const io = zion_root.getIo() catch return false;

    const argv = [_][]const u8{
        "curl",
        "-I", // HEAD request only
        "-L", // Follow redirects
        "-s", // Silent mode
        "--fail", // Fail silently on HTTP errors
        "--max-time", "10", // 10 second timeout
        url,
    };

    const child = std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return false;

    var child_mut = child;
    const term = child_mut.wait(io) catch return false;
    switch (term) {
        .exited => |code| return code == 0,
        else => return false,
    }
}

/// Downloads a package tarball for a specific version from GitHub API
pub fn downloadAndHashPackageVersion(allocator: Allocator, package_ref: []const u8, version: []const u8) !DownloadResult {
    // Get the specific version from GitHub API
    var version_info = try github.findVersion(allocator, package_ref, version);
    defer version_info.deinit(allocator);

    return downloadFromUrl(allocator, version_info.url, package_ref);
}

/// Downloads a package tarball from a URL, saves it to cache, and calculates its SHA256 hash
/// Includes performance monitoring and smart caching - uses latest version from GitHub API
pub fn downloadAndHashPackage(allocator: Allocator, package_ref: []const u8) !DownloadResult {
    // Resolve GitHub URL using API
    const url = try resolveGitHubUrl(allocator, package_ref);
    defer allocator.free(url);

    return downloadFromUrl(allocator, url, package_ref);
}

/// Ensures the .zion/cache directory exists
pub fn ensureCacheDir(_: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Create .zion directory if it doesn't exist
    cwd.createDir(io, ".zion", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    // Create .zion/cache directory if it doesn't exist
    cwd.createDir(io, ".zion/cache", .default_dir) catch |err| {
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
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const file = try cwd.openFile(io, file_path, .{});
    defer file.close(io);

    std.debug.print("Calculating SHA256 hash for {s}...\n", .{file_path});

    // Calculate the hash with larger buffer for better I/O performance
    var hash = crypto.hash.sha2.Sha256.init(.{});
    var buffer: [65536]u8 = undefined; // Increased from 8KB to 64KB

    while (true) {
        const bytes_read = file.readStreaming(io, &.{buffer[0..]}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (bytes_read == 0) break;
        hash.update(buffer[0..bytes_read]);
    }

    // Get the digest
    var digest: [crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hash.final(&digest);

    // Convert the digest to hexadecimal
    const hex_digest = try std.fmt.allocPrint(allocator, "{x}", .{digest});

    std.debug.print("Hash: {s}\n", .{hex_digest});
    return hex_digest;
}

/// Option to use curl instead of std.http, using a subprocess
/// This implementation is a fallback in case std.http has issues
pub fn downloadWithCurl(allocator: Allocator, url: []const u8, output_path: []const u8) !void {
    const io = try zion_root.getIo();
    try validateDownloadUrl(url);
    std.debug.print("Downloading with curl: {s}...\n", .{url});

    const argv = [_][]const u8{
        "curl",
        "-L",
        "--proto",
        "=http,https",
        "--proto-redir",
        "=https",
        "--max-filesize",
        "104857600",
        "-o",
        output_path,
        url,
    };

    // Create the child process
    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // Read output using scatter/gather API
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(allocator);

    if (child.stderr) |stderr_pipe| {
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = stderr_pipe.readStreaming(io, &.{read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stderr_buf.appendSlice(allocator, read_buf[0..bytes_read]);
        }
    }

    // Wait for the process to complete
    const term = try child.wait(io);

    // Check exit code - success is 0
    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("curl failed with exit code {d}: {s}\n", .{ code, stderr_buf.items });
                return error.DownloadFailed;
            }
        },
        else => {
            std.debug.print("curl terminated abnormally: {s}\n", .{stderr_buf.items});
            return error.DownloadFailed;
        },
    }

    std.debug.print("Download completed successfully\n", .{});
}

/// Improved curl-based downloader with better error handling and validation
pub fn downloadWithCurlImproved(allocator: Allocator, url: []const u8, output_path: []const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    try validateDownloadUrl(url);
    std.debug.print("Downloading {s}...\n", .{url});

    // Ensure output directory exists
    if (Dir.path.dirname(output_path)) |dir| {
        try cwd.createDirPath(io, dir);
    }

    var random_bytes: [8]u8 = undefined;
    io.random(&random_bytes);
    const suffix = std.fmt.bytesToHex(random_bytes, .lower);
    const partial_path = try std.fmt.allocPrint(allocator, "{s}.partial-{s}", .{ output_path, suffix });
    defer allocator.free(partial_path);
    defer cwd.deleteFile(io, partial_path) catch {};

    const argv = [_][]const u8{
        "curl",
        "-L",
        "-f", // Fail on HTTP errors
        "--proto",
        "=http,https",
        "--proto-redir",
        "=https",
        "--max-redirs",
        "3",
        "--max-filesize",
        "104857600",
        "--retry", "3", // Retry on failure
        "--retry-delay", "2", // Delay between retries
        "--max-time", "300", // 5 minute timeout
        "-o",         partial_path,
        url,
    };

    // Create the child process
    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // Read stderr for error messages using scatter/gather API
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(allocator);

    if (child.stderr) |stderr_pipe| {
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = stderr_pipe.readStreaming(io, &.{read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stderr_buf.appendSlice(allocator, read_buf[0..bytes_read]);
        }
    }

    // Wait for the process to complete
    const term = try child.wait(io);

    // Check exit code - success is 0
    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("curl failed with exit code {d}: {s}\n", .{ code, stderr_buf.items });
                return error.DownloadFailed;
            }
        },
        else => {
            std.debug.print("curl terminated abnormally: {s}\n", .{stderr_buf.items});
            return error.DownloadFailed;
        },
    }

    // Verify the file was actually created and has content
    const file = cwd.openFile(io, partial_path, .{}) catch {
        std.debug.print("Downloaded file was not created\n", .{});
        return error.DownloadFailed;
    };
    defer file.close(io);

    const file_size = try file.length(io);
    if (file_size == 0) {
        std.debug.print("Downloaded file is empty\n", .{});
        return error.DownloadFailed;
    }
    if (file_size > MAX_DOWNLOAD_SIZE) return error.DownloadTooLarge;

    try std.Io.Dir.rename(cwd, partial_path, cwd, output_path, io);

    std.debug.print("Successfully downloaded {d} bytes\n", .{file_size});
}

/// Fallback downloader using wget (if curl fails)
pub fn downloadWithWget(_: Allocator, url: []const u8, output_path: []const u8) !void {
    const io = try zion_root.getIo();
    std.debug.print("Trying wget for {s}...\n", .{url});

    const argv = [_][]const u8{
        "wget",
        "-O",
        output_path,
        "--timeout=300",
        "--tries=3",
        url,
    };

    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
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
    return downloadWithCurlImproved(allocator, url, output_path);
}

test "download URL policy rejects credentials and insecure remote transport" {
    try validateDownloadUrl("https://example.test/package.tar.gz");
    try validateDownloadUrl("http://127.0.0.1:8080/package.tar.gz");
    try std.testing.expectError(error.InsecureDownloadUrl, validateDownloadUrl("http://example.test/package.tar.gz"));
    try std.testing.expectError(error.InsecureDownloadUrl, validateDownloadUrl("file:///etc/passwd"));
    try std.testing.expectError(error.CredentialsInUrl, validateDownloadUrl("https://user:secret@example.test/package.tar.gz"));
}

/// Downloads a package from a provided URL (does NOT re-resolve via GitHub)
/// Use this when you already have a resolved URL from registry lookup
pub fn downloadFromUrl(allocator: Allocator, url: []const u8, package_name: []const u8) !DownloadResult {
    // Create cache directory if it doesn't exist
    try ensureCacheDir(allocator);

    const cache_path = try cachePathForUrl(allocator, package_name, url);
    errdefer allocator.free(cache_path);

    // Check if we already have this cached
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const cached_file_exists = blk: {
        cwd.access(io, cache_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                break :blk false;
            }
            return err;
        };
        break :blk true;
    };

    if (!cached_file_exists) {
        // Download the tarball with performance monitoring
        const start_time = zion_root.milliTimestamp();

        try downloadWithCurlImproved(allocator, url, cache_path);

        const end_time = zion_root.milliTimestamp();
        const download_time = end_time - start_time;

        // Get file size for speed calculation
        const file = try cwd.openFile(io, cache_path, .{});
        defer file.close(io);
        const file_size = try file.length(io);

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

    const url_copy = try allocator.dupe(u8, url);
    errdefer allocator.free(url_copy);

    return DownloadResult{
        .url = url_copy,
        .hash = hash,
        .cache_path = cache_path,
    };
}

test "cache path identity uses resolved url" {
    const allocator = std.testing.allocator;

    const a = try cachePathForUrl(allocator, "libxev", "https://github.com/mitchellh/libxev/archive/refs/tags/v0.1.0.tar.gz");
    defer allocator.free(a);
    const b = try cachePathForUrl(allocator, "libxev", "https://github.com/mitchellh/libxev/archive/refs/tags/v0.2.0.tar.gz");
    defer allocator.free(b);
    const c = try cachePathForUrl(allocator, "libxev", "https://github.com/mitchellh/libxev/archive/refs/tags/v0.1.0.tar.gz");
    defer allocator.free(c);

    try std.testing.expect(!std.mem.eql(u8, a, b));
    try std.testing.expect(std.mem.eql(u8, a, c));
}
