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
    pub fn parseZonContent(allocator: Allocator, content: []const u8) !ZonFile {
        // Parse name first to avoid "unknown" default
        const project_name = parseZonName(content) orelse "zion"; // Use "zion" as fallback
        const project_version = parseZonField(content, ".version") orelse "0.1.0";
        
        var zon_file = try ZonFile.init(allocator, project_name, project_version);
        errdefer zon_file.deinit();

        // Parse dependencies with improved parser
        try parseDependencies(allocator, content, &zon_file);

        return zon_file;
    }

    /// Parse name field (handles both .name = .identifier and .name = "string" formats)
    fn parseZonName(content: []const u8) ?[]const u8 {
        // Try identifier format first: .name = .identifier
        if (std.mem.indexOf(u8, content, ".name = .")) |start_pos| {
            const value_start = start_pos + 9; // ".name = .".len
            var end_pos = value_start;
            
            // Find end of identifier (alphanumeric + underscore)
            while (end_pos < content.len) {
                const c = content[end_pos];
                if (!std.ascii.isAlphanumeric(c) and c != '_') break;
                end_pos += 1;
            }
            
            if (end_pos > value_start) {
                return content[value_start..end_pos];
            }
        }
        
        // Fall back to quoted string format: .name = "string"
        if (parseZonField(content, ".name")) |quoted_name| {
            // Just return the quoted name as-is to avoid memory leak
            // The caller can handle normalization if needed
            return quoted_name;
        }
        
        return null;
    }
    
    /// Parse a simple field from ZON content (quoted strings)
    fn parseZonField(content: []const u8, field_name: []const u8) ?[]const u8 {
        // Use a fixed-size buffer to avoid allocation
        var pattern_buf: [64]u8 = undefined;
        const search_pattern = std.fmt.bufPrint(&pattern_buf, "{s} = \"", .{field_name}) catch return null;

        if (std.mem.indexOf(u8, content, search_pattern)) |start_pos| {
            const value_start = start_pos + search_pattern.len;
            if (std.mem.indexOfPos(u8, content, value_start, "\"")) |end_pos| {
                return content[value_start..end_pos];
            }
        }
        return null;
    }

    /// Parse dependencies section from ZON content
    fn parseDependencies(allocator: Allocator, content: []const u8, zon_file: *ZonFile) !void {
        const deps_start = ".dependencies = .{";
        const deps_start_pos = std.mem.indexOf(u8, content, deps_start) orelse return;
        
        var pos = deps_start_pos + deps_start.len;
        var brace_depth: u32 = 1;
        
        while (pos < content.len and brace_depth > 0) {
            const c = content[pos];
            if (c == '{') brace_depth += 1
            else if (c == '}') brace_depth -= 1
            else if (c == '.' and brace_depth == 1) {
                // Found a dependency entry
                if (parseDependencyEntry(allocator, content[pos..])) |dep_entry| {
                    try zon_file.addDependency(dep_entry.name, dep_entry.url, dep_entry.hash);
                    allocator.free(dep_entry.name);
                    allocator.free(dep_entry.url);
                    allocator.free(dep_entry.hash);
                }
            }
            pos += 1;
        }
    }
    
    /// Parse a single dependency entry
    fn parseDependencyEntry(allocator: Allocator, content: []const u8) ?struct { name: []const u8, url: []const u8, hash: []const u8 } {
        // Look for pattern: .name = .{ .url = "...", .hash = "...", }
        if (!std.mem.startsWith(u8, content, ".")) return null;
        
        // Extract dependency name
        var name_end: usize = 1;
        while (name_end < content.len) {
            const c = content[name_end];
            if (!std.ascii.isAlphanumeric(c) and c != '_') break;
            name_end += 1;
        }
        
        if (name_end <= 1) return null;
        const dep_name = content[1..name_end];
        
        // Look for the dependency block
        const block_start = std.mem.indexOf(u8, content[name_end..], ".{") orelse return null;
        const block_content_start = name_end + block_start + 2;
        
        // Find matching closing brace
        var brace_depth: u32 = 1;
        var block_end = block_content_start;
        while (block_end < content.len and brace_depth > 0) {
            const c = content[block_end];
            if (c == '{') brace_depth += 1
            else if (c == '}') brace_depth -= 1;
            block_end += 1;
        }
        
        if (brace_depth > 0) return null;
        
        const block_content = content[block_content_start..block_end-1];
        
        // Extract URL and hash
        const url = parseZonField(block_content, ".url") orelse return null;
        const hash = parseZonField(block_content, ".hash") orelse return null;
        
        return .{
            .name = allocator.dupe(u8, dep_name) catch return null,
            .url = allocator.dupe(u8, url) catch return null,
            .hash = allocator.dupe(u8, hash) catch return null,
        };
    }

    /// Save ZON file to disk with proper Zig identifier format
    pub fn saveToFile(self: *const ZonFile, file_path: []const u8) !void {
        const cwd = fs.cwd();
        const file = try cwd.createFile(file_path, .{ .truncate = true });
        defer file.close();

        // Write ZON format with proper identifier syntax
        try file.writer().print(".{{\n", .{});
        try file.writer().print("    .name = .{s},\n", .{self.name}); // Use identifier format
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
