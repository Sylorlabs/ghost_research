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
    const motor_bridge = b.addModule("motor_bridge", .{ .root_source_file = b.path("src/motor_bridge.zig") });
    const logic_kernel = b.addModule("logic_kernel", .{ .root_source_file = b.path("src/logic_kernel.zig") });
    
    cognition.addImport("native_prover", core.module("native_prover"));
    cognition.addImport("domain_concept_memory", core.module("domain_concept_memory"));
    motor_bridge.addImport("native_prover", core.module("native_prover"));

    const exe = b.addExecutable(.{
        .name = "agi_final",
        .root_source_file = b.path("src/body.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("perception", perception);
    exe.root_module.addImport("cognition", cognition);
    exe.root_module.addImport("homeostasis", homeostasis);
    exe.root_module.addImport("motor_bridge", motor_bridge);
    exe.root_module.addImport("logic_kernel", logic_kernel);
    
    b.installArtifact(exe);
}
