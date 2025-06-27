const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Run project tests
pub fn test_command(allocator: Allocator, args: [][:0]u8) !void {
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
    var test_args = std.ArrayList([]const u8).init(allocator);
    defer test_args.deinit();
    
    try test_args.append("zig");
    try test_args.append("test");
    
    if (verbose) {
        try test_args.append("--verbose");
    }
    
    // Add filter if specified
    if (filter) |f| {
        try test_args.append("--test-filter");
        try test_args.append(f);
    }
    
    // Find test files or use src/main.zig as default
    const test_file = try findTestFile(allocator);
    defer allocator.free(test_file);
    try test_args.append(test_file);
    
    // Execute zig test
    var child = std.process.Child.init(test_args.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    
    const start_time = std.time.milliTimestamp();
    const term = try child.spawnAndWait();
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;
    
    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                std.debug.print("\n✅ Tests passed in {d}ms\n", .{duration});
            } else {
                std.debug.print("\n❌ Tests failed (exit code {d}) after {d}ms\n", .{ code, duration });
            }
        },
        .Signal => |signal| {
            std.debug.print("\n💥 Tests terminated by signal {d}\n", .{signal});
        },
        else => {
            std.debug.print("\n💥 Tests terminated abnormally\n", .{});
        },
    }
}

/// Find the appropriate test file to run
fn findTestFile(allocator: Allocator) ![]const u8 {
    const cwd = fs.cwd();
    
    // Check for common test file locations
    const test_candidates = [_][]const u8{
        "src/test.zig",
        "test/test.zig", 
        "tests/main.zig",
        "src/main.zig", // Fallback
    };
    
    for (test_candidates) |candidate| {
        cwd.access(candidate, .{}) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
        return allocator.dupe(u8, candidate);
    }
    
    // If none found, check if we have a src directory with any .zig files
    var src_dir = cwd.openDir("src", .{ .iterate = true }) catch {
        return allocator.dupe(u8, "src/main.zig");
    };
    defer src_dir.close();
    
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const path = try std.fmt.allocPrint(allocator, "src/{s}", .{entry.name});
            return path;
        }
    }
    
    return allocator.dupe(u8, "src/main.zig");
}