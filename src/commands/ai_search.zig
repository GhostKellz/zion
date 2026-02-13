const std = @import("std");
const zsync = @import("zsync");
const Allocator = std.mem.Allocator;
const zeke_client = @import("../zeke_client_simple.zig");

/// AI-powered package search and discovery
pub fn aiSearch(allocator: Allocator, io: zsync.Io, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        std.debug.print("Usage: zion ai-search <query>\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  zion ai-search \"HTTP client for web scraping\"\n", .{});
        std.debug.print("  zion ai-search \"JSON parsing library\"\n", .{});
        std.debug.print("  zion ai-search \"async networking\"\n", .{});
        return;
    }

    // Combine all arguments into a search query
    var query_buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer query_buffer.deinit(allocator);

    for (args[2..], 0..) |arg, i| {
        if (i > 0) try query_buffer.append(allocator, ' ');
        try query_buffer.appendSlice(allocator, arg);
    }

    const query = query_buffer.items;

    std.debug.print("🤖 **Zeke AI Package Search**\n", .{});
    std.debug.print("========================================\n", .{});
    std.debug.print("🔍 Query: \"{s}\"\n\n", .{query});

    // Initialize Zeke client
    var zeke = zeke_client.ZekeClient.init(allocator, io) catch |err| {
        std.debug.print("❌ Zeke AI unavailable: {any}\n", .{err});
        std.debug.print("💡 Start Zeke server with 'zeke --rpc' for AI search\n", .{});
        return;
    };
    defer zeke.deinit();

    if (!zeke.healthCheck()) {
        std.debug.print("❌ Zeke server not running\n", .{});
        std.debug.print("💡 Start Zeke server with 'zeke --rpc' for AI search\n", .{});
        return;
    }

    // Get package recommendations
    const recommendations = zeke.recommendPackages(query) catch |err| {
        std.debug.print("❌ Search failed: {any}\n", .{err});
        return;
    };

    if (recommendations.recommendations.len == 0) {
        std.debug.print("🤔 **No packages found**\n", .{});
        std.debug.print("💡 Try different keywords or check 'zion search' for basic search\n", .{});
        return;
    }

    std.debug.print("🎯 **Results** ({d} packages found in {d}ms)\n", .{ recommendations.total_found, recommendations.search_time_ms });
    std.debug.print("=====================================\n\n", .{});

    // Display recommendations with rich formatting
    for (recommendations.recommendations, 0..) |rec, i| {
        displayPackageRecommendation(rec, i + 1);
    }

    // Show additional search suggestions
    std.debug.print("💡 **Related Searches**:\n", .{});
    try generateRelatedSearches(query);

    std.debug.print("\n🚀 **Quick Actions**:\n", .{});
    std.debug.print("  • zion add <package>      - Add a package\n", .{});
    std.debug.print("  • zion info <package>     - Get package details\n", .{});
    std.debug.print("  • zion search <keyword>   - Traditional search\n", .{});
    std.debug.print("  • zion ai-search <query>  - AI-powered search\n", .{});
}

/// Display a single package recommendation with rich formatting
fn displayPackageRecommendation(rec: zeke_client.ZekeClient.PackageRecommendation.PackageInfo, index: usize) void {
    // Convert score to star rating
    const score_stars = @as(u8, @intFromFloat(rec.score * 5));
    const full_stars = score_stars;

    var star_display: [5]u8 = undefined;
    @memset(star_display[0..full_stars], '*');
    @memset(star_display[full_stars..], '-');

    // Score-based color coding (conceptual, would need terminal color support)
    const score_emoji = if (rec.score >= 0.9) "🏆" else if (rec.score >= 0.8) "🥈" else if (rec.score >= 0.7) "🥉" else "📦";

    std.debug.print("{s} **{d}. {s}** {s}\n", .{ score_emoji, index, rec.name, star_display });
    std.debug.print("   🎯 {s}\n", .{rec.reason});
    std.debug.print("   📍 {s} | v{s} | Score: {d:.2}\n", .{ rec.registry, rec.version, rec.score });

    // Show alternatives if available
    if (rec.alternatives.len > 0) {
        std.debug.print("   🔄 Alternatives: ", .{});
        for (rec.alternatives, 0..) |alt, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s} ({d:.1})", .{ alt.name, alt.score });
        }
        std.debug.print("\n", .{});
    }

    // Installation command
    std.debug.print("   ⚡ Quick add: zion add {s}\n", .{rec.name});
    std.debug.print("\n", .{});
}

/// Generate related search suggestions based on the query
fn generateRelatedSearches(query: []const u8) !void {
    // Simple keyword-based suggestions (in a real implementation, this could use AI)
    const suggestions = [_][]const u8{
        "async programming",
        "web development",
        "data structures",
        "cryptography",
        "networking",
        "JSON handling",
        "database drivers",
        "testing frameworks",
        "CLI tools",
        "graphics programming",
    };

    // Find related suggestions based on query keywords
    var found_suggestions: std.ArrayList([]const u8) = .{};
    defer found_suggestions.deinit(std.heap.page_allocator);

    for (suggestions) |suggestion| {
        if (queryRelatedTo(query, suggestion)) {
            try found_suggestions.append(std.heap.page_allocator, suggestion);
        }
    }

    // Show a few suggestions
    const max_suggestions = @min(3, found_suggestions.items.len);
    for (found_suggestions.items[0..max_suggestions]) |suggestion| {
        std.debug.print("  • \"{s}\"\n", .{suggestion});
    }

    if (found_suggestions.items.len == 0) {
        std.debug.print("  • \"async programming\"\n", .{});
        std.debug.print("  • \"web development\"\n", .{});
        std.debug.print("  • \"data structures\"\n", .{});
    }
}

/// Check if a query is related to a suggestion
fn queryRelatedTo(query: []const u8, suggestion: []const u8) bool {
    var query_buffer: [256]u8 = undefined;
    var suggestion_buffer: [256]u8 = undefined;

    if (query.len >= query_buffer.len or suggestion.len >= suggestion_buffer.len) return false;

    const query_lower = std.ascii.lowerString(query_buffer[0..query.len], query);
    const suggestion_lower = std.ascii.lowerString(suggestion_buffer[0..suggestion.len], suggestion);

    // Simple keyword matching
    if (std.mem.indexOf(u8, query_lower, "http") != null and
        std.mem.indexOf(u8, suggestion_lower, "web") != null) return true;

    if (std.mem.indexOf(u8, query_lower, "json") != null and
        std.mem.indexOf(u8, suggestion_lower, "data") != null) return true;

    if (std.mem.indexOf(u8, query_lower, "async") != null and
        std.mem.indexOf(u8, suggestion_lower, "async") != null) return true;

    return false;
}

/// Interactive AI chat for package discovery
pub fn aiChat(allocator: Allocator, io: zsync.Io, args: []const [:0]const u8) !void {
    _ = args;

    std.debug.print("🤖 **Zeke AI Assistant**\n", .{});
    std.debug.print("=========================\n", .{});
    std.debug.print("Interactive chat mode not yet implemented.\n", .{});
    std.debug.print("Use 'zion ai-search \"your query\"' for package recommendations.\n", .{});

    // Initialize Zeke client
    var zeke = zeke_client.ZekeClient.init(allocator, io) catch |err| {
        std.debug.print("❌ Zeke AI unavailable: {any}\n", .{err});
        return;
    };
    defer zeke.deinit();

    if (!zeke.healthCheck()) {
        std.debug.print("❌ Zeke server not running\n", .{});
        std.debug.print("💡 Start Zeke server with 'zeke --rpc'\n", .{});
        return;
    }

    // For now, just show a demo response
    const demo_response = zeke.chat("Hello Zeke!") catch |err| {
        std.debug.print("❌ Demo chat failed: {any}\n", .{err});
        return;
    };
    defer allocator.free(demo_response);

    std.debug.print("🤖 Demo response: {s}\n", .{demo_response});
}
