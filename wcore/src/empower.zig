//! Empowerment-driven agent (roadmap Stage 2).
//!
//! Empowerment = the agent's control over its own future: the mutual
//! information between its action and the resulting observation,
//!     E(s) = I(A; S' | s) = H(S'|s) - (1/|A|) Σ_a H(S'|s,a)
//! estimated from a transition model P(s'|s,a) the agent learns online from
//! ZERO knowledge. High empowerment = "I can reach many distinct outcomes AND
//! reliably choose which one." This is NOT next-observation entropy (that is
//! noise-seeking / the TV-static trap); the per-action entropy is SUBTRACTED.
//!
//! The honest, testable prediction: a walled-in state has few reliably
//! reachable outcomes, so it is low-empowerment — an empowerment agent should
//! AVOID enclosing itself, unlike the count-based curiosity agent which walled
//! itself in by accident. Whether *purposeful construction* emerges is a much
//! harder question and is reported truthfully, not assumed.

const std = @import("std");
const world = @import("world.zig");
const agent = @import("agent.zig");
const Logger = @import("logger.zig").Logger;
const Action = world.Action;
const ACTIONS = agent.ACTIONS;
const hashObs = agent.hashObs;

const MAX_OUT = 128; // scratch cap on distinct outcomes considered per state
const EXPLORE_BONUS: f64 = 1000.0; // untried (s,a) dominates until the model has data

fn mix64(x: u64) u64 {
    var h = x;
    h ^= h >> 33;
    h *%= 0xff51afd7ed558ccd;
    h ^= h >> 33;
    h *%= 0xc4ceb9fe1a85ec53;
    h ^= h >> 33;
    return h;
}
fn keyOA(oh: u64, a: Action) u64 {
    return mix64(oh *% 0x9e3779b97f4a7c15 +% (@as(u64, @intFromEnum(a)) +% 1));
}
fn keyOAO(oh: u64, a: Action, o2: u64) u64 {
    return mix64(keyOA(oh, a) *% 0x9e3779b97f4a7c15 +% o2);
}

pub const TransitionModel = struct {
    a: std.mem.Allocator,
    trans: std.AutoHashMap(u64, usize), // keyOAO -> count
    oatot: std.AutoHashMap(u64, usize), // keyOA  -> total transitions
    outs: std.AutoHashMap(u64, std.ArrayList(u64)), // keyOA -> distinct obs' hashes

    pub fn init(a: std.mem.Allocator) TransitionModel {
        return .{
            .a = a,
            .trans = std.AutoHashMap(u64, usize).init(a),
            .oatot = std.AutoHashMap(u64, usize).init(a),
            .outs = std.AutoHashMap(u64, std.ArrayList(u64)).init(a),
        };
    }

    pub fn deinit(self: *TransitionModel) void {
        var it = self.outs.valueIterator();
        while (it.next()) |list| list.deinit();
        self.outs.deinit();
        self.trans.deinit();
        self.oatot.deinit();
    }

    pub fn observe(self: *TransitionModel, oh: u64, a: Action, o2: u64) !void {
        const oa = keyOA(oh, a);
        const oao = keyOAO(oh, a, o2);
        try self.trans.put(oao, (self.trans.get(oao) orelse 0) + 1);
        try self.oatot.put(oa, (self.oatot.get(oa) orelse 0) + 1);
        const gop = try self.outs.getOrPut(oa);
        if (!gop.found_existing) gop.value_ptr.* = std.ArrayList(u64).init(self.a);
        for (gop.value_ptr.items) |existing| {
            if (existing == o2) return;
        }
        try gop.value_ptr.append(o2);
    }

    pub fn total(self: *const TransitionModel, oh: u64, a: Action) usize {
        return self.oatot.get(keyOA(oh, a)) orelse 0;
    }

    /// Distinct observed next-observation hashes for (oh, a), or null if untried.
    pub fn outcomeList(self: *const TransitionModel, oh: u64, a: Action) ?[]const u64 {
        if (self.outs.get(keyOA(oh, a))) |list| return list.items;
        return null;
    }

    pub fn transCount(self: *const TransitionModel, oh: u64, a: Action, o2: u64) usize {
        return self.trans.get(keyOAO(oh, a, o2)) orelse 0;
    }

    /// Most-likely next observation hash for (oh, a), or null if untried.
    pub fn predictNext(self: *const TransitionModel, oh: u64, a: Action) ?u64 {
        const oa = keyOA(oh, a);
        const list = self.outs.get(oa) orelse return null;
        var best: ?u64 = null;
        var best_c: usize = 0;
        for (list.items) |o2| {
            const c = self.trans.get(keyOAO(oh, a, o2)) orelse 0;
            if (best == null or c > best_c) {
                best = o2;
                best_c = c;
            }
        }
        return best;
    }

    /// One-step empowerment estimate of state `oh` (bits), from observed
    /// transitions only. Uniform prior over actions that have data.
    pub fn empowerment(self: *const TransitionModel, oh: u64) f64 {
        var union_h: [MAX_OUT]u64 = undefined;
        var union_p: [MAX_OUT]f64 = undefined;
        var nu: usize = 0;
        var n_known: usize = 0;
        var sum_cond: f64 = 0;

        for (ACTIONS) |a| {
            const oa = keyOA(oh, a);
            const tot = self.oatot.get(oa) orelse 0;
            if (tot == 0) continue;
            n_known += 1;
            const ft: f64 = @floatFromInt(tot);
            const list = self.outs.get(oa).?;
            var hc: f64 = 0;
            for (list.items) |o2| {
                const c = self.trans.get(keyOAO(oh, a, o2)) orelse 0;
                if (c == 0) continue;
                const p = @as(f64, @floatFromInt(c)) / ft;
                hc -= p * std.math.log2(p);
                // accumulate into the marginal union
                var found = false;
                for (union_h[0..nu], 0..) |uh, i| {
                    if (uh == o2) {
                        union_p[i] += p;
                        found = true;
                        break;
                    }
                }
                if (!found and nu < MAX_OUT) {
                    union_h[nu] = o2;
                    union_p[nu] = p;
                    nu += 1;
                }
            }
            sum_cond += hc;
        }
        if (n_known == 0) return 0;
        const fn_known: f64 = @floatFromInt(n_known);
        var h_marg: f64 = 0;
        for (union_p[0..nu]) |sp| {
            const pm = sp / fn_known;
            if (pm > 0) h_marg -= pm * std.math.log2(pm);
        }
        const avg_cond = sum_cond / fn_known;
        const e = h_marg - avg_cond;
        return if (e < 0) 0 else e;
    }

    /// Choose the action that leads to the highest-empowerment next state,
    /// exploring untried (state, action) pairs first to learn the model.
    pub fn chooseAction(self: *const TransitionModel, oh: u64, r: std.Random) Action {
        var best_val: f64 = -1.0;
        var n_best: usize = 0;
        var chosen: Action = .noop;
        for (ACTIONS) |a| {
            const tot = self.total(oh, a);
            var val: f64 = undefined;
            if (tot == 0) {
                val = EXPLORE_BONUS;
            } else {
                const next = self.predictNext(oh, a) orelse oh;
                val = self.empowerment(next);
            }
            if (val > best_val) {
                best_val = val;
                n_best = 1;
                chosen = a;
            } else if (val == best_val) {
                n_best += 1;
                if (r.uintLessThan(usize, n_best) == 0) chosen = a;
            }
        }
        return chosen;
    }
};

pub const Stats = struct {
    steps: usize,
    first_emp: f64,
    last_emp: f64,
    walls_built: usize,
    distinct_obs: usize,
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
    var model = TransitionModel.init(a);
    defer model.deinit();
    const r = grid.rng.random();

    var prev_obs: ?[9]u8 = null;
    var prev_action: Action = .noop;
    var seen = std.AutoHashMap(u64, void).init(a);
    defer seen.deinit();

    var window_sum: f64 = 0;
    var window_n: usize = 0;
    var first_emp: f64 = 0;
    var last_emp: f64 = 0;
    var got_first = false;
    var walls_before = countWalls(grid);
    var walls_built: usize = 0;
    var action_hist = [_]usize{0} ** ACTIONS.len;

    try log.print("[EMPOWER] zero-knowledge agent, {d} steps, empowerment-driven.\n", .{steps});
    try log.writeAll("[EMPOWER] objective: maximize control over future observations (I(A;S')).\n");

    var step: usize = 0;
    while (step < steps) : (step += 1) {
        const obs = grid.sensor();
        const oh = hashObs(obs);
        try seen.put(oh, {});

        if (prev_obs) |po| try model.observe(hashObs(po), prev_action, oh);

        const emp = model.empowerment(oh);
        window_sum += emp;
        window_n += 1;

        const action = model.chooseAction(oh, r);
        action_hist[@intFromEnum(action)] += 1;
        prev_obs = obs;
        prev_action = action;
        _ = grid.step(step, action);
        if (jitter_every != 0 and step % jitter_every == 0) grid.jitterResources();

        const walls_now = countWalls(grid);
        if (walls_now > walls_before) walls_built += walls_now - walls_before;
        walls_before = walls_now;

        if (window_n == report_every) {
            const avg = window_sum / @as(f64, @floatFromInt(window_n));
            if (!got_first) {
                first_emp = avg;
                got_first = true;
            }
            last_emp = avg;
            try log.print("[t={d:>6}] avg empowerment {d:.3} bits | distinct frames {d} | walls {d}\n", .{ step + 1, avg, seen.count(), walls_now });
            try grid.asciiMap(log, 4);
            window_sum = 0;
            window_n = 0;
        }
    }

    return Stats{
        .steps = steps,
        .first_emp = first_emp,
        .last_emp = last_emp,
        .walls_built = walls_built,
        .distinct_obs = seen.count(),
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

test "empowerment is higher for a state with controllable distinct outcomes than a stuck one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var model = TransitionModel.init(arena.allocator());
    defer model.deinit();

    const open: u64 = 1; // a state from which actions reach distinct, reliable outcomes
    const stuck: u64 = 2; // a state from which every action loops back to itself

    // open: north->10, south->11, east->12 (each deterministic & distinct)
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try model.observe(open, .move_north, 10);
        try model.observe(open, .move_south, 11);
        try model.observe(open, .move_east, 12);
        // stuck: every action returns to `stuck`
        try model.observe(stuck, .move_north, stuck);
        try model.observe(stuck, .move_south, stuck);
        try model.observe(stuck, .move_east, stuck);
    }

    try std.testing.expect(model.empowerment(open) > 1.0); // ~log2(3) distinct controllable futures
    try std.testing.expect(model.empowerment(stuck) < 0.01); // no control
    try std.testing.expect(model.empowerment(open) > model.empowerment(stuck));
}

test "empowerment agent runs from zero knowledge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var log = try Logger.initPath("logs/empower_test.log");
    defer log.deinit();

    var grid = world.World.init(0x5151);
    grid.ax = 16;
    grid.ay = 16;
    grid.scatterRandom(10);
    const stats = try run(a, &grid, 1200, 7, 600, &log);
    try std.testing.expectEqual(@as(usize, 1200), stats.steps);
}
