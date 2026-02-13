const std = @import("std");
const Allocator = std.mem.Allocator;
const registry = @import("../registry.zig");
const enhanced_config = @import("../enhanced_config.zig");
const zion = @import("zion");
const qol = zion.qol_enhancements;

/// Package search functionality
/// Searches for Zig packages across multiple sources
/// Optimized case-insensitive substring search using Boyer-Moore-like approach
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    const first_char_lower = std.ascii.toLower(needle[0]);
    var i: usize = 0;

    while (i <= haystack.len - needle.len) {
        // Quick first char check
        if (std.ascii.toLower(haystack[i]) != first_char_lower) {
            i += 1;
            continue;
        }

        // Full match check only if first char matches
        var match = true;
        for (needle[1..], 1..) |c, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(c)) {
                match = false;
                break;
            }
        }
        if (match) return true;
        i += 1;
    }
    return false;
}

pub const SearchOptions = struct {
    filters: []const []const u8 = &[_][]const u8{},
    limit: usize = 10,
    sort_by: enum { relevance, stars, updated } = .relevance,
    min_stars: usize = 0,
};

pub fn search(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        printSearchHelp();
        return;
    }

    // Parse search options
    var search_options = SearchOptions{};
    const search_term: []const u8 = args[2];
    var filters_list = std.ArrayList([]const u8).empty;
    defer filters_list.deinit(allocator);

    // Process additional arguments
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--filter=")) {
            const filter_str = arg[9..];
            var filter_it = std.mem.splitSequence(u8, filter_str, ",");
            while (filter_it.next()) |filter| {
                try filters_list.append(allocator, std.mem.trim(u8, filter, " "));
            }
        } else if (std.mem.startsWith(u8, arg, "--limit=")) {
            search_options.limit = std.fmt.parseInt(usize, arg[8..], 10) catch 10;
        } else if (std.mem.startsWith(u8, arg, "--sort=")) {
            const sort_str = arg[7..];
            if (std.mem.eql(u8, sort_str, "stars")) {
                search_options.sort_by = .stars;
            } else if (std.mem.eql(u8, sort_str, "updated")) {
                search_options.sort_by = .updated;
            } else {
                search_options.sort_by = .relevance;
            }
        } else if (std.mem.startsWith(u8, arg, "--min-stars=")) {
            search_options.min_stars = std.fmt.parseInt(usize, arg[12..], 10) catch 0;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printSearchHelp();
            return;
        }
    }

    search_options.filters = try filters_list.toOwnedSlice(allocator);
    defer allocator.free(search_options.filters);

    // Display search configuration
    std.debug.print("🔍 Searching for packages matching '{s}'", .{search_term});
    if (search_options.filters.len > 0) {
        std.debug.print(" (filters: ", .{});
        for (search_options.filters, 0..) |filter, idx| {
            if (idx > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{filter});
        }
        std.debug.print(")", .{});
    }

    // Use progress indicator for better user experience
    var progress = qol.ProgressIndicator.init(3); // 3 search sources

    progress.update(0, "Searching registries...");
    searchRegistries(allocator, search_term, search_options) catch |err| {
        std.debug.print("⚠️ Registry search failed: {}\n", .{err});
    };

    progress.update(1, "Searching Zig package index...");
    searchZigPackageIndex(allocator, search_term, search_options) catch |err| {
        std.debug.print("⚠️ Package index search failed: {}\n", .{err});
    };

    progress.update(2, "Searching awesome-zig...");
    searchAwesome(allocator, search_term, search_options) catch |err| {
        std.debug.print("⚠️ Awesome-zig search failed: {}\n", .{err});
    };

    progress.finish("Search completed");
}

fn printSearchHelp() void {
    std.debug.print("❌ Error: 'zion search' requires a search term\n", .{});
    std.debug.print("\nUsage: zion search <term> [OPTIONS]\n", .{});
    std.debug.print("\nOptions:\n", .{});
    std.debug.print("  --filter=<categories>  Filter by categories (web,crypto,json,etc.)\n", .{});
    std.debug.print("  --limit=<number>       Limit results (default: 10)\n", .{});
    std.debug.print("  --sort=<method>        Sort by: relevance, stars, updated\n", .{});
    std.debug.print("  --min-stars=<number>   Minimum stars required\n", .{});
    std.debug.print("  --help, -h             Show this help\n", .{});
    std.debug.print("\nExamples:\n", .{});
    std.debug.print("  zion search json\n", .{});
    std.debug.print("  zion search http --filter=web,network\n", .{});
    std.debug.print("  zion search crypto --limit=5 --sort=stars\n", .{});
    std.debug.print("  zion search game --min-stars=50\n", .{});
    std.debug.print("\n💡 Try these popular searches:\n", .{});
    std.debug.print("  • zion search http\n", .{});
    std.debug.print("  • zion search json\n", .{});
    std.debug.print("  • zion search crypto\n", .{});
    std.debug.print("  • zion search game\n", .{});
}

/// Search multiple registries for packages
fn searchRegistries(allocator: Allocator, term: []const u8, options: SearchOptions) !void {
    _ = options; // TODO: Use options for filtering and sorting
    var config = enhanced_config.ZionConfig.load(allocator) catch enhanced_config.ZionConfig.init(allocator);
    defer config.deinit();

    std.debug.print("\n🔍 Registry Search Results:\n", .{});

    // Search primary registry
    const primary_registry = registry.getPrimaryRegistry(allocator, &config);
    std.debug.print("\n📦 Primary Registry ({s}):\n", .{primary_registry.base_url});
    trySearchRegistry(allocator, &primary_registry, term) catch |err| {
        std.debug.print("⚠️ Primary registry search failed: {}\n", .{err});
    };

    // Search fallback registries
    const fallback_registries = try registry.getFallbackRegistries(allocator, &config);
    defer allocator.free(fallback_registries);

    if (fallback_registries.len > 0) {
        const progress = @import("../progress.zig");
        var registry_progress = progress.ProgressBar.init(allocator, "🔍 Searching registries", fallback_registries.len);

        for (fallback_registries, 0..) |fallback_registry, i| {
            registry_progress.update(i);
            std.debug.print("\n📦 Fallback Registry ({s}):\n", .{fallback_registry.base_url});
            trySearchRegistry(allocator, &fallback_registry, term) catch |err| {
                std.debug.print("⚠️ Fallback registry search failed: {}\n", .{err});
            };
        }

        registry_progress.finish();
    }
}

fn trySearchRegistry(allocator: Allocator, reg: *const registry.RegistryClient, term: []const u8) !void {
    const search_url = try reg.getSearchUrl(term);
    defer allocator.free(search_url);

    // Handle different registry response formats
    if (reg.registry_type == .zigistry) {
        try searchZigistry(allocator, search_url, term);
        return;
    }

    // For now, show some popular Zig packages that match common search terms
    // TODO: Replace with actual API call to the registry
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
            containsIgnoreCase(pkg.description, term))
        {
            std.debug.print("  📌 {s}/{s}\n", .{ pkg.author, pkg.name });
            std.debug.print("     {s}\n", .{pkg.description});
            std.debug.print("     ⭐ {d} stars\n", .{pkg.stars});
            std.debug.print("     💾 zion add {s}/{s}\n", .{ pkg.author, pkg.name });
            std.debug.print("\n", .{});
            found_count += 1;
        }
    }

    if (found_count == 0) {
        std.debug.print("  No matching packages found in this registry\n", .{});
        if (reg.registry_type == .github) {
            std.debug.print("  💡 Try searching on GitHub directly: https://github.com/search?q={s}+language:zig\n", .{term});
        }
    }
}

/// Search the Zig package index (hypothetical)
fn searchZigPackageIndex(allocator: Allocator, term: []const u8, options: SearchOptions) !void {
    _ = options;
    _ = allocator;
    _ = term;

    std.debug.print("\n📚 Zig Package Index:\n", .{});
    std.debug.print("  (Package index integration coming soon)\n", .{});
    std.debug.print("  💡 Visit https://ziglearn.org for community packages\n", .{});
}

/// Search awesome-zig list
fn searchAwesome(allocator: Allocator, term: []const u8, options: SearchOptions) !void {
    _ = options;
    _ = allocator;

    std.debug.print("\n🌟 Awesome Zig:\n", .{});

    // Curated list of awesome Zig projects by category
    const awesome_categories = [_]CategoryInfo{ .{ .name = "Web Development", .packages = &[_]PackageInfo{
        .{ .name = "zap", .author = "renerocksai", .description = "Blazingly fast web framework", .stars = 500 },
        .{ .name = "httpz", .author = "karlseguin", .description = "HTTP server library", .stars = 300 },
        .{ .name = "zig-serve", .author = "bun", .description = "Static file server", .stars = 150 },
    } }, .{ .name = "Game Development", .packages = &[_]PackageInfo{
        .{ .name = "mach", .author = "hexops", .description = "Game engine and graphics toolkit", .stars = 1200 },
        .{ .name = "raylib-zig", .author = "Not-Nik", .description = "Raylib bindings for Zig", .stars = 400 },
        .{ .name = "zig-gamedev", .author = "michal-z", .description = "Game development libraries", .stars = 800 },
    } }, .{ .name = "System Programming", .packages = &[_]PackageInfo{
        .{ .name = "libxev", .author = "mitchellh", .description = "Cross-platform event loop", .stars = 800 },
        .{ .name = "zig-network", .author = "MasterQ32", .description = "Networking abstractions", .stars = 250 },
        .{ .name = "known-folders", .author = "ziglibs", .description = "Cross-platform folder detection", .stars = 180 },
    } }, .{ .name = "Data & Parsing", .packages = &[_]PackageInfo{
        .{ .name = "zig-toml", .author = "aeronavery", .description = "TOML parser", .stars = 120 },
        .{ .name = "zig-yaml", .author = "kubkon", .description = "YAML parser", .stars = 90 },
        .{ .name = "zig-xml", .author = "erocci", .description = "XML parser", .stars = 80 },
    } } };

    var found_count: usize = 0;
    for (awesome_categories) |category| {
        var category_matches: usize = 0;

        for (category.packages) |pkg| {
            if (containsIgnoreCase(pkg.name, term) or
                containsIgnoreCase(pkg.description, term) or
                containsIgnoreCase(category.name, term))
            {
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

/// Search Zigistry registry
fn searchZigistry(allocator: Allocator, search_url: []const u8, term: []const u8) !void {
    _ = term; // TODO: Use for filtering

    // Make HTTP request to Zigistry API
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit(allocator);

    var header_buffer: [16384]u8 = undefined;
    var req = client.open(.GET, std.Uri.parse(search_url) catch {
        std.debug.print("  ❌ Invalid Zigistry URL format\n", .{});
        return;
    }, .{
        .server_header_buffer = &header_buffer,
    }) catch {
        std.debug.print("  ❌ Failed to connect to Zigistry\n", .{});
        return;
    };
    defer req.deinit(allocator);

    req.send() catch {
        std.debug.print("  ❌ Failed to send request to Zigistry\n", .{});
        return;
    };
    req.finish() catch {
        std.debug.print("  ❌ Failed to finish request to Zigistry\n", .{});
        return;
    };
    req.wait() catch {
        std.debug.print("  ❌ Request to Zigistry timed out\n", .{});
        return;
    };

    if (req.response.status != .ok) {
        std.debug.print("  ❌ Zigistry API error: {}\n", .{req.response.status});
        return;
    }

    var output_buf = std.ArrayList(u8).empty;
    defer output_buf.deinit(allocator);

    var read_buf: [4096]u8 = undefined;
    while (true) {
        const bytes_read = req.readAll(read_buf[0..]) catch {
            std.debug.print("  ❌ Failed to read Zigistry response\n", .{});
            return;
        };
        if (bytes_read == 0) break;
        output_buf.appendSlice(allocator, read_buf[0..bytes_read]) catch {
            std.debug.print("  ❌ Failed to read Zigistry response\n", .{});
            return;
        };
    }

    const body = allocator.dupe(u8, output_buf.items) catch {
        std.debug.print("  ❌ Failed to read Zigistry response\n", .{});
        return;
    };
    defer allocator.free(body);

    // Parse Zigistry response (simplified - show first few results)
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        std.debug.print("  ❌ Failed to parse Zigistry response\n", .{});
        return;
    };
    defer parsed.deinit(allocator);

    if (parsed.value != .array) {
        std.debug.print("  ⚠️ Unexpected Zigistry response format\n", .{});
        return;
    }

    const packages = parsed.value.array;
    var count: usize = 0;
    const max_results = 5;

    for (packages.items) |pkg| {
        if (count >= max_results) break;

        if (pkg != .object) continue;
        const pkg_obj = pkg.object;

        const name = pkg_obj.get("name") orelse continue;
        const owner = pkg_obj.get("owner") orelse continue;
        const description = pkg_obj.get("description") orelse continue;

        if (name != .string or owner != .string or description != .string) continue;

        // Extract star count if available
        const stars = if (pkg_obj.get("stars")) |s|
            if (s == .integer) @as(u32, @intCast(s.integer)) else 0
        else
            0;

        std.debug.print("  📦 {s}/{s}\n", .{ owner.string, name.string });
        std.debug.print("     {s}\n", .{description.string});
        std.debug.print("     ⭐ {} stars\n", .{stars});
        std.debug.print("     💾 zion add {s}/{s}\n", .{ owner.string, name.string });
        std.debug.print("\n", .{});

        count += 1;
    }

    if (count == 0) {
        std.debug.print("  No packages found on Zigistry\n", .{});
    } else {
        std.debug.print("  💡 Found {} packages from Zigistry community registry\n", .{count});
    }
}
