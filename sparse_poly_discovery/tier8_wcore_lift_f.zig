//! T8-AG-28f — Minimal promote set lift (world_sum_mod=7 only on sum_mod).
//! Run: zig build tier8-wcore-lift-f --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const ui = @import("unified_invention.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    var prep = try ie.prepareBlindBatterySeed(arena.allocator(), ie.GRID_SEED, SilentOut{});
    const grid = prep.ctx.grid;
    const X = prep.ctx.X;
    const w = prep.ctx.w[0..];

    const minimal_lib = [_]ui.Feature{.{ .world_sum_mod = 7 }};
    const Y = try arena.allocator().alloc(f64, ui.NSAMP);
    for (0..ui.NSAMP) |s| {
        var sum: usize = 0;
        for (0..8) |i| sum += grid[s][i];
        Y[s] = if (sum % 7 == 0) 1.0 else 0.0;
    }

    const cov = ui.measureCoverage(X, grid, &minimal_lib, Y, w);
    const pass = cov >= ui.COVER_THRESHOLD;

    try out.print("=== T8-AG-28f: Minimal promote set lift ===\n\n", .{});
    try out.print("  minimal lib: [world_sum_mod=7]\n", .{});
    try out.print("  sum_mod coverage: {d:.3} (threshold {d:.2})\n", .{ cov, ui.COVER_THRESHOLD });
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}