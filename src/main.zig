const std = @import("std");
const zsync = @import("zsync");
const zion = @import("zion");
const commands = zion.commands;

/// Async wrapper for add command to leverage zsync performance
fn addAsync(allocator: std.mem.Allocator, io: zsync.Io, package_ref: []const u8, options: commands.AddOptions) !void {
    _ = io; // For future async operations
    try commands.add(allocator, package_ref, options);
}

/// Async wrapper for multiple package add to leverage zsync performance  
fn addMultipleAsync(allocator: std.mem.Allocator, io: zsync.Io, packages: []const []const u8, options: commands.AddOptions) !void {
    _ = io; // For future async operations
    try commands.addMultiple(allocator, packages, options);
}

/// Async wrapper for search command to leverage zsync performance
fn searchAsync(allocator: std.mem.Allocator, io: zsync.Io, args: [][:0]u8) !void {
    _ = io; // For future async operations  
    try commands.search(allocator, args);
}

/// Async wrapper for registry operations to leverage zsync performance
fn registryAsync(allocator: std.mem.Allocator, io: zsync.Io, args: [][:0]u8) !void {
    _ = io; // For future async operations
    try commands.registry(allocator, args);
}

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
    if (std.mem.eql(u8, command, "kr")) return "keyring";
    if (std.mem.eql(u8, command, "key")) return "keyring";
    
    // Return original command if no alias found
    return command;
}

pub fn main() !void {
    // Use blocking runtime for CLI development tools (zsync v0.4.0)
    try zsync.runBlocking(zionMain, {});
}

fn zionMain(io: zsync.Io) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logging system
    zion.logger.init();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try commands.help(allocator);
        return;
    }

    const raw_command = args[1];
    
    // Handle standard flags first
    if (std.mem.eql(u8, raw_command, "--help") or std.mem.eql(u8, raw_command, "-h")) {
        try commands.help(allocator);
        return;
    }
    
    if (std.mem.eql(u8, raw_command, "--version") or std.mem.eql(u8, raw_command, "-V")) {
        try commands.version(allocator);
        return;
    }
    
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
            try addAsync(allocator, io, packages[0], options);
        } else {
            const options = commands.AddOptions{};
            try addMultipleAsync(allocator, io, packages, options);
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
        try searchAsync(allocator, io, args);
    } else if (std.mem.eql(u8, command, "registry")) {
        try registryAsync(allocator, io, args);
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
    
    // v1.0.5 Production-ready Features
    } else if (std.mem.eql(u8, command, "verify")) {
        try commands.signature_verify(allocator, args);
    } else if (std.mem.eql(u8, command, "cache")) {
        try commands.cache(allocator, args);
    } else if (std.mem.eql(u8, command, "tui") or std.mem.eql(u8, command, "interactive")) {
        try commands.tui(allocator, args);
    
    // v1.2.0 Zeke AI Integration Commands
    } else if (std.mem.eql(u8, command, "status")) {
        try commands.status(allocator, io, args);
    } else if (std.mem.eql(u8, command, "ai-search")) {
        try commands.ai_search(allocator, io, args);
    } else if (std.mem.eql(u8, command, "ai-chat")) {
        try commands.ai_chat(allocator, io, args);
    } else if (std.mem.eql(u8, command, "ai-add")) {
        if (args.len < 3) {
            std.debug.print("Error: 'zion ai-add' requires a package query\n", .{});
            std.debug.print("Usage: zion ai-add <query|package>\n", .{});
            std.debug.print("Examples:\n", .{});
            std.debug.print("  zion ai-add \"HTTP client for REST APIs\"\n", .{});
            std.debug.print("  zion ai-add mitchellh/libxev\n", .{});
            return;
        }
        // For now, just use regular add with AI feedback
        std.debug.print("🤖 AI-powered add not yet implemented, using regular add\n", .{});
        const options = commands.AddOptions{};
        try commands.add(allocator, args[2], options);
    
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
    } else if (std.mem.eql(u8, command, "keyring")) {
        try commands.keyring(allocator, args);
    } else {
        std.debug.print("❌ Unknown command: '{s}'\n\n", .{raw_command});
        
        // Suggest similar commands
        if (std.mem.startsWith(u8, raw_command, "se")) {
            std.debug.print("💡 Did you mean: 'zion search' or 'zion security'?\n\n", .{});
        } else if (std.mem.startsWith(u8, raw_command, "ad")) {
            std.debug.print("💡 Did you mean: 'zion add'?\n\n", .{});
        } else if (std.mem.startsWith(u8, raw_command, "li")) {
            std.debug.print("💡 Did you mean: 'zion list'?\n\n", .{});
        } else if (std.mem.startsWith(u8, raw_command, "re")) {
            std.debug.print("💡 Did you mean: 'zion remove' or 'zion registry'?\n\n", .{});
        } else {
            std.debug.print("💡 Run 'zion help' or 'zion --help' for available commands\n\n", .{});
        }
        
        std.debug.print("🚀 Common commands:\n", .{});
        std.debug.print("  zion search <package>     - Search for packages\n", .{});
        std.debug.print("  zion add <package>        - Add a package\n", .{});
        std.debug.print("  zion list                 - List dependencies\n", .{});
        std.debug.print("  zion help                 - Show detailed help\n", .{});
    }
}
