//! RQ C23 / the forge frontier — can GRADIENT discover the primitive parameter,
//! or only GRID SEARCH?
//!
//! `order_statistics.zig`'s forge closes the invention loop on parity-of-count by
//! GRID-searching (H, ω) for the count-Fourier feature cos(ω·#{cells≥H}); it finds
//! H=5, ω=π (i.e. (-1)^count) and promotes it. primitive_class_inference.md flags the
//! honest limit: "it is a small grid search over (H, ω), not GRADIENT discovery of ω;
//! learning the parity frequency by gradient is the canonical hard case and would likely
//! fail (a useful future negative)."
//!
//! This makes that negative concrete. Fix the threshold at the forge's H=5 to ISOLATE
//! the ω-learning problem, then ask: starting from a random ω, does gradient descent on
//! a logistic classifier with feature cos(ω·count) reach ω≈π and separate parity? Or is
//! the loss landscape in ω so oscillatory that gradient only works when warm-started
//! near the answer — i.e. the discovery is grid/luck, not gradient?
//!
//! classifier: p = σ(a·cos(ω·count) + b); learn a, b, ω by SGD.
//!   dL/dω = (p−y)·a·(−count·sin(ω·count))   <- oscillatory in ω: many local minima.
//!
//! Run: zig build family-gradient

const std = @import("std");

const NCELL = 16;
const VMAX = 6;
const H_FIXED: u8 = 5; // the forge's discovered threshold; isolate the ω problem
const TWO_PI: f64 = std.math.pi * 2.0;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn countGE(g: [NCELL]u8, h: u8) f64 {
    var c: u32 = 0;
    for (g) |v| {
        if (v >= h) c += 1;
    }
    return @floatFromInt(c);
}

const Sample = struct { count: f64, y: f64 };

fn makeData(alloc: std.mem.Allocator, n: usize, seed: u64) []Sample {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const d = alloc.alloc(Sample, n) catch unreachable;
    for (0..n) |i| {
        var g: [NCELL]u8 = undefined;
        for (0..NCELL) |k| g[k] = rand.intRangeAtMost(u8, 0, VMAX);
        const c = countGE(g, H_FIXED);
        const parity: f64 = @floatFromInt(@as(u32, @intFromFloat(c)) & 1);
        d[i] = .{ .count = c, .y = parity };
    }
    return d;
}

fn accAt(data: []const Sample, a: f64, b: f64, w: f64) f64 {
    var correct: usize = 0;
    for (data) |s| {
        const z = a * @cos(w * s.count) + b;
        const pred: f64 = if (z >= 0) 1.0 else 0.0;
        if (pred == s.y) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(data.len));
}

// One gradient run from a given ω init. Returns {test acc, final ω}.
fn gradientRun(tr: []const Sample, te: []const Sample, w0: f64, epochs: usize, lr: f64) struct { acc: f64, w: f64 } {
    var a: f64 = 1.0;
    var b: f64 = 0.0;
    var w: f64 = w0;
    for (0..epochs) |_| {
        for (tr) |s| {
            const cw = @cos(w * s.count);
            const z = a * cw + b;
            const e = sigmoid(z) - s.y;
            const ga = e * cw;
            const gb = e;
            const gw = e * a * (-s.count * @sin(w * s.count));
            a -= lr * ga;
            b -= lr * gb;
            w -= lr * gw;
        }
    }
    return .{ .acc = accAt(te, a, b, w), .w = w };
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

    try out.print("=== RQ C23: gradient vs grid search for the primitive parameter ω ===\n", .{});
    try out.print("target = parity of #{{cells>=5}}; feature cos(ω·count); the answer is ω=π.\n", .{});
    try out.print("(H fixed at the forge's 5 to isolate ω; 4000 train / 4000 test grids)\n\n", .{});

    // ---- grid search (the forge's method): scan ω, keep best train acc ----
    var best_grid_acc: f64 = 0;
    var best_grid_w: f64 = 0;
    {
        const steps = 2000;
        var i: usize = 1;
        while (i <= steps) : (i += 1) {
            const w = TWO_PI * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
            // fit a,b cheaply at this ω by a few logistic epochs
            var a: f64 = 1.0;
            var b: f64 = 0.0;
            for (0..5) |_| for (tr) |s| {
                const cw = @cos(w * s.count);
                const e = sigmoid(a * cw + b) - s.y;
                a -= 0.1 * e * cw;
                b -= 0.1 * e;
            };
            const acc = accAt(tr, a, b, w);
            if (acc > best_grid_acc) {
                best_grid_acc = acc;
                best_grid_w = w;
            }
        }
    }
    const grid_test = blk: {
        var a: f64 = 1.0;
        var b: f64 = 0.0;
        for (0..20) |_| for (tr) |s| {
            const cw = @cos(best_grid_w * s.count);
            const e = sigmoid(a * cw + b) - s.y;
            a -= 0.1 * e * cw;
            b -= 0.1 * e;
        };
        break :blk accAt(te, a, b, best_grid_w);
    };

    // ---- gradient from many random ω inits ----
    var prng = std.Random.DefaultPrng.init(7);
    const rand = prng.random();
    const trials = 40;
    var n_success: usize = 0;
    var best_grad_acc: f64 = 0;
    var sum_acc: f64 = 0;
    for (0..trials) |_| {
        const w0 = rand.float(f64) * TWO_PI;
        const r = gradientRun(tr, te, w0, 60, 0.02);
        sum_acc += r.acc;
        if (r.acc > best_grad_acc) best_grad_acc = r.acc;
        if (r.acc > 0.95) n_success += 1;
    }
    const mean_grad = sum_acc / @as(f64, @floatFromInt(trials));

    // ---- gradient WARM-STARTED near the answer (ω0 ∈ [π−0.3, π+0.3]) ----
    var warm_success: usize = 0;
    var warm_best: f64 = 0;
    for (0..trials) |_| {
        const w0 = std.math.pi + (rand.float(f64) - 0.5) * 0.6;
        const r = gradientRun(tr, te, w0, 60, 0.02);
        if (r.acc > warm_best) warm_best = r.acc;
        if (r.acc > 0.95) warm_success += 1;
    }

    try out.print("  method                              | test acc | notes\n", .{});
    try out.print("  ------------------------------------+----------+----------------------------\n", .{});
    try out.print("  grid search over ω (the forge)      |  {d:.3}   | best ω={d:.3} (π={d:.3})\n", .{ grid_test, best_grid_w, std.math.pi });
    try out.print("  gradient, random ω init (best/40)   |  {d:.3}   | {d}/{d} inits reached >0.95\n", .{ best_grad_acc, n_success, trials });
    try out.print("  gradient, random ω init (mean/40)   |  {d:.3}   | typical random-init outcome\n", .{ mean_grad, });
    try out.print("  gradient, warm start near π (best)   |  {d:.3}   | {d}/{d} inits reached >0.95\n", .{ warm_best, warm_success, trials });

    try out.print("\n--- VERDICT ---\n", .{});
    const grid_wins = grid_test > 0.95;
    const grad_random_fails = mean_grad < 0.75;
    const warm_works = warm_best > 0.95;
    if (grid_wins and grad_random_fails) {
        try out.print("CONFIRMED (the documented negative): grid search finds ω=π and separates parity\n", .{});
        try out.print("({d:.3}), but gradient from a RANDOM ω is stuck near chance on average ({d:.3}).\n", .{ grid_test, mean_grad });
        try out.print("The loss in ω is oscillatory (gradient ∝ -count·sin(ω·count)); SGD falls into the\n", .{});
        try out.print("nearest local minimum. ", .{});
        if (warm_works) {
            try out.print("It succeeds ONLY when warm-started near π ({d:.3}) -> the\n", .{warm_best});
            try out.print("discovery is the GRID/luck, not the gradient. The forge's grid search is doing the\n", .{});
            try out.print("real work; 'learn the primitive parameter by gradient' does NOT close the loop here.\n", .{});
        } else {
            try out.print("\n", .{});
        }
        try out.print("This is the honest frontier: forging a primitive whose parameter must be GROWN\n", .{});
        try out.print("(not enumerated) remains open. Gradient discovery presupposes a smooth landscape\n", .{});
        try out.print("the parity frequency does not provide — the closure question, re-asked in ω-space.\n", .{});
    } else if (!grad_random_fails) {
        try out.print("SURPRISE: gradient from random init reached {d:.3} mean — investigate; the parity\n", .{mean_grad});
        try out.print("frequency was expected to be a hard non-convex target. Possible easy-data leak.\n", .{});
    }
    try out.print("\nSee: order_statistics.zig (the forge), primitive_class_inference.md (the flagged limit),\n", .{});
    try out.print("CLOSURE_PRINCIPLE.md (the open frontier: discover the generator, not just select it).\n", .{});
}
