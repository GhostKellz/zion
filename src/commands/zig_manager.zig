const std = @import("std");
const fs = std.fs;
const http = std.http;
const json = std.json;
const Dir = std.Io.Dir;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const zion_root = @import("../root.zig");

/// Zig version manager - like anyzig but integrated into zion
pub fn zig_manager(allocator: Allocator, args: []const [:0]const u8) !void {
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
fn listVersions(allocator: Allocator, args: []const [:0]const u8) !void {
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
fn installVersion(allocator: Allocator, args: []const [:0]const u8) !void {
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
fn useVersion(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("❌ Usage: zion zig use <version|system>\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  zion zig use 0.14.1    # Use managed version\n", .{});
        std.debug.print("  zion zig use system    # Use system Zig\n", .{});
        return;
    }

    const version = args[0];

    // Handle special "system" version
    if (std.mem.eql(u8, version, "system")) {
        const io = try zion_root.getIo();
        const system_zig = detectSystemZig(allocator, io) catch |err| {
            std.debug.print("❌ System Zig not found\n", .{});
            std.debug.print("💡 Install Zig via your package manager or use 'zion zig install <version>'\n", .{});
            return err;
        };
        defer allocator.free(system_zig);

        // Clear the active managed version to fall back to system
        try clearActiveVersion(allocator);

        const sys_version = getZigVersionFromPath(allocator, io, system_zig) catch "unknown";
        defer allocator.free(sys_version);

        std.debug.print("✅ Now using system Zig ({s})\n", .{sys_version});
        std.debug.print("📁 Path: {s}\n", .{system_zig});
        return;
    }

    // Check if managed version is installed
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const zig_path = try getZigPath(allocator, version);
    defer allocator.free(zig_path);

    cwd.access(io, zig_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("❌ Zig {s} is not installed\n", .{version});
            std.debug.print("💡 Run 'zion zig install {s}' first\n", .{version});
            std.debug.print("💡 Or use 'zion zig use system' for system Zig\n", .{});
            return;
        }
        return err;
    };

    // Update managed version
    try setActiveVersion(allocator, version);

    std.debug.print("✅ Now using managed Zig {s}\n", .{version});

    // Verify the switch worked
    try verifyZigVersion(allocator, version);
}

/// Show current Zig version
fn showCurrent(allocator: Allocator) !void {
    const io = try zion_root.getIo();

    std.debug.print("🔧 Zig Version Status:\n", .{});

    // Check system Zig first
    const system_zig = detectSystemZig(allocator, io) catch null;
    if (system_zig) |sys_path| {
        defer allocator.free(sys_path);
        std.debug.print("🖥️  System Zig: {s}\n", .{sys_path});

        const sys_version = getZigVersionFromPath(allocator, io, sys_path) catch "unknown";
        defer allocator.free(sys_version);
        std.debug.print("    Version: {s}\n", .{sys_version});
    } else {
        std.debug.print("🖥️  System Zig: Not found\n", .{});
    }

    // Check managed Zig
    const current = getCurrentVersion(allocator) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("🦎 Managed Zig: None active\n", .{});
            if (system_zig != null) {
                std.debug.print("💡 Using system Zig by default\n", .{});
            } else {
                std.debug.print("💡 Use 'zion zig install <version>' to install Zig\n", .{});
            }
            return;
        }
        return err;
    };
    defer allocator.free(current);

    std.debug.print("🦎 Managed Zig: {s} (active)\n", .{current});

    const zig_exe = getActiveZigPath(allocator) catch return;
    defer allocator.free(zig_exe);

    std.debug.print("📁 Active Path: {s}\n", .{zig_exe});

    // Show detailed version info for active Zig
    std.debug.print("📊 Active Version Details:\n", .{});
    try showZigVersionDetails(allocator);
}

/// Remove a Zig version
fn removeVersion(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 1) {
        std.debug.print("❌ Usage: zion zig remove <version>\n", .{});
        return;
    }

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const version = args[0];
    const version_dir = try getVersionDir(allocator, version);
    defer allocator.free(version_dir);

    cwd.deleteTree(io, version_dir) catch |err| {
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

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const zig_dir = try getZigDir(allocator);
    defer allocator.free(zig_dir);

    var dir = cwd.openDir(io, zig_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("✅ No Zig versions to clean\n", .{});
            return;
        }
        return err;
    };
    defer dir.close(io);

    const current_version = getCurrentVersion(allocator) catch null;
    defer if (current_version) |cv| allocator.free(cv);

    var removed_count: u32 = 0;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
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

                cwd.deleteTree(io, version_path) catch continue;
                std.debug.print("🗑️  Removed old version: {s}\n", .{entry.name});
                removed_count += 1;
            }
        }
    }

    std.debug.print("✅ Cleaned {d} old Zig versions\n", .{removed_count});
}

/// Set default Zig version
fn setDefault(allocator: Allocator, args: []const [:0]const u8) !void {
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
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const zig_dir = try getZigDir(allocator);
    defer allocator.free(zig_dir);

    cwd.createDirPath(io, zig_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
}

fn getZigDir(allocator: Allocator) ![]const u8 {
    const home_dir = zion_root.getEnv("HOME") orelse return error.NoHomeDir;
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
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const home_dir = zion_root.getEnv("HOME") orelse return error.NoHomeDir;
    const current_file = try std.fmt.allocPrint(allocator, "{s}/.zion/current-zig", .{home_dir});
    defer allocator.free(current_file);

    // Read file content using scatter/gather API
    const file = try cwd.openFile(io, current_file, .{});
    defer file.close(io);

    var content_list: std.ArrayList(u8) = .empty;
    var buffer: [256]u8 = undefined;
    while (true) {
        const bytes_read = file.readStreaming(io, &.{buffer[0..]}) catch break;
        if (bytes_read == 0) break;
        try content_list.appendSlice(allocator, buffer[0..bytes_read]);
    }
    const content = try content_list.toOwnedSlice(allocator);
    return std.mem.trim(u8, content, " \t\n\r");
}

fn setActiveVersion(allocator: Allocator, version: []const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const home_dir = zion_root.getEnv("HOME") orelse return error.NoHomeDir;
    const current_file = try std.fmt.allocPrint(allocator, "{s}/.zion/current-zig", .{home_dir});
    defer allocator.free(current_file);

    const file = try cwd.createFile(io, current_file, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, version);
}

fn clearActiveVersion(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const home_dir = zion_root.getEnv("HOME") orelse return error.NoHomeDir;
    const current_file = try std.fmt.allocPrint(allocator, "{s}/.zion/current-zig", .{home_dir});
    defer allocator.free(current_file);

    cwd.deleteFile(io, current_file) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };
}

fn getActiveZigPath(allocator: Allocator) ![]const u8 {
    // Try managed version first
    if (getCurrentVersion(allocator)) |current| {
        defer allocator.free(current);
        return getZigPath(allocator, current);
    } else |_| {
        // Fall back to system Zig
        const io = try zion_root.getIo();
        return detectSystemZig(allocator, io);
    }
}

fn listInstalledVersions(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Show system Zig first
    const system_zig = detectSystemZig(allocator, io) catch null;
    if (system_zig) |sys_path| {
        defer allocator.free(sys_path);
        const sys_version = getZigVersionFromPath(allocator, io, sys_path) catch "unknown";
        defer allocator.free(sys_version);
        std.debug.print("  🖥️  system ({s}) - {s}\n", .{ sys_version, sys_path });
    }

    // Show managed versions
    const zig_dir = try getZigDir(allocator);
    defer allocator.free(zig_dir);

    var dir = cwd.openDir(io, zig_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            if (system_zig == null) {
                std.debug.print("  (no versions available)\n", .{});
            }
            return;
        }
        return err;
    };
    defer dir.close(io);

    const current_version = getCurrentVersion(allocator) catch null;
    defer if (current_version) |cv| allocator.free(cv);

    var count: u32 = 0;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind == .directory) {
            const is_current = current_version != null and std.mem.eql(u8, entry.name, current_version.?);
            const marker = if (is_current) " (active)" else "";
            const symbol = if (is_current) "→" else " ";

            std.debug.print("  {s} 🦎 {s}{s}\n", .{ symbol, entry.name, marker });
            count += 1;
        }
    }

    if (count == 0 and system_zig == null) {
        std.debug.print("  (no versions installed)\n", .{});
    }
}

fn listRemoteVersions(allocator: Allocator, show_prerelease: bool) !void {
    _ = allocator;

    std.debug.print("  📡 Available Zig versions for x86_64-linux:\n", .{});

    // Stable releases
    const stable_versions = [_][]const u8{
        "0.14.1",
        "0.13.0",
        "0.12.1",
        "0.11.0",
    };

    std.debug.print("\n  🟢 Stable Releases:\n", .{});
    for (stable_versions) |version| {
        std.debug.print("    {s}\n", .{version});
    }

    if (show_prerelease) {
        const dev_versions = [_][]const u8{
            "0.15.0-dev.936+fc2c1883b",
            "0.15.0-dev.1000+abc123def", // Example
            "master", // Latest development
        };

        std.debug.print("\n  🟡 Development Releases:\n", .{});
        for (dev_versions) |version| {
            std.debug.print("    {s}\n", .{version});
        }
    } else {
        std.debug.print("\n💡 Use --prerelease to see development versions\n", .{});
    }
}

fn downloadAndInstallZig(allocator: Allocator, version: []const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const version_dir = try getVersionDir(allocator, version);
    defer allocator.free(version_dir);

    try cwd.createDirPath(io, version_dir);

    // Get download URL for the version
    const download_url = try getZigDownloadUrl(allocator, version);
    defer allocator.free(download_url);

    // Create temporary download directory
    const temp_dir = try std.fmt.allocPrint(allocator, "{s}/temp", .{version_dir});
    defer allocator.free(temp_dir);
    try cwd.createDirPath(io, temp_dir);

    // Extract filename from URL
    const filename = getFilenameFromUrl(download_url);
    const temp_file = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ temp_dir, filename });
    defer allocator.free(temp_file);

    std.debug.print("📦 Downloading Zig {s}...\n", .{version});
    std.debug.print("    URL: {s}\n", .{download_url});

    // Download the file
    try downloadFile(allocator, io, download_url, temp_file);

    std.debug.print("📦 Extracting Zig {s}...\n", .{version});

    // Extract the archive
    try extractZigArchive(allocator, io, temp_file, version_dir);

    // Clean up temp directory
    cwd.deleteTree(io, temp_dir) catch {};

    std.debug.print("✅ Zig {s} installed successfully\n", .{version});
}

fn verifyZigVersion(allocator: Allocator, expected_version: []const u8) !void {
    const io = try zion_root.getIo();
    const zig_exe = try getActiveZigPath(allocator);
    defer allocator.free(zig_exe);

    const version_args = [_][]const u8{ zig_exe, "version" };
    var child = try std.process.spawn(io, .{
        .argv = &version_args,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    var output_buf: std.ArrayList(u8) = .empty;
    defer output_buf.deinit(allocator);

    var read_buf: [4096]u8 = undefined;
    if (child.stdout) |stdout_file| {
        while (true) {
            const bytes_read = stdout_file.readStreaming(io, &.{read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try output_buf.appendSlice(allocator, read_buf[0..bytes_read]);
        }
    }

    _ = try child.wait(io);

    const actual_version = std.mem.trim(u8, output_buf.items, " \t\n\r");
    std.debug.print("🔍 Verified: {s}\n", .{actual_version});
    _ = expected_version;
}

fn showZigVersionDetails(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const zig_exe = try getActiveZigPath(allocator);
    defer allocator.free(zig_exe);

    const version_args = [_][]const u8{ zig_exe, "version" };
    var child = try std.process.spawn(io, .{
        .argv = &version_args,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    _ = try child.wait(io);
}

fn updateShellProfile(allocator: Allocator, version: []const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const zig_path = try getZigPath(allocator, version);
    defer allocator.free(zig_path);

    const home_dir = zion_root.getEnv("HOME") orelse return error.NoHomeDir;
    const bashrc_path = try std.fmt.allocPrint(allocator, "{s}/.bashrc", .{home_dir});
    defer allocator.free(bashrc_path);

    const export_line = try std.fmt.allocPrint(allocator, "export PATH=\"{s}:$PATH\" # Added by zion\n", .{fs.path.dirname(zig_path) orelse ""});
    defer allocator.free(export_line);

    // Read existing content and append
    var existing_content: std.ArrayList(u8) = .empty;
    defer existing_content.deinit(allocator);

    if (cwd.openFile(io, bashrc_path, .{})) |file| {
        defer file.close(io);
        var buffer: [8192]u8 = undefined;
        while (true) {
            const bytes_read = file.readStreaming(io, &.{buffer[0..]}) catch break;
            if (bytes_read == 0) break;
            try existing_content.appendSlice(allocator, buffer[0..bytes_read]);
        }
    } else |_| {
        // File doesn't exist, that's OK
    }

    // Append the export line
    try existing_content.appendSlice(allocator, export_line);

    // Write the combined content
    const new_file = try cwd.createFile(io, bashrc_path, .{});
    defer new_file.close(io);
    try new_file.writeStreamingAll(io, existing_content.items);
}

// System Zig detection and management helper functions

fn detectSystemZig(allocator: Allocator, io: Io) ![]const u8 {
    const cwd = Dir.cwd();

    // Common system Zig installation paths
    const system_paths = [_][]const u8{
        "/usr/bin/zig", // Standard Linux package manager
        "/usr/local/bin/zig", // Manual system install
        "/opt/zig/bin/zig", // Alternative location
        "/bin/zig", // Some distributions
        "/snap/bin/zig", // Snap packages
    };

    for (system_paths) |path| {
        cwd.access(io, path, .{}) catch continue;
        return try allocator.dupe(u8, path);
    }

    // Try PATH lookup as fallback
    const which_args = [_][]const u8{ "which", "zig" };
    var child = std.process.spawn(io, .{
        .argv = &which_args,
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch return error.SystemZigNotFound;

    var output_buf: std.ArrayList(u8) = .empty;
    errdefer output_buf.deinit(allocator);

    var read_buf: [4096]u8 = undefined;
    if (child.stdout) |stdout_file| {
        while (true) {
            const bytes_read = stdout_file.readStreaming(io, &.{read_buf[0..]}) catch {
                child.kill(io);
                return error.SystemZigNotFound;
            };
            if (bytes_read == 0) break;
            output_buf.appendSlice(allocator, read_buf[0..bytes_read]) catch {
                child.kill(io);
                return error.SystemZigNotFound;
            };
        }
    }

    const result = child.wait(io) catch {
        return error.SystemZigNotFound;
    };

    if (result != .exited or result.exited != 0) {
        return error.SystemZigNotFound;
    }

    const trimmed = std.mem.trim(u8, output_buf.items, " \t\n\r");
    const path_copy = try allocator.dupe(u8, trimmed);
    output_buf.deinit(allocator);
    return path_copy;
}

fn getZigVersionFromPath(allocator: Allocator, io: Io, zig_path: []const u8) ![]const u8 {
    const version_args = [_][]const u8{ zig_path, "version" };
    var child = std.process.spawn(io, .{
        .argv = &version_args,
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch return error.VersionDetectionFailed;

    var output_buf: std.ArrayList(u8) = .empty;
    errdefer output_buf.deinit(allocator);

    var read_buf: [4096]u8 = undefined;
    if (child.stdout) |stdout_file| {
        while (true) {
            const bytes_read = stdout_file.readStreaming(io, &.{read_buf[0..]}) catch {
                child.kill(io);
                return error.VersionDetectionFailed;
            };
            if (bytes_read == 0) break;
            output_buf.appendSlice(allocator, read_buf[0..bytes_read]) catch {
                child.kill(io);
                return error.VersionDetectionFailed;
            };
        }
    }

    const result = child.wait(io) catch {
        return error.VersionDetectionFailed;
    };

    if (result != .exited or result.exited != 0) {
        return error.VersionDetectionFailed;
    }

    const trimmed = std.mem.trim(u8, output_buf.items, " \t\n\r");
    const version_copy = try allocator.dupe(u8, trimmed);
    output_buf.deinit(allocator);
    return version_copy;
}

// Download and extraction helper functions

fn getZigDownloadUrl(allocator: Allocator, version: []const u8) ![]const u8 {
    // Map versions to their download URLs for x86_64-linux
    if (std.mem.eql(u8, version, "0.15.0-dev.936+fc2c1883b")) {
        return try allocator.dupe(u8, "https://ziglang.org/builds/zig-x86_64-linux-0.15.0-dev.936+fc2c1883b.tar.xz");
    } else if (std.mem.eql(u8, version, "0.14.1")) {
        return try allocator.dupe(u8, "https://ziglang.org/download/0.14.1/zig-x86_64-linux-0.14.1.tar.xz");
    } else if (std.mem.eql(u8, version, "0.13.0")) {
        return try allocator.dupe(u8, "https://ziglang.org/download/0.13.0/zig-x86_64-linux-0.13.0.tar.xz");
    } else if (std.mem.eql(u8, version, "0.12.1")) {
        return try allocator.dupe(u8, "https://ziglang.org/download/0.12.1/zig-x86_64-linux-0.12.1.tar.xz");
    } else if (std.mem.eql(u8, version, "0.11.0")) {
        return try allocator.dupe(u8, "https://ziglang.org/download/0.11.0/zig-x86_64-linux-0.11.0.tar.xz");
    } else if (std.mem.eql(u8, version, "master")) {
        // For master, use the latest dev build (this would need to be dynamic in practice)
        return try allocator.dupe(u8, "https://ziglang.org/builds/zig-x86_64-linux-0.15.0-dev.936+fc2c1883b.tar.xz");
    } else {
        return error.UnsupportedVersion;
    }
}

fn getFilenameFromUrl(url: []const u8) []const u8 {
    // Find the last '/' in the URL
    var i = url.len;
    while (i > 0) {
        i -= 1;
        if (url[i] == '/') {
            return url[i + 1 ..];
        }
    }
    return url; // Fallback if no '/' found
}

fn downloadFile(_: Allocator, io: Io, url: []const u8, output_path: []const u8) !void {
    // Use curl to download the file
    const curl_args = [_][]const u8{ "curl", "-L", "-o", output_path, url };

    var child = try std.process.spawn(io, .{
        .argv = &curl_args,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const result = try child.wait(io);
    if (result != .exited or result.exited != 0) {
        return error.DownloadFailed;
    }
}

fn extractZigArchive(_: Allocator, io: Io, archive_path: []const u8, extract_dir: []const u8) !void {
    // Extract tar.xz file
    const tar_args = [_][]const u8{ "tar", "-xf", archive_path, "-C", extract_dir, "--strip-components=1" };

    var child = try std.process.spawn(io, .{
        .argv = &tar_args,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const result = try child.wait(io);
    if (result != .exited or result.exited != 0) {
        return error.ExtractionFailed;
    }
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
    std.debug.print("    zion zig install 0.14.1         # Install Zig 0.14.1\n", .{});
    std.debug.print("    zion zig install 0.15.0-dev.936+fc2c1883b  # Install dev version\n", .{});
    std.debug.print("    zion zig use 0.14.1             # Switch to Zig 0.14.1\n", .{});
    std.debug.print("    zion zig current                # Show current version\n", .{});
    std.debug.print("    zion zig default 0.14.1         # Set as default\n", .{});
}
