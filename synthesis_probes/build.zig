const std = @import("std");

// Standalone build — the "ghost engine" line (Ghost Core, synthesis probes,
// consultation probes, void/absolute/infinity/null adapters). Depends on
// ../core for shared engine modules; each exe is offered the full core module
// set (unused imports are free — a module compiles only when @import'd).
//
// Archived stubs under src/archived_cores/placeholders/ and the test roots
// (test_sim.zig, tests.zig, calibration.zig) are kept as sources but are not
// built into executables, matching the original monolith.
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

const Exe = struct { name: []const u8, path: []const u8 };

// Executables whose binary name differs from / is fixed independent of the
// source file name.
const explicit_exes = [_]Exe{
    .{ .name = "ghost_core", .path = "src/main.zig" },
    .{ .name = "reproduce_baseline", .path = "src/reproduce_baseline.zig" },
    .{ .name = "chat", .path = "src/chat.zig" },
    .{ .name = "ghost_search", .path = "src/search.zig" },
    .{ .name = "ghost_alien_voice", .path = "src/aetheric_adapter.zig" },
    .{ .name = "ghost_absolute", .path = "src/ghost_absolute_adapter.zig" },
    .{ .name = "ghost_absolute_proof", .path = "src/ghost_absolute_proof_adapter.zig" },
    .{ .name = "ghost_infinity", .path = "src/infinity_adapter.zig" },
    .{ .name = "ghost_null", .path = "src/ghost_null_adapter.zig" },
    .{ .name = "ghost_invent_void", .path = "src/void_cli_adapter.zig" },
    .{ .name = "ghost_final_probe", .path = "src/ghost_final_probe.zig" },
    .{ .name = "ghost_grounded_probe", .path = "src/ghost_grounded_probe.zig" },
    .{ .name = "ghost_zeroscalar_probe", .path = "src/ghost_zeroscalar_probe.zig" },
    .{ .name = "ghost_throughput_bench", .path = "src/ghost_throughput_bench.zig" },
    .{ .name = "grammar_pulse", .path = "src/grammar_pulse.zig" },
    .{ .name = "void_translator", .path = "src/void_translator.zig" },
    .{ .name = "bridge_transceiver", .path = "src/bridge_transceiver.zig" },
    .{ .name = "proper_consultation", .path = "src/proper_consultation.zig" },
};

// Synthesis executables — one per src/synthesis/{name}.zig.
const synthesis_names = [_][]const u8{
    "absolute_final_synthesis",
    "absolute_proof_synthesis",
    "absolute_synthesis",
    "bridge_synthesis",
    "cli_overhaul_synthesis",
    "decoder_synthesis",
    "entangled_singularity_synthesis",
    "final_merge_synthesis",
    "ghost_infinity_synthesis",
    "ghost_null_synthesis",
    "ghost_zero_synthesis",
    "grounded_singularity_synthesis",
    "hardware_mirror_synthesis",
    "infinity_stress_test",
    "ingestion_strategy_synthesis",
    "native_mirror_synthesis",
    "neologism_bridge_synthesis",
    "null_manifesto_synthesis",
    "primitive_resonance_synthesis",
    "probe_map",
    "reiteration_synthesis",
    "semantic_overlap_synthesis",
    "simd_resonance_synthesis",
    "truth_verdict_synthesis",
    "vsa_leap_synthesis",
    "wave2_synthesis",
    "wave3_synthesis",
    "wiki_ingestion_synthesis",
    "zero_scalar_proof",
    "zero_unit_synthesis",
};

// Consultation probes — several binaries from the one measured probe source.
const measured_names = [_][]const u8{
    "ask_experts", "debate_experts", "audit_experts",
    "omni_ingest_verdict", "final_questions", "total_audit",
};

fn addCore(exe: *std.Build.Step.Compile, core: *std.Build.Dependency) void {
    inline for (core_module_names) |n| exe.root_module.addImport(n, core.module(n));
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.dependency("core", .{ .target = target, .optimize = optimize });

    for (explicit_exes) |e| {
        const exe = b.addExecutable(.{
            .name = e.name,
            .root_source_file = b.path(e.path),
            .target = target,
            .optimize = optimize,
        });
        addCore(exe, core);
        b.installArtifact(exe);
    }

    for (synthesis_names) |name| {
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path(b.fmt("src/synthesis/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
        });
        addCore(exe, core);
        b.installArtifact(exe);
    }

    for (measured_names) |name| {
        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path("src/measured_consultation_probe.zig"),
            .target = target,
            .optimize = optimize,
        });
        addCore(exe, core);
        b.installArtifact(exe);
    }
}
