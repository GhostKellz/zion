const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_exe = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests/active_test_runner.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }) });
    const run_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run maintained standalone tests");
    test_step.dependOn(&run_tests.step);
}
