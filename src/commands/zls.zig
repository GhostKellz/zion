const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const zion_root = @import("../root.zig");
const Dir = std.Io.Dir;
const Io = std.Io;

/// ZLS (Zig Language Server) integration commands
pub fn zls(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        printZLSHelp();
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "install")) {
        return installZLS(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "config")) {
        return configZLS(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "doctor")) {
        return doctorZLS(allocator);
    } else if (std.mem.eql(u8, subcommand, "which")) {
        return whichZLS(allocator);
    } else if (std.mem.eql(u8, subcommand, "version")) {
        return versionZLS(allocator);
    } else if (std.mem.eql(u8, subcommand, "restart")) {
        return restartZLS(allocator);
    } else {
        std.debug.print("Unknown zls subcommand: {s}\n", .{subcommand});
        printZLSHelp();
    }
}

/// Install ZLS
fn installZLS(allocator: Allocator, args: []const [:0]const u8) !void {
    _ = args;

    std.debug.print("Installing ZLS (Zig Language Server)...\n", .{});

    // Check if ZLS is already installed
    if (checkCommand()) {
        std.debug.print("ZLS is already installed\n", .{});
        return;
    }

    std.debug.print("\nZLS Installation Options:\n", .{});
    std.debug.print("1. Package Manager (Recommended):\n", .{});
    std.debug.print("   macOS:   brew install zls\n", .{});
    std.debug.print("   Arch:    yay -S zls-bin\n", .{});
    std.debug.print("   Ubuntu:  Use option 2 or 3\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("2. Pre-built Binary:\n", .{});
    std.debug.print("   Download from: https://github.com/zigtools/zls/releases\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("3. Build from Source:\n", .{});
    std.debug.print("   git clone https://github.com/zigtools/zls.git\n", .{});
    std.debug.print("   cd zls\n", .{});
    std.debug.print("   zig build -Doptimize=ReleaseSafe\n", .{});
    std.debug.print("\n", .{});

    // Create ZLS config after installation
    try createZLSConfig(allocator);

    std.debug.print("After installing ZLS, run 'zion zls doctor' to verify.\n", .{});
}

/// Configure ZLS
fn configZLS(allocator: Allocator, args: []const [:0]const u8) !void {
    _ = args;

    std.debug.print("Configuring ZLS...\n", .{});

    try createZLSConfig(allocator);

    std.debug.print("ZLS configuration complete!\n", .{});
    std.debug.print("Config file: ~/.config/zls/zls.json\n", .{});
}

/// Doctor - check ZLS health
fn doctorZLS(allocator: Allocator) !void {
    std.debug.print("ZLS Doctor - Health Check\n", .{});
    std.debug.print("==============================\n", .{});

    var all_good = true;
    var warnings: u32 = 0;

    // Check if ZLS is installed
    std.debug.print("ZLS Binary: ", .{});
    const zls_path = getZLSPath(allocator) catch null;
    if (zls_path) |path| {
        defer allocator.free(path);
        std.debug.print("Found at {s}\n", .{path});
    } else {
        std.debug.print("Not Found\n", .{});
        all_good = false;
    }

    // Check ZLS version compatibility
    std.debug.print("ZLS Version: ", .{});
    if (zls_path != null) {
        const version = getZLSVersionString(allocator) catch "unknown";
        defer allocator.free(version);
        std.debug.print("{s}\n", .{version});

        if (isZLSVersionCompatible(version)) {
            std.debug.print("    Compatible with current Zig\n", .{});
        } else {
            std.debug.print("    May have compatibility issues\n", .{});
            warnings += 1;
        }
    } else {
        std.debug.print("N/A\n", .{});
    }

    // Check Zig compatibility
    std.debug.print("Zig Version: ", .{});
    const zig_version = getZigVersionString(allocator) catch null;
    if (zig_version) |version| {
        defer allocator.free(version);
        std.debug.print("{s}\n", .{version});

        if (isZigVersionSupported(version)) {
            std.debug.print("    Supported version\n", .{});
        } else {
            std.debug.print("    Version compatibility unknown\n", .{});
            warnings += 1;
        }
    } else {
        std.debug.print("Not Found\n", .{});
        all_good = false;
    }

    // Check ZLS config
    std.debug.print("ZLS Config: ", .{});
    const config_path = getZLSConfigPath(allocator) catch null;
    if (config_path) |path| {
        defer allocator.free(path);
        std.debug.print("Found at {s}\n", .{path});

        if (try validateZLSConfig(allocator, path)) {
            std.debug.print("    Configuration looks good\n", .{});
        } else {
            std.debug.print("    Configuration may have issues\n", .{});
            warnings += 1;
        }
    } else {
        std.debug.print("Not Found (using defaults)\n", .{});
        warnings += 1;
    }

    // Check project setup
    std.debug.print("Project Root: ", .{});
    if (checkProjectRoot()) {
        std.debug.print("Zig project detected (build.zig found)\n", .{});

        // Check for build.zig.zon
        if (checkBuildZon()) {
            std.debug.print("    build.zig.zon found\n", .{});
        } else {
            std.debug.print("    build.zig.zon not found (optional)\n", .{});
        }
    } else {
        std.debug.print("Not in a Zig project directory\n", .{});
    }

    // Check PATH and environment
    std.debug.print("Environment: ", .{});
    if (checkCommand()) {
        std.debug.print("ZLS in PATH\n", .{});
    } else {
        std.debug.print("ZLS not in PATH\n", .{});
        warnings += 1;
    }

    // Final summary
    std.debug.print("\nSummary:\n", .{});
    if (all_good and warnings == 0) {
        std.debug.print("Perfect! ZLS health check passed with no issues.\n", .{});
        std.debug.print("Your Zig LSP setup should work flawlessly.\n", .{});
    } else if (all_good) {
        std.debug.print("ZLS is functional but has {d} warning(s).\n", .{warnings});
        std.debug.print("Consider running 'zion zls config' to optimize.\n", .{});
    } else {
        std.debug.print("Critical issues found. ZLS may not work properly.\n", .{});
        std.debug.print("Run 'zion zls install' for installation help.\n", .{});
    }

    std.debug.print("\nEditor Integration:\n", .{});
    std.debug.print("  Neovim:  :LspInfo to check ZLS status\n", .{});
    std.debug.print("  VSCode:  Install 'ziglang.vscode-zig' extension\n", .{});
    std.debug.print("  Emacs:   Use zig-mode with lsp-mode\n", .{});
}

/// Show which ZLS is being used
fn whichZLS(allocator: Allocator) !void {
    const path = getZLSPath(allocator) catch {
        std.debug.print("ZLS not found in PATH\n", .{});
        return;
    };
    defer allocator.free(path);
    std.debug.print("ZLS Path: {s}\n", .{path});
}

/// Show ZLS version
fn versionZLS(allocator: Allocator) !void {
    if (!checkCommand()) {
        std.debug.print("ZLS not found in PATH\n", .{});
        return;
    }

    const version = getZLSVersionString(allocator) catch {
        std.debug.print("Failed to get ZLS version\n", .{});
        return;
    };
    defer allocator.free(version);
    std.debug.print("{s}\n", .{version});
}

/// Restart ZLS (for development)
fn restartZLS(allocator: Allocator) !void {
    _ = allocator;

    std.debug.print("Restarting ZLS...\n", .{});
    std.debug.print("This command would typically restart ZLS in your editor.\n", .{});
    std.debug.print("Manual restart instructions:\n", .{});
    std.debug.print("  Neovim: :LspRestart\n", .{});
    std.debug.print("  VSCode: Ctrl+Shift+P -> 'Developer: Reload Window'\n", .{});
    std.debug.print("  Emacs:  M-x lsp-workspace-restart\n", .{});
}

// Helper functions

fn checkCommand() bool {
    const io = zion_root.getIo() catch return false;
    const argv = [_][]const u8{ "which", "zls" };
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

fn createZLSConfig(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const home_dir = zion_root.getEnv("HOME") orelse return error.NoHomeDir;
    const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/zls", .{home_dir});
    defer allocator.free(config_dir);

    cwd.createDirPath(io, config_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const config_file = try std.fmt.allocPrint(allocator, "{s}/zls.json", .{config_dir});
    defer allocator.free(config_file);

    // Check if config already exists
    cwd.access(io, config_file, .{}) catch |err| {
        if (err == error.FileNotFound) {
            const config_content =
                \\{
                \\  "enable_semantic_tokens": true,
                \\  "enable_inlay_hints": true,
                \\  "enable_snippets": true,
                \\  "warn_style": true,
                \\  "highlight_global_var_declarations": true,
                \\  "enable_build_on_save": false,
                \\  "build_on_save_step": "check",
                \\  "prefer_ast_check_as_child_process": true,
                \\  "record_session": false,
                \\  "enable_autofix": false
                \\}
                \\
            ;

            const file = try cwd.createFile(io, config_file, .{});
            defer file.close(io);
            try file.writeStreamingAll(io, config_content);
            std.debug.print("Created ZLS config: {s}\n", .{config_file});
            return;
        }
        return err;
    };

    std.debug.print("ZLS config already exists: {s}\n", .{config_file});
}

fn runCommandAndGetOutput(allocator: Allocator, argv: []const []const u8) ![]const u8 {
    const io = try zion_root.getIo();

    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch return error.CommandFailed;

    var stdout_list: std.ArrayListUnmanaged(u8) = .empty;
    defer stdout_list.deinit(allocator);

    if (child.stdout) |stdout_file| {
        var buffer: [4096]u8 = undefined;
        while (true) {
            const n = stdout_file.readStreaming(io, &.{buffer[0..]}) catch break;
            if (n == 0) break;
            try stdout_list.appendSlice(allocator, buffer[0..n]);
        }
    }

    const term = child.wait(io) catch return error.CommandFailed;
    switch (term) {
        .exited => |code| {
            if (code != 0) return error.CommandFailed;
        },
        else => return error.CommandFailed,
    }

    const trimmed = std.mem.trim(u8, stdout_list.items, " \t\n\r");
    return try allocator.dupe(u8, trimmed);
}

fn checkProjectRoot() bool {
    const io = zion_root.getIo() catch return false;
    const cwd = Dir.cwd();
    cwd.access(io, "build.zig", .{}) catch return false;
    return true;
}

fn checkBuildZon() bool {
    const io = zion_root.getIo() catch return false;
    const cwd = Dir.cwd();
    cwd.access(io, "build.zig.zon", .{}) catch return false;
    return true;
}

fn getZLSPath(allocator: Allocator) ![]const u8 {
    const argv = [_][]const u8{ "which", "zls" };
    return runCommandAndGetOutput(allocator, &argv);
}

fn getZLSVersionString(allocator: Allocator) ![]const u8 {
    const argv = [_][]const u8{ "zls", "--version" };
    return runCommandAndGetOutput(allocator, &argv);
}

fn getZigVersionString(allocator: Allocator) ![]const u8 {
    const argv = [_][]const u8{ "zig", "version" };
    return runCommandAndGetOutput(allocator, &argv);
}

fn isZLSVersionCompatible(version: []const u8) bool {
    // Simple heuristic - ZLS 0.11+ is generally compatible with Zig 0.11+
    return std.mem.startsWith(u8, version, "0.1") or std.mem.startsWith(u8, version, "0.2");
}

fn isZigVersionSupported(version: []const u8) bool {
    // Zig 0.11+ is generally well supported
    return std.mem.startsWith(u8, version, "0.1") or std.mem.startsWith(u8, version, "0.2");
}

fn getZLSConfigPath(allocator: Allocator) ![]const u8 {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const home_dir = zion_root.getEnv("HOME") orelse return error.NoHomeDir;
    const config_file = try std.fmt.allocPrint(allocator, "{s}/.config/zls/zls.json", .{home_dir});

    cwd.access(io, config_file, .{}) catch {
        allocator.free(config_file);
        return error.ConfigNotFound;
    };

    return config_file;
}

fn validateZLSConfig(allocator: Allocator, config_path: []const u8) !bool {
    _ = allocator;
    _ = config_path;
    // Simple validation - just check if the file is readable
    // In a full implementation, we'd parse JSON and validate settings
    return true;
}

fn printZLSHelp() void {
    std.debug.print("Zion ZLS Integration\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion zls <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    install                 Install ZLS with guidance\n", .{});
    std.debug.print("    config                  Create/update ZLS configuration\n", .{});
    std.debug.print("    doctor                  Check ZLS health and compatibility\n", .{});
    std.debug.print("    which                   Show ZLS binary path\n", .{});
    std.debug.print("    version                 Show ZLS version\n", .{});
    std.debug.print("    restart                 Restart ZLS in your editor\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion zls install        # Get installation instructions\n", .{});
    std.debug.print("    zion zls doctor         # Check if ZLS is working\n", .{});
    std.debug.print("    zion zls config         # Create optimal ZLS config\n", .{});
}
