// Frontier 12 — Gradient Discovery
//
// New idea: when a classifier trained on an insufficient substrate fails, the
// RESIDUAL GRADIENT with respect to missing features is the discovery signal.
// The gradient points toward the needed extension — automatically.
//
// Algorithm:
//   1. Train logistic on degree-2 threshold-bit features for k3-parity (insufficient)
//   2. Compute "shadow gradients" for all degree-3 threshold-bit monomials (not in model)
//   3. Shadow gradient g_k = (1/N) Σᵢ errᵢ * f_k(xᵢ)  (residual × candidate feature)
//   4. Does the correct monomial b[0]*b[1]*b[2] rank #1 by |g_k|?
//   5. Greedy extension: add features by shadow-gradient rank, measure accuracy at each step
//
// If the gradient correctly ranks the needed feature first, this becomes an
// automatic substrate discovery algorithm — no human specification required.

const std = @import("std");
const math = std.math;

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 4000;
const NTRAIN: usize = NSAMP * 4 / 5;
const NTEST: usize = NSAMP - NTRAIN;
const LR: f64 = 0.05;
const NITERS_BASE: usize = 3000;  // train to near-convergence on insufficient substrate
const NITERS_EXT: usize = 2000;   // retrain after adding features
const MAX_FEAT: usize = 60;
const PI: f64 = math.pi;

// Degree-2 threshold-bit features: b[i] + b[i]*b[j] = 6 + 15 = 21
// Degree-3 threshold-bit monomials: b[i]*b[j]*b[l] for i<j<l = C(6,3) = 20
const NDEG2: usize = 21;
const NDEG3: usize = 20;

var g_cells: [NSAMP][NCELL]u8 = undefined;
var g_labels: [NSAMP]bool = undefined;
var g_feat: [NSAMP][MAX_FEAT]f64 = undefined;
var g_errors: [NSAMP]f64 = undefined;  // residuals after training

fn lcg(s: *u64) u64 {
    s.* ^= s.* >> 12;
    s.* ^= s.* << 25;
    s.* ^= s.* >> 27;
    return s.* *% 0x2545F4914F6CDD1D;
}

fn sigmoid(x: f64) f64 { return 1.0 / (1.0 + @exp(-x)); }

// k3-parity: XOR(b[0], b[1], b[2]) where b[i] = (c[i] >= THRESH)
fn predK3Par(c: [NCELL]u8) bool {
    var p: u1 = 0;
    for (c[0..3]) |v| p ^= if (v >= THRESH) @as(u1, 1) else 0;
    return p == 1;
}

// Threshold bits for each cell
fn threshBit(c: [NCELL]u8, i: usize) f64 {
    return if (c[i] >= THRESH) 1.0 else 0.0;
}

// Extract degree-2 threshold-bit features: b[0..5] + all b[i]*b[j] for i<j
fn extractDeg2Thresh(c: [NCELL]u8, f: *[MAX_FEAT]f64) void {
    var b: [NCELL]f64 = undefined;
    for (0..NCELL) |i| { b[i] = threshBit(c, i); f[i] = b[i]; }
    var k: usize = NCELL;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        f[k] = b[i] * b[j];
        k += 1;
    };
}

// Train logistic on first nfeat features of g_feat, return test accuracy
fn trainTest(nfeat: usize, niters: usize) f64 {
    var w = [_]f64{0.0} ** MAX_FEAT;
    var b: f64 = 0.0;
    for (0..niters) |_| {
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
    // Store residuals for shadow gradient computation
    for (0..NTRAIN) |i| {
        var logit = b;
        for (0..nfeat) |j| logit += w[j] * g_feat[i][j];
        g_errors[i] = sigmoid(logit) - if (g_labels[i]) @as(f64, 1.0) else 0.0;
    }
    // Test accuracy
    var correct: usize = 0;
    for (NTRAIN..NSAMP) |i| {
        var logit = b;
        for (0..nfeat) |j| logit += w[j] * g_feat[i][j];
        if ((logit >= 0.0) == g_labels[i]) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
}

// Shadow gradient for degree-3 threshold-bit monomial b[i]*b[j]*b[l]
// g = (1/N) Σ_train errᵢ * b[i]*b[j]*b[l](xᵢ)
fn shadowGrad(ii: usize, jj: usize, ll: usize) f64 {
    var g: f64 = 0;
    for (0..NTRAIN) |n| {
        const bi = threshBit(g_cells[n], ii);
        const bj = threshBit(g_cells[n], jj);
        const bl = threshBit(g_cells[n], ll);
        g += g_errors[n] * bi * bj * bl;
    }
    return g / @as(f64, @floatFromInt(NTRAIN));
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var rng: u64 = 0x9BAD_D15C0BEEF11;

    try stdout.print("GRADIENT DISCOVERY  NCELL={d}  VMAX={d}  THRESH={d}  NSAMP={d}\n\n", .{ NCELL, VMAX, THRESH, NSAMP });
    try stdout.print("Predicate: k3-parity = XOR(b[0], b[1], b[2])\n", .{});
    try stdout.print("Substrate: degree-2 threshold-bit features (21 features) — INSUFFICIENT\n\n", .{});

    // Generate data
    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        g_labels[i] = predK3Par(g_cells[i]);
    }

    // Extract degree-2 threshold-bit features
    for (0..NSAMP) |i| extractDeg2Thresh(g_cells[i], &g_feat[i]);

    // ── Step 1: train on degree-2, measure failure ──────────────────────────
    const acc_deg2 = trainTest(NDEG2, NITERS_BASE);
    try stdout.print("Step 1 — train on degree-2 (21 features):\n", .{});
    try stdout.print("  test accuracy = {d:.3}  (expected ~0.50, near chance)\n\n", .{acc_deg2});

    // ── Step 2: compute shadow gradients for all 20 degree-3 monomials ──────
    const Monomial = struct { i: usize, j: usize, l: usize, grad: f64, absg: f64 };
    var monomials: [NDEG3]Monomial = undefined;
    var midx: usize = 0;

    try stdout.print("Step 2 — shadow gradients for degree-3 threshold-bit monomials:\n", .{});
    try stdout.print("  g_k = (1/N) Σ errᵢ * b[i]*b[j]*b[l](xᵢ)  (residual × candidate feature)\n\n", .{});

    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |l| {
        const g = shadowGrad(i, j, l);
        monomials[midx] = .{ .i = i, .j = j, .l = l, .grad = g, .absg = @abs(g) };
        midx += 1;
    };

    // Sort by |gradient| descending (bubble sort — only 20 elements)
    for (0..NDEG3) |a| for (0..NDEG3 - 1 - a) |bb| {
        if (monomials[bb].absg < monomials[bb + 1].absg) {
            const tmp = monomials[bb];
            monomials[bb] = monomials[bb + 1];
            monomials[bb + 1] = tmp;
        }
    };

    try stdout.print("  rank  monomial       |gradient|   is_correct?\n", .{});
    try stdout.print("  ─────────────────────────────────────────────\n", .{});
    for (monomials, 0..) |m, rank| {
        // The correct monomial for k3-parity is b[0]*b[1]*b[2]
        const is_correct = (m.i == 0 and m.j == 1 and m.l == 2);
        try stdout.print("  {d:2}    b[{d}]*b[{d}]*b[{d}]  {d:.6}     {s}\n",
            .{ rank + 1, m.i, m.j, m.l, m.absg,
               if (is_correct) "← CORRECT MONOMIAL" else "" });
    }

    const correct_rank = blk: {
        for (monomials, 0..) |m, rank| {
            if (m.i == 0 and m.j == 1 and m.l == 2) break :blk rank + 1;
        }
        break :blk NDEG3 + 1;
    };
    try stdout.print("\n  Correct monomial b[0]*b[1]*b[2] ranked #{d} out of {d}\n",
        .{ correct_rank, NDEG3 });

    // ── Step 3: greedy extension — add features by shadow gradient rank ──────
    try stdout.print("\nStep 3 — greedy extension: add features in shadow-gradient rank order\n", .{});
    try stdout.print("  (each added feature is the degree-3 monomial with highest |gradient|)\n\n", .{});
    try stdout.print("  features_added  feature_added    test_accuracy\n", .{});
    try stdout.print("  ───────────────────────────────────────────────\n", .{});

    // Start fresh — re-extract degree-2 features
    for (0..NSAMP) |i| extractDeg2Thresh(g_cells[i], &g_feat[i]);

    var nfeat: usize = NDEG2;
    for (monomials[0..@min(8, NDEG3)], 0..) |m, add_idx| {
        // Append this monomial as a new feature (index NDEG2 + add_idx)
        for (0..NSAMP) |i| {
            const bi = threshBit(g_cells[i], m.i);
            const bj = threshBit(g_cells[i], m.j);
            const bl = threshBit(g_cells[i], m.l);
            g_feat[i][nfeat] = bi * bj * bl;
        }
        nfeat += 1;

        // Retrain and measure
        const acc = trainTest(nfeat, NITERS_EXT);
        try stdout.print("  {d:2}              b[{d}]*b[{d}]*b[{d}]   {d:.3}  {s}\n",
            .{ add_idx + 1, m.i, m.j, m.l, acc,
               if (acc > 0.95) "← SOLVED" else if (acc > 0.70) "← improving" else "" });

        if (acc > 0.99) break; // stop if solved
    }

    // ── Step 4: comparison — what if we added features in RANDOM order? ──────
    try stdout.print("\nStep 4 — control: add features in RANDOM order (not gradient-ranked)\n", .{});
    try stdout.print("  shows that gradient ranking is better than random selection\n\n", .{});

    // Re-extract degree-2 features
    for (0..NSAMP) |i| extractDeg2Thresh(g_cells[i], &g_feat[i]);

    // Fixed random ordering of monomials
    var random_order: [NDEG3]usize = undefined;
    for (0..NDEG3) |i| random_order[i] = i;
    // Simple shuffle using the rng at this point
    for (0..NDEG3 - 1) |i| {
        const j = i + lcg(&rng) % (NDEG3 - i);
        const tmp = random_order[i]; random_order[i] = random_order[j]; random_order[j] = tmp;
    }

    // Rebuild monomials list in original index order for lookup
    var all_monomials: [NDEG3]Monomial = undefined;
    var midx2: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |l| {
        all_monomials[midx2] = .{ .i = i, .j = j, .l = l, .grad = 0, .absg = 0 };
        midx2 += 1;
    };

    nfeat = NDEG2;
    try stdout.print("  features_added  feature_added    test_accuracy\n", .{});
    try stdout.print("  ───────────────────────────────────────────────\n", .{});
    for (random_order[0..@min(8, NDEG3)], 0..) |mi, add_idx| {
        const m = all_monomials[mi];
        for (0..NSAMP) |i| {
            const bi = threshBit(g_cells[i], m.i);
            const bj = threshBit(g_cells[i], m.j);
            const bl = threshBit(g_cells[i], m.l);
            g_feat[i][nfeat] = bi * bj * bl;
        }
        nfeat += 1;
        const acc = trainTest(nfeat, NITERS_EXT);
        try stdout.print("  {d:2}              b[{d}]*b[{d}]*b[{d}]   {d:.3}\n",
            .{ add_idx + 1, m.i, m.j, m.l, acc });
        if (acc > 0.99) break;
    }

    try stdout.print("\n{s}\n", .{"─" ** 60});
    try stdout.print("KEY QUESTION: does the gradient rank the CORRECT monomial first?\n", .{});
    try stdout.print("  Correct monomial ranked #{d} (1 = best possible)\n", .{correct_rank});
    try stdout.print("  If #1: gradient IS the substrate discovery signal\n", .{});
    try stdout.print("  If >1: gradient provides partial signal but not perfect\n", .{});
}
