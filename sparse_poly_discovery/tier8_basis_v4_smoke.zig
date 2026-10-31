//! T8-AG-22f-v4 — Basis v4 smoke: family-conditioned tax + Phase 1 gate.
//! Run: zig build tier8-basis-v4 --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    eqtax.strict_enabled = true;
    eqtax.basis_level = 4;
    eqtax.reality_lane_enabled = true;
    eqtax.resetStats();
    eqtax.resetTaxLog();

    try out.print("=== T8-AG-22f-v4: Tax basis v4 smoke ===\n\n", .{});
    try out.print("BASIS_VERSION={d} family-conditioned remix + reality lane\n\n", .{eqtax.BASIS_VERSION});

    const summary = try ie.runBlindBattery(arena.allocator(), out, true, null);
    const rate = eqtax.stats.novelRate();
    const phase1_survivors = eqtax.stats.novel_allowed >= 3;
    const phase1_rate = rate >= 0.40;
    const pass = summary.solved >= 8 and (phase1_survivors or phase1_rate);

    try out.print("\n── Phase 1 gate ──\n", .{});
    try out.print("  solve: {d}/{d}\n", .{ summary.solved, summary.total });
    try out.print("  tax survivors: {d} (need ≥3)\n", .{eqtax.stats.novel_allowed});
    try out.print("  novel rate: {d:.1}% (need ≥40%)\n", .{rate * 100.0});
    try out.print("  PHASE 1: {s}\n", .{if (pass) "PASS" else "FAIL"});
}