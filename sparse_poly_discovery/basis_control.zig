//! Basis-degree control: change ONLY the basis degree, measure the capability jump.
//!
//! The closure principle (this project's backbone) predicts a phase transition:
//!
//!   A two-sided band (keep feature(x) in [lo,hi]) is OUT OF THE LINEAR CLOSURE.
//!   A linear readout w·x cannot represent "safe in the middle, fail on both
//!   extremes": low-side and high-side failures cancel in the class mean, so any
//!   linear discriminant sees mu_fail ~= mu_safe along the constrained axis and
//!   gives it ~zero weight. The band needs the SQUARED distance from center — a
//!   quadratic term. It lives in the quadratic closure.
//!
//! So we build ONE controller, ONE training loop, ONE eval. The ONLY thing that
//! changes between runs is the feature basis:
//!   - linear:    phi(x) = [1, x_i/S]                       (17 features)
//!   - quadratic: phi(x) = [1, x_i/S, x_i^2/S^2, x_i x_j/S^2] (153 features)
//!
//! No hand-designed features (no "sum", no "left_mass", no "max_cell"). No pair
//! search. No triplet search. The controller is a per-action logistic danger model
//!   Q(x,a) = P(fail | state x, take action a) = sigmoid(w_a . phi(x))
//! trained online; control = argmin_a Q(x,a).
//!
//! HYPOTHESES (predictions BEFORE running):
//!   H1  linear basis FAILS the symmetric sum-band (cannot represent the band)
//!   H2  quadratic basis SOLVES dual-band without any feature menu (beats the
//!       hand-searched pair (left_mass,max_cell)=0.25)
//!   H3  quadratic basis SOLVES triple-band — the task that needed exhaustive
//!       O(N^3) triplet search — again with zero hand features. THE big test.
//!   H4  the per-cell overflow constraint (any cell >= 5) is a MAX / order
//!       statistic, NOT a polynomial of fixed degree. So a quadratic learner may
//!       leave overflow as a residual failure mode even when it nails the bands.
//!
//! Run: zig build basis-control

const std = @import("std");
const env_mod = @import("environment.zig");

// Feature layout. Max size is the quadratic basis.
const NLIN = 16;
const NSQ = 16;
const NCROSS = 120; // C(16,2)
const NFEAT = 1 + NLIN + NSQ + NCROSS; // 153

const Basis = enum { linear, quadratic };

// Build the feature vector for a grid. Returns the number of ACTIVE features.
fn features(grid: [16]u8, basis: Basis, phi: *[NFEAT]f32) usize {
    const S: f32 = 5.0; // value scale: cells live ~[0,5], so x/S ~ [0,1]
    phi[0] = 1.0; // bias
    var idx: usize = 1;
    for (0..16) |i| {
        phi[idx] = @as(f32, @floatFromInt(grid[i])) / S;
        idx += 1;
    }
    if (basis == .quadratic) {
        for (0..16) |i| {
            const g = @as(f32, @floatFromInt(grid[i])) / S;
            phi[idx] = g * g;
            idx += 1;
        }
        for (0..16) |i| {
            for (i + 1..16) |j| {
                const gi = @as(f32, @floatFromInt(grid[i])) / S;
                const gj = @as(f32, @floatFromInt(grid[j])) / S;
                phi[idx] = gi * gj;
                idx += 1;
            }
        }
    }
    return idx;
}

// Per-action danger VALUE model: Q(x,a) = expected discounted future failure cost
// if we take action a in state x then act greedily. Linear in the chosen basis:
//   Q(x,a) = w_a . phi(x)
// Trained by temporal-difference (Bellman) bootstrapping so danger PROPAGATES
// backward from the failure boundary into the interior — the fix for the myopic
// one-step model (which has no gradient: no single action fails from mid-band).
const QCtrl = struct {
    w: [3][NFEAT]f32,
    n: usize, // active feature count (17 linear, 153 quadratic)
    lr: f32,
    gamma: f32, // discount: lookahead horizon ~ 1/(1-gamma)

    fn init(n_active: usize, lr: f32, gamma: f32) QCtrl {
        var q: QCtrl = undefined;
        for (0..3) |a| {
            for (0..NFEAT) |k| q.w[a][k] = 0;
        }
        q.n = n_active;
        q.lr = lr;
        q.gamma = gamma;
        return q;
    }

    fn value(self: *const QCtrl, phi: *const [NFEAT]f32, a: usize) f32 {
        var z: f32 = 0;
        for (0..self.n) |k| z += self.w[a][k] * phi[k];
        return z;
    }

    fn minValue(self: *const QCtrl, phi: *const [NFEAT]f32) f32 {
        var best: f32 = 1e9;
        for (0..3) |a| {
            const v = self.value(phi, a);
            if (v < best) best = v;
        }
        return best;
    }

    fn choose(self: *const QCtrl, phi: *const [NFEAT]f32, rng: std.Random, eps: f32) u8 {
        if (rng.float(f32) < eps) return @intCast(rng.intRangeLessThan(usize, 0, 3));
        var best: u8 = 0;
        var best_v: f32 = 1e9;
        for (0..3) |a| {
            const v = self.value(phi, a);
            if (v < best_v) {
                best_v = v;
                best = @intCast(a);
            }
        }
        return best;
    }

    // TD(0) update toward Bellman target. cost=1 on failure (terminal: env resets),
    // else gamma * min_a' Q(next). Target clamped to [0,1] (bounded discounted cost).
    fn tdUpdate(self: *QCtrl, phi: *const [NFEAT]f32, a: usize, cost: f32, phi_next: *const [NFEAT]f32, failed: bool) void {
        var target: f32 = cost;
        if (!failed) target += self.gamma * self.minValue(phi_next);
        if (target < 0) target = 0;
        if (target > 1) target = 1;
        const v = self.value(phi, a);
        const err = v - target; // d/dw 0.5(v-target)^2 = (v-target)*phi
        for (0..self.n) |k| self.w[a][k] -= self.lr * err * phi[k];
    }
};

// One full episode: train_steps of online learning (with exploration), then
// eval_steps frozen (eps=0, no updates). Returns eval fail/1k.
fn episode(params: env_mod.TaskParams, basis: Basis, train_steps: usize, eval_steps: usize, seed: u64, lr: f32, gamma: f32) f64 {
    var phi: [NFEAT]f32 = undefined;
    var phi_next: [NFEAT]f32 = undefined;
    const dummy = env_mod.Environment.initWith(params);
    const n_active = features(dummy.grid, basis, &phi);

    var q = QCtrl.init(n_active, lr, gamma);
    var env = env_mod.Environment.initWith(params);
    var rng = std.Random.DefaultPrng.init(seed);
    var prev_failed = false;

    // Training phase
    const decay_end: f32 = @floatFromInt(train_steps / 2);
    for (0..train_steps) |step| {
        _ = features(env.grid, basis, &phi);
        const sf: f32 = @floatFromInt(step);
        const eps = @max(0.1, 1.0 - sf / decay_end);
        const a = q.choose(&phi, rng.random(), eps);
        env.step(@enumFromInt(a), rng.random());
        const failed = env.failed;
        _ = features(env.grid, basis, &phi_next);
        // Skip reset steps (prev_failed): the env discarded the action.
        if (!prev_failed) {
            q.tdUpdate(&phi, a, if (failed) 1.0 else 0.0, &phi_next, failed);
        }
        prev_failed = failed;
    }

    // Eval phase (frozen weights, greedy)
    var fails: u32 = 0;
    for (0..eval_steps) |_| {
        _ = features(env.grid, basis, &phi);
        const a = q.choose(&phi, rng.random(), 0.0);
        env.step(@enumFromInt(a), rng.random());
        if (env.failed) fails += 1;
    }
    return @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(eval_steps)) * 1000.0;
}

const CellResult = struct { mean: f64, worst: f64, best: f64 };

fn runCell(params: env_mod.TaskParams, basis: Basis, train_steps: usize, eval_steps: usize, n_seeds: usize, lr: f32, gamma: f32) CellResult {
    var total: f64 = 0;
    var worst: f64 = 0;
    var best: f64 = 1e9;
    for (0..n_seeds) |s| {
        const r = episode(params, basis, train_steps, eval_steps, 0xABC0 +% @as(u64, s) *% 0x9E37, lr, gamma);
        total += r;
        if (r > worst) worst = r;
        if (r < best) best = r;
    }
    return .{ .mean = total / @as(f64, @floatFromInt(n_seeds)), .worst = worst, .best = best };
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    const TRAIN: usize = 80_000;
    const EVAL: usize = 10_000;
    const SEEDS: usize = 8;
    const LR: f32 = 0.02;
    const GAMMA: f32 = 0.9;

    // Task definitions
    const single = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .shock_period = 0, .volatility_after = 1_000_000,
    };
    const dual = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };
    const triple = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .min_right_mass = 6, .max_right_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };
    // Overflow-dominant task to test H4: tight per-cell threshold makes the binding
    // constraint "no cell exceeds 2" = max_i(grid) <= 2, an ORDER STATISTIC. min_mass
    // forces mass IN (avg ~1/cell), so the agent must spread load and never let any
    // single cell pile up. This is where polynomial closure (quadratic) may break:
    // max is not a fixed-degree polynomial. Sum g_i^2 is only a soft proxy for max.
    const overflow = env_mod.TaskParams{
        .fail_threshold = 3, // a cell >= 3 fails: every cell must stay <= 2
        .min_mass = 16, .max_mass = 30, // avg 1-2 per cell; mass must stay in
        .shock_period = 0, .volatility_after = 1_000_000,
    };

    try out.print("=== BASIS-DEGREE CONTROL: change ONLY the basis, measure the jump ===\n\n", .{});
    try out.print("Controller: per-action logistic danger Q(x,a)=sigmoid(w_a . phi(x)),\n", .{});
    try out.print("learned online from the RAW 16-cell state. No hand features. No search.\n", .{});
    try out.print("Train {d} steps, eval {d} steps frozen, mean of {d} seeds.\n\n", .{ TRAIN, EVAL, SEEDS });
    try out.print("References (hand-searched, from prior experiments):\n", .{});
    try out.print("  single-band: thermostat 0.00, mb_mass(sum) ~good\n", .{});
    try out.print("  dual-band:   best pair (left_mass,max_cell)=0.25, thermostat 83.33\n", .{});
    try out.print("  triple-band: best triplet (sum,left,right)=3.79, best pair 98.40\n\n", .{});

    try out.print("  task        | basis     |    mean |   worst |    best\n", .{});
    try out.print("  ------------+-----------+---------+---------+--------\n", .{});

    const sl = runCell(single, .linear, TRAIN, EVAL, SEEDS, LR, GAMMA);
    try out.print("  single      | linear    | {d:7.2} | {d:7.2} | {d:7.2}\n", .{ sl.mean, sl.worst, sl.best });
    const sq = runCell(single, .quadratic, TRAIN, EVAL, SEEDS, LR, GAMMA);
    try out.print("  single      | quadratic | {d:7.2} | {d:7.2} | {d:7.2}\n", .{ sq.mean, sq.worst, sq.best });
    try out.print("  ------------+-----------+---------+---------+--------\n", .{});

    const dl = runCell(dual, .linear, TRAIN, EVAL, SEEDS, LR, GAMMA);
    try out.print("  dual        | linear    | {d:7.2} | {d:7.2} | {d:7.2}\n", .{ dl.mean, dl.worst, dl.best });
    const dq = runCell(dual, .quadratic, TRAIN, EVAL, SEEDS, LR, GAMMA);
    try out.print("  dual        | quadratic | {d:7.2} | {d:7.2} | {d:7.2}\n", .{ dq.mean, dq.worst, dq.best });
    try out.print("  ------------+-----------+---------+---------+--------\n", .{});

    const tl = runCell(triple, .linear, TRAIN, EVAL, SEEDS, LR, GAMMA);
    try out.print("  triple      | linear    | {d:7.2} | {d:7.2} | {d:7.2}\n", .{ tl.mean, tl.worst, tl.best });
    const tq = runCell(triple, .quadratic, TRAIN, EVAL, SEEDS, LR, GAMMA);
    try out.print("  triple      | quadratic | {d:7.2} | {d:7.2} | {d:7.2}\n", .{ tq.mean, tq.worst, tq.best });
    try out.print("  ------------+-----------+---------+---------+--------\n", .{});

    // H4: overflow-dominant (binding constraint is max_i grid <= 2, an order statistic)
    const ol = runCell(overflow, .linear, TRAIN, EVAL, SEEDS, LR, GAMMA);
    try out.print("  overflow    | linear    | {d:7.2} | {d:7.2} | {d:7.2}\n", .{ ol.mean, ol.worst, ol.best });
    const oq = runCell(overflow, .quadratic, TRAIN, EVAL, SEEDS, LR, GAMMA);
    try out.print("  overflow    | quadratic | {d:7.2} | {d:7.2} | {d:7.2}\n", .{ oq.mean, oq.worst, oq.best });

    try out.print("\n=== VERDICT ===\n", .{});
    try out.print("H1 linear unreliable on bands:     single linear mean={d:.2} worst={d:.2}\n", .{ sl.mean, sl.worst });
    try out.print("H2 quadratic solves dual:          dual quadratic mean={d:.2} worst={d:.2} vs hand 0.25\n", .{ dq.mean, dq.worst });
    try out.print("H3 quadratic solves triple:        triple quadratic mean={d:.2} worst={d:.2} vs hand 3.79\n", .{ tq.mean, tq.worst });
    try out.print("   linear on triple:               mean={d:.2} worst={d:.2}  (the contrast)\n", .{ tl.mean, tl.worst });
    try out.print("   (triple is the O(N^3)-search task — solved here with ZERO hand features)\n", .{});

    if (tq.mean < 10.0 and tq.worst < 30.0) {
        try out.print("\n  >>> H3 CONFIRMED: quadratic basis solves triple-band with no feature menu.\n", .{});
        try out.print("  The feature-discovery problem was an artifact of a too-small discrete basis.\n", .{});
    } else if (tq.mean < tl.mean / 2.0) {
        try out.print("\n  >>> PARTIAL: quadratic strongly beats linear on triple but not yet reliable.\n", .{});
    } else {
        try out.print("\n  >>> H3 not yet confirmed at this budget (triple quadratic mean={d:.2}).\n", .{tq.mean});
    }
    try out.print("\nH4 overflow (intended: max constraint = order statistic, not a polynomial):\n", .{});
    try out.print("   overflow linear   mean={d:.2} worst={d:.2}\n", .{ ol.mean, ol.worst });
    try out.print("   overflow quadratic mean={d:.2} worst={d:.2}\n", .{ oq.mean, oq.worst });
    const degenerate = @abs(oq.mean - ol.mean) < 1.0 and oq.mean > 30.0;
    if (degenerate) {
        try out.print("   >>> H4 UNTESTED (task degenerate): linear==quadratic=={d:.2} means both\n", .{oq.mean});
        try out.print("   collapse to the SAME constant policy. In this env, charge/rest act ~uniformly\n", .{});
        try out.print("   on all cells, so 'max cell <= k' and 'total mass <= K' are the SAME constraint\n", .{});
        try out.print("   (not separable like left/right mass). The order-statistic boundary is not\n", .{});
        try out.print("   isolated here. H4 needs a different environment with non-uniform dynamics.\n", .{});
    } else if (oq.mean > tq.mean + 5.0) {
        try out.print("   >>> H4 SUPPORTED: quadratic does WORSE on overflow than on the bands.\n", .{});
    } else {
        try out.print("   >>> H4 REFUTED here: quadratic handles overflow too (sum g_i^2 ~ max proxy).\n", .{});
    }
}
