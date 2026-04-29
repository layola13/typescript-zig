const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zts",
        .root_source_file = b.path("zig/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the zts executable");
    run_step.dependOn(&run_cmd.step);

    // Main test target
    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("zig/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // Test runner executable
    const test_runner = b.addExecutable(.{
        .name = "test-runner",
        .root_source_file = b.path("zig/test/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(test_runner);

    const test_run_cmd = b.addRunArtifact(test_runner);
    const test_run_step = b.step("test:run", "Run test runner");
    test_run_step.dependOn(&test_run_cmd.step);
}
