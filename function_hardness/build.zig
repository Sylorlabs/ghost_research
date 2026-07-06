const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "function_hardness",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Exhaustive n=4 predicate hardness landscape");
    run_step.dependOn(&run_cmd.step);

    const sample_exe = b.addExecutable(.{
        .name = "function_hardness_sample",
        .root_source_file = b.path("sample.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(sample_exe);

    const run_sample_cmd = b.addRunArtifact(sample_exe);
    run_sample_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_sample_cmd.addArgs(args);
    const run_sample_step = b.step("sample", "Sampling-based hardness for n=5 and n=6");
    run_sample_step.dependOn(&run_sample_cmd.step);

    const math_exe = b.addExecutable(.{
        .name = "math_hypotheses",
        .root_source_file = b.path("math_hypotheses.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(math_exe);

    const run_math_cmd = b.addRunArtifact(math_exe);
    run_math_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_math_cmd.addArgs(args);
    const run_math_step = b.step("math", "Four analytical hypotheses on the n=4 predicate landscape");
    run_math_step.dependOn(&run_math_cmd.step);

    const export_exe = b.addExecutable(.{
        .name = "function_hardness_export_top",
        .root_source_file = b.path("export_top.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(export_exe);

    const run_export_cmd = b.addRunArtifact(export_exe);
    run_export_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_export_cmd.addArgs(args);
    const run_export_step = b.step("export-top", "Top-5 hardest predicates per substrate");
    run_export_step.dependOn(&run_export_cmd.step);
}
