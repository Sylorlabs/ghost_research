//! Tier 8 ABLATION — is framework revision (tax basis v3→v4) load-bearing?
//!
//! Two arms at IDENTICAL eval budget, seeds, and code path:
//!   ARM-OFF: strict tax frozen at basis v3, reality lane off, forever.
//!   ARM-ON : starts identical to ARM-OFF; a remix-rate trigger (T8-AG-21
//!            semantics, adapted within-run: cumulative checked ≥ 5 and
//!            novel rate < 0.20) fires a witnessed closure revision
//!            (T8-AG-22/25 machinery) → basis v4 + reality lane.
//!
//! Batteries per (seed, arm), run as ONE continuous loop (library/tax state
//! shared inside battery B as in production):
//!   B: full production engine `ie.solveBlindTarget` (11 targets) — includes
//!      rescue lanes (mod/pipeline/pair-walsh escalation) that BYPASS the tax.
//!   C-ladder: battery C targets through `ui.solveOneTarget` ONLY (no xor
//!      route, no mod escalation) — every promotion goes through the tax gate,
//!      so this is the slice where revision could be provably load-bearing.
//!
//! Existence proof sought: a target solved in ARM-ON and never in ARM-OFF at
//! the same seed. HONEST rule: if no separation, report it plainly.
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe tier8_ablation.zig -O ReleaseFast
//! Run:
//!   ./tier8_ablation [--seeds=N] [--csv=PATH]
//!
//! Single-threaded. New file only — no existing file modified.

const std = @import("std");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");
const bc = @import("open_invention_tier8_battery_c.zig");
const cr = @import("closure_revision.zig");
const fv = @import("framework_vote.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

/// Seed 0 = production grid seed; 1,2 = battery-C held-out replication seeds.
const SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };

const ALERT_THRESHOLD: f64 = 0.20; // T8-AG-21 remix alert
const MIN_CHECKS: usize = 5; // within-run adaptation of the 5-run window
const INITIAL_BASIS: u32 = 3; // both arms start here (v3-full strict)
const REVISED_BASIS: u32 = 4;

const N_B = 11; // battery B targets
const MAX_TGT: usize = N_B + bc.BATTERY_C.len;

const Arm = enum { off, on };

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
    revision_fired_at: ?usize = null, // global target index (0-based, B then C)
    checked: usize = 0,
    novel: usize = 0,
    blocked: usize = 0,
    b_solved: usize = 0,
    c_solved: usize = 0,
    evals_b: usize = 0,
    ms: i64 = 0,
};

/// rq1 escalation labels are formatted into stack buffers inside the callee
/// and dangle by the time solveBlindTarget returns; keep only known-static
/// literals, otherwise substitute a stable class name.
fn safeLabel(label: []const u8) []const u8 {
    const known = [_][]const u8{
        "frozen/grown monomials", "unified escalation", "saturated",
        "base",                   "forge",              "pair",
        "walsh",                  "menu",               "world",
    };
    for (known) |k| if (std.mem.eql(u8, label, k)) return k;
    return "rq1_escalation";
}

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

/// ARM-ON only: fire witnessed revision when remix alert crosses.
fn maybeRevise(run: *ArmRun, global_idx: usize, out: anytype) !void {
    if (run.revision_fired_at != null) return;
    if (eqtax.stats.checked < MIN_CHECKS) return;
    if (eqtax.stats.novelRate() >= ALERT_THRESHOLD) return;
    const proposal = cr.proposeFromTaxonomy(taxonomyFromLog(), eqtax.basis_level);
    const vote = fv.voteOnProposal(proposal, .{
        .witness_id = "tier8-ablation-2026-07-10",
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

fn runArm(alloc: std.mem.Allocator, seed: u64, arm: Arm, out: anytype) !ArmRun {
    var run: ArmRun = .{};
    const t0 = std.time.milliTimestamp();

    // Identical initial gate state for both arms.
    eqtax.strict_enabled = true;
    eqtax.basis_level = INITIAL_BASIS;
    eqtax.reality_lane_enabled = false;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    const prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
    var ctx = prep.ctx;

    // ── Battery B: full production engine (shared growable library) ──
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

    // ── Battery C, ladder-only slice: every promotion is tax-gated ──
    for (bc.BATTERY_C) |tgt| {
        const Yb = try alloc.alloc(f64, rq1.NSAMP);
        defer alloc.free(Yb);
        for (0..rq1.NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);

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
        if (m.solved) run.c_solved += 1;
        run.rows[run.n] = .{
            .battery = "C",
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
    // The tax greedy fit keeps ~32MB of column store on the stack (layout in
    // equivalence_tax.zig greedyFit); the default 8MB main stack segfaults.
    // Run the workload on one worker thread with an explicit 512MB stack
    // (2 threads total incl. main, within the ablation constraint).
    const t = try std.Thread.spawn(.{ .stack_size = 512 * 1024 * 1024 }, realMainWrap, .{});
    t.join();
    if (g_worker_err) |e| return e;
}

var g_worker_err: ?anyerror = null;

fn realMainWrap() void {
    realMain() catch |e| {
        g_worker_err = e;
    };
}

fn realMain() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var n_seeds: usize = SEEDS.len;
    var csv_path: []const u8 =
        "/home/micah/Desktop/Sylorlabs/ghost_research/results/tier8_ablation_2026_07_10.csv";
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--seeds=")) {
            n_seeds = @min(SEEDS.len, try std.fmt.parseInt(usize, arg["--seeds=".len..], 10));
        } else if (std.mem.startsWith(u8, arg, "--csv=")) {
            csv_path = try alloc.dupe(u8, arg["--csv=".len..]);
        }
    }

    try out.print("=== TIER 8 ABLATION: framework revision ON vs OFF ===\n", .{});
    try out.print("Arms start at basis v{d} strict; ON may revise to v{d} on remix alert\n", .{ INITIAL_BASIS, REVISED_BASIS });
    try out.print("(alert: checked>={d} and novel rate <{d:.2}); OFF frozen forever.\n", .{ MIN_CHECKS, ALERT_THRESHOLD });
    try out.print("Batteries: B = full engine (rescue lanes bypass tax); C = ladder-only (fully tax-gated)\n", .{});
    try out.print("Seeds: {d}\n\n", .{n_seeds});

    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("seed,arm,battery,idx,target,solved,cov,label,checked_delta,novel_delta,remix_blocked_delta,nlib,basis_at_target,revision_fired_at\n", .{});

    var exist_on_only: usize = 0;
    var exist_off_only: usize = 0;
    var tot = [2]ArmRun{ .{}, .{} }; // aggregate counters only (b/c solved etc.)

    for (SEEDS[0..n_seeds]) |seed| {
        try out.print("──── seed 0x{X:0>16} ────\n", .{seed});

        try out.print("  ARM-OFF (frozen v{d}):\n", .{INITIAL_BASIS});
        const off = try runArm(alloc, seed, .off, out);
        try out.print("    B {d}/{d}  C-ladder {d}/{d}  tax: checked={d} novel={d} blocked={d}  evalsB={d}  {d}ms\n", .{
            off.b_solved, N_B,           off.c_solved, bc.BATTERY_C.len,
            off.checked,  off.novel,     off.blocked,  off.evals_b,
            off.ms,
        });

        try out.print("  ARM-ON (revision enabled):\n", .{});
        const on = try runArm(alloc, seed, .on, out);
        try out.print("    B {d}/{d}  C-ladder {d}/{d}  tax: checked={d} novel={d} blocked={d}  evalsB={d}  {d}ms  revision@{?d}\n", .{
            on.b_solved, N_B,       on.c_solved, bc.BATTERY_C.len,
            on.checked,  on.novel,  on.blocked,  on.evals_b,
            on.ms,       on.revision_fired_at,
        });

        // Per-target cross-arm comparison (same seed, same index).
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
            // Diagnostic: OFF saturated WITH a certified-but-tax-blocked escape
            // (promoting it would have reached COVER — direct revision leverage).
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
            t.c_solved += r.c_solved;
            t.checked += r.checked;
            t.novel += r.novel;
            t.blocked += r.blocked;
            t.evals_b += r.evals_b;
            for (r.rows[0..r.n]) |row| {
                try cw.print("0x{X:0>16},{s},{s},{d},\"{s}\",{d},{d:.4},{s},{d},{d},{d},{d},{d},{s}\n", .{
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

    try out.print("════════════════ ABLATION SUMMARY ({d} seeds) ════════════════\n", .{n_seeds});
    const nb = n_seeds * N_B;
    const ncx = n_seeds * bc.BATTERY_C.len;
    try out.print("  ARM-OFF: B {d}/{d}  C-ladder {d}/{d}  novel={d} blocked={d} (checked={d})  evalsB={d}\n", .{
        tot[0].b_solved, nb, tot[0].c_solved, ncx, tot[0].novel, tot[0].blocked, tot[0].checked, tot[0].evals_b,
    });
    try out.print("  ARM-ON : B {d}/{d}  C-ladder {d}/{d}  novel={d} blocked={d} (checked={d})  evalsB={d}\n", .{
        tot[1].b_solved, nb, tot[1].c_solved, ncx, tot[1].novel, tot[1].blocked, tot[1].checked, tot[1].evals_b,
    });
    try out.print("  targets solved ON-only : {d}\n", .{exist_on_only});
    try out.print("  targets solved OFF-only: {d}\n", .{exist_off_only});
    try out.print("  EXISTENCE PROOF (revision load-bearing for solves): {s}\n", .{
        if (exist_on_only > 0 and exist_off_only == 0) "FOUND" else if (exist_on_only > 0) "MIXED" else "NOT FOUND",
    });
    try out.print("  CSV: {s}\n", .{csv_path});
}
