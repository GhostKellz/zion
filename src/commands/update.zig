const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");

/// Print help information for the update command
fn printUpdateHelp() void {
    std.debug.print(
        \\Usage: zion update [OPTIONS] [PACKAGES...]
        \\
        \\Update dependencies to their latest versions
        \\
        \\OPTIONS:
        \\    --dry-run, -n    Show what would be updated without making changes
        \\    --help, -h       Show this help message
        \\
        \\EXAMPLES:
        \\    zion update                    # Update all dependencies
        \\    zion update libxev httpz       # Update specific packages only
        \\    zion update --dry-run          # Check for updates without applying
        \\    zion update --dry-run libxev   # Check specific package for updates
        \\
    , .{});
}

/// Update all dependencies to their latest versions, or specific packages if provided
pub fn update(allocator: Allocator, args: [][:0]u8) !void {
    // Parse command line arguments
    var dry_run = false;
    var specific_packages = std.ArrayList([]const u8).init(allocator);
    defer specific_packages.deinit();
    
    // Process arguments starting from index 2 (skip "zion update")
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUpdateHelp();
            return;
        } else {
            // Assume it's a package name
            try specific_packages.append(arg);
        }
    }
    
    if (dry_run) {
        std.debug.print("🔍 Checking for updates (dry run)...\n", .{});
    } else if (specific_packages.items.len > 0) {
        std.debug.print("Updating specific packages: ", .{});
        for (specific_packages.items, 0..) |pkg, idx| {
            if (idx > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{pkg});
        }
        std.debug.print("\n", .{});
    } else {
        std.debug.print("Updating all dependencies...\n", .{});
    }

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

    // Load existing ZON file and lock file
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();

    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    // Ensure cache and deps directories exist
    try downloader.ensureCacheDir(allocator);
    try ensureDepsDir();

    std.debug.print("Checking {d} dependencies for updates...\n", .{zon_file.dependencies.count()});

    var updated_packages = std.ArrayList([]const u8).init(allocator);
    defer {
        for (updated_packages.items) |pkg_name| {
            allocator.free(pkg_name);
        }
        updated_packages.deinit();
    }

    var unchanged_packages = std.ArrayList([]const u8).init(allocator);
    defer {
        for (unchanged_packages.items) |pkg_name| {
            allocator.free(pkg_name);
        }
        unchanged_packages.deinit();
    }

    var zon_updated = false;
    var lock_updated = false;

    // Process each dependency
    var it = zon_file.dependencies.iterator();
    while (it.next()) |entry| {
        const pkg_name = entry.key_ptr.*;
        const current_dep = entry.value_ptr.*;

        // Skip if we're only updating specific packages and this isn't one of them
        if (specific_packages.items.len > 0) {
            var found = false;
            for (specific_packages.items) |target_pkg| {
                if (std.mem.eql(u8, pkg_name, target_pkg)) {
                    found = true;
                    break;
                }
            }
            if (!found) continue;
        }

        std.debug.print("\n📦 Checking {s}...\n", .{pkg_name});

        // Re-download and compute new hash
        const package_ref = try extractPackageRefFromUrl(allocator, current_dep.url);
        defer allocator.free(package_ref);

        const download_result = try downloader.downloadAndHashPackage(allocator, package_ref);
        defer {
            allocator.free(download_result.url);
            allocator.free(download_result.hash);
            allocator.free(download_result.cache_path);
        }

        // Compare hashes
        if (std.mem.eql(u8, current_dep.hash, download_result.hash)) {
            // No change
            std.debug.print("  ✓ Up to date (hash: {s})\n", .{download_result.hash[0..16]});
            try unchanged_packages.append(try allocator.dupe(u8, pkg_name));
        } else {
            // Hash changed - need to update
            if (dry_run) {
                std.debug.print("  📋 Would update! (dry run)\n", .{});
                std.debug.print("    Old: {s}\n", .{current_dep.hash[0..16]});
                std.debug.print("    New: {s}\n", .{download_result.hash[0..16]});
                try updated_packages.append(try allocator.dupe(u8, pkg_name));
            } else {
                std.debug.print("  🔄 Hash changed! Updating...\n", .{});
                std.debug.print("    Old: {s}\n", .{current_dep.hash[0..16]});
                std.debug.print("    New: {s}\n", .{download_result.hash[0..16]});

                // Update dependency in ZON file
                allocator.free(current_dep.url);
                allocator.free(current_dep.hash);
                entry.value_ptr.url = try allocator.dupe(u8, download_result.url);
                entry.value_ptr.hash = try allocator.dupe(u8, download_result.hash);
                zon_updated = true;

                // Update lock file
                try lock_file.addPackage(pkg_name, download_result.url, download_result.hash, null);
                lock_updated = true;

                // Extract updated package
                const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{pkg_name});
                defer allocator.free(deps_path);

                std.debug.print("  📁 Extracting to {s}...\n", .{deps_path});
                try extractTarball(allocator, download_result.cache_path, deps_path);

                try updated_packages.append(try allocator.dupe(u8, pkg_name));
            }
        }
    }

    // Save updated files if needed (skip in dry-run mode)
    if (!dry_run) {
        if (zon_updated) {
            try zon_file.saveToFile(zon_path);
            std.debug.print("\n✅ Updated build.zig.zon\n", .{});
        }

        if (lock_updated) {
            try lock_file.saveToFile();
            std.debug.print("✅ Updated zion.lock\n", .{});
        }
    }

    // Print summary
    std.debug.print("\n📋 Update Summary:\n", .{});

    if (updated_packages.items.len > 0) {
        if (dry_run) {
            std.debug.print("📋 Packages that would be updated ({d}):\n", .{updated_packages.items.len});
        } else {
            std.debug.print("🔄 Updated packages ({d}):\n", .{updated_packages.items.len});
        }
        for (updated_packages.items) |pkg_name| {
            std.debug.print("  - {s}\n", .{pkg_name});
        }
    }

    if (unchanged_packages.items.len > 0) {
        std.debug.print("✅ Up-to-date packages ({d}):\n", .{unchanged_packages.items.len});
        for (unchanged_packages.items) |pkg_name| {
            std.debug.print("  - {s}\n", .{pkg_name});
        }
    }

    if (updated_packages.items.len == 0) {
        std.debug.print("🎉 All dependencies are up to date!\n", .{});
    } else if (dry_run) {
        std.debug.print("\n💡 {d} package(s) can be updated. Run 'zion update' to apply changes.\n", .{updated_packages.items.len});
    } else {
        std.debug.print("\n🚀 Updated {d} package(s). Run 'zig build' to use the latest versions.\n", .{updated_packages.items.len});
    }
}

/// Extract package reference (user/repo) from GitHub URL
fn extractPackageRefFromUrl(allocator: Allocator, url: []const u8) ![]const u8 {
    // Expected format: https://github.com/user/repo/archive/refs/heads/main.tar.gz
    const github_prefix = "https://github.com/";
    const archive_suffix = "/archive/refs/heads/";

    if (!std.mem.startsWith(u8, url, github_prefix)) {
        return error.UnsupportedUrl;
    }

    const after_prefix = url[github_prefix.len..];
    if (std.mem.indexOf(u8, after_prefix, archive_suffix)) |suffix_pos| {
        return allocator.dupe(u8, after_prefix[0..suffix_pos]);
    }

    return error.InvalidGitHubUrl;
}

/// Ensure the .zion/deps directory exists
fn ensureDepsDir() !void {
    const cwd = fs.cwd();

    // Create .zion directory if it doesn't exist
    cwd.makeDir(".zion") catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    // Create .zion/deps directory if it doesn't exist
    cwd.makeDir(".zion/deps") catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
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
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024);
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
