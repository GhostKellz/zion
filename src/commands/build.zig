const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const mem = std.mem;
const ZonFile = @import("../manifest.zig").ZonFile;
const zion_root = @import("../root.zig");

/// Builds the project by invoking the Zig build system
/// Forwards any additional arguments to zig build (e.g., -Doptimize=ReleaseFast)
pub fn build(allocator: mem.Allocator, args: []const [:0]const u8) !void {
    const zon_path = "build.zig.zon";
    const build_path = "build.zig";
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if both files exist
    cwd.access(io, zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    cwd.access(io, build_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: build.zig not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    std.debug.print("Building project...\n", .{});

    // Build argv with forwarded args
    var argv_list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv_list.deinit(allocator);

    try argv_list.append(allocator, "zig");
    try argv_list.append(allocator, "build");

    // Forward remaining args (skip "zion" and "build")
    if (args.len > 2) {
        for (args[2..]) |arg| {
            try argv_list.append(allocator, arg);
        }
    }

    var child = try std.process.spawn(io, .{
        .argv = argv_list.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code == 0) {
                std.debug.print("\n✅ Build completed successfully!\n", .{});
            } else {
                std.debug.print("\n❌ Build failed with exit code {d}\n", .{code});
                return error.BuildFailed;
            }
        },
        else => {
            std.debug.print("\n❌ Build process terminated abnormally\n", .{});
            return error.BuildFailed;
        },
    }
}
