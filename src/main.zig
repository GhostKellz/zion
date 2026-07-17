const std = @import("std");
const zion = @import("zion");
const version = @import("build_options").version;
const commands = zion.commands;
const command_metadata = zion.command_metadata;
const qol = zion.qol_enhancements;
const Runtime = zion.runtime.Runtime;

// Re-export AppContext from zion module for convenience
const AppContext = zion.AppContext;

/// Resolve command aliases to full command names
fn resolveCommandAlias(command: []const u8) []const u8 {
    return command_metadata.resolve(command);
}

/// Main entry point using the process initialization context provided by Zig.
pub fn main(init: std.process.Init) !void {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch |err| {
        std.debug.print("Failed to get command line arguments: {}\n", .{err});
        return;
    };

    const context = AppContext{
        .allocator = init.gpa,
        .std_io = init.io,
        .args = args,
        .environ = init.environ_map,
    };
    zion.app_context = &context;
    defer zion.app_context = null;

    try zionMain(&context);
}

fn zionMain(ctx: *const AppContext) !void {
    const allocator = ctx.allocator;
    const args = ctx.args;
    const runtime = Runtime.init(allocator, ctx.std_io);
    _ = runtime;

    zion.logger.init();

    if (args.len < 2) {
        try commands.help(allocator, args);
        return;
    }

    const raw_command = args[1];

    if (std.mem.eql(u8, raw_command, "--help") or std.mem.eql(u8, raw_command, "-h")) {
        try commands.help(allocator, args);
        return;
    }

    if (std.mem.eql(u8, raw_command, "--version") or std.mem.eql(u8, raw_command, "-V")) {
        try commands.version(allocator);
        return;
    }

    const command = resolveCommandAlias(raw_command);

    if (std.mem.eql(u8, command, "version")) {
        try commands.version(allocator);
    } else if (std.mem.eql(u8, command, "help")) {
        try commands.help(allocator, args);
    } else if (std.mem.eql(u8, command, "init")) {
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
        const options = commands.AddOptions{};

        if (packages.len == 1) {
            try commands.add(allocator, packages[0], options);
        } else {
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
        try commands.build(allocator, args);
    } else if (std.mem.eql(u8, command, "clean")) {
        const clean_all = args.len > 2 and std.mem.eql(u8, args[2], "--all");
        try commands.clean(allocator, clean_all);
    } else if (std.mem.eql(u8, command, "lock")) {
        try commands.lock(allocator, args);
    } else if (std.mem.eql(u8, command, "hash")) {
        try commands.hash(allocator, args);
    } else if (std.mem.eql(u8, command, "run")) {
        try commands.run(allocator, args);
    } else if (std.mem.eql(u8, command, "test")) {
        try commands.test_command(allocator, args);
    } else if (std.mem.eql(u8, command, "tree")) {
        try commands.tree(allocator, args);
    } else if (std.mem.eql(u8, command, "why")) {
        try commands.why(allocator, args);
    } else if (std.mem.eql(u8, command, "policy")) {
        try commands.policy(allocator, args);
    } else if (std.mem.eql(u8, command, "target")) {
        try commands.target(allocator, args);
    } else if (std.mem.eql(u8, command, "doc")) {
        try commands.doc(allocator, args);
    } else if (std.mem.eql(u8, command, "outdated")) {
        try commands.outdated(allocator, args);
    } else if (std.mem.eql(u8, command, "nvim")) {
        try commands.nvim(allocator, args);
    } else if (std.mem.eql(u8, command, "config")) {
        try commands.config(allocator, args);
    } else if (std.mem.eql(u8, command, "security")) {
        try commands.security(allocator, args);
    } else if (std.mem.eql(u8, command, "performance")) {
        try commands.performance(allocator, args);
    } else if (std.mem.eql(u8, command, "debug")) {
        try commands.debug(allocator, args);
    } else if (std.mem.eql(u8, command, "zig")) {
        try commands.zig_manager(allocator, args);
    } else if (std.mem.eql(u8, command, "search")) {
        if (args.len < 3) {
            std.debug.print("Error: 'zion search' requires a search query\n", .{});
            std.debug.print("Usage: zion search <query>\n", .{});
            std.debug.print("Example: zion search http\n", .{});
            return;
        }
        try commands.search(allocator, args);
    } else if (std.mem.eql(u8, command, "registry")) {
        try commands.registry(allocator, args);
    } else if (std.mem.eql(u8, command, "template")) {
        try commands.template(allocator, args);
    } else if (std.mem.eql(u8, command, "fmt")) {
        try commands.fmt(allocator, args);
    } else if (std.mem.eql(u8, command, "analyze")) {
        try commands.analyze(allocator, args);
    } else if (std.mem.eql(u8, command, "health") or std.mem.eql(u8, command, "benchmark")) {
        std.debug.print("⚠️  '{s}' is not part of the shipped v{s} runtime surface.\n", .{ command, version });
        std.debug.print("   Phase 3 removed the old zsync-backed runtime path; no Zion-specific std-based implementation exists yet.\n", .{});
    } else if (std.mem.eql(u8, command, "publish")) {
        try commands.publish(allocator, args);
    } else if (std.mem.eql(u8, command, "search-interactive")) {
        try commands.search_interactive(allocator);
    } else if (std.mem.eql(u8, command, "interface")) {
        try commands.interface(allocator);
    } else if (std.mem.eql(u8, command, "verify")) {
        try commands.signature_verify(allocator, args);
    } else if (std.mem.eql(u8, command, "cache")) {
        try commands.cache(allocator, args);
    } else if (std.mem.eql(u8, command, "tui") or std.mem.eql(u8, command, "interactive")) {
        try commands.tui(allocator, args);
    } else if (std.mem.eql(u8, command, "status")) {
        try commands.status(allocator, args);
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
    } else if (std.mem.eql(u8, command, "keyring")) {
        try commands.keyring(allocator, args);
    } else if (std.mem.eql(u8, command, "archver")) {
        const archver_str = try allocator.dupeSentinel(u8, "archver", 0);
        defer allocator.free(archver_str);
        var archver_args = [_][:0]const u8{ args[0], args[1], archver_str };
        try commands.keyring(allocator, &archver_args);
    } else {
        std.debug.print("❌ Unknown command: '{s}'\n\n", .{raw_command});

        const suggester = qol.CommandSuggester.init();
        if (suggester.suggestCommand(raw_command)) |suggestion| {
            std.debug.print("💡 Did you mean: 'zion {s}'?\n\n", .{suggestion});
        } else {
            const suggestions = suggester.suggestCommands(allocator, raw_command) catch &[_][]const u8{};
            defer allocator.free(suggestions);

            if (suggestions.len > 0) {
                std.debug.print("💡 Similar commands:\n", .{});
                for (suggestions) |cmd| {
                    std.debug.print("  zion {s}\n", .{cmd});
                }
                std.debug.print("\n", .{});
            } else {
                std.debug.print("💡 Run 'zion help' or 'zion --help' for available commands\n\n", .{});
            }
        }

        std.debug.print("🚀 Common commands:\n", .{});
        std.debug.print("  zion search <package>     - Search for packages\n", .{});
        std.debug.print("  zion add <package>        - Add a package\n", .{});
        std.debug.print("  zion list                 - List dependencies\n", .{});
        std.debug.print("  zion help                 - Show detailed help\n", .{});
    }
}
