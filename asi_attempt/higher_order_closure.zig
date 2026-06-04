//! FRONTIER 4 — the interaction-order ladder: k-parity requires k-th order binding
//!
//! The closure principle says: a search confined to degree-d polynomial features cannot
//! represent a function outside the degree-d algebraic closure. k-parity is the textbook
//! example: XOR(b0,...,b_{k-1}) requires the degree-k product monomial b0·b1·...·b_{k-1}.
//! No degree-(k-1) polynomial map separates it (this is a theorem from Boolean complexity).
//!
//! This experiment MEASURES the ceiling empirically in the repo's framework:
//!
//!   For k ∈ {2, 3, 4, 5}:
//!     label = XOR(b0,...,b_{k-1})   where bᵢ = (cellᵢ ≥ H)
//!     features of degree d ∈ {1, 2, 3, k}
//!     → accuracy should stay at chance until d = k, then jump to near 1.0
//!
//! Features: all monomials of degree ≤ d over the raw binary threshold bits b₀...b_{K−1}.
//! No Clifford: we showed real≡Clifford for symmetric predicates; the question here is ORDER.
//!
//! This is the honest closure ladder — the same principle that organises the mixer ceiling
//! (GF(2)-affine → needs ADD then MUL) instantiated over Boolean interaction depth.
//!
//! Run: zig build higher-order-closure

const std = @import("std");

const NCELL: usize = 8;  // cells; we'll test k ∈ 2..5 using cells 0..k-1
const VMAX: u8 = 6;
const THRESH: u8 = 3;
const NSAMP: usize = 6000;
const NTR:   usize = NSAMP / 2;
const EPOCHS: usize = 120;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn standardize(X: [][]f64, ntr: usize, dim: usize) void {
    for (0..dim) |j| {
        var mu: f64 = 0;
        for (0..ntr) |s| mu += X[s][j];
        mu /= @floatFromInt(ntr);
        var sd: f64 = 0;
        for (0..ntr) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
        sd = @max(1e-5, @sqrt(sd / @as(f64, @floatFromInt(ntr))));
        for (0..X.len) |s| X[s][j] = (X[s][j] - mu) / sd;
    }
}

fn linAcc(X: []const []f64, Y: []const f64, ntr: usize, dim: usize) f64 {
    const alloc = std.heap.page_allocator;
    const w = alloc.alloc(f64, dim) catch unreachable;
    defer alloc.free(w);
    @memset(w, 0);
    var bias: f64 = 0;
    const lr: f64 = 0.05;
    for (0..EPOCHS) |_| for (0..ntr) |s| {
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

// enumerate all monomials of degree exactly d over bits b[0..k]
// writes into feat starting at offset, returns count written
fn appendMonomials(bits: []const f64, k: usize, deg: usize,
                   start: usize, feat: []f64, offset: *usize) void {
    // iterate over all subsets of {0..k-1} of size deg
    var total: usize = 1;
    for (0..k) |_| total *= 2;
    for (0..total) |mask| {
        if (@popCount(mask) != deg) continue;
        var prod: f64 = 1.0;
        for (0..k) |j| {
            if (mask & (@as(usize, 1) << @as(u6, @intCast(j))) != 0) prod *= bits[start + j];
        }
        feat[offset.*] = prod;
        offset.* += 1;
    }
}

fn countMonomials(k: usize, max_deg: usize) usize {
    var total: usize = 0;
    for (1..max_deg + 1) |d| {
        // C(k, d)
        var c: usize = 1;
        for (0..d) |i| {
            c = c * (k - i) / (i + 1);
        }
        total += c;
    }
    return total;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0xB100D1F7);
    const rand = prng.random();

    // raw cell data and binary bits
    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    const bits  = try alloc.alloc([NCELL]f64, NSAMP);
    defer alloc.free(grid);
    defer alloc.free(bits);

    for (0..NSAMP) |s| {
        for (0..NCELL) |i| {
            grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
            bits[s][i] = if (grid[s][i] >= THRESH) @as(f64, 1.0) else @as(f64, 0.0);
        }
    }

    try out.print("=== FRONTIER 4: k-parity interaction-order ladder ===\n\n", .{});
    try out.print("Predicate: y = XOR(b0,...,b_{{k-1}}),  bᵢ = (cellᵢ ≥ {d})\n", .{THRESH});
    try out.print("Features: all monomials of degree ≤ d over b0..b_{{k-1}} (linear logistic readout)\n\n", .{});
    try out.print("Theory: k-parity is NOT in the closure of degree-(k−1) polynomials.\n", .{});
    try out.print("Prediction: accuracy ≈ chance for d < k;  accuracy → 1.0 at d = k.\n\n", .{});
    try out.print("  k  | d=1   | d=2   | d=3   | d=4   | d=5  | theory\n", .{});
    try out.print("  ---+-------+-------+-------+-------+------+-------\n", .{});

    const max_k: usize = 5;
    for (2..max_k + 1) |k| {
        // build labels: k-parity
        const Y = try alloc.alloc(f64, NSAMP);
        defer alloc.free(Y);
        for (0..NSAMP) |s| {
            var xor: u32 = 0;
            for (0..k) |i| xor ^= @intFromBool(bits[s][i] > 0.5);
            Y[s] = @floatFromInt(xor);
        }

        // for each feature degree test
        var acc_by_deg: [5]f64 = .{0} ** 5;
        for (1..6) |d| {
            if (d > k + 1) { acc_by_deg[d - 1] = 99; continue; } // not useful to measure
            const dim = countMonomials(k, d);
            if (dim == 0) continue;
            const X = try alloc.alloc([]f64, NSAMP);
            defer {
                for (X) |r| alloc.free(r);
                alloc.free(X);
            }
            for (0..NSAMP) |s| {
                X[s] = try alloc.alloc(f64, dim);
                var offset: usize = 0;
                for (1..d + 1) |deg| {
                    appendMonomials(&bits[s], k, deg, 0, X[s], &offset);
                }
            }
            standardize(X, NTR, dim);
            acc_by_deg[d - 1] = linAcc(X, Y, NTR, dim);
        }

        try out.print("  {d}  | {d:.3} | {d:.3} | {d:.3} | {d:.3} | {d:.3}| need d={d}\n",
            .{ k, acc_by_deg[0], acc_by_deg[1], acc_by_deg[2], acc_by_deg[3], acc_by_deg[4], k });
    }

    try out.print("\n--- VERDICT ---\n", .{});
    try out.print("If theory holds: each row should show chance (≈0.50) until the d=k column,\n", .{});
    try out.print("then jump to ≈1.0. The ceiling at each order is a REPRESENTATIONAL FACT,\n", .{});
    try out.print("not a training failure. Adding features of the correct degree collapses it.\n", .{});
    try out.print("\nThis is the same closure principle as:\n", .{});
    try out.print("  - GF(2)-affine mixer ceiling (needs ADD, then MUL)\n", .{});
    try out.print("  - VSA band ceiling (needs SUM, an out-of-XOR generator)\n", .{});
    try out.print("  - Parity closure (linear readout needs the product monomial)\n", .{});
    try out.print("instantiated over the INTERACTION ORDER axis: k-order closure requires k-order substrate.\n", .{});
    try out.print("\nSee: parity_closure.md, CLOSURE_PRINCIPLE.md.\n", .{});
}
