//! Tier 8 AIMED PROPOSER — frontier-coupled feature composition for the
//! battery-C wall (T8-AG-11 / tier8_ablation.zig finding: 10 of 11 battery-C
//! targets sit at ~0.50 coverage for BOTH the frozen (v3) and revised (v4)
//! ladder-only arms; the ladder has no primitive that can represent an XOR of
//! cell values, only threshold-of-3 style splits).
//!
//! QUESTION: can a proposer that mines the NEAR-MISS structure of the ladder's
//! own failed search (best correlated-but-insufficient monomial/Walsh masks,
//! their held-out residuals, and any tax-blocked-but-certified escapes) and
//! COMPOSES new candidates from that evidence (transforms/combinations of the
//! near-miss features) flip any of the 10 stuck targets — WITHOUT drawing a
//! ready-made "xor primitive" from a fixed pool?
//!
//! Design (per docs/research/research_round_2026_07_10.md follow-up queue +
//! the 2026-07-10b task brief):
//!   1. Baselines re-run in-harness at the same 3 seeds as yesterday's
//!      tier8_ablation.zig: ladder-only frozen (v3, no revision) and
//!      ladder-only + revision (v4 + reality lane). Expect 0/33 and 3/33.
//!   2. Aimed proposer, run per target still unsolved after the STRONGER
//!      (revision) baseline:
//!        a. EVIDENCE MINING: exhaustive degree<=4 monomial sweep (162 masks)
//!           and Walsh-S sweep (256 patterns) over the SAME held-out split the
//!           real ladder uses -- this is exactly what tryMonomialForge /
//!           tryConditionalWalsh already do internally, just with the
//!           near-miss score CAPTURED instead of thrown away after a "not
//!           certified" print. Also scan eqtax.tax_log for blocked-but-
//!           escape-shaped witnesses (expect ~0, per yesterday's finding).
//!        b. COMPOSE: take the single best near-miss monomial mask as the
//!           evidence-derived cell-subset anchor. Scan 6 elementary per-cell
//!           LENSES (threshold @1..5, i.e. a generalization of the ladder's
//!           fixed threshold-@3 split, plus mod-2/LSB) applied to that SAME
//!           mask, scored by held-out accuracy -- i.e. "which transform of
//!           the evidence explains the residual". Then greedily
//!           grow/shrink the mask one cell at a time under the winning lens
//!           (forward/backward stepwise selection, capped 16 rounds) --
//!           this is NOT capped at the ladder's degree<=4 (needed for C11,
//!           a degree-5 target). A secondary, cheaper avenue is also tried:
//!           the raw PRODUCT of the two near-miss features themselves
//!           (mono x walsh, no per-cell transform at all) -- reported as a
//!           diagnostic contrast.
//!        c. CERTIFY the grown composed candidate through the real
//!           coverage/irreducibility bar (escape >=0.90 held-out from below,
//!           AND R^2<0.40 against the existing library) -- same thresholds,
//!           same NSAMP/NTR/NVA split as unified_invention.zig's certify().
//!           Tax is NOT a gate here (hard constraint): it is computed AFTER
//!           certification purely as an export-filter/report signal (a
//!           correlation-vs-existing-features proxy -- see honesty note
//!           below for why the REAL eqtax.gatePromoteEx can't be called
//!           directly on this candidate type).
//!   3. A DELIBERATELY UNAIMED CONTROL (single seed, clearly separated from
//!      the headline number): brute-force sweep of ALL 255 masks (any
//!      popcount) x all 6 lenses, no evidence-guidance at all. This is the
//!      "just admit the missing primitive and re-run the existing exhaustive
//!      search" shortcut the 2026-07-10 ablation flagged as the trivial fix
//!      -- run here ONLY to show what unaimed brute force can reach, as the
//!      contrast the honesty check requires.
//!
//! HONESTY / derivation-chain note (mandatory per task brief point 4):
//! this file never calls open_invention_e2.zig's `xorMasked` / an
//! `xorPopcountReadout`, nor equivalence_tax.zig's `buildXorCols` (both of
//! which already implement an XOR-of-raw-values readout internally, used
//! ONLY for the tax module's own remix-basis auditing / e2's own separate
//! xor-aware forge -- never exposed to unified_invention.zig's ladder). If a
//! target flips here, the composed feature must have been discovered via the
//! per-cell LENS sweep + greedy mask search on THIS file's own from-scratch
//! numeric implementation, not via a shortcut through that pre-built xor
//! machinery. (`grep -c xorMasked\|xorPopcountReadout\|buildXorCols` on this
//! file must be 0 -- checked as part of the write-up.)
//!
//! Engineering note: equivalence_tax.zig's greedyFit column store is now
//! heap-allocated (commit 67fdd13), so this file needs no big-stack worker
//! thread -- plain single-threaded main().
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe tier8_aimed_proposer.zig -O ReleaseFast
//! Run:
//!   ./tier8_aimed_proposer
//!
//! New file only -- no existing file modified. Read-only reuse of
//! tier8_ablation.zig's plumbing pattern (prepareBlindBatterySeed,
//! seedUiFromRq1, the fresh-library-per-C-target convention, the 3 seeds).

const std = @import("std");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");
const bc = @import("open_invention_tier8_battery_c.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

/// Same 3 seeds as docs/research/tier8_ablation.md.
const SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };

const NSAMP: usize = ui.NSAMP;
const NTR: usize = ui.NTR;
const NVA: usize = ui.NVA;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;

// ── Local numeric mirrors of unified_invention.zig's private routines ──────
// (measureCoverage/evalFeaturePublic are pub and reused directly; fitLogit /
// accLogit / reconR2 / buildFeat's normalization step are private there, and
// certifyPublic's signature couples library+candidate to a single grid
// array, which the transformed-lens candidate below breaks -- so the small
// amount of numeric glue needed to score an AUGMENTED library+candidate is
// reproduced here, same hyperparameters, same splits.)

fn sigmoidL(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn fitLogitL(X: [][]f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoidL(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
}

fn accLogitL(X: [][]f64, Y: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

/// Overwrite X[s][0..lib.len] with normalized library features (same
/// convention as unified_invention.zig's buildFeat) and append ONE more
/// normalized column (dim index = lib.len) built from `cand_raw`.
fn buildAugmented(X: [][]f64, grid: []const [8]u8, lib: []const ui.Feature, cand_raw: []const f64) void {
    const k = lib.len;
    for (0..NSAMP) |s| {
        for (0..k) |c| X[s][c] = ui.evalFeaturePublic(lib[c], grid[s]);
        X[s][k] = cand_raw[s];
    }
    for (0..k + 1) |c| {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += X[s][c];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (X[s][c] - mu) * (X[s][c] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| X[s][c] = (X[s][c] - mu) / sd;
    }
}

fn coverageAugmented(X: [][]f64, grid: []const [8]u8, lib: []const ui.Feature, cand_raw: []const f64, Y: []const f64, w: []f64) f64 {
    buildAugmented(X, grid, lib, cand_raw);
    const dim = lib.len + 1;
    fitLogitL(X, Y, dim, 150, 0.05, w);
    return accLogitL(X, Y, w, dim, NVA, NSAMP);
}

/// R^2 of reconstructing raw candidate values from the (already normalized,
/// library-only) columns in X[0..lib_len] -- mirrors unified_invention.zig's
/// private reconR2 exactly (400 epochs, lr 0.01, fit on train, R^2 on test).
fn reconR2L(X: [][]f64, lib_len: usize, cand_raw: []const f64, w: []f64) f64 {
    @memset(w[0 .. lib_len + 1], 0);
    for (0..400) |_| for (0..NTR) |s| {
        var z = w[lib_len];
        for (0..lib_len) |j| z += w[j] * X[s][j];
        const e = z - cand_raw[s];
        for (0..lib_len) |j| w[j] -= 0.01 * e * X[s][j];
        w[lib_len] -= 0.01 * e;
    };
    var mu: f64 = 0;
    for (NVA..NSAMP) |s| mu += cand_raw[s];
    mu /= @floatFromInt(NSAMP - NVA);
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (NVA..NSAMP) |s| {
        var z = w[lib_len];
        for (0..lib_len) |j| z += w[j] * X[s][j];
        ssr += (cand_raw[s] - z) * (cand_raw[s] - z);
        sst += (cand_raw[s] - mu) * (cand_raw[s] - mu);
    }
    return 1.0 - ssr / @max(1e-9, sst);
}

/// Single-feature probe accuracy on the SEARCH split (train fit, val score)
/// -- mirrors unified_invention.zig's private valAccSingle exactly. Used for
/// near-miss evidence mining and lens/mask scoring (NOT the final certify,
/// which uses the held-out TEST split NVA..NSAMP via coverageAugmented).
fn valAccSingleL(feat: []const f64, Y: []const f64) f64 {
    var w: [2]f64 = .{ 0.0, 0.0 };
    for (0..80) |_| for (0..NTR) |s| {
        const e = sigmoidL(w[0] * feat[s] + w[1]) - Y[s];
        w[0] -= 0.1 * e * feat[s];
        w[1] -= 0.1 * e;
    };
    var c: usize = 0;
    for (NTR..NVA) |s| {
        if ((w[0] * feat[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NVA - NTR));
}

fn corrTest(a: []const f64, b: []const f64) f64 {
    var ma: f64 = 0;
    var mb: f64 = 0;
    const n: f64 = @floatFromInt(NSAMP - NVA);
    for (NVA..NSAMP) |s| {
        ma += a[s];
        mb += b[s];
    }
    ma /= n;
    mb /= n;
    var num: f64 = 0;
    var da: f64 = 0;
    var db: f64 = 0;
    for (NVA..NSAMP) |s| {
        const xa = a[s] - ma;
        const xb = b[s] - mb;
        num += xa * xb;
        da += xa * xa;
        db += xb * xb;
    }
    return num / @max(1e-12, @sqrt(da * db));
}

// ── Evidence mining ─────────────────────────────────────────────────────────

const MonoEvidence = struct { mask: u8, val: f64 };
const WalshEvidence = struct { s: u8, val: f64 };

fn monomialSweep(grid: []const [8]u8, Y: []const f64, scratch: []f64, evals: *usize) MonoEvidence {
    var best_val: f64 = -1;
    var best_mask: u8 = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        const pc = @popCount(mask);
        if (pc < 1 or pc > 4) continue;
        for (0..NSAMP) |s| scratch[s] = ui.evalFeaturePublic(.{ .monomial = mask }, grid[s]);
        const v = valAccSingleL(scratch, Y);
        evals.* += 1;
        if (v > best_val) {
            best_val = v;
            best_mask = mask;
        }
    }
    return .{ .mask = best_mask, .val = best_val };
}

fn walshSweep(grid: []const [8]u8, Y: []const f64, scratch: []f64, evals: *usize) WalshEvidence {
    var best_val: f64 = -1;
    var best_s: u8 = 0;
    var sm: u16 = 0;
    while (sm < 256) : (sm += 1) {
        const sv: u8 = @intCast(sm);
        for (0..NSAMP) |s| scratch[s] = ui.evalFeaturePublic(.{ .walsh = sv }, grid[s]);
        const v = valAccSingleL(scratch, Y);
        evals.* += 1;
        if (v > best_val) {
            best_val = v;
            best_s = sv;
        }
    }
    return .{ .s = best_s, .val = best_val };
}

// ── Composition: per-cell lenses + greedy mask growth ──────────────────────

const Lens = enum { th1, th2, th3, th4, th5, mod2 };
const LENSES = [_]Lens{ .th1, .th2, .th3, .th4, .th5, .mod2 };

fn lensBit(v: u8, lens: Lens) bool {
    return switch (lens) {
        .th1 => v >= 1,
        .th2 => v >= 2,
        .th3 => v >= 3, // == the ladder's existing threshold split (signPattern/phi sign)
        .th4 => v >= 4,
        .th5 => v >= 5,
        .mod2 => (v & 1) == 1, // LSB / parity split -- NOT in the ladder's Feature union
    };
}

fn composedVal(row: [8]u8, mask: u8, lens: Lens) f64 {
    var bits: u32 = 0;
    for (0..8) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0 and lensBit(row[i], lens)) bits += 1;
    }
    return if (bits & 1 == 0) 1.0 else -1.0;
}

fn composedSweepVal(grid: []const [8]u8, mask: u8, lens: Lens, Y: []const f64, scratch: []f64) f64 {
    for (0..NSAMP) |s| scratch[s] = composedVal(grid[s], mask, lens);
    return valAccSingleL(scratch, Y);
}

const GrowResult = struct { mask: u8, val: f64, rounds: usize };

/// Greedy forward/backward stepwise mask search under a FIXED lens, seeded
/// from the evidence mask. Not capped at the ladder's degree<=4 (needed for
/// C11's 5-cell true mask). On a genuine k-way parity target this is a flat
/// (zero-gradient) landscape everywhere except the exact true mask, so this
/// search is expected to plateau unless the seed mask is already close.
fn greedyGrow(grid: []const [8]u8, Y: []const f64, scratch: []f64, start_mask: u8, lens: Lens, evals: *usize) GrowResult {
    var mask = start_mask;
    var best_val = composedSweepVal(grid, mask, lens, Y, scratch);
    evals.* += 1;
    var rounds: usize = 0;
    var improved = true;
    while (improved and rounds < 16) : (rounds += 1) {
        improved = false;
        var try_mask = mask;
        var try_val = best_val;
        for (0..8) |i| {
            const bit: u8 = @as(u8, 1) << @intCast(i);
            const cm = mask ^ bit;
            if (cm == 0) continue;
            const v = composedSweepVal(grid, cm, lens, Y, scratch);
            evals.* += 1;
            if (v > try_val) {
                try_val = v;
                try_mask = cm;
            }
        }
        if (try_val > best_val + 1e-9) {
            best_val = try_val;
            mask = try_mask;
            improved = true;
        }
    }
    return .{ .mask = mask, .val = best_val, .rounds = rounds };
}

// ── Aimed proposer result ───────────────────────────────────────────────────

const AimedResult = struct {
    already_solved_by_ladder: bool,
    cov_before: f64,
    mono_mask: u8,
    mono_val: f64,
    walsh_s: u8,
    walsh_val: f64,
    combo_val: f64, // product of the two near-miss features, no lens transform
    blocked_witnesses: usize,
    chosen_lens: Lens,
    lens_scan: [6]f64,
    seed_mask: u8, // == mono_mask, the evidence anchor
    grown_mask: u8,
    grown_val: f64,
    grown_rounds: usize,
    cov_after: f64,
    r2: f64,
    certified: bool,
    tax_proxy_novel: bool,
    tax_proxy_best_corr: f64,
    evals: usize,
};

fn taxProxy(
    grid: []const [8]u8,
    lib: []const ui.Feature,
    mono_mask: u8,
    walsh_s: u8,
    cand_raw: []const f64,
) struct { novel: bool, best_corr: f64 } {
    var best: f64 = 0;
    var mono_buf: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| mono_buf[s] = ui.evalFeaturePublic(.{ .monomial = mono_mask }, grid[s]);
    best = @max(best, @abs(corrTest(cand_raw, mono_buf[0..])));
    var walsh_buf: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| walsh_buf[s] = ui.evalFeaturePublic(.{ .walsh = walsh_s }, grid[s]);
    best = @max(best, @abs(corrTest(cand_raw, walsh_buf[0..])));
    var lib_buf: [NSAMP]f64 = undefined;
    for (lib) |f| {
        for (0..NSAMP) |s| lib_buf[s] = ui.evalFeaturePublic(f, grid[s]);
        best = @max(best, @abs(corrTest(cand_raw, lib_buf[0..])));
    }
    return .{ .novel = best <= 0.90, .best_corr = best };
}

/// Run the standard ladder to exhaustion (identical call as the baselines),
/// then -- only if still unsolved -- mine near-miss evidence and compose.
fn runAimedProposer(
    X: [][]f64,
    grid: []const [8]u8,
    phiTgt: []f64,
    trained_lib: []const rq1.Feature,
    Y: []const f64,
    scratch: []f64,
) AimedResult {
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(trained_lib, &lib, &nlib);
    var w_mut: [33]f64 = undefined;

    const r0 = eqtax.stats.remix_blocked;
    const m = ui.solveOneTarget(X, grid, &lib, &nlib, Y, phiTgt, w_mut[0..], SilentOut{}, true);
    const blocked = eqtax.stats.remix_blocked - r0;

    if (m.solved) {
        return .{
            .already_solved_by_ladder = true,
            .cov_before = m.cov,
            .mono_mask = 0,
            .mono_val = 0,
            .walsh_s = 0,
            .walsh_val = 0,
            .combo_val = 0,
            .blocked_witnesses = blocked,
            .chosen_lens = .th3,
            .lens_scan = .{0} ** 6,
            .seed_mask = 0,
            .grown_mask = 0,
            .grown_val = 0,
            .grown_rounds = 0,
            .cov_after = m.cov,
            .r2 = 0,
            .certified = true,
            .tax_proxy_novel = false,
            .tax_proxy_best_corr = 0,
            .evals = 0,
        };
    }

    var evals: usize = 0;
    const mono_ev = monomialSweep(grid, Y, scratch, &evals);
    const walsh_ev = walshSweep(grid, Y, scratch, &evals);
    const combo_val = blk: {
        var mono_buf: [NSAMP]f64 = undefined;
        var walsh_buf: [NSAMP]f64 = undefined;
        for (0..NSAMP) |s| mono_buf[s] = ui.evalFeaturePublic(.{ .monomial = mono_ev.mask }, grid[s]);
        for (0..NSAMP) |s| walsh_buf[s] = ui.evalFeaturePublic(.{ .walsh = walsh_ev.s }, grid[s]);
        for (0..NSAMP) |s| scratch[s] = mono_buf[s] * walsh_buf[s];
        evals += 1;
        break :blk valAccSingleL(scratch, Y);
    };

    var lens_scan: [6]f64 = undefined;
    for (LENSES, 0..) |lens, li| {
        lens_scan[li] = composedSweepVal(grid, mono_ev.mask, lens, Y, scratch);
        evals += 1;
    }
    var best_li: usize = 0;
    for (1..6) |li| {
        if (lens_scan[li] > lens_scan[best_li]) best_li = li;
    }
    const chosen_lens = LENSES[best_li];

    const grown = greedyGrow(grid, Y, scratch, mono_ev.mask, chosen_lens, &evals);

    var cand_raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| cand_raw[s] = composedVal(grid[s], grown.mask, chosen_lens);

    const cov_before = ui.measureCoverage(X, grid, lib[0..nlib], Y, w_mut[0..]);
    var w_r2: [34]f64 = undefined;
    const r2 = reconR2L(X, nlib, cand_raw[0..], w_r2[0..]);
    var w_aug: [34]f64 = undefined;
    const cov_after = coverageAugmented(X, grid, lib[0..nlib], cand_raw[0..], Y, w_aug[0..]);
    evals += 2; // one coverage fit, one R^2 fit

    const escape = cov_after >= COVER and cov_before < COVER;
    const certified = escape and r2 < R2_MAX;

    const tp = taxProxy(grid, lib[0..nlib], mono_ev.mask, walsh_ev.s, cand_raw[0..]);

    return .{
        .already_solved_by_ladder = false,
        .cov_before = cov_before,
        .mono_mask = mono_ev.mask,
        .mono_val = mono_ev.val,
        .walsh_s = walsh_ev.s,
        .walsh_val = walsh_ev.val,
        .combo_val = combo_val,
        .blocked_witnesses = blocked,
        .chosen_lens = chosen_lens,
        .lens_scan = lens_scan,
        .seed_mask = mono_ev.mask,
        .grown_mask = grown.mask,
        .grown_val = grown.val,
        .grown_rounds = grown.rounds,
        .cov_after = cov_after,
        .r2 = r2,
        .certified = certified,
        .tax_proxy_novel = tp.novel,
        .tax_proxy_best_corr = tp.best_corr,
        .evals = evals,
    };
}

// ── Baselines: ladder-only frozen (v3) / ladder-only + revision (v4) ──────
// Reproduces tier8_ablation.zig's Battery-C ladder-only slice numbers
// (0/33 frozen, 3/33 with revision). Simplification vs yesterday's harness:
// the revision arm here starts DIRECTLY at basis v4 / reality-lane-on rather
// than running Battery B first to trip the T8-AG-21 remix-rate trigger.
// Justified because (a) Battery C's fresh-per-target library never shares
// state with Battery B in tier8_ablation.zig either, and (b) yesterday's own
// finding was that the trigger fires after target 1 in every run ("ARM-ON is
// effectively v4 from target 2 onward") -- so this reproduces the same
// steady-state tax configuration without needing Battery B's ~30s of runtime
// per seed just to trip a threshold that fires almost immediately anyway.

const BaselineArm = enum { frozen, revision };

fn configureArm(arm: BaselineArm) void {
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();
    eqtax.strict_enabled = true;
    switch (arm) {
        .frozen => {
            eqtax.basis_level = 3;
            eqtax.reality_lane_enabled = false;
        },
        .revision => {
            eqtax.basis_level = 4;
            eqtax.reality_lane_enabled = true;
        },
    }
}

fn runLadderOnlyBattery(
    X: [][]f64,
    grid: []const [8]u8,
    phiTgt: []f64,
    trained_lib: []const rq1.Feature,
    arm: BaselineArm,
    solved_mask: *[bc.BATTERY_C.len]bool,
    cov_out: *[bc.BATTERY_C.len]f64,
) usize {
    configureArm(arm);
    var solved: usize = 0;
    for (bc.BATTERY_C, 0..) |tgt, ti| {
        var Yb: [NSAMP]f64 = undefined;
        for (0..NSAMP) |s| Yb[s] = bc.labelTarget(grid[s], tgt);
        var lib: [32]ui.Feature = undefined;
        var nlib: usize = 0;
        ie.seedUiFromRq1(trained_lib, &lib, &nlib);
        var w_mut: [33]f64 = undefined;
        const m = ui.solveOneTarget(X, grid, &lib, &nlib, Yb[0..], phiTgt, w_mut[0..], SilentOut{}, true);
        solved_mask[ti] = m.solved;
        cov_out[ti] = m.cov;
        if (m.solved) solved += 1;
    }
    return solved;
}

// ── Unaimed control: brute (mask x lens) sweep, no evidence guidance ──────

const ControlResult = struct { solved: bool, mask: u8, lens: Lens, val: f64, cov_before: f64, cov_after: f64, r2: f64 };

fn runBruteControl(
    X: [][]f64,
    grid: []const [8]u8,
    trained_lib: []const rq1.Feature,
    Y: []const f64,
) ControlResult {
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(trained_lib, &lib, &nlib);
    var w_mut: [33]f64 = undefined;
    const cov_before = ui.measureCoverage(X, grid, lib[0..nlib], Y, w_mut[0..]);

    var scratch: [NSAMP]f64 = undefined;
    var best_val: f64 = -1;
    var best_mask: u8 = 0;
    var best_lens: Lens = .th3;
    for (LENSES) |lens| {
        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const mask: u8 = @intCast(mm);
            const v = composedSweepVal(grid, mask, lens, Y, scratch[0..]);
            if (v > best_val) {
                best_val = v;
                best_mask = mask;
                best_lens = lens;
            }
        }
    }
    var cand_raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| cand_raw[s] = composedVal(grid[s], best_mask, best_lens);
    var w_r2: [34]f64 = undefined;
    const r2 = reconR2L(X, nlib, cand_raw[0..], w_r2[0..]);
    var w_aug: [34]f64 = undefined;
    const cov_after = coverageAugmented(X, grid, lib[0..nlib], cand_raw[0..], Y, w_aug[0..]);
    const escape = cov_after >= COVER and cov_before < COVER;
    return .{
        .solved = escape and r2 < R2_MAX,
        .mask = best_mask,
        .lens = best_lens,
        .val = best_val,
        .cov_before = cov_before,
        .cov_after = cov_after,
        .r2 = r2,
    };
}

// ── Main ─────────────────────────────────────────────────────────────────

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/aimed_proposer_2026_07_10.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("seed,arm,target,family,solved,cov_before,cov_after,r2,mono_mask,mono_val,walsh_s,walsh_val,combo_val,chosen_lens,seed_mask,grown_mask,grown_val,grown_rounds,blocked_witnesses,evals,tax_proxy_novel,tax_proxy_best_corr\n", .{});

    try out.print("=== TIER 8 AIMED PROPOSER: frontier-coupled composition for the battery-C wall ===\n\n", .{});

    var tot_frozen: usize = 0;
    var tot_revision: usize = 0;
    var tot_aimed: usize = 0;
    var flips: usize = 0;
    var total_evals: usize = 0;

    for (SEEDS, 0..) |seed, si| {
        try out.print("──── seed 0x{X:0>16} ────\n", .{seed});
        const prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
        const ctx = prep.ctx;

        var solved_frozen: [bc.BATTERY_C.len]bool = undefined;
        var cov_frozen: [bc.BATTERY_C.len]f64 = undefined;
        const nf = runLadderOnlyBattery(ctx.X, ctx.grid, ctx.phiTgt, prep.trained_lib, .frozen, &solved_frozen, &cov_frozen);
        tot_frozen += nf;

        var solved_rev: [bc.BATTERY_C.len]bool = undefined;
        var cov_rev: [bc.BATTERY_C.len]f64 = undefined;
        const nr = runLadderOnlyBattery(ctx.X, ctx.grid, ctx.phiTgt, prep.trained_lib, .revision, &solved_rev, &cov_rev);
        tot_revision += nr;

        try out.print("  BASELINE frozen(v3):   {d}/{d}\n", .{ nf, bc.BATTERY_C.len });
        try out.print("  BASELINE revision(v4): {d}/{d}\n", .{ nr, bc.BATTERY_C.len });

        for (bc.BATTERY_C, 0..) |tgt, ti| {
            try cw.print("0x{X:0>16},frozen,\"{s}\",{s},{d},{d:.4},,,,,,,,,,,,,,,,\n", .{
                seed, tgt.name, tgt.family, @intFromBool(solved_frozen[ti]), cov_frozen[ti],
            });
            try cw.print("0x{X:0>16},revision,\"{s}\",{s},{d},{d:.4},,,,,,,,,,,,,,,,\n", .{
                seed, tgt.name, tgt.family, @intFromBool(solved_rev[ti]), cov_rev[ti],
            });
        }

        // Aimed proposer: only on targets the STRONGER (revision) baseline missed.
        configureArm(.revision); // tax config the aimed proposer layers on top of
        try out.print("  AIMED PROPOSER on targets unsolved by revision baseline:\n", .{});
        var n_aimed_solved: usize = 0;
        for (bc.BATTERY_C, 0..) |tgt, ti| {
            if (solved_rev[ti]) continue; // already solved, nothing to aim at
            var Yb: [NSAMP]f64 = undefined;
            for (0..NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);
            var scratch: [NSAMP]f64 = undefined;
            const r = runAimedProposer(ctx.X, ctx.grid, ctx.phiTgt, prep.trained_lib, Yb[0..], scratch[0..]);
            total_evals += r.evals;
            if (r.certified) {
                n_aimed_solved += 1;
                flips += 1;
                try out.print("    >> FLIP: {s} solved via composed mask=0x{X:0>2} lens={s} (seed_mask=0x{X:0>2} mono_val={d:.3} walsh(S=0x{X:0>2})_val={d:.3} cov {d:.3}->{d:.3} R2={d:.3})\n", .{
                    tgt.name, r.grown_mask, @tagName(r.chosen_lens), r.seed_mask, r.mono_val, r.walsh_s, r.walsh_val, r.cov_before, r.cov_after, r.r2,
                });
            } else {
                try out.print("    .. {s}: no flip (mono_val={d:.3} walsh_val={d:.3} combo_val={d:.3} best_lens={s} grown_val={d:.3} cov {d:.3}->{d:.3} R2={d:.3} blocked_witnesses={d})\n", .{
                    tgt.name, r.mono_val, r.walsh_val, r.combo_val, @tagName(r.chosen_lens), r.grown_val, r.cov_before, r.cov_after, r.r2, r.blocked_witnesses,
                });
            }
            try cw.print("0x{X:0>16},aimed,\"{s}\",{s},{d},{d:.4},{d:.4},{d:.4},0x{X:0>2},{d:.4},0x{X:0>2},{d:.4},{d:.4},{s},0x{X:0>2},0x{X:0>2},{d:.4},{d},{d},{d},{s},{d:.4}\n", .{
                seed,               tgt.name,   tgt.family,       @intFromBool(r.certified),
                r.cov_before,       r.cov_after, r.r2,            r.mono_mask,
                r.mono_val,         r.walsh_s,   r.walsh_val,      r.combo_val,
                @tagName(r.chosen_lens), r.seed_mask, r.grown_mask, r.grown_val,
                r.grown_rounds,     r.blocked_witnesses, r.evals,  if (r.tax_proxy_novel) "novel" else "remix",
                r.tax_proxy_best_corr,
            });
        }
        tot_aimed += nr + n_aimed_solved;
        try out.print("  aimed-proposer flips this seed: {d}\n\n", .{n_aimed_solved});

        // Unaimed control (single seed only, production seed, clearly separated).
        if (si == 0) {
            try out.print("  ── UNAIMED CONTROL (brute mask x lens sweep, seed 0 only, NOT part of the aimed headline) ──\n", .{});
            for (bc.BATTERY_C, 0..) |tgt, ti| {
                if (solved_rev[ti]) continue;
                var Yb: [NSAMP]f64 = undefined;
                for (0..NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);
                const cr = runBruteControl(ctx.X, ctx.grid, prep.trained_lib, Yb[0..]);
                try out.print("    {s}: solved={} mask=0x{X:0>2} lens={s} val={d:.3} cov {d:.3}->{d:.3} R2={d:.3}\n", .{
                    tgt.name, cr.solved, cr.mask, @tagName(cr.lens), cr.val, cr.cov_before, cr.cov_after, cr.r2,
                });
                try cw.print("0x{X:0>16},control,\"{s}\",{s},{d},{d:.4},{d:.4},{d:.4},,,,,,{s},0x{X:0>2},0x{X:0>2},{d:.4},,,,,\n", .{
                    seed, tgt.name, tgt.family, @intFromBool(cr.solved), cr.cov_before, cr.cov_after, cr.r2, @tagName(cr.lens), cr.mask, cr.mask, cr.val,
                });
            }
        }
    }

    const total_targets = SEEDS.len * bc.BATTERY_C.len;
    try out.print("════════════════ SUMMARY ({d} seeds x {d} targets = {d}) ════════════════\n", .{ SEEDS.len, bc.BATTERY_C.len, total_targets });
    try out.print("  baseline frozen (v3, no revision):   {d}/{d}\n", .{ tot_frozen, total_targets });
    try out.print("  baseline revision (v4 + reality lane): {d}/{d}\n", .{ tot_revision, total_targets });
    try out.print("  aimed proposer (revision + composition): {d}/{d}  (+{d} flip(s) beyond revision baseline)\n", .{ tot_aimed, total_targets, flips });
    try out.print("  total aimed-proposer eval cost (mining+compose+certify, excl. ladder itself): {d}\n", .{total_evals});
    try out.print("  CSV: {s}\n", .{csv_path});
    try out.print("  VERDICT: frontier-coupled composition {s} the 10/11 wall.\n", .{if (flips > 0) "MOVES" else "does NOT move"});
}
