//! Prospective controller disagreement: a forward-looking feature selection approach.
//!
//! The insight from correlation_discover.zig: retrospective failure analysis misses
//! features that prevent failures via proactive action selection (max_cell has 0 OOR
//! at failure time but is the best pairing feature). No O(N) retrospective approach
//! can identify it.
//!
//! This experiment tries a PROSPECTIVE approach:
//!   Run N single-feature ScalarControllers simultaneously on the same environment.
//!   At each step, collect each controller's action recommendation.
//!   Count: how often does controller j CONTRADICT the primary controller (sum)?
//!
//! Hypothesis: the feature-controller that most often contradicts the primary
//! controller is tracking a constraint the primary misses. High disagreement =
//! different constraints are simultaneously active = that feature matters.
//!
//! If this correctly identifies max_cell as the best partner for left_mass,
//! then prospective disagreement succeeds where retrospective correlation failed.
//!
//! Run: zig build parallel-disagree

const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

const FeatureKind = agent_mod.FeatureKind;
const ALL_FEATURES = [_]FeatureKind{ .sum, .left_mass, .right_mass, .max_cell, .nonzero_count };
const N_FEATURES = ALL_FEATURES.len;

const ScalarCtrl = struct {
    feature: FeatureKind,
    cur: u32,
    delta: [3]f32,
    dn: [3]u32,
    safe_min: u32,
    safe_max: u32,
    safe_n: u32,
    prev_failed: bool,

    fn init(f: FeatureKind) ScalarCtrl {
        return .{
            .feature = f, .cur = 0,
            .delta = .{ 0, 0, 0 }, .dn = .{ 0, 0, 0 },
            .safe_min = std.math.maxInt(u32), .safe_max = 0, .safe_n = 0,
            .prev_failed = false,
        };
    }

    fn recommendAction(self: *const ScalarCtrl, rng: std.Random) u8 {
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

    fn observe(self: *ScalarCtrl, env: *const env_mod.Environment, action_idx: u8, failed: bool) void {
        const feat_next = agent_mod.featureValue(env.grid, self.feature);
        if (!self.prev_failed) {
            const d = @as(f32, @floatFromInt(feat_next)) - @as(f32, @floatFromInt(self.cur));
            self.dn[action_idx] += 1;
            const n: f32 = @floatFromInt(self.dn[action_idx]);
            self.delta[action_idx] += (d - self.delta[action_idx]) / n;
            if (!failed) {
                self.safe_min = @min(self.safe_min, feat_next);
                self.safe_max = @max(self.safe_max, feat_next);
                self.safe_n += 1;
            }
        }
        self.prev_failed = failed;
        self.cur = feat_next;
    }
};

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    const dual = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };

    const STEPS: usize = 8_000;
    const N_SEEDS: usize = 8;

    try out.print("=== PROSPECTIVE CONTROLLER DISAGREEMENT ===\n\n", .{});
    try out.print("Run {d} single-feature controllers simultaneously on DUAL_BAND.\n", .{N_FEATURES});
    try out.print("Primary controller: sum. Measure disagreement with each other controller.\n\n", .{});
    try out.print("Hypothesis: the controller that most often contradicts the primary\n", .{});
    try out.print("is tracking a constraint the primary misses — best candidate to add.\n\n", .{});

    // Accumulate disagreement counts across seeds
    var disagree_count: [N_FEATURES]u64 = [_]u64{0} ** N_FEATURES;
    var total_steps: u64 = 0;
    var fail_rate: [N_FEATURES]f64 = [_]f64{0} ** N_FEATURES;

    for (0..N_SEEDS) |s| {
        const seed = 0xABC0 +% @as(u64, s) *% 0x9E37;
        var env = env_mod.Environment.initWith(dual);
        var rng_main = std.Random.DefaultPrng.init(seed);
        var rng_ctrl: [N_FEATURES]std.Random.DefaultPrng = undefined;
        var ctrls: [N_FEATURES]ScalarCtrl = undefined;

        for (0..N_FEATURES) |fi| {
            ctrls[fi] = ScalarCtrl.init(ALL_FEATURES[fi]);
            ctrls[fi].cur = agent_mod.featureValue(env.grid, ALL_FEATURES[fi]);
            rng_ctrl[fi] = std.Random.DefaultPrng.init(seed +% @as(u64, fi) *% 0x1234);
        }

        var seed_fails: [N_FEATURES]u32 = [_]u32{0} ** N_FEATURES;

        for (0..STEPS) |_| {
            // Let primary (sum = index 0) choose the action
            const primary_action = ctrls[0].recommendAction(rng_main.random());

            // Apply primary's action to environment
            env.step(@enumFromInt(primary_action), rng_main.random());
            const failed = env.failed;

            // Count failures under this policy per-feature (for reference)
            if (failed) for (0..N_FEATURES) |fi| { seed_fails[fi] += 1; };

            // Collect what each controller WOULD have recommended
            // Count disagreement: different recommendation from primary
            for (0..N_FEATURES) |fi| {
                const rec = ctrls[fi].recommendAction(rng_ctrl[fi].random());
                if (rec != primary_action) disagree_count[fi] += 1;
                // All controllers observe the outcome and update their models
                ctrls[fi].observe(&env, primary_action, failed);
            }
            total_steps += 1;
        }

        for (0..N_FEATURES) |fi| {
            fail_rate[fi] += @as(f64, @floatFromInt(seed_fails[fi])) / @as(f64, @floatFromInt(STEPS)) * 1000.0;
        }
    }

    // Rank by disagreement rate with primary (sum)
    const total_f: f64 = @floatFromInt(total_steps);
    try out.print("--- Disagreement rate with primary controller (sum) ---\n", .{});
    try out.print("  feature        | disagree_rate | fail/1k (under sum policy)\n", .{});
    try out.print("  ---------------+---------------+---------------------------\n", .{});

    var ranked = [_]usize{0} ** N_FEATURES;
    for (0..N_FEATURES) |i| ranked[i] = i;
    for (1..N_FEATURES) |i| {
        var j = i;
        while (j > 0 and disagree_count[ranked[j]] > disagree_count[ranked[j-1]]) {
            const tmp = ranked[j]; ranked[j] = ranked[j-1]; ranked[j-1] = tmp;
            j -= 1;
        }
    }

    for (ranked) |fi| {
        const dr = @as(f64, @floatFromInt(disagree_count[fi])) / total_f;
        const fr = fail_rate[fi] / @as(f64, @floatFromInt(N_SEEDS));
        const top = fi == ranked[0] or fi == ranked[1];
        try out.print("  {s:<14} | {d:13.3} | {d:.2}{s}\n", .{
            @tagName(ALL_FEATURES[fi]), dr, fr,
            if (top) " <-- TOP" else "",
        });
    }

    const top1_fi = ranked[0];
    const top2_fi = ranked[1];
    try out.print("\n  Top-1 disagree: {s}\n", .{@tagName(ALL_FEATURES[top1_fi])});
    try out.print("  Top-2 disagree: {s}\n", .{@tagName(ALL_FEATURES[top2_fi])});
    try out.print("  => Disagreement-proposed pair: (sum, {s}) OR ({s}, {s})\n\n", .{
        @tagName(ALL_FEATURES[top1_fi]),
        @tagName(ALL_FEATURES[top1_fi]),
        @tagName(ALL_FEATURES[top2_fi]),
    });

    // Also: among features not=sum, rank the top-2 by disagreement with the PRIMARY
    // (not with each other) — these are the candidates to ADD to a sum-based controller
    try out.print("--- Non-sum features ranked by disagreement ---\n", .{});
    try out.print("    (candidates to ADD as second feature alongside sum)\n\n", .{});
    var best_nonsym_fi: usize = 0;
    var best_nonsym_count: u64 = 0;
    for (1..N_FEATURES) |fi| { // skip 0 = sum
        if (disagree_count[fi] > best_nonsym_count) {
            best_nonsym_count = disagree_count[fi];
            best_nonsym_fi = fi;
        }
    }
    try out.print("  Best non-sum candidate: {s} (disagree={d:.3})\n\n", .{
        @tagName(ALL_FEATURES[best_nonsym_fi]),
        @as(f64, @floatFromInt(best_nonsym_count)) / total_f,
    });

    try out.print("=== VERDICT ===\n", .{});
    const top1 = ALL_FEATURES[top1_fi];
    const top2 = ALL_FEATURES[top2_fi];
    const found = (top1 == .max_cell or top2 == .max_cell) or
                  (top1 == .left_mass or top2 == .left_mass);
    if (found) {
        try out.print("  max_cell or left_mass appear in top-2 disagreement features.\n", .{});
        try out.print("  Prospective disagreement correctly identifies relevant features.\n", .{});
    } else {
        try out.print("  NEGATIVE: top-2 disagreement features are ({s},{s}).\n",
            .{ @tagName(top1), @tagName(top2) });
        try out.print("  Neither max_cell nor left_mass appears — disagreement signal insufficient.\n", .{});
    }
    try out.print("\nKey question: does {s} or {s} disagree with sum MORE than nonzero_count?\n", .{
        @tagName(.max_cell), @tagName(.left_mass),
    });
    try out.print("If yes: prospective disagreement > retrospective correlation (which found nonzero_count).\n", .{});
}
