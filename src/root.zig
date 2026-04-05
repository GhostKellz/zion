//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const commands = @import("commands/mod.zig");
pub const logger = @import("logger.zig");
pub const progress = @import("progress.zig");
pub const qol_enhancements = @import("qol_enhancements.zig");
pub const semver = @import("semver.zig");
pub const version_resolver = @import("version_resolver.zig");
pub const runtime = @import("runtime.zig");
pub const testing = @import("testing/mod.zig");

/// Current version of zion
pub const ZION_VERSION = "1.1.0";

/// Application context passed through from main to commands
/// Contains std.Io for filesystem and network operations (required by Zig 0.16.0)
pub const AppContext = struct {
    allocator: std.mem.Allocator,
    std_io: std.Io,
    args: []const [:0]const u8,
    environ: *std.process.Environ.Map,
};

/// Thread-local storage for AppContext
/// Set by main() and accessed by commands that need std.Io
pub threadlocal var app_context: ?*const AppContext = null;

/// Helper to get std.Io from the application context
/// Returns error if context is not available
pub fn getIo() !std.Io {
    const ctx = app_context orelse return error.AppContextUnavailable;
    return ctx.std_io;
}

/// Helper to get an environment variable from the application context
/// Returns null if context is not available or variable not set
pub fn getEnv(key: []const u8) ?[]const u8 {
    const ctx = app_context orelse return null;
    return ctx.environ.get(key);
}

/// Helper to sleep for a given number of nanoseconds (Zig 0.16.0 compatibility)
/// Replaces std.Thread.sleep() which was removed
pub fn sleep(nanoseconds: u64) void {
    _ = std.c.nanosleep(&.{
        .sec = @intCast(@divTrunc(nanoseconds, std.time.ns_per_s)),
        .nsec = @intCast(@mod(nanoseconds, std.time.ns_per_s)),
    }, null);
}

/// Helper to get current Unix timestamp in seconds (Zig 0.16.0 compatibility)
/// Replaces std.time.timestamp() which was removed
pub fn timestamp() i64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.posix.CLOCK.REALTIME, &ts) != 0) return 0;
    return ts.sec;
}

/// Helper to get current timestamp in milliseconds (Zig 0.16.0 compatibility)
/// Replaces std.time.milliTimestamp() which was removed
/// Uses monotonic clock for elapsed time measurements
pub fn milliTimestamp() i64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts) != 0) {
        // Fallback to realtime clock
        if (std.c.clock_gettime(std.posix.CLOCK.REALTIME, &ts) != 0) {
            return 0;
        }
    }
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), std.time.ns_per_ms);
}

// ============================================================================
// Accessibility Features
// ============================================================================

/// Check if colors should be disabled (NO_COLOR standard)
/// See: https://no-color.org/
pub fn shouldDisableColors() bool {
    // NO_COLOR standard - any value means disable colors
    if (getEnv("NO_COLOR")) |_| return true;
    // Also check ZION_NO_COLOR for zion-specific override
    if (getEnv("ZION_NO_COLOR")) |_| return true;
    // Check if output is not a TTY (for piping)
    // Note: In Zig 0.16.0, we'd check std.io.getStdOut().isTty() but
    // for simplicity we'll rely on environment variables
    if (getEnv("TERM")) |term| {
        if (std.mem.eql(u8, term, "dumb")) return true;
    }
    return false;
}

/// ANSI color codes - returns empty string if colors disabled
pub const Color = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
    pub const bright_red = "\x1b[91m";
    pub const bright_green = "\x1b[92m";
    pub const bright_yellow = "\x1b[93m";
    pub const bright_blue = "\x1b[94m";

    /// Get color code, respecting NO_COLOR
    pub fn get(code: []const u8) []const u8 {
        if (shouldDisableColors()) return "";
        return code;
    }
};

/// Print success message with optional emoji (screen reader friendly)
pub fn printSuccess(comptime fmt: []const u8, args: anytype) void {
    const prefix = if (shouldDisableColors()) "[OK] " else "✅ ";
    std.debug.print("{s}" ++ fmt ++ "\n", .{prefix} ++ args);
}

/// Print error message with optional emoji (screen reader friendly)
pub fn printError(comptime fmt: []const u8, args: anytype) void {
    const prefix = if (shouldDisableColors()) "[ERROR] " else "❌ ";
    std.debug.print("{s}{s}" ++ fmt ++ "{s}\n", .{ Color.get(Color.red), prefix } ++ args ++ .{Color.get(Color.reset)});
}

/// Print warning message with optional emoji (screen reader friendly)
pub fn printWarning(comptime fmt: []const u8, args: anytype) void {
    const prefix = if (shouldDisableColors()) "[WARN] " else "⚠️  ";
    std.debug.print("{s}{s}" ++ fmt ++ "{s}\n", .{ Color.get(Color.yellow), prefix } ++ args ++ .{Color.get(Color.reset)});
}

/// Print info message with optional emoji (screen reader friendly)
pub fn printInfo(comptime fmt: []const u8, args: anytype) void {
    const prefix = if (shouldDisableColors()) "[INFO] " else "ℹ️  ";
    std.debug.print("{s}" ++ fmt ++ "\n", .{prefix} ++ args);
}

/// Print a section header (accessible format)
pub fn printHeader(title: []const u8) void {
    if (shouldDisableColors()) {
        std.debug.print("\n=== {s} ===\n\n", .{title});
    } else {
        std.debug.print("\n{s}{s}{s} {s} {s}{s}\n\n", .{
            Color.bold,  Color.cyan,
            "━━━",
            title,
            "━━━",
            Color.reset,
        });
    }
}

// Enhanced Modules
pub const enhanced_config = @import("enhanced_config.zig");
pub const package_registry = @import("package_registry.zig");
pub const registry_manager = @import("registry_manager.zig");
pub const security = @import("security.zig");
pub const parallel_downloader = @import("parallel_downloader.zig");

// AI Integration
// AI integration removed

// Core modules
pub const config = @import("config.zig");
pub const registry = @import("registry.zig");
pub const downloader = @import("downloader.zig");
pub const hash_conversion = @import("hash_conversion.zig");

// Advanced print function used in the main.zig example
pub fn advancedPrint() !void {
    std.debug.print("Zion v{s} package manager is ready!\n", .{ZION_VERSION});
}
