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
}
