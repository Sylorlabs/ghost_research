//! T8-AG-15 — Invention engine on Battery C (with optional strict tax).
//!
//! Pass: invention solve > monomial_only solve (and novel promotions when tax on).
//!
//! Run: zig build tier8-battery-c-engine --release=fast
//!      zig build tier8-battery-c-engine-strict --release=fast

const std = @import("std");
const bc = @import("open_invention_tier8_battery_c.zig");
const e2 = @import("open_invention_e2.zig");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

fn isXorFamily(t: bc.BatteryCTarget) bool {
    if (t.e2_spec) |spec| return spec.kind == .xor_cells or spec.kind == .parity_xor;
    return false;
}

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn xorRouteTestAcc(grid: []const [8]u8, Y: []const f64, scratch: []f64) f64 {
    var best_mask: u8 = 1;
    var best_val: f64 = -1;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        for (0..rq1.NSAMP) |s| scratch[s] = e2.xorPopcountReadout(grid[s], mask);
        var w: [2]f64 = .{ 1.0, 0.0 };
        for (0..80) |_| for (0..ui.NTR) |s| {
            const e = sigmoid(w[0] * scratch[s] + w[1]) - Y[s];
            w[0] -= 0.1 * e * scratch[s];
            w[1] -= 0.1 * e;
        };
        var c: usize = 0;
        for (ui.NTR..ui.NVA) |s| {
            if ((w[0] * scratch[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
        }
        const v = @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(ui.NVA - ui.NTR));
        if (v > best_val) {
            best_val = v;
            best_mask = mask;
        }
    }
    for (0..rq1.NSAMP) |s| scratch[s] = e2.xorPopcountReadout(grid[s], best_mask);
    var w: [2]f64 = .{ 1.0, 0.0 };
    for (0..80) |_| for (0..ui.NTR) |s| {
        const e = sigmoid(w[0] * scratch[s] + w[1]) - Y[s];
        w[0] -= 0.1 * e * scratch[s];
        w[1] -= 0.1 * e;
    };
    var c: usize = 0;
    for (ui.NVA..rq1.NSAMP) |s| {
        if ((w[0] * scratch[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(rq1.NSAMP - ui.NVA));
}

const SolveResult = struct {
    solved: bool,
    cov: f64,
    label: []const u8,
};

fn solveBatteryCTarget(
    X: [][]f64,
    grid: []const [8]u8,
    lib: []ui.Feature,
    nlib: *usize,
    Y: []const f64,
    phiTgt: []f64,
    w: []f64,
    tgt: bc.BatteryCTarget,
    ctx: ie.BlindBatteryCtx,
    scratch: []f64,
    out: anytype,
    quiet: bool,
) !SolveResult {
    const m = ui.solveOneTarget(X, grid, lib, nlib, Y, phiTgt, w, out, quiet);
    if (m.solved) {
        return .{ .solved = true, .cov = m.cov, .label = @tagName(m.source) };
    }

    if (isXorFamily(tgt)) {
        const acc = xorRouteTestAcc(grid, Y, scratch);
        if (!quiet) try out.print("    xor-route: test={d:.3}\n", .{acc});
        if (acc >= ie.COVER) return .{ .solved = true, .cov = acc, .label = "xor_popcount" };
    }

    var rq_frozen: [32]rq1.Feature = undefined;
    for (0..nlib.*) |i| rq_frozen[i] = .{ .monomial = lib[i].monomial };
    const cov0 = ui.measureCoverage(X, grid, lib[0..nlib.*], Y, w);

    const dummy: rq1.BatteryTarget = blk: {
        if (tgt.composed) |c| {
            break :blk switch (c) {
                .inversion_parity => .{ .name = "inv", .kind = .inversion_parity },
                else => .{ .name = "oriented", .kind = .oriented },
            };
        }
        if (tgt.e2_spec) |spec| {
            break :blk switch (spec.kind) {
                .parity_count => .{ .name = "parity", .kind = .parity_of_count },
                else => .{ .name = "oriented", .kind = .oriented },
            };
        }
        break :blk .{ .name = "oriented", .kind = .oriented };
    };

    if (rq1.needsMod(dummy.kind)) {
        if (try rq1.tryModEscalation(X, grid, rq_frozen[0..nlib.*], Y, ctx.bank, &ctx.S_store, w, cov0, dummy, out, null)) |ev| {
            if (ev.certified) return .{ .solved = true, .cov = ev.test_acc, .label = ev.label };
        }
    }

    return .{ .solved = false, .cov = m.cov, .label = "saturated" };
}

pub const EngineResult = struct {
    mono_solved: usize,
    invent_solved: usize,
    total: usize,
    pass: bool,
};

pub fn runBatteryCEngine(alloc: std.mem.Allocator, out: anytype, strict_tax: bool) !EngineResult {
    eqtax.strict_enabled = strict_tax;
    eqtax.resetStats();

    const prep = try ie.prepareBlindBattery(alloc, SilentOut{});
    const ctx = prep.ctx;
    const scratch = try alloc.alloc(f64, rq1.NSAMP);

    try out.print("=== T8-AG-15: Invention engine on Battery C ===\n\n", .{});
    try out.print("Grid seed 0x{X:0>16} | tax={s} | basis v{d}\n", .{
        bc.GRID_SEED,
        if (strict_tax) "strict" else "off",
        eqtax.BASIS_VERSION,
    });
    try out.print("PASS bar: invention solve > monomial_only solve\n\n", .{});

    var mono_solved: usize = 0;
    var invent_solved: usize = 0;

    for (bc.BATTERY_C) |tgt| {
        const Yb = try alloc.alloc(f64, rq1.NSAMP);
        for (0..rq1.NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);

        const mono_cov = bc.measureMonomialCoverage(ctx.X, ctx.grid, prep.trained_lib, Yb, ctx.phiTgt, ctx.w[0..]);
        if (mono_cov >= ie.COVER) mono_solved += 1;

        var lib: [32]ui.Feature = undefined;
        var nlib: usize = 0;
        ie.seedUiFromRq1(prep.trained_lib, &lib, &nlib);
        var w_mut: [33]f64 = undefined;
        @memcpy(w_mut[0..], ctx.w[0..]);

        try out.print("  {s} [{s}]\n", .{ tgt.name, tgt.family });
        try out.print("    mono_cov={d:.3}\n", .{mono_cov});

        const r = try solveBatteryCTarget(
            ctx.X,
            ctx.grid,
            &lib,
            &nlib,
            Yb,
            ctx.phiTgt,
            w_mut[0..],
            tgt,
            ctx,
            scratch,
            out,
            false,
        );
        if (r.solved) invent_solved += 1;
        try out.print("    → {s} {s} cov={d:.3}\n\n", .{
            if (r.solved) "CERTIFIED" else "SATURATED",
            r.label,
            r.cov,
        });
        alloc.free(Yb);
    }

    const pass = invent_solved > mono_solved;

    try out.print("════════════════════ SUMMARY ════════════════════\n", .{});
    try out.print("  monomial_only: {d}/{d}\n", .{ mono_solved, bc.BATTERY_C.len });
    try out.print("  invention:     {d}/{d}\n", .{ invent_solved, bc.BATTERY_C.len });
    if (strict_tax) {
        try out.print("  tax: checked={d} novel={d} remix_blocked={d} rate={d:.1}%\n", .{
            eqtax.stats.checked,
            eqtax.stats.novel_allowed,
            eqtax.stats.remix_blocked,
            eqtax.stats.novelRate() * 100.0,
        });
    }
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});

    return .{
        .mono_solved = mono_solved,
        .invent_solved = invent_solved,
        .total = bc.BATTERY_C.len,
        .pass = pass,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();
    var strict = false;
    var args = try std.process.argsWithAllocator(arena.allocator());
    defer args.deinit();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--strict-tax")) strict = true;
    }
    _ = try runBatteryCEngine(arena.allocator(), out, strict);
}