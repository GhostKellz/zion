const std = @import("std");
const http = std.http;
const json = std.json;
const Allocator = std.mem.Allocator;
const ZionConfig = @import("enhanced_config.zig").ZionConfig;

pub const RegistryType = enum {
    github,
    zepplin,
    zigistry,
    custom,
    
    pub fn fromUrl(url: []const u8) RegistryType {
        if (std.mem.indexOf(u8, url, "api.github.com") != null) {
            return .github;
        } else if (std.mem.indexOf(u8, url, "/api/v1") != null) {
            return .zepplin; // Assume Zepplin-compatible
        } else if (std.mem.indexOf(u8, url, "zigistry-api.hf.space") != null) {
            return .zigistry;
        }
        return .custom;
    }
};

pub const RegistryClient = struct {
    allocator: Allocator,
    base_url: []const u8,
    registry_type: RegistryType,
    timeout_sec: u32,
    
    pub fn init(allocator: Allocator, base_url: []const u8, timeout_sec: u32) RegistryClient {
        return RegistryClient{
            .allocator = allocator,
            .base_url = base_url,
            .registry_type = RegistryType.fromUrl(base_url),
            .timeout_sec = timeout_sec,
        };
    }
    
    /// Build API URL for releases endpoint
    pub fn getReleasesUrl(self: *const RegistryClient, owner: []const u8, repo: []const u8) ![]const u8 {
        return switch (self.registry_type) {
            .github => try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/releases", .{ self.base_url, owner, repo }),
            .zepplin => try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}/{s}/releases", .{ self.base_url, owner, repo }),
            .zigistry => try std.fmt.allocPrint(self.allocator, "{s}/api/packages/github/{s}/{s}", .{ self.base_url, owner, repo }),
            .custom => try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/releases", .{ self.base_url, owner, repo }), // Default to GitHub format
        };
    }
    
    /// Build API URL for tags endpoint  
    pub fn getTagsUrl(self: *const RegistryClient, owner: []const u8, repo: []const u8) ![]const u8 {
        return switch (self.registry_type) {
            .github => try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/tags", .{ self.base_url, owner, repo }),
            .zepplin => try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}/{s}/tags", .{ self.base_url, owner, repo }),
            .zigistry => try std.fmt.allocPrint(self.allocator, "{s}/api/packages/github/{s}/{s}", .{ self.base_url, owner, repo }),
            .custom => try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/tags", .{ self.base_url, owner, repo }),
        };
    }
    
    /// Build API URL for search endpoint
    pub fn getSearchUrl(self: *const RegistryClient, query: []const u8) ![]const u8 {
        return switch (self.registry_type) {
            .github => try std.fmt.allocPrint(self.allocator, "{s}/search/repositories?q={s}+language:zig&sort=stars&order=desc&per_page=10", .{ self.base_url, query }),
            .zepplin => try std.fmt.allocPrint(self.allocator, "{s}/search?q={s}&language=zig&sort=stars&order=desc&per_page=10", .{ self.base_url, query }),
            .zigistry => try std.fmt.allocPrint(self.allocator, "{s}/api/searchPackages?q={s}", .{ self.base_url, query }),
            .custom => try std.fmt.allocPrint(self.allocator, "{s}/search/repositories?q={s}+language:zig", .{ self.base_url, query }),
        };
    }
    
    /// Check if registry supports alias resolution
    pub fn supportsAliases(self: *const RegistryClient) bool {
        return self.registry_type == .zepplin;
    }
    
    /// Get alias resolution URL (Zepplin-specific)
    pub fn getAliasUrl(self: *const RegistryClient, short_name: []const u8) ![]const u8 {
        if (!self.supportsAliases()) return error.AliasNotSupported;
        return try std.fmt.allocPrint(self.allocator, "{s}/resolve/{s}", .{ self.base_url, short_name });
    }
};

/// Get the primary registry client from config
pub fn getPrimaryRegistry(allocator: Allocator, config: *const ZionConfig) RegistryClient {
    const base_url = config.registry_url orelse "https://api.github.com";
    return RegistryClient.init(allocator, base_url, config.registry_timeout_sec);
}

/// Get fallback registry clients
pub fn getFallbackRegistries(allocator: Allocator, config: *const ZionConfig) ![]RegistryClient {
    var registries = std.ArrayList(RegistryClient).init(allocator);
    
    for (config.fallback_registries.items) |registry_url| {
        try registries.append(RegistryClient.init(allocator, registry_url, config.registry_timeout_sec));
    }
    
    return try registries.toOwnedSlice();
}