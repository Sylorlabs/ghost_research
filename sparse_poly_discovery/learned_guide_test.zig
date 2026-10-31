//! EXP-6: learned candidate policy vs baseline unified invention.
//! Run: zig build learned-guide-test --release=fast

const std = @import("std");
const ui = @import("unified_invention");

const SEED: u64 = 0xF0235A11CE0FF1CE;
const BOOT_SEED: u64 = 0xA11CE_0001;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== EXP-6: Learned Candidate Guide vs Baseline ({d} targets) ===\n\n", .{ui.NT});
    try out.print("Features: probe_corr, hardness_class, inner_type | perceptron trained on verifier labels\n", .{});
    try out.print("Seed: 0x{X}  top-k forge={d} world={d}\n\n", .{ SEED, ui.guide.TOP_K_FORGE, ui.guide.TOP_K_WORLD });

    // ── Baseline (standard unified loop, cost model only) ──
    const baseline_cost = try ui.countBaselineCertify(alloc, SEED);
    const baseline_bench = baseline_cost.summary;

    try out.print("── Baseline (exhaustive certify) ──\n", .{});
    try out.print("  unified solved: {d}/{d}\n", .{ baseline_bench.unified_solved, ui.NT });
    try out.print("  certify calls:  {d}\n", .{baseline_cost.certify_calls});
    try out.print("  forge fits:     {d}\n", .{baseline_cost.forge_fits});
    try out.print("  probe calls:    {d}\n\n", .{baseline_cost.probe_calls});

    // ── Bootstrap guide on routing battery ──
    var guide = ui.guide.Guide.init(alloc);
    defer guide.deinit();
    try ui.bootstrapGuide(alloc, &guide, BOOT_SEED);
    try out.print("── Bootstrap (routing battery: parity, sum%7, mono c3) ──\n", .{});
    try guide.printLog(out);
    try out.print("\n", .{});

    // ── Guided top-k ──
    const guided = try ui.runGuidedBenchmark(alloc, out, SEED, false, &guide, ui.guide.TOP_K_FORGE);

    try out.print("── Guided (perceptron forge-k={d} world-k={d}) ──\n", .{ ui.guide.TOP_K_FORGE, ui.guide.TOP_K_WORLD });
    try out.print("  unified solved: {d}/{d}\n", .{ guided.summary.unified_solved, ui.NT });
    try out.print("  certify calls:  {d}\n", .{guided.certify_calls});
    try out.print("  forge fits:     {d}\n", .{guided.forge_fits});
    try out.print("  probe calls:    {d}\n\n", .{guided.probe_calls});

    // ── Per-target comparison ──
    try out.print("{s:<32} | base cov | guided cov | source\n", .{"target"});
    try out.print("{s}\n", .{"--------------------------------+----------+------------+--------"});
    for (0..ui.NT) |t| {
        try out.print("{s:<32} | {d:.3}    | {d:.3}      | {s}\n", .{
            ui.TARGETS[t].name,
            baseline_bench.unified_cov[t],
            guided.summary.unified_cov[t],
            @tagName(guided.summary.solved_by[t]),
        });
    }
    try out.print("\n", .{});

    const certify_same = baseline_bench.unified_solved == guided.summary.unified_solved;
    var cov_match: usize = 0;
    for (0..ui.NT) |t| {
        const bok = baseline_bench.unified_cov[t] >= ui.COVER_THRESHOLD;
        const gok = guided.summary.unified_cov[t] >= ui.COVER_THRESHOLD;
        if (bok == gok) cov_match += 1;
    }

    const speedup = if (guided.certify_calls > 0)
        @as(f64, @floatFromInt(baseline_cost.certify_calls)) / @as(f64, @floatFromInt(guided.certify_calls))
    else
        1.0;

    const pass = certify_same and cov_match == ui.NT and speedup >= 1.4;

    try out.print("════════════════════ EXP-6 VERDICT ════════════════════\n", .{});
    try out.print("Certify rate unchanged: {s} ({d}/{d} solved, {d}/{d} target match)\n", .{
        if (certify_same) "YES" else "NO",
        guided.summary.unified_solved,
        baseline_bench.unified_solved,
        cov_match,
        ui.NT,
    });
    try out.print("Speedup factor (baseline/guided certify): {d:.2}x  ({d} → {d} calls)\n", .{
        speedup,
        baseline_cost.certify_calls,
        guided.certify_calls,
    });
    try out.print("Guide train steps after bootstrap+run: {d}\n", .{guide.train_steps});
    try out.print("RESULT: {s}\n", .{if (pass) "PASS" else "FAIL"});
    try out.print("\nDoc: boundary_crossing/docs/research/swarm_exp06_learned_guide.md\n", .{});
}