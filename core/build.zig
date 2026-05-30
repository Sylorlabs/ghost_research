const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Core Modules ---
    // These are the shared engines exposed to all project folders.

    const linear = b.addModule("linear", .{ .root_source_file = b.path("src/linear.zig") });
    const linear_lite = b.addModule("linear_lite", .{ .root_source_file = b.path("src/linear_lite.zig") });
    const flux = b.addModule("flux", .{ .root_source_file = b.path("src/flux.zig") });
    const loop_linear = b.addModule("loop_linear", .{ .root_source_file = b.path("src/loop_linear.zig") });
    const triple_linear = b.addModule("triple_linear", .{ .root_source_file = b.path("src/triple_linear.zig") });
    const state = b.addModule("state", .{ .root_source_file = b.path("src/state_node.zig") });
    const vsa = b.addModule("vsa", .{ .root_source_file = b.path("src/vsa.zig") });

    // Helper: add all modules to a target
    const all_modules = [_]struct { name: []const u8, module: *std.Build.Module }{
        .{ .name = "linear", .module = linear },
        .{ .name = "linear_lite", .module = linear_lite },
        .{ .name = "flux", .module = flux },
        .{ .name = "loop_linear", .module = loop_linear },
        .{ .name = "triple_linear", .module = triple_linear },
        .{ .name = "state", .module = state },
        .{ .name = "vsa", .module = vsa },
    };

    // --- Dual-role Executables ---
    // Some core components are also standalone tools.

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/linear.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
