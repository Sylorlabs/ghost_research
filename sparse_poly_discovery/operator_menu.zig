//! Direction 1 prototype — unified operator menu: spectral vs Walsh vs Clifford grade-2.
//!
//! Given a black-box predicate signal (labels over cell grids), each discovery operator
//! proposes its best feature and reports held-out test accuracy. The menu argmax picks
//! the winner — the first step toward wiring operator selection into inner_forge's
//! promote loop when monomial forging saturates.
//!
//! Test zoo (each predicate has a known best operator):
//!   P1 parity-of-count   → spectral peak on count signal (ω=π)
//!   P2 hidden pair (2,5) → Walsh coefficient χ_{2,5}
//!   P3 oriented sign(v1−v0) → Clifford grade-2 sin(θ(v1−v0))
//!
//! Run: zig build operator-menu --release=fast

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const THETA: f64 = 0.40;
const NSAMP: usize = 5000;
const NTR: usize = 3500;
const NVA: usize = 4250;
const DOM: usize = 1 << NCELL;

const Operator = enum { spectral, walsh, clifford };
const op_name = [_][]const u8{ "spectral", "walsh", "clifford_g2" };

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn accLogit(feat: []const f64, Y: []const f64, lo: usize, hi: usize) f64 {
    var w: [2]f64 = .{ 0.0, 0.0 };
    for (0..80) |_| for (0..NTR) |s| {
        const e = sigmoid(w[0] * feat[s] + w[1]) - Y[s];
        w[0] -= 0.1 * e * feat[s];
        w[1] -= 0.1 * e;
    };
    var c: usize = 0;
    for (lo..hi) |s| {
        if ((w[0] * feat[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

fn signPattern(g: [NCELL]u8) u8 {
    var p: u8 = 0;
    for (0..NCELL) |i| {
        if (g[i] >= THRESH) p |= @as(u8, 1) << @intCast(i);
    }
    return p;
}

fn chi(S: u8, p: u8) f64 {
    const neg = @popCount(S & ~p);
    return if (neg & 1 == 0) 1.0 else -1.0;
}

fn countGE(g: [NCELL]u8) f64 {
    var c: usize = 0;
    for (g) |v| if (v >= THRESH) {
        c += 1;
    };
    return @floatFromInt(c);
}

// Cl(2,0) grade-2 blade of geo(C0,C1) with shared-basis encoding
fn cliffordG2(g: [NCELL]u8) f64 {
    const v0: f64 = @floatFromInt(g[0]);
    const v1: f64 = @floatFromInt(g[1]);
    return @sin(THETA * (v1 - v0));
}

const Pred = enum { parity_count, hidden_pair, oriented };
const pred_name = [_][]const u8{ "parity-of-count", "hidden pair (2,5)", "oriented sign(v1-v0)" };
const pred_expected = [_]Operator{ .spectral, .walsh, .clifford };

fn label(g: [NCELL]u8, p: Pred) f64 {
    return switch (p) {
        .parity_count => blk: {
            var c: usize = 0;
            for (g) |v| if (v >= THRESH) {
        c += 1;
    };
            break :blk if (c & 1 == 0) 0.0 else 1.0;
        },
        .hidden_pair => if (((g[2] >= THRESH) != (g[5] >= THRESH))) 1.0 else 0.0,
        .oriented => if (g[1] > g[0]) 1.0 else 0.0,
    };
}

// ── Operator 1: spectral peak on count signal ──────────────────────────────
fn opSpectral(grid: []const [NCELL]u8, Y: []const f64, feat_out: []f64) struct { val: f64, tst: f64, omega: f64 } {
    const CMAX = NCELL + 1;
    var fsum = [_]f64{0} ** CMAX;
    var ncnt = [_]f64{0} ** CMAX;
    for (0..NTR) |s| {
        const c: usize = @intFromFloat(countGE(grid[s]));
        fsum[c] += Y[s];
        ncnt[c] += 1;
    }
    var f = [_]f64{0} ** CMAX;
    var fbar: f64 = 0;
    var ntot: f64 = 0;
    for (0..CMAX) |c| {
        if (ncnt[c] > 0) f[c] = fsum[c] / ncnt[c];
        fbar += fsum[c];
        ntot += ncnt[c];
    }
    fbar /= ntot;

    const NF = 200;
    var peak_pw: f64 = -1;
    var peak_w: f64 = 0;
    var i: usize = 1;
    while (i <= NF) : (i += 1) {
        const w = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
        var re: f64 = 0;
        var im: f64 = 0;
        for (0..CMAX) |c| {
            if (ncnt[c] == 0) continue;
            const amp = ncnt[c] * (f[c] - fbar);
            const cc: f64 = @floatFromInt(c);
            re += amp * @cos(w * cc);
            im += amp * @sin(w * cc);
        }
        const pw = re * re + im * im;
        if (pw > peak_pw) {
            peak_pw = pw;
            peak_w = w;
        }
    }
    for (0..NSAMP) |s| feat_out[s] = @cos(peak_w * countGE(grid[s]));
    return .{ .val = accLogit(feat_out, Y, NTR, NVA), .tst = accLogit(feat_out, Y, NVA, NSAMP), .omega = peak_w };
}

// ── Operator 2: Walsh — argmax |f̂(S)| over all subsets (n=8 exact) ─────────
fn opWalsh(grid: []const [NCELL]u8, Y: []const f64, feat_out: []f64) struct { val: f64, tst: f64, bestS: u8 } {
    // estimate f̂(S) from train samples
    var est = [_]f64{0} ** DOM;
    for (0..NTR) |s| {
        const p = signPattern(grid[s]);
        const g: f64 = if (Y[s] > 0.5) @as(f64, -1.0) else @as(f64, 1.0); // ±1 signal
        for (0..DOM) |S| est[S] += g * chi(@intCast(S), p);
    }
    var best_abs: f64 = -1;
    var bestS: u8 = 0;
    for (0..DOM) |S| {
        const v = @abs(est[S]) / @as(f64, @floatFromInt(NTR));
        if (v > best_abs) {
            best_abs = v;
            bestS = @intCast(S);
        }
    }
    for (0..NSAMP) |s| {
        const p = signPattern(grid[s]);
        feat_out[s] = chi(bestS, p);
    }
    return .{ .val = accLogit(feat_out, Y, NTR, NVA), .tst = accLogit(feat_out, Y, NVA, NSAMP), .bestS = bestS };
}

// ── Operator 3: Clifford grade-2 on focal pair (0,1) ─────────────────────────
fn opClifford(grid: []const [NCELL]u8, Y: []const f64, feat_out: []f64) struct { val: f64, tst: f64 } {
    for (0..NSAMP) |s| feat_out[s] = cliffordG2(grid[s]);
    return .{ .val = accLogit(feat_out, Y, NTR, NVA), .tst = accLogit(feat_out, Y, NVA, NSAMP) };
}

fn fmtSet(buf: []u8, S: u8) []const u8 {
    var w: usize = 0;
    buf[w] = '{';
    w += 1;
    var first = true;
    for (0..NCELL) |i| {
        if (S & (@as(u8, 1) << @intCast(i)) != 0) {
            if (!first) {
                buf[w] = ',';
                w += 1;
            }
            buf[w] = '0' + @as(u8, @intCast(i));
            w += 1;
            first = false;
        }
    }
    buf[w] = '}';
    w += 1;
    return buf[0..w];
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0xC0FFEE123456);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    const Y = try alloc.alloc([]f64, 3);
    const feat = try alloc.alloc(f64, NSAMP);
    for (0..3) |pi| Y[pi] = try alloc.alloc(f64, NSAMP);

    for (0..NSAMP) |s| {
        for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
        inline for (0..3) |pi| Y[pi][s] = label(grid[s], @enumFromInt(pi));
    }

    try out.print("=== Direction 1: unified operator menu (spectral vs Walsh vs Clifford) ===\n\n", .{});
    try out.print("Selection: argmax validation accuracy; report held-out test. Split {d}/{d}/{d}.\n\n", .{ NTR, NVA - NTR, NSAMP - NVA });

    var setbuf: [32]u8 = undefined;
    var n_correct: usize = 0;

    for (0..3) |pi| {
        const spec = opSpectral(grid, Y[pi], feat);
        const wal = opWalsh(grid, Y[pi], feat);
        const clf = opClifford(grid, Y[pi], feat);

        const accs = [_]f64{ spec.val, wal.val, clf.val };
        const tests = [_]f64{ spec.tst, wal.tst, clf.tst };

        var best: usize = 0;
        for (1..3) |k| if (accs[k] > accs[best]) {
            best = k;
        };
        const winner: Operator = @enumFromInt(best);
        const ok = winner == pred_expected[pi];
        if (ok) n_correct += 1;

        try out.print("──────── predicate: {s} (expected winner: {s}) ────────\n", .{ pred_name[pi], op_name[@intFromEnum(pred_expected[pi])] });
        try out.print("  operator        | val acc | test acc | detail\n", .{});
        try out.print("  ----------------+---------+----------+---------------------------\n", .{});
        try out.print("  spectral        | {d:.3}   | {d:.3}    | ω={d:.4}\n", .{ spec.val, spec.tst, spec.omega });
        const ws = fmtSet(&setbuf, wal.bestS);
        try out.print("  walsh           | {d:.3}   | {d:.3}    | argmax χ{s}\n", .{ wal.val, wal.tst, ws });
        try out.print("  clifford_g2     | {d:.3}   | {d:.3}    | sin(θ(v1-v0)), pair (0,1)\n", .{ clf.val, clf.tst });
        try out.print("  → MENU PICK: {s} (test={d:.3}) {s}\n\n", .{ op_name[best], tests[best], if (ok) "✓" else "✗" });
    }

    try out.print("════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("Menu routed {d}/3 predicates to the structurally correct operator.\n", .{n_correct});
    if (n_correct == 3) {
        try out.print("All three operators stay in their lane: spectral reads periodic count structure,\n", .{});
        try out.print("Walsh recovers the parity character on the cube, Clifford grade-2 captures orientation.\n", .{});
        try out.print("Next integration step: call this menu from inner_forge.zig when monomial promotion\n", .{});
        try out.print("saturates (T5 parity) instead of brute-force φ_S enumeration.\n", .{});
    }
    try out.print("\nSee: structure_discovery.zig (inner⊗outer menu), inner_forge.zig (forge loop),\n", .{});
    try out.print("spectral_discovery.zig, boolean_fourier.zig, antisymmetric_relational.zig.\n", .{});
}