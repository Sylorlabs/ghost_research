//! Production invention engine — single entrypoint for blind battery B.
//!
//! Ladder (verifier-certified, growable library):
//!   monomial saturation → growable pair menu (certify+promote) → mod/pipeline (targeted)
//!   → conditional Walsh → operator menu → world pool
//!
//! Seeds: grid 0xF0235A11CE0FF1CE, battery 0xE1B10D20A11CE01 (same as RQ1++).
//!
//! Run: zig build invention-engine --release=fast

const std = @import("std");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");

pub const GRID_SEED = rq1.GRID_SEED;
pub const BATTERY_SEED = rq1.BATTERY_SEED;
pub const COVER = rq1.COVER;
pub const EvalCounter = rq1.EvalCounter;

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

pub const BlindSolveResult = struct {
    solved: bool,
    cov: f64,
    source: ui.Source,
    label: []const u8,
};

pub const BlindBatterySummary = struct {
    solved: usize,
    total: usize,
    evals: usize,
    final_nlib: usize,
};

pub fn seedUiFromRq1(rq1_lib: []const rq1.Feature, ui_lib: []ui.Feature, nlib: *usize) void {
    nlib.* = 0;
    for (rq1_lib) |f| {
        ui_lib[nlib.*] = .{ .monomial = f.monomial };
        nlib.* += 1;
    }
}

/// Solve one blind battery target with growable menu + targeted escalation.
pub fn solveBlindTarget(
    X: [][]f64,
    grid: []const [8]u8,
    lib: []ui.Feature,
    nlib: *usize,
    Y: []const f64,
    phiTgt: []f64,
    w: []f64,
    tgt: rq1.BatteryTarget,
    bank: anytype,
    S_store: *const [rq1.N_INNER1][]f64,
    pf: []const []f64,
    feat: []f64,
    budget: *EvalCounter,
    out: anytype,
    quiet: bool,
) !BlindSolveResult {
    budget.fit += 1;
    const cov0 = ui.measureCoverage(X, grid, lib[0..nlib.*], Y, w);
    if (cov0 >= COVER) {
        return .{ .solved = true, .cov = cov0, .source = .base, .label = "frozen/grown monomials" };
    }

    const m = ui.solveOneTarget(X, grid, lib, nlib, Y, phiTgt, w, out, quiet);
    budget.certify += m.iters_to_certify;
    budget.probe += 2;
    if (m.solved) {
        return .{ .solved = true, .cov = m.cov, .source = m.source, .label = "unified escalation" };
    }

    if (rq1.needsMod(tgt.kind)) {
        var rq_frozen: [32]rq1.Feature = undefined;
        for (0..nlib.*) |i| rq_frozen[i] = .{ .monomial = lib[i].monomial };
        if (try rq1.tryModEscalation(X, grid, rq_frozen[0..nlib.*], Y, bank, S_store, w, cov0, tgt, out, budget)) |ev| {
            if (ev.certified) {
                return .{ .solved = true, .cov = ev.test_acc, .source = .menu, .label = ev.label };
            }
        }
    }

    var rq_frozen2: [32]rq1.Feature = undefined;
    for (0..nlib.*) |i| rq_frozen2[i] = .{ .monomial = lib[i].monomial };
    if (try rq1.tryPairWalshEscalation(grid, rq_frozen2[0..nlib.*], Y, pf, feat, w, cov0, tgt, out, budget)) |ev| {
        if (ev.certified) {
            const src: ui.Source = switch (ev.method) {
                .pair_router => .pair,
                .walsh_corr => .walsh,
                else => .menu,
            };
            return .{ .solved = true, .cov = ev.test_acc, .source = src, .label = ev.label };
        }
    }

    return .{ .solved = false, .cov = m.cov, .source = .base, .label = "saturated" };
}

pub const BlindBatteryCtx = struct {
    grid: [][8]u8,
    X: [][]f64,
    phiTgt: []f64,
    w: [33]f64,
    bank: rq1.ProgBank,
    S_store: [rq1.N_INNER1][]f64,
    pf: [][]f64,
    feat: []f64,
    battery: []rq1.BatteryTarget,
};

pub fn prepareBlindBattery(alloc: std.mem.Allocator, out: anytype) !struct {
    ctx: BlindBatteryCtx,
    trained_lib: []const rq1.Feature,
    trained_nlib: usize,
} {
    var prng = std.Random.DefaultPrng.init(GRID_SEED);
    const rand = prng.random();

    const grid = try alloc.alloc([8]u8, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| {
        for (0..8) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, 5);
    }

    const X = try alloc.alloc([]f64, rq1.NSAMP);
    const phiTgt = try alloc.alloc(f64, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| X[s] = try alloc.alloc(f64, 32);
    var w_store: [33]f64 = undefined;

    const Yzoo = try alloc.alloc([]f64, 4);
    const zoo_masks = [_]u8{ (1 << 2) | (1 << 5), (1 << 1) | (1 << 3) | (1 << 6), (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7), (1 << 3) };
    for (0..4) |t| {
        Yzoo[t] = try alloc.alloc(f64, rq1.NSAMP);
        for (0..rq1.NSAMP) |s| {
            var p: f64 = 1.0;
            for (0..8) |i| {
                if (zoo_masks[t] & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(grid[s][i])) - 2.5);
            }
            Yzoo[t][s] = if (p > 0) 1.0 else 0.0;
        }
    }

    const trained = try rq1.trainZooA(X, grid, Yzoo, phiTgt, &w_store, out);
    const bank = try rq1.buildProgBank(alloc);
    const S_store = try rq1.buildInner1Store(alloc, grid);
    const pf = try alloc.alloc([]f64, rq1.NSAMP);
    for (0..rq1.NSAMP) |s| pf[s] = try alloc.alloc(f64, 3);
    const feat = try alloc.alloc(f64, rq1.NSAMP);

    var bprng = std.Random.DefaultPrng.init(BATTERY_SEED);
    const battery = try rq1.generateBatteryB(bprng.random(), alloc);

    return .{
        .ctx = .{
            .grid = grid,
            .X = X,
            .phiTgt = phiTgt,
            .w = w_store,
            .bank = bank,
            .S_store = S_store,
            .pf = pf,
            .feat = feat,
            .battery = battery,
        },
        .trained_lib = trained.lib[0..trained.nlib],
        .trained_nlib = trained.nlib,
    };
}

/// Run blind battery B from prepared context; counts only battery-phase evals in `budget`.
pub fn runBlindBatteryOnCtx(
    ctx: *BlindBatteryCtx,
    trained_lib: []const rq1.Feature,
    out: anytype,
    verbose: bool,
    budget: ?*EvalCounter,
) !BlindBatterySummary {
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    seedUiFromRq1(trained_lib, &lib, &nlib);

    var local_budget = EvalCounter{};
    const b = if (budget) |bp| bp else &local_budget;

    if (verbose) {
        try out.print("=== INVENTION ENGINE: blind battery B (growable menu production path) ===\n\n", .{});
        try out.print("Grid seed 0x{X:0>16} | battery seed 0x{X:0>16}\n", .{ GRID_SEED, BATTERY_SEED });
        try out.print("Ladder: mono forge → growable pair → mod/pipeline (targeted) → Walsh → menu → world\n", .{});
        try out.print("PASS bar: ≥10/11 certified at test ≥{d:.2}\n\n", .{COVER});
    }

    var solved: usize = 0;
    for (ctx.battery) |tgt| {
        const Yb = try std.heap.page_allocator.alloc(f64, rq1.NSAMP);
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);
        if (verbose) try out.print("  TARGET: {s} [{s}]\n", .{ tgt.name, @tagName(tgt.kind) });
        const r = if (verbose)
            try solveBlindTarget(ctx.X, ctx.grid, &lib, &nlib, Yb, ctx.phiTgt, ctx.w[0..], tgt, ctx.bank, &ctx.S_store, ctx.pf, ctx.feat, b, out, false)
        else
            try solveBlindTarget(ctx.X, ctx.grid, &lib, &nlib, Yb, ctx.phiTgt, ctx.w[0..], tgt, ctx.bank, &ctx.S_store, ctx.pf, ctx.feat, b, SilentOut{}, true);
        if (r.solved) solved += 1;
        if (verbose) {
            try out.print("    → {s} {s} cov={d:.3} library={d}\n\n", .{
                if (r.solved) "CERTIFIED" else "SATURATED",
                r.label,
                r.cov,
                nlib,
            });
        }
        std.heap.page_allocator.free(Yb);
    }

    if (verbose) {
        try out.print("════════════════════ SUMMARY ════════════════════\n", .{});
        try out.print("  certified: {d}/{d}\n", .{ solved, ctx.battery.len });
        try out.print("  battery evals: {d}\n", .{b.total()});
        try out.print("  final library: {d} features (growable promotions)\n", .{nlib});
        try out.print("  VERDICT: {s}\n", .{if (solved >= 10) "PASS" else "FAIL"});
    }

    return .{ .solved = solved, .total = ctx.battery.len, .evals = b.total(), .final_nlib = nlib };
}

/// Run full blind battery B with persistent growable feature library.
pub fn runBlindBattery(
    alloc: std.mem.Allocator,
    out: anytype,
    verbose: bool,
    budget: ?*EvalCounter,
) !BlindBatterySummary {
    var prep = try prepareBlindBattery(alloc, SilentOut{});
    return runBlindBatteryOnCtx(&prep.ctx, prep.trained_lib, out, verbose, budget);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();
    _ = try runBlindBattery(arena.allocator(), out, true, null);
}