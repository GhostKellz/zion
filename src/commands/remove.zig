const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;

/// Remove a dependency from the project
pub fn remove(allocator: Allocator, package_name: []const u8) !void {
    std.debug.print("Removing package: {s}\n", .{package_name});

    // Check if build.zig.zon exists
    const zon_path = "build.zig.zon";
    const cwd = fs.cwd();

    cwd.access(zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: build.zig.zon not found. No project to remove dependencies from.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Step 1: Load and check if package exists in build.zig.zon
    std.debug.print("Checking build.zig.zon for package {s}...\n", .{package_name});
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();

    // Check if the dependency exists
    if (!zon_file.dependencies.contains(package_name)) {
        std.debug.print("Error: Package '{s}' not found in build.zig.zon dependencies.\n", .{package_name});
        std.debug.print("Available packages:\n", .{});

        var it = zon_file.dependencies.iterator();
        var count: usize = 0;
        while (it.next()) |entry| {
            std.debug.print("  - {s}\n", .{entry.key_ptr.*});
            count += 1;
        }

        if (count == 0) {
            std.debug.print("  (no dependencies found)\n", .{});
        }

        return error.PackageNotFound;
    }

    // Step 2: Remove from build.zig.zon
    std.debug.print("Removing {s} from build.zig.zon...\n", .{package_name});
    const removed_dep = zon_file.dependencies.get(package_name).?;

    // Free the dependency memory and remove from map
    allocator.free(removed_dep.url);
    allocator.free(removed_dep.hash);

    // Get the key that we need to free after removal
    var it = zon_file.dependencies.iterator();
    var key_to_free: ?[]const u8 = null;
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, package_name)) {
            key_to_free = entry.key_ptr.*;
            break;
        }
    }

    _ = zon_file.dependencies.remove(package_name);

    // Free the key if we found it
    if (key_to_free) |key| {
        allocator.free(key);
    }

    // Save the updated ZON file
    try zon_file.saveToFile(zon_path);

    // Step 3: Remove from lock file
    std.debug.print("Updating lock file...\n", .{});
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    try removeFromLockFile(&lock_file, package_name);
    try lock_file.saveToFile();

    // Step 4: Remove from build.zig
    std.debug.print("Removing from build.zig...\n", .{});
    removeFromBuildZig(allocator, package_name) catch |err| {
        std.debug.print("Warning: Could not automatically remove from build.zig: {}\n", .{err});
        std.debug.print("You may need to manually remove the dependency from your build.zig file.\n", .{});
    };

    // Step 5: Remove the package directory
    const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
    defer allocator.free(deps_path);

    std.debug.print("Removing package directory {s}...\n", .{deps_path});
    cwd.deleteTree(deps_path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("  (directory not found, skipping)\n", .{});
        } else {
            std.debug.print("Warning: Could not remove package directory: {}\n", .{err});
        }
    };

    // Step 6: Print summary
    std.debug.print("✅ Successfully removed {s}\n", .{package_name});
    std.debug.print("Actions taken:\n", .{});
    std.debug.print("  ✓ Removed from build.zig.zon\n", .{});
    std.debug.print("  ✓ Updated zion.lock\n", .{});
    std.debug.print("  ✓ Removed from build.zig (if found)\n", .{});
    std.debug.print("  ✓ Deleted .zion/deps/{s}/ (if found)\n", .{package_name});
    std.debug.print("Run 'zig build' to verify the removal.\n", .{});
}

/// Remove a package from the lock file
fn removeFromLockFile(lock_file: *LockFile, package_name: []const u8) !void {
    var i: usize = 0;
    while (i < lock_file.packages.items.len) {
        const pkg = &lock_file.packages.items[i];
        if (std.mem.eql(u8, pkg.name, package_name)) {
            // Free the memory for this package
            lock_file.allocator.free(pkg.name);
            lock_file.allocator.free(pkg.url);
            lock_file.allocator.free(pkg.hash);
            if (pkg.version) |version| {
                lock_file.allocator.free(version);
            }

            // Remove from the list
            _ = lock_file.packages.swapRemove(i);
            return;
        }
        i += 1;
    }
}

/// Remove the dependency from build.zig
fn removeFromBuildZig(allocator: Allocator, package_name: []const u8) !void {
    const cwd = fs.cwd();

    // Check if build.zig exists
    cwd.access("build.zig", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return; // No build.zig to modify
        }
        return err;
    };

    // Read build.zig content
    const build_content = try cwd.readFileAlloc(allocator, "build.zig", 10 * 1024 * 1024);
    defer allocator.free(build_content);

    // Look for the dependency block to remove
    const search_pattern = try std.fmt.allocPrint(allocator, "// Added by zion add {s}", .{package_name});
    defer allocator.free(search_pattern);

    if (std.mem.indexOf(u8, build_content, search_pattern)) |start_pos| {
        // Find the start of the line
        var line_start = start_pos;
        while (line_start > 0 and build_content[line_start - 1] != '\n') {
            line_start -= 1;
        }

        // Find the end of the dependency block (look for the closing }});)
        var end_pos = start_pos;
        var brace_count: i32 = 0;
        var found_end = false;

        while (end_pos < build_content.len) {
            const char = build_content[end_pos];
            if (char == '{') {
                brace_count += 1;
            } else if (char == '}') {
                brace_count -= 1;
                if (brace_count <= 0) {
                    // Look for the closing });
                    if (end_pos + 2 < build_content.len and
                        build_content[end_pos + 1] == ')' and
                        build_content[end_pos + 2] == ';')
                    {
                        end_pos += 3;
                        // Include the newline if present
                        if (end_pos < build_content.len and build_content[end_pos] == '\n') {
                            end_pos += 1;
                        }
                        found_end = true;
                        break;
                    }
                }
            }
            end_pos += 1;
        }

        if (found_end) {
            // Remove the dependency block
            const new_content = try std.fmt.allocPrint(allocator, "{s}{s}", .{
                build_content[0..line_start],
                build_content[end_pos..],
            });
            defer allocator.free(new_content);

            // Write back to file
            try cwd.writeFile(.{ .sub_path = "build.zig", .data = new_content });
            std.debug.print("  ✓ Removed {s} module definition from build.zig\n", .{package_name});
        } else {
            std.debug.print("  ⚠️  Found dependency comment but could not locate full block to remove\n", .{});
        }
    } else {
        // Check if there's a manual dependency that we should warn about
        const module_pattern = try std.fmt.allocPrint(allocator, "const {s}_mod", .{package_name});
        defer allocator.free(module_pattern);

        if (std.mem.indexOf(u8, build_content, module_pattern) != null) {
            std.debug.print("  ⚠️  Found manual {s} dependency in build.zig - please remove manually\n", .{package_name});
        } else {
            std.debug.print("  ℹ️  No {s} dependency found in build.zig\n", .{package_name});
        }
    }
}
