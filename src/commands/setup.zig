const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const zig_manager = @import("zig_manager.zig");

/// One Nation Under Zig - Complete development environment setup
pub fn setup(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 3) {
        printSetupHelp();
        return;
    }
    
    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "all")) {
        return setupAll(allocator);
    } else if (std.mem.eql(u8, subcommand, "zig")) {
        return setupZig(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "zls")) {
        return setupZLS(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "shell")) {
        return setupShell(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "nvim")) {
        return setupNvim(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "tools")) {
        return setupTools(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "verify")) {
        return verifySetup(allocator);
    } else {
        std.debug.print("❌ Unknown setup subcommand: {s}\n", .{subcommand});
        printSetupHelp();
    }
}

/// Complete setup - the "One Nation Under Zig" experience
fn setupAll(allocator: Allocator) !void {
    std.debug.print("🇺🇸 Welcome to 'One Nation Under Zig' Setup! 🦎\n", .{});
    std.debug.print("==============================================\n\n", .{});
    
    std.debug.print("This will set up a complete Zig development environment:\n", .{});
    std.debug.print("  🔧 Latest Zig version\n", .{});
    std.debug.print("  🧠 ZLS (Zig Language Server)\n", .{});
    std.debug.print("  🐚 Shell integration (PATH, completions)\n", .{});
    std.debug.print("  🛠️  Essential development tools\n", .{});
    std.debug.print("  ✅ Verification of everything\n\n", .{});
    
    // Ask for confirmation
    std.debug.print("Continue with setup? [Y/n]: ", .{});
    
    const stdin = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    var buf: [256]u8 = undefined;
    const bytes_read = try stdin.readAll(&buf);
    const response = if (bytes_read > 0) buf[0..bytes_read] else "";
    const trimmed = std.mem.trim(u8, response, " \t\r\n");
    
    if (trimmed.len > 0 and !std.mem.eql(u8, trimmed, "Y") and !std.mem.eql(u8, trimmed, "y")) {
        std.debug.print("Setup cancelled.\n", .{});
        return;
    }
    
    std.debug.print("\n🚀 Starting setup...\n\n", .{});
    
    // Step 1: Setup Zig
    std.debug.print("📋 Step 1/5: Setting up Zig...\n", .{});
    try setupZig(allocator, &.{});
    
    // Step 2: Setup ZLS
    std.debug.print("\n📋 Step 2/5: Setting up ZLS...\n", .{});
    try setupZLS(allocator, &.{});
    
    // Step 3: Setup Shell
    std.debug.print("\n📋 Step 3/5: Setting up shell integration...\n", .{});
    try setupShell(allocator, &.{});
    
    // Step 4: Setup Tools
    std.debug.print("\n📋 Step 4/5: Setting up development tools...\n", .{});
    try setupTools(allocator, &.{});
    
    // Step 5: Verify
    std.debug.print("\n📋 Step 5/5: Verifying setup...\n", .{});
    try verifySetup(allocator);
    
    std.debug.print("\n🎉 'One Nation Under Zig' setup complete!\n", .{});
    std.debug.print("🦎 You're now ready to develop with Zig!\n\n", .{});
    
    std.debug.print("📚 Next steps:\n", .{});
    std.debug.print("  • Restart your shell: source ~/.bashrc\n", .{});
    std.debug.print("  • Create a new project: zion init my-project\n", .{});
    std.debug.print("  • Check everything works: zion setup verify\n", .{});
    std.debug.print("  • Join the Zig community: https://ziglearn.org\n", .{});
}

/// Setup Zig version management
fn setupZig(allocator: Allocator, args: [][:0]u8) !void {
    var install_latest = true;
    var version: []const u8 = "0.12.0"; // Default to stable
    
    // Parse arguments
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--version=")) {
            version = arg["--version=".len..];
        } else if (std.mem.eql(u8, arg, "--skip-install")) {
            install_latest = false;
        }
    }
    
    std.debug.print("🔧 Setting up Zig version management...\n", .{});
    
    // Check if Zig is already installed system-wide
    const has_system_zig = checkSystemZig(allocator);
    if (has_system_zig) {
        std.debug.print("  ℹ️  System Zig detected\n", .{});
    }
    
    if (install_latest) {
        std.debug.print("  📦 Installing Zig {s}...\n", .{version});
        
        // Use the existing zig_manager to install
        const version_z = try allocator.dupeZ(u8, version);
        defer allocator.free(version_z);
        
        var install_args = std.ArrayList([:0]u8).init(allocator);
        defer install_args.deinit(allocator);
        try install_args.append(try allocator.dupeZ(u8, "zion"));
        try install_args.append(try allocator.dupeZ(u8, "zig"));
        try install_args.append(try allocator.dupeZ(u8, "install"));
        try install_args.append(allocator, version_z);
        
        try zig_manager.zig_manager(allocator, install_args.items);
        
        std.debug.print("  🔗 Setting as active version...\n", .{});
        var use_args = std.ArrayList([:0]u8).init(allocator);
        defer use_args.deinit(allocator);
        try use_args.append(try allocator.dupeZ(u8, "zion"));
        try use_args.append(try allocator.dupeZ(u8, "zig"));
        try use_args.append(try allocator.dupeZ(u8, "use"));
        try use_args.append(allocator, version_z);
        
        try zig_manager.zig_manager(allocator, use_args.items);
        
        // Free allocated strings
        for (install_args.items) |arg| {
            if (arg.ptr != version_z.ptr) allocator.free(arg);
        }
        for (use_args.items) |arg| {
            if (arg.ptr != version_z.ptr) allocator.free(arg);
        }
    }
    
    std.debug.print("  ✅ Zig setup complete\n", .{});
}

/// Setup ZLS (Zig Language Server)
fn setupZLS(allocator: Allocator, args: [][:0]u8) !void {
    _ = args;
    
    std.debug.print("🧠 Setting up ZLS (Zig Language Server)...\n", .{});
    
    // Check if ZLS is already installed
    const has_zls = checkCommand("zls");
    if (has_zls) {
        std.debug.print("  ✅ ZLS already installed\n", .{});
        return;
    }
    
    std.debug.print("  📦 Installing ZLS...\n", .{});
    
    // For now, provide instructions (real implementation would download/build ZLS)
    std.debug.print("  📝 ZLS installation options:\n", .{});
    std.debug.print("    1. Install via package manager: 'brew install zls' (macOS)\n", .{});
    std.debug.print("    2. Build from source: https://github.com/zigtools/zls\n", .{});
    std.debug.print("    3. Download pre-built: https://github.com/zigtools/zls/releases\n", .{});
    
    // Create ZLS config
    try createZLSConfig(allocator);
    
    std.debug.print("  ✅ ZLS setup instructions provided\n", .{});
}

/// Setup shell integration
fn setupShell(allocator: Allocator, args: [][:0]u8) !void {
    var shell_type: ?[]const u8 = null;
    
    // Parse arguments
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--zsh")) {
            shell_type = "zsh";
        } else if (std.mem.eql(u8, arg, "--bash")) {
            shell_type = "bash";
        } else if (std.mem.eql(u8, arg, "--fish")) {
            shell_type = "fish";
        }
    }
    
    std.debug.print("🐚 Setting up shell integration...\n", .{});
    
    // Auto-detect shell if not specified
    const detected_shell = shell_type orelse detectShell();
    std.debug.print("  🔍 Detected shell: {s}\n", .{detected_shell});
    
    // Setup PATH
    try setupShellPath(allocator, detected_shell);
    
    // Setup completions
    try setupShellCompletions(allocator, detected_shell);
    
    std.debug.print("  ✅ Shell integration complete\n", .{});
}

/// Setup Neovim integration
fn setupNvim(allocator: Allocator, args: [][:0]u8) !void {
    _ = args;
    
    std.debug.print("🔥 Setting up Neovim integration...\n", .{});
    
    // Check if Neovim is installed
    const has_nvim = checkCommand("nvim");
    if (!has_nvim) {
        std.debug.print("  ⚠️  Neovim not found. Please install Neovim first.\n", .{});
        return;
    }
    
    std.debug.print("  📝 Neovim Zion plugin setup:\n", .{});
    std.debug.print("    Add to your Neovim config (init.lua):\n", .{});
    std.debug.print("    \n", .{});
    std.debug.print("    -- Using lazy.nvim\n", .{});
    std.debug.print("    {\n", .{});
    std.debug.print("      'ghostkellz/zion.nvim',\n", .{});
    std.debug.print("      dependencies = { 'nvim-telescope/telescope.nvim' },\n", .{});
    std.debug.print("      config = function() require('zion').setup() end,\n", .{});
    std.debug.print("      ft = { 'zig' },\n", .{});
    std.debug.print("    }\n", .{});
    
    // Create basic zion.nvim config file if it doesn't exist
    try createNvimConfig(allocator);
    
    std.debug.print("  ✅ Neovim integration setup instructions provided\n", .{});
}

/// Setup development tools
fn setupTools(allocator: Allocator, args: [][:0]u8) !void {
    _ = args;
    
    std.debug.print("🛠️  Setting up development tools...\n", .{});
    
    const tools = [_][]const u8{
        "git",
        "curl", 
        "tar",
        "unzip",
    };
    
    for (tools) |tool| {
        const has_tool = checkCommand(tool);
        const status = if (has_tool) "✅" else "❌";
        std.debug.print("  {s} {s}\n", .{ status, tool });
    }
    
    // Create development directories
    try createDevDirectories(allocator);
    
    std.debug.print("  ✅ Development tools check complete\n", .{});
}

/// Verify the entire setup
fn verifySetup(allocator: Allocator) !void {
    std.debug.print("🔍 Verifying Zion setup...\n", .{});
    
    var all_good = true;
    
    // Check Zig
    std.debug.print("  🔧 Zig: ", .{});
    if (checkCommand("zig")) {
        std.debug.print("✅ Found\n", .{});
    } else {
        std.debug.print("❌ Not found\n", .{});
        all_good = false;
    }
    
    // Check ZLS
    std.debug.print("  🧠 ZLS: ", .{});
    if (checkCommand("zls")) {
        std.debug.print("✅ Found\n", .{});
    } else {
        std.debug.print("⚠️  Not found (optional)\n", .{});
    }
    
    // Check Zion
    std.debug.print("  🦎 Zion: ", .{});
    if (checkZionInPath()) {
        std.debug.print("✅ In PATH\n", .{});
    } else {
        std.debug.print("⚠️  Not in PATH\n", .{});
    }
    
    // Check shell completions
    std.debug.print("  🐚 Shell completions: ", .{});
    if (try checkShellCompletions(allocator)) {
        std.debug.print("✅ Installed\n", .{});
    } else {
        std.debug.print("⚠️  Not found\n", .{});
    }
    
    if (all_good) {
        std.debug.print("\n🎉 Setup verification successful!\n", .{});
        std.debug.print("🦎 Your Zig development environment is ready!\n", .{});
    } else {
        std.debug.print("\n⚠️  Some issues found. Run setup commands to fix.\n", .{});
    }
}

// Helper functions

fn checkSystemZig(allocator: Allocator) bool {
    _ = allocator;
    return checkCommand("zig");
}

fn checkCommand(command: []const u8) bool {
    const which_args = [_][]const u8{ "which", command };
    var child = std.process.Child.init(&which_args, std.heap.page_allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    
    const result = child.spawnAndWait() catch return false;
    return result.Exited == 0;
}

fn detectShell() []const u8 {
    if (std.posix.getenv("ZSH_VERSION")) |_| return "zsh";
    if (std.posix.getenv("BASH_VERSION")) |_| return "bash";
    if (std.posix.getenv("FISH_VERSION")) |_| return "fish";
    
    // Fallback to checking SHELL env var
    if (std.posix.getenv("SHELL")) |shell| {
        if (std.mem.endsWith(u8, shell, "zsh")) return "zsh";
        if (std.mem.endsWith(u8, shell, "bash")) return "bash";
        if (std.mem.endsWith(u8, shell, "fish")) return "fish";
    }
    
    return "bash"; // Default fallback
}

fn setupShellPath(allocator: Allocator, shell: []const u8) !void {
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const zion_bin_path = try std.fmt.allocPrint(allocator, "{s}/.local/bin", .{home_dir});
    defer allocator.free(zion_bin_path);
    
    const shell_config = if (std.mem.eql(u8, shell, "zsh")) 
        try std.fmt.allocPrint(allocator, "{s}/.zshrc", .{home_dir})
    else if (std.mem.eql(u8, shell, "fish"))
        try std.fmt.allocPrint(allocator, "{s}/.config/fish/config.fish", .{home_dir})
    else
        try std.fmt.allocPrint(allocator, "{s}/.bashrc", .{home_dir});
    defer allocator.free(shell_config);
    
    const export_line = if (std.mem.eql(u8, shell, "fish"))
        try std.fmt.allocPrint(allocator, "set -gx PATH {s} $PATH  # Added by zion\n", .{zion_bin_path})
    else
        try std.fmt.allocPrint(allocator, "export PATH=\"{s}:$PATH\"  # Added by zion\n", .{zion_bin_path});
    defer allocator.free(export_line);
    
    // Check if already added
    const existing_content = fs.cwd().readFileAlloc(shell_config, allocator, @enumFromInt(1024 * 1024)) catch "";
    defer allocator.free(existing_content);
    
    if (std.mem.indexOf(u8, existing_content, "# Added by zion") != null) {
        std.debug.print("    PATH already configured\n", .{});
        return;
    }
    
    // Append to shell config
    const file = fs.cwd().openFile(shell_config, .{ .mode = .write_only }) catch |err| {
        if (err == error.FileNotFound) {
            try fs.cwd().writeFile(.{ .sub_path = shell_config, .data = export_line });
            std.debug.print("    Created {s} with PATH\n", .{shell_config});
            return;
        }
        return err;
    };
    defer file.close();
    
    try file.seekFromEnd(0);
    try file.writeAll("\n");
    try file.writeAll(export_line);
    
    std.debug.print("    Added PATH to {s}\n", .{shell_config});
}

fn setupShellCompletions(allocator: Allocator, shell: []const u8) !void {
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    
    if (std.mem.eql(u8, shell, "zsh")) {
        const completion_dir = try std.fmt.allocPrint(allocator, "{s}/.zsh/completions", .{home_dir});
        defer allocator.free(completion_dir);
        
        try fs.cwd().makePath(completion_dir);
        
        const completion_file = try std.fmt.allocPrint(allocator, "{s}/_zion", .{completion_dir});
        defer allocator.free(completion_file);
        
        // Copy completion file if it exists
        fs.cwd().copyFile("release/completions/zion.zsh", fs.cwd(), completion_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("    ⚠️  Completion file not found (run from zion repo)\n", .{});
                return;
            }
        };
        
        std.debug.print("    Zsh completions installed\n", .{});
    } else if (std.mem.eql(u8, shell, "bash")) {
        const completion_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/bash-completion/completions", .{home_dir});
        defer allocator.free(completion_dir);
        
        try fs.cwd().makePath(completion_dir);
        
        const completion_file = try std.fmt.allocPrint(allocator, "{s}/zion", .{completion_dir});
        defer allocator.free(completion_file);
        
        fs.cwd().copyFile("release/completions/zion.bash", fs.cwd(), completion_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("    ⚠️  Completion file not found (run from zion repo)\n", .{});
                return;
            }
        };
        
        std.debug.print("    Bash completions installed\n", .{});
    } else if (std.mem.eql(u8, shell, "fish")) {
        const completion_dir = try std.fmt.allocPrint(allocator, "{s}/.config/fish/completions", .{home_dir});
        defer allocator.free(completion_dir);
        
        try fs.cwd().makePath(completion_dir);
        
        const completion_file = try std.fmt.allocPrint(allocator, "{s}/zion.fish", .{completion_dir});
        defer allocator.free(completion_file);
        
        fs.cwd().copyFile("release/completions/zion.fish", fs.cwd(), completion_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("    ⚠️  Completion file not found (run from zion repo)\n", .{});
                return;
            }
        };
        
        std.debug.print("    Fish completions installed\n", .{});
    }
}

fn createZLSConfig(allocator: Allocator) !void {
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/zls", .{home_dir});
    defer allocator.free(config_dir);
    
    try fs.cwd().makePath(config_dir);
    
    const config_file = try std.fmt.allocPrint(allocator, "{s}/zls.json", .{config_dir});
    defer allocator.free(config_file);
    
    const config_content =
        \\{
        \\  "enable_semantic_tokens": true,
        \\  "enable_inlay_hints": true,
        \\  "enable_snippets": true,
        \\  "warn_style": true,
        \\  "highlight_global_var_declarations": true
        \\}
        \\
    ;
    
    fs.cwd().access(config_file, .{}) catch |err| {
        if (err == error.FileNotFound) {
            try fs.cwd().writeFile(.{ .sub_path = config_file, .data = config_content });
            std.debug.print("  📝 Created ZLS config: {s}\n", .{config_file});
        }
    };
}

fn createNvimConfig(allocator: Allocator) !void {
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/nvim/lua/zion", .{home_dir});
    defer allocator.free(config_dir);
    
    try fs.cwd().makePath(config_dir);
    
    const config_file = try std.fmt.allocPrint(allocator, "{s}/setup.lua", .{config_dir});
    defer allocator.free(config_file);
    
    const config_content =
        \\-- Zion.nvim setup example
        \\-- Add this to your init.lua or create as a separate file
        \\
        \\return {
        \\  'ghostkellz/zion.nvim',
        \\  dependencies = {
        \\    'nvim-telescope/telescope.nvim',
        \\    'nvim-lua/plenary.nvim',
        \\  },
        \\  config = function()
        \\    require('zion').setup({
        \\      auto_update = false,
        \\      keymaps = {
        \\        add_dependency = '<leader>za',
        \\        search_packages = '<leader>zs',
        \\        build_project = '<leader>zb',
        \\      },
        \\    })
        \\  end,
        \\  ft = { 'zig' },
        \\}
        \\
    ;
    
    fs.cwd().access(config_file, .{}) catch |err| {
        if (err == error.FileNotFound) {
            try fs.cwd().writeFile(.{ .sub_path = config_file, .data = config_content });
            std.debug.print("  📝 Created Neovim config example: {s}\n", .{config_file});
        }
    };
}

fn createDevDirectories(allocator: Allocator) !void {
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    
    const directories = [_][]const u8{
        "/.local/bin",
        "/.local/share/zion",
        "/.config/zion", 
        "/dev/zig",
    };
    
    for (directories) |dir| {
        const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ home_dir, dir });
        defer allocator.free(full_path);
        
        fs.cwd().makePath(full_path) catch |err| {
            if (err != error.PathAlreadyExists) {
                std.debug.print("    ⚠️  Could not create {s}\n", .{full_path});
            }
        };
    }
    
    std.debug.print("    Development directories created\n", .{});
}

fn checkZionInPath() bool {
    return checkCommand("zion");
}

fn checkShellCompletions(allocator: Allocator) !bool {
    const home_dir = std.posix.getenv("HOME") orelse return false;
    
    const completion_paths = [_][]const u8{
        "/.zsh/completions/_zion",
        "/.local/share/bash-completion/completions/zion",
        "/.config/fish/completions/zion.fish",
    };
    
    for (completion_paths) |path| {
        const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ home_dir, path });
        defer allocator.free(full_path);
        
        fs.cwd().access(full_path, .{}) catch continue;
        return true; // Found at least one
    }
    
    return false;
}

fn printSetupHelp() void {
    std.debug.print("🇺🇸 Zion Setup - 'One Nation Under Zig' 🦎\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion setup <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    all                     Complete Zig development setup\n", .{});
    std.debug.print("    zig [--version=X.Y.Z]   Setup Zig version management\n", .{});
    std.debug.print("    zls                     Setup ZLS (Zig Language Server)\n", .{});
    std.debug.print("    shell [--zsh|--bash]    Setup shell integration\n", .{});
    std.debug.print("    nvim                    Setup Neovim integration\n", .{});
    std.debug.print("    tools                   Setup development tools\n", .{});
    std.debug.print("    verify                  Verify setup completion\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion setup all              # Complete setup (recommended)\n", .{});
    std.debug.print("    zion setup zig              # Install latest Zig\n", .{});
    std.debug.print("    zion setup shell --zsh       # Setup zsh integration\n", .{});
    std.debug.print("    zion setup verify            # Check everything works\n", .{});
}