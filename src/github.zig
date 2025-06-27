const std = @import("std");
const json = std.json;
const http = std.http;
const mem = std.mem;
const Allocator = std.mem.Allocator;

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
    // Validate package reference format
    const slash_index = std.mem.indexOf(u8, package_ref, "/") orelse return error.InvalidPackageReference;
    const owner = package_ref[0..slash_index];
    const repo = package_ref[slash_index + 1..];
    
    var versions = std.ArrayList(PackageVersion).init(allocator);
    errdefer {
        for (versions.items) |*version| {
            version.deinit(allocator);
        }
        versions.deinit();
    }
    
    // First try to get releases (these are preferred over plain tags)
    if (fetchReleases(allocator, owner, repo)) |releases| {
        defer {
            for (releases) |*release| {
                release.deinit(allocator);
            }
            allocator.free(releases);
        }
        
        // Add releases as versions
        for (releases) |release| {
            if (!release.prerelease) { // Skip prereleases for now
                try versions.append(PackageVersion{
                    .version = try allocator.dupe(u8, release.tag_name),
                    .url = try allocator.dupe(u8, release.tarball_url),
                    .is_tag = false,
                });
            }
        }
    } else |_| {
        // If releases fail, fall back to tags
        if (fetchTags(allocator, owner, repo)) |tags| {
            defer {
                for (tags) |*tag| {
                    tag.deinit(allocator);
                }
                allocator.free(tags);
            }
            
            // Add tags as versions
            for (tags) |tag| {
                try versions.append(PackageVersion{
                    .version = try allocator.dupe(u8, tag.name),
                    .url = try allocator.dupe(u8, tag.tarball_url),
                    .is_tag = true,
                });
            }
        } else |_| {
            // If both fail, return main branch URL
            const main_url = try std.fmt.allocPrint(allocator, "https://github.com/{s}/{s}/archive/refs/heads/main.tar.gz", .{ owner, repo });
            try versions.append(PackageVersion{
                .version = try allocator.dupe(u8, "main"),
                .url = main_url,
                .is_tag = false,
            });
        }
    }
    
    return versions.toOwnedSlice();
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
    
    return error.VersionNotFound;
}

/// Generate GitHub tarball URL for a specific version
pub fn generateTarballUrl(allocator: Allocator, package_ref: []const u8, version: []const u8) ![]const u8 {
    const slash_index = std.mem.indexOf(u8, package_ref, "/") orelse return error.InvalidPackageReference;
    const owner = package_ref[0..slash_index];
    const repo = package_ref[slash_index + 1..];
    
    // Handle different version formats
    if (std.mem.eql(u8, version, "main") or std.mem.eql(u8, version, "master")) {
        return std.fmt.allocPrint(allocator, "https://github.com/{s}/{s}/archive/refs/heads/{s}.tar.gz", .{ owner, repo, version });
    } else {
        // Assume it's a tag/release
        return std.fmt.allocPrint(allocator, "https://github.com/{s}/{s}/archive/refs/tags/{s}.tar.gz", .{ owner, repo, version });
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
    var releases = std.ArrayList(GitHubRelease).init(allocator);
    
    for (releases_array.items) |release_json| {
        const release_obj = release_json.object;
        
        const tag_name = try allocator.dupe(u8, release_obj.get("tag_name").?.string);
        const name = try allocator.dupe(u8, release_obj.get("name").?.string);
        const published_at = try allocator.dupe(u8, release_obj.get("published_at").?.string);
        const prerelease = release_obj.get("prerelease").?.bool;
        const tarball_url = try allocator.dupe(u8, release_obj.get("tarball_url").?.string);
        const zipball_url = try allocator.dupe(u8, release_obj.get("zipball_url").?.string);
        
        try releases.append(GitHubRelease{
            .tag_name = tag_name,
            .name = name,
            .published_at = published_at,
            .prerelease = prerelease,
            .tarball_url = tarball_url,
            .zipball_url = zipball_url,
        });
    }
    
    return releases.toOwnedSlice();
}

/// Fetch tags from GitHub API using curl
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
    var tags = std.ArrayList(GitHubTag).init(allocator);
    
    for (tags_array.items) |tag_json| {
        const tag_obj = tag_json.object;
        
        const name = try allocator.dupe(u8, tag_obj.get("name").?.string);
        const tarball_url = try allocator.dupe(u8, tag_obj.get("tarball_url").?.string);
        const zipball_url = try allocator.dupe(u8, tag_obj.get("zipball_url").?.string);
        
        try tags.append(GitHubTag{
            .name = name,
            .tarball_url = tarball_url,
            .zipball_url = zipball_url,
        });
    }
    
    return tags.toOwnedSlice();
}

/// Fetch JSON data using curl (fallback for HTTP client issues)
fn fetchJsonWithCurl(allocator: Allocator, url: []const u8) ![]const u8 {
    const argv = [_][]const u8{
        "curl",
        "-s",
        "-H", "Accept: application/vnd.github.v3+json",
        "-H", "User-Agent: Zion-Package-Manager/0.5.0",
        url,
    };
    
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    
    const stdout = try child.stdout.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024); // 10MB limit
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);
    
    const term = try child.wait();
    
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("curl failed (exit code {d}): {s}\n", .{ code, stderr });
                allocator.free(stdout);
                return error.CurlFailed;
            }
        },
        else => {
            std.debug.print("curl terminated abnormally: {s}\n", .{stderr});
            allocator.free(stdout);
            return error.CurlFailed;
        },
    }
    
    return stdout;
}