// Predicate Tomography — Frontier 10
//
// For 12 predicates × 9 substrates, measure accuracy and build a fingerprint table.
// Core question: does the accuracy profile across substrates uniquely identify
// the predicate's algebraic class? And which predicates defeat all known substrates?

const std = @import("std");
const math = std.math;

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 3600;
const NTRAIN: usize = NSAMP * 4 / 5; // 2880
const NTEST: usize = NSAMP - NTRAIN; //  720
const LR: f64 = 0.03;
const NITERS: usize = 1800;
const MAX_FEAT: usize = 50;
const NGRID: usize = 500;
const PI: f64 = math.pi;

// Global buffers — avoid stack overflow
var g_cells: [NSAMP][NCELL]u8 = undefined;
var g_labels: [NSAMP]bool = undefined;
var g_feat: [NSAMP][MAX_FEAT]f64 = undefined;
var g_stat: [NSAMP]usize = undefined;

// ─── RNG ──────────────────────────────────────────────────────────────────────
fn lcg(s: *u64) u64 {
    s.* ^= s.* >> 12;
    s.* ^= s.* << 25;
    s.* ^= s.* >> 27;
    return s.* *% 0x2545F4914F6CDD1D;
}

// ─── inner statistics ─────────────────────────────────────────────────────────
fn statCount(c: [NCELL]u8) usize {
    var n: usize = 0;
    for (c) |v| if (v >= THRESH) { n += 1; };
    return n;
}

fn statInv(c: [NCELL]u8) usize {
    var inv: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        if (c[i] > c[j]) inv += 1;
    };
    return inv;
}

fn statRange(c: [NCELL]u8) usize {
    var mn = c[0];
    var mx = c[0];
    for (c[1..]) |v| {
        if (v < mn) mn = v;
        if (v > mx) mx = v;
    }
    return mx - mn;
}

fn statVar4(c: [NCELL]u8) usize {
    // sum of squared pairwise differences / NCELL — integer variance proxy
    var s: u32 = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        const d: i32 = @as(i32, c[i]) - @as(i32, c[j]);
        s += @intCast(d * d);
    };
    return @intCast(s / NCELL);
}

// ─── predicates ───────────────────────────────────────────────────────────────

// Group A — count/spectral domain
fn predCountParity(c: [NCELL]u8) bool { return (statCount(c) & 1) == 1; }
fn predCountPeriod3(c: [NCELL]u8) bool { return statCount(c) % 3 == 0; }
fn predCountAnd(c: [NCELL]u8) bool { return predCountParity(c) and predCountPeriod3(c); }
fn predCountXor(c: [NCELL]u8) bool { return predCountParity(c) != predCountPeriod3(c); }

// Group B — relational domain
fn predInvParity(c: [NCELL]u8) bool { return (statInv(c) & 1) == 1; }
fn predOrientation(c: [NCELL]u8) bool { return c[0] > c[1]; }
fn predMaxFirst(c: [NCELL]u8) bool {
    for (c[1..]) |v| if (v > c[0]) return false;
    return true;
}

// Group C — distributional domain (novel — no prior frontier tested these)
fn predVarianceHigh(c: [NCELL]u8) bool { return statVar4(c) >= 10; }
fn predRangeHigh(c: [NCELL]u8) bool { return statRange(c) >= 4; }

// Group D — bit parity (degree ladder)
fn predK2Par(c: [NCELL]u8) bool {
    return ((if (c[0] >= THRESH) @as(u1, 1) else 0) ^
        (if (c[1] >= THRESH) @as(u1, 1) else 0)) == 1;
}
fn predK3Par(c: [NCELL]u8) bool {
    var p: u1 = 0;
    for (c[0..3]) |v| p ^= if (v >= THRESH) @as(u1, 1) else 0;
    return p == 1;
}
fn predK4Par(c: [NCELL]u8) bool {
    var p: u1 = 0;
    for (c[0..4]) |v| p ^= if (v >= THRESH) @as(u1, 1) else 0;
    return p == 1;
}

// ─── feature extractors ───────────────────────────────────────────────────────
fn featLinear(c: [NCELL]u8, f: *[MAX_FEAT]f64) usize {
    for (c, 0..) |v, i| f[i] = @as(f64, @floatFromInt(v)) / @as(f64, VMAX);
    return NCELL;
}

fn featDegree2(c: [NCELL]u8, f: *[MAX_FEAT]f64) usize {
    var k: usize = 0;
    for (c) |v| {
        f[k] = @as(f64, @floatFromInt(v)) / @as(f64, VMAX);
        k += 1;
    }
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        f[k] = @as(f64, @floatFromInt(c[i])) * @as(f64, @floatFromInt(c[j])) /
            (@as(f64, VMAX) * @as(f64, VMAX));
        k += 1;
    };
    return k; // 6 + 15 = 21
}

fn featDegree3(c: [NCELL]u8, f: *[MAX_FEAT]f64) usize {
    var k = featDegree2(c, f);
    const vm3 = @as(f64, VMAX) * @as(f64, VMAX) * @as(f64, VMAX);
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |l| {
        f[k] = @as(f64, @floatFromInt(c[i])) * @as(f64, @floatFromInt(c[j])) *
            @as(f64, @floatFromInt(c[l])) / vm3;
        k += 1;
    };
    return k; // 21 + 20 = 41
}

fn featPairwiseDiff(c: [NCELL]u8, f: *[MAX_FEAT]f64) usize {
    var k: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        f[k] = (@as(f64, @floatFromInt(c[i])) - @as(f64, @floatFromInt(c[j]))) / @as(f64, VMAX);
        k += 1;
    };
    return k; // 15
}

fn featSorted(c: [NCELL]u8, f: *[MAX_FEAT]f64) usize {
    var s = c;
    for (0..NCELL) |i| for (0..NCELL - 1 - i) |j| {
        if (s[j] > s[j + 1]) {
            const tmp = s[j];
            s[j] = s[j + 1];
            s[j + 1] = tmp;
        }
    };
    for (s, 0..) |v, i| f[i] = @as(f64, @floatFromInt(v)) / @as(f64, VMAX);
    return NCELL;
}

fn featClifford(c: [NCELL]u8, f: *[MAX_FEAT]f64) usize {
    // grade-2[geo(Ci,Cj)] = sin(θj − θi) with shared basis, θ = π*v/VMAX
    var k: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        const ti = PI * @as(f64, @floatFromInt(c[i])) / @as(f64, VMAX);
        const tj = PI * @as(f64, @floatFromInt(c[j])) / @as(f64, VMAX);
        f[k] = @sin(tj - ti);
        k += 1;
    };
    return k; // 15
}

// ─── logistic regression ──────────────────────────────────────────────────────
fn sigmoid(x: f64) f64 {
    return 1.0 / (1.0 + @exp(-x));
}

fn trainTest(nfeat: usize) f64 {
    var w = [_]f64{0.0} ** MAX_FEAT;
    var b: f64 = 0.0;

    for (0..NITERS) |_| {
        var dw = [_]f64{0.0} ** MAX_FEAT;
        var db: f64 = 0.0;
        for (0..NTRAIN) |i| {
            var logit = b;
            for (0..nfeat) |j| logit += w[j] * g_feat[i][j];
            const err = sigmoid(logit) - if (g_labels[i]) @as(f64, 1.0) else 0.0;
            for (0..nfeat) |j| dw[j] += err * g_feat[i][j];
            db += err;
        }
        const nf: f64 = @floatFromInt(NTRAIN);
        for (0..nfeat) |j| w[j] -= LR * dw[j] / nf;
        b -= LR * db / nf;
    }

    var correct: usize = 0;
    for (NTRAIN..NSAMP) |i| {
        var logit = b;
        for (0..nfeat) |j| logit += w[j] * g_feat[i][j];
        if ((logit >= 0.0) == g_labels[i]) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
}

fn substrateLogistic(extractor: *const fn ([NCELL]u8, *[MAX_FEAT]f64) usize) f64 {
    var nfeat: usize = 0;
    for (0..NSAMP) |i| nfeat = extractor(g_cells[i], &g_feat[i]);
    const acc = trainTest(nfeat);
    return @max(acc, 1.0 - acc); // report majority-class-corrected accuracy
}

// ─── spectral helpers ─────────────────────────────────────────────────────────
fn bestOmegaByPower(max_stat: usize) f64 {
    const cap = @min(max_stat + 1, 64);
    var cnt = [_]u32{0} ** 64;
    var pos = [_]u32{0} ** 64;
    for (0..NTRAIN) |i| {
        const s = @min(g_stat[i], cap - 1);
        cnt[s] += 1;
        if (g_labels[i]) pos[s] += 1;
    }
    var ey = [_]f64{0.5} ** 64;
    for (0..cap) |s| if (cnt[s] > 0) {
        ey[s] = @as(f64, @floatFromInt(pos[s])) / @as(f64, @floatFromInt(cnt[s]));
    };
    var best_w: f64 = PI;
    var best_p: f64 = -1;
    for (1..NGRID + 1) |gi| {
        const w = PI * @as(f64, @floatFromInt(gi)) / @as(f64, @floatFromInt(NGRID));
        var re: f64 = 0;
        var im: f64 = 0;
        var wt: f64 = 0;
        for (0..cap) |s| if (cnt[s] > 0) {
            const sf: f64 = @floatFromInt(s);
            re += ey[s] * @cos(w * sf);
            im += ey[s] * @sin(w * sf);
            wt += 1;
        };
        const p = if (wt > 0) (re * re + im * im) / wt else 0;
        if (p > best_p) {
            best_p = p;
            best_w = w;
        }
    }
    return best_w;
}

fn bestOmegaByAccuracy() f64 {
    var best_w: f64 = PI;
    var best_acc: f64 = 0;
    for (1..NGRID + 1) |gi| {
        const w = PI * @as(f64, @floatFromInt(gi)) / @as(f64, @floatFromInt(NGRID));
        var correct: usize = 0;
        for (0..NTRAIN) |i| {
            const sf: f64 = @floatFromInt(g_stat[i]);
            if ((@cos(w * sf) >= 0) == g_labels[i]) correct += 1;
        }
        var acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTRAIN));
        acc = @max(acc, 1.0 - acc);
        if (acc > best_acc) {
            best_acc = acc;
            best_w = w;
        }
    }
    return best_w;
}

fn evalOmega(w: f64) f64 {
    var correct: usize = 0;
    for (NTRAIN..NSAMP) |i| {
        const sf: f64 = @floatFromInt(g_stat[i]);
        if ((@cos(w * sf) >= 0) == g_labels[i]) correct += 1;
    }
    const acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
    return @max(acc, 1.0 - acc);
}

fn substrateSpectralPower() f64 {
    for (0..NSAMP) |i| g_stat[i] = statCount(g_cells[i]);
    return evalOmega(bestOmegaByPower(NCELL));
}

fn substrateSpectralGrid() f64 {
    for (0..NSAMP) |i| g_stat[i] = statCount(g_cells[i]);
    return evalOmega(bestOmegaByAccuracy());
}

// Staged: try multiple inner quantities, return best accuracy-grid result
fn substrateStaged() f64 {
    var best: f64 = 0;

    // count
    for (0..NSAMP) |i| g_stat[i] = statCount(g_cells[i]);
    best = @max(best, evalOmega(bestOmegaByAccuracy()));

    // inversion count
    for (0..NSAMP) |i| g_stat[i] = statInv(g_cells[i]);
    best = @max(best, evalOmega(bestOmegaByAccuracy()));

    // range
    for (0..NSAMP) |i| g_stat[i] = statRange(g_cells[i]);
    best = @max(best, evalOmega(bestOmegaByAccuracy()));

    // variance proxy
    for (0..NSAMP) |i| g_stat[i] = statVar4(g_cells[i]);
    best = @max(best, evalOmega(bestOmegaByAccuracy()));

    return best;
}

// ─── main ─────────────────────────────────────────────────────────────────────
pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const Pred = struct {
        name: *const [16:0]u8,
        fn_: *const fn ([NCELL]u8) bool,
        group: u8,
    };

    const preds = [_]Pred{
        .{ .name = "count-parity    ", .fn_ = predCountParity,   .group = 'A' },
        .{ .name = "count-period3   ", .fn_ = predCountPeriod3,  .group = 'A' },
        .{ .name = "count-AND       ", .fn_ = predCountAnd,      .group = 'A' },
        .{ .name = "count-XOR       ", .fn_ = predCountXor,      .group = 'A' },
        .{ .name = "inv-parity      ", .fn_ = predInvParity,     .group = 'B' },
        .{ .name = "orientation     ", .fn_ = predOrientation,   .group = 'B' },
        .{ .name = "max-first       ", .fn_ = predMaxFirst,      .group = 'B' },
        .{ .name = "variance-high   ", .fn_ = predVarianceHigh,  .group = 'C' },
        .{ .name = "range-high      ", .fn_ = predRangeHigh,     .group = 'C' },
        .{ .name = "k2-parity       ", .fn_ = predK2Par,         .group = 'D' },
        .{ .name = "k3-parity       ", .fn_ = predK3Par,         .group = 'D' },
        .{ .name = "k4-parity       ", .fn_ = predK4Par,         .group = 'D' },
    };

    try stdout.print(
        "PREDICATE TOMOGRAPHY  NCELL={d}  VMAX={d}  THRESH={d}  NSAMP={d}\n\n",
        .{ NCELL, VMAX, THRESH, NSAMP },
    );
    try stdout.print(
        "G  {s}  lin    d2     d3     pair   sort   cliff  sp-pow sp-grd staged  pos%\n",
        .{"predicate      "},
    );
    try stdout.print("{s}\n", .{"─" ** 100});

    var rng: u64 = 0xFEEDFACE_DEADC0DE;

    for (preds) |pred| {
        // Generate data
        var npos: usize = 0;
        for (0..NSAMP) |i| {
            for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
            g_labels[i] = pred.fn_(g_cells[i]);
            if (g_labels[i]) npos += 1;
        }

        const a_lin = substrateLogistic(featLinear);
        const a_d2 = substrateLogistic(featDegree2);
        const a_d3 = substrateLogistic(featDegree3);
        const a_pair = substrateLogistic(featPairwiseDiff);
        const a_sort = substrateLogistic(featSorted);
        const a_cliff = substrateLogistic(featClifford);
        const a_sppow = substrateSpectralPower();
        const a_spgrd = substrateSpectralGrid();
        const a_staged = substrateStaged();
        const pos_pct = @as(f64, @floatFromInt(npos)) * 100.0 / @as(f64, @floatFromInt(NSAMP));

        try stdout.print(
            "{c}  {s}  {d:.3}  {d:.3}  {d:.3}  {d:.3}  {d:.3}  {d:.3}  {d:.3}  {d:.3}  {d:.3}   {d:.0}%\n",
            .{ pred.group, pred.name, a_lin, a_d2, a_d3, a_pair, a_sort, a_cliff,
               a_sppow, a_spgrd, a_staged, pos_pct },
        );
    }

    try stdout.print("\n{s}\n", .{"─" ** 100});
    try stdout.print("Substrates: lin=degree-1 logistic  d2=degree-2  d3=degree-3\n", .{});
    try stdout.print("            pair=pairwise-diff  sort=sorted-cells  cliff=Clifford-grade2\n", .{});
    try stdout.print("            sp-pow=spectral-power-peak  sp-grd=spectral-accuracy-grid\n", .{});
    try stdout.print("            staged=best of {{count,inv,range,var4}} with accuracy-grid\n", .{});
    try stdout.print("\nProfile uniqueness: each row is a fingerprint — collisions mean substrate aliasing.\n", .{});
    try stdout.print("Ceiling gaps: predicates where max(row) < 0.95 have no solution in the current library.\n", .{});
}
