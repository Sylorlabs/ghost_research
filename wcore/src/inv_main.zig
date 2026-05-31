//! The primitive-inventing engine — driver (PLAN_INVENTION_ENGINE.md).
//!
//! Phases run strictly in order, each with a kill-test (§5):
//!   phase0 — substrate + executor + fitness + sanity gate
//!   phase1 — flat regularized evolution vs random search (the reproduction)
//!   phase2 — + the compounding library (the core hypothesis)
//!
//! Usage:
//!   zig build run-invent -- phase0
//!   zig build run-invent -- phase1 [seed]
//!   zig build run-invent -- phase2 [seed]

const std = @import("std");
const sub = @import("inv_substrate.zig");
const tasks = @import("inv_tasks.zig");
const evo = @import("inv_evolve.zig");
const lib = @import("inv_library.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);

    const phase = if (args.len > 1) args[1] else "phase0";
    const seed: u64 = if (args.len > 2) (std.fmt.parseInt(u64, args[2], 0) catch 0xC0FFEE) else 0xC0FFEE;

    const out = std.io.getStdOut().writer();
    if (std.mem.eql(u8, phase, "phase0")) {
        try phase0(out);
    } else if (std.mem.eql(u8, phase, "phase1")) {
        try phase1(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase2")) {
        try phase2(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase3")) {
        try phase3(al, out, seed);
    } else if (std.mem.eql(u8, phase, "phase4")) {
        try phase4(al, out, seed);
    } else {
        try out.print("unknown phase '{s}'. try: phase0 | phase1 | phase2 | phase3 | phase4\n", .{phase});
    }
}

/// Count calls to a specific macro index across a champion's predict+learn.
fn callsTo(prog: *const sub.Program, macro_idx: usize) usize {
    var n: usize = 0;
    for (prog.predict.slice()) |ins| if (ins.op == .call and @as(usize, @intFromFloat(ins.imm)) == macro_idx) {
        n += 1;
    };
    for (prog.learn.slice()) |ins| if (ins.op == .call and @as(usize, @intFromFloat(ins.imm)) == macro_idx) {
        n += 1;
    };
    return n;
}

/// Phase 4 — THE TOWER. Phase 3 showed a single primitive (C0) does NOT buy
/// compositional reach: K=2 was 0/4. Here we add the SECOND level — C1 = a
/// composition macro (sum of two products) built ON TOP OF C0 — and ask: does the
/// next abstraction collapse the next task? Expected honest shape:
///   K=1 collapses via C0 (1 call); K=2 collapses via C1 (1 call) — LIFTING the
///   Phase-3 wall; K=4 re-hits the composition trap (it needs 2 C1s + a combine),
///   showing the trap recurs one level up and the tower must be climbed level by
///   level. C0/C1 are verified-by-hand (like C0 in Phase 3); DISCOVERING C1
///   autonomously is blocked by that same per-level trap — the frontier.
fn phase4(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 4: the tower — does the next abstraction collapse the next task? ===\n\n");

    // C0 = product (level 1), C1 = sum-of-two-products built on C0 (level 2)
    var library = [_]sub.Macro{ lib.referenceProductMacro(), lib.referenceComposeMacro() };
    const c0_label = try lib.decode(&library[0], al);
    try out.print("Library: C0 = {s}\n", .{c0_label});
    try out.writeAll("         C1 = sum of two products  v0[p0]·v0[p1] + v0[p2]·v0[p3]  (CALLS C0 twice — the tower)\n\n");

    const cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4 };
    const p = evo.Params{ .max_evals = 250_000, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.18 };
    const cell_seeds: usize = 4;

    const sweep = [_]struct { name: []const u8, t: tasks.Task, need: []const u8 }{
        .{ .name = "K=1 (1 product) ", .t = tasks.gate(2, 0, 1), .need = "1 C0 call" },
        .{ .name = "K=2 (2 products)", .t = tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } }), .need = "1 C1 call" },
        .{ .name = "K=4 (4 products)", .t = tasks.multiGate(8, &.{ .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 } }), .need = "2 C1 + add" },
    };

    try out.print("Tower reach sweep | budget {d} evals | {d} seeds/cell | C0+C1 available\n\n", .{ p.max_evals, cell_seeds });
    try out.writeAll("  task             | min solution | solves | best e→t | champion uses\n");
    try out.writeAll("  -----------------+--------------+--------+----------+---------------\n");

    for (sweep) |sw| {
        var hits: usize = 0;
        var best: ?usize = null;
        var best_c0: usize = 0;
        var best_c1: usize = 0;
        for (0..cell_seeds) |c| {
            var prng = std.Random.DefaultPrng.init(base_seed +% 0x77 +% hashName(sw.name) +% c *% 0x9E3779B1);
            const r = try evo.runEvolution(al, prng.random(), sw.t, cfg, p, &library, &.{});
            if (r.evals_to_target) |e| {
                hits += 1;
                if (best == null or e < best.?) {
                    best = e;
                    best_c0 = callsTo(&r.best, 0);
                    best_c1 = callsTo(&r.best, 1);
                }
            }
        }
        try out.print("  {s} | {s:<12} |  {d}/{d}   | ", .{ sw.name, sw.need, hits, cell_seeds });
        try printEvals(out, best, 8);
        if (best != null) {
            try out.print(" | {d}×C0, {d}×C1\n", .{ best_c0, best_c1 });
        } else {
            try out.writeAll(" | —\n");
        }
    }

    try out.writeAll("\n[READING] Phase 3 showed C0 alone gives K=2 = 0/4. If C1 now solves K=2 with a\n");
    try out.writeAll("single CALL, the SECOND abstraction collapsed the task C0 could not reach — the\n");
    try out.writeAll("tower compounds. If K=4 then stalls, the composition trap has simply moved up a\n");
    try out.writeAll("level (it needs C2 = sum-of-two-C1s): reach compounds, but one rung at a time,\n");
    try out.writeAll("and escaping each rung's trap to DISCOVER the next macro is the open frontier.\n");
}

/// Phase 3 — TIER-3 BRICK: does compounding give REACH? Two separable questions,
/// reported separately and honestly:
///   (1) Can the engine reliably DISCOVER a *composable* product primitive? A
///       short regression-graded bootstrap probes this. (It is hard — see below.)
///   (2) GIVEN a composable primitive, does reusing it let search reach
///       compositional tasks that flat search cannot? This is the reach
///       hypothesis, and it is tested with a verified product macro so the answer
///       does not depend on (1). Sweep arity (1 → 2 → 3 products), dim scaling
///       with K so flat stays solvable at K=1, and compare evals-to-target.
fn phase3(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 3: compounding for reach (Tier-3 brick) ===\n\n");

    // ---- (1) can it DISCOVER a composable product? (honest probe) --------------
    const boot_cfg = tasks.Config{ .n_train = 60, .n_test = 120, .n_seeds = 4, .grade = .regress };
    const boot_p = evo.Params{ .max_evals = 150_000, .pop_size = 1500, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.12 };
    const n_boot_seeds: usize = 4;
    try out.print("(1) DISCOVERY probe — regression-graded (so product≠ratio), {d} seeds x {d} evals:\n", .{ n_boot_seeds, boot_p.max_evals });
    var corpus = std.ArrayList(sub.Program).init(al);
    defer corpus.deinit();
    const train = tasks.gate(2, 0, 1);
    var disc_solves: usize = 0;
    var disc_best: f64 = 0;
    for (0..n_boot_seeds) |s| {
        var prng = std.Random.DefaultPrng.init(base_seed +% s *% 0xD1B54A32D192ED03);
        const elites = try al.alloc(sub.Program, 24);
        defer al.free(elites);
        const r = try evo.runEvolution(al, prng.random(), train, boot_cfg, boot_p, &.{}, elites);
        if (r.best_perf >= boot_p.target) disc_solves += 1;
        if (r.best_perf > disc_best) disc_best = r.best_perf;
        if (r.best_perf >= 0.9) for (elites) |e| try corpus.append(e);
    }
    const prod_ext = try lib.bestProductExtraction(al, corpus.items);
    try out.print("    {d}/{d} reached corr≥{d:.2} (best {d:.3}); abstractable PRODUCT found: {s}\n", .{ disc_solves, n_boot_seeds, boot_p.target, disc_best, if (prod_ext != null) "yes" else "no" });
    try out.writeAll("    ⇒ Reliable discovery of the *composable* form is the open sub-problem: the\n");
    try out.writeAll("      classification basin prefers the non-composing ratio gate, and the engine's\n");
    try out.writeAll("      favourite product (vector-scaling) writes a vector, outside the v1 macro\n");
    try out.writeAll("      language. So the reach test below uses a VERIFIED product macro instead.\n\n");

    // ---- (2) GIVEN a composable primitive, does reuse buy REACH? ---------------
    var library = [_]sub.Macro{lib.referenceProductMacro()};
    const c0_label = try lib.decode(&library[0], al);
    try out.print("(2) REACH test — C0 = verified macro, decodes as: {s}\n", .{c0_label});

    const sweep_cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4 };
    // higher diversity to give C0-lib its best shot at escaping the partial-credit
    // trap (one product already predicts the sign of a sum of products ~70%)
    const sweep_p = evo.Params{ .max_evals = 300_000, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.18 };
    const cell_seeds: usize = 4; // solve RATE per cell, not a single noisy attempt

    // dim scales with K so the K=1 wiring needle stays solvable by flat evolution
    const sweep = [_]struct { name: []const u8, t: tasks.Task, min_ops: usize }{
        .{ .name = "K=1  (1 product) ", .t = tasks.gate(2, 0, 1), .min_ops = 3 },
        .{ .name = "K=2  (2 products)", .t = tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } }), .min_ops = 7 },
        .{ .name = "K=3  (3 products)", .t = tasks.multiGate(6, &.{ .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 } }), .min_ops = 11 },
    };

    try out.print("    budget {d} evals | target {d:.2} | dim=2K | {d} seeds/cell\n\n", .{ sweep_p.max_evals, sweep_p.target, cell_seeds });
    try out.writeAll("  task              | raw min_ops | flat solves | flat best e→t | C0-lib solves | C0-lib best e→t\n");
    try out.writeAll("  ------------------+-------------+-------------+---------------+---------------+----------------\n");

    for (sweep) |sw| {
        var flat_hits: usize = 0;
        var lib_hits: usize = 0;
        var flat_best: ?usize = null;
        var lib_best: ?usize = null;
        for (0..cell_seeds) |c| {
            var p_flat = std.Random.DefaultPrng.init(base_seed +% 0x55 +% hashName(sw.name) +% c *% 0xABCDEF);
            var p_lib = std.Random.DefaultPrng.init(base_seed +% 0x66 +% hashName(sw.name) +% c *% 0x123457);
            const rf = try evo.runEvolution(al, p_flat.random(), sw.t, sweep_cfg, sweep_p, &.{}, &.{});
            const rl = try evo.runEvolution(al, p_lib.random(), sw.t, sweep_cfg, sweep_p, &library, &.{});
            if (rf.evals_to_target) |e| {
                flat_hits += 1;
                if (flat_best == null or e < flat_best.?) flat_best = e;
            }
            if (rl.evals_to_target) |e| {
                lib_hits += 1;
                if (lib_best == null or e < lib_best.?) lib_best = e;
            }
        }
        try out.print("  {s} |     {d:>2}      |     {d}/{d}     | ", .{ sw.name, sw.min_ops, flat_hits, cell_seeds });
        try printEvals(out, flat_best, 13);
        try out.print(" |     {d}/{d}     | ", .{ lib_hits, cell_seeds });
        try printEvals(out, lib_best, 14);
        try out.writeAll("\n");
    }

    try out.writeAll("\n[READING] K=1: a reused primitive collapses the task to one CALL — a huge\n");
    try out.writeAll("acceleration. The K≥2 columns are the real test: does one primitive AUTOMATICALLY\n");
    try out.writeAll("buy compositional reach, or does composing K of them re-introduce the needle\n");
    try out.writeAll("(a single product already predicts a sum-of-products' sign ~70% — a deceptive\n");
    try out.writeAll("trap)? If C0-lib also stalls at K≥2, reach needs the TOWER (abstract the\n");
    try out.writeAll("composition itself), not just one primitive — the precise §8 wall.\n");
}

/// Phase 2 — THE CORE HYPOTHESIS (§5). Build a library by abstracting the
/// recurring gate from elites of a bootstrap solve, then measure evals-to-target
/// on NEW family members with vs without that library. Kill-test: library
/// evolution reaches target in SIGNIFICANTLY fewer evals than flat evolution.
fn phase2(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 2: the compounding library (the ratchet) ===\n\n");

    const boot_cfg = tasks.Config{ .n_train = 60, .n_test = 150, .n_seeds = 5 };
    const boot_p = evo.Params{ .max_evals = 300_000, .pop_size = 1500, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.12 };
    const k_elites: usize = 24;
    const n_boot_seeds: usize = 5;

    // ---- bootstrap: pool elites across several solves of pair (0,1), abstract ----
    try out.print("Bootstrap: solve gate(0,1) up to {d}x, pool top-{d} elites, abstract the recurring motif.\n", .{ n_boot_seeds, k_elites });
    var corpus = std.ArrayList(sub.Program).init(al);
    defer corpus.deinit();
    const train = tasks.gate(4, 0, 1);
    var solves: usize = 0;
    for (0..n_boot_seeds) |s| {
        var prng = std.Random.DefaultPrng.init(base_seed +% s *% 0xD1B54A32D192ED03);
        const elites = try al.alloc(sub.Program, k_elites);
        defer al.free(elites);
        const r = try evo.runEvolution(al, prng.random(), train, boot_cfg, boot_p, &.{}, elites);
        if (r.best_perf >= boot_p.target) {
            solves += 1;
            for (elites) |e| try corpus.append(e);
        }
    }
    try out.print("  {d}/{d} bootstrap solves succeeded; corpus = {d} elite programs.\n", .{ solves, n_boot_seeds, corpus.items.len });

    const ext_opt = try lib.bestExtraction(al, corpus.items);
    if (ext_opt == null) {
        try out.writeAll("\n[WALL] No recurring abstractable template found in the elites.\n");
        try out.writeAll("The converged solutions use forms outside the v1 macro scope (e.g. vector\n");
        try out.writeAll("writes via v_scale). The ratchet cannot be tested until the macro language\n");
        try out.writeAll("covers them — this is a precise, honest negative (§8), not a silent failure.\n");
        return;
    }
    const ext = ext_opt.?;
    const label = try lib.decode(&ext.macro, al);
    var library = [_]sub.Macro{ext.macro};
    try out.print("\n[ABSTRACT] discovered C0: occurs {d}x, length {d}, saves {d} description nodes\n", .{ ext.occurrences, ext.length, ext.saved });
    try out.print("           C0 decoded behaviourally as: {s}\n", .{label});
    try out.print("           C0 takes {d} params (the element indices), {d} local registers\n\n", .{ ext.macro.params.len, ext.macro.n_local });

    // ---- reuse test on NEW family members --------------------------------------
    // Budget chosen so flat evolution can usually solve the single-gate tasks
    // (Phase 1 ⇒ ~100k mean), giving real speedup ratios rather than misses, while
    // the library still solves in <1k. The double-gate probes the next frontier.
    const reuse_cfg = tasks.Config{ .n_train = 50, .n_test = 120, .n_seeds = 4 };
    const reuse_p = evo.Params{ .max_evals = 250_000, .pop_size = 1000, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.12 };

    const reuse_tasks = [_]struct { name: []const u8, t: tasks.Task }{
        .{ .name = "gate(2,3)", .t = tasks.gate(4, 2, 3) },
        .{ .name = "gate(1,3)", .t = tasks.gate(4, 1, 3) },
        .{ .name = "gate(0,3)", .t = tasks.gate(4, 0, 3) },
        .{ .name = "dbl(01,23)", .t = tasks.multiGate(4, &.{ .{ 0, 1 }, .{ 2, 3 } }) },
    };

    try out.print("Reuse test (NEW tasks the library never saw) | budget {d} evals | target {d:.2}\n\n", .{ reuse_p.max_evals, reuse_p.target });
    try out.writeAll("  task        | random e→t | flat-evo e→t | LIB-evo e→t | lib speedup | calls in champ\n");
    try out.writeAll("  ------------+------------+--------------+-------------+-------------+---------------\n");

    var flat_sum: f64 = 0;
    var lib_sum: f64 = 0;
    var both_hit: usize = 0;
    var rand_solved: usize = 0;
    var flat_solved: usize = 0;
    var lib_solved: usize = 0;

    for (reuse_tasks) |rt| {
        var p_rand = std.Random.DefaultPrng.init(base_seed +% 0x111 +% hashName(rt.name));
        var p_flat = std.Random.DefaultPrng.init(base_seed +% 0x222 +% hashName(rt.name));
        var p_lib = std.Random.DefaultPrng.init(base_seed +% 0x333 +% hashName(rt.name));

        const rr = evo.runRandomSearch(p_rand.random(), rt.t, reuse_cfg, reuse_p, &.{});
        const rf = try evo.runEvolution(al, p_flat.random(), rt.t, reuse_cfg, reuse_p, &.{}, &.{});
        const rl = try evo.runEvolution(al, p_lib.random(), rt.t, reuse_cfg, reuse_p, &library, &.{});

        if (rr.evals_to_target != null) rand_solved += 1;
        if (rf.evals_to_target != null) flat_solved += 1;
        if (rl.evals_to_target != null) lib_solved += 1;

        try out.print("  {s:<11} | ", .{rt.name});
        try printEvals(out, rr.evals_to_target, 10);
        try out.writeAll(" | ");
        try printEvals(out, rf.evals_to_target, 12);
        try out.writeAll(" | ");
        try printEvals(out, rl.evals_to_target, 11);
        try out.writeAll(" | ");
        if (rf.evals_to_target != null and rl.evals_to_target != null and rl.evals_to_target.? > 0) {
            const sp = @as(f64, @floatFromInt(rf.evals_to_target.?)) / @as(f64, @floatFromInt(rl.evals_to_target.?));
            try out.print("{d:>9.1}x | {d}\n", .{ sp, rl.lib_calls_in_best });
            flat_sum += @floatFromInt(rf.evals_to_target.?);
            lib_sum += @floatFromInt(rl.evals_to_target.?);
            both_hit += 1;
        } else {
            try out.print("{s:>10} | {d}\n", .{ "  n/a", rl.lib_calls_in_best });
        }
    }

    try out.writeAll("\n");
    try out.print("[SOLVE RATE over {d} tasks]  random {d}/{d}  |  flat-evo {d}/{d}  |  LIB-evo {d}/{d}\n", .{ reuse_tasks.len, rand_solved, reuse_tasks.len, flat_solved, reuse_tasks.len, lib_solved, reuse_tasks.len });
    if (both_hit > 0) {
        try out.print("[RATCHET] across {d} tasks both flat & LIB solved: flat mean {d:.0} e→t, LIB mean {d:.0} e→t  ⇒  {d:.1}x fewer evals\n", .{ both_hit, flat_sum / @as(f64, @floatFromInt(both_hit)), lib_sum / @as(f64, @floatFromInt(both_hit)), flat_sum / lib_sum });
    }
    try out.writeAll("\nThe library macro is reused as a single op; new gate tasks collapse to one CALL.\n");
}

fn hashName(s: []const u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (s) |c| {
        h ^= c;
        h *%= 0x100000001b3;
    }
    return h;
}

/// Phase 1 kill-test: evolution must reach the target MARKEDLY faster than random
/// search and rediscover the gate + a learn rule. If evolution ≈ random, the
/// substrate/fitness/mutation is broken (§5 Phase 1).
fn phase1(al: std.mem.Allocator, out: anytype, base_seed: u64) !void {
    try out.writeAll("=== PHASE 1: flat regularized evolution vs random search ===\n\n");
    const task = tasks.gate(2, 0, 1);
    // Higher fidelity (more seeds/held-out) collapses deceptive optima — which
    // rely on small-sample flukes — back toward chance, while the true gate stays
    // at 1.0. That widens the gap selection must climb and de-fangs the traps.
    const cfg = tasks.Config{ .n_train = 60, .n_test = 150, .n_seeds = 5 };
    // λ tiny: MDL is a TIE-BREAKER, not a search driver, so partial scaffolds
    // survive in the population (neutral drift is evolution's whole advantage here).
    // Weaker tournament + more immigrants = less premature convergence on traps.
    const p = evo.Params{ .max_evals = 300_000, .pop_size = 1500, .tournament = 8, .target = 0.95, .lambda = 1e-4, .immigrant_rate = 0.12 };
    const n_runs: usize = 5;

    try out.print("Task A: y=sign(x0*x1)  | budget {d} evals/run | {d} runs | target perf {d:.2}\n\n", .{ p.max_evals, n_runs, p.target });
    try out.writeAll("  run | evolution evals→target | random evals→target | evo best | rand best\n");
    try out.writeAll("  ----+------------------------+---------------------+----------+----------\n");

    var evo_hits: usize = 0;
    var rand_hits: usize = 0;
    var evo_sum: usize = 0;
    var rand_sum: usize = 0;
    var champion: sub.Program = .{};
    var champion_perf: f64 = -1;

    for (0..n_runs) |run| {
        var pe = std.Random.DefaultPrng.init(base_seed +% run *% 0xA24BAED4963EE407);
        var pr = std.Random.DefaultPrng.init(base_seed +% run *% 0x9E3779B97F4A7C15 +% 1);
        const re = try evo.runEvolution(al, pe.random(), task, cfg, p, &.{}, &.{});
        const rr = evo.runRandomSearch(pr.random(), task, cfg, p, &.{});

        try out.print("  {d:>3} | ", .{run});
        try printEvals(out, re.evals_to_target, 22);
        try out.writeAll(" | ");
        try printEvals(out, rr.evals_to_target, 19);
        try out.print(" | {d:.4}   | {d:.4}\n", .{ re.best_perf, rr.best_perf });
        if (re.evals_to_target) |e| {
            evo_hits += 1;
            evo_sum += e;
        }
        if (rr.evals_to_target) |e| {
            rand_hits += 1;
            rand_sum += e;
        }
        if (re.best_perf > champion_perf) {
            champion_perf = re.best_perf;
            champion = re.best;
        }
    }

    try out.writeAll("\n");
    try out.print("  evolution: {d}/{d} runs hit target", .{ evo_hits, n_runs });
    if (evo_hits > 0) try out.print(", mean {d} evals→target", .{evo_sum / evo_hits});
    try out.writeAll("\n");
    try out.print("  random   : {d}/{d} runs hit target", .{ rand_hits, n_runs });
    if (rand_hits > 0) try out.print(", mean {d} evals→target", .{rand_sum / rand_hits});
    try out.writeAll("\n\n");

    // high-fidelity re-validation of the champion (guard against lucky noise)
    const valcfg = tasks.Config{ .n_train = 200, .n_test = 400, .n_seeds = 12, .base_seed = 0xBEEF };
    const val = tasks.evaluate(&champion, &.{}, task, valcfg);
    try out.print("[VALIDATE] champion re-scored on 12 fresh seeds x 400 held-out: acc = {d:.4}\n\n", .{val});
    try out.writeAll("The best program evolution discovered (raw, undecoded):\n");
    try sub.writeProgram(&champion, out);
}

fn printEvals(out: anytype, e: ?usize, width: usize) !void {
    var buf: [32]u8 = undefined;
    const txt = if (e) |v| try std.fmt.bufPrint(&buf, "{d}", .{v}) else try std.fmt.bufPrint(&buf, "— (miss)", .{});
    var pad = width;
    if (txt.len < width) pad = width - txt.len else pad = 0;
    for (0..pad) |_| try out.writeAll(" ");
    try out.writeAll(txt);
}

/// Phase 0 sanity gate: the verifier must score a correct hand-written program
/// high and garbage low. If it doesn't, everything downstream is meaningless.
fn phase0(out: anytype) !void {
    try out.writeAll("=== PHASE 0: substrate + fitness verifier sanity gate ===\n\n");
    const cfg = tasks.Config{ .n_train = 200, .n_test = 400, .n_seeds = 8 };
    const task = tasks.gate(2, 0, 1);

    const ref = tasks.referenceGate(0, 1);
    const lin = tasks.referenceLinear();
    const empty = sub.Program{};

    const acc_ref = tasks.evaluate(&ref, &.{}, task, cfg);
    const acc_lin = tasks.evaluate(&lin, &.{}, task, cfg);
    const acc_empty = tasks.evaluate(&empty, &.{}, task, cfg);

    try out.print("Task A: y = sign(x0 * x1), dim=2, {d} seeds x {d} held-out\n\n", .{ cfg.n_seeds, cfg.n_test });
    try out.print("  hand-written gate+gradient : held-out acc = {d:.4}\n", .{acc_ref});
    try out.print("  linear model (no product)  : held-out acc = {d:.4}\n", .{acc_lin});
    try out.print("  empty/garbage program      : held-out acc = {d:.4}\n\n", .{acc_empty});

    const pass = acc_ref > 0.95 and acc_lin < 0.65 and acc_empty < 0.65;
    try out.print("[GATE] correct >> chance, gate is load-bearing: {s}\n", .{if (pass) "PASS" else "FAIL"});
    try out.writeAll("\nThe reference gate program (what a correct candidate looks like):\n");
    try sub.writeProgram(&ref, out);
}

test {
    std.testing.refAllDecls(@This());
    _ = sub;
    _ = tasks;
    _ = evo;
    _ = lib;
}
