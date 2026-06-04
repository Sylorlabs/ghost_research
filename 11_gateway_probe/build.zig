const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const gateway = b.addModule("gateway", .{ .root_source_file = b.path("src/compiler_gateway.zig") });
    gateway.addImport("native_prover", core.module("native_prover"));

    const exe = b.addExecutable(.{
        .name = "agi_final",
        .root_source_file = b.path("src/body.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("gateway", gateway);
    b.installArtifact(exe);
}
