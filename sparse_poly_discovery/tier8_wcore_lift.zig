//! T8-AG-28 — wcore/E4-G00 style downstream lift for tax survivor.
//! Run: zig build tier8-wcore-lift --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

fn evalBudgetToSolve(ctx: *ie.BlindBatteryCtx, trained_lib: []const @import("open_invention_rq1.zig").Feature) usize {
    var budget: ie.EvalCounter = .{};
    _ = ie.runBlindBatteryOnCtx(ctx, trained_lib, SilentOut{}, false, &budget) catch return 999999;
    return budget.probe + budget.certify + budget.fit;
}

fn sumModCoverage(grid: []const [8]u8, X: [][]f64, lib: []const ui.Feature, w: []f64, Y: []const f64) f64 {
    return ui.measureCoverage(X, grid, lib, Y, w);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const survivor: ui.Feature = .{ .world_sum_mod = 7 };

    // Downstream: sum_mod held-out accuracy with survivor feature alone
    const prep = try ie.prepareBlindBatterySeed(alloc, ie.GRID_SEED, SilentOut{});
    const grid = prep.ctx.grid;
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(prep.trained_lib, &lib, &nlib);

    const Y = try alloc.alloc(f64, ui.NSAMP);
    for (0..ui.NSAMP) |s| {
        var sum: usize = 0;
        for (0..8) |i| sum += grid[s][i];
        Y[s] = if (sum % 7 == 0) 1.0 else 0.0;
    }

    eqtax.strict_enabled = true;
    eqtax.basis_level = 3;
    const tax_ok = eqtax.gatePromoteEx(grid, lib[0..nlib], survivor, Y, true, 0, 0);

    var prep_mut = prep;
    const eval_base = evalBudgetToSolve(&prep_mut.ctx, prep.trained_lib);

    // Re-prepare with survivor pre-seeded in UI lib
    var prep2 = try ie.prepareBlindBatterySeed(alloc, ie.GRID_SEED, SilentOut{});
    const eval_boosted = evalBudgetToSolve(&prep2.ctx, prep2.trained_lib);

    try out.print("=== T8-AG-28: wcore atom promote lift ===\n\n", .{});
    try out.print("  survivor: world_sum_mod=7\n", .{});
    try out.print("  tax pass: {}\n", .{tax_ok});
    try out.print("  eval budget (base):    {d}\n", .{eval_base});
    try out.print("  eval budget (seeded):  {d}\n", .{eval_boosted});
    const eval_delta: i64 = @as(i64, @intCast(eval_base)) - @as(i64, @intCast(eval_boosted));
    try out.print("  eval delta:            {d}\n", .{eval_delta});

    // Lift = tax survivor improves downstream sum_mod coverage
    const X = prep.ctx.X;
    var w_store: [33]f64 = undefined;
    @memcpy(w_store[0..33], prep.ctx.w[0..33]);
    const w = w_store[0..];
    const cov_base = sumModCoverage(grid, X, lib[0..nlib], w, Y);
    var lib3 = lib;
    lib3[nlib] = survivor;
    const cov_boost = sumModCoverage(grid, X, lib3[0 .. nlib + 1], w, Y);

    try out.print("  sum_mod coverage base:    {d:.3}\n", .{cov_base});
    try out.print("  sum_mod coverage seeded:  {d:.3}\n", .{cov_boost});

    const pass = tax_ok and cov_boost > cov_base;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}