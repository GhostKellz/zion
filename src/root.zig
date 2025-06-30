//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const commands = @import("commands/mod.zig");

/// Current version of zion
pub const ZION_VERSION = "0.7.0";

// v0.7.0 Enhanced Modules
pub const enhanced_config = @import("enhanced_config.zig");
pub const registry_v2 = @import("registry_v2.zig");
pub const registry_manager = @import("registry_manager.zig");
pub const security = @import("security.zig");
pub const parallel_downloader = @import("parallel_downloader.zig");
pub const zion_v7 = @import("zion_v7.zig");

// Legacy compatibility
pub const config = @import("config.zig");
pub const registry = @import("registry.zig");
pub const downloader = @import("downloader.zig");

// Advanced print function used in the main.zig example
pub fn advancedPrint() !void {
    std.debug.print("Zion v{s} package manager is ready!\n", .{ZION_VERSION});
    std.debug.print("🚀 New in v0.7.0: Multi-registry support, enhanced security, and performance optimizations!\n", .{});
}
