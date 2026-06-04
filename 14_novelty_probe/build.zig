const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "divergence_engine",
        .root_source_file = b.path("src/divergence_engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("domain_agi_creative_divergence", core.module("domain_agi_creative_divergence"));
    exe.root_module.addImport("domain_concept_memory", core.module("domain_concept_memory"));
    exe.root_module.addImport("native_prover", core.module("native_prover"));
    b.installArtifact(exe);
}
