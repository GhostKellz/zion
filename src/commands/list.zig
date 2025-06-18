const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;

/// List all dependencies in the project
pub fn list(allocator: Allocator, json_mode: bool) !void {
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

    if (json_mode) {
        try printJsonList(allocator, &zon_file, &lock_file);
    } else {
        try printTableList(allocator, &zon_file, &lock_file);
    }
}

/// Print dependencies in JSON format
fn printJsonList(allocator: Allocator, zon_file: *ZonFile, lock_file: *LockFile) !void {
    _ = allocator;

    std.debug.print("[\n", .{});

    var it = zon_file.dependencies.iterator();
    var first = true;

    while (it.next()) |entry| {
        if (!first) {
            std.debug.print(",\n", .{});
        }
        first = false;

        const pkg_name = entry.key_ptr.*;
        const dep = entry.value_ptr.*;
        const locked_pkg = lock_file.getPackage(pkg_name);

        // Check if package directory exists
        const deps_path = try std.fmt.allocPrint(std.heap.page_allocator, ".zion/deps/{s}", .{pkg_name});
        defer std.heap.page_allocator.free(deps_path);

        const installed = blk: {
            fs.cwd().access(deps_path, .{}) catch {
                break :blk false;
            };
            break :blk true;
        };

        // Extract repository info from URL
        const repo_info = try extractRepoInfo(std.heap.page_allocator, dep.url);
        defer std.heap.page_allocator.free(repo_info.owner);
        defer std.heap.page_allocator.free(repo_info.repo);

        std.debug.print("  {{\n", .{});
        std.debug.print("    \"name\": \"{s}\",\n", .{pkg_name});
        std.debug.print("    \"url\": \"{s}\",\n", .{dep.url});
        std.debug.print("    \"hash\": \"{s}\",\n", .{dep.hash});
        std.debug.print("    \"installed\": {s},\n", .{if (installed) "true" else "false"});
        std.debug.print("    \"owner\": \"{s}\",\n", .{repo_info.owner});
        std.debug.print("    \"repository\": \"{s}\"", .{repo_info.repo});

        if (locked_pkg) |locked| {
            std.debug.print(",\n    \"timestamp\": {d}", .{locked.timestamp});
            if (locked.version) |version| {
                std.debug.print(",\n    \"version\": \"{s}\"", .{version});
            }
        }

        std.debug.print("\n  }}", .{});
    }

    std.debug.print("\n]\n", .{});
}

/// Print dependencies in table format
fn printTableList(allocator: Allocator, zon_file: *ZonFile, lock_file: *LockFile) !void {
    _ = allocator;

    std.debug.print("📦 Dependencies for project '{s}' v{s}:\n", .{ zon_file.name, zon_file.version });
    std.debug.print("──────────────────────────────────────────────────────────────────────\n", .{});
    std.debug.print("Name                 Status     Repository                     Hash\n", .{});
    std.debug.print("──────────────────────────────────────────────────────────────────────\n", .{});

    var total: usize = 0;
    var installed: usize = 0;

    var it = zon_file.dependencies.iterator();
    while (it.next()) |entry| {
        const pkg_name = entry.key_ptr.*;
        const dep = entry.value_ptr.*;

        // Check if package directory exists
        const deps_path = try std.fmt.allocPrint(std.heap.page_allocator, ".zion/deps/{s}", .{pkg_name});
        defer std.heap.page_allocator.free(deps_path);

        const is_installed = blk: {
            fs.cwd().access(deps_path, .{}) catch {
                break :blk false;
            };
            break :blk true;
        };

        // Extract repository info from URL
        const repo_info = try extractRepoInfo(std.heap.page_allocator, dep.url);
        defer std.heap.page_allocator.free(repo_info.owner);
        defer std.heap.page_allocator.free(repo_info.repo);

        const status = if (is_installed) "✅ Installed" else "❌ Missing";
        const repo_str = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ repo_info.owner, repo_info.repo });
        defer std.heap.page_allocator.free(repo_str);

        // Check for hash mismatch
        const locked_pkg = lock_file.getPackage(pkg_name);
        const hash_mismatch = if (locked_pkg) |locked|
            !std.mem.eql(u8, locked.hash, dep.hash)
        else
            false;

        const hash_display = if (hash_mismatch) "⚠️ " else "";

        std.debug.print("{s:<20} {s:<10} {s:<30} {s}{s}\n", .{
            pkg_name,
            status,
            repo_str,
            hash_display,
            dep.hash[0..12],
        });

        total += 1;
        if (is_installed) installed += 1;
    }

    std.debug.print("──────────────────────────────────────────────────────────────────────\n", .{});
    std.debug.print("Total: {d} dependencies, {d} installed, {d} missing\n", .{ total, installed, total - installed });

    if (installed < total) {
        std.debug.print("\n💡 Run 'zion fetch' to install missing dependencies.\n", .{});
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
