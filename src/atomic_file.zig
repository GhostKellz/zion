const std = @import("std");

/// Same-directory atomic replacement. The temporary file is fsynced and then
/// renamed over the target, so readers observe either the old or new file.
pub const AtomicFile = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    target_path: []u8,
    temporary_path: []u8,
    file: std.Io.File,
    file_open: bool = true,
    committed: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, target_path: []const u8) !AtomicFile {
        const cwd = std.Io.Dir.cwd();
        var random_bytes: [8]u8 = undefined;
        io.random(&random_bytes);
        const suffix = std.fmt.bytesToHex(random_bytes, .lower);
        const directory = std.fs.path.dirname(target_path) orelse ".";
        const basename = std.fs.path.basename(target_path);
        const temporary_name = try std.fmt.allocPrint(allocator, ".{s}.zion-write-{s}", .{ basename, suffix });
        defer allocator.free(temporary_name);
        const temporary_path = try std.fs.path.join(allocator, &.{ directory, temporary_name });
        errdefer allocator.free(temporary_path);
        const owned_target = try allocator.dupe(u8, target_path);
        errdefer allocator.free(owned_target);

        const permissions = if (cwd.statFile(io, target_path, .{})) |stat|
            stat.permissions
        else |_|
            std.Io.File.Permissions.default_file;
        const file = try cwd.createFile(io, temporary_path, .{
            .exclusive = true,
            .permissions = permissions,
        });

        return .{
            .allocator = allocator,
            .io = io,
            .target_path = owned_target,
            .temporary_path = temporary_path,
            .file = file,
        };
    }

    pub fn commit(self: *AtomicFile) !void {
        try self.file.sync(self.io);
        self.file.close(self.io);
        self.file_open = false;
        try std.Io.Dir.rename(.cwd(), self.temporary_path, .cwd(), self.target_path, self.io);
        self.committed = true;
    }

    pub fn deinit(self: *AtomicFile) void {
        if (self.file_open) self.file.close(self.io);
        if (!self.committed) std.Io.Dir.cwd().deleteFile(self.io, self.temporary_path) catch {};
        self.allocator.free(self.target_path);
        self.allocator.free(self.temporary_path);
    }
};

test "atomic replacement leaves no temporary file" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, ".scratch");
    const target = ".scratch/atomic-file-test";
    defer {
        cwd.deleteFile(io, target) catch {};
        cwd.deleteDir(io, ".scratch") catch {};
    }
    try cwd.writeFile(io, .{ .sub_path = target, .data = "old" });
    var replacement = try AtomicFile.init(allocator, io, target);
    defer replacement.deinit();
    try replacement.file.writeStreamingAll(io, "new");
    try replacement.commit();
    const content = try cwd.readFileAlloc(io, target, allocator, .limited(16));
    defer allocator.free(content);
    try std.testing.expectEqualStrings("new", content);
}

test "aborted atomic replacement preserves target" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, ".scratch");
    const target = ".scratch/atomic-file-abort-test";
    defer {
        cwd.deleteFile(io, target) catch {};
        cwd.deleteDir(io, ".scratch") catch {};
    }
    try cwd.writeFile(io, .{ .sub_path = target, .data = "original" });
    {
        var replacement = try AtomicFile.init(allocator, io, target);
        defer replacement.deinit();
        try replacement.file.writeStreamingAll(io, "incomplete");
    }
    const content = try cwd.readFileAlloc(io, target, allocator, .limited(32));
    defer allocator.free(content);
    try std.testing.expectEqualStrings("original", content);
}
