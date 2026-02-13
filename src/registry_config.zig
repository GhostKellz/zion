const std = @import("std");
const Allocator = std.mem.Allocator;
const zion_root = @import("root.zig");

/// Registry configuration for multi-registry support
pub const RegistryConfig = struct {
    name: []const u8,
    base_url: []const u8,
    api_version: []const u8 = "v1",
    auth_token: ?[]const u8 = null,
    priority: u32 = 0, // Lower = higher priority
    enabled: bool = true,
    timeout_ms: u32 = 30000,

    pub fn getApiUrl(self: RegistryConfig, allocator: Allocator) ![]const u8 {
        // Handle GitHub's special case (no /api/v1 prefix)
        if (std.mem.eql(u8, self.name, "github")) {
            return try allocator.dupe(u8, self.base_url);
        }

        return std.fmt.allocPrint(allocator, "{s}/api/{s}", .{ std.mem.trimEnd(u8, self.base_url, "/"), self.api_version });
    }

    pub fn deinit(self: RegistryConfig, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.base_url);
        if (!std.mem.eql(u8, self.api_version, "v1")) {
            allocator.free(self.api_version);
        }
        if (self.auth_token) |token| {
            allocator.free(token);
        }
    }
};

/// Enhanced Zion configuration for v1.1.0 registry abstraction
pub const ZionConfig = struct {
    allocator: Allocator,
    registries: std.ArrayList(RegistryConfig),
    github_username: ?[]const u8 = null,
    cache_dir: []const u8,

    pub fn init(allocator: Allocator) ZionConfig {
        return ZionConfig{
            .allocator = allocator,
            .registries = .{},
            .cache_dir = "/tmp/zion-cache", // Default
        };
    }

    pub fn loadFromEnvironment(self: *ZionConfig) !void {
        // Primary registry from environment
        if (zion_root.getEnv("ZION_REGISTRY_URL")) |registry_url| {
            const auth_token = zion_root.getEnv("ZION_REGISTRY_TOKEN");

            try self.registries.append(self.allocator, RegistryConfig{
                .name = try self.allocator.dupe(u8, "custom"),
                .base_url = try self.allocator.dupe(u8, registry_url),
                .auth_token = if (auth_token) |token|
                    try self.allocator.dupe(u8, token)
                else
                    null,
                .priority = 0, // Highest priority
            });
        }

        // Multiple registries support
        if (zion_root.getEnv("ZION_REGISTRIES")) |registries_str| {
            var it = std.mem.splitScalar(u8, registries_str, ',');
            var priority: u32 = 1;

            while (it.next()) |registry_url| {
                const trimmed = std.mem.trim(u8, registry_url, " ");
                if (trimmed.len > 0) {
                    try self.registries.append(self.allocator, RegistryConfig{
                        .name = try std.fmt.allocPrint(self.allocator, "registry-{}", .{priority}),
                        .base_url = try self.allocator.dupe(u8, trimmed),
                        .priority = priority,
                    });
                    priority += 1;
                }
            }
        }

        // Add Zigistry as preferred registry (if not already configured)
        if (self.registries.items.len == 0 or !self.hasRegistry("zigistry")) {
            try self.registries.append(self.allocator, RegistryConfig{
                .name = try self.allocator.dupe(u8, "zigistry"),
                .base_url = try self.allocator.dupe(u8, "https://zigistry-api.hf.space"),
                .priority = 1,
            });
        }

        // Always add GitHub as fallback (lowest priority)
        try self.registries.append(self.allocator, RegistryConfig{
            .name = try self.allocator.dupe(u8, "github"),
            .base_url = try self.allocator.dupe(u8, "https://api.github.com"),
            .api_version = try self.allocator.dupe(u8, ""), // GitHub doesn't use /api/v1 prefix
            .priority = 999, // Lowest priority
        });

        // Sort registries by priority
        std.sort.block(RegistryConfig, self.registries.items, {}, struct {
            fn lessThan(context: void, a: RegistryConfig, b: RegistryConfig) bool {
                _ = context;
                return a.priority < b.priority;
            }
        }.lessThan);

        // Load other config
        if (zion_root.getEnv("ZION_GITHUB_USERNAME")) |username| {
            self.github_username = try self.allocator.dupe(u8, username);
        }

        if (zion_root.getEnv("ZION_CACHE_DIR")) |cache_dir| {
            self.cache_dir = try self.allocator.dupe(u8, cache_dir);
        }
    }

    pub fn deinit(self: *ZionConfig) void {
        for (self.registries.items) |registry| {
            registry.deinit(self.allocator);
        }
        self.registries.deinit(self.allocator);

        if (self.github_username) |username| {
            self.allocator.free(username);
        }

        if (!std.mem.eql(u8, self.cache_dir, "/tmp/zion-cache")) {
            self.allocator.free(self.cache_dir);
        }
    }

    fn hasRegistry(self: *const ZionConfig, name: []const u8) bool {
        for (self.registries.items) |registry| {
            if (std.mem.eql(u8, registry.name, name)) {
                return true;
            }
        }
        return false;
    }

    pub fn createDefault(allocator: Allocator) !ZionConfig {
        var config = ZionConfig.init(allocator);

        // Add default registries
        try config.registries.append(RegistryConfig{
            .name = try allocator.dupe(u8, "zigistry"),
            .base_url = try allocator.dupe(u8, "https://zigistry.dev"),
            .priority = 0,
        });

        try config.registries.append(RegistryConfig{
            .name = try allocator.dupe(u8, "github"),
            .base_url = try allocator.dupe(u8, "https://api.github.com"),
            .priority = 1,
        });

        return config;
    }

    pub fn loadOrDefault(allocator: Allocator) !ZionConfig {
        var config = try createDefault(allocator);
        try config.loadFromEnvironment();
        return config;
    }
};
