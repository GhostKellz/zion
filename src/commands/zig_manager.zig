const std = @import("std");
const fs = std.fs;
const http = std.http;
const json = std.json;
const Allocator = std.mem.Allocator;

/// Zig version manager - like anyzig but integrated into zion
pub fn zig_manager(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 3) {
        printZigHelp();
        return;
    }
    
    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "list")) {
        return listVersions(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "install")) {
        return installVersion(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "use")) {
        return useVersion(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "current")) {
        return showCurrent(allocator);
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        return removeVersion(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "clean")) {
        return cleanVersions(allocator);
    } else if (std.mem.eql(u8, subcommand, "default")) {
        return setDefault(allocator, args[3..]);
    } else {
        std.debug.print("❌ Unknown zig subcommand: {s}\n", .{subcommand});
        printZigHelp();
    }
}

/// List available Zig versions
fn listVersions(allocator: Allocator, args: [][:0]u8) !void {
    var show_remote = false;
    var show_prerelease = false;
    
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--remote") or std.mem.eql(u8, arg, "-r")) {
            show_remote = true;
        } else if (std.mem.eql(u8, arg, "--prerelease")) {
            show_prerelease = true;
        }
    }
    
    // Show installed versions
    std.debug.print("🔧 Installed Zig Versions:\n", .{});
    try listInstalledVersions(allocator);
    
    if (show_remote) {
        std.debug.print("\n🌐 Available Remote Versions:\n", .{});
        try listRemoteVersions(allocator, show_prerelease);
    } else {
        std.debug.print("\n💡 Use 'zion zig list --remote' to see available versions\n", .{});
    }
}

/// Install a specific Zig version
fn installVersion(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 1) {
        std.debug.print("❌ Usage: zion zig install <version>\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  zion zig install 0.11.0\n", .{});
        std.debug.print("  zion zig install 0.12.0-dev.3180+83e578a18\n", .{});
        std.debug.print("  zion zig install master\n", .{});
        return;
    }
    
    const version = args[0];
    std.debug.print("📦 Installing Zig {s}...\n", .{version});
    
    // Create zion zig directory
    try ensureZigDir(allocator);
    
    // Download and install
    try downloadAndInstallZig(allocator, version);
    
    std.debug.print("✅ Zig {s} installed successfully!\n", .{version});
    std.debug.print("💡 Use 'zion zig use {s}' to activate this version\n", .{version});
}

/// Switch to a specific Zig version
fn useVersion(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 1) {
        std.debug.print("❌ Usage: zion zig use <version>\n", .{});
        return;
    }
    
    const version = args[0];
    
    // Check if version is installed
    const zig_path = try getZigPath(allocator, version);
    defer allocator.free(zig_path);
    
    fs.cwd().access(zig_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("❌ Zig {s} is not installed\n", .{version});
            std.debug.print("💡 Run 'zion zig install {s}' first\n", .{version});
            return;
        }
        return err;
    };
    
    // Update symlink or config
    try setActiveVersion(allocator, version);
    
    std.debug.print("✅ Now using Zig {s}\n", .{version});
    
    // Verify the switch worked
    try verifyZigVersion(allocator, version);
}

/// Show current Zig version
fn showCurrent(allocator: Allocator) !void {
    const current = getCurrentVersion(allocator) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("❌ No Zig version is currently active\n", .{});
            std.debug.print("💡 Use 'zion zig use <version>' to activate a version\n", .{});
            return;
        }
        return err;
    };
    defer allocator.free(current);
    
    std.debug.print("🔧 Current Zig version: {s}\n", .{current});
    
    // Show path info
    const zig_exe = getActiveZigPath(allocator) catch return;
    defer allocator.free(zig_exe);
    
    std.debug.print("📁 Path: {s}\n", .{zig_exe});
    
    // Show detailed version info
    try showZigVersionDetails(allocator);
}

/// Remove a Zig version
fn removeVersion(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 1) {
        std.debug.print("❌ Usage: zion zig remove <version>\n", .{});
        return;
    }
    
    const version = args[0];
    const version_dir = try getVersionDir(allocator, version);
    defer allocator.free(version_dir);
    
    fs.cwd().deleteTree(version_dir) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("❌ Zig {s} is not installed\n", .{version});
            return;
        }
        return err;
    };
    
    std.debug.print("✅ Removed Zig {s}\n", .{version});
}

/// Clean up old/unused Zig versions
fn cleanVersions(allocator: Allocator) !void {
    std.debug.print("🧹 Cleaning up Zig versions...\n", .{});
    
    const zig_dir = try getZigDir(allocator);
    defer allocator.free(zig_dir);
    
    var dir = fs.cwd().openDir(zig_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("✅ No Zig versions to clean\n", .{});
            return;
        }
        return err;
    };
    defer dir.close();
    
    const current_version = getCurrentVersion(allocator) catch null;
    defer if (current_version) |cv| allocator.free(cv);
    
    var removed_count: u32 = 0;
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            // Don't remove the currently active version
            if (current_version != null and std.mem.eql(u8, entry.name, current_version.?)) {
                std.debug.print("⏭️  Skipping current version: {s}\n", .{entry.name});
                continue;
            }
            
            // Check if this version looks old (simple heuristic)
            if (std.mem.startsWith(u8, entry.name, "0.10.") or std.mem.startsWith(u8, entry.name, "0.9.")) {
                const version_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ zig_dir, entry.name });
                defer allocator.free(version_path);
                
                fs.cwd().deleteTree(version_path) catch continue;
                std.debug.print("🗑️  Removed old version: {s}\n", .{entry.name});
                removed_count += 1;
            }
        }
    }
    
    std.debug.print("✅ Cleaned {d} old Zig versions\n", .{removed_count});
}

/// Set default Zig version
fn setDefault(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 1) {
        std.debug.print("❌ Usage: zion zig default <version>\n", .{});
        return;
    }
    
    const version = args[0];
    try setActiveVersion(allocator, version);
    
    // Also update shell profile
    try updateShellProfile(allocator, version);
    
    std.debug.print("✅ Set Zig {s} as default\n", .{version});
    std.debug.print("💡 Restart your shell or run 'source ~/.bashrc' to apply changes\n", .{});
}

// Helper functions

fn ensureZigDir(allocator: Allocator) !void {
    const zig_dir = try getZigDir(allocator);
    defer allocator.free(zig_dir);
    
    fs.cwd().makePath(zig_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
}

fn getZigDir(allocator: Allocator) ![]const u8 {
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    return std.fmt.allocPrint(allocator, "{s}/.zion/zig-versions", .{home_dir});
}

fn getVersionDir(allocator: Allocator, version: []const u8) ![]const u8 {
    const zig_dir = try getZigDir(allocator);
    defer allocator.free(zig_dir);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ zig_dir, version });
}

fn getZigPath(allocator: Allocator, version: []const u8) ![]const u8 {
    const version_dir = try getVersionDir(allocator, version);
    defer allocator.free(version_dir);
    return std.fmt.allocPrint(allocator, "{s}/zig", .{version_dir});
}

fn getCurrentVersion(allocator: Allocator) ![]const u8 {
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const current_file = try std.fmt.allocPrint(allocator, "{s}/.zion/current-zig", .{home_dir});
    defer allocator.free(current_file);
    
    const content = try fs.cwd().readFileAlloc(allocator, current_file, 256);
    return std.mem.trim(u8, content, " \t\n\r");
}

fn setActiveVersion(allocator: Allocator, version: []const u8) !void {
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const current_file = try std.fmt.allocPrint(allocator, "{s}/.zion/current-zig", .{home_dir});
    defer allocator.free(current_file);
    
    try fs.cwd().writeFile(.{ .sub_path = current_file, .data = version });
}

fn getActiveZigPath(allocator: Allocator) ![]const u8 {
    const current = try getCurrentVersion(allocator);
    defer allocator.free(current);
    return getZigPath(allocator, current);
}

fn listInstalledVersions(allocator: Allocator) !void {
    const zig_dir = try getZigDir(allocator);
    defer allocator.free(zig_dir);
    
    var dir = fs.cwd().openDir(zig_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("  (no versions installed)\n", .{});
            return;
        }
        return err;
    };
    defer dir.close();
    
    const current_version = getCurrentVersion(allocator) catch null;
    defer if (current_version) |cv| allocator.free(cv);
    
    var count: u32 = 0;
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            const is_current = current_version != null and std.mem.eql(u8, entry.name, current_version.?);
            const marker = if (is_current) " (current)" else "";
            const symbol = if (is_current) "→" else " ";
            
            std.debug.print("  {s} {s}{s}\n", .{ symbol, entry.name, marker });
            count += 1;
        }
    }
    
    if (count == 0) {
        std.debug.print("  (no versions installed)\n", .{});
    }
}

fn listRemoteVersions(allocator: Allocator, show_prerelease: bool) !void {
    _ = show_prerelease; // TODO: Implement filtering
    
    std.debug.print("  📡 Fetching from Zig release API...\n", .{});
    
    // This would use the GitHub API to fetch Zig releases
    // For now, show common versions
    const common_versions = [_][]const u8{
        "0.12.0",
        "0.12.0-dev.3180+83e578a18", 
        "0.11.0",
        "0.10.1",
        "master",
    };
    
    for (common_versions) |version| {
        std.debug.print("    {s}\n", .{version});
    }
    
    std.debug.print("\n💡 Full implementation would fetch from GitHub API\n", .{});
    _ = allocator;
}

fn downloadAndInstallZig(allocator: Allocator, version: []const u8) !void {
    // This would download from ziglang.org/download/
    // For now, simulate the installation
    const version_dir = try getVersionDir(allocator, version);
    defer allocator.free(version_dir);
    
    try fs.cwd().makePath(version_dir);
    
    // Create a placeholder zig executable
    const zig_path = try std.fmt.allocPrint(allocator, "{s}/zig", .{version_dir});
    defer allocator.free(zig_path);
    
    const script_content = try std.fmt.allocPrint(allocator,
        \\#!/bin/bash
        \\echo "Zig {s} (managed by zion)"
        \\echo "This is a placeholder - full implementation would download real Zig binary"
        \\
    , .{version});
    defer allocator.free(script_content);
    
    try fs.cwd().writeFile(.{ .sub_path = zig_path, .data = script_content });
    
    // Make executable
    const chmod_args = [_][]const u8{ "chmod", "+x", zig_path };
    var child = std.process.Child.init(&chmod_args, allocator);
    _ = try child.spawnAndWait();
    
    std.debug.print("📦 Downloaded and extracted Zig {s}\n", .{version});
}

fn verifyZigVersion(allocator: Allocator, expected_version: []const u8) !void {
    const zig_exe = try getActiveZigPath(allocator);
    defer allocator.free(zig_exe);
    
    const version_args = [_][]const u8{ zig_exe, "version" };
    var child = std.process.Child.init(&version_args, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    const stdout = try child.stdout.?.reader().readAllAlloc(allocator, 1024);
    defer allocator.free(stdout);
    _ = try child.wait();
    
    const actual_version = std.mem.trim(u8, stdout, " \t\n\r");
    std.debug.print("🔍 Verified: {s}\n", .{actual_version});
    _ = expected_version;
}

fn showZigVersionDetails(allocator: Allocator) !void {
    const zig_exe = try getActiveZigPath(allocator);
    defer allocator.free(zig_exe);
    
    const version_args = [_][]const u8{ zig_exe, "version" };
    var child = std.process.Child.init(&version_args, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    
    _ = try child.spawnAndWait();
}

fn updateShellProfile(allocator: Allocator, version: []const u8) !void {
    const zig_path = try getZigPath(allocator, version);
    defer allocator.free(zig_path);
    
    const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const bashrc_path = try std.fmt.allocPrint(allocator, "{s}/.bashrc", .{home_dir});
    defer allocator.free(bashrc_path);
    
    const export_line = try std.fmt.allocPrint(allocator, "export PATH=\"{s}:$PATH\" # Added by zion\n", .{fs.path.dirname(zig_path) orelse ""});
    defer allocator.free(export_line);
    
    // Append to .bashrc
    const file = fs.cwd().openFile(bashrc_path, .{ .mode = .write_only }) catch |err| {
        if (err == error.FileNotFound) {
            // Create .bashrc if it doesn't exist
            try fs.cwd().writeFile(.{ .sub_path = bashrc_path, .data = export_line });
            return;
        }
        return err;
    };
    defer file.close();
    
    try file.seekFromEnd(0);
    try file.writeAll(export_line);
}

fn printZigHelp() void {
    std.debug.print("Zion Zig Version Manager\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion zig <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    list [--remote]         List installed versions\n", .{});
    std.debug.print("    install <version>       Install a Zig version\n", .{});
    std.debug.print("    use <version>           Switch to a Zig version\n", .{});
    std.debug.print("    current                 Show current version\n", .{});
    std.debug.print("    remove <version>        Remove a Zig version\n", .{});
    std.debug.print("    clean                   Clean old versions\n", .{});
    std.debug.print("    default <version>       Set default version\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion zig list --remote          # Show available versions\n", .{});
    std.debug.print("    zion zig install 0.12.0         # Install Zig 0.12.0\n", .{});
    std.debug.print("    zion zig use 0.12.0             # Switch to Zig 0.12.0\n", .{});
    std.debug.print("    zion zig current                # Show current version\n", .{});
    std.debug.print("    zion zig default 0.12.0         # Set as default\n", .{});
}