const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "transcendence_synthesis",
        .root_source_file = b.path("src/transcendence_synthesis.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("domain_agi_transcendence", core.module("domain_agi_transcendence"));
    b.installArtifact(exe);
}
