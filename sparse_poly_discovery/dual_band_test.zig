//! Quick test: 2D mb_mass controller and pair feature discovery on dual-band.
//! Faster standalone version of the DUAL_BAND eval section.
//! Run: zig build dual-band-test
const std = @import("std");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

fn runPolicy(allocator: std.mem.Allocator, params: env_mod.TaskParams, cfg: agent_mod.Config, n: usize, seed: u64) !f64 {
    var env = env_mod.Environment.initWith(params);
    var rng = std.Random.DefaultPrng.init(seed);
    var ag = try agent_mod.Agent.init(allocator, rng.random(), cfg, &env);
    defer ag.deinit();
    var fails: u32 = 0;
    for (0..n) |_| {
        const r = ag.step(&env, rng.random());
        if (r.failed) fails += 1;
    }
    return @as(f64, @floatFromInt(fails)) / @as(f64, @floatFromInt(n)) * 1000.0;
}

fn mean(allocator: std.mem.Allocator, params: env_mod.TaskParams, cfg: agent_mod.Config, n: usize, n_seeds: usize) !f64 {
    var total: f64 = 0;
    for (0..n_seeds) |s| {
        total += try runPolicy(allocator, params, cfg, n, 0xABC0 +% @as(u64, s) *% 0x9E37);
    }
    return total / @as(f64, @floatFromInt(n_seeds));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const n: usize = 5000;
    const s: usize = 4;
    const dual = env_mod.TaskParams{
        .min_mass = 16, .max_mass = 48,
        .min_left_mass = 6, .max_left_mass = 22,
        .shock_period = 0, .volatility_after = 1_000_000,
    };

    try out.print("=== DUAL_BAND 2D CONTROLLER TEST ({d} steps x {d} seeds) ===\n", .{ n, s });
    try out.print("  policy               | fail/1k\n", .{});
    try out.print("  ---------------------+---------\n", .{});
    try out.print("  ref: thermostat      |   83.33  (from main eval)\n", .{});
    try out.print("  ref: mb_mass(sum)    |   83.31\n", .{});
    try out.print("  ref: mb_mass(left)   |   39.02  <- best single feature\n", .{});
    try out.print("  ref: mb_mass(max)    |  115.92  <- nonlinear (order-stat) decoy\n", .{});
    try out.print("  ---------------------+---------\n", .{});

    // C21 focal: obvious 2-feature (sum + nonlinear max) — sum alone is insufficient.
    const r_sum_max = try mean(alloc, dual, .{ .action_mode = .mb_mass2, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = .sum, .feature2 = .max_cell }, n, s);
    try out.print("  mb_mass2(sum,max)    | {d:7.2}  <- (sum,max) variant (sum+nonlinear)\n", .{r_sum_max});

    const r1 = try mean(alloc, dual, .{ .action_mode = .mb_mass2, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = .sum, .feature2 = .left_mass }, n, s);
    try out.print("  mb_mass2(sum,left)   | {d:7.2}  <- predicted fix\n", .{r1});

    const r2 = try mean(alloc, dual, .{ .action_mode = .mb_mass2, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = .sum, .feature2 = .right_mass }, n, s);
    try out.print("  mb_mass2(sum,right)  | {d:7.2}\n", .{r2});

    const r3 = try mean(alloc, dual, .{ .action_mode = .mb_mass2, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = .left_mass, .feature2 = .right_mass }, n, s);
    try out.print("  mb_mass2(left,right) | {d:7.2}\n", .{r3});

    try out.print("\n--- pair feature search (all (i,j)) ---\n", .{});
    const feats = [_]agent_mod.FeatureKind{ .sum, .left_mass, .right_mass, .max_cell };
    var best_r: f64 = 1e9;
    var best_f1 = feats[0];
    var best_f2 = feats[1];
    for (feats) |f1| {
        for (feats) |f2| {
            if (f1 == f2) continue;
            const r = try mean(alloc, dual, .{ .action_mode = .mb_mass2, .enable_macros = false, .enable_meta = false, .epsilon = 0.0, .feature = f1, .feature2 = f2 }, n, s);
            try out.print("  pair({s},{s}) | {d:.2}\n", .{ @tagName(f1), @tagName(f2), r });
            if (r < best_r) { best_r = r; best_f1 = f1; best_f2 = f2; }
        }
    }
    try out.print("=> BEST PAIR: ({s},{s}) = {d:.2} fail/1k\n", .{ @tagName(best_f1), @tagName(best_f2), best_r });
}
