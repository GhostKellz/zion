const std = @import("std");
const zion_root = @import("../root.zig");

pub const Config = struct {
    iterations: u32 = 200,
    warmup_iterations: u32 = 20,
    track_memory: bool = true,
};

pub const Stats = struct {
    mean_ns: f64,
    median_ns: f64,
    p95_ns: f64,
    p99_ns: f64,
    min_ns: u64,
    max_ns: u64,
};

pub const MemoryInfo = struct {
    bytes_allocated: usize,
    bytes_freed: usize,
    peak_memory: usize,
    allocations: usize,
};

pub const Result = struct {
    name: []const u8,
    iterations_run: u32,
    total_time_ns: u64,
    stats: Stats,
    memory_info: ?MemoryInfo = null,
};

pub const TrackingAllocator = struct {
    child: std.mem.Allocator,
    bytes_allocated: usize = 0,
    bytes_freed: usize = 0,
    peak_memory: usize = 0,
    current_memory: usize = 0,
    allocations: usize = 0,

    pub fn init(child: std.mem.Allocator) TrackingAllocator {
        return .{ .child = child };
    }

    pub fn allocator(self: *TrackingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    pub fn snapshot(self: *const TrackingAllocator) MemoryInfo {
        return .{
            .bytes_allocated = self.bytes_allocated,
            .bytes_freed = self.bytes_freed,
            .peak_memory = self.peak_memory,
            .allocations = self.allocations,
        };
    }

    pub fn reset(self: *TrackingAllocator) void {
        self.bytes_allocated = 0;
        self.bytes_freed = 0;
        self.peak_memory = 0;
        self.current_memory = 0;
        self.allocations = 0;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        const memory = self.child.rawAlloc(len, alignment, ra) orelse return null;
        self.bytes_allocated += len;
        self.current_memory += len;
        self.allocations += 1;
        if (self.current_memory > self.peak_memory) self.peak_memory = self.current_memory;
        return memory;
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) bool {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        if (!self.child.rawResize(buf, alignment, new_len, ra)) return false;
        if (new_len > buf.len) {
            const delta = new_len - buf.len;
            self.bytes_allocated += delta;
            self.current_memory += delta;
            if (self.current_memory > self.peak_memory) self.peak_memory = self.current_memory;
        } else {
            const delta = buf.len - new_len;
            self.bytes_freed += delta;
            self.current_memory -= delta;
        }
        return true;
    }

    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *TrackingAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(buf, alignment, ra);
        self.bytes_freed += buf.len;
        self.current_memory -= buf.len;
    }
};

pub fn envConfig() Config {
    return .{
        .iterations = @intCast(parseEnvUnsigned("ZION_TEST_CASES") orelse 200),
        .warmup_iterations = @intCast(parseEnvUnsigned("ZION_TEST_BENCH_WARMUP") orelse 20),
        .track_memory = parseEnvBool("ZION_TEST_TRACK_MEMORY") orelse true,
    };
}

pub fn run(comptime name: []const u8, comptime bench_fn: anytype) !void {
    var runner = Runner.init(std.testing.allocator, envConfig());
    const result = try runner.runBenchmark(name, bench_fn);
    printResult(result);
}

pub const Runner = struct {
    allocator: std.mem.Allocator,
    config: Config,

    pub fn init(allocator: std.mem.Allocator, config: Config) Runner {
        return .{ .allocator = allocator, .config = config };
    }

    pub fn runBenchmark(self: *Runner, comptime name: []const u8, comptime bench_fn: anytype) !Result {
        var tracking = TrackingAllocator.init(self.allocator);
        var samples: std.ArrayListUnmanaged(u64) = .empty;
        defer samples.deinit(self.allocator);

        var warmup: u32 = 0;
        while (warmup < self.config.warmup_iterations) : (warmup += 1) {
            _ = runSingle(&tracking, bench_fn);
        }
        tracking.reset();

        var total: u64 = 0;
        var iter: u32 = 0;
        while (iter < self.config.iterations) : (iter += 1) {
            const elapsed = runSingle(&tracking, bench_fn);
            try samples.append(self.allocator, elapsed);
            total += elapsed;
        }

        return .{
            .name = name,
            .iterations_run = iter,
            .total_time_ns = total,
            .stats = calculateStats(self.allocator, samples.items),
            .memory_info = if (self.config.track_memory) tracking.snapshot() else null,
        };
    }
};

fn runSingle(tracking: *TrackingAllocator, comptime bench_fn: anytype) u64 {
    const start = monotonicNow();
    const fn_info = @typeInfo(@TypeOf(bench_fn)).@"fn";
    if (fn_info.params.len == 0) {
        bench_fn();
    } else {
        bench_fn(tracking.allocator());
    }
    return monotonicNow() - start;
}

fn monotonicNow() u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

fn calculateStats(allocator: std.mem.Allocator, input: []const u64) Stats {
    if (input.len == 0) return .{ .mean_ns = 0, .median_ns = 0, .p95_ns = 0, .p99_ns = 0, .min_ns = 0, .max_ns = 0 };

    var sorted: std.ArrayListUnmanaged(u64) = .empty;
    defer sorted.deinit(allocator);
    sorted.appendSlice(allocator, input) catch unreachable;
    std.mem.sort(u64, sorted.items, {}, std.sort.asc(u64));

    var total: f64 = 0;
    for (input) |item| total += @floatFromInt(item);

    return .{
        .mean_ns = total / @as(f64, @floatFromInt(input.len)),
        .median_ns = percentile(sorted.items, 50),
        .p95_ns = percentile(sorted.items, 95),
        .p99_ns = percentile(sorted.items, 99),
        .min_ns = sorted.items[0],
        .max_ns = sorted.items[sorted.items.len - 1],
    };
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

fn printResult(result: Result) void {
    std.debug.print("Benchmark: {s}\n", .{result.name});
    std.debug.print("  Iterations: {d}\n", .{result.iterations_run});
    std.debug.print("  Mean: {d:.2}ns\n", .{result.stats.mean_ns});
    std.debug.print("  Median: {d:.2}ns\n", .{result.stats.median_ns});
    std.debug.print("  P95: {d:.2}ns\n", .{result.stats.p95_ns});
    std.debug.print("  P99: {d:.2}ns\n", .{result.stats.p99_ns});
    if (result.memory_info) |memory| {
        std.debug.print("  Peak memory: {d} bytes\n", .{memory.peak_memory});
    }
}

fn parseEnvUnsigned(name: []const u8) ?u64 {
    const value = zion_root.getEnv(name) orelse return null;
    return std.fmt.parseInt(u64, value, 10) catch null;
}

fn parseEnvBool(name: []const u8) ?bool {
    const value = zion_root.getEnv(name) orelse return null;
    if (std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "false")) return false;
    return null;
}

test "benchmark stats calculate" {
    const stats = calculateStats(std.testing.allocator, &.{ 10, 20, 30, 40, 50 });
    try std.testing.expect(stats.mean_ns > 0);
    try std.testing.expect(stats.p99_ns >= stats.p95_ns);
}
