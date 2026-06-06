//! Item 2 — the closure principle on a REAL, canonical problem: k-sparse parity.
//!
//! Parity (y = XOR of k specific input bits) is the textbook out-of-linear-closure
//! function: every individual bit is uncorrelated with y for k >= 2, so a linear
//! model has zero signal and sits at chance. This is the learning-theory twin of
//! affine_closure (mixers) and the band-readout ceiling (control). We confirm the
//! ceiling and its two escapes:
//!   1) a nonlinearity (a small MLP) -- the implicit generator;
//!   2) the explicit product monomial of the relevant bits -- the out-of-closure
//!      generator that makes parity LINEAR in the lifted space.
//!
//! Honest framing: parity-hardness for linear models is a known theorem. The point
//! is that the closure principle PREDICTS exactly where the ceiling is and what
//! escapes it, on a real, studied problem we did not invent.
//!
//! Run: zig build parity
const std = @import("std");

const N: usize = 16; // input bits

fn sigmoid(z: f64) f64 {
    const zc = @max(@as(f64, -30), @min(@as(f64, 30), z));
    return 1.0 / (1.0 + @exp(-zc));
}

// y = parity of the first k bits (a fixed relevant subset). x in {-1,+1}^N.
fn parityLabel(x: [N]f64, k: usize) f64 {
    var p: f64 = 1.0;
    for (0..k) |i| p *= x[i]; // product of +-1 = parity in +-1 encoding
    return if (p > 0) 0.0 else 1.0; // map +1->0, -1->1
}

fn genX(r: std.Random) [N]f64 {
    var x: [N]f64 = undefined;
    for (0..N) |i| x[i] = if (r.boolean()) 1.0 else -1.0;
    return x;
}

// Linear logistic regression on raw bits. With `lift`, append the product of the
// first k bits (the relevant monomial = the out-of-closure generator).
fn linearAcc(seed: u64, k: usize, n_train: usize, n_test: usize, lift: bool) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const D = N + 1; // optional lifted feature in slot N
    var w: [N + 1]f64 = [_]f64{0} ** (N + 1);
    var b: f64 = 0;
    const lr: f64 = 0.1;
    for (0..30) |_| for (0..n_train) |_| {
        const x = genX(r);
        const y = parityLabel(x, k);
        var feat: [N + 1]f64 = undefined;
        for (0..N) |i| feat[i] = x[i];
        feat[N] = if (lift) blk: {
            var p: f64 = 1;
            for (0..k) |i| p *= x[i];
            break :blk p;
        } else 0;
        var z: f64 = b;
        for (0..D) |i| z += w[i] * feat[i];
        const e = sigmoid(z) - y;
        for (0..D) |i| w[i] -= lr * e * feat[i];
        b -= lr * e;
    };
    var correct: f64 = 0;
    for (0..n_test) |_| {
        const x = genX(r);
        const y = parityLabel(x, k);
        var z: f64 = b;
        for (0..N) |i| z += w[i] * x[i];
        if (lift) {
            var p: f64 = 1;
            for (0..k) |i| p *= x[i];
            z += w[N] * p;
        }
        if ((sigmoid(z) > 0.5) == (y > 0.5)) correct += 1;
    }
    return correct / @as(f64, @floatFromInt(n_test));
}

// Tiny MLP: N -> H ReLU -> 1 sigmoid, on raw bits.
fn mlpAcc(seed: u64, k: usize, n_train: usize, n_test: usize) f64 {
    const H = 32;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    var W1: [H][N]f64 = undefined;
    var b1: [H]f64 = [_]f64{0} ** H;
    var W2: [H]f64 = undefined;
    var b2: f64 = 0;
    for (0..H) |h| {
        W2[h] = (r.float(f64) - 0.5);
        for (0..N) |i| W1[h][i] = (r.float(f64) - 0.5) * 0.5;
    }
    const lr: f64 = 0.05;
    for (0..200) |_| for (0..n_train) |_| {
        const x = genX(r);
        const y = parityLabel(x, k);
        var a1: [H]f64 = undefined;
        var z1: [H]f64 = undefined;
        var z2: f64 = b2;
        for (0..H) |h| {
            var z: f64 = b1[h];
            for (0..N) |i| z += W1[h][i] * x[i];
            z1[h] = z;
            a1[h] = if (z > 0) z else 0;
            z2 += W2[h] * a1[h];
        }
        const e = sigmoid(z2) - y;
        for (0..H) |h| {
            const d1 = e * W2[h] * (if (z1[h] > 0) @as(f64, 1) else 0);
            W2[h] -= lr * e * a1[h];
            for (0..N) |i| W1[h][i] -= lr * d1 * x[i];
            b1[h] -= lr * d1;
        }
        b2 -= lr * e;
    };
    var correct: f64 = 0;
    for (0..n_test) |_| {
        const x = genX(r);
        const y = parityLabel(x, k);
        var z2: f64 = b2;
        for (0..H) |h| {
            var z: f64 = b1[h];
            for (0..N) |i| z += W1[h][i] * x[i];
            z2 += W2[h] * (if (z > 0) z else 0);
        }
        if ((sigmoid(z2) > 0.5) == (y > 0.5)) correct += 1;
    }
    return correct / @as(f64, @floatFromInt(n_test));
}

// Hard parity: relevant bits are RANDOM (chosen once per seed, then fixed).
// The MLP must discover WHICH k bits matter, not just their relationship.
// This is the genuinely hard version — C(N,k) possible feature subsets.
fn hardParityLabel(x: [N]f64, bit_mask: u32, k: usize) f64 {
    var p: f64 = 1.0;
    var found: usize = 0;
    for (0..N) |i| {
        if (bit_mask & (@as(u32, 1) << @intCast(i)) != 0) {
            p *= x[i];
            found += 1;
            if (found >= k) break;
        }
    }
    return if (p > 0) 0.0 else 1.0;
}

fn randomBitMask(r: std.Random, k: usize) u32 {
    var mask: u32 = 0;
    var chosen: usize = 0;
    var available = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    for (0..k) |i| {
        const j = i + r.intRangeLessThan(usize, 0, N - i);
        const tmp = available[i];
        available[i] = available[j];
        available[j] = tmp;
        mask |= @as(u32, 1) << @intCast(available[i]);
        chosen += 1;
    }
    return mask;
}

fn mlpAccHard(seed: u64, k: usize, n_train: usize, n_test: usize) f64 {
    const H = 64; // bigger network for harder task
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const bit_mask = randomBitMask(r, k); // fixed for this trial
    var W1: [H][N]f64 = undefined;
    var b1: [H]f64 = [_]f64{0} ** H;
    var W2: [H]f64 = undefined;
    var b2: f64 = 0;
    for (0..H) |h| {
        W2[h] = (r.float(f64) - 0.5);
        for (0..N) |i| W1[h][i] = (r.float(f64) - 0.5) * 0.5;
    }
    const lr: f64 = 0.02;
    const epochs: usize = 300;
    for (0..epochs) |_| for (0..n_train) |_| {
        const x = genX(r);
        const y = hardParityLabel(x, bit_mask, k);
        var a1: [H]f64 = undefined;
        var z1: [H]f64 = undefined;
        var z2: f64 = b2;
        for (0..H) |h| {
            var z: f64 = b1[h];
            for (0..N) |i| z += W1[h][i] * x[i];
            z1[h] = z;
            a1[h] = if (z > 0) z else 0;
            z2 += W2[h] * a1[h];
        }
        const e = sigmoid(z2) - y;
        for (0..H) |h| {
            const d1 = e * W2[h] * (if (z1[h] > 0) @as(f64, 1) else 0);
            W2[h] -= lr * e * a1[h];
            for (0..N) |i| W1[h][i] -= lr * d1 * x[i];
            b1[h] -= lr * d1;
        }
        b2 -= lr * e;
    };
    var correct: f64 = 0;
    for (0..n_test) |_| {
        const x = genX(r);
        const y = hardParityLabel(x, bit_mask, k);
        var z2: f64 = b2;
        for (0..H) |h| {
            var z: f64 = b1[h];
            for (0..N) |i| z += W1[h][i] * x[i];
            z2 += W2[h] * (if (z > 0) z else 0);
        }
        if ((sigmoid(z2) > 0.5) == (y > 0.5)) correct += 1;
    }
    return correct / @as(f64, @floatFromInt(n_test));
}

// Phase-boundary sweep: for each (k, n_train) pair, run the MLP and record
// whether SGD finds the parity function. Returns accuracy (>0.9 = found).
// Uses fewer epochs/hidden to make the sweep feasible.
fn mlpAccFast(seed: u64, k: usize, n_train: usize, n_test: usize) f64 {
    const H = 32;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    var W1: [H][N]f64 = undefined;
    var b1: [H]f64 = [_]f64{0} ** H;
    var W2: [H]f64 = undefined;
    var b2: f64 = 0;
    for (0..H) |h| {
        W2[h] = (r.float(f64) - 0.5);
        for (0..N) |i| W1[h][i] = (r.float(f64) - 0.5) * 0.5;
    }
    const lr: f64 = 0.05;
    const epochs: usize = 150;
    for (0..epochs) |_| for (0..n_train) |_| {
        const x = genX(r);
        const y = parityLabel(x, k);
        var a1: [H]f64 = undefined;
        var z1: [H]f64 = undefined;
        var z2: f64 = b2;
        for (0..H) |h| {
            var z: f64 = b1[h];
            for (0..N) |i| z += W1[h][i] * x[i];
            z1[h] = z;
            a1[h] = if (z > 0) z else 0;
            z2 += W2[h] * a1[h];
        }
        const e = sigmoid(z2) - y;
        for (0..H) |h| {
            const d1 = e * W2[h] * (if (z1[h] > 0) @as(f64, 1) else 0);
            W2[h] -= lr * e * a1[h];
            for (0..N) |i| W1[h][i] -= lr * d1 * x[i];
            b1[h] -= lr * d1;
        }
        b2 -= lr * e;
    };
    var correct: f64 = 0;
    for (0..n_test) |_| {
        const x = genX(r);
        const y = parityLabel(x, k);
        var z2: f64 = b2;
        for (0..H) |h| {
            var z: f64 = b1[h];
            for (0..N) |i| z += W1[h][i] * x[i];
            z2 += W2[h] * (if (z > 0) z else 0);
        }
        if ((sigmoid(z2) > 0.5) == (y > 0.5)) correct += 1;
    }
    return correct / @as(f64, @floatFromInt(n_test));
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    const ntr: usize = 20000;
    const nte: usize = 5000;
    try out.print("=== Item 2: closure principle on k-sparse parity (a real problem) ===\n", .{});
    try out.print("y = XOR of k of {d} bits. Linear is provably blind for k>=2 (parity ceiling).\n", .{N});
    try out.print("(test accuracy; {d} train / {d} test)\n\n", .{ ntr, nte });
    try out.print("  k | linear(raw) | MLP(raw) | linear(+product monomial)\n", .{});
    try out.print("  --+-------------+----------+--------------------------\n", .{});
    for ([_]usize{ 1, 2, 3, 4 }) |k| {
        const lin = linearAcc(1, k, ntr, nte, false);
        const mlp = mlpAcc(2, k, ntr, nte);
        const lift = linearAcc(3, k, ntr, nte, true);
        try out.print("  {d} |    {d:.3}    |   {d:.3}  |          {d:.3}\n", .{ k, lin, mlp, lift });
    }
    try out.print("\nReading: k=1 is linear (a single bit). For k>=2, linear(raw) collapses to ~0.5 --\n", .{});
    try out.print("the parity ceiling, a theorem: each bit is uncorrelated with y, so the linear\n", .{});
    try out.print("closure contains no signal. Two escapes, exactly as the closure principle predicts:\n", .{});
    try out.print("a nonlinearity (the MLP), and the explicit out-of-closure GENERATOR -- the product\n", .{});
    try out.print("monomial of the relevant bits, which makes parity linear again (lifted column = 1.0).\n", .{});
    try out.print("Honest: parity-hardness for linear models is known; the contribution is that the\n", .{});
    try out.print("SAME principle (affine_closure / band-readout / Claim C) predicts the ceiling and its\n", .{});
    try out.print("generator on a canonical, un-invented problem. Large-k sparse parity stays hard for\n", .{});
    try out.print("SGD even for the MLP -- the real frontier (the generator gets exponentially hidden).\n", .{});

    // #41: phase boundary — (k, n_train) grid where MLP transitions from finding to not finding parity.
    // Theory: sample complexity for SGD on parity is ~2^k × poly(N). We map this empirically.
    try out.print("\n=== #41: phase boundary — where does the MLP STOP finding k-sparse parity? ===\n", .{});
    try out.print("MLP accuracy (>0.90 = found, ~0.50 = chance). 3 seeds, take max.\n", .{});
    const ks = [_]usize{ 1, 2, 3, 4, 5, 6 };
    const ntrains = [_]usize{ 100, 500, 2000, 8000, 20000 };
    try out.print("  n_train -> | ", .{});
    for (ntrains) |nt| try out.print("{d:>6} ", .{nt});
    try out.print("\n  k          |\n", .{});
    try out.print("  -----------+", .{});
    for (ntrains) |_| try out.print("-------", .{});
    try out.print("\n", .{});
    for (ks) |k| {
        try out.print("  k={d}        | ", .{k});
        for (ntrains) |nt| {
            var best: f64 = 0;
            for ([_]u64{ 0xABC, 0xDEF, 0x123 }) |s| {
                const acc = mlpAccFast(s, k, nt, 1000);
                if (acc > best) best = acc;
            }
            const marker: u8 = if (best > 0.90) '.' else if (best > 0.70) '?' else ' ';
            try out.print("{d:.3}{c} ", .{ best, marker });
        }
        try out.print("\n", .{});
    }
    try out.print("\n  Legend: '.' = found (>0.90), '?' = partial (0.70-0.90), ' ' = not found (<0.70)\n", .{});
    try out.print("  Reading: shows the (k, n_train) boundary where SGD transitions from solving to\n", .{});
    try out.print("  not solving k-sparse parity. Theoretical complexity ~2^k -- verify empirically.\n", .{});
    try out.print("\n  IMPORTANT caveat: relevant bits are ALWAYS the first k (fixed). This is the EASY\n", .{});
    try out.print("  version. The MLP only needs to learn WHAT to do with those bits, not WHICH bits\n", .{});
    try out.print("  matter. The hard version (unknown relevant bits) should be much more sample-costly.\n", .{});

    // Hard version: RANDOM relevant bits — the MLP must discover which k bits matter.
    // C(N,k) possible subsets. This is the genuine statistical-query-hard version.
    try out.print("\n=== HARD parity: random relevant bits (MLP must find WHICH k bits) ===\n", .{});
    try out.print("H=64 neurons, 300 epochs, 3 seeds. C(16,k) possible feature subsets.\n\n", .{});
    const ks_hard = [_]usize{ 1, 2, 3, 4 };
    const ntrains_hard = [_]usize{ 500, 2000, 8000, 20000 };
    try out.print("  n_train -> | ", .{});
    for (ntrains_hard) |nt| try out.print("{d:>6} ", .{nt});
    try out.print("\n  k          |\n", .{});
    try out.print("  -----------+", .{});
    for (ntrains_hard) |_| try out.print("-------", .{});
    try out.print("\n", .{});
    for (ks_hard) |k| {
        try out.print("  k={d}        | ", .{k});
        for (ntrains_hard) |nt| {
            var best: f64 = 0;
            for ([_]u64{ 0xABC, 0xDEF, 0x123 }) |s| {
                const acc = mlpAccHard(s, k, nt, 1000);
                if (acc > best) best = acc;
            }
            const marker: u8 = if (best > 0.90) '.' else if (best > 0.70) '?' else ' ';
            try out.print("{d:.3}{c} ", .{ best, marker });
        }
        try out.print("\n", .{});
    }
    try out.print("\n  Prediction: hard k=2 should need ~N^2 = 256 samples (quadratic in N);\n", .{});
    try out.print("  hard k=3 should need ~N^3 = 4096; hard k=4 near-impossible at these budgets.\n", .{});
    try out.print("  This is the statistical-query lower bound for parity discovery.\n", .{});
}
