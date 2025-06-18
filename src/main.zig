const std = @import("std");
const zion = @import("zion");
const commands = zion.commands;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try commands.help(allocator);
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "init")) {
        try commands.init(allocator);
    } else if (std.mem.eql(u8, command, "add")) {
        if (args.len < 3) {
            std.debug.print("Error: 'zion add' requires one or more package names\n", .{});
            std.debug.print("Usage: zion add <package> [<package2> ...]\n", .{});
            std.debug.print("Examples:\n", .{});
            std.debug.print("  zion add mitchellh/libxev\n", .{});
            std.debug.print("  zion add mitchellh/libxev karlseguin/httpz\n", .{});
            return;
        }

        const packages = args[2..];
        if (packages.len == 1) {
            try commands.add(allocator, packages[0]);
        } else {
            try commands.addMultiple(allocator, packages);
        }
    } else if (std.mem.eql(u8, command, "remove") or std.mem.eql(u8, command, "rm")) {
        if (args.len < 3) {
            std.debug.print("Error: 'zion remove' requires a package name\n", .{});
            std.debug.print("Usage: zion remove <package>\n", .{});
            std.debug.print("Example: zion remove libxev\n", .{});
            return;
        }
        try commands.remove(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "update")) {
        try commands.update(allocator);
    } else if (std.mem.eql(u8, command, "list") or std.mem.eql(u8, command, "ls")) {
        const json_mode = args.len > 2 and std.mem.eql(u8, args[2], "--json");
        try commands.list(allocator, json_mode);
    } else if (std.mem.eql(u8, command, "info")) {
        if (args.len < 3) {
            std.debug.print("Error: 'zion info' requires a package name\n", .{});
            std.debug.print("Usage: zion info <package>\n", .{});
            std.debug.print("Example: zion info libxev\n", .{});
            return;
        }
        try commands.info(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "fetch")) {
        try commands.fetch(allocator);
    } else if (std.mem.eql(u8, command, "build")) {
        try commands.build(allocator);
    } else if (std.mem.eql(u8, command, "clean")) {
        const clean_all = args.len > 2 and std.mem.eql(u8, args[2], "--all");
        try commands.clean(allocator, clean_all);
    } else if (std.mem.eql(u8, command, "lock")) {
        try commands.lock(allocator);
    } else if (std.mem.eql(u8, command, "version")) {
        try commands.version(allocator);
    } else if (std.mem.eql(u8, command, "help")) {
        try commands.help(allocator);
    } else if (std.mem.eql(u8, command, "security")) {
        try commands.security(allocator, args);
    } else if (std.mem.eql(u8, command, "performance")) {
        try commands.performance(allocator, args);
    } else if (std.mem.eql(u8, command, "debug")) {
        try commands.debug(allocator, args);
    } else if (std.mem.eql(u8, command, "zig")) {
        try commands.zig(allocator, args);
    } else if (std.mem.eql(u8, command, "search")) {
        try commands.search(allocator, args);
    } else if (std.mem.eql(u8, command, "template")) {
        try commands.template(allocator, args);
    } else if (std.mem.eql(u8, command, "debug")) {
        try commands.debug(allocator, args);
    } else if (std.mem.eql(u8, command, "fmt")) {
        try commands.fmt(allocator, args);
    } else if (std.mem.eql(u8, command, "analyze")) {
        try commands.analyze(allocator, args);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        std.debug.print("Run 'zion help' for available commands.\n", .{});
    }
}
