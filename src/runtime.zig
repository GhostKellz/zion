const std = @import("std");

/// Sync-first runtime boundary for Zion.
///
/// This intentionally does not try to replace a general async runtime.
/// It keeps the std.Io handle and a few process-level sizing helpers in one
/// place so targeted concurrency can grow behind a Zion-owned API later.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Runtime {
        return .{
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn workerHint(self: Runtime) usize {
        _ = self;
        const cpu_count = std.Thread.getCpuCount() catch 1;
        return if (cpu_count > 1) cpu_count - 1 else 1;
    }
};
