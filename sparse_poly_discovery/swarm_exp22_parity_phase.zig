//! Swarm EXP-22 (F41) — (k, n, samples) phase boundary for sparse parity SGD
//!
//! Learner: logistic regression on ALL C(n,k) degree-k monomials (SGD).
//! Label: XOR(b0,...,b_{k-1}) with bᵢ = (cellᵢ ≥ THRESH).
//! Success: train acc ≥ 0.95 AND held-out acc ≥ 0.90 at minimum sample count.
//!
//! Run: zig build-exe -OReleaseFast swarm_exp22_parity_phase.zig && ./swarm_exp22_parity_phase

const std = @import("std");

const VMAX: u8 = 6;
const THRESH: u8 = 3;
const TRAIN_THRESH: f64 = 0.95;
const HOLD_THRESH: f64 = 0.90;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

const FitResult = struct { train_acc: f64, hold_acc: f64 };

fn fitAndEval(X: []const []f64, Y: []const f64, ntr: usize, nsamp: usize, dim: usize,
              epochs: usize) FitResult {
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

    var train_ok: usize = 0;
    for (0..ntr) |s| {
        var z = bias;
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) train_ok += 1;
    }
    var hold_ok: usize = 0;
    for (ntr..nsamp) |s| {
        var z = bias;
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) hold_ok += 1;
    }
    return .{
        .train_acc = @as(f64, @floatFromInt(train_ok)) / @as(f64, @floatFromInt(ntr)),
        .hold_acc = @as(f64, @floatFromInt(hold_ok)) / @as(f64, @floatFromInt(nsamp - ntr)),
    };
}

fn comb(n: usize, k: usize) usize {
    if (k > n) return 0;
    if (k == 0 or k == n) return 1;
    var c: usize = 1;
    const r = if (k < n - k) k else n - k;
    for (0..r) |i| c = c * (n - i) / (i + 1);
    return c;
}

fn enumSubsets(n: usize, k: usize, subsets: [][]usize) usize {
    var count: usize = 0;
    var total: usize = 1;
    for (0..n) |_| total *= 2;
    for (0..total) |mask| {
        if (@popCount(mask) != k) continue;
        for (0..k) |j| {
            var bit: usize = 0;
            var pos: usize = 0;
            for (0..n) |bi| {
                if (mask & (@as(usize, 1) << @as(u6, @intCast(bi))) != 0) {
                    if (bit == j) {
                        pos = bi;
                        break;
                    }
                    bit += 1;
                }
            }
            subsets[count][j] = pos;
        }
        count += 1;
    }
    return count;
}

const SweepResult = struct {
    min_samples: usize,
    dim: usize,
    train_acc: f64,
    hold_acc: f64,
    found: bool,
};

fn sweepMinSamples(alloc: std.mem.Allocator, k: usize, n: usize, seed: u64) SweepResult {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const dim = comb(n, k);
    if (dim == 0) return .{ .min_samples = 0, .dim = 0, .train_acc = 0, .hold_acc = 0, .found = false };

    const subsets = alloc.alloc([]usize, dim) catch unreachable;
    defer alloc.free(subsets);
    for (0..dim) |i| subsets[i] = alloc.alloc(usize, k) catch unreachable;
    defer for (0..dim) |i| alloc.free(subsets[i]);
    _ = enumSubsets(n, k, subsets);

    const test_sizes = [_]usize{ 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 40000 };

    var last: SweepResult = .{ .min_samples = 0, .dim = dim, .train_acc = 0, .hold_acc = 0, .found = false };
    for (test_sizes) |nsamp| {
        const ntr = nsamp * 2 / 3;

        const cells = alloc.alloc([32]u8, nsamp) catch unreachable;
        defer alloc.free(cells);
        for (0..nsamp) |s| {
            for (0..n) |i| cells[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
        }

        const Y = alloc.alloc(f64, nsamp) catch unreachable;
        defer alloc.free(Y);
        for (0..nsamp) |s| {
            var xr: u32 = 0;
            for (0..k) |j| {
                if (cells[s][j] >= THRESH) xr ^= 1;
            }
            Y[s] = @floatFromInt(xr);
        }

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

        for (0..dim) |j| {
            var mu: f64 = 0;
            for (0..ntr) |s| mu += X[s][j];
            mu /= @floatFromInt(ntr);
            var sd: f64 = 0;
            for (0..ntr) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
            sd = @max(1e-5, @sqrt(sd / @as(f64, @floatFromInt(ntr))));
            for (0..nsamp) |s| X[s][j] = (X[s][j] - mu) / sd;
        }

        const epochs: usize = if (dim > 200) 80 else if (dim > 50) 120 else 150;
        const fit = fitAndEval(X, Y, ntr, nsamp, dim, epochs);

        last = .{
            .min_samples = nsamp,
            .dim = dim,
            .train_acc = fit.train_acc,
            .hold_acc = fit.hold_acc,
            .found = fit.train_acc >= TRAIN_THRESH and fit.hold_acc >= HOLD_THRESH,
        };
        if (last.found) break;
    }
    return last;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== Swarm EXP-22 (F41): sparse parity phase boundary ===\n\n", .{});
    try out.print("Learner: logistic SGD on ALL C(n,k) degree-k monomials\n", .{});
    try out.print("Predicate: y = XOR(b0,...,b_{{k-1}}), bᵢ=(cellᵢ≥{d})\n", .{THRESH});
    try out.print("Success: train ≥ {d:.2} AND held-out ≥ {d:.2} (split 2/3 train, 1/3 hold)\n\n", .{
        TRAIN_THRESH, HOLD_THRESH,
    });

    const ks = [_]usize{ 2, 3, 4 };
    const k2_ns = [_]usize{ 2, 4, 8, 16, 24 };
    const k3_ns = [_]usize{ 3, 6, 9, 12, 16 };
    const k4_ns = [_]usize{ 4, 8, 12, 16, 20 };

    var total_found: usize = 0;
    var total_cells: usize = 0;

    for (ks) |k| {
        try out.print("── k={d} ──\n", .{k});
        try out.print("  n | C(n,k) | min_samples | train | hold | status\n", .{});
        try out.print("  --+--------+-------------+-------+------+--------\n", .{});

        const ns: []const usize = switch (k) {
            2 => &k2_ns,
            3 => &k3_ns,
            4 => &k4_ns,
            else => unreachable,
        };

        for (ns) |n| {
            total_cells += 1;
            const r = sweepMinSamples(alloc, k, n, 0x5EED_0022 ^ (@as(u64, @intCast(k)) << 8) ^ n);
            const status: []const u8 = if (r.found) blk: {
                total_found += 1;
                break :blk "FOUND";
            } else if (r.min_samples >= 40000) "WALL" else "FAIL";
            try out.print(" {d:2} | {d:6} | {d:11} | {d:.3} | {d:.3} | {s}\n", .{
                n, r.dim, r.min_samples, r.train_acc, r.hold_acc, status,
            });
        }
        try out.print("\n", .{});
    }

    try out.print("=== PHASE BOUNDARY SUMMARY ===\n", .{});
    try out.print("Cells with success criterion: {d}/{d}\n", .{ total_found, total_cells });
    try out.print("WALL = did not reach thresholds even at 40000 samples.\n", .{});
    try out.print("n=k rows are expected WALL (single monomial cannot represent XOR).\n", .{});
}