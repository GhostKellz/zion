const std = @import("std");
const Config = @import("../config.zig").Config;
const ZionConfig = @import("../registry_config.zig").ZionConfig;
const GhostKellzEcosystem = @import("../ghostkellz_ecosystem.zig").GhostKellzEcosystem;
const ZigLibsIntegration = @import("../ziglibs_integration.zig").ZigLibsIntegration;

/// Launch enhanced ecosystem interface for GhostLibs and ZigLibs management
pub fn interface(allocator: std.mem.Allocator) !void {
    std.log.info("🚀 Launching Zion - GhostLibs & ZigLibs Ecosystem Manager", .{});

    // Initialize ecosystems for demonstration
    var ghostkellz = GhostKellzEcosystem.init(allocator) catch |err| {
        std.log.err("❌ Failed to initialize GhostLibs: {any}", .{err});
        return;
    };
    defer ghostkellz.deinit();

    var ziglibs = ZigLibsIntegration.init(allocator) catch |err| {
        std.log.err("❌ Failed to initialize ZigLibs: {any}", .{err});
        return;
    };
    defer ziglibs.deinit();

    // Display available ecosystems
    std.log.info("👻 GhostLibs Ecosystem ({d} packages available):", .{ghostkellz.packages.items.len});
    std.log.info("  • http_client - Standard HTTP client (replaced ghostnet)", .{});
    std.log.info("  • zcrypto - Quantum-resistant cryptography", .{});
    std.log.info("  • zquic - Ultra-fast QUIC/HTTP3 implementation", .{});
    std.log.info("  • zsync - Structured concurrency runtime", .{});
    std.log.info("  • flash - Blazing-fast build system", .{});
    std.log.info("  • jaguar - High-performance JIT compiler", .{});
    std.log.info("  • zqlite - Lightning-fast embedded database", .{});
    std.log.info("  • shroud - Advanced privacy toolkit", .{});
    std.log.info("  • zsig - Digital signature and verification", .{});
    std.log.info("  • zwallet - Cryptocurrency wallet framework", .{});
    std.log.info("  • zledger - Distributed ledger technology", .{});

    std.log.info("🦎 ZigLibs Integration ({d} packages, {d} tools):", .{ ziglibs.packages.items.len, ziglibs.tools.items.len });
    std.log.info("  • 25+ curated packages from ziglibs repository", .{});
    std.log.info("  • Development tools and utilities", .{});
    std.log.info("  • Comprehensive ecosystem support", .{});

    // Display available repositories
    std.log.info("📦 Available GhostLibs repositories (all main archive branch):", .{});
    const ghostlibs = [_][]const u8{
        // "github.com/ghostkellz/ghostnet", // removed - using standard HTTP client
        "github.com/ghostkellz/zcrypto",
        "github.com/ghostkellz/zquic",
        "github.com/ghostkellz/zsync",
        "github.com/ghostkellz/flash",
        "github.com/ghostkellz/jaguar",
        "github.com/ghostkellz/zqlite",
        "github.com/ghostkellz/shroud",
        "github.com/ghostkellz/zsig",
        "github.com/ghostkellz/zwallet",
        "github.com/ghostkellz/zledger",
    };

    for (ghostlibs) |repo| {
        std.log.info("  📁 {s}", .{repo});
    }

    std.log.info("🦎 ZigLibs packages from: https://github.com/ziglibs/repository", .{});
    std.log.info("📚 Tools from: https://github.com/ziglibs/repository/tree/main/tools", .{});

    // Generate sample installation commands
    std.log.info("", .{});
    std.log.info("🛠️ Quick Installation Examples:", .{});
    std.log.info("", .{});

    // GhostLibs examples
    std.log.info("👻 Install GhostLibs packages:", .{});
    // ghostnet removed - using standard HTTP client now
    std.log.info("  # ghostnet removed - using standard HTTP client", .{});

    // ZigLibs examples
    std.log.info("🦎 Install ZigLibs packages:", .{});
    if (ziglibs.findPackage("zig-clap")) |pkg| {
        const cmd = try pkg.getZigFetchCommand(allocator);
        defer allocator.free(cmd);
        std.log.info("  {s}", .{cmd});
    }
    if (ziglibs.findPackage("zig-network")) |pkg| {
        const cmd = try pkg.getZigFetchCommand(allocator);
        defer allocator.free(cmd);
        std.log.info("  {s}", .{cmd});
    }

    std.log.info("", .{});
    std.log.info("🎯 Interactive TUI Coming Soon!", .{});
    std.log.info("💡 For now, use: zion search <package> | zion add <package>", .{});
    std.log.info("🔍 Search both ecosystems with: zion search --all <query>", .{});
}
