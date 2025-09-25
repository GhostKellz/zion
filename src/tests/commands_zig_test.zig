const std = @import("std");
const testing = std.testing;
const commands = @import("../commands/mod.zig");

const Harness = struct {
    pub var expected: []const []const u8 = &[_][]const u8{};
    pub var call_count: usize = 0;

    fn handler(_: std.mem.Allocator, args: [][:0]u8) !void {
        call_count += 1;
        try testing.expectEqual(expected.len + 2, args.len);
        try testing.expect(std.mem.eql(u8, std.mem.sliceTo(args[0], 0), "zion"));
        try testing.expect(std.mem.eql(u8, std.mem.sliceTo(args[1], 0), "zig"));

        for (expected, 0..) |exp, idx| {
            try testing.expect(std.mem.eql(u8, std.mem.sliceTo(args[idx + 2], 0), exp));
        }

        for (args) |arg| {
            try testing.expectEqual(@as(u8, 0), arg[arg.len]);
        }
    }
};

test "zion zig alias prefixes base command" {
    const allocator = testing.allocator;

    defer commands.resetZigCommandHandler();

    const input_args = [_][]const u8{ "install", "0.14.1", "--force" };

    Harness.expected = input_args[0..];
    Harness.call_count = 0;
    commands.setZigCommandHandler(Harness.handler);

    try commands.zig(allocator, input_args[0..]);

    try testing.expectEqual(@as(usize, 1), Harness.call_count);
}

test "zion zig alias handles empty args" {
    const allocator = testing.allocator;

    defer commands.resetZigCommandHandler();

    Harness.expected = &[_][]const u8{};
    Harness.call_count = 0;
    commands.setZigCommandHandler(Harness.handler);

    try commands.zig(allocator, &[_][]const u8{});

    try testing.expectEqual(@as(usize, 1), Harness.call_count);
}
