//! aimed_open.zig — Round 2026-07-11 (Round E), experiment E4: an AIMED search
//! pointed at the closest genuinely-open LABS gap, with an independent verifier
//! and a mandatory EXTRAORDINARY-NEEDS-SCRUTINY protocol.
//!
//! ---------------------------------------------------------------------------
//! TARGET CHOICE (documented per task instructions)
//! ---------------------------------------------------------------------------
//! Candidates surveyed (from docs/research/labs_even_n.md, labs_swarm.md):
//!   N=61 (odd):  current best E=230, best-known E=226 -> gap = 4  (1.77% above)
//!   N=48 (even): current best E=148, best-known E=140 -> gap = 8  (5.71% above)
//!   all other misses (50,52,54,56,58,60,62,63,64): gaps 8-76, all worse than
//!     the above two both in absolute AND relative terms.
//! N=61 is the closest-to-closed gap in the whole 12-length miss table (both
//! smallest ABSOLUTE gap and smallest RELATIVE gap), AND it is odd, so the
//! known, proven, algebraic skew-symmetric structure (s_{c+d} = (-1)^d s_{c-d},
//! integer center c=(N-1)/2, forces all odd-lag correlations to exactly 0)
//! applies exactly — unlike the even-N misses, where labs_even_n.md's honest
//! finding was that NO structural analogue of skew-symmetry was ever found
//! (mirror_altern/palindrome/antipalindrome all lost badly to plain search).
//! N=61 is therefore chosen as the primary AIMED target: smallest gap, richest
//! known structure, most tractable path to closing 4 more energy units.
//! N=48 (the task prompt's illustrative "e.g.") is run as a SECONDARY check in
//! `plain` mode (no known even-N structural analogue exists per labs_even_n.md)
//! to see whether the aim mechanism generalizes to a harder, structure-poor case.
//!
//! ---------------------------------------------------------------------------
//! THE AIM MECHANISM (what makes this "aimed" and not just "more of the same")
//! ---------------------------------------------------------------------------
//! Every prior round's tabu search samples its pair/triple neighborhood
//! UNIFORMLY at random over free indices — undirected. This file adds a
//! genuinely computed steering signal: RESIDUAL AUTOCORRELATION.
//!
//! E = sum_k C_k^2, so the lag(s) k with the largest |C_k| are, by construction,
//! the dominant contributors to the current energy. A pair-flip move at raw
//! index gap exactly k directly engages the C_k term (s_i * s_{i+k} is literally
//! one of the summands of C_k). So instead of drawing (pa, pb) uniformly, the
//! aimed engine:
//!   1. computes |C_k| for every lag every iteration (already have C[] from the
//!      incremental update — this costs one O(N) scan, not a new eval);
//!   2. keeps a magnitude-weighted top-T list of the largest-|C_k| lags;
//!   3. draws pa uniformly (kept undirected — only the SECOND index is aimed,
//!      so exploration is not lost entirely), then draws a target gap k from
//!      the weighted top-T list and sets pb = pa +/- k (falling back to a
//!      uniform pb if that lands out of range or collides with pa).
//! This is a controlled ablation: `aim=false` and `aim=true` share IDENTICAL
//! code for everything else (init, singles pass, tabu tenure, aspiration,
//! restart/stagnation, triples if enabled, internal soundness check) — the two
//! arms are generated from the SAME function with one boolean flipped, which is
//! the safest way to guarantee the only difference measured is the aim signal
//! itself, not an accidental implementation drift between two separate copies.
//!
//! Caveat documented honestly: in skew_odd mode a "free index" gap does not
//! equal ONLY the targeted raw lag — flipping free index i also flips its
//! mirror position (2c-i), so a pair move touches 4 raw positions and several
//! induced lags besides the intended one. The aim signal targets the DOMINANT
//! term but is not an exact single-lag scalpel. This is reported as a limitation,
//! not hidden.
//!
//! ---------------------------------------------------------------------------
//! Energy/flip/structural machinery below (computeC / energyFromC / energyDirect
//! / applyFlipDelta / merit / Mode / freeCount / mirrorOf / signOf / modeName /
//! initStruct / applyFreeFlip / applyMoveOnce / probeMove) is COPIED VERBATIM
//! from boundary_crossing/labs_even_n.zig (itself copied verbatim from
//! labs_campaign.zig), per repo convention: any behavioral difference is
//! attributable to the NEW aim mechanism, never to a divergent energy engine.
//! ---------------------------------------------------------------------------
//!
//! Build (from repo root):
//!   zig build-exe boundary_crossing/aimed_open.zig -O ReleaseFast \
//!       -femit-bin=/tmp/claude-1000/aimed_open
//!   /tmp/claude-1000/aimed_open --help
//!
//! Verify claims independently (existing, unmodified verifier):
//!   zig build-exe scripts/zig/labs_check.zig -O ReleaseFast -femit-bin=/tmp/claude-1000/labs_check
//!   /tmp/claude-1000/labs_check results/aimed_open_claims_2026_07_11.json

const std = @import("std");

const MaxN: usize = 64;

// ===========================================================================
// energy machinery — COPIED VERBATIM from labs_even_n.zig / labs_campaign.zig
// ===========================================================================
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

// ===========================================================================
// structural modes — COPIED VERBATIM from labs_even_n.zig
// ===========================================================================
const Mode = enum { plain, skew_odd, mirror_altern, mirror_pos, mirror_neg };

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

const Move = struct { count: u8, idx: [3]usize, d: i64 };

// ===========================================================================
// NEW: residual-autocorrelation aim signal
// ===========================================================================
const TopT: usize = 4;
const LagList = struct { k: [TopT]usize = undefined, w: [TopT]i64 = undefined, count: usize = 0 };

/// Scan C[1..n) and keep the TopT largest |C_k| (magnitude-weighted). O(N).
fn topLags(C: []const i64, n: usize) LagList {
    var out = LagList{};
    var k: usize = 1;
    while (k < n) : (k += 1) {
        const w: i64 = @intCast(@abs(C[k]));
        if (w == 0) continue;
        // insertion into a small sorted-descending list of size <= TopT
        if (out.count < TopT) {
            var pos = out.count;
            while (pos > 0 and out.w[pos - 1] < w) : (pos -= 1) {
                out.w[pos] = out.w[pos - 1];
                out.k[pos] = out.k[pos - 1];
            }
            out.w[pos] = w;
            out.k[pos] = k;
            out.count += 1;
        } else if (w > out.w[TopT - 1]) {
            var pos = TopT - 1;
            while (pos > 0 and out.w[pos - 1] < w) : (pos -= 1) {
                out.w[pos] = out.w[pos - 1];
                out.k[pos] = out.k[pos - 1];
            }
            out.w[pos] = w;
            out.k[pos] = k;
        }
    }
    return out;
}

/// aimed pb: pa uniform, pb targets a magnitude-weighted top lag's gap from pa.
/// Falls back to uniform if the lag list is empty or the targeted gap is
/// unusable (out of range on both sides, or collides with pa).
fn aimedPartner(rng: std.Random, m: usize, pa: usize, lags: LagList) usize {
    if (lags.count == 0) {
        var pb = rng.uintLessThan(usize, m);
        var tries: u8 = 0;
        while (pb == pa and tries < 4) : (tries += 1) pb = rng.uintLessThan(usize, m);
        return pb;
    }
    var total: i64 = 0;
    for (lags.w[0..lags.count]) |w| total += w;
    var r = rng.uintLessThan(u64, @intCast(@max(total, 1)));
    var chosen_k: usize = lags.k[0];
    var acc: i64 = 0;
    for (0..lags.count) |i| {
        acc += lags.w[i];
        if (r < @as(u64, @intCast(acc))) {
            chosen_k = lags.k[i];
            break;
        }
    }
    _ = &r;
    const go_up = rng.boolean();
    if (go_up and pa + chosen_k < m and pa + chosen_k != pa) return pa + chosen_k;
    if (pa >= chosen_k and pa - chosen_k != pa) return pa - chosen_k;
    if (pa + chosen_k < m) return pa + chosen_k;
    // fallback: uniform
    var pb = rng.uintLessThan(usize, m);
    var tries: u8 = 0;
    while (pb == pa and tries < 4) : (tries += 1) pb = rng.uintLessThan(usize, m);
    return pb;
}

// ===========================================================================
// yield-curve recording + diagnostics
// ===========================================================================
const Yield = struct { n: usize, method: []const u8, evals: u64, e: i64 };

const RunStats = struct {
    evals_used: u64 = 0,
    aim_pair_wins: u64 = 0, // # times the committed best move was an aim-sampled pair
    total_committed: u64 = 0,
};

/// Unified tabu search: structural mode x {single,pair} neighborhood, with an
/// `aim` flag that ONLY changes how the pair partner index is drawn. Every
/// other code path (init, singles pass, tenure, aspiration, restart/stagnation,
/// internal soundness check) is IDENTICAL for aim=true and aim=false — the
/// single controlled variable in this ablation.
fn tabuRun(
    n: usize,
    mode: Mode,
    aim: bool,
    budget: u64,
    seed: u64,
    gbest_seq: []i8,
    gbestE: *i64,
    yields: ?*std.ArrayList(Yield),
    method_name: []const u8,
    evals_offset: u64,
    stats: *RunStats,
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

    while (evals < budget) {
        initStruct(mode, n, s[0..n], rng);
        computeC(s[0..n], C[0..n]);
        var curE = energyFromC(C[0..n], n);
        evals += 1;
        for (0..m) |i| tabu_until[i] = 0;
        if (curE < gbestE.*) {
            gbestE.* = curE;
            @memcpy(gbest_seq[0..n], s[0..n]);
            if (yields) |y| try y.append(.{ .n = n, .method = method_name, .evals = evals_offset + evals, .e = curE });
        }

        var iter: u64 = 1;
        var last_improve: u64 = 0;
        while (iter < iters_per_restart and evals < budget) : (iter += 1) {
            var bestD: i64 = std.math.maxInt(i64);
            var bestMove: Move = .{ .count = 1, .idx = .{ 0, 0, 0 }, .d = 0 };
            var anyD: i64 = std.math.maxInt(i64);
            var anyMove: Move = bestMove;
            var found = false;
            var best_is_aim_pair = false;

            // singles (exhaustive, m evals) — identical for both arms
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
                    best_is_aim_pair = false;
                }
            }

            // sampled pairs (m evals) — the ONLY place aim vs undirected differ
            const lags = if (aim) topLags(C[0..n], n) else LagList{};
            var kk: usize = 0;
            while (kk < m) : (kk += 1) {
                const pa = rng.uintLessThan(usize, m);
                var pb: usize = undefined;
                if (aim) {
                    pb = aimedPartner(rng, m, pa, lags);
                } else {
                    pb = rng.uintLessThan(usize, m);
                    var tries: u8 = 0;
                    while (pb == pa and tries < 4) : (tries += 1) pb = rng.uintLessThan(usize, m);
                }
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
                    best_is_aim_pair = aim;
                }
            }

            if (!found) {
                bestD = anyD;
                bestMove = anyMove;
            }
            const committed_d = applyMoveOnce(mode, n, bestMove.idx[0..bestMove.count], s[0..n], C[0..n]);
            curE += committed_d;
            stats.total_committed += 1;
            if (best_is_aim_pair) stats.aim_pair_wins += 1;
            const tenure = iter + 4 + rng.uintLessThan(u64, @max(2, m / 4));
            for (bestMove.idx[0..bestMove.count]) |ix| tabu_until[ix] = tenure;
            if (curE < gbestE.*) {
                gbestE.* = curE;
                @memcpy(gbest_seq[0..n], s[0..n]);
                if (yields) |y| try y.append(.{ .n = n, .method = method_name, .evals = evals_offset + evals, .e = curE });
                last_improve = iter;
            }
            if (iter - last_improve > stall_limit) break;
        }
        const check = energyDirect(s[0..n]);
        if (check != curE) {
            std.debug.print("INTERNAL ERROR: incremental E={d} != direct E={d} at n={d} mode={s}\n", .{ curE, check, n, modeName(mode) });
            std.process.exit(3);
        }
    }
    stats.evals_used = evals;
    return evals;
}

// ===========================================================================
// experiment harness
// ===========================================================================
const RunResult = struct { e: i64, seq: [MaxN]i8, evals: u64, aim_pair_wins: u64, total_committed: u64 };

fn runOne(n: usize, mode: Mode, aim: bool, budget: u64, seed: u64, method_name: []const u8, evals_offset: u64, yields: ?*std.ArrayList(Yield)) !RunResult {
    var gbestE: i64 = std.math.maxInt(i64);
    var gseq: [MaxN]i8 = undefined;
    var stats = RunStats{};
    const used = try tabuRun(n, mode, aim, budget, seed, gseq[0..n], &gbestE, yields, method_name, evals_offset, &stats);
    return .{ .e = gbestE, .seq = gseq, .evals = used, .aim_pair_wins = stats.aim_pair_wins, .total_committed = stats.total_committed };
}

const Claim = struct { n: usize, e: i64, seq: [MaxN]i8, method: []const u8, evals: u64 };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const A = arena.allocator();
    const out = std.io.getStdOut().writer();

    var div: u64 = 1;
    var seeds_n: u64 = 5;
    var eq_budget: u64 = 12_000_000;
    var big_budget: u64 = 60_000_000;
    var csv_path: []const u8 = "results/aimed_open_2026_07_11.csv";
    var json_path: []const u8 = "results/aimed_open_claims_2026_07_11.json";
    var target_n: usize = 61;
    var target_mode: Mode = .skew_odd;
    var known_e: i64 = 226;
    var prior_best_e: i64 = 230;

    var it = try std.process.argsWithAllocator(A);
    defer it.deinit();
    _ = it.next();
    while (it.next()) |a| {
        if (std.mem.eql(u8, a, "--quick")) {
            div = 200;
        } else if (std.mem.startsWith(u8, a, "--div=")) {
            div = try std.fmt.parseInt(u64, a["--div=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--seeds=")) {
            seeds_n = try std.fmt.parseInt(u64, a["--seeds=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--eq-budget=")) {
            eq_budget = try std.fmt.parseInt(u64, a["--eq-budget=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--big-budget=")) {
            big_budget = try std.fmt.parseInt(u64, a["--big-budget=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--csv=")) {
            csv_path = a["--csv=".len..];
        } else if (std.mem.startsWith(u8, a, "--json=")) {
            json_path = a["--json=".len..];
        } else if (std.mem.startsWith(u8, a, "--n=")) {
            target_n = try std.fmt.parseInt(usize, a["--n=".len..], 10);
        } else if (std.mem.eql(u8, a, "--mode=plain")) {
            target_mode = .plain;
        } else if (std.mem.eql(u8, a, "--mode=skew")) {
            target_mode = .skew_odd;
        } else if (std.mem.startsWith(u8, a, "--known-e=")) {
            known_e = try std.fmt.parseInt(i64, a["--known-e=".len..], 10);
        } else if (std.mem.startsWith(u8, a, "--prior-best=")) {
            prior_best_e = try std.fmt.parseInt(i64, a["--prior-best=".len..], 10);
        }
    }
    eq_budget /= div;
    big_budget /= div;

    try out.print("=== aimed_open — Round 2026-07-11 E4: aimed engine on target n={d} mode={s} ===\n", .{ target_n, modeName(target_mode) });
    try out.print("known-best E={d}, prior campaign best E={d}, gap={d}\n", .{ known_e, prior_best_e, prior_best_e - known_e });
    try out.print("equal-budget per-seed={d}, seeds={d}, big-budget={d}\n\n", .{ eq_budget, seeds_n, big_budget });

    var timer = try std.time.Timer.start();
    var yields = std.ArrayList(Yield).init(A);
    var csv_rows = std.ArrayList([]const u8).init(A);
    var claims = std.ArrayList(Claim).init(A);

    // ---- phase 1: equal-budget ablation, undirected vs aimed, multi-seed ----
    try out.print("{s:>6} {s:>10} {s:>6} {s:>10} {s:>10} {s:>12} {s:>10}\n", .{ "method", "seed", "n", "best_E", "best_F", "aim_win_%", "evals" });
    var undirected_best: i64 = std.math.maxInt(i64);
    var undirected_best_seq: [MaxN]i8 = undefined;
    var aimed_best: i64 = std.math.maxInt(i64);
    var aimed_best_seq: [MaxN]i8 = undefined;
    var undirected_sum: f64 = 0;
    var aimed_sum: f64 = 0;

    for (0..seeds_n) |si| {
        const seed_u: u64 = 0xA5A5_0000_0000_0000 ^ (@as(u64, si) *% 0x9E3779B97F4A7C15) ^ @as(u64, target_n);
        const seed_a: u64 = 0x5A5A_0000_0000_0000 ^ (@as(u64, si) *% 0xBF58476D1CE4E5B9) ^ @as(u64, target_n);

        const ru = try runOne(target_n, target_mode, false, eq_budget, seed_u, "undirected_eq", 0, &yields);
        const ra = try runOne(target_n, target_mode, true, eq_budget, seed_a, "aimed_eq", 0, &yields);

        undirected_sum += @floatFromInt(ru.e);
        aimed_sum += @floatFromInt(ra.e);
        if (ru.e < undirected_best) {
            undirected_best = ru.e;
            undirected_best_seq = ru.seq;
        }
        if (ra.e < aimed_best) {
            aimed_best = ra.e;
            aimed_best_seq = ra.seq;
        }

        const u_pct: f64 = if (ru.total_committed > 0) 100.0 * @as(f64, @floatFromInt(ru.aim_pair_wins)) / @as(f64, @floatFromInt(ru.total_committed)) else 0;
        const a_pct: f64 = if (ra.total_committed > 0) 100.0 * @as(f64, @floatFromInt(ra.aim_pair_wins)) / @as(f64, @floatFromInt(ra.total_committed)) else 0;
        try out.print("{s:>6} {d:>10} {d:>6} {d:>10} {d:>10.4} {d:>12.2} {d:>10}\n", .{ "undir", si, target_n, ru.e, merit(target_n, ru.e), u_pct, ru.evals });
        try out.print("{s:>6} {d:>10} {d:>6} {d:>10} {d:>10.4} {d:>12.2} {d:>10}\n", .{ "aimed", si, target_n, ra.e, merit(target_n, ra.e), a_pct, ra.evals });

        try csv_rows.append(try std.fmt.allocPrint(A, "{d},undirected_eq,{d},{d},{d},{d:.6},{d:.6}\n", .{ target_n, si, eq_budget, ru.e, merit(target_n, ru.e), u_pct }));
        try csv_rows.append(try std.fmt.allocPrint(A, "{d},aimed_eq,{d},{d},{d},{d:.6},{d:.6}\n", .{ target_n, si, eq_budget, ra.e, merit(target_n, ra.e), a_pct }));
    }
    const undirected_mean = undirected_sum / @as(f64, @floatFromInt(seeds_n));
    const aimed_mean = aimed_sum / @as(f64, @floatFromInt(seeds_n));
    try out.print("\nEQUAL-BUDGET SUMMARY (n={d}, budget/seed={d}, seeds={d}):\n", .{ target_n, eq_budget, seeds_n });
    try out.print("  undirected: best={d} mean={d:.2}\n", .{ undirected_best, undirected_mean });
    try out.print("  aimed:      best={d} mean={d:.2}\n", .{ aimed_best, aimed_mean });
    if (aimed_best < undirected_best) {
        try out.print("  -> AIM WINS at equal budget (best): {d} < {d}\n", .{ aimed_best, undirected_best });
    } else if (aimed_best > undirected_best) {
        try out.print("  -> undirected wins at equal budget (best): {d} < {d}\n", .{ undirected_best, aimed_best });
    } else {
        try out.print("  -> TIE at equal budget (best)\n", .{});
    }

    try claims.append(.{ .n = target_n, .e = undirected_best, .seq = undirected_best_seq, .method = "undirected_eq_best", .evals = eq_budget * seeds_n });
    try claims.append(.{ .n = target_n, .e = aimed_best, .seq = aimed_best_seq, .method = "aimed_eq_best", .evals = eq_budget * seeds_n });

    // ---- phase 2: best-effort push at a bigger, still-equal budget ----
    try out.print("\n=== phase 2: best-effort push, big-budget={d} each (equal for both arms) ===\n", .{big_budget});
    const bu = try runOne(target_n, target_mode, false, big_budget, 0xBEEF_D00D ^ @as(u64, target_n), "undirected_big", 0, &yields);
    const ba = try runOne(target_n, target_mode, true, big_budget, 0xFEED_CAFE ^ @as(u64, target_n), "aimed_big", 0, &yields);
    try out.print("  undirected_big: E={d} F={d:.4} evals={d}\n", .{ bu.e, merit(target_n, bu.e), bu.evals });
    try out.print("  aimed_big:      E={d} F={d:.4} evals={d}\n", .{ ba.e, merit(target_n, ba.e), ba.evals });

    try csv_rows.append(try std.fmt.allocPrint(A, "{d},undirected_big,0,{d},{d},{d:.6},0.0\n", .{ target_n, big_budget, bu.e, merit(target_n, bu.e) }));
    try csv_rows.append(try std.fmt.allocPrint(A, "{d},aimed_big,0,{d},{d},{d:.6},0.0\n", .{ target_n, big_budget, ba.e, merit(target_n, ba.e) }));

    try claims.append(.{ .n = target_n, .e = bu.e, .seq = bu.seq, .method = "undirected_big", .evals = bu.evals });
    try claims.append(.{ .n = target_n, .e = ba.e, .seq = ba.seq, .method = "aimed_big", .evals = ba.evals });

    // ---- overall best across everything, honest scrutiny gate ----
    var overall_best_e = undirected_best;
    var overall_best_seq = undirected_best_seq;
    var overall_best_method: []const u8 = "undirected_eq_best";
    if (aimed_best < overall_best_e) {
        overall_best_e = aimed_best;
        overall_best_seq = aimed_best_seq;
        overall_best_method = "aimed_eq_best";
    }
    if (bu.e < overall_best_e) {
        overall_best_e = bu.e;
        overall_best_seq = bu.seq;
        overall_best_method = "undirected_big";
    }
    if (ba.e < overall_best_e) {
        overall_best_e = ba.e;
        overall_best_seq = ba.seq;
        overall_best_method = "aimed_big";
    }
    try out.print("\n=== OVERALL best across all arms: E={d} (method={s}) vs prior campaign best {d} vs known-best {d} ===\n", .{ overall_best_e, overall_best_method, prior_best_e, known_e });
    if (overall_best_e < known_e) {
        try out.print("*** EXTRAORDINARY-NEEDS-SCRUTINY: E={d} is BELOW recalled best-known {d} at n={d}. DO NOT declare victory. Suspect the recalled table FIRST. Re-verify independently three ways before reporting. ***\n", .{ overall_best_e, known_e, target_n });
    } else if (overall_best_e == known_e) {
        try out.print("GAP FULLY CLOSED (matches recalled best-known exactly). Not a new record — matches the tabled value.\n", .{});
    } else {
        try out.print("Gap remains: {d} above recalled best-known ({d} vs {d}). Honest distance to record reported below.\n", .{ overall_best_e - known_e, overall_best_e, known_e });
    }

    const echk = energyDirect(overall_best_seq[0..target_n]);
    if (echk != overall_best_e) {
        std.debug.print("INTERNAL ERROR: overall best seq E={d} != claimed {d}\n", .{ echk, overall_best_e });
        std.process.exit(3);
    }

    const elapsed_ms = timer.read() / std.time.ns_per_ms;
    try out.print("\ntotal wall time: {d} ms (single-threaded)\n", .{elapsed_ms});

    // ---- write CSV ----
    {
        var f = try std.fs.cwd().createFile(csv_path, .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.print("n,method,seed_idx,budget,best_E,best_F,aim_win_pct\n", .{});
        for (csv_rows.items) |row| try w.print("{s}", .{row});
        try bw.flush();
    }

    // ---- write claims JSON for scripts/zig/labs_check.zig ----
    {
        var f = try std.fs.cwd().createFile(json_path, .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.print("{{\n  \"date\": \"2026-07-11\",\n  \"note\": \"Round E, E4: aimed vs undirected skew-symmetric tabu on LABS n={d} (residual-autocorrelation aim signal); all HEURISTIC\",\n  \"claims\": [\n", .{target_n});
        for (claims.items, 0..) |c, ci| {
            try w.print("    {{\"n\": {d}, \"status\": \"HEURISTIC\", \"E\": {d}, \"F\": {d:.6}, \"evals\": {d}, \"method\": \"{s}\", \"seq\": [", .{ c.n, c.e, merit(c.n, c.e), c.evals, c.method });
            for (c.seq[0..c.n], 0..) |x, i| {
                if (i > 0) try w.print(",", .{});
                try w.print("{d}", .{x});
            }
            try w.print("]}}{s}\n", .{if (ci + 1 < claims.items.len) "," else ""});
        }
        try w.print("  ]\n}}\n", .{});
        try bw.flush();
    }

    try out.print("\nwrote {s} and {s}\n", .{ csv_path, json_path });
    try out.print("verify independently: <labs_check binary> {s}\n", .{json_path});
}
