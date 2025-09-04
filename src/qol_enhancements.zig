const std = @import("std");
const Allocator = std.mem.Allocator;

/// Quality of Life Enhancements for Zion v1.0.6
/// Focuses on CLI improvements, smart suggestions, and user experience

/// Smart command suggestions system
pub const CommandSuggester = struct {
    commands: []const []const u8,
    
    const COMMANDS = [_][]const u8{
        "add", "remove", "update", "list", "info", "fetch", "pin", "unpin", 
        "repair", "check", "build", "clean", "lock", "run", "test", "doc", 
        "tree", "outdated", "hash", "config", "nvim", "security", "performance", 
        "search", "registry", "template", "debug", "fmt", "analyze", "version", 
        "zig", "zls", "workspace", "setup", "keyring", "archver", "help"
    };
    
    pub fn init() CommandSuggester {
        return CommandSuggester{
            .commands = &COMMANDS,
        };
    }
    
    /// Find the most similar command using edit distance
    pub fn suggestCommand(self: *const CommandSuggester, input: []const u8) ?[]const u8 {
        var best_match: ?[]const u8 = null;
        var best_distance: usize = std.math.maxInt(usize);
        const max_distance = @min(input.len / 2 + 1, 3); // Allow up to 3 typos
        
        for (self.commands) |cmd| {
            const distance = editDistance(input, cmd);
            if (distance < best_distance and distance <= max_distance) {
                best_distance = distance;
                best_match = cmd;
            }
            
            // Also check for prefix matches
            if (std.mem.startsWith(u8, cmd, input) and input.len >= 2) {
                return cmd;
            }
        }
        
        return best_match;
    }
    
    /// Get multiple suggestions for ambiguous inputs
    pub fn suggestCommands(self: *const CommandSuggester, allocator: Allocator, input: []const u8) ![][]const u8 {
        var suggestions: std.ArrayList([]const u8) = .{};
        defer suggestions.deinit(allocator);
        
        // Find prefix matches first
        for (self.commands) |cmd| {
            if (std.mem.startsWith(u8, cmd, input) and input.len >= 1) {
                try suggestions.append(allocator, cmd);
            }
        }
        
        // If no prefix matches, find similar commands
        if (suggestions.items.len == 0) {
            for (self.commands) |cmd| {
                const distance = editDistance(input, cmd);
                if (distance <= 2) {
                    try suggestions.append(allocator, cmd);
                }
            }
        }
        
        // Limit to top 5 suggestions
        if (suggestions.items.len > 5) {
            suggestions.shrinkRetainingCapacity(5);
        }
        
        return suggestions.toOwnedSlice(allocator);
    }
    
    /// Calculate edit distance between two strings
    fn editDistance(a: []const u8, b: []const u8) usize {
        const len_a = a.len;
        const len_b = b.len;
        
        // Use stack allocation for small strings
        if (len_a <= 32 and len_b <= 32) {
            var matrix: [33][33]usize = undefined;
            return editDistanceMatrix(a, b, &matrix);
        }
        
        // For larger strings, fall back to simpler metric
        var common: usize = 0;
        const min_len = @min(len_a, len_b);
        for (0..min_len) |i| {
            if (a[i] == b[i]) common += 1;
        }
        
        return len_a + len_b - (2 * common);
    }
    
    fn editDistanceMatrix(a: []const u8, b: []const u8, matrix: *[33][33]usize) usize {
        const len_a = a.len;
        const len_b = b.len;
        
        // Initialize matrix
        for (0..len_a + 1) |i| {
            matrix[i][0] = i;
        }
        for (0..len_b + 1) |j| {
            matrix[0][j] = j;
        }
        
        // Fill matrix
        for (1..len_a + 1) |i| {
            for (1..len_b + 1) |j| {
                const cost: usize = if (a[i-1] == b[j-1]) 0 else 1;
                matrix[i][j] = @min(
                    matrix[i-1][j] + 1,      // deletion
                    @min(
                        matrix[i][j-1] + 1,  // insertion
                        matrix[i-1][j-1] + cost  // substitution
                    )
                );
            }
        }
        
        return matrix[len_a][len_b];
    }
};

/// Enhanced progress indicators with animations
pub const ProgressIndicator = struct {
    current: usize,
    total: usize,
    start_time: i64,
    last_update: i64,
    spinner_frame: usize,
    
    const SPINNER_FRAMES = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
    const BAR_CHARS = [_][]const u8{ " ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" };
    
    pub fn init(total: usize) ProgressIndicator {
        return ProgressIndicator{
            .current = 0,
            .total = total,
            .start_time = std.time.milliTimestamp(),
            .last_update = std.time.milliTimestamp(),
            .spinner_frame = 0,
        };
    }
    
    pub fn update(self: *ProgressIndicator, current: usize, message: []const u8) void {
        self.current = current;
        const now = std.time.milliTimestamp();
        
        // Only update display every 100ms to avoid flicker
        if (now - self.last_update < 100) return;
        self.last_update = now;
        
        const percent = if (self.total > 0) (@as(f64, @floatFromInt(current)) / @as(f64, @floatFromInt(self.total))) * 100.0 else 0.0;
        const elapsed = now - self.start_time;
        
        // Estimate completion time
        const eta = if (current > 0) (elapsed * (@as(i64, @intCast(self.total)) - @as(i64, @intCast(current)))) / @as(i64, @intCast(current)) else 0;
        
        // Draw progress bar
        const bar_width = 30;
        const filled_width = (@as(f64, @floatFromInt(bar_width)) * percent / 100.0);
        const filled_chars = @as(usize, @intFromFloat(filled_width));
        const partial_char_index = @as(usize, @intFromFloat((filled_width - @as(f64, @floatFromInt(filled_chars))) * 8));
        
        std.debug.print("\r{s} [", .{SPINNER_FRAMES[self.spinner_frame % SPINNER_FRAMES.len]});
        
        for (0..bar_width) |i| {
            if (i < filled_chars) {
                std.debug.print("{s}", .{BAR_CHARS[8]});
            } else if (i == filled_chars and partial_char_index > 0) {
                std.debug.print("{s}", .{BAR_CHARS[partial_char_index]});
            } else {
                std.debug.print("{s}", .{BAR_CHARS[0]});
            }
        }
        
        std.debug.print("] {d:.1}% {s} ETA: {}s", .{ percent, message, @divFloor(eta, 1000) });
        
        self.spinner_frame += 1;
    }
    
    pub fn finish(self: *ProgressIndicator, success_message: []const u8) void {
        const elapsed = std.time.milliTimestamp() - self.start_time;
        std.debug.print("\r✅ {s} ({}ms)\n", .{ success_message, elapsed });
    }
    
    pub fn fail(self: *ProgressIndicator, error_message: []const u8) void {
        const elapsed = std.time.milliTimestamp() - self.start_time;
        std.debug.print("\r❌ {s} ({}ms)\n", .{ error_message, elapsed });
    }
};

/// Smart output formatting with colors and icons
pub const OutputFormatter = struct {
    use_colors: bool,
    
    pub fn init() OutputFormatter {
        // Check if terminal supports colors
        const term = std.posix.getenv("TERM");
        const use_colors = if (term) |t| 
            !std.mem.eql(u8, t, "dumb") and !std.mem.eql(u8, t, "")
        else 
            false;
            
        return OutputFormatter{ .use_colors = use_colors };
    }
    
    pub fn success(self: *const OutputFormatter, comptime fmt: []const u8, args: anytype) void {
        if (self.use_colors) {
            std.debug.print("\x1b[32m✅ " ++ fmt ++ "\x1b[0m\n", args);
        } else {
            std.debug.print("✅ " ++ fmt ++ "\n", args);
        }
    }
    
    pub fn error_msg(self: *const OutputFormatter, comptime fmt: []const u8, args: anytype) void {
        if (self.use_colors) {
            std.debug.print("\x1b[31m❌ " ++ fmt ++ "\x1b[0m\n", args);
        } else {
            std.debug.print("❌ " ++ fmt ++ "\n", args);
        }
    }
    
    pub fn warning(self: *const OutputFormatter, comptime fmt: []const u8, args: anytype) void {
        if (self.use_colors) {
            std.debug.print("\x1b[33m⚠️  " ++ fmt ++ "\x1b[0m\n", args);
        } else {
            std.debug.print("⚠️  " ++ fmt ++ "\n", args);
        }
    }
    
    pub fn info(self: *const OutputFormatter, comptime fmt: []const u8, args: anytype) void {
        if (self.use_colors) {
            std.debug.print("\x1b[34m💡 " ++ fmt ++ "\x1b[0m\n", args);
        } else {
            std.debug.print("💡 " ++ fmt ++ "\n", args);
        }
    }
    
    pub fn heading(self: *const OutputFormatter, comptime fmt: []const u8, args: anytype) void {
        if (self.use_colors) {
            std.debug.print("\x1b[1m\x1b[36m🚀 " ++ fmt ++ "\x1b[0m\n", args);
        } else {
            std.debug.print("🚀 " ++ fmt ++ "\n", args);
        }
    }
};

/// Performance optimization hints
pub const PerformanceHints = struct {
    pub fn analyzeAndSuggest(allocator: Allocator) !void {
        var formatter = OutputFormatter.init();
        
        formatter.heading("Performance Analysis & Recommendations");
        
        // Analyze system
        const cpu_count = std.Thread.getCpuCount() catch 1;
        const available_parallelism = @min(cpu_count, 8);
        
        formatter.info("System Analysis:");
        std.debug.print("  🖥️  CPU Cores: {} (recommending {} parallel downloads)\n", .{ cpu_count, available_parallelism });
        
        // Check cache directory
        const home_dir = std.posix.getenv("HOME") orelse "/tmp";
        const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.cache/zion", .{home_dir});
        defer allocator.free(cache_dir);
        
        var cache_size: u64 = 0;
        if (std.fs.cwd().openDir(cache_dir, .{ .iterate = true })) |dir| {
            var iterator = dir.iterate();
            while (iterator.next() catch null) |entry| {
                if (entry.kind == .file) {
                    const file_info = dir.statFile(entry.name) catch continue;
                    cache_size += file_info.size;
                }
            }
            dir.close();
        } else |_| {
            // Cache directory doesn't exist
        }
        
        std.debug.print("  🗄️  Cache Size: {d:.1}MB\n", .{@as(f64, @floatFromInt(cache_size)) / (1024.0 * 1024.0)});
        
        // Performance recommendations
        formatter.info("Recommendations:");
        
        if (cpu_count >= 4) {
            std.debug.print("  ⚡ Enable parallel builds: export ZION_PARALLEL=true\n", .{});
        }
        
        if (cache_size > 500 * 1024 * 1024) {
            formatter.warning("Large cache detected - consider cleaning: zion performance cleanup");
        } else if (cache_size == 0) {
            std.debug.print("  🗄️  No cache found - first run will be slower\n", .{});
        }
        
        // Network optimization
        formatter.info("Network Optimization:");
        std.debug.print("  🌐 Use CDN mirrors: zion config set use_mirrors true\n", .{});
        std.debug.print("  📦 Enable compression: zion config set compress_downloads true\n", .{});
        
        // Build optimization
        formatter.info("Build Optimization:");
        std.debug.print("  🔧 Use release mode for final builds: zig build -Doptimize=ReleaseFast\n", .{});
        std.debug.print("  ⚡ Enable LTO: zig build -Doptimize=ReleaseFast -Dstrip=true\n", .{});
    }
    
    pub fn showQuickTips() void {
        var formatter = OutputFormatter.init();
        
        formatter.heading("Quick Performance Tips");
        std.debug.print("\n", .{});
        
        const tips = [_][]const u8{
            "Use 'zion list --json' for faster parsing in scripts",
            "Add frequently used packages to your shell's completion",
            "Set ZION_CACHE_DIR to an SSD for faster access",
            "Use 'zion add pkg1 pkg2 pkg3' to add multiple packages at once",
            "Enable parallel downloads with ZION_PARALLEL=true",
            "Use 'zion repair' if you see hash mismatches",
            "Cache builds with ZION_BUILD_CACHE=true",
            "Use short aliases: 'a' for add, 'r' for remove, 'l' for list",
        };
        
        for (tips, 1..) |tip, i| {
            std.debug.print("  {}. 💡 {s}\n", .{ i, tip });
        }
        
        std.debug.print("\n", .{});
        formatter.info("Run 'zion performance engine optimize' for automatic tuning!");
    }
};

/// Command history and bookmarks system
pub const CommandHistory = struct {
    allocator: Allocator,
    history_file: []const u8,
    
    pub fn init(allocator: Allocator) !CommandHistory {
        const home_dir = std.posix.getenv("HOME") orelse "/tmp";
        const history_file = try std.fmt.allocPrint(allocator, "{s}/.zion_history", .{home_dir});
        
        return CommandHistory{
            .allocator = allocator,
            .history_file = history_file,
        };
    }
    
    pub fn deinit(self: *CommandHistory) void {
        self.allocator.free(self.history_file);
    }
    
    pub fn addCommand(self: *CommandHistory, command: []const u8) !void {
        const file = std.fs.cwd().openFile(self.history_file, .{ .mode = .write_only }) catch |err| switch (err) {
            error.FileNotFound => try std.fs.cwd().createFile(self.history_file, .{}),
            else => return err,
        };
        defer file.close();
        
        try file.seekFromEnd(0);
        const timestamp = std.time.timestamp();
        try file.writer().print("{}: {s}\n", .{ timestamp, command });
    }
    
    pub fn getRecentCommands(self: *CommandHistory, count: usize) ![][]const u8 {
        const content = std.fs.cwd().readFileAlloc(self.history_file, self.allocator, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return &[_][]const u8{},
            else => return err,
        };
        defer self.allocator.free(content);
        
        var commands: std.ArrayList([]const u8) = .{};
        defer commands.deinit(self.allocator);
        
        var lines = std.mem.splitBackwards(u8, content, "\n");
        var added: usize = 0;
        
        while (lines.next()) |line| {
            if (added >= count) break;
            if (line.len == 0) continue;
            
            // Extract command after timestamp
            if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                const command = line[colon_pos + 2..];
                try commands.append(self.allocator, try self.allocator.dupe(u8, command));
                added += 1;
            }
        }
        
        return commands.toOwnedSlice(self.allocator);
    }
    
    pub fn showHistory(self: *CommandHistory) !void {
        var formatter = OutputFormatter.init();
        
        const recent = try self.getRecentCommands(10);
        defer {
            for (recent) |cmd| {
                self.allocator.free(cmd);
            }
            self.allocator.free(recent);
        }
        
        formatter.heading("Recent Commands");
        
        if (recent.len == 0) {
            formatter.info("No command history found");
            return;
        }
        
        for (recent, 1..) |cmd, i| {
            std.debug.print("  {}. zion {s}\n", .{ i, cmd });
        }
        
        std.debug.print("\n", .{});
        formatter.info("Use ↑/↓ arrow keys in your shell to navigate command history");
    }
};

/// Main QoL enhancement integration
pub fn enhanceCommand(allocator: Allocator, args: []const []const u8, unknown_command: []const u8) !void {
    _ = args;
    var suggester = CommandSuggester.init();
    var formatter = OutputFormatter.init();
    
    formatter.error_msg("Unknown command: '{s}'", .{unknown_command});
    
    // Try to suggest a similar command
    if (suggester.suggestCommand(unknown_command)) |suggestion| {
        formatter.info("Did you mean: 'zion {s}'?", .{suggestion});
        
        // Show multiple suggestions if available
        const suggestions = try suggester.suggestCommands(allocator, unknown_command);
        defer allocator.free(suggestions);
        
        if (suggestions.len > 1) {
            std.debug.print("\n💡 Other possibilities:\n", .{});
            for (suggestions[1..]) |cmd| {
                std.debug.print("  - zion {s}\n", .{cmd});
            }
        }
    }
    
    // Show common commands
    std.debug.print("\n🚀 Common commands:\n", .{});
    const common_commands = [_][]const u8{ "add", "remove", "list", "search", "help" };
    for (common_commands) |cmd| {
        std.debug.print("  - zion {s}\n", .{cmd});
    }
    
    formatter.info("Run 'zion help' for complete command list");
    
    // Record this failed command attempt
    var history = CommandHistory.init(allocator) catch return;
    defer history.deinit();
    
    const failed_command = try std.fmt.allocPrint(allocator, "FAILED: {s}", .{unknown_command});
    defer allocator.free(failed_command);
    history.addCommand(failed_command) catch {};
}

/// Show QoL features help
pub fn showQoLHelp() void {
    var formatter = OutputFormatter.init();
    
    formatter.heading("Quality of Life Features in Zion v1.0.6");
    
    formatter.info("Smart Command Suggestions:");
    std.debug.print("  🎯 Typo correction: 'zion ad' → suggests 'zion add'\n", .{});
    std.debug.print("  📝 Prefix completion: 'zion se' → suggests 'zion search'\n", .{});
    std.debug.print("  🔍 Multiple suggestions for ambiguous commands\n", .{});
    
    formatter.info("Enhanced Progress Indicators:");
    std.debug.print("  ⏳ Animated spinners for long operations\n", .{});
    std.debug.print("  📊 Progress bars with ETA calculations\n", .{});
    std.debug.print("  🎨 Color-coded output for better readability\n", .{});
    
    formatter.info("Performance Hints:");
    std.debug.print("  💡 Automatic system analysis and recommendations\n", .{});
    std.debug.print("  ⚡ Quick performance tips and optimizations\n", .{});
    std.debug.print("  📈 Cache and build optimization suggestions\n", .{});
    
    formatter.info("Command History:");
    std.debug.print("  📜 Persistent command history across sessions\n", .{});
    std.debug.print("  🔄 Easy access to recently used commands\n", .{});
    std.debug.print("  ⭐ Bookmark frequently used commands (coming soon)\n", .{});
    
    std.debug.print("\n", .{});
    formatter.info("Try these commands:");
    std.debug.print("  zion performance hints   # Show performance tips\n", .{});
    std.debug.print("  zion history             # Show command history\n", .{});
    std.debug.print("  zion nonexistent         # Test smart suggestions\n", .{});
}

/// Performance command integration
pub fn runPerformanceHints(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        PerformanceHints.showQuickTips();
        return;
    }
    
    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "analyze")) {
        try PerformanceHints.analyzeAndSuggest(allocator);
    } else if (std.mem.eql(u8, subcommand, "tips")) {
        PerformanceHints.showQuickTips();
    } else {
        PerformanceHints.showQuickTips();
    }
}

/// History command integration  
pub fn runHistoryCommand(allocator: Allocator, args: []const []const u8) !void {
    _ = args;
    var history = try CommandHistory.init(allocator);
    defer history.deinit();
    
    try history.showHistory();
}