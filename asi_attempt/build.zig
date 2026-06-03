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

    // Generalization harness: train on one regime, test cold on held-out regimes.
    const gen_exe = b.addExecutable(.{
        .name = "ghost_gen_eval",
        .root_source_file = b.path("gen_eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_exe);
    const run_gen_cmd = b.addRunArtifact(gen_exe);
    run_gen_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_gen_cmd.addArgs(args);
    }
    const run_gen_step = b.step("eval-gen", "Run the generalization (held-out) harness");
    run_gen_step.dependOn(&run_gen_cmd.step);

    // Expressiveness-ceiling probe: forward-model error on affine vs real dynamics.
    const probe_exe = b.addExecutable(.{
        .name = "ghost_dynamics_probe",
        .root_source_file = b.path("dynamics_probe.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(probe_exe);
    const run_probe_cmd = b.addRunArtifact(probe_exe);
    run_probe_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_probe_cmd.addArgs(args);
    }
    const run_probe_step = b.step("probe", "Run the expressiveness-ceiling dynamics probe");
    run_probe_step.dependOn(&run_probe_cmd.step);

    // Item 2: closure principle on a real problem (k-sparse parity).
    const parity_exe = b.addExecutable(.{
        .name = "ghost_parity",
        .root_source_file = b.path("parity_closure.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(parity_exe);
    const run_parity_cmd = b.addRunArtifact(parity_exe);
    run_parity_cmd.step.dependOn(b.getInstallStep());
    const run_parity_step = b.step("parity", "Run the k-sparse parity closure experiment");
    run_parity_step.dependOn(&run_parity_cmd.step);

    // Macro-action discovery: temporal primitives for dual-band control.
    const macro_exe = b.addExecutable(.{
        .name = "ghost_macro",
        .root_source_file = b.path("macro_discover.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(macro_exe);
    const run_macro_cmd = b.addRunArtifact(macro_exe);
    run_macro_cmd.step.dependOn(b.getInstallStep());
    const run_macro_step = b.step("macro-discover", "Run macro-action discovery experiment");
    run_macro_step.dependOn(&run_macro_cmd.step);

    // Adaptive feature discovery: self-directed model repair via disagreement detection.
    const adapt_exe = b.addExecutable(.{
        .name = "ghost_adaptive",
        .root_source_file = b.path("adaptive_feature.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(adapt_exe);
    const run_adapt_cmd = b.addRunArtifact(adapt_exe);
    run_adapt_cmd.step.dependOn(b.getInstallStep());
    const run_adapt_step = b.step("adaptive-feature", "Run adaptive feature discovery experiment");
    run_adapt_step.dependOn(&run_adapt_cmd.step);

    // #38/#53: emergent op-pair escape + closure-principle falsification.
    const syn_exe = b.addExecutable(.{
        .name = "ghost_synergy",
        .root_source_file = b.path("synergy.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(syn_exe);
    const run_syn_cmd = b.addRunArtifact(syn_exe);
    run_syn_cmd.step.dependOn(b.getInstallStep());
    const run_syn_step = b.step("synergy", "Run the emergent-escape / falsification experiment");
    run_syn_step.dependOn(&run_syn_cmd.step);

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
