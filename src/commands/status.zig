const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const zion_root = @import("../root.zig");
const Dir = std.Io.Dir;
const Io = std.Io;

/// Display comprehensive project status
pub fn status(allocator: Allocator, args: []const [:0]const u8) !void {
    _ = args; // Reserved for future options

    std.debug.print("🚦 **Zion Project Status**\n", .{});
    std.debug.print("=====================================\n\n", .{});

    // Basic project info
    try displayBasicStatus(allocator);
}

/// Display basic project status without AI
fn displayBasicStatus(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    std.debug.print("📁 **Project Overview**\n", .{});
    std.debug.print("-----------------------------\n", .{});

    // Check if build.zig.zon exists
    const zon_exists = blk: {
        cwd.access(io, "build.zig.zon", .{}) catch break :blk false;
        break :blk true;
    };
    const build_exists = blk: {
        cwd.access(io, "build.zig", .{}) catch break :blk false;
        break :blk true;
    };

    if (!zon_exists) {
        std.debug.print("❌ No build.zig.zon found\n", .{});
        std.debug.print("💡 Run 'zion init' to initialize project\n\n", .{});
        return;
    }

    std.debug.print("✅ build.zig.zon: Found\n", .{});
    std.debug.print("✅ build.zig: {s}\n", .{if (build_exists) "Found" else "Missing"});

    // Parse and display zon file info
    const zon_content = cwd.readFileAlloc(io, "build.zig.zon", allocator, Io.Limit.limited(1024 * 1024)) catch |err| {
        std.debug.print("❌ Failed to read build.zig.zon: {any}\n\n", .{err});
        return;
    };
    defer allocator.free(zon_content);

    var zon_file = ZonFile.parseZonContent(allocator, zon_content) catch |err| {
        std.debug.print("❌ Failed to parse build.zig.zon: {any}\n\n", .{err});
        return;
    };
    defer zon_file.deinit();

    std.debug.print("📦 Project: {s}\n", .{zon_file.name});
    std.debug.print("🏷️  Version: {s}\n", .{zon_file.version});

    const dep_count = zon_file.dependencies.count();
    std.debug.print("📚 Dependencies: {d}\n", .{dep_count});

    if (dep_count > 0) {
        std.debug.print("\n📋 **Dependencies**:\n", .{});
        var iterator = zon_file.dependencies.iterator();
        while (iterator.next()) |entry| {
            std.debug.print("  • {s}\n", .{entry.key_ptr.*});
        }
    }

    std.debug.print("\n", .{});
}

/// Show minimal status for CI/CD environments
pub fn statusMinimal(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const zon_exists = blk: {
        cwd.access(io, "build.zig.zon", .{}) catch break :blk false;
        break :blk true;
    };
    if (!zon_exists) {
        std.debug.print("not_initialized\n", .{});
        return;
    }

    const zon_content = cwd.readFileAlloc(io, "build.zig.zon", allocator, Io.Limit.limited(1024 * 1024)) catch {
        std.debug.print("parse_error\n", .{});
        return;
    };
    defer allocator.free(zon_content);

    var zon_file = ZonFile.parseZonContent(allocator, zon_content) catch {
        std.debug.print("parse_error\n", .{});
        return;
    };
    defer zon_file.deinit();

    std.debug.print("ok:{d}_deps\n", .{zon_file.dependencies.count()});
}
