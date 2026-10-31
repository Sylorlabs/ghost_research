//! Swarm EXP-10 (I56): hard grid-tune hand-coded thermostat on BAND task.
//! Hysteresis + threshold sweep + optional one-step lookahead.
//! Run: zig build swarm-exp10 --release=fast
const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

const N_STEPS: usize = 15000;
const N_SEEDS: usize = 6;

const ThermoMode = enum { normal, charging, dumping };

fn gridMass(grid: [16]u8) u32 {
    var m: u32 = 0;
    for (grid) |c| m += c;
    return m;
}

fn bandViolation(mass: u32, p: env_mod.TaskParams) u32 {
    if (p.min_mass > 0 and mass < p.min_mass) return p.min_mass - mass;
    if (p.max_mass > 0 and mass > p.max_mass) return mass - p.max_mass;
    return 0;
}

fn bandMid(p: env_mod.TaskParams) u32 {
    if (p.max_mass > 0) return (p.min_mass + p.max_mass) / 2;
    return p.min_mass + 16;
}

fn distToMid(mass: u32, p: env_mod.TaskParams) u32 {
    const mid = bandMid(p);
    return if (mass >= mid) mass - mid else mid - mass;
}

// E1 baseline: 3-branch, no hysteresis (from eval.zig).
fn thermostatTuned(
    params: env_mod.TaskParams,
    charge_below: u32,
    high_above: u32,
    rest_high: bool,
    n_steps: usize,
    seeds: usize,
) f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| {
        var prng = std.Random.DefaultPrng.init(@as(u64, s) + 1);
        const rand = prng.random();
        var env = env_mod.Environment.initWith(params);
        var failures: u64 = 0;
        for (0..n_steps) |_| {
            const mass = gridMass(env.grid);
            const action: env_mod.Action = blk: {
                if (mass <= charge_below) break :blk .charge;
                if (mass >= high_above) break :blk (if (rest_high) .rest else .discharge);
                break :blk .discharge;
            };
            env.step(action, rand);
            if (env.failed) failures += 1;
        }
        acc += @as(f64, @floatFromInt(failures)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
    }
    return acc / @as(f64, @floatFromInt(seeds));
}

// Hysteresis thermostat: separate enter/exit thresholds per branch.
fn thermostatHysteresis(
    params: env_mod.TaskParams,
    charge_below: u32,
    charge_above: u32,
    high_below: u32,
    high_above: u32,
    rest_high: bool,
    mid_rest: bool,
    n_steps: usize,
    seeds: usize,
) f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| {
        var prng = std.Random.DefaultPrng.init(@as(u64, s) + 1);
        const rand = prng.random();
        var env = env_mod.Environment.initWith(params);
        var failures: u64 = 0;
        var mode: ThermoMode = .normal;
        for (0..n_steps) |_| {
            const mass = gridMass(env.grid);
            const action: env_mod.Action = blk: {
                switch (mode) {
                    .charging => {
                        if (mass >= charge_above) mode = .normal;
                        if (mode == .charging) break :blk .charge;
                        // fell through: re-evaluate from normal rules
                    },
                    .dumping => {
                        if (mass <= high_below) mode = .normal;
                        if (mode == .dumping) break :blk (if (rest_high) .rest else .discharge);
                    },
                    .normal => {},
                }
                if (mass <= charge_below) {
                    mode = .charging;
                    break :blk .charge;
                }
                if (mass >= high_above) {
                    mode = .dumping;
                    break :blk (if (rest_high) .rest else .discharge);
                }
                break :blk (if (mid_rest) .rest else .discharge);
            };
            env.step(action, rand);
            if (env.failed) failures += 1;
        }
        acc += @as(f64, @floatFromInt(failures)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
    }
    return acc / @as(f64, @floatFromInt(seeds));
}

fn scoreAfterAction(env: env_mod.Environment, action: env_mod.Action, params: env_mod.TaskParams) struct { failed: bool, mass: u32, violation: u32, mid_dist: u32 } {
    var sim = env;
    var prng = std.Random.DefaultPrng.init(0);
    sim.step(action, prng.random());
    const mass = gridMass(sim.grid);
    const viol = bandViolation(mass, params);
    const mid = bandMid(params);
    const dist: u32 = if (mass >= mid) mass - mid else mid - mass;
    return .{ .failed = sim.failed, .mass = mass, .violation = viol, .mid_dist = dist };
}

// One-step lookahead: pick action minimizing band violation, then mid distance.
fn thermostatLookahead1(
    params: env_mod.TaskParams,
    n_steps: usize,
    seeds: usize,
) f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| {
        var prng = std.Random.DefaultPrng.init(@as(u64, s) + 1);
        const rand = prng.random();
        var env = env_mod.Environment.initWith(params);
        var failures: u64 = 0;
        for (0..n_steps) |_| {
            var best_act = env_mod.Action.rest;
            var best_viol: u32 = std.math.maxInt(u32);
            var best_dist: u32 = std.math.maxInt(u32);
            var best_failed = true;
            const acts = [_]env_mod.Action{ .charge, .discharge, .rest };
            for (acts) |act| {
                const sc = scoreAfterAction(env, act, params);
                const failed_worse = sc.failed and !best_failed;
                const viol_worse = sc.violation > best_viol;
                const dist_worse = sc.violation == best_viol and sc.mid_dist > best_dist;
                if (failed_worse or viol_worse or dist_worse) continue;
                if (sc.failed and best_failed) {
                    // both fail: prefer lower violation anyway
                    if (sc.violation > best_viol or (sc.violation == best_viol and sc.mid_dist > best_dist)) continue;
                }
                best_act = act;
                best_viol = sc.violation;
                best_dist = sc.mid_dist;
                best_failed = sc.failed;
            }
            env.step(best_act, rand);
            if (env.failed) failures += 1;
        }
        acc += @as(f64, @floatFromInt(failures)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
    }
    return acc / @as(f64, @floatFromInt(seeds));
}

// H-step exhaustive lookahead (deterministic band, noise off).
fn thermostatLookaheadH(
    params: env_mod.TaskParams,
    horizon: u32,
    n_steps: usize,
    seeds: usize,
) f64 {
    const actions = [_]env_mod.Action{ .charge, .discharge, .rest };

    const RolloutScore = struct {
        failed: bool,
        violation: u32,
        mid_dist: u32,
    };

    const EvalCtx = struct {
        params: env_mod.TaskParams,
        horizon: u32,
        actions: [3]env_mod.Action,

        fn evalPath(self: @This(), env: env_mod.Environment, depth: u32) RolloutScore {
            if (depth == 0) {
                const mass = gridMass(env.grid);
                return .{
                    .failed = env.failed,
                    .violation = bandViolation(mass, self.params),
                    .mid_dist = distToMid(mass, self.params),
                };
            }
            var best: RolloutScore = .{ .failed = true, .violation = std.math.maxInt(u32), .mid_dist = std.math.maxInt(u32) };
            for (self.actions) |act| {
                var sim = env;
                var prng = std.Random.DefaultPrng.init(0);
                sim.step(act, prng.random());
                const sc = self.evalPath(sim, depth - 1);
                if (better(sc, best)) best = sc;
            }
            return best;
        }

        fn better(a: RolloutScore, b: RolloutScore) bool {
            if (a.failed != b.failed) return !a.failed;
            if (a.violation != b.violation) return a.violation < b.violation;
            return a.mid_dist < b.mid_dist;
        }
    };

    var acc: f64 = 0;
    for (0..seeds) |s| {
        var prng = std.Random.DefaultPrng.init(@as(u64, s) + 1);
        const rand = prng.random();
        var env = env_mod.Environment.initWith(params);
        var failures: u64 = 0;
        const ctx = EvalCtx{ .params = params, .horizon = horizon, .actions = actions };
        for (0..n_steps) |_| {
            var best_act = env_mod.Action.rest;
            var best: RolloutScore = .{ .failed = true, .violation = std.math.maxInt(u32), .mid_dist = std.math.maxInt(u32) };
            for (actions) |act| {
                var sim = env;
                var prng2 = std.Random.DefaultPrng.init(0);
                sim.step(act, prng2.random());
                const sc = ctx.evalPath(sim, horizon - 1);
                if (EvalCtx.better(sc, best)) {
                    best = sc;
                    best_act = act;
                }
            }
            env.step(best_act, rand);
            if (env.failed) failures += 1;
        }
        acc += @as(f64, @floatFromInt(failures)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
    }
    return acc / @as(f64, @floatFromInt(seeds));
}

fn runMbMass(allocator: std.mem.Allocator, params: env_mod.TaskParams, n_steps: usize, seeds: usize) !f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| {
        var env = env_mod.Environment.initWith(params);
        var rng = std.Random.DefaultPrng.init(@as(u64, s) + 1);
        var ag = try agent_mod.Agent.init(allocator, rng.random(), .{
            .action_mode = .mb_mass,
            .enable_macros = false,
            .enable_meta = false,
            .epsilon = 0.0,
        }, &env);
        defer ag.deinit();
        var fails: u64 = 0;
        for (0..n_steps) |_| {
            const r = ag.step(&env, rng.random());
            if (r.failed) fails += 1;
        }
        acc += @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
    }
    return acc / @as(f64, @floatFromInt(seeds));
}

const TunedBest = struct {
    fail: f64,
    charge_below: u32,
    high_above: u32,
    rest_high: bool,
};

const HystBest = struct {
    fail: f64,
    charge_below: u32,
    charge_above: u32,
    high_below: u32,
    high_above: u32,
    rest_high: bool,
    mid_rest: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const band = env_mod.TaskParams{
        .min_mass = 16,
        .max_mass = 48,
        .shock_period = 0,
        .volatility_after = 1_000_000,
    };

    try out.print("=== Swarm EXP-10 (I56): thermostat hard tune on BAND [{d},{d}] ===\n", .{ band.min_mass, band.max_mass });
    try out.print("    {d} steps x {d} seeds, disturbances off\n\n", .{ N_STEPS, N_SEEDS });

    // --- E1 reproduction (eval.zig grid) ---
    try out.print("[1] E1 baseline grid (no hysteresis) — repro eval.zig\n", .{});
    var best_e1: TunedBest = .{ .fail = 1e9, .charge_below = 0, .high_above = 0, .rest_high = true };
    const cbs_e1 = [_]u32{ 14, 16, 18, 20, 22, 24 };
    const ras_e1 = [_]u32{ 28, 32, 36, 40, 44, 47 };
    for (cbs_e1) |cb| for (ras_e1) |ra| {
        if (ra <= cb) continue;
        for ([_]bool{ true, false }) |rh| {
            const f = thermostatTuned(band, cb, ra, rh, N_STEPS, N_SEEDS);
            if (f < best_e1.fail) best_e1 = .{ .fail = f, .charge_below = cb, .high_above = ra, .rest_high = rh };
        }
    };
    try out.print("  best E1: {d:.2} fail/1k  charge<={d} high>={d} high={s}\n\n", .{
        best_e1.fail, best_e1.charge_below, best_e1.high_above, if (best_e1.rest_high) "rest" else "discharge",
    });

    // --- Hysteresis + expanded thresholds ---
    // Screen on 2k x 2 seeds; full 15k x 6 only on survivors scoring <= 0.5 fail/1k.
    try out.print("[2] Hysteresis grid (expanded thresholds + mid zone)\n", .{});
    var best_h: HystBest = .{ .fail = 1e9, .charge_below = 0, .charge_above = 0, .high_below = 0, .high_above = 0, .rest_high = true, .mid_rest = false };
    var configs_tried: u64 = 0;
    var cb: u32 = 12;
    while (cb <= 24) : (cb += 2) {
        var ca: u32 = cb + 1;
        while (ca <= cb + 6) : (ca += 1) {
            var hb: u32 = 30;
            while (hb <= 44) : (hb += 2) {
                var ha: u32 = hb + 1;
                while (ha <= hb + 6) : (ha += 1) {
                    for ([_]bool{ true, false }) |rh| {
                        for ([_]bool{ true, false }) |mr| {
                            configs_tried += 1;
                            const f = thermostatHysteresis(band, cb, ca, hb, ha, rh, mr, 2000, 2);
                            if (f <= 0.5 and f < best_h.fail) {
                                const full = thermostatHysteresis(band, cb, ca, hb, ha, rh, mr, N_STEPS, N_SEEDS);
                                if (full < best_h.fail) {
                                    best_h = .{ .fail = full, .charge_below = cb, .charge_above = ca, .high_below = hb, .high_above = ha, .rest_high = rh, .mid_rest = mr };
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    try out.print("  configs screened: {d} (2k x 2 seeds, full verify if screen <= 0.5)\n", .{configs_tried});
    try out.print("  best hysteresis: {d:.2} fail/1k\n", .{best_h.fail});
    try out.print("    charge<={d} -> charge>={d} | high>={d} -> high<={d}\n", .{ best_h.charge_below, best_h.charge_above, best_h.high_above, best_h.high_below });
    try out.print("    high-action={s}  mid-action={s}\n\n", .{
        if (best_h.rest_high) "rest" else "discharge",
        if (best_h.mid_rest) "rest" else "discharge",
    });

    // --- Lookahead variants ---
    try out.print("[3] Lookahead thermostats (deterministic one-step / H-step)\n", .{});
    const la1 = thermostatLookahead1(band, N_STEPS, N_SEEDS);
    try out.print("  lookahead H=1: {d:.2} fail/1k\n", .{la1});
    const la2 = thermostatLookaheadH(band, 2, N_STEPS, N_SEEDS);
    try out.print("  lookahead H=2: {d:.2} fail/1k\n", .{la2});
    // H>=3 exhaustive rollout is 3^H per step; report as supplementary only.
    const la3 = thermostatLookaheadH(band, 3, 3000, 2);
    try out.print("  lookahead H=3: {d:.2} fail/1k (3k x 2 seeds, supplementary)\n", .{la3});
    const la4 = thermostatLookaheadH(band, 4, 2000, 2);
    try out.print("  lookahead H=4: {d:.2} fail/1k (2k x 2 seeds, supplementary)\n\n", .{la4});

    // --- mb_mass reference ---
    const mb = try runMbMass(alloc, band, N_STEPS, N_SEEDS);
    try out.print("[4] Learned reference\n", .{});
    try out.print("  mb_mass(sum): {d:.2} fail/1k\n\n", .{mb});

    // --- Grand best ---
    // Grand best uses full-protocol policies only (15k x 6).
    const grand = @min(@min(best_e1.fail, best_h.fail), @min(la1, la2));
    try out.print("=== VERDICT ===\n", .{});
    try out.print("  best hand-tuned (any class): {d:.2} fail/1k\n", .{grand});
    try out.print("  mb_mass:                     {d:.2} fail/1k\n", .{mb});
    if (grand < mb) {
        try out.print("  => mb_mass LOSES to best hand-coded thermostat — prior win was STRAWMAN.\n", .{});
    } else if (grand > mb) {
        try out.print("  => mb_mass BEATS best hand-tuned thermostat ({d:.2} < {d:.2}) — win survives (unexpected).\n", .{ mb, grand });
    } else {
        try out.print("  => tie at {d:.2} fail/1k\n", .{grand});
    }

    // Which class won?
    if (grand == best_e1.fail) try out.print("  winner class: E1 tuned (cb={d}, ha={d}, {s})\n", .{ best_e1.charge_below, best_e1.high_above, if (best_e1.rest_high) "rest" else "discharge" });
    if (grand == best_h.fail) try out.print("  winner class: hysteresis\n", .{});
    if (grand == la1) try out.print("  winner class: lookahead H=1\n", .{});
    if (grand == la2) try out.print("  winner class: lookahead H=2\n", .{});
    if (la3 < grand) try out.print("  note: H=3 supplementary screen ({d:.2}) — not full-protocol\n", .{la3});
    if (la4 < grand) try out.print("  note: H=4 supplementary screen ({d:.2}) — not full-protocol\n", .{la4});
}