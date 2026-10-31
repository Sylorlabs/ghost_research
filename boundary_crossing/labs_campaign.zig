//! labs_campaign.zig — "Dial 3" campaign on LABS (Low-Autocorrelation Binary Sequences).
//!
//! Target: S in {+1,-1}^N; aperiodic autocorrelations C_k = sum_{i=0}^{N-1-k} s_i s_{i+k};
//! energy E = sum_{k=1}^{N-1} C_k^2; merit factor F = N^2 / (2E). Minimizing E (maximizing F)
//! is a genuinely-hard open combinatorial problem (no closed form; optima proven only for
//! small N via exhaustive search in the literature).
//!
//! Two regimes in this campaign:
//!   * N <= 24: EXHAUSTIVE Gray-code scan over 2^(N-1) sequences (s_0 = +1 fixed WLOG by the
//!     negation symmetry E(s) = E(-s)) with incremental O(N) single-flip energy updates.
//!     The result is a PROVEN optimum at this N.
//!   * 25 <= N <= 64: tabu local search with incremental O(N) single-flip energy updates,
//!     multi-restart, aspiration criterion; for odd N additionally a tabu search restricted
//!     to SKEW-SYMMETRIC sequences (s_{c+d} = (-1)^d s_{c-d}, center c=(N-1)/2 — forces all
//!     odd-lag correlations to 0, halves the search dimension). Results are HEURISTIC only.
//!
//! Outputs (paths relative to the CWD — run from the repository root):
//!   results/labs_yield_2026_07_10.csv    yield curve: best E/F vs cumulative eval count per N
//!   results/labs_claims_2026_07_10.json  claims file for the INDEPENDENT verifier
//!                                        scripts/zig/labs_check.zig (never trust this binary
//!                                        on its own word)
//!
//! Honesty rules (repo culture):
//!   * The embedded best-known table is marked with provenance + confidence PER ENTRY.
//!     Entries for N in [25,64] are RECALLED from Packebusch & Mertens (2016), J.Phys.A 49,
//!     165001 (arXiv:1512.02475) and have NOT been independently re-verified in this session;
//!     treat any disagreement as "suspect the recalled table first".
//!   * If our best E is ever LOWER than the tabled best-known, the program prints
//!     EXTRAORDINARY-NEEDS-SCRUTINY and does NOT declare victory.
//!   * "eval" = one neighbor delta-E evaluation (O(N) work); for the skew-restricted search
//!     one eval = one pair-flip neighbor probe (~4 O(N) passes). Exhaustive: 1 eval = 1
//!     sequence energy (via O(N) incremental Gray step).
//!
//! Build + run (from repo root):
//!   zig build-exe boundary_crossing/labs_campaign.zig -O ReleaseFast \
//!       -femit-bin=/tmp/claude-1000/labs_campaign
//!   /tmp/claude-1000/labs_campaign            (add --quick for a 20x-smaller smoke run)

const std = @import("std");

const MaxN: usize = 64;
const ExhMax: usize = 24; // exhaustive (PROVEN) up to and including this N

// ---------------------------------------------------------------------------
// best-known optimal energies, indexed by N (0 = no entry).
// N=2..24: literature exhaustive values; this run RE-PROVES them independently.
// N=3,4,5,7,11,13: Barker sequences, classical, HIGH confidence.
// N=25..64: recalled from Packebusch & Mertens 2016 exhaustive tables — MEDIUM
//           confidence (proven optimal in the literature, but the recall itself
//           is unverified here). Do not treat as gospel.
// ---------------------------------------------------------------------------
const known_e = [MaxN + 1]i64{
    0, 0, //           0,1 unused
    1, 1, 2, 2, //     N=2..5
    7, 3, 8, 12, //    N=6..9
    13, 5, 10, 6, //   N=10..13  (13: Barker, E=6, F=169/12=14.083)
    19, 15, 24, 32, // N=14..17
    25, 29, 26, 26, // N=18..21
    39, 47, 36, 36, // N=22..25
    45, 37, 50, 62, // N=26..29
    59, 67, 64, 64, // N=30..33
    65, 73, 82, 86, // N=34..37
    87, 99, 108, 108, // N=38..41
    101, 109, 122, 118, // N=42..45
    131, 135, 140, 136, // N=46..49
    153, 153, 166, 170, // N=50..53
    175, 171, 192, 188, // N=54..57
    197, 205, 218, 226, // N=58..61
    235, 207, 208, // N=62..64
};

fn knownConf(n: usize) []const u8 {
    return switch (n) {
        3, 4, 5, 7, 11, 13 => "HIGH: Barker sequence, classical optimality",
        2, 6, 8, 9, 10, 12, 14...24 => "HIGH: literature exhaustive + re-proven by this run",
        25...64 => "MEDIUM: recalled Packebusch-Mertens 2016; recall unverified this session",
        else => "none",
    };
}

// ---------------------------------------------------------------------------
// energy machinery (shared by exhaustive + tabu; the INDEPENDENT verifier in
// scripts/zig/labs_check.zig deliberately shares NONE of this code)
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

/// delta E if position i were flipped (does NOT mutate). O(N).
fn flipDeltaE(s: []const i8, C: []const i64, i: usize, n: usize) i64 {
    var d: i64 = 0;
    var k: usize = 1;
    while (k < n) : (k += 1) {
        var t: i64 = 0;
        if (i >= k) t += @as(i64, s[i - k]);
        if (i + k < n) t += @as(i64, s[i + k]);
        if (t != 0) {
            const nc = C[k] - 2 * @as(i64, s[i]) * t;
            d += nc * nc - C[k] * C[k];
        }
    }
    return d;
}

/// flip position i, updating C in place; returns delta E. O(N).
/// Applying twice at the same i restores s and C exactly (used for probe-revert).
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
// exhaustive Gray-code scan: PROVEN optimum for this N.
// Enumerates all 2^(N-1) sequences with s_0=+1 (negation symmetry); consecutive
// sequences differ in exactly one position -> O(N) incremental update each.
// ---------------------------------------------------------------------------
fn exhaustive(n: usize, best_seq: []i8, yields: *std.ArrayList(Yield)) !struct { e: i64, evals: u64 } {
    var s: [MaxN]i8 = undefined;
    var C: [MaxN]i64 = undefined;
    for (0..n) |i| s[i] = 1;
    computeC(s[0..n], C[0..n]);
    var E = energyFromC(C[0..n], n);
    var bestE = E;
    @memcpy(best_seq[0..n], s[0..n]);
    try yields.append(.{ .n = n, .method = "exhaustive", .evals = 1, .e = bestE });

    const total: u64 = @as(u64, 1) << @intCast(n - 1);
    var g: u64 = 1;
    while (g < total) : (g += 1) {
        // standard Gray walk: flip position ctz(g)+1 (position 0 stays fixed at +1)
        const j: usize = @as(usize, @intCast(@ctz(g))) + 1;
        E += applyFlipDelta(s[0..n], C[0..n], j, n);
        if (E < bestE) {
            bestE = E;
            @memcpy(best_seq[0..n], s[0..n]);
            try yields.append(.{ .n = n, .method = "exhaustive", .evals = g + 1, .e = bestE });
        }
    }
    return .{ .e = bestE, .evals = total };
}

// ---------------------------------------------------------------------------
// tabu local search (plain, and skew-symmetric-restricted for odd N).
// Single-threaded. Multi-restart; aspiration = move allowed while tabu if it
// beats the global best. Stagnation (no global improvement for `stall` moves)
// triggers a restart.
// ---------------------------------------------------------------------------
fn tabuRun(
    n: usize,
    skew: bool,
    budget: u64,
    seed: u64,
    gbest_seq: []i8,
    gbestE: *i64,
    yields: *std.ArrayList(Yield),
    evals_offset: u64,
) !u64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var s: [MaxN]i8 = undefined;
    var C: [MaxN]i64 = undefined;
    var tabu_until: [MaxN]u64 = undefined;
    var evals: u64 = 0;
    const m: usize = if (skew) (n + 1) / 2 else n; // neighborhood size
    const c: usize = if (skew) (n - 1) / 2 else 0; // center index (skew only)
    const method: []const u8 = if (skew) "tabu_skew" else "tabu";
    const stall_limit: u64 = 60 * @as(u64, n);
    const iters_per_restart: u64 = 4000;

    while (evals < budget) {
        // ---- (re)initialize
        if (skew) {
            for (0..c + 1) |i| s[i] = if (rng.boolean()) 1 else -1;
            var d: usize = 1;
            while (c + d < n) : (d += 1) {
                const sign: i8 = if (d % 2 == 1) -1 else 1;
                s[c + d] = sign * s[c - d];
            }
        } else {
            for (0..n) |i| s[i] = if (rng.boolean()) 1 else -1;
        }
        computeC(s[0..n], C[0..n]);
        var curE = energyFromC(C[0..n], n);
        evals += 1;
        for (0..n) |i| tabu_until[i] = 0;
        if (curE < gbestE.*) {
            gbestE.* = curE;
            @memcpy(gbest_seq[0..n], s[0..n]);
            try yields.append(.{ .n = n, .method = method, .evals = evals_offset + evals, .e = curE });
        }

        var iter: u64 = 1;
        var last_improve: u64 = 0;
        while (iter < iters_per_restart and evals < budget) : (iter += 1) {
            var bestD: i64 = std.math.maxInt(i64);
            var bestI: usize = 0;
            var anyD: i64 = std.math.maxInt(i64);
            var anyI: usize = 0;
            var found = false;
            for (0..m) |i| {
                var d: i64 = undefined;
                if (skew and i != c) {
                    // pair flip (i, mirror): apply i, probe mirror, revert i
                    const j = 2 * c - i;
                    const d1 = applyFlipDelta(s[0..n], C[0..n], i, n);
                    const d2 = flipDeltaE(s[0..n], C[0..n], j, n);
                    _ = applyFlipDelta(s[0..n], C[0..n], i, n); // revert
                    d = d1 + d2;
                } else {
                    d = flipDeltaE(s[0..n], C[0..n], i, n);
                }
                evals += 1;
                if (d < anyD) {
                    anyD = d;
                    anyI = i;
                }
                const aspiration = (curE + d) < gbestE.*;
                if ((tabu_until[i] <= iter or aspiration) and d < bestD) {
                    bestD = d;
                    bestI = i;
                    found = true;
                }
            }
            if (!found) {
                bestD = anyD;
                bestI = anyI;
            }
            // ---- commit the move
            if (skew and bestI != c) {
                const j = 2 * c - bestI;
                var dd = applyFlipDelta(s[0..n], C[0..n], bestI, n);
                dd += applyFlipDelta(s[0..n], C[0..n], j, n);
                curE += dd;
            } else {
                curE += applyFlipDelta(s[0..n], C[0..n], bestI, n);
            }
            tabu_until[bestI] = iter + 4 + rng.uintLessThan(u64, @max(2, n / 4));
            if (curE < gbestE.*) {
                gbestE.* = curE;
                @memcpy(gbest_seq[0..n], s[0..n]);
                try yields.append(.{ .n = n, .method = method, .evals = evals_offset + evals, .e = curE });
                last_improve = iter;
            }
            if (iter - last_improve > stall_limit) break; // stagnation -> restart
        }
        // ---- internal soundness check: incremental energy must equal from-scratch energy
        const check = energyDirect(s[0..n]);
        if (check != curE) {
            std.debug.print("INTERNAL ERROR: incremental E={d} != direct E={d} at n={d}\n", .{ curE, check, n });
            std.process.exit(3);
        }
    }
    return evals;
}

// ---------------------------------------------------------------------------
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const A = arena.allocator();
    const out = std.io.getStdOut().writer();

    var quick = false;
    var it = try std.process.argsWithAllocator(A);
    defer it.deinit();
    _ = it.next();
    while (it.next()) |a| {
        if (std.mem.eql(u8, a, "--quick")) quick = true;
    }

    // budgets scale up at N>=40 where the search visibly needs more evals
    const plain_budget_lo: u64 = if (quick) 300_000 else 20_000_000;
    const skew_budget_lo: u64 = if (quick) 150_000 else 6_000_000;
    const plain_budget_hi: u64 = if (quick) 300_000 else 60_000_000;
    const skew_budget_hi: u64 = if (quick) 150_000 else 18_000_000;

    var yields = std.ArrayList(Yield).init(A);
    var bestE_all: [MaxN + 1]i64 = undefined;
    var evals_all: [MaxN + 1]u64 = undefined;
    var seq_all: [MaxN + 1][MaxN]i8 = undefined;

    try out.print("=== LABS dial-3 campaign — exhaustive (N<={d}) + tabu / skew-tabu (N<={d}) ===\n", .{ ExhMax, MaxN });
    try out.print("E = sum C_k^2, F = N^2/(2E).  eval = one neighbor delta-E probe (O(N)).\n", .{});
    try out.print("budgets: tabu {d}/{d} evals (N<40 / N>=40), skew-tabu {d}/{d} evals (odd N only). quick={}\n\n", .{ plain_budget_lo, plain_budget_hi, skew_budget_lo, skew_budget_hi, quick });
    try out.print("{s:>3} {s:>7} {s:>9} {s:>9} {s:>11} {s:>10}  {s}\n", .{ "N", "best E", "best F", "known F", "status", "evals", "assessment" });

    var timer = try std.time.Timer.start();

    for (2..MaxN + 1) |n| {
        var proven = false;
        if (n <= ExhMax) {
            const r = try exhaustive(n, seq_all[n][0..n], &yields);
            bestE_all[n] = r.e;
            evals_all[n] = r.evals;
            proven = true;
        } else {
            const plain_budget = if (n >= 40) plain_budget_hi else plain_budget_lo;
            const skew_budget = if (n >= 40) skew_budget_hi else skew_budget_lo;
            var gbestE: i64 = std.math.maxInt(i64);
            var ev = try tabuRun(n, false, plain_budget, 0xC0FFEE ^ @as(u64, n), seq_all[n][0..n], &gbestE, &yields, 0);
            if (n % 2 == 1) {
                ev += try tabuRun(n, true, skew_budget, 0x5EED ^ @as(u64, n), seq_all[n][0..n], &gbestE, &yields, ev);
            }
            bestE_all[n] = gbestE;
            evals_all[n] = ev;
        }
        // final yield row so the curve always ends at the final state
        try yields.append(.{ .n = n, .method = "final", .evals = evals_all[n], .e = bestE_all[n] });

        // independent-of-incremental re-check of the reported artifact
        const echk = energyDirect(seq_all[n][0..n]);
        if (echk != bestE_all[n]) {
            std.debug.print("INTERNAL ERROR: stored best seq E={d} != claimed {d} at n={d}\n", .{ echk, bestE_all[n], n });
            std.process.exit(3);
        }

        const ke = known_e[n];
        var status: []const u8 = "NO-REFERENCE";
        var assess: []const u8 = "";
        if (ke != 0) {
            if (bestE_all[n] == ke) {
                status = if (proven) "PROVEN=known" else "MATCH-known";
            } else if (bestE_all[n] > ke) {
                status = if (proven) "TABLE-AUDIT!" else "BELOW-known";
                assess = if (proven) "exhaustive proof disagrees with recalled table — recalled entry is wrong (or exhaustive bug)" else "";
            } else {
                status = "EXTRAORD.!";
                assess = "EXTRAORDINARY-NEEDS-SCRUTINY: E below recalled best-known. Suspect the recalled table entry FIRST; do not declare victory.";
            }
        } else {
            status = if (proven) "PROVEN" else "HEURISTIC";
        }
        const kf: f64 = if (ke != 0) merit(n, ke) else 0.0;
        try out.print("{d:>3} {d:>7} {d:>9.4} {d:>9.4} {s:>11} {d:>10}  {s}\n", .{ n, bestE_all[n], merit(n, bestE_all[n]), kf, status, evals_all[n], assess });
    }

    const elapsed_ms = timer.read() / std.time.ns_per_ms;
    try out.print("\ntotal wall time: {d} ms (single-threaded)\n", .{elapsed_ms});

    // ---- showcase sequences
    try out.print("\nshowcase artifacts (+/- strings):\n", .{});
    const showcase = [_]usize{ 13, 21, 27, 41, 57, 64 };
    for (showcase) |n| {
        try out.print("  N={d:<2} E={d:<4} F={d:.4}  ", .{ n, bestE_all[n], merit(n, bestE_all[n]) });
        for (seq_all[n][0..n]) |x| try out.print("{c}", .{@as(u8, if (x > 0) '+' else '-')});
        try out.print("\n", .{});
    }

    // ---- write yield CSV
    {
        var f = try std.fs.cwd().createFile("results/labs_yield_2026_07_10.csv", .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.print("N,method,evals,best_E,best_F\n", .{});
        for (yields.items) |y| {
            try w.print("{d},{s},{d},{d},{d:.6}\n", .{ y.n, y.method, y.evals, y.e, merit(y.n, y.e) });
        }
        try bw.flush();
    }

    // ---- write claims JSON for the independent verifier
    {
        var f = try std.fs.cwd().createFile("results/labs_claims_2026_07_10.json", .{});
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        const w = bw.writer();
        try w.print("{{\n  \"date\": \"2026-07-10\",\n  \"claims\": [\n", .{});
        for (2..MaxN + 1) |n| {
            const st: []const u8 = if (n <= ExhMax) "PROVEN" else "HEURISTIC";
            try w.print("    {{\"n\": {d}, \"status\": \"{s}\", \"E\": {d}, \"F\": {d:.6}, \"evals\": {d}, \"seq\": [", .{ n, st, bestE_all[n], merit(n, bestE_all[n]), evals_all[n] });
            for (seq_all[n][0..n], 0..) |x, i| {
                if (i > 0) try w.print(",", .{});
                try w.print("{d}", .{x});
            }
            try w.print("]}}{s}\n", .{if (n < MaxN) "," else ""});
        }
        try w.print("  ]\n}}\n", .{});
        try bw.flush();
    }

    try out.print("\nwrote results/labs_yield_2026_07_10.csv and results/labs_claims_2026_07_10.json\n", .{});
    try out.print("verify independently: /tmp/claude-1000/labs_check results/labs_claims_2026_07_10.json\n", .{});
}
