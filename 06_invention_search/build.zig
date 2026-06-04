const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("core", .{
        .target = target,
        .optimize = optimize,
    });

    const domain_meta_architect = b.addModule("domain_meta_architect", .{
        .root_source_file = b.path("src/domain_meta_architect.zig"),
    });
    // Add required dependencies to the module
    domain_meta_architect.addImport("domain_graph_alien", core.module("domain_graph_alien"));
    domain_meta_architect.addImport("domain_alien_hack", core.module("domain_alien_hack"));
    domain_meta_architect.addImport("smt_verify", core.module("smt_verify"));
    domain_meta_architect.addImport("smt_graph_alien", core.module("smt_graph_alien"));

    const exe_body = b.addExecutable(.{
        .name = "agi_body_plan_search",
        .root_source_file = b.path("src/agi_body_plan_search.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_body.root_module.addImport("domain_agi_body", core.module("domain_agi_body"));
    b.installArtifact(exe_body);

    const exe_agi = b.addExecutable(.{
        .name = "agi_blueprint_search",
        .root_source_file = b.path("src/agi_blueprint_search.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_agi.root_module.addImport("domain_agi_blueprint", core.module("domain_agi_blueprint"));
    b.installArtifact(exe_agi);

    const exe_gaunt = b.addExecutable(.{
        .name = "adversarial_gauntlet",
        .root_source_file = b.path("src/adversarial_gauntlet.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_gaunt.root_module.addImport("domain_graph_alien", core.module("domain_graph_alien"));
    exe_gaunt.root_module.addImport("domain_alien_hack", core.module("domain_alien_hack"));
    exe_gaunt.root_module.addImport("domain_sort_net", core.module("domain_sort_net"));
    exe_gaunt.root_module.addImport("domain_u64_mixer", core.module("domain_u64_mixer"));
    exe_gaunt.root_module.addImport("invention_engine", core.module("invention_engine"));
    b.installArtifact(exe_gaunt);

    const exe_reflect = b.addExecutable(.{
        .name = "recursive_reflection_search",
        .root_source_file = b.path("src/recursive_reflection_search.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_reflect.root_module.addImport("domain_heuristic_evolution", core.module("domain_heuristic_evolution"));
    exe_reflect.root_module.addImport("invention_engine", core.module("invention_engine"));
    b.installArtifact(exe_reflect);

    const exe_inv = b.addExecutable(.{
        .name = "heuristic_invention",
        .root_source_file = b.path("src/heuristic_invention.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_inv.root_module.addImport("heuristic_gp", core.module("heuristic_gp"));
    b.installArtifact(exe_inv);

    const exe_tourn = b.addExecutable(.{
        .name = "generality_tournament",
        .root_source_file = b.path("src/generality_tournament.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_tourn.root_module.addImport("domain_graph_alien", core.module("domain_graph_alien"));
    exe_tourn.root_module.addImport("domain_alien_hack", core.module("domain_alien_hack"));
    exe_tourn.root_module.addImport("domain_sort_net", core.module("domain_sort_net"));
    exe_tourn.root_module.addImport("domain_u64_mixer", core.module("domain_u64_mixer"));
    exe_tourn.root_module.addImport("invention_engine", core.module("invention_engine"));
    b.installArtifact(exe_tourn);

    const exe_combat = b.addExecutable(.{
        .name = "combat_benchmark",
        .root_source_file = b.path("src/combat_benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_combat.root_module.addImport("domain_graph_alien", core.module("domain_graph_alien"));
    exe_combat.root_module.addImport("domain_alien_hack", core.module("domain_alien_hack"));
    exe_combat.root_module.addImport("smt_verify", core.module("smt_verify"));
    exe_combat.root_module.addImport("smt_graph_alien", core.module("smt_graph_alien"));
    
    // Link Z3/C
    exe_combat.root_module.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    exe_combat.root_module.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
    exe_combat.root_module.linkSystemLibrary("z3", .{});
    exe_combat.root_module.linkSystemLibrary("c", .{});

    b.installArtifact(exe_combat);

    const exe_law = b.addExecutable(.{
        .name = "law_synthesizer",
        .root_source_file = b.path("src/law_synthesizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe_law);

    const exe_phys = b.addExecutable(.{
        .name = "search_physics_emitter",
        .root_source_file = b.path("src/search_physics_emitter.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_phys.root_module.addImport("domain_meta_architect", domain_meta_architect);
    exe_phys.root_module.addImport("domain_graph_alien", core.module("domain_graph_alien"));
    exe_phys.root_module.addImport("domain_alien_hack", core.module("domain_alien_hack"));
    b.installArtifact(exe_phys);

    const exe_meta = b.addExecutable(.{
        .name = "actual_meta_invention",
        .root_source_file = b.path("src/actual_meta_invention.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_meta.root_module.addImport("domain_meta_architect", domain_meta_architect);
    
    // Link Z3/C for SMT integration
    exe_meta.root_module.addSystemIncludePath(.{ .cwd_relative = "/usr/include" });
    exe_meta.root_module.addLibraryPath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu" });
    exe_meta.root_module.linkSystemLibrary("z3", .{});
    exe_meta.root_module.linkSystemLibrary("c", .{});
    
    b.installArtifact(exe_meta);
}
