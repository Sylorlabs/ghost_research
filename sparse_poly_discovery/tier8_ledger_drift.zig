//! T8-AG-19 — Replay promotion ledger; detect basis drift.
//!
//! PASS: 0 v3 re-replay flips; flags retroactive remix under narrower basis.
//!
//! Run: zig build tier8-ledger-drift --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");
const ledger = @import("invention_ledger.zig");
const ui = @import("unified_invention.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    ledger.enabled = true;
    ledger.resetLedger();
    try ledger.openLedger();
    defer ledger.closeLedger();

    eqtax.strict_enabled = true;
    eqtax.basis_level = 3;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    try out.print("=== T8-AG-19: Ledger drift replay ===\n\n", .{});

    var prep = try ie.prepareBlindBattery(arena.allocator(), SilentOut{});
    const summary = try ie.runBlindBatteryOnCtx(&prep.ctx, prep.trained_lib, SilentOut{}, false, null);
    const grid = prep.ctx.grid;

    var drift_flips: usize = 0;
    var retroactive_novel: usize = 0;

    for (0..eqtax.replay_n) |i| {
        const cap = eqtax.replay_captures[i];
        const Y = eqtax.replay_pool[i][0..ui.NSAMP];

        const r3 = eqtax.witnessRemixAtLevel(grid, cap.lib[0..cap.nlib], cap.cand, Y, 3);
        if (r3.verdict != cap.verdict) drift_flips += 1;

        if (cap.verdict == .remix) {
            const r2 = eqtax.witnessRemixAtLevel(grid, cap.lib[0..cap.nlib], cap.cand, Y, 2);
            if (r2.verdict == .novel) retroactive_novel += 1;
        }
    }

    const ls = ledger.summarize();

    try out.print("  battery solve: {d}/{d}\n", .{ summary.solved, summary.total });
    try out.print("  replay captures: {d}\n", .{eqtax.replay_n});
    try out.print("  ledger records: {d}\n", .{ls.total});
    try out.print("  v3 re-replay drift flips: {d}\n", .{drift_flips});
    try out.print("  retroactive novel (v3 remix → v2 novel): {d}\n", .{retroactive_novel});
    const pass = drift_flips == 0 and eqtax.replay_n > 0;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}