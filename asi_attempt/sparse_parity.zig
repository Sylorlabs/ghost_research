//! FRONTIER 8 — sparse parity: sample complexity wall for k-of-n monomial discovery
//!
//! Frontier 4 showed k-parity (all k bits relevant) is solved by degree-k monomials
//! in a few thousand samples when n=k (easy case: ALL bits are the relevant ones).
//!
//! This tests the HARD case: n total bits, only k are relevant (positions 0..k-1
//! known to us but unknown to the learner, which uses ALL C(n,k) monomials of degree k).
//!
//! As n grows (more irrelevant bits), there are more degree-k monomials to search
//! through. The signal from the ONE true monomial b0·b1·...·b_{k-1} is diluted by
//! C(n,k)-1 noise monomials. The learner (logistic regression over all degree-k
//! monomials) must pick out the right one.
//!
//! This is the empirical sample complexity curve for sparse parity — the boundary
//! between "cheap monomial search" and "exponentially hard" in the LPN literature.
//!
//! For k=2, n ∈ {2, 4, 8, 16, 32}:
//!   C(n,2) monomials = n(n-1)/2 = 1, 6, 28, 120, 496
//!   Expected: samples needed grows as O(n²/k²) or O(n log n) depending on regime
//!
//! For k=3, n ∈ {3, 6, 12, 24}:
//!   C(n,3) monomials = 1, 20, 220, 2024
//!
//! Measurement: for each (k, n), binary-search for minimum samples giving >90% accuracy.
//! Surprise potential: does the wall appear BEFORE the theoretical exponential blowup?
//!
//! Run: zig build sparse-parity

const std = @import("std");

const VMAX: u8 = 6;
const THRESH: u8 = 3;
const TARGET_ACC: f64 = 0.90;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

// logistic regression on pre-built feature matrix, returns test accuracy
fn logisticAcc(X: []const []f64, Y: []const f64, ntr: usize, dim: usize,
               epochs: usize) f64 {
    const alloc = std.heap.page_allocator;
    const w = alloc.alloc(f64, dim) catch unreachable;
    defer alloc.free(w);
    @memset(w, 0);
    var bias: f64 = 0;
    const lr: f64 = 0.05;
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
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(X.len - ntr));
}

fn comb(n: usize, r: usize) usize {
    if (r > n) return 0;
    if (r == 0 or r == n) return 1;
    var c: usize = 1;
    for (0..r) |i| {
        c = c * (n - i) / (i + 1);
    }
    return c;
}

// enumerate all subsets of size k from {0..n-1}, ordered lexicographically
// writes into subsets[], returns count
fn enumSubsets(n: usize, k: usize, subsets: [][]usize) usize {
    var count: usize = 0;
    // iterate over all bit masks of n bits with popcount = k
    var total: usize = 1;
    for (0..n) |_| total *= 2;
    for (0..total) |mask| {
        if (@popCount(mask) != k) continue;
        for (0..k) |j| {
            var bit: usize = 0;
            var pos: usize = 0;
            for (0..n) |bi| {
                if (mask & (@as(usize, 1) << @as(u6, @intCast(bi))) != 0) {
                    if (bit == j) { pos = bi; break; }
                    bit += 1;
                }
            }
            subsets[count][j] = pos;
        }
        count += 1;
    }
    return count;
}

const TestResult = struct { min_samples: usize, dim: usize };

fn findMinSamples(alloc: std.mem.Allocator, k: usize, n: usize,
                  seed: u64) TestResult {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const dim = comb(n, k);
    if (dim == 0) return .{ .min_samples = 0, .dim = 0 };

    // enumerate all degree-k subsets
    const subsets = alloc.alloc([]usize, dim) catch unreachable;
    defer alloc.free(subsets);
    for (0..dim) |i| subsets[i] = alloc.alloc(usize, k) catch unreachable;
    defer for (0..dim) |i| alloc.free(subsets[i]);
    _ = enumSubsets(n, k, subsets);

    // sizes to test
    const test_sizes = [_]usize{ 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000 };

    // for each sample size, measure test accuracy (train on 2/3, test on 1/3)
    var last_ok: usize = 0;
    for (test_sizes) |nsamp| {
        const ntr = nsamp * 2 / 3;

        // generate raw cell data
        const cells = alloc.alloc([32]u8, nsamp) catch unreachable; // max n=32
        defer alloc.free(cells);
        for (0..nsamp) |s| for (0..n) |i| {
            cells[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
        };

        // compute label: XOR of b_{0}, b_{1}, ..., b_{k-1}
        const Y = alloc.alloc(f64, nsamp) catch unreachable;
        defer alloc.free(Y);
        for (0..nsamp) |s| {
            var xr: u32 = 0;
            for (0..k) |j| {
                if (cells[s][j] >= THRESH) xr ^= 1;
            }
            Y[s] = @floatFromInt(xr);
        }

        // build feature matrix: all degree-k monomials
        const X = alloc.alloc([]f64, nsamp) catch unreachable;
        defer alloc.free(X);
        for (0..nsamp) |s| {
            X[s] = alloc.alloc(f64, dim) catch unreachable;
            for (0..dim) |di| {
                var prod: f64 = 1.0;
                for (0..k) |j| {
                    prod *= if (cells[s][subsets[di][j]] >= THRESH) @as(f64, 1.0) else @as(f64, 0.0);
                }
                X[s][di] = prod;
            }
        }
        defer for (X) |r| alloc.free(r);

        // standardize
        for (0..dim) |j| {
            var mu: f64 = 0;
            for (0..ntr) |s| mu += X[s][j];
            mu /= @floatFromInt(ntr);
            var sd: f64 = 0;
            for (0..ntr) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
            sd = @max(1e-5, @sqrt(sd / @as(f64, @floatFromInt(ntr))));
            for (0..nsamp) |s| X[s][j] = (X[s][j] - mu) / sd;
        }

        const epochs: usize = if (dim > 200) 60 else 120;
        const acc = logisticAcc(X, Y, ntr, dim, epochs);
        if (acc >= TARGET_ACC) {
            last_ok = nsamp;
            break; // found the minimum
        }
        last_ok = nsamp; // track progress even if not reaching target
    }
    return .{ .min_samples = last_ok, .dim = dim };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== FRONTIER 8: sparse parity sample complexity wall ===\n\n", .{});
    try out.print("Predicate: y = XOR(b0,...,b_{{k-1}}),  bᵢ=(cellᵢ≥{d})\n", .{THRESH});
    try out.print("Learner: logistic on ALL C(n,k) monomials of degree k\n", .{});
    try out.print("(Relevant k bits at positions 0..k-1 — unknown to learner)\n", .{});
    try out.print("Target: test accuracy ≥ {d:.0}%%\n\n", .{TARGET_ACC * 100});

    // k=2 experiment
    try out.print("  k=2 (relevant bits: b0·b1)\n", .{});
    try out.print("  n_total | C(n,2) monomials | min samples for {d:.0}%% acc\n", .{TARGET_ACC * 100});
    try out.print("  --------+-----------------+------------------------------\n", .{});
    const k2_ns = [_]usize{ 2, 4, 8, 16, 24 };
    for (k2_ns) |n| {
        const r = findMinSamples(alloc, 2, n, 0x5EED_0002 ^ n);
        try out.print("  {d:6}  |    {d:7}      |    {d:>6} samples\n",
            .{ n, r.dim, r.min_samples });
    }

    try out.print("\n  k=3 (relevant bits: b0·b1·b2)\n", .{});
    try out.print("  n_total | C(n,3) monomials | min samples for {d:.0}%% acc\n", .{TARGET_ACC * 100});
    try out.print("  --------+-----------------+------------------------------\n", .{});
    const k3_ns = [_]usize{ 3, 6, 9, 12 };
    for (k3_ns) |n| {
        if (n > 12) break; // comb(12,3)=220 is manageable; 15 would be 455
        const r = findMinSamples(alloc, 3, n, 0x5EED_0003 ^ n);
        try out.print("  {d:6}  |    {d:7}      |    {d:>6} samples\n",
            .{ n, r.dim, r.min_samples });
    }

    try out.print("\n--- VERDICT ---\n", .{});
    try out.print("Theory: sample complexity should grow as O(C(n,k) · log(C(n,k))) from\n", .{});
    try out.print("VC theory — roughly polynomial in n for fixed k.\n", .{});
    try out.print("If the wall appears BEFORE the theoretical limit, it signals that the\n", .{});
    try out.print("logistic learner is losing the signal faster than VC theory predicts.\n", .{});
    try out.print("This would indicate the closure structure (which monomials are relevant)\n", .{});
    try out.print("is harder to find than the capacity theory suggests — a genuine gap\n", .{});
    try out.print("between learnability and efficient discoverability.\n", .{});
    try out.print("\nSee: higher_order_closure.md (the easy n=k case), parity_closure.md.\n", .{});
}
