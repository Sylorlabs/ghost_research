//! Macro-action discovery: can the agent discover USEFUL COMPOUND ACTIONS
//! (temporal primitives) that single-step actions can't match?
//!
//! Background: the dual-band task (total_mass + left_mass constraint) defeats all
//! single-feature 1D controllers. A 2D controller (mb_mass2) can solve it by tracking
//! both features. But can an agent WITHOUT knowing which features matter discover that
//! certain ACTION SEQUENCES are more useful than single steps?
//!
//! The experiment: define a macro action space of k-step sequences {charge×2,
//! discharge×2, rest×2, charge+rest, discharge+rest, rest+charge}. A macro-mb_mass
//! agent learns the expected feature-delta for each macro (not each primitive action)
//! and picks the macro with the best predicted outcome.
//!
//! Key question: does the macro that is optimal for the dual-band task correspond
//! to a sequence that "single-step greedy" would never pick?
//!
//! Run: zig build macro-discover

const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

const Action = env_mod.Action;

// A macro is a fixed 2-step action sequence.
const Macro = struct {
    name: []const u8,
    steps: [2]Action,
};

const macros = [_]Macro{
    .{ .name = "charge+charge", .steps = .{ .charge, .charge } },
    .{ .name = "discharge+discharge", .steps = .{ .discharge, .discharge } },
    .{ .name = "rest+rest", .steps = .{ .rest, .rest } },
    .{ .name = "charge+rest", .steps = .{ .charge, .rest } },
    .{ .name = "discharge+rest", .steps = .{ .discharge, .rest } },
    .{ .name = "rest+charge", .steps = .{ .rest, .charge } },
    .{ .name = "rest+discharge", .steps = .{ .rest, .discharge } },
    .{ .name = "charge+discharge", .steps = .{ .charge, .discharge } },
    .{ .name = "discharge+charge", .steps = .{ .discharge, .charge } },
};

const N_MACROS = macros.len;

const MacroAgent = struct {
    // Learned mean 2-step delta for each feature per macro
    sum_delta: [N_MACROS]f32,
    left_delta: [N_MACROS]f32,
    sum_dn: [N_MACROS]u32,
    left_dn: [N_MACROS]u32,

    // Learned safe range for sum and left_mass
    safe_sum_min: u32,
    safe_sum_max: u32,
    safe_left_min: u32,
    safe_left_max: u32,
    safe_n: u32,

    // Tracking for model disagreement
    predicted_safe: u32,
    unexplained_fail: u32,

    fn init() MacroAgent {
        return .{
            .sum_delta = [_]f32{0} ** N_MACROS,
            .left_delta = [_]f32{0} ** N_MACROS,
            .sum_dn = [_]u32{0} ** N_MACROS,
            .left_dn = [_]u32{0} ** N_MACROS,
            .safe_sum_min = std.math.maxInt(u32),
            .safe_sum_max = 0,
            .safe_left_min = std.math.maxInt(u32),
            .safe_left_max = 0,
            .safe_n = 0,
            .predicted_safe = 0,
            .unexplained_fail = 0,
        };
    }

    fn sumMass(grid: [16]u8) u32 {
        var s: u32 = 0;
        for (grid) |c| s += c;
        return s;
    }

    fn leftMass(grid: [16]u8) u32 {
        var s: u32 = 0;
        for (grid[0..8]) |c| s += c;
        return s;
    }

    fn chooseMacro(self: *MacroAgent, grid: [16]u8, rng: std.Random) usize {
        if (self.safe_n < 50) return rng.intRangeLessThan(usize, 0, N_MACROS);
        const sp_sum = @as(f32, @floatFromInt(self.safe_sum_min + self.safe_sum_max)) / 2.0;
        const sp_left = @as(f32, @floatFromInt(self.safe_left_min + self.safe_left_max)) / 2.0;
        const lo_sum: f32 = @floatFromInt(self.safe_sum_min);
        const hi_sum: f32 = @floatFromInt(self.safe_sum_max);
        const lo_left: f32 = @floatFromInt(self.safe_left_min);
        const hi_left: f32 = @floatFromInt(self.safe_left_max);
        const cs: f32 = @floatFromInt(sumMass(grid));
        const cl: f32 = @floatFromInt(leftMass(grid));
        var best: usize = 0;
        var best_cost: f32 = 1e9;
        for (0..N_MACROS) |m| {
            const ps = cs + self.sum_delta[m];
            const pl = cl + self.left_delta[m];
            const es: f32 = if (ps < lo_sum) (lo_sum - ps) else if (ps > hi_sum) (ps - hi_sum) else 0;
            const el: f32 = if (pl < lo_left) (lo_left - pl) else if (pl > hi_left) (pl - hi_left) else 0;
            const c = (@abs(ps - sp_sum) + @abs(pl - sp_left)) * 0.01;
            if (es + el + c < best_cost) {
                best_cost = es + el + c;
                best = m;
            }
        }
        return best;
    }

    fn runStep(self: *MacroAgent, env: *env_mod.Environment, rng: std.Random) bool {
        const sum_before = sumMass(env.grid);
        const left_before = leftMass(env.grid);
        const macro_idx = self.chooseMacro(env.grid, rng);

        // Track model disagreement before executing
        if (self.safe_n > 50) {
            const in_range = (sum_before >= self.safe_sum_min and sum_before <= self.safe_sum_max and
                left_before >= self.safe_left_min and left_before <= self.safe_left_max);
            if (in_range) self.predicted_safe += 1;
        }

        // Execute 2-step macro
        var any_fail = false;
        for (macros[macro_idx].steps) |act| {
            env.step(act, rng);
            if (env.failed) { any_fail = true; break; }
        }

        if (any_fail and self.safe_n > 50) {
            const was_predicted_safe = (sum_before >= self.safe_sum_min and sum_before <= self.safe_sum_max and
                left_before >= self.safe_left_min and left_before <= self.safe_left_max);
            if (was_predicted_safe) self.unexplained_fail += 1;
        }

        const sum_after = sumMass(env.grid);
        const left_after = leftMass(env.grid);

        // Update delta estimates
        const ds = @as(f32, @floatFromInt(sum_after)) - @as(f32, @floatFromInt(sum_before));
        self.sum_dn[macro_idx] += 1;
        const ns: f32 = @floatFromInt(self.sum_dn[macro_idx]);
        self.sum_delta[macro_idx] += (ds - self.sum_delta[macro_idx]) / ns;

        const dl = @as(f32, @floatFromInt(left_after)) - @as(f32, @floatFromInt(left_before));
        self.left_dn[macro_idx] += 1;
        const nl: f32 = @floatFromInt(self.left_dn[macro_idx]);
        self.left_delta[macro_idx] += (dl - self.left_delta[macro_idx]) / nl;

        if (!any_fail) {
            self.safe_sum_min = @min(self.safe_sum_min, sum_after);
            self.safe_sum_max = @max(self.safe_sum_max, sum_after);
            self.safe_left_min = @min(self.safe_left_min, left_after);
            self.safe_left_max = @max(self.safe_left_max, left_after);
            self.safe_n += 1;
        }

        return any_fail;
    }
};

fn runMacroAgent(params: env_mod.TaskParams, n_steps: usize, seed: u64) struct { fail_per_1k: f64, best_macro: usize, disagree_rate: f64 } {
    var env = env_mod.Environment.initWith(params);
    var ag = MacroAgent.init();
    var rng = std.Random.DefaultPrng.init(seed);
    var fails: u32 = 0;
    // Each "step" is one macro (2 actions), so n_steps macros = 2*n_steps primitive steps
    for (0..n_steps) |_| {
        if (ag.runStep(&env, rng.random())) fails += 1;
    }
    // Find which macro got chosen most often in the last phase (use sum_dn as proxy)
    var best_m: usize = 0;
    var best_use: u32 = 0;
    for (0..N_MACROS) |m| {
        if (ag.sum_dn[m] > best_use) { best_use = ag.sum_dn[m]; best_m = m; }
    }
    const dr: f64 = if (ag.predicted_safe > 0)
        @as(f64, @floatFromInt(ag.unexplained_fail)) / @as(f64, @floatFromInt(ag.predicted_safe))
    else 0.0;
    return .{
        .fail_per_1k = @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n_steps)) * 1000.0,
        .best_macro = best_m,
        .disagree_rate = dr,
    };
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    const n_steps: usize = 5000;
    const seeds: usize = 5;

    const dual_band = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };
    const band = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .shock_period = 0, .volatility_after = 1_000_000,
    };

    try out.print("=== MACRO-ACTION DISCOVERY: temporal primitives for dual-band control ===\n\n", .{});
    try out.print("Each macro is a 2-step action sequence. The agent learns expected (sum_delta,\n", .{});
    try out.print("left_delta) per macro and picks the macro minimizing total out-of-band violation.\n\n", .{});

    // Baseline: single-action (k=1 macros = primitive actions) on dual-band
    try out.print("Task: DUAL_BAND (total_mass[16,48] + left_mass[6,22])\n", .{});
    try out.print("  (reference: thermostat=83.33, mb_mass(sum)=83.31, mb_mass(left)=39.02 fail/1k)\n\n", .{});
    try out.print("  macro agent results ({d} seeds x {d} steps each):\n", .{ seeds, n_steps });
    try out.print("  seed | fail/1k | best-macro                | disagree-rate\n", .{});
    try out.print("  -----+---------+---------------------------+--------------\n", .{});
    var total_fail: f64 = 0;
    for (0..seeds) |s| {
        const r = runMacroAgent(dual_band, n_steps, 0xABC0 +% @as(u64, s) *% 0x9E3779B9);
        total_fail += r.fail_per_1k;
        try out.print("  {d:<4} | {d:7.2} | {s:<25} | {d:.3}\n", .{
            s, r.fail_per_1k, macros[r.best_macro].name, r.disagree_rate,
        });
    }
    try out.print("  mean | {d:7.2} |\n\n", .{ total_fail / @as(f64, @floatFromInt(seeds)) });

    // What macro deltas did the agent learn?
    try out.print("Learned macro deltas (last seed -- what the agent's model says about each macro):\n", .{});
    try out.print("  macro                | sum_delta | left_delta | uses\n", .{});
    try out.print("  ---------------------+-----------+------------+------\n", .{});
    {
        var env = env_mod.Environment.initWith(dual_band);
        var ag = MacroAgent.init();
        var rng = std.Random.DefaultPrng.init(0xABC4);
        for (0..n_steps) |_| _ = ag.runStep(&env, rng.random());
        for (0..N_MACROS) |m| {
            try out.print("  {s:<20} | {d:9.3} | {d:10.3} | {d}\n", .{
                macros[m].name, ag.sum_delta[m], ag.left_delta[m], ag.sum_dn[m],
            });
        }
    }

    // Same agent on single-band (no left_mass constraint) for comparison
    try out.print("\nTask: single BAND (total_mass[16,48] only -- for reference)\n", .{});
    var band_fail: f64 = 0;
    for (0..seeds) |s| {
        const r = runMacroAgent(band, n_steps, 0xABC0 +% @as(u64, s) *% 0x9E3779B9);
        band_fail += r.fail_per_1k;
    }
    try out.print("  macro agent: {d:.2} fail/1k  (ref: mb_mass(sum) 11.02, thermostat 0.00)\n\n", .{ band_fail / @as(f64, @floatFromInt(seeds)) });

    try out.print("Reading: if macro-agent on dual_band << 39.02 (best 1D), macro discovery helps.\n", .{});
    try out.print("The disagreement rate reveals whether the agent detects its own blindspots.\n", .{});
    try out.print("The best-macro column shows which compound action the agent learned to prefer.\n", .{});
}
