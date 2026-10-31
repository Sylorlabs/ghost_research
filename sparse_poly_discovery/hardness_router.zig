//! Hardness router — classify control tasks by substrate hardness, route to pair search.
//!
//! Analog of function_hardness Q38 (emergent escape):
//!   deg1 fails ∧ extremal fails ∧ joint (cross-class pair) succeeds.
//!
//! On DUAL_BAND: additive features (sum, left_mass, …) are deg1-class; order
//! statistics (max_cell) are extremal-class. The router probes singles per class,
//! detects Q38 compound structure, and proposes the cross-class pair without O(N²)
//! brute enumeration over all directed pairs.
//!
//! Run standalone: zig build hardness-router-test
//!
//! Pair-selection extension (menu-growth cell pairs): see `pair_hardness_router.zig`
//! and `zig build pair-hardness-router-test` (EXP-2).

const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

pub const FeatureKind = agent_mod.FeatureKind;

/// Mirrors function_hardness substrates mapped onto the control feature menu.
pub const SubstrateClass = enum {
    deg1, // additive / partition statistics (raw-bit analog)
    extremal, // order statistics outside deg1 closure (XOR/extremal analog)
};

/// Features probed for dual-band routing (matches eval pair menu).
pub const ROUTE_FEATURES = [_]FeatureKind{
    .sum, .left_mass, .right_mass, .max_cell,
};

/// Q38 thresholds scaled from function_hardness (fail ≤10/16, succ ≥14/16).
/// Single-band reference ≈11 fail/1k; dual-band singles cluster at 39–115.
pub const Q38_FAIL_SINGLE: f64 = 25.0;
pub const Q38_SUCC_PAIR: f64 = 50.0;

pub const ProbeResult = struct {
    feature: FeatureKind,
    class: SubstrateClass,
    fail_per_1k: f64,
};

pub const TaskClass = enum {
    single_sufficient,
    q38_compound,
    unknown,
};

pub const PairProposal = struct {
    f1: FeatureKind,
    f2: FeatureKind,
    fail_per_1k: f64,
};

pub const RouteResult = struct {
    task_class: TaskClass,
    best_deg1: FeatureKind,
    best_deg1_fail: f64,
    best_extremal: FeatureKind,
    best_extremal_fail: f64,
    proposal: PairProposal,
    probes: [ROUTE_FEATURES.len]ProbeResult,
    n_cross_class_pairs: usize,
};

pub fn featureClass(f: FeatureKind) SubstrateClass {
    return switch (f) {
        .sum, .left_mass, .right_mass, .nonzero_count => .deg1,
        .max_cell, .first_cell => .extremal,
    };
}

pub fn isCompoundTask(params: env_mod.TaskParams) bool {
    return params.min_left_mass > 0 or params.max_left_mass > 0;
}

pub fn runPolicyFailRate(
    allocator: std.mem.Allocator,
    params: env_mod.TaskParams,
    feature: FeatureKind,
    n_steps: usize,
    seed: u64,
) !f64 {
    var env = env_mod.Environment.initWith(params);
    var rng = std.Random.DefaultPrng.init(seed);
    var ag = try agent_mod.Agent.init(allocator, rng.random(), .{
        .action_mode = .mb_mass,
        .enable_macros = false,
        .enable_meta = false,
        .epsilon = 0.0,
        .feature = feature,
    }, &env);
    defer ag.deinit();
    var fails: u32 = 0;
    for (0..n_steps) |_| {
        const r = ag.step(&env, rng.random());
        if (r.failed) fails += 1;
    }
    return @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
}

pub fn meanFailRate(
    allocator: std.mem.Allocator,
    params: env_mod.TaskParams,
    feature: FeatureKind,
    n_steps: usize,
    n_seeds: usize,
    seed_base: u64,
) !f64 {
    var total: f64 = 0;
    for (0..n_seeds) |s| {
        total += try runPolicyFailRate(allocator, params, feature, n_steps, seed_base +% @as(u64, s) *% 0x9E3779B9);
    }
    return total / @as(f64, @floatFromInt(n_seeds));
}

pub fn runPairFailRate(
    allocator: std.mem.Allocator,
    params: env_mod.TaskParams,
    f1: FeatureKind,
    f2: FeatureKind,
    n_steps: usize,
    seed: u64,
) !f64 {
    var env = env_mod.Environment.initWith(params);
    var rng = std.Random.DefaultPrng.init(seed);
    var ag = try agent_mod.Agent.init(allocator, rng.random(), .{
        .action_mode = .mb_mass2,
        .enable_macros = false,
        .enable_meta = false,
        .epsilon = 0.0,
        .feature = f1,
        .feature2 = f2,
    }, &env);
    defer ag.deinit();
    var fails: u32 = 0;
    for (0..n_steps) |_| {
        const r = ag.step(&env, rng.random());
        if (r.failed) fails += 1;
    }
    return @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
}

pub fn meanPairFailRate(
    allocator: std.mem.Allocator,
    params: env_mod.TaskParams,
    f1: FeatureKind,
    f2: FeatureKind,
    n_steps: usize,
    n_seeds: usize,
    seed_base: u64,
) !f64 {
    var total: f64 = 0;
    for (0..n_seeds) |s| {
        total += try runPairFailRate(allocator, params, f1, f2, n_steps, seed_base +% @as(u64, s) *% 0x9E3779B9);
    }
    return total / @as(f64, @floatFromInt(n_seeds));
}

pub fn probeAll(
    allocator: std.mem.Allocator,
    params: env_mod.TaskParams,
    n_steps: usize,
    n_seeds: usize,
    seed_base: u64,
    out: *[ROUTE_FEATURES.len]ProbeResult,
) !void {
    for (ROUTE_FEATURES, 0..) |f, i| {
        out[i] = .{
            .feature = f,
            .class = featureClass(f),
            .fail_per_1k = try meanFailRate(allocator, params, f, n_steps, n_seeds, seed_base),
        };
    }
}

fn bestInClass(probes: []const ProbeResult, class: SubstrateClass) ?ProbeResult {
    var best: ?ProbeResult = null;
    for (probes) |p| {
        if (p.class != class) continue;
        if (best == null or p.fail_per_1k < best.?.fail_per_1k) best = p;
    }
    return best;
}

fn bestOverall(probes: []const ProbeResult) ProbeResult {
    var best = probes[0];
    for (probes[1..]) |p| {
        if (p.fail_per_1k < best.fail_per_1k) best = p;
    }
    return best;
}

pub fn classifyTask(probes: []const ProbeResult, compound: bool) TaskClass {
    const overall = bestOverall(probes);
    if (overall.fail_per_1k <= Q38_FAIL_SINGLE) return .single_sufficient;

    const deg1 = bestInClass(probes, .deg1) orelse return .unknown;
    const ext = bestInClass(probes, .extremal) orelse return .unknown;

    // Q38 analog: both substrate classes fail alone on a compound-constraint task.
    if (compound and deg1.fail_per_1k > Q38_FAIL_SINGLE and ext.fail_per_1k > Q38_FAIL_SINGLE) {
        return .q38_compound;
    }
    return .unknown;
}

pub fn countCrossClassPairs() usize {
    var n: usize = 0;
    for (ROUTE_FEATURES) |f1| {
        for (ROUTE_FEATURES) |f2| {
            if (f1 == f2) continue;
            if (featureClass(f1) != featureClass(f2)) n += 1;
        }
    }
    return n;
}

/// Propose cross-class pair from per-class single-feature probes (no brute search).
pub fn proposeCrossClassPair(probes: []const ProbeResult) struct {
    f1: FeatureKind,
    f2: FeatureKind,
    best_deg1_fail: f64,
    best_extremal_fail: f64,
} {
    const deg1 = bestInClass(probes, .deg1).?;
    const ext = bestInClass(probes, .extremal).?;
    return .{
        .f1 = deg1.feature,
        .f2 = ext.feature,
        .best_deg1_fail = deg1.fail_per_1k,
        .best_extremal_fail = ext.fail_per_1k,
    };
}

pub fn route(
    allocator: std.mem.Allocator,
    params: env_mod.TaskParams,
    probe_steps: usize,
    verify_steps: usize,
    n_seeds: usize,
    seed_base: u64,
) !RouteResult {
    var probes: [ROUTE_FEATURES.len]ProbeResult = undefined;
    try probeAll(allocator, params, probe_steps, n_seeds, seed_base, &probes);

    const compound = isCompoundTask(params);
    const task_class = classifyTask(&probes, compound);

    const cross = proposeCrossClassPair(&probes);
    const pair_fail = try meanPairFailRate(
        allocator,
        params,
        cross.f1,
        cross.f2,
        verify_steps,
        n_seeds,
        seed_base,
    );

    return .{
        .task_class = task_class,
        .best_deg1 = cross.f1,
        .best_deg1_fail = cross.best_deg1_fail,
        .best_extremal = cross.f2,
        .best_extremal_fail = cross.best_extremal_fail,
        .proposal = .{ .f1 = cross.f1, .f2 = cross.f2, .fail_per_1k = pair_fail },
        .probes = probes,
        .n_cross_class_pairs = countCrossClassPairs(),
    };
}

/// Exhaustive directed pair search (baseline for comparison).
pub fn brutePairSearch(
    allocator: std.mem.Allocator,
    params: env_mod.TaskParams,
    n_steps: usize,
    n_seeds: usize,
    seed_base: u64,
) !PairProposal {
    var best: PairProposal = .{ .f1 = ROUTE_FEATURES[0], .f2 = ROUTE_FEATURES[1], .fail_per_1k = 1e9 };
    for (ROUTE_FEATURES) |f1| {
        for (ROUTE_FEATURES) |f2| {
            if (f1 == f2) continue;
            const r = try meanPairFailRate(allocator, params, f1, f2, n_steps, n_seeds, seed_base);
            if (r < best.fail_per_1k) best = .{ .f1 = f1, .f2 = f2, .fail_per_1k = r };
        }
    }
    return best;
}