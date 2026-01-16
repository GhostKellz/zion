const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const zion_root = @import("../root.zig");

/// Generate and optionally open documentation
pub fn doc(allocator: Allocator, args: []const [:0]const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    var open_browser = false;
    var package_name: ?[]const u8 = null;
    var output_dir: []const u8 = "zig-out/doc";

    // Parse arguments
    var i: usize = 2; // Skip "zion" and "doc"
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--open")) {
            open_browser = true;
        } else if (std.mem.startsWith(u8, arg, "--package=")) {
            package_name = arg[10..]; // Skip "--package="
        } else if (std.mem.eql(u8, arg, "--package") and i + 1 < args.len) {
            i += 1;
            package_name = args[i];
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            output_dir = arg[9..]; // Skip "--output="
        } else if (std.mem.eql(u8, arg, "--output") and i + 1 < args.len) {
            i += 1;
            output_dir = args[i];
        } else {
            // Assume it's a package name
            package_name = arg;
        }
        i += 1;
    }

    std.debug.print("📚 Generating documentation", .{});
    if (package_name) |pkg| {
        std.debug.print(" for package '{s}'", .{pkg});
    }
    std.debug.print("...\n", .{});

    // Build documentation command
    var doc_args: std.ArrayList([]const u8) = .empty;
    defer doc_args.deinit(allocator);

    try doc_args.append(allocator, "zig");

    if (package_name) |pkg| {
        // Generate docs for a specific package
        try doc_args.append(allocator, "build-lib");

        // Find the package source file
        const src_file = try findPackageSource(allocator, io, cwd, pkg);
        defer allocator.free(src_file);
        try doc_args.append(allocator, src_file);
    } else {
        // Generate docs for the main project
        try doc_args.append(allocator, "build");
        try doc_args.append(allocator, "--zig-lib-dir");
        try doc_args.append(allocator, "/usr/lib/zig/lib"); // Adjust as needed
    }

    // Add documentation flags
    try doc_args.append(allocator, "-femit-docs");
    const docs_path = try std.fmt.allocPrint(allocator, "-femit-docs={s}", .{output_dir});
    defer allocator.free(docs_path);
    try doc_args.append(allocator, docs_path);

    // Execute zig documentation generation
    var child = try std.process.spawn(io, .{
        .argv = doc_args.items,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // Drain stdout (not used for doc generation)
    var stdout_buf: [4096]u8 = undefined;
    while (true) {
        const bytes_read = child.stdout.?.readStreaming(io, &.{stdout_buf[0..]}) catch break;
        if (bytes_read == 0) break;
    }

    var stderr_output_buf: std.ArrayList(u8) = .empty;
    defer stderr_output_buf.deinit(allocator);

    var stderr_read_buf: [4096]u8 = undefined;
    while (true) {
        const bytes_read = child.stderr.?.readStreaming(io, &.{stderr_read_buf[0..]}) catch break;
        if (bytes_read == 0) break;
        try stderr_output_buf.appendSlice(allocator, stderr_read_buf[0..bytes_read]);
    }

    const stderr = try allocator.dupe(u8, stderr_output_buf.items);
    defer allocator.free(stderr);

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code == 0) {
                std.debug.print("✅ Documentation generated successfully\n", .{});
                std.debug.print("📁 Output directory: {s}\n", .{output_dir});

                // Show the main index file
                const index_path = try std.fmt.allocPrint(allocator, "{s}/index.html", .{output_dir});
                defer allocator.free(index_path);

                cwd.access(io, index_path, .{}) catch |err| {
                    if (err == error.FileNotFound) {
                        std.debug.print("📄 Documentation files generated in {s}/\n", .{output_dir});
                        return;
                    }
                };

                const real_path = try cwd.realPathFileAlloc(io, ".", allocator);
                defer allocator.free(real_path);
                std.debug.print("🌐 Open in browser: file://{s}/{s}\n", .{ real_path, index_path });

                if (open_browser) {
                    try openInBrowser(allocator, io, cwd, index_path);
                }
            } else {
                std.debug.print("❌ Documentation generation failed (exit code {d})\n", .{code});
                if (stderr.len > 0) {
                    std.debug.print("Error output:\n{s}\n", .{stderr});
                }
            }
        },
        else => {
            std.debug.print("❌ Documentation generation terminated abnormally\n", .{});
            if (stderr.len > 0) {
                std.debug.print("Error output:\n{s}\n", .{stderr});
            }
        },
    }
}

/// Find the source file for a given package
fn findPackageSource(allocator: Allocator, io: Io, cwd: Dir, package_name: []const u8) ![]const u8 {
    // Check common locations
    const candidates = [_][]const u8{
        "src/main.zig",
        "src/lib.zig",
        "src/root.zig",
    };

    for (candidates) |candidate| {
        cwd.access(io, candidate, .{}) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
        return allocator.dupe(u8, candidate);
    }

    // Try package-specific source
    const pkg_src = try std.fmt.allocPrint(allocator, "src/{s}.zig", .{package_name});
    cwd.access(io, pkg_src, .{}) catch |err| {
        if (err == error.FileNotFound) {
            allocator.free(pkg_src);
            // Fallback to main
            return allocator.dupe(u8, "src/main.zig");
        }
        allocator.free(pkg_src);
        return err;
    };

    return pkg_src;
}

/// Attempt to open documentation in the default browser
fn openInBrowser(allocator: Allocator, io: Io, cwd: Dir, index_path: []const u8) !void {
    const abs_path = try cwd.realPathFileAlloc(io, index_path, allocator);
    defer allocator.free(abs_path);

    const url = try std.fmt.allocPrint(allocator, "file://{s}", .{abs_path});
    defer allocator.free(url);

    std.debug.print("🌐 Opening documentation in browser...\n", .{});

    // Try different commands based on the system
    const open_commands = [_]struct { args: []const []const u8 }{
        .{ .args = &[_][]const u8{ "xdg-open", url } }, // Linux
        .{ .args = &[_][]const u8{ "open", url } }, // macOS
        .{ .args = &[_][]const u8{ "start", url } }, // Windows
    };

    for (open_commands) |cmd| {
        var child = std.process.spawn(io, .{
            .argv = cmd.args,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch continue;

        const term = child.wait(io) catch continue;
        switch (term) {
            .exited => |code| {
                if (code == 0) {
                    std.debug.print("✅ Documentation opened in browser\n", .{});
                    return;
                }
            },
            else => continue,
        }
    }

    std.debug.print("⚠️  Could not open browser automatically\n", .{});
    std.debug.print("💡 Manually open: {s}\n", .{url});
}
