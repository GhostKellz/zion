const std = @import("std");
const generator = @import("generator.zig");
const zion_root = @import("../root.zig");

pub const Config = struct {
    seed: ?u64 = null,
    cases: u32 = 100,
    max_size: u32 = 64,
    enable_shrinking: bool = true,
    max_shrinking_attempts: u32 = 32,
};

pub const Result = struct {
    passed: bool,
    tests_run: u32,
    seed: u64,
    counterexample: ?[]const u8 = null,
    shrunk_counterexample: ?[]const u8 = null,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        if (self.counterexample) |value| allocator.free(value);
        if (self.shrunk_counterexample) |value| allocator.free(value);
    }
};

pub const Runner = struct {
    allocator: std.mem.Allocator,
    config: Config,
    runner_seed: u64,
    prng: std.Random.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, config: Config) Runner {
        const runner_seed = config.seed orelse @as(u64, @intCast(zion_root.milliTimestamp()));
        return .{
            .allocator = allocator,
            .config = config,
            .runner_seed = runner_seed,
            .prng = std.Random.DefaultPrng.init(runner_seed),
        };
    }

    pub fn seed(self: *const Runner) u64 {
        return self.runner_seed;
    }

    pub fn run(self: *Runner, comptime T: type, comptime property_fn: anytype) !Result {
        var result = Result{ .passed = true, .tests_run = 0, .seed = self.seed() };

        var index: u32 = 0;
        while (index < self.config.cases) : (index += 1) {
            const value = try generator.generate(T, self.allocator, self.prng.random(), self.config.max_size);
            defer generator.deinit(T, value, self.allocator);

            property_fn(value) catch {
                result.passed = false;
                result.tests_run = index + 1;
                result.counterexample = try valueToString(self.allocator, T, value);
                if (self.config.enable_shrinking) {
                    if (try shrinkValue(self.allocator, self.config, T, value, property_fn)) |shrunk| {
                        defer generator.deinit(T, shrunk, self.allocator);
                        result.shrunk_counterexample = try valueToString(self.allocator, T, shrunk);
                    }
                }
                return result;
            };
        }

        result.tests_run = self.config.cases;
        return result;
    }
};

pub fn envConfig() Config {
    return .{
        .seed = parseEnvUnsigned("ZION_TEST_SEED"),
        .cases = @intCast(parseEnvUnsigned("ZION_TEST_CASES") orelse 100),
        .max_size = @intCast(parseEnvUnsigned("ZION_TEST_MAX_SIZE") orelse 64),
    };
}

fn parseEnvUnsigned(name: []const u8) ?u64 {
    const value = @import("../root.zig").getEnv(name) orelse return null;
    return std.fmt.parseInt(u64, value, 10) catch null;
}

fn shrinkValue(allocator: std.mem.Allocator, config: Config, comptime T: type, value: T, comptime property_fn: anytype) !?T {
    _ = allocator;
    return switch (@typeInfo(T)) {
        .int => blk: {
            var current = value;
            var attempts: u32 = 0;
            while (attempts < config.max_shrinking_attempts) : (attempts += 1) {
                if (current == 0) break;
                const next = @divTrunc(current, 2);
                property_fn(next) catch {
                    current = next;
                    continue;
                };
                break;
            }
            break :blk if (current != value) current else null;
        },
        else => null,
    };
}

fn valueToString(allocator: std.mem.Allocator, comptime T: type, value: T) ![]const u8 {
    return switch (@typeInfo(T)) {
        .int, .float, .bool => std.fmt.allocPrint(allocator, "{any}", .{value}),
        .pointer => |ptr_info| if (ptr_info.child == u8) std.fmt.allocPrint(allocator, "\"{s}\"", .{value}) else std.fmt.allocPrint(allocator, "ptr@{*}", .{value.ptr}),
        else => std.fmt.allocPrint(allocator, "value<{s}>", .{@typeName(T)}),
    };
}

test "property runner uses seed and shrink" {
    const Check = struct {
        fn failing(value: u32) !void {
            if (value > 0) return error.Failed;
        }
    };

    var runner = Runner.init(std.testing.allocator, .{ .seed = 1234, .cases = 10 });
    var result = try runner.run(u32, Check.failing);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(@as(u64, 1234), result.seed);
    try std.testing.expect(result.counterexample != null);
}
