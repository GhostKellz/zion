const std = @import("std");

pub const ProgressBar = struct {
    total: u64,
    current: u64,
    width: u32,
    title: []const u8,
    allocator: std.mem.Allocator,
    start_time: i64,
    last_update_time: i64,
    update_interval_ms: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, title: []const u8, total: u64) Self {
        return Self{
            .total = total,
            .current = 0,
            .width = 40,
            .title = title,
            .allocator = allocator,
            .start_time = std.time.milliTimestamp(),
            .last_update_time = 0,
            .update_interval_ms = 100, // Update every 100ms
        };
    }

    pub fn update(self: *Self, current: u64) void {
        self.current = current;
        
        const now = std.time.milliTimestamp();
        if (now - self.last_update_time < self.update_interval_ms and current < self.total) {
            return; // Don't update too frequently
        }
        self.last_update_time = now;
        
        self.render();
    }

    pub fn finish(self: *Self) void {
        self.current = self.total;
        self.render();
        std.debug.print("\n", .{});
    }

    fn render(self: *Self) void {
        if (self.total == 0) return;
        
        const percentage = @min(100, (self.current * 100) / self.total);
        const filled = @min(self.width, (self.current * self.width) / self.total);
        
        // Calculate speed and ETA
        const elapsed_ms = std.time.milliTimestamp() - self.start_time;
        const elapsed_sec = @max(1, @divTrunc(elapsed_ms, 1000));
        const rate = if (elapsed_sec > 0) self.current / @as(u64, @intCast(elapsed_sec)) else 0;
        
        const remaining = if (self.current > 0 and rate > 0) 
            (self.total - self.current) / rate else 0;
        
        // Clear line and move cursor to beginning
        std.debug.print("\r\x1b[K", .{});
        
        // Print title and stats
        std.debug.print("{s} ", .{self.title});
        
        // Print progress bar
        std.debug.print("[", .{});
        var i: u32 = 0;
        while (i < self.width) : (i += 1) {
            if (i < filled) {
                std.debug.print("█", .{});
            } else if (i == filled and self.current < self.total) {
                std.debug.print("▓", .{});
            } else {
                std.debug.print("░", .{});
            }
        }
        
        std.debug.print("] {}% ({}/{}", .{ percentage, self.current, self.total });
        
        // Add rate and ETA if available
        if (rate > 0) {
            std.debug.print(" | {} items/s", .{rate});
            if (remaining > 0 and remaining < 3600) {
                std.debug.print(" | ETA: {}s", .{remaining});
            }
        }
        
        std.debug.print(")", .{});
    }
};

pub const Spinner = struct {
    message: []const u8,
    frames: []const []const u8,
    current_frame: usize,
    start_time: i64,
    last_update: i64,

    const Self = @This();
    const DEFAULT_FRAMES = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };

    pub fn init(message: []const u8) Self {
        return Self{
            .message = message,
            .frames = &DEFAULT_FRAMES,
            .current_frame = 0,
            .start_time = std.time.milliTimestamp(),
            .last_update = 0,
        };
    }

    pub fn tick(self: *Self) void {
        const now = std.time.milliTimestamp();
        if (now - self.last_update < 80) return; // 80ms between frames
        
        self.last_update = now;
        self.current_frame = (self.current_frame + 1) % self.frames.len;
        
        const elapsed = @divTrunc(now - self.start_time, 1000);
        
        std.debug.print("\r\x1b[K{s} {s} ({}s)", .{ 
            self.frames[self.current_frame], 
            self.message, 
            elapsed 
        });
    }

    pub fn finish(self: *Self, success_message: []const u8) void {
        const elapsed = @divTrunc(std.time.milliTimestamp() - self.start_time, 1000);
        std.debug.print("\r\x1b[K✅ {s} ({}s)\n", .{ success_message, elapsed });
    }

    pub fn fail(self: *Self, error_message: []const u8) void {
        const elapsed = @divTrunc(std.time.milliTimestamp() - self.start_time, 1000);
        std.debug.print("\r\x1b[K❌ {s} ({}s)\n", .{ error_message, elapsed });
    }
};

pub const MultiProgress = struct {
    bars: std.ArrayList(*ProgressBar),
    allocator: std.mem.Allocator,
    active: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .bars = std.ArrayList(*ProgressBar).init(allocator),
            .allocator = allocator,
            .active = true,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.bars.items) |bar| {
            self.allocator.destroy(bar);
        }
        self.bars.deinit();
    }

    pub fn addBar(self: *Self, title: []const u8, total: u64) !*ProgressBar {
        const bar = try self.allocator.create(ProgressBar);
        bar.* = ProgressBar.init(self.allocator, title, total);
        try self.bars.append(bar);
        return bar;
    }

    pub fn render(self: *Self) void {
        if (!self.active) return;
        
        // Move cursor up to overwrite previous bars
        if (self.bars.items.len > 0) {
            std.debug.print("\x1b[{}A", .{self.bars.items.len});
        }
        
        for (self.bars.items) |bar| {
            bar.render();
            std.debug.print("\n", .{});
        }
    }

    pub fn finishAll(self: *Self) void {
        for (self.bars.items) |bar| {
            bar.finish();
        }
        self.active = false;
    }
};

// Quick progress indicators for common operations
pub fn withProgress(
    comptime T: type,
    allocator: std.mem.Allocator,
    title: []const u8,
    items: []const T,
    comptime processFn: fn(T) anyerror!void
) !void {
    var progress = ProgressBar.init(allocator, title, items.len);
    
    for (items, 0..) |item, i| {
        try processFn(item);
        progress.update(i + 1);
    }
    
    progress.finish();
}

pub fn withSpinner(
    allocator: std.mem.Allocator,
    message: []const u8,
    comptime workFn: fn(std.mem.Allocator) anyerror!void
) !void {
    _ = workFn; // For future implementation
    _ = allocator;
    var spinner = Spinner.init(message);
    
    // In a real implementation, this would run workFn in a separate thread
    // and tick the spinner while work is happening
    // For now, we'll simulate it
    
    const iterations = 20; // Simulate work
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        spinner.tick();
        std.time.sleep(100_000_000); // 100ms
    }
    
    spinner.finish("Operation completed");
}

// Pretty formatting helpers
pub fn formatBytes(bytes: u64) ![]const u8 {
    const allocator = std.heap.page_allocator;
    
    if (bytes < 1024) {
        return try std.fmt.allocPrint(allocator, "{}B", .{bytes});
    } else if (bytes < 1024 * 1024) {
        return try std.fmt.allocPrint(allocator, "{d:.1}KB", .{@as(f64, @floatFromInt(bytes)) / 1024.0});
    } else if (bytes < 1024 * 1024 * 1024) {
        return try std.fmt.allocPrint(allocator, "{d:.1}MB", .{@as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0)});
    } else {
        return try std.fmt.allocPrint(allocator, "{d:.1}GB", .{@as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0)});
    }
}

pub fn formatDuration(seconds: u64) ![]const u8 {
    const allocator = std.heap.page_allocator;
    
    if (seconds < 60) {
        return try std.fmt.allocPrint(allocator, "{}s", .{seconds});
    } else if (seconds < 3600) {
        const mins = seconds / 60;
        const secs = seconds % 60;
        return try std.fmt.allocPrint(allocator, "{}m {}s", .{mins, secs});
    } else {
        const hours = seconds / 3600;
        const mins = (seconds % 3600) / 60;
        return try std.fmt.allocPrint(allocator, "{}h {}m", .{hours, mins});
    }
}