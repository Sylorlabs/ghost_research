const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "agi_manifesto",
        .root_source_file = b.path("src/manifesto_synthesis.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("domain_agi_manifesto", core.module("domain_agi_manifesto"));
    b.installArtifact(exe);
}
