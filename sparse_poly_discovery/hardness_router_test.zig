//! Fork 2 test: hardness router → DUAL_BAND control.
//! Compares guided cross-class pair routing vs brute O(N²) pair search.
//! Run: zig build hardness-router-test

const std = @import("std");
const env_mod = @import("environment.zig");
const router = @import("hardness_router.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const probe_steps: usize = 5000;
    const verify_steps: usize = 15000;
    const n_seeds: usize = 6;
    const seed_base: u64 = 0xABC0;

    const dual = env_mod.TaskParams{
        .min_mass = 16,
        .max_mass = 48,
        .min_left_mass = 6,
        .max_left_mass = 22,
        .shock_period = 0,
        .volatility_after = 1_000_000,
    };

    try out.print("=== FORK 2: Hardness Router → DUAL_BAND ({d} probe / {d} verify x {d} seeds) ===\n\n", .{
        probe_steps, verify_steps, n_seeds,
    });

    // Phase 1: single-feature substrate probes
    try out.print("--- Phase 1: single-feature probes (substrate hardness) ---\n", .{});
    try out.print("  feature        | class     | fail/1k\n", .{});
    try out.print("  ---------------+-----------+--------\n", .{});

    var probes: [router.ROUTE_FEATURES.len]router.ProbeResult = undefined;
    try router.probeAll(alloc, dual, probe_steps, n_seeds, seed_base, &probes);
    for (probes) |p| {
        try out.print("  {s:<14} | {s:<9} | {d:>7.2}\n", .{
            @tagName(p.feature), @tagName(p.class), p.fail_per_1k,
        });
    }

    const task_class = router.classifyTask(&probes, router.isCompoundTask(dual));
    try out.print("\n  Task classification: {s}\n", .{@tagName(task_class)});
    try out.print("  (Q38 analog: deg1∧extremal both fail alone → compound pair needed)\n\n", .{});

    // Phase 2: hardness-guided routing (1 cross-class pair verify only)
    const cross = router.proposeCrossClassPair(&probes);
    const guided_fail = try router.meanPairFailRate(alloc, dual, cross.f1, cross.f2, verify_steps, n_seeds, seed_base);
    const n_cross = router.countCrossClassPairs();
    const n_directed = router.ROUTE_FEATURES.len * (router.ROUTE_FEATURES.len - 1);
    try out.print("--- Phase 2: hardness-guided pair proposal ---\n", .{});
    try out.print("  best deg1:     {s} ({d:.2} fail/1k on singles)\n", .{
        @tagName(cross.f1), cross.best_deg1_fail,
    });
    try out.print("  best extremal: {s} ({d:.2} fail/1k on singles)\n", .{
        @tagName(cross.f2), cross.best_extremal_fail,
    });
    try out.print("  proposed pair: ({s},{s}) = {d:.2} fail/1k\n", .{
        @tagName(cross.f1), @tagName(cross.f2), guided_fail,
    });
    try out.print("  cross-class pairs searched: {d} (vs {d} directed pairs brute)\n\n", .{
        n_cross, n_directed,
    });

    // Phase 3: brute baseline
    try out.print("--- Phase 3: brute O(N²) pair search baseline ---\n", .{});
    const brute = try router.brutePairSearch(alloc, dual, verify_steps, n_seeds, seed_base);
    try out.print("  brute best: ({s},{s}) = {d:.2} fail/1k\n\n", .{
        @tagName(brute.f1), @tagName(brute.f2), brute.fail_per_1k,
    });

    // Reference: naive default pair (sum, left_mass) — the "obvious" wrong choice
    const naive = try router.meanPairFailRate(alloc, dual, .sum, .left_mass, verify_steps, n_seeds, seed_base);
    try out.print("--- Reference pairs ---\n", .{});
    try out.print("  naive (sum,left_mass):     {d:.2} fail/1k\n", .{naive});
    const swapped = try router.meanPairFailRate(alloc, dual, .max_cell, .left_mass, verify_steps, n_seeds, seed_base);
    try out.print("  (max_cell,left_mass):      {d:.2} fail/1k\n", .{swapped});

    // Verdict
    const matched = (cross.f1 == brute.f1 and cross.f2 == brute.f2) or
        (cross.f1 == brute.f2 and cross.f2 == brute.f1);
    const gap = guided_fail - brute.fail_per_1k;

    try out.print("\n=== VERDICT ===\n", .{});
    if (task_class == .q38_compound) {
        try out.print("  Q38 compound classification: CONFIRMED on DUAL_BAND.\n", .{});
    } else {
        try out.print("  Q38 compound classification: NOT triggered (got {s}).\n", .{@tagName(task_class)});
    }
    if (matched) {
        try out.print("  Hardness router found SAME pair as brute search.\n", .{});
    } else {
        try out.print("  Hardness router pair DIFFERS from brute: guided ({s},{s}) vs brute ({s},{s}).\n", .{
            @tagName(cross.f1), @tagName(cross.f2),
            @tagName(brute.f1), @tagName(brute.f2),
        });
    }
    try out.print("  Guided fail/1k: {d:.2}  |  Brute fail/1k: {d:.2}  |  gap: {d:.2}\n", .{
        guided_fail, brute.fail_per_1k, gap,
    });
    if (guided_fail <= brute.fail_per_1k + 0.5) {
        try out.print("  Hardness-guided discovery MATCHES or BEATS blind pair search.\n", .{});
    } else {
        try out.print("  Hardness-guided discovery WORSE than brute (gap {d:.2}).\n", .{gap});
    }
    try out.print("  Search cost: {d} single probes + 1 pair vs {d} brute pair runs.\n", .{
        router.ROUTE_FEATURES.len + 1,
        n_directed,
    });
}