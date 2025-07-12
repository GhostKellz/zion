const std = @import("std");
const Allocator = std.mem.Allocator;
const enhanced_config = @import("../enhanced_config.zig");
const registry_manager = @import("../registry_manager.zig");
const registry_v2 = @import("../registry_v2.zig");

/// Print help information for the search command
fn printSearchHelp() void {
    std.debug.print("❌ Error: 'zion search' requires a search term\n", .{});
    std.debug.print("\n📖 Usage: zion search <term> [options]\n", .{});
    std.debug.print("\nOptions:\n", .{});
    std.debug.print("  --filter=<categories>   Filter by categories (comma-separated)\n", .{});
    std.debug.print("  --license=<license>     Filter by license type\n", .{});
    std.debug.print("  --min-stars=<count>     Minimum stars required\n", .{});
    std.debug.print("  --sort=<field>          Sort by: relevance, stars, downloads, updated\n", .{});
    std.debug.print("  --registry=<name>       Search specific registry only\n", .{});
    std.debug.print("  --zig-version=<ver>     Filter by Zig version compatibility\n", .{});
    std.debug.print("  --limit=<count>         Maximum results (default: 20)\n", .{});
    std.debug.print("  --help, -h              Show this help message\n", .{});
    std.debug.print("\nExamples:\n", .{});
    std.debug.print("  zion search json\n", .{});
    std.debug.print("  zion search http --filter=web,network\n", .{});
    std.debug.print("  zion search crypto --license=MIT --min-stars=50\n", .{});
    std.debug.print("  zion search game --registry=zigistry\n", .{});
    std.debug.print("\n💡 Try these popular searches:\n", .{});
    std.debug.print("  • zion search http\n", .{});
    std.debug.print("  • zion search json\n", .{});
    std.debug.print("  • zion search crypto\n", .{});
    std.debug.print("  • zion search game\n", .{});
}

/// Enhanced search command for v0.7.0 with multi-registry support
pub fn search(allocator: Allocator, args: []const []const u8) !void {
    // Check for help first
    if (args.len >= 3 and (std.mem.eql(u8, args[2], "--help") or std.mem.eql(u8, args[2], "-h"))) {
        printSearchHelp();
        return;
    }
    
    if (args.len < 3) {
        printSearchHelp();
        return;
    }

    const search_term = args[2];
    
    // Parse search options
    var options = SearchOptions{};
    try parseSearchOptions(&options, args[3..], allocator);
    defer options.deinit(allocator);
    
    // Load configuration
    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();
    
    // Initialize registry manager
    var manager = registry_manager.RegistryManager.init(allocator, &config);
    defer manager.deinit();
    try manager.initClients();
    
    // Show search header
    std.debug.print("🔍 Searching for packages matching '{s}'", .{search_term});
    if (options.filters.categories.len > 0) {
        std.debug.print(" in categories: ", .{});
        for (options.filters.categories, 0..) |cat, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{cat});
        }
    }
    if (options.specific_registry) |registry| {
        std.debug.print(" (registry: {s})", .{registry});
    }
    std.debug.print("\n\n", .{});
    
    // Perform search
    const search_results = if (options.specific_registry) |registry_name|
        try searchSpecificRegistry(allocator, &manager, search_term, registry_name, options.filters)
    else
        try manager.searchPackages(search_term, options.filters);
    
    defer {
        for (search_results) |pkg| pkg.deinit(allocator);
        allocator.free(search_results);
    }
    
    // Display results
    if (search_results.len == 0) {
        std.debug.print("❌ No packages found matching '{s}'\n", .{search_term});
        std.debug.print("\n💡 Suggestions:\n", .{});
        std.debug.print("  • Try different search terms\n", .{});
        std.debug.print("  • Check your spelling\n", .{});
        std.debug.print("  • Remove filters to broaden the search\n", .{});
        std.debug.print("  • Search in a different registry\n", .{});
        return;
    }
    
    std.debug.print("✅ Found {d} packages:\n\n", .{search_results.len});
    
    // Group results by registry if from multiple sources
    var current_registry: []const u8 = "";
    
    for (search_results, 0..) |pkg, i| {
        // Show registry header if changed
        if (!std.mem.eql(u8, current_registry, pkg.registry_name)) {
            current_registry = pkg.registry_name;
            std.debug.print("\n🌐 From {s}:\n", .{pkg.registry_name});
            std.debug.print("{s}\n\n", .{"-" ** 60});
        }
        
        // Package header
        std.debug.print("{d}. 📦 {s}", .{ i + 1, pkg.full_name });
        if (pkg.version.len > 0 and !std.mem.eql(u8, pkg.version, "latest")) {
            std.debug.print(" (v{s})", .{pkg.version});
        }
        std.debug.print("\n", .{});
        
        // Description
        if (pkg.description) |desc| {
            // Wrap long descriptions
            const max_width = 70;
            if (desc.len > max_width) {
                std.debug.print("   {s}...\n", .{desc[0..max_width]});
            } else {
                std.debug.print("   {s}\n", .{desc});
            }
        }
        
        // Metadata line
        std.debug.print("   ", .{});
        
        // Stars
        if (pkg.stars > 0) {
            std.debug.print("⭐ {d} ", .{pkg.stars});
        }
        
        // Downloads
        if (pkg.download_count > 0) {
            std.debug.print("📥 {s} ", .{formatCount(pkg.download_count)});
        }
        
        // License
        if (pkg.license) |license| {
            std.debug.print("📜 {s} ", .{license});
        }
        
        // Author
        if (pkg.author) |author| {
            std.debug.print("👤 {s} ", .{author});
        }
        
        // Last updated
        if (pkg.last_updated.len > 0) {
            std.debug.print("🕐 {s}", .{formatDate(pkg.last_updated)});
        }
        std.debug.print("\n", .{});
        
        // Categories/Topics
        if (pkg.categories.len > 0) {
            std.debug.print("   🏷️  ", .{});
            for (pkg.categories, 0..) |cat, j| {
                if (j > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{cat});
            }
            std.debug.print("\n", .{});
        }
        
        // Zig version compatibility
        if (pkg.zig_version_min != null or pkg.zig_version_max != null) {
            std.debug.print("   🔧 Zig ", .{});
            if (pkg.zig_version_min) |min| {
                std.debug.print("{s}", .{min});
            }
            if (pkg.zig_version_max) |max| {
                if (pkg.zig_version_min != null) std.debug.print(" - ", .{});
                std.debug.print("{s}", .{max});
            }
            std.debug.print("\n", .{});
        }
        
        // Homepage/Repository
        if (pkg.homepage) |homepage| {
            std.debug.print("   🏠 {s}\n", .{homepage});
        } else if (pkg.repository_url) |repo_url| {
            std.debug.print("   📂 {s}\n", .{repo_url});
        }
        
        // Installation command
        std.debug.print("   💻 zion add {s}\n", .{pkg.full_name});
        
        std.debug.print("\n", .{});
    }
    
    // Show registry health status
    const registry_statuses = try manager.getRegistryStatus();
    defer allocator.free(registry_statuses);
    
    std.debug.print("\n📊 Registry Status:\n", .{});
    for (registry_statuses) |status| {
        const status_emoji = switch (status.status) {
            .healthy => "✅",
            .degraded => "⚠️",
            .unhealthy => "❌",
            .unknown => "❓",
        };
        std.debug.print("   {s} {s}: {s} ({d}ms)\n", .{
            status_emoji,
            status.name,
            @tagName(status.status),
            status.response_time_ms,
        });
    }
    
    // Search tips
    std.debug.print("\n💡 Search Tips:\n", .{});
    std.debug.print("   • Use 'zion info <package>' for detailed information\n", .{});
    std.debug.print("   • Filter by category: zion search --filter=web,api\n", .{});
    std.debug.print("   • Find popular packages: zion search --min-stars=100\n", .{});
    std.debug.print("   • Search specific registry: zion search --registry=zigistry\n", .{});
}

/// Search options structure
const SearchOptions = struct {
    filters: registry_v2.SearchFilters = .{},
    specific_registry: ?[]const u8 = null,
    
    // Track what was allocated vs default literals
    allocated_license: bool = false,
    allocated_zig_version: bool = false,
    allocated_registry: bool = false,
    allocated_categories: bool = false,
    
    fn deinit(self: *SearchOptions, allocator: Allocator) void {
        // Only free language if it was changed from default
        if (self.filters.language) |lang| {
            if (!std.mem.eql(u8, lang, "zig")) {
                allocator.free(lang);
            }
        }
        
        if (self.allocated_license and self.filters.license != null) {
            allocator.free(self.filters.license.?);
        }
        if (self.allocated_zig_version and self.filters.zig_version != null) {
            allocator.free(self.filters.zig_version.?);
        }
        if (self.allocated_registry and self.specific_registry != null) {
            allocator.free(self.specific_registry.?);
        }
        
        if (self.allocated_categories) {
            for (self.filters.categories) |cat| {
                allocator.free(cat);
            }
            if (self.filters.categories.len > 0) {
                allocator.free(self.filters.categories);
            }
        }
    }
};

/// Parse command line options
fn parseSearchOptions(options: *SearchOptions, args: []const []const u8, allocator: Allocator) !void {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--filter=")) {
            const filter_str = arg[9..];
            var categories = std.ArrayList([]const u8).init(allocator);
            var it = std.mem.splitSequence(u8, filter_str, ",");
            while (it.next()) |cat| {
                try categories.append(try allocator.dupe(u8, cat));
            }
            options.filters.categories = try categories.toOwnedSlice();
            options.allocated_categories = true;
        } else if (std.mem.startsWith(u8, arg, "--license=")) {
            options.filters.license = try allocator.dupe(u8, arg[10..]);
            options.allocated_license = true;
        } else if (std.mem.startsWith(u8, arg, "--min-stars=")) {
            options.filters.min_stars = try std.fmt.parseInt(u64, arg[12..], 10);
        } else if (std.mem.startsWith(u8, arg, "--sort=")) {
            const sort_str = arg[7..];
            options.filters.sort_by = std.meta.stringToEnum(registry_v2.SortOption, sort_str) orelse .relevance;
        } else if (std.mem.startsWith(u8, arg, "--registry=")) {
            options.specific_registry = try allocator.dupe(u8, arg[11..]);
            options.allocated_registry = true;
        } else if (std.mem.startsWith(u8, arg, "--zig-version=")) {
            options.filters.zig_version = try allocator.dupe(u8, arg[14..]);
            options.allocated_zig_version = true;
        } else if (std.mem.startsWith(u8, arg, "--limit=")) {
            options.filters.per_page = try std.fmt.parseInt(u32, arg[8..], 10);
        }
    }
}

/// Search a specific registry
fn searchSpecificRegistry(
    allocator: Allocator,
    manager: *registry_manager.RegistryManager,
    term: []const u8,
    registry_name: []const u8,
    filters: registry_v2.SearchFilters,
) ![]registry_v2.Package {
    // Find the specific registry client
    for (manager.clients.items) |*client| {
        if (std.mem.eql(u8, client.config.name, registry_name)) {
            return try client.searchPackages(term, filters);
        }
    }
    
    std.debug.print("⚠️  Registry '{s}' not found or not enabled\n", .{registry_name});
    return allocator.alloc(registry_v2.Package, 0);
}

/// Format large numbers with K/M suffixes
fn formatCount(count: u64) []const u8 {
    if (count >= 1_000_000) {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d}M", .{count / 1_000_000}) catch "?";
    } else if (count >= 1_000) {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d}K", .{count / 1_000}) catch "?";
    } else {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{count}) catch "?";
    }
}

/// Format ISO date to relative time
fn formatDate(iso_date: []const u8) []const u8 {
    // In a real implementation, would parse and calculate relative time
    // For now, just return a shortened version
    if (iso_date.len >= 10) {
        return iso_date[0..10];
    }
    return iso_date;
}

/// Interactive search mode for better UX
pub fn interactiveSearch(allocator: Allocator) !void {
    std.debug.print("🔍 Zion Interactive Package Search\n", .{});
    std.debug.print("Type 'help' for search tips, 'exit' to quit\n\n", .{});
    
    const stdin = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    
    while (true) {
        try stdout.writeAll("search> ");
        
        var buf: [1024]u8 = undefined;
        const bytes_read = try stdin.readAll(&buf);
        if (bytes_read == 0) break; // EOF
        
        const input = buf[0..bytes_read];
        const trimmed = std.mem.trim(u8, input, " \t\r\n");
        
        if (std.mem.eql(u8, trimmed, "exit") or std.mem.eql(u8, trimmed, "quit")) {
            break;
        } else if (std.mem.eql(u8, trimmed, "help")) {
            try printInteractiveHelp();
        } else if (trimmed.len > 0) {
            // Parse the search command
            var args = std.ArrayList([]const u8).init(allocator);
            defer args.deinit();
            
            try args.append("zion");
            try args.append("search");
            
            var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
            while (it.next()) |token| {
                try args.append(token);
            }
            
            search(allocator, args.items) catch |err| {
                std.debug.print("❌ Search error: {}\n", .{err});
            };
        }
    }
    
    std.debug.print("\n👋 Happy coding with Zion!\n", .{});
}

fn printInteractiveHelp() !void {
    std.debug.print("\n📖 Interactive Search Help:\n", .{});
    std.debug.print("\nBasic search:\n", .{});
    std.debug.print("  json                    Search for 'json' packages\n", .{});
    std.debug.print("  \"http client\"           Search for exact phrase\n", .{});
    std.debug.print("\nFiltered search:\n", .{});
    std.debug.print("  crypto --filter=security,cryptography\n", .{});
    std.debug.print("  web --license=MIT --min-stars=50\n", .{});
    std.debug.print("  game --registry=zigistry\n", .{});
    std.debug.print("\nSorting:\n", .{});
    std.debug.print("  http --sort=stars       Sort by stars\n", .{});
    std.debug.print("  json --sort=downloads   Sort by downloads\n", .{});
    std.debug.print("  api --sort=updated      Sort by last updated\n", .{});
    std.debug.print("\nCommands:\n", .{});
    std.debug.print("  help                    Show this help\n", .{});
    std.debug.print("  exit/quit               Exit interactive mode\n", .{});
    std.debug.print("\n", .{});
}