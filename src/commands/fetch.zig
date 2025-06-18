const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");

/// Fetches dependencies specified in build.zig.zon
pub fn fetch(allocator: mem.Allocator) !void {
    const zon_path = "build.zig.zon";
    const cwd = fs.cwd();

    // Ensure .zion/cache directory exists
    try downloader.ensureCacheDir(allocator);

    // Check if file exists
    cwd.access(zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Load existing ZON file
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();

    // Load or create lock file
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    std.debug.print("Fetching dependencies for project {s} v{s}:\n", .{ zon_file.name, zon_file.version });

    var it = zon_file.dependencies.iterator();
    var count: usize = 0;
    var updated_lock = false;
    var downloaded_count: usize = 0;

    while (it.next()) |entry| {
        const pkg_name = entry.key_ptr.*;
        const url = entry.value_ptr.url;
        const hash = entry.value_ptr.hash;

        // Check cache path
        const cache_path = try std.fmt.allocPrint(allocator, ".zion/cache/{s}.tar.gz", .{pkg_name});
        defer allocator.free(cache_path);

        const cached_file_exists = blk: {
            cwd.access(cache_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    break :blk false;
                }
                return err;
            };
            break :blk true;
        };

        // Check if the package is in the lock file
        const locked_pkg = lock_file.getPackage(pkg_name);

        if (locked_pkg) |pkg| {
            // Package is locked
            if (std.mem.eql(u8, pkg.hash, hash)) {
                // Hash matches, check if we have it cached
                if (cached_file_exists) {
                    std.debug.print("  - {s}: Using cached package (hash: {s})\n", .{ pkg_name, hash });
                } else {
                    // Not cached, need to download
                    std.debug.print("  - {s}: Downloading using locked info\n", .{pkg_name});
                    try downloadPackage(allocator, pkg.url, cache_path);
                    downloaded_count += 1;
                }
            } else {
                // Hash doesn't match, need to verify and update lock
                std.debug.print("  - {s}: Hash mismatch in lock file, re-verifying\n", .{pkg_name});

                if (!cached_file_exists) {
                    // Need to download before verifying
                    try downloadPackage(allocator, url, cache_path);
                    downloaded_count += 1;
                }

                // Verify the hash
                const computed_hash = try downloader.calculateFileHash(allocator, cache_path);
                defer allocator.free(computed_hash);

                if (std.mem.eql(u8, computed_hash, hash)) {
                    // Update lock file with new hash
                    try lock_file.addPackage(pkg_name, url, hash, null);
                    updated_lock = true;
                    std.debug.print("    Hash verified and lock updated\n", .{});
                } else {
                    std.debug.print("    Warning: Computed hash {s} doesn't match expected {s}\n", .{ computed_hash, hash });
                }
            }
        } else {
            // Package not in lock file, need to download and add
            std.debug.print("  - {s}: New package, adding to lock file\n", .{pkg_name});

            if (!cached_file_exists) {
                // Download it first
                try downloadPackage(allocator, url, cache_path);
                downloaded_count += 1;
            }

            // Verify the hash
            const computed_hash = try downloader.calculateFileHash(allocator, cache_path);
            defer allocator.free(computed_hash);

            if (std.mem.eql(u8, computed_hash, hash)) {
                // Add to lock file
                try lock_file.addPackage(pkg_name, url, hash, null);
                updated_lock = true;
                std.debug.print("    Package verified and added to lock file\n", .{});
            } else {
                std.debug.print("    Warning: Computed hash {s} doesn't match expected {s}\n", .{ computed_hash, hash });
            }
        }

        count += 1;
    }

    if (count == 0) {
        std.debug.print("No dependencies found.\n", .{});
    } else {
        std.debug.print("Processed {d} dependencies, downloaded {d} packages.\n", .{ count, downloaded_count });

        if (updated_lock) {
            // Save the updated lock file
            try lock_file.saveToFile();
            std.debug.print("Lock file updated.\n", .{});
        }
    }
}

/// Helper function to download a package from a URL to the cache
fn downloadPackage(allocator: mem.Allocator, url: []const u8, cache_path: []const u8) !void {
    // Use the improved curl downloader instead of HTTP client
    try downloader.downloadWithCurlImproved(allocator, url, cache_path);
}
