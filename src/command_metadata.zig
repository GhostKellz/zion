const std = @import("std");

pub const Status = enum {
    stable,
    experimental,
    compatibility,
    reserved,

    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .stable => "stable",
            .experimental => "experimental",
            .compatibility => "compatibility-only",
            .reserved => "reserved",
        };
    }
};

pub const Command = struct {
    name: []const u8,
    aliases: []const []const u8 = &.{},
    summary: []const u8,
    status: Status,
    visible: bool = true,
};

/// Authoritative top-level command names, aliases, summaries, and maturity.
/// Dispatch, help, documentation, and completion parity checks consume this list.
pub const commands = [_]Command{
    .{ .name = "init", .summary = "Initialize a Zig project", .status = .stable },
    .{ .name = "add", .aliases = &.{"a"}, .summary = "Resolve and add a dependency transactionally", .status = .experimental },
    .{ .name = "remove", .aliases = &.{ "r", "rm" }, .summary = "Remove a dependency transactionally", .status = .stable },
    .{ .name = "update", .aliases = &.{"u"}, .summary = "Resolve and apply dependency updates", .status = .experimental },
    .{ .name = "list", .aliases = &.{ "l", "ls" }, .summary = "List project dependencies", .status = .stable },
    .{ .name = "info", .aliases = &.{"i"}, .summary = "Show dependency metadata", .status = .stable },
    .{ .name = "fetch", .aliases = &.{"f"}, .summary = "Fetch dependency artifacts", .status = .experimental },
    .{ .name = "pin", .summary = "Pin a dependency reference", .status = .experimental },
    .{ .name = "unpin", .summary = "Resume release or branch tracking", .status = .experimental },
    .{ .name = "repair", .summary = "Repair dependency metadata", .status = .experimental },
    .{ .name = "check", .aliases = &.{"c"}, .summary = "Check project health", .status = .stable },
    .{ .name = "build", .aliases = &.{"b"}, .summary = "Build the project", .status = .stable },
    .{ .name = "clean", .summary = "Clean project artifacts", .status = .stable },
    .{ .name = "lock", .summary = "Manage the dependency lock file", .status = .stable },
    .{ .name = "hash", .summary = "Generate and verify package hashes", .status = .stable },
    .{ .name = "run", .summary = "Run a project executable", .status = .stable },
    .{ .name = "test", .aliases = &.{"t"}, .summary = "Run project and Zion workflow tests", .status = .stable },
    .{ .name = "tree", .summary = "Show the dependency tree", .status = .stable },
    .{ .name = "why", .aliases = &.{"w"}, .summary = "Explain why a dependency is present", .status = .stable },
    .{ .name = "policy", .aliases = &.{"pol"}, .summary = "Manage package trust policy", .status = .stable },
    .{ .name = "target", .aliases = &.{"tgt"}, .summary = "Manage compilation targets", .status = .stable },
    .{ .name = "doc", .summary = "Generate project documentation", .status = .stable },
    .{ .name = "outdated", .summary = "Check for resolvable dependency updates", .status = .experimental },
    .{ .name = "nvim", .summary = "Configure Neovim integration", .status = .experimental },
    .{ .name = "config", .aliases = &.{"cfg"}, .summary = "Manage Zion configuration", .status = .stable },
    .{ .name = "security", .aliases = &.{"sec"}, .summary = "Run package trust helpers", .status = .experimental },
    .{ .name = "performance", .aliases = &.{"perf"}, .summary = "Inspect local performance data", .status = .experimental },
    .{ .name = "debug", .aliases = &.{"dbg"}, .summary = "Inspect project build failures", .status = .experimental },
    .{ .name = "zig", .summary = "Manage local Zig toolchains", .status = .experimental },
    .{ .name = "search", .aliases = &.{"s"}, .summary = "Search configured package registries", .status = .experimental },
    .{ .name = "registry", .aliases = &.{"reg"}, .summary = "Manage experimental registry integrations", .status = .experimental },
    .{ .name = "template", .summary = "Reserved compiler-template workflow", .status = .reserved },
    .{ .name = "fmt", .summary = "Reserved formatter workflow", .status = .reserved },
    .{ .name = "analyze", .summary = "Reserved analysis workflow", .status = .reserved },
    .{ .name = "health", .aliases = &.{"hc"}, .summary = "Legacy unavailable health command", .status = .compatibility, .visible = false },
    .{ .name = "benchmark", .aliases = &.{"bench"}, .summary = "Legacy unavailable benchmark command", .status = .compatibility, .visible = false },
    .{ .name = "publish", .summary = "Publish through an experimental registry", .status = .experimental },
    .{ .name = "search-interactive", .aliases = &.{"si"}, .summary = "Use interactive registry search", .status = .experimental },
    .{ .name = "interface", .aliases = &.{"ui"}, .summary = "Open the compatibility interface", .status = .compatibility },
    .{ .name = "verify", .summary = "Verify a detached signature", .status = .experimental },
    .{ .name = "cache", .summary = "Inspect or clean the Zion cache", .status = .stable },
    .{ .name = "tui", .aliases = &.{"interactive"}, .summary = "Open the terminal interface", .status = .experimental },
    .{ .name = "status", .summary = "Show project status", .status = .stable },
    .{ .name = "setup", .summary = "Show local setup guidance", .status = .stable },
    .{ .name = "zls", .summary = "Manage local ZLS integration", .status = .experimental },
    .{ .name = "workspace", .summary = "Manage Zion workspaces", .status = .experimental },
    .{ .name = "ziglibs", .summary = "Legacy Ziglibs integration", .status = .compatibility, .visible = false },
    .{ .name = "zigistry", .summary = "Legacy Zigistry integration", .status = .compatibility, .visible = false },
    .{ .name = "keyring", .aliases = &.{ "kr", "key" }, .summary = "Manage signing key trust", .status = .experimental },
    .{ .name = "archver", .summary = "Compatibility alias for keyring archver", .status = .compatibility, .visible = false },
    .{ .name = "version", .aliases = &.{"v"}, .summary = "Show the Zion version", .status = .stable },
    .{ .name = "help", .aliases = &.{"h"}, .summary = "Show command help", .status = .stable },
};

pub fn find(input: []const u8) ?*const Command {
    for (&commands) |*command| {
        if (std.mem.eql(u8, input, command.name)) return command;
        for (command.aliases) |alias| {
            if (std.mem.eql(u8, input, alias)) return command;
        }
    }
    return null;
}

pub fn resolve(input: []const u8) []const u8 {
    return if (find(input)) |command| command.name else input;
}

test "command names and aliases are unique" {
    for (commands, 0..) |command, i| {
        try std.testing.expect(command.name.len > 0);
        try std.testing.expect(command.summary.len > 0);
        for (commands[i + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, command.name, other.name));
            for (other.aliases) |alias| {
                try std.testing.expect(!std.mem.eql(u8, command.name, alias));
            }
        }
        for (command.aliases, 0..) |alias, alias_index| {
            try std.testing.expect(alias.len > 0);
            for (command.aliases[alias_index + 1 ..]) |other_alias| {
                try std.testing.expect(!std.mem.eql(u8, alias, other_alias));
            }
        }
    }
}

test "aliases resolve to canonical names" {
    try std.testing.expectEqualStrings("remove", resolve("rm"));
    try std.testing.expectEqualStrings("search-interactive", resolve("si"));
    try std.testing.expectEqualStrings("unknown", resolve("unknown"));
}
