//! FUNCTION HARDNESS — exhaustive n=4 boolean predicate landscape
//!
//! All prior work asks: "can substrate S learn predicate P?"
//! This asks the INVERSE: "given substrate S, what predicate is hardest for it?"
//!
//! n=4 binary inputs → 16 possible input patterns → 2^16 = 65536 boolean predicates.
//! For each predicate we fit 4 substrates using logistic regression over all 16 inputs.
//!
//! Substrates:
//!   deg1  — raw bits {b0,b1,b2,b3}                            (4 features)
//!   deg2  — deg1 + AND-pairs {bi*bj}                          (10 features)
//!   xor2  — XOR-pairs {bi⊕bj}                                 (6 features)
//!   joint — raw bits + XOR-pairs                              (10 features)
//!
//! Key research questions:
//!   1. How many predicates are in each substrate's closure (perfect accuracy)?
//!   2. Which specific predicates are hardest per substrate?
//!   3. Q38: do any predicates escape jointly (deg1 fails ∧ xor2 fails ∧ joint succeeds)?
//!
//! Run: zig build run -Doptimize=ReleaseFast

const std = @import("std");

const N_BITS: usize = 4;
const N_IN:   usize = 1 << N_BITS;   // 16 input patterns
const N_PREDS: usize = 1 << N_IN;    // 65536 predicates
const EPOCHS: usize = 400;
const LR:     f64   = 0.5;
const MAX_DIM: usize = 16;

// ── feature extraction ────────────────────────────────────────────────────────

fn b(s: usize, i: usize) f64 {
    return if ((s >> @intCast(i)) & 1 == 1) 1.0 else 0.0;
}

fn xp(s: usize, i: usize, j: usize) f64 {
    // XOR of bit i and bit j of input pattern s
    const bi: u1 = @truncate(s >> @intCast(i));
    const bj: u1 = @truncate(s >> @intCast(j));
    return if (bi ^ bj == 1) 1.0 else 0.0;
}

const SubstrateId = enum { deg1, deg2, xor2, joint };

fn buildX(s: usize, sub: SubstrateId, out: *[MAX_DIM]f64) usize {
    var d: usize = 0;
    switch (sub) {
        .deg1 => {
            for (0..N_BITS) |i| { out[d] = b(s, i); d += 1; }
        },
        .deg2 => {
            for (0..N_BITS) |i| { out[d] = b(s, i); d += 1; }
            for (0..N_BITS) |i| for (i + 1..N_BITS) |j| {
                out[d] = b(s, i) * b(s, j); d += 1;
            };
        },
        .xor2 => {
            for (0..N_BITS) |i| for (i + 1..N_BITS) |j| {
                out[d] = xp(s, i, j); d += 1;
            };
        },
        .joint => {
            for (0..N_BITS) |i| { out[d] = b(s, i); d += 1; }
            for (0..N_BITS) |i| for (i + 1..N_BITS) |j| {
                out[d] = xp(s, i, j); d += 1;
            };
        },
    }
    return d;
}

// ── logistic regression ───────────────────────────────────────────────────────

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(-20.0, @min(20.0, z))));
}

fn logReg(
    X:   *const [N_IN][MAX_DIM]f64,
    dim: usize,
    Y:   *const [N_IN]f64,
) u32 {
    var w = [_]f64{0.0} ** MAX_DIM;
    var bias: f64 = 0.0;

    for (0..EPOCHS) |_| {
        for (0..N_IN) |s| {
            var z = bias;
            for (0..dim) |j| z += w[j] * X[s][j];
            const e = sigmoid(z) - Y[s];
            for (0..dim) |j| w[j] -= LR * e * X[s][j];
            bias -= LR * e;
        }
    }

    var correct: u32 = 0;
    for (0..N_IN) |s| {
        var z = bias;
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0.0) == (Y[s] > 0.5)) correct += 1;
    }
    return correct;
}

// ── main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Precompute fixed feature matrices (same for every predicate)
    const subs = [_]SubstrateId{ .deg1, .deg2, .xor2, .joint };
    const sub_names = [_][]const u8{ "deg1 ", "deg2 ", "xor2 ", "joint" };
    var Xs:   [4][N_IN][MAX_DIM]f64 = undefined;
    var dims: [4]usize              = undefined;

    for (subs, 0..) |sub, m| {
        for (0..N_IN) |s| {
            dims[m] = buildX(s, sub, &Xs[m][s]);
        }
    }

    try stdout.print("=== FUNCTION HARDNESS: exhaustive n={d} predicate landscape ===\n\n", .{N_BITS});
    try stdout.print("Substrates:\n", .{});
    try stdout.print("  deg1  : raw bits               ({d} features)\n", .{dims[0]});
    try stdout.print("  deg2  : bits + AND-pairs        ({d} features)\n", .{dims[1]});
    try stdout.print("  xor2  : XOR-pairs only          ({d} features)\n", .{dims[2]});
    try stdout.print("  joint : bits + XOR-pairs        ({d} features)\n", .{dims[3]});
    try stdout.print("\n{d} predicates × 4 substrates × {d} epochs...\n\n", .{ N_PREDS, EPOCHS });

    // Histograms: hist[substrate][accuracy 0..16]
    var hist: [4][N_IN + 1]u32 = [_][N_IN + 1]u32{[_]u32{0} ** (N_IN + 1)} ** 4;

    // Track hardest predicate per substrate (lowest accuracy)
    var worst_acc:  [4]u32 = [_]u32{N_IN} ** 4;
    var worst_pred: [4]u32 = [_]u32{0}    ** 4;

    // Q38: deg1 fails AND xor2 fails AND joint succeeds
    const Q38_FAIL:  u32 = 10; // ≤10/16 counts as "fails"
    const Q38_SUCC:  u32 = 14; // ≥14/16 counts as "succeeds"
    var q38_count: u32 = 0;
    const Q38_MAX_EX = 8;
    var q38_ex: [Q38_MAX_EX]struct { pred: u32, a0: u32, a2: u32, a3: u32 } = undefined;
    var q38_n: usize = 0;

    var Y: [N_IN]f64 = undefined;

    // Progress bar (one dot per 2048 predicates = 32 dots total)
    var next_dot: usize = 0;

    for (0..N_PREDS) |pred| {
        if (pred >= next_dot) {
            try stdout.print(".", .{});
            next_dot += 2048;
        }

        for (0..N_IN) |s| {
            Y[s] = if ((pred >> @intCast(s)) & 1 == 1) 1.0 else 0.0;
        }

        var acc: [4]u32 = undefined;
        for (0..4) |m| {
            acc[m] = logReg(&Xs[m], dims[m], &Y);
            hist[m][acc[m]] += 1;
            if (acc[m] < worst_acc[m]) {
                worst_acc[m]  = acc[m];
                worst_pred[m] = @intCast(pred);
            }
        }

        if (acc[0] <= Q38_FAIL and acc[2] <= Q38_FAIL and acc[3] >= Q38_SUCC) {
            q38_count += 1;
            if (q38_n < Q38_MAX_EX) {
                q38_ex[q38_n] = .{ .pred = @intCast(pred), .a0 = acc[0], .a2 = acc[2], .a3 = acc[3] };
                q38_n += 1;
            }
        }
    }

    try stdout.print("\n\n", .{});

    // ── accuracy histograms ──
    try stdout.print("--- ACCURACY HISTOGRAMS (number of predicates at each accuracy) ---\n\n", .{});
    try stdout.print("  acc/16 | {s} | {s} | {s} | {s}\n", .{ sub_names[0], sub_names[1], sub_names[2], sub_names[3] });
    try stdout.print("  -------|-------|-------|-------|-------\n", .{});
    for (0..N_IN + 1) |acc| {
        const total = hist[0][acc] + hist[1][acc] + hist[2][acc] + hist[3][acc];
        if (total == 0) continue;
        try stdout.print("   {d:2}/16 | {d:5} | {d:5} | {d:5} | {d:5}\n", .{
            acc, hist[0][acc], hist[1][acc], hist[2][acc], hist[3][acc],
        });
    }

    // ── closure summary ──
    try stdout.print("\n--- CLOSURE SUMMARY (predicates with perfect 16/16 accuracy) ---\n\n", .{});
    for (0..4) |m| {
        const perfect = hist[m][N_IN];
        try stdout.print("  {s}: {d:5} / {d}  ({d:.2}%)\n", .{
            sub_names[m], perfect, N_PREDS,
            @as(f64, @floatFromInt(perfect)) / N_PREDS * 100.0,
        });
    }

    // ── hardest predicates ──
    try stdout.print("\n--- HARDEST PREDICATE PER SUBSTRATE ---\n\n", .{});
    for (0..4) |m| {
        const wp = worst_pred[m];
        try stdout.print("  {s}: pred=0x{X:0>4}  worst_acc={d}/16  tt=", .{
            sub_names[m], wp, worst_acc[m],
        });
        for (0..N_IN) |s| try stdout.print("{d}", .{ (wp >> @intCast(s)) & 1 });
        try stdout.print("\n", .{});
    }

    // ── Q38 emergent escape ──
    try stdout.print("\n--- Q38 EMERGENT ESCAPE (deg1≤{d} ∧ xor2≤{d} ∧ joint≥{d}) ---\n\n", .{
        Q38_FAIL, Q38_FAIL, Q38_SUCC,
    });
    try stdout.print("  Count: {d}\n", .{q38_count});
    if (q38_n > 0) {
        try stdout.print("  Examples:\n", .{});
        for (0..q38_n) |i| {
            const ex = q38_ex[i];
            try stdout.print("    0x{X:0>4}: deg1={d}/16 xor2={d}/16 joint={d}/16  tt=", .{
                ex.pred, ex.a0, ex.a2, ex.a3,
            });
            for (0..N_IN) |s| try stdout.print("{d}", .{ (ex.pred >> @intCast(s)) & 1 });
            try stdout.print("\n", .{});
        }
    } else {
        try stdout.print("  (none — no emergent escape at these thresholds)\n", .{});
    }

    // ── kill-test spot checks ──
    try stdout.print("\n--- KILL-TESTS (spot checks against known theory) ---\n\n", .{});

    // 4-way parity: XOR(b0,b1,b2,b3). Not linearly separable by any degree<4 substrate.
    // Expected: deg1≈12, deg2≈12, xor2≈12, joint≈12  (best linear on non-sep = 12/16)
    const parity4: usize = 0x6996;
    for (0..N_IN) |s| Y[s] = if ((parity4 >> @intCast(s)) & 1 == 1) 1.0 else 0.0;
    try stdout.print("  4-way parity 0x6996  (XOR b0..b3) — expect all substrates < 16/16:\n", .{});
    for (0..4) |m| {
        const acc = logReg(&Xs[m], dims[m], &Y);
        try stdout.print("    {s}: {d}/16\n", .{ sub_names[m], acc });
    }

    // XOR(b0,b1): not sep by deg1, sep by deg2 (b0+b1-2*b0*b1) and xor2 (direct feature)
    const xor01: usize = 0x6666;
    for (0..N_IN) |s| Y[s] = if ((xor01 >> @intCast(s)) & 1 == 1) 1.0 else 0.0;
    try stdout.print("  XOR(b0,b1)  0x6666  — expect deg1<16, deg2=16, xor2=16, joint=16:\n", .{});
    for (0..4) |m| {
        const acc = logReg(&Xs[m], dims[m], &Y);
        try stdout.print("    {s}: {d}/16\n", .{ sub_names[m], acc });
    }

    // AND(b0,b1): linearly separable by deg1 (b0+b1≥1.5), also by deg2, joint
    // xor2 has no AND feature — expect xor2 < 16
    const and01: usize = 0x8888;
    for (0..N_IN) |s| Y[s] = if ((and01 >> @intCast(s)) & 1 == 1) 1.0 else 0.0;
    try stdout.print("  AND(b0,b1)  0x8888  — expect deg1=16, deg2=16, xor2<16, joint<16:\n", .{});
    for (0..4) |m| {
        const acc = logReg(&Xs[m], dims[m], &Y);
        try stdout.print("    {s}: {d}/16\n", .{ sub_names[m], acc });
    }

    try stdout.print("\n--- VERDICT ---\n\n", .{});
    try stdout.print("Total predicates in each closure (perfect 16/16):\n", .{});
    for (0..4) |m| {
        try stdout.print("  {s}: {d}\n", .{ sub_names[m], hist[m][N_IN] });
    }
    if (q38_count > 0) {
        try stdout.print("\nQ38 CONFIRMED: {d} predicates show emergent escape — ", .{q38_count});
        try stdout.print("the joint substrate solves predicates that neither component solves.\n", .{});
    } else {
        try stdout.print("\nQ38 OPEN: no emergent escape found at these thresholds.\n", .{});
        try stdout.print("The joint substrate's closure may be the union of its components'.\n", .{});
    }
}
