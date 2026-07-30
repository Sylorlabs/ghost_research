//! Tier 8 gate v5 — patching the v4 vacuous escape-authentic lane.
//!
//! Yesterday's ablation (tier8_ablation.zig / docs/research/tier8_ablation.md)
//! proved basis revision v3->v4 is load-bearing (C08 "parity count" only
//! solves with the revision). But it also exposed a hole: v4's escape lane
//! condition inside equivalence_tax.gatePromoteEx is
//!
//!     cov_before < COVER and cov_after >= COVER
//!
//! which is IDENTICAL to unified_invention.certify()'s own `escape` predicate
//! (COVER = 0.90). Since gatePromoteEx is only ever invoked when `certified`
//! (escape && r2<R2_MAX) is already true, the override fires on literally
//! every live call — 0 post-revision blocks, 100% "novel" (confirmed by the
//! ablation). The family-conditioned remix test still runs and still logs a
//! verdict (tax_log/replay_captures store it PRE-override), it just never
//! gets to veto anything.
//!
//! This harness designs and measures two v5 gate replacements, built ONLY
//! from equivalence_tax.zig's existing public API (witnessRemixAtLevel,
//! gatePromoteEx, replay_captures/replay_pool, COVER) plus
//! unified_invention.certifyPublic — no existing file is edited.
//!
//!   v5-FULL (design (a), leave-one-out / full-basis, generalized by (c)):
//!     survivor iff witnessRemixAtLevel(grid, lib, cand, Y, level=3).test_acc
//!     < (COVER - eps).
//!     level=3 = the full, non-family-narrowed static+xor+pipeline+mod-synth
//!     basis; `lib` is the actual current growable library (already contains
//!     every previously promoted escape, so "current basis PLUS all
//!     previously promoted escapes" falls out for free — the thing v4's
//!     narrowing removes from the test). eps=0 is literal leave-one-out/full-
//!     basis remix; eps>0 is design (c), a tightened epsilon sweep over the
//!     SAME statistic (test_acc), reported jointly since they are one
//!     mechanism, not two.
//!
//!   v5-MARGIN (design (b), marginal-coverage gate):
//!     survivor iff (cov_after - test_acc_L3) >= MARGIN_THRESH.
//!     Requires the candidate to beat the best full-basis reconstruction by
//!     a real margin, not just clear an absolute bar — catches near-miss
//!     remix that v5-FULL's hard threshold could let through.
//!
//!   v5-LADDER (engine-expressible remix test — added after seed-1 interim
//!     data showed BOTH variants above block the C08 escape; provenance
//!     disclosed, evaluated on all 3 seeds and all 3 test parts like the
//!     others):
//!     survivor iff witnessRemixAtLevel(grid, lib, cand, Y, level=1).test_acc
//!     < COVER.
//!     Level 1 = library + static candidate pool only (monomial / pair /
//!     walsh / world_sum / world_sign / clifford) — exactly the families the
//!     ladder can PROMOTE. Levels 2-3 add xor/pipeline/mod-synth columns
//!     that exist ONLY inside the audit basis: no ladder rung can promote
//!     them into the library. Rationale: "the audit basis reconstructs this
//!     target" is not remix evidence when the reconstruction runs through
//!     columns the engine cannot express — then the candidate genuinely
//!     extends the engine's reachable set. C08 is the type case: mod-synth
//!     reconstructs parity-count at ~1.0, yet ARM-OFF saturates at 0.50
//!     because nothing can promote a mod-synth column. Remix should mean
//!     "reconstructible by what the ENGINE already has", not "by what the
//!     AUDITOR can imagine".
//!
//! Three-part test battery, all 3 of yesterday's seeds:
//!   ADMISSION   — replay the real C08 "parity count" promotion event(s) from
//!                 a live ARM-ON run (basis v3->v4 revision, identical to
//!                 tier8_ablation.zig) through each v5 variant; rebuild the
//!                 library from ONLY v5-admitted candidates and recompute
//!                 coverage. PASS iff reconstructed cov >= COVER (ideally
//!                 1.000, matching the ablation's ARM-ON result).
//!   DISCRIMINATION — take every candidate the live ARM-OFF pass (basis
//!                 frozen v3, no override — same mechanism T8-AG-02f used)
//!                 found to be remix-blocked (test_acc>=COVER at full basis)
//!                 and "inject" it post-revision: recompute real
//!                 cov_before/cov_after via ui.certifyPublic, then ask what
//!                 the LIVE v4 gate (basis=4, reality_lane=true) says versus
//!                 what each v5 variant says. v4 is expected to admit ~100%
//!                 (the vacuous hole, empirically reproduced on real
//!                 candidates, not hypothetical ones); v5 must block them.
//!   NO-HARM     — take every REAL promotion event from the live ARM-ON pass
//!                 (all of battery B + the tax-gated C-ladder slice) and ask
//!                 whether each v5 variant would have made the SAME (admit)
//!                 decision v4 actually made. Since gate decisions are pure
//!                 functions of (grid, lib, cand, Y), 0 disagreements over
//!                 every real decision point in the run is a PROOF (not an
//!                 estimate) that substituting v5 live would reproduce the
//!                 identical trajectory — same solves, same eval budget.
//!                 Any disagreement is reported as a bounded no-harm risk
//!                 (not a proven regression — escalation lanes may still
//!                 rescue a blocked rung, as they did for arm A in
//!                 tier8_tax_gate_ab.zig).
//!
//! HONEST SCOPE: this harness evaluates v5 as a byte-for-byte faithful SHADOW
//! gate (same inputs, same deterministic functions v4 uses) rather than by
//! hot-wiring equivalence_tax.zig's mutable globals into the live solve loop
//! (which would require editing an existing file). The no-harm argument
//! (identical inputs -> identical decision -> identical trajectory) is
//! logically airtight for events actually captured; it does not simulate
//! what NEW candidates a genuinely-different trajectory might propose.
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe tier8_gate_v5.zig -O ReleaseFast
//! Run:
//!   ./tier8_gate_v5
//!
//! 2 threads total (main + 1 big-stack worker, matching tier8_ablation.zig /
//! tier8_tax_gate_ab.zig — greedyFit's column store is heap-backed now, but
//! kept as a safety margin). New file only — no existing file modified.

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

const SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };

const ALERT_THRESHOLD: f64 = 0.20; // T8-AG-21 remix alert (identical to ablation)
const MIN_CHECKS: usize = 5;
const INITIAL_BASIS: u32 = 3;
const REVISED_BASIS: u32 = 4;

const N_B = 11;
const C08_NAME = "C08 parity count";

const MARGIN_THRESH: f64 = 0.03; // v5-MARGIN: candidate must beat best reconstruction by >=3pp
const EPS_SWEEP = [_]f64{ 0.0, 0.02, 0.05, 0.08 }; // v5-FULL tightened-epsilon sweep

// ── Captured candidate tuple (owned copy, survives eqtax.reset*) ───────────

const CapTuple = struct {
    nlib: usize,
    lib: [32]ui.Feature,
    cand: ui.Feature,
    y: []f64, // owned NSAMP-length copy
    raw_verdict: eqtax.TaxVerdict, // pre-override verdict AT CAPTURE TIME
    family: eqtax.ColFamily,
    /// True iff the LIVE gate decision for this event happened after the
    /// v3->v4 revision (live = v4 lane, admits every certified candidate).
    /// False = decided by v3-strict (remix verdict => live-blocked).
    post_rev: bool,
};

fn copyCapture(alloc: std.mem.Allocator, idx: usize, post_rev: bool) !CapTuple {
    const cap = eqtax.replay_captures[idx];
    const y = try alloc.dupe(f64, eqtax.replay_pool[idx][0..ui.NSAMP]);
    return .{
        .nlib = cap.nlib,
        .lib = cap.lib,
        .cand = cap.cand,
        .y = y,
        .raw_verdict = cap.verdict,
        .family = eqtax.tax_log[idx].primary_family,
        .post_rev = post_rev,
    };
}

// ── v5 gate mechanisms (pure functions over existing eqtax API only) ───────

/// Full, non-family-narrowed basis test_acc at level 3. `lib` already IS the
/// current growable library (contains every previously promoted escape) so
/// this realizes design (a): current basis + all prior escapes, minus cand
/// (cand cannot be in `lib` yet — it hasn't been promoted).
fn fullBasisTestAcc(grid: []const [8]u8, lib: []const ui.Feature, cand: ui.Feature, y: []const f64) f64 {
    return eqtax.witnessRemixAtLevel(grid, lib, cand, y, 3).test_acc;
}

/// v5-FULL / v5-tightened-epsilon (designs (a) and (c) — one mechanism).
fn v5FullSurvivor(test_acc_l3: f64, eps: f64) bool {
    return test_acc_l3 < (eqtax.COVER - eps);
}

/// v5-MARGIN (design (b)): candidate must beat the best full-basis
/// reconstruction of the TARGET by a real margin, not just clear COVER.
fn v5MarginSurvivor(test_acc_l3: f64, cov_after: f64) bool {
    return (cov_after - test_acc_l3) >= MARGIN_THRESH;
}

/// v5-LADDER: remix only if the ENGINE-EXPRESSIBLE basis (level 1: library +
/// monomial/pair/walsh/world/clifford static pool — every family a ladder
/// rung can promote) reconstructs the target. Audit-only families
/// (xor/pipeline/mod-synth) are excluded from the remix test because the
/// engine has no way to promote them.
fn ladderBasisTestAcc(grid: []const [8]u8, lib: []const ui.Feature, cand: ui.Feature, y: []const f64) f64 {
    return eqtax.witnessRemixAtLevel(grid, lib, cand, y, 1).test_acc;
}

fn v5LadderSurvivor(test_acc_l1: f64) bool {
    return test_acc_l1 < eqtax.COVER;
}

/// Recompute real cov_before/cov_after/r2/ok for an arbitrary (lib,cand,Y)
/// tuple via the production certifier. strict_enabled is forced off for the
/// duration so the internal gatePromoteEx call is a no-op passthrough (does
/// not touch tax_log/replay_captures/stats) — cov_before/cov_after/r2 are
/// pure functions of (X,grid,lib,cand,Y) and are unaffected either way.
fn recomputeCert(ctx: *ie.BlindBatteryCtx, lib: []const ui.Feature, cand: ui.Feature, y: []const f64) ui.CertResult {
    const saved = eqtax.strict_enabled;
    eqtax.strict_enabled = false;
    defer eqtax.strict_enabled = saved;
    var w_scratch: [33]f64 = ctx.w;
    return ui.certifyPublic(ctx.X, ctx.grid, lib, cand, y, ctx.feat, w_scratch[0..]);
}

/// Recompute the LIVE v4 decision (basis=4, reality_lane=true) for a tuple
/// with known cov_before/cov_after, via the real gatePromoteEx (not a
/// reimplementation). Resets eqtax bookkeeping afterward.
fn recomputeV4Admit(ctx: *ie.BlindBatteryCtx, lib: []const ui.Feature, cand: ui.Feature, y: []const f64, cov_before: f64, cov_after: f64) bool {
    eqtax.strict_enabled = true;
    eqtax.basis_level = 4;
    eqtax.reality_lane_enabled = true;
    const admit = eqtax.gatePromoteEx(ctx.grid, lib, cand, y, true, cov_before, cov_after);
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();
    return admit;
}

// ── Per-candidate audit row (for CSV + aggregation) ────────────────────────

const AuditRow = struct {
    seed: u64,
    pool: []const u8, // "admission_c08" | "planted_remix" | "no_harm_real"
    family: []const u8,
    raw_verdict_at_capture: []const u8,
    post_rev: bool, // live decision made after the v3->v4 revision?
    v4_admit: bool,
    cov_before: f64,
    cov_after: f64,
    test_acc_l3: f64,
    test_acc_l1: f64,
    margin: f64,
    v5_full_e0: bool,
    v5_full_e02: bool,
    v5_full_e05: bool,
    v5_full_e08: bool,
    v5_margin: bool,
    v5_ladder: bool,
};

fn auditCandidate(
    ctx: *ie.BlindBatteryCtx,
    seed: u64,
    pool: []const u8,
    cap: CapTuple,
) AuditRow {
    const cert = recomputeCert(ctx, cap.lib[0..cap.nlib], cap.cand, cap.y);
    const v4_admit = recomputeV4Admit(ctx, cap.lib[0..cap.nlib], cap.cand, cap.y, cert.cov_before, cert.cov_after);
    const test_acc_l3 = fullBasisTestAcc(ctx.grid, cap.lib[0..cap.nlib], cap.cand, cap.y);
    const test_acc_l1 = ladderBasisTestAcc(ctx.grid, cap.lib[0..cap.nlib], cap.cand, cap.y);
    const margin = cert.cov_after - test_acc_l3;
    return .{
        .seed = seed,
        .pool = pool,
        .family = @tagName(cap.family),
        .raw_verdict_at_capture = @tagName(cap.raw_verdict),
        .post_rev = cap.post_rev,
        .v4_admit = v4_admit,
        .cov_before = cert.cov_before,
        .cov_after = cert.cov_after,
        .test_acc_l3 = test_acc_l3,
        .test_acc_l1 = test_acc_l1,
        .margin = margin,
        .v5_full_e0 = v5FullSurvivor(test_acc_l3, EPS_SWEEP[0]),
        .v5_full_e02 = v5FullSurvivor(test_acc_l3, EPS_SWEEP[1]),
        .v5_full_e05 = v5FullSurvivor(test_acc_l3, EPS_SWEEP[2]),
        .v5_full_e08 = v5FullSurvivor(test_acc_l3, EPS_SWEEP[3]),
        .v5_margin = v5MarginSurvivor(test_acc_l3, cert.cov_after),
        .v5_ladder = v5LadderSurvivor(test_acc_l1),
    };
}

// ── ARM-ON revision trigger (identical semantics to tier8_ablation.zig) ────

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
    return .{ .mono_remix = mono, .walsh_remix = walsh, .pipe_remix = pipe, .novel_count = novel, .checked = eqtax.stats.checked };
}

fn maybeRevise(revision_fired_at: *?usize, revision_replay_idx: *usize, global_idx: usize) void {
    if (revision_fired_at.* != null) return;
    if (eqtax.stats.checked < MIN_CHECKS) return;
    if (eqtax.stats.novelRate() >= ALERT_THRESHOLD) return;
    const proposal = cr.proposeFromTaxonomy(taxonomyFromLog(), eqtax.basis_level);
    const vote = fv.voteOnProposal(proposal, .{
        .witness_id = "tier8-gate-v5-2026-07-10",
        .approved = true,
        .timestamp_seed = 0xAB1A20260710,
    }, false);
    if (!vote.recorded) return;
    eqtax.basis_level = REVISED_BASIS;
    eqtax.reality_lane_enabled = true;
    revision_fired_at.* = global_idx;
    // Captures with replay index >= this value were decided POST-revision
    // (live gate = v4 lane, admits everything certified). Earlier captures
    // were decided by v3-strict (remix verdict => live-blocked).
    revision_replay_idx.* = eqtax.replay_n;
}

// ── Per-seed aggregates ─────────────────────────────────────────────────────

const SeedAgg = struct {
    seed: u64,
    off_b_solved: usize = 0,
    off_c_solved: usize = 0,
    off_checked: usize = 0,
    off_blocked: usize = 0,
    on_b_solved: usize = 0,
    on_c_solved: usize = 0,
    on_evals_b: usize = 0,
    revision_fired_at: ?usize = null,
    c08_solved_live: bool = false,
    c08_cov_live: f64 = 0,
    c08_n_events: usize = 0,
    c08_has_event: bool = false,
    cov_v4_recon: f64 = -1,
    cov_full_e0: f64 = -1,
    cov_full_e02: f64 = -1,
    cov_full_e05: f64 = -1,
    cov_full_e08: f64 = -1,
    cov_margin: f64 = -1,
    cov_ladder: f64 = -1,
    planted_n: usize = 0,
    no_harm_n: usize = 0,
};

fn runSeed(
    alloc: std.mem.Allocator,
    seed: u64,
    rows: *std.ArrayList(AuditRow),
    out: anytype,
) !SeedAgg {
    var agg = SeedAgg{ .seed = seed };

    const prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
    var ctx = prep.ctx;

    // ── PASS 1: ARM-OFF — basis frozen v3, no override (mirrors T8-AG-02f /
    //    tier8_ablation ARM-OFF exactly). Source of the "planted remix" pool.
    eqtax.strict_enabled = true;
    eqtax.basis_level = INITIAL_BASIS;
    eqtax.reality_lane_enabled = false;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    {
        var lib: [32]ui.Feature = undefined;
        var nlib: usize = 0;
        ie.seedUiFromRq1(prep.trained_lib, &lib, &nlib);
        var budget = ie.EvalCounter{};
        for (ctx.battery) |tgt| {
            const Yb = try alloc.alloc(f64, rq1.NSAMP);
            for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);
            const res = try ie.solveBlindTarget(ctx.X, ctx.grid, &lib, &nlib, Yb, ctx.phiTgt, ctx.w[0..], tgt, ctx.bank, &ctx.S_store, ctx.pf, ctx.feat, &budget, SilentOut{}, true);
            if (res.solved) agg.off_b_solved += 1;
        }
        for (bc.BATTERY_C) |tgt| {
            const Yb = try alloc.alloc(f64, rq1.NSAMP);
            for (0..rq1.NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);
            var clib: [32]ui.Feature = undefined;
            var cnlib: usize = 0;
            ie.seedUiFromRq1(prep.trained_lib, &clib, &cnlib);
            var w_mut: [33]f64 = ctx.w;
            const m = ui.solveOneTarget(ctx.X, ctx.grid, &clib, &cnlib, Yb, ctx.phiTgt, w_mut[0..], SilentOut{}, true);
            if (m.solved) agg.off_c_solved += 1;
        }
    }
    agg.off_checked = eqtax.stats.checked;
    agg.off_blocked = eqtax.stats.remix_blocked;

    var planted: [64]CapTuple = undefined;
    var n_planted: usize = 0;
    for (0..eqtax.replay_n) |i| {
        if (eqtax.replay_captures[i].verdict == .remix) {
            planted[n_planted] = try copyCapture(alloc, i, false);
            n_planted += 1;
        }
    }
    agg.planted_n = n_planted;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    // ── PASS 2: ARM-ON — v3->v4 revision, identical to tier8_ablation.zig.
    //    Source of the ADMISSION (C08) and NO-HARM (every real promotion) pools.
    eqtax.strict_enabled = true;
    eqtax.basis_level = INITIAL_BASIS;
    eqtax.reality_lane_enabled = false;

    var revision_fired_at: ?usize = null;
    var revision_replay_idx: usize = std.math.maxInt(usize); // captures >= this are post-revision
    var global_idx: usize = 0;
    {
        var lib: [32]ui.Feature = undefined;
        var nlib: usize = 0;
        ie.seedUiFromRq1(prep.trained_lib, &lib, &nlib);
        var budget = ie.EvalCounter{};
        for (ctx.battery) |tgt| {
            const Yb = try alloc.alloc(f64, rq1.NSAMP);
            for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);
            const res = try ie.solveBlindTarget(ctx.X, ctx.grid, &lib, &nlib, Yb, ctx.phiTgt, ctx.w[0..], tgt, ctx.bank, &ctx.S_store, ctx.pf, ctx.feat, &budget, SilentOut{}, true);
            if (res.solved) agg.on_b_solved += 1;
            maybeRevise(&revision_fired_at, &revision_replay_idx, global_idx);
            global_idx += 1;
        }
        agg.on_evals_b = budget.total();

        var c08_start: ?usize = null;
        var c08_end: usize = 0;
        for (bc.BATTERY_C) |tgt| {
            const Yb = try alloc.alloc(f64, rq1.NSAMP);
            for (0..rq1.NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);
            var clib: [32]ui.Feature = undefined;
            var cnlib: usize = 0;
            ie.seedUiFromRq1(prep.trained_lib, &clib, &cnlib);
            var w_mut: [33]f64 = ctx.w;
            const cap0 = eqtax.replay_n;
            const m = ui.solveOneTarget(ctx.X, ctx.grid, &clib, &cnlib, Yb, ctx.phiTgt, w_mut[0..], SilentOut{}, true);
            const cap1 = eqtax.replay_n;
            if (m.solved) agg.on_c_solved += 1;
            if (std.mem.eql(u8, tgt.name, C08_NAME)) {
                c08_start = cap0;
                c08_end = cap1;
                agg.c08_solved_live = m.solved;
                agg.c08_cov_live = m.cov;
            }
            maybeRevise(&revision_fired_at, &revision_replay_idx, global_idx);
            global_idx += 1;
        }
        agg.revision_fired_at = revision_fired_at;

        // Drain ALL real ON-pass promotions (battery B + C-ladder) — every
        // one of these is a genuine production decision; v4 admitted all of
        // them (the known 0-post-revision-blocks fact). c08_start/c08_end
        // index into this SAME array (built in the same 0..replay_n order).
        var on_all: [64]CapTuple = undefined;
        var n_on: usize = 0;
        for (0..eqtax.replay_n) |i| {
            on_all[n_on] = try copyCapture(alloc, i, i >= revision_replay_idx);
            n_on += 1;
        }
        agg.no_harm_n = n_on;
        agg.c08_n_events = if (c08_start) |s0| c08_end - s0 else 0;

        eqtax.resetStats();
        eqtax.resetTaxLog();
        eqtax.resetReplay();

        // ── ADMISSION: audit the C08 event(s), then rebuild the C08 library
        //    from ONLY v5-admitted candidates and recompute coverage.
        if (c08_start) |s0| {
            const events = on_all[s0..c08_end];
            var y_c08 = try alloc.alloc(f64, rq1.NSAMP);
            const c08_tgt = bc.BATTERY_C[7]; // "C08 parity count"
            std.debug.assert(std.mem.eql(u8, c08_tgt.name, C08_NAME));
            for (0..rq1.NSAMP) |s| y_c08[s] = bc.labelTarget(ctx.grid[s], c08_tgt);

            var base_lib: [32]ui.Feature = undefined;
            var base_n: usize = 0;
            ie.seedUiFromRq1(prep.trained_lib, &base_lib, &base_n);

            var admit_v4all: [8]ui.Feature = undefined;
            var admit_full0: [8]ui.Feature = undefined;
            var admit_full02: [8]ui.Feature = undefined;
            var admit_full05: [8]ui.Feature = undefined;
            var admit_full08: [8]ui.Feature = undefined;
            var admit_margin: [8]ui.Feature = undefined;
            var admit_ladder: [8]ui.Feature = undefined;
            var nv4: usize = 0;
            var n0: usize = 0;
            var n02: usize = 0;
            var n05: usize = 0;
            var n08: usize = 0;
            var nm: usize = 0;
            var nl: usize = 0;

            for (events) |ev| {
                const row = auditCandidate(&ctx, seed, "admission_c08", ev);
                try rows.append(row);
                admit_v4all[nv4] = ev.cand;
                nv4 += 1;
                if (row.v5_full_e0) {
                    admit_full0[n0] = ev.cand;
                    n0 += 1;
                }
                if (row.v5_full_e02) {
                    admit_full02[n02] = ev.cand;
                    n02 += 1;
                }
                if (row.v5_full_e05) {
                    admit_full05[n05] = ev.cand;
                    n05 += 1;
                }
                if (row.v5_full_e08) {
                    admit_full08[n08] = ev.cand;
                    n08 += 1;
                }
                if (row.v5_margin) {
                    admit_margin[nm] = ev.cand;
                    nm += 1;
                }
                if (row.v5_ladder) {
                    admit_ladder[nl] = ev.cand;
                    nl += 1;
                }
            }

            const covFor = struct {
                fn f(c: *ie.BlindBatteryCtx, base: []const ui.Feature, base_len: usize, extra: []const ui.Feature, y: []const f64) f64 {
                    var recon_lib: [40]ui.Feature = undefined;
                    @memcpy(recon_lib[0..base_len], base[0..base_len]);
                    @memcpy(recon_lib[base_len .. base_len + extra.len], extra);
                    var w_mut: [33]f64 = c.w;
                    return ui.measureCoverage(c.X, c.grid, recon_lib[0 .. base_len + extra.len], y, w_mut[0..]);
                }
            }.f;

            agg.c08_has_event = true;
            agg.cov_v4_recon = covFor(&ctx, base_lib[0..], base_n, admit_v4all[0..nv4], y_c08);
            agg.cov_full_e0 = covFor(&ctx, base_lib[0..], base_n, admit_full0[0..n0], y_c08);
            agg.cov_full_e02 = covFor(&ctx, base_lib[0..], base_n, admit_full02[0..n02], y_c08);
            agg.cov_full_e05 = covFor(&ctx, base_lib[0..], base_n, admit_full05[0..n05], y_c08);
            agg.cov_full_e08 = covFor(&ctx, base_lib[0..], base_n, admit_full08[0..n08], y_c08);
            agg.cov_margin = covFor(&ctx, base_lib[0..], base_n, admit_margin[0..nm], y_c08);
            agg.cov_ladder = covFor(&ctx, base_lib[0..], base_n, admit_ladder[0..nl], y_c08);

            try out.print("  [seed 0x{X:0>16}] C08 events={d} live_solved={} live_cov={d:.3}\n", .{ seed, events.len, agg.c08_solved_live, agg.c08_cov_live });
            try out.print("    reconstructed coverage — v4(all admit)={d:.3}  v5-full(e=0)={d:.3}  v5-full(e=0.02)={d:.3}  v5-full(e=0.05)={d:.3}  v5-full(e=0.08)={d:.3}  v5-margin={d:.3}  v5-ladder={d:.3}\n", .{
                agg.cov_v4_recon, agg.cov_full_e0, agg.cov_full_e02, agg.cov_full_e05, agg.cov_full_e08, agg.cov_margin, agg.cov_ladder,
            });
        } else {
            try out.print("  [seed 0x{X:0>16}] WARNING: no C08 promotion event captured (live_solved={})\n", .{ seed, agg.c08_solved_live });
        }

        // ── DISCRIMINATION: audit the planted (v3-remix-blocked) pool.
        for (planted[0..n_planted]) |cap| {
            const row = auditCandidate(&ctx, seed, "planted_remix", cap);
            try rows.append(row);
        }

        // ── NO-HARM: audit every real ON-pass promotion.
        for (on_all[0..n_on]) |cap| {
            const row = auditCandidate(&ctx, seed, "no_harm_real", cap);
            try rows.append(row);
        }
    }

    return agg;
}

// ── Main ─────────────────────────────────────────────────────────────────

pub fn main() !void {
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

    try out.print("=== TIER 8 GATE v5: patching the v4 vacuous escape lane ===\n", .{});
    try out.print("v5-FULL: witnessRemixAtLevel(level=3, current lib) < COVER-eps, no override\n", .{});
    try out.print("v5-MARGIN: cov_after - test_acc_L3 >= {d:.2}\n\n", .{MARGIN_THRESH});

    var rows = std.ArrayList(AuditRow).init(alloc);
    var aggs: [SEEDS.len]SeedAgg = undefined;

    for (SEEDS, 0..) |seed, si| {
        try out.print("──── seed 0x{X:0>16} ────\n", .{seed});
        aggs[si] = try runSeed(alloc, seed, &rows, out);
        const a = aggs[si];
        try out.print("  ARM-OFF: B {d}/{d} C-ladder {d}/{d}  checked={d} blocked={d}  planted_pool={d}\n", .{
            a.off_b_solved, N_B, a.off_c_solved, bc.BATTERY_C.len, a.off_checked, a.off_blocked, a.planted_n,
        });
        try out.print("  ARM-ON : B {d}/{d} C-ladder {d}/{d}  evalsB={d}  revision@{?d}  no_harm_pool={d}\n\n", .{
            a.on_b_solved, N_B, a.on_c_solved, bc.BATTERY_C.len, a.on_evals_b, a.revision_fired_at, a.no_harm_n,
        });
    }

    // ── Write CSV ────────────────────────────────────────────────────────
    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/gate_v5_2026_07_10.csv";
    {
        const f = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
        defer f.close();
        const w = f.writer();
        try w.print("seed,pool,family,raw_verdict_capture,post_revision,v4_admit,cov_before,cov_after,test_acc_l3,test_acc_l1,margin,v5_full_e0,v5_full_e02,v5_full_e05,v5_full_e08,v5_margin,v5_ladder\n", .{});
        for (rows.items) |r| {
            try w.print("0x{X:0>16},{s},{s},{s},{d},{d},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d},{d},{d},{d},{d},{d}\n", .{
                r.seed,                r.pool,
                r.family,              r.raw_verdict_at_capture,
                @intFromBool(r.post_rev),
                @intFromBool(r.v4_admit), r.cov_before,
                r.cov_after,           r.test_acc_l3,
                r.test_acc_l1,         r.margin,
                @intFromBool(r.v5_full_e0),
                @intFromBool(r.v5_full_e02), @intFromBool(r.v5_full_e05),
                @intFromBool(r.v5_full_e08), @intFromBool(r.v5_margin),
                @intFromBool(r.v5_ladder),
            });
        }
    }

    // ── Aggregate summary ───────────────────────────────────────────────
    try out.print("════════════════ GATE v5 SUMMARY ════════════════\n", .{});

    var planted_n: usize = 0;
    var planted_block_v4: usize = 0;
    var planted_block_e0: usize = 0;
    var planted_block_e02: usize = 0;
    var planted_block_e05: usize = 0;
    var planted_block_e08: usize = 0;
    var planted_block_margin: usize = 0;
    var planted_block_ladder: usize = 0;
    // Post-revision events: live gate = v4 lane, live decision = ADMIT.
    // v5 disagreement = v5 would block. Pre-revision events: live gate =
    // v3-strict, live decision = admit iff raw verdict was novel; v5
    // disagreement = v5 decision differs from that.
    var noharm_n: usize = 0; // post-revision only (the slice v5 would replace)
    var noharm_flip_e0: usize = 0;
    var noharm_flip_e02: usize = 0;
    var noharm_flip_e05: usize = 0;
    var noharm_flip_e08: usize = 0;
    var noharm_flip_margin: usize = 0;
    var noharm_flip_ladder: usize = 0;
    var prerev_n: usize = 0;
    var prerev_flip_e0: usize = 0;
    var prerev_flip_ladder: usize = 0;

    for (rows.items) |r| {
        if (std.mem.eql(u8, r.pool, "planted_remix")) {
            planted_n += 1;
            if (r.v4_admit) planted_block_v4 += 1; // v4 "blocks" nothing == admits (the hole)
            if (!r.v5_full_e0) planted_block_e0 += 1;
            if (!r.v5_full_e02) planted_block_e02 += 1;
            if (!r.v5_full_e05) planted_block_e05 += 1;
            if (!r.v5_full_e08) planted_block_e08 += 1;
            if (!r.v5_margin) planted_block_margin += 1;
            if (!r.v5_ladder) planted_block_ladder += 1;
        } else if (std.mem.eql(u8, r.pool, "no_harm_real")) {
            if (r.post_rev) {
                noharm_n += 1;
                if (!r.v5_full_e0) noharm_flip_e0 += 1;
                if (!r.v5_full_e02) noharm_flip_e02 += 1;
                if (!r.v5_full_e05) noharm_flip_e05 += 1;
                if (!r.v5_full_e08) noharm_flip_e08 += 1;
                if (!r.v5_margin) noharm_flip_margin += 1;
                if (!r.v5_ladder) noharm_flip_ladder += 1;
            } else {
                prerev_n += 1;
                const live_admit = std.mem.eql(u8, r.raw_verdict_at_capture, "novel");
                if (r.v5_full_e0 != live_admit) prerev_flip_e0 += 1;
                if (r.v5_ladder != live_admit) prerev_flip_ladder += 1;
            }
        }
    }

    try out.print("ADMISSION (C08 \"parity count\", reconstructed coverage per seed, need >=0.90):\n", .{});
    var admit_pass_v4: usize = 0;
    var admit_pass_e0: usize = 0;
    var admit_pass_e02: usize = 0;
    var admit_pass_e05: usize = 0;
    var admit_pass_e08: usize = 0;
    var admit_pass_margin: usize = 0;
    var admit_pass_ladder: usize = 0;
    var admit_n: usize = 0;
    for (aggs) |a| {
        if (!a.c08_has_event) continue;
        admit_n += 1;
        if (a.cov_v4_recon >= 0.90) admit_pass_v4 += 1;
        if (a.cov_full_e0 >= 0.90) admit_pass_e0 += 1;
        if (a.cov_full_e02 >= 0.90) admit_pass_e02 += 1;
        if (a.cov_full_e05 >= 0.90) admit_pass_e05 += 1;
        if (a.cov_full_e08 >= 0.90) admit_pass_e08 += 1;
        if (a.cov_margin >= 0.90) admit_pass_margin += 1;
        if (a.cov_ladder >= 0.90) admit_pass_ladder += 1;
        try out.print("  seed 0x{X:0>16}: v4={d:.3} v5-full(e0)={d:.3} v5-full(e02)={d:.3} v5-full(e05)={d:.3} v5-full(e08)={d:.3} v5-margin={d:.3} v5-ladder={d:.3}\n", .{
            a.seed, a.cov_v4_recon, a.cov_full_e0, a.cov_full_e02, a.cov_full_e05, a.cov_full_e08, a.cov_margin, a.cov_ladder,
        });
    }
    try out.print("  PASS count (of {d} seeds with a captured C08 event): v4={d} v5-full(e0)={d} v5-full(e02)={d} v5-full(e05)={d} v5-full(e08)={d} v5-margin={d} v5-ladder={d}\n\n", .{
        admit_n, admit_pass_v4, admit_pass_e0, admit_pass_e02, admit_pass_e05, admit_pass_e08, admit_pass_margin, admit_pass_ladder,
    });

    try out.print("DISCRIMINATION (planted v3-remix-blocked pool, n={d} across 3 seeds):\n", .{planted_n});
    try out.print("  v4 (live, current shipped gate) admits: {d}/{d} ({d:.1}%)  <- the vacuous hole, reproduced on real candidates\n", .{
        planted_block_v4, planted_n, 100.0 * @as(f64, @floatFromInt(planted_block_v4)) / @as(f64, @floatFromInt(@max(1, planted_n))),
    });
    try out.print("  v5-full  eps=0.00 blocks: {d}/{d} ({d:.1}%)\n", .{ planted_block_e0, planted_n, 100.0 * @as(f64, @floatFromInt(planted_block_e0)) / @as(f64, @floatFromInt(@max(1, planted_n))) });
    try out.print("  v5-full  eps=0.02 blocks: {d}/{d} ({d:.1}%)\n", .{ planted_block_e02, planted_n, 100.0 * @as(f64, @floatFromInt(planted_block_e02)) / @as(f64, @floatFromInt(@max(1, planted_n))) });
    try out.print("  v5-full  eps=0.05 blocks: {d}/{d} ({d:.1}%)\n", .{ planted_block_e05, planted_n, 100.0 * @as(f64, @floatFromInt(planted_block_e05)) / @as(f64, @floatFromInt(@max(1, planted_n))) });
    try out.print("  v5-full  eps=0.08 blocks: {d}/{d} ({d:.1}%)\n", .{ planted_block_e08, planted_n, 100.0 * @as(f64, @floatFromInt(planted_block_e08)) / @as(f64, @floatFromInt(@max(1, planted_n))) });
    try out.print("  v5-margin (thresh={d:.2}) blocks: {d}/{d} ({d:.1}%)\n", .{ MARGIN_THRESH, planted_block_margin, planted_n, 100.0 * @as(f64, @floatFromInt(planted_block_margin)) / @as(f64, @floatFromInt(@max(1, planted_n))) });
    try out.print("  v5-ladder (level-1 basis) blocks: {d}/{d} ({d:.1}%)\n\n", .{ planted_block_ladder, planted_n, 100.0 * @as(f64, @floatFromInt(planted_block_ladder)) / @as(f64, @floatFromInt(@max(1, planted_n))) });

    try out.print("NO-HARM (real POST-revision ON-pass promotions, n={d} across 3 seeds; live v4 admitted ALL):\n", .{noharm_n});
    try out.print("  v5-full  eps=0.00 disagreements (would-block): {d}/{d}\n", .{ noharm_flip_e0, noharm_n });
    try out.print("  v5-full  eps=0.02 disagreements: {d}/{d}\n", .{ noharm_flip_e02, noharm_n });
    try out.print("  v5-full  eps=0.05 disagreements: {d}/{d}\n", .{ noharm_flip_e05, noharm_n });
    try out.print("  v5-full  eps=0.08 disagreements: {d}/{d}\n", .{ noharm_flip_e08, noharm_n });
    try out.print("  v5-margin disagreements: {d}/{d}\n", .{ noharm_flip_margin, noharm_n });
    try out.print("  v5-ladder disagreements: {d}/{d}\n", .{ noharm_flip_ladder, noharm_n });
    try out.print("  (pre-revision events, live=v3-strict, n={d}: v5-full(e0) flips={d}, v5-ladder flips={d})\n\n", .{ prerev_n, prerev_flip_e0, prerev_flip_ladder });

    try out.print("CSV: {s}\n", .{csv_path});
}
