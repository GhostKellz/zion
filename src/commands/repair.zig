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

/// Repair broken hashes and dependency issues in the project
pub fn repair(allocator: Allocator) !void {
    std.debug.print("🔧 Repairing project dependencies...\n", .{});

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

    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    // Ensure cache directory exists
    try downloader.ensureCacheDir(allocator);

    std.debug.print("📋 Found {d} dependencies to check\n", .{zon_file.dependencies.count()});

    var repaired_count: usize = 0;
    var error_count: usize = 0;
    var verified_count: usize = 0;

    var repaired_packages: std.ArrayList([]const u8) = .empty;
    defer {
        for (repaired_packages.items) |pkg_name| {
            allocator.free(pkg_name);
        }
        repaired_packages.deinit(allocator);
    }

    var failed_packages: std.ArrayList([]const u8) = .empty;
    defer {
        for (failed_packages.items) |pkg_name| {
            allocator.free(pkg_name);
        }
        failed_packages.deinit(allocator);
    }

    // Process each dependency
    var it = zon_file.dependencies.iterator();
    while (it.next()) |entry| {
        const package_name = entry.key_ptr.*;
        const dep = entry.value_ptr;

        std.debug.print("\n🔍 Checking {s}...\n", .{package_name});

        // Generate cache path
        const cache_path = try std.fmt.allocPrint(allocator, ".zion/cache/{s}.tar.gz", .{package_name});
        defer allocator.free(cache_path);

        // Check if file exists in cache
        const cached_exists = blk: {
            cwd.access(io, cache_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    break :blk false;
                }
                std.debug.print("  ⚠️  Cache access error: {}\n", .{err});
                break :blk false;
            };
            break :blk true;
        };

        var needs_download = false;
        var hash_mismatch = false;

        if (cached_exists) {
            // Verify hash
            const computed_hash = downloader.calculateFileHash(allocator, cache_path) catch |err| {
                std.debug.print("  ❌ Failed to compute hash: {}\n", .{err});
                needs_download = true;
                continue;
            };
            defer allocator.free(computed_hash);

            if (std.mem.eql(u8, dep.hash, computed_hash)) {
                std.debug.print("  ✅ Hash verified: {s}\n", .{computed_hash[0..16]});
                verified_count += 1;
                continue;
            } else {
                std.debug.print("  🔥 Hash mismatch!\n", .{});
                std.debug.print("     Expected: {s}\n", .{dep.hash[0..16]});
                std.debug.print("     Computed: {s}\n", .{computed_hash[0..16]});
                hash_mismatch = true;
                needs_download = true;
            }
        } else {
            std.debug.print("  📥 Not cached, needs download\n", .{});
            needs_download = true;
        }

        if (needs_download) {
            std.debug.print("  ⬇️  Re-downloading from {s}...\n", .{dep.url});

            // Download the package
            if (downloader.downloadWithCurlImproved(allocator, dep.url, cache_path)) {
                // Recalculate hash
                const new_hash = downloader.calculateFileHash(allocator, cache_path) catch |err| {
                    std.debug.print("  ❌ Failed to compute new hash: {}\n", .{err});
                    try failed_packages.append(allocator, try allocator.dupe(u8, package_name));
                    error_count += 1;
                    continue;
                };
                defer allocator.free(new_hash);

                if (hash_mismatch) {
                    std.debug.print("  🔧 Updating hash in manifest...\n", .{});

                    // Update the hash in the ZON file
                    allocator.free(dep.hash);
                    dep.hash = try allocator.dupe(u8, new_hash);

                    // Update lock file
                    try lock_file.addPackage(package_name, dep.url, new_hash, null);

                    std.debug.print("  ✅ Hash updated: {s}\n", .{new_hash[0..16]});
                    try repaired_packages.append(allocator, try allocator.dupe(u8, package_name));
                    repaired_count += 1;
                } else {
                    // Just downloaded, verify it matches expected hash
                    if (std.mem.eql(u8, dep.hash, new_hash)) {
                        std.debug.print("  ✅ Download verified: {s}\n", .{new_hash[0..16]});
                        verified_count += 1;
                    } else {
                        std.debug.print("  ❌ Downloaded hash still doesn't match!\n", .{});
                        std.debug.print("     Expected: {s}\n", .{dep.hash[0..16]});
                        std.debug.print("     Downloaded: {s}\n", .{new_hash[0..16]});
                        try failed_packages.append(allocator, try allocator.dupe(u8, package_name));
                        error_count += 1;
                    }
                }

                // Extract to deps directory
                const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
                defer allocator.free(deps_path);

                std.debug.print("  📁 Extracting to {s}...\n", .{deps_path});
                if (tar_extract.extractPackage(allocator, cache_path, deps_path)) {
                    std.debug.print("  ✅ Extracted successfully\n", .{});
                } else |err| {
                    std.debug.print("  ⚠️  Extraction warning: {}\n", .{err});
                }
            } else |err| {
                std.debug.print("  ❌ Download failed: {}\n", .{err});
                try failed_packages.append(allocator, try allocator.dupe(u8, package_name));
                error_count += 1;
            }
        }
    }

    // Save updated files if repairs were made
    if (repaired_count > 0) {
        try zon_file.saveToFile(zon_path);
        try lock_file.saveToFile();
        std.debug.print("\n✅ Updated build.zig.zon and zion.lock\n", .{});
    }

    // Print summary
    std.debug.print("\n📊 Repair Summary:\n", .{});
    std.debug.print("   ✅ Verified: {d} packages\n", .{verified_count});

    if (repaired_count > 0) {
        std.debug.print("   🔧 Repaired: {d} packages\n", .{repaired_count});
        for (repaired_packages.items) |pkg_name| {
            std.debug.print("      - {s}\n", .{pkg_name});
        }
    }

    if (error_count > 0) {
        std.debug.print("   ❌ Failed: {d} packages\n", .{error_count});
        for (failed_packages.items) |pkg_name| {
            std.debug.print("      - {s}\n", .{pkg_name});
        }
    }

    if (error_count == 0 and repaired_count == 0) {
        std.debug.print("🎉 All dependencies are healthy! No repairs needed.\n", .{});
    } else if (error_count == 0) {
        std.debug.print("🎉 All issues repaired successfully!\n", .{});
        std.debug.print("💡 Run 'zig build' to verify everything works correctly.\n", .{});
    } else {
        std.debug.print("⚠️  Some packages could not be repaired. Check URLs and network connectivity.\n", .{});
        if (repaired_count > 0) {
            std.debug.print("💡 Run 'zig build' to test the successfully repaired packages.\n", .{});
        }
    }
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
