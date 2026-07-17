const std = @import("std");
const metadata = @import("../command_metadata.zig");

pub fn help(_: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len >= 3) {
        const requested = metadata.find(args[2]) orelse {
            std.debug.print("Unknown command '{s}'.\n", .{args[2]});
            printGeneral();
            return;
        };
        std.debug.print("zion {s} [{s}]\n\n{s}\n", .{
            requested.name,
            requested.status.label(),
            requested.summary,
        });
        if (requested.aliases.len > 0) {
            std.debug.print("Aliases:", .{});
            for (requested.aliases) |alias| std.debug.print(" {s}", .{alias});
            std.debug.print("\n", .{});
        }
        return;
    }

    printGeneral();
}

fn printGeneral() void {
    std.debug.print(
        \\Zion - Zig project and dependency utility
        \\
        \\USAGE:
        \\    zion <command> [arguments]
        \\
        \\COMMANDS:
        \\
    , .{});

    for (metadata.commands) |command| {
        if (!command.visible) continue;
        std.debug.print("    {s:<20} {s} [{s}]\n", .{
            command.name,
            command.summary,
            command.status.label(),
        });
    }

    std.debug.print(
        \\
        \\Use `zion help <command>` for command status and aliases.
        \\Registry-backed dependency operations remain experimental.
        \\
    , .{});
}

test "every visible help entry resolves through metadata" {
    for (metadata.commands) |command| {
        if (!command.visible) continue;
        try std.testing.expect(metadata.find(command.name) != null);
    }
}
