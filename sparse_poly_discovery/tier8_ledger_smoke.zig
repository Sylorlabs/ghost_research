//! T8-AG-18 smoke — promotion ledger on strict-tax battery B run.
//! Run: zig build tier8-ledger-smoke --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");
const ledger = @import("invention_ledger.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    ledger.enabled = true;
    ledger.resetLedger();
    try ledger.openLedger();
    defer ledger.closeLedger();

    eqtax.strict_enabled = true;
    eqtax.resetStats();
    eqtax.resetTaxLog();

    try out.print("=== T8-AG-18: Promotion ledger smoke ===\n\n", .{});

    const summary = try ie.runBlindBattery(arena.allocator(), out, false, null);
    const ls = ledger.summarize();

    try out.print("\n── Ledger ──\n", .{});
    try out.print("  path: {s}\n", .{ledger.path});
    try out.print("  records: {d}\n", .{ls.total});
    try out.print("  survivors: {d}\n", .{ls.survivors});
    try out.print("  blocked: {d}\n", .{ls.blocked});
    try out.print("  battery: {d}/{d}\n", .{ summary.solved, summary.total });
    const pass = ls.total > 0 and ls.total == eqtax.stats.checked;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}