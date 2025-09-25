const std = @import("std");
const zsync = @import("zsync");

const Allocator = std.mem.Allocator;

/// Cancellable operations with cooperative cancellation support
pub const CancellableOps = struct {
    allocator: Allocator,
    runtime: *zsync.Runtime,
    cancellation_token: *CancellationToken,
    
    const Self = @This();
    
    /// Thread-safe cancellation token
    pub const CancellationToken = struct {
        cancelled: std.atomic.Value(bool),
        
        pub fn init(allocator: Allocator) !*CancellationToken {
            const token = try allocator.create(CancellationToken);
            token.* = .{
                .cancelled = std.atomic.Value(bool).init(false),
            };
            return token;
        }
        
        pub fn deinit(self: *CancellationToken, allocator: Allocator) void {
            allocator.destroy(self);
        }
        
        pub fn cancel(self: *CancellationToken) void {
            self.cancelled.store(true, .seq_cst);
        }
        
        pub fn isCancelled(self: *CancellationToken) bool {
            return self.cancelled.load(.seq_cst);
        }
    };
    
    pub fn init(allocator: Allocator, runtime: *zsync.Runtime) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .runtime = runtime,
            .cancellation_token = try CancellationToken.init(allocator),
        };
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.cancellation_token.deinit(self.allocator);
        self.allocator.destroy(self);
    }
    
    /// Install signal handler for Ctrl+C cancellation
    pub fn installSignalHandler(self: *Self) !void {
        const handler = struct {
            var token: ?*CancellationToken = null;
            
            fn handleSignal(sig: c_int) callconv(.c) void {
                _ = sig;
                if (token) |t| {
                    t.cancel();
                    std.debug.print("\n🛑 Operation cancelled by user\n", .{});
                }
            }
        };
        
        handler.token = self.cancellation_token;
        
        // Signal handling would be implemented platform-specifically
        // For now, cancellation is manual via the cancellation token
    }
    
    /// Long-running download with cancellation support
    pub fn cancellableDownload(self: *Self, url: []const u8, dest_path: []const u8) !void {
        const DownloadTask = struct {
            ops: *CancellableOps,
            url: []const u8,
            dest_path: []const u8,
            
            fn run(task: @This(), io: zsync.Io) !void {
                // Check if already cancelled
                if (task.ops.cancellation_token.isCancelled()) {
                    return error.OperationCancelled;
                }
                
                // Mock download implementation
                const file = try std.fs.cwd().createFile(task.dest_path, .{});
                defer file.close();
                
                const total_size: usize = 100 * 1024 * 1024; // 100MB mock download
                const chunk_size: usize = 1024 * 1024; // 1MB chunks
                var downloaded: usize = 0;
                
                std.debug.print("📥 Downloading {s}...\n", .{task.url});
                
                while (downloaded < total_size) {
                    // Check for cancellation at each chunk
                    if (task.ops.cancellation_token.isCancelled()) {
                        std.debug.print("⚠️  Download cancelled at {d:.1}%\n", .{
                            @as(f64, @floatFromInt(downloaded)) / @as(f64, @floatFromInt(total_size)) * 100.0
                        });
                        return error.OperationCancelled;
                    }
                    
                    // Simulate downloading a chunk
                    const chunk = @min(chunk_size, total_size - downloaded);
                    const mock_data = try task.ops.allocator.alloc(u8, chunk);
                    defer task.ops.allocator.free(mock_data);
                    
                    @memset(mock_data, 0);
                    try file.writeAll(mock_data);
                    downloaded += chunk;
                    
                    // Progress update
                    if (downloaded % (10 * 1024 * 1024) == 0) {
                        std.debug.print("  Progress: {d:.1}%\n", .{
                            @as(f64, @floatFromInt(downloaded)) / @as(f64, @floatFromInt(total_size)) * 100.0
                        });
                    }
                    
                    // Cooperative yield
                    try io.yield();
                    
                    // Simulate network delay
                    try io.sleep(10);
                }
                
                std.debug.print("✅ Download completed: {s}\n", .{task.dest_path});
            }
        };
        
        const future = try zsync.spawn(self.runtime, DownloadTask{
            .ops = self,
            .url = url,
            .dest_path = dest_path,
        }, DownloadTask.run);
        
        try future.wait();
    }
    
    /// Batch operation with cancellation support
    pub fn cancellableBatch(self: *Self, items: []const []const u8) !void {
        std.debug.print("🔄 Processing {d} items...\n", .{items.len});
        
        for (items, 0..) |item, i| {
            // Check cancellation before each item
            if (self.cancellation_token.isCancelled()) {
                std.debug.print("⚠️  Batch cancelled at item {d}/{d}\n", .{i, items.len});
                return error.OperationCancelled;
            }
            
            // Process item
            std.debug.print("  Processing: {s}\n", .{item});
            
            // Simulate work
            std.time.sleep(100 * std.time.ns_per_ms);
        }
        
        std.debug.print("✅ Batch completed successfully\n", .{});
    }
    
    /// Search operation with early termination on cancellation
    pub fn cancellableSearch(self: *Self, query: []const u8, max_results: usize) ![][]const u8 {
    var results = std.ArrayList([]const u8).empty;
    defer results.deinit(self.allocator);
        
        std.debug.print("🔍 Searching for: {s}\n", .{query});
        
        var found: usize = 0;
        while (found < max_results) {
            // Check for cancellation
            if (self.cancellation_token.isCancelled()) {
                std.debug.print("⚠️  Search cancelled after {d} results\n", .{found});
                break;
            }
            
            // Simulate finding a result
            const result = try std.fmt.allocPrint(self.allocator, "Result {d} for '{s}'", .{found + 1, query});
            try results.append(self.allocator, result);
            found += 1;
            
            // Simulate search delay
            std.time.sleep(50 * std.time.ns_per_ms);
        }
        
    return try results.toOwnedSlice(self.allocator);
    }
    
    /// Run operation with automatic cancellation on timeout
    pub fn withTimeout(self: *Self, comptime T: type, timeout_ms: u64, operation: fn(*Self) T) !T {
        const TimeoutTask = struct {
            ops: *CancellableOps,
            timeout: u64,
            
            fn run(task: @This(), io: zsync.Io) !void {
                try io.sleep(@intCast(task.timeout));
                task.ops.cancellation_token.cancel();
            }
        };
        
        // Start timeout timer
        const timeout_future = try zsync.spawn(self.runtime, TimeoutTask{
            .ops = self,
            .timeout = timeout_ms,
        }, TimeoutTask.run);
        defer timeout_future.cancel();
        
        // Run the operation
        const result = try operation(self);
        
        // Cancel timeout if operation completed
        timeout_future.cancel();
        
        return result;
    }
};