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
