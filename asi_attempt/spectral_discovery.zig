//! FRONTIER 2 (closing C's gap) — a PERIODICITY-AWARE operator discovers the primitive
//! parameter ω where gradient structurally cannot.
//!
//! family_gradient.md (RQ C23) showed gradient descent cannot find ω=π for parity: the
//! ω-gradient ∝ −count·sin(ω·count) VANISHES at the optimum (sin(π·integer)=0), so ω=π is a
//! measure-zero spike invisible to first-order methods. The doc named the fix: a "periodicity-
//! aware / spectral" discovery operator. This builds it and shows it works.
//!
//! The operator does NOT search ω against classification accuracy (the forge's grid method)
//! and does NOT use gradients. It transforms to the domain where a period is a single peak:
//!   1. estimate the conditional-mean signal f(c) = E[label | count = c];
//!   2. take its (count-weighted) power spectrum over ω;
//!   3. the PEAK frequency IS the primitive's period — for parity, a sharp spike at ω=π.
//! Then verify the classifier cos(ω*·count) separates parity. O(bins × freqs) on a 17-point
//! signal — trivially cheap, and principled: it reads the period rather than hunting a knob.
//!
//! Run: zig build spectral-discovery

const std = @import("std");

const NCELL = 16;
const VMAX = 6;
const H_FIXED: u8 = 5;
const CMAX = NCELL + 1; // count ∈ 0..16

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

const Sample = struct { count: f64, y: f64 };

fn makeData(alloc: std.mem.Allocator, n: usize, seed: u64) []Sample {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const d = alloc.alloc(Sample, n) catch unreachable;
    for (0..n) |i| {
        var c: u32 = 0;
        for (0..NCELL) |_| {
            if (rand.intRangeAtMost(u8, 0, VMAX) >= H_FIXED) c += 1;
        }
        d[i] = .{ .count = @floatFromInt(c), .y = @floatFromInt(c & 1) };
    }
    return d;
}

fn classifierAccAt(data: []const Sample, w: f64) f64 {
    // fit a,b for feature cos(w·count) by a few logistic epochs, then accuracy
    var a: f64 = 1.0;
    var b: f64 = 0.0;
    for (0..30) |_| for (data) |s| {
        const cw = @cos(w * s.count);
        const e = sigmoid(a * cw + b) - s.y;
        a -= 0.1 * e * cw;
        b -= 0.1 * e;
    };
    var correct: usize = 0;
    for (data) |s| {
        const z = a * @cos(w * s.count) + b;
        if ((z >= 0) == (s.y > 0.5)) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(data.len));
}

// the gradient baseline (from family_gradient.md) for contrast: mean over random inits
fn gradientMean(tr: []const Sample, te: []const Sample, trials: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var acc_sum: f64 = 0;
    for (0..trials) |_| {
        var a: f64 = 1.0;
        var b: f64 = 0.0;
        var w: f64 = rand.float(f64) * std.math.pi * 2.0;
        for (0..60) |_| for (tr) |s| {
            const cw = @cos(w * s.count);
            const e = sigmoid(a * cw + b) - s.y;
            a -= 0.02 * e * cw;
            b -= 0.02 * e;
            w -= 0.02 * e * a * (-s.count * @sin(w * s.count));
        };
        var correct: usize = 0;
        for (te) |s| {
            if ((a * @cos(w * s.count) + b >= 0) == (s.y > 0.5)) correct += 1;
        }
        acc_sum += @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(te.len));
    }
    return acc_sum / @as(f64, @floatFromInt(trials));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const tr = makeData(alloc, 4000, 1);
    defer alloc.free(tr);
    const te = makeData(alloc, 4000, 2);
    defer alloc.free(te);

    // 1. conditional-mean signal f(c) and bin counts n(c)
    var fsum = [_]f64{0} ** CMAX;
    var ncnt = [_]f64{0} ** CMAX;
    for (tr) |s| {
        const c: usize = @intFromFloat(s.count);
        if (c < CMAX) {
            fsum[c] += s.y;
            ncnt[c] += 1;
        }
    }
    var f = [_]f64{0} ** CMAX;
    var fbar: f64 = 0;
    var ntot: f64 = 0;
    for (0..CMAX) |c| {
        if (ncnt[c] > 0) f[c] = fsum[c] / ncnt[c];
        fbar += fsum[c];
        ntot += ncnt[c];
    }
    fbar /= ntot;

    // 2. count-weighted power spectrum over ω ∈ (0, π]
    const NF = 600;
    var peak_pw: f64 = -1;
    var peak_w: f64 = 0;
    var i: usize = 1;
    while (i <= NF) : (i += 1) {
        const w = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
        var re: f64 = 0;
        var im: f64 = 0;
        for (0..CMAX) |c| {
            if (ncnt[c] == 0) continue;
            const amp = ncnt[c] * (f[c] - fbar);
            const cc: f64 = @floatFromInt(c);
            re += amp * @cos(w * cc);
            im += amp * @sin(w * cc);
        }
        const pw = re * re + im * im;
        if (pw > peak_pw) {
            peak_pw = pw;
            peak_w = w;
        }
    }

    // 3. verify the discovered ω separates parity
    const spectral_acc = classifierAccAt(te, peak_w);
    const grad_mean = gradientMean(tr, te, 20, 7);

    try out.print("=== FRONTIER 2: periodicity-aware discovery of ω where gradient fails ===\n", .{});
    try out.print("target = parity of #{{cells>=5}}; the period-2 structure lives at ω=π={d:.4}.\n\n", .{std.math.pi});

    try out.print("conditional-mean signal f(c)=E[label|count=c] (should alternate 0,1,0,1...):\n  ", .{});
    for (0..CMAX) |c| {
        if (ncnt[c] > 0) try out.print("{d:.0} ", .{f[c]}) else try out.print("· ", .{});
    }
    try out.print("\n\n", .{});

    try out.print("  discovery operator                  | found ω  | test acc | notes\n", .{});
    try out.print("  ------------------------------------+----------+----------+--------------------\n", .{});
    try out.print("  gradient descent (random init, 20)  |  varies  |  {d:.3}   | from family_gradient: STUCK\n", .{grad_mean});
    try out.print("  spectral peak (periodicity-aware)   |  {d:.4}  |  {d:.3}   | reads the period directly\n", .{ peak_w, spectral_acc });

    try out.print("\n--- VERDICT ---\n", .{});
    const spectral_works = spectral_acc > 0.95;
    const near_pi = @abs(peak_w - std.math.pi) < 0.05;
    const grad_fails = grad_mean < 0.75;
    if (spectral_works and near_pi and grad_fails) {
        try out.print("CONFIRMED — the operator matters. The spectral peak lands at ω={d:.4} (π={d:.4}) and the\n", .{ peak_w, std.math.pi });
        try out.print("classifier there separates parity at {d:.3}, while gradient from random inits is stuck at\n", .{spectral_acc});
        try out.print("{d:.3}. The same parameter gradient cannot find — because its loss is oscillatory with a\n", .{grad_mean});
        try out.print("vanishing gradient at the optimum — a periodicity-aware operator reads off a single\n", .{});
        try out.print("spectral peak. C's open lever is real: discovery is possible with the RIGHT operator,\n", .{});
        try out.print("one matched to the primitive family's structure (here, periodicity), not a generic\n", .{});
        try out.print("descent. This is the constructive other half of the family_gradient negative.\n", .{});
    } else if (!spectral_works) {
        try out.print("Spectral operator did not cleanly separate (acc {d:.3}, ω={d:.4}); investigate the\n", .{ spectral_acc, peak_w });
        try out.print("conditional-mean estimate or bin coverage.\n", .{});
    } else {
        try out.print("Spectral acc {d:.3} at ω={d:.4}; gradient {d:.3}. Mixed — read the numbers above.\n", .{ spectral_acc, peak_w, grad_mean });
    }
    try out.print("\nSee: family_gradient.md (the gradient negative this completes), order_statistics.zig (the forge),\n", .{});
    try out.print("CLOSURE_PRINCIPLE.md (discover-the-generator frontier).\n", .{});
}
