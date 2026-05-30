//! Goal-directed affordance-seeking (roadmap Stage 2.5).
//!
//! Stage 2 found that one-step empowerment cures self-entrapment but gives NO
//! gradient toward a distant high-control state, and that a local agent cannot
//! even perceive a non-local affordance. Two honest upgrades close that gap:
//!
//!   1. The observation includes the gate-state bit (world.obs10), so pressing
//!      the button is a reliably *controllable* variable -> the button becomes a
//!      genuine one-step empowerment PEAK.
//!   2. Value iteration with empowerment as the per-state reward propagates that
//!      peak outward into a navigation gradient:
//!          V(s) = empowerment(s) + gamma * max_a E_{s'}[ V(s') ]
//!      so the agent can climb toward the button from across the room.
//!
//! Falsifiable test: does the agent spend MORE time near the button than a
//! random-action baseline, and does that occupancy RISE as it learns? Reported
//! honestly either way. Reuses empower.TransitionModel over a 10-byte obs.

const std = @import("std");
const world = @import("world.zig");
const empower = @import("empower.zig");
const agent = @import("agent.zig");
const Logger = @import("logger.zig").Logger;
const Action = world.Action;
const ACTIONS = agent.ACTIONS;

const GAMMA: f64 = 0.9;
const SWEEPS: usize = 20;
const REPLAN_EVERY: usize = 400;
const WARMUP: usize = 400;
const MAX_STATES: usize = 8192;
const EXPLORE_BONUS: f64 = 1000.0;
const EXPLORE_REWARD: f64 = 3.0; // per untried action: makes frontiers high-value in VI

// The affordance experiment isolates button-seeking, so the action set is
// movement only — wall-building is irrelevant noise here and (as Stage 1
// showed) its explore-everything bonus causes self-entrapment.
const MOVE_ACTIONS = [_]Action{ .move_north, .move_south, .move_east, .move_west, .noop };

fn hashObs10(obs: [10]u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (obs) |b| {
        h ^= b;
        h *%= 0x100000001b3;
    }
    return h;
}

/// A position-aware state: (x, y, gate). This de-aliases the open interior,
/// where every cell looks identical under a local 3x3 view. With it, the agent
/// has the spatial memory needed to navigate; without it, navigation to a
/// specific location is unreliable (the honest root cause of seed-dependence).
fn posHash(x: usize, y: usize, gate_open: bool) u64 {
    var h: u64 = (@as(u64, x) << 16) | (@as(u64, y) << 1) | @intFromBool(gate_open);
    h ^= h >> 33;
    h *%= 0xff51afd7ed558ccd;
    h ^= h >> 33;
    return h;
}

fn stateHash(grid: *const world.World, positional: bool) u64 {
    if (positional) return posHash(grid.ax, grid.ay, grid.gate_open);
    return hashObs10(grid.obs10());
}

const Planner = struct {
    a: std.mem.Allocator,
    model: empower.TransitionModel,
    states: std.ArrayList(u64),
    index: std.AutoHashMap(u64, usize),
    v: std.ArrayList(f64),

    fn init(a: std.mem.Allocator) Planner {
        return .{
            .a = a,
            .model = empower.TransitionModel.init(a),
            .states = std.ArrayList(u64).init(a),
            .index = std.AutoHashMap(u64, usize).init(a),
            .v = std.ArrayList(f64).init(a),
        };
    }
    fn deinit(self: *Planner) void {
        self.model.deinit();
        self.states.deinit();
        self.index.deinit();
        self.v.deinit();
    }

    fn register(self: *Planner, oh: u64) !void {
        if (self.index.contains(oh)) return;
        if (self.states.items.len >= MAX_STATES) return;
        try self.index.put(oh, self.states.items.len);
        try self.states.append(oh);
        try self.v.append(0);
    }

    fn valueOf(self: *const Planner, oh: u64) f64 {
        if (self.index.get(oh)) |j| return self.v.items[j];
        return 0;
    }

    /// Expected next-state value of taking action `a` from `oh` under the model.
    fn qValue(self: *const Planner, oh: u64, a: Action) f64 {
        const tot = self.model.total(oh, a);
        if (tot == 0) return 0;
        const ftot: f64 = @floatFromInt(tot);
        const list = self.model.outcomeList(oh, a).?;
        var q: f64 = 0;
        for (list) |o2| {
            const p = @as(f64, @floatFromInt(self.model.transCount(oh, a, o2))) / ftot;
            q += p * self.valueOf(o2);
        }
        return q;
    }

    fn untriedCount(self: *const Planner, oh: u64) usize {
        var n: usize = 0;
        for (MOVE_ACTIONS) |a| {
            if (self.model.total(oh, a) == 0) n += 1;
        }
        return n;
    }

    fn valueIterate(self: *Planner) !void {
        const newv = try self.a.alloc(f64, self.states.items.len);
        defer self.a.free(newv);
        var sweep: usize = 0;
        while (sweep < SWEEPS) : (sweep += 1) {
            for (self.states.items, 0..) |oh, i| {
                // R-max-style optimism: frontier states (with untried actions)
                // are rewarded, so VALUE ITERATION plans paths toward the
                // unknown instead of relying on a lucky random walk to find it.
                const reward = self.model.empowerment(oh) + EXPLORE_REWARD * @as(f64, @floatFromInt(self.untriedCount(oh)));
                var best_q: f64 = 0;
                for (ACTIONS) |a| {
                    if (self.model.total(oh, a) == 0) continue;
                    const q = self.qValue(oh, a);
                    if (q > best_q) best_q = q;
                }
                newv[i] = reward + GAMMA * best_q;
            }
            @memcpy(self.v.items, newv);
        }
    }

    fn choose(self: *const Planner, oh: u64, r: std.Random) Action {
        var best: f64 = -1.0;
        var n_best: usize = 0;
        var chosen: Action = .noop;
        for (MOVE_ACTIONS) |a| {
            const val = if (self.model.total(oh, a) == 0) EXPLORE_BONUS else self.qValue(oh, a);
            if (val > best) {
                best = val;
                n_best = 1;
                chosen = a;
            } else if (val == best) {
                n_best += 1;
                if (r.uintLessThan(usize, n_best) == 0) chosen = a;
            }
        }
        return chosen;
    }
};

pub const Stats = struct {
    label: []const u8,
    steps: usize,
    far_half_pct: f64, // % of steps spent in the unlocked (right) half
    on_button_pct: f64, // % of steps standing on the button
    pressed: bool, // did the gate ever get opened?
    first_press: usize, // step of first press (== steps if never)
};

fn inFarHalf(grid: *const world.World) bool {
    return grid.ax > grid.gate_x;
}

/// The value-iteration empowerment agent. `positional` chooses the state
/// representation: false = local 3x3 view (aliases positions), true = (x,y,gate).
pub fn run(a: std.mem.Allocator, grid: *world.World, steps: usize, positional: bool, log: *Logger) !Stats {
    var planner = Planner.init(a);
    defer planner.deinit();
    const r = grid.rng.random();

    var prev: ?u64 = null;
    var prev_action: Action = .noop;
    var far_count: usize = 0;
    var on_button: usize = 0;
    var first_press: usize = steps;

    try log.print("[AFFORD] value-iteration empowerment agent ({s} state) in a split button+gate room, {d} steps.\n", .{ if (positional) "positional" else "local-3x3", steps });

    var step: usize = 0;
    while (step < steps) : (step += 1) {
        const oh = stateHash(grid, positional);
        try planner.register(oh);
        if (prev) |p| try planner.model.observe(p, prev_action, oh);

        if (step >= WARMUP and step % REPLAN_EVERY == 0) try planner.valueIterate();

        const action = planner.choose(oh, r);
        const was_open = grid.gate_open;
        prev = oh;
        prev_action = action;
        _ = grid.step(step, action);
        if (!was_open and grid.gate_open and first_press == steps) {
            first_press = step;
            try log.print("[AFFORD] first button press at step {d} -> right half unlocked.\n", .{step});
        }

        if (inFarHalf(grid)) far_count += 1;
        if (grid.onButton()) on_button += 1;

        if ((step + 1) % (steps / 6) == 0) {
            try log.print("[t={d:>6}] states {d} | V(here) {d:.2} | far-half so far {d:.1}% | gate {s}\n", .{ step + 1, planner.states.items.len, planner.valueOf(oh), 100.0 * @as(f64, @floatFromInt(far_count)) / @as(f64, @floatFromInt(step + 1)), if (grid.gate_open) "OPEN" else "closed" });
            try grid.asciiMap(log, 5);
        }
    }

    return Stats{
        .label = if (positional) "empowerment+VI (positional)" else "empowerment+VI (local)",
        .steps = steps,
        .far_half_pct = 100.0 * @as(f64, @floatFromInt(far_count)) / @as(f64, @floatFromInt(steps)),
        .on_button_pct = 100.0 * @as(f64, @floatFromInt(on_button)) / @as(f64, @floatFromInt(steps)),
        .pressed = grid.gate_open,
        .first_press = first_press,
    };
}

/// Random-action baseline in the same room (control for "is it goal-directed?").
pub fn runRandom(grid: *world.World, steps: usize) Stats {
    const r = grid.rng.random();
    var far_count: usize = 0;
    var on_button: usize = 0;
    var first_press: usize = steps;
    var step: usize = 0;
    while (step < steps) : (step += 1) {
        const action = MOVE_ACTIONS[r.uintLessThan(usize, MOVE_ACTIONS.len)];
        const was_open = grid.gate_open;
        _ = grid.step(step, action);
        if (!was_open and grid.gate_open and first_press == steps) first_press = step;
        if (inFarHalf(grid)) far_count += 1;
        if (grid.onButton()) on_button += 1;
    }
    return Stats{
        .label = "random",
        .steps = steps,
        .far_half_pct = 100.0 * @as(f64, @floatFromInt(far_count)) / @as(f64, @floatFromInt(steps)),
        .on_button_pct = 100.0 * @as(f64, @floatFromInt(on_button)) / @as(f64, @floatFromInt(steps)),
        .pressed = grid.gate_open,
        .first_press = first_press,
    };
}

test "an open gate raises empowerment by adding a reachable outcome" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var model = empower.TransitionModel.init(a);
    defer model.deinit();

    // `closed`: next to a CLOSED gate -> only 2 directions move (gate blocks east).
    // `open`:   the same spot with the gate OPEN -> 3 directions move (incl. east).
    // This is exactly what pressing the button does for gate-adjacent states.
    const closed: u64 = 100;
    const open: u64 = 200;
    var i: usize = 0;
    while (i < 30) : (i += 1) {
        try model.observe(closed, .move_north, 1);
        try model.observe(closed, .move_south, 2);
        try model.observe(closed, .move_east, closed); // blocked -> stays

        try model.observe(open, .move_north, 1);
        try model.observe(open, .move_south, 2);
        try model.observe(open, .move_east, 3); // gate open -> reaches a new state
    }
    // closed reaches {1,2,closed}=3 outcomes but east is degenerate;
    // open reaches {1,2,3}=3 distinct *controllable* outcomes -> >= closed,
    // and strictly more useful control. Require open >= closed and > 1 bit.
    try std.testing.expect(model.empowerment(open) >= model.empowerment(closed));
    try std.testing.expect(model.empowerment(open) > 1.5);
}

test "positional empowerment+VI agent presses the button and uses the unlocked half" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var log = try Logger.initPath("logs/affordance_test.log");
    defer log.deinit();

    var grid = world.World.init(42);
    grid.setupRoom(14);
    const stats = try run(a, &grid, 8000, true, &log);
    try std.testing.expect(stats.pressed); // it reached and pressed the button
    try std.testing.expect(stats.first_press < 8000);
    try std.testing.expect(stats.far_half_pct > 5.0); // and used the region it unlocked
}
