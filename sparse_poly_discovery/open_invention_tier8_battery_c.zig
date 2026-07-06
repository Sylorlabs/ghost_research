//! T8-AG-11 — Battery C: hard predicates outside deg2 monomial closure.
//!
//! Targets from E2 POET + E14 composed family (xor, rank-stat, pipelines).
//! Pass: ≥8 targets, mean monomial-only coverage < 0.55.
//!
//! Run: zig build tier8-battery-c --release=fast

const std = @import("std");
const e2 = @import("open_invention_e2.zig");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");

pub const GRID_SEED = ie.GRID_SEED;
pub const MONO_THRESH: f64 = 0.55;
pub const MIN_TARGETS: usize = 8;

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

const ComposedKind = enum {
    inversion_parity,
    product_bind,
    rank2_eq1,
    max_parity,
};

pub const BatteryCTarget = struct {
    name: []const u8,
    e2_spec: ?e2.PredSpec = null,
    composed: ?ComposedKind = null,
    family: []const u8,
};

fn rank2Triple(a: u8, b: u8, c: u8) u8 {
    var s = [_]u8{ a, b, c };
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    return s[1];
}

fn inversionCount(g: [8]u8) usize {
    var inv: usize = 0;
    for (0..8) |i| for (i + 1..8) |j| {
        if (g[i] > g[j]) inv += 1;
    };
    return inv;
}

fn gridSum(g: [8]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}

fn countGE(g: [8]u8, thresh: u8) f64 {
    var c: usize = 0;
    for (g) |v| {
        if (v >= thresh) c += 1;
    }
    return @floatFromInt(c);
}

fn maxCell(g: [8]u8) u8 {
    var m: u8 = 0;
    for (g) |v| m = @max(m, v);
    return m;
}

fn labelComposed(g: [8]u8, kind: ComposedKind) f64 {
    return switch (kind) {
        .inversion_parity => @floatFromInt(inversionCount(g) & 1),
        .product_bind => if (@as(usize, g[0]) * g[1] > 12) 1.0 else 0.0,
        .rank2_eq1 => if (rank2Triple(g[0], g[1], g[2]) == 1) 1.0 else 0.0,
        .max_parity => @floatFromInt(@as(usize, maxCell(g)) & 1),
    };
}

pub fn labelTarget(g: [8]u8, t: BatteryCTarget) f64 {
    if (t.e2_spec) |spec| return e2.label(g, spec);
    return labelComposed(g, t.composed.?);
}

pub const BATTERY_C = [_]BatteryCTarget{
    .{ .name = "C01 XOR 0x0F", .e2_spec = .{ .kind = .xor_cells, .mask = 0x0F }, .family = "xor_popcount" },
    .{ .name = "C02 parity XOR 0x33", .e2_spec = .{ .kind = .parity_xor, .mask = 0x33 }, .family = "xor_popcount" },
    .{ .name = "C03 XOR 0x55", .e2_spec = .{ .kind = .xor_cells, .mask = 0x55 }, .family = "xor_popcount" },
    .{ .name = "C04 XOR 0xAA", .e2_spec = .{ .kind = .xor_cells, .mask = 0xAA }, .family = "xor_popcount" },
    .{ .name = "C05 XOR 0x3C", .e2_spec = .{ .kind = .xor_cells, .mask = 0x3C }, .family = "xor_popcount" },
    .{ .name = "C06 XOR 0x66", .e2_spec = .{ .kind = .xor_cells, .mask = 0x66 }, .family = "xor_popcount" },
    .{ .name = "C07 XOR 0x99", .e2_spec = .{ .kind = .xor_cells, .mask = 0x99 }, .family = "xor_popcount" },
    .{ .name = "C08 parity count", .e2_spec = .{ .kind = .parity_count }, .family = "mod_synthesis" },
    .{ .name = "C09 inv parity", .composed = .inversion_parity, .family = "pipeline" },
    .{ .name = "C10 parity XOR 0x0F", .e2_spec = .{ .kind = .parity_xor, .mask = 0x0F }, .family = "xor_popcount" },
    .{ .name = "C11 XOR 0x37", .e2_spec = .{ .kind = .xor_cells, .mask = 0x37 }, .family = "xor_popcount" },
};

pub const BatteryCResult = struct {
    n_targets: usize,
    mean_mono_cov: f64,
    hard_targets: usize,
    pass: bool,
};

pub fn measureMonomialCoverage(
    X: [][]f64,
    grid: []const [8]u8,
    trained_lib: []const rq1.Feature,
    Y: []const f64,
    phiTgt: []f64,
    w_in: []const f64,
) f64 {
    var w: [33]f64 = undefined;
    @memcpy(w[0..w_in.len], w_in);
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(trained_lib, &lib, &nlib);

    var cov = ui.measureCoverage(X, grid, lib[0..nlib], Y, w[0..]);
    if (cov >= ie.COVER) return cov;

    var round: usize = 0;
    while (round < 6) : (round += 1) {
        if (ui.tryMonomialForge(X, grid, &lib, &nlib, Y, phiTgt, w[0..], SilentOut{}, true) catch false) {
            cov = ui.measureCoverage(X, grid, lib[0..nlib], Y, w[0..]);
            if (cov >= ie.COVER) return cov;
        } else break;
    }
    return cov;
}

pub fn runBatteryC(alloc: std.mem.Allocator, out: anytype) !BatteryCResult {
    const prep = try ie.prepareBlindBattery(alloc, SilentOut{});
    const ctx = prep.ctx;

    try out.print("=== T8-AG-11: Battery C (outside deg2 monomial closure) ===\n\n", .{});
    try out.print("Grid seed 0x{X:0>16} | targets={d}\n", .{ GRID_SEED, BATTERY_C.len });
    try out.print("PASS bar: ≥{d} targets, mean mono coverage <{d:.2}\n\n", .{ MIN_TARGETS, MONO_THRESH });

    var sum_cov: f64 = 0;
    var hard: usize = 0;

    for (BATTERY_C) |tgt| {
        const Yb = try alloc.alloc(f64, rq1.NSAMP);
        for (0..rq1.NSAMP) |s| Yb[s] = labelTarget(ctx.grid[s], tgt);
        const mono_cov = measureMonomialCoverage(ctx.X, ctx.grid, prep.trained_lib, Yb, ctx.phiTgt, ctx.w[0..]);
        sum_cov += mono_cov;
        if (mono_cov < MONO_THRESH) hard += 1;
        try out.print("  {s} [{s}] mono_cov={d:.3}\n", .{ tgt.name, tgt.family, mono_cov });
        alloc.free(Yb);
    }

    const mean = sum_cov / @as(f64, @floatFromInt(BATTERY_C.len));
    const pass = BATTERY_C.len >= MIN_TARGETS and mean < MONO_THRESH;

    try out.print("\n════════════════════ SUMMARY ════════════════════\n", .{});
    try out.print("  targets: {d}\n", .{BATTERY_C.len});
    try out.print("  hard (mono<{d:.2}): {d}/{d}\n", .{ MONO_THRESH, hard, BATTERY_C.len });
    try out.print("  mean mono coverage: {d:.3}\n", .{mean});
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});

    return .{
        .n_targets = BATTERY_C.len,
        .mean_mono_cov = mean,
        .hard_targets = hard,
        .pass = pass,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();
    _ = try runBatteryC(arena.allocator(), out);
}