const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;

/// Show detailed information about a package dependency
pub fn info(allocator: Allocator, package_name: []const u8) !void {
    const zon_path = "build.zig.zon";
    const cwd = fs.cwd();

    // Check if build.zig.zon exists
    cwd.access(zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Load ZON file and lock file
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();

    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    // Check if the package exists in dependencies
    if (zon_file.dependencies.get(package_name)) |dep| {
        std.debug.print("📦 Package Information: {s}\n", .{package_name});
        std.debug.print("──────────────────────────────────────────────────\n", .{});
        std.debug.print("📍 Name:        {s}\n", .{package_name});
        std.debug.print("🔗 URL:         {s}\n", .{dep.url});
        std.debug.print("🔒 Hash:        {s}\n", .{dep.hash[0..16]});
        std.debug.print("📦 Full Hash:   {s}\n", .{dep.hash});

        // Check installation status
        const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
        defer allocator.free(deps_path);

        const installed = blk: {
            fs.cwd().access(deps_path, .{}) catch {
                break :blk false;
            };
            break :blk true;
        };

        const status = if (installed) "✅ Installed" else "❌ Missing";
        std.debug.print("{s} Status:      {s}\n", .{ if (installed) "✅" else "❌", status });
        std.debug.print("📁 Location:    {s}\n", .{deps_path});

        // Lock file information
        std.debug.print("\n🔒 Lock File Information:\n", .{});
        if (lock_file.getPackage(package_name)) |locked_pkg| {
            std.debug.print("🕐 Timestamp:   {d}\n", .{locked_pkg.timestamp});
            std.debug.print("📅 Added:       {d} (Unix timestamp)\n", .{locked_pkg.timestamp});

            // Check hash consistency
            if (std.mem.eql(u8, locked_pkg.hash, dep.hash)) {
                std.debug.print("✅ Hash Match:  Manifest and lock file are synchronized\n", .{});
            } else {
                std.debug.print("⚠️  Hash Mismatch: Manifest and lock file differ\n", .{});
                std.debug.print("   Manifest: {s}\n", .{dep.hash[0..16]});
                std.debug.print("   Lock:     {s}\n", .{locked_pkg.hash[0..16]});
            }

            if (locked_pkg.version) |version| {
                std.debug.print("🏷️  Version:    {s}\n", .{version});
            }
        } else {
            std.debug.print("❌ Not found in lock file\n", .{});
            std.debug.print("💡 Run 'zion lock' to add to lock file\n", .{});
        }

        // Repository information
        std.debug.print("\n🌐 Repository Information:\n", .{});
        const repo_info = try extractRepoInfo(allocator, dep.url);
        defer allocator.free(repo_info.owner);
        defer allocator.free(repo_info.repo);

        std.debug.print("👤 Owner:       {s}\n", .{repo_info.owner});
        std.debug.print("📚 Repository:  {s}\n", .{repo_info.repo});
        std.debug.print("🔗 GitHub:      https://github.com/{s}/{s}\n", .{ repo_info.owner, repo_info.repo });

        // Suggestions based on status
        std.debug.print("\n💡 Suggestions:\n", .{});
        if (!installed) {
            std.debug.print("  • Run 'zion fetch' to install this package\n", .{});
        }
        std.debug.print("  • Run 'zion update' to check for updates\n", .{});
        std.debug.print("  • Run 'zion remove {s}' to remove this package\n", .{package_name});
    } else {
        std.debug.print("❌ Package '{s}' not found in dependencies.\n", .{package_name});
        std.debug.print("\nAvailable packages:\n", .{});

        var it = zon_file.dependencies.iterator();
        var count: usize = 0;
        while (it.next()) |entry| {
            std.debug.print("  - {s}\n", .{entry.key_ptr.*});
            count += 1;
        }

        if (count == 0) {
            std.debug.print("  (no dependencies found)\n", .{});
            std.debug.print("\n💡 Add dependencies with: zion add <package>\n", .{});
        }
    }
}

/// Repository information extracted from URL
const RepoInfo = struct {
    owner: []const u8,
    repo: []const u8,
};

/// Extract owner and repository name from GitHub URL
fn extractRepoInfo(allocator: Allocator, url: []const u8) !RepoInfo {
    // Expected format: https://github.com/owner/repo/archive/refs/heads/main.tar.gz
    const github_prefix = "https://github.com/";

    if (!std.mem.startsWith(u8, url, github_prefix)) {
        return RepoInfo{
            .owner = try allocator.dupe(u8, "unknown"),
            .repo = try allocator.dupe(u8, "unknown"),
        };
    }

    const after_prefix = url[github_prefix.len..];
    const slash_pos = std.mem.indexOf(u8, after_prefix, "/");

    if (slash_pos == null) {
        return RepoInfo{
            .owner = try allocator.dupe(u8, "unknown"),
            .repo = try allocator.dupe(u8, "unknown"),
        };
    }

    const owner = after_prefix[0..slash_pos.?];
    const rest = after_prefix[slash_pos.? + 1 ..];

    const next_slash = std.mem.indexOf(u8, rest, "/");
    const repo = if (next_slash) |pos| rest[0..pos] else rest;

    return RepoInfo{
        .owner = try allocator.dupe(u8, owner),
        .repo = try allocator.dupe(u8, repo),
    };
}
