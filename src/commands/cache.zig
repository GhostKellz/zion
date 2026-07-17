const std = @import("std");
const build_cache = @import("../build_cache.zig");
const zion_root = @import("../root.zig");
const paths = @import("../paths.zig");
const Allocator = std.mem.Allocator;

pub fn cache(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        std.debug.print("Usage: zion cache <command> [options]\n", .{});
        std.debug.print("\nCommands:\n", .{});
        std.debug.print("  clear              Clear all cached build artifacts\n", .{});
        std.debug.print("  stats              Show cache statistics\n", .{});
        std.debug.print("  check <project>    Check if build cache is valid for project\n", .{});
        std.debug.print("  restore <project>  Restore build from cache\n", .{});
        return;
    }

    const cache_dir = paths.cacheDir(allocator) catch |err| {
        std.debug.print("❌ Unable to determine a safe cache directory: {s}\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(cache_dir);
    const io = try zion_root.getIo();
    try paths.ensurePrivateDir(io, cache_dir);

    var cache_system = build_cache.BuildCache.init(allocator, cache_dir) catch |err| {
        std.debug.print("❌ Failed to initialize build cache: {}\n", .{err});
        return;
    };
    defer cache_system.deinit();

    const command = args[2];

    if (std.mem.eql(u8, command, "clear")) {
        try cache_system.clearCache();
    } else if (std.mem.eql(u8, command, "stats")) {
        const stats = try cache_system.getStats(allocator);
        defer {
            var mut_stats = stats;
            mut_stats.deinit(allocator);
        }

        std.debug.print("📊 Build Cache Statistics\n", .{});
        std.debug.print("═══════════════════════════\n", .{});
        std.debug.print("Cache Directory: {s}\n", .{stats.cache_dir});
        std.debug.print("Cached Projects: {d}\n", .{stats.entry_count});
        std.debug.print("Total Files: {d}\n", .{stats.file_count});
        std.debug.print("Total Size: {d:.2} MB\n", .{@as(f64, @floatFromInt(stats.total_size_bytes)) / 1024.0 / 1024.0});

        if (stats.total_size_bytes > 500 * 1024 * 1024) { // > 500MB
            std.debug.print("💡 Consider running 'zion cache clear' to free up space\n", .{});
        }
    } else if (std.mem.eql(u8, command, "check")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion cache check <project_name>\n", .{});
            return;
        }

        const project_name = args[3];
        const source_hash = try cache_system.computeSourceHash("src");
        defer allocator.free(source_hash);

        const empty_deps = [_][]const u8{};
        const empty_flags = [_][]const u8{};

        const is_valid = try cache_system.isCacheValid(project_name, source_hash, &empty_deps, &empty_flags);

        if (is_valid) {
            std.debug.print("✅ Cache is valid for project '{s}'\n", .{project_name});
        } else {
            std.debug.print("❌ Cache is invalid or missing for project '{s}'\n", .{project_name});
        }
    } else if (std.mem.eql(u8, command, "restore")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion cache restore <project_name> [output_dir]\n", .{});
            return;
        }

        const project_name = args[3];
        const output_dir = if (args.len > 4) args[4] else "zig-out";

        const restored = try cache_system.restoreCachedBuild(project_name, output_dir);

        if (!restored) {
            std.debug.print("❌ No valid cache entry found for project '{s}'\n", .{project_name});
            std.process.exit(1);
        }
    } else {
        std.debug.print("❌ Unknown cache command: {s}\n", .{command});
        std.debug.print("Run 'zion cache' for usage information\n", .{});
        std.process.exit(1);
    }
}
