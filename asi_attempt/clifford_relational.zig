//! FRONTIER 1 (the test A left open) — does Clifford's geometric product expose RELATIONAL
//! (pairwise) structure that a plain real bind does not?
//!
//! RQ A10 (clifford_binding.md) found that on the mass/sum predicate, a plain real Hadamard
//! bind reads the target as well as the full Clifford geometric product — so "leave GF(2)",
//! not the geometric product, was the lever. BUT that predicate was a symmetric function of
//! the sum; it never needed the geometric product's distinctive gift: the grade-2 (bivector)
//! part, which carries oriented PAIRWISE products xᵢxⱼ. This experiment builds the predicate
//! that DOES need it and asks whether Clifford finally beats the cheap real control.
//!
//! Predicate: y = b0 XOR b1, where bᵢ = (cell_i >= 3). XOR is NOT linearly separable and is
//! NOT a function of the sum — it needs the genuine interaction x0·x1 (XOR = b0+b1−2 b0 b1).
//!
//! All substrates feed a LINEAR readout; we vary only how second-order structure is formed:
//!   - bundle-only        f1 = Σᵢ Cᵢ                         (first order only — must FAIL)
//!   - Clifford pairwise  [f1 ; Σᵢ<ⱼ geo(Cᵢ,Cⱼ)]            (geometric-product interaction)
//!   - MAP real pairwise  [f1 ; Σᵢ<ⱼ (Cᵢ ⊙ Cⱼ)]            (real elementwise interaction)
//!   - ground truth       [b0, b1, b0·b1]                    (must hit ~1.0 — predicate is learnable)
//!
//! Decisive comparison: Clifford-pairwise vs MAP-real-pairwise. Tie => "second-order BINDING
//! is the lever, not Clifford specifically" (same deflation as A). Clifford wins => the grade
//! structure gives a cleaner linearly-readable relational code.
//!
//! Run: zig build clifford-relational

const std = @import("std");

const NCELL = 4; // few cells so the (0,1) interaction isn't diluted across 120 pairs
const VMAX = 6;
const THRESH = 3;
const NQ: u4 = 7;
const BLADES: usize = 1 << NQ; // 128

inline fn reorderSign(a0: u16, b: u16) f32 {
    var a = a0 >> 1;
    var sum: u32 = 0;
    while (a != 0) {
        sum += @popCount(a & b);
        a >>= 1;
    }
    return if (sum & 1 == 0) @as(f32, 1.0) else @as(f32, -1.0);
}

// full dense geometric product out += a*b (Euclidean Cl(7,0))
fn geoFull(a: []const f32, b: []const f32, out: []f32) void {
    for (0..BLADES) |p| {
        const ap = a[p];
        if (ap == 0) continue;
        for (0..BLADES) |q| {
            const bq = b[q];
            if (bq == 0) continue;
            out[@as(u16, @intCast(p)) ^ @as(u16, @intCast(q))] += reorderSign(@intCast(p), @intCast(q)) * ap * bq;
        }
    }
}

fn geoBlade(mv: []const f32, blade: u16, out: []f32) void {
    @memset(out, 0);
    for (0..BLADES) |a| {
        const c = mv[a];
        if (c == 0) continue;
        out[@as(u16, @intCast(a)) ^ blade] += reorderSign(@intCast(a), blade) * c;
    }
}

fn standardize(X: [][]f32, ntr: usize, dim: usize) void {
    for (0..dim) |j| {
        var mu: f32 = 0;
        for (0..ntr) |s| mu += X[s][j];
        mu /= @floatFromInt(ntr);
        var sd: f32 = 0;
        for (0..ntr) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
        sd = @max(1e-3, @sqrt(sd / @as(f32, @floatFromInt(ntr))));
        for (0..X.len) |s| X[s][j] = (X[s][j] - mu) / sd;
    }
}

fn linAcc(X: [][]f32, Y: []const f32, ntr: usize, dim: usize, epochs: usize) f32 {
    const alloc = std.heap.page_allocator;
    const w = alloc.alloc(f32, dim) catch unreachable;
    defer alloc.free(w);
    @memset(w, 0);
    var b: f32 = 0;
    const lr: f32 = 0.02;
    for (0..epochs) |_| for (0..ntr) |s| {
        var z: f32 = b;
        const x = X[s];
        for (0..dim) |j| z += w[j] * x[j];
        const p = 1.0 / (1.0 + @exp(-@max(@as(f32, -30), @min(@as(f32, 30), z))));
        const e = p - Y[s];
        for (0..dim) |j| w[j] -= lr * e * x[j];
        b -= lr * e;
    };
    var correct: usize = 0;
    for (ntr..X.len) |s| {
        var z: f32 = b;
        const x = X[s];
        for (0..dim) |j| z += w[j] * x[j];
        if ((z >= 0) == (Y[s] > 0.5)) correct += 1;
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(X.len - ntr));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const nsamp: usize = 3000;
    const ntr = nsamp / 2;
    var prng = std.Random.DefaultPrng.init(0xC11FFEE1);
    const rand = prng.random();

    // Clifford roles + precomputed PBᵢ (rotor bivector per cell).
    const P = try alloc.alloc([]f32, NCELL);
    const PB = try alloc.alloc([]f32, NCELL);
    defer {
        for (P) |r| alloc.free(r);
        for (PB) |r| alloc.free(r);
        alloc.free(P);
        alloc.free(PB);
    }
    for (0..NCELL) |i| {
        P[i] = try alloc.alloc(f32, BLADES);
        PB[i] = try alloc.alloc(f32, BLADES);
        var norm: f32 = 0;
        for (0..BLADES) |b| {
            const x = rand.floatNorm(f32);
            P[i][b] = x;
            norm += x * x;
        }
        norm = @sqrt(norm);
        for (0..BLADES) |b| P[i][b] /= norm;
        const p: u4 = @intCast(rand.intRangeLessThan(usize, 0, NQ));
        var q: u4 = @intCast(rand.intRangeLessThan(usize, 0, NQ));
        while (q == p) q = @intCast(rand.intRangeLessThan(usize, 0, NQ));
        geoBlade(P[i], (@as(u16, 1) << p) | (@as(u16, 1) << q), PB[i]);
    }
    const theta: f32 = 0.20;

    // feature matrices
    const Xbundle = try alloc.alloc([]f32, nsamp); // f1 (128)
    const Xcl = try alloc.alloc([]f32, nsamp); // [f1 ; pairwise geo] (256)
    const Xmap = try alloc.alloc([]f32, nsamp); // [f1 ; pairwise elementwise] (256)
    const Xgt = try alloc.alloc([]f32, nsamp); // [b0,b1,b0*b1] (3)
    const Xgto = try alloc.alloc([]f32, nsamp); // [sin((v0-v1)φ)] (1) — oriented ground truth
    const Y = try alloc.alloc(f32, nsamp); // symmetric: XOR
    const Yor = try alloc.alloc(f32, nsamp); // oriented: sign of sin((v0-v1)φ)
    defer {
        for (Xbundle) |r| alloc.free(r);
        for (Xcl) |r| alloc.free(r);
        for (Xmap) |r| alloc.free(r);
        for (Xgt) |r| alloc.free(r);
        for (Xgto) |r| alloc.free(r);
        alloc.free(Xbundle);
        alloc.free(Xcl);
        alloc.free(Xmap);
        alloc.free(Xgt);
        alloc.free(Xgto);
        alloc.free(Y);
        alloc.free(Yor);
    }
    const PHI: f32 = 0.9;

    const Ci = try alloc.alloc([]f32, NCELL);
    defer {
        for (Ci) |r| alloc.free(r);
        alloc.free(Ci);
    }
    for (0..NCELL) |i| Ci[i] = try alloc.alloc(f32, BLADES);
    const tmp = try alloc.alloc(f32, BLADES);
    defer alloc.free(tmp);

    for (0..nsamp) |s| {
        var g: [NCELL]u8 = undefined;
        for (0..NCELL) |i| g[i] = rand.intRangeAtMost(u8, 0, VMAX);
        const b0: f32 = if (g[0] >= THRESH) 1.0 else 0.0;
        const b1: f32 = if (g[1] >= THRESH) 1.0 else 0.0;
        Y[s] = if ((b0 > 0.5) != (b1 > 0.5)) 1.0 else 0.0; // XOR (symmetric)
        const diff: f32 = @as(f32, @floatFromInt(g[0])) - @as(f32, @floatFromInt(g[1]));
        const so = @sin(diff * PHI);
        Yor[s] = if (so > 0) 1.0 else 0.0; // oriented: depends on SIGN of (v0-v1), antisymmetric

        // per-cell bound multivectors Cᵢ = cos·Pᵢ + sin·PBᵢ
        for (0..NCELL) |i| {
            const v: f32 = @floatFromInt(g[i]);
            const c = @cos(v * theta);
            const sn = @sin(v * theta);
            for (0..BLADES) |b| Ci[i][b] = c * P[i][b] + sn * PB[i][b];
        }
        // first order: f1 = Σ Cᵢ
        var f1: [BLADES]f32 = [_]f32{0} ** BLADES;
        for (0..NCELL) |i| for (0..BLADES) |b| {
            f1[b] += Ci[i][b];
        };
        // second order
        var f2cl: [BLADES]f32 = [_]f32{0} ** BLADES;
        var f2map: [BLADES]f32 = [_]f32{0} ** BLADES;
        for (0..NCELL) |i| {
            for (i + 1..NCELL) |j| {
                @memset(tmp, 0);
                geoFull(Ci[i], Ci[j], tmp);
                for (0..BLADES) |b| f2cl[b] += tmp[b];
                for (0..BLADES) |b| f2map[b] += Ci[i][b] * Ci[j][b];
            }
        }
        Xbundle[s] = try alloc.alloc(f32, BLADES);
        @memcpy(Xbundle[s], &f1);
        Xcl[s] = try alloc.alloc(f32, 2 * BLADES);
        @memcpy(Xcl[s][0..BLADES], &f1);
        @memcpy(Xcl[s][BLADES..], &f2cl);
        Xmap[s] = try alloc.alloc(f32, 2 * BLADES);
        @memcpy(Xmap[s][0..BLADES], &f1);
        @memcpy(Xmap[s][BLADES..], &f2map);
        Xgt[s] = try alloc.alloc(f32, 3);
        Xgt[s][0] = b0;
        Xgt[s][1] = b1;
        Xgt[s][2] = b0 * b1;
        Xgto[s] = try alloc.alloc(f32, 1);
        Xgto[s][0] = @sin(diff * PHI); // the explicit oriented feature
    }

    standardize(Xbundle, ntr, BLADES);
    standardize(Xcl, ntr, 2 * BLADES);
    standardize(Xmap, ntr, 2 * BLADES);
    standardize(Xgt, ntr, 3);
    standardize(Xgto, ntr, 1);

    const acc_bundle = linAcc(Xbundle, Y, ntr, BLADES, 80);
    const acc_cl = linAcc(Xcl, Y, ntr, 2 * BLADES, 80);
    const acc_map = linAcc(Xmap, Y, ntr, 2 * BLADES, 80);
    const acc_gt = linAcc(Xgt, Y, ntr, 3, 80);

    var pos: f32 = 0;
    for (ntr..nsamp) |s| pos += Y[s];
    const nte: f32 = @floatFromInt(nsamp - ntr);
    const chance = @max(pos, nte - pos) / nte;

    try out.print("=== FRONTIER 1: does Clifford's geometric product give relational features? ===\n", .{});
    try out.print("predicate = (cell0>=3) XOR (cell1>=3); needs the pairwise product, NOT the sum.\n", .{});
    try out.print("({d} grids 50/50; chance = {d:.3}; all readouts LINEAR)\n\n", .{ nsamp, chance });
    try out.print("  encoding                              | test acc | second-order via\n", .{});
    try out.print("  --------------------------------------+----------+---------------------------\n", .{});
    try out.print("  bundle only  Σ Cᵢ                     |  {d:.3}   | (none — first order only)\n", .{acc_bundle});
    try out.print("  Clifford pairwise  +Σ geo(Cᵢ,Cⱼ)      |  {d:.3}   | geometric product\n", .{acc_cl});
    try out.print("  MAP real pairwise  +Σ (Cᵢ⊙Cⱼ)         |  {d:.3}   | real elementwise product\n", .{acc_map});
    try out.print("  ground truth [b0,b1,b0·b1]            |  {d:.3}   | the explicit interaction\n", .{acc_gt});

    try out.print("\n--- VERDICT ---\n", .{});
    const bundle_fails = acc_bundle < 0.65;
    const cl_works = acc_cl > 0.85;
    const map_works = acc_map > 0.85;
    const cl_beats_map = acc_cl > acc_map + 0.03;
    if (bundle_fails) {
        try out.print("Confirmed the predicate needs SECOND order: bundle-only is near chance ({d:.3}) —\n", .{acc_bundle});
        try out.print("XOR is not a linear function of the first-order (bundled) code.\n", .{});
    }
    if (cl_beats_map and cl_works) {
        try out.print("\nCLIFFORD WINS: the geometric-product pairwise code ({d:.3}) beats the real elementwise\n", .{acc_cl});
        try out.print("pairwise code ({d:.3}) by >0.03. The grade-2 (bivector) structure gives a cleaner\n", .{acc_map});
        try out.print("linearly-readable relational feature than a plain real interaction bind. THIS is where\n", .{});
        try out.print("the geometric product earns its keep — unlike the mass predicate in clifford_binding.md.\n", .{});
    } else if (cl_works and map_works and !cl_beats_map) {
        try out.print("\nDEFLATION AGAIN: Clifford pairwise ({d:.3}) and real elementwise pairwise ({d:.3}) TIE.\n", .{ acc_cl, acc_map });
        try out.print("Even on a genuinely relational predicate, the lever is SECOND-ORDER BINDING, not the\n", .{});
        try out.print("geometric product specifically. And there's a REASON, now clear: XOR is SYMMETRIC in\n", .{});
        try out.print("(c0,c1), so it needs only the symmetric/scalar part of the product = the dot product\n", .{});
        try out.print("⟨C0,C1⟩, which BOTH substrates expose (it is the grade-0 part of the geo product, and\n", .{});
        try out.print("Σ C0⊙C1 for MAP). The geometric product's DISTINCTIVE gift is the bivector (grade-2):\n", .{});
        try out.print("ANTISYMMETRIC, oriented C0∧C1 = −C1∧C0 — which a symmetric predicate never uses and a\n", .{});
        try out.print("commutative real product cannot represent. Predicted: Clifford pulls ahead ONLY on an\n", .{});
        try out.print("oriented/non-commutative relation (where order matters), not on symmetric sum/XOR.\n", .{});
    } else if (!cl_works) {
        try out.print("\nNeither relational code cracked it cleanly (cl {d:.3}, map {d:.3}); ground truth = {d:.3}.\n", .{ acc_cl, acc_map, acc_gt });
        try out.print("The pairwise (0,1) term is still diluted among the {d} pair interactions.\n", .{NCELL * (NCELL - 1) / 2});
    }
    try out.print("\nSee: clifford_binding.md (the sum-predicate deflation this follows up).\n", .{});
}
