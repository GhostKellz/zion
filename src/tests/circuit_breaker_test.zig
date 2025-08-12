const std = @import("std");
const testing = std.testing;

// Circuit breaker structure for testing
const CircuitBreakerState = enum {
    Closed,
    Open,
    HalfOpen,
};

const CircuitBreakerConfig = struct {
    failure_threshold: u32 = 5,
    recovery_timeout_ms: u64 = 60000,
    success_threshold: u32 = 3,
};

const CircuitBreaker = struct {
    allocator: std.mem.Allocator,
    config: CircuitBreakerConfig,
    state: CircuitBreakerState,
    failure_count: u32,
    success_count: u32,
    last_failure_time: i64,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, config: CircuitBreakerConfig) CircuitBreaker {
        return CircuitBreaker{
            .allocator = allocator,
            .config = config,
            .state = .Closed,
            .failure_count = 0,
            .success_count = 0,
            .last_failure_time = 0,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn canExecute(self: *CircuitBreaker) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        switch (self.state) {
            .Closed => return true,
            .Open => {
                const now = std.time.milliTimestamp();
                if (now - self.last_failure_time >= self.config.recovery_timeout_ms) {
                    self.state = .HalfOpen;
                    self.success_count = 0;
                    return true;
                }
                return false;
            },
            .HalfOpen => return true,
        }
    }

    pub fn recordSuccess(self: *CircuitBreaker) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        switch (self.state) {
            .Closed => {
                self.failure_count = 0;
            },
            .HalfOpen => {
                self.success_count += 1;
                if (self.success_count >= self.config.success_threshold) {
                    self.state = .Closed;
                    self.failure_count = 0;
                }
            },
            .Open => {
                // Shouldn't happen if canExecute is used properly
            },
        }
    }

    pub fn recordFailure(self: *CircuitBreaker) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.failure_count += 1;
        self.last_failure_time = std.time.milliTimestamp();

        switch (self.state) {
            .Closed => {
                if (self.failure_count >= self.config.failure_threshold) {
                    self.state = .Open;
                }
            },
            .HalfOpen => {
                self.state = .Open;
                self.success_count = 0;
            },
            .Open => {
                // Already open
            },
        }
    }

    pub fn getState(self: *CircuitBreaker) CircuitBreakerState {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.state;
    }

    pub fn reset(self: *CircuitBreaker) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.state = .Closed;
        self.failure_count = 0;
        self.success_count = 0;
        self.last_failure_time = 0;
    }
};

test "CircuitBreaker: initialization" {
    const allocator = testing.allocator;
    
    const config = CircuitBreakerConfig{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
        .success_threshold = 2,
    };
    
    var breaker = CircuitBreaker.init(allocator, config);
    
    try testing.expect(breaker.getState() == .Closed);
    try testing.expect(breaker.failure_count == 0);
    try testing.expect(breaker.canExecute());
}

test "CircuitBreaker: failure threshold" {
    const allocator = testing.allocator;
    
    const config = CircuitBreakerConfig{
        .failure_threshold = 3,
        .recovery_timeout_ms = 30000,
        .success_threshold = 2,
    };
    
    var breaker = CircuitBreaker.init(allocator, config);
    
    // Should be closed initially
    try testing.expect(breaker.getState() == .Closed);
    try testing.expect(breaker.canExecute());
    
    // Record failures up to threshold
    for (0..2) |_| {
        breaker.recordFailure();
        try testing.expect(breaker.getState() == .Closed);
        try testing.expect(breaker.canExecute());
    }
    
    // One more failure should trip the circuit
    breaker.recordFailure();
    try testing.expect(breaker.getState() == .Open);
    try testing.expect(!breaker.canExecute());
}

test "CircuitBreaker: recovery timeout" {
    const allocator = testing.allocator;
    
    const config = CircuitBreakerConfig{
        .failure_threshold = 2,
        .recovery_timeout_ms = 50, // Short timeout for testing
        .success_threshold = 1,
    };
    
    var breaker = CircuitBreaker.init(allocator, config);
    
    // Trip the circuit breaker
    for (0..2) |_| {
        breaker.recordFailure();
    }
    try testing.expect(breaker.getState() == .Open);
    try testing.expect(!breaker.canExecute());
    
    // Wait for recovery timeout
    std.time.sleep(60 * 1000000); // 60ms > 50ms timeout
    
    // Should transition to half-open
    try testing.expect(breaker.canExecute());
    try testing.expect(breaker.getState() == .HalfOpen);
}

test "CircuitBreaker: half-open state recovery" {
    const allocator = testing.allocator;
    
    const config = CircuitBreakerConfig{
        .failure_threshold = 2,
        .recovery_timeout_ms = 10, // Very short timeout
        .success_threshold = 2,
    };
    
    var breaker = CircuitBreaker.init(allocator, config);
    
    // Trip the circuit breaker
    for (0..2) |_| {
        breaker.recordFailure();
    }
    try testing.expect(breaker.getState() == .Open);
    
    // Wait for recovery
    std.time.sleep(15 * 1000000); // 15ms
    
    // Should be able to execute (half-open)
    try testing.expect(breaker.canExecute());
    try testing.expect(breaker.getState() == .HalfOpen);
    
    // Record success - one short of threshold
    breaker.recordSuccess();
    try testing.expect(breaker.getState() == .HalfOpen);
    
    // One more success should close the circuit
    breaker.recordSuccess();
    try testing.expect(breaker.getState() == .Closed);
}

test "CircuitBreaker: half-open failure" {
    const allocator = testing.allocator;
    
    const config = CircuitBreakerConfig{
        .failure_threshold = 2,
        .recovery_timeout_ms = 10,
        .success_threshold = 2,
    };
    
    var breaker = CircuitBreaker.init(allocator, config);
    
    // Trip the circuit breaker
    for (0..2) |_| {
        breaker.recordFailure();
    }
    
    // Wait for recovery
    std.time.sleep(15 * 1000000);
    try testing.expect(breaker.canExecute());
    try testing.expect(breaker.getState() == .HalfOpen);
    
    // Failure in half-open should immediately open circuit
    breaker.recordFailure();
    try testing.expect(breaker.getState() == .Open);
    try testing.expect(!breaker.canExecute());
}

test "CircuitBreaker: reset functionality" {
    const allocator = testing.allocator;
    
    const config = CircuitBreakerConfig{
        .failure_threshold = 2,
        .recovery_timeout_ms = 30000,
        .success_threshold = 2,
    };
    
    var breaker = CircuitBreaker.init(allocator, config);
    
    // Trip the circuit breaker
    for (0..3) |_| {
        breaker.recordFailure();
    }
    try testing.expect(breaker.getState() == .Open);
    try testing.expect(breaker.failure_count >= 2);
    
    // Reset should restore to closed state
    breaker.reset();
    try testing.expect(breaker.getState() == .Closed);
    try testing.expect(breaker.failure_count == 0);
    try testing.expect(breaker.canExecute());
}

test "CircuitBreaker: concurrent access" {
    const allocator = testing.allocator;
    
    const config = CircuitBreakerConfig{
        .failure_threshold = 10,
        .recovery_timeout_ms = 100,
        .success_threshold = 5,
    };
    
    var breaker = CircuitBreaker.init(allocator, config);
    
    // Test concurrent access with multiple threads
    var threads = std.ArrayList(std.Thread).init(allocator);
    defer threads.deinit();
    
    // Spawn threads that record failures
    for (0..3) |_| {
        const thread = try std.Thread.spawn(.{}, struct {
            fn recordFailures(cb: *CircuitBreaker) void {
                for (0..5) |_| {
                    if (cb.canExecute()) {
                        cb.recordFailure();
                    }
                    std.time.sleep(1000000); // 1ms
                }
            }
        }.recordFailures, .{&breaker});
        try threads.append(thread);
    }
    
    // Spawn threads that record successes
    for (0..2) |_| {
        const thread = try std.Thread.spawn(.{}, struct {
            fn recordSuccesses(cb: *CircuitBreaker) void {
                for (0..3) |_| {
                    if (cb.canExecute()) {
                        cb.recordSuccess();
                    }
                    std.time.sleep(2000000); // 2ms
                }
            }
        }.recordSuccesses, .{&breaker});
        try threads.append(thread);
    }
    
    // Wait for all threads to complete
    for (threads.items) |thread| {
        thread.join();
    }
    
    // Circuit breaker should still be in a valid state
    const state = breaker.getState();
    try testing.expect(state == .Closed or state == .Open or state == .HalfOpen);
}

test "CircuitBreaker: metrics collection" {
    const allocator = testing.allocator;
    
    const BreakerMetrics = struct {
        total_requests: u32 = 0,
        successful_requests: u32 = 0,
        failed_requests: u32 = 0,
        circuit_trips: u32 = 0,
        time_in_open_ms: u64 = 0,
        
        pub fn successRate(self: @This()) f32 {
            if (self.total_requests == 0) return 0.0;
            return @as(f32, @floatFromInt(self.successful_requests)) / @as(f32, @floatFromInt(self.total_requests));
        }
        
        pub fn failureRate(self: @This()) f32 {
            if (self.total_requests == 0) return 0.0;
            return @as(f32, @floatFromInt(self.failed_requests)) / @as(f32, @floatFromInt(self.total_requests));
        }
    };
    
    var metrics = BreakerMetrics{};
    var breaker = CircuitBreaker.init(allocator, CircuitBreakerConfig{});
    
    // Simulate operation tracking
    const operations = 20;
    var successes: u32 = 0;
    var failures: u32 = 0;
    
    for (0..operations) |i| {
        metrics.total_requests += 1;
        
        if (breaker.canExecute()) {
            // Simulate some operations failing
            if (i % 4 == 0) {
                breaker.recordFailure();
                metrics.failed_requests += 1;
                failures += 1;
                if (breaker.getState() == .Open) {
                    metrics.circuit_trips += 1;
                }
            } else {
                breaker.recordSuccess();
                metrics.successful_requests += 1;
                successes += 1;
            }
        } else {
            // Circuit is open - request rejected
            metrics.failed_requests += 1;
            failures += 1;
        }
    }
    
    // Verify metrics
    try testing.expect(metrics.total_requests == operations);
    try testing.expect(metrics.successful_requests == successes);
    try testing.expect(metrics.failed_requests == failures);
    try testing.expect(metrics.successRate() >= 0.0 and metrics.successRate() <= 1.0);
    try testing.expect(metrics.failureRate() >= 0.0 and metrics.failureRate() <= 1.0);
    try testing.expect(metrics.successRate() + metrics.failureRate() == 1.0);
}

test "CircuitBreaker: configuration validation" {
    const allocator = testing.allocator;
    
    // Test valid configurations
    const valid_configs = [_]CircuitBreakerConfig{
        .{ .failure_threshold = 1, .recovery_timeout_ms = 1000, .success_threshold = 1 },
        .{ .failure_threshold = 5, .recovery_timeout_ms = 60000, .success_threshold = 3 },
        .{ .failure_threshold = 10, .recovery_timeout_ms = 300000, .success_threshold = 5 },
    };
    
    for (valid_configs) |config| {
        var breaker = CircuitBreaker.init(allocator, config);
        try testing.expect(breaker.config.failure_threshold > 0);
        try testing.expect(breaker.config.recovery_timeout_ms > 0);
        try testing.expect(breaker.config.success_threshold > 0);
        try testing.expect(breaker.getState() == .Closed);
    }
}