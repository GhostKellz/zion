const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const mem = std.mem;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");
const github = @import("../github.zig");
const zion_root = @import("../root.zig");

/// Fetches dependencies specified in build.zig.zon or a specific package with version
pub fn fetch(allocator: mem.Allocator, args: []const [:0]const u8) !void {
    // Check if we're fetching a specific package with version
    if (args.len >= 3) {
        const package_spec = args[2];

        // Check if it contains @version syntax
        if (std.mem.indexOf(u8, package_spec, "@")) |at_index| {
            const package_ref = package_spec[0..at_index];
            const version = package_spec[at_index + 1 ..];
            return fetchSpecificVersion(allocator, package_ref, version);
        } else {
            // Regular package reference without version - fetch latest
            return fetchLatestVersion(allocator, package_spec);
        }
    }

    // No arguments - fetch all dependencies from build.zig.zon
    return fetchAll(allocator);
}

/// Fetch a specific version of a package
fn fetchSpecificVersion(allocator: mem.Allocator, package_ref: []const u8, version: []const u8) !void {
    std.debug.print("📦 Fetching {s}@{s}...\n", .{ package_ref, version });

    const slash_index = std.mem.lastIndexOf(u8, package_ref, "/") orelse return error.InvalidPackageReference;
    const package_name = package_ref[slash_index + 1 ..];

    // Find the specific version
    var version_info = try github.findVersion(allocator, package_ref, version);
    defer version_info.deinit(allocator);

    std.debug.print("✅ Found version {s}: {s}\n", .{ version_info.version, version_info.url });

    const download_result = try downloader.downloadAndHashPackageVersion(allocator, package_ref, version);
    defer download_result.deinit(allocator);

    std.debug.print("🔐 Hash: {s}\n", .{download_result.hash[0..16]});
    std.debug.print("📁 Cached at: {s}\n", .{download_result.cache_path});

    std.debug.print("💡 To add to your project:\n", .{});
    std.debug.print("   zion add {s}  # (adds latest)\n", .{package_ref});
    std.debug.print("   zion pin {s}@{s}  # (pins to this version)\n", .{ package_name, version_info.version });
}

/// Fetch the latest version of a package
fn fetchLatestVersion(allocator: mem.Allocator, package_ref: []const u8) !void {
    std.debug.print("📦 Fetching latest version of {s}...\n", .{package_ref});

    // Get the latest version
    var latest_version = try github.getLatestVersion(allocator, package_ref);
    defer latest_version.deinit(allocator);

    std.debug.print("✅ Latest version: {s}\n", .{latest_version.version});
    std.debug.print("   URL: {s}\n", .{latest_version.url});

    const download_result = try downloader.downloadAndHashPackage(allocator, package_ref);
    defer download_result.deinit(allocator);

    std.debug.print("🔐 Hash: {s}\n", .{download_result.hash[0..16]});
    std.debug.print("📁 Cached at: {s}\n", .{download_result.cache_path});

    std.debug.print("💡 To add to your project:\n", .{});
    std.debug.print("   zion add {s}  # (adds to dependencies)\n", .{package_ref});
}

/// Fetch all dependencies from build.zig.zon
fn fetchAll(allocator: mem.Allocator) !void {
    const zon_path = "build.zig.zon";
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Ensure .zion/cache directory exists
    try downloader.ensureCacheDir(allocator);

    // Check if file exists
    cwd.access(io, zon_path, .{}) catch |err| {
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

        const cache_path = try downloader.cachePathForUrl(allocator, pkg_name, url);
        defer allocator.free(cache_path);

        const cached_file_exists = blk: {
            cwd.access(io, cache_path, .{}) catch |err| {
                if (err == error.FileNotFound) break :blk false;
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
                    const download_result = try downloader.downloadFromUrl(allocator, pkg.url, pkg_name);
                    defer download_result.deinit(allocator);
                    downloaded_count += 1;
                }
            } else {
                // Hash doesn't match, need to verify and update lock
                std.debug.print("  - {s}: Hash mismatch in lock file, re-verifying\n", .{pkg_name});

                if (!cached_file_exists) {
                    // Need to download before verifying
                    const download_result = try downloader.downloadFromUrl(allocator, url, pkg_name);
                    defer download_result.deinit(allocator);
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
                const download_result = try downloader.downloadFromUrl(allocator, url, pkg_name);
                defer download_result.deinit(allocator);
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
