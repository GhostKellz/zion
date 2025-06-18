const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");

/// Add a dependency to the project - COMPLETE IMPLEMENTATION
pub fn add(allocator: Allocator, package_ref: []const u8) !void {
    std.debug.print("Adding package: {s}\n", .{package_ref});

    // Validate package reference format (should be "user/repo")
    const slash_index = std.mem.indexOf(u8, package_ref, "/");
    if (slash_index == null) {
        std.debug.print("Error: Invalid package reference. Use format 'user/repo' (e.g. 'mitchellh/libxev')\n", .{});
        return error.InvalidPackageReference;
    }

    // Check if build.zig.zon exists
    const zon_path = "build.zig.zon";
    const cwd = fs.cwd();

    cwd.access(zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Extract package name from reference (last part after slash)
    const package_name = package_ref[slash_index.? + 1 ..];

    // Step 1: Download and hash the package
    std.debug.print("Downloading {s}...\n", .{package_ref});
    const download_result = try downloader.downloadAndHashPackage(allocator, package_ref);
    defer {
        allocator.free(download_result.url);
        allocator.free(download_result.hash);
        allocator.free(download_result.cache_path);
    }

    // Step 2: Extract the tarball to deps directory
    try ensureDepsDir();
    const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
    defer allocator.free(deps_path);

    std.debug.print("Extracting package to {s}...\n", .{deps_path});
    try extractTarball(allocator, download_result.cache_path, deps_path);

    // Step 3: Load and update build.zig.zon
    std.debug.print("Updating build.zig.zon...\n", .{});
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();

    // Add the dependency
    try zon_file.addDependency(package_name, download_result.url, download_result.hash);

    // Save the updated ZON file
    try zon_file.saveToFile(zon_path);

    // Step 4: Update lock file
    std.debug.print("Updating lock file...\n", .{});
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    try lock_file.addPackage(package_name, download_result.url, download_result.hash, null);
    try lock_file.saveToFile();

    // Step 5: Automatically modify build.zig
    std.debug.print("Updating build.zig...\n", .{});
    modifyBuildZig(allocator, package_name, deps_path) catch |err| {
        std.debug.print("⚠️  Could not automatically update build.zig: {}\n", .{err});
        std.debug.print("Manual integration required:\n", .{});
        try printBuildInstructions(package_name, deps_path);
        return;
    };

    std.debug.print("✅ Successfully added {s}\n", .{package_ref});
    std.debug.print("Package extracted to: {s}\n", .{deps_path});
    std.debug.print("Run 'zig build' to verify the integration.\n", .{});
}

/// Add multiple dependencies to the project
pub fn addMultiple(allocator: Allocator, packages: []const []const u8) !void {
    std.debug.print("Adding {d} packages...\n", .{packages.len});

    var success_count: usize = 0;
    var error_count: usize = 0;

    for (packages, 0..) |package_ref, i| {
        std.debug.print("\n[{d}/{d}] ", .{ i + 1, packages.len });

        add(allocator, package_ref) catch |err| {
            error_count += 1;
            std.debug.print("❌ Failed to add {s}: {}\n", .{ package_ref, err });
            continue;
        };

        success_count += 1;
    }

    std.debug.print("\n📊 Summary: {d} successful, {d} failed\n", .{ success_count, error_count });

    if (success_count > 0) {
        std.debug.print("🚀 Run 'zig build' to verify all integrations.\n", .{});
    }
}

/// Ensure the .zion/deps directory exists
fn ensureDepsDir() !void {
    const cwd = fs.cwd();

    // Create .zion directory if it doesn't exist
    cwd.makeDir(".zion") catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    // Create .zion/deps directory if it doesn't exist
    cwd.makeDir(".zion/deps") catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
}

/// Extract a tarball to a destination directory
fn extractTarball(allocator: Allocator, tarball_path: []const u8, dest_path: []const u8) !void {
    const cwd = fs.cwd();

    // Remove existing directory if it exists
    cwd.deleteTree(dest_path) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };

    // Create destination directory
    try cwd.makePath(dest_path);

    // Use tar to extract (most reliable cross-platform solution)
    const argv = [_][]const u8{
        "tar",
        "-xzf",
        tarball_path,
        "-C",
        dest_path,
        "--strip-components=1", // Remove the top-level directory from the archive
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    const term = try child.wait();

    // Read stderr for error messages
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("tar extraction failed (exit code {d}): {s}\n", .{ code, stderr });
                return error.ExtractionFailed;
            }
        },
        else => {
            std.debug.print("tar extraction terminated abnormally: {s}\n", .{stderr});
            return error.ExtractionFailed;
        },
    }

    std.debug.print("Package extracted successfully\n", .{});

    // Validate that this looks like a valid Zig package
    try validateExtractedPackage(dest_path);
}

/// Validate that the extracted package has the expected structure
fn validateExtractedPackage(package_path: []const u8) !void {
    const cwd = fs.cwd();

    // Check for build.zig (required for Zig packages)
    const build_zig_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/build.zig", .{package_path});
    defer std.heap.page_allocator.free(build_zig_path);

    cwd.access(build_zig_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("⚠️  Warning: No build.zig found in package. This may not be a valid Zig package.\n", .{});
            return;
        }
        return err;
    };

    // Check for src/ directory (conventional)
    const src_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/src", .{package_path});
    defer std.heap.page_allocator.free(src_path);

    cwd.access(src_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("⚠️  Warning: No src/ directory found. Package structure may be non-standard.\n", .{});
            return;
        }
        return err;
    };

    std.debug.print("✅ Package structure validated\n", .{});
}

/// Print instructions for integrating the dependency into build.zig
fn printBuildInstructions(package_name: []const u8, deps_path: []const u8) !void {
    std.debug.print("\n", .{});
    std.debug.print("To use this dependency in your project, add the following to your build.zig:\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("// Add this near the top where modules are defined:\n", .{});
    std.debug.print("const {s}_mod = b.addModule(\"{s}\", .{{\n", .{ package_name, package_name });
    std.debug.print("    .root_source_file = b.path(\"{s}/src/root.zig\"),\n", .{deps_path});
    std.debug.print("    .target = target,\n", .{});
    std.debug.print("    .optimize = optimize,\n", .{});
    std.debug.print("}});\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("// Add this to your executable's imports:\n", .{});
    std.debug.print(".imports = &.{{\n", .{});
    std.debug.print("    .{{ .name = \"{s}\", .module = {s}_mod }},\n", .{ package_name, package_name });
    std.debug.print("    // ... your other imports\n", .{});
    std.debug.print("}},\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("// Then in your Zig code, you can use:\n", .{});
    std.debug.print("const {s} = @import(\"{s}\");\n", .{ package_name, package_name });
}

/// Automatically modify build.zig to include the new dependency
fn modifyBuildZig(allocator: Allocator, package_name: []const u8, deps_path: []const u8) !void {
    const cwd = fs.cwd();

    // Check if build.zig exists
    cwd.access("build.zig", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("⚠️  No build.zig found - skipping automatic integration\n", .{});
            return;
        }
        return err;
    };

    // Read build.zig content
    const build_content = try cwd.readFileAlloc(allocator, "build.zig", 10 * 1024 * 1024);
    defer allocator.free(build_content);

    // Check if dependency already exists
    const search_pattern = try std.fmt.allocPrint(allocator, "const {s}_mod = b.addModule", .{package_name});
    defer allocator.free(search_pattern);

    if (std.mem.indexOf(u8, build_content, search_pattern) != null) {
        std.debug.print("✅ Dependency {s} already exists in build.zig\n", .{package_name});
        return;
    }

    // Look for our injection point
    const injection_marker = "// zion:deps - dependencies will be added below this line";

    if (std.mem.indexOf(u8, build_content, injection_marker)) |marker_pos| {
        // Found our marker, inject after it
        try injectAfterMarker(allocator, build_content, marker_pos, package_name, deps_path);
    } else {
        // No marker found, try to find a good insertion point
        try injectAtBestLocation(allocator, build_content, package_name, deps_path);
    }
}

/// Inject dependency after the zion:deps marker
fn injectAfterMarker(allocator: Allocator, content: []const u8, marker_pos: usize, package_name: []const u8, deps_path: []const u8) !void {
    // Find the end of the line with the marker
    const line_end = std.mem.indexOfScalarPos(u8, content, marker_pos, '\n') orelse content.len;

    // Create the dependency code to inject
    const dep_code = try std.fmt.allocPrint(allocator,
        \\n        \\    // Added by zion add {s}
        \\    const {s}_mod = b.addModule("{s}", .{{
        \\        .root_source_file = b.path("{s}/src/root.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\n
    , .{ package_name, package_name, package_name, deps_path });
    defer allocator.free(dep_code);

    // Create new content with injection
    const new_content = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
        content[0 .. line_end + 1],
        dep_code,
        content[line_end + 1 ..],
    });
    defer allocator.free(new_content);

    // Write back to file
    const cwd = fs.cwd();
    try cwd.writeFile(.{ .sub_path = "build.zig", .data = new_content });
    std.debug.print("✅ Added {s} to build.zig after marker\n", .{package_name});
}

/// Try to inject at a reasonable location in build.zig
fn injectAtBestLocation(allocator: Allocator, content: []const u8, package_name: []const u8, deps_path: []const u8) !void {
    // Look for a good insertion point - after the module creation but before exe creation
    const mod_creation = "const mod = b.addModule(";
    const exe_creation = "const exe = b.addExecutable(";

    var injection_pos: ?usize = null;

    if (std.mem.indexOf(u8, content, mod_creation)) |mod_pos| {
        // Find the end of the module creation block
        if (std.mem.indexOfScalarPos(u8, content, mod_pos, '}')) |block_end| {
            if (std.mem.indexOfScalarPos(u8, content, block_end, '\n')) |line_end| {
                injection_pos = line_end + 1;
            }
        }
    } else if (std.mem.indexOf(u8, content, exe_creation)) |exe_pos| {
        // Insert before exe creation
        injection_pos = exe_pos;
    }

    if (injection_pos) |pos| {
        const dep_code = try std.fmt.allocPrint(allocator,
            \\n            \\    // Added by zion add {s}
            \\    const {s}_mod = b.addModule("{s}", .{{
            \\        .root_source_file = b.path("{s}/src/root.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\n
        , .{ package_name, package_name, package_name, deps_path });
        defer allocator.free(dep_code);

        const new_content = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
            content[0..pos],
            dep_code,
            content[pos..],
        });
        defer allocator.free(new_content);

        const cwd = fs.cwd();
        try cwd.writeFile(.{ .sub_path = "build.zig", .data = new_content });
        std.debug.print("✅ Added {s} to build.zig automatically\n", .{package_name});
    } else {
        std.debug.print("⚠️  Could not find good injection point in build.zig\n", .{});
        std.debug.print("💡 Add this line to your build.zig: // zion:deps - dependencies will be added below this line\n", .{});
        return error.CouldNotInject;
    }
}
