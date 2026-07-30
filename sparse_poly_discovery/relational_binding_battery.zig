//! EXP-3 relational battery — blind substrate selector on genuinely relational predicates.
//!
//! Compares focal-pair substrates (not symmetric mass/sum):
//!   product(i,j)     scalar cᵢ·cⱼ  (structure_discovery menu inner)
//!   cliff_biv        grade-2 sin(θ(vⱼ−vᵢ))  shared Cl(2,0)
//!   cliff_geo_sym    grade-0 cos(θ(vᵢ−vⱼ))  symmetric part of geo product
//!   cov_ij           centered product (cᵢ−μ)(cⱼ−μ)
//!   bundle_ij        [cᵢ ; cⱼ] first-order ordered
//!
//! Predicates:
//!   hidden_pair      XOR(bᵢ,bⱼ) on pair (2,5) — symmetric, needs interaction
//!   oriented_pair    sign(vⱼ−vᵢ) on (0,1) — antisymmetric
//!   covariance       sign((v₀−μ)(v₁−μ)) on (0,1) — symmetric distributional
//!
//! Run: zig build relational-binding-battery

const std = @import("std");

const NCELL: usize = 6;
const VMAX: u8 = 6;
const THRESH: u8 = 3;
const THETA: f32 = 0.40;
const MU: f32 = 3.5;
const NSAMP: usize = 4000;
const NTR: usize = NSAMP / 2;
const NVAL: usize = NSAMP / 4;
const NTE: usize = NSAMP - NTR - NVAL;

const Substrate = enum {
    bundle_ij,
    product_ij,
    cliff_biv,
    cliff_geo_sym,
    cov_ij,

    fn name(self: Substrate) []const u8 {
        return switch (self) {
            .bundle_ij => "bundle_ij [ci;cj]",
            .product_ij => "product_ij ci*cj",
            .cliff_biv => "cliff_biv sin(θΔ)",
            .cliff_geo_sym => "cliff_geo_sym cos(θΔ)",
            .cov_ij => "cov_ij (ci-μ)(cj-μ)",
        };
    }
};

const Pred = struct {
    name: []const u8,
    i: usize,
    j: usize,
    label_fn: *const fn (f32, f32, f32, f32) f32,

    fn hiddenPair(_: f32, _: f32, bi: f32, bj: f32) f32 {
        return if ((bi > 0.5) != (bj > 0.5)) 1.0 else 0.0;
    }
    fn oriented(_: f32, _: f32, v0: f32, v1: f32) f32 {
        return if (v1 > v0) 1.0 else 0.0;
    }
    fn covariance(v0: f32, v1: f32, _: f32, _: f32) f32 {
        return if ((v0 - MU) * (v1 - MU) > 0) 1.0 else 0.0;
    }
};

const PREDS = [_]Pred{
    .{ .name = "hidden_pair(2,5)", .i = 2, .j = 5, .label_fn = Pred.hiddenPair },
    .{ .name = "oriented_pair(0,1)", .i = 0, .j = 1, .label_fn = Pred.oriented },
    .{ .name = "covariance(0,1)", .i = 0, .j = 1, .label_fn = Pred.covariance },
};

fn sigmoid(z: f32) f32 {
    return 1.0 / (1.0 + @exp(-@max(@as(f32, -30), @min(@as(f32, 30), z))));
}

fn standardize(X: [][]f32, n_fit: usize, dim: usize) void {
    for (0..dim) |d| {
        var mu: f32 = 0;
        for (0..n_fit) |s| mu += X[s][d];
        mu /= @floatFromInt(n_fit);
        var sd: f32 = 0;
        for (0..n_fit) |s| sd += (X[s][d] - mu) * (X[s][d] - mu);
        sd = @max(1e-4, @sqrt(sd / @as(f32, @floatFromInt(n_fit))));
        for (0..X.len) |s| X[s][d] = (X[s][d] - mu) / sd;
    }
}

const AccSplit = struct { train_acc: f32, val_acc: f32, test_acc: f32 };

fn linAccSplit(X: [][]f32, Y: []const f32, tr_end: usize, val_end: usize, dim: usize, epochs: usize) AccSplit {
    const alloc = std.heap.page_allocator;
    const w = alloc.alloc(f32, dim) catch unreachable;
    defer alloc.free(w);
    @memset(w, 0);
    var bias: f32 = 0;
    const lr: f32 = 0.03;
    for (0..epochs) |_| for (0..tr_end) |s| {
        var z = bias;
        for (0..dim) |d| z += w[d] * X[s][d];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |d| w[d] -= lr * e * X[s][d];
        bias -= lr * e;
    };
    return .{
        .train_acc = score(X, Y, w, bias, 0, tr_end, dim),
        .val_acc = score(X, Y, w, bias, tr_end, val_end, dim),
        .test_acc = score(X, Y, w, bias, val_end, X.len, dim),
    };
}

fn score(X: [][]f32, Y: []const f32, w: []const f32, bias: f32, start: usize, end: usize, dim: usize) f32 {
    var correct: usize = 0;
    for (start..end) |s| {
        var z = bias;
        for (0..dim) |d| z += w[d] * X[s][d];
        if ((z >= 0) == (Y[s] > 0.5)) correct += 1;
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(end - start));
}

fn substrateDim(sub: Substrate) usize {
    return switch (sub) {
        .bundle_ij => 2,
        .product_ij, .cliff_biv, .cliff_geo_sym, .cov_ij => 1,
    };
}

fn fillFeatures(sub: Substrate, vi: f32, vj: f32, out: []f32) void {
    switch (sub) {
        .bundle_ij => {
            out[0] = vi;
            out[1] = vj;
        },
        .product_ij => out[0] = vi * vj,
        .cliff_biv => out[0] = @sin(THETA * (vj - vi)),
        .cliff_geo_sym => out[0] = @cos(THETA * (vi - vj)),
        .cov_ij => out[0] = (vi - MU) * (vj - MU),
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0xE3C1100D);
    const rand = prng.random();

    const SUBS = [_]Substrate{ .bundle_ij, .product_ij, .cliff_biv, .cliff_geo_sym, .cov_ij };

    try out.print("=== EXP-3 relational binding battery (blind substrate selector) ===\n\n", .{});
    try out.print("Split: train {d} / val {d} / test {d}. Linear readout, shared θ={d:.2}.\n\n", .{ NTR, NVAL, NTE, THETA });

    var cliff_beats_product_any = false;
    var product_beats_cliff_any = false;

    for (PREDS) |pred| {
        const Y = try alloc.alloc(f32, NSAMP);
        defer alloc.free(Y);

        const mats = blk: {
            var m: [SUBS.len][][]f32 = undefined;
            for (SUBS, 0..) |sub, si| {
                const dim = substrateDim(sub);
                m[si] = try alloc.alloc([]f32, NSAMP);
                for (0..NSAMP) |s| {
                    var g: [NCELL]u8 = undefined;
                    for (0..NCELL) |c| g[c] = rand.intRangeAtMost(u8, 0, VMAX);
                    const vi: f32 = @floatFromInt(g[pred.i]);
                    const vj: f32 = @floatFromInt(g[pred.j]);
                    const bi: f32 = if (g[pred.i] >= THRESH) 1.0 else 0.0;
                    const bj: f32 = if (g[pred.j] >= THRESH) 1.0 else 0.0;
                    Y[s] = pred.label_fn(vi, vj, bi, bj);
                    m[si][s] = try alloc.alloc(f32, dim);
                    fillFeatures(sub, vi, vj, m[si][s]);
                }
            }
            break :blk m;
        };
        defer for (SUBS, 0..) |_, si| {
            for (mats[si]) |row| alloc.free(row);
            alloc.free(mats[si]);
        };

        for (SUBS, 0..) |_, si| standardize(mats[si], NTR, substrateDim(SUBS[si]));

        var best_val: f32 = -1;
        var best_sub: Substrate = .product_ij;
        var best_test: f32 = 0;

        try out.print("--- {s} ---\n", .{pred.name});
        try out.print("  substrate                  |  train |   val |  test\n", .{});
        try out.print("  ---------------------------+--------+-------+------\n", .{});

        var prod_test: f32 = 0;
        var cliff_biv_test: f32 = 0;

        for (SUBS, 0..) |sub, si| {
            const dim = substrateDim(sub);
            const acc = linAccSplit(mats[si], Y, NTR, NTR + NVAL, dim, 120);
            const marker: []const u8 = if (acc.val_acc > best_val + 0.001) "*" else "";
            try out.print("  {s:<26} | {d:.3}  | {d:.3} | {d:.3}{s}\n", .{ sub.name(), acc.train_acc, acc.val_acc, acc.test_acc, marker });
            if (acc.val_acc > best_val + 0.001) {
                best_val = acc.val_acc;
                best_sub = sub;
                best_test = acc.test_acc;
            } else if (@abs(acc.val_acc - best_val) <= 0.001 and @intFromEnum(sub) < @intFromEnum(best_sub)) {
                best_sub = sub;
                best_test = acc.test_acc;
            }
            if (sub == .product_ij) prod_test = acc.test_acc;
            if (sub == .cliff_biv) cliff_biv_test = acc.test_acc;
        }

        if (cliff_biv_test > prod_test + 0.03) cliff_beats_product_any = true;
        if (prod_test > cliff_biv_test + 0.03) product_beats_cliff_any = true;

        try out.print("  BLIND PICK: {s}  (val={d:.3}, test={d:.3})\n\n", .{ best_sub.name(), best_val, best_test });
    }

    try out.print("--- CROSS-SUBSTRATE SUMMARY ---\n", .{});
    try out.print("  cliff_biv beats product_ij (>0.03) on any predicate? {s}\n", .{if (cliff_beats_product_any) "YES" else "NO"});
    try out.print("  product_ij beats cliff_biv (>0.03) on any predicate? {s}\n", .{if (product_beats_cliff_any) "YES" else "NO"});
    try out.print("\nSee: clifford_relational, antisymmetric_relational, oriented_control.\n", .{});
}