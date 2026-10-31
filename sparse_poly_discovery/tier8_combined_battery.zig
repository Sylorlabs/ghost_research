//! T8-AG-32b — Combined battery B+C invention with tax v4.
//! Run: zig build tier8-combined-battery --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const bc = @import("open_invention_tier8_battery_c.zig");
const bce = @import("tier8_battery_c_engine.zig");
const eqtax = @import("equivalence_tax.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    eqtax.strict_enabled = true;
    eqtax.basis_level = 4;
    eqtax.reality_lane_enabled = true;
    eqtax.resetStats();

    try out.print("=== T8-AG-32b: Combined battery B+C (tax v4) ===\n\n", .{});

    const b = try ie.runBlindBattery(arena.allocator(), out, false, null);
    const c = try bce.runBatteryCEngineEx(arena.allocator(), out, true, false);

    const survivors = eqtax.stats.novel_allowed;
    const rate = eqtax.stats.novelRate();
    const pass = b.solved >= 10 and c.invent_solved >= c.mono_solved and survivors >= 3;

    try out.print("\n── Combined summary ──\n", .{});
    try out.print("  battery B: {d}/{d}\n", .{ b.solved, b.total });
    try out.print("  battery C: invent {d}/{d} mono {d}/{d}\n", .{ c.invent_solved, c.total, c.mono_solved, c.total });
    try out.print("  tax survivors: {d} rate={d:.1}%\n", .{ survivors, rate * 100.0 });
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "PARTIAL"});
}