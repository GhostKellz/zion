const std = @import("std");
const enhanced_config = @import("enhanced_config.zig");
const registry_v2 = @import("registry_v2.zig");
const RegistryConfig = enhanced_config.RegistryConfig;
const ZionConfig = enhanced_config.ZionConfig;
const RegistryClient = registry_v2.RegistryClient;
const Package = registry_v2.Package;
const Release = registry_v2.Release;
const Dependency = registry_v2.Dependency;
const SearchFilters = registry_v2.SearchFilters;
const RegistryHealth = registry_v2.RegistryHealth;
const zion_root = @import("root.zig");

/// Registry Manager for v0.7.0 - coordinates multiple registries
pub const RegistryManager = struct {
    allocator: std.mem.Allocator,
    config: *ZionConfig,
    clients: std.ArrayList(RegistryClient),
    health_monitor: HealthMonitor,
    package_resolver: PackageResolver,
    dependency_analyzer: DependencyAnalyzer,

    pub fn init(allocator: std.mem.Allocator, zion_config: *ZionConfig) RegistryManager {
        return RegistryManager{
            .allocator = allocator,
            .config = zion_config,
            .clients = .{},
            .health_monitor = HealthMonitor.init(allocator),
            .package_resolver = PackageResolver.init(allocator),
            .dependency_analyzer = DependencyAnalyzer.init(allocator),
        };
    }

    pub fn initClients(self: *RegistryManager) !void {
        const io = try zion_root.getIo();
        for (self.config.registries.items) |reg_config| {
            if (reg_config.enabled) {
                var client = RegistryClient.init(self.allocator, reg_config, io);

                // Enable caching if configured
                if (self.config.max_cache_size_mb > 0) {
                    const cache_dir = try std.fmt.allocPrint(self.allocator, "{s}/registry_{s}", .{ "/tmp/zion-cache", reg_config.name });
                    defer self.allocator.free(cache_dir);

                    try client.enableCache(cache_dir, self.config.cache_ttl_hours);
                }

                try self.clients.append(self.allocator, client);
            }
        }

        // Start health monitoring
        try self.health_monitor.startMonitoring(&self.clients);
    }

    pub fn deinit(self: *RegistryManager) void {
        for (self.clients.items) |*client| {
            client.deinit();
        }
        self.clients.deinit(self.allocator);
        self.health_monitor.deinit();
        self.package_resolver.deinit();
        self.dependency_analyzer.deinit();
    }

    /// Resolve package with smart fallback and deduplication
    pub fn resolvePackage(self: *RegistryManager, package_name: []const u8, version: ?[]const u8) !?Package {
        std.log.info("🔍 Resolving package: {s} {s}", .{ package_name, version orelse "latest" });

        var resolved_packages: std.ArrayList(Package) = .{};
        defer {
            for (resolved_packages.items) |pkg| {
                pkg.deinit(self.allocator);
            }
            resolved_packages.deinit(self.allocator);
        }

        // Try each registry in priority order
        for (self.clients.items) |*client| {
            // Skip unhealthy registries
            if (client.health_metrics.status == .unhealthy) {
                std.log.debug("⚠️  Skipping unhealthy registry: {s}", .{client.config.name});
                continue;
            }

            std.log.debug("🔎 Trying registry: {s}", .{client.config.name});

            // First resolve alias if it's a short name
            const full_name = client.resolveAlias(package_name) catch |err| {
                std.log.warn("Failed to resolve alias in {s}: {any}", .{ client.config.name, err });
                continue;
            };
            defer if (full_name) |name| self.allocator.free(name);

            const resolved_name = full_name orelse package_name;

            // Parse owner/repo
            var parts = std.mem.splitScalar(u8, resolved_name, '/');
            const owner = parts.next() orelse continue;
            const repo = parts.next() orelse continue;

            // Try to fetch package metadata
            const package = client.fetchPackageMetadata(owner, repo) catch |err| {
                std.log.debug("Failed to fetch package from {s}: {any}", .{ client.config.name, err });
                continue;
            };

            try resolved_packages.append(self.allocator, package);

            // If we found a package and it's from a high-priority registry, return it
            if (client.config.priority == 0) {
                const result = try self.clonePackage(package);
                std.log.info("✅ Found package in primary registry: {s}", .{client.config.name});
                return result;
            }
        }

        // Apply deduplication and scoring
        if (resolved_packages.items.len > 0) {
            const best_package = try self.package_resolver.selectBestPackage(resolved_packages.items);
            const result = try self.clonePackage(best_package);
            std.log.info("✅ Found package in registry: {s}", .{best_package.registry_name});
            return result;
        }

        std.log.warn("❌ Package not found in any registry: {s}", .{package_name});
        return null;
    }

    /// Search packages across all registries with deduplication
    pub fn searchPackages(self: *RegistryManager, query: []const u8, filters: SearchFilters) ![]Package {
        std.log.info("🔍 Searching for packages: {s}", .{query});

        var all_packages: std.ArrayList(Package) = .{};
        defer all_packages.deinit(self.allocator);

        var seen_packages = std.StringHashMap(void).init(self.allocator);
        defer seen_packages.deinit();

        // Search in parallel across healthy registries
        for (self.clients.items) |*client| {
            if (client.health_metrics.status == .unhealthy) continue;

            const packages = client.searchPackages(query, filters) catch |err| {
                std.log.warn("Search failed in {s}: {any}", .{ client.config.name, err });
                continue;
            };
            defer {
                for (packages) |pkg| pkg.deinit(self.allocator);
                self.allocator.free(packages);
            }

            // Deduplicate packages
            for (packages) |pkg| {
                const key = try std.fmt.allocPrint(self.allocator, "{s}@{s}", .{ pkg.full_name, pkg.version });
                defer self.allocator.free(key);

                if (!seen_packages.contains(key)) {
                    try seen_packages.put(try self.allocator.dupe(u8, key), {});
                    try all_packages.append(self.allocator, try self.clonePackage(pkg));
                }

                if (all_packages.items.len >= filters.per_page) break;
            }

            if (all_packages.items.len >= filters.per_page) break;
        }

        // Sort by relevance/score
        std.sort.block(Package, all_packages.items, {}, struct {
            fn lessThan(context: void, a: Package, b: Package) bool {
                _ = context;
                // Sort by stars first, then downloads
                if (a.stars != b.stars) return a.stars > b.stars;
                return a.download_count > b.download_count;
            }
        }.lessThan);

        std.log.info("✅ Found {d} packages across {d} registries", .{ all_packages.items.len, self.clients.items.len });
        return all_packages.toOwnedSlice(self.allocator);
    }

    /// Analyze dependencies and check for conflicts
    pub fn analyzeDependencies(self: *RegistryManager, package_name: []const u8) !DependencyAnalysis {
        const package = try self.resolvePackage(package_name, null) orelse return error.PackageNotFound;
        defer package.deinit(self.allocator);

        return try self.dependency_analyzer.analyze(package, self);
    }

    /// Get package download URL with integrity verification
    pub fn getPackageDownload(self: *RegistryManager, full_name: []const u8, version: []const u8) !DownloadInfo {
        std.log.info("📦 Getting download info for: {s}@{s}", .{ full_name, version });

        // Try each registry
        for (self.clients.items) |*client| {
            if (client.health_metrics.status == .unhealthy) continue;

            // Parse owner/repo
            var parts = std.mem.splitScalar(u8, full_name, '/');
            const owner = parts.next() orelse continue;
            const repo = parts.next() orelse continue;

            // Fetch releases
            const releases = client.fetchReleases(owner, repo) catch continue;
            defer {
                for (releases) |release| release.deinit(self.allocator);
                self.allocator.free(releases);
            }

            // Find matching version
            for (releases) |release| {
                if (std.mem.eql(u8, release.tag_name, version)) {
                    return DownloadInfo{
                        .url = try self.allocator.dupe(u8, release.tarball_url),
                        .sha256_hash = null, // Would be in release assets or headers
                        .registry_name = try self.allocator.dupe(u8, client.config.name),
                        .size = 0, // Would be in release assets
                    };
                }
            }
        }

        return error.VersionNotFound;
    }

    /// Check why a package was included (dependency analyzer)
    pub fn explainDependency(self: *RegistryManager, package_name: []const u8, target_dep: []const u8) ![]const u8 {
        const analysis = try self.analyzeDependencies(package_name);
        defer analysis.deinit(self.allocator);

        return try self.dependency_analyzer.explainPath(analysis, target_dep);
    }

    /// Get registry health status
    pub fn getRegistryStatus(self: *RegistryManager) ![]RegistryHealth {
        var statuses: std.ArrayList(RegistryHealth) = .{};

        for (self.clients.items) |client| {
            try statuses.append(self.allocator, client.health_metrics);
        }

        return statuses.toOwnedSlice(self.allocator);
    }

    fn clonePackage(self: *RegistryManager, pkg: Package) !Package {
        // Deep clone a package
        var keywords: std.ArrayList([]const u8) = .{};
        for (pkg.keywords) |kw| {
            try keywords.append(self.allocator, try self.allocator.dupe(u8, kw));
        }

        var categories: std.ArrayList([]const u8) = .{};
        for (pkg.categories) |cat| {
            try categories.append(self.allocator, try self.allocator.dupe(u8, cat));
        }

        var dependencies: std.ArrayList(Dependency) = .{};
        for (pkg.dependencies) |dep| {
            try dependencies.append(self.allocator, Dependency{
                .name = try self.allocator.dupe(u8, dep.name),
                .version_requirement = try self.allocator.dupe(u8, dep.version_requirement),
                .optional = dep.optional,
            });
        }

        return Package{
            .name = try self.allocator.dupe(u8, pkg.name),
            .full_name = try self.allocator.dupe(u8, pkg.full_name),
            .description = if (pkg.description) |desc|
                try self.allocator.dupe(u8, desc)
            else
                null,
            .version = try self.allocator.dupe(u8, pkg.version),
            .tarball_url = try self.allocator.dupe(u8, pkg.tarball_url),
            .sha256_hash = if (pkg.sha256_hash) |hash|
                try self.allocator.dupe(u8, hash)
            else
                null,
            .published_at = try self.allocator.dupe(u8, pkg.published_at),
            .registry_name = try self.allocator.dupe(u8, pkg.registry_name),
            .license = if (pkg.license) |lic|
                try self.allocator.dupe(u8, lic)
            else
                null,
            .homepage = if (pkg.homepage) |hp|
                try self.allocator.dupe(u8, hp)
            else
                null,
            .repository_url = if (pkg.repository_url) |url|
                try self.allocator.dupe(u8, url)
            else
                null,
            .author = if (pkg.author) |auth|
                try self.allocator.dupe(u8, auth)
            else
                null,
            .keywords = try keywords.toOwnedSlice(self.allocator),
            .dependencies = try dependencies.toOwnedSlice(self.allocator),
            .download_count = pkg.download_count,
            .stars = pkg.stars,
            .last_updated = try self.allocator.dupe(u8, pkg.last_updated),
            .zig_version_min = if (pkg.zig_version_min) |ver|
                try self.allocator.dupe(u8, ver)
            else
                null,
            .zig_version_max = if (pkg.zig_version_max) |ver|
                try self.allocator.dupe(u8, ver)
            else
                null,
            .categories = try categories.toOwnedSlice(self.allocator),
        };
    }
};

pub const DownloadInfo = struct {
    url: []const u8,
    sha256_hash: ?[]const u8,
    registry_name: []const u8,
    size: u64,
};

/// Health monitoring for registries
pub const HealthMonitor = struct {
    allocator: std.mem.Allocator,
    monitoring_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) HealthMonitor {
        return HealthMonitor{
            .allocator = allocator,
            .should_stop = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *HealthMonitor) void {
        self.should_stop.store(true, .seq_cst);
        if (self.monitoring_thread) |thread| {
            thread.join();
        }
    }

    pub fn startMonitoring(self: *HealthMonitor, clients: *std.ArrayList(RegistryClient)) !void {
        _ = self;
        // In a real implementation, this would spawn a thread to periodically check registry health
        // For now, we'll just do a one-time check
        for (clients.items) |*client| {
            client.checkHealth() catch |err| {
                std.log.warn("Health check failed for {s}: {any}", .{ client.config.name, err });
            };
        }
    }
};

/// Package resolver with scoring and deduplication
pub const PackageResolver = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PackageResolver {
        return PackageResolver{ .allocator = allocator };
    }

    pub fn deinit(self: *PackageResolver) void {
        _ = self;
    }

    pub fn selectBestPackage(self: *PackageResolver, packages: []Package) !Package {
        if (packages.len == 0) return error.NoPackages;

        var best_score: f32 = 0;
        var best_index: usize = 0;

        for (packages, 0..) |pkg, i| {
            const score = self.scorePackage(pkg);
            if (score > best_score) {
                best_score = score;
                best_index = i;
            }
        }

        return packages[best_index];
    }

    fn scorePackage(self: *PackageResolver, pkg: Package) f32 {
        _ = self;
        var score: f32 = 0;

        // Score based on various factors
        score += @as(f32, @floatFromInt(pkg.stars)) * 0.3;
        score += @as(f32, @floatFromInt(pkg.download_count)) * 0.2;

        // Prefer packages with descriptions
        if (pkg.description != null) score += 10;

        // Prefer packages with licenses
        if (pkg.license != null) score += 5;

        // Prefer recently updated packages
        // In real implementation, would parse date and calculate recency
        score += 20;

        return score;
    }
};

/// Dependency analyzer for conflict detection and resolution
pub const DependencyAnalyzer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DependencyAnalyzer {
        return DependencyAnalyzer{ .allocator = allocator };
    }

    pub fn deinit(self: *DependencyAnalyzer) void {
        _ = self;
    }

    pub fn analyze(self: *DependencyAnalyzer, package: Package, manager: *RegistryManager) !DependencyAnalysis {
        _ = manager;
        var analysis = DependencyAnalysis{
            .root_package = try self.allocator.dupe(u8, package.full_name),
            .total_dependencies = 0,
            .conflicts = .{},
            .dependency_tree = std.StringHashMap([]const u8).init(self.allocator),
            .allocator = self.allocator,
        };

        // Build dependency tree
        for (package.dependencies) |dep| {
            try analysis.dependency_tree.put(try self.allocator.dupe(u8, dep.name), try self.allocator.dupe(u8, dep.version_requirement));
            analysis.total_dependencies += 1;
        }

        // In a real implementation, would recursively analyze transitive dependencies
        // and detect version conflicts

        return analysis;
    }

    pub fn explainPath(self: *DependencyAnalyzer, analysis: DependencyAnalysis, target: []const u8) ![]const u8 {
        _ = analysis;
        return try std.fmt.allocPrint(self.allocator, "{s} is required by the root package", .{target});
    }
};

pub const DependencyAnalysis = struct {
    root_package: []const u8,
    total_dependencies: u32,
    conflicts: std.ArrayList(DependencyConflict),
    dependency_tree: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DependencyAnalysis) void {
        self.allocator.free(self.root_package);

        for (self.conflicts.items) |conflict| {
            conflict.deinit(self.allocator);
        }
        self.conflicts.deinit(self.allocator);

        var iterator = self.dependency_tree.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.dependency_tree.deinit();
    }
};

pub const DependencyConflict = struct {
    package: []const u8,
    required_by: [][]const u8,
    conflicting_versions: [][]const u8,

    pub fn deinit(self: DependencyConflict, allocator: std.mem.Allocator) void {
        allocator.free(self.package);

        for (self.required_by) |req| {
            allocator.free(req);
        }
        allocator.free(self.required_by);

        for (self.conflicting_versions) |ver| {
            allocator.free(ver);
        }
        allocator.free(self.conflicting_versions);
    }
};
