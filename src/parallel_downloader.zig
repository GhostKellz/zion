const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const fs = std.fs;
const downloader = @import("downloader.zig");

/// Configuration for parallel downloads
pub const DownloadConfig = struct {
    max_concurrent: u8 = 4,
    timeout_seconds: u32 = 30,
    retry_count: u8 = 3,
    show_progress: bool = true,
    bandwidth_limit: ?u64 = null, // bytes per second
};

/// Request for downloading a package
pub const DownloadRequest = struct {
    package_ref: []const u8,
    url: ?[]const u8 = null, // Optional pre-resolved URL
};

/// Result of a parallel download operation
pub const ParallelDownloadResult = struct {
    success: bool,
    package_ref: []const u8,
    result: ?downloader.DownloadResult = null,
    error_message: ?[]const u8 = null,
    duration_ms: u64 = 0,

    pub fn deinit(self: *ParallelDownloadResult, allocator: Allocator) void {
        if (self.result) |*res| {
            res.deinit(allocator);
        }
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// Parallel downloader for handling multiple package downloads concurrently
pub const ParallelDownloader = struct {
    allocator: Allocator,
    config: DownloadConfig,
    progress: DownloadProgress,
    mutex: Mutex,

    const Self = @This();

    pub fn init(allocator: Allocator, config: DownloadConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .progress = DownloadProgress.init(),
            .mutex = Mutex{},
        };
    }

    /// Download multiple packages concurrently
    pub fn downloadPackages(
        self: *Self,
        requests: []const DownloadRequest
    ) ![]ParallelDownloadResult {
        if (requests.len == 0) {
            return &[_]ParallelDownloadResult{};
        }

        if (self.config.show_progress) {
            std.debug.print("📦 Starting parallel download of {d} packages...\n", .{requests.len});
            std.debug.print("⚙️  Concurrency: {d} threads\n\n", .{self.config.max_concurrent});
        }

        self.progress.total = requests.len;
        self.progress.start_time = std.time.milliTimestamp();

        // Prepare results array
        var results = try self.allocator.alloc(ParallelDownloadResult, requests.len);
        
        // Initialize all results
        for (results, 0..) |*result, i| {
            result.* = ParallelDownloadResult{
                .success = false,
                .package_ref = requests[i].package_ref,
            };
        }

        // Create work queue
        var work_queue = WorkQueue.init(self.allocator, requests, results);
        defer work_queue.deinit();

        // Create worker threads
        var threads = try self.allocator.alloc(Thread, self.config.max_concurrent);
        defer self.allocator.free(threads);

        // Spawn worker threads
        for (threads, 0..) |*thread, i| {
            const worker_id = @as(u8, @intCast(i));
            thread.* = try Thread.spawn(.{}, workerThread, .{ self, &work_queue, worker_id });
        }

        // Wait for all threads to complete
        for (threads) |thread| {
            thread.join();
        }

        if (self.config.show_progress) {
            self.printFinalSummary(results);
        }

        return results;
    }

    /// Worker thread function
    fn workerThread(self: *Self, work_queue: *WorkQueue, worker_id: u8) void {
        _ = worker_id; // Could be used for logging
        
        while (work_queue.getNextTask()) |task| {
            const start_time = std.time.milliTimestamp();
            
            // Perform the download
            const result = self.downloadSinglePackage(task.request) catch |err| {
                task.result.error_message = std.fmt.allocPrint(
                    self.allocator, 
                    "Download failed: {}", 
                    .{err}
                ) catch "Unknown error";
                task.result.success = false;
                continue;
            };

            // Update result
            task.result.success = true;
            task.result.result = result;
            task.result.duration_ms = @as(u64, @intCast(std.time.milliTimestamp() - start_time));

            // Update progress
            self.updateProgress();
        }
    }

    /// Download a single package with retries
    fn downloadSinglePackage(self: *Self, request: DownloadRequest) !downloader.DownloadResult {
        var last_error: ?anyerror = null;
        
        for (0..self.config.retry_count) |attempt| {
            if (attempt > 0) {
                if (self.config.show_progress) {
                    std.debug.print("🔄 Retry {d}/{d} for {s}\n", .{ attempt, self.config.retry_count - 1, request.package_ref });
                }
                
                // Exponential backoff: 1s, 2s, 4s...
                const delay_ms = @as(u64, 1000) << @as(u6, @intCast(attempt - 1));
                std.time.sleep(delay_ms * std.time.ns_per_ms);
            }

            const result = downloader.downloadAndHashPackage(self.allocator, request.package_ref) catch |err| {
                last_error = err;
                continue;
            };

            return result;
        }

        return last_error orelse error.DownloadFailed;
    }

    /// Update download progress (thread-safe)
    fn updateProgress(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.progress.completed += 1;
        
        if (self.config.show_progress) {
            const percent = (self.progress.completed * 100) / self.progress.total;
            const elapsed = std.time.milliTimestamp() - self.progress.start_time;
            const rate = if (elapsed > 0) (self.progress.completed * 1000) / @as(usize, @intCast(elapsed)) else 0;
            
            std.debug.print("\r📊 Progress: {d}/{d} ({d}%) - Rate: {d}/s", .{
                self.progress.completed,
                self.progress.total,
                percent,
                rate
            });
            
            if (self.progress.completed == self.progress.total) {
                std.debug.print("\n");
            }
        }
    }

    /// Print final download summary
    fn printFinalSummary(self: *Self, results: []const ParallelDownloadResult) void {
        const total_time = std.time.milliTimestamp() - self.progress.start_time;
        var successful: usize = 0;
        var failed: usize = 0;
        var total_size: u64 = 0;

        for (results) |result| {
            if (result.success) {
                successful += 1;
                // Could add size tracking here
            } else {
                failed += 1;
            }
        }

        std.debug.print("\n📋 Download Summary:\n");
        std.debug.print("   ✅ Successful: {d}\n", .{successful});
        if (failed > 0) {
            std.debug.print("   ❌ Failed: {d}\n", .{failed});
        }
        std.debug.print("   ⏱️  Total time: {d}ms\n", .{total_time});
        std.debug.print("   🚀 Average: {d}ms per package\n", .{if (results.len > 0) total_time / results.len else 0});
        
        if (failed > 0) {
            std.debug.print("\n⚠️  Failed downloads:\n");
            for (results) |result| {
                if (!result.success) {
                    const error_msg = result.error_message orelse "Unknown error";
                    std.debug.print("   • {s}: {s}\n", .{ result.package_ref, error_msg });
                }
            }
        }
    }
};

/// Work queue for distributing download tasks among threads
const WorkQueue = struct {
    allocator: Allocator,
    requests: []const DownloadRequest,
    results: []ParallelDownloadResult,
    next_index: usize,
    mutex: Mutex,

    const Task = struct {
        request: DownloadRequest,
        result: *ParallelDownloadResult,
    };

    pub fn init(
        allocator: Allocator,
        requests: []const DownloadRequest,
        results: []ParallelDownloadResult
    ) WorkQueue {
        return WorkQueue{
            .allocator = allocator,
            .requests = requests,
            .results = results,
            .next_index = 0,
            .mutex = Mutex{},
        };
    }

    pub fn deinit(self: *WorkQueue) void {
        _ = self;
        // Nothing to clean up
    }

    pub fn getNextTask(self: *WorkQueue) ?Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.next_index >= self.requests.len) {
            return null;
        }

        const index = self.next_index;
        self.next_index += 1;

        return Task{
            .request = self.requests[index],
            .result = &self.results[index],
        };
    }
};

/// Progress tracking for downloads
const DownloadProgress = struct {
    total: usize = 0,
    completed: usize = 0,
    start_time: i64 = 0,

    pub fn init() DownloadProgress {
        return DownloadProgress{};
    }
};

/// Convenience function for downloading multiple packages
pub fn downloadPackagesConcurrently(
    allocator: Allocator,
    package_refs: []const []const u8,
    config: DownloadConfig
) ![]ParallelDownloadResult {
    var downloader_instance = ParallelDownloader.init(allocator, config);
    
    // Convert package refs to download requests
    var requests = try allocator.alloc(DownloadRequest, package_refs.len);
    defer allocator.free(requests);
    
    for (package_refs, 0..) |package_ref, i| {
        requests[i] = DownloadRequest{ .package_ref = package_ref };
    }
    
    return downloader_instance.downloadPackages(requests);
}

/// Enhanced download function with progress and concurrency
pub fn downloadWithProgress(
    allocator: Allocator,
    package_refs: []const []const u8
) ![]ParallelDownloadResult {
    const config = DownloadConfig{
        .max_concurrent = 4,
        .show_progress = true,
        .retry_count = 3,
        .timeout_seconds = 30,
    };
    
    return downloadPackagesConcurrently(allocator, package_refs, config);
}