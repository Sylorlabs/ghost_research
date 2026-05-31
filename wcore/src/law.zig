//! Law discovery — the symbolic/embodied unification (roadmap §3 apex).
//!
//! The agent lives in its world and records what happens. A sleep phase then
//! searches for the SHORTEST RULE that explains the world's dynamics, scored by
//! description length (rule size + mispredictions). It is never told where the
//! button is; it finds the causal law of the gate by compressing raw experience
//! — embodied experience in, symbolic law out.
//!
//! The rule language is general (a small predicate over position: "always",
//! "never", "x == v", "y == v", or the conjunction "x == vx AND y == vy"). The
//! engine blindly evaluates every candidate and keeps the most-compressing one.
//! Nothing checks "is this the button rule"; that it finds the button location
//! is a consequence of the button being the minimal description of the gate.

const std = @import("std");
const world = @import("world.zig");
const Logger = @import("logger.zig").Logger;

pub const Sample = struct { x: usize, y: usize, gate: bool };

pub const Pred = union(enum) {
    all, // gate always open
    none, // gate never open
    eqx: usize, // x == v
    eqy: usize, // y == v
    conj: struct { vx: usize, vy: usize }, // x == vx AND y == vy

    pub fn eval(p: Pred, x: usize, y: usize) bool {
        return switch (p) {
            .all => true,
            .none => false,
            .eqx => |v| x == v,
            .eqy => |v| y == v,
            .conj => |c| x == c.vx and y == c.vy,
        };
    }

    /// Description length of the rule itself (bits), over a coordinate range.
    pub fn bits(p: Pred, coord_bits: f64) f64 {
        return switch (p) {
            .all, .none => 1.0,
            .eqx, .eqy => 1.0 + coord_bits,
            .conj => 1.0 + 2.0 * coord_bits,
        };
    }

    pub fn write(p: Pred, w: anytype) !void {
        switch (p) {
            .all => try w.writeAll("ALWAYS"),
            .none => try w.writeAll("NEVER"),
            .eqx => |v| try w.print("x == {d}", .{v}),
            .eqy => |v| try w.print("y == {d}", .{v}),
            .conj => |c| try w.print("x == {d} AND y == {d}", .{ c.vx, c.vy }),
        }
    }
};

pub const Law = struct {
    pred: Pred,
    errors: usize,
    bits: f64,
};

fn errorsOf(pred: Pred, data: []const Sample) usize {
    var e: usize = 0;
    for (data) |s| {
        if (Pred.eval(pred, s.x, s.y) != s.gate) e += 1;
    }
    return e;
}

/// Find the minimum-description-length rule for the gate over `data`.
/// total cost = rule bits + errors * (bits to store one exception).
pub fn induce(a: std.mem.Allocator, data: []const Sample, log: *Logger) !Law {
    const coord_bits = std.math.log2(@as(f64, @floatFromInt(world.Size)));
    const err_bits = 2.0 * coord_bits + 1.0; // storing an exception ~ a coordinate pair

    // candidate values actually observed (keeps the search grounded in data)
    var xs = std.ArrayList(usize).init(a);
    var ys = std.ArrayList(usize).init(a);
    var pos = std.ArrayList([2]usize).init(a);
    defer xs.deinit();
    defer ys.deinit();
    defer pos.deinit();
    for (data) |s| {
        try addUnique(&xs, s.x);
        try addUnique(&ys, s.y);
        try addUniquePair(&pos, s.x, s.y);
    }

    var best: ?Law = null;
    const consider = struct {
        fn f(b: *?Law, p: Pred, d: []const Sample, cb: f64, eb: f64) void {
            const errs = errorsOf(p, d);
            const cost = p.bits(cb) + @as(f64, @floatFromInt(errs)) * eb;
            if (b.* == null or cost < (b.*.?.pred.bits(cb) + @as(f64, @floatFromInt(b.*.?.errors)) * eb)) {
                b.* = Law{ .pred = p, .errors = errs, .bits = cost };
            }
        }
    }.f;

    consider(&best, .all, data, coord_bits, err_bits);
    consider(&best, .none, data, coord_bits, err_bits);
    for (xs.items) |v| consider(&best, .{ .eqx = v }, data, coord_bits, err_bits);
    for (ys.items) |v| consider(&best, .{ .eqy = v }, data, coord_bits, err_bits);
    for (pos.items) |p| consider(&best, .{ .conj = .{ .vx = p[0], .vy = p[1] } }, data, coord_bits, err_bits);

    try log.print("[LAW] searched {d} predicates over {d} samples.\n", .{ 2 + xs.items.len + ys.items.len + pos.items.len, data.len });
    return best.?;
}

fn addUnique(list: *std.ArrayList(usize), v: usize) !void {
    for (list.items) |e| {
        if (e == v) return;
    }
    try list.append(v);
}
fn addUniquePair(list: *std.ArrayList([2]usize), x: usize, y: usize) !void {
    for (list.items) |e| {
        if (e[0] == x and e[1] == y) return;
    }
    try list.append(.{ x, y });
}

/// Collect gate-dynamics samples by letting the agent wander (random policy in
/// a momentary-gate room). Records (post-action position, resulting gate).
pub fn collect(a: std.mem.Allocator, grid: *world.World, steps: usize) ![]Sample {
    const r = grid.rng.random();
    const actions = [_]world.Action{ .move_north, .move_south, .move_east, .move_west, .noop };
    var data = std.ArrayList(Sample).init(a);
    var step: usize = 0;
    while (step < steps) : (step += 1) {
        const act = actions[r.uintLessThan(usize, actions.len)];
        _ = grid.step(step, act);
        try data.append(.{ .x = grid.ax, .y = grid.ay, .gate = grid.gate_open });
    }
    return data.toOwnedSlice();
}

test "induces the exact gate law from raw experience (and finds the button)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var log = try Logger.initPath("logs/law_test.log");
    defer log.deinit();

    var grid = world.World.init(0xC0FFEE);
    grid.setupRoom(12);
    grid.gate_momentary = true;
    const data = try collect(a, &grid, 40000);
    const law = try induce(a, data, &log);

    // the minimal rule is exactly "on the button" with zero errors
    try std.testing.expectEqual(@as(usize, 0), law.errors);
    switch (law.pred) {
        .conj => |c| {
            try std.testing.expectEqual(grid.button_x, c.vx);
            try std.testing.expectEqual(grid.button_y, c.vy);
        },
        else => return error.WrongLawShape,
    }
}
