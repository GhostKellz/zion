const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Configuration manager for Zion
pub const Config = struct {
    // Security settings
    verify_signatures: bool = false,
    require_signatures: bool = false,
    trusted_signers: [][]const u8 = &[_][]const u8{},

    // Performance settings
    max_cache_size_mb: u32 = 500,
    cache_max_age_hours: u32 = 24,
    parallel_downloads: u8 = 4,
    compression_enabled: bool = true,

    // Network settings
    download_timeout_seconds: u32 = 30,
    max_retries: u8 = 3,

    allocator: Allocator,

    pub fn deinit(self: *Config) void {
        for (self.trusted_signers) |signer| {
            self.allocator.free(signer);
        }
        self.allocator.free(self.trusted_signers);
    }

    /// Load configuration from file or create default
    pub fn load(allocator: Allocator) !Config {
        const config_path = ".zion/config.json";

        // If config file doesn't exist, return default config
        const file = fs.cwd().openFile(config_path, .{}) catch {
            return Config{ .allocator = allocator };
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        // Parse JSON config (simplified implementation)
        // In a real implementation, you'd use std.json
        var config = Config{ .allocator = allocator };

        // Simple parsing for demonstration
        if (std.mem.indexOf(u8, content, "\"verify_signatures\": true")) |_| {
            config.verify_signatures = true;
        }

        return config;
    }

    /// Save configuration to file
    pub fn save(self: *const Config) !void {
        try fs.cwd().makePath(".zion");

        const file = try fs.cwd().createFile(".zion/config.json", .{});
        defer file.close();

        try file.writer().print(
            \\{{
            \\  "security": {{
            \\    "verify_signatures": {s},
            \\    "require_signatures": {s}
            \\  }},
            \\  "performance": {{
            \\    "max_cache_size_mb": {d},
            \\    "cache_max_age_hours": {d},
            \\    "parallel_downloads": {d},
            \\    "compression_enabled": {s}
            \\  }},
            \\  "network": {{
            \\    "download_timeout_seconds": {d},
            \\    "max_retries": {d}
            \\  }}
            \\}}
            \\
        , .{
            if (self.verify_signatures) "true" else "false",
            if (self.require_signatures) "true" else "false",
            self.max_cache_size_mb,
            self.cache_max_age_hours,
            self.parallel_downloads,
            if (self.compression_enabled) "true" else "false",
            self.download_timeout_seconds,
            self.max_retries,
        });
    }
};
