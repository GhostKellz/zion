const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Workspace management - Cargo-style workspaces for Zig
pub fn workspace(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 3) {
        printWorkspaceHelp();
        return;
    }
    
    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "init")) {
        return initWorkspace(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "add")) {
        return addToWorkspace(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        return listWorkspaceMembers(allocator);
    } else if (std.mem.eql(u8, subcommand, "build")) {
        return buildWorkspace(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "test")) {
        return testWorkspace(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "clean")) {
        return cleanWorkspace(allocator);
    } else {
        std.debug.print("Unknown workspace subcommand: {s}\n", .{subcommand});
        printWorkspaceHelp();
    }
}

fn initWorkspace(allocator: Allocator, args: [][:0]u8) !void {
    _ = args;
    
    std.debug.print("Initializing Zig workspace...\n", .{});
    
    // Check if already in a workspace
    if (checkWorkspaceConfig()) {
        std.debug.print("Already in a workspace directory\n", .{});
        return;
    }
    
    // Create workspace configuration file
    try createWorkspaceConfig(allocator);
    
    // Create basic workspace structure
    try createWorkspaceStructure();
    
    std.debug.print("Zig workspace initialized!\n", .{});
    std.debug.print("Structure created:\n", .{});
    std.debug.print("  zion-workspace.toml - Workspace configuration\n", .{});
    std.debug.print("  packages/           - Package directory\n", .{});
    std.debug.print("  target/             - Shared build output\n", .{});
    std.debug.print("\nNext steps:\n", .{});
    std.debug.print("  zion workspace add mypackage  # Add a package\n", .{});
    std.debug.print("  zion workspace build          # Build all packages\n", .{});
}

fn addToWorkspace(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: zion workspace add <package-name>\n", .{});
        return;
    }
    
    const package_name = args[0];
    
    std.debug.print("Adding package '{s}' to workspace...\n", .{package_name});
    
    // Check if we're in a workspace
    if (!checkWorkspaceConfig()) {
        std.debug.print("Not in a workspace directory. Run 'zion workspace init' first.\n", .{});
        return;
    }
    
    // Create package directory
    const package_dir = try std.fmt.allocPrint(allocator, "packages/{s}", .{package_name});
    defer allocator.free(package_dir);
    
    try fs.cwd().makePath(package_dir);
    
    // Create basic package files
    try createPackageStructure(allocator, package_dir, package_name);
    
    // Update workspace config
    try updateWorkspaceConfig(allocator, package_name);
    
    std.debug.print("Package '{s}' added to workspace!\n", .{package_name});
    std.debug.print("Location: {s}/\n", .{package_dir});
}

fn listWorkspaceMembers(allocator: Allocator) !void {
    if (!checkWorkspaceConfig()) {
        std.debug.print("Not in a workspace directory\n", .{});
        return;
    }
    
    std.debug.print("Workspace Members:\n", .{});
    
    // Read workspace config and list members
    const members = try getWorkspaceMembers(allocator);
    defer {
        for (members) |member| {
            allocator.free(member);
        }
        allocator.free(members);
    }
    
    if (members.len == 0) {
        std.debug.print("  (no packages)\n", .{});
    } else {
        for (members) |member| {
            std.debug.print("  packages/{s}/\n", .{member});
        }
    }
}

fn buildWorkspace(allocator: Allocator, args: [][:0]u8) !void {
    _ = args;
    
    if (!checkWorkspaceConfig()) {
        std.debug.print("Not in a workspace directory\n", .{});
        return;
    }
    
    std.debug.print("Building workspace...\n", .{});
    
    const members = try getWorkspaceMembers(allocator);
    defer {
        for (members) |member| {
            allocator.free(member);
        }
        allocator.free(members);
    }
    
    for (members) |member| {
        std.debug.print("Building {s}...\n", .{member});
        
        const package_dir = try std.fmt.allocPrint(allocator, "packages/{s}", .{member});
        defer allocator.free(package_dir);
        
        // Change to package directory and build
        const old_cwd = fs.cwd();
        var package_cwd = fs.cwd().openDir(package_dir, .{}) catch |err| {
            std.debug.print("  Error: Could not open {s}: {}\n", .{ package_dir, err });
            continue;
        };
        defer package_cwd.close();
        
        // Build the package (simplified)
        const build_args = [_][]const u8{ "zig", "build" };
        var child = std.process.Child.init(&build_args, allocator);
        child.cwd_dir = package_cwd;
        
        const result = child.spawnAndWait() catch |err| {
            std.debug.print("  Error building {s}: {}\n", .{ member, err });
            continue;
        };
        
        if (result.Exited == 0) {
            std.debug.print("  ✅ Built {s}\n", .{member});
        } else {
            std.debug.print("  ❌ Failed to build {s}\n", .{member});
        }
        
        _ = old_cwd;
    }
    
    std.debug.print("Workspace build complete!\n", .{});
}

fn testWorkspace(allocator: Allocator, args: [][:0]u8) !void {
    _ = args;
    
    std.debug.print("Testing workspace...\n", .{});
    std.debug.print("(Test functionality would run tests for all packages)\n", .{});
    _ = allocator;
}

fn cleanWorkspace(allocator: Allocator) !void {
    std.debug.print("Cleaning workspace...\n", .{});
    
    // Clean shared target directory
    fs.cwd().deleteTree("target") catch {};
    
    // Clean individual package caches
    const members = try getWorkspaceMembers(allocator);
    defer {
        for (members) |member| {
            allocator.free(member);
        }
        allocator.free(members);
    }
    
    for (members) |member| {
        const cache_dir = try std.fmt.allocPrint(allocator, "packages/{s}/.zig-cache", .{member});
        defer allocator.free(cache_dir);
        
        fs.cwd().deleteTree(cache_dir) catch {};
        
        const out_dir = try std.fmt.allocPrint(allocator, "packages/{s}/zig-out", .{member});
        defer allocator.free(out_dir);
        
        fs.cwd().deleteTree(out_dir) catch {};
    }
    
    std.debug.print("Workspace cleaned!\n", .{});
}

// Helper functions

fn checkWorkspaceConfig() bool {
    fs.cwd().access("zion-workspace.toml", .{}) catch return false;
    return true;
}

fn createWorkspaceConfig(allocator: Allocator) !void {
    _ = allocator;
    
    const config_content =
        \\# Zion Workspace Configuration
        \\# Cargo-style workspace for Zig projects
        \\
        \\[workspace]
        \\name = "my-workspace"
        \\version = "0.1.0"
        \\
        \\# List of packages in this workspace
        \\members = [
        \\    # "packages/mypackage",
        \\]
        \\
        \\# Shared dependencies for all packages
        \\[workspace.dependencies]
        \\# std = "0.15.0"
        \\
        \\# Build configuration
        \\[workspace.build]
        \\optimize = "Debug"
        \\target_dir = "target"
        \\
    ;
    
    try fs.cwd().writeFile(.{ .sub_path = "zion-workspace.toml", .data = config_content });
}

fn createWorkspaceStructure() !void {
    try fs.cwd().makePath("packages");
    try fs.cwd().makePath("target");
}

fn createPackageStructure(allocator: Allocator, package_dir: []const u8, package_name: []const u8) !void {
    // Create src directory
    const src_dir = try std.fmt.allocPrint(allocator, "{s}/src", .{package_dir});
    defer allocator.free(src_dir);
    try fs.cwd().makePath(src_dir);
    
    // Create main.zig
    const main_file = try std.fmt.allocPrint(allocator, "{s}/src/main.zig", .{package_dir});
    defer allocator.free(main_file);
    
    const main_content = try std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\
        \\pub fn main() !void {{
        \\    std.debug.print("Hello from {s}!\\n", .{{}});
        \\}}
        \\
    , .{package_name});
    defer allocator.free(main_content);
    
    try fs.cwd().writeFile(.{ .sub_path = main_file, .data = main_content });
    
    // Create build.zig
    const build_file = try std.fmt.allocPrint(allocator, "{s}/build.zig", .{package_dir});
    defer allocator.free(build_file);
    
    const build_content = try std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\
        \\    const exe = b.addExecutable(.{{
        \\        .name = "{s}",
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\
        \\    b.installArtifact(exe);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    run_cmd.step.dependOn(b.getInstallStep());
        \\
        \\    const run_step = b.step("run", "Run the app");
        \\    run_step.dependOn(&run_cmd.step);
        \\}}
        \\
    , .{package_name});
    defer allocator.free(build_content);
    
    try fs.cwd().writeFile(.{ .sub_path = build_file, .data = build_content });
}

fn updateWorkspaceConfig(allocator: Allocator, package_name: []const u8) !void {
    _ = allocator;
    _ = package_name;
    // Simple implementation - in practice would parse and update TOML
    std.debug.print("(Workspace config update not fully implemented)\n", .{});
}

fn getWorkspaceMembers(allocator: Allocator) ![][]const u8 {
    // Simple implementation - just list directories in packages/
    var dir = fs.cwd().openDir("packages", .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            return try allocator.alloc([]const u8, 0);
        }
        return err;
    };
    defer dir.close();
    
    var members = std.ArrayList([]const u8).init(allocator);
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            const name = try allocator.dupe(u8, entry.name);
            try members.append(name);
        }
    }
    
    return members.toOwnedSlice();
}

fn printWorkspaceHelp() void {
    std.debug.print("Zion Workspace Management\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion workspace <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    init                    Initialize a new workspace\n", .{});
    std.debug.print("    add <name>              Add a package to workspace\n", .{});
    std.debug.print("    list                    List workspace members\n", .{});
    std.debug.print("    build                   Build all packages\n", .{});
    std.debug.print("    test                    Test all packages\n", .{});
    std.debug.print("    clean                   Clean workspace build artifacts\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion workspace init             # Initialize workspace\n", .{});
    std.debug.print("    zion workspace add mylib        # Add package 'mylib'\n", .{});
    std.debug.print("    zion workspace build            # Build all packages\n", .{});
    std.debug.print("    zion workspace list             # Show all packages\n", .{});
}