const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---- wcore: the typed W-type invention engine -------------------------
    const exe = b.addExecutable(.{
        .name = "wcore",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Run the wcore W-type invention engine");
    run_step.dependOn(&run.step);

    // ---- wcore-pure: the minimal-bias SK-combinator engine ----------------
    const pure = b.addExecutable(.{
        .name = "wcore-pure",
        .root_source_file = b.path("src/pure_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(pure);

    const run_pure = b.addRunArtifact(pure);
    if (b.args) |args| run_pure.addArgs(args);
    const run_pure_step = b.step("run-pure", "Run the minimal-bias SK-combinator engine");
    run_pure_step.dependOn(&run_pure.step);

    // ---- wcore-agent: the compression-driven sensorimotor agent -----------
    const agent_exe = b.addExecutable(.{
        .name = "wcore-agent",
        .root_source_file = b.path("src/agent_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(agent_exe);

    const run_agent = b.addRunArtifact(agent_exe);
    if (b.args) |args| run_agent.addArgs(args);
    const run_agent_step = b.step("run-agent", "Run the compression-driven sensorimotor agent");
    run_agent_step.dependOn(&run_agent.step);

    // ---- wcore-invent: the primitive-inventing engine (PLAN_INVENTION) ----
    const invent = b.addExecutable(.{
        .name = "wcore-invent",
        .root_source_file = b.path("src/inv_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(invent);

    const run_invent = b.addRunArtifact(invent);
    if (b.args) |args| run_invent.addArgs(args);
    const run_invent_step = b.step("run-invent", "Run the primitive-inventing engine");
    run_invent_step.dependOn(&run_invent.step);

    // ---- tests (all engines) ----------------------------------------------
    const test_step = b.step("test", "Run all wcore tests");

    const invent_tests = b.addTest(.{
        .root_source_file = b.path("src/inv_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(invent_tests).step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const pure_tests = b.addTest(.{
        .root_source_file = b.path("src/pure_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(pure_tests).step);

    const agent_tests = b.addTest(.{
        .root_source_file = b.path("src/agent_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(agent_tests).step);
}
