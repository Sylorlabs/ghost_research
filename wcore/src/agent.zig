//! A compression-driven sensorimotor agent (roadmap Stage 1, honest version).
//!
//! The agent starts with ZERO knowledge of its world. It maintains an online
//! predictive model of its 3x3 sensor stream (just observation counts) and
//! measures the **description length** of that stream as the ideal code length
//!     bits(obs) = -log2 P(obs),  P(obs) = (count+1)/(total + A)
//! with A = 3^9 the size of the 3x3 frame alphabet. A never-seen frame costs
//! ~log2(A) ≈ 14.3 bits; a frequently-seen frame costs almost nothing. So the
//! per-observation code length FALLING over time is genuine compression: the
//! agent is learning the regularities of its world from scratch.
//!
//! ACTION SELECTION is count-based curiosity (compression *progress*, not
//! compression *level*): pick the least-tried (action, observation) context.
//! This deliberately avoids the dark-room degeneracy of a naive "minimize
//! description length" drive (which would just sit still to make the stream
//! constant). It is greedy 1-step curiosity — a real intrinsic drive, but NOT
//! deep MCTS over programs; that is the next increment.

const std = @import("std");
const world = @import("world.zig");
const Logger = @import("logger.zig").Logger;
const Action = world.Action;

const ALPHABET: f64 = 19683.0; // 3^9 possible 3x3 frames

pub const ACTIONS = [_]Action{ .move_north, .move_south, .move_east, .move_west, .push, .build_wall, .noop };

pub fn hashObs(obs: [9]u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (obs) |b| {
        h ^= b;
        h *%= 0x100000001b3;
    }
    return h;
}

fn hashKey(action: Action, obs: [9]u8) u64 {
    var h = hashObs(obs);
    h ^= @as(u64, @intFromEnum(action)) +% 0x9e3779b97f4a7c15;
    h *%= 0x100000001b3;
    return h;
}

pub const Model = struct {
    obs_counts: std.AutoHashMap(u64, usize),
    key_counts: std.AutoHashMap(u64, usize),
    total: usize = 0,

    pub fn init(a: std.mem.Allocator) Model {
        return .{
            .obs_counts = std.AutoHashMap(u64, usize).init(a),
            .key_counts = std.AutoHashMap(u64, usize).init(a),
        };
    }

    pub fn deinit(self: *Model) void {
        self.obs_counts.deinit();
        self.key_counts.deinit();
    }

    /// Ideal code length (bits) of `obs` under the current model — measured
    /// BEFORE the observation is folded in (a true predictive cost).
    pub fn bits(self: *const Model, obs: [9]u8) f64 {
        const c: f64 = @floatFromInt(self.obs_counts.get(hashObs(obs)) orelse 0);
        const t: f64 = @floatFromInt(self.total);
        const p = (c + 1.0) / (t + ALPHABET);
        return -std.math.log2(p);
    }

    fn keyCount(self: *const Model, action: Action, obs: [9]u8) usize {
        return self.key_counts.get(hashKey(action, obs)) orelse 0;
    }

    /// Curiosity: choose the least-tried (action, observation) context, ties
    /// broken randomly.
    pub fn chooseAction(self: *const Model, obs: [9]u8, r: std.Random) Action {
        var best_count: usize = std.math.maxInt(usize);
        var n_best: usize = 0;
        var chosen: Action = .noop;
        for (ACTIONS) |a| {
            const c = self.keyCount(a, obs);
            if (c < best_count) {
                best_count = c;
                n_best = 1;
                chosen = a;
            } else if (c == best_count) {
                n_best += 1;
                if (r.uintLessThan(usize, n_best) == 0) chosen = a; // reservoir tie-break
            }
        }
        return chosen;
    }

    pub fn update(self: *Model, action: Action, obs: [9]u8) !void {
        const oh = hashObs(obs);
        try self.obs_counts.put(oh, (self.obs_counts.get(oh) orelse 0) + 1);
        self.total += 1;
        const kh = hashKey(action, obs);
        try self.key_counts.put(kh, (self.key_counts.get(kh) orelse 0) + 1);
    }
};

pub const Stats = struct {
    steps: usize,
    first_window_bits: f64,
    last_window_bits: f64,
    distinct_obs: usize,
    walls_built: usize,
    action_hist: [ACTIONS.len]usize,
};

pub fn run(
    a: std.mem.Allocator,
    grid: *world.World,
    steps: usize,
    jitter_every: usize,
    report_every: usize,
    log: *Logger,
) !Stats {
    var model = Model.init(a);
    defer model.deinit();
    const r = grid.rng.random();

    var window_sum: f64 = 0;
    var window_n: usize = 0;
    var first_window_bits: f64 = 0;
    var last_window_bits: f64 = 0;
    var got_first = false;
    var walls_before = countWalls(grid);
    var walls_built: usize = 0;
    var action_hist = [_]usize{0} ** ACTIONS.len;

    try log.print("[AGENT] zero-knowledge sensorimotor loop: {d} steps, curiosity-driven.\n", .{steps});
    try log.writeAll("[AGENT] objective measured: description length (bits) of the sensor stream.\n");

    var step: usize = 0;
    while (step < steps) : (step += 1) {
        const obs = grid.sensor();
        const b = model.bits(obs);
        window_sum += b;
        window_n += 1;

        const action = model.chooseAction(obs, r);
        try model.update(action, obs);
        action_hist[@intFromEnum(action)] += 1;
        _ = grid.step(step, action);

        if (jitter_every != 0 and step % jitter_every == 0) grid.jitterResources();

        const walls_now = countWalls(grid);
        if (walls_now > walls_before) walls_built += walls_now - walls_before;
        walls_before = walls_now;

        if (window_n == report_every) {
            const avg = window_sum / @as(f64, @floatFromInt(window_n));
            if (!got_first) {
                first_window_bits = avg;
                got_first = true;
            }
            last_window_bits = avg;
            try log.print("[t={d:>6}] avg code length {d:.2} bits/obs | distinct frames {d} | walls {d}\n", .{ step + 1, avg, model.obs_counts.count(), walls_now });
            try grid.asciiMap(log, 4);
            window_sum = 0;
            window_n = 0;
        }
    }

    return Stats{
        .steps = steps,
        .first_window_bits = first_window_bits,
        .last_window_bits = last_window_bits,
        .distinct_obs = model.obs_counts.count(),
        .walls_built = walls_built,
        .action_hist = action_hist,
    };
}

fn countWalls(grid: *const world.World) usize {
    var n: usize = 0;
    for (grid.grid) |c| {
        if (c == .wall) n += 1;
    }
    return n;
}

pub fn actionName(i: usize) []const u8 {
    return @tagName(ACTIONS[i]);
}

test "code length of a repeated observation falls as the model learns it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var model = Model.init(arena.allocator());
    defer model.deinit();
    const obs = [_]u8{ 0, 0, 0, 0, 2, 0, 0, 0, 0 };

    const before = model.bits(obs); // ~log2(3^9) for a never-seen frame
    var i: usize = 0;
    while (i < 50) : (i += 1) try model.update(.noop, obs);
    const after_some = model.bits(obs);
    while (i < 40000) : (i += 1) try model.update(.noop, obs);
    const after_lots = model.bits(obs);

    try std.testing.expect(before > 13.0); // a novel frame is expensive (fair prior over 3^9)
    try std.testing.expect(after_some < before); // learning it makes it cheaper
    try std.testing.expect(after_lots < after_some); // and cheaper still with more evidence
    try std.testing.expect(after_lots < 1.5); // a dominant frame costs almost nothing
}

test "curiosity prefers the least-tried action in a context" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var model = Model.init(arena.allocator());
    defer model.deinit();
    var prng = std.Random.DefaultPrng.init(1);
    const obs = [_]u8{0} ** 9;

    // hammer every action except build_wall in this context
    for (ACTIONS) |a| {
        if (a == .build_wall) continue;
        var i: usize = 0;
        while (i < 5) : (i += 1) try model.update(a, obs);
    }
    try std.testing.expectEqual(Action.build_wall, model.chooseAction(obs, prng.random()));
}

test "agent loop runs from zero knowledge and compresses its stream" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var log = try Logger.initPath("logs/agent_test.log");
    defer log.deinit();

    var grid = world.World.init(0xA9E7);
    grid.ax = 16;
    grid.ay = 16;
    grid.scatterRandom(12);
    const stats = try run(a, &grid, 1500, 7, 500, &log);

    try std.testing.expectEqual(@as(usize, 1500), stats.steps);
    // by the end, the stream is more compressible than at the start
    try std.testing.expect(stats.last_window_bits < stats.first_window_bits);
}
