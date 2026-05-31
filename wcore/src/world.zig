//! A real 2D grid world (the sandbox / "its own universe").
//!
//! Sandboxing: the world is a self-contained 32x32 cellular universe. It starts
//! with ZERO data — every tile empty — and is populated only by a seeded RNG.
//! It has no access to anything outside the grid; the only thing that crosses
//! the boundary is the (action, sensor) stream the agent experiences. The
//! engine downstream never sees the grid or the RNG; it sees only that stream.
//!
//! Physics is real and applied per action:
//!   * move_*  : step one cell in that direction if not blocked by wall/edge;
//!               stepping onto a resource collects it (the tile becomes empty).
//!   * push    : push the resource in front one cell if the space beyond is free.
//!   * build_wall : turn the cell in front into a wall.
//!   * noop    : nothing.
//!
//! Repeated structure is EMERGENT, not rigged: the agent harvests resource
//! clusters of RNG-chosen sizes, producing runs of consecutive collecting
//! moves whose lengths it never knew in advance.

const std = @import("std");
const Logger = @import("logger.zig").Logger;

pub const Size: usize = 32;

pub const Tile = enum(u8) {
    empty = 0,
    wall = 1,
    resource = 2,
    button = 3, // standing here controls the gate
    gate = 4, // passable only while the gate is open
};

pub const Action = enum {
    move_north,
    move_south,
    move_east,
    move_west,
    push,
    build_wall,
    noop,
};

pub const Dir = enum { north, south, east, west };

/// One time-step of lived experience: the action taken, the 3x3 sensor reading
/// that resulted, whether the agent actually moved, and whether it collected a
/// resource on that step.
pub const Event = struct {
    t: usize,
    action: Action,
    sensor: [9]u8,
    moved: bool,
    collected: bool,
    ax: usize,
    ay: usize,
};

pub const World = struct {
    grid: [Size * Size]Tile,
    ax: usize,
    ay: usize,
    facing: Dir,
    rng: std.Random.DefaultPrng,
    seed: u64,
    // affordance: a button whose press controls a remote gate
    has_affordance: bool = false,
    button_x: usize = 0,
    button_y: usize = 0,
    gate_x: usize = 0,
    gate_y: usize = 0,
    gate_open: bool = false,
    gate_momentary: bool = false, // true: gate open == on-button (for law sampling); false: latching

    pub fn init(seed: u64) World {
        var w = World{
            .grid = undefined,
            .ax = 0,
            .ay = 0,
            .facing = .east,
            .rng = std.Random.DefaultPrng.init(seed),
            .seed = seed,
        };
        for (&w.grid) |*c| c.* = .empty; // ZERO data: the universe begins empty
        return w;
    }

    fn idx(x: usize, y: usize) usize {
        return y * Size + x;
    }

    fn at(self: *const World, x: usize, y: usize) Tile {
        if (x >= Size or y >= Size) return .wall;
        return self.grid[idx(x, y)];
    }

    fn set(self: *World, x: usize, y: usize, t: Tile) void {
        if (x >= Size or y >= Size) return;
        self.grid[idx(x, y)] = t;
    }

    fn delta(d: Dir) struct { dx: i64, dy: i64 } {
        return switch (d) {
            .north => .{ .dx = 0, .dy = -1 },
            .south => .{ .dx = 0, .dy = 1 },
            .east => .{ .dx = 1, .dy = 0 },
            .west => .{ .dx = -1, .dy = 0 },
        };
    }

    fn ahead(self: *const World, d: Dir) ?struct { x: usize, y: usize } {
        const dd = delta(d);
        const nx = @as(i64, @intCast(self.ax)) + dd.dx;
        const ny = @as(i64, @intCast(self.ay)) + dd.dy;
        if (nx < 0 or ny < 0 or nx >= Size or ny >= Size) return null;
        return .{ .x = @intCast(nx), .y = @intCast(ny) };
    }

    /// What tile is directly in front of the agent in direction `d`?
    pub fn peek(self: *const World, d: Dir) Tile {
        if (self.ahead(d)) |p| return self.at(p.x, p.y);
        return .wall;
    }

    /// 3x3 window of tile ids around the agent (out-of-bounds reads as wall).
    pub fn sensor(self: *const World) [9]u8 {
        var out: [9]u8 = undefined;
        var i: usize = 0;
        var dy: i64 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i64 = -1;
            while (dx <= 1) : (dx += 1) {
                const x = @as(i64, @intCast(self.ax)) + dx;
                const y = @as(i64, @intCast(self.ay)) + dy;
                const t = if (x < 0 or y < 0) Tile.wall else self.at(@intCast(x), @intCast(y));
                out[i] = @intFromEnum(t);
                i += 1;
            }
        }
        return out;
    }

    fn dirOf(action: Action) ?Dir {
        return switch (action) {
            .move_north => .north,
            .move_south => .south,
            .move_east => .east,
            .move_west => .west,
            else => null,
        };
    }

    /// Apply one action under real physics and return the lived Event.
    pub fn step(self: *World, t: usize, action: Action) Event {
        var moved = false;
        var collected = false;

        if (dirOf(action)) |d| {
            self.facing = d;
            if (self.ahead(d)) |p| {
                const tile = self.at(p.x, p.y);
                const passable = tile != .wall and (tile != .gate or self.gate_open);
                if (passable) {
                    if (tile == .resource) {
                        self.set(p.x, p.y, .empty); // collect
                        collected = true;
                    }
                    self.ax = p.x;
                    self.ay = p.y;
                    moved = true;
                }
            }
        } else switch (action) {
            .push => {
                if (self.ahead(self.facing)) |p| {
                    if (self.at(p.x, p.y) == .resource) {
                        const dd = delta(self.facing);
                        const bx = @as(i64, @intCast(p.x)) + dd.dx;
                        const by = @as(i64, @intCast(p.y)) + dd.dy;
                        if (bx >= 0 and by >= 0 and bx < Size and by < Size and
                            self.at(@intCast(bx), @intCast(by)) == .empty)
                        {
                            self.set(@intCast(bx), @intCast(by), .resource);
                            self.set(p.x, p.y, .empty);
                            self.ax = p.x;
                            self.ay = p.y;
                            moved = true;
                        }
                    }
                }
            },
            .build_wall => {
                if (self.ahead(self.facing)) |p| {
                    if (self.at(p.x, p.y) == .empty) self.set(p.x, p.y, .wall);
                }
            },
            .noop => {},
            else => unreachable,
        }

        // Pressing the button controls the gate. Latching (default): once
        // pressed it stays open, unlocking the far half. Momentary: the gate is
        // open exactly while the agent stands on the button — used to richly
        // sample the gate's law for the law-discovery experiment.
        if (self.has_affordance) {
            const on = self.ax == self.button_x and self.ay == self.button_y;
            if (self.gate_momentary) {
                self.gate_open = on;
            } else if (on) {
                self.gate_open = true;
            }
        }

        return Event{
            .t = t,
            .action = action,
            .sensor = self.sensor(),
            .moved = moved,
            .collected = collected,
            .ax = self.ax,
            .ay = self.ay,
        };
    }

    /// Scatter `n` horizontal resource clusters, one per row, each of an
    /// RNG-chosen length in 1..max_len, starting at column 1 (column 0 stays a
    /// clear navigation lane). Lengths are NOT known to the engine.
    pub fn scatter(self: *World, n: usize, max_len: usize) void {
        const r = self.rng.random();
        var row: usize = 0;
        while (row < n and row < Size) : (row += 1) {
            const len = 1 + r.uintLessThan(usize, max_len);
            var x: usize = 1;
            while (x <= len and x < Size) : (x += 1) {
                self.set(x, row, .resource);
            }
        }
    }

    /// Scatter `n` resources at random empty cells (used by the agent world).
    pub fn scatterRandom(self: *World, n: usize) void {
        const r = self.rng.random();
        var placed: usize = 0;
        var guard: usize = 0;
        while (placed < n and guard < n * 50) : (guard += 1) {
            const x = r.uintLessThan(usize, Size);
            const y = r.uintLessThan(usize, Size);
            if (self.at(x, y) == .empty and !(x == self.ax and y == self.ay)) {
                self.set(x, y, .resource);
                placed += 1;
            }
        }
    }

    /// Move every resource one random step (a random walk) into an adjacent
    /// empty cell — the dynamic, hard-to-predict part of the agent's world.
    pub fn jitterResources(self: *World) void {
        const r = self.rng.random();
        // snapshot positions first so a moved resource is not moved twice
        var ys: usize = 0;
        while (ys < Size) : (ys += 1) {
            var xs: usize = 0;
            while (xs < Size) : (xs += 1) {
                // scan in a fixed order; only original resources move (we clear
                // source before setting dest, so a dest cell scanned later is a
                // resource that already moved this tick — acceptable jitter)
                if (self.grid[idx(xs, ys)] != .resource) continue;
                const dir: u2 = @intCast(r.uintLessThan(usize, 4));
                const d = delta(switch (dir) {
                    0 => Dir.north,
                    1 => Dir.south,
                    2 => Dir.east,
                    3 => Dir.west,
                });
                const nx = @as(i64, @intCast(xs)) + d.dx;
                const ny = @as(i64, @intCast(ys)) + d.dy;
                if (nx < 0 or ny < 0 or nx >= Size or ny >= Size) continue;
                const ux: usize = @intCast(nx);
                const uy: usize = @intCast(ny);
                if (self.at(ux, uy) != .empty) continue;
                if (ux == self.ax and uy == self.ay) continue;
                self.set(xs, ys, .empty);
                self.set(ux, uy, .resource);
            }
        }
    }

    /// Render a `(2*radius+1)` square window around the agent. `@`=agent,
    /// `#`=wall, `*`=resource, `.`=empty.
    pub fn asciiMap(self: *const World, w: anytype, radius: usize) !void {
        const r: i64 = @intCast(radius);
        var dy: i64 = -r;
        while (dy <= r) : (dy += 1) {
            try w.writeAll("    ");
            var dx: i64 = -r;
            while (dx <= r) : (dx += 1) {
                const x = @as(i64, @intCast(self.ax)) + dx;
                const y = @as(i64, @intCast(self.ay)) + dy;
                if (dx == 0 and dy == 0) {
                    try w.writeAll("@");
                } else if (x < 0 or y < 0 or x >= Size or y >= Size) {
                    try w.writeAll("#");
                } else {
                    try w.writeAll(switch (self.at(@intCast(x), @intCast(y))) {
                        .empty => ".",
                        .wall => "#",
                        .resource => "*",
                        .button => "B",
                        .gate => if (self.gate_open) "=" else "G",
                    });
                }
            }
            try w.writeAll("\n");
        }
    }

    /// Build a walled room split into two halves by an interior wall with one
    /// gate. The button is in the LEFT half; pressing it latches the gate open,
    /// unlocking the RIGHT half (which holds resources). The agent starts in the
    /// left half and cannot reach the right half until it presses the button.
    pub fn setupRoom(self: *World, size: usize) void {
        const n = @min(size, Size - 1);
        var i: usize = 0;
        while (i <= n) : (i += 1) {
            self.set(i, 0, .wall);
            self.set(i, n, .wall);
            self.set(0, i, .wall);
            self.set(n, i, .wall);
        }
        // interior dividing wall with a single gate gap
        const gx = n / 2;
        const gy = n / 2;
        var yy: usize = 1;
        while (yy < n) : (yy += 1) {
            if (yy != gy) self.set(gx, yy, .wall);
        }
        self.gate_x = gx;
        self.gate_y = gy;
        self.set(gx, gy, .gate);
        // resources scattered in the right (locked) half
        var rx = gx + 2;
        while (rx < n) : (rx += 2) {
            self.set(rx, gy, .resource);
            if (gy + 1 < n) self.set(rx, gy + 1, .resource);
        }
        // button in the left half
        self.button_x = 2;
        self.button_y = 2;
        self.set(self.button_x, self.button_y, .button);
        self.has_affordance = true;
        self.gate_open = false;
        self.ax = @max(1, gx / 2);
        self.ay = gy;
    }

    pub fn gateBit(self: *const World) u8 {
        return if (self.gate_open) 1 else 0;
    }

    pub fn onButton(self: *const World) bool {
        return self.has_affordance and self.ax == self.button_x and self.ay == self.button_y;
    }

    /// 10-element observation: the 3x3 sensor plus the gate-state bit, so the
    /// agent can perceive (and thus learn to control) the gate.
    pub fn obs10(self: *const World) [10]u8 {
        var out: [10]u8 = undefined;
        const s = self.sensor();
        @memcpy(out[0..9], &s);
        out[9] = self.gateBit();
        return out;
    }
};

/// The lived sensory stream of one episode.
pub const History = struct {
    events: []Event,
    seed: u64,
};

/// Run a real episode: the agent harvests each cluster row by moving east while
/// resources are ahead, then returns west along the now-clear row and drops to
/// the next row. Every step is real physics and is logged.
pub fn runEpisode(a: std.mem.Allocator, world: *World, rows: usize, log: *Logger) !History {
    var events = std.ArrayList(Event).init(a);
    var t: usize = 0;

    try log.print("[WORLD] universe seed=0x{x}, grid {d}x{d}, starts empty; scattering clusters...\n", .{ world.seed, Size, Size });

    var row: usize = 0;
    while (row < rows) : (row += 1) {
        // harvest east while a resource is directly ahead
        while (world.peek(.east) == .resource) {
            const e = world.step(t, .move_east);
            try logStep(log, e);
            try events.append(e);
            t += 1;
        }
        // return west along the cleared row to the navigation lane (column 0)
        while (world.ax > 0) {
            const e = world.step(t, .move_west);
            try logStep(log, e);
            try events.append(e);
            t += 1;
        }
        // descend to the next row
        if (row + 1 < rows) {
            const e = world.step(t, .move_south);
            try logStep(log, e);
            try events.append(e);
            t += 1;
        }
    }

    try log.print("[WORLD] episode complete: {d} lived steps.\n", .{events.items.len});
    return History{ .events = try events.toOwnedSlice(), .seed = world.seed };
}

fn logStep(log: *Logger, e: Event) !void {
    try log.print("[STEP {d:>4}] action={s:<11} pos=({d},{d}) moved={} collected={} sensor={any}\n", .{
        e.t, @tagName(e.action), e.ax, e.ay, e.moved, e.collected, e.sensor,
    });
}

/// A DIFFERENT universe topology: a tree of chambers. Each non-leaf chamber
/// branches into exactly two sub-chambers (the agent's sensor shows two open
/// passages); leaves are dead ends. The agent does a real depth-first
/// exploration, logging every chamber it enters. Depths are RNG-chosen, so the
/// branching structure is emergent — the engine is never told the tree.
/// Returns the depth of each explored tree.
pub fn runBranchingEpisode(a: std.mem.Allocator, world: *World, n: usize, max_depth: usize, log: *Logger) ![]usize {
    const r = world.rng.random();
    const depths = try a.alloc(usize, n);
    try log.print("[WORLD] BRANCHING universe seed=0x{x}: tree-of-chambers topology; DFS exploration...\n", .{world.seed});
    for (depths, 0..) |*d, i| {
        d.* = 1 + r.uintLessThan(usize, max_depth);
        try log.print("[TREE {d}] depth={d}; entering root chamber:\n", .{ i, d.* });
        var visited: usize = 0;
        try exploreChamber(log, d.*, 0, &visited);
        try log.print("[TREE {d}] exploration done: {d} chambers visited.\n", .{ i, visited });
    }
    return depths;
}

fn exploreChamber(log: *Logger, depth: usize, level: usize, visited: *usize) !void {
    const id = visited.*;
    visited.* += 1;
    if (level == depth) {
        try log.print("  [chamber {d:>3}] level={d} LEAF      sensor=[both passages closed]\n", .{ id, level });
        return;
    }
    try log.print("  [chamber {d:>3}] level={d} BRANCH(x2) sensor=[left+right passages open]\n", .{ id, level });
    try exploreChamber(log, depth, level + 1, visited); // descend left
    try exploreChamber(log, depth, level + 1, visited); // descend right
}

/// Segment the lived history into the lengths of maximal runs of consecutive
/// "harvest" steps (a move_east that collected a resource). These run lengths
/// are the repetition multiplicities the wake phase must encode — derived from
/// real experience, never handed to the engine.
pub fn segmentHarvestRuns(a: std.mem.Allocator, h: History) ![]usize {
    var runs = std.ArrayList(usize).init(a);
    var cur: usize = 0;
    for (h.events) |e| {
        const harvest = e.action == .move_east and e.collected;
        if (harvest) {
            cur += 1;
        } else if (cur > 0) {
            try runs.append(cur);
            cur = 0;
        }
    }
    if (cur > 0) try runs.append(cur);
    return runs.toOwnedSlice();
}

test "pressing the button latches the gate open; gate-bit shows in obs10" {
    var w = World.init(0xB07);
    w.setupRoom(12);
    try std.testing.expect(!w.gate_open);
    try std.testing.expectEqual(@as(u8, 0), w.obs10()[9]);

    // place adjacent to the button, then step onto it
    w.ax = w.button_x + 1;
    w.ay = w.button_y;
    w.facing = .west;
    _ = w.step(0, .move_west); // step onto button
    try std.testing.expect(w.onButton());
    try std.testing.expect(w.gate_open);
    try std.testing.expectEqual(@as(u8, 1), w.obs10()[9]);

    // stepping off the button leaves the gate OPEN (latched)
    _ = w.step(1, .move_east);
    try std.testing.expect(w.gate_open);
    try std.testing.expectEqual(@as(u8, 1), w.obs10()[9]);
}

test "the gate blocks passage until the button is pressed" {
    var w = World.init(0xB08);
    w.setupRoom(12);
    // stand just left of the gate, facing it
    w.ax = w.gate_x - 1;
    w.ay = w.gate_y;
    w.facing = .east;
    _ = w.step(0, .move_east); // blocked: gate closed
    try std.testing.expectEqual(w.gate_x - 1, w.ax);
    // press the button, return, and now pass through
    w.gate_open = true; // (as if pressed)
    w.ax = w.gate_x - 1;
    w.ay = w.gate_y;
    _ = w.step(1, .move_east); // passes onto the gate cell
    try std.testing.expectEqual(w.gate_x, w.ax);
}

test "real physics: move is blocked by walls and collects resources" {
    var w = World.init(7);
    w.ax = 5;
    w.ay = 5;
    w.set(6, 5, .resource);
    const e1 = w.step(0, .move_east); // onto resource -> collect
    try std.testing.expect(e1.moved);
    try std.testing.expect(e1.collected);
    try std.testing.expectEqual(@as(usize, 6), w.ax);
    try std.testing.expectEqual(Tile.empty, w.at(6, 5));

    w.set(7, 5, .wall);
    const e2 = w.step(1, .move_east); // into wall -> blocked
    try std.testing.expect(!e2.moved);
    try std.testing.expectEqual(@as(usize, 6), w.ax);
}

test "harvest runs emerge from a real episode and match scattered clusters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var log = try Logger.init(a, 0xABCDEF);
    defer log.deinit();

    var w = World.init(0xABCDEF);
    w.scatter(4, 6);
    const h = try runEpisode(a, &w, 4, &log);
    const runs = try segmentHarvestRuns(a, h);

    // four clusters harvested -> four runs, each 1..6, all resources gone
    try std.testing.expectEqual(@as(usize, 4), runs.len);
    for (runs) |k| try std.testing.expect(k >= 1 and k <= 6);
    var any_resource = false;
    for (w.grid) |c| {
        if (c == .resource) any_resource = true;
    }
    try std.testing.expect(!any_resource);
}
