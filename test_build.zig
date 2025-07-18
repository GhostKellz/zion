const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Create test step
    const test_step = b.step("test-v103", "Run v1.0.3 comprehensive tests");
    
    // Import dependencies
    const zsync_mod = b.lazyDependency("zsync", .{
        .target = target,
        .optimize = optimize,
    });
    
    const phantom_mod = b.lazyDependency("phantom", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Create test executable
    const test_exe = b.addTest(.{
        .root_source_file = b.path("src/tests/test_runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add dependencies
    if (zsync_mod) |zsync| {
        test_exe.root_module.addImport("zsync", zsync.module("zsync"));
    }
    
    if (phantom_mod) |phantom| {
        test_exe.root_module.addImport("phantom", phantom.module("phantom"));
    }
    
    // Add source files to module
    test_exe.root_module.addAnonymousImport("unified_registry_manager", .{
        .root_source_file = b.path("src/unified_registry_manager.zig"),
        .imports = &.{
            .{ .name = "zsync", .module = zsync_mod.?.module("zsync") },
        },
    });
    
    test_exe.root_module.addAnonymousImport("http_client", .{
        .root_source_file = b.path("src/http_client.zig"),
    });
    
    test_exe.root_module.addAnonymousImport("async_downloader", .{
        .root_source_file = b.path("src/async_downloader.zig"),
        .imports = &.{
            .{ .name = "zsync", .module = zsync_mod.?.module("zsync") },
        },
    });
    
    test_exe.root_module.addAnonymousImport("request_batcher", .{
        .root_source_file = b.path("src/request_batcher.zig"),
        .imports = &.{
            .{ .name = "zsync", .module = zsync_mod.?.module("zsync") },
        },
    });
    
    test_exe.root_module.addAnonymousImport("registry_config", .{
        .root_source_file = b.path("src/registry_config.zig"),
    });
    
    // Run the tests
    const run_tests = b.addRunArtifact(test_exe);
    test_step.dependOn(&run_tests.step);
}