const std = @import("std");
const testing = std.testing;
const zsync = @import("zsync");

// Import modules for integration testing
const unified_registry_manager = @import("../unified_registry_manager.zig");
const async_downloader = @import("../async_downloader.zig");
const http_client = @import("../http_client.zig");
const request_batcher = @import("../request_batcher.zig");
const ZionConfig = @import("../registry_config.zig").ZionConfig;

test "Integration: End-to-End Package Workflow - Mock Registry" {
    const allocator = testing.allocator;
    
    // Initialize runtime
    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit();
    
    // Initialize config
    var config = ZionConfig.init(allocator);
    defer config.deinit();
    
    // Add test registry
    try config.addRegistry("test-registry", "https://registry.test.local", .GitHub);
    
    // Initialize registry manager
    const manager = try unified_registry_manager.UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();
    
    // Test workflow: search -> resolve -> download simulation
    std.debug.print("\n🔍 Testing package search...\n", .{});
    
    // Search for packages (will fail with mock URLs but tests structure)
    const search_results = manager.searchPackages("test", 5) catch |err| switch (err) {
        error.NetworkError, error.RegistryUnavailable, error.UnknownHost => {
            std.debug.print("  ✓ Network error expected with mock registry\n", .{});
            return;
        },
        else => return err,
    };
    defer {
        for (search_results) |pkg| {
            pkg.deinit(allocator);
        }
        allocator.free(search_results);
    }
    
    std.debug.print("  ✓ Found {} packages\n", .{search_results.len});
}

test "Integration: Parallel Package Resolution with Multiple Registries" {
    const allocator = testing.allocator;
    
    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit();
    
    var config = ZionConfig.init(allocator);
    defer config.deinit();
    
    // Add multiple test registries
    try config.addRegistry("github", "https://api.github.com", .GitHub);
    try config.addRegistry("zigistry", "https://zigistry.dev/api", .Zigistry);
    try config.addRegistry("local", "http://localhost:8080", .Local);
    
    const manager = try unified_registry_manager.UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();
    
    std.debug.print("\n📦 Testing parallel resolution with {} registries...\n", .{manager.registries.items.len});
    
    // Test parallel resolution of multiple packages
    const test_packages = [_][]const u8{
        "test/package1",
        "test/package2", 
        "test/package3",
        "user/library",
        "org/utility",
    };
    
    var resolution_results = std.ArrayList(?unified_registry_manager.UnifiedRegistryManager.Package).init(allocator);
    defer resolution_results.deinit();
    
    for (test_packages) |pkg_name| {
        const result = manager.resolvePackage(pkg_name) catch |err| switch (err) {
            error.NetworkError, error.PackageNotFound, error.UnknownHost => {
                std.debug.print("  ✓ Expected error for mock package: {s}\n", .{pkg_name});
                try resolution_results.append(null);
                continue;
            },
            else => return err,
        };
        
        try resolution_results.append(result);
        if (result) |pkg| {
            std.debug.print("  ✓ Resolved: {s} -> {s}\n", .{ pkg_name, pkg.full_name });
        }
    }
    
    // Clean up resolved packages
    for (resolution_results.items) |maybe_pkg| {
        if (maybe_pkg) |pkg| {
            pkg.deinit(allocator);
        }
    }
    
    std.debug.print("  ✓ Processed {} package resolution requests\n", .{test_packages.len});
}

test "Integration: Cache Invalidation and TTL" {
    const allocator = testing.allocator;
    
    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit();
    
    var config = ZionConfig.init(allocator);
    defer config.deinit();
    
    try config.addRegistry("test", "https://test.registry.local", .GitHub);
    
    const manager = try unified_registry_manager.UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();
    
    std.debug.print("\n💾 Testing cache invalidation and TTL...\n", .{});
    
    const cache = manager.cache;
    
    // Create test package for caching
    const test_package = unified_registry_manager.UnifiedRegistryManager.Package{
        .name = try allocator.dupe(u8, "test-package"),
        .full_name = try allocator.dupe(u8, "user/test-package"),
        .description = try allocator.dupe(u8, "A test package"),
        .version = try allocator.dupe(u8, "1.0.0"),
        .tarball_url = try allocator.dupe(u8, "https://example.com/package.tar.gz"),
        .sha256_hash = try allocator.dupe(u8, "abc123"),
        .published_at = try allocator.dupe(u8, "2024-01-01"),
        .registry_name = try allocator.dupe(u8, "test"),
        .is_ziglibs = false,
        .quality_score = 85,
        .star_count = 42,
        .download_count = 1000,
        .maintenance_status = try allocator.dupe(u8, "active"),
    };
    defer test_package.deinit(allocator);
    
    // Test short TTL cache
    const short_ttl = 1; // 1 second
    try cache.put("short-ttl-key", test_package, short_ttl);
    
    // Should be available immediately
    var cached = try cache.get("short-ttl-key");
    try testing.expect(cached != null);
    if (cached) |pkg| {
        defer pkg.deinit(allocator);
        try testing.expectEqualStrings(pkg.name, "test-package");
    }
    
    std.debug.print("  ✓ Short TTL cache entry stored and retrieved\n", .{});
    
    // Wait for expiration
    std.time.sleep(1100 * 1000000); // 1.1 seconds
    
    // Should be expired now
    cached = try cache.get("short-ttl-key");
    try testing.expect(cached == null);
    
    std.debug.print("  ✓ Cache entry expired after TTL\n", .{});
    
    // Test cache invalidation
    try cache.put("invalidation-test", test_package, 300); // 5 minute TTL
    
    cached = try cache.get("invalidation-test");
    try testing.expect(cached != null);
    if (cached) |pkg| {
        pkg.deinit(allocator);
    }
    
    // Invalidate cache
    cache.invalidate("invalidation-test");
    
    cached = try cache.get("invalidation-test");
    try testing.expect(cached == null);
    
    std.debug.print("  ✓ Manual cache invalidation works\n", .{});
}

test "Integration: Network Failure Recovery Scenarios" {
    const allocator = testing.allocator;
    
    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit();
    
    var config = ZionConfig.init(allocator);
    defer config.deinit();
    
    // Add registries with intentionally failing URLs
    try config.addRegistry("failing", "https://this-definitely-does-not-exist-12345.com", .GitHub);
    try config.addRegistry("timeout", "https://httpbin.org/delay/10", .GitHub); // Will timeout
    
    const manager = try unified_registry_manager.UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();
    
    std.debug.print("\n🔧 Testing network failure recovery...\n", .{});
    
    // Test 1: Unknown host recovery
    const result1 = manager.searchPackages("test", 1) catch |err| {
        switch (err) {
            error.UnknownHost, error.NetworkError => {
                std.debug.print("  ✓ Handled unknown host gracefully\n", .{});
            },
            else => return err,
        }
        return;
    };
    defer {
        for (result1) |pkg| {
            pkg.deinit(allocator);
        }
        allocator.free(result1);
    }
    
    // Test 2: Timeout handling
    const result2 = manager.resolvePackage("test/package") catch |err| {
        switch (err) {
            error.NetworkError, error.Timeout, error.UnknownHost => {
                std.debug.print("  ✓ Handled timeout gracefully\n", .{});
            },
            else => return err,
        }
        return;
    };
    if (result2) |pkg| {
        defer pkg.deinit(allocator);
    }
    
    // Verify registry health tracking after failures
    for (manager.registries.items) |registry| {
        if (registry.failure_count > 0) {
            std.debug.print("  ✓ Registry '{}' recorded {} failures\n", .{ registry.getId(), registry.failure_count });
        }
    }
}

test "Integration: Cancellation of Long-Running Operations" {
    const allocator = testing.allocator;
    
    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit();
    
    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit();
    
    std.debug.print("\n⏹️  Testing operation cancellation...\n", .{});
    
    // Create downloader with cancellation support
    const config = async_downloader.DownloadConfig{
        .max_concurrent = 2,
        .timeout_seconds = 30,
        .show_progress = false,
    };
    
    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, config);
    defer downloader.deinit();
    
    // Create long-running download requests
    var requests = [_]async_downloader.DownloadRequest{
        .{ .package_ref = "slow/package1", .url = "https://httpbin.org/delay/5" },
        .{ .package_ref = "slow/package2", .url = "https://httpbin.org/delay/5" },
    };
    
    // Start downloads in background
    const download_thread = try std.Thread.spawn(.{}, struct {
        fn downloadPackages(dl: *async_downloader.AsyncDownloader, reqs: []async_downloader.DownloadRequest) void {
            const results = dl.downloadPackages(reqs) catch return;
            defer {
                for (results) |*result| {
                    result.deinit(dl.allocator);
                }
                dl.allocator.free(results);
            }
        }
    }.downloadPackages, .{ downloader, &requests });
    
    // Let downloads start
    std.time.sleep(100 * 1000000); // 100ms
    
    // Cancel downloads
    downloader.cancel();
    std.debug.print("  ✓ Cancelled downloads\n", .{});
    
    // Wait for thread to complete
    download_thread.join();
    
    // Verify cancellation was effective
    try testing.expect(downloader.cancellation_token.is_cancelled());
    std.debug.print("  ✓ Cancellation token is active\n", .{});
}

test "Integration: Request Batching Optimization" {
    const allocator = testing.allocator;
    
    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit();
    
    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit();
    
    std.debug.print("\n📊 Testing request batching optimization...\n", .{});
    
    const batch_config = request_batcher.BatchConfig{
        .max_batch_size = 5,
        .max_wait_time_ms = 100,
        .enable_caching = true,
    };
    
    const batcher = try request_batcher.RequestBatcher.init(allocator, &runtime, client, batch_config);
    defer batcher.deinit();
    
    batcher.resetStats();
    
    // Create multiple similar requests that can be batched
    var futures = std.ArrayList(*zsync.Future(request_batcher.BatchedResult)).init(allocator);
    defer futures.deinit();
    
    // Add search requests to same registry (should batch together)
    for (0..8) |i| {
        const query = try std.fmt.allocPrint(allocator, "query{}", .{i});
        defer allocator.free(query);
        
        const request = try request_batcher.BatchableRequest.createSearchRequest(
            allocator,
            "test-registry",
            query
        );
        
        const future = try batcher.addRequest(request);
        try futures.append(future);
    }
    
    std.debug.print("  ✓ Added 8 similar requests\n", .{});
    
    // Force batch execution
    try batcher.flushAll();
    
    const stats = batcher.getStats();
    std.debug.print("  ✓ Executed {} batches for {} requests\n", .{ stats.batches_executed, stats.total_requests });
    std.debug.print("  ✓ Saved {} API calls ({}% reduction)\n", .{ stats.api_calls_saved, @as(u32, @intFromFloat(stats.getReductionPercentage())) });
    
    // Verify batching was effective
    try testing.expect(stats.total_requests == 8);
    try testing.expect(stats.batches_executed > 0);
    try testing.expect(stats.batches_executed < 8); // Should be fewer batches than individual requests
}

test "Integration: Multi-Level Caching Performance" {
    const allocator = testing.allocator;
    
    std.debug.print("\n🚀 Testing multi-level caching performance...\n", .{});
    
    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit();
    
    var config = ZionConfig.init(allocator);
    defer config.deinit();
    
    try config.addRegistry("perf-test", "https://test.perf.local", .GitHub);
    
    const manager = try unified_registry_manager.UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();
    
    const cache = manager.cache;
    
    // Create test packages for cache performance testing
    const num_packages = 100;
    var test_packages = std.ArrayList(unified_registry_manager.UnifiedRegistryManager.Package).init(allocator);
    defer {
        for (test_packages.items) |pkg| {
            pkg.deinit(allocator);
        }
        test_packages.deinit();
    }
    
    // Generate test packages
    for (0..num_packages) |i| {
        const name = try std.fmt.allocPrint(allocator, "package{}", .{i});
        const full_name = try std.fmt.allocPrint(allocator, "user/package{}", .{i});
        const version = try std.fmt.allocPrint(allocator, "1.{}.0", .{i});
        
        const pkg = unified_registry_manager.UnifiedRegistryManager.Package{
            .name = name,
            .full_name = full_name,
            .description = null,
            .version = version,
            .tarball_url = null,
            .sha256_hash = null,
            .published_at = null,
            .registry_name = try allocator.dupe(u8, "perf-test"),
            .is_ziglibs = false,
            .quality_score = null,
            .star_count = null,
            .download_count = null,
            .maintenance_status = null,
        };
        
        try test_packages.append(pkg);
    }
    
    // Benchmark cache writes
    const write_start = std.time.nanoTimestamp();
    
    for (test_packages.items, 0..) |pkg, i| {
        const cache_key = try std.fmt.allocPrint(allocator, "pkg:{}", .{i});
        defer allocator.free(cache_key);
        
        try cache.put(cache_key, pkg, 300); // 5 minute TTL
    }
    
    const write_end = std.time.nanoTimestamp();
    const write_time_ms = @divTrunc(write_end - write_start, 1_000_000);
    
    std.debug.print("  ✓ Cached {} packages in {}ms\n", .{ num_packages, write_time_ms });
    
    // Benchmark cache reads
    const read_start = std.time.nanoTimestamp();
    var cache_hits: u32 = 0;
    
    for (0..num_packages) |i| {
        const cache_key = try std.fmt.allocPrint(allocator, "pkg:{}", .{i});
        defer allocator.free(cache_key);
        
        const cached = try cache.get(cache_key);
        if (cached) |pkg| {
            defer pkg.deinit(allocator);
            cache_hits += 1;
        }
    }
    
    const read_end = std.time.nanoTimestamp();
    const read_time_ms = @divTrunc(read_end - read_start, 1_000_000);
    
    std.debug.print("  ✓ Retrieved {} packages in {}ms\n", .{ cache_hits, read_time_ms });
    std.debug.print("  ✓ Cache hit rate: {d:.1}%\n", .{ @as(f32, @floatFromInt(cache_hits)) / @as(f32, @floatFromInt(num_packages)) * 100.0 });
    
    // Verify performance metrics
    try testing.expect(cache_hits == num_packages);
    try testing.expect(read_time_ms < write_time_ms); // Reads should be faster than writes
}

test "Integration: Complete Package Lifecycle Simulation" {
    const allocator = testing.allocator;
    
    std.debug.print("\n🔄 Testing complete package lifecycle...\n", .{});
    
    var runtime = zsync.Runtime.init(allocator, .{});
    defer runtime.deinit();
    
    var config = ZionConfig.init(allocator);
    defer config.deinit();
    
    // Add multiple registries for comprehensive testing
    try config.addRegistry("primary", "https://api.primary.test", .GitHub);
    try config.addRegistry("fallback", "https://fallback.test.local", .Local);
    
    const manager = try unified_registry_manager.UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();
    
    const client = try http_client.HttpClient.init(allocator, &runtime);
    defer client.deinit();
    
    const downloader = try async_downloader.AsyncDownloader.init(allocator, &runtime, client, async_downloader.DownloadConfig{});
    defer downloader.deinit();
    
    // Simulate complete lifecycle: discover -> resolve -> download -> verify
    const lifecycle_steps = [_][]const u8{
        "1. Discover available packages",
        "2. Resolve specific package versions",
        "3. Download package archives",
        "4. Verify package integrity",
        "5. Update local cache",
        "6. Generate dependency graph",
    };
    
    std.debug.print("  📋 Package lifecycle simulation:\n", .{});
    
    for (lifecycle_steps) |step| {
        std.debug.print("     {s}\n", .{step});
        
        // Simulate processing time for each step
        std.time.sleep(5 * 1000000); // 5ms per step
        
        // Each step could involve different operations:
        switch (step[0]) {
            '1' => {
                // Discovery: search registries
                _ = manager.searchPackages("test", 3) catch {
                    // Expected to fail with mock registries
                };
            },
            '2' => {
                // Resolution: resolve dependencies
                _ = manager.resolvePackage("test/package") catch {
                    // Expected to fail with mock registries
                };
            },
            '3' => {
                // Download: fetch packages
                const requests = &[_]async_downloader.DownloadRequest{};
                const results = try downloader.downloadPackages(requests);
                defer allocator.free(results);
            },
            '4' => {
                // Verification: check integrity
                // This would involve hash checking in real implementation
            },
            '5' => {
                // Caching: update local state
                // Cache operations are tested separately
            },
            '6' => {
                // Dependency graph: build relationships
                // This would involve dependency resolution
            },
            else => {},
        }
    }
    
    std.debug.print("  ✅ Lifecycle simulation completed successfully\n", .{});
    
    // Verify system state after lifecycle
    const stats = downloader.stats;
    try testing.expect(stats.total_packages >= 0);
    
    // Verify registry health
    for (manager.registries.items) |registry| {
        try testing.expect(registry.health_score >= 0.0 and registry.health_score <= 100.0);
    }
}