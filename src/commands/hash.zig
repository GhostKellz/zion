const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const downloader = @import("../downloader.zig");
const github = @import("../github.zig");
const zion_root = @import("../root.zig");
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const hash_conversion = @import("../hash_conversion.zig");

/// Hash management commands for package integrity
pub fn hash(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        printHashHelp();
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "generate")) {
        return generateHash(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "verify")) {
        return verifyHash(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "update")) {
        return updateHash(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "check")) {
        return checkAllHashes(allocator);
    } else {
        std.debug.print("❌ Unknown hash subcommand: {s}\n", .{subcommand});
        printHashHelp();
    }
}

/// Generate hash for a local file or remote package
fn generateHash(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("❌ Usage: zion hash generate <file|package@version>\n", .{});
        return;
    }

    const target = args[0];
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if it's a local file path
    if (cwd.access(io, target, .{})) {
        // Local file
        const file_hash = try downloader.calculateFileHash(allocator, target);
        defer allocator.free(file_hash);

        std.debug.print("📁 File: {s}\n", .{target});
        std.debug.print("🔐 SHA256: {s}\n", .{file_hash});

        // Also provide multihash format used by Zig
        const multihash = try std.fmt.allocPrint(allocator, "1220{s}", .{file_hash});
        defer allocator.free(multihash);
        std.debug.print("🏷️  Multihash: {s}\n", .{multihash});
    } else |_| {
        // Assume it's a package reference
        if (std.mem.indexOf(u8, target, "@")) |at_index| {
            const package_ref = target[0..at_index];
            const version = target[at_index + 1 ..];

            std.debug.print("📦 Generating hash for {s}@{s}...\n", .{ package_ref, version });

            const download_result = try downloader.downloadAndHashPackageVersion(allocator, package_ref, version);
            defer {
                allocator.free(download_result.url);
                allocator.free(download_result.hash);
                allocator.free(download_result.cache_path);
            }

            std.debug.print("✅ Package: {s}@{s}\n", .{ package_ref, version });
            std.debug.print("🌐 URL: {s}\n", .{download_result.url});
            std.debug.print("🔐 SHA256: {s}\n", .{download_result.hash});

            const multihash = try std.fmt.allocPrint(allocator, "1220{s}", .{download_result.hash});
            defer allocator.free(multihash);
            std.debug.print("🏷️  Multihash: {s}\n", .{multihash});
        } else {
            // Latest version
            std.debug.print("📦 Generating hash for latest {s}...\n", .{target});

            const download_result = try downloader.downloadAndHashPackage(allocator, target);
            defer {
                allocator.free(download_result.url);
                allocator.free(download_result.hash);
                allocator.free(download_result.cache_path);
            }

            std.debug.print("✅ Package: {s} (latest)\n", .{target});
            std.debug.print("🌐 URL: {s}\n", .{download_result.url});
            std.debug.print("🔐 SHA256: {s}\n", .{download_result.hash});

            const multihash = try std.fmt.allocPrint(allocator, "1220{s}", .{download_result.hash});
            defer allocator.free(multihash);
            std.debug.print("🏷️  Multihash: {s}\n", .{multihash});
        }
    }
}

/// Verify hash of a file against expected hash
fn verifyHash(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 2) {
        std.debug.print("❌ Usage: zion hash verify <file> <expected_hash>\n", .{});
        return;
    }

    const file_path = args[0];
    const expected_hash = args[1];

    const computed_hash = try downloader.calculateFileHash(allocator, file_path);
    defer allocator.free(computed_hash);

    std.debug.print("📁 File: {s}\n", .{file_path});
    std.debug.print("🔐 Computed: {s}\n", .{computed_hash});
    std.debug.print("🎯 Expected: {s}\n", .{expected_hash});

    if (std.mem.eql(u8, computed_hash, expected_hash)) {
        std.debug.print("✅ Hash verification PASSED\n", .{});
    } else {
        std.debug.print("❌ Hash verification FAILED\n", .{});
        std.debug.print("⚠️  File may be corrupted or tampered with!\n", .{});
    }
}

/// Update hash for a dependency in build.zig.zon
fn updateHash(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: zion hash update <package_name|--all>\n", .{});
        return;
    }

    const target = args[0];
    const update_all = std.mem.eql(u8, target, "--all");

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if build.zig.zon exists
    cwd.access(io, "build.zig.zon", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("build.zig.zon not found. Run 'zion init' first.\n", .{});
            return;
        }
        return err;
    };

    // Load the ZON file
    var zon_file = try ZonFile.loadFromFile(allocator, "build.zig.zon");
    defer zon_file.deinit();

    // Load or create lock file
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    var updated_count: usize = 0;

    if (update_all) {
        std.debug.print("Updating hashes for all dependencies...\n\n", .{});

        var it = zon_file.dependencies.iterator();
        while (it.next()) |entry| {
            const pkg_name = entry.key_ptr.*;
            const dep = entry.value_ptr.*;

            if (try updateSingleHash(allocator, &zon_file, &lock_file, pkg_name, dep.url)) {
                updated_count += 1;
            }
        }
    } else {
        // Update single package
        const dep = zon_file.dependencies.get(target);
        if (dep == null) {
            std.debug.print("Dependency '{s}' not found in build.zig.zon\n", .{target});
            return;
        }

        if (try updateSingleHash(allocator, &zon_file, &lock_file, target, dep.?.url)) {
            updated_count += 1;
        }
    }

    if (updated_count > 0) {
        // Save updated ZON file
        try zon_file.saveToFile("build.zig.zon");
        std.debug.print("\nUpdated build.zig.zon with {d} new hash(es)\n", .{updated_count});

        // Save updated lock file
        try lock_file.saveToFile();
        std.debug.print("Updated zion.lock\n", .{});
    } else {
        std.debug.print("\nNo hashes needed updating\n", .{});
    }
}

/// Update hash for a single dependency
fn updateSingleHash(
    allocator: Allocator,
    zon_file: *ZonFile,
    lock_file: *LockFile,
    pkg_name: []const u8,
    url: []const u8,
) !bool {
    std.debug.print("  {s}: ", .{pkg_name});

    // Extract version from URL (e.g., .../v0.7.8.tar.gz)
    const version = extractVersionFromUrl(url) orelse "unknown";

    // Download and calculate hash
    const cache_dir = ".zion/cache";
    const cache_filename = try std.fmt.allocPrint(allocator, "{s}/{s}-{s}.tar.gz", .{ cache_dir, pkg_name, version });
    defer allocator.free(cache_filename);

    // Download the package
    downloader.downloadFile(allocator, url, cache_filename) catch |err| {
        std.debug.print("download failed: {}\n", .{err});
        return false;
    };

    // Calculate hash
    const sha256_hex = downloader.calculateFileHash(allocator, cache_filename) catch |err| {
        std.debug.print("hash calculation failed: {}\n", .{err});
        return false;
    };
    defer allocator.free(sha256_hex);

    // Convert to Zig native format
    const zig_hash = hash_conversion.hexToZigNativeHash(allocator, sha256_hex, pkg_name, version) catch |err| {
        std.debug.print("hash conversion failed: {}\n", .{err});
        return false;
    };
    defer allocator.free(zig_hash);

    // Check if hash changed
    if (zon_file.dependencies.get(pkg_name)) |existing| {
        if (std.mem.eql(u8, existing.hash, zig_hash)) {
            std.debug.print("unchanged\n", .{});
            return false;
        }
    }

    // Update ZON file
    try zon_file.addDependency(pkg_name, url, zig_hash);

    // Update lock file
    try lock_file.addPackage(pkg_name, url, zig_hash, version);

    std.debug.print("updated -> {s}\n", .{zig_hash[0..@min(zig_hash.len, 40)]});
    return true;
}

/// Extract version from a GitHub tarball URL
fn extractVersionFromUrl(url: []const u8) ?[]const u8 {
    // Pattern: .../refs/tags/v{version}.tar.gz or .../refs/tags/{version}.tar.gz
    if (std.mem.indexOf(u8, url, "/refs/tags/")) |tags_pos| {
        const after_tags = url[tags_pos + 11 ..]; // Skip "/refs/tags/"
        if (std.mem.indexOf(u8, after_tags, ".tar.gz")) |tar_pos| {
            var version_str = after_tags[0..tar_pos];
            // Strip leading 'v' if present
            if (version_str.len > 0 and version_str[0] == 'v') {
                version_str = version_str[1..];
            }
            return version_str;
        }
    }
    return null;
}

/// Check all hashes in the project
fn checkAllHashes(allocator: Allocator) !void {
    std.debug.print("Checking all package hashes...\n\n", .{});

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if build.zig.zon exists
    cwd.access(io, "build.zig.zon", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("build.zig.zon not found. Run 'zion init' first.\n", .{});
            return;
        }
        return err;
    };

    // Load the ZON file
    var zon_file = try ZonFile.loadFromFile(allocator, "build.zig.zon");
    defer zon_file.deinit();

    var pass_count: usize = 0;
    var fail_count: usize = 0;
    var missing_count: usize = 0;

    var it = zon_file.dependencies.iterator();
    while (it.next()) |entry| {
        const pkg_name = entry.key_ptr.*;
        const dep = entry.value_ptr.*;

        std.debug.print("  {s}: ", .{pkg_name});

        // Extract version from hash or URL
        const version = hash_conversion.extractVersion(dep.hash) orelse
            extractVersionFromUrl(dep.url) orelse
            "unknown";

        // Check if cached file exists
        const cache_path = try std.fmt.allocPrint(allocator, ".zion/cache/{s}-{s}.tar.gz", .{ pkg_name, version });
        defer allocator.free(cache_path);

        if (cwd.access(io, cache_path, .{})) {
            // File exists, verify hash
            const computed_hash = downloader.calculateFileHash(allocator, cache_path) catch |err| {
                std.debug.print("hash error: {}\n", .{err});
                fail_count += 1;
                continue;
            };
            defer allocator.free(computed_hash);

            // Convert computed hash to Zig native format for comparison
            const computed_zig_hash = hash_conversion.hexToZigNativeHash(allocator, computed_hash, pkg_name, version) catch {
                std.debug.print("conversion error\n", .{});
                fail_count += 1;
                continue;
            };
            defer allocator.free(computed_zig_hash);

            if (std.mem.eql(u8, computed_zig_hash, dep.hash)) {
                std.debug.print("OK\n", .{});
                pass_count += 1;
            } else {
                std.debug.print("MISMATCH\n", .{});
                std.debug.print("    Expected: {s}\n", .{dep.hash[0..@min(dep.hash.len, 50)]});
                std.debug.print("    Got:      {s}\n", .{computed_zig_hash[0..@min(computed_zig_hash.len, 50)]});
                fail_count += 1;
            }
        } else |_| {
            std.debug.print("NOT CACHED\n", .{});
            missing_count += 1;
        }
    }

    // Summary
    std.debug.print("\nHash Check Summary:\n", .{});
    std.debug.print("  Passed:  {d}\n", .{pass_count});
    std.debug.print("  Failed:  {d}\n", .{fail_count});
    std.debug.print("  Missing: {d}\n", .{missing_count});

    if (fail_count > 0) {
        std.debug.print("\nRun 'zion hash update --all' to fix mismatched hashes.\n", .{});
    }
    if (missing_count > 0) {
        std.debug.print("Run 'zion fetch' to download missing packages.\n", .{});
    }
    if (pass_count > 0 and fail_count == 0 and missing_count == 0) {
        std.debug.print("\nAll hashes verified successfully!\n", .{});
    }
}

fn printHashHelp() void {
    std.debug.print("Zion Hash Management\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion hash <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    generate <file|package[@version]>   Generate SHA256 hash\n", .{});
    std.debug.print("    verify <file> <hash>                Verify file against hash\n", .{});
    std.debug.print("    update <package|--all>              Update package hash in ZON\n", .{});
    std.debug.print("    check                               Check all project hashes\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion hash generate myfile.tar.gz           # Hash local file\n", .{});
    std.debug.print("    zion hash generate ziglang/zig@0.14.1      # Hash specific version\n", .{});
    std.debug.print("    zion hash generate mitchellh/libxev        # Hash latest version\n", .{});
    std.debug.print("    zion hash verify file.tar.gz abc123...     # Verify file hash\n", .{});
    std.debug.print("    zion hash update libxev                    # Update single dependency\n", .{});
    std.debug.print("    zion hash update --all                     # Update all dependencies\n", .{});
    std.debug.print("    zion hash check                            # Check all hashes\n", .{});
}
