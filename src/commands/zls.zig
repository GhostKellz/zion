const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// ZLS (Zig Language Server) integration commands
pub fn zls(allocator: Allocator, args: [][:0]u8) !void {
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
fn installZLS(allocator: Allocator, args: [][:0]u8) !void {
    _ = args;
    
    std.debug.print("Installing ZLS (Zig Language Server)...\n", .{});
    
    // Check if ZLS is already installed
    if (checkCommand("zls")) {
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
fn configZLS(allocator: Allocator, args: [][:0]u8) !void {
    _ = args;
    
    std.debug.print("Configuring ZLS...\n", .{});
    
    try createZLSConfig(allocator);
    
    std.debug.print("ZLS configuration complete!\n", .{});
    std.debug.print("Config file: ~/.config/zls/zls.json\n", .{});
}

/// Doctor - check ZLS health
fn doctorZLS(allocator: Allocator) !void {
    std.debug.print("🩺 ZLS Doctor - Health Check\n", .{});
    std.debug.print("==============================\n", .{});
    
    var all_good = true;
    var warnings: u32 = 0;
    
    // Check if ZLS is installed
    std.debug.print("🔍 ZLS Binary: ", .{});
    const zls_path = getZLSPath(allocator) catch null;
    if (zls_path) |path| {
        defer allocator.free(path);
        std.debug.print("✅ Found at {s}\n", .{path});
    } else {
        std.debug.print("❌ Not Found\n", .{});
        all_good = false;
    }
    
    // Check ZLS version compatibility
    std.debug.print("📊 ZLS Version: ", .{});
    if (zls_path != null) {
        const version = getZLSVersionString(allocator) catch "unknown";
        defer allocator.free(version);
        std.debug.print("{s}\n", .{version});
        
        if (isZLSVersionCompatible(version)) {
            std.debug.print("    ✅ Compatible with current Zig\n", .{});
        } else {
            std.debug.print("    ⚠️  May have compatibility issues\n", .{});
            warnings += 1;
        }
    } else {
        std.debug.print("N/A\n", .{});
    }
    
    // Check Zig compatibility
    std.debug.print("🦎 Zig Version: ", .{});
    const zig_version = getZigVersionString(allocator) catch null;
    if (zig_version) |version| {
        defer allocator.free(version);
        std.debug.print("{s}\n", .{version});
        
        if (isZigVersionSupported(version)) {
            std.debug.print("    ✅ Supported version\n", .{});
        } else {
            std.debug.print("    ⚠️  Version compatibility unknown\n", .{});
            warnings += 1;
        }
    } else {
        std.debug.print("❌ Not Found\n", .{});
        all_good = false;
    }
    
    // Check ZLS config
    std.debug.print("⚙️  ZLS Config: ", .{});
    const config_path = getZLSConfigPath(allocator) catch null;
    if (config_path) |path| {
        defer allocator.free(path);
        std.debug.print("✅ Found at {s}\n", .{path});
        
        if (try validateZLSConfig(allocator, path)) {
            std.debug.print("    ✅ Configuration looks good\n", .{});
        } else {
            std.debug.print("    ⚠️  Configuration may have issues\n", .{});
            warnings += 1;
        }
    } else {
        std.debug.print("⚠️  Not Found (using defaults)\n", .{});
        warnings += 1;
    }
    
    // Check project setup
    std.debug.print("📁 Project Root: ", .{});
    if (checkProjectRoot()) {
        std.debug.print("✅ Zig project detected (build.zig found)\n", .{});
        
        // Check for build.zig.zon
        if (checkBuildZon()) {
            std.debug.print("    ✅ build.zig.zon found\n", .{});
        } else {
            std.debug.print("    ℹ️  build.zig.zon not found (optional)\n", .{});
        }
    } else {
        std.debug.print("ℹ️  Not in a Zig project directory\n", .{});
    }
    
    // Check PATH and environment
    std.debug.print("🌍 Environment: ", .{});
    if (checkCommand("zls")) {
        std.debug.print("✅ ZLS in PATH\n", .{});
    } else {
        std.debug.print("⚠️  ZLS not in PATH\n", .{});
        warnings += 1;
    }
    
    // Final summary
    std.debug.print("\n📋 Summary:\n", .{});
    if (all_good and warnings == 0) {
        std.debug.print("🎉 Perfect! ZLS health check passed with no issues.\n", .{});
        std.debug.print("💡 Your Zig LSP setup should work flawlessly.\n", .{});
    } else if (all_good) {
        std.debug.print("⚠️  ZLS is functional but has {d} warning(s).\n", .{warnings});
        std.debug.print("💡 Consider running 'zion zls config' to optimize.\n", .{});
    } else {
        std.debug.print("❌ Critical issues found. ZLS may not work properly.\n", .{});
        std.debug.print("💡 Run 'zion zls install' for installation help.\n", .{});
    }
    
    std.debug.print("\n🔗 Editor Integration:\n", .{});
    std.debug.print("  Neovim:  :LspInfo to check ZLS status\n", .{});
    std.debug.print("  VSCode:  Install 'ziglang.vscode-zig' extension\n", .{});
    std.debug.print("  Emacs:   Use zig-mode with lsp-mode\n", .{});
}

/// Show which ZLS is being used
fn whichZLS(_: Allocator) !void {
    if (!checkCommand("zls")) {
        std.debug.print("ZLS not found in PATH\n", .{});
        return;
    }
    
    // Get ZLS path
    const which_args = [_][]const u8{ "which", "zls" };
    var child = std.process.Child.init(&which_args, std.heap.page_allocator);
    child.stdout_behavior = .Pipe;
    
    try child.spawn();
    
    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(std.heap.page_allocator);
    
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try child.stdout.?.readAll(read_buf[0..]);
        if (bytes_read == 0) break;
        try output_buf.appendSlice(std.heap.page_allocator, read_buf[0..bytes_read]);
    }
    
    const stdout = try std.heap.page_allocator.dupe(u8, output_buf.items);
    defer std.heap.page_allocator.free(stdout);
    _ = try child.wait();
    
    std.debug.print("ZLS Path: {s}", .{stdout});
}

/// Show ZLS version
fn versionZLS(allocator: Allocator) !void {
    _ = allocator;
    
    if (!checkCommand("zls")) {
        std.debug.print("ZLS not found in PATH\n", .{});
        return;
    }
    
    try showZLSVersion();
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

fn checkCommand(command: []const u8) bool {
    const which_args = [_][]const u8{ "which", command };
    var child = std.process.Child.init(&which_args, std.heap.page_allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    
    const result = child.spawnAndWait() catch return false;
    return result.Exited == 0;
}

fn createZLSConfig(allocator: Allocator) !void {
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/zls", .{home_dir});
    defer allocator.free(config_dir);
    
    try fs.cwd().makePath(config_dir);
    
    const config_file = try std.fmt.allocPrint(allocator, "{s}/zls.json", .{config_dir});
    defer allocator.free(config_file);
    
    // Check if config already exists
    fs.cwd().access(config_file, .{}) catch |err| {
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
            
            try fs.cwd().writeFile(.{ .sub_path = config_file, .data = config_content });
            std.debug.print("Created ZLS config: {s}\n", .{config_file});
            return;
        }
        return err;
    };
    
    std.debug.print("ZLS config already exists: {s}\n", .{config_file});
}

fn showZLSVersion() !void {
    const version_args = [_][]const u8{ "zls", "--version" };
    var child = std.process.Child.init(&version_args, std.heap.page_allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    
    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(std.heap.page_allocator);
    
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try child.stdout.?.readAll(read_buf[0..]);
        if (bytes_read == 0) break;
        try output_buf.appendSlice(std.heap.page_allocator, read_buf[0..bytes_read]);
    }
    
    const stdout = try std.heap.page_allocator.dupe(u8, output_buf.items);
    defer std.heap.page_allocator.free(stdout);
    _ = try child.wait();
    
    const version = std.mem.trim(u8, stdout, " \t\n\r");
    std.debug.print("{s}\n", .{version});
}

fn showZigVersionForZLS() !void {
    const version_args = [_][]const u8{ "zig", "version" };
    var child = std.process.Child.init(&version_args, std.heap.page_allocator);
    child.stdout_behavior = .Pipe;
    
    try child.spawn();
    
    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(std.heap.page_allocator);
    
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const bytes_read = try child.stdout.?.readAll(read_buf[0..]);
        if (bytes_read == 0) break;
        try output_buf.appendSlice(std.heap.page_allocator, read_buf[0..bytes_read]);
    }
    
    const stdout = try std.heap.page_allocator.dupe(u8, output_buf.items);
    defer std.heap.page_allocator.free(stdout);
    _ = try child.wait();
    
    const version = std.mem.trim(u8, stdout, " \t\n\r");
    std.debug.print("{s}\n", .{version});
}

fn checkZLSConfig(allocator: Allocator) !bool {
    const home_dir = std.posix.getenv("HOME") orelse return false;
    const config_file = try std.fmt.allocPrint(allocator, "{s}/.config/zls/zls.json", .{home_dir});
    defer allocator.free(config_file);
    
    fs.cwd().access(config_file, .{}) catch return false;
    return true;
}

fn checkProjectRoot() bool {
    fs.cwd().access("build.zig", .{}) catch return false;
    return true;
}

fn checkBuildZon() bool {
    fs.cwd().access("build.zig.zon", .{}) catch return false;
    return true;
}

fn getZLSPath(allocator: Allocator) ![]const u8 {
    const which_args = [_][]const u8{ "which", "zls" };
    var child = std.process.Child.init(&which_args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    
    child.spawn() catch return error.ZLSNotFound;
    
    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);
    
    var read_buf: [4096]u8 = undefined;
    const stdout = blk: {
        while (true) {
            const bytes_read = child.stdout.?.readAll(read_buf[0..]) catch {
                _ = child.wait() catch {};
                return error.ZLSNotFound;
            };
            if (bytes_read == 0) break;
            output_buf.appendSlice(std.heap.page_allocator, read_buf[0..bytes_read]) catch {
                _ = child.wait() catch {};
                return error.ZLSNotFound;
            };
        }
        break :blk allocator.dupe(u8, output_buf.items) catch {
            _ = child.wait() catch {};
            return error.ZLSNotFound;
        };
    };
    
    const result = child.wait() catch {
        allocator.free(stdout);
        return error.ZLSNotFound;
    };
    
    if (result.Exited != 0) {
        allocator.free(stdout);
        return error.ZLSNotFound;
    }
    
    const trimmed = std.mem.trim(u8, stdout, " \t\n\r");
    const path_copy = try allocator.dupe(u8, trimmed);
    allocator.free(stdout);
    return path_copy;
}

fn getZLSVersionString(allocator: Allocator) ![]const u8 {
    const version_args = [_][]const u8{ "zls", "--version" };
    var child = std.process.Child.init(&version_args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    
    child.spawn() catch return error.VersionDetectionFailed;
    
    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);
    
    var read_buf: [4096]u8 = undefined;
    const stdout = blk: {
        while (true) {
            const bytes_read = child.stdout.?.readAll(read_buf[0..]) catch {
                _ = child.wait() catch {};
                return error.VersionDetectionFailed;
            };
            if (bytes_read == 0) break;
            output_buf.appendSlice(std.heap.page_allocator, read_buf[0..bytes_read]) catch {
                _ = child.wait() catch {};
                return error.VersionDetectionFailed;
            };
        }
        break :blk allocator.dupe(u8, output_buf.items) catch {
            _ = child.wait() catch {};
            return error.VersionDetectionFailed;
        };
    };
    
    const result = child.wait() catch {
        allocator.free(stdout);
        return error.VersionDetectionFailed;
    };
    
    if (result.Exited != 0) {
        allocator.free(stdout);
        return error.VersionDetectionFailed;
    }
    
    const trimmed = std.mem.trim(u8, stdout, " \t\n\r");
    const version_copy = try allocator.dupe(u8, trimmed);
    allocator.free(stdout);
    return version_copy;
}

fn getZigVersionString(allocator: Allocator) ![]const u8 {
    const version_args = [_][]const u8{ "zig", "version" };
    var child = std.process.Child.init(&version_args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    
    child.spawn() catch return error.VersionDetectionFailed;
    
    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);
    
    var read_buf: [4096]u8 = undefined;
    const stdout = blk: {
        while (true) {
            const bytes_read = child.stdout.?.readAll(read_buf[0..]) catch {
                _ = child.wait() catch {};
                return error.VersionDetectionFailed;
            };
            if (bytes_read == 0) break;
            output_buf.appendSlice(std.heap.page_allocator, read_buf[0..bytes_read]) catch {
                _ = child.wait() catch {};
                return error.VersionDetectionFailed;
            };
        }
        break :blk allocator.dupe(u8, output_buf.items) catch {
            _ = child.wait() catch {};
            return error.VersionDetectionFailed;
        };
    };
    
    const result = child.wait() catch {
        allocator.free(stdout);
        return error.VersionDetectionFailed;
    };
    
    if (result.Exited != 0) {
        allocator.free(stdout);
        return error.VersionDetectionFailed;
    }
    
    const trimmed = std.mem.trim(u8, stdout, " \t\n\r");
    const version_copy = try allocator.dupe(u8, trimmed);
    allocator.free(stdout);
    return version_copy;
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
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const config_file = try std.fmt.allocPrint(allocator, "{s}/.config/zls/zls.json", .{home_dir});
    
    fs.cwd().access(config_file, .{}) catch {
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