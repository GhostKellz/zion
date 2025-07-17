const std = @import("std");
const zsync = @import("zsync");
const http_client = @import("http_client.zig");
const Allocator = std.mem.Allocator;
const ZionConfig = @import("registry_config.zig").ZionConfig;
const RegistryConfig = @import("registry_config.zig").RegistryConfig;
const Package = @import("registry_client.zig").Package;
const Release = @import("registry_client.zig").Release;

/// Enhanced Registry Manager v2.0 with standard HTTP client for v1.0.1
pub const EnhancedRegistryManager = struct {
    allocator: Allocator,
    config: *ZionConfig,
    http_client: *http_client.HttpClient,
    runtime: *zsync.Runtime,
    registries: std.ArrayList(RegistryEndpoint),
    
    const RegistryEndpoint = struct {
        name: []const u8,
        base_url: []const u8,
        api_token: ?[]const u8,
        enabled: bool,
        priority: u8,
    };
    
    pub fn init(allocator: Allocator, zion_config: *ZionConfig) !*EnhancedRegistryManager {
        var manager = try allocator.create(EnhancedRegistryManager);
        
        // Initialize zsync runtime for async operations
        const runtime = try allocator.create(zsync.Runtime);
        runtime.* = zsync.Runtime.init(allocator, .{});
        
        // Initialize standard HTTP client
        const http_client_instance = try http_client.HttpClient.init(allocator, runtime);
        
        manager.* = .{
            .allocator = allocator,
            .config = zion_config,
            .http_client = http_client_instance,
            .runtime = runtime,
            .registries = std.ArrayList(RegistryEndpoint).init(allocator),
        };
        
        try manager.initRegistries();
        return manager;
    }
    
    pub fn deinit(self: *EnhancedRegistryManager) void {
        for (self.registries.items) |registry| {
            self.allocator.free(registry.name);
            self.allocator.free(registry.base_url);
            if (registry.api_token) |token| self.allocator.free(token);
        }
        self.registries.deinit();
        
        self.http_client.deinit();
        self.runtime.deinit();
        self.allocator.destroy(self.runtime);
        self.allocator.destroy(self);
    }
    
    fn initRegistries(self: *EnhancedRegistryManager) !void {
        for (self.config.registries.items) |reg_config| {
            if (reg_config.enabled) {
                const endpoint = RegistryEndpoint{
                    .name = try self.allocator.dupe(u8, reg_config.name),
                    .base_url = try self.allocator.dupe(u8, reg_config.base_url),
                    .api_token = if (reg_config.auth_token) |token| try self.allocator.dupe(u8, token) else null,
                    .enabled = reg_config.enabled,
                    .priority = @intCast(reg_config.priority),
                };
                try self.registries.append(endpoint);
            }
        }
        
        // Sort by priority (lower number = higher priority)
        std.sort.block(RegistryEndpoint, self.registries.items, {}, struct {
            fn lessThan(context: void, a: RegistryEndpoint, b: RegistryEndpoint) bool {
                _ = context;
                return a.priority < b.priority;
            }
        }.lessThan);
    }
    
    /// Resolve package with HTTP client
    pub fn resolvePackage(self: *EnhancedRegistryManager, package_name: []const u8) !?Package {
        std.log.info("🔍 Resolving package: {s}", .{package_name});
        
        // Use parallel async resolution
        var futures = std.ArrayList(*zsync.Future(PackageResult)).init(self.allocator);
        defer {
            for (futures.items) |future| future.deinit();
            futures.deinit();
        }
        
        // Start parallel resolution across all registries
        for (self.registries.items) |registry| {
            const future = try self.resolveFromRegistryAsync(registry, package_name);
            try futures.append(future);
        }
        
        // Wait for first successful result
        for (futures.items) |future| {
            const result = try future.await();
            if (result.package) |pkg| {
                std.log.info("✅ Found package {s} from {s}", .{ pkg.full_name, pkg.registry_name });
                return pkg;
            }
        }
        
        std.log.warn("❌ Package not found in any registry: {s}", .{package_name});
        return null;
    }
    
    /// Enhanced search with parallel HTTP execution
    pub fn searchPackages(self: *EnhancedRegistryManager, query: []const u8, max_results: usize) ![]Package {
        std.log.info("🔍 Searching packages: {s}", .{query});
        
        var search_futures = std.ArrayList(*zsync.Future(SearchResult)).init(self.allocator);
        defer {
            for (search_futures.items) |future| future.deinit();
            search_futures.deinit();
        }
        
        // Start parallel search across all registries
        for (self.registries.items) |registry| {
            const future = try self.searchInRegistryAsync(registry, query);
            try search_futures.append(future);
        }
        
        // Collect and aggregate results
        var all_packages = std.ArrayList(Package).init(self.allocator);
        defer all_packages.deinit();
        
        for (search_futures.items) |future| {
            const result = try future.await();
            if (result.packages) |packages| {
                defer self.allocator.free(packages);
                
                for (packages) |pkg| {
                    if (all_packages.items.len >= max_results) break;
                    
                    // Check for duplicates
                    var is_duplicate = false;
                    for (all_packages.items) |existing| {
                        if (std.mem.eql(u8, existing.full_name, pkg.full_name)) {
                            is_duplicate = true;
                            break;
                        }
                    }
                    
                    if (!is_duplicate) {
                        try all_packages.append(pkg);
                    }
                }
            }
        }
        
        // Sort by quality and relevance
        std.sort.block(Package, all_packages.items, {}, packageComparator);
        
        std.log.info("📦 Found {} packages via HTTP", .{all_packages.items.len});
        return all_packages.toOwnedSlice();
    }
    
    /// Download package with HTTP client
    pub fn downloadPackage(self: *EnhancedRegistryManager, url: []const u8, dest_path: []const u8) !void {
        std.log.info("⬇️ Downloading: {s}", .{url});
        
        // Use HTTP client
        const response = try self.http_client.get(url);
        defer response.deinit(self.allocator);
        
        if (response.status_code != 200) {
            return error.DownloadFailed;
        }
        
        if (response.body) |body| {
            const file = try std.fs.cwd().createFile(dest_path, .{});
            defer file.close();
            try file.writeAll(body);
            
            std.log.info("✅ Download complete: {s} ({} bytes)", .{ dest_path, body.len });
        } else {
            return error.EmptyResponse;
        }
    }
    
    /// Enhanced package metadata with HTTP client
    pub fn getPackageMetadata(self: *EnhancedRegistryManager, full_name: []const u8) !?PackageMetadata {
        var parts = std.mem.splitScalar(u8, full_name, '/');
        const owner = parts.next() orelse return null;
        const repo = parts.next() orelse return null;
        
        // Use parallel metadata requests
        var metadata_futures = std.ArrayList(*zsync.Future(?PackageMetadata)).init(self.allocator);
        defer {
            for (metadata_futures.items) |future| future.deinit();
            metadata_futures.deinit();
        }
        
        for (self.registries.items) |registry| {
            const future = try self.fetchMetadataAsync(registry, owner, repo);
            try metadata_futures.append(future);
        }
        
        // Return first successful metadata
        for (metadata_futures.items) |future| {
            const metadata = try future.await();
            if (metadata) |meta| {
                return meta;
            }
        }
        
        return null;
    }
    
    // Async helper functions
    
    fn resolveFromRegistryAsync(self: *EnhancedRegistryManager, registry: RegistryEndpoint, package_name: []const u8) !*zsync.Future(PackageResult) {
        const Task = struct {
            manager: *EnhancedRegistryManager,
            registry: RegistryEndpoint,
            package_name: []const u8,
            
            fn run(task: @This()) PackageResult {
                return task.manager.resolveFromRegistrySync(task.registry, task.package_name) catch |err| PackageResult{
                    .package = null,
                    .registry_name = task.registry.name,
                    .error_msg = @errorName(err),
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
    
    fn searchInRegistryAsync(self: *EnhancedRegistryManager, registry: RegistryEndpoint, query: []const u8) !*zsync.Future(SearchResult) {
        const Task = struct {
            manager: *EnhancedRegistryManager,
            registry: RegistryEndpoint,
            query: []const u8,
            
            fn run(task: @This()) SearchResult {
                return task.manager.searchInRegistrySync(task.registry, task.query) catch |err| SearchResult{
                    .packages = null,
                    .registry_name = task.registry.name,
                    .error_msg = @errorName(err),
                };
            }
        };
        
        const task = Task{
            .manager = self,
            .registry = registry,
            .query = query,
        };
        
        return try zsync.spawn(self.runtime, task, Task.run);
    }
    
    fn fetchMetadataAsync(self: *EnhancedRegistryManager, registry: RegistryEndpoint, owner: []const u8, repo: []const u8) !*zsync.Future(?PackageMetadata) {
        const Task = struct {
            manager: *EnhancedRegistryManager,
            registry: RegistryEndpoint,
            owner: []const u8,
            repo: []const u8,
            
            fn run(task: @This()) ?PackageMetadata {
                return task.manager.fetchMetadataSync(task.registry, task.owner, task.repo) catch null;
            }
        };
        
        const task = Task{
            .manager = self,
            .registry = registry,
            .owner = owner,
            .repo = repo,
        };
        
        return try zsync.spawn(self.runtime, task, Task.run);
    }
    
    // Synchronous implementations for async wrappers
    
    fn resolveFromRegistrySync(self: *EnhancedRegistryManager, registry: RegistryEndpoint, package_name: []const u8) !PackageResult {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/packages/{s}", .{ registry.base_url, package_name });
        defer self.allocator.free(url);
        
        const response = try self.http_client.get(url);
        defer response.deinit(self.allocator);
        
        if (response.status_code == 200 and response.body != null) {
            // Parse JSON response and create Package
            // For now, return a basic result
            return PackageResult{
                .package = null, // TODO: Parse JSON to Package
                .registry_name = registry.name,
                .error_msg = null,
            };
        }
        
        return PackageResult{
            .package = null,
            .registry_name = registry.name,
            .error_msg = "Package not found",
        };
    }
    
    fn searchInRegistrySync(self: *EnhancedRegistryManager, registry: RegistryEndpoint, query: []const u8) !SearchResult {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/search?q={s}", .{ registry.base_url, query });
        defer self.allocator.free(url);
        
        const response = try self.http_client.get(url);
        defer response.deinit(self.allocator);
        
        if (response.status_code == 200 and response.body != null) {
            // Parse JSON response and create Package array
            // For now, return empty result
            return SearchResult{
                .packages = &[_]Package{},
                .registry_name = registry.name,
                .error_msg = null,
            };
        }
        
        return SearchResult{
            .packages = null,
            .registry_name = registry.name,
            .error_msg = "Search failed",
        };
    }
    
    fn fetchMetadataSync(self: *EnhancedRegistryManager, registry: RegistryEndpoint, owner: []const u8, repo: []const u8) !?PackageMetadata {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/packages/{s}/{s}/metadata", .{ registry.base_url, owner, repo });
        defer self.allocator.free(url);
        
        const response = try self.http_client.get(url);
        defer response.deinit(self.allocator);
        
        if (response.status_code == 200 and response.body != null) {
            // Parse JSON response and create PackageMetadata
            return PackageMetadata{
                .dependencies = &[_][]const u8{},
                .build_dependencies = &[_][]const u8{},
                .zig_version = null,
                .license = null,
                .homepage = null,
                .repository = null,
            };
        }
        
        return null;
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

// Result structures for async operations
const PackageResult = struct {
    package: ?Package,
    registry_name: []const u8,
    error_msg: ?[]const u8,
};

const SearchResult = struct {
    packages: ?[]Package,
    registry_name: []const u8,
    error_msg: ?[]const u8,
};

pub const PackageMetadata = struct {
    dependencies: [][]const u8,
    build_dependencies: [][]const u8,
    zig_version: ?[]const u8,
    license: ?[]const u8,
    homepage: ?[]const u8,
    repository: ?[]const u8,
};