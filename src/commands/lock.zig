const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;

const Allocator = std.mem.Allocator;

/// Creates or updates a lock file based on build.zig.zon
pub fn lock(allocator: Allocator) !void {
    std.debug.print("Updating lock file...\n", .{});

    const zon_path = "build.zig.zon";
    const cwd = fs.cwd();

    // Check if file exists
    cwd.access(zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Load existing ZON file
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();

    // Load or create lock file
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    std.debug.print("Locking dependencies for project {s} v{s}:\n", .{ zon_file.name, zon_file.version });

    // Create or update lock entries for each dependency
    var it = zon_file.dependencies.iterator();
    var count: usize = 0;
    var updated_lock = false;

    while (it.next()) |entry| {
        const pkg_name = entry.key_ptr.*;
        const url = entry.value_ptr.url;
        const hash = entry.value_ptr.hash;

        // Check if the package is already in the lock file
        const locked_pkg = lock_file.getPackage(pkg_name);

        if (locked_pkg != null) {
            // Update the existing entry if needed
            if (!std.mem.eql(u8, locked_pkg.?.url, url) or
                !std.mem.eql(u8, locked_pkg.?.hash, hash))
            {
                std.debug.print("  - {s}: Updating lock entry\n", .{pkg_name});
                try lock_file.addPackage(pkg_name, url, hash, null);
                updated_lock = true;
            } else {
                std.debug.print("  - {s}: Already locked (hash: {s})\n", .{ pkg_name, hash[0..16] });
            }
        } else {
            // Add new entry
            std.debug.print("  - {s}: Adding to lock file\n", .{pkg_name});
            try lock_file.addPackage(pkg_name, url, hash, null);
            updated_lock = true;
        }

        count += 1;
    }

    if (count == 0) {
        std.debug.print("No dependencies found to lock.\n", .{});
    } else if (updated_lock) {
        // Save the updated lock file
        try lock_file.saveToFile();
        std.debug.print("✅ Lock file updated with {d} dependencies.\n", .{count});
    } else {
        std.debug.print("✅ Lock file is already up-to-date.\n", .{});
    }
}
