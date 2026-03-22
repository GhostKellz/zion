const std = @import("std");
const http = std.http;
const json = std.json;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const enhanced_config = @import("enhanced_config.zig");
const RegistryConfig = enhanced_config.RegistryConfig;
const zion_root = @import("root.zig");

/// Package structure with enhanced metadata for v0.7.0
pub const Package = struct {
    name: []const u8,
    full_name: []const u8,
    description: ?[]const u8,
    version: []const u8,
    tarball_url: []const u8,
    sha256_hash: ?[]const u8,
    published_at: []const u8,
    registry_name: []const u8,

    // Enhanced metadata for v0.7.0
    license: ?[]const u8 = null,
    homepage: ?[]const u8 = null,
    repository_url: ?[]const u8 = null,
    author: ?[]const u8 = null,
    keywords: []const []const u8 = &[_][]const u8{},
    dependencies: []const Dependency = &[_]Dependency{},
    download_count: u64 = 0,
    stars: u64 = 0,
    last_updated: []const u8,
    zig_version_min: ?[]const u8 = null,
    zig_version_max: ?[]const u8 = null,
    categories: []const []const u8 = &[_][]const u8{},

    pub fn deinit(self: Package, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.full_name);
        if (self.description) |desc| allocator.free(desc);
        allocator.free(self.version);
        allocator.free(self.tarball_url);
        if (self.sha256_hash) |hash| allocator.free(hash);
        allocator.free(self.published_at);
        allocator.free(self.registry_name);

        // Free enhanced metadata
        if (self.license) |license| allocator.free(license);
        if (self.homepage) |homepage| allocator.free(homepage);
        if (self.repository_url) |repo_url| allocator.free(repo_url);
        if (self.author) |author| allocator.free(author);

        for (self.keywords) |keyword| {
            allocator.free(keyword);
        }
        if (self.keywords.len > 0) {
            allocator.free(self.keywords);
        }

        for (self.dependencies) |dep| {
            dep.deinit(allocator);
        }
        if (self.dependencies.len > 0) {
            allocator.free(self.dependencies);
        }

        allocator.free(self.last_updated);
        if (self.zig_version_min) |ver| allocator.free(ver);
        if (self.zig_version_max) |ver| allocator.free(ver);

        for (self.categories) |category| {
            allocator.free(category);
        }
        if (self.categories.len > 0) {
            allocator.free(self.categories);
        }
    }
};

/// Dependency structure for package resolution
pub const Dependency = struct {
    name: []const u8,
    version_requirement: []const u8,
    optional: bool = false,

    pub fn deinit(self: Dependency, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version_requirement);
    }
};

/// Release structure with enhanced metadata
pub const Release = struct {
    tag_name: []const u8,
    name: []const u8,
    published_at: []const u8,
    prerelease: bool,
    tarball_url: []const u8,
    zipball_url: ?[]const u8,

    // Enhanced metadata
    release_notes: ?[]const u8 = null,
    assets: []const Asset = &[_]Asset{},

    pub fn deinit(self: Release, allocator: std.mem.Allocator) void {
        allocator.free(self.tag_name);
        allocator.free(self.name);
        allocator.free(self.published_at);
        allocator.free(self.tarball_url);
        if (self.zipball_url) |url| allocator.free(url);
        if (self.release_notes) |notes| allocator.free(notes);

        for (self.assets) |asset| {
            asset.deinit(allocator);
        }
        if (self.assets.len > 0) {
            allocator.free(self.assets);
        }
    }
};

/// Asset structure for release assets
pub const Asset = struct {
    name: []const u8,
    download_url: []const u8,
    size: u64,
    content_type: []const u8,

    pub fn deinit(self: Asset, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.download_url);
        allocator.free(self.content_type);
    }
};

/// Search filters for enhanced discovery
pub const SearchFilters = struct {
    language: ?[]const u8 = "zig",
    license: ?[]const u8 = null,
    min_stars: ?u64 = null,
    categories: []const []const u8 = &[_][]const u8{},
    zig_version: ?[]const u8 = null,
    sort_by: SortOption = .relevance,
    order: SortOrder = .desc,
    per_page: u32 = 20,
    page: u32 = 1,
};

pub const SortOption = enum {
    relevance,
    stars,
    downloads,
    updated,
    created,
    name,
};

pub const SortOrder = enum {
    asc,
    desc,
};

/// Registry health metrics
pub const RegistryHealth = struct {
    name: []const u8,
    status: HealthStatus,
    response_time_ms: u64,
    last_checked: i64,
    uptime_percentage: f32,
    error_count: u32,

    pub const HealthStatus = enum {
        healthy,
        degraded,
        unhealthy,
        unknown,
    };
};

/// Enhanced Registry Client with v0.7.0 features
pub const RegistryClient = struct {
    allocator: Allocator,
    config: RegistryConfig,
    io: Io,
    http_client: std.http.Client,
    health_metrics: RegistryHealth,
    cache: ?PackageCache = null,

    pub fn init(allocator: Allocator, registry_config: RegistryConfig, io: Io) RegistryClient {
        return RegistryClient{
            .allocator = allocator,
            .config = registry_config,
            .io = io,
            .http_client = std.http.Client{ .allocator = allocator, .io = io },
            .health_metrics = RegistryHealth{
                .name = registry_config.name,
                .status = .unknown,
                .response_time_ms = 0,
                .last_checked = 0,
                .uptime_percentage = 100.0,
                .error_count = 0,
            },
        };
    }

    pub fn deinit(self: *RegistryClient) void {
        self.http_client.deinit();
        if (self.cache) |*cache| {
            cache.deinit();
        }
    }

    /// Enable caching for this registry client
    pub fn enableCache(self: *RegistryClient, cache_dir: []const u8, ttl_hours: u32) !void {
        self.cache = try PackageCache.init(self.allocator, cache_dir, ttl_hours);
    }

    /// Check registry health
    pub fn checkHealth(self: *RegistryClient) !void {
        const start_time = zion_root.milliTimestamp();

        const health_url = try std.fmt.allocPrint(self.allocator, "{s}/health", .{self.config.base_url});
        defer self.allocator.free(health_url);

        const response = self.makeRequest("GET", health_url, null) catch |err| {
            self.health_metrics.status = .unhealthy;
            self.health_metrics.error_count += 1;
            return err;
        };
        defer self.allocator.free(response);

        const end_time = zion_root.milliTimestamp();
        self.health_metrics.response_time_ms = @intCast(end_time - start_time);
        self.health_metrics.last_checked = end_time;
        self.health_metrics.status = .healthy;
    }

    /// Resolve short name to full name with caching
    pub fn resolveAlias(self: *RegistryClient, short_name: []const u8) !?[]const u8 {
        if (std.mem.indexOf(u8, short_name, "/") != null) {
            return try self.allocator.dupe(u8, short_name);
        }

        // Check cache first
        if (self.cache) |*cache| {
            if (try cache.getAlias(short_name)) |cached_name| {
                return cached_name;
            }
        }

        // Try registry-specific alias resolution
        const api_url = try self.config.getApiUrl(self.allocator);
        defer self.allocator.free(api_url);

        const resolve_url = try std.fmt.allocPrint(self.allocator, "{s}/resolve/{s}", .{ api_url, short_name });
        defer self.allocator.free(resolve_url);

        const response = self.makeRequest("GET", resolve_url, null) catch {
            return null;
        };
        defer self.allocator.free(response);

        const parsed = std.json.parseFromSlice(struct {
            full_name: []const u8,
            resolved: bool,
        }, self.allocator, response, .{}) catch return null;
        defer parsed.deinit();

        if (parsed.value.resolved) {
            const full_name = try self.allocator.dupe(u8, parsed.value.full_name);

            // Cache the result
            if (self.cache) |*cache| {
                try cache.putAlias(short_name, full_name);
            }

            return full_name;
        }

        return null;
    }

    /// Fetch package metadata with enhanced information
    pub fn fetchPackageMetadata(self: *RegistryClient, owner: []const u8, repo: []const u8) !Package {
        const api_url = try self.config.getApiUrl(self.allocator);
        defer self.allocator.free(api_url);

        const package_url = if (std.mem.eql(u8, self.config.name, "github"))
            try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}", .{ api_url, owner, repo })
        else if (std.mem.eql(u8, self.config.name, "zigistry"))
            try std.fmt.allocPrint(self.allocator, "{s}/api/packages/github/{s}/{s}", .{ api_url, owner, repo })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}/{s}", .{ api_url, owner, repo });
        defer self.allocator.free(package_url);

        const response = try self.makeRequest("GET", package_url, null);
        defer self.allocator.free(response);

        return try self.parsePackageMetadata(response, owner, repo);
    }

    /// Search packages with enhanced filters
    pub fn searchPackages(self: *RegistryClient, query: []const u8, filters: SearchFilters) ![]Package {
        const api_url = try self.config.getApiUrl(self.allocator);
        defer self.allocator.free(api_url);

        // Build search URL based on registry type
        const search_url = if (std.mem.eql(u8, self.config.name, "github"))
            try self.buildGitHubSearchUrl(api_url, query, filters)
        else if (std.mem.eql(u8, self.config.name, "zigistry"))
            try self.buildZigistrySearchUrl(api_url, query, filters)
        else
            try self.buildGenericSearchUrl(api_url, query, filters);
        defer self.allocator.free(search_url);

        const response = try self.makeRequest("GET", search_url, null);
        defer self.allocator.free(response);

        if (std.mem.eql(u8, self.config.name, "github")) {
            return try self.parseGitHubSearchResults(response);
        } else if (std.mem.eql(u8, self.config.name, "zigistry")) {
            return try self.parseZigistrySearchResults(response);
        } else {
            return try self.parseGenericSearchResults(response);
        }
    }

    /// Fetch releases for a package
    pub fn fetchReleases(self: *RegistryClient, owner: []const u8, repo: []const u8) ![]Release {
        const api_url = try self.config.getApiUrl(self.allocator);
        defer self.allocator.free(api_url);

        const releases_url = try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/releases", .{ api_url, owner, repo });
        defer self.allocator.free(releases_url);

        const response = self.makeRequest("GET", releases_url, null) catch {
            return &[_]Release{}; // Empty releases
        };
        defer self.allocator.free(response);

        // For now, return a mock release
        var releases = try self.allocator.alloc(Release, 1);
        releases[0] = Release{
            .tag_name = try self.allocator.dupe(u8, "v1.0.0"),
            .name = try self.allocator.dupe(u8, "Release 1.0.0"),
            .published_at = try self.allocator.dupe(u8, "2024-01-01"),
            .prerelease = false,
            .tarball_url = try self.allocator.dupe(u8, ""),
            .zipball_url = null,
        };
        return releases;
    }

    /// Fetch dependency graph for a package
    pub fn fetchDependencyGraph(self: *RegistryClient, owner: []const u8, repo: []const u8) ![]Dependency {
        const api_url = try self.config.getApiUrl(self.allocator);
        defer self.allocator.free(api_url);

        const deps_url = try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}/{s}/dependencies", .{ api_url, owner, repo });
        defer self.allocator.free(deps_url);

        const response = self.makeRequest("GET", deps_url, null) catch {
            return &[_]Dependency{}; // Empty dependencies
        };
        defer self.allocator.free(response);

        return try self.parseDependencies(response);
    }

    /// Make HTTP request with authentication and retry logic
    pub fn makeRequest(self: *RegistryClient, method: []const u8, url: []const u8, body: ?[]const u8) ![]const u8 {
        var retry_count: u32 = 0;
        const max_retries = 3;

        while (retry_count < max_retries) : (retry_count += 1) {
            const result = try self.makeRequestInternal(method, url, body);
            if (result.success) {
                return result.data;
            }

            // Exponential backoff
            const backoff_ms = std.math.pow(u32, 2, retry_count) * 1000;
            zion_root.sleep(backoff_ms * std.time.ns_per_ms);
        }

        return error.MaxRetriesExceeded;
    }

    fn makeRequestInternal(self: *RegistryClient, method: []const u8, url: []const u8, body: ?[]const u8) !struct { success: bool, data: []const u8 } {
        // For v0.7.0, we'll use a simplified HTTP approach
        // In a real implementation, you would use proper HTTP client with headers
        _ = method;
        _ = body;

        // Simulate HTTP request - in production, use actual HTTP client
        const logger = @import("logger.zig");
        logger.debug("Making request to: {s}", .{url});

        // Return mock data for now
        const mock_response = try self.allocator.dupe(u8, "{}");
        return .{ .success = true, .data = mock_response };
    }

    // URL builders for different registry types
    fn buildGitHubSearchUrl(self: *RegistryClient, api_url: []const u8, query: []const u8, filters: SearchFilters) ![]const u8 {
        var url_buffer: std.ArrayList(u8) = .empty;
        defer url_buffer.deinit(self.allocator);

        try url_buffer.appendSlice(self.allocator, api_url);
        try url_buffer.appendSlice(self.allocator, "/search/repositories?q=");
        try url_buffer.appendSlice(self.allocator, query);

        if (filters.language) |lang| {
            try url_buffer.appendSlice(self.allocator, "+language:");
            try url_buffer.appendSlice(self.allocator, lang);
        }

        if (filters.license) |license| {
            try url_buffer.appendSlice(self.allocator, "+license:");
            try url_buffer.appendSlice(self.allocator, license);
        }

        if (filters.min_stars) |min_stars| {
            try url_buffer.appendSlice(self.allocator, "+stars:>=");
            const stars_str = try std.fmt.allocPrint(self.allocator, "{d}", .{min_stars});
            defer self.allocator.free(stars_str);
            try url_buffer.appendSlice(self.allocator, stars_str);
        }

        const sort_field = switch (filters.sort_by) {
            .relevance => "",
            .stars => "stars",
            .downloads => "stars", // GitHub doesn't have downloads
            .updated => "updated",
            .created => "created",
            .name => "name",
        };

        if (sort_field.len > 0) {
            try url_buffer.appendSlice(self.allocator, "&sort=");
            try url_buffer.appendSlice(self.allocator, sort_field);
        }

        try url_buffer.appendSlice(self.allocator, "&order=");
        try url_buffer.appendSlice(self.allocator, if (filters.order == .desc) "desc" else "asc");

        const pagination_str = try std.fmt.allocPrint(self.allocator, "&per_page={d}&page={d}", .{ filters.per_page, filters.page });
        defer self.allocator.free(pagination_str);
        try url_buffer.appendSlice(self.allocator, pagination_str);

        return url_buffer.toOwnedSlice(self.allocator);
    }

    fn buildZigistrySearchUrl(self: *RegistryClient, api_url: []const u8, query: []const u8, filters: SearchFilters) ![]const u8 {
        var url_buffer: std.ArrayList(u8) = .empty;
        defer url_buffer.deinit(self.allocator);

        try url_buffer.appendSlice(self.allocator, api_url);
        try url_buffer.appendSlice(self.allocator, "/api/searchPackages?q=");
        try url_buffer.appendSlice(self.allocator, query);

        // Add Zigistry-specific filters
        if (filters.categories.len > 0) {
            try url_buffer.appendSlice(self.allocator, "&filter=");
            for (filters.categories, 0..) |category, i| {
                if (i > 0) try url_buffer.append(self.allocator, ',');
                try url_buffer.appendSlice(self.allocator, category);
            }
        }

        if (filters.zig_version) |version| {
            try url_buffer.appendSlice(self.allocator, "&zigVersion=");
            try url_buffer.appendSlice(self.allocator, version);
        }

        const limit_str = try std.fmt.allocPrint(self.allocator, "&limit={d}&offset={d}", .{
            filters.per_page,
            (filters.page - 1) * filters.per_page,
        });
        defer self.allocator.free(limit_str);
        try url_buffer.appendSlice(self.allocator, limit_str);

        return url_buffer.toOwnedSlice(self.allocator);
    }

    fn buildGenericSearchUrl(self: *RegistryClient, api_url: []const u8, query: []const u8, filters: SearchFilters) ![]const u8 {
        return try std.fmt.allocPrint(self.allocator, "{s}/search?q={s}&language={s}&sort={s}&order={s}&per_page={d}&page={d}", .{ api_url, query, filters.language orelse "zig", @tagName(filters.sort_by), @tagName(filters.order), filters.per_page, filters.page });
    }

    // Parsers for different response formats
    fn parsePackageMetadata(self: *RegistryClient, response: []const u8, owner: []const u8, repo: []const u8) !Package {
        _ = response;
        // This is a simplified parser - in reality, you'd need proper JSON parsing
        // based on the registry type
        const full_name = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ owner, repo });

        return Package{
            .name = try self.allocator.dupe(u8, repo),
            .full_name = full_name,
            .description = null,
            .version = try self.allocator.dupe(u8, "latest"),
            .tarball_url = try self.allocator.dupe(u8, ""),
            .sha256_hash = null,
            .published_at = try self.allocator.dupe(u8, ""),
            .registry_name = try self.allocator.dupe(u8, self.config.name),
            .last_updated = try self.allocator.dupe(u8, ""),
        };
    }

    fn parseGitHubSearchResults(self: *RegistryClient, response: []const u8) ![]Package {
        const parsed = try std.json.parseFromSlice(struct {
            items: []struct {
                name: []const u8,
                full_name: []const u8,
                description: ?[]const u8,
                updated_at: []const u8,
                clone_url: []const u8,
                stargazers_count: u64,
                license: ?struct { key: []const u8 },
                homepage: ?[]const u8,
                topics: [][]const u8,
            },
        }, self.allocator, response, .{});
        defer parsed.deinit();

        var packages: std.ArrayList(Package) = .empty;
        for (parsed.value.items) |item| {
            // Clone topics/categories
            var categories: std.ArrayList([]const u8) = .empty;
            for (item.topics) |topic| {
                try categories.append(self.allocator, try self.allocator.dupe(u8, topic));
            }

            try packages.append(self.allocator, Package{
                .name = try self.allocator.dupe(u8, item.name),
                .full_name = try self.allocator.dupe(u8, item.full_name),
                .description = if (item.description) |desc|
                    try self.allocator.dupe(u8, desc)
                else
                    null,
                .version = try self.allocator.dupe(u8, "latest"),
                .tarball_url = try self.allocator.dupe(u8, item.clone_url),
                .sha256_hash = null,
                .published_at = try self.allocator.dupe(u8, item.updated_at),
                .registry_name = try self.allocator.dupe(u8, self.config.name),
                .license = if (item.license) |lic|
                    try self.allocator.dupe(u8, lic.key)
                else
                    null,
                .homepage = if (item.homepage) |hp|
                    try self.allocator.dupe(u8, hp)
                else
                    null,
                .stars = item.stargazers_count,
                .last_updated = try self.allocator.dupe(u8, item.updated_at),
                .categories = try categories.toOwnedSlice(self.allocator),
            });
        }

        return packages.toOwnedSlice(self.allocator);
    }

    fn parseZigistrySearchResults(self: *RegistryClient, response: []const u8) ![]Package {
        // Parse Zigistry-specific response format
        const parsed = try std.json.parseFromSlice(struct {
            results: []struct {
                name: []const u8,
                description: ?[]const u8,
                version: []const u8,
                author: []const u8,
                repository: []const u8,
                downloads: u64,
                topics: [][]const u8,
            },
        }, self.allocator, response, .{});
        defer parsed.deinit();

        var packages: std.ArrayList(Package) = .empty;
        for (parsed.value.results) |result| {
            // Clone topics
            var categories: std.ArrayList([]const u8) = .empty;
            for (result.topics) |topic| {
                try categories.append(self.allocator, try self.allocator.dupe(u8, topic));
            }

            try packages.append(self.allocator, Package{
                .name = try self.allocator.dupe(u8, result.name),
                .full_name = try self.allocator.dupe(u8, result.name),
                .description = if (result.description) |desc|
                    try self.allocator.dupe(u8, desc)
                else
                    null,
                .version = try self.allocator.dupe(u8, result.version),
                .tarball_url = try self.allocator.dupe(u8, result.repository),
                .sha256_hash = null,
                .published_at = try self.allocator.dupe(u8, ""),
                .registry_name = try self.allocator.dupe(u8, self.config.name),
                .author = try self.allocator.dupe(u8, result.author),
                .download_count = result.downloads,
                .last_updated = try self.allocator.dupe(u8, ""),
                .categories = try categories.toOwnedSlice(self.allocator),
            });
        }

        return packages.toOwnedSlice(self.allocator);
    }

    fn parseGenericSearchResults(self: *RegistryClient, response: []const u8) ![]Package {
        const parsed = try std.json.parseFromSlice(struct {
            items: []Package,
        }, self.allocator, response, .{});
        defer parsed.deinit();

        // Deep clone packages
        var packages: std.ArrayList(Package) = .empty;
        for (parsed.value.items) |pkg| {
            // Clone all string fields
            var keywords: std.ArrayList([]const u8) = .empty;
            for (pkg.keywords) |kw| {
                try keywords.append(self.allocator, try self.allocator.dupe(u8, kw));
            }

            var categories: std.ArrayList([]const u8) = .empty;
            for (pkg.categories) |cat| {
                try categories.append(self.allocator, try self.allocator.dupe(u8, cat));
            }

            var dependencies: std.ArrayList(Dependency) = .empty;
            for (pkg.dependencies) |dep| {
                try dependencies.append(self.allocator, Dependency{
                    .name = try self.allocator.dupe(u8, dep.name),
                    .version_requirement = try self.allocator.dupe(u8, dep.version_requirement),
                    .optional = dep.optional,
                });
            }

            try packages.append(self.allocator, Package{
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
                .registry_name = try self.allocator.dupe(u8, self.config.name),
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
            });
        }

        return packages.toOwnedSlice(self.allocator);
    }

    fn parseDependencies(self: *RegistryClient, response: []const u8) ![]Dependency {
        const parsed = try std.json.parseFromSlice(struct {
            dependencies: []struct {
                name: []const u8,
                version: []const u8,
                optional: bool,
            },
        }, self.allocator, response, .{});
        defer parsed.deinit();

        var deps: std.ArrayList(Dependency) = .empty;
        for (parsed.value.dependencies) |dep| {
            try deps.append(self.allocator, Dependency{
                .name = try self.allocator.dupe(u8, dep.name),
                .version_requirement = try self.allocator.dupe(u8, dep.version),
                .optional = dep.optional,
            });
        }

        return deps.toOwnedSlice(self.allocator);
    }
};

/// Package cache for offline support and performance
pub const PackageCache = struct {
    allocator: Allocator,
    cache_dir: []const u8,
    ttl_hours: u32,

    pub fn init(allocator: Allocator, cache_dir: []const u8, ttl_hours: u32) !PackageCache {
        // Create cache directory if it doesn't exist
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();
        try cwd.createDirPath(io, cache_dir);

        return PackageCache{
            .allocator = allocator,
            .cache_dir = try allocator.dupe(u8, cache_dir),
            .ttl_hours = ttl_hours,
        };
    }

    pub fn deinit(self: *PackageCache) void {
        self.allocator.free(self.cache_dir);
    }

    pub fn getAlias(self: *PackageCache, short_name: []const u8) !?[]const u8 {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        const cache_file = try std.fmt.allocPrint(self.allocator, "{s}/aliases/{s}.json", .{ self.cache_dir, short_name });
        defer self.allocator.free(cache_file);

        const file = cwd.openFile(io, cache_file, .{}) catch return null;
        defer file.close(io);

        const stat = try file.stat(io);
        const now = zion_root.timestamp();
        const mtime_sec = stat.mtime.toSeconds();
        const age_hours: i64 = @divTrunc(now - mtime_sec, std.time.s_per_hour);

        if (age_hours > self.ttl_hours) {
            return null; // Cache expired
        }

        const file_size = try file.length(io);
        const content = try self.allocator.alloc(u8, file_size);
        _ = try file.readPositionalAll(io, content, 0);
        return content;
    }

    pub fn putAlias(self: *PackageCache, short_name: []const u8, full_name: []const u8) !void {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        const aliases_dir = try std.fmt.allocPrint(self.allocator, "{s}/aliases", .{self.cache_dir});
        defer self.allocator.free(aliases_dir);

        try cwd.createDirPath(io, aliases_dir);

        const cache_file = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ aliases_dir, short_name });
        defer self.allocator.free(cache_file);

        const file = try cwd.createFile(io, cache_file, .{});
        defer file.close(io);

        try file.writeStreamingAll(io, full_name);
    }
};
