//! FRONTIER 3 — Clifford's bivector earns its keep: orientation
//!
//! Previous result (clifford_relational.md): even on a pairwise-relational predicate (XOR),
//! Clifford ties real pairwise — because XOR is SYMMETRIC and the random per-cell roles
//! (P_i) make the bivector MAGNITUDE symmetric in values. The bivector changes sign under
//! cell SWAP, but XOR is invariant to swap, so the sign-flip is unused.
//!
//! This experiment identifies the EXACT structural condition where Clifford wins:
//!   (a) the predicate is ANTISYMMETRIC (swapping cells flips the label)
//!   (b) the encoding uses a SHARED BASIS (all cells map to the same unit circle)
//!
//! Shared-basis Cl(2,0) encoding:  Cᵢ = cos(θvᵢ)·e₁ + sin(θvᵢ)·e₂
//!
//! Then:
//!   grade-0(geo(C0,C1)) = cos(θv0)cos(θv1) + sin(θv0)sin(θv1) = cos(θ(v0−v1))  [SYMMETRIC]
//!   grade-2(geo(C0,C1)) = cos(θv0)sin(θv1) − sin(θv0)cos(θv1) = sin(θ(v1−v0))  [ANTISYMMETRIC]
//!
//!   real pairwise C0⊙C1 = (cos(θv0)cos(θv1), sin(θv0)sin(θv1))                 [SYMMETRIC]
//!   no antisymmetric information present.
//!
//! Oriented predicate:  y = sign(sin(θ(v1−v0))) = sign(v1 − v0)  (for small θ)
//!   → ANTISYMMETRIC: swapping cells flips y.
//!
//! Predictions:
//!   bundle (C0+C1)            → chance  [symmetric, loses identity]
//!   real pairwise sym (C0⊙C1) → chance  [symmetric product, orientation-blind]
//!   Clifford grade-2           → 1.000  [bivector IS sin(θ(v1−v0)) — exact feature]
//!   first-order ordered [C0;C1]→ works  [identity preserved, baseline antisymmetric]
//!   ground truth               → 1.000  [direct check]
//!
//! Run: zig build antisymmetric-relational

const std = @import("std");

// Cl(2,0): 4 blades — scalar(0), e1(1), e2(2), e12(3)
const BLADES = 4;
const NCELL = 4;
const VMAX: u8 = 6;
const THETA: f32 = 0.40; // large enough to spread values across the circle

// Geometric product in Cl(2,0) Euclidean: e1²=e2²=1, e12²=-1
// blade XOR gives the result blade; reorderSign gives +/- from canonical order
inline fn reorderSign2d(a: u8, b: u8) f32 {
    // count swaps needed to merge sorted basis blades
    var aa = a >> 1;
    var sum: u32 = 0;
    while (aa != 0) {
        sum += @popCount(aa & b);
        aa >>= 1;
    }
    return if (sum & 1 == 0) @as(f32, 1.0) else @as(f32, -1.0);
}

fn geo2d(a: [BLADES]f32, b: [BLADES]f32) [BLADES]f32 {
    var out: [BLADES]f32 = .{0} ** BLADES;
    for (0..BLADES) |p| {
        if (a[p] == 0) continue;
        for (0..BLADES) |q| {
            if (b[q] == 0) continue;
            const blade: u8 = @as(u8, @intCast(p)) ^ @as(u8, @intCast(q));
            out[blade] += reorderSign2d(@intCast(p), @intCast(q)) * a[p] * b[q];
        }
    }
    return out;
}

// encode cell value → unit-circle multivector on shared e1,e2 basis
fn encode(v: u8) [BLADES]f32 {
    const fv: f32 = @floatFromInt(v);
    return .{
        0, // scalar
        @cos(THETA * fv), // e1
        @sin(THETA * fv), // e2
        0, // e12
    };
}

fn sigmoid(z: f32) f32 {
    return 1.0 / (1.0 + @exp(-@max(@as(f32, -30), @min(@as(f32, 30), z))));
}

fn standardize(X: [][]f32, ntr: usize, dim: usize) void {
    for (0..dim) |j| {
        var mu: f32 = 0;
        for (0..ntr) |s| mu += X[s][j];
        mu /= @floatFromInt(ntr);
        var sd: f32 = 0;
        for (0..ntr) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
        sd = @max(1e-4, @sqrt(sd / @as(f32, @floatFromInt(ntr))));
        for (0..X.len) |s| X[s][j] = (X[s][j] - mu) / sd;
    }
}

fn linAcc(X: [][]f32, Y: []const f32, ntr: usize, dim: usize, epochs: usize) f32 {
    const alloc = std.heap.page_allocator;
    const w = alloc.alloc(f32, dim) catch unreachable;
    defer alloc.free(w);
    @memset(w, 0);
    var bias: f32 = 0;
    const lr: f32 = 0.03;
    for (0..epochs) |_| for (0..ntr) |s| {
        var z = bias;
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        bias -= lr * e;
    };
    var correct: usize = 0;
    for (ntr..X.len) |s| {
        var z = bias;
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) correct += 1;
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(X.len - ntr));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const nsamp: usize = 4000;
    const ntr = nsamp * 3 / 4;
    var prng = std.Random.DefaultPrng.init(0xAB1E1234);
    const rand = prng.random();

    // five feature matrices:
    // (1) bundle: C0+C1+...                   dim=4
    // (2) real pairwise sym: Σᵢ<ⱼ C0⊙C1       dim=4
    // (3) Clifford grade-2 ordered: geo(C0,C1)[3]   dim=1 (the bivector)
    // (4) first-order ordered [C0;C1]          dim=8  (identity preserved)
    // (5) ground truth sin(θ(v1−v0))           dim=1

    const Xbundle = try alloc.alloc([]f32, nsamp);
    const Xrpair  = try alloc.alloc([]f32, nsamp);
    const Xcl2    = try alloc.alloc([]f32, nsamp);
    const Xord    = try alloc.alloc([]f32, nsamp);
    const Xgt     = try alloc.alloc([]f32, nsamp);
    // also symmetric predicate XOR(b0,b1) to verify no regression
    const Ysym = try alloc.alloc(f32, nsamp);  // symmetric: XOR(b0>=H, b1>=H)
    const Yor  = try alloc.alloc(f32, nsamp);  // oriented:  sign(v1-v0)

    defer {
        for (Xbundle) |r| alloc.free(r);
        for (Xrpair)  |r| alloc.free(r);
        for (Xcl2)    |r| alloc.free(r);
        for (Xord)    |r| alloc.free(r);
        for (Xgt)     |r| alloc.free(r);
        alloc.free(Xbundle); alloc.free(Xrpair); alloc.free(Xcl2); alloc.free(Xord); alloc.free(Xgt);
        alloc.free(Ysym); alloc.free(Yor);
    }

    const THRESH: u8 = 3;
    const PHI: f32 = THETA; // ground truth angle matches encoding

    for (0..nsamp) |s| {
        var g: [NCELL]u8 = undefined;
        for (0..NCELL) |i| g[i] = rand.intRangeAtMost(u8, 0, VMAX);

        // cells 0 and 1 are the focal pair for oriented predicate
        const v0: f32 = @floatFromInt(g[0]);
        const v1: f32 = @floatFromInt(g[1]);
        const b0: f32 = if (g[0] >= THRESH) 1.0 else 0.0;
        const b1: f32 = if (g[1] >= THRESH) 1.0 else 0.0;

        Ysym[s] = if ((b0 > 0.5) != (b1 > 0.5)) 1.0 else 0.0; // XOR
        // oriented: +1 when v1 > v0, 0 when equal, decided by sin for smoothness
        Yor[s] = if (@sin(PHI * (v1 - v0)) > 0) 1.0 else 0.0;

        var C: [NCELL][BLADES]f32 = undefined;
        for (0..NCELL) |i| C[i] = encode(g[i]);

        // (1) bundle
        var bundle: [BLADES]f32 = .{0} ** BLADES;
        for (0..NCELL) |i| for (0..BLADES) |b| { bundle[b] += C[i][b]; };

        // (2) real pairwise symmetric (focussed on cells 0,1 only for clarity)
        var rpair: [BLADES]f32 = .{0} ** BLADES;
        for (0..BLADES) |b| rpair[b] = C[0][b] * C[1][b]; // C0⊙C1

        // (3) Clifford grade-2 component of geo(C0,C1): blade index 3 = e12
        const geo01 = geo2d(C[0], C[1]);
        const biv01: f32 = geo01[3]; // sin(θ(v1-v0)) — the antisymmetric part

        // (4) first-order ordered: [C0 ; C1] (8-dim)
        // (5) ground truth: sin(PHI*(v1-v0))
        const gt_biv: f32 = @sin(PHI * (v1 - v0));

        Xbundle[s] = try alloc.alloc(f32, BLADES);
        @memcpy(Xbundle[s], &bundle);

        Xrpair[s] = try alloc.alloc(f32, BLADES);
        @memcpy(Xrpair[s], &rpair);

        Xcl2[s] = try alloc.alloc(f32, 1);
        Xcl2[s][0] = biv01;

        Xord[s] = try alloc.alloc(f32, 2 * BLADES);
        @memcpy(Xord[s][0..BLADES], &C[0]);
        @memcpy(Xord[s][BLADES..], &C[1]);

        Xgt[s] = try alloc.alloc(f32, 1);
        Xgt[s][0] = gt_biv;
    }

    standardize(Xbundle, ntr, BLADES);
    standardize(Xrpair,  ntr, BLADES);
    standardize(Xcl2,    ntr, 1);
    standardize(Xord,    ntr, 2 * BLADES);
    standardize(Xgt,     ntr, 1);

    // --- test on ORIENTED predicate ---
    const acc_bun_or  = linAcc(Xbundle, Yor, ntr, BLADES,     100);
    const acc_rp_or   = linAcc(Xrpair,  Yor, ntr, BLADES,     100);
    const acc_cl2_or  = linAcc(Xcl2,    Yor, ntr, 1,          100);
    const acc_ord_or  = linAcc(Xord,    Yor, ntr, 2 * BLADES, 100);
    const acc_gt_or   = linAcc(Xgt,     Yor, ntr, 1,          100);

    // --- test on SYMMETRIC predicate (sanity / no-regression) ---
    const acc_bun_sym = linAcc(Xbundle, Ysym, ntr, BLADES,     100);
    const acc_rp_sym  = linAcc(Xrpair,  Ysym, ntr, BLADES,     100);
    const acc_cl2_sym = linAcc(Xcl2,    Ysym, ntr, 1,          100);
    const acc_ord_sym = linAcc(Xord,    Ysym, ntr, 2 * BLADES, 100);

    var pos_or: f32 = 0; var pos_sym: f32 = 0;
    const nte: f32 = @floatFromInt(nsamp - ntr);
    for (ntr..nsamp) |s| { pos_or += Yor[s]; pos_sym += Ysym[s]; }
    const ch_or  = @max(pos_or,  nte - pos_or)  / nte;
    const ch_sym = @max(pos_sym, nte - pos_sym) / nte;

    try out.print("=== FRONTIER 3: shared-basis Clifford encoding exposes orientation ===\n\n", .{});
    try out.print("Shared Cl(2,0) encoding: Cᵢ = cos(θvᵢ)·e1 + sin(θvᵢ)·e2, θ={d:.2}\n", .{THETA});
    try out.print("grade-2(geo(C0,C1)) = sin(θ(v1−v0)) — antisymmetric by construction\n", .{});
    try out.print("real pairwise C0⊙C1 = symmetric product — orientation-blind by construction\n\n", .{});

    try out.print("  --- ORIENTED predicate:  y = sign(v1−v0)  (chance={d:.3}) ---\n", .{ch_or});
    try out.print("  feature                     | dim | test acc\n", .{});
    try out.print("  ----------------------------+-----+---------\n", .{});
    try out.print("  bundle Σ Cᵢ                 |  {d:2} | {d:.3}\n", .{ BLADES, acc_bun_or });
    try out.print("  real pairwise sym  C0⊙C1    |  {d:2} | {d:.3}   ← symmetric, should FAIL\n", .{ BLADES, acc_rp_or });
    try out.print("  Clifford grade-2  geo[e12]  |   1 | {d:.3}   ← antisymmetric, predicted WIN\n", .{acc_cl2_or});
    try out.print("  first-order ordered [C0;C1] |  {d:2} | {d:.3}   ← baseline antisymmetric\n", .{ 2 * BLADES, acc_ord_or });
    try out.print("  ground truth sin(θ(v1−v0))  |   1 | {d:.3}\n", .{acc_gt_or});

    try out.print("\n  --- SYMMETRIC predicate: y = XOR(b0,b1) (chance={d:.3}) ---\n", .{ch_sym});
    try out.print("  bundle              |  {d:2} | {d:.3}\n", .{ BLADES, acc_bun_sym });
    try out.print("  real pairwise sym   |  {d:2} | {d:.3}\n", .{ BLADES, acc_rp_sym });
    try out.print("  Clifford grade-2    |   1 | {d:.3}   ← expected: low (bivector doesn't help XOR)\n", .{acc_cl2_sym});
    try out.print("  first-order ordered |  {d:2} | {d:.3}\n", .{ 2 * BLADES, acc_ord_sym });

    try out.print("\n--- VERDICT ---\n", .{});
    const clifford_wins = acc_cl2_or > 0.90;
    const real_fails    = acc_rp_or  < 0.70;
    const biv_useless_on_sym = acc_cl2_sym < 0.70;
    if (clifford_wins and real_fails) {
        try out.print("CLIFFORD WINS on oriented predicate: grade-2 ({d:.3}) >> real pairwise ({d:.3}).\n",
            .{ acc_cl2_or, acc_rp_or });
        try out.print("The bivector is sin(θ(v1−v0)) — it IS the oriented feature. Real pairwise\n", .{});
        try out.print("gives only symmetric products: cos-product and sin-product, both invariant\n", .{});
        try out.print("to value swap. Orientation requires the ANTISYMMETRIC grade-2 blade.\n", .{});
        if (biv_useless_on_sym)
            try out.print("\nCorrectly: grade-2 is near-chance ({d:.3}) on SYMMETRIC XOR — the bivector\n", .{acc_cl2_sym})
        else
            try out.print("\nNote: grade-2 ({d:.3}) on symmetric XOR — check if bivector leaks XOR structure.\n", .{acc_cl2_sym});
    } else if (!clifford_wins) {
        try out.print("Clifford grade-2 underperformed ({d:.3}). Encoding mismatch or insufficient spread?\n", .{acc_cl2_or});
        try out.print("THETA={d:.2}: θ*VMAX={d:.2} — may need larger θ for clean unit-circle spread.\n",
            .{ THETA, THETA * @as(f32, @floatFromInt(VMAX)) });
    } else {
        try out.print("Partial: Clifford works ({d:.3}) but real pairwise also partial ({d:.3}).\n",
            .{ acc_cl2_or, acc_rp_or });
    }
    try out.print("\nKey structural lesson: Clifford earns its keep when ENCODING and PREDICATE share\n", .{});
    try out.print("the SAME ALGEBRAIC STRUCTURE — shared-basis angle encoding + oriented predicate.\n", .{});
    try out.print("Random per-cell roles (Frontier 1) break this: the bivector is then MAGNITUDE-\n", .{});
    try out.print("symmetric in values, and orientation is destroyed.\n", .{});
    try out.print("\nSee: clifford_relational.md (random-role deflation), clifford_binding.md (mass deflation).\n", .{});
}
