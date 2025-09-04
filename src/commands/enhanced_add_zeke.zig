const std = @import("std");
const zsync = @import("zsync");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");
const enhanced_config = @import("../enhanced_config.zig");
const registry = @import("../registry.zig");
const zeke_client = @import("../zeke_client_simple.zig");

/// Enhanced add command with Zeke AI-powered package recommendations
pub fn enhancedAdd(allocator: Allocator, io: zsync.Io, package_ref: []const u8, options: AddOptions) !void {
    // Initialize Zeke client for AI recommendations
    var zeke = zeke_client.ZekeClient.init(allocator, io) catch |err| {
        std.debug.print("⚠️  Zeke AI unavailable ({any}), using standard add\n", .{err});
        return fallbackAdd(allocator, package_ref, options);
    };
    defer zeke.deinit(allocator);
    
    // Check if Zeke server is running
    if (!zeke.healthCheck()) {
        std.debug.print("⚠️  Zeke server not running, using standard add\n", .{});
        return fallbackAdd(allocator, package_ref, options);
    }
    
    std.debug.print("🤖 **Zeke AI Assistant Active**\n\n", .{});
    
    // If this looks like a search query rather than a specific package, use AI recommendations
    if (shouldUseAIRecommendations(package_ref)) {
        try handleAIPackageDiscovery(allocator, &zeke, package_ref, options);
        return;
    }
    
    // For specific packages, get AI insights and suggestions
    try handleSpecificPackageAdd(allocator, &zeke, package_ref, options);
}

pub const AddOptions = struct {
    dev_only: bool = false,
    version: ?[]const u8 = null,
    interactive: bool = false,
    show_alternatives: bool = true,
    security_check: bool = true,
};

/// Determine if the package reference should trigger AI recommendations
fn shouldUseAIRecommendations(package_ref: []const u8) bool {
    // If it contains spaces or question words, it's likely a search query
    if (std.mem.indexOf(u8, package_ref, " ") != null) return true;
    if (std.mem.startsWith(u8, package_ref, "how")) return true;
    if (std.mem.startsWith(u8, package_ref, "what")) return true;
    if (std.mem.startsWith(u8, package_ref, "find")) return true;
    if (std.mem.startsWith(u8, package_ref, "need")) return true;
    
    // If it doesn't contain a slash and is longer than typical package names
    if (std.mem.indexOf(u8, package_ref, "/") == null and package_ref.len > 10) return true;
    
    return false;
}

/// Handle AI-powered package discovery for search queries
fn handleAIPackageDiscovery(allocator: Allocator, zeke: *zeke_client.ZekeClient, query: []const u8, options: AddOptions) !void {
    std.debug.print("🔍 **AI Package Discovery**\n", .{});
    std.debug.print("Query: \"{s}\"\n\n", .{query});
    
    // Get AI recommendations
    const recommendations = zeke.recommendPackages(query) catch |err| {
        std.debug.print("❌ Failed to get AI recommendations: {any}\n", .{err});
        return;
    };
    
    if (recommendations.recommendations.len == 0) {
        std.debug.print("🤔 No packages found matching: \"{s}\"\n", .{query});
        std.debug.print("💡 Try being more specific or use 'zion search' to browse packages\n", .{});
        return;
    }
    
    std.debug.print("🎯 **AI Recommendations** (found {d} packages in {d}ms):\n\n", .{ 
        recommendations.total_found, recommendations.search_time_ms 
    });
    
    for (recommendations.recommendations, 0..) |rec, i| {
        const score_stars = @as(u8, @intFromFloat(rec.score * 5));
        const star_display = "★★★★★"[0..score_stars];
        
        std.debug.print("{}. 📦 **{s}** {s}\n", .{ i + 1, rec.name, star_display });
        std.debug.print("   🎯 {s}\n", .{rec.reason});
        std.debug.print("   📍 Registry: {s} | Version: {s}\n", .{ rec.registry, rec.version });
        
        if (rec.alternatives.len > 0) {
            std.debug.print("   🔄 Alternatives: ", .{});
            for (rec.alternatives, 0..) |alt, j| {
                if (j > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{alt.name});
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("\n", .{});
    }
    
    if (options.interactive) {
        try interactivePackageSelection(allocator, &recommendations, options);
    } else {
        // Auto-add the top recommendation
        const top_rec = recommendations.recommendations[0];
        std.debug.print("🚀 **Auto-adding top recommendation**: {s}\n\n", .{top_rec.name});
        try fallbackAdd(allocator, top_rec.name, options);
    }
}

/// Handle adding a specific package with AI insights
fn handleSpecificPackageAdd(allocator: Allocator, zeke: *zeke_client.ZekeClient, package_ref: []const u8, options: AddOptions) !void {
    std.debug.print("📦 **Adding Package**: {s}\n", .{package_ref});
    
    // Get dependency suggestions for context
    const suggestions = zeke.suggestDependencies(package_ref) catch |err| {
        std.debug.print("⚠️  AI analysis unavailable: {any}\n", .{err});
        return fallbackAdd(allocator, package_ref, options);
    };
    
    // Show AI insights about this package
    if (suggestions.suggestions.len > 0) {
        std.debug.print("\n🤖 **AI Package Analysis**:\n", .{});
        for (suggestions.suggestions) |suggestion| {
            if (std.mem.eql(u8, suggestion.name, package_ref) or 
                std.mem.endsWith(u8, suggestion.name, package_ref)) {
                
                std.debug.print("  🛡️  Security Score: {d}/100\n", .{suggestion.security_score});
                std.debug.print("  📈 Popularity Score: {d}/100\n", .{suggestion.popularity_score});
                std.debug.print("  🔧 Maintenance Score: {d}/100\n", .{suggestion.maintenance_score});
                std.debug.print("  📝 {s}\n", .{suggestion.description});
                break;
            }
        }
        std.debug.print("\n", .{});
    }
    
    // Show alternatives if requested
    if (options.show_alternatives and suggestions.suggestions.len > 1) {
        std.debug.print("🔄 **Alternative Packages**:\n", .{});
        for (suggestions.suggestions[0..@min(3, suggestions.suggestions.len)]) |alt| {
            if (!std.mem.eql(u8, alt.name, package_ref)) {
                std.debug.print("  • {s} - {s}\n", .{ alt.name, alt.description });
            }
        }
        std.debug.print("\n", .{});
    }
    
    // Proceed with standard add
    try fallbackAdd(allocator, package_ref, options);
    
    // Get project analysis after adding
    if (options.security_check) {
        try performPostAddAnalysis(allocator, zeke);
    }
}

/// Interactive package selection interface (simplified)
fn interactivePackageSelection(allocator: Allocator, recommendations: *const zeke_client.ZekeClient.PackageRecommendation, options: AddOptions) !void {
    std.debug.print("🎮 **Auto-selecting top recommendation** (interactive mode not yet fully implemented):\n", .{});
    
    if (recommendations.recommendations.len > 0) {
        const selected = recommendations.recommendations[0];
        std.debug.print("✅ Selected: {s}\n\n", .{selected.name});
        try fallbackAdd(allocator, selected.name, options);
    } else {
        std.debug.print("❌ No packages to select\n", .{});
    }
}

/// Perform project analysis after adding a package
fn performPostAddAnalysis(_: Allocator, zeke: *zeke_client.ZekeClient) !void {
    std.debug.print("🔍 **Post-Add Project Analysis**...\n", .{});
    
    const analysis = zeke.analyzeProject(".") catch |err| {
        std.debug.print("⚠️  Analysis failed: {any}\n", .{err});
        return;
    };
    
    std.debug.print("📊 **Project Health Score**: {d}/100\n", .{analysis.summary.health_score});
    std.debug.print("🎯 **Project Status**: {s}\n", .{analysis.summary.readiness});
    
    if (analysis.build_issues.len > 0) {
        std.debug.print("\n⚠️  **Build Issues Detected**:\n", .{});
        for (analysis.build_issues[0..@min(3, analysis.build_issues.len)]) |issue| {
            std.debug.print("  • {s}: {s}\n", .{ issue.type, issue.message });
            std.debug.print("    💡 {s}\n", .{issue.suggestion});
        }
    }
    
    if (analysis.summary.recommendations.len > 0) {
        std.debug.print("\n💡 **AI Recommendations**:\n", .{});
        for (analysis.summary.recommendations[0..@min(3, analysis.summary.recommendations.len)]) |rec| {
            std.debug.print("  • {s}\n", .{rec});
        }
    }
    
    std.debug.print("\n", .{});
}

/// Fallback to standard add implementation
fn fallbackAdd(allocator: Allocator, package_ref: []const u8, options: AddOptions) !void {
    _ = options; // Options will be used in future versions
    
    // Import and use the existing add function
    const add_command = @import("add.zig");
    try add_command.add(allocator, package_ref);
}