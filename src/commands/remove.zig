const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const zion_root = @import("../root.zig");
const DependencyTransaction = @import("../dependency_transaction.zig").DependencyTransaction;

/// Remove a dependency from the project
pub fn remove(allocator: Allocator, package_name: []const u8) !void {
    std.debug.print("Removing package: {s}\n", .{package_name});

    // Check if build.zig.zon exists
    const zon_path = "build.zig.zon";
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    cwd.access(io, zon_path, .{}) catch |err| {
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
    const dev_only = !zon_file.dependencies.contains(package_name) and zon_file.dev_dependencies.contains(package_name);
    if (!zon_file.dependencies.contains(package_name) and !dev_only) {
        std.debug.print("Package '{s}' is already absent; no changes needed.\n", .{package_name});
        return;
    }

    // Step 2: Remove from build.zig.zon
    std.debug.print("Removing {s} from build.zig.zon...\n", .{package_name});
    var transaction = try DependencyTransaction.init(allocator, io, package_name, dev_only);
    defer transaction.deinit();
    if (!zon_file.removeDependency(package_name, dev_only)) return error.PackageNotFound;

    // Save the updated ZON file
    try zon_file.saveToFile(zon_path);

    // Step 3: Remove from lock file
    std.debug.print("Updating lock file...\n", .{});
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    try removeFromLockFile(&lock_file, package_name);
    try lock_file.saveToFile();

    // Step 4: Stage removal of the installed package directory.
    const deps_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ if (dev_only) ".zion/dev-deps" else ".zion/deps", package_name });
    defer allocator.free(deps_path);
    try transaction.removeInstalled();
    try transaction.commit();

    // Step 6: Print summary
    std.debug.print("✅ Successfully removed {s}\n", .{package_name});
    std.debug.print("Actions taken:\n", .{});
    std.debug.print("  ✓ Removed from build.zig.zon\n", .{});
    std.debug.print("  ✓ Updated zion.lock\n", .{});
    std.debug.print("  ✓ Deleted .zion/deps/{s}/ (if found)\n", .{package_name});
    std.debug.print("  ℹ️  Remove any manual build.zig imports separately\n", .{});
    std.debug.print("Run 'zig build' to verify the removal.\n", .{});
}

/// Remove a package from the lock file
fn removeFromLockFile(lock_file: *LockFile, package_name: []const u8) !void {
    var i: usize = 0;
    while (i < lock_file.packages.items.len) {
        const pkg = &lock_file.packages.items[i];
        if (std.mem.eql(u8, pkg.name, package_name)) {
            // Free all allocated fields for this package
            pkg.deinit(lock_file.allocator);

            // Remove from the list
            _ = lock_file.packages.swapRemove(i);
            return;
        }
        i += 1;
    }
}

/// Remove the dependency from build.zig
fn removeFromBuildZig(allocator: Allocator, package_name: []const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if build.zig exists
    cwd.access(io, "build.zig", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return; // No build.zig to modify
        }
        return err;
    };

    // Read build.zig content
    const build_content = try cwd.readFileAlloc(io, "build.zig", allocator, Io.Limit.limited(10 * 1024 * 1024));
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
            try cwd.writeFile(io, .{ .sub_path = "build.zig", .data = new_content });
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
