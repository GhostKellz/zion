const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;
const zion_root = @import("root.zig");
const json_escape = @import("json_escape.zig");

/// Lock file format version
pub const LOCK_FILE_VERSION: u32 = 2;

/// Represents a package entry in the lock file
pub const LockedPackage = struct {
    name: []const u8,
    url: []const u8,
    hash: []const u8,
    version: ?[]const u8,
    timestamp: i64,
    // enhanced fields
    registry: ?[]const u8 = null,
    resolved_from: ?[]const u8 = null,
    integrity: ?[]const u8 = null,
    dependencies: ?[][]const u8 = null,
    dev_only: bool = false,
    // version constraint fields
    version_constraint: ?[]const u8 = null, // Original constraint like "^1.0.0"
    pinned: bool = false, // If true, skip auto-updates
    pinned_ref: ?[]const u8 = null, // Git ref if pinned (tag or commit)
    last_checked: ?i64 = null, // When we last checked for updates
    // provenance tracking fields (from Babylon)
    origin_url: ?[]const u8 = null, // Original fetch URL before any redirects
    content_size: ?u64 = null, // Downloaded archive size in bytes
    fetched_at: ?i64 = null, // Unix timestamp of actual download
    fetch_duration_ms: ?u32 = null, // How long the download took
    checksum_sha256: ?[]const u8 = null, // SHA256 of downloaded content
    checksum_verified: bool = false, // Whether checksum was verified during download

    pub fn deinit(self: *LockedPackage, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.url);
        allocator.free(self.hash);
        if (self.version) |v| allocator.free(v);
        if (self.registry) |r| allocator.free(r);
        if (self.resolved_from) |rf| allocator.free(rf);
        if (self.integrity) |i| allocator.free(i);
        if (self.dependencies) |deps| {
            for (deps) |dep| allocator.free(dep);
            allocator.free(deps);
        }
        if (self.version_constraint) |vc| allocator.free(vc);
        if (self.pinned_ref) |pr| allocator.free(pr);
        // provenance fields
        if (self.origin_url) |ou| allocator.free(ou);
        if (self.checksum_sha256) |cs| allocator.free(cs);
    }
};

/// Represents the lock file structure
pub const LockFile = struct {
    packages: std.ArrayList(LockedPackage),
    allocator: Allocator,

    /// Initialize a new, empty lock file
    pub fn init(allocator: Allocator) LockFile {
        return LockFile{
            .packages = .empty,
            .allocator = allocator,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *LockFile) void {
        for (self.packages.items) |*pkg| {
            pkg.deinit(self.allocator);
        }
        self.packages.deinit(self.allocator);
    }

    /// Add a package to the lock file
    pub fn addPackage(
        self: *LockFile,
        name: []const u8,
        url: []const u8,
        hash: []const u8,
        version: ?[]const u8,
    ) !void {
        return self.addPackageWithMetadata(name, url, hash, .{ .version = version });
    }

    /// Add a package with branch/ref tracking (for main branch unpinning)
    pub fn addPackageWithRef(
        self: *LockFile,
        name: []const u8,
        url: []const u8,
        hash: []const u8,
        version: ?[]const u8,
        ref: []const u8,
    ) !void {
        return self.addPackageWithMetadata(name, url, hash, .{
            .version = version,
            .pinned = false, // Tracking a branch, not pinned to specific version
            .pinned_ref = ref, // Store the branch name (e.g., "main", "master", "develop")
        });
    }

    /// Enhanced metadata structure for package entries
    pub const PackageMetadata = struct {
        version: ?[]const u8 = null,
        registry: ?[]const u8 = null,
        resolved_from: ?[]const u8 = null,
        integrity: ?[]const u8 = null,
        dependencies: ?[][]const u8 = null,
        dev_only: bool = false,
        // constraint fields
        version_constraint: ?[]const u8 = null,
        pinned: bool = false,
        pinned_ref: ?[]const u8 = null,
        // provenance fields
        origin_url: ?[]const u8 = null,
        content_size: ?u64 = null,
        fetched_at: ?i64 = null,
        fetch_duration_ms: ?u32 = null,
        checksum_sha256: ?[]const u8 = null,
        checksum_verified: bool = false,
    };

    /// Add a package with enhanced metadata
    pub fn addPackageWithMetadata(
        self: *LockFile,
        name: []const u8,
        url: []const u8,
        hash: []const u8,
        metadata: PackageMetadata,
    ) !void {
        // Check if package already exists, if so update it
        for (self.packages.items) |*pkg| {
            if (std.mem.eql(u8, pkg.name, name)) {
                pkg.deinit(self.allocator);

                pkg.* = LockedPackage{
                    .name = try self.allocator.dupe(u8, name),
                    .url = try self.allocator.dupe(u8, url),
                    .hash = try self.allocator.dupe(u8, hash),
                    .version = if (metadata.version) |v| try self.allocator.dupe(u8, v) else null,
                    .registry = if (metadata.registry) |r| try self.allocator.dupe(u8, r) else null,
                    .resolved_from = if (metadata.resolved_from) |rf| try self.allocator.dupe(u8, rf) else null,
                    .integrity = if (metadata.integrity) |i| try self.allocator.dupe(u8, i) else null,
                    .dependencies = if (metadata.dependencies) |deps| blk: {
                        const deps_copy = try self.allocator.alloc([]const u8, deps.len);
                        for (deps, 0..) |dep, idx| {
                            deps_copy[idx] = try self.allocator.dupe(u8, dep);
                        }
                        break :blk deps_copy;
                    } else null,
                    .dev_only = metadata.dev_only,
                    .version_constraint = if (metadata.version_constraint) |vc| try self.allocator.dupe(u8, vc) else null,
                    .pinned = metadata.pinned,
                    .pinned_ref = if (metadata.pinned_ref) |pr| try self.allocator.dupe(u8, pr) else null,
                    .last_checked = zion_root.timestamp(),
                    .timestamp = zion_root.timestamp(),
                    // provenance fields
                    .origin_url = if (metadata.origin_url) |ou| try self.allocator.dupe(u8, ou) else null,
                    .content_size = metadata.content_size,
                    .fetched_at = metadata.fetched_at orelse zion_root.timestamp(),
                    .fetch_duration_ms = metadata.fetch_duration_ms,
                    .checksum_sha256 = if (metadata.checksum_sha256) |cs| try self.allocator.dupe(u8, cs) else null,
                    .checksum_verified = metadata.checksum_verified,
                };
                return;
            }
        }

        // Otherwise add a new package
        const new_pkg = LockedPackage{
            .name = try self.allocator.dupe(u8, name),
            .url = try self.allocator.dupe(u8, url),
            .hash = try self.allocator.dupe(u8, hash),
            .version = if (metadata.version) |v| try self.allocator.dupe(u8, v) else null,
            .registry = if (metadata.registry) |r| try self.allocator.dupe(u8, r) else null,
            .resolved_from = if (metadata.resolved_from) |rf| try self.allocator.dupe(u8, rf) else null,
            .integrity = if (metadata.integrity) |i| try self.allocator.dupe(u8, i) else null,
            .dependencies = if (metadata.dependencies) |deps| blk: {
                const deps_copy = try self.allocator.alloc([]const u8, deps.len);
                for (deps, 0..) |dep, idx| {
                    deps_copy[idx] = try self.allocator.dupe(u8, dep);
                }
                break :blk deps_copy;
            } else null,
            .dev_only = metadata.dev_only,
            .version_constraint = if (metadata.version_constraint) |vc| try self.allocator.dupe(u8, vc) else null,
            .pinned = metadata.pinned,
            .pinned_ref = if (metadata.pinned_ref) |pr| try self.allocator.dupe(u8, pr) else null,
            .last_checked = zion_root.timestamp(),
            .timestamp = zion_root.timestamp(),
            // provenance fields
            .origin_url = if (metadata.origin_url) |ou| try self.allocator.dupe(u8, ou) else null,
            .content_size = metadata.content_size,
            .fetched_at = metadata.fetched_at orelse zion_root.timestamp(),
            .fetch_duration_ms = metadata.fetch_duration_ms,
            .checksum_sha256 = if (metadata.checksum_sha256) |cs| try self.allocator.dupe(u8, cs) else null,
            .checksum_verified = metadata.checksum_verified,
        };

        try self.packages.append(self.allocator, new_pkg);
    }

    /// Load lock file from disk
    pub fn loadFromFile(allocator: Allocator) !LockFile {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();
        const lock_path = "zion.lock";

        // Check if file exists
        cwd.access(io, lock_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // If file doesn't exist, return an empty lock file
                return LockFile.init(allocator);
            }
            return err;
        };

        // Read file
        const file_content = try cwd.readFileAlloc(io, lock_path, allocator, Io.Limit.limited(10 * 1024 * 1024));
        defer allocator.free(file_content);

        // Parse JSON using new API
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, file_content, .{}) catch |err| {
            std.debug.print("Error parsing lock file: {}\n", .{err});
            std.debug.print("Lock file content might be corrupted. Creating new lock file.\n", .{});
            return LockFile.init(allocator);
        };
        defer parsed.deinit();
        const root = parsed.value;

        var lock_file = LockFile.init(allocator);
        errdefer lock_file.deinit();

        // Handle different JSON structures
        if (root == .object) {
            if (root.object.get("packages")) |packages_value| {
                if (packages_value == .array) {
                    const packages = packages_value.array.items;
                    for (packages) |pkg_value| {
                        if (pkg_value == .object) {
                            const pkg_obj = pkg_value.object;

                            // Get required fields with error checking
                            const name = if (pkg_obj.get("name")) |n|
                                if (n == .string) n.string else continue
                            else
                                continue;

                            const url = if (pkg_obj.get("url")) |u|
                                if (u == .string) u.string else continue
                            else
                                continue;

                            const hash = if (pkg_obj.get("hash")) |h|
                                if (h == .string) h.string else continue
                            else
                                continue;

                            // Get optional fields
                            const version = if (pkg_obj.get("version")) |v|
                                if (v == .string) v.string else null
                            else
                                null;

                            const timestamp = if (pkg_obj.get("timestamp")) |t|
                                if (t == .integer) t.integer else zion_root.timestamp()
                            else
                                zion_root.timestamp();

                            // enhanced fields
                            const registry = if (pkg_obj.get("registry")) |r|
                                if (r == .string) r.string else null
                            else
                                null;

                            const resolved_from = if (pkg_obj.get("resolved_from")) |rf|
                                if (rf == .string) rf.string else null
                            else
                                null;

                            const integrity = if (pkg_obj.get("integrity")) |i|
                                if (i == .string) i.string else null
                            else
                                null;

                            const dev_only = if (pkg_obj.get("dev_only")) |d|
                                if (d == .bool) d.bool else false
                            else
                                false;

                            const dependencies = if (pkg_obj.get("dependencies")) |deps_val| blk: {
                                if (deps_val == .array) {
                                    const deps_array = deps_val.array.items;
                                    const deps_copy = try allocator.alloc([]const u8, deps_array.len);
                                    for (deps_array, 0..) |dep_val, idx| {
                                        if (dep_val == .string) {
                                            deps_copy[idx] = try allocator.dupe(u8, dep_val.string);
                                        } else {
                                            break :blk null;
                                        }
                                    }
                                    break :blk deps_copy;
                                }
                                break :blk null;
                            } else null;

                            // constraint fields
                            const version_constraint = if (pkg_obj.get("version_constraint")) |vc|
                                if (vc == .string) vc.string else null
                            else
                                null;

                            const pinned = if (pkg_obj.get("pinned")) |p|
                                if (p == .bool) p.bool else false
                            else
                                false;

                            const pinned_ref = if (pkg_obj.get("pinned_ref")) |pr|
                                if (pr == .string) pr.string else null
                            else
                                null;

                            const last_checked = if (pkg_obj.get("last_checked")) |lc|
                                if (lc == .integer) lc.integer else null
                            else
                                null;

                            // provenance fields
                            const origin_url = if (pkg_obj.get("origin_url")) |ou|
                                if (ou == .string) ou.string else null
                            else
                                null;

                            const content_size: ?u64 = if (pkg_obj.get("content_size")) |cs|
                                if (cs == .integer) @intCast(cs.integer) else null
                            else
                                null;

                            const fetched_at = if (pkg_obj.get("fetched_at")) |fa|
                                if (fa == .integer) fa.integer else null
                            else
                                null;

                            const fetch_duration_ms: ?u32 = if (pkg_obj.get("fetch_duration_ms")) |fdm|
                                if (fdm == .integer) @intCast(fdm.integer) else null
                            else
                                null;

                            const checksum_sha256 = if (pkg_obj.get("checksum_sha256")) |cs256|
                                if (cs256 == .string) cs256.string else null
                            else
                                null;

                            const checksum_verified = if (pkg_obj.get("checksum_verified")) |cv|
                                if (cv == .bool) cv.bool else false
                            else
                                false;

                            var loaded_pkg = LockedPackage{
                                .name = try allocator.dupe(u8, name),
                                .url = try allocator.dupe(u8, url),
                                .hash = try allocator.dupe(u8, hash),
                                .version = if (version) |v| try allocator.dupe(u8, v) else null,
                                .registry = if (registry) |r| try allocator.dupe(u8, r) else null,
                                .resolved_from = if (resolved_from) |rf| try allocator.dupe(u8, rf) else null,
                                .integrity = if (integrity) |integ| try allocator.dupe(u8, integ) else null,
                                .dependencies = dependencies,
                                .dev_only = dev_only,
                                .version_constraint = if (version_constraint) |vc| try allocator.dupe(u8, vc) else null,
                                .pinned = pinned,
                                .pinned_ref = if (pinned_ref) |pr| try allocator.dupe(u8, pr) else null,
                                .last_checked = last_checked,
                                .timestamp = timestamp,
                                // provenance fields
                                .origin_url = if (origin_url) |ou| try allocator.dupe(u8, ou) else null,
                                .content_size = content_size,
                                .fetched_at = fetched_at,
                                .fetch_duration_ms = fetch_duration_ms,
                                .checksum_sha256 = if (checksum_sha256) |cs256| try allocator.dupe(u8, cs256) else null,
                                .checksum_verified = checksum_verified,
                            };
                            errdefer loaded_pkg.deinit(allocator);

                            try lock_file.packages.append(allocator, loaded_pkg);
                        }
                    }
                }
            }
        }

        return lock_file;
    }

    /// Save lock file to disk
    pub fn saveToFile(self: *const LockFile) !void {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();
        const lock_path = "zion.lock";

        var file = try cwd.createFile(io, lock_path, .{ .truncate = true });
        defer file.close(io);

        // Create a simple JSON structure manually for better control
        // Write version header for migration support
        const header_line = try std.fmt.allocPrint(self.allocator, "{{\n  \"version\": {d},\n  \"packages\": [\n", .{LOCK_FILE_VERSION});
        defer self.allocator.free(header_line);
        try file.writeStreamingAll(io, header_line);

        for (self.packages.items, 0..) |pkg, i| {
            try file.writeStreamingAll(io, "    {\n");

            // Escape string values for JSON safety
            const escaped_name = try json_escape.escapeJsonString(self.allocator, pkg.name);
            defer self.allocator.free(escaped_name);
            const name_line = try std.fmt.allocPrint(self.allocator, "      \"name\": \"{s}\",\n", .{escaped_name});
            defer self.allocator.free(name_line);
            try file.writeStreamingAll(io, name_line);

            const escaped_url = try json_escape.escapeJsonString(self.allocator, pkg.url);
            defer self.allocator.free(escaped_url);
            const url_line = try std.fmt.allocPrint(self.allocator, "      \"url\": \"{s}\",\n", .{escaped_url});
            defer self.allocator.free(url_line);
            try file.writeStreamingAll(io, url_line);

            const escaped_hash = try json_escape.escapeJsonString(self.allocator, pkg.hash);
            defer self.allocator.free(escaped_hash);
            const hash_line = try std.fmt.allocPrint(self.allocator, "      \"hash\": \"{s}\",\n", .{escaped_hash});
            defer self.allocator.free(hash_line);
            try file.writeStreamingAll(io, hash_line);

            const timestamp_line = try std.fmt.allocPrint(self.allocator, "      \"timestamp\": {d}", .{pkg.timestamp});
            defer self.allocator.free(timestamp_line);
            try file.writeStreamingAll(io, timestamp_line);

            if (pkg.version) |version| {
                const escaped_version = try json_escape.escapeJsonString(self.allocator, version);
                defer self.allocator.free(escaped_version);
                const version_line = try std.fmt.allocPrint(self.allocator, ",\n      \"version\": \"{s}\"", .{escaped_version});
                defer self.allocator.free(version_line);
                try file.writeStreamingAll(io, version_line);
            }

            // enhanced fields
            if (pkg.registry) |registry| {
                const escaped_registry = try json_escape.escapeJsonString(self.allocator, registry);
                defer self.allocator.free(escaped_registry);
                const registry_line = try std.fmt.allocPrint(self.allocator, ",\n      \"registry\": \"{s}\"", .{escaped_registry});
                defer self.allocator.free(registry_line);
                try file.writeStreamingAll(io, registry_line);
            }

            if (pkg.resolved_from) |resolved_from| {
                const escaped_resolved_from = try json_escape.escapeJsonString(self.allocator, resolved_from);
                defer self.allocator.free(escaped_resolved_from);
                const resolved_from_line = try std.fmt.allocPrint(self.allocator, ",\n      \"resolved_from\": \"{s}\"", .{escaped_resolved_from});
                defer self.allocator.free(resolved_from_line);
                try file.writeStreamingAll(io, resolved_from_line);
            }

            if (pkg.integrity) |integrity| {
                const escaped_integrity = try json_escape.escapeJsonString(self.allocator, integrity);
                defer self.allocator.free(escaped_integrity);
                const integrity_line = try std.fmt.allocPrint(self.allocator, ",\n      \"integrity\": \"{s}\"", .{escaped_integrity});
                defer self.allocator.free(integrity_line);
                try file.writeStreamingAll(io, integrity_line);
            }

            if (pkg.dependencies) |dependencies| {
                try file.writeStreamingAll(io, ",\n      \"dependencies\": [");
                for (dependencies, 0..) |dep, dep_i| {
                    const escaped_dep = try json_escape.escapeJsonString(self.allocator, dep);
                    defer self.allocator.free(escaped_dep);
                    const dep_line = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{escaped_dep});
                    defer self.allocator.free(dep_line);
                    try file.writeStreamingAll(io, dep_line);
                    if (dep_i < dependencies.len - 1) {
                        try file.writeStreamingAll(io, ", ");
                    }
                }
                try file.writeStreamingAll(io, "]");
            }

            if (pkg.dev_only) {
                const dev_only_line = try std.fmt.allocPrint(self.allocator, ",\n      \"dev_only\": {}", .{pkg.dev_only});
                defer self.allocator.free(dev_only_line);
                try file.writeStreamingAll(io, dev_only_line);
            }

            // constraint fields
            if (pkg.version_constraint) |vc| {
                const escaped_vc = try json_escape.escapeJsonString(self.allocator, vc);
                defer self.allocator.free(escaped_vc);
                const vc_line = try std.fmt.allocPrint(self.allocator, ",\n      \"version_constraint\": \"{s}\"", .{escaped_vc});
                defer self.allocator.free(vc_line);
                try file.writeStreamingAll(io, vc_line);
            }

            if (pkg.pinned) {
                try file.writeStreamingAll(io, ",\n      \"pinned\": true");
            }

            if (pkg.pinned_ref) |pr| {
                const escaped_pr = try json_escape.escapeJsonString(self.allocator, pr);
                defer self.allocator.free(escaped_pr);
                const pr_line = try std.fmt.allocPrint(self.allocator, ",\n      \"pinned_ref\": \"{s}\"", .{escaped_pr});
                defer self.allocator.free(pr_line);
                try file.writeStreamingAll(io, pr_line);
            }

            if (pkg.last_checked) |lc| {
                const lc_line = try std.fmt.allocPrint(self.allocator, ",\n      \"last_checked\": {d}", .{lc});
                defer self.allocator.free(lc_line);
                try file.writeStreamingAll(io, lc_line);
            }

            // provenance fields
            if (pkg.origin_url) |ou| {
                const escaped_ou = try json_escape.escapeJsonString(self.allocator, ou);
                defer self.allocator.free(escaped_ou);
                const ou_line = try std.fmt.allocPrint(self.allocator, ",\n      \"origin_url\": \"{s}\"", .{escaped_ou});
                defer self.allocator.free(ou_line);
                try file.writeStreamingAll(io, ou_line);
            }

            if (pkg.content_size) |cs| {
                const cs_line = try std.fmt.allocPrint(self.allocator, ",\n      \"content_size\": {d}", .{cs});
                defer self.allocator.free(cs_line);
                try file.writeStreamingAll(io, cs_line);
            }

            if (pkg.fetched_at) |fa| {
                const fa_line = try std.fmt.allocPrint(self.allocator, ",\n      \"fetched_at\": {d}", .{fa});
                defer self.allocator.free(fa_line);
                try file.writeStreamingAll(io, fa_line);
            }

            if (pkg.fetch_duration_ms) |fdm| {
                const fdm_line = try std.fmt.allocPrint(self.allocator, ",\n      \"fetch_duration_ms\": {d}", .{fdm});
                defer self.allocator.free(fdm_line);
                try file.writeStreamingAll(io, fdm_line);
            }

            if (pkg.checksum_sha256) |cs256| {
                const escaped_cs256 = try json_escape.escapeJsonString(self.allocator, cs256);
                defer self.allocator.free(escaped_cs256);
                const cs256_line = try std.fmt.allocPrint(self.allocator, ",\n      \"checksum_sha256\": \"{s}\"", .{escaped_cs256});
                defer self.allocator.free(cs256_line);
                try file.writeStreamingAll(io, cs256_line);
            }

            if (pkg.checksum_verified) {
                try file.writeStreamingAll(io, ",\n      \"checksum_verified\": true");
            }

            try file.writeStreamingAll(io, "\n    }");

            if (i < self.packages.items.len - 1) {
                try file.writeStreamingAll(io, ",");
            }
            try file.writeStreamingAll(io, "\n");
        }

        try file.writeStreamingAll(io, "  ]\n}\n");
    }

    /// Get a package by name
    pub fn getPackage(self: *const LockFile, name: []const u8) ?LockedPackage {
        for (self.packages.items) |pkg| {
            if (std.mem.eql(u8, pkg.name, name)) {
                return pkg;
            }
        }
        return null;
    }
};
