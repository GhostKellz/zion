const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;

/// Display dependency tree
pub fn tree(allocator: Allocator, args: [][:0]u8) !void {
    var max_depth: ?u32 = null;
    var show_duplicates = false;
    var show_versions = true;
    
    // Parse arguments
    var i: usize = 2; // Skip "zion" and "tree"
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--duplicates")) {
            show_duplicates = true;
        } else if (std.mem.eql(u8, arg, "--no-versions")) {
            show_versions = false;
        } else if (std.mem.startsWith(u8, arg, "--depth=")) {
            const depth_str = arg[8..]; // Skip "--depth="
            max_depth = std.fmt.parseInt(u32, depth_str, 10) catch {
                std.debug.print("❌ Invalid depth value: {s}\n", .{depth_str});
                return;
            };
        } else if (std.mem.eql(u8, arg, "--depth") and i + 1 < args.len) {
            i += 1;
            max_depth = std.fmt.parseInt(u32, args[i], 10) catch {
                std.debug.print("❌ Invalid depth value: {s}\n", .{args[i]});
                return;
            };
        }
        i += 1;
    }
    
    // Load project info
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
    
    std.debug.print("📦 {s} v{s}\n", .{ zon_file.name, zon_file.version });
    
    if (zon_file.dependencies.count() == 0) {
        std.debug.print("└── (no dependencies)\n", .{});
        return;
    }
    
    // Track visited packages to detect duplicates
    var visited = std.StringHashMap(u32).init(allocator);
    defer visited.deinit();
    
    // Display dependency tree
    var it = zon_file.dependencies.iterator();
    var dep_count: usize = 0;
    const total_deps = zon_file.dependencies.count();
    
    while (it.next()) |entry| {
        dep_count += 1;
        const is_last = dep_count == total_deps;
        const prefix = if (is_last) "└── " else "├── ";
        const next_prefix = if (is_last) "    " else "│   ";
        
        try printDependency(allocator, entry.key_ptr.*, entry.value_ptr.*, prefix, next_prefix, 0, max_depth, show_duplicates, show_versions, &visited);
    }
    
    // Show statistics
    std.debug.print("\n📊 Statistics:\n", .{});
    std.debug.print("   Direct dependencies: {d}\n", .{zon_file.dependencies.count()});
    
    if (show_duplicates and visited.count() > 0) {
        var duplicate_count: u32 = 0;
        var duplicate_it = visited.iterator();
        while (duplicate_it.next()) |entry| {
            if (entry.value_ptr.* > 1) {
                duplicate_count += 1;
            }
        }
        if (duplicate_count > 0) {
            std.debug.print("   Duplicate dependencies: {d}\n", .{duplicate_count});
        }
    }
}

/// Print a single dependency with proper tree formatting
fn printDependency(
    allocator: Allocator,
    name: []const u8,
    dep: anytype, // Dependency struct
    prefix: []const u8,
    next_prefix: []const u8,
    current_depth: u32,
    max_depth: ?u32,
    show_duplicates: bool,
    show_versions: bool,
    visited: *std.StringHashMap(u32),
) !void {
    // Track visits for duplicate detection
    const visit_count = visited.get(name) orelse 0;
    try visited.put(try allocator.dupe(u8, name), visit_count + 1);
    
    // Extract version from URL if possible
    var version_info: []const u8 = "";
    if (show_versions) {
        version_info = extractVersionFromUrl(allocator, dep.url) catch "";
    }
    defer if (version_info.len > 0) allocator.free(version_info);
    
    // Print the dependency
    std.debug.print("{s}{s}", .{ prefix, name });
    
    if (show_versions and version_info.len > 0) {
        std.debug.print(" v{s}", .{version_info});
    }
    
    if (show_duplicates and visit_count > 0) {
        std.debug.print(" (duplicate #{d})", .{visit_count + 1});
    }
    
    // Show hash (truncated)
    if (dep.hash.len >= 16) {
        std.debug.print(" [{s}...]", .{dep.hash[0..16]});
    }
    
    std.debug.print("\n", .{});
    
    // Check if we should recurse deeper
    if (max_depth) |depth| {
        if (current_depth >= depth) return;
    }
    
    // For now, we don't recurse into sub-dependencies since we'd need to
    // download and parse their build.zig.zon files
    // This could be a future enhancement
    _ = next_prefix;
}

/// Extract version information from a GitHub URL
fn extractVersionFromUrl(allocator: Allocator, url: []const u8) ![]const u8 {
    // Look for version patterns in GitHub URLs
    // https://github.com/user/repo/archive/refs/tags/v1.0.0.tar.gz
    // https://github.com/user/repo/archive/refs/heads/main.tar.gz
    
    if (std.mem.indexOf(u8, url, "/tags/")) |tags_pos| {
        const version_start = tags_pos + 6; // "/tags/".len
        if (std.mem.indexOfPos(u8, url, version_start, ".tar.gz")) |version_end| {
            var version = url[version_start..version_end];
            // Remove 'v' prefix if present
            if (std.mem.startsWith(u8, version, "v")) {
                version = version[1..];
            }
            return allocator.dupe(u8, version);
        }
    }
    
    if (std.mem.indexOf(u8, url, "/heads/")) |heads_pos| {
        const branch_start = heads_pos + 7; // "/heads/".len
        if (std.mem.indexOfPos(u8, url, branch_start, ".tar.gz")) |branch_end| {
            const branch = url[branch_start..branch_end];
            return std.fmt.allocPrint(allocator, "branch-{s}", .{branch});
        }
    }
    
    return allocator.dupe(u8, "unknown");
}