const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const zion_root = @import("root.zig");
const AtomicFile = @import("atomic_file.zig").AtomicFile;

/// Escapes a string for safe use in ZON string literals
/// Handles: backslash, double quote, newline, carriage return, tab, and control chars
fn escapeZonString(allocator: Allocator, input: []const u8) ![]u8 {
    // Calculate required size
    var required_size: usize = 0;
    for (input) |c| {
        required_size += switch (c) {
            '\\', '"' => 2,
            '\n', '\r', '\t' => 2,
            else => if (c < 0x20) 4 else 1, // \xNN for control chars
        };
    }

    // If no escaping needed, just dupe
    if (required_size == input.len) {
        return try allocator.dupe(u8, input);
    }

    var result = try allocator.alloc(u8, required_size);
    var i: usize = 0;
    for (input) |c| {
        switch (c) {
            '\\' => {
                result[i] = '\\';
                result[i + 1] = '\\';
                i += 2;
            },
            '"' => {
                result[i] = '\\';
                result[i + 1] = '"';
                i += 2;
            },
            '\n' => {
                result[i] = '\\';
                result[i + 1] = 'n';
                i += 2;
            },
            '\r' => {
                result[i] = '\\';
                result[i + 1] = 'r';
                i += 2;
            },
            '\t' => {
                result[i] = '\\';
                result[i + 1] = 't';
                i += 2;
            },
            else => {
                if (c < 0x20) {
                    // Escape control characters as \xNN
                    const hex = "0123456789abcdef";
                    result[i] = '\\';
                    result[i + 1] = 'x';
                    result[i + 2] = hex[c >> 4];
                    result[i + 3] = hex[c & 0xf];
                    i += 4;
                } else {
                    result[i] = c;
                    i += 1;
                }
            },
        }
    }
    return result;
}

fn unescapeZonString(allocator: Allocator, input: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (c != '\\') {
            try result.append(allocator, c);
            continue;
        }

        i += 1;
        if (i >= input.len) return error.InvalidEscapeSequence;

        switch (input[i]) {
            '\\' => try result.append(allocator, '\\'),
            '"' => try result.append(allocator, '"'),
            'n' => try result.append(allocator, '\n'),
            'r' => try result.append(allocator, '\r'),
            't' => try result.append(allocator, '\t'),
            'x' => {
                if (i + 2 >= input.len) return error.InvalidEscapeSequence;
                const hi = std.fmt.charToDigit(input[i + 1], 16) catch return error.InvalidEscapeSequence;
                const lo = std.fmt.charToDigit(input[i + 2], 16) catch return error.InvalidEscapeSequence;
                try result.append(allocator, @as(u8, @intCast((hi << 4) | lo)));
                i += 2;
            },
            else => return error.InvalidEscapeSequence,
        }
    }

    return result.toOwnedSlice(allocator);
}

fn isValidBareIdentifier(name: []const u8) bool {
    if (name.len == 0) return false;
    const first = name[0];
    if (!std.ascii.isAlphabetic(first) and first != '_') return false;

    for (name[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    }

    return true;
}

fn formatDependencyKey(allocator: Allocator, name: []const u8) ![]u8 {
    if (isValidBareIdentifier(name)) {
        return std.fmt.allocPrint(allocator, ".{s}", .{name});
    }

    const escaped = try escapeZonString(allocator, name);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, ".@\"{s}\"", .{escaped});
}

fn formatProjectNameValue(allocator: Allocator, name: []const u8) ![]u8 {
    if (isValidBareIdentifier(name)) {
        return std.fmt.allocPrint(allocator, ".{s}", .{name});
    }

    const escaped = try escapeZonString(allocator, name);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, "\"{s}\"", .{escaped});
}

fn parseQuotedZonValueRange(content: []const u8, value_start: usize) ?struct { start: usize, end: usize } {
    var i = value_start;
    while (i < content.len) : (i += 1) {
        if (content[i] != '"') continue;

        var backslashes: usize = 0;
        var j = i;
        while (j > value_start and content[j - 1] == '\\') : (j -= 1) {
            backslashes += 1;
        }

        if (backslashes % 2 == 0) {
            return .{ .start = value_start, .end = i };
        }
    }

    return null;
}

/// Represents a dependency in the build.zig.zon file
pub const Dependency = struct {
    url: []const u8,
    hash: []const u8,
    version: ?[]const u8 = null,
    registry: ?[]const u8 = null,
    resolved_from: ?[]const u8 = null,
    dev_only: bool = false,
    comment: ?[]const u8 = null,

    pub fn deinit(self: *Dependency, allocator: Allocator) void {
        allocator.free(self.url);
        allocator.free(self.hash);
        if (self.version) |v| allocator.free(v);
        if (self.registry) |r| allocator.free(r);
        if (self.resolved_from) |rf| allocator.free(rf);
        if (self.comment) |c| allocator.free(c);
    }
};

/// Represents the build.zig.zon manifest file
pub const ZonFile = struct {
    const DepRange = struct {
        start: usize,
        end: usize,
    };

    name: []const u8,
    version: []const u8,
    dependencies_prefix: ?[]const u8,
    dependencies_body_leading: ?[]const u8,
    dependencies_body_trailing: ?[]const u8,
    dependencies_suffix: ?[]const u8,
    dependencies: std.HashMap([]const u8, Dependency, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    dev_dependencies: std.HashMap([]const u8, Dependency, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    comments: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,

    /// Initialize a new ZON file structure
    pub fn init(allocator: Allocator, name: []const u8, version: []const u8) !ZonFile {
        return ZonFile{
            .name = try allocator.dupe(u8, name),
            .version = try allocator.dupe(u8, version),
            .dependencies_prefix = null,
            .dependencies_body_leading = null,
            .dependencies_body_trailing = null,
            .dependencies_suffix = null,
            .dependencies = std.HashMap([]const u8, Dependency, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .dev_dependencies = std.HashMap([]const u8, Dependency, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .comments = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .allocator = allocator,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *ZonFile) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        if (self.dependencies_prefix) |prefix| self.allocator.free(prefix);
        if (self.dependencies_body_leading) |leading| self.allocator.free(leading);
        if (self.dependencies_body_trailing) |trailing| self.allocator.free(trailing);
        if (self.dependencies_suffix) |suffix| self.allocator.free(suffix);

        var it = self.dependencies.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.dependencies.deinit();

        var dev_it = self.dev_dependencies.iterator();
        while (dev_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.dev_dependencies.deinit();

        var comment_it = self.comments.iterator();
        while (comment_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.comments.deinit();
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

    pub fn removeDependency(self: *ZonFile, name: []const u8, dev_only: bool) bool {
        var dependencies = if (dev_only) &self.dev_dependencies else &self.dependencies;
        var iterator = dependencies.iterator();
        while (iterator.next()) |entry| {
            if (!std.mem.eql(u8, entry.key_ptr.*, name)) continue;
            const owned_name = entry.key_ptr.*;
            entry.value_ptr.deinit(self.allocator);
            _ = dependencies.remove(name);
            self.allocator.free(owned_name);
            return true;
        }
        return false;
    }

    /// Load ZON file from disk
    pub fn loadFromFile(allocator: Allocator, file_path: []const u8) !ZonFile {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();
        const content = try cwd.readFileAlloc(io, file_path, allocator, Io.Limit.limited(10 * 1024 * 1024));
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

        if (findDependenciesBlockRange(content)) |dep_block| {
            const closing_line_start = findLineStart(content, dep_block.body_end);
            const dependency_suffix_start = if (closing_line_start < dep_block.body_start) dep_block.body_end else closing_line_start;
            zon_file.dependencies_prefix = try allocator.dupe(u8, content[0..dep_block.body_start]);
            zon_file.dependencies_suffix = try allocator.dupe(u8, content[dependency_suffix_start..]);

            var parsed_ranges = try parseDependenciesWithRanges(allocator, content, &zon_file, dep_block.body_start, dependency_suffix_start);
            defer parsed_ranges.deinit(allocator);

            if (parsed_ranges.items.len > 0) {
                const first = parsed_ranges.items[0];
                const last = parsed_ranges.items[parsed_ranges.items.len - 1];
                zon_file.dependencies_body_leading = try allocator.dupe(u8, content[dep_block.body_start..first.start]);
                zon_file.dependencies_body_trailing = try allocator.dupe(u8, content[last.end..dependency_suffix_start]);
            } else {
                zon_file.dependencies_body_leading = try allocator.dupe(u8, content[dep_block.body_start..dependency_suffix_start]);
                zon_file.dependencies_body_trailing = try allocator.dupe(u8, "");
            }
        } else {
            // Parse dependencies with improved parser for non-standard files.
            try parseDependencies(allocator, content, &zon_file);
        }

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

    fn parseOwnedZonField(allocator: Allocator, content: []const u8, field_name: []const u8) ?[]const u8 {
        var pattern_buf: [64]u8 = undefined;
        const search_pattern = std.fmt.bufPrint(&pattern_buf, "{s} = \"", .{field_name}) catch return null;

        if (std.mem.indexOf(u8, content, search_pattern)) |start_pos| {
            const value_start = start_pos + search_pattern.len;
            const range = parseQuotedZonValueRange(content, value_start) orelse return null;
            return unescapeZonString(allocator, content[range.start..range.end]) catch return null;
        }

        return null;
    }

    /// Parse dependencies section from ZON content
    fn parseDependencies(allocator: Allocator, content: []const u8, zon_file: *ZonFile) !void {
        const dep_block = findDependenciesBlockRange(content) orelse return;

        var pos = dep_block.body_start;
        var brace_depth: u32 = 0;
        while (pos < dep_block.body_end) {
            const c = content[pos];
            if (c == '{') {
                brace_depth += 1;
            } else if (c == '}') {
                if (brace_depth > 0) brace_depth -= 1;
            } else if (c == '.' and brace_depth == 0 and isDependencyEntryStart(content, pos)) {
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

    fn parseDependenciesWithRanges(
        allocator: Allocator,
        content: []const u8,
        zon_file: *ZonFile,
        body_start: usize,
        body_end_exclusive: usize,
    ) !std.ArrayList(DepRange) {
        var ranges: std.ArrayList(DepRange) = .empty;

        var pos = body_start;
        var brace_depth: u32 = 0;
        while (pos < body_end_exclusive) {
            const c = content[pos];
            if (c == '{') {
                brace_depth += 1;
                pos += 1;
                continue;
            }
            if (c == '}') {
                if (brace_depth > 0) brace_depth -= 1;
                pos += 1;
                continue;
            }

            if (c == '.' and brace_depth == 0 and isDependencyEntryStart(content, pos)) {
                if (parseDependencyEntry(allocator, content[pos..])) |dep_entry| {
                    defer allocator.free(dep_entry.name);
                    defer allocator.free(dep_entry.url);
                    defer allocator.free(dep_entry.hash);

                    try zon_file.addDependency(dep_entry.name, dep_entry.url, dep_entry.hash);

                    const entry_start = findLineStart(content, pos);
                    var entry_end = pos + dep_entry.bytes_consumed;

                    while (entry_end < body_end_exclusive and (content[entry_end] == ' ' or content[entry_end] == '\t')) {
                        entry_end += 1;
                    }
                    if (entry_end < body_end_exclusive and content[entry_end] == ',') {
                        entry_end += 1;
                    }
                    if (entry_end < body_end_exclusive and content[entry_end] == '\r') {
                        entry_end += 1;
                    }
                    if (entry_end < body_end_exclusive and content[entry_end] == '\n') {
                        entry_end += 1;
                    }

                    try ranges.append(allocator, .{ .start = entry_start, .end = entry_end });
                    pos = entry_end;
                    continue;
                }
            }

            pos += 1;
        }

        return ranges;
    }

    fn findDependenciesBlockRange(content: []const u8) ?struct { body_start: usize, body_end: usize } {
        const deps_start = ".dependencies = .{";
        const deps_start_pos = std.mem.indexOf(u8, content, deps_start) orelse return null;

        const body_start = deps_start_pos + deps_start.len;
        var pos = body_start;
        var brace_depth: u32 = 1;

        while (pos < content.len) {
            const c = content[pos];
            if (c == '{') {
                brace_depth += 1;
            } else if (c == '}') {
                brace_depth -= 1;
                if (brace_depth == 0) {
                    return .{ .body_start = body_start, .body_end = pos };
                }
            }
            pos += 1;
        }

        return null;
    }

    /// Parse a single dependency entry
    fn parseDependencyEntry(allocator: Allocator, content: []const u8) ?struct { name: []const u8, url: []const u8, hash: []const u8, bytes_consumed: usize } {
        // Look for pattern: .name = .{ .url = "...", .hash = "...", }
        if (!std.mem.startsWith(u8, content, ".")) return null;

        var name_end: usize = 0;
        const dep_name = blk: {
            if (content.len > 3 and content[1] == '@' and content[2] == '"') {
                var quoted_end: usize = 3;
                while (quoted_end < content.len and content[quoted_end] != '"') {
                    quoted_end += 1;
                }
                if (quoted_end >= content.len) return null;
                name_end = quoted_end + 1;
                break :blk unescapeZonString(allocator, content[3..quoted_end]) catch return null;
            }

            var bare_end: usize = 1;
            while (bare_end < content.len) {
                const c = content[bare_end];
                if (!std.ascii.isAlphanumeric(c) and c != '_') break;
                bare_end += 1;
            }
            if (bare_end <= 1) return null;
            name_end = bare_end;
            break :blk allocator.dupe(u8, content[1..bare_end]) catch return null;
        };
        errdefer allocator.free(dep_name);

        // Look for the dependency block
        const block_start = std.mem.indexOf(u8, content[name_end..], ".{") orelse return null;
        const block_content_start = name_end + block_start + 2;

        // Find matching closing brace
        var brace_depth: u32 = 1;
        var block_end = block_content_start;
        while (block_end < content.len and brace_depth > 0) {
            const c = content[block_end];
            if (c == '{') brace_depth += 1 else if (c == '}') brace_depth -= 1;
            block_end += 1;
        }

        if (brace_depth > 0) return null;

        const block_content = content[block_content_start .. block_end - 1];

        // Extract URL and hash
        const url = parseOwnedZonField(allocator, block_content, ".url") orelse return null;
        errdefer allocator.free(url);
        const hash = parseOwnedZonField(allocator, block_content, ".hash") orelse return null;
        errdefer allocator.free(hash);

        return .{
            .name = dep_name,
            .url = url,
            .hash = hash,
            .bytes_consumed = block_end,
        };
    }

    fn findLineStart(content: []const u8, pos: usize) usize {
        if (pos == 0) return 0;
        var i = pos;
        while (i > 0) {
            if (content[i - 1] == '\n') return i;
            i -= 1;
        }
        return 0;
    }

    fn isDependencyEntryStart(content: []const u8, pos: usize) bool {
        const line_start = findLineStart(content, pos);
        var i = line_start;
        while (i < pos and (content[i] == ' ' or content[i] == '\t')) : (i += 1) {}
        return i == pos;
    }

    /// Save ZON file to disk with proper Zig identifier format
    pub fn saveToFile(self: *const ZonFile, file_path: []const u8) !void {
        const io = try zion_root.getIo();
        var replacement = try AtomicFile.init(self.allocator, io, file_path);
        defer replacement.deinit();
        const file = replacement.file;

        if (self.dependencies_prefix) |prefix| {
            try file.writeStreamingAll(io, prefix);
            if (self.dependencies_body_leading) |leading| {
                try file.writeStreamingAll(io, leading);
            }
        } else {
            // Fallback when we do not have source template context.
            try file.writeStreamingAll(io, ".{\n");

            const formatted_name = try formatProjectNameValue(self.allocator, self.name);
            defer self.allocator.free(formatted_name);
            const name_line = try std.fmt.allocPrint(self.allocator, "    .name = {s},\n", .{formatted_name});
            defer self.allocator.free(name_line);
            try file.writeStreamingAll(io, name_line);

            const escaped_version = try escapeZonString(self.allocator, self.version);
            defer self.allocator.free(escaped_version);
            const version_line = try std.fmt.allocPrint(self.allocator, "    .version = \"{s}\",\n", .{escaped_version});
            defer self.allocator.free(version_line);
            try file.writeStreamingAll(io, version_line);

            try file.writeStreamingAll(io, "    .dependencies = .{");
        }

        var it = self.dependencies.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const dep = entry.value_ptr.*;
            const formatted_key = try formatDependencyKey(self.allocator, name);
            defer self.allocator.free(formatted_key);
            const dep_name_line = try std.fmt.allocPrint(self.allocator, "        {s} = .{{\n", .{formatted_key});
            defer self.allocator.free(dep_name_line);
            try file.writeStreamingAll(io, dep_name_line);

            const escaped_url = try escapeZonString(self.allocator, dep.url);
            defer self.allocator.free(escaped_url);
            const dep_url_line = try std.fmt.allocPrint(self.allocator, "            .url = \"{s}\",\n", .{escaped_url});
            defer self.allocator.free(dep_url_line);
            try file.writeStreamingAll(io, dep_url_line);

            const escaped_hash = try escapeZonString(self.allocator, dep.hash);
            defer self.allocator.free(escaped_hash);
            const dep_hash_line = try std.fmt.allocPrint(self.allocator, "            .hash = \"{s}\",\n", .{escaped_hash});
            defer self.allocator.free(dep_hash_line);
            try file.writeStreamingAll(io, dep_hash_line);

            try file.writeStreamingAll(io, "        },\n");
        }

        if (self.dependencies_body_trailing) |trailing| {
            try file.writeStreamingAll(io, trailing);
        }

        if (self.dependencies_suffix) |suffix| {
            try file.writeStreamingAll(io, suffix);
            try replacement.commit();
            return;
        }

        try file.writeStreamingAll(io, "    },\n");

        // Add development dependencies section if any exist
        if (self.dev_dependencies.count() > 0) {
            try file.writeStreamingAll(io, "    .dev_dependencies = .{\n");

            var dev_it = self.dev_dependencies.iterator();
            while (dev_it.next()) |entry| {
                const name = entry.key_ptr.*;
                const dep = entry.value_ptr.*;

                const formatted_key = try formatDependencyKey(self.allocator, name);
                defer self.allocator.free(formatted_key);
                const dev_dep_name_line = try std.fmt.allocPrint(self.allocator, "        {s} = .{{\n", .{formatted_key});
                defer self.allocator.free(dev_dep_name_line);
                try file.writeStreamingAll(io, dev_dep_name_line);

                const escaped_dev_url = try escapeZonString(self.allocator, dep.url);
                defer self.allocator.free(escaped_dev_url);
                const dev_dep_url_line = try std.fmt.allocPrint(self.allocator, "            .url = \"{s}\",\n", .{escaped_dev_url});
                defer self.allocator.free(dev_dep_url_line);
                try file.writeStreamingAll(io, dev_dep_url_line);

                const escaped_dev_hash = try escapeZonString(self.allocator, dep.hash);
                defer self.allocator.free(escaped_dev_hash);
                const dev_dep_hash_line = try std.fmt.allocPrint(self.allocator, "            .hash = \"{s}\",\n", .{escaped_dev_hash});
                defer self.allocator.free(dev_dep_hash_line);
                try file.writeStreamingAll(io, dev_dep_hash_line);

                try file.writeStreamingAll(io, "        },\n");
            }

            try file.writeStreamingAll(io, "    },\n");
        }

        try file.writeStreamingAll(io, "}\n");
        try replacement.commit();
    }

    /// Add a development dependency
    pub fn addDevDependency(self: *ZonFile, name: []const u8, url: []const u8, hash: []const u8) !void {
        // Check if dependency already exists and free old memory
        if (self.dev_dependencies.get(name)) |existing_dep| {
            var old_dep = existing_dep;
            old_dep.deinit(self.allocator);

            // Find and free the key
            var it = self.dev_dependencies.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, name)) {
                    self.allocator.free(entry.key_ptr.*);
                    break;
                }
            }
            _ = self.dev_dependencies.remove(name);
        }

        const dep = Dependency{
            .url = try self.allocator.dupe(u8, url),
            .hash = try self.allocator.dupe(u8, hash),
            .dev_only = true,
        };

        const name_copy = try self.allocator.dupe(u8, name);
        try self.dev_dependencies.put(name_copy, dep);
    }

    /// Add a comment for a dependency
    pub fn addComment(self: *ZonFile, name: []const u8, comment: []const u8) !void {
        // Check if comment already exists and free old memory
        if (self.comments.get(name)) |existing_comment| {
            self.allocator.free(existing_comment);

            // Find and free the key
            var it = self.comments.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, name)) {
                    self.allocator.free(entry.key_ptr.*);
                    break;
                }
            }
            _ = self.comments.remove(name);
        }

        const name_copy = try self.allocator.dupe(u8, name);
        const comment_copy = try self.allocator.dupe(u8, comment);
        try self.comments.put(name_copy, comment_copy);
    }
};

test "dependency key rendering supports non-identifiers" {
    const allocator = std.testing.allocator;

    const bare = try formatDependencyKey(allocator, "libxev");
    defer allocator.free(bare);
    try std.testing.expectEqualStrings(".libxev", bare);

    const escaped = try formatDependencyKey(allocator, "zig-clap");
    defer allocator.free(escaped);
    try std.testing.expectEqualStrings(".@\"zig-clap\"", escaped);
}

test "development dependency removal is idempotent" {
    var zon = try ZonFile.init(std.testing.allocator, "fixture", "1.0.0");
    defer zon.deinit();
    try zon.addDevDependency("tool", "https://example.test/tool.tar.gz", "hash");
    try std.testing.expect(zon.removeDependency("tool", true));
    try std.testing.expect(!zon.removeDependency("tool", true));
}
