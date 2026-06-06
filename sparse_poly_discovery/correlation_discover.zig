//! Correlation-based feature pair discovery.
//!
//! Research question: can an agent identify WHICH two features to track for
//! dual-band control, using ONLY its failure history — without exhaustive search?
//!
//! Algorithm (O(N) analysis vs O(N²) probes):
//!   Phase 1: warmup (3000 steps) with feature=sum for control.
//!             After each env.step(), read ALL features from env.grid.
//!             On failure steps, env.grid still holds the failed state (reset
//!             happens at the START of the next call to step(), not immediately).
//!             This lets us see POST-action feature values at failure time.
//!   Phase 2: for each candidate feature, compute failure_correlation:
//!             mean feature value on FAILURE steps vs SAFE steps.
//!             Also compute: what fraction of failures had this feature outside
//!             the [5th..95th percentile] of its safe-step distribution?
//!   Phase 3: rank features by failure_correlation. Propose top-2 as the pair.
//!   Phase 4: verify with one 10,000-step probe using mb_mass2(top2).
//!             Compare to exhaustive result: (left_mass, max_cell) = 0.25 fail/1k.
//!
//! Run: zig build correlation-discover

const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

const FeatureKind = agent_mod.FeatureKind;

const ALL_FEATURES = [_]FeatureKind{ .sum, .max_cell, .left_mass, .right_mass, .nonzero_count };
const N_FEATURES = ALL_FEATURES.len;

// For residual analysis: track each feature's OOR at failure time,
// conditioned on whether a "primary" feature was OOR at that failure.
const ResidualStat = struct {
    // Failures where primary was NOT OOR — residual failures
    resid_total: u32,
    // Of those: how many had THIS feature OOR?
    resid_oor: [N_FEATURES]u32,

    fn init() ResidualStat {
        var s: ResidualStat = .{ .resid_total = 0, .resid_oor = undefined };
        @memset(&s.resid_oor, 0);
        return s;
    }
};

// Collect per-feature summary stats over safe and failure steps.
const FeatureStat = struct {
    // Safe step distribution (post-action grid, no failure)
    safe_sum: f64,
    safe_sum2: f64,
    safe_n: u32,
    safe_min: u32,
    safe_max: u32,

    // Failure step distribution (post-action grid, env.failed==true)
    fail_sum: f64,
    fail_n: u32,

    // Count failures where feature is outside [safe_p5 .. safe_p95]
    // (approximated as mean ± 1.5*std)
    fail_oor: u32,

    fn init() FeatureStat {
        return .{
            .safe_sum = 0, .safe_sum2 = 0, .safe_n = 0,
            .safe_min = std.math.maxInt(u32), .safe_max = 0,
            .fail_sum = 0, .fail_n = 0, .fail_oor = 0,
        };
    }

    fn safeMean(self: *const FeatureStat) f64 {
        if (self.safe_n == 0) return 0;
        return self.safe_sum / @as(f64, @floatFromInt(self.safe_n));
    }

    fn safeStd(self: *const FeatureStat) f64 {
        if (self.safe_n < 2) return 0;
        const n: f64 = @floatFromInt(self.safe_n);
        const mean = self.safe_sum / n;
        const variance = (self.safe_sum2 / n) - (mean * mean);
        return @sqrt(@max(0, variance));
    }

    fn failMean(self: *const FeatureStat) f64 {
        if (self.fail_n == 0) return 0;
        return self.fail_sum / @as(f64, @floatFromInt(self.fail_n));
    }

    // Normalized distance: how far does fail_mean deviate from safe_mean, in std units?
    // High = this feature has different values at failure time → informative.
    fn deviationScore(self: *const FeatureStat) f64 {
        const sd = self.safeStd();
        if (sd < 0.1) return 0;
        return @abs(self.failMean() - self.safeMean()) / sd;
    }

    // OOR fraction: what fraction of failures had this feature outside safe range?
    fn oorFraction(self: *const FeatureStat) f64 {
        if (self.fail_n == 0) return 0;
        return @as(f64, @floatFromInt(self.fail_oor)) / @as(f64, @floatFromInt(self.fail_n));
    }

    fn update(self: *FeatureStat, val: u32, failed: bool) void {
        const v: f64 = @floatFromInt(val);
        if (!failed) {
            self.safe_sum += v;
            self.safe_sum2 += v * v;
            self.safe_n += 1;
            self.safe_min = @min(self.safe_min, val);
            self.safe_max = @max(self.safe_max, val);
        } else {
            self.fail_sum += v;
            self.fail_n += 1;
            // OOR: outside observed safe range
            const oor = (self.safe_n > 50) and (val < self.safe_min or val > self.safe_max);
            if (oor) self.fail_oor += 1;
        }
    }

    fn mergeInto(self: *const FeatureStat, dst: *FeatureStat) void {
        dst.safe_sum += self.safe_sum;
        dst.safe_sum2 += self.safe_sum2;
        dst.safe_n += self.safe_n;
        dst.safe_min = @min(dst.safe_min, self.safe_min);
        dst.safe_max = @max(dst.safe_max, self.safe_max);
        dst.fail_sum += self.fail_sum;
        dst.fail_n += self.fail_n;
        dst.fail_oor += self.fail_oor;
    }
};

// Minimal scalar controller — controls with feature=sum only
const ScalarCtrl = struct {
    cur: u32,
    delta: [3]f32,
    dn: [3]u32,
    safe_min: u32,
    safe_max: u32,
    safe_n: u32,

    fn init() ScalarCtrl {
        return .{ .cur = 0, .delta = .{ 0, 0, 0 }, .dn = .{ 0, 0, 0 },
                  .safe_min = std.math.maxInt(u32), .safe_max = 0, .safe_n = 0 };
    }

    fn chooseAction(self: *const ScalarCtrl, rng: std.Random) u8 {
        if (self.safe_n < 30) return @intCast(rng.intRangeLessThan(usize, 0, 3));
        const sp = @as(f32, @floatFromInt(self.safe_min + self.safe_max)) / 2.0;
        const cm: f32 = @floatFromInt(self.cur);
        var best: u8 = 0;
        var best_err: f32 = 1e9;
        for (0..3) |a| {
            const pred = cm + self.delta[a];
            if (@abs(pred - sp) < best_err) { best_err = @abs(pred - sp); best = @intCast(a); }
        }
        return best;
    }
};

// Run mb_mass2 with a specific feature pair for n_steps. Returns fail/1k.
fn runPair(allocator: std.mem.Allocator, f1: FeatureKind, f2: FeatureKind,
           params: env_mod.TaskParams, n_steps: usize, seed: u64) !f64 {
    var env = env_mod.Environment.initWith(params);
    var rng = std.Random.DefaultPrng.init(seed);
    const cfg = agent_mod.Config{
        .action_mode = .mb_mass2,
        .enable_macros = false, .enable_meta = false,
        .epsilon = 0.0, .feature = f1, .feature2 = f2,
    };
    var ag = try agent_mod.Agent.init(allocator, rng.random(), cfg, &env);
    defer ag.deinit();
    var fails: u32 = 0;
    for (0..n_steps) |_| {
        const r = ag.step(&env, rng.random());
        if (r.failed) fails += 1;
    }
    return @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
}

fn meanPair(allocator: std.mem.Allocator, f1: FeatureKind, f2: FeatureKind,
            params: env_mod.TaskParams, n_steps: usize, n_seeds: usize, base_seed: u64) !f64 {
    var total: f64 = 0;
    for (0..n_seeds) |s| {
        total += try runPair(allocator, f1, f2, params, n_steps, base_seed +% @as(u64, s) *% 0x9E37);
    }
    return total / @as(f64, @floatFromInt(n_seeds));
}

// Run a single-feature ScalarCtrl for n_steps. Returns fail/1k.
// This is the "controllability" probe: does tracking this feature alone help?
fn probeFeatureCtrl(f: FeatureKind, params: env_mod.TaskParams, n_steps: usize, seed: u64) f64 {
    var ctrl = ScalarCtrl.init();
    var env = env_mod.Environment.initWith(params);
    var rng = std.Random.DefaultPrng.init(seed);
    var fails: u32 = 0;
    for (0..n_steps) |_| {
        ctrl.cur = agent_mod.featureValue(env.grid, f);
        const action_idx = ctrl.chooseAction(rng.random());
        env.step(@enumFromInt(action_idx), rng.random());
        if (env.failed) fails += 1;
        const feat_next = agent_mod.featureValue(env.grid, f);
        const d = @as(f32, @floatFromInt(feat_next)) - @as(f32, @floatFromInt(ctrl.cur));
        ctrl.dn[action_idx] += 1;
        const n: f32 = @floatFromInt(ctrl.dn[action_idx]);
        ctrl.delta[action_idx] += (d - ctrl.delta[action_idx]) / n;
        if (!env.failed) {
            ctrl.safe_min = @min(ctrl.safe_min, feat_next);
            ctrl.safe_max = @max(ctrl.safe_max, feat_next);
            ctrl.safe_n += 1;
        }
    }
    return @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
}

fn meanProbe(f: FeatureKind, params: env_mod.TaskParams, n_steps: usize, n_seeds: usize, base_seed: u64) f64 {
    var total: f64 = 0;
    for (0..n_seeds) |s| {
        total += probeFeatureCtrl(f, params, n_steps, base_seed +% @as(u64, s) *% 0x9E37);
    }
    return total / @as(f64, @floatFromInt(n_seeds));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const dual = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };

    const WARMUP: usize = 5000;
    const VERIFY_STEPS: usize = 10_000;
    const VERIFY_SEEDS: usize = 6;
    const N_SEEDS: usize = 8;

    try out.print("=== CORRELATION-BASED FEATURE PAIR DISCOVERY ===\n\n", .{});
    try out.print("Task: DUAL_BAND (sum+left_mass constraints)\n", .{});
    try out.print("Known exhaustive result: (left_mass,max_cell)=0.25 fail/1k\n\n", .{});
    try out.print("KEY DESIGN: features measured AFTER env.step() returns.\n", .{});
    try out.print("When failed==true, env.grid is the POST-ACTION state that caused failure.\n", .{});
    try out.print("(Reset happens at START of next step(), not immediately.)\n\n", .{});

    // Accumulate across seeds
    var global_stats: [N_FEATURES]FeatureStat = undefined;
    for (0..N_FEATURES) |i| global_stats[i] = FeatureStat.init();
    // Residual stats: per primary feature, what other features are OOR on residual failures?
    var resid: [N_FEATURES]ResidualStat = undefined;
    for (0..N_FEATURES) |i| resid[i] = ResidualStat.init();

    try out.print("--- Phase 1+2: Warmup ({d} steps x {d} seeds, feature=sum control) ---\n\n",
        .{ WARMUP, N_SEEDS });

    for (0..N_SEEDS) |s| {
        const seed = 0xABC0 +% @as(u64, s) *% 0x9E37;
        var env = env_mod.Environment.initWith(dual);
        var rng = std.Random.DefaultPrng.init(seed);
        var ctrl = ScalarCtrl.init();
        var seed_stats: [N_FEATURES]FeatureStat = undefined;
        for (0..N_FEATURES) |i| seed_stats[i] = FeatureStat.init();

        for (0..WARMUP) |_| {
            // Choose action based on sum
            ctrl.cur = agent_mod.featureValue(env.grid, .sum);
            const action_idx = ctrl.chooseAction(rng.random());

            // Apply action
            env.step(@enumFromInt(action_idx), rng.random());

            // KEY: read features NOW from env.grid.
            // If env.failed==true, this is the post-action failed state.
            // If env.failed==false, this is the post-action safe state.
            var feat_vals: [N_FEATURES]u32 = undefined;
            for (ALL_FEATURES, 0..) |f, fi| {
                feat_vals[fi] = agent_mod.featureValue(env.grid, f);
            }
            for (0..N_FEATURES) |fi| {
                seed_stats[fi].update(feat_vals[fi], env.failed);
            }

            // Residual analysis: at failure time, for each feature p that was NOT OOR,
            // record which OTHER features j were OOR (those are residual-failure causes).
            if (env.failed) {
                for (0..N_FEATURES) |p| {
                    // Check if feature p was OOR
                    const p_oor = seed_stats[p].safe_n > 50 and
                        (feat_vals[p] < seed_stats[p].safe_min or feat_vals[p] > seed_stats[p].safe_max);
                    if (!p_oor) {
                        // p was NOT the primary cause. Among residual failures (p in-range),
                        // which other feature j was OOR?
                        resid[p].resid_total += 1;
                        for (0..N_FEATURES) |j| {
                            if (j == p) continue;
                            const j_oor = seed_stats[j].safe_n > 50 and
                                (feat_vals[j] < seed_stats[j].safe_min or feat_vals[j] > seed_stats[j].safe_max);
                            if (j_oor) resid[p].resid_oor[j] += 1;
                        }
                    }
                }
            }

            // Update scalar sum controller from post-step sum
            const sum_next = feat_vals[0]; // sum is index 0 in ALL_FEATURES
            const d = @as(f32, @floatFromInt(sum_next)) - @as(f32, @floatFromInt(ctrl.cur));
            ctrl.dn[action_idx] += 1;
            const n: f32 = @floatFromInt(ctrl.dn[action_idx]);
            ctrl.delta[action_idx] += (d - ctrl.delta[action_idx]) / n;
            if (!env.failed) {
                ctrl.safe_min = @min(ctrl.safe_min, sum_next);
                ctrl.safe_max = @max(ctrl.safe_max, sum_next);
                ctrl.safe_n += 1;
            }
        }

        for (0..N_FEATURES) |fi| seed_stats[fi].mergeInto(&global_stats[fi]);
    }

    // Print per-feature stats
    try out.print("--- Phase 2: Feature distributions at safe vs failure steps ---\n", .{});
    try out.print("  feature        | safe_mean | safe_std | fail_mean | deviation | oor_frac\n", .{});
    try out.print("  ---------------+-----------+----------+-----------+-----------+---------\n", .{});

    // Sort by deviation score
    var ranked = [_]usize{0} ** N_FEATURES;
    for (0..N_FEATURES) |i| ranked[i] = i;
    for (1..N_FEATURES) |i| {
        var j = i;
        while (j > 0 and global_stats[ranked[j]].deviationScore() > global_stats[ranked[j-1]].deviationScore()) {
            const tmp = ranked[j]; ranked[j] = ranked[j-1]; ranked[j-1] = tmp;
            j -= 1;
        }
    }

    for (ranked) |fi| {
        const st = &global_stats[fi];
        const top = fi == ranked[0] or fi == ranked[1];
        try out.print("  {s:<14} | {d:9.2} | {d:8.2} | {d:9.2} | {d:9.3} | {d:8.3}{s}\n", .{
            @tagName(ALL_FEATURES[fi]),
            st.safeMean(), st.safeStd(),
            st.failMean(),
            st.deviationScore(),
            st.oorFraction(),
            if (top) " <-- TOP" else "",
        });
    }

    const top1_fi = ranked[0];
    const top2_fi = ranked[1];
    const top1 = ALL_FEATURES[top1_fi];
    const top2 = ALL_FEATURES[top2_fi];

    // Residual analysis: rank by OOR fraction. Primary = highest OOR.
    // Then find: given primary is in-range, which OTHER feature is most often OOR?
    var oor_ranked = [_]usize{0} ** N_FEATURES;
    for (0..N_FEATURES) |i| oor_ranked[i] = i;
    for (1..N_FEATURES) |i| {
        var j = i;
        while (j > 0 and global_stats[oor_ranked[j]].oorFraction() > global_stats[oor_ranked[j-1]].oorFraction()) {
            const tmp = oor_ranked[j]; oor_ranked[j] = oor_ranked[j-1]; oor_ranked[j-1] = tmp;
            j -= 1;
        }
    }
    const primary_fi = oor_ranked[0];
    const primary = ALL_FEATURES[primary_fi];
    // Given primary is in-range at failure, which feature j was most often OOR?
    var best_resid_j: usize = 0;
    var best_resid_count: u32 = 0;
    for (0..N_FEATURES) |j| {
        if (j == primary_fi) continue;
        if (resid[primary_fi].resid_oor[j] > best_resid_count) {
            best_resid_count = resid[primary_fi].resid_oor[j];
            best_resid_j = j;
        }
    }
    const secondary = ALL_FEATURES[best_resid_j];

    try out.print("\n--- APPROACH 3: Residual analysis ---\n", .{});
    try out.print("  Primary (highest OOR): {s} (oor_frac={d:.3})\n", .{
        @tagName(primary), global_stats[primary_fi].oorFraction(),
    });
    try out.print("  Residual failures (primary in-range): {d}\n", .{ resid[primary_fi].resid_total });
    try out.print("  Residual OOR counts per feature:\n", .{});
    for (0..N_FEATURES) |j| {
        if (j == primary_fi) continue;
        const frac: f64 = if (resid[primary_fi].resid_total > 0)
            @as(f64, @floatFromInt(resid[primary_fi].resid_oor[j])) / @as(f64, @floatFromInt(resid[primary_fi].resid_total))
        else 0;
        try out.print("    {s:<14}: {d}/{d} = {d:.3}{s}\n", .{
            @tagName(ALL_FEATURES[j]),
            resid[primary_fi].resid_oor[j], resid[primary_fi].resid_total,
            frac,
            if (j == best_resid_j) " <-- TOP RESIDUAL" else "",
        });
    }
    try out.print("  => Residual-proposed pair: ({s}, {s})\n\n", .{ @tagName(primary), @tagName(secondary) });

    const resid_result = try meanPair(alloc, primary, secondary, dual, VERIFY_STEPS, VERIFY_SEEDS, 0xABC0);
    try out.print("  Verify ({s},{s}): {d:.2} fail/1k\n",
        .{ @tagName(primary), @tagName(secondary), resid_result });
    const resid_matched = (primary == .left_mass and secondary == .max_cell) or
                          (primary == .max_cell and secondary == .left_mass);
    if (resid_matched and resid_result < 5.0) {
        try out.print("  APPROACH 3 POSITIVE: residual analysis found the correct pair!\n", .{});
    } else if (resid_result < 5.0) {
        try out.print("  APPROACH 3 PARTIAL: different pair name but achieves {d:.2} fail/1k.\n", .{resid_result});
    } else {
        try out.print("  APPROACH 3 NEGATIVE: {d:.2} fail/1k. Residual analysis insufficient.\n", .{resid_result});
    }

    try out.print("\n--- Phase 3: Correlation-proposed pair (deviation score) ---\n", .{});
    try out.print("  Top-1: {s} (deviation={d:.3}, oor={d:.3})\n", .{
        @tagName(top1), global_stats[top1_fi].deviationScore(), global_stats[top1_fi].oorFraction(),
    });
    try out.print("  Top-2: {s} (deviation={d:.3}, oor={d:.3})\n", .{
        @tagName(top2), global_stats[top2_fi].deviationScore(), global_stats[top2_fi].oorFraction(),
    });
    try out.print("  => Proposed pair: ({s}, {s})\n\n", .{ @tagName(top1), @tagName(top2) });

    // Phase 4: Verify
    try out.print("--- Phase 4: Verify proposed pair ({d} steps x {d} seeds) ---\n",
        .{ VERIFY_STEPS, VERIFY_SEEDS });

    const proposed_result = try meanPair(alloc, top1, top2, dual, VERIFY_STEPS, VERIFY_SEEDS, 0xABC0);
    try out.print("  proposed ({s},{s}): {d:.2} fail/1k\n",
        .{ @tagName(top1), @tagName(top2), proposed_result });

    const known_best = try meanPair(alloc, .left_mass, .max_cell, dual, VERIFY_STEPS, VERIFY_SEEDS, 0xABC0);
    try out.print("  known best (left_mass,max_cell): {d:.2} fail/1k\n", .{known_best});

    const naive = try meanPair(alloc, .sum, .left_mass, dual, VERIFY_STEPS, VERIFY_SEEDS, 0xABC0);
    try out.print("  naive (sum,left_mass): {d:.2} fail/1k\n\n", .{naive});

    try out.print("=== VERDICT ===\n", .{});
    const matched = (top1 == .left_mass and top2 == .max_cell) or
                    (top1 == .max_cell and top2 == .left_mass);
    if (matched) {
        try out.print("  POSITIVE: correlation analysis proposed ({s},{s}) — the correct pair.\n",
            .{ @tagName(top1), @tagName(top2) });
        try out.print("  O(N) analysis matched O(N^2) exhaustive search. Achieved {d:.2} fail/1k.\n",
            .{proposed_result});
        if (proposed_result < 5.0) {
            try out.print("  STRONG: proposed pair achieves near-optimal control.\n", .{});
        }
    } else {
        try out.print("  NEGATIVE: proposed ({s},{s}), not (left_mass,max_cell).\n",
            .{ @tagName(top1), @tagName(top2) });
        try out.print("  Proposed: {d:.2} fail/1k. Exhaustive best: {d:.2} fail/1k.\n",
            .{ proposed_result, known_best });
        // But is the proposed pair still good?
        if (proposed_result < 10.0) {
            try out.print("  PARTIAL: proposed pair is still effective ({d:.2} fail/1k < 10.0).\n",
                .{proposed_result});
        } else {
            try out.print("  Correlation analysis finds different features than exhaustive search\n", .{});
            try out.print("  but fails to achieve good control. Exhaustive search is still needed.\n", .{});
        }
    }

    // APPROACH 2: Controllability-ranked pairing
    // Rank features by single-feature control quality (O(N) probes), pair top-2.
    // Hypothesis: pairing the two individually-best features gives the best pair.
    const CTRL_PROBE_STEPS: usize = 8_000;
    const CTRL_PROBE_SEEDS: usize = 6;

    try out.print("\n=== APPROACH 2: Controllability-ranked pairing (O(N) probes) ===\n\n", .{});
    try out.print("Run {d}x{d} single-feature probes, rank by fail/1k, pair top-2.\n\n",
        .{ CTRL_PROBE_STEPS, CTRL_PROBE_SEEDS });

    var ctrl_scores: [N_FEATURES]f64 = undefined;
    var ctrl_ranked = [_]usize{0} ** N_FEATURES;
    for (0..N_FEATURES) |i| ctrl_ranked[i] = i;

    for (0..N_FEATURES) |fi| {
        ctrl_scores[fi] = meanProbe(ALL_FEATURES[fi], dual, CTRL_PROBE_STEPS, CTRL_PROBE_SEEDS, 0xABC0);
        try out.print("  {s:<14}: {d:.2} fail/1k (single-feature)\n",
            .{ @tagName(ALL_FEATURES[fi]), ctrl_scores[fi] });
    }

    // Sort ascending (lower fail/1k is better)
    for (1..N_FEATURES) |i| {
        var j = i;
        while (j > 0 and ctrl_scores[ctrl_ranked[j]] < ctrl_scores[ctrl_ranked[j-1]]) {
            const tmp = ctrl_ranked[j]; ctrl_ranked[j] = ctrl_ranked[j-1]; ctrl_ranked[j-1] = tmp;
            j -= 1;
        }
    }

    const c1_fi = ctrl_ranked[0];
    const c2_fi = ctrl_ranked[1];
    const c1 = ALL_FEATURES[c1_fi];
    const c2 = ALL_FEATURES[c2_fi];
    try out.print("\n  Top-1: {s} ({d:.2} fail/1k)\n", .{ @tagName(c1), ctrl_scores[c1_fi] });
    try out.print("  Top-2: {s} ({d:.2} fail/1k)\n", .{ @tagName(c2), ctrl_scores[c2_fi] });
    try out.print("  => Controllability-proposed pair: ({s}, {s})\n\n", .{ @tagName(c1), @tagName(c2) });

    const ctrl_pair_result = try meanPair(alloc, c1, c2, dual, VERIFY_STEPS, VERIFY_SEEDS, 0xABC0);
    try out.print("  Verify ({s},{s}): {d:.2} fail/1k\n",
        .{ @tagName(c1), @tagName(c2), ctrl_pair_result });
    try out.print("  Known best (left_mass,max_cell): {d:.2} fail/1k\n\n", .{known_best});

    const ctrl_matched = (c1 == .left_mass and c2 == .max_cell) or
                         (c1 == .max_cell and c2 == .left_mass);
    try out.print("=== APPROACH 2 VERDICT ===\n", .{});
    if (ctrl_matched and ctrl_pair_result < 5.0) {
        try out.print("  POSITIVE: controllability-ranked pairing found the right pair.\n", .{});
        try out.print("  O(N) probes ({d} features x {d} steps) matches O(N^2) exhaustive.\n",
            .{ N_FEATURES, CTRL_PROBE_STEPS });
        try out.print("  Reduction: {d} probes vs {d} exhaustive pair probes.\n",
            .{ N_FEATURES, N_FEATURES * (N_FEATURES - 1) });
    } else if (ctrl_pair_result < 5.0) {
        try out.print("  PARTIAL POSITIVE: different pair name but achieves {d:.2} fail/1k < 5.0.\n",
            .{ctrl_pair_result});
        try out.print("  Controllability ranking finds a different-but-effective pair.\n", .{});
    } else {
        try out.print("  NEGATIVE: controllability-ranked pair achieves {d:.2} fail/1k.\n",
            .{ctrl_pair_result});
        try out.print("  O(N) controllability probes insufficient; O(N^2) search still needed.\n", .{});
    }
}
