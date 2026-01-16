const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;
const zion_root = @import("root.zig");

/// Represents a package entry in the lock file
pub const LockedPackage = struct {
    name: []const u8,
    url: []const u8,
    hash: []const u8,
    version: ?[]const u8,
    timestamp: i64,
    // v0.7.0 enhanced fields
    registry: ?[]const u8 = null,
    resolved_from: ?[]const u8 = null,
    integrity: ?[]const u8 = null,
    dependencies: ?[][]const u8 = null,
    dev_only: bool = false,
    
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
    }
};

/// Represents the lock file structure
pub const LockFile = struct {
    packages: std.ArrayList(LockedPackage),
    allocator: Allocator,

    /// Initialize a new, empty lock file
    pub fn init(allocator: Allocator) LockFile {
        return LockFile{
            .packages = .{},
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

    /// Enhanced metadata structure for v0.7.0
    pub const PackageMetadata = struct {
        version: ?[]const u8 = null,
        registry: ?[]const u8 = null,
        resolved_from: ?[]const u8 = null,
        integrity: ?[]const u8 = null,
        dependencies: ?[][]const u8 = null,
        dev_only: bool = false,
    };

    /// Add a package with enhanced metadata (v0.7.0)
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
                        for (deps, 0..) |dep, i| {
                            deps_copy[i] = try self.allocator.dupe(u8, dep);
                        }
                        break :blk deps_copy;
                    } else null,
                    .dev_only = metadata.dev_only,
                    .timestamp = zion_root.timestamp(),
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
                for (deps, 0..) |dep, i| {
                    deps_copy[i] = try self.allocator.dupe(u8, dep);
                }
                break :blk deps_copy;
            } else null,
            .dev_only = metadata.dev_only,
            .timestamp = zion_root.timestamp(),
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

                            // v0.7.0 enhanced fields
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
                                    for (deps_array, 0..) |dep_val, i| {
                                        if (dep_val == .string) {
                                            deps_copy[i] = try allocator.dupe(u8, dep_val.string);
                                        } else {
                                            break :blk null;
                                        }
                                    }
                                    break :blk deps_copy;
                                }
                                break :blk null;
                            } else null;

                            try lock_file.packages.append(allocator, LockedPackage{
                                .name = try allocator.dupe(u8, name),
                                .url = try allocator.dupe(u8, url),
                                .hash = try allocator.dupe(u8, hash),
                                .version = if (version) |v| try allocator.dupe(u8, v) else null,
                                .registry = if (registry) |r| try allocator.dupe(u8, r) else null,
                                .resolved_from = if (resolved_from) |rf| try allocator.dupe(u8, rf) else null,
                                .integrity = if (integrity) |i| try allocator.dupe(u8, i) else null,
                                .dependencies = dependencies,
                                .dev_only = dev_only,
                                .timestamp = timestamp,
                            });
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
        try file.writeStreamingAll(io, "{\n  \"packages\": [\n");

        for (self.packages.items, 0..) |pkg, i| {
            try file.writeStreamingAll(io, "    {\n");
            const name_line = try std.fmt.allocPrint(self.allocator, "      \"name\": \"{s}\",\n", .{pkg.name});
            defer self.allocator.free(name_line);
            try file.writeStreamingAll(io, name_line);

            const url_line = try std.fmt.allocPrint(self.allocator, "      \"url\": \"{s}\",\n", .{pkg.url});
            defer self.allocator.free(url_line);
            try file.writeStreamingAll(io, url_line);

            const hash_line = try std.fmt.allocPrint(self.allocator, "      \"hash\": \"{s}\",\n", .{pkg.hash});
            defer self.allocator.free(hash_line);
            try file.writeStreamingAll(io, hash_line);

            const timestamp_line = try std.fmt.allocPrint(self.allocator, "      \"timestamp\": {d}", .{pkg.timestamp});
            defer self.allocator.free(timestamp_line);
            try file.writeStreamingAll(io, timestamp_line);

            if (pkg.version) |version| {
                const version_line = try std.fmt.allocPrint(self.allocator, ",\n      \"version\": \"{s}\"", .{version});
                defer self.allocator.free(version_line);
                try file.writeStreamingAll(io, version_line);
            }

            // v0.7.0 enhanced fields
            if (pkg.registry) |registry| {
                const registry_line = try std.fmt.allocPrint(self.allocator, ",\n      \"registry\": \"{s}\"", .{registry});
                defer self.allocator.free(registry_line);
                try file.writeStreamingAll(io, registry_line);
            }

            if (pkg.resolved_from) |resolved_from| {
                const resolved_from_line = try std.fmt.allocPrint(self.allocator, ",\n      \"resolved_from\": \"{s}\"", .{resolved_from});
                defer self.allocator.free(resolved_from_line);
                try file.writeStreamingAll(io, resolved_from_line);
            }

            if (pkg.integrity) |integrity| {
                const integrity_line = try std.fmt.allocPrint(self.allocator, ",\n      \"integrity\": \"{s}\"", .{integrity});
                defer self.allocator.free(integrity_line);
                try file.writeStreamingAll(io, integrity_line);
            }

            if (pkg.dependencies) |dependencies| {
                try file.writeStreamingAll(io, ",\n      \"dependencies\": [");
                for (dependencies, 0..) |dep, dep_i| {
                    const dep_line = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{dep});
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
