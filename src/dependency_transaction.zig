const std = @import("std");
const paths = @import("paths.zig");
const AtomicFile = @import("atomic_file.zig").AtomicFile;

const Snapshot = struct {
    path: []const u8,
    content: ?[]u8,
};

/// Coordinates manifest, lockfile, and installed-directory changes. Callers
/// stage and verify an archive first, write both metadata files atomically,
/// install the staged directory, and then commit. Any error restores the
/// pre-operation snapshots and installed directory.
pub const DependencyTransaction = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    stage_root: []u8,
    staged_path: []u8,
    final_path: []u8,
    previous_path: []u8,
    manifest: Snapshot,
    lockfile: Snapshot,
    installed: bool = false,
    removed: bool = false,
    had_previous_dir: bool = false,
    finished: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, package_name: []const u8, dev_only: bool) !DependencyTransaction {
        try validatePackageName(package_name);
        try recoverPending(allocator, io);
        try paths.ensurePrivateDir(io, paths.project_staging_dir);
        const stage_root = try paths.uniqueProjectStagingPath(allocator, io, "dependency");
        errdefer allocator.free(stage_root);
        try paths.ensurePrivateDir(io, stage_root);
        errdefer std.Io.Dir.cwd().deleteTree(io, stage_root) catch {};
        const staged_path = try std.fs.path.join(allocator, &.{ stage_root, "next" });
        errdefer allocator.free(staged_path);
        const previous_path = try std.fs.path.join(allocator, &.{ stage_root, "previous" });
        errdefer allocator.free(previous_path);
        const parent = if (dev_only) ".zion/dev-deps" else ".zion/deps";
        const final_path = try std.fs.path.join(allocator, &.{ parent, package_name });
        errdefer allocator.free(final_path);

        const manifest_content = try readOptional(allocator, io, "build.zig.zon");
        errdefer if (manifest_content) |content| allocator.free(content);
        const lockfile_content = try readOptional(allocator, io, "zion.lock");
        errdefer if (lockfile_content) |content| allocator.free(content);

        try writeJournal(io, stage_root, package_name, dev_only, final_path, manifest_content, lockfile_content);

        return .{
            .allocator = allocator,
            .io = io,
            .stage_root = stage_root,
            .staged_path = staged_path,
            .final_path = final_path,
            .previous_path = previous_path,
            .manifest = .{ .path = "build.zig.zon", .content = manifest_content },
            .lockfile = .{ .path = "zion.lock", .content = lockfile_content },
        };
    }

    pub fn installStaged(self: *DependencyTransaction) !void {
        const cwd = std.Io.Dir.cwd();
        try cwd.createDirPath(self.io, std.fs.path.dirname(self.final_path).?);
        cwd.access(self.io, self.final_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        if (cwd.access(self.io, self.final_path, .{})) |_| {
            try std.Io.Dir.rename(cwd, self.final_path, cwd, self.previous_path, self.io);
            self.had_previous_dir = true;
        } else |_| {}
        errdefer if (self.had_previous_dir) std.Io.Dir.rename(cwd, self.previous_path, cwd, self.final_path, self.io) catch {};
        try std.Io.Dir.rename(cwd, self.staged_path, cwd, self.final_path, self.io);
        self.installed = true;
    }

    pub fn commit(self: *DependencyTransaction) !void {
        if (!self.installed and !self.removed) return error.DependencyDirectoryUnchanged;
        const cwd = std.Io.Dir.cwd();
        const committed_path = try std.fs.path.join(self.allocator, &.{ self.stage_root, "committed" });
        defer self.allocator.free(committed_path);
        const marker = try cwd.createFile(self.io, committed_path, .{ .permissions = paths.privateFilePermissions() });
        try marker.sync(self.io);
        marker.close(self.io);
        self.finished = true;
        if (self.had_previous_dir) cwd.deleteTree(self.io, self.previous_path) catch {};
        cwd.deleteTree(self.io, self.stage_root) catch {};
        cleanupStagingParent(self.io);
    }

    pub fn removeInstalled(self: *DependencyTransaction) !void {
        const cwd = std.Io.Dir.cwd();
        if (cwd.access(self.io, self.final_path, .{})) |_| {
            try std.Io.Dir.rename(cwd, self.final_path, cwd, self.previous_path, self.io);
            self.had_previous_dir = true;
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
        self.removed = true;
    }

    pub fn rollback(self: *DependencyTransaction) !void {
        if (self.finished) return;
        const cwd = std.Io.Dir.cwd();
        if (self.installed) {
            cwd.deleteTree(self.io, self.final_path) catch |err| if (err != error.FileNotFound) return err;
        }
        if (self.had_previous_dir) {
            try std.Io.Dir.rename(cwd, self.previous_path, cwd, self.final_path, self.io);
        }
        try restoreSnapshot(self.allocator, self.io, self.manifest);
        try restoreSnapshot(self.allocator, self.io, self.lockfile);
        cwd.deleteTree(self.io, self.stage_root) catch |err| if (err != error.FileNotFound) return err;
        cleanupStagingParent(self.io);
        self.finished = true;
    }

    pub fn deinit(self: *DependencyTransaction) void {
        if (!self.finished) self.rollback() catch {};
        if (self.manifest.content) |content| self.allocator.free(content);
        if (self.lockfile.content) |content| self.allocator.free(content);
        self.allocator.free(self.stage_root);
        self.allocator.free(self.staged_path);
        self.allocator.free(self.final_path);
        self.allocator.free(self.previous_path);
    }
};

fn validatePackageName(name: []const u8) !void {
    if (name.len == 0 or name.len > 100) return error.InvalidPackageName;
    for (name) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_' and byte != '.') return error.InvalidPackageName;
    }
}

fn readOptional(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(10 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
}

fn restoreSnapshot(allocator: std.mem.Allocator, io: std.Io, snapshot: Snapshot) !void {
    const cwd = std.Io.Dir.cwd();
    if (snapshot.content) |content| {
        var replacement = try AtomicFile.init(allocator, io, snapshot.path);
        defer replacement.deinit();
        try replacement.file.writeStreamingAll(io, content);
        try replacement.commit();
    } else {
        cwd.deleteFile(io, snapshot.path) catch |err| if (err != error.FileNotFound) return err;
    }
}

fn cleanupStagingParent(io: std.Io) void {
    const cwd = std.Io.Dir.cwd();
    cwd.deleteDir(io, paths.project_staging_dir) catch {};
}

fn writeJournal(
    io: std.Io,
    stage_root: []const u8,
    package_name: []const u8,
    dev_only: bool,
    final_path: []const u8,
    manifest: ?[]const u8,
    lockfile: ?[]const u8,
) !void {
    const cwd = std.Io.Dir.cwd();
    var record_buffer: [256]u8 = undefined;
    const record = try std.fmt.bufPrint(&record_buffer, "{s}\n{s}\n{s}\n", .{ package_name, if (dev_only) "dev" else "normal", final_path });
    try writePrivate(io, cwd, stage_root, "record", record);
    try writeSnapshotJournal(io, cwd, stage_root, "manifest", manifest);
    try writeSnapshotJournal(io, cwd, stage_root, "lockfile", lockfile);
    if (cwd.access(io, final_path, .{})) |_| {
        try writePrivate(io, cwd, stage_root, "had-directory", "1");
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
}

fn writeSnapshotJournal(io: std.Io, cwd: std.Io.Dir, stage_root: []const u8, name: []const u8, content: ?[]const u8) !void {
    if (content) |bytes| {
        try writePrivate(io, cwd, stage_root, name, bytes);
    } else {
        var marker_name: [64]u8 = undefined;
        const absent_name = try std.fmt.bufPrint(&marker_name, "{s}.absent", .{name});
        try writePrivate(io, cwd, stage_root, absent_name, "1");
    }
}

fn writePrivate(io: std.Io, cwd: std.Io.Dir, stage_root: []const u8, name: []const u8, content: []const u8) !void {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ stage_root, name });
    const file = try cwd.createFile(io, path, .{ .permissions = paths.privateFilePermissions() });
    defer file.close(io);
    try file.writeStreamingAll(io, content);
    try file.sync(io);
}

pub fn recoverPending(allocator: std.mem.Allocator, io: std.Io) !void {
    const cwd = std.Io.Dir.cwd();
    var staging = cwd.openDir(io, paths.project_staging_dir, .{ .iterate = true, .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer staging.close(io);
    var iterator = staging.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .directory or !std.mem.startsWith(u8, entry.name, "dependency-")) continue;
        const stage_root = try std.fs.path.join(allocator, &.{ paths.project_staging_dir, entry.name });
        defer allocator.free(stage_root);
        try recoverOne(allocator, io, stage_root);
    }
    cleanupStagingParent(io);
}

fn recoverOne(allocator: std.mem.Allocator, io: std.Io, stage_root: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const committed_path = try std.fs.path.join(allocator, &.{ stage_root, "committed" });
    defer allocator.free(committed_path);
    if (cwd.access(io, committed_path, .{})) |_| {
        try cwd.deleteTree(io, stage_root);
        return;
    } else |_| {}

    const record_path = try std.fs.path.join(allocator, &.{ stage_root, "record" });
    defer allocator.free(record_path);
    const record = try cwd.readFileAlloc(io, record_path, allocator, .limited(1024));
    defer allocator.free(record);
    var lines = std.mem.splitScalar(u8, record, '\n');
    const package_name = lines.next() orelse return error.InvalidTransactionJournal;
    const dependency_kind = lines.next() orelse return error.InvalidTransactionJournal;
    const final_path = lines.next() orelse return error.InvalidTransactionJournal;
    try validatePackageName(package_name);
    const expected_parent = if (std.mem.eql(u8, dependency_kind, "dev")) ".zion/dev-deps" else if (std.mem.eql(u8, dependency_kind, "normal")) ".zion/deps" else return error.InvalidTransactionJournal;
    const expected_final = try std.fs.path.join(allocator, &.{ expected_parent, package_name });
    defer allocator.free(expected_final);
    if (!std.mem.eql(u8, expected_final, final_path)) return error.InvalidTransactionJournal;

    const previous_path = try std.fs.path.join(allocator, &.{ stage_root, "previous" });
    defer allocator.free(previous_path);
    const had_marker = try std.fs.path.join(allocator, &.{ stage_root, "had-directory" });
    defer allocator.free(had_marker);
    const had_directory = if (cwd.access(io, had_marker, .{})) |_| true else |_| false;
    if (cwd.access(io, previous_path, .{})) |_| {
        cwd.deleteTree(io, final_path) catch |err| if (err != error.FileNotFound) return err;
        try std.Io.Dir.rename(cwd, previous_path, cwd, final_path, io);
    } else |_| {
        if (!had_directory) cwd.deleteTree(io, final_path) catch |err| if (err != error.FileNotFound) return err;
    }

    try restoreJournalSnapshot(allocator, io, stage_root, "manifest", "build.zig.zon");
    try restoreJournalSnapshot(allocator, io, stage_root, "lockfile", "zion.lock");
    try cwd.deleteTree(io, stage_root);
}

fn restoreJournalSnapshot(allocator: std.mem.Allocator, io: std.Io, stage_root: []const u8, journal_name: []const u8, target: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const backup_path = try std.fs.path.join(allocator, &.{ stage_root, journal_name });
    defer allocator.free(backup_path);
    const absent_name = try std.fmt.allocPrint(allocator, "{s}.absent", .{journal_name});
    defer allocator.free(absent_name);
    const absent_path = try std.fs.path.join(allocator, &.{ stage_root, absent_name });
    defer allocator.free(absent_path);
    if (cwd.access(io, absent_path, .{})) |_| {
        cwd.deleteFile(io, target) catch |err| if (err != error.FileNotFound) return err;
        return;
    } else |_| {}
    const content = try cwd.readFileAlloc(io, backup_path, allocator, .limited(10 * 1024 * 1024));
    defer allocator.free(content);
    var replacement = try AtomicFile.init(allocator, io, target);
    defer replacement.deinit();
    try replacement.file.writeStreamingAll(io, content);
    try replacement.commit();
}
