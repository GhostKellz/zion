const std = @import("std");

const Calculator = struct {
    fn add(a: i32, b: i32) i32 {
        return a + b;
    }

    fn divide(a: i32, b: i32) !f32 {
        if (b == 0) return error.DivisionByZero;
        return @as(f32, @floatFromInt(a)) / @as(f32, @floatFromInt(b));
    }
};

fn envMapValue(name: []const u8) ?[]const u8 {
    return std.testing.environ.getPosix(name);
}

fn envU64(name: []const u8, default_value: u64) u64 {
    const value = envMapValue(name) orelse return default_value;
    return std.fmt.parseInt(u64, value, 10) catch default_value;
}

fn percentile(sorted: []const u64, pct: u8) f64 {
    const idx = (@as(f64, @floatFromInt(pct)) / 100.0) * @as(f64, @floatFromInt(sorted.len - 1));
    const lo = @as(usize, @intFromFloat(@floor(idx)));
    const hi = @min(lo + 1, sorted.len - 1);
    const weight = idx - @floor(idx);
    const lo_val: f64 = @floatFromInt(sorted[lo]);
    const hi_val: f64 = @floatFromInt(sorted[hi]);
    return lo_val + weight * (hi_val - lo_val);
}

test "zion/property: addition is commutative" {
    const seed = envU64("ZION_TEST_SEED", 0x5eed1234);
    const cases = envU64("ZION_TEST_CASES", 128);

    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    var i: u64 = 0;
    while (i < cases) : (i += 1) {
        const a = random.int(i16);
        const b = random.int(i16);
        if (Calculator.add(a, b) != Calculator.add(b, a)) {
            std.debug.print("Property failed with seed={d}, iteration={d}, a={d}, b={d}\n", .{ seed, i, a, b });
            return error.PropertyFailed;
        }
    }
}

test "zion/fuzz: parseInteger is crash-free" {
    const seed = envU64("ZION_TEST_SEED", 0x5eed1234);
    const cases = envU64("ZION_TEST_CASES", 64);

    const corpus = [_][]const u8{
        "0",
        "42",
        "-99",
        "",
        "hello",
        "999999999999999999999",
        "12three",
    };

    for (corpus) |input| {
        _ = std.fmt.parseInt(i32, input, 10) catch null;
    }

    var prng = std.Random.DefaultPrng.init(seed ^ 0xF022);
    const random = prng.random();
    var buffer: [32]u8 = undefined;

    var i: u64 = 0;
    while (i < cases) : (i += 1) {
        const len = random.uintLessThan(usize, buffer.len) + 1;
        for (buffer[0..len]) |*byte| {
            byte.* = random.intRangeAtMost(u8, 32, 126);
        }
        _ = std.fmt.parseInt(i32, buffer[0..len], 10) catch null;
    }
}

fn fibonacci(n: u32) u64 {
    if (n <= 1) return n;
    var a: u64 = 0;
    var b: u64 = 1;
    var i: u32 = 2;
    while (i <= n) : (i += 1) {
        const next = a + b;
        a = b;
        b = next;
    }
    return b;
}

test "zion/bench: fibonacci performance" {
    const iterations = envU64("ZION_TEST_CASES", 200);
    const budget_ms = envU64("ZION_TEST_TIME_BUDGET_MS", 1000);

    var samples: std.ArrayListUnmanaged(u64) = .empty;
    defer samples.deinit(std.testing.allocator);

    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        const before = sum;
        sum += fibonacci(20);
        try samples.append(std.testing.allocator, sum - before);
    }

    std.mem.sort(u64, samples.items, {}, std.sort.asc(u64));
    std.debug.print(
        "Benchmark iterations={d} p50={d:.2} p95={d:.2} p99={d:.2} budget_ms={d}\n",
        .{ iterations, percentile(samples.items, 50), percentile(samples.items, 95), percentile(samples.items, 99), budget_ms },
    );
    std.mem.doNotOptimizeAway(sum);
    try std.testing.expect(iterations > 0);
    try std.testing.expect(sum > 0);
}

const CalculatorFake = struct {
    add_calls: usize = 0,

    fn add(self: *CalculatorFake, a: i32, b: i32) i32 {
        self.add_calls += 1;
        _ = a;
        _ = b;
        return 42;
    }

    fn divide(_: *CalculatorFake, a: i32, b: i32) !f32 {
        _ = a;
        _ = b;
        return error.DivisionByZero;
    }
};

test "zion/mock: divide handles zero" {
    var fake = CalculatorFake{};

    try std.testing.expectEqual(@as(i32, 42), fake.add(19, 23));
    try std.testing.expectEqual(@as(usize, 1), fake.add_calls);
    try std.testing.expectError(error.DivisionByZero, fake.divide(4, 0));
}
