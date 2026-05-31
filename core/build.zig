const std = @import("std");

// Ghost Research — shared engine library ("core").
//
// Every shared source file is exposed as a PUBLIC named module so that the
// per-project builds (../ghost_engines, ../01_reservoir_engines, ...) can
// import it via:  const core = b.dependency("core", .{}); core.module("linear")
//
// The modules are wired into a full mesh below: each core module can
// @import any other core module by name. This mirrors the original
// makeGhostModules/addGhostImports wiring from the monolith and guarantees
// exactly ONE instance of each engine across the whole build graph.
const CoreModule = struct { name: []const u8, path: []const u8 };

const core_modules = [_]CoreModule{
    .{ .name = "absolute_final", .path = "src/absolute_final.zig" },
    .{ .name = "anchor_readout", .path = "src/adapters/anchor_readout.zig" },
    .{ .name = "domain_bittape", .path = "src/adapters/domain_bittape.zig" },
    .{ .name = "domain_boolean", .path = "src/adapters/domain_boolean.zig" },
    .{ .name = "domain_meta_engine_dual", .path = "src/adapters/domain_meta_engine_dual.zig" },
    .{ .name = "domain_meta_engine_mulfree_l24", .path = "src/adapters/domain_meta_engine_mulfree_l24.zig" },
    .{ .name = "domain_meta_engine_mulfree", .path = "src/adapters/domain_meta_engine_mulfree.zig" },
    .{ .name = "domain_meta_engine_opset", .path = "src/adapters/domain_meta_engine_opset.zig" },
    .{ .name = "domain_meta_engine_sort", .path = "src/adapters/domain_meta_engine_sort.zig" },
    .{ .name = "domain_meta_engine", .path = "src/adapters/domain_meta_engine.zig" },
    .{ .name = "domain_meta_meta_engine_dual", .path = "src/adapters/domain_meta_meta_engine_dual.zig" },
    .{ .name = "domain_meta_meta_engine_mulfree_l24", .path = "src/adapters/domain_meta_meta_engine_mulfree_l24.zig" },
    .{ .name = "domain_meta_meta_engine_mulfree", .path = "src/adapters/domain_meta_meta_engine_mulfree.zig" },
    .{ .name = "domain_meta_meta_engine_opset", .path = "src/adapters/domain_meta_meta_engine_opset.zig" },
    .{ .name = "domain_meta_meta_engine_sort", .path = "src/adapters/domain_meta_meta_engine_sort.zig" },
    .{ .name = "domain_meta_meta_engine", .path = "src/adapters/domain_meta_meta_engine.zig" },
    .{ .name = "domain_meta_meta_meta_engine_dual", .path = "src/adapters/domain_meta_meta_meta_engine_dual.zig" },
    .{ .name = "domain_meta_meta_meta_engine_mulfree_l24", .path = "src/adapters/domain_meta_meta_meta_engine_mulfree_l24.zig" },
    .{ .name = "domain_meta_meta_meta_engine_mulfree", .path = "src/adapters/domain_meta_meta_meta_engine_mulfree.zig" },
    .{ .name = "domain_meta_meta_meta_engine_opset", .path = "src/adapters/domain_meta_meta_meta_engine_opset.zig" },
    .{ .name = "domain_meta_meta_meta_engine_sort", .path = "src/adapters/domain_meta_meta_meta_engine_sort.zig" },
    .{ .name = "domain_meta_meta_meta_engine", .path = "src/adapters/domain_meta_meta_meta_engine.zig" },
    .{ .name = "domain_meta_meta_meta_meta_engine", .path = "src/adapters/domain_meta_meta_meta_meta_engine.zig" },
    .{ .name = "domain_opset", .path = "src/adapters/domain_opset.zig" },
    .{ .name = "domain_search_strategy", .path = "src/adapters/domain_search_strategy.zig" },
    .{ .name = "domain_128_arx", .path = "src/adapters/domain_128_arx.zig" },
    .{ .name = "domain_128_tier4", .path = "src/adapters/domain_128_tier4.zig" },
    .{ .name = "domain_alien_hack", .path = "src/adapters/domain_alien_hack.zig" },
    .{ .name = "domain_graph_alien", .path = "src/adapters/domain_graph_alien.zig" },
    .{ .name = "domain_general", .path = "src/adapters/domain_general.zig" },
    .{ .name = "domain_symbolic_arx", .path = "src/adapters/domain_symbolic_arx.zig" },
    .{ .name = "native_prover", .path = "src/adapters/native_prover.zig" },
    .{ .name = "domain_sort_net", .path = "src/adapters/domain_sort_net.zig" },
    .{ .name = "domain_u64_bijective", .path = "src/adapters/domain_u64_bijective.zig" },
    .{ .name = "domain_u64_mixer_dual", .path = "src/adapters/domain_u64_mixer_dual.zig" },
    .{ .name = "domain_u64_mixer_mulfree_compat_l24", .path = "src/adapters/domain_u64_mixer_mulfree_compat_l24.zig" },
    .{ .name = "domain_u64_mixer_mulfree_compat", .path = "src/adapters/domain_u64_mixer_mulfree_compat.zig" },
    .{ .name = "domain_u64_mixer_mulfree", .path = "src/adapters/domain_u64_mixer_mulfree.zig" },
    .{ .name = "domain_u64_mixer_nonlinear", .path = "src/adapters/domain_u64_mixer_nonlinear.zig" },
    .{ .name = "domain_u64_mixer", .path = "src/adapters/domain_u64_mixer.zig" },
    .{ .name = "invention_engine", .path = "src/adapters/invention_engine.zig" },
    .{ .name = "mul_free_challenge", .path = "src/adapters/mul_free_challenge.zig" },
    .{ .name = "smt_verify", .path = "src/adapters/smt_verify.zig" },
    .{ .name = "smt_alien_hack", .path = "src/adapters/smt_alien_hack.zig" },
    .{ .name = "smt_graph_alien", .path = "src/adapters/smt_graph_alien.zig" },
    .{ .name = "sovereign_interface", .path = "src/adapters/sovereign_interface.zig" },
    .{ .name = "vsa_decoder", .path = "src/adapters/vsa_decoder.zig" },
    .{ .name = "aetheric", .path = "src/aetheric.zig" },
    .{ .name = "aether", .path = "src/aether.zig" },
    .{ .name = "absolute_production", .path = "src/archived_cores/absolute_production.zig" },
    .{ .name = "absolute_proof_core", .path = "src/archived_cores/absolute_proof_core.zig" },
    .{ .name = "absolute_archived", .path = "src/archived_cores/absolute.zig" },
    .{ .name = "grounded_core", .path = "src/archived_cores/grounded_core.zig" },
    .{ .name = "infinity_core", .path = "src/archived_cores/infinity.zig" },
    .{ .name = "null_core", .path = "src/archived_cores/null_core.zig" },
    .{ .name = "ghost_ast_emitter", .path = "src/compiler/ast_emitter.zig" },
    .{ .name = "echo", .path = "src/echo.zig" },
    .{ .name = "linear", .path = "src/linear.zig" },
    .{ .name = "linear_lite", .path = "src/linear_lite.zig" },
    .{ .name = "flux", .path = "src/flux.zig" },
    .{ .name = "loop_linear", .path = "src/loop_linear.zig" },
    .{ .name = "triple_linear", .path = "src/triple_linear.zig" },
    .{ .name = "hyper_bitset", .path = "src/hyper_bitset.zig" },
    .{ .name = "lore", .path = "src/lore.zig" },
    .{ .name = "manifold", .path = "src/manifold.zig" },
    .{ .name = "omni", .path = "src/omni.zig" },
    .{ .name = "ghost_compiler_loop", .path = "src/oracle/compiler_loop.zig" },
    .{ .name = "sandbox", .path = "src/oracle/sandbox.zig" },
    .{ .name = "ghost_codebook", .path = "src/semantics/concept_codebook.zig" },
    .{ .name = "ghost_grounding", .path = "src/semantics/intent_grounding.zig" },
    .{ .name = "ghost_topology", .path = "src/semantics/topology.zig" },
    .{ .name = "sovereign", .path = "src/sovereign.zig" },
    .{ .name = "state", .path = "src/state_node.zig" },
    .{ .name = "vsa", .path = "src/vsa.zig" },
};

// Files that are both a core library module AND an executable entry point.
const dual_exes = [_]CoreModule{
    .{ .name = "anchor_readout", .path = "src/adapters/anchor_readout.zig" },
    .{ .name = "mul_free_challenge", .path = "src/adapters/mul_free_challenge.zig" },
    .{ .name = "sovereign_interface", .path = "src/adapters/sovereign_interface.zig" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var mods: [core_modules.len]*std.Build.Module = undefined;
    inline for (core_modules, 0..) |cm, i| {
        mods[i] = b.addModule(cm.name, .{
            .root_source_file = b.path(cm.path),
            .target = target,
            .optimize = optimize,
        });
    }

    // Full mesh wiring.
    for (mods) |dst| {
        inline for (core_modules, 0..) |cm, i| {
            if (dst != mods[i]) dst.addImport(cm.name, mods[i]);
        }
    }

    // Build the dual-role executables from core sources so their binaries
    // exist; dependents still import them as modules.
    for (dual_exes) |de| {
        const exe = b.addExecutable(.{
            .name = de.name,
            .root_source_file = b.path(de.path),
            .target = target,
            .optimize = optimize,
        });
        inline for (core_modules, 0..) |cm, i| {
            exe.root_module.addImport(cm.name, mods[i]);
        }
        b.installArtifact(exe);
    }
}
