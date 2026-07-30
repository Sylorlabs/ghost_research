//! Tier 8 BATTERY-D ABLATION — turn the C08 existence proof into an effect size.
//!
//! docs/research/tier8_ablation.md found the decisive band (ladder-reachable
//! escape + v3-tax-blockable) contained ~1 target (C08 "parity count") out of
//! 22. This harness (a) builds ~11 candidate targets in the same family
//! (tier8_battery_d.zig), (b) empirically classifies each one's band
//! membership (DECISIVE / TOO_EASY / TOO_HARD / OTHER) via a direct two-arm
//! probe at the production seed, then (c) re-runs the FULL two-arm ablation
//! (identical structure/seeds/trigger to tier8_ablation.zig -- Battery B
//! unchanged, Battery-C slot replaced by the DECISIVE subset of battery D)
//! at all 3 seeds, to measure the effect size on a battery designed to
//! detect it.
//!
//! Reads-only reuse of the tier8_ablation.zig two-arm harness *pattern*
//! (that file exposes no pub helpers to import; its structure -- arm state,
//! revision trigger, per-target row logging -- is reproduced here against
//! the new battery). No existing file modified.
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe tier8_ablation_d.zig -O ReleaseFast
//! Run:
//!   ./tier8_ablation_d
//!
//! Single-threaded, default stack (greedyFit's column store is heap-backed
//! as of commit 67fdd13 -- no 512MB worker-thread workaround needed).

const std = @import("std");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");
const bd = @import("tier8_battery_d.zig");
const cr = @import("closure_revision.zig");
const fv = @import("framework_vote.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

const SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };

const ALERT_THRESHOLD: f64 = 0.20;
const MIN_CHECKS: usize = 5;
const INITIAL_BASIS: u32 = 3;
const REVISED_BASIS: u32 = 4;

const N_B = 11;
const MAX_D = bd.BATTERY_D.len;
const MAX_TGT: usize = N_B + MAX_D;

const Arm = enum { off, on };

// ── Phase 1: band classification ─────────────────────────────────────────

const ClassResult = struct {
    off_solved: bool,
    off_cov: f64,
    off_source: []const u8,
    off_blocked: usize,
    on_solved: bool,
    on_cov: f64,
    on_source: []const u8,
    base_rate: f64,
    class: []const u8,
};

fn classifyOne(
    X: [][]f64,
    grid: []const [8]u8,
    trained_lib: []const rq1.Feature,
    phiTgt: []f64,
    tgt: bd.BatteryDTarget,
    Yb: []f64,
) ClassResult {
    for (0..rq1.NSAMP) |s| Yb[s] = bd.labelTarget(grid[s], tgt);

    // ARM-OFF: basis frozen v3, reality lane off, fresh library.
    eqtax.strict_enabled = true;
    eqtax.basis_level = INITIAL_BASIS;
    eqtax.reality_lane_enabled = false;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();
    var lib_off: [32]ui.Feature = undefined;
    var nlib_off: usize = 0;
    ie.seedUiFromRq1(trained_lib, &lib_off, &nlib_off);
    var w_off: [33]f64 = undefined;
    const b0 = eqtax.stats.remix_blocked;
    const off = ui.solveOneTarget(X, grid, &lib_off, &nlib_off, Yb, phiTgt, w_off[0..], SilentOut{}, true);
    const off_blocked = eqtax.stats.remix_blocked - b0;

    // ARM-ON: basis v4 + reality lane, fresh library (as if revision already fired).
    eqtax.basis_level = REVISED_BASIS;
    eqtax.reality_lane_enabled = true;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();
    var lib_on: [32]ui.Feature = undefined;
    var nlib_on: usize = 0;
    ie.seedUiFromRq1(trained_lib, &lib_on, &nlib_on);
    var w_on: [33]f64 = undefined;
    const on = ui.solveOneTarget(X, grid, &lib_on, &nlib_on, Yb, phiTgt, w_on[0..], SilentOut{}, true);

    const class: []const u8 = if (on.solved and !off.solved)
        "DECISIVE"
    else if (off.solved and on.solved)
        "TOO_EASY"
    else if (!off.solved and !on.solved)
        "TOO_HARD"
    else
        "OTHER";

    return .{
        .off_solved = off.solved,
        .off_cov = off.cov,
        .off_source = @tagName(off.source),
        .off_blocked = off_blocked,
        .on_solved = on.solved,
        .on_cov = on.cov,
        .on_source = @tagName(on.source),
        .base_rate = bd.baseRate(grid, tgt),
        .class = class,
    };
}

// ── Phase 2: full two-arm x 3-seed ablation on the decisive subset ──────

/// rq1 escalation labels are formatted into stack buffers inside the callee
/// and dangle by the time solveBlindTarget returns; keep only known-static
/// literals, otherwise substitute a stable class name. (Mirrors
/// tier8_ablation.zig's safeLabel -- same underlying hazard.)
fn safeLabel(label: []const u8) []const u8 {
    const known = [_][]const u8{
        "frozen/grown monomials", "unified escalation", "saturated",
        "base",                   "forge",              "pair",
        "walsh",                  "menu",               "world",
    };
    for (known) |k| if (std.mem.eql(u8, label, k)) return k;
    return "rq1_escalation";
}

const Row = struct {
    battery: []const u8,
    idx: usize,
    name: []const u8,
    solved: bool,
    cov: f64,
    label: []const u8,
    checked_d: usize,
    novel_d: usize,
    blocked_d: usize,
    nlib: usize,
    basis: u32,
};

const ArmRun = struct {
    rows: [MAX_TGT]Row = undefined,
    n: usize = 0,
    revision_fired_at: ?usize = null,
    checked: usize = 0,
    novel: usize = 0,
    blocked: usize = 0,
    b_solved: usize = 0,
    d_solved: usize = 0,
    evals_b: usize = 0,
    ms: i64 = 0,
};

fn taxonomyFromLog() cr.TaxonomyInput {
    var mono: usize = 0;
    var walsh: usize = 0;
    var pipe: usize = 0;
    var novel: usize = 0;
    for (0..eqtax.tax_log_n) |i| {
        const e = eqtax.tax_log[i];
        if (e.verdict == .novel) {
            novel += 1;
        } else switch (e.primary_family) {
            .monomial => mono += 1,
            .walsh => walsh += 1,
            .pipeline => pipe += 1,
            else => {},
        }
    }
    return .{
        .mono_remix = mono,
        .walsh_remix = walsh,
        .pipe_remix = pipe,
        .novel_count = novel,
        .checked = eqtax.stats.checked,
    };
}

fn maybeRevise(run: *ArmRun, global_idx: usize, out: anytype) !void {
    if (run.revision_fired_at != null) return;
    if (eqtax.stats.checked < MIN_CHECKS) return;
    if (eqtax.stats.novelRate() >= ALERT_THRESHOLD) return;
    const proposal = cr.proposeFromTaxonomy(taxonomyFromLog(), eqtax.basis_level);
    const vote = fv.voteOnProposal(proposal, .{
        .witness_id = "tier8-ablation-d-2026-07-10",
        .approved = true,
        .timestamp_seed = 0xAB1A20260710,
    }, false);
    if (!vote.recorded) return;
    eqtax.basis_level = REVISED_BASIS;
    eqtax.reality_lane_enabled = true;
    run.revision_fired_at = global_idx;
    try out.print("    [REVISION after target {d}: {s} v{d}->v{d}, rate={d:.1}% over {d} checks]\n", .{
        global_idx,
        proposal.id,
        proposal.tax_basis_from,
        REVISED_BASIS,
        eqtax.stats.novelRate() * 100.0,
        eqtax.stats.checked,
    });
}

fn runArm(alloc: std.mem.Allocator, seed: u64, arm: Arm, decisive: []const bd.BatteryDTarget, out: anytype) !ArmRun {
    var run: ArmRun = .{};
    const t0 = std.time.milliTimestamp();

    eqtax.strict_enabled = true;
    eqtax.basis_level = INITIAL_BASIS;
    eqtax.reality_lane_enabled = false;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    const prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
    var ctx = prep.ctx;

    // ── Battery B: full production engine, unchanged from tier8_ablation.zig ──
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(prep.trained_lib, &lib, &nlib);
    var budget = ie.EvalCounter{};

    var global_idx: usize = 0;
    for (ctx.battery) |tgt| {
        const Yb = try alloc.alloc(f64, rq1.NSAMP);
        defer alloc.free(Yb);
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);

        const c0 = eqtax.stats.checked;
        const n0 = eqtax.stats.novel_allowed;
        const r0 = eqtax.stats.remix_blocked;
        const res = try ie.solveBlindTarget(
            ctx.X,
            ctx.grid,
            &lib,
            &nlib,
            Yb,
            ctx.phiTgt,
            ctx.w[0..],
            tgt,
            ctx.bank,
            &ctx.S_store,
            ctx.pf,
            ctx.feat,
            &budget,
            SilentOut{},
            true,
        );
        if (res.solved) run.b_solved += 1;
        run.rows[run.n] = .{
            .battery = "B",
            .idx = global_idx,
            .name = tgt.name,
            .solved = res.solved,
            .cov = res.cov,
            .label = safeLabel(res.label),
            .checked_d = eqtax.stats.checked - c0,
            .novel_d = eqtax.stats.novel_allowed - n0,
            .blocked_d = eqtax.stats.remix_blocked - r0,
            .nlib = nlib,
            .basis = eqtax.basis_level,
        };
        run.n += 1;
        if (arm == .on) try maybeRevise(&run, global_idx, out);
        global_idx += 1;
    }
    run.evals_b = budget.total();

    // ── Battery D, decisive subset, ladder-only slice: fully tax-gated ──
    for (decisive) |tgt| {
        const Yb = try alloc.alloc(f64, rq1.NSAMP);
        defer alloc.free(Yb);
        for (0..rq1.NSAMP) |s| Yb[s] = bd.labelTarget(ctx.grid[s], tgt);

        var clib: [32]ui.Feature = undefined;
        var cnlib: usize = 0;
        ie.seedUiFromRq1(prep.trained_lib, &clib, &cnlib);
        var w_mut: [33]f64 = undefined;
        @memcpy(w_mut[0..], ctx.w[0..]);

        const c0 = eqtax.stats.checked;
        const n0 = eqtax.stats.novel_allowed;
        const r0 = eqtax.stats.remix_blocked;
        const m = ui.solveOneTarget(
            ctx.X,
            ctx.grid,
            &clib,
            &cnlib,
            Yb,
            ctx.phiTgt,
            w_mut[0..],
            SilentOut{},
            true,
        );
        if (m.solved) run.d_solved += 1;
        run.rows[run.n] = .{
            .battery = "D",
            .idx = global_idx,
            .name = tgt.name,
            .solved = m.solved,
            .cov = m.cov,
            .label = @tagName(m.source),
            .checked_d = eqtax.stats.checked - c0,
            .novel_d = eqtax.stats.novel_allowed - n0,
            .blocked_d = eqtax.stats.remix_blocked - r0,
            .nlib = cnlib,
            .basis = eqtax.basis_level,
        };
        run.n += 1;
        if (arm == .on) try maybeRevise(&run, global_idx, out);
        global_idx += 1;
    }

    run.checked = eqtax.stats.checked;
    run.novel = eqtax.stats.novel_allowed;
    run.blocked = eqtax.stats.remix_blocked;
    run.ms = std.time.milliTimestamp() - t0;
    return run;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/battery_d_2026_07_10.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("phase,seed,arm,battery,idx,target,solved,cov,label,checked_delta,novel_delta,remix_blocked_delta,nlib,basis_at_target,revision_fired_at,classification\n", .{});

    try out.print("=== TIER 8 BATTERY D: decisive-band construction + ablation ===\n\n", .{});

    // ── PHASE 1: band-membership classification (production seed) ──
    try out.print("---- PHASE 1: band classification (seed 0x{X:0>16}) ----\n", .{ie.GRID_SEED});
    const prep = try ie.prepareBlindBatterySeed(alloc, ie.GRID_SEED, SilentOut{});
    const ctx = prep.ctx;
    const Yb_scratch = try alloc.alloc(f64, rq1.NSAMP);

    var decisive_buf: [MAX_D]bd.BatteryDTarget = undefined;
    var n_decisive: usize = 0;

    for (bd.BATTERY_D, 0..) |tgt, i| {
        const r = classifyOne(ctx.X, ctx.grid, prep.trained_lib, ctx.phiTgt, tgt, Yb_scratch);
        try out.print("  {s:<24} base_rate={d:.3} | OFF {s:<6} cov={d:.3} src={s:<6} blocked={d} | ON {s:<6} cov={d:.3} src={s:<6} => {s}\n", .{
            tgt.name,       r.base_rate,
            if (r.off_solved) "SOLVE" else "stuck", r.off_cov, r.off_source, r.off_blocked,
            if (r.on_solved) "SOLVE" else "stuck",  r.on_cov,  r.on_source,
            r.class,
        });
        try cw.print("classify,0x{X:0>16},off,D,{d},\"{s}\",{d},{d:.4},{s},0,0,{d},0,{d},n/a,{s}\n", .{
            ie.GRID_SEED, i, tgt.name, @intFromBool(r.off_solved), r.off_cov, r.off_source, r.off_blocked, INITIAL_BASIS, r.class,
        });
        try cw.print("classify,0x{X:0>16},on,D,{d},\"{s}\",{d},{d:.4},{s},0,0,0,0,{d},n/a,{s}\n", .{
            ie.GRID_SEED, i, tgt.name, @intFromBool(r.on_solved), r.on_cov, r.on_source, REVISED_BASIS, r.class,
        });
        if (std.mem.eql(u8, r.class, "DECISIVE")) {
            decisive_buf[n_decisive] = tgt;
            n_decisive += 1;
        }
    }
    const decisive = decisive_buf[0..n_decisive];
    try out.print("\n  DECISIVE: {d}/{d} candidates -> ", .{ n_decisive, bd.BATTERY_D.len });
    for (decisive) |t| try out.print("[{s}] ", .{t.name});
    try out.print("\n\n", .{});

    if (n_decisive == 0) {
        try out.print("No decisive candidates found -- skipping Phase 2 (nothing to re-ablate).\n", .{});
        try out.print("CSV: {s}\n", .{csv_path});
        return;
    }

    // ── PHASE 2: full two-arm x 3-seed ablation on the decisive subset ──
    try out.print("---- PHASE 2: two-arm x 3-seed ablation on decisive subset ----\n\n", .{});

    var exist_on_only: usize = 0;
    var exist_off_only: usize = 0;
    var tot = [2]ArmRun{ .{}, .{} };

    for (SEEDS) |seed| {
        try out.print("──── seed 0x{X:0>16} ────\n", .{seed});

        try out.print("  ARM-OFF (frozen v{d}):\n", .{INITIAL_BASIS});
        const off = try runArm(alloc, seed, .off, decisive, out);
        try out.print("    B {d}/{d}  D-decisive {d}/{d}  tax: checked={d} novel={d} blocked={d}  evalsB={d}  {d}ms\n", .{
            off.b_solved, N_B,       off.d_solved, n_decisive,
            off.checked,  off.novel, off.blocked,  off.evals_b,
            off.ms,
        });

        try out.print("  ARM-ON (revision enabled):\n", .{});
        const on = try runArm(alloc, seed, .on, decisive, out);
        try out.print("    B {d}/{d}  D-decisive {d}/{d}  tax: checked={d} novel={d} blocked={d}  evalsB={d}  {d}ms  revision@{?d}\n", .{
            on.b_solved, N_B,      on.d_solved, n_decisive,
            on.checked,  on.novel, on.blocked,  on.evals_b,
            on.ms,       on.revision_fired_at,
        });

        for (0..off.n) |i| {
            const ro = off.rows[i];
            const rn = on.rows[i];
            if (rn.solved and !ro.solved) {
                exist_on_only += 1;
                try out.print("    >> EXISTENCE CANDIDATE: {s}[{s}] solved ON-only (ON cov={d:.3} via {s}; OFF cov={d:.3}, blocked_certs={d})\n", .{
                    ro.name, ro.battery, rn.cov, rn.label, ro.cov, ro.blocked_d,
                });
            } else if (ro.solved and !rn.solved) {
                exist_off_only += 1;
                try out.print("    >> REVERSE SEPARATION: {s}[{s}] solved OFF-only\n", .{ ro.name, ro.battery });
            }
            if (!ro.solved and ro.blocked_d > 0) {
                try out.print("    .. OFF saturated with {d} tax-blocked certified escape(s): {s}[{s}]\n", .{
                    ro.blocked_d, ro.name, ro.battery,
                });
            }
        }
        try out.print("\n", .{});

        for ([2]Arm{ .off, .on }) |arm| {
            const r = if (arm == .off) &off else &on;
            const t = &tot[@intFromEnum(arm)];
            t.b_solved += r.b_solved;
            t.d_solved += r.d_solved;
            t.checked += r.checked;
            t.novel += r.novel;
            t.blocked += r.blocked;
            t.evals_b += r.evals_b;
            for (r.rows[0..r.n]) |row| {
                try cw.print("ablation,0x{X:0>16},{s},{s},{d},\"{s}\",{d},{d:.4},{s},{d},{d},{d},{d},{d},{s},\n", .{
                    seed,
                    if (arm == .off) "off" else "on",
                    row.battery,
                    row.idx,
                    row.name,
                    @intFromBool(row.solved),
                    row.cov,
                    row.label,
                    row.checked_d,
                    row.novel_d,
                    row.blocked_d,
                    row.nlib,
                    row.basis,
                    if (arm == .on)
                        (if (r.revision_fired_at) |fi|
                            (if (fi <= row.idx) "post" else "pre")
                        else
                            "never")
                    else
                        "frozen",
                });
            }
        }
    }

    try out.print("════════════════ BATTERY-D ABLATION SUMMARY ({d} seeds, {d} decisive targets) ════════════════\n", .{ SEEDS.len, n_decisive });
    const nb = SEEDS.len * N_B;
    const ndx = SEEDS.len * n_decisive;
    try out.print("  ARM-OFF: B {d}/{d}  D-decisive {d}/{d}  novel={d} blocked={d} (checked={d})  evalsB={d}\n", .{
        tot[0].b_solved, nb, tot[0].d_solved, ndx, tot[0].novel, tot[0].blocked, tot[0].checked, tot[0].evals_b,
    });
    try out.print("  ARM-ON : B {d}/{d}  D-decisive {d}/{d}  novel={d} blocked={d} (checked={d})  evalsB={d}\n", .{
        tot[1].b_solved, nb, tot[1].d_solved, ndx, tot[1].novel, tot[1].blocked, tot[1].checked, tot[1].evals_b,
    });
    try out.print("  targets solved ON-only : {d}\n", .{exist_on_only});
    try out.print("  targets solved OFF-only: {d}\n", .{exist_off_only});
    try out.print("  EFFECT (revision load-bearing on battery-D decisive subset): {s}\n", .{
        if (exist_on_only > 0 and exist_off_only == 0) "CONFIRMED" else if (exist_on_only > 0) "MIXED" else "NOT REPLICATED",
    });
    try out.print("  CSV: {s}\n", .{csv_path});
}
