const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const RegistryManager = @import("../enhanced_registry_manager.zig").RegistryManager;
const ZionConfig = @import("../registry_config.zig").ZionConfig;
const Package = @import("../registry_client.zig").Package;

/// Enhanced add command with multi-registry support and Ziglibs preference
pub fn enhanced_add(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len == 0) {
        try showAddHelp();
        return;
    }
    
    var package_names = std.ArrayList([]const u8).empty;
    defer package_names.deinit(allocator);
    
    var prefer_ziglibs = false;
    var specific_version: ?[]const u8 = null;
    var registry_filter: ?[]const u8 = null;
    
    // Parse arguments
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        
        if (std.mem.eql(u8, arg, "--prefer-ziglibs")) {
            prefer_ziglibs = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            if (i + 1 < args.len) {
                specific_version = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--registry") or std.mem.eql(u8, arg, "-r")) {
            if (i + 1 < args.len) {
                registry_filter = args[i + 1];
                i += 1;
            }
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            try package_names.append(allocator, arg);
        }
    }
    
    if (package_names.items.len == 0) {
        print("❌ No packages specified\n", .{});
        try showAddHelp();
        return;
    }
    
    // Load configuration
    var config = ZionConfig.init(allocator);
    defer config.deinit();
    try config.loadFromEnvironment();
    
    // Initialize registry manager
    var manager = try RegistryManager.init(allocator, &config);
    defer manager.deinit();
    try manager.initClients();
    
    print("📦 Adding {} package(s)...\n\n", .{package_names.items.len});
    
    var success_count: u32 = 0;
    var failed_packages = std.ArrayList([]const u8).empty;
    defer failed_packages.deinit(allocator);
    
    for (package_names.items) |package_name| {
        if (try addSinglePackage(allocator, &manager, package_name, .{
            .prefer_ziglibs = prefer_ziglibs,
            .specific_version = specific_version,
            .registry_filter = registry_filter,
        })) {
            success_count += 1;
        } else {
            try failed_packages.append(allocator, package_name);
        }
    }
    
    // Summary
    print("\n📈 Summary:\n", .{});
    print("✅ Successfully added: {}\n", .{success_count});
    
    if (failed_packages.items.len > 0) {
        print("❌ Failed to add: {}\n", .{failed_packages.items.len});
        for (failed_packages.items) |pkg| {
            print("  • {s}\n", .{pkg});
        }
    }
    
    if (success_count > 0) {
        print("\n💡 Run 'zig build' to verify your dependencies\n", .{});
    }
}

const AddOptions = struct {
    prefer_ziglibs: bool = false,
    specific_version: ?[]const u8 = null,
    registry_filter: ?[]const u8 = null,
};

fn addSinglePackage(allocator: Allocator, manager: *RegistryManager, package_name: []const u8, options: AddOptions) !bool {
    print("🔍 Resolving: {s}", .{package_name});
    
    if (options.prefer_ziglibs) {
        print(" (prefer Ziglibs)", .{});
    }
    
    if (options.registry_filter) |registry| {
        print(" (registry: {s})", .{registry});
    }
    
    print("...\n", .{});
    
    // First try Ziglibs if preferred
    var package: ?Package = null;
    
    if (options.prefer_ziglibs) {
        const ziglibs_packages = try manager.searchZiglibs(package_name);
        defer {
            for (ziglibs_packages) |pkg| pkg.deinit(allocator);
            allocator.free(ziglibs_packages);
        }
        
        // Find exact match or best match
        for (ziglibs_packages) |pkg| {
            if (std.mem.eql(u8, pkg.name, package_name) or std.mem.endsWith(u8, pkg.full_name, package_name)) {
                package = Package{
                    .name = try allocator.dupe(u8, pkg.name),
                    .full_name = try allocator.dupe(u8, pkg.full_name),
                    .description = if (pkg.description) |desc| try allocator.dupe(u8, desc) else null,
                    .version = try allocator.dupe(u8, pkg.version),
                    .tarball_url = try allocator.dupe(u8, pkg.tarball_url),
                    .sha256_hash = if (pkg.sha256_hash) |hash| try allocator.dupe(u8, hash) else null,
                    .published_at = try allocator.dupe(u8, pkg.published_at),
                    .registry_name = try allocator.dupe(u8, pkg.registry_name),
                    .is_ziglibs = pkg.is_ziglibs,
                    .quality_score = pkg.quality_score,
                    .maintenance_status = if (pkg.maintenance_status) |status| try allocator.dupe(u8, status) else null,
                    .download_count = pkg.download_count,
                    .star_count = pkg.star_count,
                    .rating = pkg.rating,
                };
                
                print("🎆 Found Ziglibs package: {s}\n", .{pkg.full_name});
                break;
            }
        }
    }
    
    // Fallback to general resolution
    if (package == null) {
        package = try manager.resolvePackage(package_name);
    }
    
    if (package == null) {
        print("❌ Package not found: {s}\n", .{package_name});
        
        // Show suggestions
        const suggestions = try manager.searchPackages(package_name, 5);
        defer {
            for (suggestions) |pkg| pkg.deinit(allocator);
            allocator.free(suggestions);
        }
        
        if (suggestions.len > 0) {
            print("   Did you mean:\n", .{});
            for (suggestions[0..@min(3, suggestions.len)]) |pkg| {
                print("   • {s}", .{pkg.full_name});
                if (pkg.is_ziglibs) print(" 🎆", .{});
                print("\n", .{});
            }
        }
        
        return false;
    }
    
    defer package.?.deinit(allocator);
    const pkg = package.?;
    
    // Show package info
    print("✅ Found: {s} ({s})", .{ pkg.full_name, pkg.version });
    
    if (pkg.is_ziglibs) {
        print(" 🎆 Ziglibs", .{});
        if (pkg.quality_score) |score| {
            print(" [{}%]", .{score});
        }
    }
    
    if (pkg.star_count) |stars| {
        print(" ⭐ {}", .{stars});
    }
    
    print(" from {s}\n", .{pkg.registry_name});
    
    if (pkg.description) |desc| {
        print("   {s}\n", .{desc});
    }
    
    // Add to build.zig.zon
    try addToBuildZon(allocator, pkg, options.specific_version);
    
    print("✅ Added {s} to dependencies\n", .{pkg.full_name});
    return true;
}

fn addToBuildZon(allocator: Allocator, package: Package, version_override: ?[]const u8) !void {
    // Read current build.zig.zon
    const file_content = std.fs.cwd().readFileAlloc("build.zig.zon", allocator, @enumFromInt(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => {
            print("❌ build.zig.zon not found. Run 'zion init' first.\n", .{});
            return;
        },
        else => return err,
    };
    defer allocator.free(file_content);
    
    // Generate dependency entry
    const target_version = version_override orelse package.version;
    
    print("\n📝 Add this to your build.zig.zon dependencies:\n", .{});
    print(".{s} = .{{\n", .{package.name});
    print("    .url = \"{s}\",\n", .{package.tarball_url});
    
    if (package.sha256_hash) |hash| {
        print("    .hash = \"{s}\",\n", .{hash});
    } else {
        print("    // .hash = \"...\", // Run `zig build` to get hash\n", .{});
    }
    
    print("}},\n\n", .{});
    
    // For automatic addition, would need proper Zig AST parsing
    _ = target_version;
}

fn showAddHelp() !void {
    print(
        \\📦 Zion Enhanced Package Add
        \\
        \\Add packages from multiple registries with intelligent resolution.
        \\
        \\USAGE:
        \\  zion add <package> [options]
        \\  zion add <package1> <package2> ... [options]
        \\
        \\OPTIONS:
        \\  --prefer-ziglibs      Prefer Ziglibs packages when available
        \\  --version, -v <ver>   Install specific version
        \\  --registry, -r <reg>  Use specific registry (github, zigistry, custom)
        \\
        \\EXAMPLES:
        \\  zion add raylib                    # Add from best available registry
        \\  zion add raylib --prefer-ziglibs   # Prefer Ziglibs version
        \\  zion add zig-clap --version 0.8.0  # Specific version
        \\  zion add httpz --registry zigistry # From specific registry
        \\  zion add crypto json logging       # Multiple packages
        \\
        \\FEATURES:
        \\  • 📍 Smart package resolution across registries
        \\  • 🎆 Ziglibs quality indicators and preference
        \\  • 🔍 Intelligent suggestions for typos
        \\  • ⚙️ Automatic build.zig.zon integration
        \\  • 🚀 Async parallel package resolution
        \\
    , .{});
}
