const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const zion_root = @import("../root.zig");

/// Run project tests
pub fn test_command(allocator: Allocator, args: []const [:0]const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    var filter: ?[]const u8 = null;
    var verbose = false;
    var i: usize = 2; // Skip "zion" and "test"

    // Parse arguments
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.startsWith(u8, arg, "--filter=")) {
            filter = arg[9..]; // Skip "--filter="
        } else if (std.mem.eql(u8, arg, "--filter") and i + 1 < args.len) {
            i += 1;
            filter = args[i];
        } else {
            // Assume it's a filter pattern
            filter = arg;
        }
        i += 1;
    }

    std.debug.print("🧪 Running tests", .{});
    if (filter) |f| {
        std.debug.print(" (filter: {s})", .{f});
    }
    std.debug.print("...\n", .{});

    // Build test command
    var test_args: std.ArrayList([]const u8) = .empty;
    defer test_args.deinit(allocator);

    try test_args.append(allocator, "zig");
    try test_args.append(allocator, "test");

    if (verbose) {
        try test_args.append(allocator, "--verbose");
    }

    // Add filter if specified
    if (filter) |f| {
        try test_args.append(allocator, "--test-filter");
        try test_args.append(allocator, f);
    }

    // Find test files or use src/main.zig as default
    const test_file = try findTestFile(allocator, io, cwd);
    defer allocator.free(test_file);
    try test_args.append(allocator, test_file);

    // Execute zig test
    var child = try std.process.spawn(io, .{
        .argv = test_args.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const start_time = zion_root.milliTimestamp();
    const term = try child.wait(io);
    const end_time = zion_root.milliTimestamp();
    const duration = end_time - start_time;

    switch (term) {
        .exited => |code| {
            if (code == 0) {
                std.debug.print("\n✅ Tests passed in {d}ms\n", .{duration});
            } else {
                std.debug.print("\n❌ Tests failed (exit code {d}) after {d}ms\n", .{ code, duration });
            }
        },
        .signal => |sig| {
            std.debug.print("\n💥 Tests terminated by signal {}\n", .{sig});
        },
        else => {
            std.debug.print("\n💥 Tests terminated abnormally\n", .{});
        },
    }
}

/// Find the appropriate test file to run
fn findTestFile(allocator: Allocator, io: Io, cwd: Dir) ![]const u8 {
    // Check for common test file locations
    const test_candidates = [_][]const u8{
        "src/test.zig",
        "test/test.zig",
        "tests/main.zig",
        "src/main.zig", // Fallback
    };

    for (test_candidates) |candidate| {
        cwd.access(io, candidate, .{}) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
        return allocator.dupe(u8, candidate);
    }

    // If none found, check if we have a src directory with any .zig files
    var src_dir = cwd.openDir(io, "src", .{ .iterate = true }) catch {
        return allocator.dupe(u8, "src/main.zig");
    };
    defer src_dir.close(io);

    var iterator = src_dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const path = try std.fmt.allocPrint(allocator, "src/{s}", .{entry.name});
            return path;
        }
    }

    return allocator.dupe(u8, "src/main.zig");
}
