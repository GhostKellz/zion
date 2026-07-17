const std = @import("std");
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;
const json = std.json;
const zion_root = @import("../root.zig");

/// Target configuration file
const TARGET_FILE = ".zion/targets.json";

/// Common Zig cross-compilation targets
const COMMON_TARGETS = [_][]const u8{
    "x86_64-linux-gnu",
    "x86_64-linux-musl",
    "aarch64-linux-gnu",
    "aarch64-linux-musl",
    "x86_64-macos",
    "aarch64-macos",
    "x86_64-windows-gnu",
    "aarch64-windows-gnu",
    "wasm32-wasi",
    "wasm32-freestanding",
    "riscv64-linux-gnu",
    "arm-linux-gnueabihf",
};

/// Target management command
pub fn target(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        try listTargets(allocator);
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion target add <target-triple>\n", .{});
            std.debug.print("\nExample targets:\n", .{});
            for (COMMON_TARGETS) |t| {
                std.debug.print("  {s}\n", .{t});
            }
            return;
        }
        try addTarget(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "remove") or std.mem.eql(u8, subcommand, "rm")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion target remove <target-triple>\n", .{});
            return;
        }
        try removeTarget(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "list") or std.mem.eql(u8, subcommand, "ls")) {
        try listTargets(allocator);
    } else if (std.mem.eql(u8, subcommand, "available")) {
        try showAvailableTargets();
    } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "-h")) {
        printHelp();
    } else {
        // Assume it's a target triple for `add`
        try addTarget(allocator, subcommand);
    }
}

fn printHelp() void {
    std.debug.print(
        \\zion target - Manage cross-compilation targets
        \\
        \\Usage: zion target <command> [target-triple]
        \\
        \\Commands:
        \\  add <triple>      Add a compilation target
        \\  remove <triple>   Remove a compilation target
        \\  list              List configured targets (default)
        \\  available         Show common target triples
        \\  help              Show this help message
        \\
        \\Examples:
        \\  zion target add wasm32-wasi
        \\  zion target add aarch64-linux-gnu
        \\  zion target remove x86_64-windows-gnu
        \\  zion target list
        \\
        \\Target Triple Format:
        \\  <arch>-<os>[-<abi>]
        \\
        \\  Architectures: x86_64, aarch64, arm, riscv64, wasm32
        \\  Operating Systems: linux, macos, windows, freestanding, wasi
        \\  ABIs: gnu, musl, gnueabihf, msvc (optional)
        \\
        \\Integration:
        \\  Configured targets are stored in .zion/targets.json
        \\  Use with: zig build -Dtarget=<triple>
        \\
    , .{});
}

/// Load targets from config file
fn loadTargets(allocator: Allocator) !std.ArrayList([]const u8) {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    var targets: std.ArrayList([]const u8) = .empty;

    // Check if file exists
    cwd.access(io, TARGET_FILE, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return targets; // Return empty list
        }
        return err;
    };

    // Read and parse file
    const content = try cwd.readFileAlloc(io, TARGET_FILE, allocator, std.Io.Limit.limited(64 * 1024));
    defer allocator.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch {
        return targets; // Return empty on parse error
    };
    defer parsed.deinit();

    if (parsed.value == .object) {
        if (parsed.value.object.get("targets")) |targets_val| {
            if (targets_val == .array) {
                for (targets_val.array.items) |item| {
                    if (item == .string) {
                        try targets.append(allocator, try allocator.dupe(u8, item.string));
                    }
                }
            }
        }
    }

    return targets;
}

/// Save targets to config file
fn saveTargets(allocator: Allocator, targets: *const std.ArrayList([]const u8)) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Ensure .zion directory exists
    cwd.createDir(io, ".zion", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var file = try cwd.createFile(io, TARGET_FILE, .{ .truncate = true });
    defer file.close(io);

    try file.writeStreamingAll(io, "{\n  \"targets\": [\n");

    for (targets.items, 0..) |t, i| {
        const line = try std.fmt.allocPrint(allocator, "    \"{s}\"", .{t});
        defer allocator.free(line);
        try file.writeStreamingAll(io, line);

        if (i < targets.items.len - 1) {
            try file.writeStreamingAll(io, ",\n");
        } else {
            try file.writeStreamingAll(io, "\n");
        }
    }

    try file.writeStreamingAll(io, "  ]\n}\n");
}

/// Add a compilation target
fn addTarget(allocator: Allocator, target_triple: []const u8) !void {
    // Validate target format (basic check)
    if (!isValidTarget(target_triple)) {
        std.debug.print("Warning: '{s}' may not be a valid Zig target triple.\n", .{target_triple});
        std.debug.print("Expected format: <arch>-<os>[-<abi>]\n\n", .{});
        std.debug.print("Common targets:\n", .{});
        for (COMMON_TARGETS[0..5]) |t| {
            std.debug.print("  {s}\n", .{t});
        }
        std.debug.print("\nAdding anyway...\n\n", .{});
    }

    var targets = try loadTargets(allocator);
    defer {
        for (targets.items) |t| allocator.free(t);
        targets.deinit(allocator);
    }

    // Check if already exists
    for (targets.items) |existing| {
        if (std.mem.eql(u8, existing, target_triple)) {
            std.debug.print("Target '{s}' is already configured.\n", .{target_triple});
            return;
        }
    }

    // Add new target
    try targets.append(allocator, try allocator.dupe(u8, target_triple));
    try saveTargets(allocator, &targets);

    std.debug.print("Added target: {s}\n", .{target_triple});
    std.debug.print("\nTo build for this target:\n", .{});
    std.debug.print("  zig build -Dtarget={s}\n", .{target_triple});
}

/// Remove a compilation target
fn removeTarget(allocator: Allocator, target_triple: []const u8) !void {
    var targets = try loadTargets(allocator);
    defer {
        for (targets.items) |t| allocator.free(t);
        targets.deinit(allocator);
    }

    // Find and remove target
    var found = false;
    var i: usize = 0;
    while (i < targets.items.len) {
        if (std.mem.eql(u8, targets.items[i], target_triple)) {
            allocator.free(targets.orderedRemove(i));
            found = true;
        } else {
            i += 1;
        }
    }

    if (!found) {
        std.debug.print("Target '{s}' is not configured.\n", .{target_triple});
        return;
    }

    try saveTargets(allocator, &targets);
    std.debug.print("Removed target: {s}\n", .{target_triple});
}

/// List configured targets
fn listTargets(allocator: Allocator) !void {
    var targets = try loadTargets(allocator);
    defer {
        for (targets.items) |t| allocator.free(t);
        targets.deinit(allocator);
    }

    std.debug.print("\nConfigured Build Targets\n", .{});
    std.debug.print("========================\n\n", .{});

    if (targets.items.len == 0) {
        std.debug.print("No targets configured.\n", .{});
        std.debug.print("Native target will be used by default.\n\n", .{});
        std.debug.print("Add targets with: zion target add <triple>\n", .{});
        std.debug.print("See available targets: zion target available\n", .{});
        return;
    }

    for (targets.items, 0..) |t, i| {
        const category = categorizeTarget(t);
        std.debug.print("  {d}. {s}", .{ i + 1, t });
        if (category.len > 0) {
            std.debug.print(" ({s})", .{category});
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("\nBuild commands:\n", .{});
    for (targets.items) |t| {
        std.debug.print("  zig build -Dtarget={s}\n", .{t});
    }
}

/// Show common available targets
fn showAvailableTargets() !void {
    std.debug.print("\nCommon Zig Cross-Compilation Targets\n", .{});
    std.debug.print("=====================================\n\n", .{});

    std.debug.print("Linux:\n", .{});
    std.debug.print("  x86_64-linux-gnu       64-bit x86 Linux (glibc)\n", .{});
    std.debug.print("  x86_64-linux-musl      64-bit x86 Linux (musl, static)\n", .{});
    std.debug.print("  aarch64-linux-gnu      64-bit ARM Linux (glibc)\n", .{});
    std.debug.print("  aarch64-linux-musl     64-bit ARM Linux (musl, static)\n", .{});
    std.debug.print("  arm-linux-gnueabihf    32-bit ARM Linux (hard float)\n", .{});
    std.debug.print("  riscv64-linux-gnu      64-bit RISC-V Linux\n", .{});

    std.debug.print("\nmacOS:\n", .{});
    std.debug.print("  x86_64-macos           Intel Mac\n", .{});
    std.debug.print("  aarch64-macos          Apple Silicon Mac\n", .{});

    std.debug.print("\nWindows:\n", .{});
    std.debug.print("  x86_64-windows-gnu     64-bit Windows (MinGW)\n", .{});
    std.debug.print("  aarch64-windows-gnu    ARM64 Windows\n", .{});

    std.debug.print("\nWebAssembly:\n", .{});
    std.debug.print("  wasm32-wasi            WebAssembly (WASI runtime)\n", .{});
    std.debug.print("  wasm32-freestanding    WebAssembly (bare metal)\n", .{});

    std.debug.print("\nUse: zion target add <triple>\n", .{});
}

/// Basic validation of target triple format
fn isValidTarget(target_triple: []const u8) bool {
    // Must have at least arch-os format
    const first_dash = std.mem.indexOf(u8, target_triple, "-") orelse return false;
    if (first_dash == 0 or first_dash == target_triple.len - 1) return false;

    const arch = target_triple[0..first_dash];
    const valid_archs = [_][]const u8{
        "x86_64",  "aarch64", "arm",         "armeb", "riscv64",
        "riscv32", "wasm32",  "wasm64",      "i386",  "powerpc64",
        "powerpc", "mips",    "mips64",      "sparc", "sparc64",
        "thumb",   "thumbeb", "hexagon",     "s390x", "m68k",
        "native",  "x86",     "loongarch64",
    };

    var arch_valid = false;
    for (valid_archs) |va| {
        if (std.mem.eql(u8, arch, va)) {
            arch_valid = true;
            break;
        }
    }

    return arch_valid;
}

/// Categorize a target for display
fn categorizeTarget(target_triple: []const u8) []const u8 {
    if (std.mem.indexOf(u8, target_triple, "linux") != null) {
        if (std.mem.indexOf(u8, target_triple, "musl") != null) {
            return "Linux static";
        }
        return "Linux";
    }
    if (std.mem.indexOf(u8, target_triple, "macos") != null) return "macOS";
    if (std.mem.indexOf(u8, target_triple, "windows") != null) return "Windows";
    if (std.mem.indexOf(u8, target_triple, "wasm") != null) {
        if (std.mem.indexOf(u8, target_triple, "wasi") != null) {
            return "WebAssembly WASI";
        }
        return "WebAssembly";
    }
    if (std.mem.indexOf(u8, target_triple, "freestanding") != null) return "Bare metal";
    return "";
}
