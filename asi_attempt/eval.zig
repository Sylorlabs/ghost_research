const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

// =============================================================================
// asi_attempt — evaluation harness
//
// The original project had NO evaluation: it ran a real-time daemon, pushed
// telemetry to a dashboard, and never answered "does the agent actually control
// the battery cell?". This harness answers it with reproducible numbers.
//
// Environment recap (environment.zig): a 16-cell ion grid. `charge` piles mass
// toward the anode, `discharge` moves it toward the cathode and drains the top,
// `rest` decays every cell by 1. Any cell >= 5 is a dendrite short-circuit =
// FAILURE (the cell auto-resets the following tick). Scheduled shocks every 500
// steps; volatility after step 750. The control objective is to AVOID failure.
//
// Primary metric: failures per 1000 steps (lower = better control).
// Secondary:      mean grid mass (lower = more safety margin).
// Learning check: mean prediction error in the first vs last decile of the run.
// =============================================================================

const RunStats = struct {
    fail_per_1k: f64,
    mean_mass: f64,
    err_early: f64,
    err_late: f64,
};

fn runPolicy(allocator: std.mem.Allocator, cfg: agent_mod.Config, n_steps: usize, seed: u64) !RunStats {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var env = env_mod.Environment.init();
    var agent = try agent_mod.Agent.init(allocator, rand, cfg, &env);
    defer agent.deinit();

    var failures: u64 = 0;
    var mass_sum: u64 = 0;

    const decile = @max(n_steps / 10, 1);
    var err_early_sum: f64 = 0;
    var err_late_sum: f64 = 0;

    for (0..n_steps) |i| {
        const r = agent.step(&env, rand);
        if (r.failed) failures += 1;
        mass_sum += r.grid_mass;
        if (i < decile) err_early_sum += r.prediction_error;
        if (i >= n_steps - decile) err_late_sum += r.prediction_error;
    }

    const nf: f64 = @floatFromInt(n_steps);
    const df: f64 = @floatFromInt(decile);
    return .{
        .fail_per_1k = @as(f64, @floatFromInt(failures)) / nf * 1000.0,
        .mean_mass = @as(f64, @floatFromInt(mass_sum)) / nf,
        .err_early = err_early_sum / df,
        .err_late = err_late_sum / df,
    };
}

fn runPolicyMeanSeeds(allocator: std.mem.Allocator, cfg: agent_mod.Config, n_steps: usize, seeds: usize) !RunStats {
    var acc = RunStats{ .fail_per_1k = 0, .mean_mass = 0, .err_early = 0, .err_late = 0 };
    for (0..seeds) |s| {
        const st = try runPolicy(allocator, cfg, n_steps, @as(u64, s) + 1);
        acc.fail_per_1k += st.fail_per_1k;
        acc.mean_mass += st.mean_mass;
        acc.err_early += st.err_early;
        acc.err_late += st.err_late;
    }
    const sf: f64 = @floatFromInt(seeds);
    return .{
        .fail_per_1k = acc.fail_per_1k / sf,
        .mean_mass = acc.mean_mass / sf,
        .err_early = acc.err_early / sf,
        .err_late = acc.err_late / sf,
    };
}

fn printRow(label: []const u8, st: RunStats) void {
    std.debug.print("  {s:<22} | {d:>9.2} | {d:>9.3} | {d:>8.3} | {d:>8.3}\n", .{
        label, st.fail_per_1k, st.mean_mass, st.err_early, st.err_late,
    });
}

// Q5: how often does the safest action coincide with the most-predictable
// (lowest-surprise) action? Acts by safety; records agreement each step once the
// agent has experience. Tests the active-inference premise that minimising
// surprise keeps you in preferred (safe) states.
fn runQ5(allocator: std.mem.Allocator, n_steps: usize, seed: u64) !f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var env = env_mod.Environment.init();
    var agent = try agent_mod.Agent.init(allocator, rand, .{
        .action_mode = .mb_safety,
        .enable_macros = false,
        .enable_meta = false,
        .epsilon = 0.05,
    }, &env);
    defer agent.deinit();

    var agree: u64 = 0;
    var counted: u64 = 0;
    for (0..n_steps) |i| {
        if (i > n_steps / 4) { // only after the model has warmed up
            const s_act = agent.probeSafetyAction();
            const u_act = agent.probeSurpriseAction();
            if (s_act == u_act) agree += 1;
            counted += 1;
        }
        _ = agent.step(&env, rand);
    }
    if (counted == 0) return 0;
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(counted)) * 100.0;
}

const ActionRun = struct {
    fail_per_1k: f64,
    frac: [3]f64, // charge, discharge, rest
};

fn runActions(allocator: std.mem.Allocator, cfg: agent_mod.Config, n_steps: usize, seed: u64) !ActionRun {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var env = env_mod.Environment.init();
    var agent = try agent_mod.Agent.init(allocator, rand, cfg, &env);
    defer agent.deinit();

    var failures: u64 = 0;
    var counts = [_]u64{ 0, 0, 0 };
    for (0..n_steps) |_| {
        const r = agent.step(&env, rand);
        if (r.failed) failures += 1;
        counts[r.action] += 1;
    }
    const nf: f64 = @floatFromInt(n_steps);
    return .{
        .fail_per_1k = @as(f64, @floatFromInt(failures)) / nf * 1000.0,
        .frac = .{
            @as(f64, @floatFromInt(counts[0])) / nf,
            @as(f64, @floatFromInt(counts[1])) / nf,
            @as(f64, @floatFromInt(counts[2])) / nf,
        },
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // CLI: eval [n_steps] [seeds]
    var n_steps: usize = 15000;
    var seeds: usize = 6;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // exe name
    if (args.next()) |a| n_steps = std.fmt.parseInt(usize, a, 10) catch n_steps;
    if (args.next()) |a| seeds = std.fmt.parseInt(usize, a, 10) catch seeds;

    std.debug.print("=== asi_attempt evaluation: {d} steps x {d} seeds ===\n\n", .{ n_steps, seeds });
    std.debug.print("  {s:<22} | {s:>9} | {s:>9} | {s:>8} | {s:>8}\n", .{ "policy", "fail/1k", "mean_mass", "err_e", "err_l" });
    std.debug.print("  ----------------------+-----------+-----------+----------+---------\n", .{});

    // --- Baselines (no learning, fixed/random policies) ---
    printRow("baseline_random", try runPolicyMeanSeeds(allocator, .{
        .action_mode = .random, .enable_learning = false, .enable_macros = false, .enable_meta = false,
    }, n_steps, seeds));
    printRow("baseline_rest", try runPolicyMeanSeeds(allocator, .{
        .action_mode = .fixed, .fixed_action = .rest, .enable_learning = false, .enable_macros = false, .enable_meta = false,
    }, n_steps, seeds));
    printRow("baseline_discharge", try runPolicyMeanSeeds(allocator, .{
        .action_mode = .fixed, .fixed_action = .discharge, .enable_learning = false, .enable_macros = false, .enable_meta = false,
    }, n_steps, seeds));
    printRow("baseline_charge", try runPolicyMeanSeeds(allocator, .{
        .action_mode = .fixed, .fixed_action = .charge, .enable_learning = false, .enable_macros = false, .enable_meta = false,
    }, n_steps, seeds));

    std.debug.print("  ----------------------+-----------+-----------+----------+---------\n", .{});

    // --- The as-built architecture: perceptual learning + RANDOM actions + macros + meta ---
    printRow("as_built", try runPolicyMeanSeeds(allocator, .{
        .action_mode = .random, .enable_learning = true, .enable_macros = true, .enable_meta = true,
    }, n_steps, seeds));

    // --- Model-based control variants ---
    printRow("mb_surprise", try runPolicyMeanSeeds(allocator, .{
        .action_mode = .mb_surprise, .enable_learning = true, .enable_macros = false, .enable_meta = false,
    }, n_steps, seeds));
    printRow("mb_safety (clean)", try runPolicyMeanSeeds(allocator, .{
        .action_mode = .mb_safety, .enable_learning = true, .enable_macros = false, .enable_meta = false,
    }, n_steps, seeds));
    printRow("mb_safety +macros", try runPolicyMeanSeeds(allocator, .{
        .action_mode = .mb_safety, .enable_learning = true, .enable_macros = true, .enable_meta = false,
    }, n_steps, seeds));
    printRow("mb_safety +macros+meta", try runPolicyMeanSeeds(allocator, .{
        .action_mode = .mb_safety, .enable_learning = true, .enable_macros = true, .enable_meta = true,
    }, n_steps, seeds));

    std.debug.print("\n", .{});

    // --- Q5: safety/surprise action agreement ---
    var q5_sum: f64 = 0;
    for (0..seeds) |s| q5_sum += try runQ5(allocator, n_steps, @as(u64, s) + 1);
    const q5 = q5_sum / @as(f64, @floatFromInt(seeds));
    std.debug.print("[Q5] safest action == lowest-surprise action: {d:.1}% of decisions\n", .{q5});
    std.debug.print("     (chance for 3 actions = 33.3%. >>33% => surprise tracks safety; ~33% => they are unrelated)\n", .{});

    // --- Follow-up E1: is the failure floor just exploration cost? ---
    // Sweep epsilon for the clean mb_safety controller. If failures collapse as
    // epsilon -> 0, the floor is the 10% random actions (incl. catastrophic charge),
    // not the controller. If they stay high, the controller/model is the limit.
    std.debug.print("\n[E1] mb_safety (clean) epsilon sweep:\n", .{});
    const epsilons = [_]f32{ 0.30, 0.10, 0.02, 0.0 };
    for (epsilons) |eps| {
        const st = try runPolicyMeanSeeds(allocator, .{
            .action_mode = .mb_safety, .enable_macros = false, .enable_meta = false, .epsilon = eps,
        }, n_steps, seeds);
        std.debug.print("     epsilon={d:.2} -> {d:>8.2} fail/1k   (mean_mass {d:.2})\n", .{ eps, st.fail_per_1k, st.mean_mass });
    }

    // --- Follow-up E2: does the controller LEARN that 'rest' is best? ---
    // Action histogram for the greedy controller, at the disrupted (0.02) and the
    // competent (0.00) regimes. Shows how a little exploration shifts the mix.
    std.debug.print("\n[E2] mb_safety (clean) action mix (optimal = ~100% rest):\n", .{});
    const e2_eps = [_]f32{ 0.02, 0.0 };
    const sf2: f64 = @floatFromInt(seeds);
    for (e2_eps) |eps| {
        var frac = [_]f64{ 0, 0, 0 };
        var e2_fail: f64 = 0;
        for (0..seeds) |s| {
            const ar = try runActions(allocator, .{
                .action_mode = .mb_safety, .enable_macros = false, .enable_meta = false, .epsilon = eps,
            }, n_steps, @as(u64, s) + 1);
            for (0..3) |k| frac[k] += ar.frac[k];
            e2_fail += ar.fail_per_1k;
        }
        std.debug.print("     epsilon={d:.2}: charge={d:.1}%  discharge={d:.1}%  rest={d:.1}%   ({d:.2} fail/1k)\n", .{
            eps, frac[0] / sf2 * 100.0, frac[1] / sf2 * 100.0, frac[2] / sf2 * 100.0, e2_fail / sf2,
        });
    }
}
