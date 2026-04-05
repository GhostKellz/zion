const std = @import("std");

pub fn zigistry(allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    _ = allocator;
    _ = args;

    std.debug.print("🔥 'zion zigistry' is not part of the shipped v1.1.0 runtime surface.\n", .{});
    std.debug.print("   Phase 3 removed the old zsync-backed Zigistry integration behind this command.\n", .{});
    std.debug.print("   Use 'zion search --registry=zigistry', 'zion info', and 'zion publish' for supported workflows.\n", .{});
}
