const std = @import("std");
const zsync = @import("zsync");
const Allocator = std.mem.Allocator;
const ZionConfig = @import("registry_config.zig").ZionConfig;
const RegistryConfig = @import("registry_config.zig").RegistryConfig;
const RegistryClient = @import("registry_client.zig").RegistryClient;
const Package = @import("registry_client.zig").Package;
const Release = @import("registry_client.zig").Release;

/// Enhanced Registry Manager with zsync async support for v1.1.0
pub const RegistryManager = struct {
    allocator: Allocator,
    config: *ZionConfig,
    clients: std.ArrayList(RegistryClient),
    io: zsync.ThreadPoolIo,
    
    pub fn init(allocator: Allocator, zion_config: *ZionConfig) !RegistryManager {
        return RegistryManager{
            .allocator = allocator,
            .config = zion_config,
            .clients = std.ArrayList(RegistryClient).init(allocator),
            .io = try zsync.ThreadPoolIo.init(allocator, .{}),
        };
    }
    
    pub fn initClients(self: *RegistryManager) !void {
        for (self.config.registries.items) |reg_config| {
            if (reg_config.enabled) {
                const client = RegistryClient.init(self.allocator, reg_config);
                try self.clients.append(client);
            }
        }
    }
    
    pub fn deinit(self: *RegistryManager) void {
        for (self.clients.items) |*client| {
            client.deinit();
        }
        self.clients.deinit();
        self.io.deinit();
    }
    
    /// Resolve package with registry priority and async support
    pub fn resolvePackage(self: *RegistryManager, package_name: []const u8) !?Package {
        std.log.info("🔍 Resolving package: {s}", .{package_name});
        
        // For now, use sequential resolution with priority order
        // TODO: Implement proper async resolution with zsync Future API
        for (self.clients.items) |*client| {
            const result = resolveFromRegistry(client, package_name) catch |err| {
                std.log.debug("❌ {s}: {}", .{ client.config.name, err });
                continue;
            };
            
            if (result.package) |pkg| {
                std.log.info("✅ Found package {s} from {s}", .{ pkg.full_name, pkg.registry_name });
                return pkg;
            } else if (result.error_msg) |err| {
                std.log.debug("❌ {s}: {s}", .{ result.registry_name, err });
            }
        }
        
        std.log.warn("❌ Package not found in any registry: {s}", .{package_name});
        return null;
    }
    
    /// Async search across all registries with result aggregation
    pub fn searchPackages(self: *RegistryManager, query: []const u8, max_results: usize) ![]Package {
        std.log.info("🔍 Searching for: {s}", .{query});
        
        // For now, use sequential search across registries
        // TODO: Implement proper async search with zsync Future API
        var all_packages = std.ArrayList(Package).init(self.allocator);
        defer all_packages.deinit();
        
        for (self.clients.items) |*client| {
            const result = searchInRegistry(client, query) catch |err| {
                std.log.warn("Search failed in {s}: {}", .{ client.config.name, err });
                continue;
            };
            
            if (result.packages) |packages| {
                defer self.allocator.free(packages);
                
                for (packages) |pkg| {
                    if (all_packages.items.len >= max_results) break;
                    
                    // Check for duplicates by full_name
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
        
        // Sort by relevance (Ziglibs first, then by star count/downloads)
        std.sort.block(Package, all_packages.items, {}, struct {
            fn lessThan(context: void, a: Package, b: Package) bool {
                _ = context;
                
                // Ziglibs packages have highest priority
                if (a.is_ziglibs and !b.is_ziglibs) return true;
                if (!a.is_ziglibs and b.is_ziglibs) return false;
                
                // Then by star count
                const a_stars = a.star_count orelse 0;
                const b_stars = b.star_count orelse 0;
                if (a_stars != b_stars) return a_stars > b_stars;
                
                // Then by download count
                const a_downloads = a.download_count orelse 0;
                const b_downloads = b.download_count orelse 0;
                return a_downloads > b_downloads;
            }
        }.lessThan);
        
        std.log.info("📦 Found {} packages", .{all_packages.items.len});
        return all_packages.toOwnedSlice();
    }
    
    /// Enhanced Ziglibs package search
    pub fn searchZiglibs(self: *RegistryManager, query: ?[]const u8) ![]Package {
        std.log.info("🔍 Searching Ziglibs packages...", .{});
        
        // Search specifically in Zigistry for ziglibs packages
        for (self.clients.items) |*client| {
            if (std.mem.eql(u8, client.config.name, "zigistry")) {
                const search_query = if (query) |q| 
                    try std.fmt.allocPrint(self.allocator, "ziglibs {s}", .{q})
                else 
                    try self.allocator.dupe(u8, "ziglibs");
                defer self.allocator.free(search_query);
                
                const packages = try client.searchPackages(search_query, "zig");
                
                // Filter for ziglibs only
                var ziglibs_packages = std.ArrayList(Package).init(self.allocator);
                for (packages) |pkg| {
                    if (pkg.is_ziglibs) {
                        try ziglibs_packages.append(pkg);
                    } else {
                        pkg.deinit(self.allocator);
                    }
                }
                self.allocator.free(packages);
                
                return ziglibs_packages.toOwnedSlice();
            }
        }
        
        return &[_]Package{};
    }
    
    /// Get package download information with verification
    pub fn getPackageDownload(self: *RegistryManager, full_name: []const u8, version: []const u8) !?DownloadInfo {
        var parts = std.mem.splitScalar(u8, full_name, '/');
        const owner = parts.next() orelse return null;
        const repo = parts.next() orelse return null;
        
        // Try registries in priority order
        for (self.clients.items) |*client| {
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
                        .sha256_hash = null, // Will be computed during download
                        .registry_name = try self.allocator.dupe(u8, client.config.name),
                        .version = try self.allocator.dupe(u8, release.tag_name),
                    };
                }
            }
        }
        
        return null;
    }
};

/// Result structures for async operations
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

pub const DownloadInfo = struct {
    url: []const u8,
    sha256_hash: ?[]const u8,
    registry_name: []const u8,
    version: []const u8,
    
    pub fn deinit(self: DownloadInfo, allocator: Allocator) void {
        allocator.free(self.url);
        if (self.sha256_hash) |hash| allocator.free(hash);
        allocator.free(self.registry_name);
        allocator.free(self.version);
    }
};

/// Async function to resolve package from a single registry
fn resolveFromRegistry(client: *RegistryClient, package_name: []const u8) PackageResult {
    // First resolve alias if it's a short name
    const full_name = client.resolveAlias(package_name) catch |err| {
        return PackageResult{
            .package = null,
            .registry_name = client.config.name,
            .error_msg = switch (err) {
                error.OutOfMemory => "Out of memory",
                else => "Failed to resolve alias",
            },
        };
    };
    defer if (full_name) |name| client.allocator.free(name);
    
    const resolved_name = full_name orelse package_name;
    
    // Parse owner/repo
    var parts = std.mem.splitScalar(u8, resolved_name, '/');
    const owner = parts.next() orelse {
        return PackageResult{
            .package = null,
            .registry_name = client.config.name,
            .error_msg = "Invalid package name format",
        };
    };
    const repo = parts.next() orelse {
        return PackageResult{
            .package = null,
            .registry_name = client.config.name,
            .error_msg = "Invalid package name format",
        };
    };
    
    // Try to fetch releases
    const releases = client.fetchReleases(owner, repo) catch |err| {
        return PackageResult{
            .package = null,
            .registry_name = client.config.name,
            .error_msg = switch (err) {
                error.HttpRequestFailed => "Package not found",
                error.OutOfMemory => "Out of memory",
                else => "Network error",
            },
        };
    };
    defer {
        for (releases) |release| release.deinit(client.allocator);
        client.allocator.free(releases);
    }
    
    if (releases.len > 0) {
        const package = convertReleaseToPackage(client.allocator, releases[0], resolved_name, client.config.name) catch {
            return PackageResult{
                .package = null,
                .registry_name = client.config.name,
                .error_msg = "Failed to convert release to package",
            };
        };
        
        return PackageResult{
            .package = package,
            .registry_name = client.config.name,
            .error_msg = null,
        };
    }
    
    return PackageResult{
        .package = null,
        .registry_name = client.config.name,
        .error_msg = "No releases found",
    };
}

/// Async function to search in a single registry
fn searchInRegistry(client: *RegistryClient, query: []const u8) SearchResult {
    const packages = client.searchPackages(query, "zig") catch |err| {
        return SearchResult{
            .packages = null,
            .registry_name = client.config.name,
            .error_msg = switch (err) {
                error.HttpRequestFailed => "Search failed",
                error.OutOfMemory => "Out of memory",
                else => "Network error",
            },
        };
    };
    
    return SearchResult{
        .packages = packages,
        .registry_name = client.config.name,
        .error_msg = null,
    };
}

fn convertReleaseToPackage(allocator: Allocator, release: Release, full_name: []const u8, registry_name: []const u8) !Package {
    var parts = std.mem.splitScalar(u8, full_name, '/');
    const owner = parts.next() orelse return error.InvalidPackageName;
    const name = parts.next() orelse return error.InvalidPackageName;
    
    // Check if it's a Ziglibs package
    const is_ziglibs = std.mem.eql(u8, owner, "ziglibs");
    
    return Package{
        .name = try allocator.dupe(u8, name),
        .full_name = try allocator.dupe(u8, full_name),
        .description = null,
        .version = try allocator.dupe(u8, release.tag_name),
        .tarball_url = try allocator.dupe(u8, release.tarball_url),
        .sha256_hash = null,
        .published_at = try allocator.dupe(u8, release.published_at),
        .registry_name = try allocator.dupe(u8, registry_name),
        .is_ziglibs = is_ziglibs,
        .quality_score = if (is_ziglibs) @as(?u8, 95) else null,
        .maintenance_status = if (is_ziglibs) 
            try allocator.dupe(u8, "well-maintained") else null,
    };
}
