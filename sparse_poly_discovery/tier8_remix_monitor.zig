//! T8-AG-21 — Rolling remix rate monitor; alert when <20% over 5 runs.
//! Run: zig build tier8-remix-monitor --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");
const mon = @import("remix_rate_monitor.zig");

const RUN_SEEDS = [_]u64{
    ie.GRID_SEED,
    ie.GRID_SEED +% 1,
    ie.GRID_SEED +% 2,
    ie.GRID_SEED +% 3,
    ie.GRID_SEED +% 4,
};

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    try out.print("=== T8-AG-21: Remix rate monitor ===\n\n", .{});
    try out.print("Window: {d} runs | alert threshold: {d:.0}%\n\n", .{ mon.WINDOW, mon.ALERT_THRESHOLD * 100.0 });

    var rolling: mon.RollingMonitor = .{};
    eqtax.strict_enabled = true;
    eqtax.basis_level = 3;

    for (RUN_SEEDS, 0..) |seed, ri| {
        eqtax.resetStats();
        eqtax.resetTaxLog();
        eqtax.resetReplay();
        var prep = try ie.prepareBlindBatterySeed(arena.allocator(), seed, SilentOut{});
        _ = try ie.runBlindBatteryOnCtx(&prep.ctx, prep.trained_lib, SilentOut{}, false, null);
        const sample: mon.RunSample = .{
            .novel = eqtax.stats.novel_allowed,
            .checked = eqtax.stats.checked,
        };
        rolling.push(sample);
        try out.print("  run {d} seed=0x{X:0>16} checked={d} novel={d} rate={d:.1}%\n", .{
            ri + 1, seed, sample.checked, sample.novel, sample.rate() * 100.0,
        });
    }

    try out.print("\n  mean rate: {d:.1}%\n", .{rolling.meanRate() * 100.0});
    try out.print("  min rate:  {d:.1}%\n", .{rolling.minRate() * 100.0});
    const alert = rolling.alertFired();
    try out.print("  REMIX ALERT: {s}\n", .{if (alert) "FIRED (<20% sustained)" else "not fired"});
    const pass = alert;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}