const std = @import("std");

/// Display the version of Zion
pub fn version(allocator: std.mem.Allocator) !void {
    _ = allocator; // unused but required for API consistency
    const zion_version = @import("../root.zig").ZION_VERSION;
    std.debug.print("zion {s}\n", .{zion_version});
}
