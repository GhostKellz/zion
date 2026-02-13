const std = @import("std");
const zsync = @import("zsync");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const zeke_client = @import("../zeke_client_simple.zig");
const zion_root = @import("../root.zig");
const Dir = std.Io.Dir;
const Io = std.Io;

/// Display comprehensive project status with Zeke AI analysis
pub fn status(allocator: Allocator, io: zsync.Io, args: []const [:0]const u8) !void {
    _ = args; // Reserved for future options

    std.debug.print("🦄 **Zion Project Status**\n", .{});
    std.debug.print("=====================================\n\n", .{});

    // Basic project info
    try displayBasicStatus(allocator);

    // Try to get Zeke AI analysis
    var zeke = zeke_client.ZekeClient.init(allocator, io) catch |err| {
        std.debug.print("⚠️  Zeke AI unavailable ({any})\n", .{err});
        std.debug.print("💡 Start Zeke server for enhanced analysis\n\n", .{});
        return;
    };
    defer zeke.deinit();

    if (!zeke.healthCheck()) {
        std.debug.print("⚠️  Zeke server not running\n", .{});
        std.debug.print("💡 Run 'zeke --rpc' in background for AI analysis\n\n", .{});
        return;
    }

    std.debug.print("🤖 **AI-Powered Analysis**\n", .{});
    std.debug.print("-----------------------------\n", .{});

    try performZekeAnalysis(allocator, &zeke);
}

/// Display basic project status without AI
fn displayBasicStatus(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    std.debug.print("📁 **Project Overview**\n", .{});
    std.debug.print("-----------------------------\n", .{});

    // Check if build.zig.zon exists
    const zon_exists = blk: {
        cwd.access(io, "build.zig.zon", .{}) catch break :blk false;
        break :blk true;
    };
    const build_exists = blk: {
        cwd.access(io, "build.zig", .{}) catch break :blk false;
        break :blk true;
    };

    if (!zon_exists) {
        std.debug.print("❌ No build.zig.zon found\n", .{});
        std.debug.print("💡 Run 'zion init' to initialize project\n\n", .{});
        return;
    }

    std.debug.print("✅ build.zig.zon: Found\n", .{});
    std.debug.print("✅ build.zig: {s}\n", .{if (build_exists) "Found" else "Missing"});

    // Parse and display zon file info
    const zon_content = cwd.readFileAlloc(io, "build.zig.zon", allocator, Io.Limit.limited(1024 * 1024)) catch |err| {
        std.debug.print("❌ Failed to read build.zig.zon: {any}\n\n", .{err});
        return;
    };
    defer allocator.free(zon_content);

    var zon_file = ZonFile.parseZonContent(allocator, zon_content) catch |err| {
        std.debug.print("❌ Failed to parse build.zig.zon: {any}\n\n", .{err});
        return;
    };
    defer zon_file.deinit();

    std.debug.print("📦 Project: {s}\n", .{zon_file.name});
    std.debug.print("🏷️  Version: {s}\n", .{zon_file.version});

    const dep_count = zon_file.dependencies.count();
    std.debug.print("📚 Dependencies: {d}\n", .{dep_count});

    if (dep_count > 0) {
        std.debug.print("\n📋 **Dependencies**:\n", .{});
        var iterator = zon_file.dependencies.iterator();
        while (iterator.next()) |entry| {
            std.debug.print("  • {s}\n", .{entry.key_ptr.*});
        }
    }

    std.debug.print("\n", .{});
}

/// Perform comprehensive Zeke AI analysis
fn performZekeAnalysis(_: Allocator, zeke: *zeke_client.ZekeClient) !void {
    const analysis = zeke.analyzeProject(".") catch |err| {
        std.debug.print("❌ AI analysis failed: {any}\n\n", .{err});
        return;
    };

    // Overall health score with visual indicator
    const health_score = analysis.summary.health_score;
    const health_emoji = if (health_score >= 90) "🟢" else if (health_score >= 70) "🟡" else if (health_score >= 50) "🟠" else "🔴";

    std.debug.print("{s} **Overall Health**: {d}/100 ({s})\n", .{ health_emoji, health_score, analysis.summary.readiness });

    // Project information
    std.debug.print("🏗️  **Build System**: {s}\n", .{analysis.project_info.build_system});
    std.debug.print("📊 **Modules**: {d}\n", .{analysis.project_info.module_count});
    std.debug.print("⚡ **Optimization**: {s}\n", .{analysis.project_info.optimization_level});

    // Dependencies with security scores
    if (analysis.dependencies.len > 0) {
        std.debug.print("\n🛡️  **Dependency Security**:\n", .{});
        for (analysis.dependencies) |dep| {
            const security_emoji = if (dep.security_score >= 90) "🟢" else if (dep.security_score >= 70) "🟡" else if (dep.security_score >= 50) "🟠" else "🔴";

            std.debug.print("  {s} {s} v{s} - {d}/100\n", .{ security_emoji, dep.name, dep.version, dep.security_score });

            if (dep.alternatives.len > 0) {
                std.debug.print("    🔄 Alternatives: ", .{});
                for (dep.alternatives, 0..) |alt, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{alt});
                }
                std.debug.print("\n", .{});
            }
        }
    }

    // Build issues
    if (analysis.build_issues.len > 0) {
        std.debug.print("\n⚠️  **Build Issues** ({d} found):\n", .{analysis.build_issues.len});
        for (analysis.build_issues[0..@min(5, analysis.build_issues.len)]) |issue| {
            const severity_emoji = if (std.mem.eql(u8, issue.severity, "high")) "🔴" else if (std.mem.eql(u8, issue.severity, "medium")) "🟡" else "🟢";

            std.debug.print("  {s} **{s}**: {s}\n", .{ severity_emoji, issue.type, issue.message });
            std.debug.print("    💡 {s}\n", .{issue.suggestion});
            if (issue.line > 0) {
                std.debug.print("    📍 {s}:{d}\n", .{ issue.file, issue.line });
            }
        }

        if (analysis.build_issues.len > 5) {
            std.debug.print("  ... and {d} more issues\n", .{analysis.build_issues.len - 5});
        }
    } else {
        std.debug.print("\n✅ **No Build Issues Found**\n", .{});
    }

    // AI recommendations
    if (analysis.summary.recommendations.len > 0) {
        std.debug.print("\n🎯 **AI Recommendations**:\n", .{});
        for (analysis.summary.recommendations) |rec| {
            std.debug.print("  💡 {s}\n", .{rec});
        }
    }

    // Quick actions
    std.debug.print("\n🚀 **Quick Actions**:\n", .{});
    std.debug.print("  • zion check          - Verify dependencies\n", .{});
    std.debug.print("  • zion update         - Update packages\n", .{});
    std.debug.print("  • zion security       - Security audit\n", .{});
    std.debug.print("  • zion build          - Build project\n", .{});

    if (health_score < 80) {
        std.debug.print("  • zion repair         - Fix common issues\n", .{});
    }

    std.debug.print("\n", .{});
}

/// Show minimal status for CI/CD environments
pub fn statusMinimal(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const zon_exists = blk: {
        cwd.access(io, "build.zig.zon", .{}) catch break :blk false;
        break :blk true;
    };
    if (!zon_exists) {
        std.debug.print("not_initialized\n", .{});
        return;
    }

    const zon_content = cwd.readFileAlloc(io, "build.zig.zon", allocator, Io.Limit.limited(1024 * 1024)) catch {
        std.debug.print("parse_error\n", .{});
        return;
    };
    defer allocator.free(zon_content);

    var zon_file = ZonFile.parseFromString(allocator, zon_content) catch {
        std.debug.print("parse_error\n", .{});
        return;
    };
    defer zon_file.deinit();

    std.debug.print("ok:{d}_deps\n", .{zon_file.dependencies.count()});
}
