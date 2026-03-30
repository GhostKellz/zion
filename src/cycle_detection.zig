const std = @import("std");
const Allocator = std.mem.Allocator;

/// Dependency information for cycle detection
pub const DependencyInfo = struct {
    name: []const u8,
    url: ?[]const u8 = null,
    dependencies: []const DependencyInfo = &.{},
};

/// Cycle detection result
pub const CycleResult = struct {
    has_cycle: bool,
    cycle_path: []const []const u8,

    pub fn deinit(self: *CycleResult, allocator: Allocator) void {
        if (self.cycle_path.len > 0) {
            allocator.free(self.cycle_path);
        }
    }
};

/// Graph-based cycle detector using DFS
pub const CycleDetector = struct {
    allocator: Allocator,
    visited: std.StringHashMap(void),
    recursion_stack: std.StringHashMap(void),
    cycle_path: std.ArrayList([]const u8),
    found_cycle: bool = false,

    pub fn init(allocator: Allocator) CycleDetector {
        return .{
            .allocator = allocator,
            .visited = std.StringHashMap(void).init(allocator),
            .recursion_stack = std.StringHashMap(void).init(allocator),
            .cycle_path = .empty,
        };
    }

    pub fn deinit(self: *CycleDetector) void {
        self.visited.deinit();
        self.recursion_stack.deinit();
        self.cycle_path.deinit(self.allocator);
    }

    /// Reset detector state for reuse
    pub fn reset(self: *CycleDetector) void {
        self.visited.clearRetainingCapacity();
        self.recursion_stack.clearRetainingCapacity();
        self.cycle_path.clearRetainingCapacity();
        self.found_cycle = false;
    }

    /// Detect cycles in dependency graph
    /// Returns the cycle path if found, null otherwise
    pub fn detectCycle(
        self: *CycleDetector,
        root_name: []const u8,
        deps: []const DependencyInfo,
    ) !?[]const []const u8 {
        self.reset();
        _ = try self.dfs(root_name, deps);

        if (self.found_cycle) {
            // Return a copy of the cycle path
            const path = try self.allocator.alloc([]const u8, self.cycle_path.items.len);
            @memcpy(path, self.cycle_path.items);
            return path;
        }
        return null;
    }

    /// Check if adding a dependency would create a cycle
    pub fn wouldCreateCycle(
        self: *CycleDetector,
        current_package: []const u8,
        new_dependency: []const u8,
        existing_deps: []const DependencyInfo,
    ) !bool {
        // First, check if the new dependency is the same as the current package
        if (std.mem.eql(u8, current_package, new_dependency)) {
            try self.cycle_path.append(self.allocator, current_package);
            try self.cycle_path.append(self.allocator, new_dependency);
            return true;
        }

        // Check if new_dependency depends (transitively) on current_package
        self.reset();
        try self.recursion_stack.put(current_package, {});
        try self.cycle_path.append(self.allocator, current_package);

        // Find the new dependency in existing deps and check its dependencies
        for (existing_deps) |dep| {
            if (std.mem.eql(u8, dep.name, new_dependency)) {
                if (try self.dfs(new_dependency, dep.dependencies)) {
                    return true;
                }
                break;
            }
        }

        return false;
    }

    fn dfs(self: *CycleDetector, pkg_name: []const u8, deps: []const DependencyInfo) !bool {
        // Check if we've found a cycle
        if (self.recursion_stack.contains(pkg_name)) {
            // Build the cycle path from current point
            try self.cycle_path.append(self.allocator, pkg_name);
            self.found_cycle = true;
            return true;
        }

        // Skip if already visited completely
        if (self.visited.contains(pkg_name)) {
            return false;
        }

        // Mark as being processed
        try self.recursion_stack.put(pkg_name, {});
        try self.cycle_path.append(self.allocator, pkg_name);

        // Visit all dependencies
        for (deps) |dep| {
            if (try self.dfs(dep.name, dep.dependencies)) {
                return true;
            }
        }

        // Mark as fully processed
        _ = self.recursion_stack.remove(pkg_name);
        try self.visited.put(pkg_name, {});
        _ = self.cycle_path.pop();

        return false;
    }
};

/// Format cycle path as a human-readable string
pub fn formatCyclePath(allocator: Allocator, path: []const []const u8) ![]const u8 {
    if (path.len == 0) return "";

    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    for (path, 0..) |pkg, i| {
        try result.appendSlice(allocator, pkg);
        if (i < path.len - 1) {
            try result.appendSlice(allocator, " -> ");
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Simple adjacency list graph for dependency analysis
pub const DependencyGraph = struct {
    allocator: Allocator,
    edges: std.StringHashMap(std.ArrayList([]const u8)),
    all_nodes: std.StringHashMap(void),

    pub fn init(allocator: Allocator) DependencyGraph {
        return .{
            .allocator = allocator,
            .edges = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
            .all_nodes = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *DependencyGraph) void {
        var it = self.edges.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.allocator);
        }
        self.edges.deinit();
        self.all_nodes.deinit();
    }

    /// Add a dependency relationship
    pub fn addEdge(self: *DependencyGraph, from: []const u8, to: []const u8) !void {
        try self.all_nodes.put(from, {});
        try self.all_nodes.put(to, {});

        const result = try self.edges.getOrPut(from);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).empty;
        }
        try result.value_ptr.append(self.allocator, to);
    }

    /// Find all cycles in the graph
    pub fn findAllCycles(self: *DependencyGraph) ![]const []const []const u8 {
        var cycles: std.ArrayList([]const []const u8) = .empty;
        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        var rec_stack = std.StringHashMap(void).init(self.allocator);
        defer rec_stack.deinit();

        var path: std.ArrayList([]const u8) = .empty;
        defer path.deinit(self.allocator);

        var node_it = self.all_nodes.keyIterator();
        while (node_it.next()) |node| {
            if (!visited.contains(node.*)) {
                try self.findCyclesDFS(node.*, &visited, &rec_stack, &path, &cycles);
            }
        }

        return cycles.toOwnedSlice(self.allocator);
    }

    fn findCyclesDFS(
        self: *DependencyGraph,
        node: []const u8,
        visited: *std.StringHashMap(void),
        rec_stack: *std.StringHashMap(void),
        path: *std.ArrayList([]const u8),
        cycles: *std.ArrayList([]const []const u8),
    ) !void {
        try visited.put(node, {});
        try rec_stack.put(node, {});
        try path.append(self.allocator, node);

        if (self.edges.get(node)) |neighbors| {
            for (neighbors.items) |neighbor| {
                if (!visited.contains(neighbor)) {
                    try self.findCyclesDFS(neighbor, visited, rec_stack, path, cycles);
                } else if (rec_stack.contains(neighbor)) {
                    // Found a cycle - extract it
                    var cycle_start: usize = 0;
                    for (path.items, 0..) |p, i| {
                        if (std.mem.eql(u8, p, neighbor)) {
                            cycle_start = i;
                            break;
                        }
                    }

                    const cycle_len = path.items.len - cycle_start + 1;
                    const cycle = try self.allocator.alloc([]const u8, cycle_len);
                    for (cycle_start..path.items.len) |i| {
                        cycle[i - cycle_start] = path.items[i];
                    }
                    cycle[cycle_len - 1] = neighbor; // Complete the cycle
                    try cycles.append(self.allocator, cycle);
                }
            }
        }

        _ = rec_stack.remove(node);
        _ = path.pop();
    }

    /// Get dependency depth (longest path from root)
    pub fn getDepth(self: *DependencyGraph, root: []const u8) usize {
        var visited = std.StringHashMap(usize).init(self.allocator);
        defer visited.deinit();

        return self.getDepthDFS(root, &visited);
    }

    fn getDepthDFS(self: *DependencyGraph, node: []const u8, visited: *std.StringHashMap(usize)) usize {
        if (visited.get(node)) |depth| {
            return depth;
        }

        var max_child_depth: usize = 0;
        if (self.edges.get(node)) |neighbors| {
            for (neighbors.items) |neighbor| {
                const child_depth = self.getDepthDFS(neighbor, visited);
                max_child_depth = @max(max_child_depth, child_depth + 1);
            }
        }

        visited.put(node, max_child_depth) catch {};
        return max_child_depth;
    }
};

/// Print cycle warning message
pub fn printCycleWarning(cycle_path: []const []const u8) void {
    const stderr = std.io.getStdErr().writer();

    stderr.print("\n⚠️  Circular dependency detected!\n\n", .{}) catch {};
    stderr.print("   Cycle: ", .{}) catch {};

    for (cycle_path, 0..) |pkg, i| {
        stderr.print("{s}", .{pkg}) catch {};
        if (i < cycle_path.len - 1) {
            stderr.print(" -> ", .{}) catch {};
        }
    }

    stderr.print("\n\n", .{}) catch {};
    stderr.print("   This may cause build issues or infinite loops.\n", .{}) catch {};
    stderr.print("   Consider refactoring to break the dependency cycle.\n\n", .{}) catch {};
}

// Tests
test "simple cycle detection" {
    const allocator = std.testing.allocator;
    var detector = CycleDetector.init(allocator);
    defer detector.deinit();

    // A -> B -> C -> A (cycle)
    const deps_c = [_]DependencyInfo{.{ .name = "A" }};
    const deps_b = [_]DependencyInfo{.{ .name = "C", .dependencies = &deps_c }};
    const deps_a = [_]DependencyInfo{.{ .name = "B", .dependencies = &deps_b }};

    const result = try detector.detectCycle("A", &deps_a);
    try std.testing.expect(result != null);
    allocator.free(result.?);
}

test "no cycle detection" {
    const allocator = std.testing.allocator;
    var detector = CycleDetector.init(allocator);
    defer detector.deinit();

    // A -> B -> C (no cycle)
    const deps_c = [_]DependencyInfo{};
    const deps_b = [_]DependencyInfo{.{ .name = "C", .dependencies = &deps_c }};
    const deps_a = [_]DependencyInfo{.{ .name = "B", .dependencies = &deps_b }};

    const result = try detector.detectCycle("A", &deps_a);
    try std.testing.expect(result == null);
}

test "format cycle path" {
    const allocator = std.testing.allocator;
    const path = [_][]const u8{ "A", "B", "C", "A" };
    const formatted = try formatCyclePath(allocator, &path);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("A -> B -> C -> A", formatted);
}
