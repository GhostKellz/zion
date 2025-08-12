const std = @import("std");
const zsync = @import("zsync");
const http_client = @import("http_client.zig");
const Allocator = std.mem.Allocator;

/// Request batcher for reducing API calls by grouping similar requests
pub const RequestBatcher = struct {
    allocator: Allocator,
    runtime: *zsync.Runtime,
    http_client: *http_client.HttpClient,
    batches: std.HashMap([]const u8, *RequestBatch),
    config: BatchConfig,
    stats: BatchStats,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, runtime: *zsync.Runtime, client: *http_client.HttpClient, config: BatchConfig) !*Self {
        const batcher = try allocator.create(Self);
        batcher.* = .{
            .allocator = allocator,
            .runtime = runtime,
            .http_client = client,
            .batches = std.HashMap([]const u8, *RequestBatch).init(allocator),
            .config = config,
            .stats = BatchStats.init(),
        };
        
        return batcher;
    }
    
    pub fn deinit(self: *Self) void {
        // Clean up batches
        var iterator = self.batches.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.batches.deinit();
        
        self.allocator.destroy(self);
    }
    
    /// Add a request to the appropriate batch
    pub fn addRequest(self: *Self, request: BatchableRequest) !*zsync.Future(BatchedResult) {
        const batch_key = try self.getBatchKey(request);
        
        // Get or create batch
        var batch = self.batches.get(batch_key) orelse blk: {
            const new_batch = try self.allocator.create(RequestBatch);
            new_batch.* = RequestBatch.init(self.allocator, batch_key, self.config);
            
            const owned_key = try self.allocator.dupe(u8, batch_key);
            try self.batches.put(owned_key, new_batch);
            
            break :blk new_batch;
        };
        
        // Add request to batch
        const future = try batch.addRequest(request);
        
        // Check if batch should be executed
        if (batch.shouldExecute()) {
            try self.executeBatch(batch);
        }
        
        return future;
    }
    
    /// Force execution of all pending batches
    pub fn flushAll(self: *Self) !void {
        var iterator = self.batches.iterator();
        while (iterator.next()) |entry| {
            const batch = entry.value_ptr.*;
            if (batch.hasPendingRequests()) {
                try self.executeBatch(batch);
            }
        }
    }
    
    /// Execute a batch of requests
    fn executeBatch(self: *Self, batch: *RequestBatch) !void {
        const start_time = std.time.milliTimestamp();
        
        // Update stats
        self.stats.batches_executed += 1;
        self.stats.total_requests += batch.requests.items.len;
        
        std.log.debug("🔄 Executing batch '{}' with {} requests", .{ batch.key, batch.requests.items.len });
        
        // Execute batch based on type
        switch (batch.batch_type) {
            .Search => try self.executeBatchSearch(batch),
            .PackageInfo => try self.executeBatchPackageInfo(batch),
            .Download => try self.executeBatchDownload(batch),
            .Registry => try self.executeBatchRegistry(batch),
        }
        
        const duration = std.time.milliTimestamp() - start_time;
        self.stats.total_time_ms += @intCast(duration);
        
        // Calculate API call reduction
        const potential_calls = batch.requests.items.len;
        const actual_calls = @as(u32, 1); // Batched into single call
        const reduction = if (potential_calls > 0) 
            @as(f64, @floatFromInt(potential_calls - actual_calls)) / @as(f64, @floatFromInt(potential_calls))
        else 0.0;
        
        self.stats.api_calls_saved += potential_calls - actual_calls;
        
        std.log.debug("✅ Batch executed in {}ms ({}% API call reduction)", .{ duration, @as(u32, @intFromFloat(reduction * 100)) });
    }
    
    /// Execute a batch of search requests
    fn executeBatchSearch(self: *Self, batch: *RequestBatch) !void {
        // Combine all search queries into a single request
        var combined_query = std.ArrayList([]const u8).init(self.allocator);
        defer combined_query.deinit();
        
        for (batch.requests.items) |request| {
            try combined_query.append(request.search_query orelse "");
        }
        
        // Create batch search URL
        const query_param = try std.mem.join(self.allocator, " OR ", combined_query.items);
        defer self.allocator.free(query_param);
        
        const url = try std.fmt.allocPrint(self.allocator, "/api/search?q={s}&limit={d}", .{ query_param, batch.requests.items.len * 10 });
        defer self.allocator.free(url);
        
        // Execute batch request
        const response = try self.http_client.get(url);
        defer response.deinit(self.allocator);
        
        // Parse and distribute results
        if (response.isSuccess() and response.body != null) {
            // Parse JSON response for search results
            self.parseAndDistributeSearchResults(batch, response.body.?) catch |err| {
                // If JSON parsing fails, fallback to error handling
                std.debug.print("Warning: JSON parsing failed: {}\n", .{err});
                self.handleBatchError(batch, "JSON parsing error");
                return;
            };
        } else {
            // Handle error for all requests in batch
            for (batch.requests.items) |request| {
                const result = BatchedResult{
                    .success = false,
                    .data = null,
                    .error_message = "Batch search failed",
                    .from_cache = false,
                    .batch_size = @intCast(batch.requests.items.len),
                };
                
                request.future.complete(result);
            }
        }
        
        // Clear batch
        batch.clear();
    }
    
    /// Execute a batch of package info requests
    fn executeBatchPackageInfo(self: *Self, batch: *RequestBatch) !void {
        // Combine all package names into a single request
        var package_names = std.ArrayList([]const u8).init(self.allocator);
        defer package_names.deinit();
        
        for (batch.requests.items) |request| {
            try package_names.append(request.package_name orelse "");
        }
        
        // Create batch package info URL
        const packages_param = try std.mem.join(self.allocator, ",", package_names.items);
        defer self.allocator.free(packages_param);
        
        const url = try std.fmt.allocPrint(self.allocator, "/api/packages?names={s}", .{packages_param});
        defer self.allocator.free(url);
        
        // Execute batch request
        const response = try self.http_client.get(url);
        defer response.deinit(self.allocator);
        
        // Parse and distribute results
        if (response.isSuccess() and response.body != null) {
            // Parse JSON response for package info
            self.parseAndDistributePackageInfo(batch, response.body.?) catch |err| {
                // If JSON parsing fails, fallback to error handling
                std.debug.print("Warning: Package info JSON parsing failed: {}\n", .{err});
                self.handleBatchError(batch, "Package info parsing error");
                return;
            };
        } else {
            // Handle error for all requests in batch
            for (batch.requests.items) |request| {
                const result = BatchedResult{
                    .success = false,
                    .data = null,
                    .error_message = "Batch package info failed",
                    .from_cache = false,
                    .batch_size = @intCast(batch.requests.items.len),
                };
                
                request.future.complete(result);
            }
        }
        
        // Clear batch
        batch.clear();
    }
    
    /// Execute a batch of download requests
    fn executeBatchDownload(self: *Self, batch: *RequestBatch) !void {
        // Downloads are typically executed individually for security/integrity
        // But we can still batch the metadata requests
        
        var download_futures = std.ArrayList(*zsync.Future(BatchedResult)).init(self.allocator);
        defer download_futures.deinit();
        
        // Start parallel downloads
        for (batch.requests.items) |request| {
            const future = try self.downloadSingleAsync(request);
            try download_futures.append(future);
        }
        
        // Wait for all downloads to complete
        for (download_futures.items, 0..) |future, i| {
            const result = try future.await();
            future.deinit();
            
            // Complete the original request
            batch.requests.items[i].future.complete(result);
        }
        
        // Clear batch
        batch.clear();
    }
    
    /// Execute a batch of registry requests
    fn executeBatchRegistry(self: *Self, batch: *RequestBatch) !void {
        // Registry health checks can be batched
        const url = "/api/health";
        
        const response = try self.http_client.get(url);
        defer response.deinit(self.allocator);
        
        // Distribute results to all requests
        for (batch.requests.items) |request| {
            const result = BatchedResult{
                .success = response.isSuccess(),
                .data = response.body,
                .error_message = if (response.isSuccess()) null else "Registry health check failed",
                .from_cache = false,
                .batch_size = @intCast(batch.requests.items.len),
            };
            
            request.future.complete(result);
        }
        
        // Clear batch
        batch.clear();
    }
    
    /// Download a single file asynchronously
    fn downloadSingleAsync(self: *Self, request: BatchableRequest) !*zsync.Future(BatchedResult) {
        const Task = struct {
            batcher: *RequestBatcher,
            url: []const u8,
            
            fn run(task: @This()) BatchedResult {
                const response = task.batcher.http_client.get(task.url) catch |err| {
                    return BatchedResult{
                        .success = false,
                        .data = null,
                        .error_message = @errorName(err),
                        .from_cache = false,
                        .batch_size = 1,
                    };
                };
                defer response.deinit(task.batcher.allocator);
                
                return BatchedResult{
                    .success = response.isSuccess(),
                    .data = response.body,
                    .error_message = if (response.isSuccess()) null else "Download failed",
                    .from_cache = false,
                    .batch_size = 1,
                };
            }
        };
        
        const task = Task{
            .batcher = self,
            .url = request.download_url orelse "",
        };
        
        return try zsync.spawn(self.runtime, task, Task.run);
    }
    
    /// Generate batch key for grouping requests
    fn getBatchKey(self: *Self, request: BatchableRequest) ![]const u8 {
        _ = self;
        return switch (request.request_type) {
            .Search => try std.fmt.allocPrint(self.allocator, "search:{s}", .{request.registry_name orelse "default"}),
            .PackageInfo => try std.fmt.allocPrint(self.allocator, "package:{s}", .{request.registry_name orelse "default"}),
            .Download => try std.fmt.allocPrint(self.allocator, "download:{s}", .{request.registry_name orelse "default"}),
            .Registry => try std.fmt.allocPrint(self.allocator, "registry:{s}", .{request.registry_name orelse "default"}),
        };
    }
    
    /// Get batch statistics
    pub fn getStats(self: *const Self) BatchStats {
        return self.stats;
    }
    
    /// Reset batch statistics
    pub fn resetStats(self: *Self) void {
        self.stats = BatchStats.init();
    }
    
    /// Parse search results JSON and distribute to individual futures
    fn parseAndDistributeSearchResults(self: *Self, batch: *RequestBatch, json_body: []const u8) !void {
        // Basic JSON structure expected: {"packages": [{"name": "...", "version": "...", ...}, ...]}
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_body, .{}) catch {
            std.debug.print("Failed to parse search JSON\n", .{});
            // Fallback to simple data distribution
            for (batch.requests.items) |request| {
                const result = BatchedResult{
                    .success = true,
                    .data = json_body,
                    .error_message = null,
                    .from_cache = false,
                    .batch_size = @intCast(batch.requests.items.len),
                };
                request.future.complete(result);
            }
            return;
        };
        defer parsed.deinit();
        
        // Extract packages array
        const packages_array = if (parsed.value.object.get("packages")) |packages| 
            packages.array else {
            // No packages array found, distribute raw data
            for (batch.requests.items) |request| {
                const result = BatchedResult{
                    .success = true,
                    .data = json_body,
                    .error_message = null,
                    .from_cache = false,
                    .batch_size = @intCast(batch.requests.items.len),
                };
                request.future.complete(result);
            }
            return;
        };
        
        // Distribute search results to matching requests
        for (batch.requests.items) |request| {
            // For search requests, return all results for now
            // In a more sophisticated implementation, we'd filter results per query
            const result = BatchedResult{
                .success = true,
                .data = json_body,
                .error_message = null,
                .from_cache = false,
                .batch_size = @intCast(batch.requests.items.len),
            };
            request.future.complete(result);
        }
    }
    
    /// Parse package info JSON and distribute to individual futures
    fn parseAndDistributePackageInfo(self: *Self, batch: *RequestBatch, json_body: []const u8) !void {
        // Basic JSON structure expected: {"packages": {"pkg1": {...}, "pkg2": {...}, ...}}
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_body, .{}) catch {
            std.debug.print("Failed to parse package info JSON\n", .{});
            // Fallback to error distribution
            self.handleBatchError(batch, "JSON parsing failed");
            return;
        };
        defer parsed.deinit();
        
        // Extract packages object
        const packages_obj = if (parsed.value.object.get("packages")) |packages| 
            packages.object else {
            self.handleBatchError(batch, "Invalid JSON structure");
            return;
        };
        
        // Distribute package info to matching requests
        for (batch.requests.items) |request| {
            const package_name = request.package_name orelse "";
            
            if (packages_obj.get(package_name)) |package_info| {
                // Found specific package info
                const package_json = std.json.stringifyAlloc(self.allocator, package_info, .{}) catch {
                    const result = BatchedResult{
                        .success = false,
                        .data = null,
                        .error_message = "Failed to serialize package info",
                        .from_cache = false,
                        .batch_size = @intCast(batch.requests.items.len),
                    };
                    request.future.complete(result);
                    continue;
                };
                defer self.allocator.free(package_json);
                
                const result = BatchedResult{
                    .success = true,
                    .data = try self.allocator.dupe(u8, package_json),
                    .error_message = null,
                    .from_cache = false,
                    .batch_size = @intCast(batch.requests.items.len),
                };
                request.future.complete(result);
            } else {
                // Package not found
                const result = BatchedResult{
                    .success = false,
                    .data = null,
                    .error_message = "Package not found",
                    .from_cache = false,
                    .batch_size = @intCast(batch.requests.items.len),
                };
                request.future.complete(result);
            }
        }
    }
    
    /// Handle batch errors by distributing error results to all requests
    fn handleBatchError(self: *Self, batch: *RequestBatch, error_message: []const u8) void {
        for (batch.requests.items) |request| {
            const result = BatchedResult{
                .success = false,
                .data = null,
                .error_message = error_message,
                .from_cache = false,
                .batch_size = @intCast(batch.requests.items.len),
            };
            request.future.complete(result);
        }
    }
};

/// Configuration for request batching
pub const BatchConfig = struct {
    max_batch_size: u32 = 10,
    max_wait_time_ms: u64 = 100,
    auto_flush: bool = true,
    enable_caching: bool = true,
};

/// Statistics for batch operations
pub const BatchStats = struct {
    batches_executed: u32,
    total_requests: u32,
    api_calls_saved: u32,
    total_time_ms: u64,
    
    fn init() BatchStats {
        return BatchStats{
            .batches_executed = 0,
            .total_requests = 0,
            .api_calls_saved = 0,
            .total_time_ms = 0,
        };
    }
    
    /// Get API call reduction percentage
    pub fn getReductionPercentage(self: *const BatchStats) f64 {
        if (self.total_requests == 0) return 0.0;
        return @as(f64, @floatFromInt(self.api_calls_saved)) / @as(f64, @floatFromInt(self.total_requests)) * 100.0;
    }
    
    /// Get average batch size
    pub fn getAverageBatchSize(self: *const BatchStats) f64 {
        if (self.batches_executed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_requests)) / @as(f64, @floatFromInt(self.batches_executed));
    }
};

/// Types of requests that can be batched
pub const RequestType = enum {
    Search,
    PackageInfo,
    Download,
    Registry,
};

/// A request that can be batched
pub const BatchableRequest = struct {
    request_type: RequestType,
    registry_name: ?[]const u8 = null,
    search_query: ?[]const u8 = null,
    package_name: ?[]const u8 = null,
    download_url: ?[]const u8 = null,
    future: *Future(BatchedResult),
    
    pub fn createSearchRequest(allocator: Allocator, registry: []const u8, query: []const u8) !BatchableRequest {
        return BatchableRequest{
            .request_type = .Search,
            .registry_name = try allocator.dupe(u8, registry),
            .search_query = try allocator.dupe(u8, query),
            .future = try Future(BatchedResult).init(allocator),
        };
    }
    
    pub fn createPackageInfoRequest(allocator: Allocator, registry: []const u8, package_name: []const u8) !BatchableRequest {
        return BatchableRequest{
            .request_type = .PackageInfo,
            .registry_name = try allocator.dupe(u8, registry),
            .package_name = try allocator.dupe(u8, package_name),
            .future = try Future(BatchedResult).init(allocator),
        };
    }
    
    pub fn createDownloadRequest(allocator: Allocator, registry: []const u8, url: []const u8) !BatchableRequest {
        return BatchableRequest{
            .request_type = .Download,
            .registry_name = try allocator.dupe(u8, registry),
            .download_url = try allocator.dupe(u8, url),
            .future = try Future(BatchedResult).init(allocator),
        };
    }
    
    pub fn deinit(self: *BatchableRequest, allocator: Allocator) void {
        if (self.registry_name) |name| allocator.free(name);
        if (self.search_query) |query| allocator.free(query);
        if (self.package_name) |name| allocator.free(name);
        if (self.download_url) |url| allocator.free(url);
        self.future.deinit();
    }
};

/// Result of a batched request
pub const BatchedResult = struct {
    success: bool,
    data: ?[]const u8,
    error_message: ?[]const u8,
    from_cache: bool,
    batch_size: u32,
};

/// A batch of similar requests
const RequestBatch = struct {
    allocator: Allocator,
    key: []const u8,
    batch_type: RequestType,
    requests: std.ArrayList(BatchableRequest),
    created_at: i64,
    config: BatchConfig,
    
    fn init(allocator: Allocator, key: []const u8, config: BatchConfig) RequestBatch {
        // Determine batch type from key
        const batch_type = if (std.mem.startsWith(u8, key, "search:"))
            RequestType.Search
        else if (std.mem.startsWith(u8, key, "package:"))
            RequestType.PackageInfo
        else if (std.mem.startsWith(u8, key, "download:"))
            RequestType.Download
        else
            RequestType.Registry;
        
        return RequestBatch{
            .allocator = allocator,
            .key = key,
            .batch_type = batch_type,
            .requests = std.ArrayList(BatchableRequest).init(allocator),
            .created_at = std.time.milliTimestamp(),
            .config = config,
        };
    }
    
    fn deinit(self: *RequestBatch) void {
        for (self.requests.items) |*request| {
            request.deinit(self.allocator);
        }
        self.requests.deinit();
    }
    
    fn addRequest(self: *RequestBatch, request: BatchableRequest) !*zsync.Future(BatchedResult) {
        try self.requests.append(request);
        return request.future;
    }
    
    fn shouldExecute(self: *const RequestBatch) bool {
        // Execute if batch is full
        if (self.requests.items.len >= self.config.max_batch_size) {
            return true;
        }
        
        // Execute if batch has been waiting too long
        const now = std.time.milliTimestamp();
        const wait_time = now - self.created_at;
        if (wait_time >= self.config.max_wait_time_ms) {
            return true;
        }
        
        return false;
    }
    
    fn hasPendingRequests(self: *const RequestBatch) bool {
        return self.requests.items.len > 0;
    }
    
    fn clear(self: *RequestBatch) void {
        for (self.requests.items) |*request| {
            request.deinit(self.allocator);
        }
        self.requests.clearRetainingCapacity();
        self.created_at = std.time.milliTimestamp();
    }
};

/// Simple future implementation for batched results
const Future = struct {
    T: type,
    allocator: Allocator,
    result: ?T,
    completed: bool,
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    
    fn init(allocator: Allocator, comptime T: type) !*Future(T) {
        const future = try allocator.create(Future(T));
        future.* = Future(T){
            .T = T,
            .allocator = allocator,
            .result = null,
            .completed = false,
            .mutex = std.Thread.Mutex{},
            .condition = std.Thread.Condition{},
        };
        return future;
    }
    
    fn deinit(self: *Future(T)) void {
        self.allocator.destroy(self);
    }
    
    fn complete(self: *Future(T), result: T) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.result = result;
        self.completed = true;
        self.condition.broadcast();
    }
    
    fn await(self: *Future(T)) T {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        while (!self.completed) {
            self.condition.wait(&self.mutex);
        }
        
        return self.result.?;
    }
};

/// Convenience function for batched search requests
pub fn batchedSearch(
    allocator: Allocator,
    batcher: *RequestBatcher,
    registry: []const u8,
    queries: []const []const u8,
) ![]BatchedResult {
    var futures = std.ArrayList(*zsync.Future(BatchedResult)).init(allocator);
    defer futures.deinit();
    
    // Submit all search requests
    for (queries) |query| {
        const request = try BatchableRequest.createSearchRequest(allocator, registry, query);
        const future = try batcher.addRequest(request);
        try futures.append(future);
    }
    
    // Force flush to ensure execution
    try batcher.flushAll();
    
    // Collect results
    var results = try allocator.alloc(BatchedResult, futures.items.len);
    for (futures.items, 0..) |future, i| {
        results[i] = try future.await();
    }
    
    return results;
}

/// Convenience function for batched package info requests
pub fn batchedPackageInfo(
    allocator: Allocator,
    batcher: *RequestBatcher,
    registry: []const u8,
    package_names: []const []const u8,
) ![]BatchedResult {
    var futures = std.ArrayList(*zsync.Future(BatchedResult)).init(allocator);
    defer futures.deinit();
    
    // Submit all package info requests
    for (package_names) |name| {
        const request = try BatchableRequest.createPackageInfoRequest(allocator, registry, name);
        const future = try batcher.addRequest(request);
        try futures.append(future);
    }
    
    // Force flush to ensure execution
    try batcher.flushAll();
    
    // Collect results
    var results = try allocator.alloc(BatchedResult, futures.items.len);
    for (futures.items, 0..) |future, i| {
        results[i] = try future.await();
    }
    
    return results;
}