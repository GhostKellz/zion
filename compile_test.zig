const std = @import("std");

// Import the main components to test for compilation errors
const root = @import("src/root.zig");
const main_mod = @import("src/main.zig");

pub fn main() !void {
    std.debug.print("Testing basic compilation...\n", .{});
    try root.advancedPrint();
}

// Test compilation by importing each command module
test "import all command modules" {
    _ = @import("src/commands/mod.zig");
    _ = @import("src/commands/search.zig");
    _ = @import("src/commands/template.zig");
    _ = @import("src/commands/zig.zig");
}