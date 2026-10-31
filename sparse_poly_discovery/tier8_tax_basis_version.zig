//! T8-AG-17 — Tax basis version registry + monotonic novel-rate audit.
//!
//! PASS: novel count is non-increasing as basis_level expands (1→2→3).
//!
//! Run: zig build tier8-basis-version --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");
const ui = @import("unified_invention.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

const BasisSpec = struct {
    level: u32,
    label: []const u8,
    xor: bool,
    pipeline: bool,
    mod_synth: bool,
};

const REGISTRY = [_]BasisSpec{
    .{ .level = 1, .label = "v1-static", .xor = false, .pipeline = false, .mod_synth = false },
    .{ .level = 2, .label = "v2-xor", .xor = true, .pipeline = false, .mod_synth = false },
    .{ .level = 3, .label = "v3-full", .xor = true, .pipeline = true, .mod_synth = true },
};

fn isNovel(w: eqtax.TaxEntry) bool {
    return w.verdict == .novel;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    eqtax.strict_enabled = true;
    eqtax.basis_level = 3;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    var prep = try ie.prepareBlindBattery(arena.allocator(), SilentOut{});
    _ = try ie.runBlindBatteryOnCtx(&prep.ctx, prep.trained_lib, SilentOut{}, false, null);
    const grid = prep.ctx.grid;

    try out.print("=== T8-AG-17: Tax basis version registry ===\n\n", .{});
    for (REGISTRY) |spec| {
        try out.print("  level {d}: {s} | xor={} pipe={} mod={}\n", .{
            spec.level, spec.label, spec.xor, spec.pipeline, spec.mod_synth,
        });
    }
    try out.print("\n  replay captures: {d}\n\n", .{eqtax.replay_n});

    var novel_at_level: [3]usize = .{0} ** 3;
    var violations: usize = 0;

    for (0..eqtax.replay_n) |i| {
        const cap = eqtax.replay_captures[i];
        const Yfull = eqtax.replay_pool[i][0..ui.NSAMP];

        var verdicts: [3]bool = .{false} ** 3;
        for (REGISTRY, 0..) |spec, li| {
            const w = eqtax.witnessRemixAtLevel(grid, cap.lib[0..cap.nlib], cap.cand, Yfull, spec.level);
            verdicts[li] = isNovel(w);
            if (verdicts[li]) novel_at_level[li] += 1;
        }
        // Monotonic: novel@L1 >= novel@L2 >= novel@L3 per capture
        if (verdicts[0] == false and verdicts[1]) violations += 1;
        if (verdicts[1] == false and verdicts[2]) violations += 1;
    }

    var monotonic_rates = true;
    var prev_rate: f64 = 1.1;
    for (REGISTRY, 0..) |spec, li| {
        const rate = if (eqtax.replay_n == 0) 0 else
            @as(f64, @floatFromInt(novel_at_level[li])) / @as(f64, @floatFromInt(eqtax.replay_n));
        if (rate > prev_rate) monotonic_rates = false;
        try out.print("  level {d} ({s}): novel={d}/{d} rate={d:.3}\n", .{
            spec.level, spec.label, novel_at_level[li], eqtax.replay_n, rate,
        });
        prev_rate = rate;
    }

    const pass = violations == 0 and monotonic_rates and eqtax.replay_n > 0;
    try out.print("\n  per-capture monotonic violations: {d}\n", .{violations});
    try out.print("  aggregate rate monotonic: {}\n", .{monotonic_rates});
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}