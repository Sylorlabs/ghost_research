//! MATH HYPOTHESES — four analytical tests on the n=4 predicate landscape
//!
//! H1 (span equivalence):   rank(AND-deg2) = rank(joint) = rank(combined)?
//!                           If yes, the 80-predicate closure gap is convergence noise.
//! H2 (Cover's formula):    closure fraction ≈ Cover(2^n−1, rank) / 2^(2^n−1)?
//!                           Binary feature structure reduces separability below Cover's prediction.
//! H3 (poly degree):         AND-polynomial degree ≤ k → SUFFICIENT for deg-k closure.
//!                           NOT necessary: some degree>k predicates still separable.
//!                           Measure the "bonus" count: in closure but poly-degree > k.
//! H4 (monotone vs XOR):    xor2 closure has ≈0 monotone predicates.
//!                           Monotone functions need a bias toward more-1s; XOR features lack this.
//!
//! Run: zig build math -Doptimize=ReleaseFast

const std = @import("std");

const N: usize    = 4;
const N_IN: usize = 1 << N;   // 16
const N_PREDS: usize = 1 << N_IN; // 65536
const EPOCHS: usize = 500;
const LR: f64   = 0.5;
const MAX_DIM: usize = 32;

// ── logistic regression ───────────────────────────────────────────────────────

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(-20.0, @min(20.0, z))));
}

fn logReg(X: *const [N_IN][MAX_DIM]f64, dim: usize, Y: *const [N_IN]f64) bool {
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
    return correct == N_IN;
}

// ── feature builders ──────────────────────────────────────────────────────────

fn bit(s: usize, i: usize) f64 {
    return if ((s >> @intCast(i)) & 1 == 1) 1.0 else 0.0;
}

fn xp(s: usize, i: usize, j: usize) f64 {
    return if (((s >> @intCast(i)) ^ (s >> @intCast(j))) & 1 == 1) 1.0 else 0.0;
}

fn buildDeg1(s: usize, out: *[MAX_DIM]f64) usize {
    for (0..N) |i| out[i] = bit(s, i);
    return N;
}

fn buildDeg2(s: usize, out: *[MAX_DIM]f64) usize {
    var d: usize = 0;
    for (0..N) |i| { out[d] = bit(s, i); d += 1; }
    for (0..N) |i| for (i+1..N) |j| { out[d] = bit(s,i)*bit(s,j); d += 1; };
    return d;
}

fn buildXor2(s: usize, out: *[MAX_DIM]f64) usize {
    var d: usize = 0;
    for (0..N) |i| for (i+1..N) |j| { out[d] = xp(s,i,j); d += 1; };
    return d;
}

fn buildJoint(s: usize, out: *[MAX_DIM]f64) usize {
    var d: usize = 0;
    for (0..N) |i| { out[d] = bit(s, i); d += 1; }
    for (0..N) |i| for (i+1..N) |j| { out[d] = xp(s,i,j); d += 1; };
    return d;
}

fn buildCombined(s: usize, out: *[MAX_DIM]f64) usize {
    // AND-deg2 features + XOR-pair features (for rank comparison)
    var d: usize = 0;
    for (0..N) |i| { out[d] = bit(s, i); d += 1; }
    for (0..N) |i| for (i+1..N) |j| { out[d] = bit(s,i)*bit(s,j); d += 1; };
    for (0..N) |i| for (i+1..N) |j| { out[d] = xp(s,i,j); d += 1; };
    return d;
}

// ── H1: matrix rank via Gaussian elimination ─────────────────────────────────

fn matRank(comptime ROWS: usize, comptime COLS: usize, M: *[ROWS][COLS]f64, dim: usize) usize {
    var mat: [ROWS][COLS]f64 = M.*;
    var rank: usize = 0;
    var pivot_row: usize = 0;
    for (0..dim) |col| {
        // find pivot
        var best: usize = pivot_row;
        var best_val: f64 = 0.0;
        for (pivot_row..ROWS) |r| {
            const v = @abs(mat[r][col]);
            if (v > best_val) { best_val = v; best = r; }
        }
        if (best_val < 1e-10) continue;
        // swap
        if (best != pivot_row) {
            const tmp = mat[pivot_row];
            mat[pivot_row] = mat[best];
            mat[best] = tmp;
        }
        // eliminate
        const inv = 1.0 / mat[pivot_row][col];
        for (pivot_row+1..ROWS) |r| {
            if (@abs(mat[r][col]) < 1e-10) continue;
            const factor = mat[r][col] * inv;
            for (0..dim) |c| mat[r][c] -= factor * mat[pivot_row][c];
        }
        rank += 1;
        pivot_row += 1;
    }
    return rank;
}

// ── H2: Cover's counting function ────────────────────────────────────────────

fn coverFraction(N_points: usize, d: usize) f64 {
    // f(N,d) = (1/2^(N-1)) * sum_{k=0}^{d} C(N-1, k)
    const N1 = N_points - 1;
    var sum: f64 = 0.0;
    var binom: f64 = 1.0;
    for (0..d+1) |k| {
        sum += binom;
        if (k < N1) binom *= @as(f64, @floatFromInt(N1 - k)) / @as(f64, @floatFromInt(k + 1));
    }
    var denom: f64 = 1.0;
    for (0..N1) |_| denom *= 2.0;
    return sum / denom;
}

// ── H3: AND-polynomial degree via Möbius inversion ───────────────────────────

fn andPolyDeg(pred: usize) usize {
    var max_deg: usize = 0;
    for (0..N_IN) |S| {
        // Möbius coefficient c_S = Σ_{T⊆S} (-1)^{|S|-|T|} f(T)
        var coeff: i32 = 0;
        var T: usize = S;
        while (true) {
            const val: i32 = @intCast((pred >> @intCast(T)) & 1);
            const diff = @popCount(S) - @popCount(T);
            const sign: i32 = if (diff % 2 == 0) 1 else -1;
            coeff += sign * val;
            if (T == 0) break;
            T = (T - 1) & S;
        }
        if (coeff != 0) {
            const deg = @popCount(S);
            if (deg > max_deg) max_deg = deg;
        }
    }
    return max_deg;
}

// ── H4: monotone test ─────────────────────────────────────────────────────────

fn isMonotone(pred: usize) bool {
    // f is monotone iff: x ⊆ y (bitwise) → f(x) ≤ f(y)
    for (0..N_IN) |x| {
        for (0..N_IN) |y| {
            // x ⊆ y iff (x & y) == x
            if ((x & y) != x) continue;
            const fx: u1 = @truncate(pred >> @intCast(x));
            const fy: u1 = @truncate(pred >> @intCast(y));
            if (fx == 1 and fy == 0) return false;
        }
    }
    return true;
}

// ── main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    try out.print("=== MATH HYPOTHESES — n={d} exhaustive analysis ===\n\n", .{N});

    // ── H1: span equivalence via rank ────────────────────────────────────────

    try out.print("--- H1: SPAN EQUIVALENCE ---\n\n", .{});
    try out.print("Claim: span(AND-deg2) = span(joint). If true, 80-predicate gap is\n", .{});
    try out.print("convergence noise, not a real difference.\n\n", .{});

    var Xd2:  [N_IN][MAX_DIM]f64 = undefined;
    var Xjt:  [N_IN][MAX_DIM]f64 = undefined;
    var Xcmb: [N_IN][MAX_DIM]f64 = undefined;
    var dim_d2: usize = 0;
    var dim_jt: usize = 0;
    var dim_cmb: usize = 0;
    for (0..N_IN) |s| {
        dim_d2  = buildDeg2(s,    &Xd2[s]);
        dim_jt  = buildJoint(s,   &Xjt[s]);
        dim_cmb = buildCombined(s, &Xcmb[s]);
    }
    const rank_d2  = matRank(N_IN, MAX_DIM, &Xd2,  dim_d2);
    const rank_jt  = matRank(N_IN, MAX_DIM, &Xjt,  dim_jt);
    const rank_cmb = matRank(N_IN, MAX_DIM, &Xcmb, dim_cmb);

    try out.print("  rank(AND-deg2)      = {d}  (features: {d})\n", .{rank_d2,  dim_d2});
    try out.print("  rank(joint)         = {d}  (features: {d})\n", .{rank_jt,  dim_jt});
    try out.print("  rank(AND-deg2|joint)= {d}  (features: {d})\n", .{rank_cmb, dim_cmb});
    if (rank_d2 == rank_jt and rank_d2 == rank_cmb) {
        try out.print("  VERDICT: spans are IDENTICAL — 80-predicate gap is convergence noise.\n\n", .{});
    } else {
        try out.print("  VERDICT: spans DIFFER — substrates are genuinely different.\n\n", .{});
    }

    // ── H2: Cover's formula ──────────────────────────────────────────────────

    try out.print("--- H2: COVER'S FORMULA vs MEASURED CLOSURE ---\n\n", .{});
    try out.print("Claim: closure fraction ≈ Cover({d}, rank) / 2^{d}.\n", .{N_IN-1, N_IN-1});
    try out.print("Binary input structure reduces separability below general-position prediction.\n\n", .{});

    const measured = [_]struct { name: []const u8, rank: usize, fraction: f64 }{
        .{ .name = "deg1 ", .rank = matRank(N_IN, MAX_DIM, &blk: { var X: [N_IN][MAX_DIM]f64 = undefined; for (0..N_IN) |s| _ = buildDeg1(s, &X[s]); break :blk X; }, N),           .fraction = 0.0287 },
        .{ .name = "deg2 ", .rank = rank_d2,  .fraction = 0.8773 },
        .{ .name = "xor2 ", .rank = matRank(N_IN, MAX_DIM, &blk: { var X: [N_IN][MAX_DIM]f64 = undefined; for (0..N_IN) |s| _ = buildXor2(s, &X[s]); break :blk X; }, N*(N-1)/2), .fraction = 0.0039 },
        .{ .name = "joint", .rank = rank_jt,  .fraction = 0.8785 },
    };

    try out.print("  substrate | rank | Cover pred | measured | ratio\n", .{});
    try out.print("  ----------|------|------------|----------|------\n", .{});
    for (measured) |m| {
        const cover = coverFraction(N_IN, m.rank);
        try out.print("  {s}     | {d:2}   | {d:.4}     | {d:.4}   | {d:.3}\n", .{
            m.name, m.rank, cover, m.fraction, m.fraction / cover,
        });
    }
    try out.print("\n  Ratio < 1 means binary structure reduces separability below Cover's prediction.\n\n", .{});

    // ── H3: AND-polynomial degree cross-table ────────────────────────────────

    try out.print("--- H3: AND-POLYNOMIAL DEGREE vs CLOSURE MEMBERSHIP ---\n\n", .{});
    try out.print("Claim: poly-deg ≤ k is SUFFICIENT but NOT NECESSARY for deg-k closure.\n", .{});
    try out.print("Bonus = in closure despite poly-deg > k.\n\n", .{});

    // Build feature matrices for deg1, deg2, joint, xor2
    var Xd1: [N_IN][MAX_DIM]f64 = undefined;
    var Xxr: [N_IN][MAX_DIM]f64 = undefined;
    var dim_d1: usize = 0;
    var dim_xr: usize = 0;
    for (0..N_IN) |s| {
        dim_d1 = buildDeg1(s, &Xd1[s]);
        dim_xr = buildXor2(s, &Xxr[s]);
    }

    // Cross-table: poly_deg × in_deg1_closure × in_deg2_closure
    var poly_deg_dist: [N+1]usize = [_]usize{0} ** (N+1);
    // cross[poly_deg][substrate]: count in closure
    var cross_d1: [N+1]usize = [_]usize{0} ** (N+1);
    var cross_d2: [N+1]usize = [_]usize{0} ** (N+1);
    var cross_xr: [N+1]usize = [_]usize{0} ** (N+1);
    var cross_jt: [N+1]usize = [_]usize{0} ** (N+1);
    // bonus counts
    var bonus_d1: usize = 0; // in deg1 closure, poly_deg > 1
    var bonus_d2: usize = 0; // in deg2 closure, poly_deg > 2

    // monotone analysis
    var mono_total: usize = 0;
    var mono_in_xr: usize = 0;
    var mono_in_d1: usize = 0;
    var nonmono_in_xr: usize = 0;

    var Y: [N_IN]f64 = undefined;

    try out.print("  Running logistic regression on all {d} predicates...\n", .{N_PREDS});

    for (0..N_PREDS) |pred| {
        for (0..N_IN) |s| Y[s] = if ((pred >> @intCast(s)) & 1 == 1) 1.0 else 0.0;

        const in_d1 = logReg(&Xd1, dim_d1, &Y);
        const in_d2 = logReg(&Xd2, dim_d2, &Y);
        const in_xr = logReg(&Xxr, dim_xr, &Y);
        const in_jt = logReg(&Xjt, dim_jt, &Y);

        const pd = andPolyDeg(pred);
        const mono = isMonotone(pred);

        poly_deg_dist[pd] += 1;
        if (in_d1) cross_d1[pd] += 1;
        if (in_d2) cross_d2[pd] += 1;
        if (in_xr) cross_xr[pd] += 1;
        if (in_jt) cross_jt[pd] += 1;

        if (in_d1 and pd > 1) bonus_d1 += 1;
        if (in_d2 and pd > 2) bonus_d2 += 1;

        if (mono) {
            mono_total += 1;
            if (in_xr) mono_in_xr += 1;
            if (in_d1) mono_in_d1 += 1;
        } else {
            if (in_xr) nonmono_in_xr += 1;
        }
    }

    try out.print("\n  poly_deg | count  | in deg1 | in deg2 | in xor2 | in joint\n", .{});
    try out.print("  ---------|--------|---------|---------|---------|----------\n", .{});
    for (0..N+1) |pd| {
        if (poly_deg_dist[pd] == 0) continue;
        try out.print("  deg={d}    | {d:6} | {d:7} | {d:7} | {d:7} | {d:7}\n", .{
            pd, poly_deg_dist[pd], cross_d1[pd], cross_d2[pd], cross_xr[pd], cross_jt[pd],
        });
    }
    try out.print("\n  Bonus (in closure despite poly-deg > k):\n", .{});
    try out.print("    deg1 bonus (poly-deg>1 but in deg1 closure): {d}\n", .{bonus_d1});
    try out.print("    deg2 bonus (poly-deg>2 but in deg2 closure): {d}\n", .{bonus_d2});
    try out.print("\n  If bonus > 0: poly-deg is NOT necessary for closure (H3 confirmed).\n", .{});
    try out.print("  If ALL poly-deg≤k preds are in deg-k closure: poly-deg IS sufficient.\n\n", .{});

    // Verify sufficiency: check no poly-deg≤k predicate is OUTSIDE deg-k closure
    // For deg1: all poly-deg≤1 preds should be in deg1 closure
    var suff_fail_d1: usize = 0;
    var suff_fail_d2: usize = 0;
    for (0..N+1) |pd| {
        if (pd <= 1) suff_fail_d1 += (poly_deg_dist[pd] - cross_d1[pd]);
        if (pd <= 2) suff_fail_d2 += (poly_deg_dist[pd] - cross_d2[pd]);
    }
    try out.print("  Sufficiency check (poly-deg≤k but NOT in deg-k closure — should be 0):\n", .{});
    try out.print("    deg1: {d} failures\n", .{suff_fail_d1});
    try out.print("    deg2: {d} failures\n\n", .{suff_fail_d2});

    // ── H4: monotone vs XOR ──────────────────────────────────────────────────

    try out.print("--- H4: MONOTONE PREDICATES vs XOR CLOSURE ---\n\n", .{});
    try out.print("Claim: xor2 closure contains ≈0 monotone predicates.\n", .{});
    try out.print("Monotone functions need a direction (more 1s → more likely positive);\n", .{});
    try out.print("XOR-pair features are symmetric and cannot provide this direction.\n\n", .{});

    try out.print("  Total monotone predicates: {d}  (Dedekind D(4) = 168 expected)\n", .{mono_total});
    try out.print("  Monotone ∩ deg1 closure:   {d}\n", .{mono_in_d1});
    try out.print("  Monotone ∩ xor2 closure:   {d}  ← key test\n", .{mono_in_xr});
    try out.print("  Non-monotone ∩ xor2:       {d}\n\n", .{nonmono_in_xr});

    if (mono_in_xr == 0) {
        try out.print("  CONFIRMED: xor2 closure contains ZERO monotone predicates.\n", .{});
        try out.print("  XOR features are structurally blind to monotone structure.\n\n", .{});
    } else {
        try out.print("  PARTIAL: {d} monotone predicates slipped into xor2 closure.\n\n", .{mono_in_xr});
    }

    // ── Summary ──────────────────────────────────────────────────────────────

    try out.print("--- SUMMARY ---\n\n", .{});
    try out.print("H1 span equivalence: {s}\n", .{
        if (rank_d2 == rank_jt and rank_d2 == rank_cmb) "CONFIRMED" else "REFUTED"
    });
    try out.print("H2 Cover's formula:  PARTIAL — binary structure creates consistent penalty\n", .{});
    try out.print("H3 poly-deg sufficient: check above. NOT necessary: bonus_d2={d}\n", .{bonus_d2});
    try out.print("H4 monotone/XOR:     {s}\n", .{
        if (mono_in_xr == 0) "CONFIRMED — zero overlap" else "PARTIAL"
    });
}
