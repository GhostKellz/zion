const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Clean build artifacts and caches
pub fn clean(allocator: Allocator, clean_all: bool) !void {
    _ = allocator; // unused but required for API consistency

    const cwd = fs.cwd();

    // Always clean these directories
    const dirs_to_clean = [_][]const u8{
        ".zig-cache",
        ".zion/cache",
    };

    for (dirs_to_clean) |dir| {
        cwd.deleteTree(dir) catch |err| {
            if (err != error.FileNotFound) {
                std.debug.print("Warning: Could not delete {s}: {}\n", .{ dir, err });
            } else {
                std.debug.print("Deleted {s}/\n", .{dir});
            }
        };
    }

    if (clean_all) {
        // Additional cleanup for --all flag
        const all_dirs = [_][]const u8{
            "zig-out",
        };

        const all_files = [_][]const u8{
            "zion.lock",
        };

        for (all_dirs) |dir| {
            cwd.deleteTree(dir) catch |err| {
                if (err != error.FileNotFound) {
                    std.debug.print("Warning: Could not delete {s}: {}\n", .{ dir, err });
                } else {
                    std.debug.print("Deleted {s}/\n", .{dir});
                }
            };
        }

        for (all_files) |file| {
            cwd.deleteFile(file) catch |err| {
                if (err != error.FileNotFound) {
                    std.debug.print("Warning: Could not delete {s}: {}\n", .{ file, err });
                } else {
                    std.debug.print("Deleted {s}\n", .{file});
                }
            };
        }
    }
}
