const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const ZonFile = @import("../manifest.zig").ZonFile;

/// Builds the project by invoking the Zig build system
pub fn build(allocator: mem.Allocator) !void {
    const zon_path = "build.zig.zon";
    const build_path = "build.zig";

    // Check if both files exist
    const cwd = fs.cwd();
    cwd.access(zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    cwd.access(build_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: build.zig not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    std.debug.print("Building project...\n", .{});

    // Invoke zig build
    const argv = [_][]const u8{ "zig", "build" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
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
