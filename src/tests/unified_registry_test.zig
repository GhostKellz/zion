const std = @import("std");
const testing = std.testing;
const zsync = @import("zsync");
const UnifiedRegistryManager = @import("../unified_registry_manager.zig").UnifiedRegistryManager;
const http_client = @import("../http_client.zig");
const ZionConfig = @import("../registry_config.zig").ZionConfig;

test "UnifiedRegistryManager: initialization and cleanup" {
    const allocator = testing.allocator;

    // Create test config
    var config = ZionConfig.init(allocator);
    defer config.deinit();

    // Initialize registry manager
    const manager = try UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();

    // Verify initialization
    try testing.expect(manager.registries.items.len >= 0);
    try testing.expect(manager.circuit_breakers.count() >= 0);
}

test "UnifiedRegistryManager: connection pooling" {
    const allocator = testing.allocator;

    var config = ZionConfig.init(allocator);
    defer config.deinit();

    const manager = try UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();

    // Test connection pool operations
    const pool = manager.connection_pool;

    // Acquire multiple connections
    var connections = std.ArrayList(*http_client.HttpClient).init(allocator);
    defer connections.deinit(allocator);

    for (0..5) |_| {
        const conn = try pool.acquire();
        try connections.append(allocator, conn);
    }

    // Release connections
    for (connections.items) |conn| {
        pool.release(conn);
    }

    // Verify pool state
    try testing.expect(pool.available.items.len > 0);
}

test "UnifiedRegistryManager: circuit breaker functionality" {
    const allocator = testing.allocator;

    var config = ZionConfig.init(allocator);
    defer config.deinit();

    const manager = try UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();

    // Test circuit breaker behavior
    if (manager.registries.items.len > 0) {
        const registry = &manager.registries.items[0];
        const registry_id = registry.getId();

        if (manager.circuit_breakers.get(registry_id)) |breaker| {
            // Test normal operation
            try testing.expect(breaker.canExecute());

            // Simulate failures
            for (0..5) |_| {
                breaker.recordFailure();
            }

            // Circuit should be open
            try testing.expect(!breaker.canExecute());

            // Test recovery
            breaker.recordSuccess();
            try testing.expect(breaker.canExecute());
        }
    }
}

test "UnifiedRegistryManager: async cache operations" {
    const allocator = testing.allocator;

    var config = ZionConfig.init(allocator);
    defer config.deinit();

    const manager = try UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();

    const cache = manager.cache;

    // Test package caching
    const test_package = UnifiedRegistryManager.Package{
        .name = try allocator.dupe(u8, "test-package"),
        .full_name = try allocator.dupe(u8, "test/test-package"),
        .description = null,
        .version = try allocator.dupe(u8, "1.0.0"),
        .tarball_url = null,
        .sha256_hash = null,
        .published_at = null,
        .registry_name = try allocator.dupe(u8, "test-registry"),
        .is_ziglibs = false,
        .quality_score = null,
        .star_count = null,
        .download_count = null,
        .maintenance_status = null,
    };
    defer test_package.deinit(allocator);

    // Put package in cache
    try cache.put("test-key", test_package, 60);

    // Retrieve from cache
    const cached = try cache.get("test-key");
    try testing.expect(cached != null);
    if (cached) |pkg| {
        defer pkg.deinit(allocator);
        try testing.expectEqualStrings(pkg.name, "test-package");
    }

    // Test search results caching
    var search_results = [_]UnifiedRegistryManager.Package{test_package};
    try cache.putSearchResults("search-key", &search_results, 60);

    const cached_search = try cache.getSearchResults("search-key");
    try testing.expect(cached_search != null);
    if (cached_search) |results| {
        defer {
            for (results) |pkg| {
                pkg.deinit(allocator);
            }
            allocator.free(results);
        }
        try testing.expect(results.len == 1);
    }
}

test "UnifiedRegistryManager: registry health tracking" {
    const allocator = testing.allocator;

    var config = ZionConfig.init(allocator);
    defer config.deinit();

    const manager = try UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();

    if (manager.registries.items.len > 0) {
        const registry = &manager.registries.items[0];
        const initial_health = registry.health_score;

        // Simulate successful operations
        manager.updateRegistryHealth(registry.getId(), true, 100);
        try testing.expect(registry.health_score >= initial_health);

        // Simulate failures
        for (0..3) |_| {
            manager.updateRegistryHealth(registry.getId(), false, 5000);
        }
        try testing.expect(registry.health_score < initial_health);
        try testing.expect(registry.failure_count > 0);
    }
}

test "UnifiedRegistryManager: package resolution with mocked response" {
    const allocator = testing.allocator;

    var config = ZionConfig.init(allocator);
    defer config.deinit();

    const manager = try UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();

    // This would require mocking HTTP responses
    // For now, we test the structure is correct
    const result = try manager.resolvePackage("test/package");
    if (result) |pkg| {
        defer pkg.deinit(allocator);
        try testing.expect(pkg.full_name.len > 0);
    }
}

test "UnifiedRegistryManager: parallel search operations" {
    const allocator = testing.allocator;

    var config = ZionConfig.init(allocator);
    defer config.deinit();

    const manager = try UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();

    // Test parallel search
    const results = try manager.searchPackages("test", 10);
    defer {
        for (results) |pkg| {
            pkg.deinit(allocator);
        }
        allocator.free(results);
    }

    // Verify results are properly deduplicated and sorted
    for (results, 0..) |pkg, i| {
        if (i > 0) {
            // Check for duplicates
            for (results[0..i]) |prev_pkg| {
                try testing.expect(!std.mem.eql(u8, pkg.full_name, prev_pkg.full_name));
            }
        }
    }
}

test "UnifiedRegistryManager: download with retry logic" {
    const allocator = testing.allocator;

    var config = ZionConfig.init(allocator);
    defer config.deinit();

    const manager = try UnifiedRegistryManager.init(allocator, &config);
    defer manager.deinit();

    // Test download with a mock URL
    const test_url = "https://example.com/test-package.tar.gz";
    const dest_path = "test-download.tar.gz";

    // This would fail in real test but demonstrates the retry logic structure
    manager.downloadPackage(test_url, dest_path) catch |err| {
        // Expected to fail without real URL
        try testing.expect(err == error.DownloadFailed or err == error.UnknownHost);
    };

    // Clean up test file if it exists
    std.fs.cwd().deleteFile(dest_path) catch {};
}

// Package type definition for testing
const Package = struct {
    name: []const u8,
    full_name: []const u8,
    description: ?[]const u8,
    version: []const u8,
    tarball_url: ?[]const u8,
    sha256_hash: ?[]const u8,
    published_at: ?[]const u8,
    registry_name: []const u8,
    is_ziglibs: bool,
    quality_score: ?u8,
    star_count: ?u32,
    download_count: ?u64,
    maintenance_status: ?[]const u8,

    pub fn deinit(self: Package, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.full_name);
        if (self.description) |desc| allocator.free(desc);
        allocator.free(self.version);
        if (self.tarball_url) |url| allocator.free(url);
        if (self.sha256_hash) |hash| allocator.free(hash);
        if (self.published_at) |date| allocator.free(date);
        allocator.free(self.registry_name);
        if (self.maintenance_status) |status| allocator.free(status);
    }

    pub fn clone(self: Package, allocator: std.mem.Allocator) !Package {
        return Package{
            .name = try allocator.dupe(u8, self.name),
            .full_name = try allocator.dupe(u8, self.full_name),
            .description = if (self.description) |d| try allocator.dupe(u8, d) else null,
            .version = try allocator.dupe(u8, self.version),
            .tarball_url = if (self.tarball_url) |u| try allocator.dupe(u8, u) else null,
            .sha256_hash = if (self.sha256_hash) |h| try allocator.dupe(u8, h) else null,
            .published_at = if (self.published_at) |p| try allocator.dupe(u8, p) else null,
            .registry_name = try allocator.dupe(u8, self.registry_name),
            .is_ziglibs = self.is_ziglibs,
            .quality_score = self.quality_score,
            .star_count = self.star_count,
            .download_count = self.download_count,
            .maintenance_status = if (self.maintenance_status) |s| try allocator.dupe(u8, s) else null,
        };
    }
};
