const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const zion_root = @import("root.zig");

pub const LintResult = struct {
    file_path: []const u8,
    issues: []LintIssue,

    pub const LintIssue = struct {
        line: u32,
        column: u32,
        severity: Severity,
        rule: []const u8,
        message: []const u8,
        suggestion: ?[]const u8,

        pub const Severity = enum { @"error", warning, info, hint };

        pub fn deinit(self: *LintIssue, allocator: Allocator) void {
            allocator.free(self.rule);
            allocator.free(self.message);
            if (self.suggestion) |suggestion| {
                allocator.free(suggestion);
            }
        }
    };

    pub fn deinit(self: *LintResult, allocator: Allocator) void {
        allocator.free(self.file_path);
        for (self.issues) |*issue| {
            issue.deinit(allocator);
        }
        allocator.free(self.issues);
    }
};

pub const FormatResult = struct {
    original_content: []const u8,
    formatted_content: []const u8,
    changes_made: bool,

    pub fn deinit(self: *FormatResult, allocator: Allocator) void {
        allocator.free(self.original_content);
        allocator.free(self.formatted_content);
    }
};

pub const LintFormatConfig = struct {
    max_line_length: u32 = 120,
    tab_size: u32 = 4,
    use_spaces: bool = true,
    trailing_comma: bool = true,
    blank_line_before_fn: bool = true,
    enforce_naming_convention: bool = true,
    check_unused_variables: bool = true,
    check_missing_docs: bool = false,
    auto_fix_imports: bool = true,

    pub fn loadFromFile(allocator: Allocator, config_path: []const u8) !LintFormatConfig {
        const content = fs.cwd().readFileAlloc(config_path, allocator, @enumFromInt(1024 * 1024)) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("📝 No lint config found, using defaults\n", .{});
                return LintFormatConfig{};
            }
            return err;
        };
        defer allocator.free(content);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        return LintFormatConfig{
            .max_line_length = if (root.get("max_line_length")) |v| @as(u32, @intCast(v.integer)) else 120,
            .tab_size = if (root.get("tab_size")) |v| @as(u32, @intCast(v.integer)) else 4,
            .use_spaces = if (root.get("use_spaces")) |v| v.bool else true,
            .trailing_comma = if (root.get("trailing_comma")) |v| v.bool else true,
            .blank_line_before_fn = if (root.get("blank_line_before_fn")) |v| v.bool else true,
            .enforce_naming_convention = if (root.get("enforce_naming_convention")) |v| v.bool else true,
            .check_unused_variables = if (root.get("check_unused_variables")) |v| v.bool else true,
            .check_missing_docs = if (root.get("check_missing_docs")) |v| v.bool else false,
            .auto_fix_imports = if (root.get("auto_fix_imports")) |v| v.bool else true,
        };
    }
};

pub const ZigLinter = struct {
    allocator: Allocator,
    config: LintFormatConfig,

    pub fn init(allocator: Allocator, config: LintFormatConfig) ZigLinter {
        return ZigLinter{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn lintFile(self: *ZigLinter, file_path: []const u8) !LintResult {
        const content = try fs.cwd().readFileAlloc(file_path, self.allocator, @enumFromInt(10 * 1024 * 1024));
        defer self.allocator.free(content);

        var issues: std.ArrayList(LintResult.LintIssue) = .{};
        defer issues.deinit(self.allocator);

        try self.checkLineLength(content, &issues);
        try self.checkNamingConventions(content, &issues);
        try self.checkImportOrder(content, &issues);
        try self.checkUnusedVariables(content, &issues);
        try self.checkMissingDocs(content, &issues);

        return LintResult{
            .file_path = try self.allocator.dupe(u8, file_path),
            .issues = try issues.toOwnedSlice(self.allocator),
        };
    }

    fn checkLineLength(self: *ZigLinter, content: []const u8, issues: *std.ArrayList(LintResult.LintIssue)) !void {
        var line_num: u32 = 1;
        var line_start: usize = 0;

        for (content, 0..) |char, i| {
            if (char == '\n') {
                const line_length = i - line_start;
                if (line_length > self.config.max_line_length) {
                    try issues.append(self.allocator, LintResult.LintIssue{
                        .line = line_num,
                        .column = @as(u32, @intCast(line_length)),
                        .severity = .warning,
                        .rule = try self.allocator.dupe(u8, "line_length"),
                        .message = try std.fmt.allocPrint(self.allocator, "Line too long ({d} chars, max {d})", .{ line_length, self.config.max_line_length }),
                        .suggestion = try self.allocator.dupe(u8, "Consider breaking this line into multiple lines"),
                    });
                }
                line_num += 1;
                line_start = i + 1;
            }
        }
    }

    fn checkNamingConventions(self: *ZigLinter, content: []const u8, issues: *std.ArrayList(LintResult.LintIssue)) !void {
        if (!self.config.enforce_naming_convention) return;

        var line_num: u32 = 1;
        var i: usize = 0;

        while (i < content.len) {
            if (content[i] == '\n') {
                line_num += 1;
                i += 1;
                continue;
            }

            // Check for function definitions
            if (std.mem.startsWith(u8, content[i..], "fn ")) {
                i += 3;
                while (i < content.len and std.ascii.isWhitespace(content[i])) i += 1;

                const fn_start = i;
                while (i < content.len and (std.ascii.isAlphanumeric(content[i]) or content[i] == '_')) {
                    i += 1;
                }

                if (i > fn_start) {
                    const fn_name = content[fn_start..i];
                    if (fn_name.len > 0 and std.ascii.isUpper(fn_name[0])) {
                        try issues.append(self.allocator, LintResult.LintIssue{
                            .line = line_num,
                            .column = @as(u32, @intCast(fn_start)),
                            .severity = .warning,
                            .rule = try self.allocator.dupe(u8, "naming_convention"),
                            .message = try std.fmt.allocPrint(self.allocator, "Function name '{s}' should start with lowercase", .{fn_name}),
                            .suggestion = try std.fmt.allocPrint(self.allocator, "Consider renaming to '{c}{s}'", .{ std.ascii.toLower(fn_name[0]), fn_name[1..] }),
                        });
                    }
                }
            }

            // Check for struct/enum definitions
            if (std.mem.startsWith(u8, content[i..], "const ")) {
                i += 6;
                while (i < content.len and std.ascii.isWhitespace(content[i])) i += 1;

                const name_start = i;
                while (i < content.len and (std.ascii.isAlphanumeric(content[i]) or content[i] == '_')) {
                    i += 1;
                }

                if (i > name_start and i < content.len and content[i] == ' ') {
                    const name = content[name_start..i];
                    i += 1;
                    while (i < content.len and std.ascii.isWhitespace(content[i])) i += 1;

                    if (std.mem.startsWith(u8, content[i..], "= struct") or
                        std.mem.startsWith(u8, content[i..], "= enum") or
                        std.mem.startsWith(u8, content[i..], "= union"))
                    {
                        if (name.len > 0 and std.ascii.isLower(name[0])) {
                            try issues.append(self.allocator, LintResult.LintIssue{
                                .line = line_num,
                                .column = @as(u32, @intCast(name_start)),
                                .severity = .warning,
                                .rule = try self.allocator.dupe(u8, "naming_convention"),
                                .message = try std.fmt.allocPrint(self.allocator, "Type name '{s}' should start with uppercase", .{name}),
                                .suggestion = try std.fmt.allocPrint(self.allocator, "Consider renaming to '{c}{s}'", .{ std.ascii.toUpper(name[0]), name[1..] }),
                            });
                        }
                    }
                }
            }

            i += 1;
        }
    }

    fn checkImportOrder(self: *ZigLinter, content: []const u8, issues: *std.ArrayList(LintResult.LintIssue)) !void {
        if (!self.config.auto_fix_imports) return;

        var line_num: u32 = 1;
        var last_import: ?[]const u8 = null;
        var i: usize = 0;

        while (i < content.len) {
            if (std.mem.startsWith(u8, content[i..], "const ") and
                std.mem.indexOf(u8, content[i..], "@import(") != null)
            {
                const line_start = i;
                while (i < content.len and content[i] != '\n') i += 1;
                const import_line = content[line_start..i];

                if (last_import) |last| {
                    if (std.mem.order(u8, import_line, last) == .lt) {
                        try issues.append(self.allocator, LintResult.LintIssue{
                            .line = line_num,
                            .column = 1,
                            .severity = .info,
                            .rule = try self.allocator.dupe(u8, "import_order"),
                            .message = try self.allocator.dupe(u8, "Imports should be sorted alphabetically"),
                            .suggestion = try self.allocator.dupe(u8, "Run 'zion fmt' to auto-fix import order"),
                        });
                    }
                }
                last_import = import_line;
            }

            if (content[i] == '\n') line_num += 1;
            i += 1;
        }
    }

    fn checkUnusedVariables(self: *ZigLinter, content: []const u8, issues: *std.ArrayList(LintResult.LintIssue)) !void {
        if (!self.config.check_unused_variables) return;

        // Simple unused variable detection (would need AST for proper implementation)
        var line_num: u32 = 1;
        var i: usize = 0;

        while (i < content.len) {
            if (std.mem.startsWith(u8, content[i..], "var ") or std.mem.startsWith(u8, content[i..], "const ")) {
                const is_const = std.mem.startsWith(u8, content[i..], "const ");
                i += if (is_const) 6 else 4;

                while (i < content.len and std.ascii.isWhitespace(content[i])) i += 1;

                const var_start = i;
                while (i < content.len and (std.ascii.isAlphanumeric(content[i]) or content[i] == '_')) {
                    i += 1;
                }

                if (i > var_start) {
                    const var_name = content[var_start..i];

                    // Skip common patterns like _ or std
                    if (std.mem.eql(u8, var_name, "_") or std.mem.eql(u8, var_name, "std")) {
                        continue;
                    }

                    // Simple check: if variable name appears only once more in remaining content
                    const remaining = content[i..];
                    if (std.mem.count(u8, remaining, var_name) <= 1) {
                        try issues.append(self.allocator, LintResult.LintIssue{
                            .line = line_num,
                            .column = @as(u32, @intCast(var_start)),
                            .severity = .warning,
                            .rule = try self.allocator.dupe(u8, "unused_variable"),
                            .message = try std.fmt.allocPrint(self.allocator, "Variable '{s}' is potentially unused", .{var_name}),
                            .suggestion = try self.allocator.dupe(u8, "Consider removing or prefixing with '_'"),
                        });
                    }
                }
            }

            if (content[i] == '\n') line_num += 1;
            i += 1;
        }
    }

    fn checkMissingDocs(self: *ZigLinter, content: []const u8, issues: *std.ArrayList(LintResult.LintIssue)) !void {
        if (!self.config.check_missing_docs) return;

        var line_num: u32 = 1;
        var i: usize = 0;

        while (i < content.len) {
            if (std.mem.startsWith(u8, content[i..], "pub fn ")) {
                // Check if there's a doc comment above
                var check_i = i;
                var found_doc = false;

                // Look backwards for doc comments
                while (check_i > 0) {
                    check_i -= 1;
                    if (content[check_i] == '\n') {
                        if (check_i > 3 and std.mem.startsWith(u8, content[check_i - 3 ..], "///")) {
                            found_doc = true;
                            break;
                        }
                        if (!std.ascii.isWhitespace(content[check_i + 1])) {
                            break;
                        }
                    }
                }

                if (!found_doc) {
                    i += 7; // Skip "pub fn "
                    while (i < content.len and std.ascii.isWhitespace(content[i])) i += 1;

                    const fn_start = i;
                    while (i < content.len and content[i] != '(') i += 1;

                    if (i > fn_start) {
                        const fn_name = content[fn_start..i];
                        try issues.append(self.allocator, LintResult.LintIssue{
                            .line = line_num,
                            .column = 1,
                            .severity = .info,
                            .rule = try self.allocator.dupe(u8, "missing_docs"),
                            .message = try std.fmt.allocPrint(self.allocator, "Public function '{s}' is missing documentation", .{fn_name}),
                            .suggestion = try self.allocator.dupe(u8, "Add a doc comment with /// above the function"),
                        });
                    }
                }
            }

            if (content[i] == '\n') line_num += 1;
            i += 1;
        }
    }
};

pub const ZigFormatter = struct {
    allocator: Allocator,
    config: LintFormatConfig,

    pub fn init(allocator: Allocator, config: LintFormatConfig) ZigFormatter {
        return ZigFormatter{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn formatFile(self: *ZigFormatter, file_path: []const u8) !FormatResult {
        const original_content = try fs.cwd().readFileAlloc(file_path, self.allocator, @enumFromInt(10 * 1024 * 1024));

        // Use zig fmt for primary formatting
        var formatted_content = try self.runZigFmt(original_content);

        // Apply additional custom formatting rules
        const final_content = try self.applyCustomFormatting(formatted_content);
        self.allocator.free(formatted_content);

        const changes_made = !std.mem.eql(u8, original_content, final_content);

        return FormatResult{
            .original_content = original_content,
            .formatted_content = final_content,
            .changes_made = changes_made,
        };
    }

    fn runZigFmt(self: *ZigFormatter, content: []const u8) ![]const u8 {
        // Create temporary file
        const tmp_path = try std.fmt.allocPrint(self.allocator, "/tmp/zion_fmt_{d}.zig", .{zion_root.timestamp()});
        defer self.allocator.free(tmp_path);

        try fs.cwd().writeFile(tmp_path, content);
        defer fs.cwd().deleteFile(tmp_path) catch {};

        // Run zig fmt
        var child = std.process.Child.init(&[_][]const u8{ "zig", "fmt", tmp_path }, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();
        const result = try child.wait();

        if (result != .Exited or result.Exited != 0) {
            return try self.allocator.dupe(u8, content); // Return original if fmt fails
        }

        return try fs.cwd().readFileAlloc(tmp_path, self.allocator, @enumFromInt(10 * 1024 * 1024));
    }

    fn applyCustomFormatting(self: *ZigFormatter, content: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .{};
        defer result.deinit(self.allocator);

        var lines = std.mem.split(u8, content, "\n");
        var prev_line_was_fn = false;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            // Add blank line before function definitions if configured
            if (self.config.blank_line_before_fn and std.mem.startsWith(u8, trimmed, "fn ") or std.mem.startsWith(u8, trimmed, "pub fn ")) {
                if (!prev_line_was_fn and result.items.len > 0) {
                    try result.append(self.allocator, '\n');
                }
                prev_line_was_fn = true;
            } else {
                prev_line_was_fn = false;
            }

            // Apply indentation rules
            if (self.config.use_spaces) {
                var formatted_line: std.ArrayList(u8) = .{};
                defer formatted_line.deinit(self.allocator);

                var indent_count: u32 = 0;
                for (line) |char| {
                    if (char == '\t') {
                        for (0..self.config.tab_size) |_| {
                            try formatted_line.append(self.allocator, ' ');
                        }
                        indent_count += self.config.tab_size;
                    } else if (char == ' ' and indent_count < 100) { // Reasonable limit
                        try formatted_line.append(self.allocator, char);
                        indent_count += 1;
                    } else {
                        try formatted_line.appendSlice(self.allocator, line[@intCast(for (line, 0..) |c, i| if (c == char) break i)..]);
                        break;
                    }
                }

                try result.appendSlice(self.allocator, formatted_line.items);
            } else {
                try result.appendSlice(self.allocator, line);
            }

            try result.append(self.allocator, '\n');
        }

        // Remove trailing newline
        if (result.items.len > 0 and result.items[result.items.len - 1] == '\n') {
            _ = result.pop();
        }

        return try result.toOwnedSlice(self.allocator);
    }

    pub fn formatProject(self: *ZigFormatter, project_path: []const u8) !void {
        var project_dir = try fs.cwd().openDir(project_path, .{ .iterate = true });
        defer project_dir.close();

        var walker = try project_dir.walk(self.allocator);
        defer walker.deinit();

        var formatted_count: u32 = 0;
        var error_count: u32 = 0;

        while (try walker.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".zig")) {
                const full_path = try fs.path.join(self.allocator, &[_][]const u8{ project_path, entry.path });
                defer self.allocator.free(full_path);

                const result = self.formatFile(full_path) catch |err| {
                    std.debug.print("❌ Failed to format {s}: {}\n", .{ entry.path, err });
                    error_count += 1;
                    continue;
                };

                if (result.changes_made) {
                    try fs.cwd().writeFile(full_path, result.formatted_content);
                    std.debug.print("📝 Formatted {s}\n", .{entry.path});
                    formatted_count += 1;
                }

                var mut_result = result;
                mut_result.deinit(self.allocator);
            }
        }

        std.debug.print("✅ Formatted {d} files", .{formatted_count});
        if (error_count > 0) {
            std.debug.print(" ({d} errors)", .{error_count});
        }
        std.debug.print("\n", .{});
    }
};
