const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const RegistryManager = @import("../enhanced_registry_manager.zig").RegistryManager;
const ZionConfig = @import("../registry_config.zig").ZionConfig;
const Package = @import("../registry_client.zig").Package;
const zion_root = @import("../root.zig");
const Dir = std.Io.Dir;
const Io = std.Io;

/// Ziglibs integration commands for enhanced package discovery
pub fn ziglibs(allocator: Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try showZiglibsHelp();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "list")) {
        const category = if (args.len > 1) args[1] else null;
        try listZiglibsPackages(allocator, category);
    } else if (std.mem.eql(u8, subcommand, "search")) {
        if (args.len < 2) {
            print("❌ Usage: zion ziglibs search <query>\n", .{});
            return;
        }
        try searchZiglibsPackages(allocator, args[1]);
    } else if (std.mem.eql(u8, subcommand, "status")) {
        try showZiglibsStatus(allocator);
    } else if (std.mem.eql(u8, subcommand, "categories")) {
        try showZiglibsCategories();
    } else {
        print("❌ Unknown subcommand: {s}\n", .{subcommand});
        try showZiglibsHelp();
    }
}

fn showZiglibsHelp() !void {
    print(
        \\🌟 Zion Ziglibs Integration
        \\
        \\Enhanced package discovery for the Ziglibs community collection.
        \\
        \\COMMANDS:
        \\  zion ziglibs list [category]     Browse all ziglibs packages by category
        \\  zion ziglibs search <query>      Search within ziglibs packages only
        \\  zion ziglibs status              Show ziglibs packages in current project
        \\  zion ziglibs categories          List available categories
        \\
        \\EXAMPLES:
        \\  zion ziglibs list network        # Browse network-related ziglibs
        \\  zion ziglibs search http         # Search for HTTP libraries in ziglibs
        \\  zion add raylib --prefer-ziglibs # Prefer ziglibs version if available
        \\
        \\FEATURES:
        \\  • ✅ Quality indicators and maintenance status
        \\  • ⭐ Community-vetted packages with consistent APIs
        \\  • 📚 Enhanced documentation and examples
        \\  • 🔒 Reliable, well-maintained packages
        \\
    , .{});
}

fn listZiglibsPackages(allocator: Allocator, category: ?[]const u8) !void {
    print("📦 Ziglibs Package Collection\n\n", .{});

    // Load configuration
    var config = ZionConfig.init(allocator);
    defer config.deinit();
    try config.loadFromEnvironment();

    // Initialize registry manager
    var manager = try RegistryManager.init(allocator, &config);
    defer manager.deinit();
    try manager.initClients();

    // Search for ziglibs packages
    const search_query = if (category) |cat|
        try std.fmt.allocPrint(allocator, "{s}", .{cat})
    else
        null;
    defer if (search_query) |q| allocator.free(q);

    const packages = try manager.searchZiglibs(search_query);
    defer {
        for (packages) |pkg| pkg.deinit(allocator);
        allocator.free(packages);
    }

    if (packages.len == 0) {
        if (category) |cat| {
            print("❌ No ziglibs packages found in category '{s}'\n", .{cat});
        } else {
            print("❌ No ziglibs packages found\n", .{});
        }
        return;
    }

    // Group packages by category (based on name/description)
    var categorized = std.StringHashMap(std.ArrayList(Package)).init(allocator);
    defer {
        var it = categorized.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        categorized.deinit();
    }

    for (packages) |pkg| {
        const cat = try inferCategory(allocator, pkg);

        var entry = try categorized.getOrPutValue(cat, std.ArrayList(Package).empty);
        try entry.value_ptr.append(allocator, pkg);
    }

    // Display categorized packages
    var it = categorized.iterator();
    while (it.next()) |entry| {
        print("📁 {s}\n", .{entry.key_ptr.*});
        print("{s}\n", .{"─" ** 40});

        for (entry.value_ptr.items) |pkg| {
            print("  📦 {s}", .{pkg.full_name});

            if (pkg.quality_score) |score| {
                print(" 🎆 Quality: {}%", .{score});
            }

            if (pkg.maintenance_status) |status| {
                print(" 🔧 {s}", .{status});
            }

            print("\n", .{});

            if (pkg.description) |desc| {
                print("     {s}\n", .{desc});
            }

            print("     Version: {s} | Published: {s}\n", .{ pkg.version, pkg.published_at });
            print("\n", .{});
        }

        print("\n", .{});
    }

    print("💡 Use 'zion add <package>' to install any package\n", .{});
    print("💡 Use 'zion add <package> --prefer-ziglibs' to prefer ziglibs versions\n", .{});
}

fn searchZiglibsPackages(allocator: Allocator, query: []const u8) !void {
    print("🔍 Searching Ziglibs for: {s}\n\n", .{query});

    // Load configuration
    var config = ZionConfig.init(allocator);
    defer config.deinit();
    try config.loadFromEnvironment();

    // Initialize registry manager
    var manager = try RegistryManager.init(allocator, &config);
    defer manager.deinit();
    try manager.initClients();

    const packages = try manager.searchZiglibs(query);
    defer {
        for (packages) |pkg| pkg.deinit(allocator);
        allocator.free(packages);
    }

    if (packages.len == 0) {
        print("❌ No ziglibs packages found for: {s}\n", .{query});
        print("💡 Try 'zion search {s}' for broader search across all registries\n", .{query});
        return;
    }

    print("🎆 Found {} high-quality ziglibs packages:\n\n", .{packages.len});

    for (packages, 0..) |pkg, i| {
        print("{}. 📦 {s}", .{ i + 1, pkg.full_name });

        if (pkg.quality_score) |score| {
            print(" [🎆 {}%]", .{score});
        }

        print("\n", .{});

        if (pkg.description) |desc| {
            print("   {s}\n", .{desc});
        }

        print("   Version: {s}", .{pkg.version});

        if (pkg.maintenance_status) |status| {
            print(" | Status: 🔧 {s}", .{status});
        }

        if (pkg.download_count) |downloads| {
            print(" | Downloads: 📊 {}", .{downloads});
        }

        print("\n\n", .{});
    }

    print("📦 Add with: zion add <package-name>\n", .{});
}

fn showZiglibsStatus(allocator: Allocator) !void {
    print("📈 Ziglibs Status for Current Project\n\n", .{});

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Read build.zig.zon to check current dependencies
    const zon_content = cwd.readFileAlloc(io, "build.zig.zon", allocator, Io.Limit.limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => {
            print("❌ No build.zig.zon found. Run 'zion init' first.\n", .{});
            return;
        },
        else => return err,
    };
    defer allocator.free(zon_content);

    // Simple parsing to find ziglibs dependencies
    var ziglibs_deps: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (ziglibs_deps.items) |dep| allocator.free(dep);
        ziglibs_deps.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, zon_content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Look for ziglibs dependencies
        if (std.mem.indexOf(u8, trimmed, "ziglibs/") != null) {
            // Extract package name
            if (std.mem.indexOf(u8, trimmed, "//")) |start| {
                if (std.mem.indexOf(u8, trimmed[start..], "ziglibs/")) |ziglibs_start| {
                    const dep_start = start + ziglibs_start;
                    if (std.mem.indexOf(u8, trimmed[dep_start..], "/archive")) |end| {
                        const dep_name = trimmed[dep_start .. dep_start + end];
                        try ziglibs_deps.append(allocator, try allocator.dupe(u8, dep_name));
                    }
                }
            }
        }
    }

    if (ziglibs_deps.items.len == 0) {
        print("📅 No ziglibs packages found in current project\n", .{});
        print("💡 Use 'zion ziglibs list' to browse available packages\n", .{});
        return;
    }

    print("✅ Found {} ziglibs packages in current project:\n\n", .{ziglibs_deps.items.len});

    for (ziglibs_deps.items, 0..) |dep, i| {
        print("{}. 🎆 {s}\n", .{ i + 1, dep });
    }

    print("\n💡 These are high-quality, community-maintained packages!\n", .{});
    print("🔄 Use 'zion update' to check for updates\n", .{});
}

fn showZiglibsCategories() !void {
    print(
        \\📁 Ziglibs Package Categories
        \\
        \\Available categories for browsing:
        \\
        \\📡 NETWORK & WEB:
        \\  • http       - HTTP clients and servers
        \\  • network    - Network utilities and protocols
        \\  • websocket  - WebSocket implementations
        \\
        \\📊 DATA & STORAGE:
        \\  • json       - JSON parsing and serialization
        \\  • database   - Database drivers and ORMs
        \\  • cache      - Caching solutions
        \\  • storage    - File and data storage
        \\
        \\🎮 GRAPHICS & GAME:
        \\  • graphics   - Graphics and rendering
        \\  • game       - Game development tools
        \\  • audio      - Audio processing
        \\  • ui         - User interface libraries
        \\
        \\🔐 CRYPTO & SECURITY:
        \\  • crypto     - Cryptography and hashing
        \\  • security   - Security utilities
        \\  • auth       - Authentication systems
        \\
        \\🛠️ DEVELOPMENT & TOOLS:
        \\  • testing    - Testing frameworks
        \\  • logging    - Logging libraries
        \\  • cli        - Command-line tools
        \\  • build      - Build system utilities
        \\
        \\USAGE:
        \\  zion ziglibs list network    # Browse network packages
        \\  zion ziglibs search http     # Search for HTTP packages
        \\
    , .{});
}

fn inferCategory(allocator: Allocator, package: Package) ![]const u8 {
    const name_lower = try std.ascii.allocLowerString(allocator, package.name);
    defer allocator.free(name_lower);

    const desc_lower = if (package.description) |desc|
        try std.ascii.allocLowerString(allocator, desc)
    else
        null;
    defer if (desc_lower) |desc| allocator.free(desc);

    // Network & Web
    if (std.mem.indexOf(u8, name_lower, "http") != null or
        std.mem.indexOf(u8, name_lower, "web") != null or
        std.mem.indexOf(u8, name_lower, "net") != null or
        (desc_lower != null and std.mem.indexOf(u8, desc_lower.?, "http") != null))
    {
        return try allocator.dupe(u8, "Network & Web");
    }

    // Graphics & Game
    if (std.mem.indexOf(u8, name_lower, "graphics") != null or
        std.mem.indexOf(u8, name_lower, "game") != null or
        std.mem.indexOf(u8, name_lower, "render") != null or
        std.mem.indexOf(u8, name_lower, "audio") != null or
        std.mem.indexOf(u8, name_lower, "ui") != null)
    {
        return try allocator.dupe(u8, "Graphics & Game");
    }

    // Data & Storage
    if (std.mem.indexOf(u8, name_lower, "json") != null or
        std.mem.indexOf(u8, name_lower, "db") != null or
        std.mem.indexOf(u8, name_lower, "data") != null or
        std.mem.indexOf(u8, name_lower, "cache") != null)
    {
        return try allocator.dupe(u8, "Data & Storage");
    }

    // Crypto & Security
    if (std.mem.indexOf(u8, name_lower, "crypto") != null or
        std.mem.indexOf(u8, name_lower, "hash") != null or
        std.mem.indexOf(u8, name_lower, "security") != null or
        std.mem.indexOf(u8, name_lower, "auth") != null)
    {
        return try allocator.dupe(u8, "Crypto & Security");
    }

    // Development & Tools
    if (std.mem.indexOf(u8, name_lower, "test") != null or
        std.mem.indexOf(u8, name_lower, "log") != null or
        std.mem.indexOf(u8, name_lower, "cli") != null or
        std.mem.indexOf(u8, name_lower, "build") != null)
    {
        return try allocator.dupe(u8, "Development & Tools");
    }

    return try allocator.dupe(u8, "Utilities");
}
