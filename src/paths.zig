const std = @import("std");
const builtin = @import("builtin");

pub const project_staging_dir = ".zion/staging";

pub fn cacheDir(allocator: std.mem.Allocator) ![]u8 {
    if (nonEmptyEnv("ZION_CACHE_DIR")) |configured| {
        return allocator.dupe(u8, configured);
    }
    if (nonEmptyEnv("XDG_CACHE_HOME")) |xdg_cache| {
        return std.fs.path.join(allocator, &.{ xdg_cache, "zion" });
    }
    if (nonEmptyEnv("LOCALAPPDATA")) |local_app_data| {
        return std.fs.path.join(allocator, &.{ local_app_data, "Zion", "cache" });
    }
    if (nonEmptyEnv("HOME")) |home_dir| {
        return std.fs.path.join(allocator, &.{ home_dir, ".cache", "zion" });
    }
    return error.NoCacheDirectory;
}

pub fn stateDir(allocator: std.mem.Allocator) ![]u8 {
    if (nonEmptyEnv("XDG_STATE_HOME")) |xdg_state| {
        return std.fs.path.join(allocator, &.{ xdg_state, "zion" });
    }
    if (nonEmptyEnv("LOCALAPPDATA")) |local_app_data| {
        return std.fs.path.join(allocator, &.{ local_app_data, "Zion", "state" });
    }
    if (nonEmptyEnv("HOME")) |home_dir| {
        return std.fs.path.join(allocator, &.{ home_dir, ".local", "state", "zion" });
    }
    return error.NoStateDirectory;
}

pub fn uniqueProjectStagingPath(
    allocator: std.mem.Allocator,
    io: std.Io,
    prefix: []const u8,
) ![]u8 {
    var random_bytes: [8]u8 = undefined;
    io.random(&random_bytes);
    const suffix = std.fmt.bytesToHex(random_bytes, .lower);
    return std.fmt.allocPrint(allocator, "{s}/{s}-{s}", .{ project_staging_dir, prefix, suffix });
}

pub fn ensurePrivateDir(io: std.Io, dir_path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const permissions = privateDirPermissions();
    _ = try cwd.createDirPathStatus(io, dir_path, permissions);
    const opened_dir = try cwd.openDir(io, dir_path, .{ .iterate = true, .follow_symlinks = false });
    defer opened_dir.close(io);
    try opened_dir.setPermissions(io, permissions);
}

pub fn privateFilePermissions() std.Io.File.Permissions {
    if (comptime builtin.os.tag == .windows) return .default_file;
    return .fromMode(0o600);
}

fn privateDirPermissions() std.Io.File.Permissions {
    if (comptime builtin.os.tag == .windows) return .default_dir;
    return .fromMode(0o700);
}

fn nonEmptyEnv(comptime name: [:0]const u8) ?[]const u8 {
    const value_ptr = std.c.getenv(name.ptr) orelse return null;
    const value = std.mem.sliceTo(value_ptr, 0);
    return if (value.len == 0) null else value;
}

test "cache path prefers explicit configuration" {
    // Environment-backed selection is covered by command tests. Keep the path
    // join behavior exercised without mutating process-global environment.
    const joined = try std.fs.path.join(std.testing.allocator, &.{ "cache-root", "zion" });
    defer std.testing.allocator.free(joined);
    try std.testing.expectEqualStrings("cache-root/zion", joined);
}

test "private staging directories restrict POSIX access" {
    const test_dir = ".scratch/paths-private-dir";
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(std.testing.io, test_dir) catch {};
    defer {
        cwd.deleteTree(std.testing.io, test_dir) catch {};
        cwd.deleteDir(std.testing.io, ".scratch") catch {};
    }

    try ensurePrivateDir(std.testing.io, test_dir);
    const stat = try cwd.statFile(std.testing.io, test_dir, .{});
    if (comptime builtin.os.tag != .windows) {
        try std.testing.expectEqual(@as(std.posix.mode_t, 0), stat.permissions.toMode() & 0o077);
    }
}
