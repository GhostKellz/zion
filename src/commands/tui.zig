const std = @import("std");
const zion_root = @import("../root.zig");
const Allocator = std.mem.Allocator;
const commands = @import("mod.zig");
const Io = std.Io;
const File = Io.File;

/// Simple but functional TUI for Zion v1.0.6
pub fn tui(allocator: Allocator, args: []const [:0]const u8) !void {
    _ = args;

    std.debug.print("\x1b[2J\x1b[H", .{}); // Clear screen and move to top

    const io = try zion_root.getIo();
    var running = true;
    var current_screen = Screen.main_menu;
    var search_input: std.ArrayListUnmanaged(u8) = .empty;
    defer search_input.deinit(allocator);

    // Get stdin for user input
    const stdin_file = File.stdin();
    var stdin_buffer: [256]u8 = undefined;
    
    while (running) {
        switch (current_screen) {
            .main_menu => {
                try drawMainMenu();
                const choice = try getUserChoice(io, stdin_file, &stdin_buffer);
                switch (choice) {
                    '1' => current_screen = .search_packages,
                    '2' => current_screen = .list_dependencies,
                    '3' => current_screen = .settings,
                    '4' => {
                        try commands.help(allocator);
                        try waitForKeypress(io, stdin_file, &stdin_buffer);
                        std.debug.print("\x1b[2J\x1b[H", .{});
                    },
                    'q', 'Q' => running = false,
                    else => continue,
                }
            },
            .search_packages => {
                try drawSearchMenu(&search_input);
                const input = try getSearchInput(allocator, io, stdin_file, &stdin_buffer, &search_input);
                if (input.len > 0) {
                    try performSearchCommand(allocator, input);
                    try waitForKeypress(io, stdin_file, &stdin_buffer);
                }
                current_screen = .main_menu;
                std.debug.print("\x1b[2J\x1b[H", .{});
            },
            .list_dependencies => {
                std.debug.print("📋 Current Dependencies:\n", .{});
                std.debug.print("═══════════════════════\n\n", .{});
                try commands.list(allocator, false);
                std.debug.print("\n\nPress any key to return to main menu...", .{});
                _ = stdin_file.readStreaming(io, &.{stdin_buffer[0..1]}) catch 0;
                current_screen = .main_menu;
                std.debug.print("\x1b[2J\x1b[H", .{});
            },
            .settings => {
                try drawSettingsMenu();
                const choice = try getUserChoice(io, stdin_file, &stdin_buffer);
                switch (choice) {
                    '1' => {
                        try commands.performance(allocator, &[_][]const u8{ "zion", "performance", "status" });
                        try waitForKeypress(io, stdin_file, &stdin_buffer);
                    },
                    '2' => {
                        const empty_args: []const [:0]const u8 = &.{};
                        try commands.cache(allocator, empty_args);
                        try waitForKeypress(io, stdin_file, &stdin_buffer);
                    },
                    else => {},
                }
                current_screen = .main_menu;
                std.debug.print("\x1b[2J\x1b[H", .{});
            },
        }
    }
    
    std.debug.print("\n🚀 Thanks for using Zion!\n", .{});
}

const Screen = enum {
    main_menu,
    search_packages,
    list_dependencies,
    settings,
};

fn drawMainMenu() !void {
    std.debug.print("┌─────────────────────────────────────────┐\n", .{});
    std.debug.print("│          🚀 ZION v1.0.6 TUI           │\n", .{});
    std.debug.print("│        The Cargo for Zig               │\n", .{});
    std.debug.print("└─────────────────────────────────────────┘\n\n", .{});
    
    std.debug.print("📦 Main Menu:\n", .{});
    std.debug.print("═══════════════\n", .{});
    std.debug.print("1. 🔍 Search Packages\n", .{});
    std.debug.print("2. 📋 List Dependencies\n", .{});
    std.debug.print("3. ⚙️  Settings & Performance\n", .{});
    std.debug.print("4. ❓ Help & Commands\n", .{});
    std.debug.print("Q. 🚪 Quit\n\n", .{});
    std.debug.print("Enter your choice: ", .{});
}

fn drawSearchMenu(search_input: *std.ArrayListUnmanaged(u8)) !void {
    std.debug.print("┌─────────────────────────────────────────┐\n", .{});
    std.debug.print("│            🔍 Package Search           │\n", .{});
    std.debug.print("└─────────────────────────────────────────┘\n\n", .{});

    std.debug.print("Current search: {s}\n\n", .{search_input.items});
    std.debug.print("💡 Examples:\n", .{});
    std.debug.print("  • libxev (for event loops)\n", .{});
    std.debug.print("  • httpz (for HTTP servers)\n", .{});
    std.debug.print("  • json (for JSON parsing)\n\n", .{});
    std.debug.print("Enter package name to search (or press Enter to go back): ", .{});
}

fn drawSettingsMenu() !void {
    std.debug.print("┌─────────────────────────────────────────┐\n", .{});
    std.debug.print("│         ⚙️  Settings & Performance     │\n", .{});
    std.debug.print("└─────────────────────────────────────────┘\n\n", .{});
    
    std.debug.print("Settings Menu:\n", .{});
    std.debug.print("═════════════\n", .{});
    std.debug.print("1. 📊 Performance Status\n", .{});
    std.debug.print("2. 🗄️  Cache Management\n", .{});
    std.debug.print("3. 🔐 Security & Keyring\n", .{});
    std.debug.print("B. ← Back to Main Menu\n\n", .{});
    std.debug.print("Enter your choice: ", .{});
}

fn getUserChoice(io: Io, stdin_file: File, buffer: *[256]u8) !u8 {
    const bytes_read = stdin_file.readStreaming(io, &.{buffer[0..1]}) catch return '\n';
    if (bytes_read > 0) {
        return buffer[0];
    }
    return '\n';
}

fn getSearchInput(allocator: Allocator, io: Io, stdin_file: File, buffer: *[256]u8, search_input: *std.ArrayListUnmanaged(u8)) ![]const u8 {
    search_input.clearRetainingCapacity();

    const bytes_read = stdin_file.readStreaming(io, &.{buffer[0..]}) catch return "";
    if (bytes_read > 0) {
        const input_str = buffer[0..bytes_read];
        const trimmed = std.mem.trim(u8, input_str, " \n\r\t");
        try search_input.appendSlice(allocator, trimmed);
        return search_input.items;
    }
    return "";
}

fn performSearchCommand(allocator: Allocator, query: []const u8) !void {
    std.debug.print("\n🔍 Searching for '{s}'...\n", .{query});
    std.debug.print("══════════════════════════════\n\n", .{});
    
    const search_args = [_][:0]u8{
        try allocator.dupeZ(u8, "zion"),
        try allocator.dupeZ(u8, "search"), 
        try allocator.dupeZ(u8, query)
    };
    defer {
        for (search_args) |arg| allocator.free(arg);
    }
    
    try commands.search(allocator, &search_args);
}

fn waitForKeypress(io: Io, stdin_file: File, buffer: *[256]u8) !void {
    std.debug.print("\n\nPress any key to continue...", .{});
    _ = stdin_file.readStreaming(io, &.{buffer[0..1]}) catch {};
}