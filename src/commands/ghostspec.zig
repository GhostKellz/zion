const std = @import("std");
const integration = @import("../ghostspec_integration.zig");
const zion_root = @import("../root.zig");
const Dir = std.Io.Dir;
const Io = std.Io;

const compat_path = "data/ghostspec-compat.json";

fn loadCompatValue(allocator: std.mem.Allocator) !json.Parsed(json.Value) {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const contents = try cwd.readFileAlloc(io, compat_path, allocator, Io.Limit.limited(128 * 1024));
    errdefer allocator.free(contents);

    const tree = try json.parseFromSlice(json.Value, allocator, contents, .{ .ignore_unknown_fields = true });
    allocator.free(contents);
    return tree;
}

fn printArray(prefix: []const u8, array: []const json.Value) !void {
    var printed = false;
    for (array) |item| {
        const value = switch (item) {
            .string => |s| s,
            else => continue,
        };
        if (!printed) {
            std.debug.print("{s}{s}", .{ prefix, value });
            printed = true;
        } else {
            std.debug.print(", {s}", .{value});
        }
    }
    if (printed) std.debug.print("\n", .{});
}


const json = std.json;

const Usage = struct {
    pub fn header() []const u8 {
        return "GhostSpec integration commands\n"
            ++ "Usage:\n"
            ++ "  zion ghostspec <subcommand> [options]\n"
            ++ "\n";
    }

    pub fn summary() []const u8 {
        return "Subcommands:\n"
            ++ "  bootstrap      Install GhostSpec, wire build graph, and scaffold defaults\n"
            ++ "  install        Add GhostSpec dependency to the current project\n"
            ++ "  update         Bump GhostSpec dependency to the latest compatible version\n"
            ++ "  uninstall      Remove GhostSpec and clean generated assets\n"
            ++ "  wire           Inject GhostSpec build steps (supports --workspace)\n"
            ++ "  scaffold       Create sample GhostSpec suites and fixtures\n"
            ++ "  run            Execute GhostSpec suites (accepts filters, seeds, budgets)\n"
            ++ "  fuzz           Run focused property fuzzing workflows\n"
            ++ "  bench          Execute GhostSpec benchmarks and capture metrics\n"
            ++ "  report         Generate or open rich reports from the last run\n"
            ++ "  ci             Manage CI-friendly GhostSpec workflows and templates\n"
            ++ "  info           Display compatibility matrix and documentation links\n"
            ++ "  docs           Open GhostSpec documentation in the browser/terminal\n"
            ++ "\n";
    }
};

fn printHelp() void {
    std.debug.print("{s}{s}", .{ Usage.header(), Usage.summary() });
    std.debug.print("Examples:\n", .{});
    std.debug.print("  zion ghostspec bootstrap\n", .{});
    std.debug.print("  zion ghostspec run --suite core --seed 12345\n", .{});
    std.debug.print("  zion ghostspec report --open\n", .{});
}

fn summarizeInstall(result: integration.InstallResult) void {
    if (result.dependency_added) {
        std.debug.print("📦 GhostSpec dependency installed.\n", .{});
    }
    if (result.build_wired) {
        std.debug.print("🔧 build.zig wired for GhostSpec.\n", .{});
    }
    if (result.artifact_dirs_created) {
        std.debug.print("📁 Ensured .zion/ghostspec artifact directories.\n", .{});
    }
    if (result.scaffolded) {
        std.debug.print("🛠️  Scaffolded GhostSpec suite at {s}.\n", .{integration.default_suite_path});
    }
}

fn parseScaffoldOptions(ctx: CommandContext) integration.ScaffoldOptions {
    var options: integration.ScaffoldOptions = .{};
    const extras = ctx.extraArgs(3);
    for (extras) |arg| {
        if (arg.len >= 2 and arg[0] == '-' and arg[1] == '-') {
            if (std.mem.eql(u8, arg, "--force")) {
                options.force = true;
            }
            continue;
        }
        options.destination = arg;
    }
    return options;
}

fn executeIntegrationWorkflow(ctx: CommandContext, mode: integration.RunMode) !void {
    const extras = ctx.extraArgs(3);
    integration.executeWorkflow(ctx.allocator, mode, extras) catch |err| switch (err) {
        error.SpawnFailed => {
            std.debug.print("❌ Unable to spawn 'zig'. Ensure Zig 0.16+ is installed and on PATH.\n", .{});
            return err;
        },
        else => return err,
    };
}

const CommandContext = struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,

    fn subcommand(self: CommandContext) ?[]const u8 {
        return if (self.args.len > 2) self.args[2] else null;
    }

    fn extraArgs(self: CommandContext, start_index: usize) []const []const u8 {
        return if (self.args.len > start_index) self.args[start_index..] else &[_][]const u8{};
    }

    fn hasFlag(self: CommandContext, start_index: usize, flag: []const u8) bool {
        for (self.extraArgs(start_index)) |arg| {
            if (std.mem.eql(u8, arg, flag)) return true;
        }
        return false;
    }
};

fn handleBootstrap(ctx: CommandContext) !void {
    const force = ctx.hasFlag(3, "--force");
    const result = try integration.bootstrap(ctx.allocator, .{ .force_scaffold = force });
    summarizeInstall(result);
    std.debug.print("✅ GhostSpec bootstrap complete. Try 'zion ghostspec run'.\n", .{});
}

fn handleInstall(ctx: CommandContext) !void {
    const auto_wire = !ctx.hasFlag(3, "--no-wire");
    const with_scaffold = ctx.hasFlag(3, "--scaffold");
    const force_scaffold = ctx.hasFlag(3, "--force");

    const result = try integration.install(ctx.allocator, .{
        .auto_wire = auto_wire,
        .scaffold = with_scaffold,
        .force_scaffold = force_scaffold,
    });

    summarizeInstall(result);

    if (auto_wire and !result.build_wired) {
        std.debug.print("ℹ️  build.zig already contained GhostSpec wiring.\n", .{});
    }

    if (!with_scaffold) {
        std.debug.print("ℹ️  Run 'zion ghostspec scaffold' to generate a starter suite when ready.\n", .{});
    } else if (!result.scaffolded and !force_scaffold) {
        std.debug.print("ℹ️  Existing GhostSpec suite preserved. Use --force to overwrite.\n", .{});
    }
}

fn handleUpdate(ctx: CommandContext) !void {
    const auto_wire = !ctx.hasFlag(3, "--no-wire");
    const with_scaffold = ctx.hasFlag(3, "--scaffold");
    const force_scaffold = ctx.hasFlag(3, "--force");

    const result = try integration.install(ctx.allocator, .{
        .update = true,
        .auto_wire = auto_wire,
        .scaffold = with_scaffold,
        .force_scaffold = force_scaffold,
    });

    summarizeInstall(result);
    std.debug.print("✅ GhostSpec dependency up to date.\n", .{});
}

fn handleUninstall(ctx: CommandContext) !void {
    try integration.uninstall(ctx.allocator);
    std.debug.print("✅ GhostSpec dependency removed. Clean up .zion/ghostspec manually if desired.\n", .{});
}

fn handleWire(ctx: CommandContext) !void {
    const wired = try integration.ensureBuildIntegration(ctx.allocator);
    if (!wired) {
        std.debug.print("ℹ️  build.zig already includes GhostSpec wiring.\n", .{});
    }
}

fn handleScaffold(ctx: CommandContext) !void {
    const options = parseScaffoldOptions(ctx);
    const created = try integration.scaffoldSuite(ctx.allocator, options);
    if (created) {
        std.debug.print("✅ GhostSpec scaffold ready. Run 'zion ghostspec run' to verify.\n", .{});
    }
}

fn handleRun(ctx: CommandContext) !void {
    std.debug.print("🏃 Running GhostSpec suites…\n", .{});
    executeIntegrationWorkflow(ctx, .run) catch |err| switch (err) {
        error.CommandFailed => return,
        error.SpawnFailed => return,
    };
    std.debug.print("✅ GhostSpec run completed.\n", .{});
}

fn handleFuzz(ctx: CommandContext) !void {
    std.debug.print("🎲 Running GhostSpec fuzz targets…\n", .{});
    executeIntegrationWorkflow(ctx, .fuzz) catch |err| switch (err) {
        error.CommandFailed => return,
        error.SpawnFailed => return,
    };
    std.debug.print("✅ GhostSpec fuzz run completed.\n", .{});
}

fn handleBench(ctx: CommandContext) !void {
    std.debug.print("📈 Running GhostSpec benchmarks…\n", .{});
    executeIntegrationWorkflow(ctx, .bench) catch |err| switch (err) {
        error.CommandFailed => return,
        error.SpawnFailed => return,
    };
    std.debug.print("✅ GhostSpec benchmarks completed.\n", .{});
}

fn handleReport(ctx: CommandContext) !void {
    std.debug.print("🗂️  Generating GhostSpec report…\n", .{});
    executeIntegrationWorkflow(ctx, .report) catch |err| switch (err) {
        error.CommandFailed => return,
        error.SpawnFailed => return,
    };
    std.debug.print("📄 JSON output (when enabled) is stored at {s}.\n", .{integration.default_report_path});
}

fn handleCi(ctx: CommandContext) !void {
    std.debug.print("🏗️  Running GhostSpec CI profile…\n", .{});
    executeIntegrationWorkflow(ctx, .ci) catch |err| switch (err) {
        error.CommandFailed => return,
        error.SpawnFailed => return,
    };
    std.debug.print("✅ GhostSpec CI profile finished.\n", .{});
}

fn handleInfo(ctx: CommandContext) !void {
    var tree = loadCompatValue(ctx.allocator) catch |err| {
        std.debug.print("⚠️  Unable to read {s}: {s}\n", .{ compat_path, @errorName(err) });
        std.debug.print("   Run 'zion ghostspec docs' for manual resources.\n", .{});
        return;
    };
    defer tree.deinit();

    const root = tree.value;
    const root_obj = switch (root) {
        .object => |obj| obj,
        else => {
            std.debug.print("⚠️  Compatibility file is not an object.\n", .{});
            return;
        },
    };

    std.debug.print("🧭 GhostSpec Compatibility Overview\n", .{});
    const manifest_data = integration.manifestSummary();
    std.debug.print("Version: {s} (channel {s})\n", .{ manifest_data.version, manifest_data.release_channel });

    if (root_obj.get("generated_at")) |generated_val| switch (generated_val) {
        .string => |generated| std.debug.print("Generated: {s}\n", .{generated}),
        else => {},
    };

    if (root_obj.get("notes")) |notes_val| switch (notes_val) {
        .array => |arr| try printArray("Notes: ", arr.items),
        else => {},
    };

    const ghostspec_val = root_obj.get("ghostspec") orelse {
        std.debug.print("GhostSpec section missing.\n", .{});
        return;
    };

    const ghostspec_obj = switch (ghostspec_val) {
        .object => |obj| obj,
        else => {
            std.debug.print("GhostSpec section malformed.\n", .{});
            return;
        },
    };

    if (ghostspec_obj.get("current")) |current_val| switch (current_val) {
        .object => |current_obj| {
            if (current_obj.get("version")) |ver_val| switch (ver_val) {
                .string => |ver| std.debug.print("\nCurrent release: {s}\n", .{ver}),
                else => {},
            };
            if (current_obj.get("source")) |src_val| switch (src_val) {
                .string => |src| std.debug.print("Source: {s}\n", .{src}),
                else => {},
            };
        },
        else => {},
    };

    if (ghostspec_obj.get("zig")) |zig_val| switch (zig_val) {
        .object => |zig_obj| {
            if (zig_obj.get("minimum")) |min_val| switch (min_val) {
                .string => |min| std.debug.print("\nZig minimum: {s}\n", .{min}),
                else => {},
            };
            if (zig_obj.get("recommended")) |rec_val| switch (rec_val) {
                .string => |rec| std.debug.print("Recommended: {s}\n", .{rec}),
                else => {},
            };
            if (zig_obj.get("tested")) |tested_val| switch (tested_val) {
                .array => |arr| try printArray("Tested Zig releases: ", arr.items),
                else => {},
            };
        },
        else => {},
    };

    if (ghostspec_obj.get("zls")) |zls_val| switch (zls_val) {
        .object => |zls_obj| {
            if (zls_obj.get("minimum")) |min_val| switch (min_val) {
                .string => |min| std.debug.print("\nZLS minimum: {s}\n", .{min}),
                else => {},
            };
            if (zls_obj.get("tested")) |tested_val| switch (tested_val) {
                .array => |arr| try printArray("Tested ZLS releases: ", arr.items),
                else => {},
            };
            if (zls_obj.get("notes")) |notes_val| switch (notes_val) {
                .string => |notes| std.debug.print("Notes: {s}\n", .{notes}),
                else => {},
            };
        },
        else => {},
    };

    if (root_obj.get("ci_profiles")) |ci_val| switch (ci_val) {
        .object => |ci_obj| {
            std.debug.print("\nCI Profiles:\n", .{});
            var it = ci_obj.iterator();
            while (it.next()) |entry| {
                const name = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                switch (value) {
                    .object => |profile_obj| {
                        std.debug.print("  • {s}:\n", .{name});
                        if (profile_obj.get("time_budget_seconds")) |tb_val| switch (tb_val) {
                            .integer => |seconds| std.debug.print("      time_budget_seconds: {d}\n", .{seconds}),
                            .float => |f| std.debug.print("      time_budget_seconds: {d}\n", .{@as(i64, @intFromFloat(f))}),
                            else => {},
                        };
                        if (profile_obj.get("max_cases")) |cases_val| switch (cases_val) {
                            .integer => |cases| std.debug.print("      max_cases: {d}\n", .{cases}),
                            else => {},
                        };
                        if (profile_obj.get("fail_fast")) |ff_val| switch (ff_val) {
                            .bool => |flag| std.debug.print("      fail_fast: {s}\n", .{ if (flag) "true" else "false" }),
                            else => {},
                        };
                    },
                    else => {},
                }
            }
        },
        else => {},
    };
}

fn handleDocs(ctx: CommandContext) !void {
    _ = ctx;
    const links = [_][]const u8{
        "https://github.com/ghostkellz/ghostspec/blob/main/docs/architecture.md",
        "https://github.com/ghostkellz/ghostspec/blob/main/docs/property-testing.md",
        "https://github.com/ghostkellz/ghostspec/blob/main/docs/benchmarking.md",
        "https://github.com/ghostkellz/ghostspec/blob/main/SPECTRA_RC1.md",
    };

    std.debug.print("📚 GhostSpec documentation:\n", .{});
    for (links, 0..) |link, idx| {
        std.debug.print("  {d}. {s}\n", .{ idx + 1, link });
    }
    std.debug.print("\nTip: 'zion ghostspec info' highlights compatibility and CI guidance.\n", .{});
}

fn dispatch(ctx: CommandContext, subcommand: []const u8) !void {
    if (std.mem.eql(u8, subcommand, "bootstrap")) {
        try handleBootstrap(ctx);
    } else if (std.mem.eql(u8, subcommand, "install")) {
        try handleInstall(ctx);
    } else if (std.mem.eql(u8, subcommand, "update")) {
        try handleUpdate(ctx);
    } else if (std.mem.eql(u8, subcommand, "uninstall")) {
        try handleUninstall(ctx);
    } else if (std.mem.eql(u8, subcommand, "wire")) {
        try handleWire(ctx);
    } else if (std.mem.eql(u8, subcommand, "scaffold")) {
        try handleScaffold(ctx);
    } else if (std.mem.eql(u8, subcommand, "run")) {
        try handleRun(ctx);
    } else if (std.mem.eql(u8, subcommand, "fuzz")) {
        try handleFuzz(ctx);
    } else if (std.mem.eql(u8, subcommand, "bench")) {
        try handleBench(ctx);
    } else if (std.mem.eql(u8, subcommand, "report")) {
        try handleReport(ctx);
    } else if (std.mem.eql(u8, subcommand, "ci")) {
        try handleCi(ctx);
    } else if (std.mem.eql(u8, subcommand, "info")) {
        try handleInfo(ctx);
    } else if (std.mem.eql(u8, subcommand, "docs")) {
        try handleDocs(ctx);
    } else if (std.mem.eql(u8, subcommand, "help")) {
        printHelp();
    } else {
        std.debug.print("❌ Unknown ghostspec subcommand: '{s}'\n\n", .{ subcommand });
        printHelp();
    }
}

pub fn ghostspec(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var ctx = CommandContext{ .allocator = allocator, .args = args };

    if (ctx.subcommand()) |sub| {
        try dispatch(ctx, sub);
    } else {
        std.debug.print("🚀 GhostSpec integration for Zion\n\n", .{});
        printHelp();
        std.debug.print("\nTip: run 'zion ghostspec bootstrap' to get started.\n", .{});
    }
}
