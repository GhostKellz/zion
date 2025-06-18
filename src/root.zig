//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const commands = @import("commands/mod.zig");

/// Current version of zion
pub const ZION_VERSION = "0.3.0";

// Advanced print function used in the main.zig example
pub fn advancedPrint() !void {
    std.debug.print("Zion package manager is ready!\n", .{});
}
