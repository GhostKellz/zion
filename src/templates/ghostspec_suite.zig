const std = @import("std");
const ghostspec = @import("ghostspec");

/// Example domain code under test. Projects should edit or replace these with
/// their own modules. GhostSpec encourages keeping domain logic separate from
/// testing helpers so the suites stay readable.
const Calculator = struct {
    fn add(a: i32, b: i32) i32 {
        return a + b;
    }

    fn divide(a: i32, b: i32) !f32 {
        if (b == 0) return error.DivisionByZero;
        return @as(f32, @floatFromInt(a)) / @as(f32, @floatFromInt(b));
    }
};

// -----------------------------------------------------------------------------
// Property-Based Testing
// -----------------------------------------------------------------------------

fn propertyAdditionCommutative(values: struct { a: i32, b: i32 }) !void {
    try std.testing.expect(Calculator.add(values.a, values.b) == Calculator.add(values.b, values.a));
}

test "ghostspec/property: addition is commutative" {
    try ghostspec.property(struct { a: i32, b: i32 }, propertyAdditionCommutative);
}

// -----------------------------------------------------------------------------
// Fuzzing
// -----------------------------------------------------------------------------

const FuzzTargets = struct {
    fn parseInteger(input: []const u8) !void {
        _ = std.fmt.parseInt(i32, input, 10) catch {
            // Non-integer inputs are fine; they should not crash.
            return;
        };
    }
};

test "ghostspec/fuzz: parseInteger is crash-free" {
    const config = ghostspec.fuzzing.FuzzConfig{
        .max_iterations = 128,
        .max_input_size = 32,
        .timeout_ms = 200,
        .corpus_dir = ".zion/ghostspec/corpus",
        .crashes_dir = ".zion/ghostspec/crashes",
    };

    var fuzzer = try ghostspec.Fuzzer.init(std.testing.allocator, config);
    defer fuzzer.deinit();

    var result = try fuzzer.run(FuzzTargets.parseInteger, 128);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.crashes_found == 0);
}

// -----------------------------------------------------------------------------
// Benchmarking
// -----------------------------------------------------------------------------

fn benchFibonacci(_: std.mem.Allocator) void {
    const fib = fibonacci(20);
    std.mem.doNotOptimizeAway(fib);
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

test "ghostspec/bench: fibonacci performance" {
    var bench = ghostspec.benchmarking.Benchmark.init(std.testing.allocator, .{
        .iterations = 200,
        .warmup_iterations = 20,
        .track_memory = true,
    });

    const result = try bench.runBenchmark("fibonacci", benchFibonacci);
    try std.testing.expect(result.iterations_run > 0);
}

// -----------------------------------------------------------------------------
// Mocking
// -----------------------------------------------------------------------------

test "ghostspec/mock: divide handles zero" {
    var calc_mock = ghostspec.mock(Calculator);
    defer calc_mock.deinit();

    _ = calc_mock.when("add").returnValue(i32, 42);
    _ = calc_mock.when("divide").err(error.DivisionByZero);

    const sum = try calc_mock.executeCall("add", i32, .{ 19, 23 });
    try std.testing.expectEqual(@as(i32, 42), sum);

    try std.testing.expectError(error.DivisionByZero, calc_mock.executeCall("divide", !f32, .{ 4, 0 }));
    try calc_mock.verifyCalled("divide", .{ 4, 0 });
}
