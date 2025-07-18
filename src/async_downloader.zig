const std = @import("std");
const zsync = @import("zsync");
const http_client = @import("http_client.zig");
const Allocator = std.mem.Allocator;
const fs = std.fs;

/// Async downloader using zsync for high-performance concurrent downloads
pub const AsyncDownloader = struct {
    allocator: Allocator,
    runtime: *zsync.Runtime,
    http_client: *http_client.HttpClient,
    config: DownloadConfig,
    stats: DownloadStats,
    cancellation_token: CancellationToken,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, runtime: *zsync.Runtime, client: *http_client.HttpClient, config: DownloadConfig) !*Self {
        const downloader = try allocator.create(Self);
        downloader.* = .{
            .allocator = allocator,
            .runtime = runtime,
            .http_client = client,
            .config = config,
            .stats = DownloadStats.init(),
            .cancellation_token = CancellationToken.init(),
        };
        
        return downloader;
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
    
    /// Download multiple packages concurrently with zsync
    pub fn downloadPackages(self: *Self, requests: []const DownloadRequest) ![]DownloadResult {
        if (requests.len == 0) return &[_]DownloadResult{};
        
        if (self.config.show_progress) {
            std.log.info("🚀 Starting async download of {} packages with {} concurrency", .{ requests.len, self.config.max_concurrent });
        }
        
        self.stats.reset();
        self.stats.total_packages = requests.len;
        self.stats.start_time = std.time.milliTimestamp();
        
        // Create download futures
        var futures = std.ArrayList(*zsync.Future(SingleDownloadResult)).init(self.allocator);
        defer {
            for (futures.items) |future| future.deinit();
            futures.deinit();
        }
        
        // Create semaphore for concurrency control
        var semaphore = Semaphore.init(self.config.max_concurrent);
        
        // Start all downloads
        for (requests) |request| {
            if (self.cancellation_token.is_cancelled()) break;
            
            const future = try self.downloadSingleAsync(request, &semaphore);
            try futures.append(future);
        }
        
        // Collect results
        var results = std.ArrayList(DownloadResult).init(self.allocator);
        defer results.deinit();
        
        for (futures.items) |future| {
            if (self.cancellation_token.is_cancelled()) break;
            
            const single_result = try future.await();
            
            // Update stats
            self.stats.mutex.lock();
            if (single_result.success) {
                self.stats.successful += 1;
                self.stats.total_bytes += single_result.bytes_downloaded;
            } else {
                self.stats.failed += 1;
            }
            self.stats.completed += 1;
            self.stats.mutex.unlock();
            
            // Convert to public result format
            const result = DownloadResult{
                .success = single_result.success,
                .package_ref = try self.allocator.dupe(u8, single_result.package_ref),
                .url = if (single_result.url) |url| try self.allocator.dupe(u8, url) else null,
                .hash = if (single_result.hash) |hash| try self.allocator.dupe(u8, hash) else null,
                .cache_path = if (single_result.cache_path) |path| try self.allocator.dupe(u8, path) else null,
                .error_message = if (single_result.error_message) |msg| try self.allocator.dupe(u8, msg) else null,
                .duration_ms = single_result.duration_ms,
                .bytes_downloaded = single_result.bytes_downloaded,
            };
            
            try results.append(result);
            
            // Show progress
            if (self.config.show_progress) {
                self.showProgress();
            }
        }
        
        if (self.config.show_progress) {
            self.showFinalStats();
        }
        
        return results.toOwnedSlice();
    }
    
    /// Download a single package with retry logic and caching
    fn downloadSingleAsync(self: *Self, request: DownloadRequest, semaphore: *Semaphore) !*zsync.Future(SingleDownloadResult) {
        const Task = struct {
            downloader: *AsyncDownloader,
            request: DownloadRequest,
            semaphore: *Semaphore,
            
            fn run(task: @This()) SingleDownloadResult {
                const start_time = std.time.milliTimestamp();
                
                // Acquire semaphore for concurrency control
                task.semaphore.acquire();
                defer task.semaphore.release();
                
                const result = task.downloader.downloadSingleSync(task.request) catch |err| {
                    return SingleDownloadResult{
                        .success = false,
                        .package_ref = task.request.package_ref,
                        .url = task.request.url,
                        .hash = null,
                        .cache_path = null,
                        .error_message = @errorName(err),
                        .duration_ms = @intCast(std.time.milliTimestamp() - start_time),
                        .bytes_downloaded = 0,
                    };
                };
                
                return result;
            }
        };
        
        const task = Task{
            .downloader = self,
            .request = request,
            .semaphore = semaphore,
        };
        
        return try zsync.spawn(self.runtime, task, Task.run);
    }
    
    /// Synchronous download implementation with retry logic
    fn downloadSingleSync(self: *Self, request: DownloadRequest) !SingleDownloadResult {
        const start_time = std.time.milliTimestamp();
        
        // Check if already cached
        const cache_path = try self.generateCachePath(request.package_ref);
        defer self.allocator.free(cache_path);
        
        var bytes_downloaded: u64 = 0;
        
        // Check cache first
        if (self.checkCache(cache_path)) |cached_size| {
            bytes_downloaded = cached_size;
            
            // Calculate hash of cached file
            const hash = try self.calculateFileHash(cache_path);
            
            return SingleDownloadResult{
                .success = true,
                .package_ref = request.package_ref,
                .url = request.url,
                .hash = hash,
                .cache_path = cache_path,
                .error_message = null,
                .duration_ms = @intCast(std.time.milliTimestamp() - start_time),
                .bytes_downloaded = bytes_downloaded,
            };
        }
        
        // Download with retry logic
        const url = request.url orelse return error.NoUrlProvided;
        var last_error: ?[]const u8 = null;
        
        for (0..self.config.retry_count) |attempt| {
            if (self.cancellation_token.is_cancelled()) return error.Cancelled;
            
            if (attempt > 0) {
                const delay_ms = @as(u64, 1000) << @intCast(attempt - 1); // Exponential backoff
                std.time.sleep(delay_ms * 1000000); // Convert to nanoseconds
            }
            
            const download_result = self.downloadFromUrl(url, cache_path) catch |err| {
                last_error = @errorName(err);
                continue;
            };
            
            bytes_downloaded = download_result.bytes_downloaded;
            
            // Calculate hash
            const hash = try self.calculateFileHash(cache_path);
            
            return SingleDownloadResult{
                .success = true,
                .package_ref = request.package_ref,
                .url = url,
                .hash = hash,
                .cache_path = cache_path,
                .error_message = null,
                .duration_ms = @intCast(std.time.milliTimestamp() - start_time),
                .bytes_downloaded = bytes_downloaded,
            };
        }
        
        return SingleDownloadResult{
            .success = false,
            .package_ref = request.package_ref,
            .url = url,
            .hash = null,
            .cache_path = null,
            .error_message = last_error orelse "Unknown error",
            .duration_ms = @intCast(std.time.milliTimestamp() - start_time),
            .bytes_downloaded = bytes_downloaded,
        };
    }
    
    /// Download from URL using HTTP client
    fn downloadFromUrl(self: *Self, url: []const u8, output_path: []const u8) !DownloadInfo {
        // Ensure output directory exists
        if (fs.path.dirname(output_path)) |dir| {
            try fs.cwd().makePath(dir);
        }
        
        const response = try self.http_client.get(url);
        defer response.deinit(self.allocator);
        
        if (!response.isSuccess()) {
            return error.HttpError;
        }
        
        const body = response.body orelse return error.EmptyResponse;
        
        // Write to file
        const file = try fs.cwd().createFile(output_path, .{});
        defer file.close();
        
        try file.writeAll(body);
        
        return DownloadInfo{
            .bytes_downloaded = body.len,
        };
    }
    
    /// Generate cache path for package
    fn generateCachePath(self: *Self, package_ref: []const u8) ![]const u8 {
        // Ensure cache directory exists
        try fs.cwd().makePath(".zion/cache");
        
        // Sanitize package name
        const sanitized = try self.sanitizePackageName(package_ref);
        defer self.allocator.free(sanitized);
        
        return try std.fmt.allocPrint(self.allocator, ".zion/cache/{s}.tar.gz", .{sanitized});
    }
    
    /// Check if file exists in cache and return size
    fn checkCache(self: *Self, cache_path: []const u8) ?u64 {
        _ = self;
        const file = fs.cwd().openFile(cache_path, .{}) catch return null;
        defer file.close();
        
        const size = file.getEndPos() catch return null;
        return if (size > 0) size else null;
    }
    
    /// Calculate SHA256 hash of file
    fn calculateFileHash(self: *Self, file_path: []const u8) ![]const u8 {
        const file = try fs.cwd().openFile(file_path, .{});
        defer file.close();
        
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        
        const buffer_size = 64 * 1024; // 64KB chunks
        var buffer = try self.allocator.alloc(u8, buffer_size);
        defer self.allocator.free(buffer);
        
        while (true) {
            const bytes_read = try file.readAll(buffer);
            if (bytes_read == 0) break;
            
            hasher.update(buffer[0..bytes_read]);
        }
        
        var hash_bytes: [32]u8 = undefined;
        hasher.final(&hash_bytes);
        
        // Convert to hex string
        var hash_str = try self.allocator.alloc(u8, 64);
        _ = try std.fmt.bufPrint(hash_str, "{}", .{std.fmt.fmtSliceHexLower(&hash_bytes)});
        
        return hash_str;
    }
    
    /// Sanitize package name for filename
    fn sanitizePackageName(self: *Self, package_name: []const u8) ![]const u8 {
        var result = try self.allocator.alloc(u8, package_name.len);
        for (package_name, 0..) |char, i| {
            result[i] = switch (char) {
                '/', '\\', ':', '*', '?', '"', '<', '>', '|' => '_',
                else => char,
            };
        }
        return result;
    }
    
    /// Show download progress
    fn showProgress(self: *Self) void {
        self.stats.mutex.lock();
        defer self.stats.mutex.unlock();
        
        const elapsed = std.time.milliTimestamp() - self.stats.start_time;
        const percent = if (self.stats.total_packages > 0) 
            (self.stats.completed * 100) / self.stats.total_packages 
        else 0;
        
        const rate = if (elapsed > 0) 
            (self.stats.completed * 1000) / @as(u64, @intCast(elapsed))
        else 0;
        
        std.log.info("📊 Progress: {}/{} ({}%) - {}/s - {} MB total", .{
            self.stats.completed,
            self.stats.total_packages,
            percent,
            rate,
            self.stats.total_bytes / (1024 * 1024),
        });
    }
    
    /// Show final download statistics
    fn showFinalStats(self: *Self) void {
        self.stats.mutex.lock();
        defer self.stats.mutex.unlock();
        
        const total_time = std.time.milliTimestamp() - self.stats.start_time;
        const total_mb = @as(f64, @floatFromInt(self.stats.total_bytes)) / (1024.0 * 1024.0);
        const speed_mbps = if (total_time > 0) 
            total_mb / (@as(f64, @floatFromInt(total_time)) / 1000.0)
        else 0.0;
        
        std.log.info("🎉 Download complete!");
        std.log.info("   ✅ Successful: {}", .{self.stats.successful});
        std.log.info("   ❌ Failed: {}", .{self.stats.failed});
        std.log.info("   📦 Total size: {d:.1} MB", .{total_mb});
        std.log.info("   ⏱️  Total time: {}ms", .{total_time});
        std.log.info("   🚀 Average speed: {d:.1} MB/s", .{speed_mbps});
    }
    
    /// Cancel all ongoing downloads
    pub fn cancel(self: *Self) void {
        self.cancellation_token.cancel();
    }
};

/// Configuration for async downloader
pub const DownloadConfig = struct {
    max_concurrent: u32 = 4,
    retry_count: u32 = 3,
    timeout_seconds: u32 = 30,
    show_progress: bool = true,
    cache_enabled: bool = true,
};

/// Request for downloading a package
pub const DownloadRequest = struct {
    package_ref: []const u8,
    url: ?[]const u8 = null,
};

/// Result of a download operation
pub const DownloadResult = struct {
    success: bool,
    package_ref: []const u8,
    url: ?[]const u8,
    hash: ?[]const u8,
    cache_path: ?[]const u8,
    error_message: ?[]const u8,
    duration_ms: u64,
    bytes_downloaded: u64,
    
    pub fn deinit(self: *DownloadResult, allocator: Allocator) void {
        allocator.free(self.package_ref);
        if (self.url) |url| allocator.free(url);
        if (self.hash) |hash| allocator.free(hash);
        if (self.cache_path) |path| allocator.free(path);
        if (self.error_message) |msg| allocator.free(msg);
    }
};

/// Internal result structure for async operations
const SingleDownloadResult = struct {
    success: bool,
    package_ref: []const u8,
    url: ?[]const u8,
    hash: ?[]const u8,
    cache_path: ?[]const u8,
    error_message: ?[]const u8,
    duration_ms: u64,
    bytes_downloaded: u64,
};

/// Download statistics
const DownloadStats = struct {
    total_packages: usize,
    completed: usize,
    successful: usize,
    failed: usize,
    total_bytes: u64,
    start_time: i64,
    mutex: std.Thread.Mutex,
    
    fn init() DownloadStats {
        return DownloadStats{
            .total_packages = 0,
            .completed = 0,
            .successful = 0,
            .failed = 0,
            .total_bytes = 0,
            .start_time = 0,
            .mutex = std.Thread.Mutex{},
        };
    }
    
    fn reset(self: *DownloadStats) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.total_packages = 0;
        self.completed = 0;
        self.successful = 0;
        self.failed = 0;
        self.total_bytes = 0;
        self.start_time = 0;
    }
};

/// Semaphore for controlling concurrency
const Semaphore = struct {
    count: u32,
    max_count: u32,
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    
    fn init(max_count: u32) Semaphore {
        return Semaphore{
            .count = max_count,
            .max_count = max_count,
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
        };
    }
    
    fn acquire(self: *Semaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        while (self.count == 0) {
            self.condition.wait(&self.mutex);
        }
        
        self.count -= 1;
    }
    
    fn release(self: *Semaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.count += 1;
        self.condition.signal();
    }
};

/// Cancellation token for download operations
const CancellationToken = struct {
    cancelled: bool,
    mutex: std.Thread.Mutex,
    
    fn init() CancellationToken {
        return CancellationToken{
            .cancelled = false,
            .mutex = std.Thread.Mutex{},
        };
    }
    
    fn cancel(self: *CancellationToken) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.cancelled = true;
    }
    
    fn is_cancelled(self: *CancellationToken) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.cancelled;
    }
};

/// Information about a download
const DownloadInfo = struct {
    bytes_downloaded: u64,
};

/// Convenience function for downloading packages with default config
pub fn downloadPackagesAsync(
    allocator: Allocator,
    runtime: *zsync.Runtime,
    http_client: *http_client.HttpClient,
    requests: []const DownloadRequest,
) ![]DownloadResult {
    const config = DownloadConfig{};
    var downloader = try AsyncDownloader.init(allocator, runtime, http_client, config);
    defer downloader.deinit();
    
    return try downloader.downloadPackages(requests);
}

/// Convenience function for downloading a single package
pub fn downloadSingleAsync(
    allocator: Allocator,
    runtime: *zsync.Runtime,
    http_client: *http_client.HttpClient,
    package_ref: []const u8,
    url: []const u8,
) !DownloadResult {
    const request = DownloadRequest{
        .package_ref = package_ref,
        .url = url,
    };
    
    const results = try downloadPackagesAsync(allocator, runtime, http_client, &[_]DownloadRequest{request});
    defer {
        for (results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }
    
    if (results.len > 0) {
        // Clone the result before cleanup
        const result = results[0];
        return DownloadResult{
            .success = result.success,
            .package_ref = try allocator.dupe(u8, result.package_ref),
            .url = if (result.url) |url| try allocator.dupe(u8, url) else null,
            .hash = if (result.hash) |hash| try allocator.dupe(u8, hash) else null,
            .cache_path = if (result.cache_path) |path| try allocator.dupe(u8, path) else null,
            .error_message = if (result.error_message) |msg| try allocator.dupe(u8, msg) else null,
            .duration_ms = result.duration_ms,
            .bytes_downloaded = result.bytes_downloaded,
        };
    }
    
    return error.DownloadFailed;
}