//! Semantic Versioning (SemVer) implementation for Zion package manager.
//!
//! This module provides parsing, comparison, and constraint evaluation for
//! semantic versions following the SemVer 2.0.0 specification.
//!
//! Supported version formats:
//! - Standard: "1.2.3"
//! - With v prefix: "v1.2.3"
//! - With prerelease: "1.2.3-beta.1"
//! - With build metadata: "1.2.3+build.456"
//! - Full: "1.2.3-rc.1+build.789"
//!
//! Supported constraint formats:
//! - Exact: "1.2.3" or "=1.2.3"
//! - Caret: "^1.2.3" (compatible with 1.x.x)
//! - Tilde: "~1.2.3" (compatible with 1.2.x)
//! - Greater/Less: ">=1.0.0", ">1.0.0", "<=2.0.0", "<2.0.0"
//! - Any: "*" or "latest"

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Semantic version representation
pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
    prerelease: ?[]const u8 = null,
    build_metadata: ?[]const u8 = null,

    pub const ParseError = error{
        InvalidFormat,
        InvalidNumber,
        EmptyInput,
        InvalidPrerelease,
    };

    /// Parse a version string like "1.2.3", "v1.2.3", "1.2.3-beta.1", "1.2.3+build.456"
    pub fn parse(input: []const u8) ParseError!Version {
        if (input.len == 0) return ParseError.EmptyInput;

        // Strip leading 'v' or 'V'
        const version_str = if (input[0] == 'v' or input[0] == 'V')
            input[1..]
        else
            input;

        if (version_str.len == 0) return ParseError.EmptyInput;

        // Find build metadata separator (+)
        var core_and_pre: []const u8 = version_str;
        var build_metadata: ?[]const u8 = null;

        if (std.mem.indexOf(u8, version_str, "+")) |plus_idx| {
            core_and_pre = version_str[0..plus_idx];
            const meta = version_str[plus_idx + 1 ..];
            if (meta.len > 0) {
                build_metadata = meta;
            }
        }

        // Find prerelease separator (-)
        var core: []const u8 = core_and_pre;
        var prerelease: ?[]const u8 = null;

        if (std.mem.indexOf(u8, core_and_pre, "-")) |dash_idx| {
            core = core_and_pre[0..dash_idx];
            const pre = core_and_pre[dash_idx + 1 ..];
            if (pre.len > 0) {
                prerelease = pre;
            }
        }

        // Parse major.minor.patch
        var parts = std.mem.splitScalar(u8, core, '.');

        const major_str = parts.next() orelse return ParseError.InvalidFormat;
        const minor_str = parts.next() orelse return ParseError.InvalidFormat;
        const patch_str = parts.next() orelse "0"; // patch is optional for some formats

        // Check for extra parts (invalid)
        if (parts.next() != null) return ParseError.InvalidFormat;

        return Version{
            .major = std.fmt.parseInt(u32, major_str, 10) catch return ParseError.InvalidNumber,
            .minor = std.fmt.parseInt(u32, minor_str, 10) catch return ParseError.InvalidNumber,
            .patch = std.fmt.parseInt(u32, patch_str, 10) catch return ParseError.InvalidNumber,
            .prerelease = prerelease,
            .build_metadata = build_metadata,
        };
    }

    /// Compare two versions. Returns .lt, .eq, or .gt
    /// Build metadata is ignored in comparison per SemVer spec
    pub fn compare(self: Version, other: Version) std.math.Order {
        // Compare major
        if (self.major != other.major) {
            return std.math.order(self.major, other.major);
        }
        // Compare minor
        if (self.minor != other.minor) {
            return std.math.order(self.minor, other.minor);
        }
        // Compare patch
        if (self.patch != other.patch) {
            return std.math.order(self.patch, other.patch);
        }
        // Compare prerelease (no prerelease > prerelease per SemVer spec)
        return comparePrerelease(self.prerelease, other.prerelease);
    }

    /// Check if self is compatible with other (semver compatibility rules)
    /// For major version 0, compatibility is stricter (minor version must match)
    pub fn isCompatibleWith(self: Version, other: Version) bool {
        // Major version 0 - no compatibility guarantees, minor must match
        if (self.major == 0 or other.major == 0) {
            return self.major == other.major and self.minor == other.minor;
        }
        // Same major version = compatible
        return self.major == other.major;
    }

    /// Format version to string (caller owns returned memory)
    pub fn format(self: Version, allocator: Allocator) ![]const u8 {
        var result = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{
            self.major,
            self.minor,
            self.patch,
        });
        errdefer allocator.free(result);

        if (self.prerelease) |pre| {
            const new_result = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ result, pre });
            allocator.free(result);
            result = new_result;
        }

        if (self.build_metadata) |build| {
            const new_result = try std.fmt.allocPrint(allocator, "{s}+{s}", .{ result, build });
            allocator.free(result);
            result = new_result;
        }

        return result;
    }

    /// Check if this is a prerelease version
    pub fn isPrerelease(self: Version) bool {
        return self.prerelease != null;
    }

    /// Check if this is a stable version (not prerelease and major > 0)
    pub fn isStable(self: Version) bool {
        return self.major > 0 and self.prerelease == null;
    }

    /// Get the next major version (for caret constraint upper bound)
    pub fn nextMajor(self: Version) Version {
        return Version{
            .major = self.major + 1,
            .minor = 0,
            .patch = 0,
        };
    }

    /// Get the next minor version (for tilde constraint upper bound)
    pub fn nextMinor(self: Version) Version {
        return Version{
            .major = self.major,
            .minor = self.minor + 1,
            .patch = 0,
        };
    }
};

/// Version range/constraint representation
pub const VersionRange = struct {
    constraint_type: ConstraintType,
    version: Version,
    upper_bound: ?Version = null, // For range constraints like >=1.0 <2.0

    pub const ConstraintType = enum {
        exact, // =1.2.3 or 1.2.3
        caret, // ^1.2.3 (compatible with 1.x.x)
        tilde, // ~1.2.3 (compatible with 1.2.x)
        greater_eq, // >=1.2.3
        greater, // >1.2.3
        less_eq, // <=1.2.3
        less, // <1.2.3
        range, // >=1.0.0 <2.0.0
        any, // * or latest
    };

    pub const ParseError = error{
        InvalidConstraint,
        InvalidVersion,
        EmptyInput,
    };

    /// Parse constraint string
    pub fn parse(input: []const u8) ParseError!VersionRange {
        const trimmed = std.mem.trim(u8, input, " \t\n\r");
        if (trimmed.len == 0) return ParseError.EmptyInput;

        // Handle special cases
        if (std.mem.eql(u8, trimmed, "*") or
            std.mem.eql(u8, trimmed, "latest") or
            std.mem.eql(u8, trimmed, "any"))
        {
            return VersionRange{
                .constraint_type = .any,
                .version = Version{ .major = 0, .minor = 0, .patch = 0 },
            };
        }

        // Handle caret: ^1.2.3
        if (trimmed[0] == '^') {
            const ver = Version.parse(trimmed[1..]) catch return ParseError.InvalidVersion;
            return VersionRange{ .constraint_type = .caret, .version = ver };
        }

        // Handle tilde: ~1.2.3
        if (trimmed[0] == '~') {
            const ver = Version.parse(trimmed[1..]) catch return ParseError.InvalidVersion;
            return VersionRange{ .constraint_type = .tilde, .version = ver };
        }

        // Handle comparison operators (check longer operators first)
        if (std.mem.startsWith(u8, trimmed, ">=")) {
            const ver = Version.parse(std.mem.trim(u8, trimmed[2..], " ")) catch return ParseError.InvalidVersion;
            return VersionRange{ .constraint_type = .greater_eq, .version = ver };
        }
        if (std.mem.startsWith(u8, trimmed, "<=")) {
            const ver = Version.parse(std.mem.trim(u8, trimmed[2..], " ")) catch return ParseError.InvalidVersion;
            return VersionRange{ .constraint_type = .less_eq, .version = ver };
        }
        if (std.mem.startsWith(u8, trimmed, ">")) {
            const ver = Version.parse(std.mem.trim(u8, trimmed[1..], " ")) catch return ParseError.InvalidVersion;
            return VersionRange{ .constraint_type = .greater, .version = ver };
        }
        if (std.mem.startsWith(u8, trimmed, "<")) {
            const ver = Version.parse(std.mem.trim(u8, trimmed[1..], " ")) catch return ParseError.InvalidVersion;
            return VersionRange{ .constraint_type = .less, .version = ver };
        }
        if (std.mem.startsWith(u8, trimmed, "=")) {
            const ver = Version.parse(std.mem.trim(u8, trimmed[1..], " ")) catch return ParseError.InvalidVersion;
            return VersionRange{ .constraint_type = .exact, .version = ver };
        }

        // Default: exact version
        const ver = Version.parse(trimmed) catch return ParseError.InvalidVersion;
        return VersionRange{ .constraint_type = .exact, .version = ver };
    }

    /// Check if a version satisfies this constraint
    pub fn satisfiedBy(self: VersionRange, version: Version) bool {
        switch (self.constraint_type) {
            .any => return true,
            .exact => return version.compare(self.version) == .eq,
            .greater => return version.compare(self.version) == .gt,
            .greater_eq => return version.compare(self.version) != .lt,
            .less => return version.compare(self.version) == .lt,
            .less_eq => return version.compare(self.version) != .gt,
            .caret => return self.satisfiesCaret(version),
            .tilde => return self.satisfiesTilde(version),
            .range => return self.satisfiesRange(version),
        }
    }

    /// Caret constraint: ^1.2.3 means >=1.2.3 <2.0.0 (or stricter for 0.x versions)
    fn satisfiesCaret(self: VersionRange, version: Version) bool {
        // Must be >= constraint version
        if (version.compare(self.version) == .lt) return false;

        // Special handling for 0.x versions per npm semver conventions
        if (self.version.major == 0) {
            if (self.version.minor == 0) {
                // ^0.0.x means =0.0.x (exact patch)
                return version.major == 0 and version.minor == 0 and
                    version.patch == self.version.patch;
            }
            // ^0.x.y means >=0.x.y <0.(x+1).0
            return version.major == 0 and version.minor == self.version.minor;
        }

        // ^x.y.z means >=x.y.z <(x+1).0.0
        return version.major == self.version.major;
    }

    /// Tilde constraint: ~1.2.3 means >=1.2.3 <1.3.0
    fn satisfiesTilde(self: VersionRange, version: Version) bool {
        // Must be >= constraint version
        if (version.compare(self.version) == .lt) return false;

        // Must be same major and minor
        return version.major == self.version.major and
            version.minor == self.version.minor;
    }

    /// Range constraint: explicit upper and lower bounds
    fn satisfiesRange(self: VersionRange, version: Version) bool {
        if (version.compare(self.version) == .lt) return false;
        if (self.upper_bound) |upper| {
            if (version.compare(upper) != .lt) return false;
        }
        return true;
    }

    /// Get a human-readable description of this constraint
    pub fn describe(self: VersionRange, allocator: Allocator) ![]const u8 {
        const ver_str = try self.version.format(allocator);
        defer allocator.free(ver_str);

        return switch (self.constraint_type) {
            .any => try allocator.dupe(u8, "any version"),
            .exact => try std.fmt.allocPrint(allocator, "exactly {s}", .{ver_str}),
            .caret => try std.fmt.allocPrint(allocator, "^{s} (compatible with {d}.x.x)", .{ ver_str, self.version.major }),
            .tilde => try std.fmt.allocPrint(allocator, "~{s} (compatible with {d}.{d}.x)", .{ ver_str, self.version.major, self.version.minor }),
            .greater => try std.fmt.allocPrint(allocator, ">{s}", .{ver_str}),
            .greater_eq => try std.fmt.allocPrint(allocator, ">={s}", .{ver_str}),
            .less => try std.fmt.allocPrint(allocator, "<{s}", .{ver_str}),
            .less_eq => try std.fmt.allocPrint(allocator, "<={s}", .{ver_str}),
            .range => blk: {
                if (self.upper_bound) |upper| {
                    const upper_str = try upper.format(allocator);
                    defer allocator.free(upper_str);
                    break :blk try std.fmt.allocPrint(allocator, ">={s} <{s}", .{ ver_str, upper_str });
                }
                break :blk try std.fmt.allocPrint(allocator, ">={s}", .{ver_str});
            },
        };
    }

    /// Format constraint back to string (caller owns returned memory)
    pub fn format(self: VersionRange, allocator: Allocator) ![]const u8 {
        const ver_str = try self.version.format(allocator);
        defer allocator.free(ver_str);

        return switch (self.constraint_type) {
            .any => try allocator.dupe(u8, "*"),
            .exact => try allocator.dupe(u8, ver_str),
            .caret => try std.fmt.allocPrint(allocator, "^{s}", .{ver_str}),
            .tilde => try std.fmt.allocPrint(allocator, "~{s}", .{ver_str}),
            .greater => try std.fmt.allocPrint(allocator, ">{s}", .{ver_str}),
            .greater_eq => try std.fmt.allocPrint(allocator, ">={s}", .{ver_str}),
            .less => try std.fmt.allocPrint(allocator, "<{s}", .{ver_str}),
            .less_eq => try std.fmt.allocPrint(allocator, "<={s}", .{ver_str}),
            .range => blk: {
                if (self.upper_bound) |upper| {
                    const upper_str = try upper.format(allocator);
                    defer allocator.free(upper_str);
                    break :blk try std.fmt.allocPrint(allocator, ">={s} <{s}", .{ ver_str, upper_str });
                }
                break :blk try std.fmt.allocPrint(allocator, ">={s}", .{ver_str});
            },
        };
    }
};

/// Helper function for prerelease comparison
/// Per SemVer: no prerelease > prerelease, and prerelease identifiers are compared
fn comparePrerelease(a: ?[]const u8, b: ?[]const u8) std.math.Order {
    // Both null = equal
    if (a == null and b == null) return .eq;
    // No prerelease > prerelease (stable releases sort higher)
    if (a == null) return .gt;
    if (b == null) return .lt;
    // Both have prerelease - compare lexicographically
    return std.mem.order(u8, a.?, b.?);
}

/// Infer a default constraint from a version string
/// Returns "^version" for stable versions, exact for 0.x prereleases
pub fn inferConstraint(version_str: []const u8, allocator: Allocator) ![]const u8 {
    const version = Version.parse(version_str) catch {
        // If can't parse, return exact
        return try std.fmt.allocPrint(allocator, "{s}", .{version_str});
    };

    // For 0.x versions, use tilde (more conservative)
    if (version.major == 0) {
        return try std.fmt.allocPrint(allocator, "~{s}", .{version_str});
    }

    // For stable versions, use caret
    return try std.fmt.allocPrint(allocator, "^{s}", .{version_str});
}

// ============= Tests =============

test "Version.parse basic" {
    const v = try Version.parse("1.2.3");
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 2), v.minor);
    try std.testing.expectEqual(@as(u32, 3), v.patch);
    try std.testing.expect(v.prerelease == null);
    try std.testing.expect(v.build_metadata == null);
}

test "Version.parse with v prefix" {
    const v = try Version.parse("v1.2.3");
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 2), v.minor);
    try std.testing.expectEqual(@as(u32, 3), v.patch);
}

test "Version.parse with V prefix" {
    const v = try Version.parse("V10.20.30");
    try std.testing.expectEqual(@as(u32, 10), v.major);
    try std.testing.expectEqual(@as(u32, 20), v.minor);
    try std.testing.expectEqual(@as(u32, 30), v.patch);
}

test "Version.parse with prerelease" {
    const v = try Version.parse("1.2.3-beta.1");
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 2), v.minor);
    try std.testing.expectEqual(@as(u32, 3), v.patch);
    try std.testing.expectEqualStrings("beta.1", v.prerelease.?);
}

test "Version.parse with build metadata" {
    const v = try Version.parse("1.2.3+build.456");
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqualStrings("build.456", v.build_metadata.?);
}

test "Version.parse full format" {
    const v = try Version.parse("v1.2.3-rc.1+build.789");
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 2), v.minor);
    try std.testing.expectEqual(@as(u32, 3), v.patch);
    try std.testing.expectEqualStrings("rc.1", v.prerelease.?);
    try std.testing.expectEqualStrings("build.789", v.build_metadata.?);
}

test "Version.parse errors" {
    try std.testing.expectError(Version.ParseError.EmptyInput, Version.parse(""));
    try std.testing.expectError(Version.ParseError.EmptyInput, Version.parse("v"));
    try std.testing.expectError(Version.ParseError.InvalidFormat, Version.parse("1"));
    try std.testing.expectError(Version.ParseError.InvalidNumber, Version.parse("a.b.c"));
}

test "Version.compare equal" {
    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.3");
    try std.testing.expectEqual(std.math.Order.eq, v1.compare(v2));
}

test "Version.compare different patch" {
    const v1 = try Version.parse("1.2.3");
    const v2 = try Version.parse("1.2.4");
    try std.testing.expectEqual(std.math.Order.lt, v1.compare(v2));
    try std.testing.expectEqual(std.math.Order.gt, v2.compare(v1));
}

test "Version.compare different minor" {
    const v1 = try Version.parse("1.1.9");
    const v2 = try Version.parse("1.2.0");
    try std.testing.expectEqual(std.math.Order.lt, v1.compare(v2));
}

test "Version.compare different major" {
    const v1 = try Version.parse("1.9.9");
    const v2 = try Version.parse("2.0.0");
    try std.testing.expectEqual(std.math.Order.lt, v1.compare(v2));
}

test "Version.compare prerelease" {
    const stable = try Version.parse("1.0.0");
    const prerelease = try Version.parse("1.0.0-alpha");
    // Stable > prerelease
    try std.testing.expectEqual(std.math.Order.gt, stable.compare(prerelease));
    try std.testing.expectEqual(std.math.Order.lt, prerelease.compare(stable));
}

test "VersionRange.parse caret" {
    const range = try VersionRange.parse("^1.2.3");
    try std.testing.expectEqual(VersionRange.ConstraintType.caret, range.constraint_type);
    try std.testing.expectEqual(@as(u32, 1), range.version.major);
    try std.testing.expectEqual(@as(u32, 2), range.version.minor);
    try std.testing.expectEqual(@as(u32, 3), range.version.patch);
}

test "VersionRange.parse tilde" {
    const range = try VersionRange.parse("~1.2.3");
    try std.testing.expectEqual(VersionRange.ConstraintType.tilde, range.constraint_type);
}

test "VersionRange.parse comparison operators" {
    const ge = try VersionRange.parse(">=1.0.0");
    try std.testing.expectEqual(VersionRange.ConstraintType.greater_eq, ge.constraint_type);

    const gt = try VersionRange.parse(">1.0.0");
    try std.testing.expectEqual(VersionRange.ConstraintType.greater, gt.constraint_type);

    const le = try VersionRange.parse("<=2.0.0");
    try std.testing.expectEqual(VersionRange.ConstraintType.less_eq, le.constraint_type);

    const lt = try VersionRange.parse("<2.0.0");
    try std.testing.expectEqual(VersionRange.ConstraintType.less, lt.constraint_type);
}

test "VersionRange.parse any" {
    const any1 = try VersionRange.parse("*");
    try std.testing.expectEqual(VersionRange.ConstraintType.any, any1.constraint_type);

    const any2 = try VersionRange.parse("latest");
    try std.testing.expectEqual(VersionRange.ConstraintType.any, any2.constraint_type);
}

test "VersionRange.parse exact" {
    const exact1 = try VersionRange.parse("1.2.3");
    try std.testing.expectEqual(VersionRange.ConstraintType.exact, exact1.constraint_type);

    const exact2 = try VersionRange.parse("=1.2.3");
    try std.testing.expectEqual(VersionRange.ConstraintType.exact, exact2.constraint_type);
}

test "VersionRange.satisfiedBy caret standard" {
    const range = try VersionRange.parse("^1.2.3");

    // Should satisfy
    try std.testing.expect(range.satisfiedBy(try Version.parse("1.2.3")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("1.2.4")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("1.2.99")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("1.9.0")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("1.99.99")));

    // Should not satisfy
    try std.testing.expect(!range.satisfiedBy(try Version.parse("1.2.2")));
    try std.testing.expect(!range.satisfiedBy(try Version.parse("2.0.0")));
    try std.testing.expect(!range.satisfiedBy(try Version.parse("0.9.9")));
}

test "VersionRange.satisfiedBy caret 0.x" {
    const range = try VersionRange.parse("^0.2.3");

    // Should satisfy (only 0.2.x)
    try std.testing.expect(range.satisfiedBy(try Version.parse("0.2.3")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("0.2.4")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("0.2.99")));

    // Should not satisfy
    try std.testing.expect(!range.satisfiedBy(try Version.parse("0.2.2")));
    try std.testing.expect(!range.satisfiedBy(try Version.parse("0.3.0")));
    try std.testing.expect(!range.satisfiedBy(try Version.parse("1.0.0")));
}

test "VersionRange.satisfiedBy caret 0.0.x" {
    const range = try VersionRange.parse("^0.0.3");

    // Should satisfy (only exact 0.0.3)
    try std.testing.expect(range.satisfiedBy(try Version.parse("0.0.3")));

    // Should not satisfy
    try std.testing.expect(!range.satisfiedBy(try Version.parse("0.0.2")));
    try std.testing.expect(!range.satisfiedBy(try Version.parse("0.0.4")));
    try std.testing.expect(!range.satisfiedBy(try Version.parse("0.1.0")));
}

test "VersionRange.satisfiedBy tilde" {
    const range = try VersionRange.parse("~1.2.3");

    // Should satisfy (only 1.2.x >= 1.2.3)
    try std.testing.expect(range.satisfiedBy(try Version.parse("1.2.3")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("1.2.4")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("1.2.99")));

    // Should not satisfy
    try std.testing.expect(!range.satisfiedBy(try Version.parse("1.2.2")));
    try std.testing.expect(!range.satisfiedBy(try Version.parse("1.3.0")));
    try std.testing.expect(!range.satisfiedBy(try Version.parse("2.0.0")));
}

test "VersionRange.satisfiedBy greater/less" {
    const ge = try VersionRange.parse(">=1.0.0");
    try std.testing.expect(ge.satisfiedBy(try Version.parse("1.0.0")));
    try std.testing.expect(ge.satisfiedBy(try Version.parse("2.0.0")));
    try std.testing.expect(!ge.satisfiedBy(try Version.parse("0.9.9")));

    const gt = try VersionRange.parse(">1.0.0");
    try std.testing.expect(!gt.satisfiedBy(try Version.parse("1.0.0")));
    try std.testing.expect(gt.satisfiedBy(try Version.parse("1.0.1")));

    const le = try VersionRange.parse("<=2.0.0");
    try std.testing.expect(le.satisfiedBy(try Version.parse("2.0.0")));
    try std.testing.expect(le.satisfiedBy(try Version.parse("1.0.0")));
    try std.testing.expect(!le.satisfiedBy(try Version.parse("2.0.1")));

    const lt = try VersionRange.parse("<2.0.0");
    try std.testing.expect(!lt.satisfiedBy(try Version.parse("2.0.0")));
    try std.testing.expect(lt.satisfiedBy(try Version.parse("1.9.9")));
}

test "VersionRange.satisfiedBy any" {
    const range = try VersionRange.parse("*");
    try std.testing.expect(range.satisfiedBy(try Version.parse("0.0.1")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("1.0.0")));
    try std.testing.expect(range.satisfiedBy(try Version.parse("99.99.99")));
}
