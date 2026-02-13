const std = @import("std");
const testing = std.testing;
const zsync = @import("zsync");
const async_downloader = @import("../async_downloader.zig");
const http_client = @import("../http_client.zig");

test "AsyncDownloader: initialization and cleanup" {
    const allocator = testing.allocator;

    // Initialize runtime
    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    // Initialize HTTP client
    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    // Create downloader with config
    const config = async_downloader.DownloadConfig{
        .max_concurrent = 4,
        .retry_count = 3,
        .timeout_seconds = 30,
        .show_progress = false, // Disable for tests
        .cache_enabled = true,
    };

    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, config);
    defer downloader.deinit(allocator);

    // Verify initialization
    try testing.expect(downloader.config.max_concurrent == 4);
    try testing.expect(downloader.config.retry_count == 3);
}

test "AsyncDownloader: cache path generation" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = async_downloader.DownloadConfig{ .show_progress = false };
    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, config);
    defer downloader.deinit(allocator);

    // Test cache path generation
    const cache_path = try downloader.generateCachePath("test/package");
    defer allocator.free(cache_path);

    try testing.expect(std.mem.indexOf(u8, cache_path, ".zion/cache/") != null);
    try testing.expect(std.mem.endsWith(u8, cache_path, ".tar.gz"));
}

test "AsyncDownloader: package name sanitization" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = async_downloader.DownloadConfig{ .show_progress = false };
    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, config);
    defer downloader.deinit(allocator);

    // Test sanitization of special characters
    const sanitized = try downloader.sanitizePackageName("test/package:name*with?chars");
    defer allocator.free(sanitized);

    // Verify special characters are replaced
    try testing.expect(std.mem.indexOf(u8, sanitized, "/") == null);
    try testing.expect(std.mem.indexOf(u8, sanitized, ":") == null);
    try testing.expect(std.mem.indexOf(u8, sanitized, "*") == null);
    try testing.expect(std.mem.indexOf(u8, sanitized, "?") == null);
}

test "AsyncDownloader: statistics tracking" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = async_downloader.DownloadConfig{ .show_progress = false };
    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, config);
    defer downloader.deinit(allocator);

    // Test stats initialization
    try testing.expect(downloader.stats.total_packages == 0);
    try testing.expect(downloader.stats.completed == 0);
    try testing.expect(downloader.stats.successful == 0);
    try testing.expect(downloader.stats.failed == 0);

    // Test stats reset
    downloader.stats.total_packages = 10;
    downloader.stats.reset();
    try testing.expect(downloader.stats.total_packages == 0);
}

test "AsyncDownloader: cancellation token" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = async_downloader.DownloadConfig{ .show_progress = false };
    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, config);
    defer downloader.deinit(allocator);

    // Test cancellation
    try testing.expect(!downloader.cancellation_token.is_cancelled());

    downloader.cancel();
    try testing.expect(downloader.cancellation_token.is_cancelled());
}

test "AsyncDownloader: empty request handling" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = async_downloader.DownloadConfig{ .show_progress = false };
    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, config);
    defer downloader.deinit(allocator);

    // Test empty request list
    const empty_requests = &[_]async_downloader.DownloadRequest{};
    const results = try downloader.downloadPackages(empty_requests);
    defer allocator.free(results);

    try testing.expect(results.len == 0);
}

test "AsyncDownloader: hash calculation simulation" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = async_downloader.DownloadConfig{ .show_progress = false };
    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, config);
    defer downloader.deinit(allocator);

    // Create a test file
    const test_content = "test file content for hashing";
    const test_file = "test_hash_file.tmp";

    const file = try std.fs.cwd().createFile(test_file, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(test_file) catch {};

    try file.writeAll(test_content);

    // Calculate hash
    const hash = try downloader.calculateFileHash(test_file);
    defer allocator.free(hash);

    // Verify hash format
    try testing.expect(hash.len == 64); // SHA256 hex string
    for (hash) |c| {
        try testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
    }
}

test "AsyncDownloader: concurrent download structure" {
    const allocator = testing.allocator;

    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit(allocator);

    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit(allocator);

    const config = async_downloader.DownloadConfig{
        .max_concurrent = 2,
        .show_progress = false,
    };
    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, config);
    defer downloader.deinit(allocator);

    // Create test requests
    var requests = [_]async_downloader.DownloadRequest{
        .{ .package_ref = "test/package1", .url = "https://example.com/1.tar.gz" },
        .{ .package_ref = "test/package2", .url = "https://example.com/2.tar.gz" },
        .{ .package_ref = "test/package3", .url = "https://example.com/3.tar.gz" },
    };

    // This will fail with real URLs, but tests the structure
    const results = try downloader.downloadPackages(&requests);
    defer {
        for (results) |*result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }

    // Verify results structure
    try testing.expect(results.len == 3);
    for (results, 0..) |result, i| {
        try testing.expectEqualStrings(result.package_ref, requests[i].package_ref);
        // These would be failed downloads in test
        try testing.expect(!result.success);
        try testing.expect(result.error_message != null);
    }
}

test "Semaphore: concurrency control" {
    const Semaphore = async_downloader.Semaphore;

    var sem = Semaphore.init(2);

    // Test initial state
    try testing.expect(sem.count == 2);

    // Acquire permits
    sem.acquire();
    try testing.expect(sem.count == 1);

    sem.acquire();
    try testing.expect(sem.count == 0);

    // Release permits
    sem.release();
    try testing.expect(sem.count == 1);

    sem.release();
    try testing.expect(sem.count == 2);
}

test "DownloadStats: operations" {
    var stats = async_downloader.DownloadStats.init();

    // Test initial state
    try testing.expect(stats.total_packages == 0);
    try testing.expect(stats.completed == 0);

    // Update stats
    stats.total_packages = 10;
    stats.completed = 5;
    stats.successful = 4;
    stats.failed = 1;
    stats.total_bytes = 1024 * 1024 * 50; // 50MB

    // Test reset
    stats.reset();
    try testing.expect(stats.total_packages == 0);
    try testing.expect(stats.completed == 0);
    try testing.expect(stats.successful == 0);
    try testing.expect(stats.failed == 0);
    try testing.expect(stats.total_bytes == 0);
}
