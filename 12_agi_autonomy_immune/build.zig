const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "agi_immune_loop",
        .root_source_file = b.path("src/immune_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("domain_agi_snapshot", core.module("domain_agi_snapshot"));
    exe.root_module.addImport("domain_agi_adversarial_tester", core.module("domain_agi_adversarial_tester"));
    b.installArtifact(exe);
}
