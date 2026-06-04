const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const perception = b.addModule("perception", .{ .root_source_file = b.path("src/perception.zig") });
    const cognition = b.addModule("cognition", .{ .root_source_file = b.path("src/cognition.zig") });
    const homeostasis = b.addModule("homeostasis", .{ .root_source_file = b.path("src/homeostasis.zig") });
    const motor = b.addModule("motor", .{ .root_source_file = b.path("src/motor.zig") });
    
    cognition.addImport("native_prover", core.module("native_prover"));
    cognition.addImport("domain_concept_memory", core.module("domain_concept_memory"));
    motor.addImport("native_prover", core.module("native_prover"));

    const exe_curi = b.addExecutable(.{
        .name = "agi_curiosity_learner",
        .root_source_file = b.path("src/agi_curiosity_learner.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_curi.root_module.addImport("domain_agi_curiosity", core.module("domain_agi_curiosity"));
    exe_curi.root_module.addImport("perception", perception);
    exe_curi.root_module.addImport("cognition", cognition);
    b.installArtifact(exe_curi);

    const exe_autonomy = b.addExecutable(.{
        .name = "agi_autonomy_loop",
        .root_source_file = b.path("src/agi_autonomy_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_autonomy.root_module.addImport("domain_agi_objective_synthesis", core.module("domain_agi_objective_synthesis"));
    exe_autonomy.root_module.addImport("perception", perception);
    exe_autonomy.root_module.addImport("cognition", cognition);
    exe_autonomy.root_module.addImport("motor", motor);
    b.installArtifact(exe_autonomy);

    const exe_hw = b.addExecutable(.{
        .name = "hardware_manifest_search",
        .root_source_file = b.path("src/hardware_manifest_search.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_hw.root_module.addImport("domain_agi_hardware_substrate", core.module("domain_agi_hardware_substrate"));
    b.installArtifact(exe_hw);

    const exe_obs = b.addExecutable(.{
        .name = "self_observation_search",
        .root_source_file = b.path("src/self_observation_search.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_obs.root_module.addImport("domain_agi_self_observation", core.module("domain_agi_self_observation"));
    b.installArtifact(exe_obs);

    const exe_plan = b.addExecutable(.{
        .name = "motor_plan_search",
        .root_source_file = b.path("src/motor_plan_search.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_plan.root_module.addImport("domain_agi_subsystem_synthesis", core.module("domain_agi_subsystem_synthesis"));
    b.installArtifact(exe_plan);

    const exe = b.addExecutable(.{
        .name = "agi_body",
        .root_source_file = b.path("src/body.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("perception", perception);
    exe.root_module.addImport("cognition", cognition);
    exe.root_module.addImport("homeostasis", homeostasis);
    exe.root_module.addImport("motor", motor);
    
    b.installArtifact(exe);
}
