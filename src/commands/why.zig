const std = @import("std");
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const zion_root = @import("../root.zig");

/// Explain why a package is in the dependency tree
pub fn why(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        std.debug.print("Usage: zion why <package>\n\n", .{});
        std.debug.print("Shows why a package is in your dependency tree.\n", .{});
        std.debug.print("Traces the dependency chain from direct dependencies to the target package.\n", .{});
        return;
    }

    const target_package = args[2];

    // Load manifest
    const zon_path = "build.zig.zon";
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    cwd.access(io, zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("build.zig.zon not found. Run 'zion init' first.\n", .{});
            return;
        }
        return err;
    };

    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();

    // Load lockfile for transitive dependency information
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    std.debug.print("\nWhy is '{s}' in your dependencies?\n", .{target_package});
    std.debug.print("----------------------------------------\n\n", .{});

    // Check if it's a direct dependency
    if (zon_file.dependencies.contains(target_package)) {
        std.debug.print("{s}\n", .{zon_file.name});
        std.debug.print("  {s} (direct dependency in build.zig.zon)\n", .{target_package});

        // Show info from lockfile if available
        if (lock_file.getPackage(target_package)) |pkg| {
            std.debug.print("\nPackage details:\n", .{});
            if (pkg.version) |v| {
                std.debug.print("  Version: {s}\n", .{v});
            }
            if (pkg.registry) |r| {
                std.debug.print("  Registry: {s}\n", .{r});
            }
            if (pkg.resolved_from) |rf| {
                std.debug.print("  Source: {s}\n", .{rf});
            }
        }
        return;
    }

    // Check if it exists in the lockfile as a transitive dependency
    const target_pkg = lock_file.getPackage(target_package);
    if (target_pkg == null) {
        std.debug.print("Package '{s}' not found in dependency tree.\n", .{target_package});
        std.debug.print("\nDid you mean one of these?\n", .{});

        // Suggest similar packages
        var count: usize = 0;
        for (lock_file.packages.items) |pkg| {
            if (fuzzyMatch(pkg.name, target_package)) {
                std.debug.print("  - {s}\n", .{pkg.name});
                count += 1;
                if (count >= 5) break;
            }
        }

        if (count == 0) {
            // Show all packages if no fuzzy matches
            std.debug.print("\nAvailable packages:\n", .{});
            for (lock_file.packages.items, 0..) |pkg, i| {
                std.debug.print("  - {s}\n", .{pkg.name});
                if (i >= 9) {
                    std.debug.print("  ... and {d} more\n", .{lock_file.packages.items.len - 10});
                    break;
                }
            }
        }
        return;
    }

    // Find dependency chains leading to this package
    var chains: std.ArrayList(DependencyChain) = .empty;
    defer {
        for (chains.items) |*chain| chain.deinit(allocator);
        chains.deinit(allocator);
    }

    // Build reverse dependency map: package -> list of packages that depend on it
    var reverse_deps = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var it = reverse_deps.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        reverse_deps.deinit();
    }

    for (lock_file.packages.items) |pkg| {
        if (pkg.dependencies) |deps| {
            for (deps) |dep| {
                var list = reverse_deps.get(dep) orelse std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
                try list.append(allocator, pkg.name);
                try reverse_deps.put(dep, list);
            }
        }
    }

    // Also add direct dependencies from manifest
    var manifest_it = zon_file.dependencies.iterator();
    while (manifest_it.next()) |entry| {
        var list = reverse_deps.get(entry.key_ptr.*) orelse std.ArrayList([]const u8){ .items = &.{}, .capacity = 0 };
        try list.append(allocator, zon_file.name);
        try reverse_deps.put(entry.key_ptr.*, list);
    }

    // Trace paths from target back to root
    try findChains(allocator, target_package, zon_file.name, &reverse_deps, &chains);

    if (chains.items.len == 0) {
        // Check if it's an orphaned lockfile entry
        std.debug.print("'{s}' is in the lockfile but no dependency chain was found.\n", .{target_package});
        std.debug.print("It may be an orphaned entry. Run 'zion check' to verify.\n", .{});
        return;
    }

    // Display chains
    std.debug.print("Dependency chain(s):\n\n", .{});

    for (chains.items, 0..) |chain, i| {
        if (i > 0) std.debug.print("\n", .{});

        // Print chain from root to target
        for (chain.path.items, 0..) |node, depth| {
            // Indentation
            for (0..depth) |_| {
                std.debug.print("  ", .{});
            }

            if (depth == 0) {
                std.debug.print("{s} (your project)\n", .{node});
            } else if (depth == chain.path.items.len - 1) {
                std.debug.print("{s} (target)\n", .{node});
            } else {
                // Check if this is a direct dependency
                const is_direct = zon_file.dependencies.contains(node);
                if (is_direct) {
                    std.debug.print("{s} (direct)\n", .{node});
                } else {
                    std.debug.print("{s}\n", .{node});
                }
            }
        }
    }

    // Show package details
    if (target_pkg) |pkg| {
        std.debug.print("\n----------------------------------------\n", .{});
        std.debug.print("Package details:\n", .{});
        if (pkg.version) |v| {
            std.debug.print("  Version: {s}\n", .{v});
        }
        if (pkg.registry) |r| {
            std.debug.print("  Registry: {s}\n", .{r});
        }
        if (pkg.dependencies) |deps| {
            std.debug.print("  Dependencies: {d}\n", .{deps.len});
        }
    }
}

const DependencyChain = struct {
    path: std.ArrayList([]const u8),

    pub fn deinit(self: *DependencyChain, allocator: Allocator) void {
        for (self.path.items) |item| {
            allocator.free(item);
        }
        self.path.deinit(allocator);
    }
};

/// Find all chains from target to root using BFS
fn findChains(
    allocator: Allocator,
    target: []const u8,
    root: []const u8,
    reverse_deps: *std.StringHashMap(std.ArrayList([]const u8)),
    chains: *std.ArrayList(DependencyChain),
) !void {
    // BFS queue: each entry is a partial path from target toward root
    var queue: std.ArrayList(std.ArrayList([]const u8)) = .empty;
    defer {
        for (queue.items) |*path| path.deinit(allocator);
        queue.deinit(allocator);
    }

    // Start with target
    var initial_path: std.ArrayList([]const u8) = .empty;
    try initial_path.append(allocator, try allocator.dupe(u8, target));
    try queue.append(allocator, initial_path);

    var max_iterations: usize = 1000; // Prevent infinite loops
    while (queue.items.len > 0 and max_iterations > 0) {
        max_iterations -= 1;

        var current_path = queue.orderedRemove(0);

        const current_node = current_path.items[current_path.items.len - 1];

        // Check if we reached the root
        if (std.mem.eql(u8, current_node, root)) {
            // Reverse the path to go from root to target
            var chain = DependencyChain{ .path = .empty };
            var i: usize = current_path.items.len;
            while (i > 0) {
                i -= 1;
                try chain.path.append(allocator, try allocator.dupe(u8, current_path.items[i]));
            }
            try chains.append(allocator, chain);

            // Clean up current path
            for (current_path.items) |item| allocator.free(item);
            current_path.deinit(allocator);

            // Limit number of chains to show
            if (chains.items.len >= 5) break;
            continue;
        }

        // Find parents of current node
        if (reverse_deps.get(current_node)) |parents| {
            for (parents.items) |parent| {
                // Avoid cycles
                var is_in_path = false;
                for (current_path.items) |node| {
                    if (std.mem.eql(u8, node, parent)) {
                        is_in_path = true;
                        break;
                    }
                }

                if (!is_in_path) {
                    // Clone path and extend
                    var new_path: std.ArrayList([]const u8) = .empty;
                    for (current_path.items) |node| {
                        try new_path.append(allocator, try allocator.dupe(u8, node));
                    }
                    try new_path.append(allocator, try allocator.dupe(u8, parent));
                    try queue.append(allocator, new_path);
                }
            }
        }

        // Clean up current path
        for (current_path.items) |item| allocator.free(item);
        current_path.deinit(allocator);
    }
}

/// Simple fuzzy matching for package names
fn fuzzyMatch(name: []const u8, query: []const u8) bool {
    // Check if query is a substring
    if (std.mem.indexOf(u8, name, query) != null) return true;

    // Check if name starts with query
    if (std.mem.startsWith(u8, name, query)) return true;

    // Check if query starts with name (typo where user added extra chars)
    if (std.mem.startsWith(u8, query, name)) return true;

    // Simple Levenshtein-like: check if most characters match
    if (name.len > 3 and query.len > 3) {
        var matches: usize = 0;
        const min_len = @min(name.len, query.len);
        for (0..min_len) |i| {
            if (name[i] == query[i]) matches += 1;
        }
        if (matches >= min_len / 2) return true;
    }

    return false;
}
