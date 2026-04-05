const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const zion_root = @import("root.zig");
const json_escape = @import("json_escape.zig");

/// Helper to get environment variable as a slice (Zig 0.16.0 compatibility)
/// Accepts string literals which are sentinel-terminated
fn getEnvVar(name: [*:0]const u8) ?[]const u8 {
    const ptr = std.c.getenv(name) orelse return null;
    return std.mem.sliceTo(ptr, 0);
}

/// Helper for dynamically constructed env var names
fn getEnvVarDynamic(name: []const u8) ?[]const u8 {
    // Stack buffer for null-terminated copy
    var buf: [256]u8 = undefined;
    if (name.len >= buf.len) return null;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    const ptr = std.c.getenv(@ptrCast(buf[0..name.len :0])) orelse return null;
    return std.mem.sliceTo(ptr, 0);
}

pub fn isLocalRegistryUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://localhost") or
        std.mem.startsWith(u8, url, "http://127.0.0.1") or
        std.mem.startsWith(u8, url, "http://[::1]");
}

pub fn validateRegistryUrl(url: []const u8) !void {
    if (std.mem.startsWith(u8, url, "https://")) return;
    if (std.mem.startsWith(u8, url, "http://")) {
        if (isLocalRegistryUrl(url)) return;
        return error.InsecureRegistryUrl;
    }
    return error.InvalidRegistryUrl;
}

/// Registry configuration for multi-registry support
pub const RegistryConfig = struct {
    name: []const u8,
    base_url: []const u8,
    api_version: []const u8 = "v1",
    auth_token: ?[]const u8 = null,
    priority: u32 = 0, // Lower = higher priority
    enabled: bool = true,
    timeout_ms: u32 = 30000,

    pub fn getApiUrl(self: RegistryConfig, allocator: std.mem.Allocator) ![]const u8 {
        // Handle GitHub's special case (no /api/v1 prefix)
        if (std.mem.eql(u8, self.name, "github")) {
            return try allocator.dupe(u8, self.base_url);
        }
        return std.fmt.allocPrint(allocator, "{s}/api/{s}", .{ std.mem.trimEnd(u8, self.base_url, "/"), self.api_version });
    }
};

/// Enhanced Zion configuration management with environment variables and Lua support
pub const ZionConfig = struct {
    // User identification
    github_username: ?[]const u8 = null,
    github_orgs: std.ArrayList([]const u8),

    // Default behavior
    auto_add_to_build: bool = true,
    auto_update_lock: bool = true,
    prefer_releases: bool = true,

    // Cache settings
    cache_ttl_hours: u32 = 24,
    max_cache_size_mb: u32 = 1024,

    // Download settings
    concurrent_downloads: u32 = 4,
    download_timeout_sec: u32 = 300,
    retry_attempts: u32 = 3,

    // Security settings
    verify_signatures: bool = false,
    trust_level_required: []const u8 = "medium",

    // Editor integration
    neovim_integration: bool = false,
    vscode_integration: bool = false,

    // Registry settings
    registry_url: ?[]const u8 = null,
    fallback_registries: std.ArrayList([]const u8),
    registry_timeout_sec: u32 = 30,
    registry_retries: u32 = 3,
    prefer_registry_over_github: bool = true,

    // Enhanced registry configuration for
    registries: std.ArrayList(RegistryConfig),
    registry_auth_tokens: std.StringHashMap([]const u8),

    // Dependency aliases for easy bulk adding
    dependency_aliases: std.StringHashMap(std.ArrayList([]const u8)),

    allocator: Allocator,

    pub fn init(allocator: Allocator) ZionConfig {
        var config = ZionConfig{
            .github_orgs = .empty,
            .fallback_registries = .empty,
            .dependency_aliases = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .registries = .empty,
            .registry_auth_tokens = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
            .trust_level_required = "medium",
        };

        // Set up default aliases
        config.setupDefaultAliases() catch {};

        return config;
    }

    pub fn deinit(self: *ZionConfig) void {
        if (self.github_username) |username| {
            self.allocator.free(username);
        }

        for (self.github_orgs.items) |org| {
            self.allocator.free(org);
        }
        self.github_orgs.deinit(self.allocator);

        // Clean up fallback registries
        for (self.fallback_registries.items) |registry| {
            self.allocator.free(registry);
        }
        self.fallback_registries.deinit(self.allocator);

        // Clean up registry_url if allocated
        if (self.registry_url) |url| {
            self.allocator.free(url);
        }

        // Clean up dependency aliases
        var iterator = self.dependency_aliases.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |dep| {
                self.allocator.free(dep);
            }
            entry.value_ptr.deinit(self.allocator);
        }
        self.dependency_aliases.deinit();

        // Clean up registries
        for (self.registries.items) |registry| {
            self.allocator.free(registry.name);
            self.allocator.free(registry.base_url);
            if (registry.auth_token) |token| {
                self.allocator.free(token);
            }
            if (!std.mem.eql(u8, registry.api_version, "v1")) {
                self.allocator.free(registry.api_version);
            }
        }
        self.registries.deinit(self.allocator);

        // Clean up registry auth tokens
        var auth_iterator = self.registry_auth_tokens.iterator();
        while (auth_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.registry_auth_tokens.deinit();

        if (!std.mem.eql(u8, self.trust_level_required, "medium")) {
            self.allocator.free(self.trust_level_required);
        }
    }

    /// Load configuration from multiple sources (env vars, config files, etc.)
    pub fn load(allocator: Allocator) !ZionConfig {
        var config = ZionConfig.init(allocator);

        // 1. Load from environment variables first
        try config.loadFromEnvironment();

        // 2. Load from JSON config file (if exists)
        config.loadFromJsonFile() catch |err| {
            if (err != error.FileNotFound) {
                std.debug.print("⚠️  Warning: Could not load zion.json: {}\n", .{err});
            }
        };

        // 3. Load from Lua config file (if exists)
        config.loadFromLuaFile() catch |err| {
            if (err != error.FileNotFound) {
                std.debug.print("⚠️  Warning: Could not load zion.lua: {}\n", .{err});
            }
        };

        return config;
    }

    /// Load configuration from environment variables
    fn loadFromEnvironment(self: *ZionConfig) !void {
        // GitHub username
        if (getEnvVar("ZION_GITHUB_USERNAME")) |username| {
            self.github_username = try self.allocator.dupe(u8, username);
        }

        // GitHub organizations (comma-separated)
        if (getEnvVar("ZION_GITHUB_ORGS")) |orgs_str| {
            var it = std.mem.splitScalar(u8, orgs_str, ',');
            while (it.next()) |org| {
                const trimmed = std.mem.trim(u8, org, " ");
                if (trimmed.len > 0) {
                    try self.github_orgs.append(self.allocator, try self.allocator.dupe(u8, trimmed));
                }
            }
        }

        // Boolean settings
        if (getEnvVar("ZION_AUTO_ADD_TO_BUILD")) |val| {
            self.auto_add_to_build = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
        }

        if (getEnvVar("ZION_VERIFY_SIGNATURES")) |val| {
            self.verify_signatures = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
        }

        // Numeric settings
        if (getEnvVar("ZION_CACHE_TTL_HOURS")) |val| {
            self.cache_ttl_hours = std.fmt.parseInt(u32, val, 10) catch self.cache_ttl_hours;
        }

        if (getEnvVar("ZION_MAX_CACHE_SIZE_MB")) |val| {
            self.max_cache_size_mb = std.fmt.parseInt(u32, val, 10) catch self.max_cache_size_mb;
        }

        if (getEnvVar("ZION_CONCURRENT_DOWNLOADS")) |val| {
            self.concurrent_downloads = std.fmt.parseInt(u32, val, 10) catch self.concurrent_downloads;
        }

        // Enhanced Registry configuration
        // Primary registry from environment
        if (getEnvVar("ZION_REGISTRY_URL")) |registry_url| {
            try validateRegistryUrl(registry_url);

            self.registry_url = try self.allocator.dupe(u8, registry_url);
            const auth_token = getEnvVar("ZION_REGISTRY_TOKEN");

            try self.registries.append(self.allocator, RegistryConfig{
                .name = try self.allocator.dupe(u8, "custom"),
                .base_url = try self.allocator.dupe(u8, registry_url),
                .auth_token = if (auth_token) |token|
                    try self.allocator.dupe(u8, token)
                else
                    null,
                .priority = 0, // Highest priority
                .api_version = try self.allocator.dupe(u8, "v1"),
            });

            if (auth_token) |token| {
                try self.registry_auth_tokens.put(try self.allocator.dupe(u8, "custom"), try self.allocator.dupe(u8, token));
            }

            std.debug.print("🔧 Using custom registry: {s}\n", .{registry_url});
        }

        // Multiple registries support
        if (getEnvVar("ZION_REGISTRIES")) |registries_str| {
            var it = std.mem.splitScalar(u8, registries_str, ',');
            var priority: u32 = 1;

            while (it.next()) |registry_url| {
                const trimmed = std.mem.trim(u8, registry_url, " ");
                if (trimmed.len > 0) {
                    try validateRegistryUrl(trimmed);

                    const registry_name = try std.fmt.allocPrint(self.allocator, "registry-{}", .{priority});

                    // Check for specific auth token
                    const auth_env_name = try std.fmt.allocPrint(self.allocator, "ZION_REGISTRY_TOKEN_{}", .{priority});
                    defer self.allocator.free(auth_env_name);
                    const auth_token = getEnvVarDynamic(auth_env_name);

                    try self.registries.append(self.allocator, RegistryConfig{
                        .name = registry_name,
                        .base_url = try self.allocator.dupe(u8, trimmed),
                        .priority = priority,
                        .auth_token = if (auth_token) |token|
                            try self.allocator.dupe(u8, token)
                        else
                            null,
                        .api_version = try self.allocator.dupe(u8, "v1"),
                    });

                    if (auth_token) |token| {
                        try self.registry_auth_tokens.put(try self.allocator.dupe(u8, registry_name), try self.allocator.dupe(u8, token));
                    }

                    priority += 1;
                }
            }
        }

        // Always add GitHub as fallback (lowest priority)
        const github_token = getEnvVar("ZION_GITHUB_TOKEN") orelse getEnvVar("GITHUB_TOKEN");
        try self.registries.append(self.allocator, RegistryConfig{
            .name = try self.allocator.dupe(u8, "github"),
            .base_url = try self.allocator.dupe(u8, "https://api.github.com"),
            .api_version = try self.allocator.dupe(u8, ""), // GitHub doesn't use /api/v1 prefix
            .priority = 999, // Lowest priority
            .auth_token = if (github_token) |token|
                try self.allocator.dupe(u8, token)
            else
                null,
        });

        if (github_token) |token| {
            try self.registry_auth_tokens.put(try self.allocator.dupe(u8, "github"), try self.allocator.dupe(u8, token));
        }

        // Sort registries by priority
        std.sort.block(RegistryConfig, self.registries.items, {}, struct {
            fn lessThan(context: void, a: RegistryConfig, b: RegistryConfig) bool {
                _ = context;
                return a.priority < b.priority;
            }
        }.lessThan);

        // Legacy fallback registries support (for backward compatibility)
        if (getEnvVar("ZION_FALLBACK_REGISTRIES")) |registries_str| {
            var it = std.mem.splitScalar(u8, registries_str, ',');
            while (it.next()) |registry| {
                const trimmed = std.mem.trim(u8, registry, " ");
                if (trimmed.len > 0) {
                    try self.fallback_registries.append(self.allocator, try self.allocator.dupe(u8, trimmed));
                }
            }
        }

        // Registry timeout
        if (getEnvVar("ZION_REGISTRY_TIMEOUT")) |val| {
            self.registry_timeout_sec = std.fmt.parseInt(u32, val, 10) catch 30;
        }

        // Registry retries
        if (getEnvVar("ZION_REGISTRY_RETRIES")) |val| {
            self.registry_retries = std.fmt.parseInt(u32, val, 10) catch 3;
        }

        // Prefer registry over GitHub
        if (getEnvVar("ZION_PREFER_REGISTRY")) |val| {
            self.prefer_registry_over_github = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
        }
    }

    /// Load configuration from zion.json file
    fn loadFromJsonFile(self: *ZionConfig) !void {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();
        const config_data = try cwd.readFileAlloc(io, "zion.json", self.allocator, Io.Limit.limited(1024 * 1024));
        defer self.allocator.free(config_data);

        var parsed = try json.parseFromSlice(json.Value, self.allocator, config_data, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Parse GitHub settings
        if (root.get("github")) |github_obj| {
            if (github_obj.object.get("username")) |username| {
                if (self.github_username == null) { // Don't override env vars
                    self.github_username = try self.allocator.dupe(u8, username.string);
                }
            }

            if (github_obj.object.get("organizations")) |orgs_array| {
                for (orgs_array.array.items) |org_val| {
                    try self.github_orgs.append(self.allocator, try self.allocator.dupe(u8, org_val.string));
                }
            }
        }

        // Parse other settings
        if (root.get("auto_add_to_build")) |val| {
            self.auto_add_to_build = val.bool;
        }

        if (root.get("verify_signatures")) |val| {
            self.verify_signatures = val.bool;
        }

        if (root.get("cache_ttl_hours")) |val| {
            self.cache_ttl_hours = @intCast(val.integer);
        }
    }

    /// Save configuration to zion.json file
    pub fn save(self: *ZionConfig) !void {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();
        const config_path = "zion.json";

        var file = try cwd.createFile(io, config_path, .{ .truncate = true });
        defer file.close(io);

        // Write JSON with proper escaping
        try file.writeStreamingAll(io, "{\n");

        // GitHub section
        try file.writeStreamingAll(io, "  \"github\": {\n");
        if (self.github_username) |username| {
            const escaped = try json_escape.escapeJsonString(self.allocator, username);
            defer self.allocator.free(escaped);
            const line = try std.fmt.allocPrint(self.allocator, "    \"username\": \"{s}\"", .{escaped});
            defer self.allocator.free(line);
            try file.writeStreamingAll(io, line);
            if (self.github_orgs.items.len > 0) {
                try file.writeStreamingAll(io, ",\n");
            } else {
                try file.writeStreamingAll(io, "\n");
            }
        }
        if (self.github_orgs.items.len > 0) {
            try file.writeStreamingAll(io, "    \"organizations\": [");
            for (self.github_orgs.items, 0..) |org, i| {
                const escaped = try json_escape.escapeJsonString(self.allocator, org);
                defer self.allocator.free(escaped);
                const org_line = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{escaped});
                defer self.allocator.free(org_line);
                try file.writeStreamingAll(io, org_line);
                if (i < self.github_orgs.items.len - 1) {
                    try file.writeStreamingAll(io, ", ");
                }
            }
            try file.writeStreamingAll(io, "]\n");
        }
        try file.writeStreamingAll(io, "  },\n");

        // Settings
        const auto_add_line = try std.fmt.allocPrint(self.allocator, "  \"auto_add_to_build\": {s},\n", .{if (self.auto_add_to_build) "true" else "false"});
        defer self.allocator.free(auto_add_line);
        try file.writeStreamingAll(io, auto_add_line);

        const verify_sig_line = try std.fmt.allocPrint(self.allocator, "  \"verify_signatures\": {s},\n", .{if (self.verify_signatures) "true" else "false"});
        defer self.allocator.free(verify_sig_line);
        try file.writeStreamingAll(io, verify_sig_line);

        const cache_ttl_line = try std.fmt.allocPrint(self.allocator, "  \"cache_ttl_hours\": {d},\n", .{self.cache_ttl_hours});
        defer self.allocator.free(cache_ttl_line);
        try file.writeStreamingAll(io, cache_ttl_line);

        const timeout_line = try std.fmt.allocPrint(self.allocator, "  \"registry_timeout_sec\": {d}\n", .{self.registry_timeout_sec});
        defer self.allocator.free(timeout_line);
        try file.writeStreamingAll(io, timeout_line);

        try file.writeStreamingAll(io, "}\n");
    }

    /// Load configuration from zion.lua file (simple key-value parser)
    fn loadFromLuaFile(self: *ZionConfig) !void {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();
        const lua_data = try cwd.readFileAlloc(io, "zion.lua", self.allocator, Io.Limit.limited(1024 * 1024));
        defer self.allocator.free(lua_data);

        std.debug.print("📋 Loading Lua configuration...\n", .{});

        // Simple Lua parser for basic key-value assignments
        var lines = std.mem.splitScalar(u8, lua_data, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Skip comments and empty lines
            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "--")) continue;

            // Look for pattern: config.key = "value" or config.key = true/false
            if (std.mem.indexOf(u8, trimmed, "config.")) |start| {
                try self.parseLuaConfigLine(trimmed[start..]);
            }
        }
    }

    test "registry url validation rejects insecure remote urls" {
        try std.testing.expectError(error.InsecureRegistryUrl, validateRegistryUrl("http://packages.example.com"));
        try validateRegistryUrl("https://packages.example.com");
        try validateRegistryUrl("http://localhost:8080");
    }

    /// Parse a single Lua configuration line
    fn parseLuaConfigLine(self: *ZionConfig, line: []const u8) !void {
        // Extract key-value pairs from lines like: config.github_username = "ghostkellz"
        if (std.mem.indexOf(u8, line, " = ")) |eq_pos| {
            const key_part = std.mem.trim(u8, line[7..eq_pos], " "); // Skip "config."
            const value_part = std.mem.trim(u8, line[eq_pos + 3 ..], " ");

            if (std.mem.eql(u8, key_part, "github_username")) {
                if (std.mem.startsWith(u8, value_part, "\"") and std.mem.endsWith(u8, value_part, "\"")) {
                    const username = value_part[1 .. value_part.len - 1];
                    if (self.github_username == null) {
                        self.github_username = try self.allocator.dupe(u8, username);
                    }
                }
            } else if (std.mem.eql(u8, key_part, "github_orgs")) {
                // Handle arrays: config.github_orgs = {"ghostkellz", "CK-Technology"}
                if (std.mem.startsWith(u8, value_part, "{") and std.mem.endsWith(u8, value_part, "}")) {
                    const array_content = value_part[1 .. value_part.len - 1];
                    var orgs = std.mem.splitScalar(u8, array_content, ',');
                    while (orgs.next()) |org| {
                        const clean_org = std.mem.trim(u8, org, " \t\"");
                        if (clean_org.len > 0) {
                            try self.github_orgs.append(self.allocator, try self.allocator.dupe(u8, clean_org));
                        }
                    }
                }
            } else if (std.mem.eql(u8, key_part, "auto_add_to_build")) {
                self.auto_add_to_build = std.mem.eql(u8, value_part, "true");
            } else if (std.mem.eql(u8, key_part, "verify_signatures")) {
                self.verify_signatures = std.mem.eql(u8, value_part, "true");
            }
        }
    }

    /// Create a sample configuration file
    pub fn createSampleConfig(allocator: Allocator, format: ConfigFormat) !void {
        switch (format) {
            .json => try createSampleJsonConfig(allocator),
            .lua => try createSampleLuaConfig(allocator),
        }
    }

    /// Get short name for a package (attempts to resolve from configured orgs/username)
    pub fn resolvePackageName(self: *const ZionConfig, short_name: []const u8) ?[]const u8 {
        // If it already contains a slash, it's likely a full name
        if (std.mem.indexOf(u8, short_name, "/") != null) {
            return null; // No resolution needed
        }

        // Try username first
        if (self.github_username) |username| {
            const full_name = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ username, short_name }) catch return null;
            return full_name;
        }

        // Try first organization
        if (self.github_orgs.items.len > 0) {
            const full_name = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.github_orgs.items[0], short_name }) catch return null;
            return full_name;
        }

        return null;
    }

    /// Set up default dependency aliases for common use cases
    fn setupDefaultAliases(self: *ZionConfig) !void {
        // Crypto libraries bundle
        var crypto_deps: std.ArrayList([]const u8) = .empty;
        try crypto_deps.append(self.allocator, try self.allocator.dupe(u8, "ghostkellz/zcrypto"));
        try crypto_deps.append(self.allocator, try self.allocator.dupe(u8, "jedisct1/libsodium"));
        try crypto_deps.append(self.allocator, try self.allocator.dupe(u8, "ziglang/crypto"));
        try self.dependency_aliases.put(try self.allocator.dupe(u8, "crypto"), crypto_deps);

        // HTTP/Network libraries bundle
        var http_deps: std.ArrayList([]const u8) = .empty;
        try http_deps.append(self.allocator, try self.allocator.dupe(u8, "karlseguin/http.zig"));
        try http_deps.append(self.allocator, try self.allocator.dupe(u8, "mitchellh/libxev"));
        try http_deps.append(self.allocator, try self.allocator.dupe(u8, "ziglang/http"));
        try self.dependency_aliases.put(try self.allocator.dupe(u8, "http"), http_deps);

        // Database libraries bundle
        var db_deps: std.ArrayList([]const u8) = .empty;
        try db_deps.append(self.allocator, try self.allocator.dupe(u8, "vrischmann/zig-sqlite"));
        try db_deps.append(self.allocator, try self.allocator.dupe(u8, "karlseguin/pg.zig"));
        try self.dependency_aliases.put(try self.allocator.dupe(u8, "db"), db_deps);

        // Gaming/Graphics libraries bundle
        var game_deps: std.ArrayList([]const u8) = .empty;
        try game_deps.append(self.allocator, try self.allocator.dupe(u8, "hexops/mach"));
        try game_deps.append(self.allocator, try self.allocator.dupe(u8, "ziglang/raylib"));
        try self.dependency_aliases.put(try self.allocator.dupe(u8, "game"), game_deps);

        // JSON/Serialization libraries bundle
        var json_deps: std.ArrayList([]const u8) = .empty;
        try json_deps.append(self.allocator, try self.allocator.dupe(u8, "ziglang/json"));
        try json_deps.append(self.allocator, try self.allocator.dupe(u8, "karlseguin/json.zig"));
        try self.dependency_aliases.put(try self.allocator.dupe(u8, "json"), json_deps);
    }

    /// Check if a name is an alias and return the expanded dependencies
    pub fn expandAlias(self: *const ZionConfig, alias: []const u8) ?[]const []const u8 {
        if (self.dependency_aliases.get(alias)) |deps| {
            return deps.items;
        }
        return null;
    }

    /// Add a custom alias
    pub fn addAlias(self: *ZionConfig, alias: []const u8, dependencies: []const []const u8) !void {
        var deps: std.ArrayList([]const u8) = .empty;
        for (dependencies) |dep| {
            try deps.append(self.allocator, try self.allocator.dupe(u8, dep));
        }
        try self.dependency_aliases.put(try self.allocator.dupe(u8, alias), deps);
    }

    /// List all available aliases
    pub fn listAliases(self: *const ZionConfig, allocator: Allocator) !void {
        _ = allocator;
        std.debug.print("📋 Available Dependency Aliases:\n\n", .{});

        var iterator = self.dependency_aliases.iterator();
        while (iterator.next()) |entry| {
            std.debug.print("🔗 {s}:\n", .{entry.key_ptr.*});
            for (entry.value_ptr.items) |dep| {
                std.debug.print("   • {s}\n", .{dep});
            }
            std.debug.print("\n", .{});
        }

        std.debug.print("💡 Usage: zion add crypto  # Adds all crypto dependencies\n", .{});
        std.debug.print("💡 Usage: zion add http    # Adds all HTTP dependencies\n", .{});
    }
};

pub const ConfigFormat = enum {
    json,
    lua,
};

/// Create sample zion.json configuration
fn createSampleJsonConfig(allocator: Allocator) !void {
    const sample_json =
        \\{
        \\  "github": {
        \\    "username": "ghostkellz",
        \\    "organizations": ["CK-Technology"]
        \\  },
        \\  "auto_add_to_build": true,
        \\  "auto_update_lock": true,
        \\  "prefer_releases": true,
        \\  "cache_ttl_hours": 24,
        \\  "max_cache_size_mb": 1024,
        \\  "concurrent_downloads": 4,
        \\  "download_timeout_sec": 300,
        \\  "retry_attempts": 3,
        \\  "verify_signatures": false,
        \\  "trust_level_required": "medium",
        \\  "neovim_integration": false,
        \\  "vscode_integration": false,
        \\  "dependency_aliases": {
        \\    "mycrypto": ["ghostkellz/zcrypto", "your-org/custom-crypto"],
        \\    "backend": ["karlseguin/http.zig", "vrischmann/zig-sqlite", "mitchellh/libxev"]
        \\  }
        \\}
        \\
    ;

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const file = try cwd.createFile(io, "zion.json", .{});
    defer file.close(io);

    try file.writeStreamingAll(io, sample_json);
    std.debug.print("✅ Created sample zion.json configuration\n", .{});
    _ = allocator;
}

/// Create sample zion.lua configuration
fn createSampleLuaConfig(allocator: Allocator) !void {
    const sample_lua =
        \\-- Zion Package Manager Configuration
        \\-- This file will be used for Neovim integration and other advanced features
        \\
        \\local config = {}
        \\
        \\-- GitHub Configuration
        \\config.github_username = "ghostkellz"
        \\config.github_orgs = {"ghostkellz", "CK-Technology"}
        \\
        \\-- Package Management Behavior
        \\config.auto_add_to_build = true
        \\config.auto_update_lock = true
        \\config.prefer_releases = true
        \\
        \\-- Cache Settings
        \\config.cache_ttl_hours = 24
        \\config.max_cache_size_mb = 1024
        \\
        \\-- Download Settings
        \\config.concurrent_downloads = 4
        \\config.download_timeout_sec = 300
        \\config.retry_attempts = 3
        \\
        \\-- Security Settings
        \\config.verify_signatures = false
        \\config.trust_level_required = "medium"
        \\
        \\-- Editor Integration
        \\config.neovim_integration = true
        \\config.vscode_integration = false
        \\
        \\-- Custom shortcuts for your packages
        \\config.shortcuts = {
        \\    zcrypto = "ghostkellz/zcrypto",
        \\    mylib = "CK-Technology/mylib",
        \\    -- Add more shortcuts as needed
        \\}
        \\
        \\return config
        \\
    ;

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const file = try cwd.createFile(io, "zion.lua", .{});
    defer file.close(io);

    try file.writeStreamingAll(io, sample_lua);
    std.debug.print("✅ Created sample zion.lua configuration\n", .{});
    std.debug.print("💡 This will enable Neovim integration and package shortcuts\n", .{});
    _ = allocator;
}
