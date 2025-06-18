const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Initialize a new Zig project
pub fn init(allocator: Allocator) !void {
    _ = allocator; // unused but required for API consistency

    const cwd = fs.cwd();

    std.debug.print("Initializing Zion project...\n", .{});

    // Create src directory
    cwd.makeDir("src") catch |err| {
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

    if (cwd.createFile("src/main.zig", .{})) |main_file| {
        defer main_file.close();
        try main_file.writeAll(main_zig_content);
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

    if (cwd.createFile("build.zig", .{})) |build_file| {
        defer build_file.close();
        try build_file.writeAll(build_zig_content);
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

    if (cwd.createFile("build.zig.zon", .{})) |zon_file| {
        defer zon_file.close();
        try zon_file.writeAll(zon_content);
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
