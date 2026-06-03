//! Adaptive feature discovery: an agent that detects when its own model is wrong
//! (model disagreement) and automatically searches for a better feature — without
//! being told which feature matters.
//!
//! This tests the minimal form of "self-directed invention":
//!   Phase 1: warm up with initial feature (sum), measure control quality
//!   Phase 2: detect high model disagreement (predicted safe but failed often)
//!   Phase 3: autonomous feature search — try each FeatureKind, pick the best
//!   Phase 4: commit to discovered feature, continue
//!
//! On dual-band (total_mass + left_mass constraint), a sum-only agent has
//! disagree_rate ~0.7 (fails even when it thinks it's safe). The adaptive agent
//! should discover left_mass autonomously and improve its own control.
//!
//! If the adaptive agent achieves ~39 fail/1k (matching mb_mass(left_mass))
//! WITHOUT being told to use left_mass, that is minimal self-directed improvement.
//!
//! Run: zig build adaptive-feature

const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

const FeatureKind = agent_mod.FeatureKind;
const all_features = [_]FeatureKind{ .sum, .max_cell, .left_mass, .right_mass, .nonzero_count };

// Minimal scalar controller: learns deltas + safe range for one feature.
const ScalarController = struct {
    feature: FeatureKind,
    cur: u32,
    delta: [3]f32,
    dn: [3]u32,
    safe_min: u32,
    safe_max: u32,
    safe_n: u32,
    predicted_safe: u32,
    unexplained_fail: u32,

    fn init(f: FeatureKind) ScalarController {
        return .{
            .feature = f,
            .cur = 0,
            .delta = .{ 0, 0, 0 },
            .dn = .{ 0, 0, 0 },
            .safe_min = std.math.maxInt(u32),
            .safe_max = 0,
            .safe_n = 0,
            .predicted_safe = 0,
            .unexplained_fail = 0,
        };
    }

    fn chooseAction(self: *const ScalarController, rng: std.Random) u8 {
        if (self.safe_n < 30) return @intCast(rng.intRangeLessThan(usize, 0, 3));
        const sp = @as(f32, @floatFromInt(self.safe_min + self.safe_max)) / 2.0;
        const cm: f32 = @floatFromInt(self.cur);
        var best: u8 = 0;
        var best_err: f32 = 1e9;
        for (0..3) |a| {
            const pred = cm + self.delta[a];
            if (@abs(pred - sp) < best_err) {
                best_err = @abs(pred - sp);
                best = @intCast(a);
            }
        }
        return best;
    }

    fn step(self: *ScalarController, env: *env_mod.Environment, rng: std.Random) bool {
        self.cur = agent_mod.featureValue(env.grid, self.feature);
        const action_idx = self.chooseAction(rng);

        // Track disagreement: in-range but about to fail?
        const in_range = self.safe_n > 30 and
            self.cur >= self.safe_min and self.cur <= self.safe_max;
        if (in_range) self.predicted_safe += 1;

        env.step(@enumFromInt(action_idx), rng);
        const failed = env.failed;
        if (failed and in_range) self.unexplained_fail += 1;

        const feat_next = agent_mod.featureValue(env.grid, self.feature);
        const d = @as(f32, @floatFromInt(feat_next)) - @as(f32, @floatFromInt(self.cur));
        self.dn[action_idx] += 1;
        const n: f32 = @floatFromInt(self.dn[action_idx]);
        self.delta[action_idx] += (d - self.delta[action_idx]) / n;
        if (!failed) {
            self.safe_min = @min(self.safe_min, feat_next);
            self.safe_max = @max(self.safe_max, feat_next);
            self.safe_n += 1;
        }
        return failed;
    }

    fn disagreeRate(self: *const ScalarController) f64 {
        if (self.predicted_safe == 0) return 0.0;
        return @as(f64, @floatFromInt(self.unexplained_fail)) / @as(f64, @floatFromInt(self.predicted_safe));
    }
};

// Run a feature probe across multiple seeds, return mean fail/1k.
// Multiple seeds eliminates the "bad probe seed" variance that caused wrong switches.
fn probeFeature(f: FeatureKind, params: env_mod.TaskParams, n_steps: usize, base_seed: u64) struct { fail_per_1k: f64, disagree: f64 } {
    const N_PROBE_SEEDS = 4;
    var total_fails: f64 = 0;
    var total_disagree: f64 = 0;
    for (0..N_PROBE_SEEDS) |s| {
        const seed = base_seed +% @as(u64, s) *% 0x4567;
        var ctrl = ScalarController.init(f);
        var env = env_mod.Environment.initWith(params);
        var rng = std.Random.DefaultPrng.init(seed);
        var fails: u32 = 0;
        for (0..n_steps) |_| { if (ctrl.step(&env, rng.random())) fails += 1; }
        total_fails += @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
        total_disagree += ctrl.disagreeRate();
    }
    return .{
        .fail_per_1k = total_fails / N_PROBE_SEEDS,
        .disagree = total_disagree / N_PROBE_SEEDS,
    };
}

// The adaptive agent: starts with sum, watches for disagreement, then searches.
const AdaptiveAgent = struct {
    ctrl: ScalarController,
    params: env_mod.TaskParams,
    phase: enum { warmup, assess, search, commit },
    warmup_fails: u32,
    warmup_steps: u32,
    search_seed: u64,
    best_search_feat: FeatureKind,
    best_search_fail: f64,
    log: *std.io.AnyWriter,

    fn init(params: env_mod.TaskParams, seed: u64, log: *std.io.AnyWriter) AdaptiveAgent {
        return .{
            .ctrl = ScalarController.init(.sum),
            .params = params,
            .phase = .warmup,
            .warmup_fails = 0,
            .warmup_steps = 0,
            .search_seed = seed,
            .best_search_feat = .sum,
            .best_search_fail = 1e9,
            .log = log,
        };
    }

    // Run n_steps total. Returns (fails, feature_switches, final_feature).
    fn run(self: *AdaptiveAgent, n_steps: usize, seed: u64) !struct { fails: u32, switched: bool, final_feat: FeatureKind } {
        var env = env_mod.Environment.initWith(self.params);
        var rng = std.Random.DefaultPrng.init(seed);
        var total_fails: u32 = 0;
        var switched = false;

        const WARMUP: usize = 3000;
        const DISAGREE_THRESHOLD: f64 = 0.03;
        const PROBE_STEPS: usize = 10_000; // fixed: 2000 was too short (exploration noise dominated)

        for (0..n_steps) |step| {
            // Phase transition logic
            if (step == WARMUP and self.phase == .warmup) {
                self.phase = .assess;
                const dr = self.ctrl.disagreeRate();
                try self.log.print("  [step {d}] WARMUP done. disagree_rate={d:.3} ({d}/{d}) fail/1k={d:.1}\n", .{
                    step, dr, self.ctrl.unexplained_fail, self.ctrl.predicted_safe,
                    @as(f64, @floatFromInt(self.warmup_fails)) / @as(f64, @floatFromInt(WARMUP)) * 1000.0,
                });
                if (dr > DISAGREE_THRESHOLD) {
                    self.phase = .search;
                    try self.log.print("  [step {d}] DISAGREEMENT HIGH ({d:.3} > {d:.3}) -- triggering autonomous feature search\n", .{
                        step, dr, DISAGREE_THRESHOLD,
                    });
                    // Run probes for each feature (brief trial)
                    for (all_features) |f| {
                        const probe = probeFeature(f, self.params, PROBE_STEPS, self.search_seed);
                        try self.log.print("    probe feat={s:<12}: fail/1k={d:6.2} disagree={d:.3}\n", .{
                            @tagName(f), probe.fail_per_1k, probe.disagree,
                        });
                        if (probe.fail_per_1k < self.best_search_fail) {
                            self.best_search_fail = probe.fail_per_1k;
                            self.best_search_feat = f;
                        }
                    }
                    // Switch to best discovered feature
                    if (self.best_search_feat != .sum) {
                        try self.log.print("  [step {d}] SWITCHING feature: sum -> {s} (probe fail/1k={d:.2})\n", .{
                            step, @tagName(self.best_search_feat), self.best_search_fail,
                        });
                        self.ctrl = ScalarController.init(self.best_search_feat);
                        switched = true;
                    } else {
                        try self.log.print("  [step {d}] search found sum is best -- staying with sum\n", .{step});
                    }
                    self.phase = .commit;
                } else {
                    try self.log.print("  [step {d}] disagreement OK ({d:.3} <= {d:.3}) -- keeping sum\n", .{
                        step, dr, DISAGREE_THRESHOLD,
                    });
                    self.phase = .commit;
                }
            }

            if (self.ctrl.step(&env, rng.random())) {
                total_fails += 1;
                if (step < WARMUP) self.warmup_fails += 1;
            }
            if (step < WARMUP) self.warmup_steps += 1;
        }
        return .{ .fails = total_fails, .switched = switched, .final_feat = self.ctrl.feature };
    }
};

pub fn main() !void {
    var out_writer = std.io.getStdOut().writer();
    var log_writer = out_writer.any();
    const out = std.io.getStdOut().writer();

    const n_steps: usize = 60_000; // warmup(3k) + probes(5 feats x 10k = 50k) + commit phase
    const seeds = [_]u64{ 0xABC1, 0xDEF2, 0x1234, 0xF00D, 0xBEEF };

    const dual_band = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };

    try out.print("=== ADAPTIVE FEATURE DISCOVERY: self-directed model repair ===\n\n", .{});
    try out.print("Agent starts with feature=sum. Detects model disagreement.\n", .{});
    try out.print("If disagree_rate > 0.08: runs autonomous feature search and switches.\n", .{});
    try out.print("Task: DUAL_BAND (sum insufficient -- reference: sum=83.31, left_mass=39.02)\n\n", .{});

    var total_fails: f64 = 0;
    var n_switched: usize = 0;
    for (seeds, 0..) |seed, i| {
        try out.print("--- seed {d} ---\n", .{i});
        var ag = AdaptiveAgent.init(dual_band, seed +% 0x42, &log_writer);
        const result = try ag.run(n_steps, seed);
        const fail_1k = @as(f64, @floatFromInt(result.fails)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
        total_fails += fail_1k;
        if (result.switched) n_switched += 1;
        try out.print("  RESULT: fail/1k={d:.2} switched={} final_feat={s}\n\n", .{
            fail_1k, result.switched, @tagName(result.final_feat),
        });
    }
    try out.print("=== SUMMARY ===\n", .{});
    try out.print("  mean fail/1k: {d:.2} ({d}/{d} seeds switched feature)\n", .{
        total_fails / @as(f64, @floatFromInt(seeds.len)), n_switched, seeds.len,
    });
    try out.print("  reference:    sum=83.31, left_mass=39.02, thermostat=83.33\n", .{});
    try out.print("\nIf mean < 39.02 AND seeds switched: adaptive discovery works.\n", .{});
    try out.print("If mean ≈ 39.02: agent discovers left_mass but doesn't improve on it.\n", .{});
    try out.print("If mean ≈ 83: disagreement signal failed to trigger useful search.\n", .{});
}
