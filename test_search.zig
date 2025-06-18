const std = @import("std");
const search = @import("src/commands/search.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Testing search module compilation...\n", .{});
    
    const test_args = [_][]const u8{ "zion", "search", "test" };
    try search.search(allocator, &test_args);
}