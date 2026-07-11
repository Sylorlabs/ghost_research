//! labs_swarm.zig — round 2026-07-10d: the swarm rematch.
//!
//! Round a (labs_campaign.zig) ran ONE concentrated method per length (single-flip
//! tabu, +skew-tabu for odd N) and matched best-known on 28/40 lengths, missing all
//! even N>=44 plus {61,63,64}. Round b (labs_even_n.zig) attacked those 12 misses by
//! SPLITTING one enlarged budget across 7-8 diverse arms (memetic, pair/triple moves,
//! structural hypotheses) run SEQUENTIALLY at fixed per-arm shares — and found that
//! naive splitting HURT: 4/12 lengths came in worse than round a's single concentrated
//! run, because thinner per-arm budget + costlier composite moves bought fewer
//! effective outer iterations than round a's simpler, fully-concentrated search.
//!
//! THE HYPOTHESIS UNDER TEST HERE: does a pool of DIVERSE strategies, combined with
//! PROPER concentration (adaptive reallocation toward whichever arm is actually
//! improving, instead of a fixed even split), beat both (a) a single concentrated
//! method and (b) round b's naive equal split — at the SAME total eval budget?
//!
//! Design: for each of the 12 miss lengths, run 5 experiments, each a FRESH
//! independent-best-tracking run at the SAME total budget T:
//!   1. concentrated_1   — one single arm (long-tenure plain pair-tabu), the whole
//!                         budget in one continuous run. "few deep strategies."
//!   2. pool3_equal      — 3 diverse arms (tabu / structural / memetic), budget split
//!                         evenly every round, no feedback. "many[-ish] shallow diverse",
//!                         round-b's mechanism at a smaller pool.
//!   3. pool3_adaptive   — same 3 arms, but each round after the first, half the
//!                         round's budget is reallocated toward whichever arm(s)
//!                         produced the most global-best improvement in the PREVIOUS
//!                         round (with an equal-split floor so no arm is ever starved
//!                         to zero). "adaptive — concentrate on whichever is improving."
//!   4. pool9_equal      — 9 diverse arms (2 tenure profiles, 2 triple-window widths,
//!                         2 restart policies, 1 structural, 2 memetic crossover modes),
//!                         even split every round.
//!   5. pool9_adaptive   — same 9 arms, adaptive reallocation as in (3).
//!
//! All 5 experiments per length get the IDENTICAL total eval budget T — this is the
//! direct, apples-to-apples test of concentration vs diversity vs adaptive-diversity
//! that round b's design (thin naive split only, no concentrated/adaptive comparison
//! point) could not answer.
//!
//! Energy/flip core (computeC/energyFromC/energyDirect/applyFlipDelta/merit) and the
//! structural-mode machinery (Mode/freeCount/mirrorOf/signOf/initStruct/applyFreeFlip/
//! applyMoveOnce/probeMove) are COPIED VERBATIM (read-only reuse) from
//! boundary_crossing/labs_even_n.zig, which itself copied them verbatim from
//! labs_campaign.zig — so any difference in outcome across all three files is
//! attributable to SEARCH STRATEGY, never to a different (possibly buggy) energy
//! engine. This file is fully standalone; it does not import or modify either.
//!
//! Move-accounting convention (same as prior rounds): 1 "eval" = 1 neighbor candidate
//! considered, regardless of internal O(N) pass count (a structural-mode pair move
//! costs ~8 passes, a plain pair move ~4, a plain single ~1 — same convention as
//! labs_even_n.zig).
//!
//! Build (from repo root):
//!   zig build-exe boundary_crossing/labs_swarm.zig -O ReleaseFast \
//!       -femit-bin=/tmp/claude-1000/labs_swarm
//!   /tmp/claude-1000/labs_swarm --ns=44,48,50 --csv=/tmp/g1.csv --json=/tmp/g1.json
//!   (add --quick for a fast smoke run; --div=N scales all budgets by 1/N)
//!
//! Outputs (default paths, override with --csv=/--json=):
//!   results/labs_swarm_2026_07_10.csv          the breadth-vs-concentration curve:
//!                                               one row per (N, config)
//!   results/labs_swarm_yield_2026_07_10.csv     auxiliary: every global-best
//!                                               improvement event (N,method,evals,E,F)
//!   results/labs_swarm_claims_2026_07_10.json   overall best sequence per N, for the
//!                                               INDEPENDENT verifier
//!                                               scripts/zig/labs_check.zig (reused
//!                                               UNMODIFIED — never trust this binary
//!                                               on its own word)

const std = @import("std");

const MaxN: usize = 64;

// ---------------------------------------------------------------------------
// the 12 miss lengths, with round a's (2026-07-10) and round b's (2026-07-10b)
// results plus the best-known table entry — all copied verbatim from
// docs/research/labs_campaign.md / labs_even_n.md for reporting context only
// (not used in any search decision).
// ---------------------------------------------------------------------------
const MissRow = struct { n: usize, round_a_e: i64, round_b_e: i64, known_e: i64 };
const miss_table = [_]MissRow{
    .{ .n = 44, .round_a_e = 126, .round_b_e = 122, .known_e = 122 },
    .{ .n = 48, .round_a_e = 160, .round_b_e = 160, .known_e = 140 },
    .{ .n = 50, .round_a_e = 161, .round_b_e = 153, .known_e = 153 },
    .{ .n = 52, .round_a_e = 174, .round_b_e = 178, .known_e = 166 },
    .{ .n = 54, .round_a_e = 199, .round_b_e = 207, .known_e = 175 },
    .{ .n = 56, .round_a_e = 208, .round_b_e = 196, .known_e = 192 },
    .{ .n = 58, .round_a_e = 229, .round_b_e = 245, .known_e = 197 },
    .{ .n = 60, .round_a_e = 254, .round_b_e = 246, .known_e = 218 },
    .{ .n = 61, .round_a_e = 230, .round_b_e = 230, .known_e = 226 },
    .{ .n = 62, .round_a_e = 283, .round_b_e = 307, .known_e = 235 },
    .{ .n = 63, .round_a_e = 271, .round_b_e = 259, .known_e = 207 },
    .{ .n = 64, .round_a_e = 312, .round_b_e = 312, .known_e = 208 },
};

fn missRow(n: usize) MissRow {
    for (miss_table) |r| if (r.n == n) return r;
    unreachable;
}

// ---------------------------------------------------------------------------
// energy machinery — COPIED VERBATIM from labs_even_n.zig / labs_campaign.zig.
// ---------------------------------------------------------------------------
fn computeC(s: []const i8, C: []i64) void {
    const n = s.len;
    var k: usize = 1;
    while (k < n) : (k += 1) {
        var c: i64 = 0;
        var i: usize = 0;
        while (i + k < n) : (i += 1) c += @as(i64, s[i]) * @as(i64, s[i + k]);
        C[k] = c;
    }
}

fn energyFromC(C: []const i64, n: usize) i64 {
    var e: i64 = 0;
    var k: usize = 1;
    while (k < n) : (k += 1) e += C[k] * C[k];
    return e;
}

fn energyDirect(s: []const i8) i64 {
    var C: [MaxN]i64 = undefined;
    computeC(s, C[0..s.len]);
    return energyFromC(C[0..s.len], s.len);
}

fn applyFlipDelta(s: []i8, C: []i64, i: usize, n: usize) i64 {
    var d: i64 = 0;
    var k: usize = 1;
    while (k < n) : (k += 1) {
        var t: i64 = 0;
        if (i >= k) t += @as(i64, s[i - k]);
        if (i + k < n) t += @as(i64, s[i + k]);
        if (t != 0) {
            const nc = C[k] - 2 * @as(i64, s[i]) * t;
            d += nc * nc - C[k] * C[k];
            C[k] = nc;
        }
    }
    s[i] = -s[i];
    return d;
}

fn merit(n: usize, e: i64) f64 {
    return @as(f64, @floatFromInt(n * n)) / (2.0 * @as(f64, @floatFromInt(e)));
}

const Yield = struct { n: usize, method: []const u8, evals: u64, e: i64 };

// ---------------------------------------------------------------------------
// structural modes — COPIED VERBATIM from labs_even_n.zig.
// ---------------------------------------------------------------------------
const Mode = enum { plain, skew_odd, mirror_altern };

fn freeCount(mode: Mode, n: usize) usize {
    return switch (mode) {
        .plain => n,
        .skew_odd => (n + 1) / 2,
        .mirror_altern => n / 2,
    };
}

fn mirrorOf(mode: Mode, n: usize, i: usize) ?usize {
    return switch (mode) {
        .plain => null,
        .skew_odd => blk: {
            const c = (n - 1) / 2;
            break :blk if (i == c) null else 2 * c - i;
        },
        .mirror_altern => n - 1 - i,
    };
}

fn signOf(mode: Mode, n: usize, i: usize) i8 {
    return switch (mode) {
        .plain => 1,
        .skew_odd => blk: {
            const c = (n - 1) / 2;
            if (i == c) break :blk 1;
            const d = if (i < c) c - i else i - c;
            break :blk if (d % 2 == 1) -1 else 1;
        },
        .mirror_altern => if (i % 2 == 1) -1 else 1,
    };
}

fn modeName(mode: Mode) []const u8 {
    return switch (mode) {
        .plain => "plain",
        .skew_odd => "skew",
        .mirror_altern => "mirror_altern",
    };
}

fn initStruct(mode: Mode, n: usize, s: []i8, rng: std.Random) void {
    const m = freeCount(mode, n);
    for (0..m) |i| s[i] = if (rng.boolean()) 1 else -1;
    for (0..m) |i| {
        if (mirrorOf(mode, n, i)) |j| s[j] = signOf(mode, n, i) * s[i];
    }
}

fn applyFreeFlip(mode: Mode, n: usize, i: usize, s: []i8, C: []i64) i64 {
    var d = applyFlipDelta(s, C, i, n);
    if (mirrorOf(mode, n, i)) |j| d += applyFlipDelta(s, C, j, n);
    return d;
}

fn applyMoveOnce(mode: Mode, n: usize, idx: []const usize, s: []i8, C: []i64) i64 {
    var d: i64 = 0;
    for (idx) |i| d += applyFreeFlip(mode, n, i, s, C);
    return d;
}

fn probeMove(mode: Mode, n: usize, idx: []const usize, s: []i8, C: []i64) i64 {
    const d = applyMoveOnce(mode, n, idx, s, C);
    _ = applyMoveOnce(mode, n, idx, s, C);
    return d;
}

const Neigh = enum { single, pair, triple };
const Move = struct { count: u8, idx: [3]usize, d: i64 };

// ---------------------------------------------------------------------------
// NEW in this file: parametrized tabu tenure/restart policy, so different arms
// in the pool can genuinely differ in tenure length AND restart aggressiveness
// (round a/b used one fixed tenure formula and one fixed stagnation-only
// restart policy everywhere).
// ---------------------------------------------------------------------------
const TabuParams = struct {
    tenure_base: u64, // tenure = iter + tenure_base + rand(tenure_span)
    tenure_span_denom: u64, // tenure_span = max(2, m / tenure_span_denom)
    stall_mult: u64, // restart if no global improvement for stall_mult*n iters
    forced_restart_iters: u64, // 0 = off; else force a restart every this many iters
};

const default_tp = TabuParams{ .tenure_base = 4, .tenure_span_denom = 4, .stall_mult = 60, .forced_restart_iters = 0 };

// ---------------------------------------------------------------------------
// generalized tabu search (structural mode x neighborhood x tenure/restart
// policy). Adapted from labs_even_n.zig's structTabuRun: same move logic, now
// with TabuParams instead of hardcoded tenure(4,n/4) and stall_mult=60, plus
// an optional forced periodic restart (a genuinely different restart POLICY,
// not just a different stagnation threshold).
// ---------------------------------------------------------------------------
fn structTabuRun(
    n: usize,
    mode: Mode,
    neigh: Neigh,
    window: usize,
    tp: TabuParams,
    budget: u64,
    seed: u64,
    gbest_seq: []i8,
    gbestE: *i64,
    yields: *std.ArrayList(Yield),
    method_name: []const u8,
    evals_offset: u64,
    seed_state: ?struct { s: []const i8, e: i64 },
    single_pass: bool,
) !u64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var s: [MaxN]i8 = undefined;
    var C: [MaxN]i64 = undefined;
    var tabu_until: [MaxN]u64 = undefined;
    var evals: u64 = 0;
    const m = freeCount(mode, n);
    const stall_limit: u64 = tp.stall_mult * @as(u64, n);
    const iters_per_restart: u64 = 4000;
    var first_pass = true;

    while (evals < budget) {
        if (first_pass and seed_state != null) {
            @memcpy(s[0..n], seed_state.?.s[0..n]);
        } else {
            initStruct(mode, n, s[0..n], rng);
        }
        first_pass = false;
        computeC(s[0..n], C[0..n]);
        var curE = energyFromC(C[0..n], n);
        evals += 1;
        for (0..m) |i| tabu_until[i] = 0;
        if (curE < gbestE.*) {
            gbestE.* = curE;
            @memcpy(gbest_seq[0..n], s[0..n]);
            try yields.append(.{ .n = n, .method = method_name, .evals = evals_offset + evals, .e = curE });
        }

        var iter: u64 = 1;
        var last_improve: u64 = 0;
        var last_forced: u64 = 0;
        while (iter < iters_per_restart and evals < budget) : (iter += 1) {
            var bestD: i64 = std.math.maxInt(i64);
            var bestMove: Move = .{ .count = 1, .idx = .{ 0, 0, 0 }, .d = 0 };
            var anyD: i64 = std.math.maxInt(i64);
            var anyMove: Move = bestMove;
            var found = false;

            for (0..m) |i| {
                const idx = [_]usize{i};
                const d = probeMove(mode, n, idx[0..1], s[0..n], C[0..n]);
                evals += 1;
                const aspiration = (curE + d) < gbestE.*;
                const allowed = (tabu_until[i] <= iter) or aspiration;
                if (d < anyD) {
                    anyD = d;
                    anyMove = .{ .count = 1, .idx = .{ i, 0, 0 }, .d = d };
                }
                if (allowed and d < bestD) {
                    bestD = d;
                    bestMove = .{ .count = 1, .idx = .{ i, 0, 0 }, .d = d };
                    found = true;
                }
            }
            if (neigh != .single) {
                var kk: usize = 0;
                while (kk < m) : (kk += 1) {
                    const pa = rng.uintLessThan(usize, m);
                    var pb = rng.uintLessThan(usize, m);
                    var tries: u8 = 0;
                    while (pb == pa and tries < 4) : (tries += 1) pb = rng.uintLessThan(usize, m);
                    if (pb == pa) continue;
                    const idx = [_]usize{ pa, pb };
                    const d = probeMove(mode, n, idx[0..2], s[0..n], C[0..n]);
                    evals += 1;
                    const aspiration = (curE + d) < gbestE.*;
                    const allowed = (tabu_until[pa] <= iter and tabu_until[pb] <= iter) or aspiration;
                    if (d < anyD) {
                        anyD = d;
                        anyMove = .{ .count = 2, .idx = .{ pa, pb, 0 }, .d = d };
                    }
                    if (allowed and d < bestD) {
                        bestD = d;
                        bestMove = .{ .count = 2, .idx = .{ pa, pb, 0 }, .d = d };
                        found = true;
                    }
                }
            }
            if (neigh == .triple) {
                var kk: usize = 0;
                const w = @max(window, 1);
                while (kk < m) : (kk += 1) {
                    const pa = rng.uintLessThan(usize, m);
                    const g1 = 1 + rng.uintLessThan(usize, w);
                    const g2 = 1 + rng.uintLessThan(usize, w);
                    const pb = (pa + g1) % m;
                    const pc = (pb + g2) % m;
                    if (pa == pb or pb == pc or pa == pc) continue;
                    const idx = [_]usize{ pa, pb, pc };
                    const d = probeMove(mode, n, idx[0..3], s[0..n], C[0..n]);
                    evals += 1;
                    const aspiration = (curE + d) < gbestE.*;
                    const allowed = (tabu_until[pa] <= iter and tabu_until[pb] <= iter and tabu_until[pc] <= iter) or aspiration;
                    if (d < anyD) {
                        anyD = d;
                        anyMove = .{ .count = 3, .idx = .{ pa, pb, pc }, .d = d };
                    }
                    if (allowed and d < bestD) {
                        bestD = d;
                        bestMove = .{ .count = 3, .idx = .{ pa, pb, pc }, .d = d };
                        found = true;
                    }
                }
            }
            if (!found) {
                bestD = anyD;
                bestMove = anyMove;
            }
            const committed_d = applyMoveOnce(mode, n, bestMove.idx[0..bestMove.count], s[0..n], C[0..n]);
            curE += committed_d;
            const tenure_span = @max(2, m / tp.tenure_span_denom);
            const tenure = iter + tp.tenure_base + rng.uintLessThan(u64, tenure_span);
            for (bestMove.idx[0..bestMove.count]) |ix| tabu_until[ix] = tenure;
            if (curE < gbestE.*) {
                gbestE.* = curE;
                @memcpy(gbest_seq[0..n], s[0..n]);
                try yields.append(.{ .n = n, .method = method_name, .evals = evals_offset + evals, .e = curE });
                last_improve = iter;
            }
            const stagnated = (iter - last_improve > stall_limit);
            const forced = (tp.forced_restart_iters != 0 and (iter - last_forced) >= tp.forced_restart_iters);
            if (stagnated or forced) {
                if (forced) last_forced = iter;
                break;
            }
        }
        const check = energyDirect(s[0..n]);
        if (check != curE) {
            std.debug.print("INTERNAL ERROR: incremental E={d} != direct E={d} at n={d} mode={s}\n", .{ curE, check, n, modeName(mode) });
            std.process.exit(3);
        }
        if (single_pass) break;
    }
    return evals;
}

// ---------------------------------------------------------------------------
// NEW in this file: memetic layer with a SELECTABLE crossover operator
// (round a/b only ever had two-point crossover). uniform crossover picks each
// bit independently from either parent — a genuinely different recombination
// operator, not just a parameter tweak.
// ---------------------------------------------------------------------------
const CrossMode = enum { two_point, uniform };

fn tournamentSelect(pop_e: []const i64, P: usize, rng: std.Random) usize {
    var best = rng.uintLessThan(usize, P);
    var best_e = pop_e[best];
    for (0..2) |_| {
        const cand = rng.uintLessThan(usize, P);
        if (pop_e[cand] < best_e) {
            best = cand;
            best_e = pop_e[cand];
        }
    }
    return best;
}

fn memeticRun(
    n: usize,
    budget: u64,
    seed: u64,
    gbest_seq: []i8,
    gbestE: *i64,
    yields: *std.ArrayList(Yield),
    evals_offset: u64,
    seed_hint: ?[]const i8,
    cross: CrossMode,
    method_name: []const u8,
    burst_name: []const u8,
) !u64 {
    const P: usize = 10;
    const burst_budget: u64 = 60 * @as(u64, n);
    const restart_every: u64 = 8;

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    var pop: [10][MaxN]i8 = undefined;
    var pop_e: [10]i64 = undefined;
    var evals: u64 = 0;

    for (0..P) |k| {
        if (seed_hint != null and k < P / 2) {
            @memcpy(pop[k][0..n], seed_hint.?[0..n]);
            var C: [MaxN]i64 = undefined;
            computeC(pop[k][0..n], C[0..n]);
            var e = energyFromC(C[0..n], n);
            const nflip = 1 + rng.uintLessThan(usize, 4);
            for (0..nflip) |_| {
                const i = rng.uintLessThan(usize, n);
                e += applyFlipDelta(pop[k][0..n], C[0..n], i, n);
            }
            pop_e[k] = e;
        } else {
            for (0..n) |i| pop[k][i] = if (rng.boolean()) 1 else -1;
            pop_e[k] = energyDirect(pop[k][0..n]);
        }
        if (pop_e[k] < gbestE.*) {
            gbestE.* = pop_e[k];
            @memcpy(gbest_seq[0..n], pop[k][0..n]);
        }
    }
    try yields.append(.{ .n = n, .method = method_name, .evals = evals_offset, .e = gbestE.* });

    var gen: u64 = 0;
    while (evals < budget) : (gen += 1) {
        for (0..P) |k| {
            var tmp_seq: [MaxN]i8 = undefined;
            @memcpy(tmp_seq[0..n], pop[k][0..n]);
            var local_best_e = pop_e[k];
            const used = try structTabuRun(
                n,
                .plain,
                .pair,
                0,
                default_tp,
                burst_budget,
                seed ^ (0x9E3779B97F4A7C15 *% (gen * 100 + k + 1)),
                tmp_seq[0..n],
                &local_best_e,
                yields,
                burst_name,
                evals_offset + evals,
                .{ .s = pop[k][0..n], .e = pop_e[k] },
                true,
            );
            evals += used;
            if (local_best_e <= pop_e[k]) {
                pop_e[k] = local_best_e;
                @memcpy(pop[k][0..n], tmp_seq[0..n]);
            }
            if (pop_e[k] < gbestE.*) {
                gbestE.* = pop_e[k];
                @memcpy(gbest_seq[0..n], pop[k][0..n]);
                try yields.append(.{ .n = n, .method = method_name, .evals = evals_offset + evals, .e = gbestE.* });
            }
            if (evals >= budget) break;
        }
        if (evals >= budget) break;

        var order: [10]usize = undefined;
        for (0..P) |k| order[k] = k;
        for (1..P) |i| {
            const key = order[i];
            var j = i;
            while (j > 0 and pop_e[order[j - 1]] > pop_e[key]) : (j -= 1) order[j] = order[j - 1];
            order[j] = key;
        }

        var next: [10][MaxN]i8 = undefined;
        var next_e: [10]i64 = undefined;
        @memcpy(next[0][0..n], pop[order[0]][0..n]);
        next_e[0] = pop_e[order[0]];

        var newk: usize = 1;
        while (newk < P) : (newk += 1) {
            const a = tournamentSelect(&pop_e, P, rng);
            const b = tournamentSelect(&pop_e, P, rng);
            var child: [MaxN]i8 = undefined;
            switch (cross) {
                .two_point => {
                    var c1 = rng.uintLessThan(usize, n);
                    var c2 = rng.uintLessThan(usize, n);
                    if (c1 > c2) std.mem.swap(usize, &c1, &c2);
                    for (0..n) |i| {
                        if (i >= c1 and i < c2) child[i] = pop[b][i] else child[i] = pop[a][i];
                    }
                },
                .uniform => {
                    for (0..n) |i| {
                        child[i] = if (rng.boolean()) pop[a][i] else pop[b][i];
                    }
                },
            }
            if (rng.boolean() and rng.boolean()) { // ~25% mutation
                const mi = rng.uintLessThan(usize, n);
                child[mi] = -child[mi];
            }
            @memcpy(next[newk][0..n], child[0..n]);
            next_e[newk] = energyDirect(child[0..n]);
            if (next_e[newk] < gbestE.*) {
                gbestE.* = next_e[newk];
                @memcpy(gbest_seq[0..n], child[0..n]);
                try yields.append(.{ .n = n, .method = method_name, .evals = evals_offset + evals, .e = gbestE.* });
            }
        }

        if (gen % restart_every == (restart_every - 1)) {
            for (0..P) |k| {
                @memcpy(pop[k][0..n], next[k][0..n]);
                pop_e[k] = next_e[k];
            }
            var order2: [10]usize = undefined;
            for (0..P) |k| order2[k] = k;
            for (1..P) |i| {
                const key = order2[i];
                var j = i;
                while (j > 0 and pop_e[order2[j - 1]] > pop_e[key]) : (j -= 1) order2[j] = order2[j - 1];
                order2[j] = key;
            }
            const worst1 = order2[P - 1];
            const worst2 = order2[P - 2];
            for ([_]usize{ worst1, worst2 }) |wk| {
                for (0..n) |i| pop[wk][i] = if (rng.boolean()) 1 else -1;
                pop_e[wk] = energyDirect(pop[wk][0..n]);
            }
        } else {
            for (0..P) |k| {
                @memcpy(pop[k][0..n], next[k][0..n]);
                pop_e[k] = next_e[k];
            }
        }
    }
    return evals;
}

// ---------------------------------------------------------------------------
// Arm: one diverse search strategy in the pool. kind selects tabu vs memetic
// dispatch; the rest of the fields configure that kind.
// ---------------------------------------------------------------------------
const ArmKind = enum { tabu, memetic };

const Arm = struct {
    name: []const u8,
    kind: ArmKind,
    mode: Mode = .plain,
    neigh: Neigh = .pair,
    window: usize = 0,
    tp: TabuParams = default_tp,
    cross: CrossMode = .two_point,
    burst_name: []const u8 = "burst",
    seed_base: u64,
};

/// Dispatch one arm for `budget` evals. Per established precedent (round b never
/// warm-started ANY tabu arm across arms/rounds, only the trailing memetic step
/// warm-started its population): tabu arms ALWAYS start from a fresh random
/// structural-manifold init (seed_state=null) — this also sidesteps a real
/// correctness pitfall: warm-starting a skew/mirror-restricted arm from a
/// plain-mode best sequence would silently break the structural invariant the
/// arm is supposed to be testing. Memetic arms DO warm-start half their
/// population from the current shared best (as round b established), since
/// memetic always operates in plain (unrestricted) space.
fn runArm(
    n: usize,
    arm: Arm,
    budget: u64,
    round_seed: u64,
    gbest_seq: []i8,
    gbestE: *i64,
    yields: *std.ArrayList(Yield),
    evals_offset: u64,
) !u64 {
    const has_best = gbestE.* != std.math.maxInt(i64);
    switch (arm.kind) {
        .tabu => return structTabuRun(n, arm.mode, arm.neigh, arm.window, arm.tp, budget, arm.seed_base ^ round_seed, gbest_seq, gbestE, yields, arm.name, evals_offset, null, false),
        .memetic => return memeticRun(n, budget, arm.seed_base ^ round_seed, gbest_seq, gbestE, yields, evals_offset, if (has_best) gbest_seq[0..n] else null, arm.cross, arm.name, arm.burst_name),
    }
}

/// Build the full 9-arm diversity pool for length n. Every one of the 5
/// diversity axes named in the brief is represented:
///   tenure:        arm 0 (long) vs arm 1 (short)
///   neighborhood:  arm 2 (triple, window 4) vs arm 3 (triple, window 14)
///   restart policy: arm 4 (aggressive stagnation limit) vs arm 5 (periodic forced restart)
///   structural restriction: arm 6 (skew_odd for odd n / mirror_altern for even n)
///   memetic + crossover: arm 7 (uniform) vs arm 8 (two-point)
fn buildFullPool(n: usize) [9]Arm {
    const odd = n % 2 == 1;
    const struct_mode: Mode = if (odd) .skew_odd else .mirror_altern;
    return [9]Arm{
        .{ .name = "tabu_pair_long_tenure", .kind = .tabu, .mode = .plain, .neigh = .pair, .tp = .{ .tenure_base = 8, .tenure_span_denom = 2, .stall_mult = 60, .forced_restart_iters = 0 }, .seed_base = 0xA001 },
        .{ .name = "tabu_pair_short_tenure", .kind = .tabu, .mode = .plain, .neigh = .pair, .tp = .{ .tenure_base = 1, .tenure_span_denom = 8, .stall_mult = 60, .forced_restart_iters = 0 }, .seed_base = 0xA002 },
        .{ .name = "tabu_triple_w4", .kind = .tabu, .mode = .plain, .neigh = .triple, .window = 4, .tp = default_tp, .seed_base = 0xA003 },
        .{ .name = "tabu_triple_w14", .kind = .tabu, .mode = .plain, .neigh = .triple, .window = 14, .tp = default_tp, .seed_base = 0xA004 },
        .{ .name = "tabu_pair_aggr_restart", .kind = .tabu, .mode = .plain, .neigh = .pair, .tp = .{ .tenure_base = 4, .tenure_span_denom = 4, .stall_mult = 15, .forced_restart_iters = 0 }, .seed_base = 0xA005 },
        .{ .name = "tabu_pair_periodic_restart", .kind = .tabu, .mode = .plain, .neigh = .pair, .tp = .{ .tenure_base = 4, .tenure_span_denom = 4, .stall_mult = 60, .forced_restart_iters = 800 }, .seed_base = 0xA006 },
        .{ .name = "structural", .kind = .tabu, .mode = struct_mode, .neigh = .pair, .tp = default_tp, .seed_base = 0xA007 },
        .{ .name = "memetic_uniform", .kind = .memetic, .cross = .uniform, .burst_name = "memetic_uniform_burst", .seed_base = 0xA008 },
        .{ .name = "memetic_twopoint", .kind = .memetic, .cross = .two_point, .burst_name = "memetic_twopoint_burst", .seed_base = 0xA009 },
    };
}

// pool3 = one representative of each METHOD FAMILY (tabu / structural / memetic),
// picked to be each family's strongest single representative from the full pool.
fn buildPool3(n: usize) [3]Arm {
    const full = buildFullPool(n);
    return [3]Arm{ full[0], full[6], full[8] }; // tabu_pair_long_tenure, structural, memetic_twopoint
}

const AllocPolicy = enum { equal, adaptive };

const ConfigResult = struct {
    evals_used: u64,
    winner: []const u8,
    arms_contributed: usize,
    pool_size: usize,
};

/// Run a pool of arms against a FRESH (gbestE = +inf) shared best, for `rounds`
/// rounds, splitting `total_budget` across rounds and arms per `policy`.
/// EQUAL: every round splits its share evenly across all arms (round b's
///   mechanism, generalized to explicit rounds for comparability).
/// ADAPTIVE: round 0 splits evenly (no history yet); every later round splits
///   half its share evenly (a floor, so no arm is ever fully starved) and half
///   proportional to each arm's OWN global-best improvement in the PREVIOUS
///   round (falling back to even split if no arm improved last round) — this
///   is the direct implementation of "concentrate on whichever strategy is
///   improving."
fn runPool(
    n: usize,
    arms: []const Arm,
    policy: AllocPolicy,
    total_budget: u64,
    rounds: u64,
    base_seed: u64,
    gbest_seq: []i8,
    gbestE: *i64,
    yields: *std.ArrayList(Yield),
) !ConfigResult {
    const len = arms.len;
    var total_gain: [16]i64 = [_]i64{0} ** 16;
    var improve_count: [16]u32 = [_]u32{0} ** 16;
    var last_gain: [16]i64 = [_]i64{0} ** 16;
    var evals_total: u64 = 0;
    const round_budget = total_budget / rounds;

    var r: u64 = 0;
    while (r < rounds) : (r += 1) {
        const is_last_round = (r == rounds - 1);
        const this_round_budget = if (is_last_round) (total_budget - round_budget * (rounds - 1)) else round_budget;

        var weight: [16]f64 = undefined;
        if (policy == .equal or r == 0) {
            for (0..len) |i| weight[i] = 1.0 / @as(f64, @floatFromInt(len));
        } else {
            var sum_gain: i64 = 0;
            for (0..len) |i| sum_gain += last_gain[i];
            if (sum_gain <= 0) {
                for (0..len) |i| weight[i] = 1.0 / @as(f64, @floatFromInt(len));
            } else {
                const floor_share = 0.5 / @as(f64, @floatFromInt(len));
                for (0..len) |i| {
                    const adaptive_share = 0.5 * (@as(f64, @floatFromInt(last_gain[i])) / @as(f64, @floatFromInt(sum_gain)));
                    weight[i] = floor_share + adaptive_share;
                }
            }
        }

        var assigned: u64 = 0;
        var budgets: [16]u64 = undefined;
        for (0..len) |i| {
            budgets[i] = @intFromFloat(@floor(weight[i] * @as(f64, @floatFromInt(this_round_budget))));
            assigned += budgets[i];
        }
        if (this_round_budget > assigned) budgets[len - 1] += (this_round_budget - assigned);

        for (0..len) |i| {
            if (budgets[i] == 0) continue;
            const before = gbestE.*;
            const round_seed = base_seed ^ (r *% 0x9E3779B97F4A7C15) ^ (@as(u64, @intCast(i)) *% 0xBF58476D1CE4E5B9);
            const used = try runArm(n, arms[i], budgets[i], round_seed, gbest_seq, gbestE, yields, evals_total);
            evals_total += used;
            const gain: i64 = if (before > gbestE.*) before - gbestE.* else 0;
            last_gain[i] = gain;
            if (gain > 0) {
                total_gain[i] += gain;
                improve_count[i] += 1;
            }
        }
    }

    var winner: []const u8 = "none";
    var best_gain: i64 = -1;
    var best_count: u32 = 0;
    var contributed: usize = 0;
    for (0..len) |i| {
        if (total_gain[i] > 0) contributed += 1;
        if (total_gain[i] > best_gain or (total_gain[i] == best_gain and improve_count[i] > best_count)) {
            best_gain = total_gain[i];
            best_count = improve_count[i];
            winner = arms[i].name;
        }
    }
    return .{ .evals_used = evals_total, .winner = winner, .arms_contributed = contributed, .pool_size = len };
}

// ---------------------------------------------------------------------------
const ExpRow = struct {
    n: usize,
    config: []const u8,
    pool_size: usize,
    alloc_policy: []const u8,
    total_budget: u64,
    evals_used: u64,
    best_e: i64,
    winner: []const u8,
    arms_contributed: usize,
    seq: [MaxN]i8,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const A = arena.allocator();
    const out = std.io.getStdOut().writer();

    var div: u64 = 1;
    var rounds: u64 = 6;
    var budget_t: u64 = 50_000_000;
    var ns_list = std.ArrayList(usize).init(A);
    var csv_path: []const u8 = "results/labs_swarm_2026_07_10.csv";
    var yield_csv_path: []const u8 = "results/labs_swarm_yield_2026_07_10.csv";
    var json_path: []const u8 = "results/labs_swarm_claims_2026_07_10.json";

    var it = try std.process.argsWithAllocator(A);
    defer it.deinit();
    _ = it.next();
    while (it.next()) |a| {
        if (std.mem.eql(u8, a, "--quick")) {
            div = 500;
        } else if (std.mem.startsWith(u8, a, "--div=")) {
            div = try std.fmt.parseInt(u64, a["--div=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--rounds=")) {
            rounds = try std.fmt.parseInt(u64, a["--rounds=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--budget=")) {
            budget_t = try std.fmt.parseInt(u64, a["--budget=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--ns=")) {
            var pieces = std.mem.splitScalar(u8, a["--ns=".len..], ',');
            while (pieces.next()) |p| {
                if (p.len == 0) continue;
                try ns_list.append(try std.fmt.parseInt(usize, p, 10));
            }
        } else if (std.mem.startsWith(u8, a, "--csv=")) {
            csv_path = a["--csv=".len..];
        } else if (std.mem.startsWith(u8, a, "--yield-csv=")) {
            yield_csv_path = a["--yield-csv=".len..];
        } else if (std.mem.startsWith(u8, a, "--json=")) {
            json_path = a["--json=".len..];
        }
    }

    const ns_default = [_]usize{ 44, 48, 50, 52, 54, 56, 58, 60, 61, 62, 63, 64 };
    const ns: []const usize = if (ns_list.items.len > 0) ns_list.items else ns_default[0..];
    const T: u64 = budget_t / div;

    try out.print("=== LABS swarm campaign 2026-07-10d: diversity vs concentration ===\n", .{});
    try out.print("targets: {any}\n", .{ns});
    try out.print("total budget per (N,config) = {d} evals; rounds={d}; div={d}\n\n", .{ T, rounds, div });
    try out.print("{s:>3} {s:>20} {s:>5} {s:>9} {s:>9} {s:>9} {s:>22} {s:>6}\n", .{ "N", "config", "pool", "evals", "best_E", "best_F", "winner_arm", "#contr" });

    var timer = try std.time.Timer.start();
    var yields = std.ArrayList(Yield).init(A);
    var rows = std.ArrayList(ExpRow).init(A);

    // overall best-per-length tracking (for the claims file: the single best
    // sequence any config found, regardless of which one)
    var overall_best_e: [MaxN + 1]i64 = undefined;
    var overall_best_seq: [MaxN + 1][MaxN]i8 = undefined;
    var overall_best_config: [MaxN + 1][]const u8 = undefined;
    for (0..MaxN + 1) |i| overall_best_e[i] = std.math.maxInt(i64);

    for (ns) |n| {
        const full_pool = buildFullPool(n);
        const pool3 = buildPool3(n);

        const ConfigSpec = struct { name: []const u8, alloc: []const u8, pool_kind: enum { one, three, nine }, policy: AllocPolicy, seed: u64 };
        const specs = [_]ConfigSpec{
            .{ .name = "concentrated_1", .alloc = "n/a", .pool_kind = .one, .policy = .equal, .seed = 0xC0FFEE },
            .{ .name = "pool3_equal", .alloc = "equal", .pool_kind = .three, .policy = .equal, .seed = 0xD00D01 },
            .{ .name = "pool3_adaptive", .alloc = "adaptive", .pool_kind = .three, .policy = .adaptive, .seed = 0xD00D02 },
            .{ .name = "pool9_equal", .alloc = "equal", .pool_kind = .nine, .policy = .equal, .seed = 0xD00D03 },
            .{ .name = "pool9_adaptive", .alloc = "adaptive", .pool_kind = .nine, .policy = .adaptive, .seed = 0xD00D04 },
        };

        for (specs) |sp| {
            var gbestE: i64 = std.math.maxInt(i64);
            var gseq: [MaxN]i8 = undefined;
            const res = switch (sp.pool_kind) {
                .one => try runPool(n, &[_]Arm{full_pool[0]}, .equal, T, 1, sp.seed ^ @as(u64, n), gseq[0..n], &gbestE, &yields),
                .three => try runPool(n, &pool3, sp.policy, T, rounds, sp.seed ^ @as(u64, n), gseq[0..n], &gbestE, &yields),
                .nine => try runPool(n, &full_pool, sp.policy, T, rounds, sp.seed ^ @as(u64, n), gseq[0..n], &gbestE, &yields),
            };
            try yields.append(.{ .n = n, .method = sp.name, .evals = res.evals_used, .e = gbestE });

            const echk = energyDirect(gseq[0..n]);
            if (echk != gbestE) {
                std.debug.print("INTERNAL ERROR: stored best seq E={d} != claimed {d} at n={d} config={s}\n", .{ echk, gbestE, n, sp.name });
                std.process.exit(3);
            }

            var row: ExpRow = .{ .n = n, .config = sp.name, .pool_size = res.pool_size, .alloc_policy = sp.alloc, .total_budget = T, .evals_used = res.evals_used, .best_e = gbestE, .winner = res.winner, .arms_contributed = res.arms_contributed, .seq = undefined };
            @memcpy(row.seq[0..n], gseq[0..n]);
            try rows.append(row);

            try out.print("{d:>3} {s:>20} {d:>5} {d:>9} {d:>9} {d:>9.4} {s:>22} {d:>6}\n", .{ n, sp.name, res.pool_size, res.evals_used, gbestE, merit(n, gbestE), res.winner, res.arms_contributed });

            if (gbestE < overall_best_e[n]) {
                overall_best_e[n] = gbestE;
                @memcpy(overall_best_seq[n][0..n], gseq[0..n]);
                overall_best_config[n] = sp.name;
            }
        }

        const mr = missRow(n);
        const swarm_best = overall_best_e[n];
        try out.print("  -> n={d}: swarm_best E={d} (config={s}) vs round_a E={d} vs round_b E={d} vs known E={d}\n\n", .{ n, swarm_best, overall_best_config[n], mr.round_a_e, mr.round_b_e, mr.known_e });
        if (swarm_best < mr.known_e) {
            try out.print("  *** EXTRAORDINARY-NEEDS-SCRUTINY at n={d}: swarm E={d} BELOW recalled best-known {d}. DO NOT declare victory — re-verify independently and suspect the recalled table first. ***\n\n", .{ n, swarm_best, mr.known_e });
        }
    }

    const elapsed_ms = timer.read() / std.time.ns_per_ms;
    try out.print("total wall time: {d} ms (single-threaded)\n", .{elapsed_ms});

    // ---- write main results CSV: one row per (N, config) — the
    // breadth-vs-concentration curve.
    {
        var f = try std.fs.cwd().createFile(csv_path, .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.print("N,config,pool_size,alloc_policy,total_budget,evals_used,best_E,best_F,winner_arm,arms_contributed\n", .{});
        for (rows.items) |rw| {
            try w.print("{d},{s},{d},{s},{d},{d},{d},{d:.6},{s},{d}\n", .{ rw.n, rw.config, rw.pool_size, rw.alloc_policy, rw.total_budget, rw.evals_used, rw.best_e, merit(rw.n, rw.best_e), rw.winner, rw.arms_contributed });
        }
        try bw.flush();
    }

    // ---- write auxiliary yield CSV (every global-best improvement event)
    {
        var f = try std.fs.cwd().createFile(yield_csv_path, .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.print("N,method,evals,best_E,best_F\n", .{});
        for (yields.items) |y| {
            try w.print("{d},{s},{d},{d},{d:.6}\n", .{ y.n, y.method, y.evals, y.e, merit(y.n, y.e) });
        }
        try bw.flush();
    }

    // ---- write claims JSON (overall best sequence per N, across all configs)
    {
        var f = try std.fs.cwd().createFile(json_path, .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.print("{{\n  \"date\": \"2026-07-10\",\n  \"note\": \"round d swarm campaign; overall best per N across 5 configs; all HEURISTIC\",\n  \"claims\": [\n", .{});
        for (ns, 0..) |n, ci| {
            try w.print("    {{\"n\": {d}, \"status\": \"HEURISTIC\", \"E\": {d}, \"F\": {d:.6}, \"won_by_config\": \"{s}\", \"seq\": [", .{ n, overall_best_e[n], merit(n, overall_best_e[n]), overall_best_config[n] });
            for (overall_best_seq[n][0..n], 0..) |x, i| {
                if (i > 0) try w.print(",", .{});
                try w.print("{d}", .{x});
            }
            try w.print("]}}{s}\n", .{if (ci + 1 < ns.len) "," else ""});
        }
        try w.print("  ]\n}}\n", .{});
        try bw.flush();
    }

    try out.print("\nwrote {s}, {s}, {s}\n", .{ csv_path, yield_csv_path, json_path });
    try out.print("verify independently: <labs_check binary> {s}\n", .{json_path});
}
