const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

// =============================================================================
// asi_attempt — generalization harness
//
// "Intelligence" is the gap between train and HELD-OUT performance. The main
// eval (eval.zig) trains and tests on one regime, so it cannot see that gap.
// This harness trains the model-based controller on a TRAIN regime, FREEZES what
// it learned, and drops it cold into held-out regimes it never saw. For each
// regime it reports three numbers:
//
//   rest_floor : failures/1k of the trivial `always rest` policy on that regime
//                (how hard the regime is on its own).
//   transfer   : the TRAIN-trained, frozen agent, zero-shot on the regime.
//   oracle     : an agent trained directly ON that regime (adaptation ceiling).
//
// transfer near oracle  => the competence generalised.
// transfer near rest_floor (or worse) => it memorised the train regime.
// =============================================================================

const Regime = struct { name: []const u8, params: env_mod.TaskParams };

fn failPer1k(failures: u64, steps: usize) f64 {
    return @as(f64, @floatFromInt(failures)) / @as(f64, @floatFromInt(steps)) * 1000.0;
}

// Fixed-policy failure rate on a regime (no learning).
fn runFixed(allocator: std.mem.Allocator, params: env_mod.TaskParams, action: env_mod.Action, n: usize, seed: u64) !f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var env = env_mod.Environment.initWith(params);
    var agent = try agent_mod.Agent.init(allocator, rand, .{
        .action_mode = .fixed, .fixed_action = action, .enable_learning = false, .enable_macros = false, .enable_meta = false,
    }, &env);
    defer agent.deinit();
    var failures: u64 = 0;
    for (0..n) |_| {
        if (agent.step(&env, rand).failed) failures += 1;
    }
    return failPer1k(failures, n);
}

// Train the greedy mb_safety controller on `train_params`, freeze it, then
// measure failures over `eval_n` steps on `test_params`.
fn trainThenEval(allocator: std.mem.Allocator, train_params: env_mod.TaskParams, test_params: env_mod.TaskParams, train_n: usize, eval_n: usize, seed: u64) !f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var train_env = env_mod.Environment.initWith(train_params);
    var agent = try agent_mod.Agent.init(allocator, rand, .{
        .action_mode = .mb_safety, .enable_learning = true, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
    }, &train_env);
    defer agent.deinit();

    for (0..train_n) |_| _ = agent.step(&train_env, rand);

    agent.cfg.enable_learning = false; // freeze rules + prototypes
    var test_env = env_mod.Environment.initWith(test_params);
    agent.beginEpisode(&test_env);

    var failures: u64 = 0;
    for (0..eval_n) |_| {
        if (agent.step(&test_env, rand).failed) failures += 1;
    }
    return failPer1k(failures, eval_n);
}

fn meanFixed(allocator: std.mem.Allocator, params: env_mod.TaskParams, n: usize, seeds: usize) !f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| acc += try runFixed(allocator, params, .rest, n, @as(u64, s) + 1);
    return acc / @as(f64, @floatFromInt(seeds));
}

fn meanTrainEval(allocator: std.mem.Allocator, tr: env_mod.TaskParams, te: env_mod.TaskParams, train_n: usize, eval_n: usize, seeds: usize) !f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| acc += try trainThenEval(allocator, tr, te, train_n, eval_n, @as(u64, s) + 1);
    return acc / @as(f64, @floatFromInt(seeds));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var train_n: usize = 10000;
    var eval_n: usize = 4000;
    var seeds: usize = 5;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    if (args.next()) |a| train_n = std.fmt.parseInt(usize, a, 10) catch train_n;
    if (args.next()) |a| eval_n = std.fmt.parseInt(usize, a, 10) catch eval_n;
    if (args.next()) |a| seeds = std.fmt.parseInt(usize, a, 10) catch seeds;

    const train_regime = env_mod.TaskParams{}; // the regime the agent learns on
    const regimes = [_]Regime{
        .{ .name = "train (default)", .params = .{} },
        .{ .name = "faster_shocks", .params = .{ .shock_period = 250 } },
        .{ .name = "bigger_shocks", .params = .{ .shock_mag = 6 } }, // >= threshold: shocks lethal
        .{ .name = "tight_threshold", .params = .{ .fail_threshold = 4 } },
        .{ .name = "stochastic", .params = .{ .noise_prob = 0.05, .noise_mag = 2 } },
        .{ .name = "homeostatic", .params = .{ .min_mass = 16, .max_mass = 48, .shock_period = 0, .volatility_after = 1_000_000 } }, // two-sided band, disturbances off
    };

    std.debug.print("=== generalization: train {d} / eval {d} x {d} seeds ===\n", .{ train_n, eval_n, seeds });
    std.debug.print("(agent trained on 'train (default)', frozen, dropped cold into each regime)\n\n", .{});
    std.debug.print("  {s:<18} | {s:>10} | {s:>10} | {s:>10}\n", .{ "regime", "rest_floor", "transfer", "oracle" });
    std.debug.print("  -------------------+------------+------------+-----------\n", .{});

    for (regimes) |rg| {
        const rest_floor = try meanFixed(allocator, rg.params, eval_n, seeds);
        const transfer = try meanTrainEval(allocator, train_regime, rg.params, train_n, eval_n, seeds);
        const oracle = try meanTrainEval(allocator, rg.params, rg.params, train_n, eval_n, seeds);
        std.debug.print("  {s:<18} | {d:>10.2} | {d:>10.2} | {d:>10.2}\n", .{ rg.name, rest_floor, transfer, oracle });
    }

    std.debug.print("\nReading: transfer<=oracle and < rest_floor => generalises. transfer~rest_floor\n", .{});
    std.debug.print("or >> oracle => the competence did not transfer to that regime.\n", .{});
}
