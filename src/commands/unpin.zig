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

/// Print help for unpin command
fn printHelp() void {
    std.debug.print(
        \\Unpin a dependency to track the latest version
        \\
        \\USAGE:
        \\    zion unpin <package> [OPTIONS]
        \\
        \\OPTIONS:
        \\    --to-main, -m    Track the repository's default branch instead of releases
        \\    --help, -h       Show this help message
        \\
        \\EXAMPLES:
        \\    zion unpin libxev              # Update to latest release/tag
        \\    zion unpin libxev --to-main    # Track default branch directly
        \\
        \\DESCRIPTION:
        \\    By default, unpin updates a dependency to the latest release or tag.
        \\    Use --to-main to track the default branch (main/master) for bleeding-edge updates.
        \\
    , .{});
}

/// Unpin a dependency to track the latest version (main/master branch)
pub fn unpin(allocator: Allocator, args: []const [:0]const u8) !void {
    // Check for help flag first
    if (args.len >= 3) {
        const arg = args[2];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return;
        }
    }

    if (args.len < 3) {
        printHelp();
        return;
    }

    const package_name = args[2];

    // Check for --to-main flag
    var use_default_branch = false;
    for (args[3..]) |arg| {
        if (std.mem.eql(u8, arg, "--to-main") or std.mem.eql(u8, arg, "-m")) {
            use_default_branch = true;
            break;
        }
    }

    if (use_default_branch) {
        std.debug.print("🔓 Unpinning {s} to track default branch...\n", .{package_name});
    } else {
        std.debug.print("🔓 Unpinning {s} to track latest...\n", .{package_name});
    }

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

    // If --to-main flag is used, skip version lookup and go directly to default branch
    if (use_default_branch) {
        std.debug.print("🔍 Detecting default branch for {s}...\n", .{package_ref});

        const branch_info = try github.generateDefaultBranchTarballUrl(allocator, package_ref);
        defer allocator.free(branch_info.url);
        defer allocator.free(branch_info.branch);

        std.debug.print("✅ Default branch: {s}\n", .{branch_info.branch});

        return updateToDefaultBranch(allocator, &zon_file, zon_path, package_name, existing_dep, branch_info.url, branch_info.branch);
    }

    std.debug.print("🔍 Getting latest version for {s}...\n", .{package_ref});

    // Get the latest version (fallback to main if no releases/tags)
    var latest_version = github.getLatestVersion(allocator, package_ref) catch |err| {
        switch (err) {
            error.NoVersionsFound => {
                std.debug.print("⚠️  No releases or tags found, detecting default branch...\n", .{});
                // Auto-detect default branch using GitHub API
                const branch_info = github.generateDefaultBranchTarballUrl(allocator, package_ref) catch {
                    // Fallback to "main" if detection fails
                    const main_url = try github.generateTarballUrl(allocator, package_ref, "main");
                    defer allocator.free(main_url);
                    return updateToDefaultBranch(allocator, &zon_file, zon_path, package_name, existing_dep, main_url, "main");
                };
                defer allocator.free(branch_info.url);
                defer allocator.free(branch_info.branch);

                std.debug.print("✅ Detected default branch: {s}\n", .{branch_info.branch});

                return updateToDefaultBranch(allocator, &zon_file, zon_path, package_name, existing_dep, branch_info.url, branch_info.branch);
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
    try tar_extract.extractPackage(allocator, cache_path, deps_path);

    std.debug.print("🎉 Successfully unpinned {s} - now tracking latest ({s})\n", .{ package_name, latest_version.version });
    std.debug.print("   URL: {s}\n", .{latest_version.url});
    std.debug.print("   Hash: {s}\n", .{new_hash[0..16]});
    std.debug.print("\n💡 To pin to a specific version: zion pin {s}@<version>\n", .{package_name});
}

/// Update dependency to use default branch (main/master/custom)
fn updateToDefaultBranch(allocator: Allocator, zon_file: *ZonFile, zon_path: []const u8, package_name: []const u8, existing_dep: *Dependency, branch_url: []const u8, branch_name: []const u8) !void {
    // Check if already using this branch
    if (std.mem.eql(u8, existing_dep.url, branch_url)) {
        std.debug.print("📌 Package {s} is already tracking {s} branch\n", .{ package_name, branch_name });
        return;
    }

    // Download and hash the branch
    std.debug.print("⬇️  Downloading {s} branch...\n", .{branch_name});

    const cache_path = try std.fmt.allocPrint(allocator, ".zion/cache/{s}-{s}.tar.gz", .{ package_name, branch_name });
    defer allocator.free(cache_path);

    // Download the package
    try downloader.ensureCacheDir(allocator);
    try downloader.downloadWithCurlImproved(allocator, branch_url, cache_path);

    // Calculate hash
    const new_hash = try downloader.calculateFileHash(allocator, cache_path);
    defer allocator.free(new_hash);

    std.debug.print("🔐 Calculated hash: {s}\n", .{new_hash[0..16]});

    // Update the dependency
    const old_url = existing_dep.url;
    const old_hash = existing_dep.hash;

    existing_dep.url = try allocator.dupe(u8, branch_url);
    existing_dep.hash = try allocator.dupe(u8, new_hash);

    // Clean up old strings
    allocator.free(old_url);
    allocator.free(old_hash);

    // Save updated ZON file
    try zon_file.saveToFile(zon_path);

    // Update lock file with branch info
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    // Store branch reference in lock file
    try lock_file.addPackageWithRef(package_name, branch_url, new_hash, null, branch_name);
    try lock_file.saveToFile();

    // Extract to deps directory
    const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
    defer allocator.free(deps_path);

    std.debug.print("📁 Extracting to {s}...\n", .{deps_path});
    try tar_extract.extractPackage(allocator, cache_path, deps_path);

    std.debug.print("🎉 Successfully unpinned {s} - now tracking {s} branch\n", .{ package_name, branch_name });
    std.debug.print("   URL: {s}\n", .{branch_url});
    std.debug.print("   Hash: {s}\n", .{new_hash[0..16]});
    std.debug.print("\n💡 To update hash when branch changes: zion hash update {s}\n", .{package_name});
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
