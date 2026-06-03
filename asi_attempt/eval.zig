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
    return runPolicyP(allocator, .{}, cfg, n_steps, seed);
}

fn runPolicyP(allocator: std.mem.Allocator, params: env_mod.TaskParams, cfg: agent_mod.Config, n_steps: usize, seed: u64) !RunStats {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var env = env_mod.Environment.initWith(params);
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

fn runPolicyPMeanSeeds(allocator: std.mem.Allocator, params: env_mod.TaskParams, cfg: agent_mod.Config, n_steps: usize, seeds: usize) !RunStats {
    var acc = RunStats{ .fail_per_1k = 0, .mean_mass = 0, .err_early = 0, .err_late = 0 };
    for (0..seeds) |s| {
        const st = try runPolicyP(allocator, params, cfg, n_steps, @as(u64, s) + 1);
        acc.fail_per_1k += st.fail_per_1k;
        acc.mean_mass += st.mean_mass;
        acc.err_early += st.err_early;
        acc.err_late += st.err_late;
    }
    const sf: f64 = @floatFromInt(seeds);
    return .{ .fail_per_1k = acc.fail_per_1k / sf, .mean_mass = acc.mean_mass / sf, .err_early = acc.err_early / sf, .err_late = acc.err_late / sf };
}

// Hand-coded thermostat: charge when total mass is near the floor, otherwise rest.
// A state-dependent (non-constant) policy. If THIS can hold the band, the task is
// solvable and the learned controller's failure is a real failure, not an
// unsolvable regime (cf. bigger_shocks, where every policy ties at the lethal floor).
fn thermostatMeanSeeds(params: env_mod.TaskParams, n_steps: usize, seeds: usize) f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| {
        var prng = std.Random.DefaultPrng.init(@as(u64, s) + 1);
        const rand = prng.random();
        var env = env_mod.Environment.initWith(params);
        var failures: u64 = 0;
        for (0..n_steps) |_| {
            var mass: u32 = 0;
            for (env.grid) |c| mass += c;
            // charge up near the floor, dump (rest) near the ceiling, else bleed (discharge).
            const action: env_mod.Action = blk: {
                if (mass <= params.min_mass + 4) break :blk .charge;
                if (params.max_mass > 0 and mass >= params.max_mass - 4) break :blk .rest;
                break :blk .discharge;
            };
            env.step(action, rand);
            if (env.failed) failures += 1;
        }
        acc += @as(f64, @floatFromInt(failures)) / @as(f64, @floatFromInt(n_steps)) * 1000.0;
    }
    return acc / @as(f64, @floatFromInt(seeds));
}

// A tunable 3-branch thermostat: charge below `charge_below`, dump above
// `high_above` (rest = fast -16, or discharge = gentle -1), else bleed (discharge).
// Used to grid-tune the BEST hand-coded baseline and check mb_mass isn't a strawman win.
fn thermostatTuned(params: env_mod.TaskParams, charge_below: u32, high_above: u32, rest_high: bool, n_steps: usize, seeds: usize) f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| {
        var prng = std.Random.DefaultPrng.init(@as(u64, s) + 1);
        const rand = prng.random();
        var env = env_mod.Environment.initWith(params);
        var failures: u64 = 0;
        for (0..n_steps) |_| {
            var mass: u32 = 0;
            for (env.grid) |c| mass += c;
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

    // --- CP3: does removing the 0.25 repulsion floor in rule learning improve
    // CONTROL, not just prediction? dynamics_probe showed pure attraction cuts
    // forward-model error 5.4x in isolation. Here we run the full mb_safety
    // controller stock vs pure at the greedy (eps=0, headline competence) and
    // exploratory (eps=0.02, 0.10) operating points. err_l/err_e show whether the
    // prediction-error drop reproduces inside the agent; fail/1k shows whether it
    // converts to control.
    std.debug.print("\n[CP3] stock repulsion vs pure attraction (mb_safety, clean):\n", .{});
    std.debug.print("  {s:<22} | {s:>9} | {s:>9} | {s:>8} | {s:>8}\n", .{ "policy", "fail/1k", "mean_mass", "err_e", "err_l" });
    std.debug.print("  ----------------------+-----------+-----------+----------+---------\n", .{});
    const cp3_eps = [_]f32{ 0.0, 0.02, 0.10 };
    for (cp3_eps) |eps| {
        var name_stock: [32]u8 = undefined;
        var name_pure: [32]u8 = undefined;
        printRow(try std.fmt.bufPrint(&name_stock, "stock  eps={d:.2}", .{eps}), try runPolicyMeanSeeds(allocator, .{
            .action_mode = .mb_safety, .enable_macros = false, .enable_meta = false, .epsilon = eps, .pure_attraction = false,
        }, n_steps, seeds));
        printRow(try std.fmt.bufPrint(&name_pure, "pure   eps={d:.2}", .{eps}), try runPolicyMeanSeeds(allocator, .{
            .action_mode = .mb_safety, .enable_macros = false, .enable_meta = false, .epsilon = eps, .pure_attraction = true,
        }, n_steps, seeds));
    }

    // --- BAND: the non-trivial task (Q0) ---------------------------------------
    // The default cell is trivially solved by `always rest` (0.00). Here a
    // homeostatic FLOOR (min_mass) makes the task two-sided: rest under-charges,
    // charge over-charges, so NO constant policy can hold the band. This is the
    // task on which "competence" is finally measurable above trivial. We report:
    //   (1) every constant policy (must all fail => task is non-trivial),
    //   (2) a hand-coded thermostat (must succeed => task is SOLVABLE),
    //   (3) the learned greedy mb_safety controller (does it discover control?),
    //   (4) CP3 re-tested here: with a task that NEEDS the model, does prediction
    //       accuracy finally couple to control?
    // Disturbances off: shocks/volatility were an accidental mass source that let a
    // constant `discharge` hold the band. With them off the band is a clean,
    // deterministic two-sided homeostasis task no constant policy can hold.
    const band = env_mod.TaskParams{ .min_mass = 16, .max_mass = 48, .shock_period = 0, .volatility_after = 1_000_000 };
    std.debug.print("\n[BAND] homeostatic band [{d},{d}], disturbances off (no constant policy can hold it):\n", .{ band.min_mass, band.max_mass });
    std.debug.print("  {s:<22} | {s:>9} | {s:>9} | {s:>8} | {s:>8}\n", .{ "policy", "fail/1k", "mean_mass", "err_e", "err_l" });
    std.debug.print("  ----------------------+-----------+-----------+----------+---------\n", .{});
    printRow("const_random", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .random, .enable_learning = false, .enable_macros = false, .enable_meta = false,
    }, n_steps, seeds));
    inline for (.{ .rest, .charge, .discharge }) |act| {
        printRow("const_" ++ @tagName(act), try runPolicyPMeanSeeds(allocator, band, .{
            .action_mode = .fixed, .fixed_action = act, .enable_learning = false, .enable_macros = false, .enable_meta = false,
        }, n_steps, seeds));
    }
    std.debug.print("  ----------------------+-----------+-----------+----------+---------\n", .{});
    std.debug.print("  {s:<22} | {d:>9.2} |  (hand-coded state-dependent baseline => task is solvable)\n", .{
        "thermostat", thermostatMeanSeeds(band, n_steps, seeds),
    });
    printRow("learned mb_safety", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_safety, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
    }, n_steps, seeds));
    printRow("learned mb_surprise", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_surprise, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
    }, n_steps, seeds));
    printRow("CP3 stock (repulsion)", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_safety, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .pure_attraction = false,
    }, n_steps, seeds));
    printRow("CP3 pure (no floor)", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_safety, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .pure_attraction = true,
    }, n_steps, seeds));
    // Ordinal encoding: inject METRIC structure into the value fillers so total mass
    // (a sum/threshold) becomes readable. The closure-principle escape in the control
    // domain — does it push the learned agent below the hand-coded thermostat (20.80)?
    std.debug.print("  - - - ordinal (metric) value encoding - - -\n", .{});
    printRow("ordinal stock", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_safety, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .ordinal_encoding = true,
    }, n_steps, seeds));
    printRow("ordinal + pure", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_safety, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .pure_attraction = true, .ordinal_encoding = true,
    }, n_steps, seeds));
    // The explicit out-of-closure generator: a learned scalar mass readout (SUM +
    // threshold, outside the XOR closure). Same agent, one nonlinear feature added.
    // Does it match/beat the hand-coded thermostat (20.80)?
    std.debug.print("  - - - nonlinear mass readout (out-of-closure) - - -\n", .{});
    printRow("mb_mass learned", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
    }, n_steps, seeds));
    printRow("mb_mass eps=0.02", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.02,
    }, n_steps, seeds));
    // Discovery: can a generic feature search FIND the out-of-closure generator?
    // Run mb_mass over candidate aggregate features; keep whichever controls best.
    // If 'sum' wins and the decoys fail, the system discovered the sum autonomously
    // (selection-level) rather than being told to use total mass.
    std.debug.print("  - - - feature search (which aggregate enables control?) - - -\n", .{});
    const feats = [_]agent_mod.FeatureKind{ .sum, .max_cell, .first_cell, .nonzero_count, .left_mass, .right_mass };
    var best_feat: agent_mod.FeatureKind = .sum;
    var best_fail: f64 = 1e9;
    for (feats) |f| {
        const st = try runPolicyPMeanSeeds(allocator, band, .{
            .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = f,
        }, n_steps, seeds);
        var name: [40]u8 = undefined;
        printRow(try std.fmt.bufPrint(&name, "feat={s}", .{@tagName(f)}), st);
        if (st.fail_per_1k < best_fail) {
            best_fail = st.fail_per_1k;
            best_feat = f;
        }
    }
    std.debug.print("  => feature search SELECTS '{s}' ({d:.2} fail/1k) as the controlling feature\n", .{ @tagName(best_feat), best_fail });

    // E1 (honesty check): did mb_mass (11.02) beat a STRAWMAN thermostat? Grid-tune
    // the hand-coded baseline over both thresholds and structure; report the best.
    std.debug.print("  - - - E1: grid-tuned thermostat (is mb_mass a strawman win?) - - -\n", .{});
    var best_t: f64 = 1e9;
    var best_cb: u32 = 0;
    var best_ra: u32 = 0;
    var best_rest = true;
    const cbs = [_]u32{ 14, 16, 18, 20, 22, 24 };
    const ras = [_]u32{ 28, 32, 36, 40, 44, 47 };
    for (cbs) |cb| for (ras) |ra| {
        if (ra <= cb) continue;
        for ([_]bool{ true, false }) |rh| {
            const f = thermostatTuned(band, cb, ra, rh, n_steps, seeds);
            if (f < best_t) {
                best_t = f;
                best_cb = cb;
                best_ra = ra;
                best_rest = rh;
            }
        }
    };
    std.debug.print("  best thermostat: {d:.2} fail/1k (charge<={d}, high>={d}, high-action={s})  vs  mb_mass 11.02\n", .{ best_t, best_cb, best_ra, if (best_rest) "rest" else "discharge" });
    if (best_t < 11.02) {
        std.debug.print("  => a tuned hand-coded thermostat BEATS mb_mass -- the 'learned beats hand-coded' win was a STRAWMAN.\n", .{});
    } else {
        std.debug.print("  => mb_mass (11.02) still beats the best grid-tuned thermostat -- the win survives.\n", .{});
    }

    // E2: does H-step planning over the learned scalar model beat greedy mb_mass,
    // or close the gap to the tuned thermostat (0.00)?
    std.debug.print("  - - - E2: planning (lookahead) vs greedy mb_mass - - -\n", .{});
    printRow("mb_plan H=4", try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_plan, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
    }, n_steps, seeds));

    // E3: is the control fragile to STOCHASTIC dynamics? Inject per-step noise.
    const band_noisy = env_mod.TaskParams{ .min_mass = 16, .max_mass = 48, .shock_period = 0, .volatility_after = 1_000_000, .noise_prob = 0.05, .noise_mag = 2 };
    std.debug.print("  - - - E3: stochastic band (noise_prob=0.05) -- is control fragile? - - -\n", .{});
    std.debug.print("  {s:<22} | {d:>9.2} |  (best tuned thermostat under noise)\n", .{ "thermostat(best)+noise", thermostatTuned(band_noisy, best_cb, best_ra, best_rest, n_steps, seeds) });
    printRow("mb_mass + noise", try runPolicyPMeanSeeds(allocator, band_noisy, .{
        .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
    }, n_steps, seeds));
    printRow("mb_plan + noise", try runPolicyPMeanSeeds(allocator, band_noisy, .{
        .action_mode = .mb_plan, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
    }, n_steps, seeds));

    // --- DUAL_BAND: task where SUM readout is insufficient (#21) ------------------
    // Band on total mass [16,48] AND left-half mass [6,22] simultaneously.
    // A single-feature mb_mass(sum) can regulate total mass but not left_mass.
    // A single-feature mb_mass(left_mass) can regulate left_mass but not total mass.
    // Neither single feature is sufficient: the task genuinely needs 2D readout.
    // Tests: does feature-search DISCOVER the limits? Which single feature is better?
    // (Seeding: total_mass=32 → each cell=2 → left_mass=16 ∈ [6,22] ✓)
    const dual_band = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };
    std.debug.print("\n[DUAL_BAND] total_mass∈[{d},{d}] AND left_mass∈[{d},{d}] (#21: sum insufficient):\n", .{
        dual_band.min_mass, dual_band.max_mass, dual_band.min_left_mass, dual_band.max_left_mass,
    });
    std.debug.print("  {s:<22} | {s:>9} | {s:>9} | {s:>8} | {s:>8}\n", .{ "policy", "fail/1k", "mean_mass", "err_e", "err_l" });
    std.debug.print("  ----------------------+-----------+-----------+----------+---------\n", .{});
    std.debug.print("  {s:<22} | {d:>9.2} |  (thermostat: sum-only, does it hold both constraints?)\n", .{
        "thermostat(sum)", thermostatMeanSeeds(dual_band, n_steps, seeds),
    });
    printRow("mb_mass(sum)", try runPolicyPMeanSeeds(allocator, dual_band, .{
        .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = .sum,
    }, n_steps, seeds));
    printRow("mb_mass(left_mass)", try runPolicyPMeanSeeds(allocator, dual_band, .{
        .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = .left_mass,
    }, n_steps, seeds));
    printRow("mb_mass(right_mass)", try runPolicyPMeanSeeds(allocator, dual_band, .{
        .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = .right_mass,
    }, n_steps, seeds));
    std.debug.print("  - - - feature search on DUAL_BAND (any single feature work?) - - -\n", .{});
    const dual_feats = [_]agent_mod.FeatureKind{ .sum, .max_cell, .left_mass, .right_mass, .nonzero_count };
    var best_dual: agent_mod.FeatureKind = .sum;
    var best_dual_fail: f64 = 1e9;
    for (dual_feats) |f| {
        const st = try runPolicyPMeanSeeds(allocator, dual_band, .{
            .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = f,
        }, n_steps, seeds);
        var name: [40]u8 = undefined;
        printRow(try std.fmt.bufPrint(&name, "feat={s}", .{@tagName(f)}), st);
        if (st.fail_per_1k < best_dual_fail) {
            best_dual_fail = st.fail_per_1k;
            best_dual = f;
        }
    }
    std.debug.print("  => best single feature on DUAL_BAND: '{s}' ({d:.2} fail/1k)\n", .{ @tagName(best_dual), best_dual_fail });
    std.debug.print("     Baseline (BAND single-feature): 11.02 fail/1k. Does DUAL_BAND need 2D readout?\n", .{});

    // 2D mb_mass: the predicted fix for dual-band.
    // Tracks BOTH features, picks actions minimizing total violation of both constraints.
    std.debug.print("  - - - 2D controller: mb_mass2(sum+left_mass) -- predicted fix - - -\n", .{});
    printRow("mb_mass2(sum,left)", try runPolicyPMeanSeeds(allocator, dual_band, .{
        .action_mode = .mb_mass2, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
        .feature = .sum, .feature2 = .left_mass,
    }, n_steps, seeds));
    printRow("mb_mass2(sum,right)", try runPolicyPMeanSeeds(allocator, dual_band, .{
        .action_mode = .mb_mass2, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
        .feature = .sum, .feature2 = .right_mass,
    }, n_steps, seeds));
    printRow("mb_mass2(left,right)", try runPolicyPMeanSeeds(allocator, dual_band, .{
        .action_mode = .mb_mass2, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
        .feature = .left_mass, .feature2 = .right_mass,
    }, n_steps, seeds));

    // Pair feature discovery: search over all pairs (i,j) of FeatureKinds on dual_band.
    // Can the system automatically find that (sum, left_mass) is the best pair?
    std.debug.print("  - - - pair feature discovery: which feature pair best controls DUAL_BAND? - - -\n", .{});
    const pair_feats = [_]agent_mod.FeatureKind{ .sum, .max_cell, .left_mass, .right_mass };
    var best_pair_f1 = pair_feats[0];
    var best_pair_f2 = pair_feats[1];
    var best_pair_fail: f64 = 1e9;
    for (pair_feats) |f1| {
        for (pair_feats) |f2| {
            if (f1 == f2) continue;
            const st = try runPolicyPMeanSeeds(allocator, dual_band, .{
                .action_mode = .mb_mass2, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
                .feature = f1, .feature2 = f2,
            }, n_steps, seeds);
            var name: [50]u8 = undefined;
            printRow(try std.fmt.bufPrint(&name, "pair({s},{s})", .{ @tagName(f1), @tagName(f2) }), st);
            if (st.fail_per_1k < best_pair_fail) {
                best_pair_fail = st.fail_per_1k;
                best_pair_f1 = f1;
                best_pair_f2 = f2;
            }
        }
    }
    std.debug.print("  => BEST PAIR: ({s},{s}) at {d:.2} fail/1k\n", .{ @tagName(best_pair_f1), @tagName(best_pair_f2), best_pair_fail });
    std.debug.print("     Prediction: (sum,left_mass) should win. Did it?\n", .{});

    // Model disagreement: how often does the 1D agent (sum) predict safe but fail?
    // This is the "can you see the ceiling" test -- does the agent detect its own blindspot?
    std.debug.print("  - - - model disagreement: does sum-agent detect its own blindspot? - - -\n", .{});
    {
        var disagree_prng = std.Random.DefaultPrng.init(0xDEAD);
        var ag = try agent_mod.Agent.init(allocator, disagree_prng.random(), .{
            .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = .sum,
        }, &env_mod.Environment.initWith(dual_band));
        defer ag.deinit();
        var env = env_mod.Environment.initWith(dual_band);
        var rng = std.Random.DefaultPrng.init(0xDEAD);
        for (0..n_steps) |_| _ = ag.step(&env, rng.random());
        const disagree_rate: f64 = if (ag.predicted_safe_n > 0)
            @as(f64, @floatFromInt(ag.unexplained_fail_n)) / @as(f64, @floatFromInt(ag.predicted_safe_n))
        else 0.0;
        std.debug.print("  predicted_safe={d}  unexplained_fail={d}  disagreement_rate={d:.3}\n", .{
            ag.predicted_safe_n, ag.unexplained_fail_n, disagree_rate,
        });
        std.debug.print("  Reading: high disagreement = model provably wrong; agent CAN detect the blindspot\n", .{});
        std.debug.print("  if disagreement_rate >> 0 => sum model is representationally wrong for dual-band\n", .{});
    }
}
