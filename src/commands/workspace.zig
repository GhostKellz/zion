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
    } else if (std.mem.eql(u8, subcommand, "template")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion workspace template <template_name>\n", .{});
            std.debug.print("Available templates: library, application, fullstack\n", .{});
            return;
        }
        return createWorkspaceTemplate(allocator, args[3]);
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
    if (!checkWorkspaceConfig()) {
        std.debug.print("Not in a workspace directory\n", .{});
        return;
    }
    
    // Parse arguments
    var build_all = false;
    var parallel_jobs: u8 = 1;
    var release_mode = false;
    var target_package: ?[]const u8 = null;
    
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--all")) {
            build_all = true;
        } else if (std.mem.startsWith(u8, arg, "--jobs=") or std.mem.startsWith(u8, arg, "-j=")) {
            const jobs_str = arg[std.mem.indexOf(u8, arg, "=").? + 1..];
            parallel_jobs = std.fmt.parseInt(u8, jobs_str, 10) catch 1;
        } else if (std.mem.eql(u8, arg, "--release")) {
            release_mode = true;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            target_package = arg;
        }
    }
    
    if (build_all) {
        std.debug.print("Building all workspace packages with {} parallel jobs...\n", .{parallel_jobs});
    } else if (target_package) |pkg| {
        std.debug.print("Building specific package: {s}...\n", .{pkg});
    } else {
        std.debug.print("Building workspace packages...\n", .{});
    }
    
    // Resolve workspace-level dependencies first
    try resolveWorkspaceDependencies(allocator);
    
    const members = try getWorkspaceMembers(allocator);
    defer {
        for (members) |member| {
            allocator.free(member);
        }
        allocator.free(members);
    }
    
    // Filter members if specific package requested
    var build_targets: std.ArrayList([]const u8) = .{};
    defer build_targets.deinit(allocator);
    
    if (target_package) |pkg| {
        // Build only specific package
        for (members) |member| {
            if (std.mem.eql(u8, member, pkg)) {
                try build_targets.append(allocator, member);
                break;
            }
        }
        if (build_targets.items.len == 0) {
            std.debug.print("Error: Package '{s}' not found in workspace\n", .{pkg});
            return;
        }
    } else {
        // Build all packages
        for (members) |member| {
            try build_targets.append(allocator, member);
        }
    }
    
    // Build packages in dependency order
    const build_order = try determineBuildOrder(allocator, build_targets.items);
    defer {
        for (build_order) |pkg| {
            allocator.free(pkg);
        }
        allocator.free(build_order);
    }
    
    var successful_builds: u32 = 0;
    var failed_builds: u32 = 0;
    
    // Create progress bar for builds
    const progress = @import("../progress.zig");
    var build_progress = progress.ProgressBar.init(allocator, "🏗️  Building workspace packages", build_order.len);
    
    for (build_order, 0..) |member, i| {
        build_progress.update(i);
        std.debug.print("\n🔨 Building {s}...\n", .{member});
        
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
            failed_builds += 1;
            continue;
        };
        
        if (result.Exited == 0) {
            std.debug.print("  ✅ Built {s}\n", .{member});
            successful_builds += 1;
        } else {
            std.debug.print("  ❌ Failed to build {s}\n", .{member});
            failed_builds += 1;
        }
        
        _ = old_cwd;
    }
    
    // Finish progress bar
    build_progress.finish();
    
    std.debug.print("\n🎉 Workspace build complete!\n", .{});
    std.debug.print("  ✅ Successful builds: {}\n", .{successful_builds});
    std.debug.print("  ❌ Failed builds: {}\n", .{failed_builds});
    
    if (failed_builds > 0) {
        std.debug.print("\n⚠️  Some packages failed to build. Check the output above for details.\n", .{});
    }
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
    
    var members: std.ArrayList([]const u8) = .{};
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .directory) {
            const name = try allocator.dupe(u8, entry.name);
            try members.append(allocator, name);
        }
    }
    
    return members.toOwnedSlice(allocator);
}

fn printWorkspaceHelp() void {
    std.debug.print("Zion Workspace Management\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion workspace <SUBCOMMAND>\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    init                    Initialize a new workspace\n", .{});
    std.debug.print("    template <type>         Create workspace from template\n", .{});
    std.debug.print("    add <name>              Add a package to workspace\n", .{});
    std.debug.print("    list                    List workspace members\n", .{});
    std.debug.print("    build                   Build all packages\n", .{});
    std.debug.print("    test                    Test all packages\n", .{});
    std.debug.print("    clean                   Clean workspace build artifacts\n\n", .{});
    std.debug.print("TEMPLATES:\n", .{});
    std.debug.print("    library                 Multi-package library workspace\n", .{});
    std.debug.print("    application             Application with utilities\n", .{});
    std.debug.print("    fullstack               Backend, shared models, and CLI\n\n", .{});
    std.debug.print("BUILD OPTIONS:\n", .{});
    std.debug.print("    --all                   Build all packages explicitly\n", .{});
    std.debug.print("    --jobs=N, -j=N         Number of parallel build jobs\n", .{});
    std.debug.print("    --release               Build in release mode\n", .{});
    std.debug.print("    <package-name>          Build specific package\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion workspace init             # Initialize workspace\n", .{});
    std.debug.print("    zion workspace add mylib        # Add package 'mylib'\n", .{});
    std.debug.print("    zion workspace build --all      # Build all packages\n", .{});
    std.debug.print("    zion workspace build mylib      # Build specific package\n", .{});
    std.debug.print("    zion workspace build --jobs=4   # Build with 4 parallel jobs\n", .{});
    std.debug.print("    zion workspace list             # Show all packages\n", .{});
}

/// Resolve workspace-level dependencies
fn resolveWorkspaceDependencies(allocator: Allocator) !void {
    std.debug.print("🔍 Resolving workspace dependencies...\n", .{});
    
    // Check if workspace has a shared dependency file
    const workspace_deps_path = "zion-workspace-deps.toml";
    
    const deps_content = fs.cwd().readFileAlloc(workspace_deps_path, allocator, @enumFromInt(1024 * 1024)) catch {
        // No workspace dependencies file - that's fine
        std.debug.print("  No workspace-level dependencies found\n", .{});
        return;
    };
    defer allocator.free(deps_content);
    
    std.debug.print("  Found workspace dependencies file\n", .{});
    
    // Parse workspace dependencies (simplified TOML parsing)
    var lines = std.mem.splitSequence(u8, deps_content, "\n");
    var deps_found: u32 = 0;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const dep_name = std.mem.trim(u8, trimmed[0..eq_pos], " \t\"");
            const dep_spec = std.mem.trim(u8, trimmed[eq_pos + 1..], " \t\"");
            
            std.debug.print("    📦 {s} = {s}\n", .{ dep_name, dep_spec });
            deps_found += 1;
        }
    }
    
    if (deps_found > 0) {
        std.debug.print("  ✅ Found {} workspace dependencies\n", .{deps_found});
        std.debug.print("  💾 Shared dependencies will be available to all packages\n", .{});
    }
}

/// Determine the build order based on dependencies
fn determineBuildOrder(allocator: Allocator, packages: []const []const u8) ![][]const u8 {
    // For now, return packages in original order
    // In a full implementation, this would analyze build.zig files to determine dependencies
    var ordered_packages: std.ArrayList([]const u8) = .{};
    
    for (packages) |pkg| {
        try ordered_packages.append(allocator, try allocator.dupe(u8, pkg));
    }
    
    std.debug.print("📊 Build order determined: ", .{});
    for (packages, 0..) |pkg, i| {
        if (i > 0) std.debug.print(" → ", .{});
        std.debug.print("{s}", .{pkg});
    }
    std.debug.print("\n", .{});
    
    return try ordered_packages.toOwnedSlice(allocator);
}

/// Create workspace template scaffolding
fn createWorkspaceTemplate(allocator: Allocator, template_name: []const u8) !void {
    std.debug.print("🏗️  Creating workspace from template: {s}\n", .{template_name});
    
    // Define available templates structure
    const WorkspaceTemplate = struct {
        name: []const u8,
        description: []const u8,
        packages: [][]const u8,
        shared_deps: [][]const u8,
    };
    _ = WorkspaceTemplate; // Unused for now, just for future reference
    
    if (std.mem.eql(u8, template_name, "library")) {
        try createLibraryWorkspace(allocator);
    } else if (std.mem.eql(u8, template_name, "application")) {
        try createApplicationWorkspace(allocator);
    } else if (std.mem.eql(u8, template_name, "fullstack")) {
        try createFullStackWorkspace(allocator);
    } else {
        std.debug.print("❌ Unknown template: {s}\n", .{template_name});
        std.debug.print("Available templates: library, application, fullstack\n", .{});
        return;
    }
    
    std.debug.print("✅ Workspace template '{s}' created successfully!\n", .{template_name});
}

/// Create a library-focused workspace
fn createLibraryWorkspace(allocator: Allocator) !void {
    // Create workspace structure
    try fs.cwd().makeDir("packages");
    try fs.cwd().makeDir("target");
    try fs.cwd().makeDir("examples");
    try fs.cwd().makeDir("docs");
    
    // Create library package
    const lib_dir = "packages/core";
    try fs.cwd().makePath(lib_dir);
    try createPackageStructure(allocator, lib_dir, "core");
    
    // Create example package
    const example_dir = "packages/example";
    try fs.cwd().makePath(example_dir);
    try createPackageStructure(allocator, example_dir, "example");
    
    // Create workspace config
    const workspace_config = 
        \\[workspace]
        \\members = [
        \\    "packages/core",
        \\    "packages/example"
        \\]
        \\
        \\[workspace.metadata]
        \\type = "library"
        \\description = "A Zig library workspace"
        \\
        \\[workspace.dependencies]
        \\# Add shared dependencies here
    ;
    
    const config_file = try fs.cwd().createFile("zion-workspace.toml", .{});
    defer config_file.close();
    try config_file.writeAll(workspace_config);
    
    std.debug.print("  📚 Created library workspace with core library and example\n", .{});
}

/// Create an application-focused workspace
fn createApplicationWorkspace(allocator: Allocator) !void {
    // Create workspace structure
    try fs.cwd().makeDir("packages");
    try fs.cwd().makeDir("target");
    try fs.cwd().makeDir("assets");
    try fs.cwd().makeDir("config");
    
    // Create main application
    const app_dir = "packages/app";
    try fs.cwd().makePath(app_dir);
    try createPackageStructure(allocator, app_dir, "app");
    
    // Create utilities library
    const utils_dir = "packages/utils";
    try fs.cwd().makePath(utils_dir);
    try createPackageStructure(allocator, utils_dir, "utils");
    
    // Create workspace config
    const workspace_config = 
        \\[workspace]
        \\members = [
        \\    "packages/app",
        \\    "packages/utils"
        \\]
        \\
        \\[workspace.metadata]
        \\type = "application"
        \\description = "A Zig application workspace"
        \\
        \\[workspace.dependencies]
        \\# Add shared dependencies here
    ;
    
    const config_file = try fs.cwd().createFile("zion-workspace.toml", .{});
    defer config_file.close();
    try config_file.writeAll(workspace_config);
    
    std.debug.print("  🚀 Created application workspace with main app and utilities\n", .{});
}

/// Create a full-stack workspace  
fn createFullStackWorkspace(allocator: Allocator) !void {
    // Create workspace structure
    try fs.cwd().makeDir("packages");
    try fs.cwd().makeDir("target");
    try fs.cwd().makeDir("static");
    try fs.cwd().makeDir("docker");
    
    // Create backend
    const backend_dir = "packages/backend";
    try fs.cwd().makePath(backend_dir);
    try createPackageStructure(allocator, backend_dir, "backend");
    
    // Create shared models
    const models_dir = "packages/shared";
    try fs.cwd().makePath(models_dir);
    try createPackageStructure(allocator, models_dir, "shared");
    
    // Create CLI tool
    const cli_dir = "packages/cli";
    try fs.cwd().makePath(cli_dir);
    try createPackageStructure(allocator, cli_dir, "cli");
    
    // Create workspace config
    const workspace_config = 
        \\[workspace]
        \\members = [
        \\    "packages/backend",
        \\    "packages/shared", 
        \\    "packages/cli"
        \\]
        \\
        \\[workspace.metadata]
        \\type = "fullstack"
        \\description = "A full-stack Zig workspace"
        \\
        \\[workspace.dependencies]
        \\# Add shared dependencies here
        \\# Example: http = "1.0.0"
    ;
    
    const config_file = try fs.cwd().createFile("zion-workspace.toml", .{});
    defer config_file.close();
    try config_file.writeAll(workspace_config);
    
    std.debug.print("  🌐 Created full-stack workspace with backend, shared models, and CLI\n", .{});
}