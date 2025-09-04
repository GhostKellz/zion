const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn tui(allocator: Allocator, args: [][:0]u8) !void {
    _ = allocator;
    _ = args;
    std.debug.print("🎨 Interactive TUI (temporarily disabled for Zig v0.16.0 compatibility)\n", .{});
    std.debug.print("This feature will be re-enabled once the I/O API migration is complete.\n", .{});
}