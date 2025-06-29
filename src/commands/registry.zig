const std = @import("std");
const enhanced_config = @import("../enhanced_config.zig");
const registry = @import("../registry.zig");

pub fn registryCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        try showRegistryHelp();
        return;
    }
    
    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "list")) {
        try listRegistries(allocator);
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion registry add <url>\n", .{});
            return;
        }
        try addRegistry(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion registry remove <url>\n", .{});
            return;
        }
        try removeRegistry(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "test")) {
        if (args.len >= 4) {
            try testRegistry(allocator, args[3]);
        } else {
            try testAllRegistries(allocator);
        }
    } else {
        try showRegistryHelp();
    }
}

fn showRegistryHelp() !void {
    std.debug.print(
        \\Registry Management Commands:
        \\
        \\  zion registry list              List configured registries
        \\  zion registry add <url>         Add a fallback registry
        \\  zion registry remove <url>      Remove a fallback registry  
        \\  zion registry test [url]        Test registry connectivity
        \\
        \\Environment Variables:
        \\  ZION_REGISTRY_URL              Primary registry URL
        \\  ZION_FALLBACK_REGISTRIES       Comma-separated fallback URLs
        \\  ZION_REGISTRY_TIMEOUT          Request timeout in seconds
        \\
        \\Supported Registries:
        \\  • GitHub API (api.github.com)
        \\  • Zepplin (custom Zig registry)
        \\  • Zigistry (zigistry-api.hf.space) - Community registry
        \\
        \\Examples:
        \\  zion registry add https://packages.company.com
        \\  zion registry test https://zigistry-api.hf.space
        \\  zion registry test https://api.github.com
        \\
    , .{});
}

fn listRegistries(allocator: std.mem.Allocator) !void {
    var config = enhanced_config.ZionConfig.load(allocator) catch enhanced_config.ZionConfig.init(allocator);
    defer config.deinit();
    
    std.debug.print("🔧 Registry Configuration:\n\n", .{});
    
    const primary_url = config.registry_url orelse "https://api.github.com";
    std.debug.print("📍 Primary: {s}\n", .{primary_url});
    
    if (config.fallback_registries.items.len > 0) {
        std.debug.print("🔄 Fallbacks:\n", .{});
        for (config.fallback_registries.items) |fallback| {
            std.debug.print("  • {s}\n", .{fallback});
        }
    } else {
        std.debug.print("🔄 Fallbacks: None configured\n", .{});
    }
    
    std.debug.print("\n💡 Use environment variables to configure:\n", .{});
    std.debug.print("   export ZION_REGISTRY_URL=https://your-registry.com\n", .{});
}

fn addRegistry(allocator: std.mem.Allocator, url: []const u8) !void {
    _ = allocator;
    std.debug.print("📝 To add a fallback registry, set the environment variable:\n", .{});
    std.debug.print("   export ZION_FALLBACK_REGISTRIES=\"https://api.github.com,{s}\"\n", .{url});
    std.debug.print("💡 This will be persistent in your shell configuration (.bashrc, .zshrc, etc.)\n", .{});
}

fn removeRegistry(allocator: std.mem.Allocator, url: []const u8) !void {
    _ = allocator;
    std.debug.print("🗑️  To remove a registry, update your ZION_FALLBACK_REGISTRIES environment variable\n", .{});
    std.debug.print("   Remove '{s}' from the comma-separated list\n", .{url});
}

fn testRegistry(allocator: std.mem.Allocator, url: []const u8) !void {
    std.debug.print("🧪 Testing registry: {s}\n", .{url});
    
    const reg = registry.RegistryClient.init(allocator, url, 10);
    
    // Test basic connectivity by trying to fetch a well-known endpoint
    const test_url = switch (reg.registry_type) {
        .github => try std.fmt.allocPrint(allocator, "{s}/rate_limit", .{url}),
        .zepplin => try std.fmt.allocPrint(allocator, "{s}/registry/config", .{url}),
        .zigistry => try std.fmt.allocPrint(allocator, "{s}/api/searchPackages?q=test", .{url}),
        .custom => try std.fmt.allocPrint(allocator, "{s}/", .{url}),
    };
    defer allocator.free(test_url);
    
    // Make HTTP request
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    
    var header_buffer: [4096]u8 = undefined;
    var req = client.open(.GET, std.Uri.parse(test_url) catch {
        std.debug.print("❌ Invalid URL format\n", .{});
        return;
    }, .{
        .server_header_buffer = &header_buffer,
    }) catch {
        std.debug.print("❌ Connection failed\n", .{});
        return;
    };
    defer req.deinit();
    
    req.send() catch {
        std.debug.print("❌ Request failed\n", .{});
        return;
    };
    req.finish() catch {
        std.debug.print("❌ Request finish failed\n", .{});
        return;
    };
    req.wait() catch {
        std.debug.print("❌ Request wait failed\n", .{});
        return;
    };
    
    std.debug.print("✅ Registry responding (Status: {})\n", .{req.response.status});
    std.debug.print("🔧 Registry type: {}\n", .{reg.registry_type});
    
    if (reg.supportsAliases()) {
        std.debug.print("🏷️  Supports package aliases\n", .{});
    }
}

fn testAllRegistries(allocator: std.mem.Allocator) !void {
    var config = enhanced_config.ZionConfig.load(allocator) catch enhanced_config.ZionConfig.init(allocator);
    defer config.deinit();
    
    std.debug.print("🧪 Testing all configured registries...\n\n", .{});
    
    // Test primary registry
    const primary_url = config.registry_url orelse "https://api.github.com";
    try testRegistry(allocator, primary_url);
    
    // Test fallback registries
    for (config.fallback_registries.items) |fallback| {
        std.debug.print("\n", .{});
        try testRegistry(allocator, fallback);
    }
}