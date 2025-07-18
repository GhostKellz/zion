const std = @import("std");
const zsync = @import("zsync");
const http_client = @import("http_client.zig");
const Allocator = std.mem.Allocator;
const ZionConfig = @import("registry_config.zig").ZionConfig;
const RegistryConfig = @import("registry_config.zig").RegistryConfig;
const Package = @import("registry_client.zig").Package;
const Release = @import("registry_client.zig").Release;

/// Unified Registry Manager v1.0.3 - Consolidates all registry operations
/// with optimized async patterns, connection pooling, and enhanced performance
pub const UnifiedRegistryManager = struct {
    allocator: Allocator,
    config: *ZionConfig,
    runtime: *zsync.Runtime,
    connection_pool: *ConnectionPool,
    registries: std.ArrayList(RegistryEndpoint),
    circuit_breakers: std.HashMap(u32, *CircuitBreaker),
    cache: *AsyncCache,
    
    const RegistryEndpoint = struct {
        name: []const u8,
        base_url: []const u8,
        api_token: ?[]const u8,
        enabled: bool,
        priority: u8,
        health_score: f32,
        last_response_time: ?u64,
        failure_count: u32,
        
        pub fn getId(self: *const RegistryEndpoint) u32 {
            return std.hash.Wyhash.hash(0, self.name);
        }
    };
    
    pub fn init(allocator: Allocator, zion_config: *ZionConfig) !*UnifiedRegistryManager {
        var manager = try allocator.create(UnifiedRegistryManager);
        
        // Initialize zsync runtime for async operations
        const runtime = try allocator.create(zsync.Runtime);
        runtime.* = zsync.Runtime.init(allocator, .{});
        
        // Initialize connection pool
        const connection_pool = try ConnectionPool.init(allocator, 10); // Max 10 connections
        
        // Initialize async cache
        const cache = try AsyncCache.init(allocator);
        
        manager.* = .{
            .allocator = allocator,
            .config = zion_config,
            .runtime = runtime,
            .connection_pool = connection_pool,
            .registries = std.ArrayList(RegistryEndpoint).init(allocator),
            .circuit_breakers = std.HashMap(u32, *CircuitBreaker).init(allocator),
            .cache = cache,
        };
        
        try manager.initRegistries();
        try manager.initCircuitBreakers();
        return manager;
    }
    
    pub fn deinit(self: *UnifiedRegistryManager) void {
        // Cleanup registries
        for (self.registries.items) |registry| {
            self.allocator.free(registry.name);
            self.allocator.free(registry.base_url);
            if (registry.api_token) |token| self.allocator.free(token);
        }
        self.registries.deinit();
        
        // Cleanup circuit breakers
        var circuit_iterator = self.circuit_breakers.iterator();
        while (circuit_iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.circuit_breakers.deinit();
        
        // Cleanup other resources
        self.cache.deinit();
        self.allocator.destroy(self.cache);
        
        self.connection_pool.deinit();
        self.allocator.destroy(self.connection_pool);
        
        self.runtime.deinit();
        self.allocator.destroy(self.runtime);
        
        self.allocator.destroy(self);
    }
    
    fn initRegistries(self: *UnifiedRegistryManager) !void {
        for (self.config.registries.items) |reg_config| {
            if (reg_config.enabled) {
                const endpoint = RegistryEndpoint{
                    .name = try self.allocator.dupe(u8, reg_config.name),
                    .base_url = try self.allocator.dupe(u8, reg_config.base_url),
                    .api_token = if (reg_config.auth_token) |token| try self.allocator.dupe(u8, token) else null,
                    .enabled = reg_config.enabled,
                    .priority = @intCast(reg_config.priority),
                    .health_score = 1.0,
                    .last_response_time = null,
                    .failure_count = 0,
                };
                try self.registries.append(endpoint);
            }
        }
        
        // Sort by priority and health score
        std.sort.block(RegistryEndpoint, self.registries.items, {}, struct {
            fn lessThan(context: void, a: RegistryEndpoint, b: RegistryEndpoint) bool {
                _ = context;
                if (a.priority != b.priority) return a.priority < b.priority;
                return a.health_score > b.health_score;
            }
        }.lessThan);
    }
    
    fn initCircuitBreakers(self: *UnifiedRegistryManager) !void {
        for (self.registries.items) |*registry| {
            const breaker = try self.allocator.create(CircuitBreaker);
            breaker.* = CircuitBreaker.init(5, 60000); // 5 failures, 60s timeout
            try self.circuit_breakers.put(registry.getId(), breaker);
        }
    }
    
    /// Enhanced parallel package resolution with circuit breakers and caching
    pub fn resolvePackage(self: *UnifiedRegistryManager, package_name: []const u8) !?Package {
        std.log.info("🔍 Resolving package: {s}", .{package_name});
        
        // Check cache first
        const cache_key = try std.fmt.allocPrint(self.allocator, "package:{s}", .{package_name});
        defer self.allocator.free(cache_key);
        
        if (try self.cache.get(cache_key)) |cached_package| {
            std.log.info("📦 Found cached package: {s}", .{package_name});
            return cached_package;
        }
        
        // Create futures for parallel resolution
        var futures = std.ArrayList(*zsync.Future(PackageResult)).init(self.allocator);
        defer {
            for (futures.items) |future| future.deinit();
            futures.deinit();
        }
        
        // Start parallel resolution across healthy registries
        for (self.registries.items) |*registry| {
            if (!registry.enabled) continue;
            
            // Check circuit breaker
            if (self.circuit_breakers.get(registry.getId())) |breaker| {
                if (!breaker.canExecute()) {
                    std.log.debug("⚡ Circuit breaker open for {s}", .{registry.name});
                    continue;
                }
            }
            
            const future = try self.resolveFromRegistryAsync(registry, package_name);
            try futures.append(future);
        }
        
        // Wait for first successful result with timeout
        const start_time = std.time.milliTimestamp();
        const timeout_ms = 30000; // 30 seconds total timeout
        
        for (futures.items) |future| {
            const elapsed = std.time.milliTimestamp() - start_time;
            if (elapsed > timeout_ms) {
                std.log.warn("⏰ Resolution timeout for package: {s}", .{package_name});
                break;
            }
            
            const result = try future.await();
            
            // Update circuit breaker and health metrics
            if (self.circuit_breakers.get(result.registry_id)) |breaker| {
                if (result.package != null) {
                    breaker.recordSuccess();
                    self.updateRegistryHealth(result.registry_id, true, result.response_time);
                } else {
                    breaker.recordFailure();
                    self.updateRegistryHealth(result.registry_id, false, result.response_time);
                }
            }
            
            if (result.package) |pkg| {
                // Cache the successful result
                try self.cache.put(cache_key, pkg, 3600); // Cache for 1 hour
                
                std.log.info("✅ Found package {s} from {s} in {}ms", .{ 
                    pkg.full_name, 
                    pkg.registry_name, 
                    result.response_time orelse 0 
                });
                return pkg;
            }
        }
        
        std.log.warn("❌ Package not found in any registry: {s}", .{package_name});
        return null;
    }
    
    /// Enhanced parallel search with result batching and deduplication
    pub fn searchPackages(self: *UnifiedRegistryManager, query: []const u8, max_results: usize) ![]Package {
        std.log.info("🔍 Searching packages: {s}", .{query});
        
        // Check cache first
        const cache_key = try std.fmt.allocPrint(self.allocator, "search:{s}:{d}", .{ query, max_results });
        defer self.allocator.free(cache_key);
        
        if (try self.cache.getSearchResults(cache_key)) |cached_results| {
            std.log.info("📦 Found cached search results for: {s}", .{query});
            return cached_results;
        }
        
        // Create futures for parallel search
        var search_futures = std.ArrayList(*zsync.Future(SearchResult)).init(self.allocator);
        defer {
            for (search_futures.items) |future| future.deinit();
            search_futures.deinit();
        }
        
        // Start parallel search across healthy registries
        for (self.registries.items) |*registry| {
            if (!registry.enabled) continue;
            
            // Check circuit breaker
            if (self.circuit_breakers.get(registry.getId())) |breaker| {
                if (!breaker.canExecute()) continue;
            }
            
            const future = try self.searchInRegistryAsync(registry, query, max_results);
            try search_futures.append(future);
        }
        
        // Collect and aggregate results with improved deduplication
        var result_map = std.HashMap([]const u8, Package).init(self.allocator);
        defer {
            var iterator = result_map.iterator();
            while (iterator.next()) |entry| {
                entry.value_ptr.deinit(self.allocator);
            }
            result_map.deinit();
        }
        
        const start_time = std.time.milliTimestamp();
        const timeout_ms = 15000; // 15 seconds for search
        
        for (search_futures.items) |future| {
            const elapsed = std.time.milliTimestamp() - start_time;
            if (elapsed > timeout_ms) break;
            
            const result = try future.await();
            
            // Update circuit breaker and health metrics
            if (self.circuit_breakers.get(result.registry_id)) |breaker| {
                if (result.packages != null) {
                    breaker.recordSuccess();
                    self.updateRegistryHealth(result.registry_id, true, result.response_time);
                } else {
                    breaker.recordFailure();
                    self.updateRegistryHealth(result.registry_id, false, result.response_time);
                }
            }
            
            if (result.packages) |packages| {
                defer self.allocator.free(packages);
                
                for (packages) |pkg| {
                    if (result_map.count() >= max_results) break;
                    
                    // Use better deduplication logic
                    const existing = result_map.getPtr(pkg.full_name);
                    if (existing == null) {
                        // New package - add it
                        const cloned_pkg = try pkg.clone(self.allocator);
                        try result_map.put(try self.allocator.dupe(u8, pkg.full_name), cloned_pkg);
                    } else if (existing.?.quality_score orelse 0 < pkg.quality_score orelse 0) {
                        // Better quality package - replace it
                        existing.?.deinit(self.allocator);
                        const cloned_pkg = try pkg.clone(self.allocator);
                        result_map.putAssumeCapacity(try self.allocator.dupe(u8, pkg.full_name), cloned_pkg);
                    }
                }
            }
        }
        
        // Convert to sorted array
        var final_results = std.ArrayList(Package).init(self.allocator);
        defer final_results.deinit();
        
        var iterator = result_map.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            try final_results.append(entry.value_ptr.*);
        }
        
        // Sort by quality and relevance
        std.sort.block(Package, final_results.items, {}, packageComparator);
        
        const results = final_results.toOwnedSlice();
        
        // Cache the results
        try self.cache.putSearchResults(cache_key, results, 1800); // Cache for 30 minutes
        
        std.log.info("📦 Found {} packages via unified search", .{results.len});
        return results;
    }
    
    /// Enhanced download with connection pooling and retry logic
    pub fn downloadPackage(self: *UnifiedRegistryManager, url: []const u8, dest_path: []const u8) !void {
        std.log.info("⬇️ Downloading: {s}", .{url});
        
        var retry_count: u32 = 0;
        const max_retries = 3;
        var backoff_ms: u64 = 1000;
        
        while (retry_count <= max_retries) {
            const client = try self.connection_pool.acquire();
            defer self.connection_pool.release(client);
            
            const start_time = std.time.milliTimestamp();
            
            const response = client.get(url) catch |err| {
                retry_count += 1;
                if (retry_count <= max_retries) {
                    std.log.warn("⚠️ Download failed (attempt {}/{}): {}", .{ retry_count, max_retries + 1, err });
                    std.time.sleep(backoff_ms * 1000000); // Convert to nanoseconds
                    backoff_ms *= 2; // Exponential backoff
                    continue;
                } else {
                    return err;
                }
            };
            defer response.deinit(self.allocator);
            
            const elapsed = std.time.milliTimestamp() - start_time;
            
            if (response.status_code != 200) {
                retry_count += 1;
                if (retry_count <= max_retries) {
                    std.log.warn("⚠️ HTTP error {} (attempt {}/{})", .{ response.status_code, retry_count, max_retries + 1 });
                    std.time.sleep(backoff_ms * 1000000);
                    backoff_ms *= 2;
                    continue;
                } else {
                    return error.DownloadFailed;
                }
            }
            
            if (response.body) |body| {
                const file = try std.fs.cwd().createFile(dest_path, .{});
                defer file.close();
                try file.writeAll(body);
                
                std.log.info("✅ Download complete: {s} ({} bytes in {}ms)", .{ dest_path, body.len, elapsed });
                return;
            } else {
                return error.EmptyResponse;
            }
        }
    }
    
    // Helper methods for async operations
    
    fn resolveFromRegistryAsync(self: *UnifiedRegistryManager, registry: *RegistryEndpoint, package_name: []const u8) !*zsync.Future(PackageResult) {
        const Task = struct {
            manager: *UnifiedRegistryManager,
            registry: *RegistryEndpoint,
            package_name: []const u8,
            
            fn run(task: @This()) PackageResult {
                const start_time = std.time.milliTimestamp();
                
                const result = task.manager.resolveFromRegistrySync(task.registry, task.package_name) catch |err| {
                    const elapsed = std.time.milliTimestamp() - start_time;
                    return PackageResult{
                        .package = null,
                        .registry_id = task.registry.getId(),
                        .response_time = @intCast(elapsed),
                        .error_msg = @errorName(err),
                    };
                };
                
                const elapsed = std.time.milliTimestamp() - start_time;
                return PackageResult{
                    .package = result.package,
                    .registry_id = task.registry.getId(),
                    .response_time = @intCast(elapsed),
                    .error_msg = result.error_msg,
                };
            }
        };
        
        const task = Task{
            .manager = self,
            .registry = registry,
            .package_name = package_name,
        };
        
        return try zsync.spawn(self.runtime, task, Task.run);
    }
    
    fn searchInRegistryAsync(self: *UnifiedRegistryManager, registry: *RegistryEndpoint, query: []const u8, max_results: usize) !*zsync.Future(SearchResult) {
        const Task = struct {
            manager: *UnifiedRegistryManager,
            registry: *RegistryEndpoint,
            query: []const u8,
            max_results: usize,
            
            fn run(task: @This()) SearchResult {
                const start_time = std.time.milliTimestamp();
                
                const result = task.manager.searchInRegistrySync(task.registry, task.query, task.max_results) catch |err| {
                    const elapsed = std.time.milliTimestamp() - start_time;
                    return SearchResult{
                        .packages = null,
                        .registry_id = task.registry.getId(),
                        .response_time = @intCast(elapsed),
                        .error_msg = @errorName(err),
                    };
                };
                
                const elapsed = std.time.milliTimestamp() - start_time;
                return SearchResult{
                    .packages = result.packages,
                    .registry_id = task.registry.getId(),
                    .response_time = @intCast(elapsed),
                    .error_msg = result.error_msg,
                };
            }
        };
        
        const task = Task{
            .manager = self,
            .registry = registry,
            .query = query,
            .max_results = max_results,
        };
        
        return try zsync.spawn(self.runtime, task, Task.run);
    }
    
    fn updateRegistryHealth(self: *UnifiedRegistryManager, registry_id: u32, success: bool, response_time: ?u64) void {
        for (self.registries.items) |*registry| {
            if (registry.getId() == registry_id) {
                registry.last_response_time = response_time;
                
                if (success) {
                    registry.failure_count = 0;
                    registry.health_score = @min(1.0, registry.health_score + 0.1);
                } else {
                    registry.failure_count += 1;
                    registry.health_score = @max(0.0, registry.health_score - 0.2);
                }
                break;
            }
        }
    }
    
    // Synchronous implementations for async wrappers
    
    fn resolveFromRegistrySync(self: *UnifiedRegistryManager, registry: *RegistryEndpoint, package_name: []const u8) !PackageResult {
        const client = try self.connection_pool.acquire();
        defer self.connection_pool.release(client);
        
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/packages/{s}", .{ registry.base_url, package_name });
        defer self.allocator.free(url);
        
        const response = try client.get(url);
        defer response.deinit(self.allocator);
        
        if (response.status_code == 200 and response.body != null) {
            // TODO: Parse JSON response and create Package
            return PackageResult{
                .package = null, // TODO: Parse JSON to Package
                .registry_id = registry.getId(),
                .response_time = null,
                .error_msg = null,
            };
        }
        
        return PackageResult{
            .package = null,
            .registry_id = registry.getId(),
            .response_time = null,
            .error_msg = "Package not found",
        };
    }
    
    fn searchInRegistrySync(self: *UnifiedRegistryManager, registry: *RegistryEndpoint, query: []const u8, max_results: usize) !SearchResult {
        const client = try self.connection_pool.acquire();
        defer self.connection_pool.release(client);
        
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/search?q={s}&limit={d}", .{ registry.base_url, query, max_results });
        defer self.allocator.free(url);
        
        const response = try client.get(url);
        defer response.deinit(self.allocator);
        
        if (response.status_code == 200 and response.body != null) {
            // TODO: Parse JSON response and create Package array
            return SearchResult{
                .packages = &[_]Package{},
                .registry_id = registry.getId(),
                .response_time = null,
                .error_msg = null,
            };
        }
        
        return SearchResult{
            .packages = null,
            .registry_id = registry.getId(),
            .response_time = null,
            .error_msg = "Search failed",
        };
    }
    
    fn packageComparator(context: void, a: Package, b: Package) bool {
        _ = context;
        
        // Ziglibs packages have highest priority
        if (a.is_ziglibs and !b.is_ziglibs) return true;
        if (!a.is_ziglibs and b.is_ziglibs) return false;
        
        // Then by quality score
        const a_score = a.quality_score orelse 0;
        const b_score = b.quality_score orelse 0;
        if (a_score != b_score) return a_score > b_score;
        
        // Then by star count
        const a_stars = a.star_count orelse 0;
        const b_stars = b.star_count orelse 0;
        return a_stars > b_stars;
    }
};

/// Connection Pool for HTTP client reuse
const ConnectionPool = struct {
    allocator: Allocator,
    connections: std.ArrayList(*http_client.HttpClient),
    available: std.ArrayList(*http_client.HttpClient),
    max_connections: usize,
    mutex: std.Thread.Mutex,
    
    fn init(allocator: Allocator, max_connections: usize) !*ConnectionPool {
        const pool = try allocator.create(ConnectionPool);
        pool.* = .{
            .allocator = allocator,
            .connections = std.ArrayList(*http_client.HttpClient).init(allocator),
            .available = std.ArrayList(*http_client.HttpClient).init(allocator),
            .max_connections = max_connections,
            .mutex = std.Thread.Mutex{},
        };
        
        // Pre-create connections
        for (0..max_connections) |_| {
            const client = try http_client.HttpClient.init(allocator, undefined);
            try pool.connections.append(client);
            try pool.available.append(client);
        }
        
        return pool;
    }
    
    fn deinit(self: *ConnectionPool) void {
        for (self.connections.items) |client| {
            client.deinit();
        }
        self.connections.deinit();
        self.available.deinit();
        self.allocator.destroy(self);
    }
    
    fn acquire(self: *ConnectionPool) !*http_client.HttpClient {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.available.items.len > 0) {
            return self.available.pop();
        }
        
        // All connections in use - create a temporary one
        return try http_client.HttpClient.init(self.allocator, undefined);
    }
    
    fn release(self: *ConnectionPool, client: *http_client.HttpClient) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Check if this is one of our pooled connections
        for (self.connections.items) |pooled_client| {
            if (client == pooled_client) {
                self.available.append(client) catch {
                    // If we can't add it back, just ignore
                };
                return;
            }
        }
        
        // This was a temporary connection - clean it up
        client.deinit();
    }
};

/// Circuit Breaker for registry health management
const CircuitBreaker = struct {
    failure_threshold: u32,
    timeout_ms: u64,
    failure_count: u32,
    last_failure_time: ?u64,
    state: State,
    
    const State = enum {
        Closed,
        Open,
        HalfOpen,
    };
    
    fn init(failure_threshold: u32, timeout_ms: u64) CircuitBreaker {
        return CircuitBreaker{
            .failure_threshold = failure_threshold,
            .timeout_ms = timeout_ms,
            .failure_count = 0,
            .last_failure_time = null,
            .state = .Closed,
        };
    }
    
    fn deinit(self: *CircuitBreaker) void {
        _ = self;
    }
    
    fn canExecute(self: *CircuitBreaker) bool {
        const now = std.time.milliTimestamp();
        
        switch (self.state) {
            .Closed => return true,
            .Open => {
                if (self.last_failure_time) |last_failure| {
                    if (now - last_failure > self.timeout_ms) {
                        self.state = .HalfOpen;
                        return true;
                    }
                }
                return false;
            },
            .HalfOpen => return true,
        }
    }
    
    fn recordSuccess(self: *CircuitBreaker) void {
        self.failure_count = 0;
        self.state = .Closed;
    }
    
    fn recordFailure(self: *CircuitBreaker) void {
        self.failure_count += 1;
        self.last_failure_time = std.time.milliTimestamp();
        
        if (self.failure_count >= self.failure_threshold) {
            self.state = .Open;
        }
    }
};

/// Async Cache for registry responses
const AsyncCache = struct {
    allocator: Allocator,
    cache: std.HashMap([]const u8, CacheEntry),
    search_cache: std.HashMap([]const u8, SearchCacheEntry),
    mutex: std.Thread.Mutex,
    
    const CacheEntry = struct {
        package: Package,
        expire_time: u64,
        
        fn isExpired(self: *const CacheEntry) bool {
            return std.time.milliTimestamp() > self.expire_time;
        }
    };
    
    const SearchCacheEntry = struct {
        packages: []Package,
        expire_time: u64,
        
        fn isExpired(self: *const SearchCacheEntry) bool {
            return std.time.milliTimestamp() > self.expire_time;
        }
    };
    
    fn init(allocator: Allocator) !*AsyncCache {
        const cache = try allocator.create(AsyncCache);
        cache.* = .{
            .allocator = allocator,
            .cache = std.HashMap([]const u8, CacheEntry).init(allocator),
            .search_cache = std.HashMap([]const u8, SearchCacheEntry).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
        return cache;
    }
    
    fn deinit(self: *AsyncCache) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clean up package cache
        var iterator = self.cache.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.package.deinit(self.allocator);
        }
        self.cache.deinit();
        
        // Clean up search cache
        var search_iterator = self.search_cache.iterator();
        while (search_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.packages) |pkg| {
                pkg.deinit(self.allocator);
            }
            self.allocator.free(entry.value_ptr.packages);
        }
        self.search_cache.deinit();
    }
    
    fn get(self: *AsyncCache, key: []const u8) !?Package {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.cache.get(key)) |entry| {
            if (!entry.isExpired()) {
                return try entry.package.clone(self.allocator);
            } else {
                // Remove expired entry
                _ = self.cache.remove(key);
                self.allocator.free(key);
                entry.package.deinit(self.allocator);
            }
        }
        
        return null;
    }
    
    fn put(self: *AsyncCache, key: []const u8, package: Package, ttl_seconds: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const expire_time = std.time.milliTimestamp() + (ttl_seconds * 1000);
        const entry = CacheEntry{
            .package = try package.clone(self.allocator),
            .expire_time = expire_time,
        };
        
        const owned_key = try self.allocator.dupe(u8, key);
        try self.cache.put(owned_key, entry);
    }
    
    fn getSearchResults(self: *AsyncCache, key: []const u8) !?[]Package {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.search_cache.get(key)) |entry| {
            if (!entry.isExpired()) {
                // Clone the packages
                var cloned_packages = try self.allocator.alloc(Package, entry.packages.len);
                for (entry.packages, 0..) |pkg, i| {
                    cloned_packages[i] = try pkg.clone(self.allocator);
                }
                return cloned_packages;
            } else {
                // Remove expired entry
                _ = self.search_cache.remove(key);
                self.allocator.free(key);
                for (entry.packages) |pkg| {
                    pkg.deinit(self.allocator);
                }
                self.allocator.free(entry.packages);
            }
        }
        
        return null;
    }
    
    fn putSearchResults(self: *AsyncCache, key: []const u8, packages: []Package, ttl_seconds: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const expire_time = std.time.milliTimestamp() + (ttl_seconds * 1000);
        
        // Clone packages for storage
        var cloned_packages = try self.allocator.alloc(Package, packages.len);
        for (packages, 0..) |pkg, i| {
            cloned_packages[i] = try pkg.clone(self.allocator);
        }
        
        const entry = SearchCacheEntry{
            .packages = cloned_packages,
            .expire_time = expire_time,
        };
        
        const owned_key = try self.allocator.dupe(u8, key);
        try self.search_cache.put(owned_key, entry);
    }
};

// Result structures for async operations
const PackageResult = struct {
    package: ?Package,
    registry_id: u32,
    response_time: ?u64,
    error_msg: ?[]const u8,
};

const SearchResult = struct {
    packages: ?[]Package,
    registry_id: u32,
    response_time: ?u64,
    error_msg: ?[]const u8,
};