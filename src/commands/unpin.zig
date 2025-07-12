const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const Dependency = @import("../manifest.zig").Dependency;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");
const github = @import("../github.zig");

/// Unpin a dependency to track the latest version (main/master branch)
pub fn unpin(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: 'zion unpin' requires a package name\n", .{});
        std.debug.print("Usage: zion unpin <package>\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  zion unpin libxev\n", .{});
        std.debug.print("  zion unpin zcrypto\n", .{});
        return;
    }

    const package_name = args[2];
    
    std.debug.print("🔓 Unpinning {s} to track latest...\n", .{package_name});
    
    // Check if build.zig.zon exists
    const zon_path = "build.zig.zon";
    const cwd = fs.cwd();
    
    cwd.access(zon_path, .{}) catch |err| {
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
    
    std.debug.print("🔍 Getting latest version for {s}...\n", .{package_ref});
    
    // Get the latest version (fallback to main if no releases/tags)
    var latest_version = github.getLatestVersion(allocator, package_ref) catch |err| {
        switch (err) {
            error.NoVersionsFound => {
                std.debug.print("⚠️  No releases or tags found, using main branch\n", .{});
                // Generate main branch URL
                const main_url = try github.generateTarballUrl(allocator, package_ref, "main");
                defer allocator.free(main_url);
                
                return updateToMainBranch(allocator, &zon_file, zon_path, package_name, existing_dep, main_url);
            },
            else => {
                std.debug.print("Error: Failed to fetch version information: {}\n", .{err});
                return err;
            },
        }
    };
    defer latest_version.deinit(allocator);
    
    std.debug.print("✅ Latest version: {s}\n", .{latest_version.version});
    std.debug.print("   URL: {s}\n", .{latest_version.url});
    
    // Check if already using this version
    if (std.mem.eql(u8, existing_dep.url, latest_version.url)) {
        std.debug.print("📌 Package {s} is already tracking the latest version ({s})\n", .{ package_name, latest_version.version });
        return;
    }
    
    // Download and hash the latest version
    std.debug.print("⬇️  Downloading latest version...\n", .{});
    
    const cache_path = try std.fmt.allocPrint(allocator, ".zion/cache/{s}-latest.tar.gz", .{package_name});
    defer allocator.free(cache_path);
    
    // Download the package
    try downloader.ensureCacheDir(allocator);
    try downloader.downloadWithCurlImproved(allocator, latest_version.url, cache_path);
    
    // Calculate hash
    const new_hash = try downloader.calculateFileHash(allocator, cache_path);
    defer allocator.free(new_hash);
    
    std.debug.print("🔐 Calculated hash: {s}\n", .{new_hash[0..16]});
    
    // Update the dependency
    const old_url = existing_dep.url;
    const old_hash = existing_dep.hash;
    
    existing_dep.url = try allocator.dupe(u8, latest_version.url);
    existing_dep.hash = try allocator.dupe(u8, new_hash);
    
    // Clean up old strings
    allocator.free(old_url);
    allocator.free(old_hash);
    
    // Save updated ZON file
    try zon_file.saveToFile(zon_path);
    
    // Update lock file (remove pinned version info)
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();
    
    try lock_file.addPackage(package_name, latest_version.url, new_hash, null); // null version = unpinned
    try lock_file.saveToFile();
    
    // Extract to deps directory
    const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
    defer allocator.free(deps_path);
    
    std.debug.print("📁 Extracting to {s}...\n", .{deps_path});
    try extractTarball(allocator, cache_path, deps_path);
    
    std.debug.print("🎉 Successfully unpinned {s} - now tracking latest ({s})\n", .{ package_name, latest_version.version });
    std.debug.print("   URL: {s}\n", .{latest_version.url});
    std.debug.print("   Hash: {s}\n", .{new_hash[0..16]});
    std.debug.print("\n💡 To pin to a specific version: zion pin {s}@<version>\n", .{package_name});
}

/// Update dependency to use main branch when no releases/tags are available
fn updateToMainBranch(
    allocator: Allocator,
    zon_file: *ZonFile,
    zon_path: []const u8,
    package_name: []const u8,
    existing_dep: *Dependency,
    main_url: []const u8
) !void {
    // Check if already using main branch
    if (std.mem.eql(u8, existing_dep.url, main_url)) {
        std.debug.print("📌 Package {s} is already tracking main branch\n", .{package_name});
        return;
    }
    
    // Download and hash main branch
    std.debug.print("⬇️  Downloading main branch...\n", .{});
    
    const cache_path = try std.fmt.allocPrint(allocator, ".zion/cache/{s}-main.tar.gz", .{package_name});
    defer allocator.free(cache_path);
    
    // Download the package
    try downloader.ensureCacheDir(allocator);
    try downloader.downloadWithCurlImproved(allocator, main_url, cache_path);
    
    // Calculate hash
    const new_hash = try downloader.calculateFileHash(allocator, cache_path);
    defer allocator.free(new_hash);
    
    std.debug.print("🔐 Calculated hash: {s}\n", .{new_hash[0..16]});
    
    // Update the dependency
    const old_url = existing_dep.url;
    const old_hash = existing_dep.hash;
    
    existing_dep.url = try allocator.dupe(u8, main_url);
    existing_dep.hash = try allocator.dupe(u8, new_hash);
    
    // Clean up old strings
    allocator.free(old_url);
    allocator.free(old_hash);
    
    // Save updated ZON file
    try zon_file.saveToFile(zon_path);
    
    // Update lock file
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();
    
    try lock_file.addPackage(package_name, main_url, new_hash, null); // null version = unpinned
    try lock_file.saveToFile();
    
    // Extract to deps directory
    const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
    defer allocator.free(deps_path);
    
    std.debug.print("📁 Extracting to {s}...\n", .{deps_path});
    try extractTarball(allocator, cache_path, deps_path);
    
    std.debug.print("🎉 Successfully unpinned {s} - now tracking main branch\n", .{package_name});
    std.debug.print("   URL: {s}\n", .{main_url});
    std.debug.print("   Hash: {s}\n", .{new_hash[0..16]});
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
    const cwd = fs.cwd();
    
    // Remove existing directory if it exists
    cwd.deleteTree(dest_path) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };
    
    // Create destination directory
    try cwd.makePath(dest_path);
    
    // Use tar to extract
    const argv = [_][]const u8{
        "tar",
        "-xzf",
        tarball_path,
        "-C",
        dest_path,
        "--strip-components=1",
    };
    
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    const term = try child.wait();
    
    // Read stderr for error messages
    var output_buf = std.ArrayList(u8).init(allocator);
    defer output_buf.deinit();
    
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try child.stderr.?.readAll(read_buf[0..]);
        if (bytes_read == 0) break;
        try output_buf.appendSlice(read_buf[0..bytes_read]);
    }
    
    const stderr = try allocator.dupe(u8, output_buf.items);
    defer allocator.free(stderr);
    
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("tar extraction failed (exit code {d}): {s}\n", .{ code, stderr });
                return error.ExtractionFailed;
            }
        },
        else => {
            std.debug.print("tar extraction terminated abnormally: {s}\n", .{stderr});
            return error.ExtractionFailed;
        },
    }
}