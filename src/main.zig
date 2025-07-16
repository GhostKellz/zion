const std = @import("std");
const zion = @import("zion");
const commands = zion.commands;

/// Resolve command aliases to full command names
fn resolveCommandAlias(command: []const u8) []const u8 {
    // Common aliases
    if (std.mem.eql(u8, command, "s")) return "search";
    if (std.mem.eql(u8, command, "i")) return "info";
    if (std.mem.eql(u8, command, "a")) return "add";
    if (std.mem.eql(u8, command, "r")) return "remove";
    if (std.mem.eql(u8, command, "u")) return "update";
    if (std.mem.eql(u8, command, "l")) return "list";
    if (std.mem.eql(u8, command, "c")) return "check";
    if (std.mem.eql(u8, command, "b")) return "build";
    if (std.mem.eql(u8, command, "t")) return "test";
    if (std.mem.eql(u8, command, "h")) return "help";
    if (std.mem.eql(u8, command, "v")) return "version";
    if (std.mem.eql(u8, command, "f")) return "fetch";
    if (std.mem.eql(u8, command, "si")) return "search-interactive";
    if (std.mem.eql(u8, command, "reg")) return "registry";
    if (std.mem.eql(u8, command, "cfg")) return "config";
    if (std.mem.eql(u8, command, "sec")) return "security";
    if (std.mem.eql(u8, command, "perf")) return "performance";
    if (std.mem.eql(u8, command, "dbg")) return "debug";
    if (std.mem.eql(u8, command, "tui")) return "interface";
    if (std.mem.eql(u8, command, "ui")) return "interface";
    
    // Return original command if no alias found
    return command;
}

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

    const raw_command = args[1];
    const command = resolveCommandAlias(raw_command);

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
            // Use default options for the enhanced add command
            const options = commands.AddOptions{};
            try commands.add(allocator, packages[0], options);
        } else {
            const options = commands.AddOptions{};
            try commands.addMultiple(allocator, packages, options);
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
        try commands.update(allocator, args);
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
        try commands.fetch(allocator, args);
    } else if (std.mem.eql(u8, command, "pin")) {
        try commands.pin(allocator, args);
    } else if (std.mem.eql(u8, command, "unpin")) {
        try commands.unpin(allocator, args);
    } else if (std.mem.eql(u8, command, "repair")) {
        try commands.repair(allocator);
    } else if (std.mem.eql(u8, command, "check")) {
        try commands.check(allocator);
    } else if (std.mem.eql(u8, command, "build")) {
        try commands.build(allocator);
    } else if (std.mem.eql(u8, command, "clean")) {
        const clean_all = args.len > 2 and std.mem.eql(u8, args[2], "--all");
        try commands.clean(allocator, clean_all);
    } else if (std.mem.eql(u8, command, "lock")) {
        try commands.lock(allocator);
    } else if (std.mem.eql(u8, command, "version")) {
        try commands.version(allocator);
    } else if (std.mem.eql(u8, command, "hash")) {
        try commands.hash(allocator, args);
    } else if (std.mem.eql(u8, command, "run")) {
        try commands.run(allocator, args);
    } else if (std.mem.eql(u8, command, "test")) {
        try commands.test_command(allocator, args);
    } else if (std.mem.eql(u8, command, "tree")) {
        try commands.tree(allocator, args);
    } else if (std.mem.eql(u8, command, "doc")) {
        try commands.doc(allocator, args);
    } else if (std.mem.eql(u8, command, "outdated")) {
        try commands.outdated(allocator, args);
    } else if (std.mem.eql(u8, command, "nvim")) {
        try commands.nvim(allocator, args);
    } else if (std.mem.eql(u8, command, "config")) {
        try commands.config(allocator, args);
    } else if (std.mem.eql(u8, command, "help")) {
        try commands.help(allocator);
    } else if (std.mem.eql(u8, command, "security")) {
        try commands.security(allocator, args);
    } else if (std.mem.eql(u8, command, "performance")) {
        try commands.performance(allocator, args);
    } else if (std.mem.eql(u8, command, "debug")) {
        try commands.debug(allocator, args);
    } else if (std.mem.eql(u8, command, "zig")) {
        try commands.zig_manager(allocator, args);
    } else if (std.mem.eql(u8, command, "search")) {
        try commands.search(allocator, args);
    } else if (std.mem.eql(u8, command, "registry")) {
        try commands.registry(allocator, args);
    } else if (std.mem.eql(u8, command, "template")) {
        try commands.template(allocator, args);
    } else if (std.mem.eql(u8, command, "debug")) {
        try commands.debug(allocator, args);
    } else if (std.mem.eql(u8, command, "fmt")) {
        try commands.fmt(allocator, args);
    } else if (std.mem.eql(u8, command, "analyze")) {
        try commands.analyze(allocator, args);
    
    // v0.7.0 Enhanced Commands
    } else if (std.mem.eql(u8, command, "publish")) {
        try commands.publish(allocator, args);
    } else if (std.mem.eql(u8, command, "search-interactive")) {
        try commands.search_interactive(allocator);
    } else if (std.mem.eql(u8, command, "interface")) {
        try commands.interface(allocator);
    
    // v0.8.0 New Commands
    } else if (std.mem.eql(u8, command, "setup")) {
        try commands.setup(allocator, args);
    } else if (std.mem.eql(u8, command, "zls")) {
        try commands.zls(allocator, args);
    } else if (std.mem.eql(u8, command, "workspace")) {
        try commands.workspace(allocator, args);
    } else if (std.mem.eql(u8, command, "ziglibs")) {
        try commands.ziglibs(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "zigistry")) {
        try commands.zigistry(allocator, args[2..]);
    } else {
        std.debug.print("Unknown command: {s}\n", .{raw_command});
        std.debug.print("Run 'zion help' for available commands.\n", .{});
        std.debug.print("\n💡 Quick aliases:\n", .{});
        std.debug.print("  s/search         - Search for packages\n", .{});
        std.debug.print("  a/add            - Add packages\n", .{});
        std.debug.print("  i/info           - Package information\n", .{});
        std.debug.print("  l/list           - List dependencies\n", .{});
        std.debug.print("  u/update         - Update packages\n", .{});
        std.debug.print("  r/remove         - Remove packages\n", .{});
        std.debug.print("  h/help           - Show help\n", .{});
        std.debug.print("  v/version        - Show version\n", .{});
    }
}
