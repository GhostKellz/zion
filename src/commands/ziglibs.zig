const std = @import("std");

pub fn ziglibs(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;

    std.debug.print("📚 'zion ziglibs' is not part of the shipped v1.1.0 runtime surface.\n", .{});
    std.debug.print("   Phase 3 removed the old zsync-backed registry integration behind this command.\n", .{});
    std.debug.print("   Use 'zion search', 'zion info', and 'zion registry' for the current supported flow.\n", .{});
}
