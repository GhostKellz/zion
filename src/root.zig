//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const commands = @import("commands/mod.zig");
pub const logger = @import("logger.zig");
pub const progress = @import("progress.zig");
pub const qol_enhancements = @import("qol_enhancements.zig");

/// Current version of zion
pub const ZION_VERSION = "1.0.6";

// v0.7.0 Enhanced Modules
pub const enhanced_config = @import("enhanced_config.zig");
pub const registry_v2 = @import("registry_v2.zig");
pub const registry_manager = @import("registry_manager.zig");
pub const security = @import("security.zig");
pub const parallel_downloader = @import("parallel_downloader.zig");
pub const zion_v7 = @import("zion_v7.zig");

// v1.2.0 Zeke AI Integration
pub const zeke_client = @import("zeke_client_simple.zig");
pub const enhanced_add_zeke = @import("commands/enhanced_add_zeke.zig").enhancedAdd;

// Legacy compatibility
pub const config = @import("config.zig");
pub const registry = @import("registry.zig");
pub const downloader = @import("downloader.zig");

// Advanced print function used in the main.zig example
pub fn advancedPrint() !void {
    std.debug.print("Zion v{s} package manager is ready!\n", .{ZION_VERSION});
    std.debug.print("🔥 New in v1.0.6: GPG keyring integration, Arch Linux support, and Zig v0.16.0 compatibility!\n", .{});
}
