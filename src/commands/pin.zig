const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const Dependency = @import("../manifest.zig").Dependency;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");
const github = @import("../github.zig");
const zion_root = @import("../root.zig");
const tar_extract = @import("../tar_extract.zig");

/// Pin a dependency to a specific version
pub fn pin(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: 'zion pin' requires a package and version\n", .{});
        std.debug.print("Usage: zion pin <package>@<version>\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  zion pin libxev@0.2.0\n", .{});
        std.debug.print("  zion pin zcrypto@v1.0.1\n", .{});
        return;
    }

    const pin_spec = args[2];

    // Parse package@version format
    const at_index = std.mem.lastIndexOf(u8, pin_spec, "@") orelse {
        std.debug.print("Error: Invalid pin format. Use <package>@<version>\n", .{});
        std.debug.print("Example: zion pin libxev@0.2.0\n", .{});
        return;
    };

    const package_name = pin_spec[0..at_index];
    const target_version = pin_spec[at_index + 1 ..];

    if (package_name.len == 0 or target_version.len == 0) {
        std.debug.print("Error: Both package name and version must be specified\n", .{});
        return;
    }

    std.debug.print("📌 Pinning {s} to version {s}...\n", .{ package_name, target_version });

    // Check if build.zig.zon exists
    const zon_path = "build.zig.zon";
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    cwd.access(io, zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Load existing ZON file
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();

    // Check if package exists in dependencies
    const existing_dep = zon_file.dependencies.getPtr(package_name) orelse {
        std.debug.print("Error: Package '{s}' not found in dependencies\n", .{package_name});
        std.debug.print("Add it first with: zion add <user/repo>\n", .{});
        return error.PackageNotFound;
    };

    // Extract package reference from existing URL
    const package_ref = try extractPackageRefFromUrl(allocator, existing_dep.url);
    defer allocator.free(package_ref);

    std.debug.print("🔍 Looking up version {s} for {s}...\n", .{ target_version, package_ref });

    // Find the specific version
    var version_info = github.findVersion(allocator, package_ref, target_version) catch |err| {
        switch (err) {
            error.VersionNotFound => {
                std.debug.print("Error: Version '{s}' not found for package '{s}'\n", .{ target_version, package_ref });
                std.debug.print("Run 'zion info {s}' to see available versions\n", .{package_name});
                return err;
            },
            else => {
                std.debug.print("Error: Failed to fetch version information: {}\n", .{err});
                return err;
            },
        }
    };
    defer version_info.deinit(allocator);

    std.debug.print("✅ Found version {s}: {s}\n", .{ version_info.version, version_info.url });

    // Download and hash the specific version
    std.debug.print("⬇️  Downloading version {s}...\n", .{version_info.version});

    const cache_path = try std.fmt.allocPrint(allocator, ".zion/cache/{s}-{s}.tar.gz", .{ package_name, version_info.version });
    defer allocator.free(cache_path);

    // Download the package
    try downloader.ensureCacheDir(allocator);
    try downloader.downloadWithCurlImproved(allocator, version_info.url, cache_path);

    // Calculate hash
    const new_hash = try downloader.calculateFileHash(allocator, cache_path);
    defer allocator.free(new_hash);

    std.debug.print("🔐 Calculated hash: {s}\n", .{new_hash[0..16]});

    // Update the dependency
    const old_url = existing_dep.url;
    const old_hash = existing_dep.hash;

    existing_dep.url = try allocator.dupe(u8, version_info.url);
    existing_dep.hash = try allocator.dupe(u8, new_hash);

    // Clean up old strings
    allocator.free(old_url);
    allocator.free(old_hash);

    // Save updated ZON file
    try zon_file.saveToFile(zon_path);

    // Update lock file
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    try lock_file.addPackage(package_name, version_info.url, new_hash, version_info.version);
    try lock_file.saveToFile();

    // Extract to deps directory
    const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
    defer allocator.free(deps_path);

    std.debug.print("📁 Extracting to {s}...\n", .{deps_path});
    try tar_extract.extractPackage(allocator, cache_path, deps_path);

    std.debug.print("🎉 Successfully pinned {s} to version {s}\n", .{ package_name, version_info.version });
    std.debug.print("   URL: {s}\n", .{version_info.url});
    std.debug.print("   Hash: {s}\n", .{new_hash[0..16]});
    std.debug.print("\n💡 To unpin and track latest: zion unpin {s}\n", .{package_name});
}

/// Extract package reference (user/repo) from GitHub URL
fn extractPackageRefFromUrl(allocator: Allocator, url: []const u8) ![]const u8 {
    // Expected formats:
    // https://github.com/user/repo/archive/refs/heads/main.tar.gz
    // https://github.com/user/repo/archive/refs/tags/v1.0.0.tar.gz
    const github_prefix = "https://github.com/";

    if (!std.mem.startsWith(u8, url, github_prefix)) {
        return error.UnsupportedUrl;
    }

    const after_prefix = url[github_prefix.len..];

    // Find the end of user/repo part
    var parts = std.mem.splitScalar(u8, after_prefix, '/');
    const user = parts.next() orelse return error.InvalidGitHubUrl;
    const repo = parts.next() orelse return error.InvalidGitHubUrl;

    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ user, repo });
}

/// Extract a tarball to a destination directory
fn extractTarball(allocator: Allocator, tarball_path: []const u8, dest_path: []const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Remove existing directory if it exists
    cwd.deleteTree(io, dest_path) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };

    // Create destination directory
    try cwd.createDirPath(io, dest_path);

    // Use tar to extract
    const argv = [_][]const u8{
        "tar",
        "-xzf",
        tarball_path,
        "-C",
        dest_path,
        "--strip-components=1",
    };

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

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("tar extraction failed (exit code {d}): {s}\n", .{ code, stderr_buf.items });
                return error.ExtractionFailed;
            }
        },
        else => {
            std.debug.print("tar extraction terminated abnormally: {s}\n", .{stderr_buf.items});
            return error.ExtractionFailed;
        },
    }
}
