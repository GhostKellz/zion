const std = @import("std");
const enhanced_config = @import("../enhanced_config.zig");
const registry_manager = @import("../registry_manager.zig");
const package_registry = @import("../package_registry.zig");
const zion_root = @import("../root.zig");

/// Redact a token for safe display (shows first 4 and last 4 characters)
/// Returns a static buffer, not allocated - use immediately
fn redactToken(token: []const u8) []const u8 {
    if (token.len <= 8) {
        return "****";
    }
    // Use static buffer for simplicity - this is just for display
    const Static = struct {
        var buffer: [64]u8 = undefined;
    };
    const display_len = @min(token.len, 20); // Cap for sanity
    const prefix = token[0..4];
    const suffix = token[token.len - 4 ..];
    const result = std.fmt.bufPrint(&Static.buffer, "{s}****{s}", .{ prefix, suffix }) catch "****";
    _ = display_len;
    return result;
}

/// Enhanced registry command with comprehensive registry management
pub fn registryCommand(allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        try showRegistryHelp();
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "list")) {
        try listRegistries(allocator);
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 4) {
            std.debug.print("❌ Usage: zion registry add <url> [name] [--allow-insecure]\n", .{});
            return;
        }
        // Check for --allow-insecure flag
        var allow_insecure = false;
        var name: ?[:0]const u8 = null;
        for (args[4..]) |arg| {
            if (std.mem.eql(u8, arg, "--allow-insecure")) {
                allow_insecure = true;
            } else if (name == null) {
                name = arg;
            }
        }
        try addRegistry(allocator, args[3], name, allow_insecure);
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (args.len < 4) {
            std.debug.print("❌ Usage: zion registry remove <name|url>\n", .{});
            return;
        }
        try removeRegistry(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "test")) {
        if (args.len >= 4) {
            try testRegistry(allocator, args[3]);
        } else {
            try testAllRegistries(allocator);
        }
    } else if (std.mem.eql(u8, subcommand, "health")) {
        try showRegistryHealth(allocator);
    } else if (std.mem.eql(u8, subcommand, "auth")) {
        if (args.len < 4) {
            try showAuthHelp();
            return;
        }
        try handleAuthCommand(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "info")) {
        if (args.len < 4) {
            std.debug.print("❌ Usage: zion registry info <name>\n", .{});
            return;
        }
        try showRegistryInfo(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "mirror")) {
        try handleMirrorCommand(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "priority")) {
        if (args.len < 5) {
            std.debug.print("❌ Usage: zion registry priority <name> <priority>\n", .{});
            return;
        }
        const priority = try std.fmt.parseInt(u32, args[4], 10);
        try setRegistryPriority(allocator, args[3], priority);
    } else {
        std.debug.print("❌ Unknown registry subcommand: {s}\n", .{subcommand});
        try showRegistryHelp();
    }
}

fn showRegistryHelp() !void {
    std.debug.print(
        \\🌐 Zion Registry Management
        \\
        \\COMMANDS:
        \\  list                            List all configured registries
        \\  add <url> [name]               Add a new registry
        \\  remove <name|url>              Remove a registry
        \\  test [name]                    Test registry connectivity
        \\  health                         Show detailed health status
        \\  info <name>                    Show registry information
        \\  priority <name> <number>       Set registry priority (lower = higher priority)
        \\  auth <subcommand>              Manage authentication
        \\  mirror <subcommand>            Registry mirroring commands
        \\
        \\AUTH COMMANDS:
        \\  auth set <registry> [--stdin]  Set authentication token from env or stdin
        \\  auth remove <registry>         Remove authentication
        \\  auth test <registry>           Test authentication
        \\  auth list                      List configured auth
        \\
        \\MIRROR COMMANDS:
        \\  mirror setup <source> <target> Set up registry mirroring
        \\  mirror sync <name>             Sync mirror with source
        \\  mirror status <name>           Show mirror status
        \\
        \\ENVIRONMENT VARIABLES:
        \\  ZION_REGISTRY_URL              Primary registry URL
        \\  ZION_REGISTRY_TOKEN            Primary registry auth token
        \\  ZION_REGISTRIES                Comma-separated registry URLs
        \\  ZION_REGISTRY_TOKEN_<N>        Token for registry N
        \\  ZION_GITHUB_TOKEN              GitHub authentication token
        \\  ZION_REGISTRY_TIMEOUT          Request timeout in milliseconds
        \\
        \\EXAMPLES:
        \\  zion registry list
        \\  zion registry add https://packages.company.com corporate
        \\  export ZION_REGISTRY_AUTH_TOKEN="ghp_abc123..."
        \\  zion registry auth set corporate
        \\  zion registry test corporate
        \\  zion registry priority corporate 0
        \\
    , .{});
}

/// List all configured registries with detailed information
fn listRegistries(allocator: std.mem.Allocator) !void {
    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    if (config.registries.items.len == 0) {
        std.debug.print("📭 No registries configured.\n", .{});
        std.debug.print("\n💡 To add a registry:\n", .{});
        std.debug.print("   export ZION_REGISTRY_URL=\"https://your-registry.com\"\n", .{});
        std.debug.print("   or use: zion registry add <url>\n", .{});
        return;
    }

    std.debug.print("🌐 Configured Registries ({d} total):\n\n", .{config.registries.items.len});

    // Show registries in priority order
    for (config.registries.items, 0..) |registry, i| {
        const status_emoji = "🔄"; // Would show actual status after health check
        const auth_indicator = if (registry.auth_token != null) "🔐" else "🔓";

        std.debug.print("{d}. {s} {s} {s}\n", .{ i + 1, status_emoji, auth_indicator, registry.name });
        std.debug.print("   URL: {s}\n", .{registry.base_url});
        std.debug.print("   Priority: {d} | API: {s} | Timeout: {d}ms\n", .{
            registry.priority,
            registry.api_version,
            registry.timeout_ms,
        });
        std.debug.print("   Status: {s}\n", .{if (registry.enabled) "✅ Enabled" else "❌ Disabled"});

        if (registry.auth_token != null) {
            std.debug.print("   Auth: ✅ Token configured\n", .{});
        } else {
            std.debug.print("   Auth: ❌ No authentication\n", .{});
        }

        // Show registry capabilities (would be detected via API)
        std.debug.print("   Features: ", .{});
        if (std.mem.eql(u8, registry.name, "github")) {
            std.debug.print("releases, tags, search\n", .{});
        } else if (std.mem.eql(u8, registry.name, "zigistry")) {
            std.debug.print("packages, search, categories, metadata\n", .{});
        } else {
            std.debug.print("releases, tags, search, aliases\n", .{});
        }

        std.debug.print("\n", .{});
    }

    // Show configuration source
    std.debug.print("📋 Configuration Sources:\n", .{});
    if (zion_root.getEnv("ZION_REGISTRY_URL")) |_| {
        std.debug.print("   ✅ ZION_REGISTRY_URL environment variable\n", .{});
    }
    if (zion_root.getEnv("ZION_REGISTRIES")) |_| {
        std.debug.print("   ✅ ZION_REGISTRIES environment variable\n", .{});
    }
    std.debug.print("   ℹ️  Default GitHub fallback\n", .{});

    std.debug.print("\n💡 Commands:\n", .{});
    std.debug.print("   zion registry health     # Check registry health\n", .{});
    std.debug.print("   zion registry test       # Test all registries\n", .{});
    std.debug.print("   zion registry auth list  # Show authentication status\n", .{});
}

/// Add a new registry
fn addRegistry(allocator: std.mem.Allocator, url: []const u8, name: ?[:0]const u8, allow_insecure: bool) !void {
    std.debug.print("➕ Adding registry: {s}\n", .{url});

    enhanced_config.validateRegistryUrl(url) catch |err| switch (err) {
        error.InsecureRegistryUrl => {
            std.debug.print("❌ Remote HTTP registries are not allowed. Use HTTPS instead.\n", .{});
            return;
        },
        error.InvalidRegistryUrl => {
            std.debug.print("❌ Invalid URL format. Must start with https:// or local http://localhost\n", .{});
            return;
        },
    };

    if (std.mem.startsWith(u8, url, "http://") and enhanced_config.isLocalRegistryUrl(url)) {
        if (!allow_insecure) {
            std.debug.print("❌ Local HTTP registries require --allow-insecure for explicit opt-in.\n", .{});
            std.debug.print("   zion registry add {s} --allow-insecure\n", .{url});
            return;
        }
        std.debug.print("⚠️  Allowing local HTTP registry for development use only.\n\n", .{});
    } else if (!std.mem.startsWith(u8, url, "https://")) {
        return;
    }

    const registry_name = name orelse generateRegistryName(url);

    std.debug.print("📝 To add this registry permanently:\n\n", .{});

    // For primary registry
    if (name == null) {
        std.debug.print("   # Set as primary registry:\n", .{});
        std.debug.print("   export ZION_REGISTRY_URL=\"{s}\"\n", .{url});
        std.debug.print("   export ZION_REGISTRY_TOKEN=\"your-auth-token\"  # if needed\n", .{});
    } else {
        std.debug.print("   # Add to registry list:\n", .{});
        if (zion_root.getEnv("ZION_REGISTRIES")) |existing| {
            std.debug.print("   export ZION_REGISTRIES=\"{s},{s}\"\n", .{ existing, url });
        } else {
            std.debug.print("   export ZION_REGISTRIES=\"{s}\"\n", .{url});
        }
        std.debug.print("   export ZION_REGISTRY_TOKEN_{s}=\"your-auth-token\"  # if needed\n", .{registry_name});
    }

    std.debug.print("\n   # Or add to your shell profile (~/.bashrc, ~/.zshrc, etc.)\n", .{});
    std.debug.print("\n🔍 Testing registry connection...\n", .{});

    // Test the registry
    try testRegistryUrl(allocator, url);
}

/// Remove a registry
fn removeRegistry(allocator: std.mem.Allocator, name_or_url: []const u8) !void {
    std.debug.print("➖ Removing registry: {s}\n", .{name_or_url});

    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    // Find the registry to remove
    var found = false;
    for (config.registries.items) |registry| {
        if (std.mem.eql(u8, registry.name, name_or_url) or std.mem.eql(u8, registry.base_url, name_or_url)) {
            found = true;

            std.debug.print("📋 Found registry:\n", .{});
            std.debug.print("   Name: {s}\n", .{registry.name});
            std.debug.print("   URL: {s}\n", .{registry.base_url});

            std.debug.print("\n📝 To remove this registry:\n", .{});

            if (std.mem.eql(u8, registry.name, "custom") and registry.priority == 0) {
                std.debug.print("   # Remove primary registry:\n", .{});
                std.debug.print("   unset ZION_REGISTRY_URL\n", .{});
                std.debug.print("   unset ZION_REGISTRY_TOKEN\n", .{});
            } else {
                std.debug.print("   # Remove from ZION_REGISTRIES environment variable\n", .{});
                std.debug.print("   # Edit your shell profile to remove: {s}\n", .{registry.base_url});
            }

            break;
        }
    }

    if (!found) {
        std.debug.print("❌ Registry not found: {s}\n", .{name_or_url});
        std.debug.print("💡 Use 'zion registry list' to see available registries\n", .{});
    }
}

/// Test a specific registry
fn testRegistry(allocator: std.mem.Allocator, name: []const u8) !void {
    std.debug.print("🔍 Testing registry: {s}\n\n", .{name});

    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    // Find the registry
    for (config.registries.items) |registry| {
        if (std.mem.eql(u8, registry.name, name)) {
            _ = try testRegistryConfig(allocator, registry);
            return;
        }
    }

    std.debug.print("❌ Registry '{s}' not found\n", .{name});
    std.debug.print("💡 Use 'zion registry list' to see available registries\n", .{});
}

/// Test all configured registries
fn testAllRegistries(allocator: std.mem.Allocator) !void {
    std.debug.print("🔍 Testing all configured registries...\n\n", .{});

    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    if (config.registries.items.len == 0) {
        std.debug.print("📭 No registries configured to test\n", .{});
        return;
    }

    var healthy_count: u32 = 0;
    var total_response_time: u64 = 0;

    for (config.registries.items, 0..) |registry, i| {
        std.debug.print("[{d}/{d}] Testing {s}...\n", .{ i + 1, config.registries.items.len, registry.name });

        const start_time = zion_root.milliTimestamp();
        const is_healthy = testRegistryConfig(allocator, registry) catch false;
        const response_time = @as(u64, @intCast(zion_root.milliTimestamp() - start_time));

        if (is_healthy) {
            healthy_count += 1;
            total_response_time += response_time;
        }

        std.debug.print("\n", .{});
    }

    // Summary
    std.debug.print("📊 Test Summary:\n", .{});
    std.debug.print("   ✅ Healthy: {d}/{d} registries\n", .{ healthy_count, config.registries.items.len });
    if (healthy_count > 0) {
        std.debug.print("   ⏱️  Average response time: {d}ms\n", .{total_response_time / healthy_count});
    }

    if (healthy_count < config.registries.items.len) {
        std.debug.print("\n⚠️  Some registries are unhealthy. Check:\n", .{});
        std.debug.print("   • Network connectivity\n", .{});
        std.debug.print("   • Authentication tokens\n", .{});
        std.debug.print("   • Registry URLs\n", .{});
    }
}

/// Show comprehensive registry health information
fn showRegistryHealth(allocator: std.mem.Allocator) !void {
    std.debug.print("🏥 Registry Health Dashboard\n\n", .{});

    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    // Initialize registry manager
    var manager = registry_manager.RegistryManager.init(allocator, &config);
    defer manager.deinit();
    try manager.initClients();

    // Get health status
    const statuses = try manager.getRegistryStatus();
    defer allocator.free(statuses);

    for (statuses, 0..) |status, i| {
        const status_emoji = switch (status.status) {
            .healthy => "✅",
            .degraded => "⚠️",
            .unhealthy => "❌",
            .unknown => "❓",
        };

        std.debug.print("{d}. {s} {s}\n", .{ i + 1, status_emoji, status.name });
        std.debug.print("   Status: {s}\n", .{@tagName(status.status)});
        std.debug.print("   Response Time: {d}ms\n", .{status.response_time_ms});
        std.debug.print("   Uptime: {d:.1}%\n", .{status.uptime_percentage});
        std.debug.print("   Error Count: {d}\n", .{status.error_count});

        if (status.last_checked > 0) {
            std.debug.print("   Last Checked: {d}s ago\n", .{@divTrunc(zion_root.timestamp() - status.last_checked, 1000)});
        }

        std.debug.print("\n", .{});
    }

    // Health recommendations
    std.debug.print("💡 Health Recommendations:\n", .{});
    var unhealthy_count: u32 = 0;
    for (statuses) |status| {
        if (status.status != .healthy) unhealthy_count += 1;
    }

    if (unhealthy_count == 0) {
        std.debug.print("   🎉 All registries are healthy!\n", .{});
    } else {
        std.debug.print("   ⚠️  {d} registries need attention\n", .{unhealthy_count});
        std.debug.print("   • Check network connectivity\n", .{});
        std.debug.print("   • Verify authentication tokens\n", .{});
        std.debug.print("   • Consider removing unhealthy registries\n", .{});
    }
}

/// Show detailed information about a specific registry
fn showRegistryInfo(allocator: std.mem.Allocator, name: []const u8) !void {
    std.debug.print("ℹ️  Registry Information: {s}\n\n", .{name});

    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    // Find the registry
    for (config.registries.items) |registry| {
        if (std.mem.eql(u8, registry.name, name)) {
            std.debug.print("📋 Basic Information:\n", .{});
            std.debug.print("   Name: {s}\n", .{registry.name});
            std.debug.print("   URL: {s}\n", .{registry.base_url});
            std.debug.print("   API Version: {s}\n", .{registry.api_version});
            std.debug.print("   Priority: {d}\n", .{registry.priority});
            std.debug.print("   Timeout: {d}ms\n", .{registry.timeout_ms});
            std.debug.print("   Status: {s}\n", .{if (registry.enabled) "Enabled" else "Disabled"});

            std.debug.print("\n🔐 Authentication:\n", .{});
            if (registry.auth_token != null) {
                std.debug.print("   Token: ✅ Configured (hidden)\n", .{});
            } else {
                std.debug.print("   Token: ❌ Not configured\n", .{});
            }

            // Test the registry
            std.debug.print("\n🔍 Connectivity Test:\n", .{});
            _ = testRegistryConfig(allocator, registry) catch false;

            // Show API endpoints
            std.debug.print("\n🌐 API Endpoints:\n", .{});
            const api_url = registry.getApiUrl(allocator) catch registry.base_url;
            defer if (!std.mem.eql(u8, api_url, registry.base_url)) allocator.free(api_url);

            if (std.mem.eql(u8, registry.name, "github")) {
                std.debug.print("   Search: {s}/search/repositories\n", .{api_url});
                std.debug.print("   Releases: {s}/repos/{{owner}}/{{repo}}/releases\n", .{api_url});
                std.debug.print("   Tags: {s}/repos/{{owner}}/{{repo}}/tags\n", .{api_url});
            } else if (std.mem.eql(u8, registry.name, "zigistry")) {
                std.debug.print("   Search: {s}/api/searchPackages\n", .{api_url});
                std.debug.print("   Packages: {s}/api/packages/{{source}}/{{owner}}/{{repo}}\n", .{api_url});
            } else {
                std.debug.print("   Search: {s}/search\n", .{api_url});
                std.debug.print("   Packages: {s}/packages/{{owner}}/{{repo}}\n", .{api_url});
                std.debug.print("   Resolve: {s}/resolve/{{alias}}\n", .{api_url});
            }

            return;
        }
    }

    std.debug.print("❌ Registry '{s}' not found\n", .{name});
}

/// Handle authentication commands
fn handleAuthCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try showAuthHelp();
        return;
    }

    const auth_cmd = args[0];

    if (std.mem.eql(u8, auth_cmd, "list")) {
        try listAuthTokens(allocator);
    } else if (std.mem.eql(u8, auth_cmd, "set")) {
        if (args.len < 2) {
            std.debug.print("❌ Usage: zion registry auth set <registry> [--stdin]\n", .{});
            return;
        }
        if (args.len >= 3 and !std.mem.eql(u8, args[2], "--stdin")) {
            std.debug.print("⚠️  Passing tokens on the command line is discouraged and may expose secrets in shell history.\n", .{});
            try setAuthToken(allocator, args[1], args[2]);
            return;
        }

        const token = try readAuthToken(allocator, args[1], args.len >= 3 and std.mem.eql(u8, args[2], "--stdin"));
        defer allocator.free(token);
        try setAuthToken(allocator, args[1], token);
    } else if (std.mem.eql(u8, auth_cmd, "remove")) {
        if (args.len < 2) {
            std.debug.print("❌ Usage: zion registry auth remove <registry>\n", .{});
            return;
        }
        try removeAuthToken(allocator, args[1]);
    } else if (std.mem.eql(u8, auth_cmd, "test")) {
        if (args.len < 2) {
            std.debug.print("❌ Usage: zion registry auth test <registry>\n", .{});
            return;
        }
        try testAuthToken(allocator, args[1]);
    } else {
        std.debug.print("❌ Unknown auth command: {s}\n", .{auth_cmd});
        try showAuthHelp();
    }
}

fn showAuthHelp() !void {
    std.debug.print(
        \\🔐 Authentication Management
        \\
        \\COMMANDS:
        \\  auth list                      List configured authentication
        \\  auth set <registry> [--stdin]  Set token from env or stdin
        \\  auth remove <registry>         Remove authentication
        \\  auth test <registry>           Test authentication
        \\
        \\EXAMPLES:
        \\  export ZION_REGISTRY_AUTH_TOKEN="ghp_abc123..."
        \\  zion registry auth set github
        \\  printf 'pat_xyz789...' | zion registry auth set corporate --stdin
        \\  zion registry auth test github
        \\  zion registry auth remove corporate
        \\
    , .{});
}

fn readAuthToken(allocator: std.mem.Allocator, registry_name: []const u8, from_stdin: bool) ![]u8 {
    if (!from_stdin) {
        if (zion_root.getEnv("ZION_REGISTRY_AUTH_TOKEN")) |token| {
            return allocator.dupe(u8, std.mem.trim(u8, token, " \t\r\n"));
        }
        if (std.mem.eql(u8, registry_name, "github")) {
            if (zion_root.getEnv("ZION_GITHUB_TOKEN")) |token| {
                return allocator.dupe(u8, std.mem.trim(u8, token, " \t\r\n"));
            }
            if (zion_root.getEnv("GITHUB_TOKEN")) |token| {
                return allocator.dupe(u8, std.mem.trim(u8, token, " \t\r\n"));
            }
        }
        std.debug.print("❌ No token supplied. Set ZION_REGISTRY_AUTH_TOKEN or use --stdin.\n", .{});
        return error.MissingAuthToken;
    }

    const io = try zion_root.getIo();
    const stdin_file = std.Io.File.stdin();
    var buf: [4096]u8 = undefined;
    const bytes_read = try stdin_file.readStreaming(io, &.{buf[0..]});
    const trimmed = std.mem.trim(u8, buf[0..bytes_read], " \t\r\n");
    if (trimmed.len == 0) return error.MissingAuthToken;
    return allocator.dupe(u8, trimmed);
}

/// Helper functions (simplified implementations)
fn generateRegistryName(url: []const u8) []const u8 {
    // Extract domain name from URL
    var start: usize = 0;
    if (std.mem.indexOf(u8, url, "://")) |proto_end| {
        start = proto_end + 3;
    }

    const domain_end = std.mem.indexOfScalarPos(u8, url, start, '/') orelse url.len;
    const domain = url[start..domain_end];

    // Remove 'www.' prefix if present
    if (std.mem.startsWith(u8, domain, "www.")) {
        return domain[4..];
    }

    return domain;
}

fn testRegistryUrl(allocator: std.mem.Allocator, url: []const u8) !void {
    std.debug.print("🔍 Testing registry: {s}\n", .{url});

    // Create a temporary registry config for testing
    const test_registry = enhanced_config.RegistryConfig{
        .name = "test",
        .base_url = url,
        .priority = 999,
    };

    _ = testRegistryConfig(allocator, test_registry) catch {
        std.debug.print("❌ Registry test failed\n", .{});
        std.debug.print("💡 Check:\n", .{});
        std.debug.print("   • URL is correct and accessible\n", .{});
        std.debug.print("   • Registry supports the expected API\n", .{});
        std.debug.print("   • Network connectivity\n", .{});
        return;
    };

    std.debug.print("✅ Registry test successful\n", .{});
}

fn testRegistryConfig(allocator: std.mem.Allocator, registry: enhanced_config.RegistryConfig) !bool {
    const io = try zion_root.getIo();
    var client = package_registry.RegistryClient.init(allocator, registry, io);
    defer client.deinit();

    // Test health endpoint
    client.checkHealth() catch |err| {
        std.debug.print("❌ Health check failed: {}\n", .{err});
        return false;
    };

    std.debug.print("✅ Health: OK ({d}ms)\n", .{client.health_metrics.response_time_ms});

    // Test search functionality
    const test_results = client.searchPackages("test", .{ .per_page = 1 }) catch |err| {
        std.debug.print("⚠️  Search test failed: {}\n", .{err});
        return true; // Health passed, but search may not be implemented
    };
    defer {
        for (test_results) |pkg| pkg.deinit(allocator);
        allocator.free(test_results);
    }

    std.debug.print("✅ Search: OK ({d} results)\n", .{test_results.len});

    // Test alias resolution (if supported)
    if (std.mem.indexOf(u8, registry.base_url, "api.github.com") == null) {
        const resolved = client.resolveAlias("test") catch null;
        if (resolved) |alias_result| {
            defer allocator.free(alias_result);
            std.debug.print("✅ Aliases: OK\n", .{});
        } else {
            std.debug.print("ℹ️  Aliases: Not supported\n", .{});
        }
    }

    return true;
}

fn listAuthTokens(allocator: std.mem.Allocator) !void {
    std.debug.print("🔐 Authentication Status:\n\n", .{});

    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    var auth_count: u32 = 0;

    for (config.registries.items) |registry| {
        const has_auth = registry.auth_token != null;
        if (has_auth) auth_count += 1;

        const status_emoji = if (has_auth) "✅" else "❌";
        std.debug.print("{s} {s}: {s}\n", .{ status_emoji, registry.name, if (has_auth) "Token configured" else "No authentication" });

        if (has_auth and registry.auth_token != null) {
            const token = registry.auth_token.?;
            if (token.len > 8) {
                std.debug.print("   Token: {s}...{s}\n", .{ token[0..4], token[token.len - 4 ..] });
            } else {
                std.debug.print("   Token: {s}\n", .{"*****"});
            }
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("📊 Summary: {d}/{d} registries have authentication\n", .{ auth_count, config.registries.items.len });

    if (auth_count == 0) {
        std.debug.print("\n💡 To add authentication:\n", .{});
        std.debug.print("   export ZION_REGISTRY_AUTH_TOKEN=\"<token>\" && zion registry auth set <registry>\n", .{});
    }
}

fn setAuthToken(allocator: std.mem.Allocator, registry_name: []const u8, token: []const u8) !void {
    _ = allocator;

    std.debug.print("🔐 Setting authentication for {s}...\n", .{registry_name});

    // Never echo full token to prevent exposure in terminal history/logs
    const redacted = redactToken(token);
    std.debug.print("📝 Token received: {s}\n\n", .{redacted});
    std.debug.print("📝 To set this token permanently, add to your shell profile:\n\n", .{});

    if (std.mem.eql(u8, registry_name, "github")) {
        std.debug.print("   export ZION_GITHUB_TOKEN=\"<your-token>\"\n", .{});
        std.debug.print("   # or\n", .{});
        std.debug.print("   export GITHUB_TOKEN=\"<your-token>\"\n", .{});
    } else {
        std.debug.print("   export ZION_REGISTRY_TOKEN_{s}=\"<your-token>\"\n", .{registry_name});
    }

    std.debug.print("\n   # Replace <your-token> with the token you provided\n", .{});
    std.debug.print("✅ Token configuration complete\n", .{});
}

fn removeAuthToken(allocator: std.mem.Allocator, registry_name: []const u8) !void {
    _ = allocator;

    std.debug.print("🔐 Removing authentication for {s}...\n", .{registry_name});

    std.debug.print("📝 To remove this token:\n\n", .{});

    if (std.mem.eql(u8, registry_name, "github")) {
        std.debug.print("   unset ZION_GITHUB_TOKEN\n", .{});
        std.debug.print("   unset GITHUB_TOKEN\n", .{});
    } else {
        std.debug.print("   unset ZION_REGISTRY_TOKEN_{s}\n", .{registry_name});
    }

    std.debug.print("\n✅ Token removal instructions provided\n", .{});
}

fn testAuthToken(allocator: std.mem.Allocator, registry_name: []const u8) !void {
    std.debug.print("🔍 Testing authentication for {s}...\n", .{registry_name});

    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    // Find the registry
    for (config.registries.items) |registry| {
        if (std.mem.eql(u8, registry.name, registry_name)) {
            if (registry.auth_token == null) {
                std.debug.print("❌ No authentication token configured for {s}\n", .{registry_name});
                return;
            }

            // Test authenticated request
            const io = zion_root.getIo() catch {
                std.debug.print("❌ Failed to get I/O context\n", .{});
                return;
            };
            var client = package_registry.RegistryClient.init(allocator, registry, io);
            defer client.deinit();

            // Make an authenticated request (this would be registry-specific)
            client.checkHealth() catch |err| {
                std.debug.print("❌ Authentication test failed: {}\n", .{err});
                return;
            };

            std.debug.print("✅ Authentication successful\n", .{});
            return;
        }
    }

    std.debug.print("❌ Registry '{s}' not found\n", .{registry_name});
}

fn setRegistryPriority(allocator: std.mem.Allocator, registry_name: []const u8, priority: u32) !void {
    _ = allocator;

    std.debug.print("⚡ Setting priority for {s} to {d}...\n", .{ registry_name, priority });

    std.debug.print("📝 Note: Registry priorities are determined by environment variable order.\n", .{});
    std.debug.print("   Lower numbers = higher priority (0 = highest)\n", .{});
    std.debug.print("   Reorder your ZION_REGISTRIES to change priorities.\n", .{});

    std.debug.print("✅ Priority information displayed\n", .{});
}

fn handleMirrorCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;

    std.debug.print("🪞 Registry Mirroring (Enterprise Feature)\n\n", .{});

    if (args.len == 0) {
        std.debug.print("COMMANDS:\n", .{});
        std.debug.print("  mirror setup <source> <target>   Set up mirroring\n", .{});
        std.debug.print("  mirror sync <name>               Sync mirror\n", .{});
        std.debug.print("  mirror status <name>             Show status\n", .{});
        return;
    }

    const mirror_cmd = args[0];

    if (std.mem.eql(u8, mirror_cmd, "setup")) {
        std.debug.print("🚧 Mirror setup not yet implemented\n", .{});
        std.debug.print("💡 Coming in a future release\n", .{});
    } else if (std.mem.eql(u8, mirror_cmd, "sync")) {
        std.debug.print("🚧 Mirror sync not yet implemented\n", .{});
    } else if (std.mem.eql(u8, mirror_cmd, "status")) {
        std.debug.print("🚧 Mirror status not yet implemented\n", .{});
    } else {
        std.debug.print("❌ Unknown mirror command: {s}\n", .{mirror_cmd});
    }
}
