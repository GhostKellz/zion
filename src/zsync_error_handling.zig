const std = @import("std");
const zsync = @import("zsync");

const Allocator = std.mem.Allocator;

/// Enhanced error handling using zsync patterns
pub const ZsyncErrorHandler = struct {
    allocator: Allocator,
    runtime: *zsync.Runtime,
    
    const Self = @This();
    
    /// Enhanced error types for better diagnostics
    pub const ZionError = error{
        NetworkTimeout,
        RegistryUnavailable,
        PackageNotFound,
        DependencyConflict,
        DownloadFailed,
        ExtractionFailed,
        PermissionDenied,
        DiskSpaceFull,
        CorruptedPackage,
        InvalidConfiguration,
        OperationCancelled,
        ConcurrencyLimit,
    } || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.WriteError;
    
    /// Error context for better debugging
    pub const ErrorContext = struct {
        operation: []const u8,
        package_name: ?[]const u8 = null,
        registry: ?[]const u8 = null,
        file_path: ?[]const u8 = null,
        error_code: ZionError,
        timestamp: i64,
        retry_count: u32 = 0,
        user_message: []const u8,
        technical_details: []const u8,
    };
    
    /// Retry configuration
    pub const RetryConfig = struct {
        max_attempts: u32 = 3,
        base_delay_ms: u64 = 1000,
        max_delay_ms: u64 = 10000,
        exponential_backoff: bool = true,
        retryable_errors: []const ZionError,
    };
    
    pub fn init(allocator: Allocator, runtime: *zsync.Runtime) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .runtime = runtime,
        };
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
    
    /// Execute operation with automatic retry and enhanced error reporting
    pub fn executeWithRetry(
        self: *Self,
        comptime T: type,
        operation: fn() ZionError!T,
        config: RetryConfig,
        context: ErrorContext,
    ) !T {
        var attempt: u32 = 0;
        var last_error: ?ZionError = null;
        
        while (attempt < config.max_attempts) {
            const result = operation() catch |err| {
                last_error = err;
                
                // Check if error is retryable
                const is_retryable = for (config.retryable_errors) |retryable_err| {
                    if (retryable_err == err) break true;
                } else false;
                
                if (!is_retryable or attempt + 1 >= config.max_attempts) {
                    // Log final failure
                    try self.logError(ErrorContext{
                        .operation = context.operation,
                        .package_name = context.package_name,
                        .registry = context.registry,
                        .file_path = context.file_path,
                        .error_code = err,
                        .timestamp = std.time.milliTimestamp(),
                        .retry_count = attempt,
                        .user_message = try self.getUserMessage(err, context),
                        .technical_details = try self.getTechnicalDetails(err, context),
                    });
                    return err;
                }
                
                // Calculate delay with exponential backoff
                const delay_ms = if (config.exponential_backoff)
                    @min(config.base_delay_ms * (@as(u64, 1) << attempt), config.max_delay_ms)
                else
                    config.base_delay_ms;
                
                std.debug.print("⚠️  Operation failed (attempt {d}/{d}), retrying in {d}ms...\n", .{
                    attempt + 1, config.max_attempts, delay_ms
                });
                
                // Wait before retry using zsync's sleep
                const DelayTask = struct {
                    delay: u64,
                    fn run(task: @This(), io: zsync.Io) !void {
                        try io.sleep(@intCast(task.delay));
                    }
                };
                
                const delay_future = try zsync.spawn(self.runtime, DelayTask{
                    .delay = delay_ms,
                }, DelayTask.run);
                
                try delay_future.wait();
                attempt += 1;
                continue;
            };
            
            // Operation succeeded
            if (attempt > 0) {
                std.debug.print("✅ Operation succeeded after {d} retries\n", .{attempt});
            }
            return result;
        }
        
        // Should not reach here, but handle just in case
        return last_error orelse ZionError.OperationCancelled;
    }
    
    /// Execute multiple operations with error aggregation
    pub fn executeParallelWithErrorHandling(
        self: *Self,
        comptime T: type,
        operations: []const fn() ZionError!T,
        contexts: []const ErrorContext,
    ) ![]Result(T) {
        if (operations.len != contexts.len) {
            return error.InvalidConfiguration;
        }
        
        var futures = try self.allocator.alloc(*zsync.Future(Result(T)), operations.len);
        defer self.allocator.free(futures);
        
        for (operations, contexts, 0..) |operation, context, i| {
            const Task = struct {
                handler: *ZsyncErrorHandler,
                op: fn() ZionError!T,
                ctx: ErrorContext,
                
                fn run(task: @This(), io: zsync.Io) !Result(T) {
                    _ = io;
                    const result = task.op() catch |err| {
                        // Log the error
                        task.handler.logError(ErrorContext{
                            .operation = task.ctx.operation,
                            .package_name = task.ctx.package_name,
                            .registry = task.ctx.registry,
                            .file_path = task.ctx.file_path,
                            .error_code = err,
                            .timestamp = std.time.milliTimestamp(),
                            .retry_count = 0,
                            .user_message = try task.handler.getUserMessage(err, task.ctx),
                            .technical_details = try task.handler.getTechnicalDetails(err, task.ctx),
                        }) catch {};
                        
                        return Result(T){ .err = err };
                    };
                    
                    return Result(T){ .ok = result };
                }
            };
            
            futures[i] = try zsync.spawn(self.runtime, Task{
                .handler = self,
                .op = operation,
                .ctx = context,
            }, Task.run);
        }
        
        // Wait for all operations
        const all_results = try zsync.all(self.runtime, futures);
        defer all_results.deinit();
        
        var results = try self.allocator.alloc(Result(T), all_results.items.len);
        for (all_results.items, 0..) |result, i| {
            results[i] = result;
        }
        
        return results;
    }
    
    /// Circuit breaker pattern for failing services
    pub const CircuitBreaker = struct {
        failure_threshold: u32,
        timeout_ms: u64,
        failure_count: u32,
        last_failure_time: i64,
        state: State,
        
        const State = enum { closed, open, half_open };
        
        pub fn init(failure_threshold: u32, timeout_ms: u64) CircuitBreaker {
            return .{
                .failure_threshold = failure_threshold,
                .timeout_ms = timeout_ms,
                .failure_count = 0,
                .last_failure_time = 0,
                .state = .closed,
            };
        }
        
        pub fn canExecute(self: *CircuitBreaker) bool {
            const now = std.time.milliTimestamp();
            
            switch (self.state) {
                .closed => return true,
                .open => {
                    if (now - self.last_failure_time > @as(i64, @intCast(self.timeout_ms))) {
                        self.state = .half_open;
                        return true;
                    }
                    return false;
                },
                .half_open => return true,
            }
        }
        
        pub fn recordSuccess(self: *CircuitBreaker) void {
            self.failure_count = 0;
            self.state = .closed;
        }
        
        pub fn recordFailure(self: *CircuitBreaker) void {
            self.failure_count += 1;
            self.last_failure_time = std.time.milliTimestamp();
            
            if (self.failure_count >= self.failure_threshold) {
                self.state = .open;
            }
        }
    };
    
    fn logError(self: *Self, error_context: ErrorContext) !void {
        _ = self;
        const timestamp = std.time.milliTimestamp();
        
        std.debug.print("\n🚨 ERROR: {s}\n", .{error_context.user_message});
        std.debug.print("   Operation: {s}\n", .{error_context.operation});
        
        if (error_context.package_name) |pkg| {
            std.debug.print("   Package: {s}\n", .{pkg});
        }
        
        if (error_context.registry) |reg| {
            std.debug.print("   Registry: {s}\n", .{reg});
        }
        
        if (error_context.file_path) |path| {
            std.debug.print("   File: {s}\n", .{path});
        }
        
        if (error_context.retry_count > 0) {
            std.debug.print("   Attempts: {d}\n", .{error_context.retry_count + 1});
        }
        
        std.debug.print("   Time: {d}\n", .{timestamp});
        std.debug.print("   Details: {s}\n\n", .{error_context.technical_details});
    }
    
    fn getUserMessage(self: *Self, err: ZionError, context: ErrorContext) ![]const u8 {
        _ = context;
        return switch (err) {
            ZionError.NetworkTimeout => try self.allocator.dupe(u8, "Network request timed out. Check your internet connection."),
            ZionError.RegistryUnavailable => try self.allocator.dupe(u8, "Package registry is currently unavailable."),
            ZionError.PackageNotFound => try self.allocator.dupe(u8, "The requested package could not be found."),
            ZionError.DependencyConflict => try self.allocator.dupe(u8, "Package has conflicting dependencies."),
            ZionError.DownloadFailed => try self.allocator.dupe(u8, "Package download failed."),
            ZionError.ExtractionFailed => try self.allocator.dupe(u8, "Failed to extract package contents."),
            ZionError.PermissionDenied => try self.allocator.dupe(u8, "Permission denied. Try running with elevated privileges."),
            ZionError.DiskSpaceFull => try self.allocator.dupe(u8, "Insufficient disk space to complete operation."),
            ZionError.CorruptedPackage => try self.allocator.dupe(u8, "Package file appears to be corrupted."),
            ZionError.InvalidConfiguration => try self.allocator.dupe(u8, "Configuration file is invalid or corrupted."),
            ZionError.OperationCancelled => try self.allocator.dupe(u8, "Operation was cancelled by user."),
            ZionError.ConcurrencyLimit => try self.allocator.dupe(u8, "Too many concurrent operations. Try again later."),
            else => try std.fmt.allocPrint(self.allocator, "Unknown error: {}", .{err}),
        };
    }
    
    fn getTechnicalDetails(self: *Self, err: ZionError, context: ErrorContext) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "Error code: {}, Operation: {s}, Timestamp: {d}", .{
            err, context.operation, context.timestamp
        });
    }
};

/// Result type for parallel operations
pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ZsyncErrorHandler.ZionError,
    };
}

/// Default retry configurations for common operations
pub const retry_configs = struct {
    pub const network_operations = ZsyncErrorHandler.RetryConfig{
        .max_attempts = 3,
        .base_delay_ms = 1000,
        .exponential_backoff = true,
        .retryable_errors = &[_]ZsyncErrorHandler.ZionError{
            .NetworkTimeout,
            .RegistryUnavailable,
        },
    };
    
    pub const file_operations = ZsyncErrorHandler.RetryConfig{
        .max_attempts = 2,
        .base_delay_ms = 500,
        .exponential_backoff = false,
        .retryable_errors = &[_]ZsyncErrorHandler.ZionError{
            .PermissionDenied,
        },
    };
    
    pub const download_operations = ZsyncErrorHandler.RetryConfig{
        .max_attempts = 5,
        .base_delay_ms = 2000,
        .exponential_backoff = true,
        .retryable_errors = &[_]ZsyncErrorHandler.ZionError{
            .DownloadFailed,
            .NetworkTimeout,
        },
    };
};