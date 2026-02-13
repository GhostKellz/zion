const std = @import("std");

// Import individual command modules
pub const init_mod = @import("init.zig");
pub const add_mod = @import("add.zig");
pub const fetch_mod = @import("fetch.zig");
pub const build_mod = @import("build.zig");
pub const version_mod = @import("version.zig");
pub const help_mod = @import("help.zig");
pub const lock_mod = @import("lock.zig");

// Re-export all command modules - v0.7.0 uses enhanced commands as defaults
pub const init = @import("init.zig").init;
pub const add = @import("add_v2.zig").add; // v0.7.0: Enhanced add is now default
pub const addMultiple = @import("add_v2.zig").addMultiple; // v0.7.0: Enhanced add multiple
pub const AddOptions = @import("add_v2.zig").AddOptions; // Export AddOptions type
pub const remove = @import("remove.zig").remove;
pub const update = @import("update.zig").update;
pub const list = @import("list.zig").list;
pub const info = @import("info.zig").info;
pub const fetch = @import("fetch.zig").fetch;
pub const pin = @import("pin.zig").pin;
pub const unpin = @import("unpin.zig").unpin;
pub const repair = @import("repair.zig").repair;
pub const check = @import("check.zig").check;
pub const build = @import("build.zig").build;
pub const clean = @import("clean.zig").clean;
pub const lock = @import("lock.zig").lock;
pub const version = @import("version.zig").version;
pub const help = @import("help.zig").help;
pub const hash = @import("hash.zig").hash;
pub const config = @import("config.zig").config;
pub const security = @import("security.zig").security;
pub const performance = @import("performance.zig").performance;
pub const debug = @import("debug.zig").debug;
pub const run = @import("run.zig").run;
pub const test_command = @import("test.zig").test_command;
pub const tree = @import("tree.zig").tree;
pub const doc = @import("doc.zig").doc;
pub const outdated = @import("outdated.zig").outdated;
pub const zig_manager = @import("zig_manager.zig").zig_manager;

pub var zig_command_override: ?fn (std.mem.Allocator, [][:0]u8) anyerror!void = null;

pub fn setZigCommandHandler(handler: ?fn (std.mem.Allocator, [][:0]u8) anyerror!void) void {
    zig_command_override = handler;
}

pub fn resetZigCommandHandler() void {
    zig_command_override = null;
}
pub const nvim = @import("nvim.zig").nvim;
pub const search = @import("search_v2.zig").search; // v0.7.0: Enhanced search is now default
pub const registry = @import("registry_v2.zig").registryCommand; // v0.7.0: Enhanced registry is now default
pub const publish = @import("publish.zig").publish; // v0.7.0: New publishing feature
pub const setup = @import("setup_simple.zig").setup; // v0.8.0: Simplified setup system
pub const zls = @import("zls.zig").zls; // v0.8.0: ZLS integration commands
pub const workspace = @import("workspace.zig").workspace; // v0.8.0: Cargo-style workspace management
pub const ghostspec = @import("ghostspec.zig").ghostspec; // v0.8.0: GhostSpec integration commands

// NEW v1.0.5: Production-ready features
pub const signature_verify = @import("signature_verify.zig").verify;
pub const cache = @import("cache.zig").cache;
pub const tui = @import("tui.zig").tui;

// NEW v1.0.1: Enhanced TUI and HTTP3/2/1 Integration Commands
pub const interface = @import("interface.zig").interface; // v1.0.1: Phantom TUI with standard HTTP client
pub const search_interactive = interface; // v1.0.1: Alias for TUI interface

// NEW v1.1.0: Community Integration Commands
pub const ziglibs = @import("ziglibs.zig").ziglibs; // v1.1.0: Enhanced Ziglibs integration
pub const zigistry = @import("zigistry.zig").zigistry; // v1.1.0: Advanced Zigistry features
pub const enhanced_add = @import("enhanced_add.zig").enhanced_add; // v1.1.0: Multi-registry add
pub const enhanced_zls = @import("enhanced_zls.zig").enhanced_zls; // v1.1.0: Deep ZLS integration
pub const enhanced_zig_manager = @import("enhanced_zig_manager.zig").enhanced_zig_manager; // v1.1.0: Enhanced Zig manager

// NEW v1.2.0: Zeke AI Integration Commands
pub const enhanced_add_zeke = @import("enhanced_add_zeke.zig").enhancedAdd; // v1.2.0: AI-powered add command
pub const status = @import("status.zig").status; // v1.2.0: Project status with AI analysis
pub const ai_search = @import("ai_search.zig").aiSearch; // v1.2.0: AI-powered package search
pub const ai_chat = @import("ai_search.zig").aiChat; // v1.2.0: Interactive AI assistant

// NEW v1.3.0: Enhanced Security & GPG Integration
pub const keyring = @import("keyring.zig").keyring; // v1.3.0: GPG keyring management with Arch Linux support

// Interactive search mode (legacy)
// pub const search_interactive = @import("search_v2.zig").interactiveSearch;

// Legacy command aliases (for transition period if needed)
pub const add_legacy = @import("add.zig").add;
pub const search_legacy = @import("search.zig").search;
pub const registry_legacy = @import("registry.zig").registryCommand;

// Alias for the old zig function - now use zig_manager
pub fn zig(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Convert args to the format expected by zig_manager
    var zig_args = try std.ArrayList([:0]u8).initCapacity(allocator, args.len + 2);
    defer zig_args.deinit(allocator);

    try zig_args.append(allocator, try allocator.dupeZ(u8, "zion"));
    try zig_args.append(allocator, try allocator.dupeZ(u8, "zig"));

    for (args) |arg| {
        try zig_args.append(allocator, try allocator.dupeZ(u8, arg));
    }

    const handler = zig_command_override orelse zig_manager;
    return handler(allocator, zig_args.items);
}

// Search function is now imported from search.zig

pub fn template(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;
    std.debug.print("📋 Project templates (coming soon)\n", .{});
    std.debug.print("This feature will allow you to:\n", .{});
    std.debug.print("  • Create projects from templates\n", .{});
    std.debug.print("  • Browse available templates\n", .{});
    std.debug.print("  • Scaffold common project types\n", .{});
}

pub fn fmt(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;
    std.debug.print("🎨 Enhanced code formatting (coming soon)\n", .{});
    std.debug.print("This feature will provide:\n", .{});
    std.debug.print("  • Project-wide formatting\n", .{});
    std.debug.print("  • Custom formatting rules\n", .{});
    std.debug.print("  • Integration with build system\n", .{});
}

pub fn analyze(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;
    _ = args;
    std.debug.print("📊 Project analysis (coming soon)\n", .{});
    std.debug.print("This feature will provide:\n", .{});
    std.debug.print("  • Dependency tree analysis\n", .{});
    std.debug.print("  • Code metrics and statistics\n", .{});
    std.debug.print("  • Build optimization suggestions\n", .{});
}
