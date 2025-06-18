const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const downloader = @import("../downloader.zig");

/// Zig version manager functionality (like anyzig/zigup)
/// Supports installing, switching, and managing Zig versions

/// Available Zig installation commands
pub fn zigManager(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        try printZigHelp();
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "install")) {
        if (args.len < 4) {
            std.debug.print("Error: 'zion zig install' requires a version\n", .{});
            std.debug.print("Usage: zion zig install <version>\n", .{});
            std.debug.print("Example: zion zig install 0.15.0\n", .{});
            return;
        }
        try installZig(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        try listZigVersions(allocator);
    } else if (std.mem.eql(u8, subcommand, "use")) {
        if (args.len < 4) {
            std.debug.print("Error: 'zion zig use' requires a version\n", .{});
            std.debug.print("Usage: zion zig use <version>\n", .{});
            std.debug.print("Example: zion zig use 0.15.0\n", .{});
            return;
        }
        try useZig(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "current")) {
        try currentZig(allocator);
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (args.len < 4) {
            std.debug.print("Error: 'zion zig remove' requires a version\n", .{});
            std.debug.print("Usage: zion zig remove <version>\n", .{});
            std.debug.print("Example: zion zig remove 0.14.0\n", .{});
            return;
        }
        try removeZig(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "available")) {
        try availableZigVersions(allocator);
    } else {
        std.debug.print("Unknown zig subcommand: {s}\n", .{subcommand});
        try printZigHelp();
    }
}

/// Print help for Zig version manager
fn printZigHelp() !void {
    const help_text =
        \\Zion Zig Version Manager
        \\
        \\USAGE:
        \\    zion zig <COMMAND>
        \\
        \\COMMANDS:
        \\    install <version>   Install a specific Zig version
        \\    list                List installed Zig versions
        \\    use <version>       Switch to a specific Zig version
        \\    current             Show current active Zig version
        \\    remove <version>    Remove an installed Zig version
        \\    available           Show available Zig versions for download
        \\
        \\EXAMPLES:
        \\    zion zig install 0.15.0     # Install Zig 0.15.0
        \\    zion zig list               # List installed versions
        \\    zion zig use 0.15.0         # Switch to Zig 0.15.0
        \\    zion zig current            # Show current version
        \\    zion zig available          # Show available versions
        \\
        \\NOTE: Zig versions are installed to ~/.zion/zig/ and symlinked to ~/.zion/bin/zig
        \\
    ;

    std.debug.print("{s}", .{help_text});
}

/// Install a specific Zig version
fn installZig(allocator: Allocator, version: []const u8) !void {
    std.debug.print("📦 Installing Zig {s}...\n", .{version});

    // Ensure Zion directories exist
    try ensureZionDirs(allocator);

    // Check if version is already installed
    if (try isZigInstalled(allocator, version)) {
        std.debug.print("✅ Zig {s} is already installed\n", .{version});
        return;
    }

    // Download and install Zig
    const download_url = try getZigDownloadUrl(allocator, version);
    defer allocator.free(download_url);

    const archive_path = try downloadZigArchive(allocator, version, download_url);
    defer allocator.free(archive_path);

    try extractZigArchive(allocator, version, archive_path);
    
    std.debug.print("✅ Successfully installed Zig {s}\n", .{version});
    std.debug.print("💡 Run 'zion zig use {s}' to make it active\n", .{version});
}

/// List installed Zig versions
fn listZigVersions(allocator: Allocator) !void {
    const home_dir = try getHomeDir(allocator);
    defer allocator.free(home_dir);

    const zig_dir = try std.fmt.allocPrint(allocator, "{s}/.zion/zig", .{home_dir});
    defer allocator.free(zig_dir);

    const cwd = fs.cwd();
    var dir = cwd.openDir(zig_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("No Zig versions installed\n", .{});
            std.debug.print("💡 Run 'zion zig install <version>' to install a version\n", .{});
            return;
        }
        return err;
    };
    defer dir.close();

    std.debug.print("📋 Installed Zig versions:\n", .{});

    var iterator = dir.iterate();
    var count: usize = 0;
    
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            const current = try getCurrentZig(allocator);
            defer if (current) |c| allocator.free(c);
            
            const is_current = if (current) |c| std.mem.eql(u8, entry.name, c) else false;
            const marker = if (is_current) " (current)" else "";
            
            std.debug.print("  • {s}{s}\n", .{ entry.name, marker });
            count += 1;
        }
    }

    if (count == 0) {
        std.debug.print("  (no versions installed)\n", .{});
        std.debug.print("💡 Run 'zion zig install <version>' to install a version\n", .{});
    }
}

/// Switch to a specific Zig version
fn useZig(allocator: Allocator, version: []const u8) !void {
    std.debug.print("🔄 Switching to Zig {s}...\n", .{version});

    // Check if version is installed
    if (!try isZigInstalled(allocator, version)) {
        std.debug.print("❌ Zig {s} is not installed\n", .{version});
        std.debug.print("💡 Run 'zion zig install {s}' first\n", .{version});
        return error.VersionNotInstalled;
    }

    // Create symlink to make this version active
    try setActiveZig(allocator, version);
    
    std.debug.print("✅ Now using Zig {s}\n", .{version});
    
    // Verify the switch worked
    const current = try getCurrentZig(allocator);
    defer if (current) |c| allocator.free(c);
    
    if (current) |c| {
        if (std.mem.eql(u8, c, version)) {
            std.debug.print("🚀 Active: zig {s}\n", .{version});
        }
    }
}

/// Show current active Zig version
fn currentZig(allocator: Allocator) !void {
    const current = try getCurrentZig(allocator);
    defer if (current) |c| allocator.free(c);

    if (current) |version| {
        std.debug.print("Current Zig version: {s}\n", .{version});
    } else {
        std.debug.print("No Zig version is currently active\n", .{});
        std.debug.print("💡 Run 'zion zig list' to see installed versions\n", .{});
        std.debug.print("💡 Run 'zion zig use <version>' to activate a version\n", .{});
    }
}

/// Remove an installed Zig version
fn removeZig(allocator: Allocator, version: []const u8) !void {
    std.debug.print("🗑️  Removing Zig {s}...\n", .{version});

    // Check if version is installed
    if (!try isZigInstalled(allocator, version)) {
        std.debug.print("❌ Zig {s} is not installed\n", .{version});
        return error.VersionNotInstalled;
    }

    // Check if this is the current version
    const current = try getCurrentZig(allocator);
    defer if (current) |c| allocator.free(c);
    
    if (current) |c| {
        if (std.mem.eql(u8, c, version)) {
            std.debug.print("⚠️  Cannot remove currently active version {s}\n", .{version});
            std.debug.print("💡 Switch to another version first with 'zion zig use <version>'\n", .{});
            return error.CannotRemoveActiveVersion;
        }
    }

    // Remove the version directory
    const home_dir = try getHomeDir(allocator);
    defer allocator.free(home_dir);

    const version_dir = try std.fmt.allocPrint(allocator, "{s}/.zion/zig/{s}", .{ home_dir, version });
    defer allocator.free(version_dir);

    const cwd = fs.cwd();
    try cwd.deleteTree(version_dir);
    
    std.debug.print("✅ Successfully removed Zig {s}\n", .{version});
}

/// Show available Zig versions for download
fn availableZigVersions(allocator: Allocator) !void {
    std.debug.print("🌐 Fetching available Zig versions...\n", .{});
    
    // This would normally fetch from the Zig releases API
    // For now, show some common versions
    const common_versions = [_][]const u8{
        "0.15.0-dev",
        "0.14.0", 
        "0.13.0",
        "0.12.0",
        "0.11.0",
        "master",
    };

    std.debug.print("📋 Available Zig versions:\n", .{});
    for (common_versions) |version| {
        const installed = try isZigInstalled(allocator, version);
        const marker = if (installed) " (installed)" else "";
        std.debug.print("  • {s}{s}\n", .{ version, marker });
    }
    
    std.debug.print("\n💡 Install with: zion zig install <version>\n", .{});
}

/// Helper functions

/// Ensure Zion directories exist
fn ensureZionDirs(allocator: Allocator) !void {
    const home_dir = try getHomeDir(allocator);
    defer allocator.free(home_dir);

    const zion_dir = try std.fmt.allocPrint(allocator, "{s}/.zion", .{home_dir});
    defer allocator.free(zion_dir);

    const zig_dir = try std.fmt.allocPrint(allocator, "{s}/.zion/zig", .{home_dir});
    defer allocator.free(zig_dir);

    const bin_dir = try std.fmt.allocPrint(allocator, "{s}/.zion/bin", .{home_dir});
    defer allocator.free(bin_dir);

    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zion/cache", .{home_dir});
    defer allocator.free(cache_dir);

    const cwd = fs.cwd();
    
    // Create directories
    cwd.makePath(zion_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    
    cwd.makePath(zig_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    
    cwd.makePath(bin_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    
    cwd.makePath(cache_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

/// Get user's home directory
fn getHomeDir(allocator: Allocator) ![]const u8 {
    const home = std.os.getenv("HOME") orelse {
        return error.HomeNotFound;
    };
    return try allocator.dupe(u8, home);
}

/// Check if a Zig version is installed
fn isZigInstalled(allocator: Allocator, version: []const u8) !bool {
    const home_dir = try getHomeDir(allocator);
    defer allocator.free(home_dir);

    const version_dir = try std.fmt.allocPrint(allocator, "{s}/.zion/zig/{s}", .{ home_dir, version });
    defer allocator.free(version_dir);

    const cwd = fs.cwd();
    cwd.access(version_dir, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        }
        return err;
    };

    return true;
}

/// Get the download URL for a Zig version
fn getZigDownloadUrl(allocator: Allocator, version: []const u8) ![]const u8 {
    // Detect platform  
    const os_tag = @tagName(builtin.target.os.tag);
    const arch_tag = @tagName(builtin.target.cpu.arch);
    
    const platform = if (std.mem.eql(u8, os_tag, "linux"))
        if (std.mem.eql(u8, arch_tag, "x86_64")) "x86_64-linux" else "aarch64-linux"
    else if (std.mem.eql(u8, os_tag, "macos"))
        if (std.mem.eql(u8, arch_tag, "x86_64")) "x86_64-macos" else "aarch64-macos"
    else if (std.mem.eql(u8, os_tag, "windows"))
        if (std.mem.eql(u8, arch_tag, "x86_64")) "x86_64-windows" else "aarch64-windows"
    else
        "x86_64-linux"; // fallback

    // Handle special versions
    if (std.mem.eql(u8, version, "master")) {
        return try std.fmt.allocPrint(allocator, "https://ziglang.org/builds/zig-{s}.tar.xz", .{platform});
    }
    
    // For release versions
    return try std.fmt.allocPrint(allocator, "https://ziglang.org/download/{s}/zig-{s}-{s}.tar.xz", .{ version, platform, version });
}

/// Download Zig archive
fn downloadZigArchive(allocator: Allocator, version: []const u8, url: []const u8) ![]const u8 {
    const home_dir = try getHomeDir(allocator);
    defer allocator.free(home_dir);

    const archive_name = try std.fmt.allocPrint(allocator, "zig-{s}.tar.xz", .{version});
    defer allocator.free(archive_name);

    const archive_path = try std.fmt.allocPrint(allocator, "{s}/.zion/cache/{s}", .{ home_dir, archive_name });
    
    std.debug.print("📥 Downloading from {s}...\n", .{url});
    
    // Use curl to download
    const argv = [_][]const u8{
        "curl",
        "-L", // Follow redirects
        "-o", archive_path,
        url,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(archive_path);
                return error.DownloadFailed;
            }
        },
        else => {
            allocator.free(archive_path);
            return error.DownloadFailed;
        },
    }

    return archive_path;
}

/// Extract Zig archive
fn extractZigArchive(allocator: Allocator, version: []const u8, archive_path: []const u8) !void {
    const home_dir = try getHomeDir(allocator);
    defer allocator.free(home_dir);

    const extract_dir = try std.fmt.allocPrint(allocator, "{s}/.zion/zig/{s}", .{ home_dir, version });
    defer allocator.free(extract_dir);

    const cwd = fs.cwd();
    
    // Create extraction directory
    try cwd.makePath(extract_dir);

    std.debug.print("📦 Extracting Zig archive...\n", .{});
    
    // Use tar to extract
    const argv = [_][]const u8{
        "tar",
        "-xJf", // Extract, XZ format
        archive_path,
        "-C", extract_dir,
        "--strip-components=1", // Remove top-level directory
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                return error.ExtractionFailed;
            }
        },
        else => {
            return error.ExtractionFailed;
        },
    }

    // Clean up archive
    try cwd.deleteFile(archive_path);
}

/// Set active Zig version by creating symlink
fn setActiveZig(allocator: Allocator, version: []const u8) !void {
    const home_dir = try getHomeDir(allocator);
    defer allocator.free(home_dir);

    const version_zig = try std.fmt.allocPrint(allocator, "{s}/.zion/zig/{s}/zig", .{ home_dir, version });
    defer allocator.free(version_zig);

    const active_zig = try std.fmt.allocPrint(allocator, "{s}/.zion/bin/zig", .{home_dir});
    defer allocator.free(active_zig);

    const cwd = fs.cwd();
    
    // Remove existing symlink
    cwd.deleteFile(active_zig) catch |err| {
        if (err != error.FileNotFound) return err;
    };

    // Create new symlink
    try cwd.symLink(version_zig, active_zig, .{});
}

/// Get current active Zig version
fn getCurrentZig(allocator: Allocator) !?[]const u8 {
    const home_dir = try getHomeDir(allocator);
    defer allocator.free(home_dir);

    const active_zig = try std.fmt.allocPrint(allocator, "{s}/.zion/bin/zig", .{home_dir});
    defer allocator.free(active_zig);

    const cwd = fs.cwd();
    
    // Read symlink target
    var buffer: [fs.max_path_bytes]u8 = undefined;
    const target = cwd.readLink(active_zig, &buffer) catch |err| {
        if (err == error.FileNotFound or err == error.NotLink) {
            return null;
        }
        return err;
    };

    // Extract version from path like "/home/user/.zion/zig/0.15.0/zig"
    const zig_dir_prefix = try std.fmt.allocPrint(allocator, "{s}/.zion/zig/", .{home_dir});
    defer allocator.free(zig_dir_prefix);

    if (std.mem.indexOf(u8, target, zig_dir_prefix)) |start| {
        const version_start = start + zig_dir_prefix.len;
        if (std.mem.indexOf(u8, target[version_start..], "/")) |end| {
            return try allocator.dupe(u8, target[version_start..version_start + end]);
        }
    }

    return null;
}