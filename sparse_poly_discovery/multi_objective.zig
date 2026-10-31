//! EXP-11 (C27): Multi-objective band control — keep mass in band AND maximise delivered work.
//!
//! Two measurable objectives (Pareto, both better = lower fail, higher work):
//!   1. fail/1k   — band + dendrite violations (minimize)
//!   2. work/1k   — charge + discharge actions per 1000 steps (maximize)
//!
//! Compare hand-coded thermostat sweep vs mb_mass(sum) vs mb_mass2 (2-feature learned).
//! Question (RQ27): can a learner trade off and Pareto-dominate hand-coded?
//!
//! Run: zig build multi-objective

const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

const Action = env_mod.Action;

const Category = enum { hand_coded, mb_mass, mb_mass2 };

const ObjPoint = struct {
    name: []const u8,
    fail_per_1k: f64,
    work_per_1k: f64,
    category: Category,
};

const RunStats = struct {
    fail_per_1k: f64,
    work_per_1k: f64,
};

fn gridMass(grid: [16]u8) u32 {
    var s: u32 = 0;
    for (grid) |c| s += c;
    return s;
}

fn isWorkAction(a: Action) bool {
    return a == .charge or a == .discharge;
}

fn runAgent(
    allocator: std.mem.Allocator,
    params: env_mod.TaskParams,
    cfg: agent_mod.Config,
    n_steps: usize,
    seed: u64,
) !RunStats {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var env = env_mod.Environment.initWith(params);
    var agent = try agent_mod.Agent.init(allocator, rand, cfg, &env);
    defer agent.deinit();

    var failures: u64 = 0;
    var work: u64 = 0;
    for (0..n_steps) |_| {
        const r = agent.step(&env, rand);
        if (r.failed) failures += 1;
        const act: Action = @enumFromInt(r.action);
        if (isWorkAction(act)) work += 1;
    }
    const nf: f64 = @floatFromInt(n_steps);
    return .{
        .fail_per_1k = @as(f64, @floatFromInt(failures)) / nf * 1000.0,
        .work_per_1k = @as(f64, @floatFromInt(work)) / nf * 1000.0,
    };
}

fn runAgentMean(
    allocator: std.mem.Allocator,
    params: env_mod.TaskParams,
    cfg: agent_mod.Config,
    n_steps: usize,
    seeds: usize,
) !RunStats {
    var acc = RunStats{ .fail_per_1k = 0, .work_per_1k = 0 };
    for (0..seeds) |s| {
        const st = try runAgent(allocator, params, cfg, n_steps, @as(u64, s) + 1);
        acc.fail_per_1k += st.fail_per_1k;
        acc.work_per_1k += st.work_per_1k;
    }
    const sf: f64 = @floatFromInt(seeds);
    return .{
        .fail_per_1k = acc.fail_per_1k / sf,
        .work_per_1k = acc.work_per_1k / sf,
    };
}

/// Hand-coded thermostat with tunable safety margins and mid-band work bias.
/// mid_work: in the safe middle, prefer charge (work) over discharge bleed.
fn runThermostat(
    params: env_mod.TaskParams,
    charge_below: u32,
    high_above: u32,
    rest_high: bool,
    mid_work: bool,
    n_steps: usize,
    seed: u64,
) RunStats {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var env = env_mod.Environment.initWith(params);
    var failures: u64 = 0;
    var work: u64 = 0;
    for (0..n_steps) |_| {
        const mass = gridMass(env.grid);
        const action: Action = blk: {
            if (mass <= charge_below) break :blk .charge;
            if (params.max_mass > 0 and mass >= high_above) break :blk (if (rest_high) .rest else .discharge);
            break :blk if (mid_work) .charge else .discharge;
        };
        env.step(action, rand);
        if (env.failed) failures += 1;
        if (isWorkAction(action)) work += 1;
    }
    const nf: f64 = @floatFromInt(n_steps);
    return .{
        .fail_per_1k = @as(f64, @floatFromInt(failures)) / nf * 1000.0,
        .work_per_1k = @as(f64, @floatFromInt(work)) / nf * 1000.0,
    };
}

fn runThermostatMean(
    params: env_mod.TaskParams,
    charge_below: u32,
    high_above: u32,
    rest_high: bool,
    mid_work: bool,
    n_steps: usize,
    seeds: usize,
) RunStats {
    var acc = RunStats{ .fail_per_1k = 0, .work_per_1k = 0 };
    for (0..seeds) |s| {
        const st = runThermostat(params, charge_below, high_above, rest_high, mid_work, n_steps, @as(u64, s) + 1);
        acc.fail_per_1k += st.fail_per_1k;
        acc.work_per_1k += st.work_per_1k;
    }
    const sf: f64 = @floatFromInt(seeds);
    return .{
        .fail_per_1k = acc.fail_per_1k / sf,
        .work_per_1k = acc.work_per_1k / sf,
    };
}

/// A dominates B when A is no worse on both axes and strictly better on at least one.
fn dominates(a: ObjPoint, b: ObjPoint) bool {
    const fail_ok = a.fail_per_1k <= b.fail_per_1k;
    const work_ok = a.work_per_1k >= b.work_per_1k;
    const strict = a.fail_per_1k < b.fail_per_1k or a.work_per_1k > b.work_per_1k;
    return fail_ok and work_ok and strict;
}

fn computePareto(points: []const ObjPoint, out_idx: []usize) usize {
    var count: usize = 0;
    for (points, 0..) |p, i| {
        var dominated = false;
        for (points) |q| {
            if (dominates(q, p)) {
                dominated = true;
                break;
            }
        }
        if (!dominated) {
            out_idx[count] = i;
            count += 1;
        }
    }
    return count;
}

fn dominatesCategory(points: []const ObjPoint, winner: Category, loser: Category) bool {
    for (points) |w| {
        if (w.category != winner) continue;
        var any_dominated = false;
        for (points) |l| {
            if (l.category != loser) continue;
            if (dominates(w, l)) any_dominated = true;
        }
        if (any_dominated) return true;
    }
    return false;
}

fn beatsBothAxes(points: []const ObjPoint, learner: Category, hand: Category) bool {
    for (points) |l| {
        if (l.category != learner) continue;
        for (points) |h| {
            if (h.category != hand) continue;
            if (l.fail_per_1k < h.fail_per_1k and l.work_per_1k > h.work_per_1k) return true;
        }
    }
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const n_steps: usize = 15_000;
    const seeds: usize = 6;
    const band = env_mod.TaskParams{
        .min_mass = 16,
        .max_mass = 48,
        .shock_period = 0,
        .volatility_after = 1_000_000,
    };

    try out.print("=== EXP-11 (C27): Multi-objective band — safety vs delivered work ===\n\n", .{});
    try out.print("Task: total_mass in [{d},{d}], disturbances off.\n", .{ band.min_mass, band.max_mass });
    try out.print("Objectives: minimize fail/1k, maximize work/1k (charge+discharge actions).\n", .{});
    try out.print("Steps: {d} x {d} seeds (matches main eval harness).\n\n", .{ n_steps, seeds });

    var points: [256]ObjPoint = undefined;
    var labels: [256][48]u8 = undefined;
    var pi: usize = 0;

    // --- Hand-coded Pareto sweep: grid-tune thermostat safety vs mid-band work ---
    try out.print("── Hand-coded thermostat sweep ──\n", .{});
    try out.print("  cb  ra  rest_hi  mid_work | fail/1k | work/1k\n", .{});
    const cbs = [_]u32{ 14, 16, 18, 20, 22, 24 };
    const ras = [_]u32{ 28, 32, 36, 40, 44, 47 };
    var best_safe = RunStats{ .fail_per_1k = 1e9, .work_per_1k = 0 };
    var best_safe_label: [48]u8 = undefined;
    var best_work_safe = RunStats{ .fail_per_1k = 1e9, .work_per_1k = 0 };
    var best_work_label: [48]u8 = undefined;

    for (cbs) |cb| {
        for (ras) |ra| {
            if (ra <= cb) continue;
            for ([_]bool{ true, false }) |rh| {
                for ([_]bool{ false, true }) |mw| {
                    const st = runThermostatMean(band, cb, ra, rh, mw, n_steps, seeds);
                    try out.print("  {d:2} {d:2}   {s:5}    {s:5}   | {d:7.2} | {d:7.1}\n", .{
                        cb, ra, if (rh) "rest" else "disch", if (mw) "work" else "bleed", st.fail_per_1k, st.work_per_1k,
                    });
                    const name = try std.fmt.bufPrint(&labels[pi], "therm cb={d} ra={d} {s} {s}", .{
                        cb, ra, if (rh) "rest" else "disch", if (mw) "work" else "bleed",
                    });
                    points[pi] = .{ .name = name, .fail_per_1k = st.fail_per_1k, .work_per_1k = st.work_per_1k, .category = .hand_coded };
                    pi += 1;
                    if (st.fail_per_1k < best_safe.fail_per_1k or
                        (st.fail_per_1k == best_safe.fail_per_1k and st.work_per_1k > best_safe.work_per_1k))
                    {
                        best_safe = st;
                        @memcpy(best_safe_label[0..name.len], name);
                    }
                    if (st.work_per_1k > best_work_safe.work_per_1k and st.fail_per_1k < 50.0) {
                        best_work_safe = st;
                        @memcpy(best_work_label[0..name.len], name);
                    }
                }
            }
        }
    }
    try out.print("\n  best safety hand-coded: {s} => fail={d:.2} work={d:.1}\n", .{ best_safe_label[0..], best_safe.fail_per_1k, best_safe.work_per_1k });
    try out.print("  best work (fail<50):    {s} => fail={d:.2} work={d:.1}\n\n", .{ best_work_label[0..], best_work_safe.fail_per_1k, best_work_safe.work_per_1k });

    // --- mb_mass (1D learned) ---
    try out.print("── mb_mass (1D learned) ──\n", .{});
    const mb_sum = try runAgentMean(alloc, band, .{
        .action_mode = .mb_mass,
        .enable_macros = false,
        .enable_meta = false,
        .epsilon = 0.0,
        .feature = .sum,
    }, n_steps, seeds);
    try out.print("  mb_mass(sum)           | {d:7.2} | {d:7.1}\n\n", .{ mb_sum.fail_per_1k, mb_sum.work_per_1k });
    points[pi] = .{ .name = "mb_mass(sum)", .fail_per_1k = mb_sum.fail_per_1k, .work_per_1k = mb_sum.work_per_1k, .category = .mb_mass };
    pi += 1;

    const mb_left = try runAgentMean(alloc, band, .{
        .action_mode = .mb_mass,
        .enable_macros = false,
        .enable_meta = false,
        .epsilon = 0.0,
        .feature = .left_mass,
    }, n_steps, seeds);
    try out.print("  mb_mass(left_mass)     | {d:7.2} | {d:7.1}\n", .{ mb_left.fail_per_1k, mb_left.work_per_1k });
    points[pi] = .{ .name = "mb_mass(left_mass)", .fail_per_1k = mb_left.fail_per_1k, .work_per_1k = mb_left.work_per_1k, .category = .mb_mass };
    pi += 1;

    // --- mb_mass2 (2-feature learned): pair search on single-band ---
    try out.print("\n── mb_mass2 (2-feature learned) — pair search ──\n", .{});
    const pair_feats = [_]agent_mod.FeatureKind{ .sum, .max_cell, .left_mass, .right_mass, .nonzero_count };
    var best2 = RunStats{ .fail_per_1k = 1e9, .work_per_1k = 0 };
    var best2_f1 = pair_feats[0];
    var best2_f2 = pair_feats[1];
    for (pair_feats) |f1| {
        for (pair_feats) |f2| {
            if (f1 == f2) continue;
            const st = try runAgentMean(alloc, band, .{
                .action_mode = .mb_mass2,
                .enable_macros = false,
                .enable_meta = false,
                .epsilon = 0.0,
                .feature = f1,
                .feature2 = f2,
            }, n_steps, seeds);
            try out.print("  pair({s},{s}) | {d:7.2} | {d:7.1}\n", .{ @tagName(f1), @tagName(f2), st.fail_per_1k, st.work_per_1k });
            const name = try std.fmt.bufPrint(&labels[pi], "mb_mass2({s},{s})", .{ @tagName(f1), @tagName(f2) });
            points[pi] = .{ .name = name, .fail_per_1k = st.fail_per_1k, .work_per_1k = st.work_per_1k, .category = .mb_mass2 };
            pi += 1;
            if (st.fail_per_1k < best2.fail_per_1k or
                (st.fail_per_1k == best2.fail_per_1k and st.work_per_1k > best2.work_per_1k))
            {
                best2 = st;
                best2_f1 = f1;
                best2_f2 = f2;
            }
        }
    }
    try out.print("\n  => best 2-feature pair: ({s},{s}) fail={d:.2} work={d:.1}\n\n", .{
        @tagName(best2_f1), @tagName(best2_f2), best2.fail_per_1k, best2.work_per_1k,
    });

    // --- Pareto analysis ---
    const all = points[0..pi];
    var pareto_idx: [256]usize = undefined;
    const pareto_n = computePareto(all, pareto_idx[0..]);

    try out.print("── Pareto frontier ({d} non-dominated of {d} points) ──\n", .{ pareto_n, pi });
    try out.print("  policy                              | fail/1k | work/1k | class\n", .{});
    try out.print("  ------------------------------------+---------+---------+----------\n", .{});
    for (pareto_idx[0..pareto_n]) |idx| {
        const p = all[idx];
        try out.print("  {s:<35} | {d:7.2} | {d:7.1} | {s}\n", .{
            p.name, p.fail_per_1k, p.work_per_1k, @tagName(p.category),
        });
    }

    // Category-level dominance
    const mb_mass_dom_hand = dominatesCategory(all, .mb_mass, .hand_coded);
    const mb_mass2_dom_hand = dominatesCategory(all, .mb_mass2, .hand_coded);
    const mb_mass2_dom_mb_mass = dominatesCategory(all, .mb_mass2, .mb_mass);
    const mb_mass_both = beatsBothAxes(all, .mb_mass, .hand_coded);
    const mb_mass2_both = beatsBothAxes(all, .mb_mass2, .hand_coded);

    try out.print("\n── Dominance summary (RQ27) ──\n", .{});
    try out.print("  mb_mass  Pareto-dominates some hand-coded point:  {s}\n", .{if (mb_mass_dom_hand) "YES" else "NO"});
    try out.print("  mb_mass2 Pareto-dominates some hand-coded point: {s}\n", .{if (mb_mass2_dom_hand) "YES" else "NO"});
    try out.print("  mb_mass2 Pareto-dominates some mb_mass point:     {s}\n", .{if (mb_mass2_dom_mb_mass) "YES" else "NO"});
    try out.print("  mb_mass  beats hand-coded on BOTH axes (any pair): {s}\n", .{if (mb_mass_both) "YES" else "NO"});
    try out.print("  mb_mass2 beats hand-coded on BOTH axes (any pair): {s}\n", .{if (mb_mass2_both) "YES" else "NO"});

    // Frontier membership by category
    var hand_on_frontier: usize = 0;
    var mb_on_frontier: usize = 0;
    var m2_on_frontier: usize = 0;
    for (pareto_idx[0..pareto_n]) |idx| {
        switch (all[idx].category) {
            .hand_coded => hand_on_frontier += 1,
            .mb_mass => mb_on_frontier += 1,
            .mb_mass2 => m2_on_frontier += 1,
        }
    }
    try out.print("\n  Pareto frontier by category: hand={d}  mb_mass={d}  mb_mass2={d}\n", .{
        hand_on_frontier, mb_on_frontier, m2_on_frontier,
    });

    if (mb_mass2_both or mb_mass_both) {
        try out.print("\n=> VERDICT: learner CAN beat hand-coded on both axes.\n", .{});
    } else if (mb_mass2_dom_hand or mb_mass_dom_hand) {
        try out.print("\n=> VERDICT: learner Pareto-dominates hand-coded on one axis trade-off, but NOT both axes simultaneously.\n", .{});
    } else {
        try out.print("\n=> VERDICT: hand-coded Pareto frontier holds — no learner dominates.\n", .{});
    }
}