//! FUNCTION HARDNESS (sampling) — n=5 and n=6
//!
//! At n=5 the predicate space is 2^32 ≈ 4B; at n=6 it is 2^64.
//! Full enumeration is infeasible, so we sample random truth tables.
//!
//! Each sample is a random 2^n-bit truth table. We run the same 5 substrates
//! as the n=4 exhaustive experiment plus degree-3 features, and report:
//!   - Accuracy histogram per substrate
//!   - Estimated closure fraction (how often perfect 2^n/2^n accuracy is hit)
//!   - Q38 rate: joint escapes where deg1 and xor2 both fail
//!
//! Run: zig build sample -Doptimize=ReleaseFast

const std = @import("std");

const N_SAMPLES = 100_000;
const EPOCHS    = 300;
const LR: f64   = 0.5;
const MAX_DIM   = 64;
const MAX_IN    = 64; // enough for n=6

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(-20.0, @min(20.0, z))));
}

// ── substrate feature builders ────────────────────────────────────────────────

fn rawBit(s: usize, i: usize) f64 {
    return if ((s >> @intCast(i)) & 1 == 1) 1.0 else 0.0;
}

fn xorPair(s: usize, i: usize, j: usize) f64 {
    const bi: u1 = @truncate(s >> @intCast(i));
    const bj: u1 = @truncate(s >> @intCast(j));
    return if (bi ^ bj == 1) 1.0 else 0.0;
}

fn buildFeatures(comptime N: usize, s: usize, mode: u8, out: *[MAX_DIM]f64) usize {
    var d: usize = 0;
    switch (mode) {
        0 => { // deg1: raw bits
            for (0..N) |i| { out[d] = rawBit(s, i); d += 1; }
        },
        1 => { // deg2: bits + AND-pairs
            for (0..N) |i| { out[d] = rawBit(s, i); d += 1; }
            for (0..N) |i| for (i+1..N) |j| {
                out[d] = rawBit(s, i) * rawBit(s, j); d += 1;
            };
        },
        2 => { // deg3: bits + AND-pairs + AND-triples
            for (0..N) |i| { out[d] = rawBit(s, i); d += 1; }
            for (0..N) |i| for (i+1..N) |j| {
                out[d] = rawBit(s, i) * rawBit(s, j); d += 1;
            };
            for (0..N) |i| for (i+1..N) |j| for (j+1..N) |k| {
                out[d] = rawBit(s, i) * rawBit(s, j) * rawBit(s, k); d += 1;
            };
        },
        3 => { // xor2: XOR-pairs
            for (0..N) |i| for (i+1..N) |j| {
                out[d] = xorPair(s, i, j); d += 1;
            };
        },
        4 => { // joint: bits + XOR-pairs
            for (0..N) |i| { out[d] = rawBit(s, i); d += 1; }
            for (0..N) |i| for (i+1..N) |j| {
                out[d] = xorPair(s, i, j); d += 1;
            };
        },
        else => {},
    }
    return d;
}

// ── logistic regression ───────────────────────────────────────────────────────

fn logReg(
    comptime N_IN: usize,
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

// ── per-n experiment ──────────────────────────────────────────────────────────

fn runExperiment(
    comptime N: usize,
    writer: anytype,
    rng: std.Random,
) !void {
    const N_IN: usize = 1 << N;
    const N_SUB = 5; // deg1 deg2 deg3 xor2 joint

    const sub_names = [N_SUB][]const u8{ "deg1 ", "deg2 ", "deg3 ", "xor2 ", "joint" };

    // Precompute feature matrices (fixed across all sampled predicates)
    var Xs:   [N_SUB][N_IN][MAX_DIM]f64 = undefined;
    var dims: [N_SUB]usize              = undefined;

    for (0..N_SUB) |m| {
        for (0..N_IN) |s| {
            dims[m] = buildFeatures(N, s, @intCast(m), &Xs[m][s]);
        }
    }

    try writer.print("=== n={d}  ({d} inputs, sampling {d} random predicates) ===\n\n",
        .{ N, N_IN, N_SAMPLES });
    try writer.print("Feature dims: ", .{});
    for (0..N_SUB) |m| try writer.print("{s}={d}  ", .{ sub_names[m], dims[m] });
    try writer.print("\n\n", .{});

    // Accuracy buckets: 0..N_IN
    const N_BUCK = N_IN + 1;
    var hist: [N_SUB][N_BUCK]u32 = [_][N_BUCK]u32{[_]u32{0} ** N_BUCK} ** N_SUB;

    // Q38 (using proportional thresholds scaled to N_IN)
    const Q38_FAIL: u32 = @intCast(N_IN * 10 / 16); // ≤ 62.5%
    const Q38_SUCC: u32 = @intCast(N_IN * 14 / 16); // ≥ 87.5%
    var q38_count: u32  = 0;

    // worst-case tracking
    var worst_acc:   [N_SUB]u32 = [_]u32{N_IN} ** N_SUB;

    var Y: [N_IN]f64 = undefined;

    var next_dot: usize = 0;
    for (0..N_SAMPLES) |sample_idx| {
        if (sample_idx >= next_dot) {
            try writer.print(".", .{});
            next_dot += N_SAMPLES / 50;
        }

        // Generate random truth table: each of the N_IN labels is a random bit
        // N_IN is at most 64; mask off bits above N_IN (for n<6 where N_IN<64)
        const raw: u64 = rng.int(u64);
        const pred: u64 = if (N_IN < 64) raw & ((@as(u64, 1) << @intCast(N_IN)) - 1) else raw;

        for (0..N_IN) |s| {
            Y[s] = if ((pred >> @intCast(s)) & 1 == 1) 1.0 else 0.0;
        }

        var acc: [N_SUB]u32 = undefined;
        for (0..N_SUB) |m| {
            acc[m] = logReg(N_IN, &Xs[m], dims[m], &Y);
            hist[m][acc[m]] += 1;
            const eff = @max(acc[m], N_IN - acc[m]); // sign-flip corrected
            if (eff < @max(worst_acc[m], N_IN - worst_acc[m])) {
                worst_acc[m] = acc[m];
            }
        }

        // Q38: deg1 fails AND xor2 fails AND joint succeeds
        if (acc[0] <= Q38_FAIL and acc[3] <= Q38_FAIL and acc[4] >= Q38_SUCC) {
            q38_count += 1;
        }
    }

    try writer.print("\n\n", .{});

    // ── histogram ──
    // bucket by corrected accuracy (max(acc, N_IN-acc)) in 10% bins
    const BIN_W: usize = N_IN / 8; // 4 bins of 12.5% each for n=5 (N_IN=32, BIN_W=4)
    try writer.print("--- ACCURACY DISTRIBUTION (corrected: max(acc, {d}-acc)) ---\n\n",
        .{N_IN});
    try writer.print("  range   | {s} | {s} | {s} | {s} | {s}\n",
        .{ sub_names[0], sub_names[1], sub_names[2], sub_names[3], sub_names[4] });
    try writer.print("  --------|-------|-------|-------|-------|-------\n", .{});

    var bin: usize = N_IN / 2;
    while (bin <= N_IN) : (bin += BIN_W) {
        var row: [N_SUB]u32 = [_]u32{0} ** N_SUB;
        const lo = if (bin >= BIN_W) bin - BIN_W + 1 else N_IN / 2;
        const hi = bin;
        for (0..N_SUB) |m| {
            for (lo..hi + 1) |a| {
                if (a <= N_IN) row[m] += hist[m][a];
                if (a > 0 and N_IN - a != a and N_IN - a <= N_IN) row[m] += hist[m][N_IN - a];
            }
        }
        try writer.print("  {d:2}-{d:2}/16eq | {d:5} | {d:5} | {d:5} | {d:5} | {d:5}\n", .{
            lo * 16 / N_IN, hi * 16 / N_IN,
            row[0], row[1], row[2], row[3], row[4],
        });
    }

    // ── closure estimate ──
    try writer.print("\n--- CLOSURE ESTIMATE (fraction reaching perfect {d}/{d}) ---\n\n",
        .{ N_IN, N_IN });
    for (0..N_SUB) |m| {
        const perfect = hist[m][N_IN];
        const pct = @as(f64, @floatFromInt(perfect)) / N_SAMPLES * 100.0;
        try writer.print("  {s}: {d:5}/{d}  ({d:.3}%)\n", .{
            sub_names[m], perfect, N_SAMPLES, pct,
        });
    }

    // ── Q38 ──
    try writer.print("\n--- Q38 EMERGENT ESCAPE (deg1≤{d} ∧ xor2≤{d} ∧ joint≥{d}) ---\n\n", .{
        Q38_FAIL, Q38_FAIL, Q38_SUCC,
    });
    const q38_pct = @as(f64, @floatFromInt(q38_count)) / N_SAMPLES * 100.0;
    try writer.print("  {d}/{d} samples  ({d:.3}%)\n", .{ q38_count, N_SAMPLES, q38_pct });

    // ── reference predicates ──
    try writer.print("\n--- REFERENCE PREDICATES ---\n\n", .{});

    // n-way parity: bit s has label = popcount(s) mod 2
    var par_pred: u64 = 0;
    for (0..N_IN) |s| {
        if (@popCount(s) % 2 == 1) par_pred |= @as(u64, 1) << @intCast(s);
    }
    for (0..N_IN) |s| Y[s] = if ((par_pred >> @intCast(s)) & 1 == 1) 1.0 else 0.0;
    try writer.print("  {d}-way parity  (all substrates expected < perfect):\n", .{N});
    for (0..N_SUB) |m| {
        const acc = logReg(N_IN, &Xs[m], dims[m], &Y);
        try writer.print("    {s}: {d}/{d}\n", .{ sub_names[m], acc, N_IN });
    }

    // XOR(b0,b1): deg2, xor2, joint should get perfect; deg1 should fail
    var xor01: u64 = 0;
    for (0..N_IN) |s| {
        const b0: u1 = @truncate(s >> 0);
        const b1: u1 = @truncate(s >> 1);
        if (b0 ^ b1 == 1) xor01 |= @as(u64, 1) << @intCast(s);
    }
    for (0..N_IN) |s| Y[s] = if ((xor01 >> @intCast(s)) & 1 == 1) 1.0 else 0.0;
    try writer.print("  XOR(b0,b1)  (deg1 fail, rest perfect):\n", .{});
    for (0..N_SUB) |m| {
        const acc = logReg(N_IN, &Xs[m], dims[m], &Y);
        try writer.print("    {s}: {d}/{d}\n", .{ sub_names[m], acc, N_IN });
    }

    try writer.print("\n", .{});
}

// ── main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var prng = std.Random.DefaultPrng.init(0xF00D_CAFE_1337_BEEF);
    const rng = prng.random();

    try stdout.print("=== FUNCTION HARDNESS (sampling) ===\n\n", .{});
    try stdout.print("{d} samples per n, {d} epochs, lr={d:.1}\n\n", .{
        N_SAMPLES, EPOCHS, LR,
    });

    try runExperiment(5, stdout, rng);
    try runExperiment(6, stdout, rng);
}
