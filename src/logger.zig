const std = @import("std");

pub const LogLevel = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,
    
    pub fn fromString(level_str: []const u8) LogLevel {
        if (std.mem.eql(u8, level_str, "debug")) return .debug;
        if (std.mem.eql(u8, level_str, "info")) return .info;
        if (std.mem.eql(u8, level_str, "warn")) return .warn;
        if (std.mem.eql(u8, level_str, "error")) return .err;
        return .info; // Default level
    }
};

var current_log_level: LogLevel = .info; // Default to info level
var is_initialized: bool = false;

pub fn init() void {
    if (is_initialized) return;

    // Check environment variable for log level using C library getenv
    // This works without requiring allocation or the Init struct
    if (std.c.getenv("ZION_LOG_LEVEL")) |level_ptr| {
        const level_str = std.mem.sliceTo(level_ptr, 0);
        current_log_level = LogLevel.fromString(level_str);
    } else {
        // Check for debug build vs release build
        if (@import("builtin").mode == .Debug) {
            current_log_level = .debug;
        } else {
            current_log_level = .info;
        }
    }

    is_initialized = true;
}

pub fn setLevel(level: LogLevel) void {
    current_log_level = level;
}

pub fn getLevel() LogLevel {
    if (!is_initialized) init();
    return current_log_level;
}

fn shouldLog(level: LogLevel) bool {
    if (!is_initialized) init();
    return @intFromEnum(level) >= @intFromEnum(current_log_level);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (!shouldLog(.debug)) return;
    std.debug.print("🐛 [DEBUG] " ++ fmt ++ "\n", args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (!shouldLog(.info)) return;
    std.debug.print("ℹ️  [INFO] " ++ fmt ++ "\n", args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (!shouldLog(.warn)) return;
    std.debug.print("⚠️  [WARN] " ++ fmt ++ "\n", args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (!shouldLog(.err)) return;
    std.debug.print("❌ [ERROR] " ++ fmt ++ "\n", args);
}

// User-facing messages (always shown)
pub fn success(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("✅ " ++ fmt ++ "\n", args);
}

pub fn progress(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("🔄 " ++ fmt ++ "\n", args);
}

pub fn user(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

// For commands that need clean output (like list --json)
pub fn clean(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

// Verbose logging (only in debug builds or when explicitly enabled)
pub fn verbose(comptime fmt: []const u8, args: anytype) void {
    if (std.c.getenv("ZION_VERBOSE") != null) {
        std.debug.print("📝 [VERBOSE] " ++ fmt ++ "\n", args);
    } else {
        if (@import("builtin").mode == .Debug and shouldLog(.debug)) {
            std.debug.print("📝 [VERBOSE] " ++ fmt ++ "\n", args);
        }
    }
}