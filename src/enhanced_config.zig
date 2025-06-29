const std = @import("std");
const fs = std.fs;
const json = std.json;
const Allocator = std.mem.Allocator;

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
    
    // Dependency aliases for easy bulk adding
    dependency_aliases: std.StringHashMap(std.ArrayList([]const u8)),
    
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) ZionConfig {
        var config = ZionConfig{
            .github_orgs = std.ArrayList([]const u8).init(allocator),
            .fallback_registries = std.ArrayList([]const u8).init(allocator),
            .dependency_aliases = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
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
        self.github_orgs.deinit();
        
        // Clean up fallback registries
        for (self.fallback_registries.items) |registry| {
            self.allocator.free(registry);
        }
        self.fallback_registries.deinit();
        
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
            entry.value_ptr.deinit();
        }
        self.dependency_aliases.deinit();
        
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
        if (std.posix.getenv("ZION_GITHUB_USERNAME")) |username| {
            self.github_username = try self.allocator.dupe(u8, username);
        }
        
        // GitHub organizations (comma-separated)
        if (std.posix.getenv("ZION_GITHUB_ORGS")) |orgs_str| {
            var it = std.mem.splitScalar(u8, orgs_str, ',');
            while (it.next()) |org| {
                const trimmed = std.mem.trim(u8, org, " ");
                if (trimmed.len > 0) {
                    try self.github_orgs.append(try self.allocator.dupe(u8, trimmed));
                }
            }
        }
        
        // Boolean settings
        if (std.posix.getenv("ZION_AUTO_ADD_TO_BUILD")) |val| {
            self.auto_add_to_build = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
        }
        
        if (std.posix.getenv("ZION_VERIFY_SIGNATURES")) |val| {
            self.verify_signatures = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
        }
        
        // Numeric settings
        if (std.posix.getenv("ZION_CACHE_TTL_HOURS")) |val| {
            self.cache_ttl_hours = std.fmt.parseInt(u32, val, 10) catch self.cache_ttl_hours;
        }
        
        if (std.posix.getenv("ZION_MAX_CACHE_SIZE_MB")) |val| {
            self.max_cache_size_mb = std.fmt.parseInt(u32, val, 10) catch self.max_cache_size_mb;
        }
        
        if (std.posix.getenv("ZION_CONCURRENT_DOWNLOADS")) |val| {
            self.concurrent_downloads = std.fmt.parseInt(u32, val, 10) catch self.concurrent_downloads;
        }
        
        // Registry configuration
        if (std.posix.getenv("ZION_REGISTRY_URL")) |url| {
            self.registry_url = try self.allocator.dupe(u8, url);
            std.debug.print("🔧 Using custom registry: {s}\n", .{url});
        }
        
        // Fallback registries (comma-separated)
        if (std.posix.getenv("ZION_FALLBACK_REGISTRIES")) |registries_str| {
            var it = std.mem.splitScalar(u8, registries_str, ',');
            while (it.next()) |registry| {
                const trimmed = std.mem.trim(u8, registry, " ");
                if (trimmed.len > 0) {
                    try self.fallback_registries.append(try self.allocator.dupe(u8, trimmed));
                }
            }
        } else {
            // Default fallbacks: GitHub and Zigistry
            try self.fallback_registries.append(try self.allocator.dupe(u8, "https://api.github.com"));
            try self.fallback_registries.append(try self.allocator.dupe(u8, "https://zigistry-api.hf.space"));
        }
        
        // Registry timeout
        if (std.posix.getenv("ZION_REGISTRY_TIMEOUT")) |val| {
            self.registry_timeout_sec = std.fmt.parseInt(u32, val, 10) catch 30;
        }
        
        // Registry retries
        if (std.posix.getenv("ZION_REGISTRY_RETRIES")) |val| {
            self.registry_retries = std.fmt.parseInt(u32, val, 10) catch 3;
        }
        
        // Prefer registry over GitHub
        if (std.posix.getenv("ZION_PREFER_REGISTRY")) |val| {
            self.prefer_registry_over_github = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
        }
    }
    
    /// Load configuration from zion.json file
    fn loadFromJsonFile(self: *ZionConfig) !void {
        const cwd = fs.cwd();
        const config_data = try cwd.readFileAlloc(self.allocator, "zion.json", 1024 * 1024);
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
                    try self.github_orgs.append(try self.allocator.dupe(u8, org_val.string));
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
    
    /// Load configuration from zion.lua file (simple key-value parser)
    fn loadFromLuaFile(self: *ZionConfig) !void {
        const cwd = fs.cwd();
        const lua_data = try cwd.readFileAlloc(self.allocator, "zion.lua", 1024 * 1024);
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
    
    /// Parse a single Lua configuration line
    fn parseLuaConfigLine(self: *ZionConfig, line: []const u8) !void {
        // Extract key-value pairs from lines like: config.github_username = "ghostkellz"
        if (std.mem.indexOf(u8, line, " = ")) |eq_pos| {
            const key_part = std.mem.trim(u8, line[7..eq_pos], " "); // Skip "config."
            const value_part = std.mem.trim(u8, line[eq_pos + 3..], " ");
            
            if (std.mem.eql(u8, key_part, "github_username")) {
                if (std.mem.startsWith(u8, value_part, "\"") and std.mem.endsWith(u8, value_part, "\"")) {
                    const username = value_part[1..value_part.len-1];
                    if (self.github_username == null) {
                        self.github_username = try self.allocator.dupe(u8, username);
                    }
                }
            } else if (std.mem.eql(u8, key_part, "github_orgs")) {
                // Handle arrays: config.github_orgs = {"ghostkellz", "CK-Technology"}
                if (std.mem.startsWith(u8, value_part, "{") and std.mem.endsWith(u8, value_part, "}")) {
                    const array_content = value_part[1..value_part.len-1];
                    var orgs = std.mem.splitScalar(u8, array_content, ',');
                    while (orgs.next()) |org| {
                        const clean_org = std.mem.trim(u8, org, " \t\"");
                        if (clean_org.len > 0) {
                            try self.github_orgs.append(try self.allocator.dupe(u8, clean_org));
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
            const full_name = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{username, short_name}) catch return null;
            return full_name;
        }
        
        // Try first organization
        if (self.github_orgs.items.len > 0) {
            const full_name = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{self.github_orgs.items[0], short_name}) catch return null;
            return full_name;
        }
        
        return null;
    }
    
    /// Set up default dependency aliases for common use cases
    fn setupDefaultAliases(self: *ZionConfig) !void {
        // Crypto libraries bundle
        var crypto_deps = std.ArrayList([]const u8).init(self.allocator);
        try crypto_deps.append(try self.allocator.dupe(u8, "ghostkellz/zcrypto"));
        try crypto_deps.append(try self.allocator.dupe(u8, "jedisct1/libsodium"));
        try crypto_deps.append(try self.allocator.dupe(u8, "ziglang/crypto"));
        try self.dependency_aliases.put(try self.allocator.dupe(u8, "crypto"), crypto_deps);
        
        // HTTP/Network libraries bundle
        var http_deps = std.ArrayList([]const u8).init(self.allocator);
        try http_deps.append(try self.allocator.dupe(u8, "karlseguin/http.zig"));
        try http_deps.append(try self.allocator.dupe(u8, "mitchellh/libxev"));
        try http_deps.append(try self.allocator.dupe(u8, "ziglang/http"));
        try self.dependency_aliases.put(try self.allocator.dupe(u8, "http"), http_deps);
        
        // Database libraries bundle
        var db_deps = std.ArrayList([]const u8).init(self.allocator);
        try db_deps.append(try self.allocator.dupe(u8, "vrischmann/zig-sqlite"));
        try db_deps.append(try self.allocator.dupe(u8, "karlseguin/pg.zig"));
        try self.dependency_aliases.put(try self.allocator.dupe(u8, "db"), db_deps);
        
        // Gaming/Graphics libraries bundle
        var game_deps = std.ArrayList([]const u8).init(self.allocator);
        try game_deps.append(try self.allocator.dupe(u8, "hexops/mach"));
        try game_deps.append(try self.allocator.dupe(u8, "ziglang/raylib"));
        try self.dependency_aliases.put(try self.allocator.dupe(u8, "game"), game_deps);
        
        // JSON/Serialization libraries bundle
        var json_deps = std.ArrayList([]const u8).init(self.allocator);
        try json_deps.append(try self.allocator.dupe(u8, "ziglang/json"));
        try json_deps.append(try self.allocator.dupe(u8, "karlseguin/json.zig"));
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
        var deps = std.ArrayList([]const u8).init(self.allocator);
        for (dependencies) |dep| {
            try deps.append(try self.allocator.dupe(u8, dep));
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
    
    const cwd = fs.cwd();
    const file = try cwd.createFile("zion.json", .{});
    defer file.close();
    
    try file.writeAll(sample_json);
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
    
    const cwd = fs.cwd();
    const file = try cwd.createFile("zion.lua", .{});
    defer file.close();
    
    try file.writeAll(sample_lua);
    std.debug.print("✅ Created sample zion.lua configuration\n", .{});
    std.debug.print("💡 This will enable Neovim integration and package shortcuts\n", .{});
    _ = allocator;
}