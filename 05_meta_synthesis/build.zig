const std = @import("std");

// Standalone build — meta-engine stack (research threads 05/06/07).
// Depends on ../core for shared engine modules; each exe is offered the full
// core module set (unused imports are free — compiled only when @import'd).
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
    "domain_symbolic_arx",
    "domain_128_arx",
    "domain_128_tier4",
    "domain_alien_hack",
    "domain_general",
    "domain_sort_net",
    "domain_u64_bijective",
    "domain_u64_mixer",
    "domain_u64_mixer_dual",
    "domain_u64_mixer_mulfree",
    "domain_u64_mixer_nonlinear",
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
    "smt_alien_hack",
    "sovereign",
    "sovereign_interface",
    "state",
    "vsa",
    "vsa_decoder",
};

const Exe = struct { name: []const u8, path: []const u8, z3: bool = false };

const exes = [_]Exe{
    .{ .name = "alien_hack_cegis", .path = "src/alien_hack_cegis.zig", .z3 = true },
    .{ .name = "symbolic_tracing_search", .path = "src/symbolic_tracing_search.zig", .z3 = false },
    .{ .name = "pure_tier4_fuzzer", .path = "src/pure_tier4_fuzzer.zig", .z3 = false },
    .{ .name = "alien_hack_search", .path = "src/alien_hack_search.zig", .z3 = false },
    .{ .name = "tier4_search", .path = "src/tier4_search.zig", .z3 = false },
    .{ .name = "generalist_search", .path = "src/generalist_search.zig", .z3 = false },
    .{ .name = "tier4_benchmark", .path = "src/tier4_benchmark.zig", .z3 = false },
    .{ .name = "arx_128_search", .path = "src/arx_128_search.zig", .z3 = false },
    .{ .name = "arx_128_practrand_emit", .path = "src/arx_128_practrand_emit.zig", .z3 = false },
    .{ .name = "arx_search", .path = "src/arx_search.zig", .z3 = false },
    .{ .name = "arx_practrand_emit", .path = "src/arx_practrand_emit.zig", .z3 = false },
    .{ .name = "nonlinear_escape_search", .path = "src/nonlinear_escape_search.zig", .z3 = false },
    .{ .name = "affine_closure", .path = "src/affine_closure.zig", .z3 = true },
    .{ .name = "bittape_inspect", .path = "src/bittape_inspect.zig" },
    .{ .name = "bittape_inventor", .path = "src/bittape_inventor.zig" },
    .{ .name = "calibration_absolute", .path = "src/calibration_absolute.zig" },
    .{ .name = "chain_runner_sort", .path = "src/chain_runner_sort.zig" },
    .{ .name = "chain_runner", .path = "src/chain_runner.zig" },
    .{ .name = "champion_holdout_validation", .path = "src/champion_holdout_validation.zig" },
    .{ .name = "champion_pairwise", .path = "src/champion_pairwise.zig" },
    .{ .name = "invention_chain", .path = "src/invention_chain.zig" },
    .{ .name = "lineage_audit", .path = "src/lineage_audit.zig" },
    .{ .name = "meta_engine_baseline_sort", .path = "src/meta_engine_baseline_sort.zig" },
    .{ .name = "meta_engine_baseline", .path = "src/meta_engine_baseline.zig" },
    .{ .name = "meta_engine_runner_sort", .path = "src/meta_engine_runner_sort.zig" },
    .{ .name = "meta_engine_runner", .path = "src/meta_engine_runner.zig" },
    .{ .name = "meta_meta_chain_runner", .path = "src/meta_meta_chain_runner.zig" },
    .{ .name = "meta_meta_engine_runner", .path = "src/meta_meta_engine_runner.zig" },
    .{ .name = "meta_mixer_export_dual", .path = "src/meta_mixer_export_dual.zig" },
    .{ .name = "meta_mixer_export_mulfree_l24", .path = "src/meta_mixer_export_mulfree_l24.zig" },
    .{ .name = "meta_mixer_export_mulfree", .path = "src/meta_mixer_export_mulfree.zig" },
    .{ .name = "meta_mixer_export", .path = "src/meta_mixer_export.zig" },
    .{ .name = "mixer_csv_emit", .path = "src/mixer_csv_emit.zig" },
    .{ .name = "mmm_chain_runner", .path = "src/mmm_chain_runner.zig" },
    .{ .name = "mmm_holdout_hillclimb_dual", .path = "src/mmm_holdout_hillclimb_dual.zig" },
    .{ .name = "mmm_holdout_hillclimb_mulfree_l24", .path = "src/mmm_holdout_hillclimb_mulfree_l24.zig" },
    .{ .name = "mmm_holdout_hillclimb_mulfree", .path = "src/mmm_holdout_hillclimb_mulfree.zig" },
    .{ .name = "mmm_holdout_hillclimb_opset", .path = "src/mmm_holdout_hillclimb_opset.zig" },
    .{ .name = "mmm_holdout_hillclimb_sac", .path = "src/mmm_holdout_hillclimb_sac.zig" },
    .{ .name = "mmm_holdout_hillclimb_sort", .path = "src/mmm_holdout_hillclimb_sort.zig" },
    .{ .name = "mmm_holdout_hillclimb", .path = "src/mmm_holdout_hillclimb.zig" },
    .{ .name = "mmmm_holdout_hillclimb", .path = "src/mmmm_holdout_hillclimb.zig" },
    .{ .name = "mmmm_qd_probe", .path = "src/mmmm_qd_probe.zig" },
    .{ .name = "mmm_qd_probe", .path = "src/mmm_qd_probe.zig" },
    .{ .name = "mul_free_comparison", .path = "src/mul_free_comparison.zig" },
    .{ .name = "mulfree_per_bit_avalanche", .path = "src/mulfree_per_bit_avalanche.zig" },
    .{ .name = "practrand_emit_mulfree", .path = "src/practrand_emit_mulfree.zig" },
    .{ .name = "practrand_emit", .path = "src/practrand_emit.zig" },
    .{ .name = "recursive_engine_loop", .path = "src/recursive_engine_loop.zig" },
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
