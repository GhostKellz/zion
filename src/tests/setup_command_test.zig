const std = @import("std");
const testing = std.testing;
const setup = @import("../commands/setup.zig");

const SetupHarness = struct {
    pub var call_index: usize = 0;
    pub var expected_version: []const u8 = "";
    pub var version_arg: ?[:0]u8 = null;

    fn handler(_: std.mem.Allocator, args: [][:0]u8) !void {
        call_index += 1;
        try testing.expectEqual(@as(usize, 4), args.len);
        try testing.expect(std.mem.eql(u8, std.mem.sliceTo(args[0], 0), "zion"));
        try testing.expect(std.mem.eql(u8, std.mem.sliceTo(args[1], 0), "zig"));

        if (call_index == 1) {
            try testing.expect(std.mem.eql(u8, std.mem.sliceTo(args[2], 0), "install"));
            version_arg = args[3];
        } else if (call_index == 2) {
            try testing.expect(std.mem.eql(u8, std.mem.sliceTo(args[2], 0), "use"));
            try testing.expect(version_arg != null);
            try testing.expectEqual(version_arg.?.ptr, args[3].ptr);
        } else {
            return error.UnexpectedCall;
        }

        const version_slice = std.mem.sliceTo(args[3], 0);
        try testing.expect(std.mem.eql(u8, version_slice, expected_version));
        try testing.expectEqual(@as(u8, 0), args[3][args[3].len]);
    }

    fn reset() void {
        call_index = 0;
        expected_version = "";
        version_arg = null;
    }
};

test "setup zig installs and activates specified version" {
    const allocator = testing.allocator;

    defer {
        setup.zig_manager_override = null;
        setup.check_command_override = null;
        SetupHarness.reset();
    }

    setup.check_command_override = struct {
        fn handler(_: []const u8) bool {
            return false;
        }
    }.handler;

    SetupHarness.reset();
    SetupHarness.expected_version = "0.14.1";
    setup.zig_manager_override = SetupHarness.handler;

    var args = [_][:0]u8{
        try allocator.dupeSentinel(u8, "zion", 0),
        try allocator.dupeSentinel(u8, "setup", 0),
        try allocator.dupeSentinel(u8, "zig", 0),
        try allocator.dupeSentinel(u8, "--version=0.14.1", 0),
    };
    defer {
        for (args) |arg| allocator.free(arg);
    }

    try setup.setup(allocator, args[0..]);

    try testing.expectEqual(@as(usize, 2), SetupHarness.call_index);
}

test "setup zig respects skip install flag" {
    const allocator = testing.allocator;

    defer {
        setup.zig_manager_override = null;
        setup.check_command_override = null;
        SetupHarness.reset();
    }

    setup.check_command_override = struct {
        fn handler(_: []const u8) bool {
            return false;
        }
    }.handler;

    SetupHarness.reset();
    setup.zig_manager_override = SetupHarness.handler;

    var args = [_][:0]u8{
        try allocator.dupeSentinel(u8, "zion", 0),
        try allocator.dupeSentinel(u8, "setup", 0),
        try allocator.dupeSentinel(u8, "zig", 0),
        try allocator.dupeSentinel(u8, "--skip-install", 0),
    };
    defer {
        for (args) |arg| allocator.free(arg);
    }

    try setup.setup(allocator, args[0..]);

    try testing.expectEqual(@as(usize, 0), SetupHarness.call_index);
}
