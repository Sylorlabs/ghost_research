//! T8-AG-27 — Deploy feedback stub: promote → downstream metric delta.
//! Run: zig build tier8-deploy-feedback --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const ui = @import("unified_invention.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

fn sumModCoverage(grid: []const [8]u8, X: [][]f64, lib: []const ui.Feature, w: []f64) f64 {
    const Y = std.heap.page_allocator.alloc(f64, ui.NSAMP) catch return 0;
    defer std.heap.page_allocator.free(Y);
    for (0..ui.NSAMP) |s| {
        var gsum: usize = 0;
        for (0..8) |i| gsum += grid[s][i];
        Y[s] = if (gsum % 7 == 0) 1.0 else 0.0;
    }
    return ui.measureCoverage(X, grid, lib, Y, w);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    const prep = try ie.prepareBlindBatterySeed(arena.allocator(), ie.GRID_SEED, SilentOut{});
    const grid = prep.ctx.grid;
    const X = prep.ctx.X;
    var w: [33]f64 = undefined;
    @memcpy(w[0..33], prep.ctx.w[0..33]);

    var lib_base: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(prep.trained_lib, &lib_base, &nlib);

    var lib_promoted: [33]ui.Feature = undefined;
    @memcpy(lib_promoted[0..nlib], lib_base[0..nlib]);
    lib_promoted[nlib] = .{ .world_sum_mod = 7 };

    const cov_before = sumModCoverage(grid, X, lib_base[0..nlib], w[0..]);
    const cov_after = sumModCoverage(grid, X, lib_promoted[0 .. nlib + 1], w[0..]);

    try out.print("=== T8-AG-27: Deploy feedback stub ===\n\n", .{});
    try out.print("  downstream task: sum_mod (grid sum mod 7)\n", .{});
    try out.print("  coverage (base lib):       {d:.3}\n", .{cov_before});
    try out.print("  coverage (+ world_sum=7):  {d:.3}\n", .{cov_after});
    const delta = cov_after - cov_before;
    try out.print("  delta:                     {d:.3}\n", .{delta});

    const pass = cov_after > cov_before;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}