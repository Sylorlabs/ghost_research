//! Baseline comparison — battery-B evals only (shared zoo-A lib, training not counted).
//!
//! Run: zig build invention-baseline-compare --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

const Mode = enum { invention, monomial_only, fixed_menu, random_search, no_verifier };

const ModeResult = struct {
    mode: Mode,
    solved: usize,
    total: usize,
    evals: usize,
};

fn modeName(m: Mode) []const u8 {
    return switch (m) {
        .invention => "invention",
        .monomial_only => "monomial_only",
        .fixed_menu => "fixed_menu",
        .random_search => "random_search",
        .no_verifier => "no_verifier",
    };
}

fn runMonomialOnly(
    ctx: *ie.BlindBatteryCtx,
    trained_lib: []const rq1.Feature,
    budget: *ie.EvalCounter,
) usize {
    const out = SilentOut{};
    var solved: usize = 0;
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(trained_lib, &lib, &nlib);

    for (ctx.battery) |tgt| {
        const Yb = std.heap.page_allocator.alloc(f64, rq1.NSAMP) catch unreachable;
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);

        budget.fit += 1;
        var cov = ui.measureCoverage(ctx.X, ctx.grid, lib[0..nlib], Yb, ctx.w[0..]);
        if (cov >= ie.COVER) {
            solved += 1;
            std.heap.page_allocator.free(Yb);
            continue;
        }

        var round: usize = 0;
        while (round < 6) : (round += 1) {
            budget.probe += 255;
            budget.certify += 1;
            if (ui.tryMonomialForge(ctx.X, ctx.grid, &lib, &nlib, Yb, ctx.phiTgt, ctx.w[0..], out, true) catch false) {
                cov = ui.measureCoverage(ctx.X, ctx.grid, lib[0..nlib], Yb, ctx.w[0..]);
                budget.fit += 1;
                if (cov >= ie.COVER) break;
            } else break;
        }
        if (cov >= ie.COVER) solved += 1;
        std.heap.page_allocator.free(Yb);
    }
    return solved;
}

fn runFixedMenu(ctx: *ie.BlindBatteryCtx, budget: *ie.EvalCounter) usize {
    var solved: usize = 0;
    for (ctx.battery) |tgt| {
        const Yb = std.heap.page_allocator.alloc(f64, rq1.NSAMP) catch unreachable;
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);
        var lib: [8]ui.Feature = undefined;
        for (0..8) |i| lib[i] = .{ .monomial = @as(u8, 1) << @intCast(i) };
        budget.fit += 1;
        if (ui.measureCoverage(ctx.X, ctx.grid, lib[0..8], Yb, ctx.w[0..]) >= ie.COVER) solved += 1;
        std.heap.page_allocator.free(Yb);
    }
    return solved;
}

fn runRandomSearch(ctx: *ie.BlindBatteryCtx, trained_lib: []const rq1.Feature, seed: u64, budget: *ie.EvalCounter) usize {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var solved: usize = 0;
    for (ctx.battery) |tgt| {
        const Yb = std.heap.page_allocator.alloc(f64, rq1.NSAMP) catch unreachable;
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);
        var found = false;
        var attempt: usize = 0;
        while (attempt < 500) : (attempt += 1) {
            const mask: u8 = @intCast(rand.intRangeAtMost(u16, 1, 255));
            if (@popCount(mask) < 1 or @popCount(mask) > 4) continue;
            var aug_buf: [33]rq1.Feature = undefined;
            @memcpy(aug_buf[0..trained_lib.len], trained_lib);
            aug_buf[trained_lib.len] = .{ .monomial = mask };
            budget.fit += 1;
            const cov_before = rq1.coverage(ctx.X, ctx.grid, trained_lib, Yb, ctx.w[0..]);
            budget.fit += 1;
            const cov_after = rq1.coverage(ctx.X, ctx.grid, aug_buf[0 .. trained_lib.len + 1], Yb, ctx.w[0..]);
            if (cov_after >= ie.COVER and cov_before < ie.COVER) {
                found = true;
                break;
            }
        }
        if (found) solved += 1;
        std.heap.page_allocator.free(Yb);
    }
    return solved;
}

fn runNoVerifier(ctx: *ie.BlindBatteryCtx, trained_lib: []const rq1.Feature, budget: *ie.EvalCounter) usize {
    var solved: usize = 0;
    for (ctx.battery) |tgt| {
        const Yb = std.heap.page_allocator.alloc(f64, rq1.NSAMP) catch unreachable;
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);
        budget.fit += 1;
        var best: f64 = rq1.coverage(ctx.X, ctx.grid, trained_lib, Yb, ctx.w[0..]);
        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const mask: u8 = @intCast(mm);
            if (@popCount(mask) < 1 or @popCount(mask) > 4) continue;
            budget.fit += 1;
            const cov = rq1.coverage(ctx.X, ctx.grid, trained_lib, Yb, ctx.w[0..]);
            if (cov > best) best = cov;
        }
        if (best >= ie.COVER) solved += 1;
        std.heap.page_allocator.free(Yb);
    }
    return solved;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== Baseline comparison (battery-B evals only) ===\n", .{});
    try out.print("grid_seed=0x{X:0>16} battery_seed=0x{X:0>16}\n", .{ ie.GRID_SEED, ie.BATTERY_SEED });
    try out.print("zoo-A training shared, NOT counted in eval columns\n\n", .{});

    var prep = try ie.prepareBlindBattery(alloc, SilentOut{});

    var inv_budget = ie.EvalCounter{};
    const inv = try ie.runBlindBatteryOnCtx(&prep.ctx, prep.trained_lib, SilentOut{}, false, &inv_budget);

    var mono_budget = ie.EvalCounter{};
    const mono_solved = runMonomialOnly(&prep.ctx, prep.trained_lib, &mono_budget);

    var fixed_budget = ie.EvalCounter{};
    const fixed_solved = runFixedMenu(&prep.ctx, &fixed_budget);

    var rand_budget = ie.EvalCounter{};
    const rand_solved = runRandomSearch(&prep.ctx, prep.trained_lib, ie.BATTERY_SEED ^ 0xDEAD, &rand_budget);

    var nover_budget = ie.EvalCounter{};
    const nover_solved = runNoVerifier(&prep.ctx, prep.trained_lib, &nover_budget);

    const results = [_]ModeResult{
        .{ .mode = .invention, .solved = inv.solved, .total = prep.ctx.battery.len, .evals = inv_budget.total() },
        .{ .mode = .monomial_only, .solved = mono_solved, .total = prep.ctx.battery.len, .evals = mono_budget.total() },
        .{ .mode = .fixed_menu, .solved = fixed_solved, .total = prep.ctx.battery.len, .evals = fixed_budget.total() },
        .{ .mode = .random_search, .solved = rand_solved, .total = prep.ctx.battery.len, .evals = rand_budget.total() },
        .{ .mode = .no_verifier, .solved = nover_solved, .total = prep.ctx.battery.len, .evals = nover_budget.total() },
    };

    try out.print("mode\tsolved\ttotal\tevals\n", .{});
    for (results) |r| try out.print("{s}\t{d}\t{d}\t{d}\n", .{ modeName(r.mode), r.solved, r.total, r.evals });

    const beats_solve = inv.solved > mono_solved and inv.solved > fixed_solved and inv.solved > rand_solved and inv.solved > nover_solved;
    try out.print("\n── verdict ──\n", .{});
    try out.print("invention beats all on solve rate: {}\n", .{beats_solve});
    try out.print("invention leaner than monomial: {} ({d} vs {d})\n", .{ inv_budget.total() < mono_budget.total(), inv_budget.total(), mono_budget.total() });
    try out.print("invention leaner than random: {} ({d} vs {d})\n", .{ inv_budget.total() < rand_budget.total(), inv_budget.total(), rand_budget.total() });
    try out.print("PASS: {}\n", .{beats_solve and inv.solved >= 10 and inv_budget.total() < mono_budget.total() and inv_budget.total() < rand_budget.total()});
}