pub const WorkflowKind = enum {
    property,
    fuzz,
    bench,
    mock,
};

pub const TestCase = struct {
    name: []const u8,
    kind: WorkflowKind,
};

pub const Profile = struct {
    name: []const u8,
    default_cases: u32,
    default_time_budget_ms: u64,
    fail_fast: bool,
};

pub const default_profile = Profile{
    .name = "default",
    .default_cases = 100,
    .default_time_budget_ms = 1000,
    .fail_fast = true,
};

pub const hardened_profile = Profile{
    .name = "hardened",
    .default_cases = 1000,
    .default_time_budget_ms = 10_000,
    .fail_fast = false,
};

pub fn profileByName(name: []const u8) Profile {
    if (@import("std").mem.eql(u8, name, hardened_profile.name)) return hardened_profile;
    return default_profile;
}

pub fn prefixForKind(kind: WorkflowKind) []const u8 {
    return switch (kind) {
        .property => "zion/property:",
        .fuzz => "zion/fuzz:",
        .bench => "zion/bench:",
        .mock => "zion/mock:",
    };
}

pub const workflow_cases = [_]TestCase{
    .{ .name = "zion/property: addition is commutative", .kind = .property },
    .{ .name = "zion/fuzz: parseInteger is crash-free", .kind = .fuzz },
    .{ .name = "zion/bench: fibonacci performance", .kind = .bench },
    .{ .name = "zion/mock: divide handles zero", .kind = .mock },
};

pub const compatibility_cases = [_]TestCase{
    .{ .name = "ghostspec/property: addition is commutative", .kind = .property },
    .{ .name = "ghostspec/fuzz: parseInteger is crash-free", .kind = .fuzz },
    .{ .name = "ghostspec/bench: fibonacci performance", .kind = .bench },
    .{ .name = "ghostspec/mock: divide handles zero", .kind = .mock },
};
