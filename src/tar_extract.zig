const std = @import("std");
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Io = std.Io;
const zion_root = @import("root.zig");

/// Options for safe tarball extraction
pub const ExtractOptions = struct {
    /// Allow symlinks in the archive (default: false for security)
    allow_symlinks: bool = false,
    /// Number of path components to strip (like tar --strip-components)
    strip_components: u8 = 1,
    /// Allow overwriting existing files
    allow_overwrite: bool = true,
};

/// Errors that can occur during extraction
pub const ExtractError = error{
    PathTraversal,
    AbsolutePath,
    SymlinkNotAllowed,
    HardlinkNotAllowed,
    DeviceFileNotAllowed,
    InvalidEntryType,
    TarListFailed,
    TarExtractFailed,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    Unexpected,
};

/// Result of tarball validation
pub const ValidationResult = struct {
    valid: bool,
    error_message: ?[]const u8,
    rejected_entries: std.ArrayList([]const u8),

    pub fn deinit(self: *ValidationResult, allocator: Allocator) void {
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
        for (self.rejected_entries.items) |entry| {
            allocator.free(entry);
        }
        self.rejected_entries.deinit(allocator);
    }
};

/// Validate a single tar entry path for security issues
fn validateEntryPath(entry: []const u8, options: ExtractOptions) ?[]const u8 {
    _ = options;

    // Check for absolute paths
    if (entry.len > 0 and entry[0] == '/') {
        return "absolute path not allowed";
    }

    // Check for path traversal (../)
    var it = std.mem.splitSequence(u8, entry, "/");
    while (it.next()) |component| {
        if (std.mem.eql(u8, component, "..")) {
            return "path traversal (..) not allowed";
        }
        // Also check for hidden traversal attempts
        if (std.mem.startsWith(u8, component, "..")) {
            return "path traversal pattern not allowed";
        }
    }

    // Check for backslash-based traversal (Windows-style)
    if (std.mem.indexOf(u8, entry, "..\\")) |_| {
        return "backslash path traversal not allowed";
    }

    return null;
}

/// Parse tar -tvf output to detect entry types
/// Returns: 'f' for file, 'd' for directory, 'l' for symlink, 'h' for hardlink, '?' for unknown
fn parseEntryType(line: []const u8) u8 {
    if (line.len == 0) return '?';

    // tar -tvf format: "drwxr-xr-x owner/group size date time name"
    // First character indicates type:
    // d = directory, l = symlink, h = hardlink, - = regular file
    // c = character device, b = block device
    return switch (line[0]) {
        'd' => 'd',
        'l' => 'l',
        'h' => 'h',
        '-' => 'f',
        'c', 'b' => 'D', // Device files
        else => '?',
    };
}

test "unsafe archive paths and entry types are rejected" {
    try std.testing.expect(validateEntryPath("package/src/main.zig", .{}) == null);
    try std.testing.expect(validateEntryPath("../escape", .{}) != null);
    try std.testing.expect(validateEntryPath("package/../../escape", .{}) != null);
    try std.testing.expect(validateEntryPath("/absolute", .{}) != null);
    try std.testing.expect(validateEntryPath("package\\..\\escape", .{}) != null);
    try std.testing.expectEqual(@as(u8, 'l'), parseEntryType("lrwxrwxrwx owner/group 0 date time link"));
    try std.testing.expectEqual(@as(u8, 'h'), parseEntryType("hrw-r--r-- owner/group 0 date time hardlink"));
    try std.testing.expectEqual(@as(u8, 'D'), parseEntryType("crw------- owner/group 0 date time device"));
    try std.testing.expectEqual(@as(u8, '?'), parseEntryType("prw------- owner/group 0 date time fifo"));
}

/// List and validate tarball contents before extraction
pub fn validateTarball(allocator: Allocator, tarball_path: []const u8, options: ExtractOptions) !ValidationResult {
    const io = try zion_root.getIo();

    var result = ValidationResult{
        .valid = true,
        .error_message = null,
        .rejected_entries = .empty,
    };

    // Use tar -tvf to list contents with metadata (shows symlinks, types)
    const argv = [_][]const u8{
        "tar",
        "-tvzf",
        tarball_path,
    };

    var child = std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch |err| {
        result.valid = false;
        result.error_message = try std.fmt.allocPrint(allocator, "Failed to list tarball: {}", .{err});
        return result;
    };

    // Read stdout
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(allocator);

    if (child.stdout) |stdout_pipe| {
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = stdout_pipe.readStreaming(io, &.{read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stdout_buf.appendSlice(allocator, read_buf[0..bytes_read]);
        }
    }

    // Read stderr
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(allocator);

    if (child.stderr) |stderr_pipe| {
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = stderr_pipe.readStreaming(io, &.{read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stderr_buf.appendSlice(allocator, read_buf[0..bytes_read]);
        }
    }

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code != 0) {
                result.valid = false;
                result.error_message = try std.fmt.allocPrint(allocator, "tar list failed (exit {d}): {s}", .{ code, stderr_buf.items });
                return result;
            }
        },
        else => {
            result.valid = false;
            result.error_message = try allocator.dupe(u8, "tar list terminated abnormally");
            return result;
        },
    }

    // Parse and validate each entry
    var lines = std.mem.splitScalar(u8, stdout_buf.items, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Parse entry type from tar -tv output
        const entry_type = parseEntryType(line);

        if (entry_type == '?') {
            result.valid = false;
            try result.rejected_entries.append(allocator, try allocator.dupe(u8, line));
            if (result.error_message == null) {
                result.error_message = try allocator.dupe(u8, "unsupported archive entry type");
            }
            continue;
        }

        // Check for device files
        if (entry_type == 'D') {
            result.valid = false;
            try result.rejected_entries.append(allocator, try allocator.dupe(u8, line));
            if (result.error_message == null) {
                result.error_message = try allocator.dupe(u8, "device files not allowed in package");
            }
            continue;
        }

        // Check for hardlinks
        if (entry_type == 'h') {
            result.valid = false;
            try result.rejected_entries.append(allocator, try allocator.dupe(u8, line));
            if (result.error_message == null) {
                result.error_message = try allocator.dupe(u8, "hardlinks not allowed in package");
            }
            continue;
        }

        // Check for symlinks (unless explicitly allowed)
        if (entry_type == 'l' and !options.allow_symlinks) {
            result.valid = false;
            try result.rejected_entries.append(allocator, try allocator.dupe(u8, line));
            if (result.error_message == null) {
                result.error_message = try allocator.dupe(u8, "symlinks not allowed in package (use allow_symlinks option)");
            }
            continue;
        }

        // Extract the path from the line (last field after date/time)
        // Format: "-rw-r--r-- user/group 1234 2024-01-01 12:00 path/to/file"
        // We need to find the path portion - it's after the time field
        var fields = std.mem.tokenizeScalar(u8, line, ' ');
        var field_count: usize = 0;
        var entry_path: ?[]const u8 = null;

        while (fields.next()) |field| {
            field_count += 1;
            // Path typically starts at field 6 (after perms, user, size, date, time)
            if (field_count >= 6) {
                entry_path = field;
                break;
            }
        }

        if (entry_path) |path| {
            // Validate the path for traversal attacks
            if (validateEntryPath(path, options)) |err_msg| {
                result.valid = false;
                try result.rejected_entries.append(allocator, try std.fmt.allocPrint(allocator, "{s}: {s}", .{ path, err_msg }));
                if (result.error_message == null) {
                    result.error_message = try std.fmt.allocPrint(allocator, "security violation: {s}", .{err_msg});
                }
            }
        }
    }

    return result;
}

/// Safely extract a tarball with security validation
/// This is the main entry point - validates before extracting
pub fn extractSafely(allocator: Allocator, tarball_path: []const u8, dest_path: []const u8, options: ExtractOptions) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Step 1: Validate tarball contents
    var validation = try validateTarball(allocator, tarball_path, options);
    defer validation.deinit(allocator);

    if (!validation.valid) {
        std.debug.print("Security validation failed for {s}\n", .{tarball_path});
        if (validation.error_message) |msg| {
            std.debug.print("  Error: {s}\n", .{msg});
        }
        if (validation.rejected_entries.items.len > 0) {
            std.debug.print("  Rejected entries:\n", .{});
            for (validation.rejected_entries.items) |entry| {
                std.debug.print("    - {s}\n", .{entry});
            }
        }
        return ExtractError.PathTraversal;
    }

    // Step 2: Remove existing directory if it exists
    cwd.deleteTree(io, dest_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };

    // Step 3: Create destination directory
    try cwd.createDirPath(io, dest_path);

    // Step 4: Extract with security flags
    var argv_list: [10][]const u8 = undefined;
    var argv_len: usize = 0;

    argv_list[argv_len] = "tar";
    argv_len += 1;
    argv_list[argv_len] = "-xzf";
    argv_len += 1;
    argv_list[argv_len] = tarball_path;
    argv_len += 1;
    argv_list[argv_len] = "-C";
    argv_len += 1;
    argv_list[argv_len] = dest_path;
    argv_len += 1;

    // Add strip-components if needed
    var strip_buf: [32]u8 = undefined;
    if (options.strip_components > 0) {
        const strip_arg = std.fmt.bufPrint(&strip_buf, "--strip-components={d}", .{options.strip_components}) catch "--strip-components=1";
        argv_list[argv_len] = strip_arg;
        argv_len += 1;
    }

    // Security: Don't preserve ownership (prevents setuid attacks when running as root)
    argv_list[argv_len] = "--no-same-owner";
    argv_len += 1;

    // Security: Don't preserve permissions (prevents setuid/setgid bits)
    argv_list[argv_len] = "--no-same-permissions";
    argv_len += 1;

    var child = try std.process.spawn(io, .{
        .argv = argv_list[0..argv_len],
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // Read stderr for error messages
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(allocator);

    if (child.stderr) |stderr_pipe| {
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = stderr_pipe.readStreaming(io, &.{read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stderr_buf.appendSlice(allocator, read_buf[0..bytes_read]);
        }
    }

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("tar extraction failed (exit code {d}): {s}\n", .{ code, stderr_buf.items });
                return ExtractError.TarExtractFailed;
            }
        },
        else => {
            std.debug.print("tar extraction terminated abnormally: {s}\n", .{stderr_buf.items});
            return ExtractError.TarExtractFailed;
        },
    }
}

/// Convenience function for typical package extraction
/// Uses secure defaults: strip 1 component, no symlinks, no special permissions
pub fn extractPackage(allocator: Allocator, tarball_path: []const u8, dest_path: []const u8) !void {
    return extractSafely(allocator, tarball_path, dest_path, .{
        .allow_symlinks = false,
        .strip_components = 1,
        .allow_overwrite = true,
    });
}
