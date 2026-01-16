const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const zion_root = @import("../root.zig");

/// Run the project executable
pub fn run(allocator: Allocator, args: []const [:0]const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Parse arguments
    var bin_name: ?[]const u8 = null;
    var run_args: std.ArrayList([]const u8) = .empty;
    defer run_args.deinit(allocator);

    var i: usize = 2; // Skip "zion" and "run"
    var found_separator = false;

    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--")) {
            found_separator = true;
            i += 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "--bin=")) {
            bin_name = arg[6..]; // Skip "--bin="
        } else if (std.mem.eql(u8, arg, "--bin") and i + 1 < args.len) {
            i += 1;
            bin_name = args[i];
        } else if (!found_separator) {
            // If we haven't found --, this might be a run argument
            try run_args.append(allocator, arg);
        }
        i += 1;
    }

    // Add remaining args after --
    while (i < args.len) {
        try run_args.append(allocator, args[i]);
        i += 1;
    }

    // Determine the executable name
    const executable_name = bin_name orelse try getDefaultExecutableName(allocator, io, cwd);
    defer if (bin_name == null) allocator.free(executable_name);

    // Check if we need to build first
    const exe_path = try std.fmt.allocPrint(allocator, "zig-out/bin/{s}", .{executable_name});
    defer allocator.free(exe_path);

    const needs_build = blk: {
        cwd.access(io, exe_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                break :blk true;
            }
            return err;
        };
        break :blk false;
    };

    if (needs_build) {
        std.debug.print("🔨 Building project...\n", .{});
        try buildProject(io);
    }

    // Run the executable
    std.debug.print("🚀 Running {s}...\n", .{executable_name});

    var cmd_args: std.ArrayList([]const u8) = .empty;
    defer cmd_args.deinit(allocator);

    try cmd_args.append(allocator, exe_path);
    for (run_args.items) |arg| {
        try cmd_args.append(allocator, arg);
    }

    // Execute the binary
    var child = try std.process.spawn(io, .{
        .argv = cmd_args.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("💥 Process exited with code {d}\n", .{code});
            }
        },
        .signal => |sig| {
            std.debug.print("💥 Process terminated by signal {}\n", .{sig});
        },
        else => {
            std.debug.print("💥 Process terminated abnormally\n", .{});
        },
    }
}

/// Get the default executable name from build.zig.zon
fn getDefaultExecutableName(allocator: Allocator, io: Io, cwd: Dir) ![]const u8 {
    // Try to read build.zig.zon to get the project name
    const file = cwd.openFile(io, "build.zig.zon", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return allocator.dupe(u8, "main"); // Default fallback
        }
        return err;
    };
    defer file.close(io);

    var zon_content: std.ArrayList(u8) = .empty;
    defer zon_content.deinit(allocator);

    var buffer: [4096]u8 = undefined;
    while (true) {
        const bytes_read = file.readStreaming(io, &.{buffer[0..]}) catch break;
        if (bytes_read == 0) break;
        try zon_content.appendSlice(allocator, buffer[0..bytes_read]);
    }

    // Simple parsing to find .name =
    if (std.mem.indexOf(u8, zon_content.items, ".name = .")) |start| {
        const name_start = start + 9; // ".name = .".len
        var name_end = name_start;

        while (name_end < zon_content.items.len) {
            const c = zon_content.items[name_end];
            if (!std.ascii.isAlphanumeric(c) and c != '_') break;
            name_end += 1;
        }

        if (name_end > name_start) {
            return allocator.dupe(u8, zon_content.items[name_start..name_end]);
        }
    }

    // Fallback: try quoted string format
    if (std.mem.indexOf(u8, zon_content.items, ".name = \"")) |start| {
        const name_start = start + 9; // ".name = \"".len
        if (std.mem.indexOfScalarPos(u8, zon_content.items, name_start, '"')) |name_end| {
            return allocator.dupe(u8, zon_content.items[name_start..name_end]);
        }
    }

    return allocator.dupe(u8, "main");
}

/// Build the project using zig build
fn buildProject(io: Io) !void {
    const argv = [_][]const u8{ "zig", "build" };

    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("❌ Build failed with exit code {d}\n", .{code});
                return error.BuildFailed;
            }
        },
        else => {
            std.debug.print("❌ Build terminated abnormally\n", .{});
            return error.BuildFailed;
        },
    }
}
