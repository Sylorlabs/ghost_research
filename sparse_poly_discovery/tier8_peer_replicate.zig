//! T8-AG-30 — Peer replication: tax survivor across independent seeds.
//! Run: zig build tier8-peer-replicate --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");
const ui = @import("unified_invention.zig");

const SEEDS = [_]u64{ 0xE11C0DE20260629, 0xA7C0DE20260629, ie.GRID_SEED };

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const survivor: ui.Feature = .{ .world_sum_mod = 7 };
    eqtax.strict_enabled = true;
    eqtax.basis_level = 3;

    try out.print("=== T8-AG-30: Peer replication protocol ===\n\n", .{});

    var replicates: usize = 0;
    for (SEEDS) |seed| {
        const prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
        var lib: [32]ui.Feature = undefined;
        var nlib: usize = 0;
        ie.seedUiFromRq1(prep.trained_lib, &lib, &nlib);
        const Y = try alloc.alloc(f64, ui.NSAMP);
        for (0..ui.NSAMP) |s| {
            var sum: usize = 0;
            for (0..8) |i| sum += prep.ctx.grid[s][i];
            Y[s] = if (sum % 7 == 0) 1.0 else 0.0;
        }
        const w = eqtax.witnessRemix(prep.ctx.grid, lib[0..nlib], survivor, Y);
        const ok = w.verdict == .novel;
        if (ok) replicates += 1;
        try out.print("  seed 0x{X:0>16}: {s}\n", .{ seed, if (ok) "SURVIVOR" else "remix" });
    }

    const pass = replicates >= 2;
    try out.print("\n  replicates: {d}/{d}\n", .{ replicates, SEEDS.len });
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}