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
    "flame",
    "flare",
    "flux",
    "fractal",
    "frost",
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
    "void",
    "vsa",
    "vsa_decoder",
};

const Exe = struct { name: []const u8, path: []const u8, z3: bool = false };

const exes = [_]Exe{
    .{ .name = "conceptless_inventor", .path = "src/conceptless_inventor.zig" },
    .{ .name = "recursive_conceptless_inventor_v2", .path = "src/recursive_conceptless_inventor_v2.zig" },
    .{ .name = "recursive_conceptless_inventor_v3", .path = "src/recursive_conceptless_inventor_v3.zig" },
    .{ .name = "recursive_conceptless_inventor_v4", .path = "src/recursive_conceptless_inventor_v4.zig" },
    .{ .name = "recursive_conceptless_inventor", .path = "src/recursive_conceptless_inventor.zig" },
    .{ .name = "synthesized_conceptless_breakthrough", .path = "src/synthesized_conceptless_breakthrough.zig" },
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
