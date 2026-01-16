const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");
const github = @import("../github.zig");
const zion_root = @import("../root.zig");

pub const HealthStatus = enum {
    healthy,
    warning,
    @"error",
};

pub const PackageHealth = struct {
    name: []const u8,
    status: HealthStatus,
    issues: std.ArrayList([]const u8),
    
    pub fn init(_: Allocator, name: []const u8) PackageHealth {
        return PackageHealth{
            .name = name,
            .status = .healthy,
            .issues = .empty,
        };
    }
    
    pub fn deinit(self: *PackageHealth, allocator: Allocator) void {
        for (self.issues.items) |issue| {
            allocator.free(issue);
        }
        self.issues.deinit(allocator);
    }
    
    pub fn addIssue(self: *PackageHealth, allocator: Allocator, severity: HealthStatus, message: []const u8) !void {
        try self.issues.append(allocator, try allocator.dupe(u8, message));
        if (severity == .@"error" or (severity == .warning and self.status == .healthy)) {
            self.status = severity;
        }
    }
};

/// Check the health of all dependencies and project structure
pub fn check(allocator: Allocator) !void {
    std.debug.print("🩺 Checking project health...\n", .{});

    // Check if build.zig.zon exists
    const zon_path = "build.zig.zon";
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    cwd.access(io, zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("❌ build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };
    
    // Load files
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();
    
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();
    
    std.debug.print("📋 Analyzing {d} dependencies...\n\n", .{zon_file.dependencies.count()});
    
    var package_healths: std.ArrayList(PackageHealth) = .empty;
    defer {
        for (package_healths.items) |*health| {
            health.deinit(allocator);
        }
        package_healths.deinit(allocator);
    }
    
    var overall_status = HealthStatus.healthy;
    
    // Check each dependency
    var it = zon_file.dependencies.iterator();
    while (it.next()) |entry| {
        const package_name = entry.key_ptr.*;
        const dep = entry.value_ptr.*;
        
        std.debug.print("🔍 Checking {s}...\n", .{package_name});
        
        var health = PackageHealth.init(allocator, package_name);
        
        // Check 1: URL accessibility
        if (checkUrlAccessibility(allocator, dep.url)) |accessible| {
            if (!accessible) {
                try health.addIssue(allocator, .@"error", "URL is not accessible");
                std.debug.print("  ❌ URL not accessible\n", .{});
            } else {
                std.debug.print("  ✅ URL accessible\n", .{});
            }
        } else |err| {
            const msg = try std.fmt.allocPrint(allocator, "Failed to check URL accessibility: {}", .{err});
            defer allocator.free(msg);
            try health.addIssue(allocator, .warning, msg);
            std.debug.print("  ⚠️  Could not verify URL accessibility\n", .{});
        }
        
        // Check 2: Hash integrity
        const cache_path = try std.fmt.allocPrint(allocator, ".zion/cache/{s}.tar.gz", .{package_name});
        defer allocator.free(cache_path);
        
        const cached_exists = blk: {
            cwd.access(io, cache_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    break :blk false;
                }
                break :blk true;
            };
            break :blk true;
        };
        
        if (cached_exists) {
            if (downloader.calculateFileHash(allocator, cache_path)) |computed_hash| {
                defer allocator.free(computed_hash);
                if (std.mem.eql(u8, dep.hash, computed_hash)) {
                    std.debug.print("  ✅ Hash verified\n", .{});
                } else {
                    try health.addIssue(allocator, .@"error", "Hash mismatch - run 'zion repair'");
                    std.debug.print("  ❌ Hash mismatch\n", .{});
                }
            } else |err| {
                const msg = try std.fmt.allocPrint(allocator, "Failed to compute hash: {}", .{err});
                defer allocator.free(msg);
                try health.addIssue(allocator, .warning, msg);
                std.debug.print("  ⚠️  Could not verify hash\n", .{});
            }
        } else {
            try health.addIssue(allocator, .warning, "Package not cached - run 'zion fetch'");
            std.debug.print("  ⚠️  Not cached\n", .{});
        }
        
        // Check 3: Extraction status
        const deps_path = try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
        defer allocator.free(deps_path);
        
        const extracted_exists = blk: {
            cwd.access(io, deps_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    break :blk false;
                }
                break :blk true;
            };
            break :blk true;
        };
        
        if (extracted_exists) {
            // Check if it has a build.zig file
            const build_zig_path = try std.fmt.allocPrint(allocator, "{s}/build.zig", .{deps_path});
            defer allocator.free(build_zig_path);
            
            cwd.access(io, build_zig_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    try health.addIssue(allocator, .warning, "No build.zig found in package");
                    std.debug.print("  ⚠️  No build.zig found\n", .{});
                } else {
                    std.debug.print("  ✅ Package structure looks good\n", .{});
                }
            };
        } else {
            try health.addIssue(allocator, .warning, "Package not extracted - run 'zion fetch'");
            std.debug.print("  ⚠️  Not extracted\n", .{});
        }
        
        // Check 4: Lock file consistency
        if (lock_file.getPackage(package_name)) |locked_pkg| {
            if (!std.mem.eql(u8, locked_pkg.hash, dep.hash)) {
                try health.addIssue(allocator, .warning, "Lock file hash mismatch");
                std.debug.print("  ⚠️  Lock file inconsistent\n", .{});
            } else {
                std.debug.print("  ✅ Lock file consistent\n", .{});
            }
        } else {
            try health.addIssue(allocator, .warning, "Package not in lock file");
            std.debug.print("  ⚠️  Not in lock file\n", .{});
        }
        
        // Check 5: Version availability (if we can detect package reference)
        if (extractPackageRefFromUrl(allocator, dep.url)) |package_ref| {
            defer allocator.free(package_ref);
            
            if (github.getLatestVersion(allocator, package_ref)) |latest_version_const| {
                var latest_version = latest_version_const;
                defer latest_version.deinit(allocator);
                
                if (!std.mem.eql(u8, dep.url, latest_version.url)) {
                    const msg = try std.fmt.allocPrint(allocator, "New version available: {s}", .{latest_version.version});
                    defer allocator.free(msg);
                    try health.addIssue(allocator, .warning, msg);
                    std.debug.print("  📦 New version available: {s}\n", .{latest_version.version});
                } else {
                    std.debug.print("  ✅ Using latest version\n", .{});
                }
            } else |_| {
                std.debug.print("  ⚠️  Could not check for updates\n", .{});
            }
        } else |_| {
            std.debug.print("  ⚠️  Non-GitHub URL, cannot check for updates\n", .{});
        }
        
        // Update overall status
        if (health.status == .@"error") {
            overall_status = .@"error";
        } else if (health.status == .warning and overall_status == .healthy) {
            overall_status = .warning;
        }
        
        try package_healths.append(allocator, health);
        std.debug.print("\n", .{});
    }
    
    // Check project structure
    std.debug.print("🏗️  Checking project structure...\n", .{});
    
    // Check for build.zig
    cwd.access(io, "build.zig", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("  ⚠️  build.zig not found\n", .{});
            if (overall_status == .healthy) overall_status = .warning;
        } else {
            std.debug.print("  ✅ build.zig found\n", .{});
        }
    };

    // Check for src directory
    cwd.access(io, "src", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("  ⚠️  src/ directory not found\n", .{});
            if (overall_status == .healthy) overall_status = .warning;
        } else {
            std.debug.print("  ✅ src/ directory found\n", .{});
        }
    };

    // Check for main.zig
    cwd.access(io, "src/main.zig", .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("  ⚠️  src/main.zig not found\n", .{});
            if (overall_status == .healthy) overall_status = .warning;
        } else {
            std.debug.print("  ✅ src/main.zig found\n", .{});
        }
    };
    
    // Print summary
    std.debug.print("\n📊 Health Summary:\n", .{});
    
    var healthy_count: usize = 0;
    var warning_count: usize = 0;
    var error_count: usize = 0;
    
    for (package_healths.items) |health| {
        switch (health.status) {
            .healthy => {
                healthy_count += 1;
                std.debug.print("  ✅ {s}: Healthy\n", .{health.name});
            },
            .warning => {
                warning_count += 1;
                std.debug.print("  ⚠️  {s}: Issues found\n", .{health.name});
                for (health.issues.items) |issue| {
                    std.debug.print("     - {s}\n", .{issue});
                }
            },
            .@"error" => {
                error_count += 1;
                std.debug.print("  ❌ {s}: Critical issues\n", .{health.name});
                for (health.issues.items) |issue| {
                    std.debug.print("     - {s}\n", .{issue});
                }
            },
        }
    }
    
    std.debug.print("\n🎯 Overall Status: ", .{});
    switch (overall_status) {
        .healthy => {
            std.debug.print("✅ HEALTHY\n", .{});
            std.debug.print("🎉 All dependencies are in good condition!\n", .{});
        },
        .warning => {
            std.debug.print("⚠️  WARNINGS\n", .{});
            std.debug.print("💡 Some issues found, but project should still work.\n", .{});
            std.debug.print("   Consider running 'zion repair' or 'zion update' to fix them.\n", .{});
        },
        .@"error" => {
            std.debug.print("❌ CRITICAL ISSUES\n", .{});
            std.debug.print("🚨 Critical problems found that may prevent building.\n", .{});
            std.debug.print("   Run 'zion repair' to fix hash mismatches and broken dependencies.\n", .{});
        },
    }
    
    std.debug.print("\n📈 Statistics:\n", .{});
    std.debug.print("   Healthy: {d}\n", .{healthy_count});
    std.debug.print("   Warnings: {d}\n", .{warning_count});
    std.debug.print("   Errors: {d}\n", .{error_count});
    std.debug.print("   Total: {d}\n", .{package_healths.items.len});
}

/// Check if a URL is accessible
fn checkUrlAccessibility(allocator: Allocator, url: []const u8) !bool {
    const io = try zion_root.getIo();

    const argv = [_][]const u8{
        "curl",
        "-s",
        "-I", // HEAD request only
        "-L", // Follow redirects
        "--max-time", "10", // 10 second timeout
        url,
    };

    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // Read and discard stdout output using scatter/gather API
    var stdout_buf: std.ArrayList(u8) = .empty;
    defer stdout_buf.deinit(allocator);

    if (child.stdout) |stdout_pipe| {
        var stdout_read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = stdout_pipe.readStreaming(io, &.{stdout_read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stdout_buf.appendSlice(allocator, stdout_read_buf[0..bytes_read]);
        }
    }

    // Read and discard stderr output using scatter/gather API
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(allocator);

    if (child.stderr) |stderr_pipe| {
        var stderr_read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = stderr_pipe.readStreaming(io, &.{stderr_read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stderr_buf.appendSlice(allocator, stderr_read_buf[0..bytes_read]);
        }
    }

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            return code == 0;
        },
        else => {
            return false;
        },
    }
}

/// Extract package reference (user/repo) from GitHub URL
fn extractPackageRefFromUrl(allocator: Allocator, url: []const u8) ![]const u8 {
    // Expected formats:
    // https://github.com/user/repo/archive/refs/heads/main.tar.gz
    // https://github.com/user/repo/archive/refs/tags/v1.0.0.tar.gz
    const github_prefix = "https://github.com/";
    
    if (!std.mem.startsWith(u8, url, github_prefix)) {
        return error.UnsupportedUrl;
    }
    
    const after_prefix = url[github_prefix.len..];
    
    // Find the end of user/repo part
    var parts = std.mem.splitScalar(u8, after_prefix, '/');
    const user = parts.next() orelse return error.InvalidGitHubUrl;
    const repo = parts.next() orelse return error.InvalidGitHubUrl;
    
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ user, repo });
}