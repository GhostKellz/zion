const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const zion_root = @import("../root.zig");

/// Simplified setup command for the current shipped surface.
pub fn setup(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        printSetupHelp();
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "all")) {
        return setupAll(allocator);
    } else if (std.mem.eql(u8, subcommand, "verify")) {
        return verifySetup(allocator);
    } else {
        std.debug.print("Unknown setup subcommand: {s}\n", .{subcommand});
        printSetupHelp();
    }
}

fn setupAll(allocator: Allocator) !void {
    _ = allocator;
    std.debug.print("Zion setup currently ships a lightweight onboarding flow.\n", .{});
    std.debug.print("\nWhat it covers in v{s}:\n", .{zion_root.ZION_VERSION});
    std.debug.print("  1. Verify the core tools you need are installed\n", .{});
    std.debug.print("  2. Point you at the follow-up commands for Zig and ZLS\n", .{});
    std.debug.print("\nRecommended next steps:\n", .{});
    std.debug.print("  • zion setup verify\n", .{});
    std.debug.print("  • zion zig current\n", .{});
    std.debug.print("  • zion zls doctor\n", .{});
}

fn verifySetup(allocator: Allocator) !void {
    _ = allocator;
    std.debug.print("Verifying Zion setup...\n", .{});

    std.debug.print("Zig: ", .{});
    if (checkCommand("zig")) {
        std.debug.print("Found\n", .{});
    } else {
        std.debug.print("Not found\n", .{});
    }

    std.debug.print("Zion: ", .{});
    if (checkCommand("zion")) {
        std.debug.print("Found\n", .{});
    } else {
        std.debug.print("Not found\n", .{});
    }
}

fn checkCommand(command: []const u8) bool {
    const io = zion_root.getIo() catch return false;
    const argv = [_][]const u8{ "which", command };
    var child = std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return false;

    const term = child.wait(io) catch return false;
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn printSetupHelp() void {
    std.debug.print("Zion Setup\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion setup <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    all                     Show the current onboarding flow\n", .{});
    std.debug.print("    verify                  Verify core tools are available\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion setup all          # Show setup guidance\n", .{});
    std.debug.print("    zion setup verify       # Check if tools are available\n", .{});
}
