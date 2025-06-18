const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Represents a dependency in the build.zig.zon file
pub const Dependency = struct {
    url: []const u8,
    hash: []const u8,

    pub fn deinit(self: *Dependency, allocator: Allocator) void {
        allocator.free(self.url);
        allocator.free(self.hash);
    }
};

/// Represents the build.zig.zon manifest file
pub const ZonFile = struct {
    name: []const u8,
    version: []const u8,
    dependencies: std.HashMap([]const u8, Dependency, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,

    /// Initialize a new ZON file structure
    pub fn init(allocator: Allocator, name: []const u8, version: []const u8) !ZonFile {
        return ZonFile{
            .name = try allocator.dupe(u8, name),
            .version = try allocator.dupe(u8, version),
            .dependencies = std.HashMap([]const u8, Dependency, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *ZonFile) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);

        var it = self.dependencies.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.dependencies.deinit();
    }

    /// Add a dependency to the ZON file
    pub fn addDependency(self: *ZonFile, name: []const u8, url: []const u8, hash: []const u8) !void {
        // Check if dependency already exists and free old memory
        if (self.dependencies.get(name)) |existing_dep| {
            var old_dep = existing_dep;
            old_dep.deinit(self.allocator);

            // Find and free the key
            var it = self.dependencies.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, name)) {
                    self.allocator.free(entry.key_ptr.*);
                    break;
                }
            }
            _ = self.dependencies.remove(name);
        }

        const dep = Dependency{
            .url = try self.allocator.dupe(u8, url),
            .hash = try self.allocator.dupe(u8, hash),
        };

        const name_copy = try self.allocator.dupe(u8, name);
        try self.dependencies.put(name_copy, dep);
    }

    /// Load ZON file from disk
    pub fn loadFromFile(allocator: Allocator, file_path: []const u8) !ZonFile {
        const cwd = fs.cwd();
        const content = try cwd.readFileAlloc(allocator, file_path, 10 * 1024 * 1024);
        defer allocator.free(content);

        return parseZonContent(allocator, content);
    }

    /// Parse ZON file content
    fn parseZonContent(allocator: Allocator, content: []const u8) !ZonFile {
        // Simple ZON parser - looks for key patterns
        var zon_file = try ZonFile.init(allocator, "unknown", "0.1.0");
        errdefer zon_file.deinit();

        // Parse name
        if (parseZonField(content, ".name")) |name_field| {
            allocator.free(zon_file.name);
            zon_file.name = try allocator.dupe(u8, name_field);
        }

        // Parse version
        if (parseZonField(content, ".version")) |version_field| {
            allocator.free(zon_file.version);
            zon_file.version = try allocator.dupe(u8, version_field);
        }

        // Parse dependencies - simplified implementation
        // In a production version, you'd use a proper ZON parser
        const deps_start = ".dependencies = .{";
        if (std.mem.indexOf(u8, content, deps_start)) |start_pos| {
            var pos = start_pos + deps_start.len;
            while (pos < content.len) {
                // Look for dependency entries
                if (std.mem.indexOfPos(u8, content, pos, ".")) |dot_pos| {
                    if (parseDependencyEntry(allocator, content[dot_pos..content.len])) |dep_entry| {
                        try zon_file.addDependency(dep_entry.name, dep_entry.url, dep_entry.hash);
                        allocator.free(dep_entry.name);
                        allocator.free(dep_entry.url);
                        allocator.free(dep_entry.hash);
                        pos = dot_pos + 1;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }
        }

        return zon_file;
    }

    /// Parse a simple field from ZON content
    fn parseZonField(content: []const u8, field_name: []const u8) ?[]const u8 {
        const search_pattern = std.fmt.allocPrint(std.heap.page_allocator, "{s} = \"", .{field_name}) catch return null;
        defer std.heap.page_allocator.free(search_pattern);

        if (std.mem.indexOf(u8, content, search_pattern)) |start_pos| {
            const value_start = start_pos + search_pattern.len;
            if (std.mem.indexOfPos(u8, content, value_start, "\"")) |end_pos| {
                return content[value_start..end_pos];
            }
        }
        return null;
    }

    /// Parse a dependency entry (simplified)
    fn parseDependencyEntry(allocator: Allocator, content: []const u8) ?struct { name: []const u8, url: []const u8, hash: []const u8 } {
        // This is a simplified parser - in production you'd use a proper ZON parser
        _ = allocator;
        _ = content;
        return null; // TODO: Implement proper dependency parsing
    }

    /// Save ZON file to disk
    pub fn saveToFile(self: *const ZonFile, file_path: []const u8) !void {
        const cwd = fs.cwd();
        const file = try cwd.createFile(file_path, .{ .truncate = true });
        defer file.close();

        // Write ZON format
        try file.writer().print(".{{\n", .{});
        try file.writer().print("    .name = \"{s}\",\n", .{self.name});
        try file.writer().print("    .version = \"{s}\",\n", .{self.version});
        try file.writer().print("    .dependencies = .{{\n", .{});

        var it = self.dependencies.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const dep = entry.value_ptr.*;
            try file.writer().print("        .{s} = .{{\n", .{name});
            try file.writer().print("            .url = \"{s}\",\n", .{dep.url});
            try file.writer().print("            .hash = \"{s}\",\n", .{dep.hash});
            try file.writer().print("        }},\n", .{});
        }

        try file.writer().print("    }},\n", .{});
        try file.writer().print("}}\n", .{});
    }
};
