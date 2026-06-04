const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "sentient_loop",
        .root_source_file = b.path("src/sentient_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("domain_agi_subjectivity", core.module("domain_agi_subjectivity"));
    exe.root_module.addImport("domain_agi_value_alignment", core.module("domain_agi_value_alignment"));
    b.installArtifact(exe);
}
