const std = @import("std");
const testing = std.testing;
const zsync = @import("zsync");
const request_batcher = @import("../request_batcher.zig");
const http_client = @import("../http_client.zig");

test "RequestBatcher: initialization and cleanup" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = request_batcher.BatchConfig{
        .max_batch_size = 10,
        .max_wait_time_ms = 100,
        .auto_flush = true,
        .enable_caching = true,
    };

    const batcher = try request_batcher.RequestBatcher.init(allocator, &runtime, client, config);
    defer batcher.deinit(allocator);

    // Verify initialization
    try testing.expect(batcher.config.max_batch_size == 10);
    try testing.expect(batcher.config.max_wait_time_ms == 100);
}

test "RequestBatcher: batch key generation" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = request_batcher.BatchConfig{};
    const batcher = try request_batcher.RequestBatcher.init(allocator, &runtime, client, config);
    defer batcher.deinit(allocator);

    // Test batch key generation for different request types
    const search_request = request_batcher.BatchableRequest{
        .request_type = .Search,
        .registry_name = "test-registry",
        .search_query = "test-query",
        .future = undefined, // Not used in this test
    };

    const key = try batcher.getBatchKey(search_request);
    defer allocator.free(key);

    try testing.expect(std.mem.startsWith(u8, key, "search:"));
    try testing.expect(std.mem.indexOf(u8, key, "test-registry") != null);
}

test "RequestBatch: should execute logic" {
    const allocator = testing.allocator;

    const config = request_batcher.BatchConfig{
        .max_batch_size = 3,
        .max_wait_time_ms = 100,
    };

    var batch = request_batcher.RequestBatch.init(allocator, "test:batch", config);
    defer batch.deinit(allocator);

    // Initially should not execute
    try testing.expect(!batch.shouldExecute());

    // Add requests up to max
    for (0..3) |_| {
        const request = request_batcher.BatchableRequest{
            .request_type = .Search,
            .registry_name = "test",
            .future = undefined,
        };
        _ = try batch.addRequest(request);
    }

    // Should execute when full
    try testing.expect(batch.shouldExecute());
}

test "RequestBatch: time-based execution" {
    const allocator = testing.allocator;

    const config = request_batcher.BatchConfig{
        .max_batch_size = 10,
        .max_wait_time_ms = 1, // Very short for testing
    };

    var batch = request_batcher.RequestBatch.init(allocator, "test:batch", config);
    defer batch.deinit(allocator);

    // Add one request
    const request = request_batcher.BatchableRequest{
        .request_type = .Search,
        .registry_name = "test",
        .future = undefined,
    };
    _ = try batch.addRequest(request);

    // Wait for timeout
    std.time.sleep(2 * 1000000); // 2ms

    // Should execute after timeout
    try testing.expect(batch.shouldExecute());
}

test "BatchStats: calculations" {
    var stats = request_batcher.BatchStats.init();

    // Set test values
    stats.batches_executed = 10;
    stats.total_requests = 100;
    stats.api_calls_saved = 90;
    stats.total_time_ms = 1000;

    // Test reduction percentage
    const reduction = stats.getReductionPercentage();
    try testing.expect(reduction == 90.0);

    // Test average batch size
    const avg_size = stats.getAverageBatchSize();
    try testing.expect(avg_size == 10.0);

    // Test with zero values
    stats = request_batcher.BatchStats.init();
    try testing.expect(stats.getReductionPercentage() == 0.0);
    try testing.expect(stats.getAverageBatchSize() == 0.0);
}

test "BatchableRequest: factory methods" {
    const allocator = testing.allocator;

    // Test search request creation
    const search_req = try request_batcher.BatchableRequest.createSearchRequest(allocator, "test-registry", "search-query");
    defer search_req.deinit(allocator);

    try testing.expect(search_req.request_type == .Search);
    try testing.expectEqualStrings(search_req.registry_name.?, "test-registry");
    try testing.expectEqualStrings(search_req.search_query.?, "search-query");

    // Test package info request creation
    const pkg_req = try request_batcher.BatchableRequest.createPackageInfoRequest(allocator, "test-registry", "test/package");
    defer pkg_req.deinit(allocator);

    try testing.expect(pkg_req.request_type == .PackageInfo);
    try testing.expectEqualStrings(pkg_req.package_name.?, "test/package");

    // Test download request creation
    const dl_req = try request_batcher.BatchableRequest.createDownloadRequest(allocator, "test-registry", "https://example.com/package.tar.gz");
    defer dl_req.deinit(allocator);

    try testing.expect(dl_req.request_type == .Download);
    try testing.expectEqualStrings(dl_req.download_url.?, "https://example.com/package.tar.gz");
}

test "RequestBatcher: batch execution structure" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = request_batcher.BatchConfig{
        .max_batch_size = 2,
        .max_wait_time_ms = 1000,
    };

    const batcher = try request_batcher.RequestBatcher.init(allocator, &runtime, client, config);
    defer batcher.deinit(allocator);

    // Reset stats
    batcher.resetStats();

    // Create multiple search requests
    var futures = std.ArrayList(*zsync.Future(request_batcher.BatchedResult)).init(allocator);
    defer futures.deinit(allocator);

    for (0..2) |i| {
        const query = try std.fmt.allocPrint(allocator, "query{}", .{i});
        defer allocator.free(query);

        const request = try request_batcher.BatchableRequest.createSearchRequest(allocator, "test-registry", query);

        const future = try batcher.addRequest(request);
        try futures.append(allocator, future);
    }

    // Force flush to execute batch
    try batcher.flushAll();

    // Verify stats
    const stats = batcher.getStats();
    try testing.expect(stats.batches_executed > 0);
    try testing.expect(stats.total_requests == 2);
}

test "RequestBatcher: flush all batches" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = request_batcher.BatchConfig{
        .max_batch_size = 100, // High limit to prevent auto-execution
        .max_wait_time_ms = 10000, // Long wait time
    };

    const batcher = try request_batcher.RequestBatcher.init(allocator, &runtime, client, config);
    defer batcher.deinit(allocator);

    // Add requests to different batch types
    const search_req = try request_batcher.BatchableRequest.createSearchRequest(allocator, "registry1", "search");
    _ = try batcher.addRequest(search_req);

    const pkg_req = try request_batcher.BatchableRequest.createPackageInfoRequest(allocator, "registry1", "package");
    _ = try batcher.addRequest(pkg_req);

    // Verify batches exist
    try testing.expect(batcher.batches.count() >= 2);

    // Flush all batches
    try batcher.flushAll();
}

test "Future: basic operations" {
    const allocator = testing.allocator;

    const TestResult = struct {
        value: u32,
        success: bool,
    };

    const future = try request_batcher.Future.init(allocator, TestResult);
    defer future.deinit(allocator);

    // Complete future in a separate thread
    const thread = try std.Thread.spawn(.{}, struct {
        fn complete(f: *request_batcher.Future(TestResult)) void {
            std.time.sleep(10 * 1000000); // 10ms
            f.complete(TestResult{ .value = 42, .success = true });
        }
    }.complete, .{future});

    // Await result
    const result = future.await();
    thread.join();

    try testing.expect(result.value == 42);
    try testing.expect(result.success);
}
