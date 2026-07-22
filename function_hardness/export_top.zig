//! Export top-5 hardest predicates per substrate (n=4 exhaustive).
//! Run: zig build export-top -Doptimize=ReleaseFast

const std = @import("std");

const N_BITS: usize = 4;
const N_IN: usize = 1 << N_BITS;
const N_PREDS: usize = 1 << N_IN;
const EPOCHS: usize = 400;
const LR: f64 = 0.5;
const MAX_DIM: usize = 16;
const TOP_K: usize = 5;

fn b(s: usize, i: usize) f64 {
    return if ((s >> @intCast(i)) & 1 == 1) 1.0 else 0.0;
}

fn xp(s: usize, i: usize, j: usize) f64 {
    const bi: u1 = @truncate(s >> @intCast(i));
    const bj: u1 = @truncate(s >> @intCast(j));
    return if (bi ^ bj == 1) 1.0 else 0.0;
}

const SubstrateId = enum { deg1, deg2, xor2, joint };

fn buildX(s: usize, sub: SubstrateId, out: *[MAX_DIM]f64) usize {
    var d: usize = 0;
    switch (sub) {
        .deg1 => for (0..N_BITS) |i| {
            out[d] = b(s, i);
            d += 1;
        },
        .deg2 => {
            for (0..N_BITS) |i| {
                out[d] = b(s, i);
                d += 1;
            }
            for (0..N_BITS) |i| for (i + 1..N_BITS) |j| {
                out[d] = b(s, i) * b(s, j);
                d += 1;
            };
        },
        .xor2 => for (0..N_BITS) |i| for (i + 1..N_BITS) |j| {
            out[d] = xp(s, i, j);
            d += 1;
        },
        .joint => {
            for (0..N_BITS) |i| {
                out[d] = b(s, i);
                d += 1;
            }
            for (0..N_BITS) |i| for (i + 1..N_BITS) |j| {
                out[d] = xp(s, i, j);
                d += 1;
            };
        },
    }
    return d;
}

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(-20.0, @min(20.0, z))));
}

fn logReg(X: *const [N_IN][MAX_DIM]f64, dim: usize, Y: *const [N_IN]f64) u32 {
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

const Entry = struct { pred: u32, acc: u32 };

fn insertTop(top: *[TOP_K]Entry, n: *usize, pred: u32, acc: u32) void {
    if (n.* < TOP_K) {
        top[n.*] = .{ .pred = pred, .acc = acc };
        n.* += 1;
        return;
    }
    var worst_i: usize = 0;
    for (1..TOP_K) |i| {
        if (top[i].acc > top[worst_i].acc or
            (top[i].acc == top[worst_i].acc and top[i].pred > top[worst_i].pred))
            worst_i = i;
    }
    if (acc < top[worst_i].acc or (acc == top[worst_i].acc and pred < top[worst_i].pred)) {
        top[worst_i] = .{ .pred = pred, .acc = acc };
    }
}

fn sortTop(top: *[TOP_K]Entry, n: usize) void {
    for (0..n) |i| {
        var best = i;
        for (i + 1..n) |j| {
            if (top[j].acc < top[best].acc or
                (top[j].acc == top[best].acc and top[j].pred < top[best].pred))
                best = j;
        }
        const tmp = top[i];
        top[i] = top[best];
        top[best] = tmp;
    }
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const subs = [_]SubstrateId{ .deg1, .deg2, .xor2, .joint };
    const sub_names = [_][]const u8{ "deg1", "deg2", "xor2", "joint" };

    var Xs: [4][N_IN][MAX_DIM]f64 = undefined;
    var dims: [4]usize = undefined;
    for (subs, 0..) |sub, m| {
        for (0..N_IN) |s| dims[m] = buildX(s, sub, &Xs[m][s]);
    }

    var tops: [4][TOP_K]Entry = undefined;
    var top_ns: [4]usize = [_]usize{0} ** 4;
    var Y: [N_IN]f64 = undefined;

    for (0..N_PREDS) |pred| {
        for (0..N_IN) |s| {
            Y[s] = if ((pred >> @intCast(s)) & 1 == 1) 1.0 else 0.0;
        }
        for (0..4) |m| {
            const acc = logReg(&Xs[m], dims[m], &Y);
            insertTop(&tops[m], &top_ns[m], @intCast(pred), acc);
        }
    }

    try stdout.print("# top-{d} hardest predicates per substrate (n=4 exhaustive)\n", .{TOP_K});
    for (0..4) |m| {
        sortTop(&tops[m], top_ns[m]);
        try stdout.print("\n## {s}\n", .{sub_names[m]});
        for (0..top_ns[m]) |i| {
            const e = tops[m][i];
            const corr = @max(e.acc, N_IN - e.acc);
            try stdout.print("  {d}. 0x{X:0>4} raw={d}/16 corrected={d}/16 tt=", .{
                i + 1, e.pred, e.acc, corr,
            });
            for (0..N_IN) |s| try stdout.print("{d}", .{(e.pred >> @intCast(s)) & 1});
            try stdout.print("\n", .{});
        }
    }
}