const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Run the project executable
pub fn run(allocator: Allocator, args: [][:0]u8) !void {
    // Parse arguments
    var bin_name: ?[]const u8 = null;
    var run_args = std.ArrayList([]const u8).init(allocator);
    defer run_args.deinit();
    
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
            try run_args.append(arg);
        }
        i += 1;
    }
    
    // Add remaining args after --
    while (i < args.len) {
        try run_args.append(args[i]);
        i += 1;
    }
    
    // Determine the executable name
    const executable_name = bin_name orelse try getDefaultExecutableName(allocator);
    defer if (bin_name == null) allocator.free(executable_name);
    
    // Check if we need to build first
    const exe_path = try std.fmt.allocPrint(allocator, "zig-out/bin/{s}", .{executable_name});
    defer allocator.free(exe_path);
    
    const needs_build = blk: {
        fs.cwd().access(exe_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                break :blk true;
            }
            return err;
        };
        break :blk false;
    };
    
    if (needs_build) {
        std.debug.print("🔨 Building project...\n", .{});
        try buildProject(allocator);
    }
    
    // Run the executable
    std.debug.print("🚀 Running {s}...\n", .{executable_name});
    
    var cmd_args = std.ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();
    
    try cmd_args.append(exe_path);
    for (run_args.items) |arg| {
        try cmd_args.append(arg);
    }
    
    // Execute the binary
    var child = std.process.Child.init(cmd_args.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    
    const term = try child.spawnAndWait();
    
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("💥 Process exited with code {d}\n", .{code});
            }
        },
        .Signal => |signal| {
            std.debug.print("💥 Process terminated by signal {d}\n", .{signal});
        },
        else => {
            std.debug.print("💥 Process terminated abnormally\n", .{});
        },
    }
}

/// Get the default executable name from build.zig.zon
fn getDefaultExecutableName(allocator: Allocator) ![]const u8 {
    const cwd = fs.cwd();
    
    // Try to read build.zig.zon to get the project name
    const zon_content = cwd.readFileAlloc(allocator, "build.zig.zon", 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) {
            return allocator.dupe(u8, "main"); // Default fallback
        }
        return err;
    };
    defer allocator.free(zon_content);
    
    // Simple parsing to find .name = 
    if (std.mem.indexOf(u8, zon_content, ".name = .")) |start| {
        const name_start = start + 9; // ".name = .".len
        var name_end = name_start;
        
        while (name_end < zon_content.len) {
            const c = zon_content[name_end];
            if (!std.ascii.isAlphanumeric(c) and c != '_') break;
            name_end += 1;
        }
        
        if (name_end > name_start) {
            return allocator.dupe(u8, zon_content[name_start..name_end]);
        }
    }
    
    // Fallback: try quoted string format
    if (std.mem.indexOf(u8, zon_content, ".name = \"")) |start| {
        const name_start = start + 9; // ".name = \"".len
        if (std.mem.indexOfScalarPos(u8, zon_content, name_start, '"')) |name_end| {
            return allocator.dupe(u8, zon_content[name_start..name_end]);
        }
    }
    
    return allocator.dupe(u8, "main");
}

/// Build the project using zig build
fn buildProject(allocator: Allocator) !void {
    const argv = [_][]const u8{ "zig", "build" };
    
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    
    const term = try child.spawnAndWait();
    
    switch (term) {
        .Exited => |code| {
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