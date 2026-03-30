const std = @import("std");
const Allocator = std.mem.Allocator;
const zion_root = @import("root.zig");

/// Retry policy for network operations with exponential backoff
pub const RetryPolicy = struct {
    max_attempts: u32 = 3,
    initial_delay_ms: u64 = 100,
    max_delay_ms: u64 = 5000,
    backoff_factor: f32 = 2.0,
    jitter: bool = true, // Add randomness to prevent thundering herd

    pub const default: RetryPolicy = .{};
    pub const aggressive: RetryPolicy = .{ .max_attempts = 5, .initial_delay_ms = 50 };
    pub const conservative: RetryPolicy = .{ .max_attempts = 2, .initial_delay_ms = 500, .max_delay_ms = 10000 };
};

/// Circuit breaker states
pub const CircuitState = enum {
    closed, // Normal operation, requests flow through
    open, // Failure threshold exceeded, reject requests immediately
    half_open, // Testing if service recovered
};

/// Circuit breaker pattern to prevent cascading failures
pub const CircuitBreaker = struct {
    state: CircuitState = .closed,
    failure_count: u32 = 0,
    success_count: u32 = 0,
    failure_threshold: u32 = 5,
    success_threshold: u32 = 3, // Successes needed in half_open to close
    reset_timeout_ms: u64 = 30000,
    last_failure_time: i64 = 0,
    last_state_change: i64 = 0,

    pub fn init() CircuitBreaker {
        return .{};
    }

    /// Record a successful operation
    pub fn recordSuccess(self: *CircuitBreaker) void {
        switch (self.state) {
            .closed => {
                self.failure_count = 0;
                self.success_count += 1;
            },
            .half_open => {
                self.success_count += 1;
                if (self.success_count >= self.success_threshold) {
                    self.transitionTo(.closed);
                }
            },
            .open => {},
        }
    }

    /// Record a failed operation
    pub fn recordFailure(self: *CircuitBreaker) void {
        self.last_failure_time = zion_root.timestamp();
        self.failure_count += 1;

        switch (self.state) {
            .closed => {
                if (self.failure_count >= self.failure_threshold) {
                    self.transitionTo(.open);
                }
            },
            .half_open => {
                // Single failure in half_open goes back to open
                self.transitionTo(.open);
            },
            .open => {},
        }
    }

    /// Check if we should attempt the operation
    pub fn shouldAttempt(self: *CircuitBreaker) bool {
        switch (self.state) {
            .closed => return true,
            .open => {
                const now = zion_root.timestamp();
                const elapsed = @as(u64, @intCast(now - self.last_state_change));
                if (elapsed >= self.reset_timeout_ms) {
                    self.transitionTo(.half_open);
                    return true;
                }
                return false;
            },
            .half_open => return true,
        }
    }

    fn transitionTo(self: *CircuitBreaker, new_state: CircuitState) void {
        self.state = new_state;
        self.last_state_change = zion_root.timestamp();
        self.failure_count = 0;
        self.success_count = 0;
    }

    /// Get human-readable state description
    pub fn stateDescription(self: *const CircuitBreaker) []const u8 {
        return switch (self.state) {
            .closed => "healthy",
            .open => "failing",
            .half_open => "recovering",
        };
    }
};

/// Health tracking for a single registry
pub const RegistryHealth = struct {
    registry_name: []const u8,
    success_count: u64 = 0,
    failure_count: u64 = 0,
    total_response_time_ms: u64 = 0,
    request_count: u64 = 0,
    last_check: i64 = 0,
    last_success: i64 = 0,
    last_error: ?[]const u8 = null,
    circuit_breaker: CircuitBreaker = .{},

    pub fn init(name: []const u8) RegistryHealth {
        return .{
            .registry_name = name,
            .circuit_breaker = CircuitBreaker.init(),
        };
    }

    /// Record a successful request with response time
    pub fn recordSuccess(self: *RegistryHealth, response_time_ms: u64) void {
        self.success_count += 1;
        self.request_count += 1;
        self.total_response_time_ms += response_time_ms;
        self.last_check = zion_root.timestamp();
        self.last_success = self.last_check;
        self.last_error = null;
        self.circuit_breaker.recordSuccess();
    }

    /// Record a failed request
    pub fn recordFailure(self: *RegistryHealth, error_msg: ?[]const u8) void {
        self.failure_count += 1;
        self.request_count += 1;
        self.last_check = zion_root.timestamp();
        self.last_error = error_msg;
        self.circuit_breaker.recordFailure();
    }

    /// Calculate health score (0.0 = dead, 1.0 = perfect)
    pub fn healthScore(self: *const RegistryHealth) f32 {
        if (self.request_count == 0) return 1.0; // No data, assume healthy

        // Base score from success rate
        const success_rate = @as(f32, @floatFromInt(self.success_count)) /
            @as(f32, @floatFromInt(self.request_count));

        // Penalty for circuit breaker state
        const state_penalty: f32 = switch (self.circuit_breaker.state) {
            .closed => 0.0,
            .half_open => 0.3,
            .open => 0.8,
        };

        return @max(0.0, success_rate - state_penalty);
    }

    /// Average response time in milliseconds
    pub fn avgResponseMs(self: *const RegistryHealth) u64 {
        if (self.success_count == 0) return 0;
        return self.total_response_time_ms / self.success_count;
    }

    /// Check if registry is available for requests
    pub fn isAvailable(self: *RegistryHealth) bool {
        return self.circuit_breaker.shouldAttempt();
    }
};

/// Execute an operation with retry and exponential backoff
pub fn retryWithBackoff(
    comptime T: type,
    policy: RetryPolicy,
    context: anytype,
    operation: fn (@TypeOf(context)) anyerror!T,
) anyerror!T {
    var attempt: u32 = 0;
    var delay_ms = policy.initial_delay_ms;

    while (attempt < policy.max_attempts) : (attempt += 1) {
        if (operation(context)) |result| {
            return result;
        } else |err| {
            // Check if error is retryable
            if (!isRetryableError(err)) {
                return err;
            }

            // Last attempt, propagate error
            if (attempt + 1 >= policy.max_attempts) {
                return err;
            }

            // Sleep with backoff
            const sleep_ms = if (policy.jitter)
                addJitter(delay_ms)
            else
                delay_ms;

            std.time.sleep(sleep_ms * std.time.ns_per_ms);

            // Calculate next delay with backoff
            const next_delay = @as(u64, @intFromFloat(@as(f32, @floatFromInt(delay_ms)) * policy.backoff_factor));
            delay_ms = @min(next_delay, policy.max_delay_ms);
        }
    }

    return error.MaxRetriesExceeded;
}

/// Add jitter to prevent thundering herd
fn addJitter(delay_ms: u64) u64 {
    const io = zion_root.getIo() catch return delay_ms;
    var random_bytes: [1]u8 = undefined;
    io.random(&random_bytes);

    // Add +/- 25% jitter
    const jitter_range = delay_ms / 4;
    const jitter = @as(u64, random_bytes[0]) * jitter_range / 255;
    const base = delay_ms - (jitter_range / 2);
    return base + jitter;
}

/// Check if an error is worth retrying
fn isRetryableError(err: anyerror) bool {
    return switch (err) {
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.NetworkUnreachable,
        error.HostUnreachable,
        error.TemporaryNameServerFailure,
        error.ServerNameResolutionFailed,
        error.Timeout,
        error.WouldBlock,
        error.SystemResources,
        => true,
        else => false,
    };
}

/// Timeout configuration for operations
pub const TimeoutConfig = struct {
    connect_ms: u64 = 5000,
    read_ms: u64 = 30000,
    total_ms: u64 = 60000,

    pub const default: TimeoutConfig = .{};
    pub const fast: TimeoutConfig = .{ .connect_ms = 2000, .read_ms = 10000, .total_ms = 20000 };
    pub const slow: TimeoutConfig = .{ .connect_ms = 10000, .read_ms = 60000, .total_ms = 120000 };
};

/// Health manager for multiple registries
pub const HealthManager = struct {
    allocator: Allocator,
    registries: std.StringHashMap(RegistryHealth),

    pub fn init(allocator: Allocator) HealthManager {
        return .{
            .allocator = allocator,
            .registries = std.StringHashMap(RegistryHealth).init(allocator),
        };
    }

    pub fn deinit(self: *HealthManager) void {
        self.registries.deinit();
    }

    /// Get or create health tracker for a registry
    pub fn getOrCreate(self: *HealthManager, registry_name: []const u8) !*RegistryHealth {
        const result = try self.registries.getOrPut(registry_name);
        if (!result.found_existing) {
            result.value_ptr.* = RegistryHealth.init(registry_name);
        }
        return result.value_ptr;
    }

    /// Get available registries sorted by health score
    pub fn getAvailableSorted(self: *HealthManager, allocator: Allocator) ![][]const u8 {
        var available = std.ArrayList(struct { name: []const u8, score: f32 }).init(allocator);
        defer available.deinit();

        var it = self.registries.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.isAvailable()) {
                try available.append(.{
                    .name = entry.key_ptr.*,
                    .score = entry.value_ptr.healthScore(),
                });
            }
        }

        // Sort by health score descending
        std.mem.sort(
            @TypeOf(available.items[0]),
            available.items,
            {},
            struct {
                fn lessThan(_: void, a: anytype, b: anytype) bool {
                    return a.score > b.score;
                }
            }.lessThan,
        );

        var result = try allocator.alloc([]const u8, available.items.len);
        for (available.items, 0..) |item, i| {
            result[i] = item.name;
        }
        return result;
    }

    /// Print health status summary
    pub fn printStatus(self: *HealthManager) void {
        std.debug.print("\nRegistry Health Status:\n", .{});
        std.debug.print("{s:<30} {s:<10} {s:<10} {s:<10} {s:<10}\n", .{
            "Registry", "State", "Success", "Failed", "Avg(ms)",
        });
        std.debug.print("{s:->70}\n", .{""});

        var it = self.registries.iterator();
        while (it.next()) |entry| {
            const health = entry.value_ptr;
            std.debug.print("{s:<30} {s:<10} {d:<10} {d:<10} {d:<10}\n", .{
                health.registry_name,
                health.circuit_breaker.stateDescription(),
                health.success_count,
                health.failure_count,
                health.avgResponseMs(),
            });
        }
    }
};

// Tests
test "circuit breaker transitions" {
    var cb = CircuitBreaker.init();

    // Should start closed
    try std.testing.expect(cb.state == .closed);
    try std.testing.expect(cb.shouldAttempt());

    // Record failures up to threshold
    var i: u32 = 0;
    while (i < cb.failure_threshold) : (i += 1) {
        cb.recordFailure();
    }

    // Should now be open
    try std.testing.expect(cb.state == .open);
    try std.testing.expect(!cb.shouldAttempt());
}

test "health score calculation" {
    var health = RegistryHealth.init("test");

    // Initial score should be 1.0 (no data)
    try std.testing.expectEqual(@as(f32, 1.0), health.healthScore());

    // Record some successes and failures
    health.recordSuccess(100);
    health.recordSuccess(100);
    health.recordFailure(null);

    // 2/3 success rate = ~0.67
    const score = health.healthScore();
    try std.testing.expect(score > 0.6 and score < 0.7);
}
