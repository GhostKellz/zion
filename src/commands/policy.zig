const std = @import("std");
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;
const Policy = @import("../policy.zig").Policy;
const PolicyResult = @import("../policy.zig").PolicyResult;
const Violation = @import("../policy.zig").Violation;
const POLICY_FILE = @import("../policy.zig").POLICY_FILE;
const LockFile = @import("../lockfile.zig").LockFile;
const zion_root = @import("../root.zig");

/// Policy management command
pub fn policy(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        printHelp();
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "init")) {
        try initPolicy(allocator);
    } else if (std.mem.eql(u8, subcommand, "audit")) {
        const json_output = args.len > 3 and std.mem.eql(u8, args[3], "--json");
        try auditPolicy(allocator, json_output);
    } else if (std.mem.eql(u8, subcommand, "show")) {
        try showPolicy(allocator);
    } else if (std.mem.eql(u8, subcommand, "add-allow")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion policy add-allow <pattern>\n", .{});
            return;
        }
        try addAllowPattern(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "add-deny")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion policy add-deny <pattern>\n", .{});
            return;
        }
        try addDenyPattern(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "-h")) {
        printHelp();
    } else {
        std.debug.print("Unknown policy subcommand: {s}\n", .{subcommand});
        printHelp();
    }
}

fn printHelp() void {
    std.debug.print(
        \\zion policy - Manage package trust policies
        \\
        \\Usage: zion policy <command> [options]
        \\
        \\Commands:
        \\  init          Create a default policy file
        \\  audit         Check lockfile against policy rules
        \\  show          Display current policy configuration
        \\  add-allow     Add an allow pattern
        \\  add-deny      Add a deny pattern
        \\  help          Show this help message
        \\
        \\Options:
        \\  --json        Output audit results in JSON format
        \\
        \\Examples:
        \\  zion policy init                    Create default zion.policy.json
        \\  zion policy audit                   Check all dependencies against policy
        \\  zion policy audit --json            Output results as JSON
        \\  zion policy add-allow github.com/*  Allow all GitHub packages
        \\  zion policy add-deny github.com/malicious/*  Block specific prefix
        \\
        \\Policy File Format (zion.policy.json):
        \\  {{
        \\    "version": 1,
        \\    "allow": ["github.com/*", "gitlab.com/*"],
        \\    "deny": ["github.com/untrusted/*"],
        \\    "require_hash": true,
        \\    "require_signature": false
        \\  }}
        \\
    , .{});
}

/// Initialize a new policy file with defaults
fn initPolicy(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if policy file already exists
    cwd.access(io, POLICY_FILE, .{}) catch |err| {
        if (err != error.FileNotFound) return err;
        // File doesn't exist, continue with creation
    };

    // If we get here without error, file exists
    cwd.access(io, POLICY_FILE, .{}) catch {
        // File doesn't exist, create it
        const default_content = try Policy.generateDefault(allocator);
        defer allocator.free(default_content);

        var file = try cwd.createFile(io, POLICY_FILE, .{ .truncate = true });
        defer file.close(io);

        try file.writeStreamingAll(io, default_content);

        std.debug.print("Created {s} with default configuration.\n", .{POLICY_FILE});
        std.debug.print("\nDefault policy:\n", .{});
        std.debug.print("  - Allow: github.com/*, gitlab.com/*, codeberg.org/*\n", .{});
        std.debug.print("  - Deny: (none)\n", .{});
        std.debug.print("  - Hash required: no\n", .{});
        std.debug.print("  - Signature required: no\n", .{});
        std.debug.print("\nEdit {s} to customize your policy.\n", .{POLICY_FILE});
        return;
    };

    std.debug.print("{s} already exists. Delete it first or edit it directly.\n", .{POLICY_FILE});
}

/// Audit the lockfile against policy rules
fn auditPolicy(allocator: Allocator, json_output: bool) !void {
    // Load policy
    var pol = try Policy.load(allocator);
    defer pol.deinit();

    // Load lockfile
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    if (lock_file.packages.items.len == 0) {
        if (json_output) {
            std.debug.print("{{\"status\": \"pass\", \"violations\": [], \"packages_checked\": 0}}\n", .{});
        } else {
            std.debug.print("No packages to audit.\n", .{});
        }
        return;
    }

    // Check each package
    var violations: std.ArrayList(Violation) = .empty;
    defer violations.deinit(allocator);

    var warnings: u32 = 0;
    var errors: u32 = 0;

    for (lock_file.packages.items) |pkg| {
        const result = pol.checkPackage(pkg.name, pkg.url, pkg.hash);

        if (!result.allowed) {
            try violations.append(allocator, .{
                .package = pkg.name,
                .url = pkg.url,
                .reason = result.reason orelse "Unknown violation",
                .severity = result.severity,
            });

            switch (result.severity) {
                .warning => warnings += 1,
                .@"error" => errors += 1,
                .info => {},
            }
        }
    }

    // Output results
    if (json_output) {
        try outputJson(allocator, &violations, lock_file.packages.items.len, errors, warnings);
    } else {
        try outputHuman(&violations, lock_file.packages.items.len, errors, warnings);
    }
}

fn outputJson(allocator: Allocator, violations: *std.ArrayList(Violation), total: usize, errors: u32, warnings: u32) !void {
    const status = if (errors > 0) "fail" else if (warnings > 0) "warn" else "pass";

    std.debug.print("{{", .{});
    std.debug.print("\"status\": \"{s}\", ", .{status});
    std.debug.print("\"packages_checked\": {d}, ", .{total});
    std.debug.print("\"errors\": {d}, ", .{errors});
    std.debug.print("\"warnings\": {d}, ", .{warnings});
    std.debug.print("\"violations\": [", .{});

    for (violations.items, 0..) |v, i| {
        if (i > 0) std.debug.print(", ", .{});

        const escaped_reason = try escapeJsonString(allocator, v.reason);
        defer allocator.free(escaped_reason);

        std.debug.print("{{\"package\": \"{s}\", \"reason\": \"{s}\", \"severity\": \"{s}\"}}", .{
            v.package,
            escaped_reason,
            @tagName(v.severity),
        });
    }

    std.debug.print("]}}\n", .{});
}

fn outputHuman(violations: *std.ArrayList(Violation), total: usize, errors: u32, warnings: u32) !void {
    std.debug.print("\nPolicy Audit Report\n", .{});
    std.debug.print("===================\n\n", .{});
    std.debug.print("Packages checked: {d}\n", .{total});

    if (violations.items.len == 0) {
        std.debug.print("\nAll packages comply with policy.\n", .{});
        return;
    }

    std.debug.print("\nViolations found: {d}\n", .{violations.items.len});
    if (errors > 0) std.debug.print("  Errors: {d}\n", .{errors});
    if (warnings > 0) std.debug.print("  Warnings: {d}\n", .{warnings});

    std.debug.print("\nDetails:\n", .{});
    for (violations.items) |v| {
        const severity_icon = switch (v.severity) {
            .@"error" => "[X]",
            .warning => "[!]",
            .info => "[i]",
        };
        std.debug.print("  {s} {s}: {s}\n", .{ severity_icon, v.package, v.reason });
        if (v.url) |url| {
            std.debug.print("      URL: {s}\n", .{url});
        }
    }

    std.debug.print("\n", .{});
    if (errors > 0) {
        std.debug.print("Policy check FAILED. Fix violations before proceeding.\n", .{});
    } else {
        std.debug.print("Policy check completed with warnings.\n", .{});
    }
}

/// Show current policy configuration
fn showPolicy(allocator: Allocator) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if policy file exists
    cwd.access(io, POLICY_FILE, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("No policy file found ({s}).\n", .{POLICY_FILE});
            std.debug.print("Run 'zion policy init' to create one.\n", .{});
            return;
        }
        return err;
    };

    var pol = try Policy.load(allocator);
    defer pol.deinit();

    std.debug.print("\nCurrent Policy Configuration\n", .{});
    std.debug.print("============================\n\n", .{});
    std.debug.print("File: {s}\n", .{POLICY_FILE});
    std.debug.print("Version: {d}\n\n", .{pol.version});

    std.debug.print("Allow patterns ({d}):\n", .{pol.allow_patterns.items.len});
    if (pol.allow_patterns.items.len == 0) {
        std.debug.print("  (none - all sources allowed)\n", .{});
    } else {
        for (pol.allow_patterns.items) |pattern| {
            std.debug.print("  - {s}\n", .{pattern});
        }
    }

    std.debug.print("\nDeny patterns ({d}):\n", .{pol.deny_patterns.items.len});
    if (pol.deny_patterns.items.len == 0) {
        std.debug.print("  (none)\n", .{});
    } else {
        for (pol.deny_patterns.items) |pattern| {
            std.debug.print("  - {s}\n", .{pattern});
        }
    }

    std.debug.print("\nRequirements:\n", .{});
    std.debug.print("  Hash required: {}\n", .{pol.require_hash});
    std.debug.print("  Signature required: {}\n", .{pol.require_signature});

    if (pol.max_transitive_depth) |depth| {
        std.debug.print("  Max transitive depth: {d}\n", .{depth});
    }

    if (pol.allowed_licenses) |licenses| {
        std.debug.print("\nAllowed licenses ({d}):\n", .{licenses.items.len});
        for (licenses.items) |license| {
            std.debug.print("  - {s}\n", .{license});
        }
    }
}

/// Add an allow pattern to the policy
fn addAllowPattern(allocator: Allocator, pattern: []const u8) !void {
    var pol = try Policy.load(allocator);
    defer pol.deinit();

    // Check if pattern already exists
    for (pol.allow_patterns.items) |existing| {
        if (std.mem.eql(u8, existing, pattern)) {
            std.debug.print("Pattern '{s}' already in allow list.\n", .{pattern});
            return;
        }
    }

    try pol.allow_patterns.append(allocator, try allocator.dupe(u8, pattern));
    try pol.saveToFile();

    std.debug.print("Added '{s}' to allow patterns.\n", .{pattern});
}

/// Add a deny pattern to the policy
fn addDenyPattern(allocator: Allocator, pattern: []const u8) !void {
    var pol = try Policy.load(allocator);
    defer pol.deinit();

    // Check if pattern already exists
    for (pol.deny_patterns.items) |existing| {
        if (std.mem.eql(u8, existing, pattern)) {
            std.debug.print("Pattern '{s}' already in deny list.\n", .{pattern});
            return;
        }
    }

    try pol.deny_patterns.append(allocator, try allocator.dupe(u8, pattern));
    try pol.saveToFile();

    std.debug.print("Added '{s}' to deny patterns.\n", .{pattern});
}

/// Escape a string for JSON output
fn escapeJsonString(allocator: Allocator, input: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    for (input) |c| {
        switch (c) {
            '"' => try result.appendSlice(allocator, "\\\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => try result.append(allocator, c),
        }
    }

    return try result.toOwnedSlice(allocator);
}
