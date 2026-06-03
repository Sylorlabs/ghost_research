//! NEW RESEARCH: is the MEDIAN outside the closure of {low-degree polynomial + max + min}?
//!
//! concentration_control.zig established: max (an EXTREMAL order statistic) is outside every
//! finite polynomial closure, but ONE max feature crosses it — because max = lim_{p→+∞} of
//! the power mean. min = lim_{p→−∞}. Both extremes are "soft-extreme limits".
//!
//! The MEDIAN is NOT a power-mean limit in ANY direction. It is a RANK/central statistic.
//! Conjecture (answer unknown in advance): the median is outside {poly_d + max + min} for
//! low d — i.e., the extremal features that crossed the max boundary DO NOT help reach the
//! central one. If so, the closure lattice splits: extremal order statistics are
//! "1-feature simple"; central ones need genuine rank information, not soft extremes.
//!
//! METHOD (the project's decisive-probe style): build a balanced dataset of states with the
//! median above vs below a threshold, where sum, Σx², max, AND min are matched EXACTLY
//! between the two classes (fixed total sum by construction; (Σx²,max,min) matched by an
//! integer-key bin-merge). Then ANY function of {poly≤2, max, min} is identical across
//! classes -> provably chance. Train logistic regression over several bases and compare:
//!   poly2                    -> chance (sum,Σx² matched)
//!   poly2 + max + min        -> chance IFF the median is not reducible to the extremes  <-- the test
//!   poly2 + median           -> ~1.0  (the explicit rank feature crosses it)
//!
//! Run: zig build order-stats

const std = @import("std");

const NCELL = 16;
const S: f64 = 5.0;

// Full feature layout (superset; each basis selects a subset of indices):
//   0            : bias
//   1..16        : x_i/S
//   17..32       : (x_i/S)^2
//   33..152      : (x_i/S)(x_j/S), i<j   (120)
//   153          : max/S
//   154          : min/S
//   155          : median/S
const NF = 156;
const I_MAX = 153;
const I_MIN = 154;
const I_MED = 155;
const NPOLY2 = 153; // indices 0..152

fn featuresFull(g: [NCELL]u8, phi: *[NF]f64) void {
    phi[0] = 1.0;
    var idx: usize = 1;
    for (0..NCELL) |i| {
        phi[idx] = @as(f64, @floatFromInt(g[i])) / S;
        idx += 1;
    }
    for (0..NCELL) |i| {
        const v = @as(f64, @floatFromInt(g[i])) / S;
        phi[idx] = v * v;
        idx += 1;
    }
    for (0..NCELL) |i| {
        for (i + 1..NCELL) |j| {
            phi[idx] = (@as(f64, @floatFromInt(g[i])) / S) * (@as(f64, @floatFromInt(g[j])) / S);
            idx += 1;
        }
    }
    // sorted copy for order statistics
    var s = g;
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    phi[I_MAX] = @as(f64, @floatFromInt(s[NCELL - 1])) / S;
    phi[I_MIN] = @as(f64, @floatFromInt(s[0])) / S;
    const med = (@as(f64, @floatFromInt(s[NCELL / 2 - 1])) + @as(f64, @floatFromInt(s[NCELL / 2]))) / 2.0;
    phi[I_MED] = med / S;
}

// Minimal symmetric power-sum basis for the degree-general strengthening:
//   [0]=1, [1]=p1, [2]=p2, [3]=p3, [4]=max/S, [5]=min/S, [6]=median/S   (p_k=Σ(x_i/S)^k)
const NPS = 7;
fn featuresPS(g: [NCELL]u8, phi: *[NPS]f64) void {
    phi[0] = 1.0;
    phi[1] = 0;
    phi[2] = 0;
    phi[3] = 0;
    for (g) |c| {
        const v = @as(f64, @floatFromInt(c)) / S;
        phi[1] += v;
        phi[2] += v * v;
        phi[3] += v * v * v;
    }
    var s = g;
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    phi[4] = @as(f64, @floatFromInt(s[NCELL - 1])) / S;
    phi[5] = @as(f64, @floatFromInt(s[0])) / S;
    phi[6] = (@as(f64, @floatFromInt(s[NCELL / 2 - 1])) + @as(f64, @floatFromInt(s[NCELL / 2]))) / 2.0 / S;
}

// Key matching p2, p3, max, min exactly (p1=sum fixed by construction). p2<4096, p3<2^15
// for our caps, max/min<32.
fn keyPS(g: [NCELL]u8) u64 {
    var p2: u64 = 0;
    var p3: u64 = 0;
    var mx: u8 = 0;
    var mn: u8 = 255;
    for (g) |c| {
        const x: u64 = c;
        p2 += x * x;
        p3 += x * x * x;
        mx = @max(mx, c);
        mn = @min(mn, c);
    }
    return (p2 << 24) | (p3 << 9) | (@as(u64, mx) << 5) | @as(u64, mn);
}

fn trainAndTestPS(grids_tr: []const [NCELL]u8, y_tr: []const f32, grids_te: []const [NCELL]u8, y_te: []const f32, active: []const usize, epochs: usize, lr: f64) f64 {
    var w = [_]f64{0} ** NPS;
    var phi: [NPS]f64 = undefined;
    for (0..epochs) |_| {
        for (grids_tr, y_tr) |g, yf| {
            featuresPS(g, &phi);
            var z: f64 = 0;
            for (active) |k| z += w[k] * phi[k];
            if (z > 30) z = 30;
            if (z < -30) z = -30;
            const p = 1.0 / (1.0 + @exp(-z));
            const grad = p - yf;
            for (active) |k| w[k] -= lr * grad * phi[k];
        }
    }
    var correct: u32 = 0;
    for (grids_te, y_te) |g, yf| {
        featuresPS(g, &phi);
        var z: f64 = 0;
        for (active) |k| z += w[k] * phi[k];
        const pred: f32 = if (z >= 0) 1.0 else 0.0;
        if (pred == yf) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(grids_te.len));
}

fn kthLargest(g: [NCELL]u8, k: usize) u8 {
    var s = g;
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    return s[NCELL - k];
}

// Rank-complexity spectrum: for the k-th largest value (k=1 max ... k=8 median), how well
// does {poly2 + max + min} classify "k-th largest >= T_k" with (p2,p3,max,min) matched? If
// accuracy falls from ~1 near the extremes toward chance at the center, that is a smooth
// rank-complexity law: order statistics get harder for poly+extremes as they go central.
fn runRankSpectrum(out: anytype) !void {
    try out.print("\n=== RANK-COMPLEXITY SPECTRUM: {{poly2+max+min}} on the k-th largest ===\n", .{});
    try out.print("Match (p1,p2,p3,max,min); classify k-th largest >= T_k. k=1 is max (degenerate,\n", .{});
    try out.print("matched -> constant). Watch accuracy fall toward chance as k -> center (median).\n\n", .{});
    for (0..POOL) |k| {
        Data.keys[k] = keyPS(Data.grids[k]);
        Data.idx[k] = k;
    }
    const Cmp2 = struct {
        fn lt(_: void, a: usize, b: usize) bool {
            return Data.keys[a] < Data.keys[b];
        }
    };
    std.sort.pdq(usize, &Data.idx, {}, Cmp2.lt);

    var poly2_mm: [NPOLY2 + 2]usize = undefined;
    for (0..NPOLY2) |k| poly2_mm[k] = k;
    poly2_mm[NPOLY2] = I_MAX;
    poly2_mm[NPOLY2 + 1] = I_MIN;

    try out.print("  k (rank) | T_k | matched n | {{poly2+max+min}} acc\n", .{});
    try out.print("  ---------+-----+-----------+---------------------\n", .{});
    for (2..NCELL / 2 + 1) |kk| {
        // balancing threshold for the k-th largest over the pool
        var hist = [_]u32{0} ** 64;
        for (0..POOL) |idx| hist[kthLargest(Data.grids[idx], kk)] += 1;
        var cum: u32 = 0;
        var t_k: u8 = 0;
        for (0..64) |b| {
            cum += hist[b];
            if (cum * 2 >= POOL) {
                t_k = @intCast(b + 1);
                break;
            }
        }
        // merge within key, balancing kth>=t_k vs <
        var n: usize = 0;
        var ia: usize = 0;
        while (ia < POOL) {
            var ja = ia;
            const kv = Data.keys[Data.idx[ia]];
            while (ja < POOL and Data.keys[Data.idx[ja]] == kv) ja += 1;
            var hi_buf: [256]usize = undefined;
            var lo_buf: [256]usize = undefined;
            var nh: usize = 0;
            var nl: usize = 0;
            var ta = ia;
            while (ta < ja) : (ta += 1) {
                const id = Data.idx[ta];
                if (kthLargest(Data.grids[id], kk) >= t_k) {
                    if (nh < hi_buf.len) {
                        hi_buf[nh] = id;
                        nh += 1;
                    }
                } else {
                    if (nl < lo_buf.len) {
                        lo_buf[nl] = id;
                        nl += 1;
                    }
                }
            }
            const m = @min(nh, nl);
            for (0..m) |c| {
                Data.mg[n] = Data.grids[hi_buf[c]];
                Data.my[n] = 1.0;
                n += 1;
                Data.mg[n] = Data.grids[lo_buf[c]];
                Data.my[n] = 0.0;
                n += 1;
            }
            ia = ja;
        }
        if (n < 400) {
            try out.print("  {d:8} | {d:3} | {d:9} | (thin)\n", .{ kk, t_k, n });
            continue;
        }
        const ntr = (n * 7) / 10;
        const acc = trainAndTest(Data.mg[0..ntr], Data.my[0..ntr], Data.mg[ntr..n], Data.my[ntr..n], &poly2_mm, 120, 0.05);
        const tag = if (kk == NCELL / 2) "  <- median" else "";
        try out.print("  {d:8} | {d:3} | {d:9} | {d:.3}{s}\n", .{ kk, t_k, n, acc, tag });
    }
    try out.print("\n  If acc falls from ~1 (k=2, near the max) toward 0.5 (k=8, median), the difficulty\n", .{});
    try out.print("  of an order statistic for {{poly+extremes}} grows smoothly with how CENTRAL it is.\n", .{});
}

// The PROPER gradient test: predictability of the k-th largest from a degree-d power-sum
// basis [1,p1..pd] (sum fixed by construction; NO other matching). If central ranks need a
// higher degree to reach a given accuracy than near-extremal ranks, that is the graded
// rank-complexity law the fixed-basis spectrum could not reveal.
fn runRankDegree(out: anytype) !void {
    try out.print("\n=== RANK × DEGREE: predict k-th largest from [1,p1..pd] (sum fixed, no matching) ===\n", .{});
    try out.print("Held-out accuracy. Does a CENTRAL rank need higher degree than a near-extremal one?\n\n", .{});
    try out.print("  k (rank) | T_k |  deg1 |  deg2 |  deg3\n", .{});
    try out.print("  ---------+-----+-------+-------+------\n", .{});
    const M: usize = 24000; // subset of the pool for speed
    const ks = [_]usize{ 1, 2, 3, 4, 6, 8 };
    for (ks) |kk| {
        var hist = [_]u32{0} ** 64;
        for (0..M) |i| hist[kthLargest(Data.grids[i], kk)] += 1;
        var cum: u32 = 0;
        var t_k: u8 = 0;
        for (0..64) |b| {
            cum += hist[b];
            if (cum * 2 >= M) {
                t_k = @intCast(b + 1);
                break;
            }
        }
        // balance classes by subsampling (interleaved) so deg1 (constant feature) -> 0.5
        var c1: usize = 0;
        var c0: usize = 0;
        for (0..M) |i| {
            if (kthLargest(Data.grids[i], kk) >= t_k) {
                Data.bidx1[c1] = i;
                c1 += 1;
            } else {
                Data.bidx0[c0] = i;
                c0 += 1;
            }
        }
        const nb = @min(c1, c0);
        var nn: usize = 0;
        for (0..nb) |c| {
            Data.mg[nn] = Data.grids[Data.bidx1[c]];
            Data.my[nn] = 1.0;
            nn += 1;
            Data.mg[nn] = Data.grids[Data.bidx0[c]];
            Data.my[nn] = 0.0;
            nn += 1;
        }
        const ntr = (nn * 7) / 10;
        const trg = Data.mg[0..ntr];
        const try_ = Data.my[0..ntr];
        const teg = Data.mg[ntr..nn];
        const tey = Data.my[ntr..nn];
        const deg1 = [_]usize{ 0, 1 };
        const deg2 = [_]usize{ 0, 1, 2 };
        const deg3 = [_]usize{ 0, 1, 2, 3 };
        const a1 = trainAndTestPS(trg, try_, teg, tey, &deg1, 100, 0.05);
        const a2 = trainAndTestPS(trg, try_, teg, tey, &deg2, 100, 0.05);
        const a3 = trainAndTestPS(trg, try_, teg, tey, &deg3, 100, 0.05);
        const tag = if (kk == 1) "  (max)" else if (kk == NCELL / 2) "  (median)" else "";
        try out.print("  {d:8} | {d:3} | {d:.3} | {d:.3} | {d:.3}{s}\n", .{ kk, t_k, a1, a2, a3, tag });
    }
    try out.print("\n  deg1 uses only the mean (sum, fixed) -> must be ~chance for all k. If deg2/deg3\n", .{});
    try out.print("  lift near-extremal ranks more than central ones, rank-complexity is graded in degree.\n", .{});
}

fn medianOf(g: [NCELL]u8) f64 {
    var s = g;
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    return (@as(f64, @floatFromInt(s[NCELL / 2 - 1])) + @as(f64, @floatFromInt(s[NCELL / 2]))) / 2.0;
}

fn sumSqU(g: [NCELL]u8) u32 {
    var s: u32 = 0;
    for (g) |c| s += @as(u32, c) * @as(u32, c);
    return s;
}

// Integer key matching (Σx², max, min). Σx² < 4096 (12b), max,min < 32 (5b each).
fn key3(g: [NCELL]u8) u64 {
    var mx: u8 = 0;
    var mn: u8 = 255;
    for (g) |c| {
        mx = @max(mx, c);
        mn = @min(mn, c);
    }
    return (@as(u64, sumSqU(g)) << 10) | (@as(u64, mx) << 5) | @as(u64, mn);
}

// Logistic regression over a chosen subset of feature indices; held-out test accuracy.
fn trainAndTest(grids_tr: []const [NCELL]u8, y_tr: []const f32, grids_te: []const [NCELL]u8, y_te: []const f32, active: []const usize, epochs: usize, lr: f64) f64 {
    var w = [_]f64{0} ** NF;
    var phi: [NF]f64 = undefined;
    for (0..epochs) |_| {
        for (grids_tr, y_tr) |g, yf| {
            featuresFull(g, &phi);
            var z: f64 = 0;
            for (active) |k| z += w[k] * phi[k];
            if (z > 30) z = 30;
            if (z < -30) z = -30;
            const p = 1.0 / (1.0 + @exp(-z));
            const grad = p - yf;
            for (active) |k| w[k] -= lr * grad * phi[k];
        }
    }
    var correct: u32 = 0;
    for (grids_te, y_te) |g, yf| {
        featuresFull(g, &phi);
        var z: f64 = 0;
        for (active) |k| z += w[k] * phi[k];
        const pred: f32 = if (z >= 0) 1.0 else 0.0;
        if (pred == yf) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(grids_te.len));
}

// Random sum-preserving state: start all at L, apply `moves` unit transfers (cap-bounded).
fn genState(rng: std.Random, L: u8, cap: u8, moves: usize) [NCELL]u8 {
    var g = [_]u8{L} ** NCELL;
    for (0..moves) |_| {
        const src = rng.intRangeLessThan(usize, 0, NCELL);
        const dst = rng.intRangeLessThan(usize, 0, NCELL);
        if (g[src] > 0 and g[dst] < cap) {
            g[src] -= 1;
            g[dst] += 1;
        }
    }
    return g;
}

const POOL = 120_000;
const Data = struct {
    var grids: [POOL][NCELL]u8 = undefined;
    var keys: [POOL]u64 = undefined;
    var meds: [POOL]f64 = undefined;
    var idx: [POOL]usize = undefined;
    // matched (balanced within key) output
    var mg: [POOL][NCELL]u8 = undefined;
    var my: [POOL]f32 = undefined;
    var bidx1: [POOL]usize = undefined;
    var bidx0: [POOL]usize = undefined;
    var osort: [POOL][NCELL]u8 = undefined; // per-state sorted-ascending values (order stats)
};

// Exact integer moment key up to degree d (p1=sum fixed by construction, so d>=2 uses p2..).
// p2<2^12, p3<2^15, p4<2^19 for our caps -> packs without overlap in u64.
fn keyD(g: [NCELL]u8, d: usize) u64 {
    var p2: u64 = 0;
    var p3: u64 = 0;
    var p4: u64 = 0;
    for (g) |c| {
        const x: u64 = c;
        const x2 = x * x;
        p2 += x2;
        p3 += x2 * x;
        p4 += x2 * x2;
    }
    return switch (d) {
        0, 1 => 0, // single bin (sum is fixed)
        2 => p2,
        3 => (p2 << 15) | p3,
        else => (p2 << 34) | (p3 << 19) | p4,
    };
}

// Residual uncertainty of order statistics given exact moments p1..pd (the truncated moment
// problem, measured empirically as pooled within-bin std). Markov-Krein theory predicts the
// extremes get pinned by high moments faster than central quantiles. If the residual ratio
// condStd(d,k)/uncondStd(k) falls toward 0 faster for extremal k than central k, that is the
// graded rank-complexity law the classifier version (Result 4) could not cleanly show.
fn runMoments(out: anytype) !void {
    try out.print("=== TRUNCATED MOMENT PROBLEM: residual uncertainty of rank k given moments p1..pd ===\n", .{});
    try out.print("Pooled within-bin std of the k-th largest, conditioning on EXACT integer moments.\n", .{});
    try out.print("d=1 = sum only (fixed) = unconditional baseline. Ratio = condStd(d,k)/uncondStd(k).\n\n", .{});

    // fresh pool. CAP sets the value range; loose enough that the max is not truncated,
    // tight enough that higher-moment bins stay populated.
    const L: u8 = 5;
    const CAP: u8 = 12;
    const MOVES: usize = 90;
    var rng = std.Random.DefaultPrng.init(0x371FE11);
    const r = rng.random();
    for (0..POOL) |k| {
        Data.grids[k] = genState(r, L, CAP, MOVES);
        var s = Data.grids[k];
        std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
        Data.osort[k] = s;
    }

    const ranks = [_]usize{ 1, 2, 3, 4, 6, 8 };
    const NR = ranks.len;
    var uncond: [NR]f64 = undefined;

    try out.print("  d (moments) | bins(n>=2) | std per rank (k=1 max .. k=8 median)\n", .{});
    try out.print("              |            |", .{});
    for (ranks) |kk| try out.print("   k={d}", .{kk});
    try out.print("\n  ------------+------------+{s}\n", .{"-------------------------------------"});

    for ([_]usize{ 1, 2, 3, 4 }) |d| {
        for (0..POOL) |k| Data.keys[k] = keyD(Data.grids[k], d);
        for (0..POOL) |k| Data.idx[k] = k;
        const Cmp3 = struct {
            fn lt(_: void, a: usize, b: usize) bool {
                return Data.keys[a] < Data.keys[b];
            }
        };
        std.sort.pdq(usize, &Data.idx, {}, Cmp3.lt);

        var totSS = [_]f64{0} ** NR;
        var dof = [_]f64{0} ** NR;
        var nbins: usize = 0;
        var i: usize = 0;
        while (i < POOL) {
            var j = i;
            const kv = Data.keys[Data.idx[i]];
            while (j < POOL and Data.keys[Data.idx[j]] == kv) j += 1;
            const nb = j - i;
            if (nb >= 2) {
                nbins += 1;
                for (ranks, 0..) |kk, ri| {
                    var sum: f64 = 0;
                    var sq: f64 = 0;
                    var t = i;
                    while (t < j) : (t += 1) {
                        const v: f64 = @floatFromInt(Data.osort[Data.idx[t]][NCELL - kk]);
                        sum += v;
                        sq += v * v;
                    }
                    const nf: f64 = @floatFromInt(nb);
                    totSS[ri] += sq - sum * sum / nf;
                    dof[ri] += nf - 1.0;
                }
            }
            i = j;
        }
        try out.print("  {d:11} | {d:10} |", .{ d, nbins });
        for (0..NR) |ri| {
            const std_k = if (dof[ri] > 0) @sqrt(totSS[ri] / dof[ri]) else 0;
            if (d == 1) uncond[ri] = std_k;
            try out.print(" {d:.3}", .{std_k});
        }
        try out.print("\n", .{});
    }

    // ratio table (residual fraction of uncertainty remaining)
    try out.print("\n  residual RATIO condStd(d,k)/uncondStd(k)  (lower = better pinned by d moments):\n", .{});
    try out.print("  d (moments) |", .{});
    for (ranks) |kk| try out.print("   k={d}", .{kk});
    try out.print("\n  ------------+{s}\n", .{"-------------------------------------"});
    for ([_]usize{ 2, 3, 4 }) |d| {
        for (0..POOL) |k| Data.keys[k] = keyD(Data.grids[k], d);
        for (0..POOL) |k| Data.idx[k] = k;
        const Cmp4 = struct {
            fn lt(_: void, a: usize, b: usize) bool {
                return Data.keys[a] < Data.keys[b];
            }
        };
        std.sort.pdq(usize, &Data.idx, {}, Cmp4.lt);
        var totSS = [_]f64{0} ** NR;
        var dof = [_]f64{0} ** NR;
        var i: usize = 0;
        while (i < POOL) {
            var j = i;
            const kv = Data.keys[Data.idx[i]];
            while (j < POOL and Data.keys[Data.idx[j]] == kv) j += 1;
            const nb = j - i;
            if (nb >= 2) {
                for (ranks, 0..) |kk, ri| {
                    var sum: f64 = 0;
                    var sq: f64 = 0;
                    var t = i;
                    while (t < j) : (t += 1) {
                        const v: f64 = @floatFromInt(Data.osort[Data.idx[t]][NCELL - kk]);
                        sum += v;
                        sq += v * v;
                    }
                    const nf: f64 = @floatFromInt(nb);
                    totSS[ri] += sq - sum * sum / nf;
                    dof[ri] += nf - 1.0;
                }
            }
            i = j;
        }
        try out.print("  {d:11} |", .{d});
        for (0..NR) |ri| {
            const std_k = if (dof[ri] > 0) @sqrt(totSS[ri] / dof[ri]) else 0;
            const ratio = if (uncond[ri] > 0) std_k / uncond[ri] else 0;
            try out.print(" {d:.3}", .{ratio});
        }
        try out.print("\n", .{});
    }
    try out.print("\n  READING: the residual RATIO rises monotonically from max (k=1) to median (k=8) at\n", .{});
    try out.print("  each d -> moments pin the EXTREMES faster than the CENTER (Markov-Krein graded law).\n", .{});
    try out.print("  At d=2 the median ratio ~1.0: mean+variance say almost nothing about the median.\n", .{});
    try out.print("  (Use the RATIO, not absolute std: the max's larger natural spread confounds the\n", .{});
    try out.print("  absolute measure; with a truncated cap the absolute view even inverts.)\n", .{});
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    var args = std.process.args();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "moments")) {
            try runMoments(out);
            return;
        }
    }

    try out.print("=== NEW: is the MEDIAN outside the closure of {{poly2 + max + min}}? ===\n", .{});
    try out.print("Matched sum (fixed), Σx², max, min between median-high and median-low classes.\n", .{});
    try out.print("If poly2+max+min stays at chance while poly2+median ~1.0, extremal features do\n", .{});
    try out.print("NOT reach the central one -> a new closure split (extremal vs rank statistics).\n\n", .{});

    const L: u8 = 4;
    const CAP: u8 = 12;
    const MOVES: usize = 140;
    var rng = std.Random.DefaultPrng.init(0x0DDBA11);
    const r = rng.random();

    for (0..POOL) |k| {
        Data.grids[k] = genState(r, L, CAP, MOVES);
        Data.keys[k] = key3(Data.grids[k]);
        Data.meds[k] = medianOf(Data.grids[k]);
        Data.idx[k] = k;
    }

    // median distribution -> pick the threshold that best balances the pool
    var hist = [_]u32{0} ** 33; // median*2 in 0..32
    for (Data.meds) |m| hist[@intFromFloat(m * 2.0)] += 1;
    try out.print("  median histogram (value : count):\n", .{});
    var cum: u32 = 0;
    var t_med: f64 = @as(f64, L);
    for (0..33) |b| {
        if (hist[b] == 0) continue;
        try out.print("    {d:.1} : {d}\n", .{ @as(f64, @floatFromInt(b)) / 2.0, hist[b] });
        cum += hist[b];
        if (cum * 2 < POOL) t_med = @as(f64, @floatFromInt(b)) / 2.0 + 0.5; // threshold just above the lower half
    }
    try out.print("  chosen median threshold T_med = {d:.2} (class1: median >= T_med)\n", .{t_med});

    // sort by key, then bin-merge: within each key, balance median>=T vs median<T
    const Cmp = struct {
        fn lt(_: void, a: usize, b: usize) bool {
            return Data.keys[a] < Data.keys[b];
        }
    };
    std.sort.pdq(usize, &Data.idx, {}, Cmp.lt);

    var n: usize = 0;
    var i: usize = 0;
    while (i < POOL) {
        var j = i;
        const kv = Data.keys[Data.idx[i]];
        while (j < POOL and Data.keys[Data.idx[j]] == kv) j += 1;
        // within run [i,j): partition by median class, take min count from each
        var hi_buf: [256]usize = undefined;
        var lo_buf: [256]usize = undefined;
        var nh: usize = 0;
        var nl: usize = 0;
        var t = i;
        while (t < j) : (t += 1) {
            const id = Data.idx[t];
            if (Data.meds[id] >= t_med) {
                if (nh < hi_buf.len) {
                    hi_buf[nh] = id;
                    nh += 1;
                }
            } else {
                if (nl < lo_buf.len) {
                    lo_buf[nl] = id;
                    nl += 1;
                }
            }
        }
        const m = @min(nh, nl);
        for (0..m) |c| {
            Data.mg[n] = Data.grids[hi_buf[c]];
            Data.my[n] = 1.0;
            n += 1;
            Data.mg[n] = Data.grids[lo_buf[c]];
            Data.my[n] = 0.0;
            n += 1;
        }
        i = j;
    }

    try out.print("\n  matched balanced samples n = {d}\n", .{n});
    if (n < 400) {
        try out.print("  overlap too thin to conclude; widen pool or relax the matched key.\n", .{});
        return;
    }

    const ntr = (n * 7) / 10;
    const tr_g = Data.mg[0..ntr];
    const tr_y = Data.my[0..ntr];
    const te_g = Data.mg[ntr..n];
    const te_y = Data.my[ntr..n];

    // build active-index sets
    var poly2: [NPOLY2]usize = undefined;
    for (0..NPOLY2) |k| poly2[k] = k;
    var poly2_mm: [NPOLY2 + 2]usize = undefined;
    for (0..NPOLY2) |k| poly2_mm[k] = k;
    poly2_mm[NPOLY2] = I_MAX;
    poly2_mm[NPOLY2 + 1] = I_MIN;
    var poly2_med: [NPOLY2 + 1]usize = undefined;
    for (0..NPOLY2) |k| poly2_med[k] = k;
    poly2_med[NPOLY2] = I_MED;
    var poly2_all: [NPOLY2 + 3]usize = undefined;
    for (0..NPOLY2) |k| poly2_all[k] = k;
    poly2_all[NPOLY2] = I_MAX;
    poly2_all[NPOLY2 + 1] = I_MIN;
    poly2_all[NPOLY2 + 2] = I_MED;

    const EPOCHS = 120;
    const LR = 0.05;
    const a_poly2 = trainAndTest(tr_g, tr_y, te_g, te_y, &poly2, EPOCHS, LR);
    const a_mm = trainAndTest(tr_g, tr_y, te_g, te_y, &poly2_mm, EPOCHS, LR);
    const a_med = trainAndTest(tr_g, tr_y, te_g, te_y, &poly2_med, EPOCHS, LR);
    const a_all = trainAndTest(tr_g, tr_y, te_g, te_y, &poly2_all, EPOCHS, LR);

    try out.print("\n  basis                    | held-out accuracy\n", .{});
    try out.print("  -------------------------+------------------\n", .{});
    try out.print("  poly2                    | {d:.3}\n", .{a_poly2});
    try out.print("  poly2 + max + min        | {d:.3}   <-- do extremal features reach the median?\n", .{a_mm});
    try out.print("  poly2 + median           | {d:.3}\n", .{a_med});
    try out.print("  poly2 + max + min + med  | {d:.3}\n", .{a_all});

    try out.print("\n  READING:\n", .{});
    if (a_mm < 0.6 and a_med > 0.9) {
        try out.print("  >>> CONJECTURE SUPPORTED: poly2+max+min ~chance ({d:.3}) but poly2+median ~1.0\n", .{a_mm});
        try out.print("      ({d:.3}). The median is NOT reducible to extremal features + low-degree poly.\n", .{a_med});
        try out.print("      New closure split: extremal order stats are 1-feature simple; the median\n", .{});
        try out.print("      (a central/rank statistic) needs genuine rank information.\n", .{});
    } else if (a_mm > 0.7) {
        try out.print("  >>> CONJECTURE REFUTED: poly2+max+min reaches the median ({d:.3}). The extremes\n", .{a_mm});
        try out.print("      DO help — either via leakage I failed to match, or the median IS reducible.\n", .{});
    } else {
        try out.print("  >>> inconclusive (poly2+max+min={d:.3}, poly2+median={d:.3}).\n", .{ a_mm, a_med });
    }

    // ---- DEGREE-GENERAL STRENGTHENING: match p1,p2,p3 AND max AND min exactly ----
    // Minimal symmetric basis [1,p1,p2,p3]. If [1,p1,p2,p3,max,min] is STILL chance while
    // [1,p1,p2,p3,median] ~1.0, the extremes give nothing even at degree 3: the median is
    // outside {degree-3 symmetric poly + max + min}, not just degree 2.
    try out.print("\n=== DEGREE-GENERAL: match p1,p2,p3 AND max AND min (minimal symmetric basis) ===\n", .{});
    for (0..POOL) |k| {
        Data.keys[k] = keyPS(Data.grids[k]);
        Data.idx[k] = k;
    }
    std.sort.pdq(usize, &Data.idx, {}, Cmp.lt);
    var n2: usize = 0;
    var ia: usize = 0;
    while (ia < POOL) {
        var ja = ia;
        const kv = Data.keys[Data.idx[ia]];
        while (ja < POOL and Data.keys[Data.idx[ja]] == kv) ja += 1;
        var hi_buf: [256]usize = undefined;
        var lo_buf: [256]usize = undefined;
        var nh: usize = 0;
        var nl: usize = 0;
        var ta = ia;
        while (ta < ja) : (ta += 1) {
            const id = Data.idx[ta];
            if (Data.meds[id] >= t_med) {
                if (nh < hi_buf.len) {
                    hi_buf[nh] = id;
                    nh += 1;
                }
            } else {
                if (nl < lo_buf.len) {
                    lo_buf[nl] = id;
                    nl += 1;
                }
            }
        }
        const m = @min(nh, nl);
        for (0..m) |c| {
            Data.mg[n2] = Data.grids[hi_buf[c]];
            Data.my[n2] = 1.0;
            n2 += 1;
            Data.mg[n2] = Data.grids[lo_buf[c]];
            Data.my[n2] = 0.0;
            n2 += 1;
        }
        ia = ja;
    }
    try out.print("  matched (p1,p2,p3,max,min) balanced samples n = {d}\n", .{n2});
    if (n2 < 400) {
        try out.print("  overlap too thin at this finer key; the degree-2 result above stands.\n", .{});
        return;
    }
    const ntr2 = (n2 * 7) / 10;
    const tr2_g = Data.mg[0..ntr2];
    const tr2_y = Data.my[0..ntr2];
    const te2_g = Data.mg[ntr2..n2];
    const te2_y = Data.my[ntr2..n2];
    const ps3 = [_]usize{ 0, 1, 2, 3 };
    const ps3_mm = [_]usize{ 0, 1, 2, 3, 4, 5 };
    const ps3_med = [_]usize{ 0, 1, 2, 3, 6 };
    const b_ps3 = trainAndTestPS(tr2_g, tr2_y, te2_g, te2_y, &ps3, 150, 0.05);
    const b_mm = trainAndTestPS(tr2_g, tr2_y, te2_g, te2_y, &ps3_mm, 150, 0.05);
    const b_med = trainAndTestPS(tr2_g, tr2_y, te2_g, te2_y, &ps3_med, 150, 0.05);
    try out.print("  [1,p1,p2,p3]             | {d:.3}\n", .{b_ps3});
    try out.print("  [1,p1,p2,p3] + max + min | {d:.3}   <-- extremes at degree 3\n", .{b_mm});
    try out.print("  [1,p1,p2,p3] + median    | {d:.3}\n", .{b_med});
    if (b_mm < 0.6 and b_med > 0.9) {
        try out.print("  >>> DEGREE-GENERAL SUPPORT: even with p1,p2,p3,max,min matched, the extremes give\n", .{});
        try out.print("      nothing ({d:.3}); only the rank feature (median) crosses ({d:.3}).\n", .{ b_mm, b_med });
    } else {
        try out.print("  >>> degree-3: extremes={d:.3}, median={d:.3} (interpret w.r.t. overlap n={d}).\n", .{ b_mm, b_med, n2 });
    }

    try runRankSpectrum(out);
    try runRankDegree(out);
}
