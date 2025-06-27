const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const github = @import("../github.zig");

/// Show outdated dependencies
pub fn outdated(allocator: Allocator, args: [][:0]u8) !void {
    var json_output = false;
    
    // Parse arguments
    var i: usize = 2; // Skip "zion" and "outdated"
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        }
        i += 1;
    }
    
    // Load project dependencies
    const zon_path = "build.zig.zon";
    const cwd = fs.cwd();
    
    cwd.access(zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("❌ build.zig.zon not found. Run 'zion init' first.\n", .{});
            return;
        }
        return err;
    };
    
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();
    
    if (!json_output) {
        std.debug.print("🔍 Checking for outdated dependencies...\n\n", .{});
    }
    
    var outdated_packages = std.ArrayList(OutdatedPackage).init(allocator);
    defer {
        for (outdated_packages.items) |*pkg| {
            pkg.deinit(allocator);
        }
        outdated_packages.deinit();
    }
    
    var it = zon_file.dependencies.iterator();
    while (it.next()) |entry| {
        const pkg_name = entry.key_ptr.*;
        const current_dep = entry.value_ptr.*;
        
        if (!json_output) {
            std.debug.print("  Checking {s}... ", .{pkg_name});
        }
        
        // Extract package reference from URL
        const package_ref = extractPackageRefFromUrl(allocator, current_dep.url) catch {
            if (!json_output) {
                std.debug.print("⚠️  (unknown repository format)\n", .{});
            }
            continue;
        };
        defer allocator.free(package_ref);
        
        // Get latest version from GitHub
        const latest_version = github.getLatestVersion(allocator, package_ref) catch |err| {
            if (!json_output) {
                std.debug.print("❌ (failed to check: {})\n", .{err});
            }
            continue;
        };
        defer {
            var mut_latest = latest_version;
            mut_latest.deinit(allocator);
        }
        
        // Compare URLs to see if there's a newer version
        if (!std.mem.eql(u8, current_dep.url, latest_version.url)) {
            const current_version = extractVersionFromUrl(allocator, current_dep.url) catch "unknown";
            defer if (!std.mem.eql(u8, current_version, "unknown")) allocator.free(current_version);
            
            try outdated_packages.append(OutdatedPackage{
                .name = try allocator.dupe(u8, pkg_name),
                .current_version = try allocator.dupe(u8, current_version),
                .latest_version = try allocator.dupe(u8, latest_version.version),
                .latest_url = try allocator.dupe(u8, latest_version.url),
            });
            
            if (!json_output) {
                std.debug.print("📦 {s} -> {s}\n", .{ current_version, latest_version.version });
            }
        } else {
            if (!json_output) {
                std.debug.print("✅ up to date\n", .{});
            }
        }
    }
    
    if (json_output) {
        try outputJsonResults(allocator, outdated_packages.items);
    } else {
        try outputHumanResults(allocator, outdated_packages.items);
    }
}

const OutdatedPackage = struct {
    name: []const u8,
    current_version: []const u8,
    latest_version: []const u8,
    latest_url: []const u8,
    
    pub fn deinit(self: *OutdatedPackage, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.current_version);
        allocator.free(self.latest_version);
        allocator.free(self.latest_url);
    }
};

/// Output results in human-readable format
fn outputHumanResults(allocator: Allocator, outdated_packages: []const OutdatedPackage) !void {
    _ = allocator;
    
    if (outdated_packages.len == 0) {
        std.debug.print("\n🎉 All dependencies are up to date!\n", .{});
        return;
    }
    
    std.debug.print("\n📋 Outdated Dependencies ({d}):\n", .{outdated_packages.len});
    std.debug.print("┌─────────────────────┬─────────────────┬─────────────────┐\n", .{});
    std.debug.print("│ Package             │ Current         │ Latest          │\n", .{});
    std.debug.print("├─────────────────────┼─────────────────┼─────────────────┤\n", .{});
    
    for (outdated_packages) |pkg| {
        std.debug.print("│ {s:<19} │ {s:<15} │ {s:<15} │\n", .{ pkg.name, pkg.current_version, pkg.latest_version });
    }
    
    std.debug.print("└─────────────────────┴─────────────────┴─────────────────┘\n", .{});
    std.debug.print("\n💡 Run 'zion update' to update all dependencies\n", .{});
    std.debug.print("💡 Run 'zion update <package>' to update specific packages\n", .{});
}

/// Output results in JSON format
fn outputJsonResults(allocator: Allocator, outdated_packages: []const OutdatedPackage) !void {
    std.debug.print("[\n", .{});
    
    for (outdated_packages, 0..) |pkg, i| {
        std.debug.print("  {{\n", .{});
        std.debug.print("    \"name\": \"{s}\",\n", .{pkg.name});
        std.debug.print("    \"current_version\": \"{s}\",\n", .{pkg.current_version});
        std.debug.print("    \"latest_version\": \"{s}\",\n", .{pkg.latest_version});
        std.debug.print("    \"latest_url\": \"{s}\"\n", .{pkg.latest_url});
        std.debug.print("  }}", .{});
        
        if (i < outdated_packages.len - 1) {
            std.debug.print(",", .{});
        }
        std.debug.print("\n", .{});
    }
    
    std.debug.print("]\n", .{});
    _ = allocator;
}

/// Extract package reference from GitHub URL
fn extractPackageRefFromUrl(allocator: Allocator, url: []const u8) ![]const u8 {
    const github_prefix = "https://github.com/";
    if (!std.mem.startsWith(u8, url, github_prefix)) {
        return error.NotGitHubUrl;
    }
    
    const after_prefix = url[github_prefix.len..];
    const slash_pos = std.mem.indexOf(u8, after_prefix, "/") orelse return error.InvalidUrl;
    const user = after_prefix[0..slash_pos];
    
    const remaining = after_prefix[slash_pos + 1..];
    const next_slash = std.mem.indexOf(u8, remaining, "/") orelse return error.InvalidUrl;
    const repo = remaining[0..next_slash];
    
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ user, repo });
}

/// Extract version from GitHub URL
fn extractVersionFromUrl(allocator: Allocator, url: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, url, "/tags/")) |tags_pos| {
        const version_start = tags_pos + 6; // "/tags/".len
        if (std.mem.indexOfPos(u8, url, version_start, ".tar.gz")) |version_end| {
            var version = url[version_start..version_end];
            if (std.mem.startsWith(u8, version, "v")) {
                version = version[1..];
            }
            return allocator.dupe(u8, version);
        }
    }
    
    if (std.mem.indexOf(u8, url, "/heads/")) |heads_pos| {
        const branch_start = heads_pos + 7;
        if (std.mem.indexOfPos(u8, url, branch_start, ".tar.gz")) |branch_end| {
            return std.fmt.allocPrint(allocator, "branch-{s}", .{url[branch_start..branch_end]});
        }
    }
    
    return allocator.dupe(u8, "unknown");
}