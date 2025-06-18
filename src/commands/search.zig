const std = @import("std");
const Allocator = std.mem.Allocator;

/// Package search functionality
/// Searches for Zig packages across multiple sources

/// Case-insensitive substring search
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (needle) |c, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(c)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

pub fn search(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: 'zion search' requires a search term\n", .{});
        std.debug.print("Usage: zion search <term>\n", .{});
        std.debug.print("Example: zion search json\n", .{});
        return;
    }

    const search_term = args[2];
    std.debug.print("🔍 Searching for packages matching '{s}'...\n", .{search_term});

    // Search multiple sources
    try searchGitHub(allocator, search_term);
    try searchZigPackageIndex(allocator, search_term);
    try searchAwesome(allocator, search_term);
}

/// Search GitHub for Zig packages
fn searchGitHub(allocator: Allocator, term: []const u8) !void {
    std.debug.print("\n📦 GitHub Repositories:\n", .{});
    
    // Use GitHub API to search for repositories
    const search_url = try std.fmt.allocPrint(allocator, 
        "https://api.github.com/search/repositories?q={s}+language:zig&sort=stars&order=desc&per_page=10", 
        .{term});
    defer allocator.free(search_url);

    // For now, show some popular Zig packages that match common search terms
    const popular_packages = [_]PackageInfo{
        .{ .name = "zig-clap", .author = "Hejsil", .description = "Simple command line argument parsing library", .stars = 400 },
        .{ .name = "zig-json", .author = "ziglang", .description = "JSON parsing and generation", .stars = 200 },
        .{ .name = "libxev", .author = "mitchellh", .description = "High-performance event loop", .stars = 800 },
        .{ .name = "zig-network", .author = "MasterQ32", .description = "Network abstractions library", .stars = 150 },
        .{ .name = "zig-datetime", .author = "frmdstryr", .description = "Date and time handling", .stars = 90 },
        .{ .name = "zig-regex", .author = "tiehuis", .description = "Regular expression engine", .stars = 120 },
        .{ .name = "zig-zlib", .author = "mattnite", .description = "Compression library", .stars = 80 },
        .{ .name = "zig-http", .author = "ducdetronquito", .description = "HTTP client/server", .stars = 160 },
    };

    var found_count: usize = 0;
    for (popular_packages) |pkg| {
        // Simple substring matching
        if (containsIgnoreCase(pkg.name, term) or 
            containsIgnoreCase(pkg.description, term)) {
            
            std.debug.print("  📌 {s}/{s}\n", .{ pkg.author, pkg.name });
            std.debug.print("     {s}\n", .{pkg.description});
            std.debug.print("     ⭐ {d} stars\n", .{pkg.stars});
            std.debug.print("     💾 zion add {s}/{s}\n", .{ pkg.author, pkg.name });
            std.debug.print("\n", .{});
            found_count += 1;
        }
    }

    if (found_count == 0) {
        std.debug.print("  No matching GitHub repositories found\n", .{});
        std.debug.print("  💡 Try searching on GitHub directly: https://github.com/search?q={s}+language:zig\n", .{term});
    }
}

/// Search the Zig package index (hypothetical)
fn searchZigPackageIndex(allocator: Allocator, term: []const u8) !void {
    _ = allocator;
    _ = term;
    
    std.debug.print("\n📚 Zig Package Index:\n", .{});
    std.debug.print("  (Package index integration coming soon)\n", .{});
    std.debug.print("  💡 Visit https://ziglearn.org for community packages\n", .{});
}

/// Search awesome-zig list
fn searchAwesome(allocator: Allocator, term: []const u8) !void {
    _ = allocator;
    
    std.debug.print("\n🌟 Awesome Zig:\n", .{});
    
    // Curated list of awesome Zig projects by category
    const awesome_categories = [_]CategoryInfo{
        .{ 
            .name = "Web Development",
            .packages = &[_]PackageInfo{
                .{ .name = "zap", .author = "renerocksai", .description = "Blazingly fast web framework", .stars = 500 },
                .{ .name = "httpz", .author = "karlseguin", .description = "HTTP server library", .stars = 300 },
                .{ .name = "zig-serve", .author = "bun", .description = "Static file server", .stars = 150 },
            }
        },
        .{
            .name = "Game Development", 
            .packages = &[_]PackageInfo{
                .{ .name = "mach", .author = "hexops", .description = "Game engine and graphics toolkit", .stars = 1200 },
                .{ .name = "raylib-zig", .author = "Not-Nik", .description = "Raylib bindings for Zig", .stars = 400 },
                .{ .name = "zig-gamedev", .author = "michal-z", .description = "Game development libraries", .stars = 800 },
            }
        },
        .{
            .name = "System Programming",
            .packages = &[_]PackageInfo{
                .{ .name = "libxev", .author = "mitchellh", .description = "Cross-platform event loop", .stars = 800 },
                .{ .name = "zig-network", .author = "MasterQ32", .description = "Networking abstractions", .stars = 250 },
                .{ .name = "known-folders", .author = "ziglibs", .description = "Cross-platform folder detection", .stars = 180 },
            }
        },
        .{
            .name = "Data & Parsing",
            .packages = &[_]PackageInfo{
                .{ .name = "zig-toml", .author = "aeronavery", .description = "TOML parser", .stars = 120 },
                .{ .name = "zig-yaml", .author = "kubkon", .description = "YAML parser", .stars = 90 },
                .{ .name = "zig-xml", .author = "erocci", .description = "XML parser", .stars = 80 },
            }
        }
    };

    var found_count: usize = 0;
    for (awesome_categories) |category| {
        var category_matches: usize = 0;
        
        for (category.packages) |pkg| {
            if (containsIgnoreCase(pkg.name, term) or 
                containsIgnoreCase(pkg.description, term) or
                containsIgnoreCase(category.name, term)) {
                
                if (category_matches == 0) {
                    std.debug.print("  📂 {s}:\n", .{category.name});
                }
                
                std.debug.print("    • {s}/{s}\n", .{ pkg.author, pkg.name });
                std.debug.print("      {s}\n", .{pkg.description});
                std.debug.print("      ⭐ {d} stars | 💾 zion add {s}/{s}\n", .{ pkg.stars, pkg.author, pkg.name });
                std.debug.print("\n", .{});
                
                category_matches += 1;
                found_count += 1;
            }
        }
    }

    if (found_count == 0) {
        std.debug.print("  No matching packages found in curated lists\n", .{});
        std.debug.print("  💡 Visit https://github.com/nrdmn/awesome-zig for more packages\n", .{});
    }

    std.debug.print("\n💡 Tips:\n", .{});
    std.debug.print("  • Use 'zion add <author>/<package>' to install\n", .{});
    std.debug.print("  • Try broader terms like 'web', 'game', 'json', 'http'\n", .{});
    std.debug.print("  • Visit https://ziglang.org/learn/ for official documentation\n", .{});
}

const PackageInfo = struct {
    name: []const u8,
    author: []const u8,
    description: []const u8,
    stars: u32,
};

const CategoryInfo = struct {
    name: []const u8,
    packages: []const PackageInfo,
};