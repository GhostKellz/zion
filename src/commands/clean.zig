const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Clean build artifacts and caches - HANDS-FREE CLEANUP
pub fn clean(allocator: Allocator, clean_all: bool) !void {
    const cwd = fs.cwd();
    
    std.debug.print("🧹 Starting hands-free cleanup...\n", .{});

    // Always clean these directories
    const dirs_to_clean = [_][]const u8{
        ".zig-cache",
        ".zion/cache",
        "zig-out",  // Always clean build output
    };

    var cleaned_count: u32 = 0;
    for (dirs_to_clean) |dir| {
        if (cwd.deleteTree(dir)) {
            std.debug.print("🗑️  Deleted {s}/\n", .{dir});
            cleaned_count += 1;
        } else |err| {
            if (err != error.FileNotFound) {
                std.debug.print("⚠️  Could not delete {s}: {}\n", .{ dir, err });
            }
        }
    }
    
    // Always clean up orphaned build.zig comments (hands-free)
    std.debug.print("🔧 Cleaning up build.zig...\n", .{});
    const orphans_removed = cleanupBuildZig(allocator) catch |err| blk: {
        std.debug.print("⚠️  Could not clean build.zig: {}\n", .{err});
        break :blk false;
    };
    if (orphans_removed) {
        cleaned_count += 1;
    }

    if (clean_all) {
        std.debug.print("🔥 Deep clean mode: removing everything...\n", .{});
        
        // Additional cleanup for --all flag  
        const all_dirs = [_][]const u8{
            ".zion/deps", // Clean extracted dependencies
            ".zion",      // Clean entire .zion directory
        };

        const all_files = [_][]const u8{
            "zion.lock",
        };

        for (all_dirs) |dir| {
            if (cwd.deleteTree(dir)) {
                std.debug.print("🗑️  Deleted {s}/\n", .{dir});
                cleaned_count += 1;
            } else |err| {
                if (err != error.FileNotFound) {
                    std.debug.print("⚠️  Could not delete {s}: {}\n", .{ dir, err });
                }
            }
        }

        for (all_files) |file| {
            if (cwd.deleteFile(file)) {
                std.debug.print("🗑️  Deleted {s}\n", .{file});
                cleaned_count += 1;
            } else |err| {
                if (err != error.FileNotFound) {
                    std.debug.print("⚠️  Could not delete {s}: {}\n", .{ file, err });
                }
            }
        }
        
        // Reset build.zig to pristine state
        std.debug.print("🔄 Resetting build.zig to pristine state...\n", .{});
        const build_reset = resetBuildZig(allocator) catch |err| blk: {
            std.debug.print("⚠️  Could not reset build.zig: {}\n", .{err});
            break :blk false;
        };
        if (build_reset) {
            cleaned_count += 1;
        }
        
        // Reset build.zig.zon dependencies
        std.debug.print("🔄 Cleaning dependencies from build.zig.zon...\n", .{});
        const zon_reset = resetZonDependencies(allocator) catch |err| blk: {
            std.debug.print("⚠️  Could not reset build.zig.zon: {}\n", .{err});
            break :blk false;
        };
        if (zon_reset) {
            cleaned_count += 1;
        }
    }
    
    // Final summary
    if (cleaned_count > 0) {
        std.debug.print("✅ Hands-free cleanup complete! Removed {d} items\n", .{cleaned_count});
        std.debug.print("🎯 Project is now clean and ready for fresh dependencies\n", .{});
    } else {
        std.debug.print("✨ Project was already clean!\n", .{});
    }
}

/// Clean up orphaned zion comments and dependency blocks in build.zig
fn cleanupBuildZig(allocator: Allocator) !bool {
    const cwd = fs.cwd();
    
    // Check if build.zig exists
    cwd.access("build.zig", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false; // No build.zig to clean
        }
        return err;
    };
    
    // Read build.zig content
    const build_content = try cwd.readFileAlloc(allocator, "build.zig", 10 * 1024 * 1024);
    defer allocator.free(build_content);
    
    // Check if there are any zion-added dependencies that no longer exist
    var cleaned_content = std.ArrayList(u8).init(allocator);
    defer cleaned_content.deinit();
    
    var lines = std.mem.splitScalar(u8, build_content, '\n');
    var skip_until_end = false;
    var found_orphans = false;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        
        // Check if this is a zion-added comment
        if (std.mem.startsWith(u8, trimmed, "// Added by zion add ")) {
            // Extract the package name
            const package_start = "// Added by zion add ".len;
            if (trimmed.len > package_start) {
                const package_name = trimmed[package_start..];
                
                // Check if this package still exists in .zion/deps/
                const deps_path = std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name}) catch continue;
                defer allocator.free(deps_path);
                
                const package_exists = blk: {
                    cwd.access(deps_path, .{}) catch |err| {
                        if (err == error.FileNotFound) {
                            break :blk false;
                        }
                        break :blk true;
                    };
                    break :blk true;
                };
                
                if (!package_exists) {
                    // This is an orphaned dependency - skip this comment and the following module block
                    skip_until_end = true;
                    found_orphans = true;
                    std.debug.print("  Removing orphaned dependency: {s}\n", .{package_name});
                    continue;
                }
            }
        }
        
        // If we're skipping, look for the end of the module definition
        if (skip_until_end) {
            if (std.mem.indexOf(u8, trimmed, "});") != null and std.mem.indexOf(u8, line, "_mod") != null) {
                skip_until_end = false;
                continue; // Skip this line too
            }
            continue; // Skip all lines in the module block
        }
        
        // Add the line to cleaned content
        try cleaned_content.appendSlice(line);
        try cleaned_content.append('\n');
    }
    
    if (found_orphans) {
        // Write the cleaned content back
        try cwd.writeFile(.{ .sub_path = "build.zig", .data = cleaned_content.items });
        std.debug.print("  ✅ Cleaned up orphaned dependencies in build.zig\n", .{});
        return true;
    } else {
        std.debug.print("  ℹ️  No orphaned dependencies found in build.zig\n", .{});
        return false;
    }
}

/// Reset build.zig to completely clean state (removes all zion modifications)
fn resetBuildZig(allocator: Allocator) !bool {
    const cwd = fs.cwd();
    
    // Check if build.zig exists
    cwd.access("build.zig", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        }
        return err;
    };
    
    // Read build.zig content
    const build_content = try cwd.readFileAlloc(allocator, "build.zig", 10 * 1024 * 1024);
    defer allocator.free(build_content);
    
    var cleaned_content = std.ArrayList(u8).init(allocator);
    defer cleaned_content.deinit();
    
    var lines = std.mem.splitScalar(u8, build_content, '\n');
    var skip_zion_block = false;
    var found_zion_content = false;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        
        // Skip zion marker and everything after until exe definition
        if (std.mem.indexOf(u8, trimmed, "// zion:deps") != null) {
            try cleaned_content.appendSlice(line);
            try cleaned_content.append('\n');
            skip_zion_block = true;
            found_zion_content = true;
            continue;
        }
        
        // Stop skipping when we hit the exe definition
        if (skip_zion_block and std.mem.indexOf(u8, trimmed, "const exe = b.addExecutable") != null) {
            try cleaned_content.append('\n'); // Add blank line
            skip_zion_block = false;
        }
        
        // Skip zion-added lines
        if (std.mem.indexOf(u8, trimmed, "// Added by zion") != null or
            std.mem.indexOf(u8, trimmed, "_mod = b.addModule") != null) {
            found_zion_content = true;
            continue;
        }
        
        if (!skip_zion_block) {
            try cleaned_content.appendSlice(line);
            try cleaned_content.append('\n');
        } else {
            found_zion_content = true;
        }
    }
    
    if (found_zion_content) {
        try cwd.writeFile(.{ .sub_path = "build.zig", .data = cleaned_content.items });
        std.debug.print("  ✅ Reset build.zig to pristine state\n", .{});
        return true;
    } else {
        std.debug.print("  ℹ️  build.zig was already clean\n", .{});
        return false;
    }
}

/// Reset build.zig.zon dependencies to empty state
fn resetZonDependencies(allocator: Allocator) !bool {
    const ZonFile = @import("../manifest.zig").ZonFile;
    const cwd = fs.cwd();
    
    // Check if build.zig.zon exists
    cwd.access("build.zig.zon", .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        }
        return err;
    };
    
    // Load the ZON file
    var zon_file = try ZonFile.loadFromFile(allocator, "build.zig.zon");
    defer zon_file.deinit();
    
    const had_dependencies = zon_file.dependencies.count() > 0;
    
    if (had_dependencies) {
        // Clear all dependencies
        zon_file.dependencies.clearAndFree();
        
        // Save the cleaned ZON file
        try zon_file.saveToFile("build.zig.zon");
        
        std.debug.print("  ✅ Cleared all dependencies from build.zig.zon\n", .{});
        return true;
    } else {
        std.debug.print("  ℹ️  build.zig.zon had no dependencies to clear\n", .{});
        return false;
    }
}
