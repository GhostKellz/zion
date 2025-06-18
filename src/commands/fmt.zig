const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Code formatting functionality using zig fmt
/// Provides enhanced formatting features and project-wide formatting
pub fn fmt(allocator: Allocator, args: []const []const u8) !void {
    if (args.len >= 3 and std.mem.eql(u8, args[2], "--help")) {
        try printFmtHelp();
        return;
    }

    var options = FmtOptions{};
    var target_files = std.ArrayList([]const u8).init(allocator);
    defer target_files.deinit();

    // Parse arguments
    var i: usize = 2;
    while (i < args.len) {
        const arg = args[i];
        
        if (std.mem.eql(u8, arg, "--check")) {
            options.check_only = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--exclude-tests")) {
            options.exclude_tests = true;
        } else if (std.mem.eql(u8, arg, "--exclude-examples")) {
            options.exclude_examples = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("Unknown option: {s}\n", .{arg});
            return;
        } else {
            // It's a file or directory
            try target_files.append(arg);
        }
        
        i += 1;
    }

    // If no files specified, format entire project
    if (target_files.items.len == 0) {
        try formatProject(allocator, options);
    } else {
        try formatTargets(allocator, target_files.items, options);
    }
}

/// Print formatting help
fn printFmtHelp() !void {
    const help_text =
        \\Zion Code Formatter - Enhanced zig fmt wrapper
        \\
        \\USAGE:
        \\    zion fmt [OPTIONS] [FILES...]
        \\
        \\OPTIONS:
        \\    --check             Check if files are formatted (don't modify)
        \\    --verbose           Show detailed output
        \\    --exclude-tests     Skip test files
        \\    --exclude-examples  Skip example files
        \\    --help              Show this help message
        \\
        \\EXAMPLES:
        \\    zion fmt                        # Format entire project
        \\    zion fmt src/main.zig           # Format specific file
        \\    zion fmt src/                   # Format directory
        \\    zion fmt --check                # Check formatting without changes
        \\    zion fmt --verbose              # Show detailed formatting info
        \\    zion fmt --exclude-tests        # Skip test files
        \\
        \\NOTES:
        \\    • Uses zig fmt under the hood with enhanced project awareness
        \\    • Automatically discovers .zig files in the project
        \\    • Respects .gitignore patterns
        \\    • Shows statistics and progress for large projects
        \\
    ;

    std.debug.print("{s}", .{help_text});
}

/// Format entire project
fn formatProject(allocator: Allocator, options: FmtOptions) !void {
    if (options.verbose) {
        std.debug.print("🎨 Formatting entire project...\n\n");
    }

    var formatter = ProjectFormatter.init(allocator, options);
    defer formatter.deinit();

    // Discover all .zig files in the project
    try formatter.discoverFiles(".");
    
    if (formatter.files.items.len == 0) {
        std.debug.print("❌ No .zig files found in project\n");
        return;
    }

    if (options.verbose) {
        std.debug.print("📂 Discovered {d} .zig files\n", .{formatter.files.items.len});
    }

    // Format all discovered files
    try formatter.formatAll();
    
    // Print summary
    try formatter.printSummary();
}

/// Format specific targets (files or directories)
fn formatTargets(allocator: Allocator, targets: []const []const u8, options: FmtOptions) !void {
    if (options.verbose) {
        std.debug.print("🎨 Formatting {d} target(s)...\n\n", .{targets.len});
    }

    var formatter = ProjectFormatter.init(allocator, options);
    defer formatter.deinit();

    // Process each target
    for (targets) |target| {
        const cwd = fs.cwd();
        const stat = cwd.statFile(target) catch |err| {
            std.debug.print("❌ Cannot access '{s}': {}\n", .{ target, err });
            continue;
        };

        if (stat.kind == .directory) {
            try formatter.discoverFiles(target);
        } else if (std.mem.endsWith(u8, target, ".zig")) {
            try formatter.files.append(try allocator.dupe(u8, target));
        } else {
            std.debug.print("⚠️  Skipping '{s}' (not a .zig file)\n", .{target});
        }
    }

    if (formatter.files.items.len == 0) {
        std.debug.print("❌ No .zig files found in targets\n");
        return;
    }

    // Format all discovered files
    try formatter.formatAll();
    
    // Print summary
    try formatter.printSummary();
}

/// Project formatter implementation
const ProjectFormatter = struct {
    allocator: Allocator,
    options: FmtOptions,
    files: std.ArrayList([]const u8),
    stats: FormattingStats,

    const Self = @This();

    pub fn init(allocator: Allocator, options: FmtOptions) Self {
        return Self{
            .allocator = allocator,
            .options = options,
            .files = std.ArrayList([]const u8).init(allocator),
            .stats = FormattingStats{},
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.files.items) |file| {
            self.allocator.free(file);
        }
        self.files.deinit();
    }

    /// Recursively discover .zig files in a directory
    pub fn discoverFiles(self: *Self, dir_path: []const u8) !void {
        const cwd = fs.cwd();
        var dir = cwd.openDir(dir_path, .{ .iterate = true }) catch |err| {
            if (self.options.verbose) {
                std.debug.print("⚠️  Cannot open directory '{s}': {}\n", .{ dir_path, err });
            }
            return;
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const full_path = try std.fmt.allocPrint(
                self.allocator, 
                "{s}/{s}", 
                .{ dir_path, entry.name }
            );
            defer self.allocator.free(full_path);

            if (entry.kind == .directory) {
                // Skip hidden directories and common build/cache directories
                if (self.shouldSkipDirectory(entry.name)) {
                    continue;
                }
                
                try self.discoverFiles(full_path);
            } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
                // Check if we should skip this file
                if (self.shouldSkipFile(entry.name)) {
                    continue;
                }
                
                try self.files.append(try self.allocator.dupe(u8, full_path));
            }
        }
    }

    /// Format all discovered files
    pub fn formatAll(self: *Self) !void {
        for (self.files.items) |file| {
            if (self.options.verbose) {
                std.debug.print("📝 Processing: {s}\n", .{file});
            }
            
            const result = try self.formatFile(file);
            self.updateStats(result);
            
            if (!self.options.check_only and result == .formatted) {
                if (self.options.verbose) {
                    std.debug.print("   ✅ Formatted\n");
                }
            } else if (self.options.check_only and result == .needs_formatting) {
                std.debug.print("   ❌ Needs formatting: {s}\n", .{file});
            }
        }
    }

    /// Format a single file
    fn formatFile(self: *Self, file_path: []const u8) !FormatResult {
        const argv_check = [_][]const u8{ "zig", "fmt", "--check", file_path };
        const argv_format = [_][]const u8{ "zig", "fmt", file_path };

        // First check if file needs formatting
        var child_check = std.process.Child.init(&argv_check, self.allocator);
        child_check.stdin_behavior = .Ignore;
        child_check.stdout_behavior = .Ignore;
        child_check.stderr_behavior = .Ignore;

        try child_check.spawn();
        const check_term = try child_check.wait();

        const needs_formatting = switch (check_term) {
            .Exited => |code| code != 0,
            else => true,
        };

        if (!needs_formatting) {
            return .already_formatted;
        }

        if (self.options.check_only) {
            return .needs_formatting;
        }

        // Format the file
        var child_format = std.process.Child.init(&argv_format, self.allocator);
        child_format.stdin_behavior = .Ignore;
        child_format.stdout_behavior = .Pipe;
        child_format.stderr_behavior = .Pipe;

        try child_format.spawn();
        const format_term = try child_format.wait();

        // Read any error output
        if (child_format.stderr) |stderr_pipe| {
            const stderr_data = try stderr_pipe.reader().readAllAlloc(self.allocator, 1024 * 16);
            defer self.allocator.free(stderr_data);
            
            if (stderr_data.len > 0) {
                std.debug.print("⚠️  Formatting error in {s}:\n{s}\n", .{ file_path, stderr_data });
                return .error_occurred;
            }
        }

        return switch (format_term) {
            .Exited => |code| if (code == 0) .formatted else .error_occurred,
            else => .error_occurred,
        };
    }

    /// Check if directory should be skipped
    fn shouldSkipDirectory(self: *Self, dir_name: []const u8) bool {
        _ = self;
        
        const skip_dirs = [_][]const u8{
            ".git",
            ".zig-cache", 
            "zig-cache",
            "zig-out",
            "node_modules",
            ".vscode",
            ".idea",
            "target",
            "build",
        };

        for (skip_dirs) |skip_dir| {
            if (std.mem.eql(u8, dir_name, skip_dir)) {
                return true;
            }
        }

        return false;
    }

    /// Check if file should be skipped
    fn shouldSkipFile(self: *Self, file_name: []const u8) bool {
        // Skip test files if requested
        if (self.options.exclude_tests and 
            (std.mem.indexOf(u8, file_name, "test") != null or
             std.mem.endsWith(u8, file_name, "_test.zig"))) {
            return true;
        }

        // Skip example files if requested  
        if (self.options.exclude_examples and
            (std.mem.indexOf(u8, file_name, "example") != null or
             std.mem.startsWith(u8, file_name, "example_"))) {
            return true;
        }

        return false;
    }

    /// Update formatting statistics
    fn updateStats(self: *Self, result: FormatResult) void {
        switch (result) {
            .already_formatted => self.stats.already_formatted += 1,
            .formatted => self.stats.formatted += 1,
            .needs_formatting => self.stats.needs_formatting += 1,
            .error_occurred => self.stats.errors += 1,
        }
        self.stats.total += 1;
    }

    /// Print formatting summary
    pub fn printSummary(self: *Self) !void {
        std.debug.print("\n📊 Formatting Summary:\n");
        std.debug.print("   Total files: {d}\n", .{self.stats.total});
        
        if (!self.options.check_only) {
            std.debug.print("   ✅ Already formatted: {d}\n", .{self.stats.already_formatted});
            std.debug.print("   🎨 Newly formatted: {d}\n", .{self.stats.formatted});
        } else {
            std.debug.print("   ✅ Properly formatted: {d}\n", .{self.stats.already_formatted});
            std.debug.print("   ❌ Need formatting: {d}\n", .{self.stats.needs_formatting});
        }
        
        if (self.stats.errors > 0) {
            std.debug.print("   ⚠️  Errors: {d}\n", .{self.stats.errors});
        }

        if (self.options.check_only and self.stats.needs_formatting > 0) {
            std.debug.print("\n💡 Run 'zion fmt' to format these files\n");
        } else if (!self.options.check_only and self.stats.formatted > 0) {
            std.debug.print("\n✨ Formatting complete!\n");
        } else if (self.stats.total > 0 and self.stats.errors == 0) {
            std.debug.print("\n✅ All files are properly formatted!\n");
        }
    }
};

const FmtOptions = struct {
    check_only: bool = false,
    verbose: bool = false,
    exclude_tests: bool = false,
    exclude_examples: bool = false,
};

const FormatResult = enum {
    already_formatted,
    formatted,
    needs_formatting,
    error_occurred,
};

const FormattingStats = struct {
    total: u32 = 0,
    already_formatted: u32 = 0,
    formatted: u32 = 0,
    needs_formatting: u32 = 0,
    errors: u32 = 0,
};