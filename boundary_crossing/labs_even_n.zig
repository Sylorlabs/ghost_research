//! labs_even_n.zig — round 2026-07-10b: richer moves for the 12 LABS lengths that
//! yesterday's campaign (labs_campaign.zig, see docs/research/labs_campaign.md)
//! could not close: even N in {44,48,50,52,54,56,58,60,62,64} plus odd N in {61,63}.
//!
//! Diagnosis carried over from yesterday: the skew-symmetric restriction (mirror
//! s_{c+d} = (-1)^d s_{c-d} around an INTEGER center c=(N-1)/2) only exists for odd
//! N, and it is exactly what closed every odd-N gap up to 59 in one run. This file:
//!   (a) adds a memetic layer (tabu bursts + population crossover + restarts) on
//!       top of the unrestricted search, to see if move-richness alone helps;
//!   (b) adds pair-flip and (window-bounded) triple-flip neighborhoods with
//!       incremental O(N) energy updates, layered onto BOTH the unrestricted
//!       search and every structural search below;
//!   (c) tests even-N structural-restriction HYPOTHESES that generalize the
//!       skew idea to even N via a full mirror pairing (i, N-1-i) with no
//!       unpaired center element (N even => N/2 exact pairs, N/2 free bits):
//!         - mirror_altern: sign alternates by free-index parity (closest
//!           structural analogue of skew-symmetry for even N)
//!         - palindrome:    sign is constant +1 (s_i = s_{N-1-i})
//!         - antipalindrome: sign is constant -1 (s_i = -s_{N-1-i})
//!       For the two ODD misses (61, 63) the EXACT classical skew-symmetric
//!       restriction (copied faithfully from labs_campaign.zig's tabuRun(skew=true))
//!       is reused and enriched with pair/triple neighborhoods, instead of the
//!       even-N mirror hypotheses (which don't apply to odd N).
//!   These are HYPOTHESES, not established methods for even N — this file measures
//!   their yield exactly as yesterday's doc measured skew vs plain, and reports
//!   honestly if a hypothesis doesn't help.
//!
//! Energy/flip core (computeC/energyFromC/energyDirect/applyFlipDelta/merit) is
//! COPIED VERBATIM from labs_campaign.zig (read-only reuse, per campaign instructions)
//! so this file is fully standalone and shares no runtime state with the campaign.
//!
//! Move accounting convention (same as yesterday): 1 "eval" = 1 neighbor candidate
//! considered, regardless of how many O(N) passes it costs internally (yesterday's
//! skew pair-flip probe already cost ~4 O(N) passes and counted as 1 eval; here,
//! a single free-flip in a paired structural mode costs ~4 O(N) passes (apply+probe+
//! revert+revert), a pair-of-free-index move ~8 passes, a window triple ~12 passes).
//! Budgets below are chosen so total evals per N are the same ORDER OF MAGNITUDE as
//! yesterday's (tens of millions), so gains are attributable to move richness/
//! structure, not to a bigger budget.
//!
//! Build (from repo root):
//!   zig build-exe boundary_crossing/labs_even_n.zig -O ReleaseFast \
//!       -femit-bin=/tmp/claude-1000/labs_even_n
//!   /tmp/claude-1000/labs_even_n            (add --quick for a fast smoke run)
//!
//! Outputs:
//!   results/labs_even_n_2026_07_10.csv          yield curves (N,method,evals,E,F)
//!   results/labs_even_n_claims_2026_07_10.json  claims for scripts/zig/labs_check.zig

const std = @import("std");

const MaxN: usize = 64;

// ---------------------------------------------------------------------------
// the 12 miss lengths from yesterday's campaign, with yesterday's best E and
// the best-known E (same provenance-tagged table as labs_campaign.zig: N in
// [25,64] recalled from Packebusch & Mertens 2016, MEDIUM confidence per that
// doc — reused verbatim, not re-derived here).
// ---------------------------------------------------------------------------
const MissRow = struct { n: usize, yesterday_e: i64, known_e: i64 };
const miss_table = [_]MissRow{
    .{ .n = 44, .yesterday_e = 126, .known_e = 122 },
    .{ .n = 48, .yesterday_e = 160, .known_e = 140 },
    .{ .n = 50, .yesterday_e = 161, .known_e = 153 },
    .{ .n = 52, .yesterday_e = 174, .known_e = 166 },
    .{ .n = 54, .yesterday_e = 199, .known_e = 175 },
    .{ .n = 56, .yesterday_e = 208, .known_e = 192 },
    .{ .n = 58, .yesterday_e = 229, .known_e = 197 },
    .{ .n = 60, .yesterday_e = 254, .known_e = 218 },
    .{ .n = 61, .yesterday_e = 230, .known_e = 226 },
    .{ .n = 62, .yesterday_e = 283, .known_e = 235 },
    .{ .n = 63, .yesterday_e = 271, .known_e = 207 },
    .{ .n = 64, .yesterday_e = 312, .known_e = 208 },
};

fn yesterdayE(n: usize) i64 {
    for (miss_table) |r| if (r.n == n) return r.yesterday_e;
    unreachable;
}
fn knownE(n: usize) i64 {
    for (miss_table) |r| if (r.n == n) return r.known_e;
    unreachable;
}

// ---------------------------------------------------------------------------
// energy machinery — COPIED VERBATIM from boundary_crossing/labs_campaign.zig.
// Deliberately identical so any difference in outcome is due to MOVES, not a
// different (possibly buggy) energy engine.
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

/// flip position i, updating C in place; returns delta E. O(N).
/// Applying twice at the same i restores s and C exactly regardless of any
/// OTHER position changes applied in between (C is always the true incremental
/// state for the CURRENT s, not path-dependent) — this is the algebraic fact
/// this whole file's composite-move machinery relies on.
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

// ---------------------------------------------------------------------------
// yield-curve recording
// ---------------------------------------------------------------------------
const Yield = struct { n: usize, method: []const u8, evals: u64, e: i64 };

// ---------------------------------------------------------------------------
// structural modes: each maps a "free index" i in [0,m) to a raw position,
// with an optional mirror raw position (n-1-i, or 2c-i for classical odd-N
// skew) that must move in lockstep to stay on the constraint manifold.
// KEY FACT (checked by hand): flipping s_i AND its mirror together preserves
// s_mirror = sign * s_i for EITHER sign — sign only matters for deriving the
// mirror value at INIT time, not for which positions a flip must touch.
// ---------------------------------------------------------------------------
const Mode = enum {
    plain, // unrestricted: m=n, no mirror. "richer moves, no structure" arm.
    skew_odd, // classical skew-symmetry, ODD n only (copied semantics from campaign)
    mirror_altern, // even-N analogue: pairs (i,n-1-i), alternating sign by index parity
    mirror_pos, // even-N: s_i = +s_{n-1-i}  (palindrome)
    mirror_neg, // even-N: s_i = -s_{n-1-i}  (anti-palindrome)
};

fn freeCount(mode: Mode, n: usize) usize {
    return switch (mode) {
        .plain => n,
        .skew_odd => (n + 1) / 2,
        .mirror_altern, .mirror_pos, .mirror_neg => n / 2,
    };
}

fn mirrorOf(mode: Mode, n: usize, i: usize) ?usize {
    return switch (mode) {
        .plain => null,
        .skew_odd => blk: {
            const c = (n - 1) / 2;
            break :blk if (i == c) null else 2 * c - i;
        },
        .mirror_altern, .mirror_pos, .mirror_neg => n - 1 - i,
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
        .mirror_pos => 1,
        .mirror_neg => -1,
    };
}

fn modeName(mode: Mode) []const u8 {
    return switch (mode) {
        .plain => "plain",
        .skew_odd => "skew",
        .mirror_altern => "mirror_altern",
        .mirror_pos => "palindrome",
        .mirror_neg => "antipalindrome",
    };
}

/// random init respecting the structural manifold: randomize the free half
/// (raw positions [0,m)), then derive every mirrored raw position from it.
fn initStruct(mode: Mode, n: usize, s: []i8, rng: std.Random) void {
    const m = freeCount(mode, n);
    for (0..m) |i| s[i] = if (rng.boolean()) 1 else -1;
    for (0..m) |i| {
        if (mirrorOf(mode, n, i)) |j| s[j] = signOf(mode, n, i) * s[i];
    }
}

/// flip free-index i (and its mirror, if any). O(N) or O(2N).
fn applyFreeFlip(mode: Mode, n: usize, i: usize, s: []i8, C: []i64) i64 {
    var d = applyFlipDelta(s, C, i, n);
    if (mirrorOf(mode, n, i)) |j| d += applyFlipDelta(s, C, j, n);
    return d;
}

/// apply a composite move (1-3 free indices) once — commits.
fn applyMoveOnce(mode: Mode, n: usize, idx: []const usize, s: []i8, C: []i64) i64 {
    var d: i64 = 0;
    for (idx) |i| d += applyFreeFlip(mode, n, i, s, C);
    return d;
}

/// probe a composite move: apply, then apply again to revert (self-inverse
/// regardless of order/overlap — see the KEY FACT note above). Returns the
/// net energy delta of the (uncommitted) move.
fn probeMove(mode: Mode, n: usize, idx: []const usize, s: []i8, C: []i64) i64 {
    const d = applyMoveOnce(mode, n, idx, s, C);
    _ = applyMoveOnce(mode, n, idx, s, C);
    return d;
}

const Neigh = enum { single, pair, triple };

const Move = struct { count: u8, idx: [3]usize, d: i64 };

// ---------------------------------------------------------------------------
// generalized tabu search: structural mode x neighborhood richness.
// Single-threaded. Multi-restart on stagnation; aspiration = move allowed
// while tabu if it would beat the global best. `single_pass`, if true, skips
// the stagnation-triggered restart (used by the memetic layer for short
// bursts seeded from a caller-supplied starting sequence).
// ---------------------------------------------------------------------------
fn structTabuRun(
    n: usize,
    mode: Mode,
    neigh: Neigh,
    window: usize,
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
    const stall_limit: u64 = 60 * @as(u64, n);
    const iters_per_restart: u64 = 4000;
    var first_pass = true;

    while (evals < budget) {
        // ---- (re)initialize
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
        while (iter < iters_per_restart and evals < budget) : (iter += 1) {
            var bestD: i64 = std.math.maxInt(i64);
            var bestMove: Move = .{ .count = 1, .idx = .{ 0, 0, 0 }, .d = 0 };
            var anyD: i64 = std.math.maxInt(i64);
            var anyMove: Move = bestMove;
            var found = false;

            // singles
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
            // sampled pairs
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
            // sampled window-bounded triples
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
            // ---- commit
            const committed_d = applyMoveOnce(mode, n, bestMove.idx[0..bestMove.count], s[0..n], C[0..n]);
            curE += committed_d;
            const tenure = iter + 4 + rng.uintLessThan(u64, @max(2, m / 4));
            for (bestMove.idx[0..bestMove.count]) |ix| tabu_until[ix] = tenure;
            if (curE < gbestE.*) {
                gbestE.* = curE;
                @memcpy(gbest_seq[0..n], s[0..n]);
                try yields.append(.{ .n = n, .method = method_name, .evals = evals_offset + evals, .e = curE });
                last_improve = iter;
            }
            if (iter - last_improve > stall_limit) break;
        }
        // ---- internal soundness check
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
// memetic layer: population of individuals in PLAIN (unrestricted) space,
// each locally optimized by a short single/pair tabu burst per generation;
// tournament selection + two-point crossover + light mutation build the next
// generation; elitism keeps the best; stagnant worst-half gets replaced by
// fresh random restarts every `restart_every` generations (the "restarts"
// half of "population crossover/restarts").
// ---------------------------------------------------------------------------
fn memeticRun(
    n: usize,
    budget: u64,
    seed: u64,
    gbest_seq: []i8,
    gbestE: *i64,
    yields: *std.ArrayList(Yield),
    evals_offset: u64,
    seed_hint: ?[]const i8, // optional warm-start sequence (e.g. best-so-far)
) !u64 {
    const P: usize = 10;
    const burst_budget: u64 = 60 * @as(u64, n); // evals per individual per generation
    const restart_every: u64 = 8;

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    var pop: [10][MaxN]i8 = undefined;
    var pop_e: [10]i64 = undefined;
    var evals: u64 = 0;

    // ---- seed population: half from a perturbed warm-start hint (if given), half random
    for (0..P) |k| {
        if (seed_hint != null and k < P / 2) {
            @memcpy(pop[k][0..n], seed_hint.?[0..n]);
            var C: [MaxN]i64 = undefined;
            computeC(pop[k][0..n], C[0..n]);
            var e = energyFromC(C[0..n], n);
            // diversify with a few random flips
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
    try yields.append(.{ .n = n, .method = "memetic", .evals = evals_offset, .e = gbestE.* });

    var gen: u64 = 0;
    while (evals < budget) : (gen += 1) {
        // ---- local search burst on every individual (plain, single+pair)
        for (0..P) |k| {
            var tmp_seq: [MaxN]i8 = undefined;
            @memcpy(tmp_seq[0..n], pop[k][0..n]);
            var local_best_e = pop_e[k];
            const used = try structTabuRun(
                n,
                .plain,
                .pair,
                0,
                burst_budget,
                seed ^ (0x9E3779B97F4A7C15 *% (gen * 100 + k + 1)),
                tmp_seq[0..n],
                &local_best_e,
                yields,
                "memetic_burst",
                evals_offset + evals,
                .{ .s = pop[k][0..n], .e = pop_e[k] },
                true, // single_pass: no internal restart, just improve from seed
            );
            evals += used;
            if (local_best_e <= pop_e[k]) {
                pop_e[k] = local_best_e;
                @memcpy(pop[k][0..n], tmp_seq[0..n]);
            }
            if (pop_e[k] < gbestE.*) {
                gbestE.* = pop_e[k];
                @memcpy(gbest_seq[0..n], pop[k][0..n]);
                try yields.append(.{ .n = n, .method = "memetic", .evals = evals_offset + evals, .e = gbestE.* });
            }
            if (evals >= budget) break;
        }
        if (evals >= budget) break;

        // ---- rank population (simple insertion sort over 10 elements)
        var order: [10]usize = undefined;
        for (0..P) |k| order[k] = k;
        for (1..P) |i| {
            const key = order[i];
            var j = i;
            while (j > 0 and pop_e[order[j - 1]] > pop_e[key]) : (j -= 1) order[j] = order[j - 1];
            order[j] = key;
        }

        // ---- build next generation: elitism + tournament crossover
        var next: [10][MaxN]i8 = undefined;
        var next_e: [10]i64 = undefined;
        @memcpy(next[0][0..n], pop[order[0]][0..n]);
        next_e[0] = pop_e[order[0]];

        var newk: usize = 1;
        while (newk < P) : (newk += 1) {
            // tournament select 2 parents (size 3) from current population
            const a = tournamentSelect(&pop_e, P, rng);
            const b = tournamentSelect(&pop_e, P, rng);
            var child: [MaxN]i8 = undefined;
            var c1 = rng.uintLessThan(usize, n);
            var c2 = rng.uintLessThan(usize, n);
            if (c1 > c2) std.mem.swap(usize, &c1, &c2);
            for (0..n) |i| {
                if (i >= c1 and i < c2) child[i] = pop[b][i] else child[i] = pop[a][i];
            }
            // light mutation
            if (rng.boolean() and rng.boolean()) { // ~25%
                const mi = rng.uintLessThan(usize, n);
                child[mi] = -child[mi];
            }
            @memcpy(next[newk][0..n], child[0..n]);
            next_e[newk] = energyDirect(child[0..n]);
            if (next_e[newk] < gbestE.*) {
                gbestE.* = next_e[newk];
                @memcpy(gbest_seq[0..n], child[0..n]);
                try yields.append(.{ .n = n, .method = "memetic", .evals = evals_offset + evals, .e = gbestE.* });
            }
        }

        // ---- restart injection: every `restart_every` gens, replace the
        // worst 2 (excluding elite at slot 0) with fresh random individuals
        if (gen % restart_every == (restart_every - 1)) {
            for (0..P) |k| {
                @memcpy(pop[k][0..n], next[k][0..n]);
                pop_e[k] = next_e[k];
            }
            // rank again to find worst
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

// ---------------------------------------------------------------------------
// per-N experiment plan
// ---------------------------------------------------------------------------
const ExpSpec = struct { mode: Mode, neigh: Neigh, window: usize, budget: u64, seed: u64, name: []const u8 };

fn buildSpecs(n: usize, div: u64, out: *std.ArrayList(ExpSpec)) !void {
    const odd = n % 2 == 1;
    try out.append(.{ .mode = .plain, .neigh = .single, .window = 0, .budget = 5_000_000 / div, .seed = 0xA1 ^ @as(u64, n), .name = "plain_single_ctrl" });
    try out.append(.{ .mode = .plain, .neigh = .pair, .window = 0, .budget = 35_000_000 / div, .seed = 0xA2 ^ @as(u64, n), .name = "plain_pair" });
    try out.append(.{ .mode = .plain, .neigh = .triple, .window = 6, .budget = 25_000_000 / div, .seed = 0xA3 ^ @as(u64, n), .name = "plain_triple" });
    if (odd) {
        try out.append(.{ .mode = .skew_odd, .neigh = .pair, .window = 0, .budget = 35_000_000 / div, .seed = 0xB1 ^ @as(u64, n), .name = "skew_pair" });
        try out.append(.{ .mode = .skew_odd, .neigh = .triple, .window = 6, .budget = 20_000_000 / div, .seed = 0xB2 ^ @as(u64, n), .name = "skew_triple" });
    } else {
        try out.append(.{ .mode = .mirror_altern, .neigh = .pair, .window = 0, .budget = 35_000_000 / div, .seed = 0xC1 ^ @as(u64, n), .name = "mirror_altern_pair" });
        try out.append(.{ .mode = .mirror_altern, .neigh = .triple, .window = 6, .budget = 15_000_000 / div, .seed = 0xC2 ^ @as(u64, n), .name = "mirror_altern_triple" });
        try out.append(.{ .mode = .mirror_pos, .neigh = .pair, .window = 0, .budget = 15_000_000 / div, .seed = 0xC3 ^ @as(u64, n), .name = "palindrome_pair" });
        try out.append(.{ .mode = .mirror_neg, .neigh = .pair, .window = 0, .budget = 15_000_000 / div, .seed = 0xC4 ^ @as(u64, n), .name = "antipalindrome_pair" });
    }
}

const memetic_budget_full: u64 = 40_000_000;

// ---------------------------------------------------------------------------
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const A = arena.allocator();
    const out = std.io.getStdOut().writer();

    var div: u64 = 1; // overall budget divisor: --quick=200, --div=N custom
    var ns_list = std.ArrayList(usize).init(A);
    var csv_path: []const u8 = "results/labs_even_n_2026_07_10.csv";
    var json_path: []const u8 = "results/labs_even_n_claims_2026_07_10.json";
    var isolate_mode: ?[]const u8 = null;
    var isolate_n: usize = 0;
    var isolate_budget: u64 = 35_000_000;
    var it = try std.process.argsWithAllocator(A);
    defer it.deinit();
    _ = it.next();
    while (it.next()) |a| {
        if (std.mem.eql(u8, a, "--quick")) {
            div = 200;
        } else if (std.mem.startsWith(u8, a, "--div=")) {
            div = try std.fmt.parseInt(u64, a["--div=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--ns=")) {
            var pieces = std.mem.splitScalar(u8, a["--ns=".len..], ',');
            while (pieces.next()) |p| {
                if (p.len == 0) continue;
                try ns_list.append(try std.fmt.parseInt(usize, p, 10));
            }
        } else if (std.mem.startsWith(u8, a, "--csv=")) {
            csv_path = a["--csv=".len..];
        } else if (std.mem.startsWith(u8, a, "--json=")) {
            json_path = a["--json=".len..];
        } else if (std.mem.startsWith(u8, a, "--isolate-mode=")) {
            isolate_mode = a["--isolate-mode=".len..];
        } else if (std.mem.startsWith(u8, a, "--isolate-n=")) {
            isolate_n = try std.fmt.parseInt(usize, a["--isolate-n=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--isolate-budget=")) {
            isolate_budget = try std.fmt.parseInt(u64, a["--isolate-budget=".len..], 10);
        }
    }

    // ---- isolation mode: run ONE structural mode standalone (fresh gbest,
    // no shared running-best inherited from earlier arms) to check whether a
    // hypothesis is intrinsically weak or was just never given a fair,
    // order-independent shot in the main sequential run below.
    if (isolate_mode) |mname| {
        const mode: Mode = if (std.mem.eql(u8, mname, "plain"))
            .plain
        else if (std.mem.eql(u8, mname, "skew_odd"))
            .skew_odd
        else if (std.mem.eql(u8, mname, "mirror_altern"))
            .mirror_altern
        else if (std.mem.eql(u8, mname, "mirror_pos"))
            .mirror_pos
        else if (std.mem.eql(u8, mname, "mirror_neg"))
            .mirror_neg
        else {
            std.debug.print("unknown isolate mode {s}\n", .{mname});
            std.process.exit(2);
        };
        var yy = std.ArrayList(Yield).init(A);
        var gseq: [MaxN]i8 = undefined;
        var gbestE: i64 = std.math.maxInt(i64);
        const used = try structTabuRun(isolate_n, mode, .pair, 0, isolate_budget, 0xFEED ^ @as(u64, isolate_n), gseq[0..isolate_n], &gbestE, &yy, "isolate", 0, null, false);
        try out.print("isolate mode={s} n={d} budget={d} evals_used={d} -> best_E={d} best_F={d:.4}\n", .{ mname, isolate_n, isolate_budget, used, gbestE, merit(isolate_n, gbestE) });
        return;
    }
    const ns_default = [_]usize{ 44, 48, 50, 52, 54, 56, 58, 60, 61, 62, 63, 64 };
    const ns: []const usize = if (ns_list.items.len > 0) ns_list.items else ns_default[0..];

    try out.print("=== LABS even-N richer-move campaign — 2026-07-10b (round b) ===\n", .{});
    try out.print("targets: the 12 misses from yesterday's campaign (even N>=44, and N in {{61,63}})\n", .{});
    try out.print("moves: memetic (tabu+crossover+restart), pair/triple-flip neighborhoods,\n", .{});
    try out.print("       even-N mirror-pair structural hypotheses (mirror_altern/palindrome/antipalindrome),\n", .{});
    try out.print("       classical skew-symmetry (odd N in {{61,63}}) enriched with pair/triple moves.\n", .{});
    try out.print("budget divisor={d}  Ns={any}\n\n", .{ div, ns });
    try out.print("{s:>3} {s:>9} {s:>9} {s:>9} {s:>9} {s:>18} {s:>12}\n", .{ "N", "yest. E", "new E", "known E", "new F", "won-by", "gap" });

    var timer = try std.time.Timer.start();

    var yields = std.ArrayList(Yield).init(A);
    var best_seq: [MaxN + 1][MaxN]i8 = undefined;
    var best_e: [MaxN + 1]i64 = undefined;
    var won_by: [MaxN + 1][]const u8 = undefined;
    var total_evals: [MaxN + 1]u64 = undefined;

    for (ns) |n| {
        var gbestE: i64 = std.math.maxInt(i64);
        var gseq: [MaxN]i8 = undefined;
        var winner: []const u8 = "none";
        var ev_total: u64 = 0;

        var specs = std.ArrayList(ExpSpec).init(A);
        try buildSpecs(n, div, &specs);

        for (specs.items) |sp| {
            const before = gbestE;
            const used = try structTabuRun(n, sp.mode, sp.neigh, sp.window, sp.budget, sp.seed, gseq[0..n], &gbestE, &yields, sp.name, ev_total, null, false);
            ev_total += used;
            if (gbestE < before) winner = sp.name;
        }

        // memetic: warm-start half its population from the best sequence found
        // by the structural/richer-move phases above.
        {
            const before = gbestE;
            const mb: u64 = memetic_budget_full / div;
            const used = try memeticRun(n, mb, 0xD00D ^ @as(u64, n), gseq[0..n], &gbestE, &yields, ev_total, gseq[0..n]);
            ev_total += used;
            if (gbestE < before) winner = "memetic";
        }

        try yields.append(.{ .n = n, .method = "final", .evals = ev_total, .e = gbestE });

        // independent-of-incremental re-check
        const echk = energyDirect(gseq[0..n]);
        if (echk != gbestE) {
            std.debug.print("INTERNAL ERROR: stored best seq E={d} != claimed {d} at n={d}\n", .{ echk, gbestE, n });
            std.process.exit(3);
        }

        best_e[n] = gbestE;
        @memcpy(best_seq[n][0..n], gseq[0..n]);
        won_by[n] = winner;
        total_evals[n] = ev_total;

        const ke = knownE(n);
        const ye = yesterdayE(n);
        var gap: []const u8 = "NONE (matches known)";
        if (gbestE > ke) {
            gap = if (gbestE < ye) "PARTIAL (improved, still above known)" else "NONE (no improvement)";
        } else if (gbestE < ke) {
            gap = "EXTRAORDINARY-NEEDS-SCRUTINY";
        }
        try out.print("{d:>3} {d:>9} {d:>9} {d:>9} {d:>9.4} {s:>18} {s}\n", .{ n, ye, gbestE, ke, merit(n, gbestE), winner, gap });
    }

    const elapsed_ms = timer.read() / std.time.ns_per_ms;
    try out.print("\ntotal wall time: {d} ms (single-threaded)\n", .{elapsed_ms});

    // ---- write yield CSV
    {
        var f = try std.fs.cwd().createFile(csv_path, .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.print("N,method,evals,best_E,best_F\n", .{});
        for (yields.items) |y| {
            try w.print("{d},{s},{d},{d},{d:.6}\n", .{ y.n, y.method, y.evals, y.e, merit(y.n, y.e) });
        }
        try bw.flush();
    }

    // ---- write claims JSON for the independent verifier (scripts/zig/labs_check.zig)
    {
        var f = try std.fs.cwd().createFile(json_path, .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.print("{{\n  \"date\": \"2026-07-10\",\n  \"note\": \"round b even-N richer-move campaign; all HEURISTIC (no exhaustive tier here)\",\n  \"claims\": [\n", .{});
        for (ns, 0..) |n, ci| {
            try w.print("    {{\"n\": {d}, \"status\": \"HEURISTIC\", \"E\": {d}, \"F\": {d:.6}, \"evals\": {d}, \"won_by\": \"{s}\", \"seq\": [", .{ n, best_e[n], merit(n, best_e[n]), total_evals[n], won_by[n] });
            for (best_seq[n][0..n], 0..) |x, i| {
                if (i > 0) try w.print(",", .{});
                try w.print("{d}", .{x});
            }
            try w.print("]}}{s}\n", .{if (ci + 1 < ns.len) "," else ""});
        }
        try w.print("  ]\n}}\n", .{});
        try bw.flush();
    }

    try out.print("\nwrote {s} and {s}\n", .{ csv_path, json_path });
    try out.print("verify independently: <labs_check binary> {s}\n", .{json_path});
    try out.print("(labs_check reads \"n/status/E/F/seq\" and ignores unknown extra keys like \"won_by\"/\"note\")\n", .{});
}
