const std = @import("std");
const Allocator = std.mem.Allocator;
const zion_root = @import("root.zig");
const testing = zion_root.testing;
const Dir = std.Io.Dir;
const Io = std.Io;

const scaffold_template = @embedFile("templates/zion_test_suite.zig");

pub const default_suite_path = "tests/zion_test_suite.zig";
pub const default_report_path = ".zion/test/reports/run.json";

pub const InstallOptions = struct {
    update: bool = false,
    auto_wire: bool = true,
    scaffold: bool = false,
    force_scaffold: bool = false,
};

pub const BootstrapOptions = struct {
    force_scaffold: bool = false,
};

pub const ScaffoldOptions = struct {
    force: bool = false,
    destination: []const u8 = default_suite_path,
};

pub const InstallResult = struct {
    workflow_ready: bool = false,
    build_wired: bool = false,
    scaffolded: bool = false,
    artifact_dirs_created: bool = false,
};

pub const RunMode = enum {
    run,
    fuzz,
    bench,
    report,
    ci,
};

pub const CommandFailed = error{ CommandFailed, SpawnFailed };

pub const ManifestSummary = struct {
    version: []const u8,
    release_channel: []const u8,
    description: []const u8,
};

const failed_tests_path = ".zion/test/reports/failed.txt";

const TestResult = struct {
    name: []const u8,
    kind: testing.metadata.WorkflowKind,
    status: []const u8,
    duration_ms: i64,
    seed: u64,
    stdout: []const u8,
    stderr: []const u8,
};

const ParsedWorkflowArgs = struct {
    suite_filter: ?[]const u8 = null,
    report_path: []const u8 = default_report_path,
    ci_profile: []const u8 = "default",
    open_report: bool = false,
    seed: ?u64 = null,
    cases: u32 = testing.metadata.default_profile.default_cases,
    time_budget_ms: u64 = testing.metadata.default_profile.default_time_budget_ms,
    format: []const u8 = "json",
    include: ?[]const u8 = null,
    exclude: ?[]const u8 = null,
    failed_only: bool = false,
    passthrough: std.ArrayListUnmanaged([]const u8) = .empty,

    fn deinit(self: *ParsedWorkflowArgs, allocator: Allocator) void {
        self.passthrough.deinit(allocator);
    }
};

const WorkflowExecution = struct {
    exit_code: u8,
    duration_ms: i64,
    mode: RunMode,
    suite_path: []const u8,
    suite_filter: ?[]const u8,
    ci_profile: []const u8,
    seed: u64,
    cases: u32,
    time_budget_ms: u64,
    report_path: []const u8,
    tests: []TestResult,

    fn succeeded(self: WorkflowExecution) bool {
        return self.exit_code == 0;
    }
};

pub fn install(allocator: Allocator, options: InstallOptions) !InstallResult {
    _ = options.update;

    var result = InstallResult{
        .workflow_ready = true,
    };

    result.artifact_dirs_created = try ensureArtifactLayout();

    if (options.auto_wire) {
        result.build_wired = try ensureBuildIntegration(allocator);
    }

    if (options.scaffold) {
        result.scaffolded = try scaffoldSuite(allocator, .{
            .force = options.force_scaffold,
        });
    }

    return result;
}

pub fn bootstrap(allocator: Allocator, options: BootstrapOptions) !InstallResult {
    return install(allocator, .{
        .auto_wire = true,
        .scaffold = true,
        .force_scaffold = options.force_scaffold,
    });
}

pub fn uninstall(allocator: Allocator) !void {
    _ = allocator;
}

pub fn ensureBuildIntegration(allocator: Allocator) !bool {
    _ = allocator;
    return false;
}

pub fn scaffoldSuite(allocator: Allocator, options: ScaffoldOptions) !bool {
    _ = allocator;
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const dest = options.destination;
    const dir_path = std.fs.path.dirname(dest) orelse ".";

    _ = try ensureArtifactLayout();

    cwd.createDirPath(io, dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    if (!options.force) {
        const file_exists = blk: {
            cwd.access(io, dest, .{}) catch break :blk false;
            break :blk true;
        };
        if (file_exists) {
            std.debug.print("{s} already exists; use --force to overwrite.\n", .{dest});
            return false;
        }
    }

    const file = try cwd.createFile(io, dest, .{ .truncate = true });
    defer file.close(io);

    try file.writeStreamingAll(io, scaffold_template);
    std.debug.print("Wrote Zion-native compatibility suite to {s}.\n", .{dest});
    return true;
}

pub fn ensureArtifactLayout() !bool {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const paths = [_][]const u8{
        ".zion/test",
        ".zion/test/corpus",
        ".zion/test/crashes",
        ".zion/test/reports",
    };

    var created = false;

    for (paths) |path| {
        cwd.access(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                cwd.createDirPath(io, path) catch |create_err| {
                    if (create_err != error.PathAlreadyExists) return create_err;
                };
                created = true;
            },
            else => return err,
        };
    }

    try createGitKeep(".zion/test/corpus/.gitkeep");
    try createGitKeep(".zion/test/crashes/.gitkeep");
    try createGitKeep(".zion/test/reports/.gitkeep");
    return created;
}

pub fn executeWorkflow(allocator: Allocator, mode: RunMode, extra_args: []const []const u8) CommandFailed!void {
    var parsed = parseWorkflowArgs(allocator, extra_args) catch return CommandFailed.CommandFailed;
    defer parsed.deinit(allocator);

    _ = ensureArtifactLayout() catch return CommandFailed.CommandFailed;

    const suite_path = resolveSuitePath(allocator) catch return CommandFailed.CommandFailed;
    defer allocator.free(suite_path);

    const execution = runZigTest(allocator, mode, suite_path, &parsed) catch |err| switch (err) {
        error.SpawnFailed => return CommandFailed.SpawnFailed,
        else => return CommandFailed.CommandFailed,
    };
    defer freeResults(allocator, execution.tests);

    if (mode == .report or mode == .ci) {
        writeReport(allocator, parsed.report_path, execution) catch return CommandFailed.CommandFailed;

        if (parsed.open_report) {
            printReport(parsed.report_path) catch return CommandFailed.CommandFailed;
        }
    }

    if (!execution.succeeded()) {
        return CommandFailed.CommandFailed;
    }
}

pub fn manifestSummary() ManifestSummary {
    return .{
        .version = "zion-native",
        .release_channel = "built-in",
        .description = "Zion-owned testing workflow compatibility surface using plain Zig tests.",
    };
}

fn parseWorkflowArgs(allocator: Allocator, extra_args: []const []const u8) !ParsedWorkflowArgs {
    var parsed = ParsedWorkflowArgs{};
    errdefer parsed.deinit(allocator);

    var i: usize = 0;
    while (i < extra_args.len) : (i += 1) {
        const arg = extra_args[i];

        if (std.mem.eql(u8, arg, "--open")) {
            parsed.open_report = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--report-path") and i + 1 < extra_args.len) {
            i += 1;
            parsed.report_path = extra_args[i];
            continue;
        }
        if (std.mem.eql(u8, arg, "--suite") and i + 1 < extra_args.len) {
            i += 1;
            parsed.suite_filter = mapSuiteSelector(extra_args[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--ci-profile") and i + 1 < extra_args.len) {
            i += 1;
            parsed.ci_profile = extra_args[i];
            const profile = testing.metadata.profileByName(parsed.ci_profile);
            parsed.cases = profile.default_cases;
            parsed.time_budget_ms = profile.default_time_budget_ms;
            continue;
        }
        if (std.mem.eql(u8, arg, "--seed") and i + 1 < extra_args.len) {
            i += 1;
            parsed.seed = std.fmt.parseInt(u64, extra_args[i], 10) catch return error.InvalidCharacter;
            continue;
        }
        if (std.mem.eql(u8, arg, "--cases") and i + 1 < extra_args.len) {
            i += 1;
            parsed.cases = std.fmt.parseInt(u32, extra_args[i], 10) catch return error.InvalidCharacter;
            continue;
        }
        if (std.mem.eql(u8, arg, "--time-budget") and i + 1 < extra_args.len) {
            i += 1;
            parsed.time_budget_ms = std.fmt.parseInt(u64, extra_args[i], 10) catch return error.InvalidCharacter;
            continue;
        }
        if (std.mem.eql(u8, arg, "--format") and i + 1 < extra_args.len) {
            i += 1;
            parsed.format = extra_args[i];
            continue;
        }
        if (std.mem.eql(u8, arg, "--include") and i + 1 < extra_args.len) {
            i += 1;
            parsed.include = extra_args[i];
            continue;
        }
        if (std.mem.eql(u8, arg, "--exclude") and i + 1 < extra_args.len) {
            i += 1;
            parsed.exclude = extra_args[i];
            continue;
        }
        if (std.mem.eql(u8, arg, "--failed-only")) {
            parsed.failed_only = true;
            continue;
        }

        try parsed.passthrough.append(allocator, arg);
    }

    return parsed;
}

fn mapSuiteSelector(selector: []const u8) []const u8 {
    if (std.mem.eql(u8, selector, "property")) return testing.metadata.prefixForKind(.property);
    if (std.mem.eql(u8, selector, "fuzz")) return testing.metadata.prefixForKind(.fuzz);
    if (std.mem.eql(u8, selector, "bench")) return testing.metadata.prefixForKind(.bench);
    if (std.mem.eql(u8, selector, "mock")) return testing.metadata.prefixForKind(.mock);
    return selector;
}

fn resolveSuitePath(allocator: Allocator) ![]const u8 {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    cwd.access(io, default_suite_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("❌ {s} not found. Run 'zion test scaffold' first.\n", .{default_suite_path});
            return error.FileNotFound;
        },
        else => return err,
    };

    return allocator.dupe(u8, default_suite_path);
}

fn runZigTest(
    allocator: Allocator,
    mode: RunMode,
    suite_path: []const u8,
    parsed: *ParsedWorkflowArgs,
) !WorkflowExecution {
    const io = try zion_root.getIo();
    const ctx = zion_root.app_context orelse return error.AppContextUnavailable;

    const inferred_filter = switch (mode) {
        .fuzz => testing.metadata.prefixForKind(.fuzz),
        .bench => testing.metadata.prefixForKind(.bench),
        else => parsed.suite_filter,
    };

    const seed = parsed.seed orelse @as(u64, @intCast(zion_root.milliTimestamp()));
    const seed_text = try std.fmt.allocPrint(allocator, "{d}", .{seed});
    defer allocator.free(seed_text);
    const cases_text = try std.fmt.allocPrint(allocator, "{d}", .{parsed.cases});
    defer allocator.free(cases_text);
    const budget_text = try std.fmt.allocPrint(allocator, "{d}", .{parsed.time_budget_ms});
    defer allocator.free(budget_text);

    var selected: std.ArrayListUnmanaged(testing.metadata.TestCase) = .empty;
    defer selected.deinit(allocator);
    const prior_failures = try loadFailedTests(allocator);
    defer freeStringSlice(allocator, prior_failures);

    const available_cases = &testing.metadata.workflow_cases;

    for (available_cases) |test_case| {
        if (!shouldRunCase(test_case, inferred_filter, parsed, prior_failures, mode)) continue;
        try selected.append(allocator, test_case);
    }

    var results: std.ArrayListUnmanaged(TestResult) = .empty;
    defer if (@errorReturnTrace() != null) freeResults(allocator, results.items);

    const started_ms = zion_root.milliTimestamp();
    var overall_success = true;

    for (selected.items) |test_case| {
        var child_env = try ctx.environ.clone(allocator);
        defer child_env.deinit();

        try child_env.put("ZION_TEST_SEED", seed_text);
        try child_env.put("ZION_TEST_CASES", cases_text);
        try child_env.put("ZION_TEST_TIME_BUDGET_MS", budget_text);
        try child_env.put("ZION_TEST_REPORT_PATH", parsed.report_path);
        try child_env.put("ZION_TEST_PROFILE", parsed.ci_profile);
        try child_env.put("ZION_TEST_MODE", @tagName(mode));
        if (parsed.include) |include| try child_env.put("ZION_TEST_INCLUDE", include);
        if (parsed.exclude) |exclude| try child_env.put("ZION_TEST_EXCLUDE", exclude);
        if (parsed.failed_only) try child_env.put("ZION_TEST_FAILED_ONLY", "1");

        var args: std.ArrayListUnmanaged([]const u8) = .empty;
        defer args.deinit(allocator);
        try args.append(allocator, "zig");
        try args.append(allocator, "test");
        try args.append(allocator, suite_path);
        try args.append(allocator, "--test-filter");
        try args.append(allocator, test_case.name);
        try args.appendSlice(allocator, parsed.passthrough.items);

        const case_start = zion_root.milliTimestamp();
        const run_result = std.process.run(allocator, io, .{
            .argv = args.items,
            .environ_map = &child_env,
            .stdout_limit = Io.Limit.limited(256 * 1024),
            .stderr_limit = Io.Limit.limited(256 * 1024),
        }) catch return error.SpawnFailed;
        const case_end = zion_root.milliTimestamp();

        const status = switch (run_result.term) {
            .exited => |code| if (code == 0) "passed" else blk: {
                overall_success = false;
                break :blk "failed";
            },
            else => blk: {
                overall_success = false;
                break :blk "failed";
            },
        };

        try results.append(allocator, .{
            .name = try allocator.dupe(u8, test_case.name),
            .kind = test_case.kind,
            .status = status,
            .duration_ms = case_end - case_start,
            .seed = seed,
            .stdout = run_result.stdout,
            .stderr = run_result.stderr,
        });
    }

    try saveFailedTests(allocator, results.items);
    const ended_ms = zion_root.milliTimestamp();
    const owned_results = try results.toOwnedSlice(allocator);

    return .{
        .exit_code = if (overall_success) 0 else 1,
        .duration_ms = ended_ms - started_ms,
        .mode = mode,
        .suite_path = suite_path,
        .suite_filter = inferred_filter,
        .ci_profile = parsed.ci_profile,
        .seed = seed,
        .cases = parsed.cases,
        .time_budget_ms = parsed.time_budget_ms,
        .report_path = parsed.report_path,
        .tests = owned_results,
    };
}

fn writeReport(allocator: Allocator, report_path: []const u8, execution: WorkflowExecution) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const dir_path = std.fs.path.dirname(report_path) orelse ".";

    cwd.createDirPath(io, dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const filter = execution.suite_filter orelse "";
    var results_json: std.ArrayListUnmanaged(u8) = .empty;
    defer results_json.deinit(allocator);

    for (execution.tests, 0..) |result, index| {
        const entry = try std.fmt.allocPrint(allocator,
            \\    {{
            \\      "name": "{s}",
            \\      "kind": "{s}",
            \\      "status": "{s}",
            \\      "duration_ms": {d},
            \\      "seed": {d},
            \\      "artifact_path": "{s}"
            \\    }}{s}
        , .{
            result.name,
            @tagName(result.kind),
            result.status,
            result.duration_ms,
            result.seed,
            execution.report_path,
            if (index + 1 < execution.tests.len) "," else "",
        });
        defer allocator.free(entry);
        try results_json.appendSlice(allocator, entry);
    }

    const json_blob = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "summary": {{
        \\    "mode": "{s}",
        \\    "success": {s},
        \\    "exit_code": {d},
        \\    "duration_ms": {d},
        \\    "timestamp_ms": {d},
        \\    "suite_path": "{s}",
        \\    "suite_filter": "{s}",
        \\    "ci_profile": "{s}",
        \\    "seed": {d},
        \\    "cases": {d},
        \\    "time_budget_ms": {d},
        \\    "report_path": "{s}"
        \\  }},
        \\  "results": [
    , .{
        @tagName(execution.mode),
        if (execution.succeeded()) "true" else "false",
        execution.exit_code,
        execution.duration_ms,
        zion_root.milliTimestamp(),
        execution.suite_path,
        filter,
        execution.ci_profile,
        execution.seed,
        execution.cases,
        execution.time_budget_ms,
        execution.report_path,
    });
    defer allocator.free(json_blob);

    const json_suffix = try allocator.dupe(u8, "\n  ]\n}\n");
    defer allocator.free(json_suffix);

    const full_json = try std.mem.concat(allocator, u8, &.{ json_blob, results_json.items, json_suffix });
    defer allocator.free(full_json);

    const file = try cwd.createFile(io, report_path, .{ .truncate = true });
    defer file.close(io);
    try file.writeStreamingAll(io, full_json);
}

fn printReport(report_path: []const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const contents = try cwd.readFileAlloc(io, report_path, std.heap.page_allocator, Io.Limit.limited(256 * 1024));
    defer std.heap.page_allocator.free(contents);
    std.debug.print("📄 Report: {s}\n{s}\n", .{ report_path, contents });
}

fn shouldRunCase(
    test_case: testing.metadata.TestCase,
    inferred_filter: ?[]const u8,
    parsed: *const ParsedWorkflowArgs,
    prior_failures: []const []const u8,
    mode: RunMode,
) bool {
    if (parsed.failed_only and !stringSliceContains(prior_failures, test_case.name)) return false;

    if (mode == .fuzz and test_case.kind != .fuzz) return false;
    if (mode == .bench and test_case.kind != .bench) return false;

    if (inferred_filter) |filter| {
        if (!std.mem.containsAtLeast(u8, test_case.name, 1, filter)) return false;
    }
    if (parsed.include) |include| {
        if (!std.mem.containsAtLeast(u8, test_case.name, 1, include)) return false;
    }
    if (parsed.exclude) |exclude| {
        if (std.mem.containsAtLeast(u8, test_case.name, 1, exclude)) return false;
    }
    return true;
}

fn loadFailedTests(allocator: Allocator) ![]const []const u8 {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const contents = cwd.readFileAlloc(io, failed_tests_path, allocator, Io.Limit.limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    errdefer allocator.free(contents);

    var lines: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer lines.deinit(allocator);

    var iter = std.mem.splitScalar(u8, contents, '\n');
    while (iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        try lines.append(allocator, try allocator.dupe(u8, trimmed));
    }
    allocator.free(contents);
    return lines.toOwnedSlice(allocator);
}

fn saveFailedTests(allocator: Allocator, results: []const TestResult) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const file = try cwd.createFile(io, failed_tests_path, .{ .truncate = true });
    defer file.close(io);

    for (results) |result| {
        if (!std.mem.eql(u8, result.status, "passed")) {
            try file.writeStreamingAll(io, result.name);
            try file.writeStreamingAll(io, "\n");
        }
    }

    _ = allocator;
}

fn stringSliceContains(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

fn freeStringSlice(allocator: Allocator, items: []const []const u8) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}

fn freeResults(allocator: Allocator, results: []const TestResult) void {
    for (results) |result| {
        allocator.free(result.name);
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    allocator.free(results);
}

fn createGitKeep(path: []const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();
    const file = cwd.createFile(io, path, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    file.close(io);
}

fn sliceHasToken(slice: []const []const u8, token: []const u8) bool {
    for (slice) |item| {
        if (std.mem.eql(u8, item, token)) return true;
    }
    return false;
}
