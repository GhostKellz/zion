const std = @import("std");
const fs = std.fs;
const zion_root = @import("root.zig");
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Io = std.Io;

pub const BuildCacheError = error{
    CacheCorrupted,
    InvalidPath,
    AccessDenied,
};

pub const CacheEntry = struct {
    source_hash: []const u8,
    build_hash: []const u8,
    timestamp: i64,
    dependencies: [][]const u8,
    build_flags: [][]const u8,
    output_files: [][]const u8,

    pub fn deinit(self: *CacheEntry, allocator: Allocator) void {
        allocator.free(self.source_hash);
        allocator.free(self.build_hash);

        for (self.dependencies) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.dependencies);

        for (self.build_flags) |flag| {
            allocator.free(flag);
        }
        allocator.free(self.build_flags);

        for (self.output_files) |file| {
            allocator.free(file);
        }
        allocator.free(self.output_files);
    }
};

pub const BuildCache = struct {
    allocator: Allocator,
    cache_dir: []const u8,
    entries: std.StringHashMap(CacheEntry),

    pub fn init(allocator: Allocator, cache_dir: []const u8) !BuildCache {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        // Create cache directory if it doesn't exist
        cwd.createDirPath(io, cache_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        return BuildCache{
            .allocator = allocator,
            .cache_dir = try allocator.dupe(u8, cache_dir),
            .entries = std.StringHashMap(CacheEntry).init(allocator),
        };
    }

    pub fn deinit(self: *BuildCache) void {
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.entries.deinit();
        self.allocator.free(self.cache_dir);
    }

    pub fn computeSourceHash(self: *BuildCache, source_path: []const u8) ![]const u8 {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});

        // Hash all source files recursively
        var source_dir = cwd.openDir(io, source_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                // Single file
                const content = try cwd.readFileAlloc(io, source_path, self.allocator, Io.Limit.limited(100 * 1024 * 1024));
                defer self.allocator.free(content);

                hasher.update(content);
                var hash_buf: [32]u8 = undefined;
                hasher.final(&hash_buf);
                var hex_buf: [64]u8 = undefined;
                const hex_str = std.fmt.bufPrint(&hex_buf, "{x}", .{hash_buf}) catch return error.InvalidHash;
                return try self.allocator.dupe(u8, hex_str);
            }
            return err;
        };
        defer source_dir.close(io);

        // Walk directory tree and hash all .zig files
        var walker = try source_dir.walk(self.allocator);
        defer walker.deinit();

        var file_paths: std.ArrayListUnmanaged([]const u8) = .empty;
        defer {
            for (file_paths.items) |path| {
                self.allocator.free(path);
            }
            file_paths.deinit(self.allocator);
        }

        while (try walker.next(io)) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".zig")) {
                try file_paths.append(self.allocator, try self.allocator.dupe(u8, entry.path));
            }
        }

        // Sort paths for consistent hashing
        std.mem.sort([]const u8, file_paths.items, {}, stringLessThan);

        for (file_paths.items) |path| {
            const content = try source_dir.readFileAlloc(io, path, self.allocator, Io.Limit.limited(10 * 1024 * 1024));
            defer self.allocator.free(content);

            hasher.update(path);
            hasher.update(content);
        }

        var hash_buf: [32]u8 = undefined;
        hasher.final(&hash_buf);
        var hex_buf: [64]u8 = undefined;
        const hex_str = std.fmt.bufPrint(&hex_buf, "{x}", .{hash_buf}) catch return error.InvalidHash;
        return try self.allocator.dupe(u8, hex_str);
    }

    fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.order(u8, lhs, rhs) == .lt;
    }

    pub fn getCacheEntry(self: *BuildCache, project_name: []const u8) ?CacheEntry {
        return self.entries.get(project_name);
    }

    pub fn isCacheValid(self: *BuildCache, project_name: []const u8, current_source_hash: []const u8, dependencies: [][]const u8, build_flags: [][]const u8) !bool {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        const entry = self.getCacheEntry(project_name) orelse return false;

        // Check source hash
        if (!std.mem.eql(u8, entry.source_hash, current_source_hash)) {
            return false;
        }

        // Check dependencies
        if (entry.dependencies.len != dependencies.len) return false;
        for (entry.dependencies, dependencies) |cached_dep, current_dep| {
            if (!std.mem.eql(u8, cached_dep, current_dep)) return false;
        }

        // Check build flags
        if (entry.build_flags.len != build_flags.len) return false;
        for (entry.build_flags, build_flags) |cached_flag, current_flag| {
            if (!std.mem.eql(u8, cached_flag, current_flag)) return false;
        }

        // Check if output files still exist
        for (entry.output_files) |output_file| {
            const full_path = try fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, output_file });
            defer self.allocator.free(full_path);

            cwd.access(io, full_path, .{}) catch return false;
        }

        return true;
    }

    pub fn storeBuildResult(self: *BuildCache, project_name: []const u8, source_hash: []const u8, build_hash: []const u8, dependencies: [][]const u8, build_flags: [][]const u8, output_files: [][]const u8) !void {
        var owned_dependencies: std.ArrayListUnmanaged([]const u8) = .empty;
        defer owned_dependencies.deinit(self.allocator);

        for (dependencies) |dep| {
            try owned_dependencies.append(self.allocator, try self.allocator.dupe(u8, dep));
        }

        var owned_build_flags: std.ArrayListUnmanaged([]const u8) = .empty;
        defer owned_build_flags.deinit(self.allocator);

        for (build_flags) |flag| {
            try owned_build_flags.append(self.allocator, try self.allocator.dupe(u8, flag));
        }

        var owned_output_files: std.ArrayListUnmanaged([]const u8) = .empty;
        defer owned_output_files.deinit(self.allocator);

        for (output_files) |file| {
            try owned_output_files.append(self.allocator, try self.allocator.dupe(u8, file));
        }

        const entry = CacheEntry{
            .source_hash = try self.allocator.dupe(u8, source_hash),
            .build_hash = try self.allocator.dupe(u8, build_hash),
            .timestamp = zion_root.timestamp(),
            .dependencies = try owned_dependencies.toOwnedSlice(self.allocator),
            .build_flags = try owned_build_flags.toOwnedSlice(self.allocator),
            .output_files = try owned_output_files.toOwnedSlice(self.allocator),
        };

        // Remove old entry if exists
        if (self.entries.get(project_name)) |old_entry| {
            var mut_entry = old_entry;
            mut_entry.deinit(self.allocator);
            _ = self.entries.remove(project_name);
            self.allocator.free(project_name);
        }

        const owned_name = try self.allocator.dupe(u8, project_name);
        try self.entries.put(owned_name, entry);
    }

    pub fn restoreCachedBuild(self: *BuildCache, project_name: []const u8, output_dir: []const u8) !bool {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        const entry = self.getCacheEntry(project_name) orelse return false;

        std.debug.print("🔄 Restoring build from cache for {s}...\n", .{project_name});

        // Copy cached output files to target directory
        cwd.createDirPath(io, output_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        for (entry.output_files) |output_file| {
            const cached_path = try fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, output_file });
            defer self.allocator.free(cached_path);

            const target_path = try fs.path.join(self.allocator, &[_][]const u8{ output_dir, fs.path.basename(output_file) });
            defer self.allocator.free(target_path);

            try cwd.copyFile(cached_path, cwd, target_path, io, .{});
        }

        std.debug.print("✅ Successfully restored build from cache\n", .{});
        return true;
    }

    pub fn cacheBuildOutput(self: *BuildCache, _: []const u8, output_files: [][]const u8) !void {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        for (output_files) |output_file| {
            const filename = fs.path.basename(output_file);
            const cached_path = try fs.path.join(self.allocator, &[_][]const u8{ self.cache_dir, filename });
            defer self.allocator.free(cached_path);

            try cwd.copyFile(output_file, cwd, cached_path, io, .{});
        }
    }

    pub fn clearCache(self: *BuildCache) !void {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.clearRetainingCapacity();

        // Remove cache directory contents
        var cache_dir = cwd.openDir(io, self.cache_dir, .{ .iterate = true }) catch return;
        defer cache_dir.close(io);

        var walker = try cache_dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next(io)) |entry| {
            if (entry.kind == .file) {
                try cache_dir.deleteFile(io, entry.path);
            }
        }

        std.debug.print("🗑️  Build cache cleared\n", .{});
    }

    pub fn getStats(self: *const BuildCache, allocator: Allocator) !CacheStats {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        var total_size: u64 = 0;
        var file_count: u64 = 0;

        var cache_dir = cwd.openDir(io, self.cache_dir, .{ .iterate = true }) catch {
            return CacheStats{
                .entry_count = self.entries.count(),
                .total_size_bytes = 0,
                .file_count = 0,
                .cache_dir = try allocator.dupe(u8, self.cache_dir),
            };
        };
        defer cache_dir.close(io);

        var walker = try cache_dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next(io)) |entry| {
            if (entry.kind == .file) {
                const file = try cache_dir.openFile(io, entry.path, .{});
                defer file.close(io);
                const stat = try file.stat(io);
                total_size += stat.size;
                file_count += 1;
            }
        }

        return CacheStats{
            .entry_count = self.entries.count(),
            .total_size_bytes = total_size,
            .file_count = file_count,
            .cache_dir = try allocator.dupe(u8, self.cache_dir),
        };
    }
};

pub const CacheStats = struct {
    entry_count: u32,
    total_size_bytes: u64,
    file_count: u64,
    cache_dir: []const u8,

    pub fn deinit(self: *CacheStats, allocator: Allocator) void {
        allocator.free(self.cache_dir);
    }
};
