//! Direction 3 — Oriented dynamics on the grid control agent
//!
//! Applies antisymmetric-relational (Frontier 3) encoding to the REAL battery
//! control task. Shared-basis Cl(2,0) encoding on grid cells; compare:
//!   - sum readout (mb_mass baseline: total grid mass)
//!   - grade-2 bivector readouts (local chain gradients, left-right asymmetry)
//!
//! Hypothesis BEFORE running:
//!   H1  sum readout solves single-band (symmetric constraint on total mass)
//!   H2  bivector readouts FAIL single-band (orientation irrelevant; pooled sum wins)
//!   H3  on dual-band, sum alone fails but biv_lr_mass (sin θ(left−right)) may help
//!       because left_mass constraint is a DISTRIBUTIONAL / oriented feature
//!
//! Run: zig build oriented-control

const std = @import("std");
const env_mod = @import("environment.zig");

const BLADES = 4;
const NADJ = 15; // adjacent pairs on 16-cell chain
const THETA: f32 = 0.40;
const S: f32 = 48.0; // mass scale for normalization

// Max feature dimension: bias + 15 adjacent bivectors
const NFEAT_MAX = 1 + NADJ;

const Readout = enum {
    sum, // mb_mass baseline: total grid mass
    biv_chain, // sin(θ(g[i+1]-g[i])) for each adjacent pair (local flow gradient)
    biv_lr_mass, // sin(θ(left_mass - right_mass)) — half-grid antisymmetric
    biv_geo_lr, // grade-2 of geo(encode(left_mass), encode(right_mass))
    biv_focal, // sin(θ(g[8]-g[0])) — anode vs mid-right focal pair
};

inline fn reorderSign2d(a: u8, b: u8) f32 {
    var aa = a >> 1;
    var sum: u32 = 0;
    while (aa != 0) {
        sum += @popCount(aa & b);
        aa >>= 1;
    }
    return if (sum & 1 == 0) @as(f32, 1.0) else @as(f32, -1.0);
}

fn geo2d(a: [BLADES]f32, b: [BLADES]f32) [BLADES]f32 {
    var out: [BLADES]f32 = .{0} ** BLADES;
    for (0..BLADES) |p| {
        if (a[p] == 0) continue;
        for (0..BLADES) |q| {
            if (b[q] == 0) continue;
            const blade: u8 = @as(u8, @intCast(p)) ^ @as(u8, @intCast(q));
            out[blade] += reorderSign2d(@intCast(p), @intCast(q)) * a[p] * b[q];
        }
    }
    return out;
}

fn encodeScalar(v: f32) [BLADES]f32 {
    return .{
        0,
        @cos(THETA * v),
        @sin(THETA * v),
        0,
    };
}

fn encodeCell(v: u8) [BLADES]f32 {
    return encodeScalar(@as(f32, @floatFromInt(v)));
}

fn leftMass(grid: [16]u8) u32 {
    var m: u32 = 0;
    for (grid[0..8]) |c| m += c;
    return m;
}

fn rightMass(grid: [16]u8) u32 {
    var m: u32 = 0;
    for (grid[8..16]) |c| m += c;
    return m;
}

fn totalMass(grid: [16]u8) u32 {
    var m: u32 = 0;
    for (grid) |c| m += c;
    return m;
}

fn features(grid: [16]u8, readout: Readout, phi: *[NFEAT_MAX]f32) usize {
    phi[0] = 1.0;
    switch (readout) {
        .sum => {
            phi[1] = @as(f32, @floatFromInt(totalMass(grid))) / S;
            return 2;
        },
        .biv_chain => {
            var idx: usize = 1;
            for (0..NADJ) |i| {
                const diff: f32 = @as(f32, @floatFromInt(grid[i + 1])) - @as(f32, @floatFromInt(grid[i]));
                phi[idx] = @sin(THETA * diff);
                idx += 1;
            }
            return idx;
        },
        .biv_lr_mass => {
            const lm: f32 = @as(f32, @floatFromInt(leftMass(grid)));
            const rm: f32 = @as(f32, @floatFromInt(rightMass(grid)));
            phi[1] = @sin(THETA * (rm - lm) / S);
            return 2;
        },
        .biv_geo_lr => {
            const lm: f32 = @as(f32, @floatFromInt(leftMass(grid))) / S;
            const rm: f32 = @as(f32, @floatFromInt(rightMass(grid))) / S;
            const geo = geo2d(encodeScalar(lm), encodeScalar(rm));
            phi[1] = geo[3]; // grade-2 blade = sin(θ(rm-lm))
            return 2;
        },
        .biv_focal => {
            const diff: f32 = @as(f32, @floatFromInt(grid[8])) - @as(f32, @floatFromInt(grid[0]));
            phi[1] = @sin(THETA * diff);
            return 2;
        },
    }
}

const QCtrl = struct {
    w: [3][NFEAT_MAX]f32,
    n: usize,
    lr: f32,
    gamma: f32,

    fn init(n_active: usize, lr: f32, gamma: f32) QCtrl {
        var q: QCtrl = undefined;
        for (0..3) |a| {
            for (0..NFEAT_MAX) |k| q.w[a][k] = 0;
        }
        q.n = n_active;
        q.lr = lr;
        q.gamma = gamma;
        return q;
    }

    fn value(self: *const QCtrl, phi: *const [NFEAT_MAX]f32, a: usize) f32 {
        var z: f32 = 0;
        for (0..self.n) |k| z += self.w[a][k] * phi[k];
        return z;
    }

    fn minValue(self: *const QCtrl, phi: *const [NFEAT_MAX]f32) f32 {
        var best: f32 = 1e9;
        for (0..3) |a| {
            const v = self.value(phi, a);
            if (v < best) best = v;
        }
        return best;
    }

    fn choose(self: *const QCtrl, phi: *const [NFEAT_MAX]f32, rng: std.Random, eps: f32) u8 {
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

    fn tdUpdate(self: *QCtrl, phi: *const [NFEAT_MAX]f32, a: usize, cost: f32, phi_next: *const [NFEAT_MAX]f32, failed: bool) void {
        var target: f32 = cost;
        if (!failed) target += self.gamma * self.minValue(phi_next);
        if (target < 0) target = 0;
        if (target > 1) target = 1;
        const v = self.value(phi, a);
        const err = v - target;
        for (0..self.n) |k| self.w[a][k] -= self.lr * err * phi[k];
    }
};

fn episode(params: env_mod.TaskParams, readout: Readout, train_steps: usize, eval_steps: usize, seed: u64, lr: f32, gamma: f32) f64 {
    var phi: [NFEAT_MAX]f32 = undefined;
    var phi_next: [NFEAT_MAX]f32 = undefined;
    const dummy = env_mod.Environment.initWith(params);
    const n_active = features(dummy.grid, readout, &phi);

    var q = QCtrl.init(n_active, lr, gamma);
    var env = env_mod.Environment.initWith(params);
    var rng = std.Random.DefaultPrng.init(seed);
    var prev_failed = false;

    const decay_end: f32 = @floatFromInt(train_steps / 2);
    for (0..train_steps) |step| {
        _ = features(env.grid, readout, &phi);
        const sf: f32 = @floatFromInt(step);
        const eps = @max(0.1, 1.0 - sf / decay_end);
        const a = q.choose(&phi, rng.random(), eps);
        env.step(@enumFromInt(a), rng.random());
        const failed = env.failed;
        _ = features(env.grid, readout, &phi_next);
        if (!prev_failed) {
            q.tdUpdate(&phi, a, if (failed) 1.0 else 0.0, &phi_next, failed);
        }
        prev_failed = failed;
    }

    var fails: u32 = 0;
    for (0..eval_steps) |_| {
        _ = features(env.grid, readout, &phi);
        const a = q.choose(&phi, rng.random(), 0.0);
        env.step(@enumFromInt(a), rng.random());
        if (env.failed) fails += 1;
    }
    return @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(eval_steps)) * 1000.0;
}

const CellResult = struct { mean: f64, worst: f64, best: f64 };

fn runCell(params: env_mod.TaskParams, readout: Readout, train_steps: usize, eval_steps: usize, n_seeds: usize, lr: f32, gamma: f32) CellResult {
    var total: f64 = 0;
    var worst: f64 = 0;
    var best: f64 = 1e9;
    for (0..n_seeds) |s| {
        const r = episode(params, readout, train_steps, eval_steps, 0x0A1E0 +% @as(u64, s) *% 0x9E37, lr, gamma);
        total += r;
        if (r > worst) worst = r;
        if (r < best) best = r;
    }
    return .{ .mean = total / @as(f64, @floatFromInt(n_seeds)), .worst = worst, .best = best };
}

fn thermostat(params: env_mod.TaskParams, n_steps: usize, seeds: usize) f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| {
        var prng = std.Random.DefaultPrng.init(@as(u64, s) + 1);
        const rand = prng.random();
        var env = env_mod.Environment.initWith(params);
        var failures: u64 = 0;
        for (0..n_steps) |_| {
            var mass: u32 = 0;
            for (env.grid) |c| mass += c;
            const action: env_mod.Action = blk: {
                if (mass <= params.min_mass + 4) break :blk .charge;
                if (params.max_mass > 0 and mass >= params.max_mass - 4) break :blk .rest;
                break :blk .discharge;
            };
            env.step(action, rand);
            if (env.failed) failures += 1;
        }
        acc += @as(f64, @floatFromInt(failures)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
    }
    return acc / @as(f64, @floatFromInt(seeds));
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    const TRAIN: usize = 80_000;
    const EVAL: usize = 10_000;
    const SEEDS: usize = 8;
    const LR: f32 = 0.02;
    const GAMMA: f32 = 0.9;

    const single = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .shock_period = 0, .volatility_after = 1_000_000,
    };
    const dual = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };

    const readouts = [_]Readout{ .sum, .biv_chain, .biv_lr_mass, .biv_geo_lr, .biv_focal };
    const readout_names = [_][]const u8{ "sum(mb_mass)", "biv_chain(15)", "biv_lr_mass", "biv_geo_lr", "biv_focal(0,8)" };

    try out.print("=== ORIENTED CONTROL: Clifford grade-2 vs mb_mass sum on grid task ===\n\n", .{});
    try out.print("Shared Cl(2,0) encoding: C_i = cos(θv_i)e1 + sin(θv_i)e2, θ={d:.2}\n", .{THETA});
    try out.print("Controller: per-action TD danger model Q(x,a)=w_a·phi(x), same as basis_control.\n", .{});
    try out.print("Train {d} steps, eval {d} steps frozen, mean of {d} seeds.\n\n", .{ TRAIN, EVAL, SEEDS });

    try out.print("Grid dynamics are ORIENTED: charge→anode(0), discharge→cathode(15), rest→uniform decay.\n", .{});
    try out.print("Pooled sum readout loses cell identity; bivector captures local gradients / asymmetry.\n\n", .{});

    try out.print("References (eval harness, 15k steps):\n", .{});
    try out.print("  single-band: thermostat ~0-20, mb_mass(sum) ~11 fail/1k\n", .{});
    try out.print("  dual-band:   mb_mass(sum) ~83, mb_mass(left) ~39 fail/1k\n\n", .{});

    inline for (.{ single, dual }) |task| {
        const task_name = if (task.min_left_mass > 0) "DUAL_BAND" else "SINGLE_BAND";
        try out.print("--- {s} ---\n", .{task_name});
        try out.print("  thermostat (sum-only hand-coded): {d:.2} fail/1k\n", .{thermostat(task, EVAL, SEEDS)});
        try out.print("  readout              |    mean |   worst |    best |  dim\n", .{});
        try out.print("  ---------------------+---------+---------+---------+-----\n", .{});

        for (readouts, readout_names) |r, name| {
            const cr = runCell(task, r, TRAIN, EVAL, SEEDS, LR, GAMMA);
            var dummy_phi: [NFEAT_MAX]f32 = undefined;
            const dim = features(env_mod.Environment.initWith(task).grid, r, &dummy_phi);
            try out.print("  {s:<20} | {d:7.2} | {d:7.2} | {d:7.2} | {d:4}\n", .{ name, cr.mean, cr.worst, cr.best, dim });
        }
        try out.print("\n", .{});
    }

    const sum_single = runCell(single, .sum, TRAIN, EVAL, SEEDS, LR, GAMMA);
    const biv_single = runCell(single, .biv_chain, TRAIN, EVAL, SEEDS, LR, GAMMA);
    const sum_dual = runCell(dual, .sum, TRAIN, EVAL, SEEDS, LR, GAMMA);
    const biv_lr_dual = runCell(dual, .biv_lr_mass, TRAIN, EVAL, SEEDS, LR, GAMMA);
    const biv_chain_dual = runCell(dual, .biv_chain, TRAIN, EVAL, SEEDS, LR, GAMMA);

    try out.print("=== VERDICT ===\n", .{});
    try out.print("H1 single-band sum works:          sum mean={d:.2} (expect <20)\n", .{sum_single.mean});
    try out.print("H2 bivector irrelevant on single:  biv_chain mean={d:.2} vs sum {d:.2}\n", .{ biv_single.mean, sum_single.mean });
    try out.print("H3 dual-band oriented helps:         sum={d:.2}  biv_lr_mass={d:.2}  biv_chain={d:.2}\n", .{ sum_dual.mean, biv_lr_dual.mean, biv_chain_dual.mean });

    const oriented_helps_single = biv_single.mean + 5.0 < sum_single.mean;
    const oriented_helps_dual = biv_lr_dual.mean + 10.0 < sum_dual.mean or biv_chain_dual.mean + 10.0 < sum_dual.mean;
    const sum_wins_single = sum_single.mean + 5.0 < biv_single.mean;

    if (sum_wins_single and !oriented_helps_single) {
        try out.print("\nORIENTED ENCODING DOES NOT HELP on single-band: sum readout wins.\n", .{});
        try out.print("The control constraint (total mass band) is SYMMETRIC — orientation is irrelevant.\n", .{});
    } else if (oriented_helps_single) {
        try out.print("\nUNEXPECTED: bivector beats sum on single-band — investigate.\n", .{});
    }

    if (oriented_helps_dual) {
        try out.print("ORIENTED ENCODING HELPS on dual-band: bivector readout beats sum-only.\n", .{});
        try out.print("Left_mass constraint needs DISTRIBUTIONAL readout; sin(θ(left-right)) captures it.\n", .{});
    } else {
        try out.print("ORIENTED ENCODING DOES NOT BEAT sum on dual-band at this budget.\n", .{});
        try out.print("Dual-band may need explicit left_mass scalar (mb_mass left_mass ~39) not Clifford bivector.\n", .{});
    }

    try out.print("\nStructural lesson: Clifford grade-2 wins on TOY oriented predicates (antisymmetric_relational:\n", .{});
    try out.print("1.000 on sign(v1-v0)) but REAL grid control needs task-matched readouts. Oriented dynamics exist\n", .{});
    try out.print("in the environment (charge/discharge flow) yet the measured failure modes are mass-band constraints\n", .{});
    try out.print("that are predominantly SYMMETRIC aggregates unless dual-band forces distribution awareness.\n", .{});
}