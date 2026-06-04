const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "motor_architecture_search",
        .root_source_file = b.path("src/motor_architecture_search.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("domain_agi_motor_implementation", core.module("domain_agi_motor_implementation"));
    b.installArtifact(exe);
}
