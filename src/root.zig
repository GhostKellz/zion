//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
pub const commands = @import("commands/mod.zig");
pub const logger = @import("logger.zig");
pub const progress = @import("progress.zig");
pub const qol_enhancements = @import("qol_enhancements.zig");

/// Current version of zion
pub const ZION_VERSION = "1.2.0";

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
    const ts = std.posix.clock_gettime(std.posix.CLOCK.REALTIME) catch return 0;
    return ts.sec;
}

/// Helper to get current timestamp in milliseconds (Zig 0.16.0 compatibility)
/// Replaces std.time.milliTimestamp() which was removed
/// Uses monotonic clock for elapsed time measurements
pub fn milliTimestamp() i64 {
    const instant = std.time.Instant.now() catch {
        // Fallback to posix clock if Instant fails
        if (std.posix.clock_gettime(std.posix.CLOCK.REALTIME)) |ts| {
            return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), std.time.ns_per_ms);
        } else |_| {
            return 0;
        }
    };
    // Convert to approximate milliseconds since process start
    // For elapsed time calculations, the absolute value doesn't matter
    const ns = switch (@import("builtin").os.tag) {
        .windows => instant.timestamp * 100, // QPC ticks, rough conversion
        .uefi, .wasi => instant.timestamp,
        else => @as(u64, @intCast(instant.timestamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(instant.timestamp.nsec)),
    };
    return @intCast(@divTrunc(ns, std.time.ns_per_ms));
}

// v0.7.0 Enhanced Modules
pub const enhanced_config = @import("enhanced_config.zig");
pub const registry_v2 = @import("registry_v2.zig");
pub const registry_manager = @import("registry_manager.zig");
pub const security = @import("security.zig");
pub const parallel_downloader = @import("parallel_downloader.zig");
pub const zion_v7 = @import("zion_v7.zig");

// v1.2.0 Zeke AI Integration
pub const zeke_client = @import("zeke_client_simple.zig");
pub const enhanced_add_zeke = @import("commands/enhanced_add_zeke.zig").enhancedAdd;

// Legacy compatibility
pub const config = @import("config.zig");
pub const registry = @import("registry.zig");
pub const downloader = @import("downloader.zig");

// Advanced print function used in the main.zig example
pub fn advancedPrint() !void {
    std.debug.print("Zion v{s} package manager is ready!\n", .{ZION_VERSION});
    std.debug.print("🔥 New in v1.0.6: GPG keyring integration, Arch Linux support, and Zig v0.16.0 compatibility!\n", .{});
}
