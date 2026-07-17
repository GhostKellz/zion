const std = @import("std");
const zion = @import("zion");

fn write(io: std.Io, path: []const u8, content: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = content });
}

fn expectFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8, expected: []const u8) !void {
    const content = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4096));
    defer allocator.free(content);
    try std.testing.expectEqualStrings(expected, content);
}

fn stageDependency(transaction: *zion.dependency_transaction.DependencyTransaction) !void {
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(transaction.io, transaction.staged_path);
    const marker = try std.fs.path.join(transaction.allocator, &.{ transaction.staged_path, "package.txt" });
    defer transaction.allocator.free(marker);
    try write(transaction.io, marker, "verified payload");
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedSandboxPath;
    if (std.c.chdir(args[1]) != 0) return error.ChangeDirectoryFailed;

    const allocator = init.gpa;
    const io = init.io;
    const original_manifest = ".{ .name = .fixture, .version = \"0.0.0\" }\n";
    const original_lock = "{\"packages\":{}}\n";
    try write(io, "build.zig.zon", original_manifest);
    try write(io, "zion.lock", original_lock);

    {
        var transaction = try zion.dependency_transaction.DependencyTransaction.init(allocator, io, "fixture", false);
        defer transaction.deinit();
        try stageDependency(&transaction);
        try write(io, "build.zig.zon", "mutated manifest\n");
        try write(io, "zion.lock", "mutated lock\n");
        try transaction.installStaged();
        try transaction.rollback();
    }
    try expectFile(allocator, io, "build.zig.zon", original_manifest);
    try expectFile(allocator, io, "zion.lock", original_lock);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, ".zion/deps/fixture", .{}));

    {
        var interrupted = try zion.dependency_transaction.DependencyTransaction.init(allocator, io, "fixture", false);
        defer interrupted.deinit();
        try stageDependency(&interrupted);
        try write(io, "build.zig.zon", "interrupted manifest\n");
        try write(io, "zion.lock", "interrupted lock\n");
        try interrupted.installStaged();
        interrupted.finished = true;
    }
    try zion.dependency_transaction.recoverPending(allocator, io);
    try expectFile(allocator, io, "build.zig.zon", original_manifest);
    try expectFile(allocator, io, "zion.lock", original_lock);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, ".zion/deps/fixture", .{}));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, ".zion/staging", .{}));
}
