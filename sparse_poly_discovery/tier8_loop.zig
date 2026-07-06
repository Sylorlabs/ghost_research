//! Tier 8 orchestrator — Wave 0 baseline + strict-tax invention engine.
//! Run: zig build tier8-loop --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    try out.print("=== TIER 8 LOOP — Wave 0 + Tier 5 tax gate ===\n\n", .{});

    try out.print("── Pass A: production engine (tax off) ──\n", .{});
    eqtax.strict_enabled = false;
    eqtax.resetStats();
    const a = try ie.runBlindBattery(arena.allocator(), out, true, null);
    try out.print("  result: {d}/{d} evals={d}\n\n", .{ a.solved, a.total, a.evals });

    try out.print("── Pass B: strict tax gate v{d} (Tier 5) ──\n", .{eqtax.BASIS_VERSION});
    eqtax.strict_enabled = true;
    eqtax.resetStats();
    const b = try ie.runBlindBattery(arena.allocator(), out, true, null);
    try out.print("\n── Tier 5 tax summary ──\n", .{});
    try out.print("  solved: {d}/{d}\n", .{ b.solved, b.total });
    try out.print("  tax checked={d} novel={d} remix_blocked={d} rate={d:.1}%\n", .{
        eqtax.stats.checked,
        eqtax.stats.novel_allowed,
        eqtax.stats.remix_blocked,
        eqtax.stats.novelRate() * 100.0,
    });
    const phase1 = b.solved >= 8 and eqtax.stats.novelRate() >= 0.40;
    try out.print("  Phase 1 gate (≥8/11 solve, ≥40% novel): {}\n", .{phase1});
    try out.print("  WAVE 0+1 VERDICT: {s}\n", .{if (a.solved >= 10 and phase1) "PASS" else if (a.solved >= 10) "PARTIAL" else "FAIL"});
}