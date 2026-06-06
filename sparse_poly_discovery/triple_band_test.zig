//! Triple-band task: sum + left_mass + right_mass all simultaneously constrained.
//! Tests whether the discovered pair (left_mass, max_cell) scales to 3 constraints,
//! or whether a triplet feature set is needed.
//!
//! Also runs exhaustive TRIPLET search to find the best 3-feature controller.
//!
//! Run: zig build triple-band-test

const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

const FeatureKind = agent_mod.FeatureKind;

fn runPair(allocator: std.mem.Allocator, f1: FeatureKind, f2: FeatureKind,
           params: env_mod.TaskParams, n: usize, seed: u64) !f64 {
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
    for (0..n) |_| if (ag.step(&env, rng.random()).failed) { fails += 1; };
    return @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n)) * 1000.0;
}

fn meanPair(allocator: std.mem.Allocator, f1: FeatureKind, f2: FeatureKind,
            params: env_mod.TaskParams, n: usize, ns: usize) !f64 {
    var total: f64 = 0;
    for (0..ns) |s| total += try runPair(allocator, f1, f2, params, n, 0xABC0 +% @as(u64, s) *% 0x9E37);
    return total / @as(f64, @floatFromInt(ns));
}

// A minimal 3-feature scalar controller that minimizes total out-of-band violation
// across three features simultaneously.
const Ctrl3 = struct {
    f: [3]FeatureKind,
    cur: [3]u32,
    delta: [3][3]f32,  // [feature][action]
    dn: [3]u32,
    safe_min: [3]u32,
    safe_max: [3]u32,
    safe_n: [3]u32,

    fn init(f0: FeatureKind, f1: FeatureKind, f2: FeatureKind) Ctrl3 {
        return .{
            .f = .{ f0, f1, f2 },
            .cur = .{ 0, 0, 0 },
            .delta = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 0 } },
            .dn = .{ 0, 0, 0 },
            .safe_min = .{ std.math.maxInt(u32), std.math.maxInt(u32), std.math.maxInt(u32) },
            .safe_max = .{ 0, 0, 0 },
            .safe_n = .{ 0, 0, 0 },
        };
    }

    fn chooseAction(self: *const Ctrl3, rng: std.Random) u8 {
        // random if any feature hasn't converged yet
        for (0..3) |fi| if (self.safe_n[fi] < 30) return @intCast(rng.intRangeLessThan(usize, 0, 3));
        var best: u8 = 0;
        var best_err: f32 = 1e18;
        for (0..3) |a| {
            var total_err: f32 = 0;
            for (0..3) |fi| {
                const sp = @as(f32, @floatFromInt(self.safe_min[fi] + self.safe_max[fi])) / 2.0;
                const pred = @as(f32, @floatFromInt(self.cur[fi])) + self.delta[fi][a];
                total_err += @abs(pred - sp);
            }
            if (total_err < best_err) { best_err = total_err; best = @intCast(a); }
        }
        return best;
    }

    fn step(self: *Ctrl3, env: *env_mod.Environment, rng: std.Random) bool {
        const prev_failed = env.failed;
        for (0..3) |fi| self.cur[fi] = agent_mod.featureValue(env.grid, self.f[fi]);
        const action_idx = self.chooseAction(rng);
        env.step(@enumFromInt(action_idx), rng);
        const failed = env.failed;
        if (!prev_failed) {
            for (0..3) |fi| {
                const next_val = agent_mod.featureValue(env.grid, self.f[fi]);
                const d = @as(f32, @floatFromInt(next_val)) - @as(f32, @floatFromInt(self.cur[fi]));
                self.dn[action_idx] += 1;
                const n: f32 = @floatFromInt(self.dn[action_idx]);
                self.delta[fi][action_idx] += (d - self.delta[fi][action_idx]) / n;
                if (!failed) {
                    self.safe_min[fi] = @min(self.safe_min[fi], next_val);
                    self.safe_max[fi] = @max(self.safe_max[fi], next_val);
                    self.safe_n[fi] += 1;
                }
            }
        }
        return failed;
    }
};

fn runTriplet(f0: FeatureKind, f1: FeatureKind, f2: FeatureKind,
              params: env_mod.TaskParams, n: usize, seed: u64) f64 {
    var ctrl = Ctrl3.init(f0, f1, f2);
    var env = env_mod.Environment.initWith(params);
    var rng = std.Random.DefaultPrng.init(seed);
    var fails: u32 = 0;
    for (0..n) |_| if (ctrl.step(&env, rng.random())) { fails += 1; };
    return @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n)) * 1000.0;
}

fn meanTriplet(f0: FeatureKind, f1: FeatureKind, f2: FeatureKind,
               params: env_mod.TaskParams, n: usize, ns: usize) f64 {
    var total: f64 = 0;
    for (0..ns) |s| {
        total += runTriplet(f0, f1, f2, params, n, 0xABC0 +% @as(u64, s) *% 0x9E37);
    }
    return total / @as(f64, @floatFromInt(ns));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const n: usize = 8_000;
    const ns: usize = 6;

    // Triple-band: sum [16,48] + left_mass [6,22] + right_mass [6,22]
    const triple = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .min_right_mass = 6, .max_right_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };
    // Dual-band for reference
    const dual = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };

    try out.print("=== TRIPLE-BAND TEST ({d} steps x {d} seeds) ===\n\n", .{ n, ns });
    try out.print("Task: sum[16,48] + left_mass[6,22] + right_mass[6,22]\n", .{});
    try out.print("Question: does (left_mass,max_cell)=0.25 on dual-band survive a third constraint?\n\n", .{});

    // Reference on dual-band
    const dual_ref = try meanPair(alloc, .left_mass, .max_cell, dual, n, ns);
    try out.print("--- Reference ---\n", .{});
    try out.print("  (left_mass,max_cell) on DUAL-BAND:   {d:.2} fail/1k\n", .{dual_ref});

    // Best dual-band pair on triple-band
    try out.print("\n--- Dual-band pairs on TRIPLE-BAND ---\n", .{});
    const pairs = [_][2]FeatureKind{
        .{ .left_mass, .max_cell },
        .{ .left_mass, .right_mass },
        .{ .sum, .left_mass },
        .{ .sum, .max_cell },
    };
    for (pairs) |p| {
        const r = try meanPair(alloc, p[0], p[1], triple, n, ns);
        try out.print("  ({s},{s}): {d:.2} fail/1k\n", .{ @tagName(p[0]), @tagName(p[1]), r });
    }

    // Exhaustive triplet search
    try out.print("\n--- Exhaustive triplet search on TRIPLE-BAND ---\n", .{});
    const feats = [_]FeatureKind{ .sum, .left_mass, .right_mass, .max_cell, .nonzero_count };
    var best_r: f64 = 1e9;
    var best_f0 = feats[0];
    var best_f1 = feats[1];
    var best_f2 = feats[2];

    for (0..feats.len) |i| {
        for (i+1..feats.len) |j| {
            for (j+1..feats.len) |k| {
                const r = meanTriplet(feats[i], feats[j], feats[k], triple, n, ns);
                try out.print("  triplet({s},{s},{s}): {d:.2} fail/1k\n", .{
                    @tagName(feats[i]), @tagName(feats[j]), @tagName(feats[k]), r,
                });
                if (r < best_r) { best_r = r; best_f0 = feats[i]; best_f1 = feats[j]; best_f2 = feats[k]; }
            }
        }
    }
    try out.print("=> BEST TRIPLET: ({s},{s},{s}) = {d:.2} fail/1k\n\n",
        .{ @tagName(best_f0), @tagName(best_f1), @tagName(best_f2), best_r });

    try out.print("=== VERDICT ===\n", .{});
    const pair_on_triple = try meanPair(alloc, .left_mass, .max_cell, triple, n, ns);
    try out.print("  (left_mass,max_cell) on TRIPLE-BAND: {d:.2} fail/1k\n", .{pair_on_triple});
    try out.print("  Best triplet:                        {d:.2} fail/1k\n", .{best_r});
    if (pair_on_triple < 5.0) {
        try out.print("  PAIR SURVIVES: (left_mass,max_cell) handles 3 constraints without modification.\n", .{});
    } else if (best_r < 5.0) {
        try out.print("  PAIR FAILS, TRIPLET SUCCEEDS: adding a 3rd feature is necessary.\n", .{});
        try out.print("  The right triplet: ({s},{s},{s})\n", .{ @tagName(best_f0), @tagName(best_f1), @tagName(best_f2) });
    } else {
        try out.print("  BOTH FAIL: triple-band may be fundamentally harder than dual-band.\n", .{});
    }
}
