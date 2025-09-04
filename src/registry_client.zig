const std = @import("std");
const http = std.http;
const json = std.json;
const Allocator = std.mem.Allocator;
const RegistryConfig = @import("registry_config.zig").RegistryConfig;

pub const Package = struct {
    name: []const u8,
    full_name: []const u8,
    description: ?[]const u8,
    version: []const u8,
    tarball_url: []const u8,
    sha256_hash: ?[]const u8,
    published_at: []const u8,
    registry_name: []const u8,
    
    // Ziglibs metadata
    is_ziglibs: bool = false,
    quality_score: ?u8 = null,
    maintenance_status: ?[]const u8 = null,
    
    // Zigistry metadata  
    download_count: ?u64 = null,
    star_count: ?u32 = null,
    rating: ?f32 = null,
    
    pub fn deinit(self: Package, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.full_name);
        if (self.description) |desc| allocator.free(desc);
        allocator.free(self.version);
        allocator.free(self.tarball_url);
        if (self.sha256_hash) |hash| allocator.free(hash);
        allocator.free(self.published_at);
        allocator.free(self.registry_name);
        if (self.maintenance_status) |status| allocator.free(status);
    }
};

pub const Release = struct {
    tag_name: []const u8,
    name: []const u8,
    published_at: []const u8,
    prerelease: bool,
    tarball_url: []const u8,
    zipball_url: ?[]const u8,
    
    pub fn deinit(self: Release, allocator: Allocator) void {
        allocator.free(self.tag_name);
        allocator.free(self.name);
        allocator.free(self.published_at);
        allocator.free(self.tarball_url);
        if (self.zipball_url) |url| allocator.free(url);
    }
};

pub const RegistryClient = struct {
    allocator: Allocator,
    config: RegistryConfig,
    http_client: http.Client,
    
    pub fn init(allocator: Allocator, registry_config: RegistryConfig) RegistryClient {
        return RegistryClient{
            .allocator = allocator,
            .config = registry_config,
            .http_client = http.Client{ .allocator = allocator },
        };
    }
    
    pub fn deinit(self: *RegistryClient) void {
        self.http_client.deinit();
    }
    
    /// Resolve short name to full name (e.g., "zcrypto" -> "cktech/zcrypto")
    pub fn resolveAlias(self: *RegistryClient, short_name: []const u8) !?[]const u8 {
        if (std.mem.indexOf(u8, short_name, "/") != null) {
            // Already a full name, return as-is
            return try self.allocator.dupe(u8, short_name);
        }
        
        // For Ziglibs packages, try common prefixes
        if (std.mem.eql(u8, self.config.name, "zigistry")) {
            // Try ziglibs prefix first
            const ziglibs_name = try std.fmt.allocPrint(self.allocator, "ziglibs/{s}", .{short_name});
            defer self.allocator.free(ziglibs_name);
            
            if (try self.packageExists(ziglibs_name)) {
                return try self.allocator.dupe(u8, ziglibs_name);
            }
        }
        
        // Try registry-specific alias resolution
        const api_url = try self.config.getApiUrl(self.allocator);
        defer self.allocator.free(api_url);
        
        const resolve_url = try std.fmt.allocPrint(self.allocator, 
            "{s}/resolve/{s}", .{ api_url, short_name });
        defer self.allocator.free(resolve_url);
        
        const response = self.makeRequest("GET", resolve_url, null) catch |err| switch (err) {
            error.HttpRequestFailed => return null, // 404 or other error
            else => return err,
        };
        defer self.allocator.free(response);
        
        // Parse JSON response
        const parsed = json.parseFromSlice(struct {
            full_name: []const u8,
            resolved: bool,
        }, self.allocator, response, .{}) catch return null;
        defer parsed.deinit();
        
        if (parsed.value.resolved) {
            return try self.allocator.dupe(u8, parsed.value.full_name);
        }
        
        return null;
    }
    
    /// Check if package exists (for alias resolution)
    fn packageExists(self: *RegistryClient, full_name: []const u8) !bool {
        var parts = std.mem.splitScalar(u8, full_name, '/');
        const owner = parts.next() orelse return false;
        const repo = parts.next() orelse return false;
        
        const releases = self.fetchReleases(owner, repo) catch return false;
        defer {
            for (releases) |release| release.deinit(self.allocator);
            self.allocator.free(releases);
        }
        
        return releases.len > 0;
    }
    
    /// Fetch package releases
    pub fn fetchReleases(self: *RegistryClient, owner: []const u8, repo: []const u8) ![]Release {
        const api_url = try self.config.getApiUrl(self.allocator);
        defer self.allocator.free(api_url);
        
        const releases_url = if (std.mem.eql(u8, self.config.name, "github")) 
            try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/releases", .{ api_url, owner, repo })
        else if (std.mem.eql(u8, self.config.name, "zigistry"))
            try std.fmt.allocPrint(self.allocator, "{s}/api/packages/github/{s}/{s}", .{ api_url, owner, repo })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}/{s}/releases", .{ api_url, owner, repo });
        defer self.allocator.free(releases_url);
        
        const response = try self.makeRequest("GET", releases_url, null);
        defer self.allocator.free(response);
        
        // Parse JSON array of releases
        const parsed = try json.parseFromSlice([]Release, self.allocator, response, .{});
        defer parsed.deinit();
        
        // Deep clone the releases
        var releases: std.ArrayList(Release) = .{};
        for (parsed.value) |release| {
            try releases.append(self.allocator, Release{
                .tag_name = try self.allocator.dupe(u8, release.tag_name),
                .name = try self.allocator.dupe(u8, release.name),
                .published_at = try self.allocator.dupe(u8, release.published_at),
                .prerelease = release.prerelease,
                .tarball_url = try self.allocator.dupe(u8, release.tarball_url),
                .zipball_url = if (release.zipball_url) |url| 
                    try self.allocator.dupe(u8, url) else null,
            });
        }
        
        return releases.toOwnedSlice(self.allocator);
    }
    
    /// Search packages with enhanced metadata
    pub fn searchPackages(self: *RegistryClient, query: []const u8, language: ?[]const u8) ![]Package {
        const api_url = try self.config.getApiUrl(self.allocator);
        defer self.allocator.free(api_url);
        
        const search_url = if (std.mem.eql(u8, self.config.name, "github"))
            try std.fmt.allocPrint(self.allocator, "{s}/search/repositories?q={s}+language:{s}", 
                .{ api_url, query, language orelse "zig" })
        else if (std.mem.eql(u8, self.config.name, "zigistry"))
            try std.fmt.allocPrint(self.allocator, "{s}/api/searchPackages?q={s}", 
                .{ api_url, query })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/search?q={s}&language={s}", 
                .{ api_url, query, language orelse "zig" });
        defer self.allocator.free(search_url);
        
        const response = try self.makeRequest("GET", search_url, null);
        defer self.allocator.free(response);
        
        // Parse search results based on registry type
        if (std.mem.eql(u8, self.config.name, "github")) {
            return try self.parseGitHubSearchResults(response);
        } else if (std.mem.eql(u8, self.config.name, "zigistry")) {
            return try self.parseZigistrySearchResults(response);
        } else {
            return try self.parseZepplinSearchResults(response);
        }
    }
    
    /// Make HTTP request with authentication
    fn makeRequest(self: *RegistryClient, method: []const u8, url: []const u8, body: ?[]const u8) ![]const u8 {
        _ = method;
        _ = url;
        _ = body;
        
        // TODO: Implement HTTP requests using current Zig HTTP API
        // For now, return mock response to get the build working
        return try self.allocator.dupe(u8, "{\"items\": []}");
    }
    
    fn parseGitHubSearchResults(self: *RegistryClient, response: []const u8) ![]Package {
        const parsed = try json.parseFromSlice(struct {
            items: []struct {
                name: []const u8,
                full_name: []const u8,
                description: ?[]const u8,
                updated_at: []const u8,
                clone_url: []const u8,
                stargazers_count: ?u32,
            },
        }, self.allocator, response, .{});
        defer parsed.deinit();
        
        var packages: std.ArrayList(Package) = .{};
        for (parsed.value.items) |item| {
            try packages.append(self.allocator, Package{
                .name = try self.allocator.dupe(u8, item.name),
                .full_name = try self.allocator.dupe(u8, item.full_name),
                .description = if (item.description) |desc| 
                    try self.allocator.dupe(u8, desc) else null,
                .version = try self.allocator.dupe(u8, "latest"),
                .tarball_url = try self.allocator.dupe(u8, item.clone_url),
                .sha256_hash = null,
                .published_at = try self.allocator.dupe(u8, item.updated_at),
                .registry_name = try self.allocator.dupe(u8, self.config.name),
                .star_count = item.stargazers_count,
            });
        }
        
        return packages.toOwnedSlice(self.allocator);
    }
    
    fn parseZigistrySearchResults(self: *RegistryClient, response: []const u8) ![]Package {
        const parsed = try json.parseFromSlice(struct {
            packages: []struct {
                name: []const u8,
                full_name: []const u8,
                description: ?[]const u8,
                version: []const u8,
                download_url: []const u8,
                published_at: []const u8,
                download_count: ?u64,
                rating: ?f32,
                // Ziglibs detection
                owner: []const u8,
            },
        }, self.allocator, response, .{});
        defer parsed.deinit();
        
        var packages: std.ArrayList(Package) = .{};
        for (parsed.value.packages) |pkg| {
            const is_ziglibs = std.mem.eql(u8, pkg.owner, "ziglibs");
            
            try packages.append(self.allocator, Package{
                .name = try self.allocator.dupe(u8, pkg.name),
                .full_name = try self.allocator.dupe(u8, pkg.full_name),
                .description = if (pkg.description) |desc| 
                    try self.allocator.dupe(u8, desc) else null,
                .version = try self.allocator.dupe(u8, pkg.version),
                .tarball_url = try self.allocator.dupe(u8, pkg.download_url),
                .sha256_hash = null,
                .published_at = try self.allocator.dupe(u8, pkg.published_at),
                .registry_name = try self.allocator.dupe(u8, self.config.name),
                .is_ziglibs = is_ziglibs,
                .quality_score = if (is_ziglibs) @as(?u8, 95) else null, // High quality for ziglibs
                .maintenance_status = if (is_ziglibs) 
                    try self.allocator.dupe(u8, "well-maintained") else null,
                .download_count = pkg.download_count,
                .rating = pkg.rating,
            });
        }
        
        return packages.toOwnedSlice(self.allocator);
    }
    
    fn parseZepplinSearchResults(self: *RegistryClient, response: []const u8) ![]Package {
        const parsed = try json.parseFromSlice(struct {
            items: []Package,
        }, self.allocator, response, .{});
        defer parsed.deinit();
        
        // Deep clone packages
        var packages: std.ArrayList(Package) = .{};
        for (parsed.value.items) |pkg| {
            try packages.append(self.allocator, Package{
                .name = try self.allocator.dupe(u8, pkg.name),
                .full_name = try self.allocator.dupe(u8, pkg.full_name),
                .description = if (pkg.description) |desc| 
                    try self.allocator.dupe(u8, desc) else null,
                .version = try self.allocator.dupe(u8, pkg.version),
                .tarball_url = try self.allocator.dupe(u8, pkg.tarball_url),
                .sha256_hash = if (pkg.sha256_hash) |hash| 
                    try self.allocator.dupe(u8, hash) else null,
                .published_at = try self.allocator.dupe(u8, pkg.published_at),
                .registry_name = try self.allocator.dupe(u8, self.config.name),
            });
        }
        
        return packages.toOwnedSlice(self.allocator);
    }
};
