const std = @import("std");
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;
const json = std.json;
const zion_root = @import("root.zig");

/// Policy file name
pub const POLICY_FILE = "zion.policy.json";

/// Policy version for migration support
pub const POLICY_VERSION: u32 = 1;

/// Result of a policy check
pub const PolicyResult = struct {
    allowed: bool,
    reason: ?[]const u8,
    severity: Severity,

    pub const Severity = enum {
        info,
        warning,
        @"error",
    };
};

/// Policy violation record
pub const Violation = struct {
    package: []const u8,
    url: ?[]const u8,
    reason: []const u8,
    severity: PolicyResult.Severity,
};

/// Policy engine for package trust management
pub const Policy = struct {
    allocator: Allocator,
    version: u32,
    allow_patterns: std.ArrayList([]const u8),
    deny_patterns: std.ArrayList([]const u8),
    require_hash: bool,
    require_signature: bool,
    max_transitive_depth: ?u32,
    allowed_licenses: ?std.ArrayList([]const u8),

    pub fn init(allocator: Allocator) Policy {
        return Policy{
            .allocator = allocator,
            .version = POLICY_VERSION,
            .allow_patterns = .empty,
            .deny_patterns = .empty,
            .require_hash = false,
            .require_signature = false,
            .max_transitive_depth = null,
            .allowed_licenses = null,
        };
    }

    pub fn deinit(self: *Policy) void {
        for (self.allow_patterns.items) |p| self.allocator.free(p);
        self.allow_patterns.deinit(self.allocator);

        for (self.deny_patterns.items) |p| self.allocator.free(p);
        self.deny_patterns.deinit(self.allocator);

        if (self.allowed_licenses) |*licenses| {
            for (licenses.items) |l| self.allocator.free(l);
            licenses.deinit(self.allocator);
        }
    }

    /// Load policy from file
    pub fn load(allocator: Allocator) !Policy {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        // Check if policy file exists
        cwd.access(io, POLICY_FILE, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Return default permissive policy
                return Policy.init(allocator);
            }
            return err;
        };

        // Read file
        const content = try cwd.readFileAlloc(io, POLICY_FILE, allocator, std.Io.Limit.limited(1024 * 1024));
        defer allocator.free(content);

        return try parsePolicy(allocator, content);
    }

    /// Parse policy from JSON content
    fn parsePolicy(allocator: Allocator, content: []const u8) !Policy {
        var policy = Policy.init(allocator);
        errdefer policy.deinit();

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch |err| {
            std.debug.print("Error parsing policy file: {}\n", .{err});
            return error.InvalidPolicy;
        };
        defer parsed.deinit();
        const root = parsed.value;

        if (root != .object) return error.InvalidPolicy;

        // Parse version
        if (root.object.get("version")) |v| {
            if (v == .integer) {
                policy.version = @intCast(v.integer);
            }
        }

        // Parse allow patterns
        if (root.object.get("allow")) |allow| {
            if (allow == .array) {
                for (allow.array.items) |item| {
                    if (item == .string) {
                        try policy.allow_patterns.append(allocator, try allocator.dupe(u8, item.string));
                    }
                }
            }
        }

        // Parse deny patterns
        if (root.object.get("deny")) |deny| {
            if (deny == .array) {
                for (deny.array.items) |item| {
                    if (item == .string) {
                        try policy.deny_patterns.append(allocator, try allocator.dupe(u8, item.string));
                    }
                }
            }
        }

        // Parse require_hash
        if (root.object.get("require_hash")) |rh| {
            if (rh == .bool) {
                policy.require_hash = rh.bool;
            }
        }

        // Parse require_signature
        if (root.object.get("require_signature")) |rs| {
            if (rs == .bool) {
                policy.require_signature = rs.bool;
            }
        }

        // Parse max_transitive_depth
        if (root.object.get("max_transitive_depth")) |mtd| {
            if (mtd == .integer) {
                policy.max_transitive_depth = @intCast(mtd.integer);
            }
        }

        // Parse allowed_licenses
        if (root.object.get("allowed_licenses")) |al| {
            if (al == .array) {
                policy.allowed_licenses = .empty;
                for (al.array.items) |item| {
                    if (item == .string) {
                        try policy.allowed_licenses.?.append(allocator, try allocator.dupe(u8, item.string));
                    }
                }
            }
        }

        return policy;
    }

    /// Check if a URL matches the policy
    pub fn checkUrl(self: *const Policy, url: []const u8) PolicyResult {
        // Check deny patterns first (deny takes precedence)
        for (self.deny_patterns.items) |pattern| {
            if (matchPattern(url, pattern)) {
                return .{
                    .allowed = false,
                    .reason = "URL matches deny pattern",
                    .severity = .@"error",
                };
            }
        }

        // If allow patterns exist, URL must match at least one
        if (self.allow_patterns.items.len > 0) {
            var matched = false;
            for (self.allow_patterns.items) |pattern| {
                if (matchPattern(url, pattern)) {
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                return .{
                    .allowed = false,
                    .reason = "URL does not match any allow pattern",
                    .severity = .@"error",
                };
            }
        }

        return .{
            .allowed = true,
            .reason = null,
            .severity = .info,
        };
    }

    /// Check if a package meets policy requirements
    pub fn checkPackage(self: *const Policy, name: []const u8, url: ?[]const u8, hash: ?[]const u8) PolicyResult {
        _ = name;

        // Check URL against allow/deny lists
        if (url) |u| {
            const url_result = self.checkUrl(u);
            if (!url_result.allowed) {
                return url_result;
            }
        }

        // Check hash requirement
        if (self.require_hash and (hash == null or hash.?.len == 0)) {
            return .{
                .allowed = false,
                .reason = "Package hash required by policy but not provided",
                .severity = .@"error",
            };
        }

        return .{
            .allowed = true,
            .reason = null,
            .severity = .info,
        };
    }

    /// Generate default policy content
    pub fn generateDefault(allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator,
            \\{{
            \\  "version": {d},
            \\  "allow": [
            \\    "github.com/*",
            \\    "gitlab.com/*",
            \\    "codeberg.org/*"
            \\  ],
            \\  "deny": [],
            \\  "require_hash": false,
            \\  "require_signature": false,
            \\  "max_transitive_depth": null,
            \\  "allowed_licenses": null
            \\}}
            \\
        , .{POLICY_VERSION});
    }

    /// Save policy to file
    pub fn saveToFile(self: *const Policy) !void {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        var file = try cwd.createFile(io, POLICY_FILE, .{ .truncate = true });
        defer file.close(io);

        // Write JSON manually for nice formatting
        try file.writeStreamingAll(io, "{\n");

        // Version
        const version_line = try std.fmt.allocPrint(self.allocator, "  \"version\": {d},\n", .{self.version});
        defer self.allocator.free(version_line);
        try file.writeStreamingAll(io, version_line);

        // Allow patterns
        try file.writeStreamingAll(io, "  \"allow\": [");
        for (self.allow_patterns.items, 0..) |pattern, i| {
            if (i > 0) try file.writeStreamingAll(io, ", ");
            const pattern_str = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{pattern});
            defer self.allocator.free(pattern_str);
            try file.writeStreamingAll(io, pattern_str);
        }
        try file.writeStreamingAll(io, "],\n");

        // Deny patterns
        try file.writeStreamingAll(io, "  \"deny\": [");
        for (self.deny_patterns.items, 0..) |pattern, i| {
            if (i > 0) try file.writeStreamingAll(io, ", ");
            const pattern_str = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{pattern});
            defer self.allocator.free(pattern_str);
            try file.writeStreamingAll(io, pattern_str);
        }
        try file.writeStreamingAll(io, "],\n");

        // Booleans
        const require_hash_str = try std.fmt.allocPrint(self.allocator, "  \"require_hash\": {},\n", .{self.require_hash});
        defer self.allocator.free(require_hash_str);
        try file.writeStreamingAll(io, require_hash_str);

        const require_sig_str = try std.fmt.allocPrint(self.allocator, "  \"require_signature\": {}\n", .{self.require_signature});
        defer self.allocator.free(require_sig_str);
        try file.writeStreamingAll(io, require_sig_str);

        try file.writeStreamingAll(io, "}\n");
    }
};

/// Match a URL against a pattern (supports * wildcard)
fn matchPattern(url: []const u8, pattern: []const u8) bool {
    // Simple wildcard matching
    // Pattern: "github.com/*" matches "github.com/anything/else"
    // Pattern: "github.com/owner/*" matches "github.com/owner/repo"

    if (std.mem.eql(u8, pattern, "*")) {
        return true;
    }

    // Check for wildcard
    if (std.mem.indexOf(u8, pattern, "*")) |wildcard_pos| {
        // Match prefix before wildcard
        const prefix = pattern[0..wildcard_pos];
        if (!std.mem.startsWith(u8, url, prefix)) {
            return false;
        }

        // If wildcard is at end, prefix match is sufficient
        if (wildcard_pos == pattern.len - 1) {
            return true;
        }

        // Match suffix after wildcard
        const suffix = pattern[wildcard_pos + 1 ..];
        return std.mem.endsWith(u8, url, suffix);
    }

    // Exact match or prefix match
    return std.mem.startsWith(u8, url, pattern);
}

test "pattern matching" {
    const testing = std.testing;

    // Wildcard at end
    try testing.expect(matchPattern("github.com/owner/repo", "github.com/*"));
    try testing.expect(matchPattern("github.com/owner/repo/archive", "github.com/*"));
    try testing.expect(!matchPattern("gitlab.com/owner/repo", "github.com/*"));

    // Specific owner wildcard
    try testing.expect(matchPattern("github.com/ghostkellz/zsync", "github.com/ghostkellz/*"));
    try testing.expect(!matchPattern("github.com/other/zsync", "github.com/ghostkellz/*"));

    // Full wildcard
    try testing.expect(matchPattern("anything", "*"));

    // Exact match
    try testing.expect(matchPattern("github.com/owner", "github.com/owner"));
    try testing.expect(!matchPattern("github.com/owner/repo", "github.com/owner"));
}
