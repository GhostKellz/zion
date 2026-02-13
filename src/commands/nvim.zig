const std = @import("std");
const Allocator = std.mem.Allocator;
const nvim_integration = @import("../nvim_integration.zig");

/// Neovim integration command
pub fn nvim(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        printNvimHelp();
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "setup")) {
        return setupNvimIntegration(allocator);
    } else if (std.mem.eql(u8, subcommand, "install")) {
        return installNvimPlugin(allocator);
    } else {
        std.debug.print("❌ Unknown nvim subcommand: {s}\n", .{subcommand});
        printNvimHelp();
    }
}

/// Setup Neovim integration
fn setupNvimIntegration(allocator: Allocator) !void {
    std.debug.print("🚀 Setting up Neovim integration for zion...\n", .{});

    // Create Neovim plugin
    try nvim_integration.createNvimPlugin(allocator);

    std.debug.print("\n🎯 Next steps:\n", .{});
    std.debug.print("1. Add to your Neovim config (init.lua):\n", .{});
    std.debug.print("   require('zion').setup({{ keymaps = true }})\n", .{});
    std.debug.print("\n2. Restart Neovim\n", .{});
    std.debug.print("\n3. Use commands like :ZionAdd or <leader>za\n", .{});
}

/// Install Neovim plugin (alias for setup)
fn installNvimPlugin(allocator: Allocator) !void {
    return setupNvimIntegration(allocator);
}

fn printNvimHelp() void {
    std.debug.print("Zion Neovim Integration\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion nvim <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    setup      Setup Neovim integration plugin\n", .{});
    std.debug.print("    install    Install Neovim plugin (alias for setup)\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion nvim setup         # Create Neovim plugin\n", .{});
    std.debug.print("\nThe plugin provides these Neovim commands:\n", .{});
    std.debug.print("    :ZionAdd <package>      # Add dependency\n", .{});
    std.debug.print("    :ZionRemove <package>   # Remove dependency  \n", .{});
    std.debug.print("    :ZionList               # List dependencies\n", .{});
    std.debug.print("    :ZionCheck              # Check project health\n", .{});
    std.debug.print("    :ZionUpdate             # Update dependencies\n", .{});
    std.debug.print("    :ZionPicker             # Interactive dependency picker\n", .{});
    std.debug.print("    :ZionZig                # Interactive Zig version picker\n", .{});
    std.debug.print("\nAnd these keymaps (with keymaps = true):\n", .{});
    std.debug.print("    <leader>za              # Add dependency\n", .{});
    std.debug.print("    <leader>zl              # List dependencies\n", .{});
    std.debug.print("    <leader>zc              # Check project\n", .{});
    std.debug.print("    <leader>zu              # Update dependencies\n", .{});
    std.debug.print("    <leader>zz              # Switch Zig version\n", .{});
}
