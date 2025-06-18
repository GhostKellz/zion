const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const json = std.json;

/// Represents a package entry in the lock file
pub const LockedPackage = struct {
    name: []const u8,
    url: []const u8,
    hash: []const u8,
    version: ?[]const u8,
    timestamp: i64,
};

/// Represents the lock file structure
pub const LockFile = struct {
    packages: std.ArrayList(LockedPackage),
    allocator: Allocator,

    /// Initialize a new, empty lock file
    pub fn init(allocator: Allocator) LockFile {
        return LockFile{
            .packages = std.ArrayList(LockedPackage).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *LockFile) void {
        for (self.packages.items) |pkg| {
            self.allocator.free(pkg.name);
            self.allocator.free(pkg.url);
            self.allocator.free(pkg.hash);
            if (pkg.version) |version| {
                self.allocator.free(version);
            }
        }
        self.packages.deinit();
    }

    /// Add a package to the lock file
    pub fn addPackage(
        self: *LockFile,
        name: []const u8,
        url: []const u8,
        hash: []const u8,
        version: ?[]const u8,
    ) !void {
        // Check if package already exists, if so update it
        for (self.packages.items) |*pkg| {
            if (std.mem.eql(u8, pkg.name, name)) {
                self.allocator.free(pkg.url);
                self.allocator.free(pkg.hash);
                if (pkg.version) |v| {
                    self.allocator.free(v);
                }

                pkg.url = try self.allocator.dupe(u8, url);
                pkg.hash = try self.allocator.dupe(u8, hash);
                pkg.version = if (version) |v| try self.allocator.dupe(u8, v) else null;
                pkg.timestamp = std.time.timestamp();
                return;
            }
        }

        // Otherwise add a new package
        const new_pkg = LockedPackage{
            .name = try self.allocator.dupe(u8, name),
            .url = try self.allocator.dupe(u8, url),
            .hash = try self.allocator.dupe(u8, hash),
            .version = if (version) |v| try self.allocator.dupe(u8, v) else null,
            .timestamp = std.time.timestamp(),
        };

        try self.packages.append(new_pkg);
    }

    /// Load lock file from disk
    pub fn loadFromFile(allocator: Allocator) !LockFile {
        const cwd = fs.cwd();
        const lock_path = "zion.lock";

        // Check if file exists
        cwd.access(lock_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // If file doesn't exist, return an empty lock file
                return LockFile.init(allocator);
            }
            return err;
        };

        // Read file
        const file_content = try cwd.readFileAlloc(allocator, lock_path, 10 * 1024 * 1024);
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
                                if (t == .integer) t.integer else std.time.timestamp()
                            else
                                std.time.timestamp();

                            try lock_file.packages.append(LockedPackage{
                                .name = try allocator.dupe(u8, name),
                                .url = try allocator.dupe(u8, url),
                                .hash = try allocator.dupe(u8, hash),
                                .version = if (version) |v| try allocator.dupe(u8, v) else null,
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
        const cwd = fs.cwd();
        const lock_path = "zion.lock";

        var file = try cwd.createFile(lock_path, .{ .truncate = true });
        defer file.close();

        // Create a simple JSON structure manually for better control
        try file.writer().writeAll("{\n  \"packages\": [\n");

        for (self.packages.items, 0..) |pkg, i| {
            try file.writer().writeAll("    {\n");
            try file.writer().print("      \"name\": \"{s}\",\n", .{pkg.name});
            try file.writer().print("      \"url\": \"{s}\",\n", .{pkg.url});
            try file.writer().print("      \"hash\": \"{s}\",\n", .{pkg.hash});
            try file.writer().print("      \"timestamp\": {d}", .{pkg.timestamp});

            if (pkg.version) |version| {
                try file.writer().print(",\n      \"version\": \"{s}\"", .{version});
            }

            try file.writer().writeAll("\n    }");

            if (i < self.packages.items.len - 1) {
                try file.writer().writeAll(",");
            }
            try file.writer().writeAll("\n");
        }

        try file.writer().writeAll("  ]\n}\n");
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
