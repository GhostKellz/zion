const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const mem = std.mem;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const zion_root = @import("../root.zig");

const Allocator = std.mem.Allocator;

/// Lock command with subcommands
pub fn lock(allocator: Allocator, args: []const [:0]const u8) !void {
    // Check for subcommand
    if (args.len >= 3) {
        const subcommand = args[2];

        if (std.mem.eql(u8, subcommand, "sync")) {
            return lockSync(allocator);
        } else if (std.mem.eql(u8, subcommand, "verify")) {
            return lockVerify(allocator);
        } else if (std.mem.eql(u8, subcommand, "clean")) {
            return lockClean(allocator);
        } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "--help")) {
            printLockHelp();
            return;
        } else {
            std.debug.print("Unknown lock subcommand: {s}\n\n", .{subcommand});
            printLockHelp();
            return;
        }
    }

    // Default behavior: create/update lock file
    return lockDefault(allocator);
}

/// Default lock behavior: Creates or updates a lock file based on build.zig.zon
fn lockDefault(allocator: Allocator) !void {
    std.debug.print("Updating lock file...\n", .{});

    const zon_path = "build.zig.zon";
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if file exists
    cwd.access(io, zon_path, .{}) catch |err| {
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
                std.debug.print("  - {s}: Already locked (hash: {s}...)\n", .{ pkg_name, hash[0..@min(hash.len, 16)] });
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
        std.debug.print("Lock file updated with {d} dependencies.\n", .{count});
    } else {
        std.debug.print("Lock file is already up-to-date.\n", .{});
    }
}

/// Sync: Bidirectional sync between ZON and lockfile
fn lockSync(allocator: Allocator) !void {
    std.debug.print("Syncing lock file with build.zig.zon...\n\n", .{});

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if build.zig.zon exists
    cwd.access(io, "build.zig.zon", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Load ZON and lock files
    var zon_file = try ZonFile.loadFromFile(allocator, "build.zig.zon");
    defer zon_file.deinit();

    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    var added: usize = 0;
    var updated: usize = 0;
    var orphaned: usize = 0;

    // Sync ZON -> Lock: Add or update entries from ZON
    var zon_it = zon_file.dependencies.iterator();
    while (zon_it.next()) |entry| {
        const pkg_name = entry.key_ptr.*;
        const dep = entry.value_ptr.*;

        const locked = lock_file.getPackage(pkg_name);
        if (locked) |existing| {
            // Check if needs update
            if (!std.mem.eql(u8, existing.url, dep.url) or
                !std.mem.eql(u8, existing.hash, dep.hash))
            {
                std.debug.print("  Updated: {s}\n", .{pkg_name});
                try lock_file.addPackage(pkg_name, dep.url, dep.hash, null);
                updated += 1;
            }
        } else {
            std.debug.print("  Added:   {s}\n", .{pkg_name});
            try lock_file.addPackage(pkg_name, dep.url, dep.hash, null);
            added += 1;
        }
    }

    // Check Lock -> ZON: Find orphaned entries
    for (lock_file.packages.items) |pkg| {
        if (zon_file.dependencies.get(pkg.name) == null) {
            std.debug.print("  Orphan:  {s} (not in build.zig.zon)\n", .{pkg.name});
            orphaned += 1;
        }
    }

    // Save if changes were made
    if (added > 0 or updated > 0) {
        try lock_file.saveToFile();
    }

    // Summary
    std.debug.print("\nSync Summary:\n", .{});
    std.debug.print("  Added:    {d}\n", .{added});
    std.debug.print("  Updated:  {d}\n", .{updated});
    std.debug.print("  Orphaned: {d}\n", .{orphaned});

    if (orphaned > 0) {
        std.debug.print("\nRun 'zion lock clean' to remove orphaned entries.\n", .{});
    }
    if (added == 0 and updated == 0 and orphaned == 0) {
        std.debug.print("\nLock file is in sync with build.zig.zon.\n", .{});
    }
}

/// Verify: Check integrity without modification
fn lockVerify(allocator: Allocator) !void {
    std.debug.print("Verifying lock file integrity...\n\n", .{});

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if build.zig.zon exists
    cwd.access(io, "build.zig.zon", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("build.zig.zon not found.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Check if lock file exists
    cwd.access(io, "zion.lock", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("zion.lock not found. Run 'zion lock' to create it.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Load both files
    var zon_file = try ZonFile.loadFromFile(allocator, "build.zig.zon");
    defer zon_file.deinit();

    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    var missing: usize = 0;
    var mismatch: usize = 0;
    var ok: usize = 0;

    // Verify each ZON dependency exists in lock with matching hash
    var it = zon_file.dependencies.iterator();
    while (it.next()) |entry| {
        const pkg_name = entry.key_ptr.*;
        const dep = entry.value_ptr.*;

        const locked = lock_file.getPackage(pkg_name);
        if (locked) |existing| {
            if (std.mem.eql(u8, existing.hash, dep.hash)) {
                std.debug.print("  OK:       {s}\n", .{pkg_name});
                ok += 1;
            } else {
                std.debug.print("  MISMATCH: {s}\n", .{pkg_name});
                std.debug.print("    ZON:  {s}...\n", .{dep.hash[0..@min(dep.hash.len, 30)]});
                std.debug.print("    Lock: {s}...\n", .{existing.hash[0..@min(existing.hash.len, 30)]});
                mismatch += 1;
            }
        } else {
            std.debug.print("  MISSING:  {s}\n", .{pkg_name});
            missing += 1;
        }
    }

    // Summary
    std.debug.print("\nVerification Summary:\n", .{});
    std.debug.print("  OK:       {d}\n", .{ok});
    std.debug.print("  Missing:  {d}\n", .{missing});
    std.debug.print("  Mismatch: {d}\n", .{mismatch});

    if (missing > 0 or mismatch > 0) {
        std.debug.print("\nRun 'zion lock sync' to fix discrepancies.\n", .{});
        return error.VerificationFailed;
    } else {
        std.debug.print("\nLock file integrity verified.\n", .{});
    }
}

/// Clean: Remove stale entries not in ZON
fn lockClean(allocator: Allocator) !void {
    std.debug.print("Cleaning stale lock file entries...\n\n", .{});

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if build.zig.zon exists
    cwd.access(io, "build.zig.zon", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("build.zig.zon not found.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Check if lock file exists
    cwd.access(io, "zion.lock", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("zion.lock not found. Nothing to clean.\n", .{});
            return;
        }
        return err;
    };

    // Load both files
    var zon_file = try ZonFile.loadFromFile(allocator, "build.zig.zon");
    defer zon_file.deinit();

    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    // Find packages to remove (by index, iterate backwards for safe removal)
    var removed_count: usize = 0;
    var i: usize = lock_file.packages.items.len;
    while (i > 0) {
        i -= 1;
        const pkg = lock_file.packages.items[i];
        if (zon_file.dependencies.get(pkg.name) == null) {
            std.debug.print("  Removing: {s}\n", .{pkg.name});
            // Free the package memory
            var pkg_mut = lock_file.packages.items[i];
            pkg_mut.deinit(allocator);
            _ = lock_file.packages.orderedRemove(i);
            removed_count += 1;
        }
    }

    if (removed_count == 0) {
        std.debug.print("No stale entries found. Lock file is clean.\n", .{});
        return;
    }

    // Save cleaned lock file
    try lock_file.saveToFile();

    std.debug.print("\nRemoved {d} stale entries from lock file.\n", .{removed_count});
}

fn printLockHelp() void {
    std.debug.print("Zion Lock File Management\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zion lock [SUBCOMMAND]\n\n", .{});
    std.debug.print("SUBCOMMANDS:\n", .{});
    std.debug.print("    (none)    Create or update lock file from build.zig.zon\n", .{});
    std.debug.print("    sync      Bidirectional sync between ZON and lock file\n", .{});
    std.debug.print("    verify    Check lock file integrity (read-only)\n", .{});
    std.debug.print("    clean     Remove stale entries not in build.zig.zon\n", .{});
    std.debug.print("    help      Show this help message\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zion lock              # Update lock file\n", .{});
    std.debug.print("    zion lock sync         # Sync ZON and lock file\n", .{});
    std.debug.print("    zion lock verify       # Verify integrity\n", .{});
    std.debug.print("    zion lock clean        # Remove orphaned entries\n", .{});
}
