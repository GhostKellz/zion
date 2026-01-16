const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const downloader = @import("../downloader.zig");
const github = @import("../github.zig");
const zion_root = @import("../root.zig");

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
            const version = target[at_index + 1..];

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
fn updateHash(_: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("❌ Usage: zion hash update <package_name>\n", .{});
        return;
    }

    const package_name = args[0];
    std.debug.print("🔄 Updating hash for {s}...\n", .{package_name});

    // This would integrate with the manifest system to update hashes
    std.debug.print("💡 This would re-download {s} and update its hash in build.zig.zon\n", .{package_name});
    std.debug.print("🚧 Full implementation would modify the ZON file directly\n", .{});
}

/// Check all hashes in the project
fn checkAllHashes(_: Allocator) !void {
    std.debug.print("🔍 Checking all package hashes...\n", .{});

    // This would integrate with the check command
    std.debug.print("💡 This would verify all dependencies in build.zig.zon\n", .{});
    std.debug.print("🚧 Full implementation would check each dependency hash\n", .{});
}

fn printHashHelp() void {
    std.debug.print("Zion Hash Management\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion hash <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    generate <file|package[@version]>   Generate SHA256 hash\n", .{});
    std.debug.print("    verify <file> <hash>                Verify file against hash\n", .{});
    std.debug.print("    update <package>                    Update package hash in ZON\n", .{});
    std.debug.print("    check                               Check all project hashes\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion hash generate myfile.tar.gz           # Hash local file\n", .{});
    std.debug.print("    zion hash generate ziglang/zig@0.14.1      # Hash specific version\n", .{});
    std.debug.print("    zion hash generate mitchellh/libxev        # Hash latest version\n", .{});
    std.debug.print("    zion hash verify file.tar.gz abc123...     # Verify file hash\n", .{});
    std.debug.print("    zion hash update libxev                    # Update dependency hash\n", .{});
    std.debug.print("    zion hash check                            # Check all hashes\n", .{});
}
