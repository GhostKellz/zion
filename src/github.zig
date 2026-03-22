const std = @import("std");
const json = std.json;
const http = std.http;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Io = std.Io;
const zion_root = @import("root.zig");
const registry = @import("registry.zig");
const enhanced_config = @import("enhanced_config.zig");

pub const GitHubTag = struct {
    name: []const u8,
    tarball_url: []const u8,
    zipball_url: []const u8,

    pub fn deinit(self: *GitHubTag, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.tarball_url);
        allocator.free(self.zipball_url);
    }
};

/// Error for malformed JSON responses
pub const JsonError = error{
    MalformedJson,
    MissingField,
    InvalidFieldType,
};

/// Safely get a string field from a JSON object, returning error instead of panicking
fn getJsonString(obj: std.json.ObjectMap, field: []const u8) JsonError![]const u8 {
    const val = obj.get(field) orelse return JsonError.MissingField;
    return switch (val) {
        .string => |s| s,
        else => JsonError.InvalidFieldType,
    };
}

/// Safely get a bool field from a JSON object, returning error instead of panicking
fn getJsonBool(obj: std.json.ObjectMap, field: []const u8) JsonError!bool {
    const val = obj.get(field) orelse return JsonError.MissingField;
    return switch (val) {
        .bool => |b| b,
        else => JsonError.InvalidFieldType,
    };
}

pub const GitHubRelease = struct {
    tag_name: []const u8,
    name: []const u8,
    published_at: []const u8,
    prerelease: bool,
    tarball_url: []const u8,
    zipball_url: []const u8,

    pub fn deinit(self: *GitHubRelease, allocator: Allocator) void {
        allocator.free(self.tag_name);
        allocator.free(self.name);
        allocator.free(self.published_at);
        allocator.free(self.tarball_url);
        allocator.free(self.zipball_url);
    }
};

pub const PackageVersion = struct {
    version: []const u8,
    url: []const u8,
    is_tag: bool,

    pub fn deinit(self: *PackageVersion, allocator: Allocator) void {
        allocator.free(self.version);
        allocator.free(self.url);
    }
};

/// Fetch available tags and releases for a GitHub repository
pub fn fetchPackageVersions(allocator: Allocator, package_ref: []const u8) ![]PackageVersion {
    // Load config to get registry settings
    var config = enhanced_config.ZionConfig.load(allocator) catch enhanced_config.ZionConfig.init(allocator);
    defer config.deinit();

    // Validate package reference format
    const slash_index = std.mem.indexOf(u8, package_ref, "/") orelse return error.InvalidPackageReference;
    const owner = package_ref[0..slash_index];
    const repo = package_ref[slash_index + 1 ..];

    var versions: std.ArrayList(PackageVersion) = .empty;
    errdefer {
        for (versions.items) |*version| {
            version.deinit(allocator);
        }
        versions.deinit(allocator);
    }

    // Try primary registry first
    const primary_registry = registry.getPrimaryRegistry(allocator, &config);
    if (tryFetchFromRegistry(allocator, &primary_registry, owner, repo, &versions)) {
        return try versions.toOwnedSlice(allocator);
    } else |err| {
        std.debug.print("⚠️ Primary registry failed: {}\n", .{err});
    }

    // Try fallback registries
    const fallback_registries = try registry.getFallbackRegistries(allocator, &config);
    defer allocator.free(fallback_registries);

    for (fallback_registries) |fallback_registry| {
        if (tryFetchFromRegistry(allocator, &fallback_registry, owner, repo, &versions)) {
            return try versions.toOwnedSlice(allocator);
        } else |err| {
            std.debug.print("⚠️ Fallback registry failed: {}\n", .{err});
        }
    }

    return error.NoRegistriesAvailable;
}

/// Get the latest version (release or tag) for a package
pub fn getLatestVersion(allocator: Allocator, package_ref: []const u8) !PackageVersion {
    const versions = try fetchPackageVersions(allocator, package_ref);
    defer {
        for (versions) |*version| {
            version.deinit(allocator);
        }
        allocator.free(versions);
    }

    if (versions.len == 0) {
        return error.NoVersionsFound;
    }

    // Return the first version (should be latest)
    return PackageVersion{
        .version = try allocator.dupe(u8, versions[0].version),
        .url = try allocator.dupe(u8, versions[0].url),
        .is_tag = versions[0].is_tag,
    };
}

/// Find a specific version from available versions
pub fn findVersion(allocator: Allocator, package_ref: []const u8, target_version: []const u8) !PackageVersion {
    const versions = try fetchPackageVersions(allocator, package_ref);
    defer {
        for (versions) |*version| {
            version.deinit(allocator);
        }
        allocator.free(versions);
    }

    if (versions.len == 0) {
        std.debug.print("❌ No versions found for package '{s}'\n", .{package_ref});
        return error.NoVersionsFound;
    }

    // Look for exact match first
    for (versions) |version| {
        if (std.mem.eql(u8, version.version, target_version)) {
            return PackageVersion{
                .version = try allocator.dupe(u8, version.version),
                .url = try allocator.dupe(u8, version.url),
                .is_tag = version.is_tag,
            };
        }
    }

    // Look for version without 'v' prefix
    const clean_target = if (std.mem.startsWith(u8, target_version, "v")) target_version[1..] else target_version;
    for (versions) |version| {
        const clean_version = if (std.mem.startsWith(u8, version.version, "v")) version.version[1..] else version.version;
        if (std.mem.eql(u8, clean_version, clean_target)) {
            return PackageVersion{
                .version = try allocator.dupe(u8, version.version),
                .url = try allocator.dupe(u8, version.url),
                .is_tag = version.is_tag,
            };
        }
    }

    // Version not found - show available versions
    std.debug.print("❌ Version '{s}' not found for package '{s}'\n", .{ target_version, package_ref });
    std.debug.print("📦 Available versions:\n", .{});
    for (versions[0..@min(versions.len, 5)]) |version| {
        std.debug.print("  - {s}\n", .{version.version});
    }
    if (versions.len > 5) {
        std.debug.print("  ... and {d} more versions\n", .{versions.len - 5});
    }
    std.debug.print("💡 Try: zion fetch {s}@{s}\n", .{ package_ref, versions[0].version });

    return error.VersionNotFound;
}

/// Generate GitHub tarball URL for a specific version
pub fn generateTarballUrl(allocator: Allocator, package_ref: []const u8, version: []const u8) ![]const u8 {
    const slash_index = std.mem.indexOf(u8, package_ref, "/") orelse return error.InvalidPackageReference;
    const owner = package_ref[0..slash_index];
    const repo = package_ref[slash_index + 1 ..];

    // Handle different version formats
    if (std.mem.eql(u8, version, "main") or std.mem.eql(u8, version, "master")) {
        return std.fmt.allocPrint(allocator, "https://github.com/{s}/{s}/archive/refs/heads/{s}.tar.gz", .{ owner, repo, version });
    } else {
        // Assume it's a tag/release
        return std.fmt.allocPrint(allocator, "https://github.com/{s}/{s}/archive/refs/tags/{s}.tar.gz", .{ owner, repo, version });
    }
}

/// New helper function to try fetching from a specific registry
fn tryFetchFromRegistry(allocator: Allocator, reg: *const registry.RegistryClient, owner: []const u8, repo: []const u8, versions: *std.ArrayList(PackageVersion)) !void {
    // First try to get releases
    if (fetchReleasesFromRegistry(allocator, reg, owner, repo)) |releases| {
        defer {
            for (releases) |*release| {
                release.deinit(allocator);
            }
            allocator.free(releases);
        }

        // Add releases as versions
        for (releases) |release| {
            if (!release.prerelease) {
                try versions.append(allocator, PackageVersion{
                    .version = try allocator.dupe(u8, release.tag_name),
                    .url = try allocator.dupe(u8, release.tarball_url),
                    .is_tag = false,
                });
            }
        }
    } else |_| {
        // If releases fail, fall back to tags
        if (fetchTagsFromRegistry(allocator, reg, owner, repo)) |tags| {
            defer {
                for (tags) |*tag| {
                    tag.deinit(allocator);
                }
                allocator.free(tags);
            }

            // Add tags as versions
            for (tags) |tag| {
                try versions.append(allocator, PackageVersion{
                    .version = try allocator.dupe(u8, tag.name),
                    .url = try allocator.dupe(u8, tag.tarball_url),
                    .is_tag = true,
                });
            }
        } else |_| {
            return error.RegistryUnavailable;
        }
    }
}

/// Fetch releases from GitHub API using curl
fn fetchReleases(allocator: Allocator, owner: []const u8, repo: []const u8) ![]GitHubRelease {
    const url = try std.fmt.allocPrint(allocator, "https://api.github.com/repos/{s}/{s}/releases", .{ owner, repo });
    defer allocator.free(url);

    const json_data = fetchJsonWithCurl(allocator, url) catch |err| {
        std.debug.print("GitHub API error fetching releases for {s}/{s}: {}\n", .{ owner, repo, err });
        return err;
    };
    defer allocator.free(json_data);

    // Check if response is empty or has error
    if (json_data.len == 0) {
        return error.EmptyResponse;
    }

    var parsed = json.parseFromSlice(json.Value, allocator, json_data, .{}) catch |err| {
        std.debug.print("JSON parse error for releases: {}\n", .{err});
        std.debug.print("Response: {s}\n", .{json_data});
        return err;
    };
    defer parsed.deinit();

    const releases_array = parsed.value.array;
    var releases: std.ArrayList(GitHubRelease) = .empty;

    for (releases_array.items) |release_json| {
        const release_obj = release_json.object;

        // Use safe JSON field access - skip malformed entries instead of panicking
        const tag_name = getJsonString(release_obj, "tag_name") catch continue;
        const name_str = getJsonString(release_obj, "name") catch continue;
        const published_at = getJsonString(release_obj, "published_at") catch continue;
        const prerelease = getJsonBool(release_obj, "prerelease") catch continue;
        const tarball_url = getJsonString(release_obj, "tarball_url") catch continue;
        const zipball_url = getJsonString(release_obj, "zipball_url") catch continue;

        try releases.append(allocator, GitHubRelease{
            .tag_name = try allocator.dupe(u8, tag_name),
            .name = try allocator.dupe(u8, name_str),
            .published_at = try allocator.dupe(u8, published_at),
            .prerelease = prerelease,
            .tarball_url = try allocator.dupe(u8, tarball_url),
            .zipball_url = try allocator.dupe(u8, zipball_url),
        });
    }

    return releases.toOwnedSlice(allocator);
}

/// Fetch releases from registry client
fn fetchReleasesFromRegistry(allocator: Allocator, reg: *const registry.RegistryClient, owner: []const u8, repo: []const u8) ![]GitHubRelease {
    const url = try reg.getReleasesUrl(owner, repo);
    defer allocator.free(url);

    const json_data = fetchJsonWithCurl(allocator, url) catch |err| {
        std.debug.print("Registry API error fetching releases for {s}/{s}: {}\n", .{ owner, repo, err });
        return err;
    };
    defer allocator.free(json_data);

    // Check if response is empty or has error
    if (json_data.len == 0) {
        return error.EmptyResponse;
    }

    var parsed = json.parseFromSlice(json.Value, allocator, json_data, .{}) catch |err| {
        std.debug.print("JSON parse error for releases: {}\n", .{err});
        std.debug.print("Response: {s}\n", .{json_data});
        return err;
    };
    defer parsed.deinit();

    const releases_array = parsed.value.array;
    var releases: std.ArrayList(GitHubRelease) = .empty;

    for (releases_array.items) |release_json| {
        const release_obj = release_json.object;

        // Use safe JSON field access - skip malformed entries instead of panicking
        const tag_name = getJsonString(release_obj, "tag_name") catch continue;
        const name_str = getJsonString(release_obj, "name") catch continue;
        const published_at = getJsonString(release_obj, "published_at") catch continue;
        const prerelease = getJsonBool(release_obj, "prerelease") catch continue;
        const tarball_url = getJsonString(release_obj, "tarball_url") catch continue;
        const zipball_url = getJsonString(release_obj, "zipball_url") catch continue;

        try releases.append(allocator, GitHubRelease{
            .tag_name = try allocator.dupe(u8, tag_name),
            .name = try allocator.dupe(u8, name_str),
            .published_at = try allocator.dupe(u8, published_at),
            .prerelease = prerelease,
            .tarball_url = try allocator.dupe(u8, tarball_url),
            .zipball_url = try allocator.dupe(u8, zipball_url),
        });
    }

    return releases.toOwnedSlice(allocator);
}

/// Fetch tags from registry client
fn fetchTagsFromRegistry(allocator: Allocator, reg: *const registry.RegistryClient, owner: []const u8, repo: []const u8) ![]GitHubTag {
    const url = try reg.getTagsUrl(owner, repo);
    defer allocator.free(url);

    const json_data = fetchJsonWithCurl(allocator, url) catch |err| {
        std.debug.print("Registry API error fetching tags for {s}/{s}: {}\n", .{ owner, repo, err });
        return err;
    };
    defer allocator.free(json_data);

    // Check if response is empty or has error
    if (json_data.len == 0) {
        return error.EmptyResponse;
    }

    var parsed = json.parseFromSlice(json.Value, allocator, json_data, .{}) catch |err| {
        std.debug.print("JSON parse error for tags: {}\n", .{err});
        std.debug.print("Response: {s}\n", .{json_data});
        return err;
    };
    defer parsed.deinit();

    const tags_array = parsed.value.array;
    var tags: std.ArrayList(GitHubTag) = .empty;

    for (tags_array.items) |tag_json| {
        const tag_obj = tag_json.object;

        // Use safe JSON field access - skip malformed entries instead of panicking
        const name = getJsonString(tag_obj, "name") catch continue;
        const tarball_url = getJsonString(tag_obj, "tarball_url") catch continue;
        const zipball_url = getJsonString(tag_obj, "zipball_url") catch continue;

        try tags.append(allocator, GitHubTag{
            .name = try allocator.dupe(u8, name),
            .tarball_url = try allocator.dupe(u8, tarball_url),
            .zipball_url = try allocator.dupe(u8, zipball_url),
        });
    }

    return tags.toOwnedSlice(allocator);
}

/// Fetch tags from GitHub API using curl (legacy)
fn fetchTags(allocator: Allocator, owner: []const u8, repo: []const u8) ![]GitHubTag {
    const url = try std.fmt.allocPrint(allocator, "https://api.github.com/repos/{s}/{s}/tags", .{ owner, repo });
    defer allocator.free(url);

    const json_data = fetchJsonWithCurl(allocator, url) catch |err| {
        std.debug.print("GitHub API error fetching tags for {s}/{s}: {}\n", .{ owner, repo, err });
        return err;
    };
    defer allocator.free(json_data);

    // Check if response is empty or has error
    if (json_data.len == 0) {
        return error.EmptyResponse;
    }

    var parsed = json.parseFromSlice(json.Value, allocator, json_data, .{}) catch |err| {
        std.debug.print("JSON parse error for tags: {}\n", .{err});
        std.debug.print("Response: {s}\n", .{json_data});
        return err;
    };
    defer parsed.deinit();

    const tags_array = parsed.value.array;
    var tags: std.ArrayList(GitHubTag) = .empty;

    for (tags_array.items) |tag_json| {
        const tag_obj = tag_json.object;

        // Use safe JSON field access - skip malformed entries instead of panicking
        const name = getJsonString(tag_obj, "name") catch continue;
        const tarball_url = getJsonString(tag_obj, "tarball_url") catch continue;
        const zipball_url = getJsonString(tag_obj, "zipball_url") catch continue;

        try tags.append(allocator, GitHubTag{
            .name = try allocator.dupe(u8, name),
            .tarball_url = try allocator.dupe(u8, tarball_url),
            .zipball_url = try allocator.dupe(u8, zipball_url),
        });
    }

    return tags.toOwnedSlice(allocator);
}

/// Fetch JSON data using curl (fallback for HTTP client issues)
fn fetchJsonWithCurl(allocator: Allocator, url: []const u8) ![]const u8 {
    const io = try zion_root.getIo();

    const argv = [_][]const u8{
        "curl",
        "-s",
        "-H",
        "Accept: application/vnd.github.v3+json",
        "-H",
        "User-Agent: Zion-Package-Manager/0.5.0",
        url,
    };

    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // Use direct file readStreaming with pre-allocated buffers
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(allocator);
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(allocator);

    // Read data in chunks using scatter/gather API
    var read_buf: [4096]u8 = undefined;
    if (child.stdout) |stdout_pipe| {
        while (true) {
            const bytes_read = stdout_pipe.readStreaming(io, &.{read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stdout_buf.appendSlice(allocator, read_buf[0..bytes_read]);
        }
    }

    if (child.stderr) |stderr_pipe| {
        while (true) {
            const bytes_read = stderr_pipe.readStreaming(io, &.{read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stderr_buf.appendSlice(allocator, read_buf[0..bytes_read]);
        }
    }

    const stdout = try allocator.dupe(u8, stdout_buf.items);
    const stderr = try allocator.dupe(u8, stderr_buf.items);
    defer allocator.free(stderr);
    errdefer allocator.free(stdout); // Free stdout on error, caller frees on success

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("curl failed (exit code {d}): {s}\n", .{ code, stderr });
                return error.CurlFailed;
            }
        },
        else => {
            std.debug.print("curl terminated abnormally: {s}\n", .{stderr});
            return error.CurlFailed;
        },
    }

    return stdout;
}
