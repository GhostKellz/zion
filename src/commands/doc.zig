const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

/// Generate and optionally open documentation
pub fn doc(allocator: Allocator, args: [][:0]u8) !void {
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
    var doc_args = std.ArrayList([]const u8).init(allocator);
    defer doc_args.deinit();
    
    try doc_args.append("zig");
    
    if (package_name) |pkg| {
        // Generate docs for a specific package
        try doc_args.append("build-lib");
        
        // Find the package source file
        const src_file = try findPackageSource(allocator, pkg);
        defer allocator.free(src_file);
        try doc_args.append(src_file);
    } else {
        // Generate docs for the main project
        try doc_args.append("build");
        try doc_args.append("--zig-lib-dir");
        try doc_args.append("/usr/lib/zig/lib"); // Adjust as needed
    }
    
    // Add documentation flags
    try doc_args.append("-femit-docs");
    const docs_path = try std.fmt.allocPrint(allocator, "-femit-docs={s}", .{output_dir});
    defer allocator.free(docs_path);
    try doc_args.append(docs_path);
    
    // Execute zig documentation generation
    var child = std.process.Child.init(doc_args.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    
    const stdout = try child.stdout.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(stdout);
    const stderr = try child.stderr.?.reader().readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);
    
    const term = try child.wait();
    
    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                std.debug.print("✅ Documentation generated successfully\n", .{});
                std.debug.print("📁 Output directory: {s}\n", .{output_dir});
                
                // Show the main index file
                const index_path = try std.fmt.allocPrint(allocator, "{s}/index.html", .{output_dir});
                defer allocator.free(index_path);
                
                const cwd = fs.cwd();
                cwd.access(index_path, .{}) catch |err| {
                    if (err == error.FileNotFound) {
                        std.debug.print("📄 Documentation files generated in {s}/\n", .{output_dir});
                        return;
                    }
                };
                
                std.debug.print("🌐 Open in browser: file://{s}/{s}\n", .{ try fs.cwd().realpathAlloc(allocator, "."), index_path });
                
                if (open_browser) {
                    try openInBrowser(allocator, index_path);
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
fn findPackageSource(allocator: Allocator, package_name: []const u8) ![]const u8 {
    // Check common locations
    const candidates = [_][]const u8{
        "src/main.zig",
        "src/lib.zig", 
        "src/root.zig",
    };
    
    const cwd = fs.cwd();
    
    for (candidates) |candidate| {
        cwd.access(candidate, .{}) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
        return allocator.dupe(u8, candidate);
    }
    
    // Try package-specific source
    const pkg_src = try std.fmt.allocPrint(allocator, "src/{s}.zig", .{package_name});
    cwd.access(pkg_src, .{}) catch |err| {
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
fn openInBrowser(allocator: Allocator, index_path: []const u8) !void {
    const abs_path = try fs.cwd().realpathAlloc(allocator, index_path);
    defer allocator.free(abs_path);
    
    const url = try std.fmt.allocPrint(allocator, "file://{s}", .{abs_path});
    defer allocator.free(url);
    
    std.debug.print("🌐 Opening documentation in browser...\n", .{});
    
    // Try different commands based on the system
    const open_commands = [_][]const []const u8{
        &[_][]const u8{ "xdg-open", url },      // Linux
        &[_][]const u8{ "open", url },          // macOS  
        &[_][]const u8{ "start", url },         // Windows
    };
    
    for (open_commands) |cmd| {
        var child = std.process.Child.init(cmd, allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        
        if (child.spawn()) {
            const term = child.wait() catch continue;
            switch (term) {
                .Exited => |code| {
                    if (code == 0) {
                        std.debug.print("✅ Documentation opened in browser\n", .{});
                        return;
                    }
                },
                else => continue,
            }
        } else |_| {
            continue;
        }
    }
    
    std.debug.print("⚠️  Could not open browser automatically\n", .{});
    std.debug.print("💡 Manually open: {s}\n", .{url});
}