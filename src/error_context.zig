const std = @import("std");
const Allocator = std.mem.Allocator;

/// Rich error context with actionable information
pub const ErrorContext = struct {
    allocator: Allocator,
    error_type: []const u8,
    message: []const u8,
    context: []const u8, // What was being attempted
    context_owned: bool = false, // Whether context was allocated and needs freeing
    registries_tried: std.ArrayList([]const u8),
    suggestions: std.ArrayList([]const u8),
    details: std.ArrayList([]const u8), // Additional context lines
    // Track which strings in suggestions/details are owned (allocated)
    owned_strings: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator) ErrorContext {
        return .{
            .allocator = allocator,
            .error_type = "",
            .message = "",
            .context = "",
            .context_owned = false,
            .registries_tried = .empty,
            .suggestions = .empty,
            .details = .empty,
            .owned_strings = .empty,
        };
    }

    pub fn deinit(self: *ErrorContext) void {
        // Free owned strings
        for (self.owned_strings.items) |s| {
            self.allocator.free(s);
        }
        self.owned_strings.deinit(self.allocator);

        // Free context if owned
        if (self.context_owned and self.context.len > 0) {
            self.allocator.free(self.context);
        }

        self.registries_tried.deinit(self.allocator);
        self.suggestions.deinit(self.allocator);
        self.details.deinit(self.allocator);
    }

    pub fn setError(self: *ErrorContext, err_type: []const u8, msg: []const u8) void {
        self.error_type = err_type;
        self.message = msg;
    }

    pub fn setContext(self: *ErrorContext, ctx: []const u8) void {
        self.context = ctx;
        self.context_owned = false;
    }

    /// Set context with an allocated string (will be freed on deinit)
    pub fn setContextOwned(self: *ErrorContext, ctx: []const u8) void {
        self.context = ctx;
        self.context_owned = true;
    }

    pub fn addRegistryTried(self: *ErrorContext, registry: []const u8) !void {
        try self.registries_tried.append(self.allocator, registry);
    }

    pub fn addSuggestion(self: *ErrorContext, suggestion: []const u8) !void {
        try self.suggestions.append(self.allocator, suggestion);
    }

    /// Add a suggestion that was allocated (will be freed on deinit)
    pub fn addSuggestionOwned(self: *ErrorContext, suggestion: []const u8) !void {
        try self.suggestions.append(self.allocator, suggestion);
        try self.owned_strings.append(self.allocator, suggestion);
    }

    pub fn addDetail(self: *ErrorContext, detail: []const u8) !void {
        try self.details.append(self.allocator, detail);
    }

    /// Add a detail that was allocated (will be freed on deinit)
    pub fn addDetailOwned(self: *ErrorContext, detail: []const u8) !void {
        try self.details.append(self.allocator, detail);
        try self.owned_strings.append(self.allocator, detail);
    }

    /// Format the error for display
    pub fn format(self: *const ErrorContext, writer: anytype) !void {
        // Main error line
        try writer.print("\n❌ {s}\n", .{self.message});

        // Context
        if (self.context.len > 0) {
            try writer.print("   Context: {s}\n", .{self.context});
        }

        // Error type
        if (self.error_type.len > 0) {
            try writer.print("   Error: {s}\n", .{self.error_type});
        }

        // Details
        for (self.details.items) |detail| {
            try writer.print("   • {s}\n", .{detail});
        }

        // Registries tried
        if (self.registries_tried.items.len > 0) {
            try writer.print("\n   Registries checked:\n", .{});
            for (self.registries_tried.items) |registry| {
                try writer.print("   • {s}\n", .{registry});
            }
        }

        // Suggestions
        if (self.suggestions.items.len > 0) {
            try writer.print("\n   Suggestions:\n", .{});
            for (self.suggestions.items) |suggestion| {
                try writer.print("   → {s}\n", .{suggestion});
            }
        }

        try writer.print("\n", .{});
    }

    /// Print to stderr
    pub fn print(self: *const ErrorContext) void {
        const stderr = std.io.getStdErr().writer();
        self.format(stderr) catch {};
    }
};

/// Calculate Levenshtein distance between two strings
pub fn levenshteinDistance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    // Use two rows instead of full matrix for space efficiency
    var prev_row: [256]usize = undefined;
    var curr_row: [256]usize = undefined;

    const m = @min(a.len, 255);
    const n = @min(b.len, 255);

    // Initialize first row
    for (0..n + 1) |j| {
        prev_row[j] = j;
    }

    // Fill in the rest
    for (0..m) |i| {
        curr_row[0] = i + 1;

        for (0..n) |j| {
            const cost: usize = if (a[i] == b[j]) 0 else 1;
            curr_row[j + 1] = @min(
                @min(
                    curr_row[j] + 1, // insertion
                    prev_row[j + 1] + 1, // deletion
                ),
                prev_row[j] + cost, // substitution
            );
        }

        // Swap rows
        const temp = prev_row;
        prev_row = curr_row;
        curr_row = temp;
    }

    return prev_row[n];
}

/// Find similar strings from a list of candidates
pub fn findSimilar(
    allocator: Allocator,
    input: []const u8,
    candidates: []const []const u8,
    max_results: usize,
    max_distance: usize,
) ![][]const u8 {
    const ScoredCandidate = struct {
        text: []const u8,
        distance: usize,
    };

    var scored: std.ArrayList(ScoredCandidate) = .empty;
    defer scored.deinit(allocator);

    // Score all candidates
    for (candidates) |candidate| {
        const distance = levenshteinDistance(input, candidate);
        if (distance <= max_distance) {
            try scored.append(allocator, .{ .text = candidate, .distance = distance });
        }
    }

    // Sort by distance
    std.mem.sort(ScoredCandidate, scored.items, {}, struct {
        fn lessThan(_: void, a: ScoredCandidate, b: ScoredCandidate) bool {
            return a.distance < b.distance;
        }
    }.lessThan);

    // Return top results
    const count = @min(scored.items.len, max_results);
    var result = try allocator.alloc([]const u8, count);
    for (0..count) |i| {
        result[i] = scored.items[i].text;
    }

    return result;
}

/// Create "Did you mean...?" suggestions for a package name
pub fn createPackageSuggestions(
    allocator: Allocator,
    input: []const u8,
    known_packages: []const []const u8,
) ![][]const u8 {
    return findSimilar(allocator, input, known_packages, 3, 3);
}

/// Error builder for common error scenarios
pub const ErrorBuilder = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ErrorBuilder {
        return .{ .allocator = allocator };
    }

    /// Package not found error with suggestions
    pub fn packageNotFound(
        self: ErrorBuilder,
        package_name: []const u8,
        registries: []const []const u8,
        similar: []const []const u8,
    ) !ErrorContext {
        var ctx = ErrorContext.init(self.allocator);

        ctx.setError("PackageNotFound", "Package not found in any registry");
        ctx.setContextOwned(try std.fmt.allocPrint(
            self.allocator,
            "Searching for package '{s}'",
            .{package_name},
        ));

        for (registries) |registry| {
            try ctx.addRegistryTried(registry);
        }

        for (similar) |name| {
            try ctx.addSuggestionOwned(try std.fmt.allocPrint(
                self.allocator,
                "Did you mean '{s}'?",
                .{name},
            ));
        }

        try ctx.addSuggestion("Check the package name spelling");
        try ctx.addSuggestion("Try: zion search <partial-name>");

        return ctx;
    }

    /// Network error with retry info
    pub fn networkError(
        self: ErrorBuilder,
        operation: []const u8,
        registry: []const u8,
        err_msg: []const u8,
    ) !ErrorContext {
        var ctx = ErrorContext.init(self.allocator);

        ctx.setError("NetworkError", err_msg);
        ctx.setContextOwned(try std.fmt.allocPrint(
            self.allocator,
            "Attempting {s} from {s}",
            .{ operation, registry },
        ));

        try ctx.addRegistryTried(registry);
        try ctx.addSuggestion("Check your internet connection");
        try ctx.addSuggestion("Try again in a few moments");
        try ctx.addSuggestion("Check if the registry is available: zion registry health");

        return ctx;
    }

    /// Version constraint error
    pub fn invalidVersionConstraint(
        self: ErrorBuilder,
        constraint: []const u8,
    ) !ErrorContext {
        var ctx = ErrorContext.init(self.allocator);

        ctx.setError("InvalidVersionConstraint", "Could not parse version constraint");
        ctx.setContextOwned(try std.fmt.allocPrint(
            self.allocator,
            "Parsing constraint: {s}",
            .{constraint},
        ));

        try ctx.addDetail("Valid formats:");
        try ctx.addDetail("  1.2.3      - Exact version");
        try ctx.addDetail("  ^1.2.3     - Compatible with 1.x.x");
        try ctx.addDetail("  ~1.2.3     - Compatible with 1.2.x");
        try ctx.addDetail("  >=1.0,<2.0 - Range");
        try ctx.addSuggestion("Check the version constraint syntax");

        return ctx;
    }

    /// Hash mismatch error
    pub fn hashMismatch(
        self: ErrorBuilder,
        package_name: []const u8,
        expected: []const u8,
        actual: []const u8,
    ) !ErrorContext {
        var ctx = ErrorContext.init(self.allocator);

        ctx.setError("HashMismatch", "Package integrity check failed");
        ctx.setContextOwned(try std.fmt.allocPrint(
            self.allocator,
            "Verifying package '{s}'",
            .{package_name},
        ));

        try ctx.addDetailOwned(try std.fmt.allocPrint(
            self.allocator,
            "Expected: {s}",
            .{expected},
        ));
        try ctx.addDetailOwned(try std.fmt.allocPrint(
            self.allocator,
            "Got:      {s}",
            .{actual},
        ));
        try ctx.addSuggestion("The package may have been modified or corrupted");
        try ctx.addSuggestionOwned(try std.fmt.allocPrint(
            self.allocator,
            "Try: zion hash update {s}",
            .{package_name},
        ));
        try ctx.addSuggestion("Or clear cache: zion clean --cache");

        return ctx;
    }

    /// Circular dependency error
    pub fn circularDependency(
        self: ErrorBuilder,
        cycle_path: []const []const u8,
    ) !ErrorContext {
        var ctx = ErrorContext.init(self.allocator);

        ctx.setError("CircularDependency", "Circular dependency detected");

        // Build cycle path string
        var path_str: std.ArrayList(u8) = .empty;
        errdefer path_str.deinit(self.allocator);

        for (cycle_path, 0..) |pkg, i| {
            try path_str.appendSlice(self.allocator, pkg);
            if (i < cycle_path.len - 1) {
                try path_str.appendSlice(self.allocator, " -> ");
            }
        }
        // Add first package again to show the cycle
        if (cycle_path.len > 0) {
            try path_str.appendSlice(self.allocator, " -> ");
            try path_str.appendSlice(self.allocator, cycle_path[0]);
        }

        // Transfer ownership to context
        ctx.setContextOwned(try path_str.toOwnedSlice(self.allocator));

        try ctx.addSuggestion("Review your dependency graph: zion tree");
        try ctx.addSuggestion("Remove or refactor one of the cyclic dependencies");

        return ctx;
    }
};

// Tests
test "levenshtein distance" {
    try std.testing.expectEqual(@as(usize, 0), levenshteinDistance("test", "test"));
    try std.testing.expectEqual(@as(usize, 1), levenshteinDistance("test", "text"));
    try std.testing.expectEqual(@as(usize, 3), levenshteinDistance("kitten", "sitting"));
}

test "find similar strings" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "libxev", "libxml", "libpng", "httpz" };
    const similar = try findSimilar(allocator, "libxe", &candidates, 3, 3);
    defer allocator.free(similar);

    try std.testing.expect(similar.len > 0);
    try std.testing.expectEqualStrings("libxev", similar[0]);
}
