//! EXP-8 / C19: multi-step planning vs greedy mb_mass on the homeostatic band.
//! Focused harness — same protocol as eval.zig [BAND] block (15000 steps × 6 seeds).

const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

const RunStats = struct {
    fail_per_1k: f64,
    mean_mass: f64,
};

fn runPolicyPMeanSeeds(allocator: std.mem.Allocator, params: env_mod.TaskParams, cfg: agent_mod.Config, n_steps: usize, seeds: usize) !RunStats {
    var acc_fail: f64 = 0;
    var acc_mass: f64 = 0;
    for (0..seeds) |s| {
        var prng = std.Random.DefaultPrng.init(@as(u64, s) + 1);
        const rand = prng.random();
        var env = env_mod.Environment.initWith(params);
        var agent = try agent_mod.Agent.init(allocator, rand, cfg, &env);
        defer agent.deinit();
        var failures: u64 = 0;
        var mass_sum: u64 = 0;
        for (0..n_steps) |_| {
            const r = agent.step(&env, rand);
            if (r.failed) failures += 1;
            mass_sum += r.grid_mass;
        }
        const nf: f64 = @floatFromInt(n_steps);
        acc_fail += @as(f64, @floatFromInt(failures)) / nf * 1000.0;
        acc_mass += @as(f64, @floatFromInt(mass_sum)) / nf;
    }
    const sf: f64 = @floatFromInt(seeds);
    return .{ .fail_per_1k = acc_fail / sf, .mean_mass = acc_mass / sf };
}

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const n_steps: usize = 15000;
    const seeds: usize = 6;
    const band = env_mod.TaskParams{ .min_mass = 16, .max_mass = 48, .shock_period = 0, .volatility_after = 1_000_000 };

    std.debug.print("=== EXP-8 planning probe: {d} steps x {d} seeds ===\n\n", .{ n_steps, seeds });
    std.debug.print("  {s:<22} | {s:>9} | {s:>9}\n", .{ "policy", "fail/1k", "mean_mass" });
    std.debug.print("  ----------------------+-----------+-----------\n", .{});

    const greedy = try runPolicyPMeanSeeds(allocator, band, .{
        .action_mode = .mb_mass, .enable_macros = false, .enable_meta = false, .epsilon = 0.0,
    }, n_steps, seeds);
    std.debug.print("  {s:<22} | {d:>9.2} | {d:>9.3}\n", .{ "mb_mass (greedy)", greedy.fail_per_1k, greedy.mean_mass });

    const plan_depths = [_]u8{ 1, 3, 5 };
    var best_plan: f64 = 1e9;
    var best_h: u8 = 0;
    for (plan_depths) |h| {
        const st = try runPolicyPMeanSeeds(allocator, band, .{
            .action_mode = .mb_plan, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .plan_horizon = h,
        }, n_steps, seeds);
        var label: [24]u8 = undefined;
        const name = try std.fmt.bufPrint(&label, "mb_plan H={d}", .{h});
        std.debug.print("  {s:<22} | {d:>9.2} | {d:>9.3}\n", .{ name, st.fail_per_1k, st.mean_mass });
        if (st.fail_per_1k < best_plan) {
            best_plan = st.fail_per_1k;
            best_h = h;
        }
    }

    // Grid-tune thermostat (same search as eval.zig E1 block).
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
    std.debug.print("  {s:<22} | {d:>9.2} |  (grid-tuned)\n", .{ "thermostat(best)", best_t });
    std.debug.print("\n  best thermostat: {d:.2} (charge<={d}, high>={d}, high={s})\n", .{
        best_t, best_cb, best_ra, if (best_rest) "rest" else "discharge",
    });
    std.debug.print("  best planning:   H={d} at {d:.2} fail/1k\n", .{ best_h, best_plan });
    std.debug.print("  greedy mb_mass:  {d:.2} fail/1k\n", .{greedy.fail_per_1k});

    const beats_greedy = best_plan < greedy.fail_per_1k;
    std.debug.print("\n  planning beats greedy? {s}\n", .{if (beats_greedy) "YES" else "NO"});
    std.debug.print("  VERDICT: {s}\n", .{if (beats_greedy) "PASS" else "FAIL"});
}