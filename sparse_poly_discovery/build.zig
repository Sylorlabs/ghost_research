const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Ensure ReleaseFast is the default to check real performance
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const exe = b.addExecutable(.{
        .name = "ghost_harness",
        .root_source_file = b.path("test_harness.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the test harness");
    run_step.dependOn(&run_cmd.step);

    const engine_exe = b.addExecutable(.{
        .name = "ghost_engine",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(engine_exe);

    const run_engine_cmd = b.addRunArtifact(engine_exe);
    run_engine_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_engine_cmd.addArgs(args);
    }
    const run_engine_step = b.step("engine", "Run the Ghost Production Engine");
    run_engine_step.dependOn(&run_engine_cmd.step);

    // Evaluation harness: reproducible control benchmark (baselines vs agent).
    const eval_exe = b.addExecutable(.{
        .name = "ghost_eval",
        .root_source_file = b.path("eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(eval_exe);

    const run_eval_cmd = b.addRunArtifact(eval_exe);
    run_eval_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_eval_cmd.addArgs(args);
    }
    const run_eval_step = b.step("eval", "Run the control-benchmark evaluation harness");
    run_eval_step.dependOn(&run_eval_cmd.step);

    // EXP-8: planning depth sweep vs greedy mb_mass on the homeostatic band.
    const plan_exe = b.addExecutable(.{
        .name = "ghost_planning_probe",
        .root_source_file = b.path("planning_probe.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(plan_exe);
    const run_plan_cmd = b.addRunArtifact(plan_exe);
    run_plan_cmd.step.dependOn(b.getInstallStep());
    const run_plan_step = b.step("planning-probe", "EXP-8: rollout depth 1/3/5 vs greedy mb_mass");
    run_plan_step.dependOn(&run_plan_cmd.step);

    // Generalization harness: train on one regime, test cold on held-out regimes.
    const gen_exe = b.addExecutable(.{
        .name = "ghost_gen_eval",
        .root_source_file = b.path("gen_eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_exe);
    const run_gen_cmd = b.addRunArtifact(gen_exe);
    run_gen_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_gen_cmd.addArgs(args);
    }
    const run_gen_step = b.step("eval-gen", "Run the generalization (held-out) harness");
    run_gen_step.dependOn(&run_gen_cmd.step);

    // Expressiveness-ceiling probe: forward-model error on affine vs real dynamics.
    const probe_exe = b.addExecutable(.{
        .name = "ghost_dynamics_probe",
        .root_source_file = b.path("dynamics_probe.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(probe_exe);
    const run_probe_cmd = b.addRunArtifact(probe_exe);
    run_probe_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_probe_cmd.addArgs(args);
    }
    const run_probe_step = b.step("probe", "Run the expressiveness-ceiling dynamics probe");
    run_probe_step.dependOn(&run_probe_cmd.step);

    // Item 2: closure principle on a real problem (k-sparse parity).
    const parity_exe = b.addExecutable(.{
        .name = "ghost_parity",
        .root_source_file = b.path("parity_closure.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(parity_exe);
    const run_parity_cmd = b.addRunArtifact(parity_exe);
    run_parity_cmd.step.dependOn(b.getInstallStep());
    const run_parity_step = b.step("parity", "Run the k-sparse parity closure experiment");
    run_parity_step.dependOn(&run_parity_cmd.step);

    // Macro-action discovery: temporal primitives for dual-band control.
    const macro_exe = b.addExecutable(.{
        .name = "ghost_macro",
        .root_source_file = b.path("macro_discover.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(macro_exe);
    const run_macro_cmd = b.addRunArtifact(macro_exe);
    run_macro_cmd.step.dependOn(b.getInstallStep());
    const run_macro_step = b.step("macro-discover", "Run macro-action discovery experiment");
    run_macro_step.dependOn(&run_macro_cmd.step);

    // Quick dual-band 2D controller test.
    const dual_exe = b.addExecutable(.{
        .name = "ghost_dual_test",
        .root_source_file = b.path("dual_band_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(dual_exe);
    const run_dual_cmd = b.addRunArtifact(dual_exe);
    run_dual_cmd.step.dependOn(b.getInstallStep());
    const run_dual_step = b.step("dual-band-test", "Run 2D controller test on dual-band");
    run_dual_step.dependOn(&run_dual_cmd.step);

    // Swarm EXP-11 (C27): multi-objective band — safety vs delivered work Pareto.
    const mo_exe = b.addExecutable(.{
        .name = "ghost_multi_objective",
        .root_source_file = b.path("multi_objective.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(mo_exe);
    const run_mo_cmd = b.addRunArtifact(mo_exe);
    run_mo_cmd.step.dependOn(b.getInstallStep());
    const run_mo_step = b.step("multi-objective", "EXP-11 (C27): Pareto safety vs delivered work");
    run_mo_step.dependOn(&run_mo_cmd.step);

    // Swarm EXP-10 (I56): hard thermostat grid-tune vs mb_mass strawman check.
    const exp10_exe = b.addExecutable(.{
        .name = "ghost_swarm_exp10",
        .root_source_file = b.path("swarm_exp10_thermostat.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exp10_exe);
    const run_exp10_cmd = b.addRunArtifact(exp10_exe);
    run_exp10_cmd.step.dependOn(b.getInstallStep());
    const run_exp10_step = b.step("swarm-exp10", "EXP-10: hysteresis thermostat grid-tune vs mb_mass");
    run_exp10_step.dependOn(&run_exp10_cmd.step);

    // Swarm EXP-23 (F43): hidden non-salient feature sample-complexity curve.
    const exp23_exe = b.addExecutable(.{
        .name = "ghost_swarm_exp23",
        .root_source_file = b.path("swarm_exp23_sample_curve.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exp23_exe);
    const run_exp23_cmd = b.addRunArtifact(exp23_exe);
    run_exp23_cmd.step.dependOn(b.getInstallStep());
    const run_exp23_step = b.step("swarm-exp23", "EXP-23 (F43): failure-label sample-complexity curve");
    run_exp23_step.dependOn(&run_exp23_cmd.step);

    // Fork 2: hardness router → DUAL_BAND Q38 compound pair discovery.
    const hr_exe = b.addExecutable(.{
        .name = "ghost_hardness_router",
        .root_source_file = b.path("hardness_router_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(hr_exe);
    const run_hr_cmd = b.addRunArtifact(hr_exe);
    const run_hr_step = b.step("hardness-router-test", "Hardness router vs brute pair search on dual-band");
    run_hr_step.dependOn(&run_hr_cmd.step);

    // EXP-2: pair-selection hardness router → menu-growth cell pairs (28 pairs, guided vs brute).
    const phr_exe = b.addExecutable(.{
        .name = "ghost_pair_hardness_router",
        .root_source_file = b.path("pair_hardness_router_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(phr_exe);
    const run_phr_cmd = b.addRunArtifact(phr_exe);
    const run_phr_step = b.step("pair-hardness-router-test", "EXP-2: guided pair routing vs brute on hidden-pair + 5 deg2 targets");
    run_phr_step.dependOn(&run_phr_cmd.step);

    // EXP-6: learned candidate policy — perceptron guide vs baseline unified invention.
    const lg_mod = b.addModule("unified_invention", .{
        .root_source_file = b.path("unified_invention.zig"),
    });
    const lg_exe = b.addExecutable(.{
        .name = "ghost_learned_guide",
        .root_source_file = b.path("learned_guide_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    lg_exe.root_module.addImport("unified_invention", lg_mod);
    b.installArtifact(lg_exe);
    const run_lg_cmd = b.addRunArtifact(lg_exe);
    const run_lg_step = b.step("learned-guide-test", "EXP-6: learned candidate policy vs baseline on 7-target benchmark");
    run_lg_step.dependOn(&run_lg_cmd.step);

    // Adaptive feature discovery: self-directed model repair via disagreement detection.
    const adapt_exe = b.addExecutable(.{
        .name = "ghost_adaptive",
        .root_source_file = b.path("adaptive_feature.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(adapt_exe);
    const run_adapt_cmd = b.addRunArtifact(adapt_exe);
    run_adapt_cmd.step.dependOn(b.getInstallStep());
    const run_adapt_step = b.step("adaptive-feature", "Run adaptive feature discovery experiment");
    run_adapt_step.dependOn(&run_adapt_cmd.step);

    // #38/#53: emergent op-pair escape + closure-principle falsification.
    const syn_exe = b.addExecutable(.{
        .name = "ghost_synergy",
        .root_source_file = b.path("synergy.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(syn_exe);
    const run_syn_cmd = b.addRunArtifact(syn_exe);
    run_syn_cmd.step.dependOn(b.getInstallStep());
    const run_syn_step = b.step("synergy", "Run the emergent-escape / falsification experiment");
    run_syn_step.dependOn(&run_syn_cmd.step);

    // Correlation-based feature pair discovery: O(N) analysis vs O(N²) exhaustive.
    const corr_exe = b.addExecutable(.{
        .name = "ghost_correlation",
        .root_source_file = b.path("correlation_discover.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(corr_exe);
    const run_corr_cmd = b.addRunArtifact(corr_exe);
    run_corr_cmd.step.dependOn(b.getInstallStep());
    const run_corr_step = b.step("correlation-discover", "Run correlation-based feature pair discovery");
    run_corr_step.dependOn(&run_corr_cmd.step);

    // Triple-band: 3-constraint task, tests whether dual-band pair scales.
    const triple_exe = b.addExecutable(.{
        .name = "ghost_triple",
        .root_source_file = b.path("triple_band_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(triple_exe);
    const run_triple_cmd = b.addRunArtifact(triple_exe);
    run_triple_cmd.step.dependOn(b.getInstallStep());
    const run_triple_step = b.step("triple-band-test", "Run triple-band constraint test");
    run_triple_step.dependOn(&run_triple_cmd.step);

    // Prospective controller disagreement: forward-looking feature selection.
    const pdis_exe = b.addExecutable(.{
        .name = "ghost_parallel_disagree",
        .root_source_file = b.path("parallel_disagree.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(pdis_exe);
    const run_pdis_cmd = b.addRunArtifact(pdis_exe);
    run_pdis_cmd.step.dependOn(b.getInstallStep());
    const run_pdis_step = b.step("parallel-disagree", "Run prospective controller disagreement experiment");
    run_pdis_step.dependOn(&run_pdis_cmd.step);

    // Basis-degree control: change only the feature basis degree, measure the jump.
    const basis_exe = b.addExecutable(.{
        .name = "ghost_basis",
        .root_source_file = b.path("basis_control.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(basis_exe);
    const run_basis_cmd = b.addRunArtifact(basis_exe);
    run_basis_cmd.step.dependOn(b.getInstallStep());
    const run_basis_step = b.step("basis-control", "Run basis-degree control experiment (linear vs quadratic)");
    run_basis_step.dependOn(&run_basis_cmd.step);

    // Concentration control: does a MAX (order-statistic) constraint defeat the
    // quadratic (polynomial) basis? Tests the closure boundary H4.
    const conc_exe = b.addExecutable(.{
        .name = "ghost_concentration",
        .root_source_file = b.path("concentration_control.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(conc_exe);
    const run_conc_cmd = b.addRunArtifact(conc_exe);
    run_conc_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_conc_cmd.addArgs(args);
    const run_conc_step = b.step("concentration-control", "Run order-statistic vs polynomial closure experiment");
    run_conc_step.dependOn(&run_conc_cmd.step);

    // Order statistics: is the MEDIAN (a central/rank statistic) outside the closure of
    // {polynomial + max + min} (extremal statistics)? A new closure-lattice split.
    const os_exe = b.addExecutable(.{
        .name = "ghost_order_stats",
        .root_source_file = b.path("order_statistics.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(os_exe);
    const run_os_cmd = b.addRunArtifact(os_exe);
    run_os_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_os_cmd.addArgs(args);
    const run_os_step = b.step("order-stats", "Run median-vs-extremal closure experiment");
    run_os_step.dependOn(&run_os_cmd.step);

    // RQ A10: does changing the BINDING ALGEBRA change the readout closure? Compares
    // XOR-VSA vs a real Hadamard control vs Clifford geometric-product binding on
    // reading total mass (the SUM the XOR substrate provably cannot expose).
    const cliff_exe = b.addExecutable(.{
        .name = "ghost_clifford",
        .root_source_file = b.path("clifford_closure.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(cliff_exe);
    const run_cliff_cmd = b.addRunArtifact(cliff_exe);
    run_cliff_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cliff_cmd.addArgs(args);
    const run_cliff_step = b.step("clifford", "Run the binding-algebra closure experiment (XOR vs Hadamard vs Clifford)");
    run_cliff_step.dependOn(&run_cliff_cmd.step);

    // RQ C23: can GRADIENT discover the primitive parameter omega, or only grid search?
    const fam_exe = b.addExecutable(.{
        .name = "ghost_family_gradient",
        .root_source_file = b.path("family_gradient.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(fam_exe);
    const run_fam_cmd = b.addRunArtifact(fam_exe);
    run_fam_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_fam_cmd.addArgs(args);
    const run_fam_step = b.step("family-gradient", "Gradient vs grid search for the primitive parameter");
    run_fam_step.dependOn(&run_fam_cmd.step);

    // RQ I53: falsification hunt — is the XOR closure ceiling robust to a nonlinear readout?
    const fals_exe = b.addExecutable(.{
        .name = "ghost_falsify",
        .root_source_file = b.path("falsify_closure.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(fals_exe);
    const run_fals_cmd = b.addRunArtifact(fals_exe);
    run_fals_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_fals_cmd.addArgs(args);
    const run_fals_step = b.step("falsify", "Falsification hunt: attack the XOR closure ceiling with an MLP");
    run_fals_step.dependOn(&run_fals_cmd.step);

    // FRONTIER 1: does Clifford's geometric product give relational (pairwise) features a
    // plain real bind doesn't? (the test clifford_binding.md left open)
    const clrel_exe = b.addExecutable(.{
        .name = "ghost_clifford_relational",
        .root_source_file = b.path("clifford_relational.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(clrel_exe);
    const run_clrel_cmd = b.addRunArtifact(clrel_exe);
    run_clrel_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_clrel_cmd.addArgs(args);
    const run_clrel_step = b.step("clifford-relational", "Clifford vs real pairwise binding on a relational (XOR) predicate");
    run_clrel_step.dependOn(&run_clrel_cmd.step);

    // FRONTIER 2: a periodicity-aware (spectral) operator discovers omega where gradient fails.
    const spec_exe = b.addExecutable(.{
        .name = "ghost_spectral_discovery",
        .root_source_file = b.path("spectral_discovery.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(spec_exe);
    const run_spec_cmd = b.addRunArtifact(spec_exe);
    run_spec_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_spec_cmd.addArgs(args);
    const run_spec_step = b.step("spectral-discovery", "Periodicity-aware discovery of the primitive parameter omega");
    run_spec_step.dependOn(&run_spec_cmd.step);

    // FRONTIER 3: Clifford's bivector earns its keep on an antisymmetric / oriented predicate.
    const anti_exe = b.addExecutable(.{
        .name = "ghost_antisymmetric_relational",
        .root_source_file = b.path("antisymmetric_relational.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(anti_exe);
    const run_anti_cmd = b.addRunArtifact(anti_exe);
    run_anti_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_anti_cmd.addArgs(args);
    const run_anti_step = b.step("antisymmetric-relational", "Clifford grade-2 vs real pairwise on oriented predicate");
    run_anti_step.dependOn(&run_anti_cmd.step);

    // Direction 3: oriented Clifford readout vs mb_mass sum on real grid control.
    const oriented_exe = b.addExecutable(.{
        .name = "ghost_oriented_control",
        .root_source_file = b.path("oriented_control.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(oriented_exe);
    const run_oriented_cmd = b.addRunArtifact(oriented_exe);
    run_oriented_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_oriented_cmd.addArgs(args);
    const run_oriented_step = b.step("oriented-control", "Grade-2 bivector readout vs mb_mass sum on grid control");
    run_oriented_step.dependOn(&run_oriented_cmd.step);

    const relbat_exe = b.addExecutable(.{
        .name = "ghost_relational_binding_battery",
        .root_source_file = b.path("relational_binding_battery.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(relbat_exe);
    const run_relbat_cmd = b.addRunArtifact(relbat_exe);
    run_relbat_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_relbat_cmd.addArgs(args);
    const run_relbat_step = b.step("relational-binding-battery", "EXP-3: blind substrate selector on relational predicates");
    run_relbat_step.dependOn(&run_relbat_cmd.step);

    // FRONTIER 4: k-parity interaction-order ladder — ceiling at each degree d < k.
    const hoc_exe = b.addExecutable(.{
        .name = "ghost_higher_order_closure",
        .root_source_file = b.path("higher_order_closure.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(hoc_exe);
    const run_hoc_cmd = b.addRunArtifact(hoc_exe);
    run_hoc_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_hoc_cmd.addArgs(args);
    const run_hoc_step = b.step("higher-order-closure", "k-parity requires k-th order monomials");
    run_hoc_step.dependOn(&run_hoc_cmd.step);

    // FRONTIER 5: composed discovery — two staged operators for composed primitive families.
    const comp_exe = b.addExecutable(.{
        .name = "ghost_composed_discovery",
        .root_source_file = b.path("composed_discovery.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(comp_exe);
    const run_comp_cmd = b.addRunArtifact(comp_exe);
    run_comp_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_comp_cmd.addArgs(args);
    const run_comp_step = b.step("composed-discovery", "Composed primitives: neither operator alone suffices");
    run_comp_step.dependOn(&run_comp_cmd.step);

    // FRONTIER 6: composition auto-detection via power-accuracy mismatch probe.
    const opi_exe = b.addExecutable(.{
        .name = "ghost_operator_inference",
        .root_source_file = b.path("operator_inference.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(opi_exe);
    const run_opi_cmd = b.addRunArtifact(opi_exe);
    run_opi_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_opi_cmd.addArgs(args);
    const run_opi_step = b.step("operator-inference", "Structural probes identify composed vs simple families");
    run_opi_step.dependOn(&run_opi_cmd.step);

    // FRONTIER 7: multi-period discovery — what does spectral do with two simultaneous periods?
    const mp_exe = b.addExecutable(.{
        .name = "ghost_multi_period",
        .root_source_file = b.path("multi_period.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(mp_exe);
    const run_mp_cmd = b.addRunArtifact(mp_exe);
    run_mp_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_mp_cmd.addArgs(args);
    const run_mp_step = b.step("multi-period", "Multi-period spectral discovery");
    run_mp_step.dependOn(&run_mp_cmd.step);

    // FRONTIER 8: sparse parity sample complexity wall.
    const sp_exe = b.addExecutable(.{
        .name = "ghost_sparse_parity",
        .root_source_file = b.path("sparse_parity.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(sp_exe);
    const run_sp_cmd = b.addRunArtifact(sp_exe);
    run_sp_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_sp_cmd.addArgs(args);
    const run_sp_step = b.step("sparse-parity", "Sample complexity wall for k-of-n sparse parity");
    run_sp_step.dependOn(&run_sp_cmd.step);

    // FRONTIER 9: period-candidate search — accuracy-grid and iterative-residual vs power-spectrum.
    const pcs_exe = b.addExecutable(.{
        .name = "ghost_period_candidate_search",
        .root_source_file = b.path("period_candidate_search.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(pcs_exe);
    const run_pcs_cmd = b.addRunArtifact(pcs_exe);
    run_pcs_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_pcs_cmd.addArgs(args);
    const run_pcs_step = b.step("period-candidate-search", "Fix for AND-composition failure: accuracy grid vs power spectrum");
    run_pcs_step.dependOn(&run_pcs_cmd.step);

    // FRONTIER 10: predicate tomography — accuracy profiles across all substrates.
    const pt_exe = b.addExecutable(.{
        .name = "ghost_predicate_tomography",
        .root_source_file = b.path("predicate_tomography.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(pt_exe);
    const run_pt_cmd = b.addRunArtifact(pt_exe);
    run_pt_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_pt_cmd.addArgs(args);
    const run_pt_step = b.step("predicate-tomography", "Fingerprint 12 predicates across 9 substrates");
    run_pt_step.dependOn(&run_pt_cmd.step);

    // FRONTIER 11: symmetry groups predict substrate requirements.
    const sym_exe = b.addExecutable(.{
        .name = "ghost_symmetry_discovery",
        .root_source_file = b.path("symmetry_discovery.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(sym_exe);
    const run_sym_cmd = b.addRunArtifact(sym_exe);
    run_sym_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_sym_cmd.addArgs(args);
    const run_sym_step = b.step("symmetry-discovery", "Symmetry groups predict substrate requirements");
    run_sym_step.dependOn(&run_sym_cmd.step);

    // FRONTIER 12: gradient discovery — failure gradient points toward needed substrate.
    const gd_exe = b.addExecutable(.{
        .name = "ghost_gradient_discovery",
        .root_source_file = b.path("gradient_discovery.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gd_exe);
    const run_gd_cmd = b.addRunArtifact(gd_exe);
    run_gd_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_gd_cmd.addArgs(args);
    const run_gd_step = b.step("gradient-discovery", "Failure gradient identifies needed substrate extension");
    run_gd_step.dependOn(&run_gd_cmd.step);

    // FRONTIER 13: basis comparison — cosine vs step vs square-wave vs dual.
    const bc_exe = b.addExecutable(.{
        .name = "ghost_basis_comparison",
        .root_source_file = b.path("basis_comparison.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(bc_exe);
    const run_bc_cmd = b.addRunArtifact(bc_exe);
    run_bc_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_bc_cmd.addArgs(args);
    const run_bc_step = b.step("basis-comparison", "Compare cosine vs step vs dual basis functions");
    run_bc_step.dependOn(&run_bc_cmd.step);

    // FRONTIER 14: discovery loop — does gradient discovery converge?
    const dl_exe = b.addExecutable(.{
        .name = "ghost_discovery_loop",
        .root_source_file = b.path("discovery_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(dl_exe);
    const run_dl_cmd = b.addRunArtifact(dl_exe);
    run_dl_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_dl_cmd.addArgs(args);
    const run_dl_step = b.step("discovery-loop", "Convergence test for gradient discovery algorithm");
    run_dl_step.dependOn(&run_dl_cmd.step);

    // FRONTIER 22: Newton's method (IRLS) — quadratic convergence on k5-parity.
    const nw_exe = b.addExecutable(.{
        .name = "ghost_newton_solver",
        .root_source_file = b.path("newton_solver.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(nw_exe);
    const run_nw_cmd = b.addRunArtifact(nw_exe);
    run_nw_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_nw_cmd.addArgs(args);
    const run_nw_step = b.step("newton-solver", "Newton IRLS vs adaptive GD on the full k-parity ladder");
    run_nw_step.dependOn(&run_nw_cmd.step);

    // FRONTIER 21: sub-monomial force-add — enumerate all sub-monomials of discovered leading term.
    const sm_exe = b.addExecutable(.{
        .name = "ghost_submonomial_solver",
        .root_source_file = b.path("submonomial_solver.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(sm_exe);
    const run_sm_cmd = b.addRunArtifact(sm_exe);
    run_sm_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_sm_cmd.addArgs(args);
    const run_sm_step = b.step("submonomial-solver", "Force-add all sub-monomials of discovered degree-k leading term");
    run_sm_step.dependOn(&run_sm_cmd.step);

    // FRONTIER 20: online position refinement — narrow pool dynamically as features are found.
    const og_exe = b.addExecutable(.{
        .name = "ghost_online_guided",
        .root_source_file = b.path("online_guided.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(og_exe);
    const run_og_cmd = b.addRunArtifact(og_exe);
    run_og_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_og_cmd.addArgs(args);
    const run_og_step = b.step("online-guided", "Online: narrow candidate pool to discovered positions after each step");
    run_og_step.dependOn(&run_og_cmd.step);

    // FRONTIER 19: guided pool extension — pass-1 finds positions, pass-2 uses filtered pool.
    const gp_exe = b.addExecutable(.{
        .name = "ghost_guided_pool",
        .root_source_file = b.path("guided_pool.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gp_exe);
    const run_gp_cmd = b.addRunArtifact(gp_exe);
    run_gp_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_gp_cmd.addArgs(args);
    const run_gp_step = b.step("guided-pool", "Guided pool: positions from pass-1 filter the degree-5 candidates");
    run_gp_step.dependOn(&run_gp_cmd.step);

    // FRONTIER 18: extended pool — degree-4 and degree-5 monomials for k4-parity and k2∧k3.
    const ep_exe = b.addExecutable(.{
        .name = "ghost_extended_pool",
        .root_source_file = b.path("extended_pool.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(ep_exe);
    const run_ep_cmd = b.addRunArtifact(ep_exe);
    run_ep_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_ep_cmd.addArgs(args);
    const run_ep_step = b.step("extended-pool", "Extend pool to degree-5; test k4/k5-parity and k2∧k3");
    run_ep_step.dependOn(&run_ep_cmd.step);

    // FRONTIER 17: adaptive retrain — LR halving closes the k3-parity optimizer gap.
    const ar_exe = b.addExecutable(.{
        .name = "ghost_adaptive_retrain",
        .root_source_file = b.path("adaptive_retrain.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(ar_exe);
    const run_ar_cmd = b.addRunArtifact(ar_exe);
    run_ar_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_ar_cmd.addArgs(args);
    const run_ar_step = b.step("adaptive-retrain", "Adaptive LR halving to close the k3-parity 0.877 ceiling");
    run_ar_step.dependOn(&run_ar_cmd.step);

    // FRONTIER 16: dual stopping criterion — gap AND magnitude (conjunction).
    const ds_exe = b.addExecutable(.{
        .name = "ghost_dual_stop_discovery",
        .root_source_file = b.path("dual_stop_discovery.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(ds_exe);
    const run_ds_cmd = b.addRunArtifact(ds_exe);
    run_ds_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_ds_cmd.addArgs(args);
    const run_ds_step = b.step("dual-stop-discovery", "Dual stopping: gap AND magnitude conjunction fixes k3-parity");
    run_ds_step.dependOn(&run_ds_cmd.step);

    // FRONTIER 15: two-phase gradient discovery — discover then solve cleanly.
    const tp_exe = b.addExecutable(.{
        .name = "ghost_two_phase_discovery",
        .root_source_file = b.path("two_phase_discovery.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tp_exe);
    const run_tp_cmd = b.addRunArtifact(tp_exe);
    run_tp_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_tp_cmd.addArgs(args);
    const run_tp_step = b.step("two-phase-discovery", "Two-phase: gap-stopped discovery then clean retrain");
    run_tp_step.dependOn(&run_tp_cmd.step);

    // FRONTIER 23: bit-state mechanism — XOR accumulator + bit-indexed recall as the third corner.
    const bs_exe = b.addExecutable(.{
        .name = "ghost_bit_state",
        .root_source_file = b.path("bit_state_mechanism.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(bs_exe);
    const run_bs_cmd = b.addRunArtifact(bs_exe);
    run_bs_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_bs_cmd.addArgs(args);
    const run_bs_step = b.step("bit-state", "Bit-state mechanism: XOR parity + bit-indexed recall as the third corner");
    run_bs_step.dependOn(&run_bs_cmd.step);

    // FRONTIER 24: autonomous structure discovery — argmax over (inner-transform ⊗ outer-operator);
    // assembles the scattered discovery pieces into one blind selector + tests the menu's own closure.
    const sd_exe = b.addExecutable(.{
        .name = "ghost_structure_discovery",
        .root_source_file = b.path("structure_discovery.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(sd_exe);
    const run_sd_cmd = b.addRunArtifact(sd_exe);
    run_sd_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_sd_cmd.addArgs(args);
    const run_sd_step = b.step("structure-discovery", "Autonomous (inner ⊗ outer) structure discovery + the menu-is-a-closure ceiling");
    run_sd_step.dependOn(&run_sd_cmd.step);

    // #3 Phase B: certified menu-growth — discover the pair, certify irreducible, break the F24 ceiling.
    const mg_exe = b.addExecutable(.{
        .name = "ghost_menu_growth",
        .root_source_file = b.path("menu_growth.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(mg_exe);
    const run_mg_cmd = b.addRunArtifact(mg_exe);
    run_mg_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_mg_cmd.addArgs(args);
    const run_mg_step = b.step("menu-growth", "Phase B: certified menu-growth that breaks the Frontier-24 hidden-pair ceiling");
    run_mg_step.dependOn(&run_mg_cmd.step);

    // #3 Phase C: the open inner-transform forge — does certified promotion saturate or grow?
    const if_exe = b.addExecutable(.{
        .name = "ghost_inner_forge",
        .root_source_file = b.path("inner_forge.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(if_exe);
    const run_if_cmd = b.addRunArtifact(if_exe);
    run_if_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_if_cmd.addArgs(args);
    const run_if_step = b.step("inner-forge", "Phase C: open inner-transform forge — saturation vs growth + algebraic-irreducibility objective");
    run_if_step.dependOn(&run_if_cmd.step);

    // E10: novelty-only forge vs usefulness — wcore novelty↔usefulness tension.
    const e10_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e10",
        .root_source_file = b.path("open_invention_e10.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e10_exe);
    const run_e10_cmd = b.addRunArtifact(e10_exe);
    if (b.args) |args| run_e10_cmd.addArgs(args);
    const run_e10_step = b.step("open-invention-e10", "E10: novelty-only forge vs random-target usefulness battery (wcore tension)");
    run_e10_step.dependOn(&run_e10_cmd.step);

    // E25: novelty-usefulness Pareto — sweep R²×escape on E10 substrate.
    const e25_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e25",
        .root_source_file = b.path("open_invention_e25.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e25_exe);
    const run_e25_cmd = b.addRunArtifact(e25_exe);
    if (b.args) |args| run_e25_cmd.addArgs(args);
    const run_e25_step = b.step("open-invention-e25", "E25: novelty-usefulness Pareto (E10++) — R²×escape sweep, useful/random≥5×");
    run_e25_step.dependOn(&run_e25_cmd.step);

    // Direction 1: unified operator menu — spectral vs Walsh vs Clifford grade-2.
    const om_exe = b.addExecutable(.{
        .name = "ghost_operator_menu",
        .root_source_file = b.path("operator_menu.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(om_exe);
    const run_om_cmd = b.addRunArtifact(om_exe);
    run_om_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_om_cmd.addArgs(args);
    const run_om_step = b.step("operator-menu", "Direction 1: unified operator menu — spectral vs Walsh vs Clifford");
    run_om_step.dependOn(&run_om_cmd.step);

    // Fork 5: unified invention loop — forge → menu → world pool.
    const ui_exe = b.addExecutable(.{
        .name = "ghost_unified_invention",
        .root_source_file = b.path("unified_invention.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(ui_exe);
    const run_ui_cmd = b.addRunArtifact(ui_exe);
    run_ui_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_ui_cmd.addArgs(args);
    const run_ui_step = b.step("unified-invention", "Fork 5: monomial forge → operator menu → world pool (mod_p)");
    run_ui_step.dependOn(&run_ui_cmd.step);

    // EXPERIMENT E1: frozen-forge blind zoo — train on T1–T4, freeze, evaluate battery B.
    const oie1_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e1",
        .root_source_file = b.path("open_invention_e1.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(oie1_exe);
    const run_oie1_cmd = b.addRunArtifact(oie1_exe);
    if (b.args) |args| run_oie1_cmd.addArgs(args);
    const run_oie1_step = b.step("open-invention-e1", "E1: frozen monomial forge → blind battery B (open invention)");
    run_oie1_step.dependOn(&run_oie1_cmd.step);

    // EXPERIMENT E2: POET-lite adversarial target generator — forge vs evaluation-only oracle.
    const oie2_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e2",
        .root_source_file = b.path("open_invention_e2.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(oie2_exe);
    const run_oie2_cmd = b.addRunArtifact(oie2_exe);
    run_oie2_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_oie2_cmd.addArgs(args);
    const run_oie2_step = b.step("open-invention-e2", "E2: POET-lite adversarial targets — forge vs evaluation-only oracle");
    run_oie2_step.dependOn(&run_oie2_cmd.step);

    // RQ2: E2 XOR gap closure — inject minimal xor_popcount(mask) readout.
    const rq2_exe = b.addExecutable(.{
        .name = "ghost_open_invention_rq2",
        .root_source_file = b.path("open_invention_rq2.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_rq2_cmd = b.addRunArtifact(rq2_exe);
    if (b.args) |args| run_rq2_cmd.addArgs(args);
    const run_rq2_step = b.step("open-invention-rq2", "RQ2: E2 XOR gap closure — xor_popcount(mask) readout vs oracle-only targets");
    run_rq2_step.dependOn(&run_rq2_cmd.step);

    // Math frontier 1: Boolean Fourier (Walsh–Hadamard) — the universal discovery operator.
    const bf_exe = b.addExecutable(.{
        .name = "ghost_boolean_fourier",
        .root_source_file = b.path("boolean_fourier.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(bf_exe);
    const run_bf_cmd = b.addRunArtifact(bf_exe);
    run_bf_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_bf_cmd.addArgs(args);
    const run_bf_step = b.step("boolean-fourier", "Math frontier 1: Walsh–Hadamard transform recovers every predicate's structure in one pass");
    run_bf_step.dependOn(&run_bf_cmd.step);

    // Math frontier 2: Post's lattice — the complete classification of Boolean closures.
    const cl_exe = b.addExecutable(.{
        .name = "ghost_clone_lattice",
        .root_source_file = b.path("clone_lattice.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(cl_exe);
    const run_cl_cmd = b.addRunArtifact(cl_exe);
    run_cl_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cl_cmd.addArgs(args);
    const run_cl_step = b.step("clone-lattice", "Math frontier 2: Post's lattice places every closure ceiling at exact coordinates");
    run_cl_step.dependOn(&run_cl_cmd.step);

    // Math frontier 3: the k≥3 cliff — where the classification of closures ceases to exist.
    const kf_exe = b.addExecutable(.{
        .name = "ghost_kary_frontier",
        .root_source_file = b.path("kary_frontier.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(kf_exe);
    const run_kf_cmd = b.addRunArtifact(kf_exe);
    run_kf_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_kf_cmd.addArgs(args);
    const run_kf_step = b.step("kary-frontier", "Math frontier 3: k=2 is fully mapped; k≥3 has uncountably many clones (no map)");
    run_kf_step.dependOn(&run_kf_cmd.step);

    // Direction 4: minimal k=3 substrate — does promotion saturation change outside Boolean k=2?
    const k3_exe = b.addExecutable(.{
        .name = "ghost_k3_substrate",
        .root_source_file = b.path("k3_substrate.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(k3_exe);
    const run_k3_cmd = b.addRunArtifact(k3_exe);
    run_k3_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_k3_cmd.addArgs(args);
    const run_k3_step = b.step("k3-substrate", "Direction 4: k=3 substrate forge — saturation vs inner-forge baseline");
    run_k3_step.dependOn(&run_k3_cmd.step);

    // E7: corpus-invented rune primitives vs frozen symbolic menu.
    const oi7_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e7",
        .root_source_file = b.path("open_invention_e7.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(oi7_exe);
    const run_oi7_cmd = b.addRunArtifact(oi7_exe);
    run_oi7_cmd.step.dependOn(&oi7_exe.step);
    if (b.args) |args| run_oi7_cmd.addArgs(args);
    const run_oi7_step = b.step("open-invention-e7", "E7: corpus-invented rune primitives vs frozen symbolic menu");
    run_oi7_step.dependOn(&run_oi7_cmd.step);

    // E22: corpus runes v2 — terminal execution traces → rune forge → Boolean/zoo.
    const oi22_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e22",
        .root_source_file = b.path("open_invention_e22.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(oi22_exe);
    const run_oi22_cmd = b.addRunArtifact(oi22_exe);
    run_oi22_cmd.step.dependOn(&oi22_exe.step);
    if (b.args) |args| run_oi22_cmd.addArgs(args);
    const run_oi22_step = b.step("open-invention-e22", "E22: terminal trace runes vs frozen menu on T5/T7 zoo");
    run_oi22_step.dependOn(&run_oi22_cmd.step);

    // Fork 6: k≥3 + order-statistic escape — T6 median wall with rank indicators.
    const k3oe_exe = b.addExecutable(.{
        .name = "ghost_k3_order_escape",
        .root_source_file = b.path("k3_order_escape.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(k3oe_exe);
    const run_k3oe_cmd = b.addRunArtifact(k3oe_exe);
    run_k3oe_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_k3oe_cmd.addArgs(args);
    const run_k3oe_step = b.step("k3-order-escape", "Fork 6: k≥3 + order-statistic escape on T6 median wall");
    run_k3oe_step.dependOn(&run_k3oe_cmd.step);

    // E3: no spectral/Walsh ablation — open invention test (parity + random Boolean).
    const e3_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e3",
        .root_source_file = b.path("open_invention_e3.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_e3_cmd = b.addRunArtifact(e3_exe);
    if (b.args) |args| run_e3_cmd.addArgs(args);
    const run_e3_step = b.step("open-invention-e3", "E3: no spectral/Walsh ablation — parity + 10 random Boolean targets");
    run_e3_step.dependOn(&run_e3_cmd.step);

    // RQ3: E3 extended — 20 non-parity periodic/composed targets, synthesis only.
    const rq3_exe = b.addExecutable(.{
        .name = "ghost_open_invention_rq3",
        .root_source_file = b.path("open_invention_rq3.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_rq3_cmd = b.addRunArtifact(rq3_exe);
    if (b.args) |args| run_rq3_cmd.addArgs(args);
    const run_rq3_step = b.step("open-invention-rq3", "RQ3: E3 extended — 20 non-parity periodic/composed targets (synthesis only)");
    run_rq3_step.dependOn(&run_rq3_cmd.step);

    // E16: mod synthesis beyond parity (E3++) — mod(sum,3), mod(popcount,4), composed mod(f,k).
    const e16_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e16",
        .root_source_file = b.path("open_invention_e16.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_e16_cmd = b.addRunArtifact(e16_exe);
    if (b.args) |args| run_e16_cmd.addArgs(args);
    const run_e16_step = b.step("open-invention-e16", "E16: mod synthesis beyond parity — 20 mod targets, synthesis only, 0 Walsh");
    run_e16_step.dependOn(&run_e16_cmd.step);

    // E6: k≥3 substrate open forge — random alien targets, no Boolean Fourier menu.
    const e6_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e6",
        .root_source_file = b.path("open_invention_e6.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e6_exe);
    const run_e6_cmd = b.addRunArtifact(e6_exe);
    run_e6_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_e6_cmd.addArgs(args);
    const run_e6_step = b.step("open-invention-e6", "E6: k≥3 open forge — random alien targets (k=3,4), no Fourier menu");
    run_e6_step.dependOn(&run_e6_cmd.step);

    // E24: k3_order_escape full substrate on E6 alien distribution — no Walsh.
    const e24_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e24",
        .root_source_file = b.path("open_invention_e24.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e24_exe);
    const run_e24_cmd = b.addRunArtifact(e24_exe);
    run_e24_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_e24_cmd.addArgs(args);
    const run_e24_step = b.step("open-invention-e24", "E24: k3_order_escape on E6 aliens — ≥4/16 certified promotions, no Walsh");
    run_e24_step.dependOn(&run_e24_cmd.step);

    // Math frontier 4: tropical & the family map — incomparable algebraic closures.
    const fc_exe = b.addExecutable(.{
        .name = "ghost_family_closures",
        .root_source_file = b.path("family_closures.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(fc_exe);
    const run_fc_cmd = b.addRunArtifact(fc_exe);
    run_fc_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_fc_cmd.addArgs(args);
    const run_fc_step = b.step("family-closures", "Math frontier 4: tropical/affine/GF(2)/monomial are incomparable closures (diagonal matrix)");
    run_fc_step.dependOn(&run_fc_cmd.step);

    // EXPERIMENT E5: meta-menu of composed pipelines — blind inner₁→inner₂ discovery.
    const e5_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e5",
        .root_source_file = b.path("open_invention_e5.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e5_exe);
    const run_e5_cmd = b.addRunArtifact(e5_exe);
    if (b.args) |args| run_e5_cmd.addArgs(args);
    const run_e5_step = b.step("open-invention-e5", "E5: meta-menu discovers composed pipelines without product/spectral hints");
    run_e5_step.dependOn(&run_e5_cmd.step);

    // RQ5: E5 pipeline transfer — freeze grammar after A+B, test 30 held-out composed targets.
    const rq5_exe = b.addExecutable(.{
        .name = "ghost_open_invention_rq5",
        .root_source_file = b.path("open_invention_rq5.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(rq5_exe);
    const run_rq5_cmd = b.addRunArtifact(rq5_exe);
    if (b.args) |args| run_rq5_cmd.addArgs(args);
    const run_rq5_step = b.step("open-invention-rq5", "RQ5: E5 pipeline transfer — freeze grammar, 30 held-out composed targets");
    run_rq5_step.dependOn(&run_rq5_cmd.step);

    // E17: pipeline grammar invention (E5++) — meta-search 2-3 stage grammars, 50 composed targets.
    const e17_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e17",
        .root_source_file = b.path("open_invention_e17.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e17_exe);
    const run_e17_cmd = b.addRunArtifact(e17_exe);
    if (b.args) |args| run_e17_cmd.addArgs(args);
    const run_e17_step = b.step("open-invention-e17", "E17: meta-search 2-3 stage pipeline grammars, certify 50 composed targets");
    run_e17_step.dependOn(&run_e17_cmd.step);

    // E11: LLM as proposer, engine as sole judge — JSON feature proposals on grid targets.
    const e11_exe = b.addExecutable(.{
        .name = "open_invention_e11",
        .root_source_file = b.path("open_invention_e11.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_e11_cmd = b.addRunArtifact(e11_exe);
    run_e11_cmd.setCwd(b.path("."));
    if (b.args) |args| run_e11_cmd.addArgs(args);
    const run_e11_step = b.step("open-invention-e11", "E11: LLM proposer JSON features, engine certifies held-out ≥0.90 on grid targets");
    run_e11_step.dependOn(&run_e11_cmd.step);

    // RQ7: E11 scale — 100 LLM proposals, 5 target families, world novelty gate.
    const rq7_exe = b.addExecutable(.{
        .name = "open_invention_rq7",
        .root_source_file = b.path("open_invention_rq7.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_rq7_cmd = b.addRunArtifact(rq7_exe);
    run_rq7_cmd.setCwd(b.path("."));
    if (b.args) |args| run_rq7_cmd.addArgs(args);
    const run_rq7_step = b.step("open-invention-rq7", "RQ7: 100 LLM proposals, engine certifies ≥0.90 on 5 families (parity/hidden_pair/sum_mod/oriented/monomial_sign)");
    run_rq7_step.dependOn(&run_rq7_cmd.step);

    // E12: POET propose-solve-verify self-play — typed TargetSpec curriculum.
    const e12_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e12",
        .root_source_file = b.path("open_invention_e12.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e12_exe);
    const run_e12_cmd = b.addRunArtifact(e12_exe);
    if (b.args) |args| run_e12_cmd.addArgs(args);
    const run_e12_step = b.step("open-invention-e12", "E12: POET propose-solve-verify self-play (TargetSpec curriculum)");
    run_e12_step.dependOn(&run_e12_cmd.step);

    // EXPERIMENT E14: hardness-routed open invention — Q38 router picks xor vs synth vs pipeline.
    const e14_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e14",
        .root_source_file = b.path("open_invention_e14.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e14_exe);
    const run_e14_cmd = b.addRunArtifact(e14_exe);
    if (b.args) |args| run_e14_cmd.addArgs(args);
    const run_e14_step = b.step("open-invention-e14", "E14: hardness-routed open invention — Q38 picks xor_popcount vs mod synthesis vs pipeline");
    run_e14_step.dependOn(&run_e14_cmd.step);

    // RQ8: E12 hard mutators — noisy labels, Walsh deg 3–5, 2-feature composition.
    const rq8_exe = b.addExecutable(.{
        .name = "ghost_open_invention_rq8",
        .root_source_file = b.path("open_invention_rq8.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(rq8_exe);
    const run_rq8_cmd = b.addRunArtifact(rq8_exe);
    if (b.args) |args| run_rq8_cmd.addArgs(args);
    const run_rq8_step = b.step("open-invention-rq8", "RQ8: E12 hard mutators — noisy labels, Walsh deg 3–5, composed AND");
    run_rq8_step.dependOn(&run_rq8_cmd.step);

    // E20: POET curriculum stress test — 200 rounds, E12/RQ8 hardened pass bar.
    const e20_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e20",
        .root_source_file = b.path("open_invention_e20.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e20_exe);
    const run_e20_cmd = b.addRunArtifact(e20_exe);
    if (b.args) |args| run_e20_cmd.addArgs(args);
    const run_e20_step = b.step("open-invention-e20", "E20: POET curriculum stress test — 200 rounds, curriculum≥20 for 50 consecutive");
    run_e20_step.dependOn(&run_e20_cmd.step);

    // E27: certified stack vs transformer on verifiable tasks (parity/compress/chain/terminal).
    const e27_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e27",
        .root_source_file = b.path("open_invention_e27.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e27_exe);
    const run_e27_cmd = b.addRunArtifact(e27_exe);
    if (b.args) |args| run_e27_cmd.addArgs(args);
    const run_e27_step = b.step("open-invention-e27", "E27: certified stack vs transformer — 100 verifiable tasks, 50 holdout");
    run_e27_step.dependOn(&run_e27_cmd.step);

    // E28: DeepSeek expert route invention — hardness router + unified loop on captured L30 activations.
    const e28_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e28",
        .root_source_file = b.path("open_invention_e28.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e28_exe);
    const run_e28_cmd = b.addRunArtifact(e28_exe);
    if (b.args) |args| run_e28_cmd.addArgs(args);
    const run_e28_step = b.step("open-invention-e28", "E28: DeepSeek expert route invention — gate scores from acts+gate_L30, held-out e11 positions");
    run_e28_step.dependOn(&run_e28_cmd.step);

    // E19: wake-sleep LLM proposer — 500 proposals, library-conditioned, RQ9 novelty gate.
    const e19_exe = b.addExecutable(.{
        .name = "open_invention_e19",
        .root_source_file = b.path("open_invention_e19.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_e19_cmd = b.addRunArtifact(e19_exe);
    run_e19_cmd.setCwd(b.path("."));
    if (b.args) |args| run_e19_cmd.addArgs(args);
    const run_e19_step = b.step("open-invention-e19", "E19: wake-sleep LLM proposer — 500 proposals, library growth, RQ9 novelty");
    run_e19_step.dependOn(&run_e19_cmd.step);

    // RQ9: cross-cutting equivalence tax — can rich basis reproduce certified escapes?
    const rq9_exe = b.addExecutable(.{
        .name = "open_invention_rq9",
        .root_source_file = b.path("open_invention_rq9.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(rq9_exe);
    const run_rq9_cmd = b.addRunArtifact(rq9_exe);
    if (b.args) |args| run_rq9_cmd.addArgs(args);
    const run_rq9_step = b.step("open-invention-rq9", "RQ9: equivalence tax — monomial+Walsh+world+VM basis vs E3/E4/E5/E11 escapes");
    run_rq9_step.dependOn(&run_rq9_cmd.step);

    // E26: equivalence tax v2 (RQ9++) — expanded basis + all E1–E12 grid escapes.
    const e26_exe = b.addExecutable(.{
        .name = "open_invention_e26",
        .root_source_file = b.path("open_invention_e26.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e26_exe);
    const run_e26_cmd = b.addRunArtifact(e26_exe);
    if (b.args) |args| run_e26_cmd.addArgs(args);
    const run_e26_step = b.step("open-invention-e26", "E26: equivalence tax v2 — +mod synth+xor_popcount+pipelines vs E1–E12 escapes");
    run_e26_step.dependOn(&run_e26_cmd.step);

    // RQ10: certifier soundness — false-promote rate on random-label targets.
    const rq10_exe = b.addExecutable(.{
        .name = "open_invention_rq10",
        .root_source_file = b.path("open_invention_rq10.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(rq10_exe);
    const run_rq10_cmd = b.addRunArtifact(rq10_exe);
    if (b.args) |args| run_rq10_cmd.addArgs(args);
    const run_rq10_step = b.step("open-invention-rq10", "RQ10: certifier soundness on random/shuffled labels");
    run_rq10_step.dependOn(&run_rq10_cmd.step);

    // E4: certified menu minting — program synthesizer mints grid→scalar transforms.
    const e4_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e4",
        .root_source_file = b.path("open_invention_e4.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e4_exe);
    const run_e4_cmd = b.addRunArtifact(e4_exe);
    if (b.args) |args| run_e4_cmd.addArgs(args);
    const run_e4_step = b.step("open-invention-e4", "E4: certified menu minting — synthesizer mints grid→scalar programs");
    run_e4_step.dependOn(&run_e4_cmd.step);

    // FORK E4-G00: hard-mint generalization across seeds + downstream library lift.
    const fork_e4_g00_exe = b.addExecutable(.{
        .name = "swarm_fork_e4_g00",
        .root_source_file = b.path("swarm_fork_e4_g00.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(fork_e4_g00_exe);
    const run_fork_e4_g00_cmd = b.addRunArtifact(fork_e4_g00_exe);
    if (b.args) |args| run_fork_e4_g00_cmd.addArgs(args);
    const run_fork_e4_g00_step = b.step("swarm-fork-e4-g00", "FORK E4-G00: hard-mint generalization + downstream promotion test");
    run_fork_e4_g00_step.dependOn(&run_fork_e4_g00_cmd.step);

    // RQ4: E4 equivalence oracle — are minted programs distinct from VM depth≤6?
    const rq4_exe = b.addExecutable(.{
        .name = "ghost_open_invention_rq4",
        .root_source_file = b.path("open_invention_rq4.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(rq4_exe);
    const run_rq4_cmd = b.addRunArtifact(rq4_exe);
    if (b.args) |args| run_rq4_cmd.addArgs(args);
    const run_rq4_step = b.step("open-invention-rq4", "RQ4: E4 equivalence oracle — minted programs vs VM depth≤6 on 10k grids");
    run_rq4_step.dependOn(&run_rq4_cmd.step);

    // E21: E4 escape VM post-RQ4 — expand generators (mod/xor/pipeline), depth≤8 oracle.
    const e21_exe = b.addExecutable(.{
        .name = "ghost_open_invention_e21",
        .root_source_file = b.path("open_invention_e21.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(e21_exe);
    const run_e21_cmd = b.addRunArtifact(e21_exe);
    if (b.args) |args| run_e21_cmd.addArgs(args);
    const run_e21_step = b.step("open-invention-e21", "E21: E4 escape VM post-RQ4 — mod/xor/pipeline minting vs depth≤8 oracle");
    run_e21_step.dependOn(&run_e21_cmd.step);

    // RQ1: E1 blind battery without handed menu (E3 synthesis + E5 pipelines only).
    const rq1_exe = b.addExecutable(.{
        .name = "ghost_open_invention_rq1",
        .root_source_file = b.path("open_invention_rq1.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(rq1_exe);
    const run_rq1_cmd = b.addRunArtifact(rq1_exe);
    if (b.args) |args| run_rq1_cmd.addArgs(args);
    const run_rq1_step = b.step("open-invention-rq1", "RQ1++: blind battery staged escalation (mono→mod→pair→Walsh q38)");
    run_rq1_step.dependOn(&run_rq1_cmd.step);

    const baseline_cmp_exe = b.addExecutable(.{
        .name = "invention_baseline_compare",
        .root_source_file = b.path("invention_baseline_compare.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(baseline_cmp_exe);
    const run_baseline_cmp_cmd = b.addRunArtifact(baseline_cmp_exe);
    if (b.args) |args| run_baseline_cmp_cmd.addArgs(args);
    const run_baseline_cmp_step = b.step("invention-baseline-compare", "Blind battery: invention vs 4 baselines (TSV)");
    run_baseline_cmp_step.dependOn(&run_baseline_cmp_cmd.step);

    const invent_engine_exe = b.addExecutable(.{
        .name = "invention_engine",
        .root_source_file = b.path("invention_engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(invent_engine_exe);
    const run_invent_engine_cmd = b.addRunArtifact(invent_engine_exe);
    if (b.args) |args| run_invent_engine_cmd.addArgs(args);
    const run_invent_engine_step = b.step("invention-engine", "Production invention engine: blind battery B with growable menu");
    run_invent_engine_step.dependOn(&run_invent_engine_cmd.step);

    const run_invent_strict_cmd = b.addRunArtifact(invent_engine_exe);
    run_invent_strict_cmd.addArg("--strict-tax");
    const run_invent_strict_step = b.step("invention-engine-strict-tax", "Invention engine with E26 tax promotion gate");
    run_invent_strict_step.dependOn(&run_invent_strict_cmd.step);

    const tier8_loop_exe = b.addExecutable(.{
        .name = "tier8_loop",
        .root_source_file = b.path("tier8_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_loop_exe);
    const run_tier8_loop_cmd = b.addRunArtifact(tier8_loop_exe);
    const run_tier8_loop_step = b.step("tier8-loop", "Tier 8 Wave 0+1: baseline + strict tax gate");
    run_tier8_loop_step.dependOn(&run_tier8_loop_cmd.step);

    const dispatch_exe = b.addExecutable(.{
        .name = "swarm_fork_dispatch",
        .root_source_file = b.path("swarm_fork_dispatch.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(dispatch_exe);
    const run_dispatch_cmd = b.addRunArtifact(dispatch_exe);
    const run_dispatch_step = b.step("tier8-dispatch", "Tier 8 fork dispatch registry");
    run_dispatch_step.dependOn(&run_dispatch_cmd.step);

    const tier8_battery_c_exe = b.addExecutable(.{
        .name = "open_invention_tier8_battery_c",
        .root_source_file = b.path("open_invention_tier8_battery_c.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_battery_c_exe);
    const run_tier8_battery_c_cmd = b.addRunArtifact(tier8_battery_c_exe);
    const run_tier8_battery_c_step = b.step("tier8-battery-c", "T8-AG-11: Battery C hardness harness");
    run_tier8_battery_c_step.dependOn(&run_tier8_battery_c_cmd.step);

    const tier8_bc_engine_exe = b.addExecutable(.{
        .name = "tier8_battery_c_engine",
        .root_source_file = b.path("tier8_battery_c_engine.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_bc_engine_exe);
    const run_tier8_bc_engine_cmd = b.addRunArtifact(tier8_bc_engine_exe);
    const run_tier8_bc_engine_step = b.step("tier8-battery-c-engine", "T8-AG-15: invention engine on Battery C");
    run_tier8_bc_engine_step.dependOn(&run_tier8_bc_engine_cmd.step);

    const run_tier8_bc_engine_strict_cmd = b.addRunArtifact(tier8_bc_engine_exe);
    run_tier8_bc_engine_strict_cmd.addArg("--strict-tax");
    const run_tier8_bc_engine_strict_step = b.step("tier8-battery-c-engine-strict", "T8-AG-15: Battery C + strict tax");
    run_tier8_bc_engine_strict_step.dependOn(&run_tier8_bc_engine_strict_cmd.step);

    const tier8_tax_tax_exe = b.addExecutable(.{
        .name = "tier8_tax_taxonomy",
        .root_source_file = b.path("tier8_tax_taxonomy.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_tax_tax_exe);
    const run_tier8_tax_tax_cmd = b.addRunArtifact(tier8_tax_tax_exe);
    const run_tier8_tax_tax_step = b.step("tier8-tax-taxonomy", "T8-AG-02f: remix taxonomy JSON");
    run_tier8_tax_tax_step.dependOn(&run_tier8_tax_tax_cmd.step);

    const run_tier8_bc_repl_cmd = b.addRunArtifact(tier8_battery_c_exe);
    run_tier8_bc_repl_cmd.addArg("--replicate");
    const run_tier8_bc_repl_step = b.step("tier8-battery-c-replicate", "T8-AG-11f: Battery C held-out ×2");
    run_tier8_bc_repl_step.dependOn(&run_tier8_bc_repl_cmd.step);

    const tier8_ledger_exe = b.addExecutable(.{
        .name = "tier8_ledger_smoke",
        .root_source_file = b.path("tier8_ledger_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_ledger_exe);
    const run_tier8_ledger_cmd = b.addRunArtifact(tier8_ledger_exe);
    const run_tier8_ledger_step = b.step("tier8-ledger-smoke", "T8-AG-18: promotion ledger smoke");
    run_tier8_ledger_step.dependOn(&run_tier8_ledger_cmd.step);

    const tier8_cross_audit_exe = b.addExecutable(.{
        .name = "tier8_cert_cross_audit",
        .root_source_file = b.path("tier8_cert_cross_audit.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_cross_audit_exe);
    const run_tier8_cross_cmd = b.addRunArtifact(tier8_cross_audit_exe);
    const run_tier8_cross_step = b.step("tier8-cert-cross-audit", "T8-AG-16: coverage/certify cross-audit");
    run_tier8_cross_step.dependOn(&run_tier8_cross_cmd.step);

    const tier8_ledger_drift_exe = b.addExecutable(.{
        .name = "tier8_ledger_drift",
        .root_source_file = b.path("tier8_ledger_drift.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_ledger_drift_exe);
    const run_tier8_ledger_drift_cmd = b.addRunArtifact(tier8_ledger_drift_exe);
    const run_tier8_ledger_drift_step = b.step("tier8-ledger-drift", "T8-AG-19: promotion ledger basis drift replay");
    run_tier8_ledger_drift_step.dependOn(&run_tier8_ledger_drift_cmd.step);

    const tier8_rq7_tax_exe = b.addExecutable(.{
        .name = "open_invention_tier8_rq7",
        .root_source_file = b.path("open_invention_tier8_rq7.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_rq7_tax_exe);
    const run_tier8_rq7_tax_cmd = b.addRunArtifact(tier8_rq7_tax_exe);
    run_tier8_rq7_tax_cmd.setCwd(b.path("."));
    const run_tier8_rq7_tax_step = b.step("tier8-rq7-tax", "T8-AG-07: RQ7 proposals + strict tax gate");
    run_tier8_rq7_tax_step.dependOn(&run_tier8_rq7_tax_cmd.step);

    const tier8_e11_tax_exe = b.addExecutable(.{
        .name = "open_invention_tier8_e11",
        .root_source_file = b.path("open_invention_tier8_e11.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_e11_tax_exe);
    const run_tier8_e11_tax_cmd = b.addRunArtifact(tier8_e11_tax_exe);
    run_tier8_e11_tax_cmd.setCwd(b.path("."));
    const run_tier8_e11_tax_step = b.step("tier8-e11-tax", "T8-AG-08: E11 proposals + strict tax gate");
    run_tier8_e11_tax_step.dependOn(&run_tier8_e11_tax_cmd.step);

    const tier8_basis_version_exe = b.addExecutable(.{
        .name = "tier8_tax_basis_version",
        .root_source_file = b.path("tier8_tax_basis_version.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tier8_basis_version_exe);
    const run_tier8_basis_version_cmd = b.addRunArtifact(tier8_basis_version_exe);
    const run_tier8_basis_version_step = b.step("tier8-basis-version", "T8-AG-17: tax basis version registry + monotonic audit");
    run_tier8_basis_version_step.dependOn(&run_tier8_basis_version_cmd.step);

    // Unit tests over the VSA primitives and the agent's readout channel.
    const tests = b.addTest(.{
        .root_source_file = b.path("tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("unit-test", "Run VSA / agent unit tests");
    test_step.dependOn(&run_tests.step);
}
