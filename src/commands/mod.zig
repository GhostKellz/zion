const std = @import("std");

// Import individual command modules
pub const init_mod = @import("init.zig");
pub const add_mod = @import("add.zig");
pub const fetch_mod = @import("fetch.zig");
pub const build_mod = @import("build.zig");
pub const version_mod = @import("version.zig");
pub const help_mod = @import("help.zig");
pub const lock_mod = @import("lock.zig");

// Re-export all command modules
pub const init = @import("init.zig").init;
pub const add = @import("add.zig").add;
pub const addMultiple = @import("add.zig").addMultiple;
pub const AddOptions = @import("add.zig").AddOptions;
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
pub const search = @import("search.zig").search;
pub const registry = @import("registry.zig").registryCommand;
pub const publish = @import("publish.zig").publish;
pub const setup = @import("setup_simple.zig").setup;
pub const zls = @import("zls.zig").zls;
pub const workspace = @import("workspace.zig").workspace;
pub const ghostspec = @import("ghostspec.zig").ghostspec;

pub const signature_verify = @import("signature_verify.zig").verify;
pub const cache = @import("cache.zig").cache;
pub const tui = @import("tui.zig").tui;

pub const interface = @import("interface.zig").interface;
pub const search_interactive = interface;

pub const ziglibs = @import("ziglibs.zig").ziglibs;
pub const zigistry = @import("zigistry.zig").zigistry;
pub const enhanced_add = @import("enhanced_add.zig").enhanced_add;
pub const enhanced_zls = @import("enhanced_zls.zig").enhanced_zls;
pub const enhanced_zig_manager = @import("enhanced_zig_manager.zig").enhanced_zig_manager;

pub const status = @import("status.zig").status;

pub const keyring = @import("keyring.zig").keyring;

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
