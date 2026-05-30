const std = @import("std");

// Standalone build for this research thread. Depends on ../core for shared
// engine modules; each exe is offered the full core module set (unused
// imports are free — a module compiles only when actually @import'd).
const core_module_names = [_][]const u8{
    "absolute_archived",
    "absolute_final",
    "absolute_production",
    "absolute_proof_core",
    "aether",
    "aetheric",
    "anchor_readout",
    "domain_bittape",
    "domain_boolean",
    "domain_meta_engine",
    "domain_meta_engine_dual",
    "domain_meta_engine_mulfree",
    "domain_meta_engine_mulfree_l24",
    "domain_meta_engine_opset",
    "domain_meta_engine_sort",
    "domain_meta_meta_engine",
    "domain_meta_meta_engine_dual",
    "domain_meta_meta_engine_mulfree",
    "domain_meta_meta_engine_mulfree_l24",
    "domain_meta_meta_engine_opset",
    "domain_meta_meta_engine_sort",
    "domain_meta_meta_meta_engine",
    "domain_meta_meta_meta_engine_dual",
    "domain_meta_meta_meta_engine_mulfree",
    "domain_meta_meta_meta_engine_mulfree_l24",
    "domain_meta_meta_meta_engine_opset",
    "domain_meta_meta_meta_engine_sort",
    "domain_meta_meta_meta_meta_engine",
    "domain_opset",
    "domain_search_strategy",
    "domain_sort_net",
    "domain_u64_mixer",
    "domain_u64_mixer_dual",
    "domain_u64_mixer_mulfree",
    "domain_u64_mixer_mulfree_compat",
    "domain_u64_mixer_mulfree_compat_l24",
    "echo",
    "linear",
    "linear_lite",
    "flux",
    "loop_linear",
    "triple_linear",
    "ghost_ast_emitter",
    "ghost_codebook",
    "ghost_compiler_loop",
    "ghost_grounding",
    "ghost_topology",
    "grounded_core",
    "hyper_bitset",
    "infinity_core",
    "invention_engine",
    "lore",
    "manifold",
    "mul_free_challenge",
    "null_core",
    "omni",
    "sandbox",
    "smt_verify",
    "sovereign",
    "sovereign_interface",
    "state",
    "vsa",
    "vsa_decoder",
};

const Exe = struct { name: []const u8, path: []const u8, z3: bool = false };

const exes = [_]Exe{
    .{ .name = "absolute_invention", .path = "src/absolute_invention.zig" },
    .{ .name = "alien_breakthrough_inventor", .path = "src/alien_breakthrough_inventor.zig" },
    .{ .name = "anchor_distribution", .path = "src/anchor_distribution.zig" },
    .{ .name = "engine_genesis", .path = "src/engine_genesis.zig" },
    .{ .name = "general_inventor", .path = "src/general_inventor.zig" },
    .{ .name = "generated_geometry_invention", .path = "src/generated_geometry_invention.zig" },
    .{ .name = "geometry_artifact_compiler", .path = "src/geometry_artifact_compiler.zig" },
    .{ .name = "invention_global", .path = "src/invention_global.zig" },
    .{ .name = "invention_relaxed", .path = "src/invention_relaxed.zig" },
    .{ .name = "novelty_invention", .path = "src/novelty_invention.zig" },
    .{ .name = "phase_lattice_inventor", .path = "src/phase_lattice_inventor.zig" },
    .{ .name = "search_strategy_meta", .path = "src/search_strategy_meta.zig" },
    .{ .name = "targeted_invention", .path = "src/targeted_invention.zig" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.dependency("core", .{ .target = target, .optimize = optimize });

    for (exes) |e| {
        const exe = b.addExecutable(.{
            .name = e.name,
            .root_source_file = b.path(e.path),
            .target = target,
            .optimize = optimize,
        });
        inline for (core_module_names) |n| exe.root_module.addImport(n, core.module(n));
        if (e.z3) {
            exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
            exe.root_module.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
            exe.root_module.linkSystemLibrary("z3", .{});
            exe.root_module.linkSystemLibrary("c", .{});
        }
        b.installArtifact(exe);
    }
}
