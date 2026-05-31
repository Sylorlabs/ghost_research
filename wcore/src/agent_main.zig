//! wcore-agent — compression- and empowerment-driven sensorimotor agents.
//!
//!   zig build run-agent                      # curiosity agent (Stage 1)
//!   zig build run-agent -- <seed> <steps> empower    # empowerment agent (Stage 2)
//!   zig build run-agent -- <seed> <steps> compare    # run both, compare self-enclosure
//!
//! The agent starts with ZERO knowledge of its world (dynamic, jittering
//! resources). Everything is logged to logs/wcore_agent_<seed>.log including
//! periodic ASCII maps. Honest expectations are stated in TESTING.md §9-10.

const std = @import("std");
const world = @import("world.zig");
const agent = @import("agent.zig");
const empower = @import("empower.zig");
const affordance = @import("affordance.zig");
const law = @import("law.zig");
const Logger = @import("logger.zig").Logger;

const DEFAULT_SEED: u64 = 0xC0FFEE;
const DEFAULT_STEPS: usize = 6000;
const DEFAULT_RESOURCES: usize = 14;
const JITTER_EVERY: usize = 5;
const REPORT_EVERY: usize = 1000;
const ROOM_SIZE: usize = 14;

const Mode = enum { curiosity, empower, compare, affordance, law };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const args = try std.process.argsAlloc(a);
    const seed = if (args.len >= 2) (parseU64(args[1]) orelse DEFAULT_SEED) else DEFAULT_SEED;
    const steps = if (args.len >= 3) (@as(usize, @intCast(parseU64(args[2]) orelse DEFAULT_STEPS))) else DEFAULT_STEPS;
    const mode: Mode = if (args.len >= 4) parseMode(args[3]) else .curiosity;

    const path = try std.fmt.allocPrint(a, "logs/wcore_agent_{x}.log", .{seed});
    var log = try Logger.initPath(path);
    defer log.deinit();

    try log.print("[SANDBOX] wcore-agent, seed=0x{x}, steps={d}, mode={s}; log -> {s}\n", .{ seed, steps, @tagName(mode), path });
    try log.writeAll("[SANDBOX] agent starts with ZERO knowledge of the world.\n");

    switch (mode) {
        .curiosity => {
            var grid = freshWorld(seed);
            const s = try agent.run(a, &grid, steps, JITTER_EVERY, REPORT_EVERY, &log);
            try reportCuriosity(&log, s);
        },
        .empower => {
            var grid = freshWorld(seed);
            const s = try empower.run(a, &grid, steps, JITTER_EVERY, REPORT_EVERY, &log);
            try reportEmpower(&log, s);
        },
        .compare => {
            try log.writeAll("\n##### CURIOSITY agent #####\n");
            var g1 = freshWorld(seed);
            const cs = try agent.run(a, &g1, steps, JITTER_EVERY, REPORT_EVERY, &log);
            try reportCuriosity(&log, cs);

            try log.writeAll("\n##### EMPOWERMENT agent (same world) #####\n");
            var g2 = freshWorld(seed);
            const es = try empower.run(a, &g2, steps, JITTER_EVERY, REPORT_EVERY, &log);
            try reportEmpower(&log, es);

            try log.writeAll("\n##### COMPARISON #####\n");
            try log.print("  walls built:      curiosity={d}   empowerment={d}\n", .{ cs.walls_built, es.walls_built });
            try log.print("  distinct frames:  curiosity={d}   empowerment={d}\n", .{ cs.distinct_obs, es.distinct_obs });
            if (es.walls_built < cs.walls_built) {
                try log.writeAll("  -> empowerment built FEWER walls: it avoided self-enclosure, as predicted.\n");
            } else {
                try log.writeAll("  -> empowerment did NOT reduce wall-building here (reported honestly).\n");
            }
        },
        .affordance => {
            try log.writeAll("\n##### RANDOM baseline (split button+gate room) #####\n");
            var g0 = freshRoom(seed);
            const rnd = affordance.runRandom(&g0, steps);

            try log.writeAll("\n##### EMPOWERMENT+VI, LOCAL 3x3 state (positions alias) #####\n");
            var g1 = freshRoom(seed);
            const loc = try affordance.run(a, &g1, steps, false, &log);

            try log.writeAll("\n##### EMPOWERMENT+VI, POSITIONAL state (de-aliased) #####\n");
            var g2 = freshRoom(seed);
            const pos = try affordance.run(a, &g2, steps, true, &log);

            try log.writeAll("\n##### DOES IT USE THE AFFORDANCE? #####\n");
            try log.print("  first press at step:   random={d}   local={d}   positional={d}   (of {d})\n", .{ rnd.first_press, loc.first_press, pos.first_press, steps });
            try log.print("  on-button occupancy:   random={d:.2}%   local={d:.2}%   positional={d:.2}%\n", .{ rnd.on_button_pct, loc.on_button_pct, pos.on_button_pct });
            try log.print("  time in unlocked half: random={d:.1}%   local={d:.1}%   positional={d:.1}%\n", .{ rnd.far_half_pct, loc.far_half_pct, pos.far_half_pct });
            if (pos.pressed and pos.far_half_pct > 10.0) {
                try log.print("  -> POSITIONAL agent is GOAL-DIRECTED: it pressed the button to unlock the\n", .{});
                try log.print("     gate and then spent {d:.0}% of its time in the region it unlocked —\n", .{pos.far_half_pct});
                try log.writeAll("     purposeful manipulation of an affordance to expand its world.\n");
            } else {
                try log.writeAll("  -> positional agent did not clearly use the affordance here (reported honestly).\n");
            }
            try log.writeAll("  -> Two ingredients were BOTH necessary (honest diagnosis):\n");
            try log.writeAll("     (1) a de-aliased state (position) — local 3x3 views alias positions, so\n");
            try log.writeAll("         the LOCAL agent cannot reliably navigate (it is seed-dependent);\n");
            try log.writeAll("     (2) R-max optimistic exploration — so value iteration PLANS toward the\n");
            try log.writeAll("         unknown instead of relying on a lucky random walk to find the button.\n");
        },
        .law => {
            try log.writeAll("\n##### LAW DISCOVERY: distil the world's causal rule from experience #####\n");
            var grid = freshRoom(seed);
            grid.gate_momentary = true; // so the gate's law is richly sampled
            const data = try law.collect(a, &grid, @max(steps, 30000));
            const discovered = try law.induce(a, data, &log);

            try log.writeAll("[LAW] discovered rule:  gate is open  <=>  ");
            try discovered.pred.write(&log);
            try log.print("   (errors: {d}/{d})\n", .{ discovered.errors, data.len });

            // honest compression check: the rule vs. memorising the gate per cell
            const cells = world.Size * world.Size;
            try log.print("[LAW] description length: rule = {d:.0} bits  vs  per-cell table ~ {d} bits\n", .{ discovered.bits, cells });
            switch (discovered.pred) {
                .conj => |c| {
                    const correct = c.vx == grid.button_x and c.vy == grid.button_y and discovered.errors == 0;
                    if (correct) {
                        try log.print("[LAW] the rule's location ({d},{d}) IS the button — found purely by\n", .{ c.vx, c.vy });
                        try log.writeAll("      compressing raw experience; the engine was never told where it is.\n");
                        try log.writeAll(">> ENGINE DISCOVERED THE CAUSAL LAW OF ITS WORLD FROM EXPERIENCE <<\n");
                    } else {
                        try log.writeAll("[LAW] rule did not match the true button cleanly (reported honestly).\n");
                    }
                },
                else => try log.writeAll("[LAW] minimal rule was not a position conjunction (reported honestly).\n"),
            }
            try log.writeAll("[NOTE] this unifies the two halves of wcore: embodied experience in,\n");
            try log.writeAll("[NOTE] a compact SYMBOLIC law out — discovered by the same 'shortest description' rule.\n");
        },
    }

    try log.print("\n[SANDBOX] complete. Full log: {s}\n", .{path});
}

fn freshWorld(seed: u64) world.World {
    var grid = world.World.init(seed);
    grid.ax = world.Size / 2;
    grid.ay = world.Size / 2;
    grid.scatterRandom(DEFAULT_RESOURCES);
    return grid;
}

fn freshRoom(seed: u64) world.World {
    var grid = world.World.init(seed);
    grid.setupRoom(ROOM_SIZE);
    return grid;
}

fn reportCuriosity(log: *Logger, s: agent.Stats) !void {
    try log.print("[RESULT/curiosity] code length {d:.2} -> {d:.2} bits/obs; distinct {d}; walls {d}\n", .{ s.first_window_bits, s.last_window_bits, s.distinct_obs, s.walls_built });
}

fn reportEmpower(log: *Logger, s: empower.Stats) !void {
    try log.print("[RESULT/empower] empowerment {d:.3} -> {d:.3} bits; distinct {d}; walls {d}\n", .{ s.first_emp, s.last_emp, s.distinct_obs, s.walls_built });
    try log.writeAll("[NOTE] empowerment = I(action; next observation): control over the future,\n");
    try log.writeAll("[NOTE] NOT next-obs entropy (which would be noise-seeking). One-step, tabular,\n");
    try log.writeAll("[NOTE] from local 3x3 views — purposeful tool-building is NOT claimed.\n");
}

fn parseMode(s: []const u8) Mode {
    if (std.mem.eql(u8, s, "empower")) return .empower;
    if (std.mem.eql(u8, s, "compare")) return .compare;
    if (std.mem.eql(u8, s, "affordance")) return .affordance;
    if (std.mem.eql(u8, s, "law")) return .law;
    return .curiosity;
}

fn parseU64(s: []const u8) ?u64 {
    if (std.mem.startsWith(u8, s, "0x")) return std.fmt.parseInt(u64, s[2..], 16) catch null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}

test {
    _ = @import("agent.zig");
    _ = @import("empower.zig");
    _ = @import("affordance.zig");
    _ = @import("law.zig");
    _ = @import("world.zig");
}
