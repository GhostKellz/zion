const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZionConfig = @import("../enhanced_config.zig").ZionConfig;
const ConfigFormat = @import("../enhanced_config.zig").ConfigFormat;

/// Configuration management commands
pub fn config(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 3) {
        printConfigHelp();
        return;
    }
    
    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "init")) {
        return initConfig(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "get")) {
        return getConfig(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "set")) {
        return setConfig(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "show")) {
        return showConfig(allocator);
    } else if (std.mem.eql(u8, subcommand, "env")) {
        return showEnvHelp();
    } else {
        std.debug.print("❌ Unknown config subcommand: {s}\n", .{subcommand});
        printConfigHelp();
    }
}

/// Initialize configuration files
fn initConfig(allocator: Allocator, args: [][:0]u8) !void {
    const format: ConfigFormat = if (args.len > 0 and std.mem.eql(u8, args[0], "--lua"))
        .lua
    else if (args.len > 0 and std.mem.eql(u8, args[0], "--json"))
        .json
    else
        .lua; // Default to Lua for Neovim integration
    
    switch (format) {
        .lua => {
            std.debug.print("🚀 Creating Lua configuration for Neovim integration...\n", .{});
            try ZionConfig.createSampleConfig(allocator, .lua);
        },
        .json => {
            std.debug.print("⚙️  Creating JSON configuration...\n", .{});
            try ZionConfig.createSampleConfig(allocator, .json);
        },
    }
    
    std.debug.print("\n💡 Configuration created! You can now:\n", .{});
    std.debug.print("   • Use 'zion fetch mypackage' to auto-resolve your packages\n", .{});
    std.debug.print("   • Set ZION_GITHUB_USERNAME environment variable\n", .{});
    std.debug.print("   • Configure Neovim integration with the zion.lua file\n", .{});
}

/// Get a configuration value
fn getConfig(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 1) {
        std.debug.print("❌ Usage: zion config get <key>\n", .{});
        return;
    }
    
    const key = args[0];
    var zion_config = try ZionConfig.load(allocator);
    defer zion_config.deinit();
    
    if (std.mem.eql(u8, key, "github_username")) {
        if (zion_config.github_username) |username| {
            std.debug.print("{s}\n", .{username});
        } else {
            std.debug.print("(not set)\n", .{});
        }
    } else if (std.mem.eql(u8, key, "github_orgs")) {
        if (zion_config.github_orgs.items.len > 0) {
            for (zion_config.github_orgs.items, 0..) |org, i| {
                if (i > 0) std.debug.print(",", .{});
                std.debug.print("{s}", .{org});
            }
            std.debug.print("\n", .{});
        } else {
            std.debug.print("(not set)\n", .{});
        }
    } else if (std.mem.eql(u8, key, "auto_add_to_build")) {
        std.debug.print("{s}\n", .{if (zion_config.auto_add_to_build) "true" else "false"});
    } else {
        std.debug.print("❌ Unknown config key: {s}\n", .{key});
    }
}

/// Set a configuration value (simplified - would need full implementation)
fn setConfig(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 2) {
        std.debug.print("❌ Usage: zion config set <key> <value>\n", .{});
        return;
    }
    
    const key = args[0];
    const value = args[1];
    
    std.debug.print("💡 Setting {s} = {s}\n", .{ key, value });
    std.debug.print("🚧 Full implementation would modify the config file\n", .{});
    _ = allocator;
}

/// Show current configuration
fn showConfig(allocator: Allocator) !void {
    var zion_config = try ZionConfig.load(allocator);
    defer zion_config.deinit();
    
    std.debug.print("📋 Current Zion Configuration:\n\n", .{});
    
    std.debug.print("🔗 GitHub Settings:\n", .{});
    if (zion_config.github_username) |username| {
        std.debug.print("   Username: {s}\n", .{username});
    } else {
        std.debug.print("   Username: (not set)\n", .{});
    }
    
    if (zion_config.github_orgs.items.len > 0) {
        std.debug.print("   Organizations: ", .{});
        for (zion_config.github_orgs.items, 0..) |org, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{org});
        }
        std.debug.print("\n", .{});
    } else {
        std.debug.print("   Organizations: (none)\n", .{});
    }
    
    std.debug.print("\n⚙️  Package Management:\n", .{});
    std.debug.print("   Auto add to build.zig: {s}\n", .{if (zion_config.auto_add_to_build) "yes" else "no"});
    std.debug.print("   Auto update lock: {s}\n", .{if (zion_config.auto_update_lock) "yes" else "no"});
    std.debug.print("   Prefer releases: {s}\n", .{if (zion_config.prefer_releases) "yes" else "no"});
    
    std.debug.print("\n💾 Cache Settings:\n", .{});
    std.debug.print("   TTL: {d} hours\n", .{zion_config.cache_ttl_hours});
    std.debug.print("   Max size: {d} MB\n", .{zion_config.max_cache_size_mb});
    
    std.debug.print("\n🌐 Download Settings:\n", .{});
    std.debug.print("   Concurrent downloads: {d}\n", .{zion_config.concurrent_downloads});
    std.debug.print("   Timeout: {d} seconds\n", .{zion_config.download_timeout_sec});
    std.debug.print("   Retry attempts: {d}\n", .{zion_config.retry_attempts});
    
    std.debug.print("\n🔐 Security Settings:\n", .{});
    std.debug.print("   Verify signatures: {s}\n", .{if (zion_config.verify_signatures) "yes" else "no"});
    std.debug.print("   Trust level required: {s}\n", .{zion_config.trust_level_required});
    
    std.debug.print("\n🔧 Editor Integration:\n", .{});
    std.debug.print("   Neovim integration: {s}\n", .{if (zion_config.neovim_integration) "enabled" else "disabled"});
    std.debug.print("   VSCode integration: {s}\n", .{if (zion_config.vscode_integration) "enabled" else "disabled"});
}

/// Show environment variable help
fn showEnvHelp() void {
    std.debug.print("🌍 Zion Environment Variables:\n\n", .{});
    
    std.debug.print("📋 GitHub Configuration:\n", .{});
    std.debug.print("   ZION_GITHUB_USERNAME     Your GitHub username\n", .{});
    std.debug.print("   ZION_GITHUB_ORGS         Comma-separated list of organizations\n", .{});
    
    std.debug.print("\n⚙️  Behavior Settings:\n", .{});
    std.debug.print("   ZION_AUTO_ADD_TO_BUILD   Automatically modify build.zig (true/false)\n", .{});
    std.debug.print("   ZION_VERIFY_SIGNATURES   Verify package signatures (true/false)\n", .{});
    
    std.debug.print("\n💾 Cache Settings:\n", .{});
    std.debug.print("   ZION_CACHE_TTL_HOURS     Cache time-to-live in hours\n", .{});
    std.debug.print("   ZION_MAX_CACHE_SIZE_MB   Maximum cache size in MB\n", .{});
    
    std.debug.print("\n🌐 Download Settings:\n", .{});
    std.debug.print("   ZION_CONCURRENT_DOWNLOADS Number of parallel downloads\n", .{});
    
    std.debug.print("\n💡 Examples:\n", .{});
    std.debug.print("   export ZION_GITHUB_USERNAME=ghostkellz\n", .{});
    std.debug.print("   export ZION_GITHUB_ORGS=\"ghostkellz,CK-Technology\"\n", .{});
    std.debug.print("   export ZION_AUTO_ADD_TO_BUILD=true\n", .{});
    
    std.debug.print("\n🚀 Quick Setup:\n", .{});
    std.debug.print("   echo 'export ZION_GITHUB_USERNAME=ghostkellz' >> ~/.bashrc\n", .{});
    std.debug.print("   echo 'export ZION_GITHUB_ORGS=\"ghostkellz,CK-Technology\"' >> ~/.bashrc\n", .{});
}

fn printConfigHelp() void {
    std.debug.print("Zion Configuration Management\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion config <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    init [--lua|--json]   Create sample configuration file\n", .{});
    std.debug.print("    show                  Show current configuration\n", .{});
    std.debug.print("    get <key>            Get configuration value\n", .{});
    std.debug.print("    set <key> <value>    Set configuration value\n", .{});
    std.debug.print("    env                  Show environment variables help\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion config init --lua              # Create Lua config for Neovim\n", .{});
    std.debug.print("    zion config show                    # Show all settings\n", .{});
    std.debug.print("    zion config get github_username     # Get username\n", .{});
    std.debug.print("    zion config env                     # Environment variables help\n", .{});
    std.debug.print("\n💡 With configuration, you can use shortcuts like:\n", .{});
    std.debug.print("    zion fetch zcrypto     # Resolves to ghostkellz/zcrypto\n", .{});
    std.debug.print("    zion add mylib         # Resolves to your configured org/mylib\n", .{});
}