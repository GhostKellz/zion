const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");
const zion_root = @import("../root.zig");
const tar_extract = @import("../tar_extract.zig");

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
pub fn update(allocator: Allocator, args: []const [:0]const u8) !void {
    // Parse command line arguments
    var dry_run = false;
    var specific_packages = std.ArrayList([]const u8).empty;
    defer specific_packages.deinit(allocator);

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
            try specific_packages.append(allocator, arg);
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
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    cwd.access(io, zon_path, .{}) catch |err| {
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

    var updated_packages = std.ArrayList([]const u8).empty;
    defer {
        for (updated_packages.items) |pkg_name| {
            allocator.free(pkg_name);
        }
        updated_packages.deinit(allocator);
    }

    var unchanged_packages = std.ArrayList([]const u8).empty;
    defer {
        for (unchanged_packages.items) |pkg_name| {
            allocator.free(pkg_name);
        }
        unchanged_packages.deinit(allocator);
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

        // Re-download using the exact artifact URL stored in the manifest.
        const download_result = try downloader.downloadFromUrl(allocator, current_dep.url, pkg_name);
        defer {
            allocator.free(download_result.url);
            allocator.free(download_result.hash);
            allocator.free(download_result.cache_path);
        }

        // Compare hashes
        if (std.mem.eql(u8, current_dep.hash, download_result.hash)) {
            // No change
            std.debug.print("  ✓ Up to date (hash: {s})\n", .{download_result.hash[0..16]});
            try unchanged_packages.append(allocator, try allocator.dupe(u8, pkg_name));
        } else {
            // Hash changed - need to update
            if (dry_run) {
                std.debug.print("  📋 Would update! (dry run)\n", .{});
                std.debug.print("    Old: {s}\n", .{current_dep.hash[0..16]});
                std.debug.print("    New: {s}\n", .{download_result.hash[0..16]});
                try updated_packages.append(allocator, try allocator.dupe(u8, pkg_name));
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
                try tar_extract.extractPackage(allocator, download_result.cache_path, deps_path);

                try updated_packages.append(allocator, try allocator.dupe(u8, pkg_name));
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

/// Ensure the .zion/deps directory exists
fn ensureDepsDir() !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Create .zion directory if it doesn't exist
    cwd.createDir(io, ".zion", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    // Create .zion/deps directory if it doesn't exist
    cwd.createDir(io, ".zion/deps", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
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
