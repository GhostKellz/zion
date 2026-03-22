//! Version constraint resolution for Zion package manager.
//!
//! This module resolves version constraints (like "^1.0.0") to concrete versions
//! by fetching available versions from registries and finding the best match.

const std = @import("std");
const Allocator = std.mem.Allocator;
const semver = @import("semver.zig");
const github = @import("github.zig");

pub const VersionResolver = struct {
    allocator: Allocator,

    /// Result of version resolution
    pub const ResolutionResult = struct {
        /// The resolved semantic version
        resolved_version: semver.Version,
        /// The version string as it appears in the registry (e.g., "v1.2.3")
        version_string: []const u8,
        /// URL to download the package
        url: []const u8,
        /// Whether this is a prerelease version
        is_prerelease: bool,
        /// Whether this is from a tag (vs release)
        is_tag: bool,

        pub fn deinit(self: *ResolutionResult, allocator: Allocator) void {
            allocator.free(self.version_string);
            allocator.free(self.url);
        }
    };

    pub const ResolveError = error{
        NoMatchingVersion,
        NoVersionsFound,
        InvalidConstraint,
        InvalidPackageReference,
        RegistryUnavailable,
        OutOfMemory,
        AppContextUnavailable,
    };

    pub fn init(allocator: Allocator) VersionResolver {
        return .{ .allocator = allocator };
    }

    /// Resolve a version constraint to a concrete version
    ///
    /// Args:
    ///   package_ref: Package reference in "owner/repo" format
    ///   constraint: Version constraint string (e.g., "^1.0.0", "~2.1.0", ">=1.0", "*")
    ///
    /// Returns the best matching version or an error
    pub fn resolve(
        self: *VersionResolver,
        package_ref: []const u8,
        constraint: []const u8,
    ) ResolveError!ResolutionResult {
        // Parse the constraint
        const range = semver.VersionRange.parse(constraint) catch return ResolveError.InvalidConstraint;

        // Fetch available versions from registry
        const versions = github.fetchPackageVersions(self.allocator, package_ref) catch {
            return ResolveError.RegistryUnavailable;
        };
        defer {
            for (versions) |*v| {
                v.deinit(self.allocator);
            }
            self.allocator.free(versions);
        }

        if (versions.len == 0) {
            return ResolveError.NoVersionsFound;
        }

        // Find the best matching version (highest that satisfies constraint)
        var best_match: ?struct {
            parsed: semver.Version,
            pkg_version: github.PackageVersion,
        } = null;

        for (versions) |pkg_ver| {
            // Try to parse the version string
            const parsed = semver.Version.parse(pkg_ver.version) catch continue;

            // Check if it satisfies the constraint
            if (range.satisfiedBy(parsed)) {
                if (best_match == null or parsed.compare(best_match.?.parsed) == .gt) {
                    best_match = .{
                        .parsed = parsed,
                        .pkg_version = pkg_ver,
                    };
                }
            }
        }

        if (best_match) |match| {
            return ResolutionResult{
                .resolved_version = match.parsed,
                .version_string = try self.allocator.dupe(u8, match.pkg_version.version),
                .url = try self.allocator.dupe(u8, match.pkg_version.url),
                .is_prerelease = match.parsed.isPrerelease(),
                .is_tag = match.pkg_version.is_tag,
            };
        }

        return ResolveError.NoMatchingVersion;
    }

    /// Resolve to the latest version (ignoring prereleases by default)
    pub fn resolveLatest(
        self: *VersionResolver,
        package_ref: []const u8,
        include_prereleases: bool,
    ) ResolveError!ResolutionResult {
        // Use "*" constraint but filter prereleases if needed
        const versions = github.fetchPackageVersions(self.allocator, package_ref) catch {
            return ResolveError.RegistryUnavailable;
        };
        defer {
            for (versions) |*v| {
                v.deinit(self.allocator);
            }
            self.allocator.free(versions);
        }

        if (versions.len == 0) {
            return ResolveError.NoVersionsFound;
        }

        // Find the highest version
        var best_match: ?struct {
            parsed: semver.Version,
            pkg_version: github.PackageVersion,
        } = null;

        for (versions) |pkg_ver| {
            const parsed = semver.Version.parse(pkg_ver.version) catch continue;

            // Skip prereleases unless requested
            if (!include_prereleases and parsed.isPrerelease()) continue;

            if (best_match == null or parsed.compare(best_match.?.parsed) == .gt) {
                best_match = .{
                    .parsed = parsed,
                    .pkg_version = pkg_ver,
                };
            }
        }

        if (best_match) |match| {
            return ResolutionResult{
                .resolved_version = match.parsed,
                .version_string = try self.allocator.dupe(u8, match.pkg_version.version),
                .url = try self.allocator.dupe(u8, match.pkg_version.url),
                .is_prerelease = match.parsed.isPrerelease(),
                .is_tag = match.pkg_version.is_tag,
            };
        }

        return ResolveError.NoMatchingVersion;
    }

    /// Check if a newer version is available within the given constraint
    ///
    /// Returns the newer version if available, null otherwise
    pub fn checkForUpdate(
        self: *VersionResolver,
        package_ref: []const u8,
        current_version: []const u8,
        constraint: []const u8,
    ) !?semver.Version {
        const current = semver.Version.parse(current_version) catch return null;
        const range = semver.VersionRange.parse(constraint) catch return null;

        const versions = github.fetchPackageVersions(self.allocator, package_ref) catch return null;
        defer {
            for (versions) |*v| {
                v.deinit(self.allocator);
            }
            self.allocator.free(versions);
        }

        for (versions) |pkg_ver| {
            const parsed = semver.Version.parse(pkg_ver.version) catch continue;

            // Check if it's newer and satisfies constraint
            if (range.satisfiedBy(parsed) and parsed.compare(current) == .gt) {
                return parsed;
            }
        }

        return null; // No update available
    }

    /// List all versions that satisfy a constraint
    pub fn listMatching(
        self: *VersionResolver,
        package_ref: []const u8,
        constraint: []const u8,
    ) ![]ResolutionResult {
        const range = semver.VersionRange.parse(constraint) catch return ResolveError.InvalidConstraint;

        const versions = github.fetchPackageVersions(self.allocator, package_ref) catch {
            return ResolveError.RegistryUnavailable;
        };
        defer {
            for (versions) |*v| {
                v.deinit(self.allocator);
            }
            self.allocator.free(versions);
        }

        var results: std.ArrayList(ResolutionResult) = .empty;
        errdefer {
            for (results.items) |*r| r.deinit(self.allocator);
            results.deinit(self.allocator);
        }

        for (versions) |pkg_ver| {
            const parsed = semver.Version.parse(pkg_ver.version) catch continue;

            if (range.satisfiedBy(parsed)) {
                try results.append(self.allocator, ResolutionResult{
                    .resolved_version = parsed,
                    .version_string = try self.allocator.dupe(u8, pkg_ver.version),
                    .url = try self.allocator.dupe(u8, pkg_ver.url),
                    .is_prerelease = parsed.isPrerelease(),
                    .is_tag = pkg_ver.is_tag,
                });
            }
        }

        return results.toOwnedSlice(self.allocator);
    }
};

/// Convenience function to resolve a constraint without creating a resolver instance
pub fn resolveConstraint(
    allocator: Allocator,
    package_ref: []const u8,
    constraint: []const u8,
) !VersionResolver.ResolutionResult {
    var resolver = VersionResolver.init(allocator);
    return try resolver.resolve(package_ref, constraint);
}

/// Convenience function to get the latest version
pub fn resolveLatest(
    allocator: Allocator,
    package_ref: []const u8,
) !VersionResolver.ResolutionResult {
    var resolver = VersionResolver.init(allocator);
    return try resolver.resolveLatest(package_ref, false);
}

// ============= Tests =============

test "VersionResolver types compile" {
    // Basic compilation test - actual resolution requires network
    const allocator = std.testing.allocator;
    const resolver = VersionResolver.init(allocator);
    _ = resolver;
}
