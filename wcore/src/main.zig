//! wcore — a zero-bias invention engine.
//!
//! Sandboxed pipeline (every line below is mirrored to logs/wcore_<seed>.log):
//!   1. The library begins with only the permitted primitives (Unit, Bool,
//!      Sensor, Action + identity, composition). No numbers, no recursion, no
//!      Bottom, no W. This is the "zero data" starting point.
//!   2. A self-contained grid universe starts empty and is populated by a
//!      seeded RNG. The agent lives a real sensorimotor episode under real
//!      physics; the lived (action, sensor) stream is the only thing that
//!      crosses the world boundary.
//!   3. Run-length segmentation of that real history yields repetition counts
//!      the engine was never told.
//!   4. The wake phase SEARCHES for the shortest base-calculus program
//!      reproducing each run (objective = node count, verified by evaluation).
//!   5. The sleep phase anti-unifies the batch, blindly enumerates small
//!      W-types, and accepts whichever lowers total node count.
//!   6. The invented eliminator is EXECUTED to verify the refactoring is
//!      behaviourally faithful, then the milestone is reported.

const std = @import("std");
const types = @import("types.zig");
const terms = @import("terms.zig");
const nodecount = @import("nodecount.zig");
const library = @import("library.zig");
const checker = @import("checker.zig");
const evaluator = @import("evaluator.zig");
const world = @import("world.zig");
const mcts = @import("mcts.zig");
const antiunify = @import("antiunify.zig");
const wpropose = @import("wpropose.zig");
const telemetry = @import("telemetry.zig");
const Logger = @import("logger.zig").Logger;

const DEFAULT_SEED: u64 = 0xC0FFEE;
const DEFAULT_ROWS: usize = 4;
const DEFAULT_MAX_CLUSTER: usize = 6;

const Mode = enum { linear, branching };

const Config = struct {
    seed: u64,
    rows: usize,
    max_cluster: usize,
    mode: Mode,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit(); // frees every allocation made through `a`
    const a = arena.allocator();

    // Each seed is a distinct, fully reproducible universe.
    //   zig build run -- <seed> [rows] [max_cluster] [linear|branching]
    const cfg = try parseConfig(a);
    const seed = cfg.seed;

    var log = try Logger.init(a, seed);
    defer log.deinit();
    try log.print("[SANDBOX] wcore run, seed=0x{x}, mode={s}, count={d}, max={d}; log -> {s}\n", .{ seed, @tagName(cfg.mode), cfg.rows, cfg.max_cluster, log.path });

    // 1. The library begins with exactly the permitted primitives.
    var lib = try library.Library.init(a);
    try telemetry.init(&log, lib.typeCount(), lib.combinatorCount(), lib.totalNodeCount());

    // Demonstrate the base type checker + evaluator are live (no W-types yet).
    try selfCheck(&lib, &log);

    // 2 & 3 & 4. A real, seeded universe + episode -> emergent structure ->
    // wake encoding. Two universe topologies; the wake uses only id/composition
    // in both. The SLEEP phase below does not know which universe produced the
    // programs — it just sees the batch.
    var grid = world.World.init(seed);
    const programs = switch (cfg.mode) {
        .linear => blk: {
            grid.scatter(cfg.rows, cfg.max_cluster);
            const history = try world.runEpisode(a, &grid, cfg.rows, &log);
            const counts = try world.segmentHarvestRuns(a, history);
            try log.print("[SEGMENT] harvest-run lengths from real history: {any}\n", .{counts});
            try log.writeAll("[WAKE] searching the program space...\n");
            break :blk try mcts.run(a, &lib, counts, &log);
        },
        .branching => blk: {
            const depths = try world.runBranchingEpisode(a, &grid, cfg.rows, cfg.max_cluster, &log);
            try log.print("[SEGMENT] explored-tree depths from real history: {any}\n", .{depths});
            try log.writeAll("[WAKE] reproducing each explored tree as a program...\n");
            break :blk try mcts.runBranching(a, &lib, depths, &log);
        },
    };
    try telemetry.wakeBatch(&log, programs.len);

    // 5. Sleep: try every motif detector, propose a W-type for each, and commit
    // ONLY the node-count winner. This is the same blind rule for both worlds.
    try telemetry.sleepHeader(&log);
    var best: ?wpropose.Proposal = null;
    if (try antiunify.detectLinear(a, programs)) |pat| {
        try log.writeAll("[SLEEP] motif: LINEAR (branching factor 1)\n");
        var p = pat;
        const prop = try wpropose.propose(a, &lib, &p, &log);
        if (prop.found and (best == null or best.?.saved < prop.saved)) best = prop;
    }
    if (try antiunify.detectBranching(a, programs)) |pat| {
        try log.writeAll("[SLEEP] motif: BRANCHING (branching factor 2)\n");
        var p = pat;
        const prop = try wpropose.propose(a, &lib, &p, &log);
        if (prop.found and (best == null or best.?.saved < prop.saved)) best = prop;
    }

    if (best) |*prop| {
        try log.print("[SLEEP] node-count winner: arity-{d} motif saving {d} nodes\n", .{ prop.arity, prop.saved });
        const outcome = try wpropose.commit(a, &lib, prop, &log);
        try telemetry.accepted(&log, outcome.name);
        try telemetry.milestone(&log, outcome.name, outcome.saved);
        if (outcome.is_naturals) try telemetry.naturals(&log);
        if (outcome.is_btree) try telemetry.binaryTrees(&log);
        if (outcome.verified) {
            try log.writeAll("[VERIFY] PASS — the invented recursor reproduces every original and every observed count.\n");
        } else {
            try log.writeAll("[VERIFY] FAIL — behaviour mismatch; invention NOT trustworthy.\n");
        }
        try telemetry.compression(&log, outcome.old_total, outcome.new_total);
    } else {
        try telemetry.noProposal(&log);
    }

    try telemetry.librarySummary(&log, lib.typeCount(), lib.combinatorCount(), lib.totalNodeCount());
    try log.print("[SANDBOX] complete. Full simulation log: {s}\n", .{log.path});
}

/// Parse `<seed> [count] [max] [linear|branching]` from argv; fall back to defaults.
fn parseConfig(a: std.mem.Allocator) !Config {
    const args = try std.process.argsAlloc(a);
    var cfg = Config{ .seed = DEFAULT_SEED, .rows = DEFAULT_ROWS, .max_cluster = DEFAULT_MAX_CLUSTER, .mode = .linear };
    if (args.len >= 2) cfg.seed = parseU64(args[1]) orelse DEFAULT_SEED;
    if (args.len >= 3) cfg.rows = @intCast(parseU64(args[2]) orelse DEFAULT_ROWS);
    if (args.len >= 4) cfg.max_cluster = @max(1, @as(usize, @intCast(parseU64(args[3]) orelse DEFAULT_MAX_CLUSTER)));
    if (args.len >= 5) {
        if (std.mem.eql(u8, args[4], "branching")) cfg.mode = .branching;
        if (std.mem.eql(u8, args[4], "linear")) cfg.mode = .linear;
    }
    return cfg;
}

fn parseU64(s: []const u8) ?u64 {
    if (std.mem.startsWith(u8, s, "0x")) return std.fmt.parseInt(u64, s[2..], 16) catch null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}

/// Type-check `identity` and evaluate `identity unit` so the run shows the base
/// kernel is real, not stubbed.
fn selfCheck(lib: *library.Library, log: *Logger) !void {
    const a = lib.a;
    const body = checker.RawTerm{ .tag = .Var, .idx = 0 };
    const id = checker.RawTerm{ .tag = .Lam, .dom = lib.unit, .a = &body };
    const expected = try types.Type.mkFun(a, lib.unit, lib.unit);
    const typed = checker.check(lib, &.{}, &id, expected) catch {
        try log.writeAll("[CHECK] identity FAILED to type-check\n");
        return;
    };
    const u = try terms.Term.unitIntro(a, lib.unit);
    const applied = try terms.Term.app(a, typed, u, lib.unit);
    const reduced = try evaluator.eval(a, applied, 100);
    try log.print("[CHECK] identity : (Unit -> Unit) verified; (identity unit) reduces to {s}.\n", .{@tagName(reduced.tag)});
}

test {
    _ = @import("types.zig");
    _ = @import("terms.zig");
    _ = @import("nodecount.zig");
    _ = @import("library.zig");
    _ = @import("checker.zig");
    _ = @import("evaluator.zig");
    _ = @import("world.zig");
    _ = @import("mcts.zig");
    _ = @import("antiunify.zig");
    _ = @import("wpropose.zig");
    _ = @import("telemetry.zig");
    _ = @import("logger.zig");
}
