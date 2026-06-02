const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Ensure ReleaseFast is the default to check real performance
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const exe = b.addExecutable(.{
        .name = "ghost_harness",
        .root_source_file = b.path("test_harness.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the test harness");
    run_step.dependOn(&run_cmd.step);

    const engine_exe = b.addExecutable(.{
        .name = "ghost_engine",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(engine_exe);

    const run_engine_cmd = b.addRunArtifact(engine_exe);
    run_engine_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_engine_cmd.addArgs(args);
    }
    const run_engine_step = b.step("engine", "Run the Ghost Production Engine");
    run_engine_step.dependOn(&run_engine_cmd.step);

    // Evaluation harness: reproducible control benchmark (baselines vs agent).
    const eval_exe = b.addExecutable(.{
        .name = "ghost_eval",
        .root_source_file = b.path("eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(eval_exe);

    const run_eval_cmd = b.addRunArtifact(eval_exe);
    run_eval_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_eval_cmd.addArgs(args);
    }
    const run_eval_step = b.step("eval", "Run the control-benchmark evaluation harness");
    run_eval_step.dependOn(&run_eval_cmd.step);

    // Unit tests over the VSA primitives and the agent's readout channel.
    const tests = b.addTest(.{
        .root_source_file = b.path("tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("unit-test", "Run VSA / agent unit tests");
    test_step.dependOn(&run_tests.step);
}
