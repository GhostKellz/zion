const std = @import("std");
const root = @import("../root.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;

/// Initialize a new Zig project
pub fn init(allocator: Allocator) !void {
    _ = allocator; // unused but required for API consistency

    // Get std.Io from application context for filesystem operations
    const io = try root.getIo();
    const cwd = Dir.cwd();

    std.debug.print("Initializing Zion project...\n", .{});

    // Create src directory
    cwd.createDir(io, "src", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    // Create src/main.zig
    const main_zig_content =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    std.debug.print("Hello, world!\n", .{});
        \\}
        \\
    ;

    if (cwd.createFile(io, "src/main.zig", .{})) |main_file| {
        defer main_file.close(io);
        try main_file.writeStreamingAll(io, main_zig_content);
        std.debug.print("Created src/main.zig\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("src/main.zig already exists, skipping...\n", .{});
        } else {
            return err;
        }
    }

    // Create build.zig
    const build_zig_content =
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\
        \\    // zion:deps - dependencies will be added below this line
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "my-project",
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\
        \\    b.installArtifact(exe);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    run_cmd.step.dependOn(b.getInstallStep());
        \\
        \\    if (b.args) |args| {
        \\        run_cmd.addArgs(args);
        \\    }
        \\
        \\    const run_step = b.step("run", "Run the app");
        \\    run_step.dependOn(&run_cmd.step);
        \\}
        \\
    ;

    if (cwd.createFile(io, "build.zig", .{})) |build_file| {
        defer build_file.close(io);
        try build_file.writeStreamingAll(io, build_zig_content);
        std.debug.print("Created build.zig\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("build.zig already exists, skipping...\n", .{});
        } else {
            return err;
        }
    }

    // Create build.zig.zon
    const zon_content =
        \\.{
        \\    .name = "my-project",
        \\    .version = "0.1.0",
        \\    .dependencies = .{
        \\    },
        \\}
        \\
    ;

    if (cwd.createFile(io, "build.zig.zon", .{})) |zon_file| {
        defer zon_file.close(io);
        try zon_file.writeStreamingAll(io, zon_content);
        std.debug.print("Created build.zig.zon\n", .{});
    } else |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("build.zig.zon already exists, skipping...\n", .{});
        } else {
            return err;
        }
    }

    std.debug.print("✅ Zion project initialized successfully!\n", .{});
    std.debug.print("Run 'zion add <package>' to add dependencies.\n", .{});
}
