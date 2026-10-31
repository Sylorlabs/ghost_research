//! Tier 8 EVIDENCE LENSES — raising the (1/3)^k aiming signal at the
//! battery-C wall (follow-up to tier8_aimed_proposer.zig, 2026-07-10b exp 2).
//!
//! YESTERDAY'S DERIVED LIMIT: the aimed proposer's evidence miner scores
//! candidate cell-subsets with the ladder's only per-cell bit, tb(v)=[v>=3].
//! A k-cell XOR target's label is parity of the mod-2 bits lb(v)=v&1, and
//! E[(-1)^{tb+lb}] = 1/3 per cell, so the tb-parity evidence at the TRUE mask
//! carries correlation exactly (1/3)^k (and exactly 0 at every other mask) —
//! below the 162-way argmax noise floor sqrt(2 ln 324)/sqrt(3500) ~ 0.058 at
//! degree >= 4. Hence ~17%/attempt hit rate at degree 4, 0/3 at degree 5
//! (C11), and a family-level miss on C09 (inversion-count parity, an
//! order-statistic that is not a function of any fixed cell subset).
//!
//! THIS EXPERIMENT: build better evidence lenses and derive each one's signal
//! formula BEFORE measuring it (culture requirement):
//!
//!   L0  baseline tb-parity argmax (162 masks, |corr| scored) — the control.
//!       Signal (1/3)^k iff mask == T.
//!   L1  single-upgrade mixed lens: lb on ONE cell i, tb on the rest of M.
//!       Signal (1/3)^{k-1} iff M == T and i in T (3x per recovered cell).
//!   L2  pairwise/second-order lens: lb on a PAIR {i,j} <= M, tb on M\{i,j}.
//!       Signal (1/3)^{k-2} iff M == T and pair <= T (9x baseline; recovered
//!       cells COMPOSE: u recovered true cells give (1/3)^{k-u}).
//!       [Correction to the round brief's a-priori "(1/3)^(k-1) per recovered
//!       pair": the derivation gives (1/3)^{k-1} per recovered CELL and
//!       (1/3)^{k-2} per recovered pair.]
//!   L3  Gibbs/conditional lens: greedy growth of (mask M, upgraded set U)
//!       seeded from L1/L2's top-J candidates, re-measuring the conditional
//!       signal (1/3)^{k-|U ∩ T|} after each accepted move, with a held-out
//!       ENDPOINT CHECK (full-mod2 parity of M on the val rows; null sd
//!       1/sqrt(1750) ~ 0.024, so accept-threshold 0.90 has ~0 false-accept
//!       probability). This beats the flat argmax structurally: the flat
//!       argmax needs the true candidate at rank 1 of ~1792; Gibbs+endpoint
//!       only needs it in the top J, because a wrong endpoint cannot pass
//!       the ~40-sigma validation bar.
//!   LW  Walsh spectral concentration on the residual, taken over the lb
//!       bits (and tb bits): WHT coefficient at S equals corr(Y, parity_S) =
//!       1.0 at S=T on the lb side (0 elsewhere); on the tb side it is the
//!       same (1/3)^k as L0 — which also shows yesterday's two evidence
//!       channels (monomial-sign sweep and chi_S Walsh sweep) were secretly
//!       the SAME tb-parity family with the same ceiling.
//!   LG  GF(2) joint solve (the algebraic lens): dictionary = 28 pairwise
//!       comparison bits c_ij=[g_i>g_j] + 8 lb + 8 tb + intercept (45
//!       columns). Every battery-C parity target is GF(2)-LINEAR in this
//!       dictionary (xor family: lb-mask; C08: tb-mask 0xFF; C09: inversion
//!       parity == XOR of ALL 28 comparison bits, by definition of inversion
//!       count). Labels are noiseless, so Gaussian elimination on ~3500 rows
//!       identifies the exact mask with k-INDEPENDENT signal (failure prob ~
//!       P(rank deficiency) ~ 0), and out-of-family targets are rejected by
//!       the consistency + held-out-validation check. The information-
//!       theoretic point: correlation lenses estimate one candidate at a
//!       time, paying (1/3)^k per candidate; elimination solves all 2^45
//!       parity hypotheses jointly because the family is closed under GF(2)
//!       addition — the argmax noise floor disappears.
//!   C09 probes (order-statistic lens family, task point c): single
//!       comparison-bit correlations, random pair-subset parities, and a
//!       Gibbs climb in comparison-bit space — all derived/expected ~0
//!       (inversion parity's spectrum over the c-bits is concentrated on the
//!       full 28-bit character), so C09 should be fixable ONLY by the joint
//!       algebraic lens, not by any correlation statistic in the same
//!       dictionary. That is the C09 verdict this file measures.
//!
//! PIPELINE (task point 3): same 3 seeds as yesterday; revision baseline
//! re-run in-harness; yesterday's aimed proposer (v1) re-run byte-identical
//! (expect 8/33); new aimed proposer (v2 = LG with LW/Gibbs fallbacks) on the
//! same stuck targets; certification through the identical coverage/R^2 bar;
//! tax as export filter/report only.
//!
//! HONESTY (task point 4): this file never calls open_invention_e2.zig's
//! xorMasked / xorPopcountReadout nor equivalence_tax.zig's buildXorCols
//! (grep must match only this comment). Ground-truth labels come from
//! bc.labelTarget (the target oracle), exactly as yesterday's harness. Every
//! v2 flip prints its full derivation chain: recovered GF(2) coefficients
//! (cmp/lb/tb/intercept) vs the target's ground-truth mask, compared
//! programmatically. Search uses only rows [0,5250); the certify bar uses
//! the held-out test rows [5250,7000) exactly as unified_invention.zig does.
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe tier8_lenses.zig -O ReleaseFast
//! Run:
//!   ./tier8_lenses                      # full: lab + pipeline, 3 seeds
//!   ./tier8_lenses --lab-only --seeds=1 --resamples=2   # smoke
//!
//! New file only — no existing file modified. The v1 block below is a
//! read-only verbatim copy from tier8_aimed_proposer.zig (kept byte-level
//! identical so the 8/33 baseline reproduces exactly).

const std = @import("std");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");
const bc = @import("open_invention_tier8_battery_c.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

/// Same 3 seeds as docs/research/tier8_ablation.md / tier8_aimed_proposer.md.
const SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };

const NSAMP: usize = ui.NSAMP;
const NTR: usize = ui.NTR;
const NVA: usize = ui.NVA;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;

// ════════════════════════════════════════════════════════════════════════════
// V1 BLOCK — verbatim copy of tier8_aimed_proposer.zig's machinery (read-only
// reuse; that file's fns are not pub). Needed to re-run the 8/33 baseline
// in-harness. Do not modify.
// ════════════════════════════════════════════════════════════════════════════

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

const Lens = enum { th1, th2, th3, th4, th5, mod2 };
const LENSES = [_]Lens{ .th1, .th2, .th3, .th4, .th5, .mod2 };

fn lensBit(v: u8, lens: Lens) bool {
    return switch (lens) {
        .th1 => v >= 1,
        .th2 => v >= 2,
        .th3 => v >= 3,
        .th4 => v >= 4,
        .th5 => v >= 5,
        .mod2 => (v & 1) == 1,
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

const AimedResult = struct {
    already_solved_by_ladder: bool,
    cov_before: f64,
    mono_mask: u8,
    mono_val: f64,
    walsh_s: u8,
    walsh_val: f64,
    combo_val: f64,
    blocked_witnesses: usize,
    chosen_lens: Lens,
    lens_scan: [6]f64,
    seed_mask: u8,
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
    evals += 2;

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

// ════════════════════════════════════════════════════════════════════════════
// NEW: bit infrastructure for the lens lab
// ════════════════════════════════════════════════════════════════════════════

const NPAIR: usize = 28;

/// Pair p -> (i,j), i<j, lexicographic: p=0:(0,1) 1:(0,2) ... 7:(1,2) ...
fn pairCells(p: usize) struct { i: usize, j: usize } {
    var k: usize = 0;
    for (0..8) |i| {
        for (i + 1..8) |j| {
            if (k == p) return .{ .i = i, .j = j };
            k += 1;
        }
    }
    unreachable;
}

const BitRow = struct { tb: u8, lb: u8, cmp: u32 };

fn bitsOf(g: [8]u8) BitRow {
    var tb: u8 = 0;
    var lb: u8 = 0;
    var cmp: u32 = 0;
    for (0..8) |i| {
        const bit = @as(u8, 1) << @intCast(i);
        if (g[i] >= 3) tb |= bit;
        if (g[i] & 1 == 1) lb |= bit;
    }
    var p: usize = 0;
    for (0..8) |i| {
        for (i + 1..8) |j| {
            if (g[i] > g[j]) cmp |= @as(u32, 1) << @intCast(p);
            p += 1;
        }
    }
    return .{ .tb = tb, .lb = lb, .cmp = cmp };
}

/// Signed agreement E[(-1)^{feature_parity XOR y}] over the given row indices.
/// feature parity = popcount(lb&lbm) + popcount(tb&tbm) + popcount(cmp&cmpm) mod 2.
fn agreeIdx(bits: []const BitRow, ybit: []const u8, idx: []const u32, lbm: u8, tbm: u8, cmpm: u32) f64 {
    var s: i64 = 0;
    for (idx) |t| {
        const b = bits[t];
        const p: u32 = (@as(u32, @popCount(b.lb & lbm)) + @as(u32, @popCount(b.tb & tbm)) + @as(u32, @popCount(b.cmp & cmpm))) & 1;
        s += if (p == ybit[t]) 1 else -1;
    }
    return @as(f64, @floatFromInt(s)) / @as(f64, @floatFromInt(idx.len));
}

// ── Ground truth metadata (from bc.BATTERY_C specs) ─────────────────────────

const TruthKind = enum { xor_lb, tb_parity, cmp_parity, none };

const TruthMeta = struct {
    kind: TruthKind = .none,
    lb: u8 = 0,
    tb: u8 = 0,
    cmp: u32 = 0,
    deg: usize = 0,
    /// cell-subset truth for the cell-mask lenses L0..L3 (xor: lb mask; C08: 0xFF)
    cell_truth: ?u8 = null,
};

const ALL28: u32 = 0x0FFF_FFFF;

fn metaForBattery(ti: usize) TruthMeta {
    const xm = [_]u8{ 0x0F, 0x33, 0x55, 0xAA, 0x3C, 0x66, 0x99, 0, 0, 0x0F, 0x37 };
    return switch (ti) {
        0, 1, 2, 3, 4, 5, 6, 9, 10 => .{
            .kind = .xor_lb,
            .lb = xm[ti],
            .deg = @popCount(xm[ti]),
            .cell_truth = xm[ti],
        },
        7 => .{ .kind = .tb_parity, .tb = 0xFF, .deg = 8, .cell_truth = 0xFF },
        8 => .{ .kind = .cmp_parity, .cmp = ALL28, .deg = 28 },
        else => unreachable,
    };
}

// ── Lens outputs ─────────────────────────────────────────────────────────────

const LensOut = struct {
    hit: bool = false,
    accepted: bool = false, // only meaningful for validated lenses (L3/LW/LG)
    false_accept: bool = false,
    alias_accept: bool = false, // LG: accepted, functionally right, different rep
    ev_lb: u8 = 0,
    ev_tb: u8 = 0,
    ev_cmp: u32 = 0,
    ev_k0: u8 = 0,
    stat: f64 = 0, // winning candidate's search-split score
    true_stat: f64 = 0, // signed score of the ground-truth candidate (the formula check)
    val_stat: f64 = 0,
    consistent: bool = false,
    rank: usize = 0,
    evals: usize = 0,
};

const SeedCand = struct { m: u8 = 0, u: u8 = 0, score: f64 = -1 };

fn pushSeed(list: []SeedCand, n: *usize, cand: SeedCand) void {
    if (n.* < list.len) {
        list[n.*] = cand;
        n.* += 1;
    } else if (cand.score > list[list.len - 1].score) {
        list[list.len - 1] = cand;
    } else return;
    // insertion sort the last element up
    var i: usize = n.* - 1;
    while (i > 0 and list[i].score > list[i - 1].score) : (i -= 1) {
        const tmp = list[i];
        list[i] = list[i - 1];
        list[i - 1] = tmp;
    }
}

// ── L0: baseline tb-parity argmax (162 masks). Signal (1/3)^k iff M==T. ────

fn lensL0(bits: []const BitRow, ybit: []const u8, idxS: []const u32, meta: TruthMeta) LensOut {
    var out = LensOut{};
    var best: f64 = -1;
    var best_m: u8 = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        const pc = @popCount(mask);
        if (pc < 1 or pc > 4) continue;
        const a = @abs(agreeIdx(bits, ybit, idxS, 0, mask, 0));
        out.evals += 1;
        if (a > best) {
            best = a;
            best_m = mask;
        }
    }
    out.stat = best;
    out.ev_tb = best_m;
    if (meta.cell_truth) |t| {
        out.true_stat = agreeIdx(bits, ybit, idxS, 0, t, 0);
        out.hit = best_m == t and meta.kind == .xor_lb; // pc<=4 excludes C08's 0xFF anyway
    }
    return out;
}

// ── L1: single-upgrade mixed lens. Signal (1/3)^{k-1} iff M==T, i in T. ────

fn lensL1(bits: []const BitRow, ybit: []const u8, idxS: []const u32, meta: TruthMeta, seeds: []SeedCand, nseeds: *usize) LensOut {
    var out = LensOut{};
    var best: f64 = -1;
    var best_m: u8 = 0;
    var best_u: u8 = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        if (@popCount(mask) < 2) continue;
        for (0..8) |i| {
            const bit = @as(u8, 1) << @intCast(i);
            if (mask & bit == 0) continue;
            const a = @abs(agreeIdx(bits, ybit, idxS, bit, mask ^ bit, 0));
            out.evals += 1;
            if (a > best) {
                best = a;
                best_m = mask;
                best_u = bit;
            }
            pushSeed(seeds, nseeds, .{ .m = mask, .u = bit, .score = a });
        }
    }
    out.stat = best;
    out.ev_lb = best_u;
    out.ev_tb = best_m ^ best_u;
    if (meta.cell_truth) |t| {
        // signed mean over the (T, i in T) candidates — the (1/3)^{k-1} check
        var acc: f64 = 0;
        var cnt: f64 = 0;
        for (0..8) |i| {
            const bit = @as(u8, 1) << @intCast(i);
            if (t & bit == 0) continue;
            acc += agreeIdx(bits, ybit, idxS, bit, t ^ bit, 0);
            cnt += 1;
        }
        if (cnt > 0) out.true_stat = acc / cnt;
        out.hit = best_m == t and meta.kind == .xor_lb;
    }
    return out;
}

// ── L2: pairwise mixed lens. Signal (1/3)^{k-2} iff M==T, pair<=T. ─────────

fn lensL2(bits: []const BitRow, ybit: []const u8, idxS: []const u32, meta: TruthMeta, seeds: []SeedCand, nseeds: *usize) LensOut {
    var out = LensOut{};
    var best: f64 = -1;
    var best_m: u8 = 0;
    var best_u: u8 = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        if (@popCount(mask) < 2) continue;
        for (0..8) |i| {
            const bi = @as(u8, 1) << @intCast(i);
            if (mask & bi == 0) continue;
            for (i + 1..8) |j| {
                const bj = @as(u8, 1) << @intCast(j);
                if (mask & bj == 0) continue;
                const u = bi | bj;
                const a = @abs(agreeIdx(bits, ybit, idxS, u, mask ^ u, 0));
                out.evals += 1;
                if (a > best) {
                    best = a;
                    best_m = mask;
                    best_u = u;
                }
                pushSeed(seeds, nseeds, .{ .m = mask, .u = u, .score = a });
            }
        }
    }
    out.stat = best;
    out.ev_lb = best_u;
    out.ev_tb = best_m ^ best_u;
    if (meta.cell_truth) |t| {
        var acc: f64 = 0;
        var cnt: f64 = 0;
        for (0..8) |i| {
            const bi = @as(u8, 1) << @intCast(i);
            if (t & bi == 0) continue;
            for (i + 1..8) |j| {
                const bj = @as(u8, 1) << @intCast(j);
                if (t & bj == 0) continue;
                acc += agreeIdx(bits, ybit, idxS, bi | bj, t ^ (bi | bj), 0);
                cnt += 1;
            }
        }
        if (cnt > 0) out.true_stat = acc / cnt;
        out.hit = best_m == t and meta.kind == .xor_lb;
    }
    return out;
}

// ── L3: Gibbs/conditional refinement with held-out endpoint validation ─────

const GIBBS_ACCEPT: f64 = 0.90;

fn gibbsFrom(bits: []const BitRow, ybit: []const u8, idxS: []const u32, m0: u8, up0: u8, evals: *usize) u8 {
    var m = m0;
    var u = up0;
    var cur = @abs(agreeIdx(bits, ybit, idxS, u, m ^ u, 0));
    evals.* += 1;
    var round: usize = 0;
    while (round < 16) : (round += 1) {
        var bm = m;
        var bu = u;
        var bs = cur;
        for (0..8) |i| {
            const bit = @as(u8, 1) << @intCast(i);
            // upgrade move: read cell i via lb instead of tb
            if (m & bit != 0 and u & bit == 0) {
                const s = @abs(agreeIdx(bits, ybit, idxS, u | bit, m ^ (u | bit), 0));
                evals.* += 1;
                if (s > bs) {
                    bs = s;
                    bm = m;
                    bu = u | bit;
                }
            }
            // toggle move: add/remove cell i from the mask
            var m2: u8 = undefined;
            var up2: u8 = undefined;
            if (m & bit != 0) {
                m2 = m & ~bit;
                up2 = u & ~bit;
            } else {
                m2 = m | bit;
                up2 = u;
            }
            if (m2 != 0) {
                const s = @abs(agreeIdx(bits, ybit, idxS, up2, m2 ^ up2, 0));
                evals.* += 1;
                if (s > bs) {
                    bs = s;
                    bm = m2;
                    bu = up2;
                }
            }
        }
        if (bs > cur + 1e-9) {
            m = bm;
            u = bu;
            cur = bs;
        } else break;
    }
    return m;
}

fn lensL3(
    bits: []const BitRow,
    ybit: []const u8,
    idxS: []const u32,
    idxV: []const u32,
    l1_seeds: []const SeedCand,
    l2_seeds: []const SeedCand,
    meta: TruthMeta,
) LensOut {
    var out = LensOut{};
    var best_val: f64 = -1;
    var best_m: u8 = 0;
    var done = false;
    for ([_][]const SeedCand{ l2_seeds, l1_seeds }) |seed_list| {
        if (done) break;
        for (seed_list) |sd| {
            const m = gibbsFrom(bits, ybit, idxS, sd.m, sd.u, &out.evals);
            const v = @abs(agreeIdx(bits, ybit, idxV, m, 0, 0)); // endpoint: full-mod2
            out.evals += 1;
            if (v > best_val) {
                best_val = v;
                best_m = m;
            }
            if (v >= GIBBS_ACCEPT) {
                done = true;
                break;
            }
        }
    }
    out.val_stat = best_val;
    out.accepted = best_val >= GIBBS_ACCEPT;
    out.ev_lb = best_m;
    out.stat = @abs(agreeIdx(bits, ybit, idxS, best_m, 0, 0));
    if (meta.cell_truth) |t| {
        out.hit = out.accepted and meta.kind == .xor_lb and best_m == t;
        out.false_accept = out.accepted and !out.hit;
    } else {
        out.false_accept = out.accepted;
    }
    return out;
}

// ── LW: Walsh spectral concentration over lb bits (and tb bits) ────────────

fn lensLW(bits: []const BitRow, ybit: []const u8, idxS: []const u32, idxV: []const u32, meta: TruthMeta) LensOut {
    var out = LensOut{};
    var h_lb = [_]i64{0} ** 256;
    var h_tb = [_]i64{0} ** 256;
    for (idxS) |t| {
        const sgn: i64 = if (ybit[t] == 0) 1 else -1;
        h_lb[bits[t].lb] += sgn;
        h_tb[bits[t].tb] += sgn;
    }
    const n: f64 = @floatFromInt(idxS.len);
    var best: f64 = 0;
    var best_m: u8 = 0;
    var best_ch: u1 = 0; // 0 = lb spectrum, 1 = tb spectrum
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        var acc_lb: i64 = 0;
        var acc_tb: i64 = 0;
        for (0..256) |pat| {
            const sgn: i64 = if (@popCount(@as(u8, @intCast(pat)) & mask) & 1 == 0) 1 else -1;
            acc_lb += sgn * h_lb[pat];
            acc_tb += sgn * h_tb[pat];
        }
        const a_lb = @abs(@as(f64, @floatFromInt(acc_lb)) / n);
        const a_tb = @abs(@as(f64, @floatFromInt(acc_tb)) / n);
        out.evals += 2;
        if (a_lb > best) {
            best = a_lb;
            best_m = mask;
            best_ch = 0;
        }
        if (a_tb > best) {
            best = a_tb;
            best_m = mask;
            best_ch = 1;
        }
    }
    out.stat = best;
    if (best_ch == 0) out.ev_lb = best_m else out.ev_tb = best_m;
    const val = @abs(if (best_ch == 0)
        agreeIdx(bits, ybit, idxV, best_m, 0, 0)
    else
        agreeIdx(bits, ybit, idxV, 0, best_m, 0));
    out.evals += 1;
    out.val_stat = val;
    out.accepted = best >= 0.5 and val >= 0.90;
    switch (meta.kind) {
        .xor_lb => {
            out.true_stat = agreeIdx(bits, ybit, idxS, meta.lb, 0, 0);
            out.hit = out.accepted and best_ch == 0 and best_m == meta.lb;
        },
        .tb_parity => {
            out.true_stat = agreeIdx(bits, ybit, idxS, 0, meta.tb, 0);
            out.hit = out.accepted and best_ch == 1 and best_m == meta.tb;
        },
        else => {},
    }
    out.false_accept = out.accepted and !out.hit;
    return out;
}

// ── LG: GF(2) joint solve over [28 cmp | 8 lb | 8 tb | 1] (45 columns) ─────

const NCOL: usize = 45;

fn rowVec(b: BitRow, y: u8) u64 {
    var r: u64 = @as(u64, b.cmp); // bits 0..27
    r |= @as(u64, b.lb) << 28; // bits 28..35
    r |= @as(u64, b.tb) << 36; // bits 36..43
    r |= @as(u64, 1) << 44; // intercept column
    r |= @as(u64, y) << 45; // rhs
    return r;
}

fn lensLG(bits: []const BitRow, ybit: []const u8, idxS: []const u32, idxV: []const u32, meta: TruthMeta) LensOut {
    var out = LensOut{};
    var piv = [_]u64{0} ** NCOL;
    var contradictions: usize = 0;
    for (idxS) |t| {
        var r = rowVec(bits[t], ybit[t]);
        var placed = false;
        var c: usize = 0;
        while (c < NCOL) : (c += 1) {
            if ((r >> @intCast(c)) & 1 == 0) continue;
            if (piv[c] != 0) {
                r ^= piv[c];
                continue;
            }
            piv[c] = r;
            placed = true;
            break;
        }
        if (!placed and (r >> 45) & 1 == 1) contradictions += 1;
    }
    out.evals += 1;
    // reduce to RREF so free-vars=0 back-substitution is a one-liner
    var cc: usize = NCOL;
    while (cc > 0) {
        cc -= 1;
        if (piv[cc] == 0) continue;
        for (0..cc) |c2| {
            if (piv[c2] != 0 and (piv[c2] >> @intCast(cc)) & 1 == 1) piv[c2] ^= piv[cc];
        }
    }
    var sol: u64 = 0;
    var rank: usize = 0;
    for (0..NCOL) |c3| {
        if (piv[c3] != 0) {
            rank += 1;
            if ((piv[c3] >> 45) & 1 == 1) sol |= @as(u64, 1) << @intCast(c3);
        }
    }
    const cmpm: u32 = @intCast(sol & ALL28);
    const lbm: u8 = @intCast((sol >> 28) & 0xFF);
    const tbm: u8 = @intCast((sol >> 36) & 0xFF);
    const k0: u8 = @intCast((sol >> 44) & 1);
    var ok: usize = 0;
    for (idxV) |t| {
        const b = bits[t];
        const p: u32 = (@as(u32, @popCount(b.cmp & cmpm)) + @as(u32, @popCount(b.lb & lbm)) + @as(u32, @popCount(b.tb & tbm)) + k0) & 1;
        if (p == ybit[t]) ok += 1;
    }
    const val_acc = @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(idxV.len));
    out.consistent = contradictions == 0;
    out.rank = rank;
    out.val_stat = val_acc;
    out.stat = 1.0 - @as(f64, @floatFromInt(contradictions)) / @as(f64, @floatFromInt(idxS.len));
    out.accepted = out.consistent and val_acc >= 0.99;
    out.ev_cmp = cmpm;
    out.ev_lb = lbm;
    out.ev_tb = tbm;
    out.ev_k0 = k0;
    const exact = meta.kind != .none and cmpm == meta.cmp and lbm == meta.lb and tbm == meta.tb and k0 == 0;
    out.hit = out.accepted and exact;
    if (out.accepted and !exact) {
        if (meta.kind != .none) out.alias_accept = true else out.false_accept = true;
    }
    out.true_stat = 1.0; // derived: noiseless linear system => exact when in-span
    return out;
}

// ── C09 order-statistic correlation probes ──────────────────────────────────

const C09Probes = struct {
    max_single: f64, // best |agree| over the 28 single comparison bits
    max_subset: f64, // best |agree| over 200 random cmp-subset parities
    gibbs_endpoint: f64, // best held-out endpoint of a cmp-space Gibbs climb
    gibbs_mask: u32,
    gibbs_hit: bool,
    evals: usize,
};

fn probeC09(bits: []const BitRow, ybit: []const u8, idxS: []const u32, idxV: []const u32, rand: std.Random) C09Probes {
    var evals: usize = 0;
    var max_single: f64 = 0;
    var best_bits = [_]SeedCand{.{}} ** 4; // reuse SeedCand.m as low bit idx
    var nbest: usize = 0;
    for (0..NPAIR) |p| {
        const m = @as(u32, 1) << @intCast(p);
        const a = @abs(agreeIdx(bits, ybit, idxS, 0, 0, m));
        evals += 1;
        if (a > max_single) max_single = a;
        pushSeed(best_bits[0..], &nbest, .{ .m = @intCast(p), .u = 0, .score = a });
    }
    var max_subset: f64 = 0;
    for (0..200) |_| {
        const m = rand.int(u32) & ALL28;
        if (m == 0) continue;
        const a = @abs(agreeIdx(bits, ybit, idxS, 0, 0, m));
        evals += 1;
        if (a > max_subset) max_subset = a;
    }
    // Gibbs climb in comparison-bit space (single-bit toggles), endpoint on val
    var best_end: f64 = -1;
    var best_mask: u32 = 0;
    for (best_bits[0..nbest]) |sd| {
        var m = @as(u32, 1) << @intCast(sd.m);
        var cur = @abs(agreeIdx(bits, ybit, idxS, 0, 0, m));
        evals += 1;
        var round: usize = 0;
        while (round < 40) : (round += 1) {
            var bm = m;
            var bs = cur;
            for (0..NPAIR) |p| {
                const m2 = m ^ (@as(u32, 1) << @intCast(p));
                if (m2 == 0) continue;
                const a = @abs(agreeIdx(bits, ybit, idxS, 0, 0, m2));
                evals += 1;
                if (a > bs) {
                    bs = a;
                    bm = m2;
                }
            }
            if (bs > cur + 1e-9) {
                m = bm;
                cur = bs;
            } else break;
        }
        const v = @abs(agreeIdx(bits, ybit, idxV, 0, 0, m));
        evals += 1;
        if (v > best_end) {
            best_end = v;
            best_mask = m;
        }
    }
    return .{
        .max_single = max_single,
        .max_subset = max_subset,
        .gibbs_endpoint = best_end,
        .gibbs_mask = best_mask,
        .gibbs_hit = best_end >= GIBBS_ACCEPT and best_mask == ALL28,
        .evals = evals,
    };
}

// ════════════════════════════════════════════════════════════════════════════
// NEW: aimed proposer v2 (LG primary, LW then Gibbs fallback)
// ════════════════════════════════════════════════════════════════════════════

const V2Route = enum { none, ladder, gf2, wht, gibbs };

const V2Result = struct {
    route: V2Route = .none,
    sol_lb: u8 = 0,
    sol_tb: u8 = 0,
    sol_cmp: u32 = 0,
    sol_k0: u8 = 0,
    exact_truth: bool = false,
    consistent: bool = false,
    rank: usize = 0,
    val_stat: f64 = 0,
    cov_before: f64 = 0,
    cov_after: f64 = 0,
    r2: f64 = 0,
    certified: bool = false,
    tax_novel: bool = false,
    tax_corr: f64 = 0,
    evals: usize = 0,
};

fn v2CandRaw(bits: []const BitRow, lbm: u8, tbm: u8, cmpm: u32, k0: u8, cand_raw: []f64) void {
    for (0..NSAMP) |s| {
        const b = bits[s];
        const p: u32 = (@as(u32, @popCount(b.lb & lbm)) + @as(u32, @popCount(b.tb & tbm)) + @as(u32, @popCount(b.cmp & cmpm)) + k0) & 1;
        cand_raw[s] = if (p == 0) 1.0 else -1.0;
    }
}

fn runAimedV2(
    X: [][]f64,
    grid: []const [8]u8,
    phiTgt: []f64,
    trained_lib: []const rq1.Feature,
    Y: []const f64,
    bits: []const BitRow,
    ybit: []const u8,
    idxS: []const u32,
    idxV: []const u32,
    meta: TruthMeta,
) V2Result {
    var res = V2Result{};
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(trained_lib, &lib, &nlib);
    var w_mut: [33]f64 = undefined;

    const m = ui.solveOneTarget(X, grid, &lib, &nlib, Y, phiTgt, w_mut[0..], SilentOut{}, true);
    if (m.solved) {
        res.route = .ladder;
        res.certified = true;
        res.cov_before = m.cov;
        res.cov_after = m.cov;
        return res;
    }

    // ── evidence mining, search split only ──
    const lg = lensLG(bits, ybit, idxS, idxV, meta);
    res.evals += lg.evals;
    if (lg.accepted) {
        res.route = .gf2;
        res.sol_lb = lg.ev_lb;
        res.sol_tb = lg.ev_tb;
        res.sol_cmp = lg.ev_cmp;
        res.sol_k0 = lg.ev_k0;
        res.consistent = lg.consistent;
        res.rank = lg.rank;
        res.val_stat = lg.val_stat;
    } else {
        const lw = lensLW(bits, ybit, idxS, idxV, meta);
        res.evals += lw.evals;
        if (lw.accepted) {
            res.route = .wht;
            res.sol_lb = lw.ev_lb;
            res.sol_tb = lw.ev_tb;
            res.val_stat = lw.val_stat;
        } else {
            var s1 = [_]SeedCand{.{}} ** 4;
            var n1: usize = 0;
            var s2 = [_]SeedCand{.{}} ** 10;
            var n2: usize = 0;
            const o1 = lensL1(bits, ybit, idxS, meta, s1[0..], &n1);
            const o2 = lensL2(bits, ybit, idxS, meta, s2[0..], &n2);
            res.evals += o1.evals + o2.evals;
            const o3 = lensL3(bits, ybit, idxS, idxV, s1[0..n1], s2[0..n2], meta);
            res.evals += o3.evals;
            if (o3.accepted) {
                res.route = .gibbs;
                res.sol_lb = o3.ev_lb;
                res.val_stat = o3.val_stat;
            }
        }
    }

    res.cov_before = ui.measureCoverage(X, grid, lib[0..nlib], Y, w_mut[0..]);
    res.evals += 1;
    if (res.route == .none) return res;

    var cand_raw: [NSAMP]f64 = undefined;
    v2CandRaw(bits, res.sol_lb, res.sol_tb, res.sol_cmp, res.sol_k0, cand_raw[0..]);

    var w_r2: [34]f64 = undefined;
    // buildFeat side-effect: measureCoverage left X as normalized library cols
    res.r2 = reconR2L(X, nlib, cand_raw[0..], w_r2[0..]);
    var w_aug: [34]f64 = undefined;
    res.cov_after = coverageAugmented(X, grid, lib[0..nlib], cand_raw[0..], Y, w_aug[0..]);
    res.evals += 2;
    const escape = res.cov_after >= COVER and res.cov_before < COVER;
    res.certified = escape and res.r2 < R2_MAX;

    res.exact_truth = meta.kind != .none and res.sol_cmp == meta.cmp and res.sol_lb == meta.lb and res.sol_tb == meta.tb and res.sol_k0 == 0;

    // tax proxy (export filter/report only, never a gate) — contrast features
    // from cheap corr-based evidence argmaxes (same families as v1's proxy)
    const l0 = lensL0(bits, ybit, idxS, meta);
    res.evals += l0.evals;
    var best_tb_wht: u8 = 1;
    {
        var best: f64 = -1;
        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const a = @abs(agreeIdx(bits, ybit, idxS, 0, @intCast(mm), 0));
            res.evals += 1;
            if (a > best) {
                best = a;
                best_tb_wht = @intCast(mm);
            }
        }
    }
    const tp = taxProxy(grid, lib[0..nlib], l0.ev_tb, best_tb_wht, cand_raw[0..]);
    res.tax_novel = tp.novel;
    res.tax_corr = tp.best_corr;
    return res;
}

// ════════════════════════════════════════════════════════════════════════════
// Main
// ════════════════════════════════════════════════════════════════════════════

const CSV_PATH = "/home/micah/Desktop/Sylorlabs/ghost_research/results/lenses_2026_07_10.csv";

const N_LAB_LENS: usize = 6; // L0,L1,L2,L3,LW,LG
const LENS_NAMES = [N_LAB_LENS][]const u8{ "L0_tb_argmax", "L1_single_up", "L2_pair_up", "L3_gibbs", "LW_mod2_wht", "LG_gf2" };
const N_BUCKET: usize = 5; // deg4, deg5(C11), C08, C09, controls
const BUCKET_NAMES = [N_BUCKET][]const u8{ "deg4_xor(8tgt)", "deg5_C11", "C08_tbpar", "C09_invpar", "controls(3)" };

const Agg = struct {
    attempts: usize = 0,
    hits: usize = 0,
    accepts: usize = 0,
    false_accepts: usize = 0,
    alias: usize = 0,
    sum_true: f64 = 0,
    n_true: usize = 0,
};

fn bucketOf(ti: usize) usize {
    return switch (ti) {
        0, 1, 2, 3, 4, 5, 6, 9 => 0,
        10 => 1,
        7 => 2,
        8 => 3,
        else => 4,
    };
}

fn splitmix(x0: u64) u64 {
    var x = x0 +% 0x9E3779B97F4A7C15;
    x = (x ^ (x >> 30)) *% 0xBF58476D1CE4E5B9;
    x = (x ^ (x >> 27)) *% 0x94D049BB133111EB;
    return x ^ (x >> 31);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var lab_only = false;
    var pipe_only = false;
    var nseeds: usize = SEEDS.len;
    var nres: usize = 20;
    {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();
        _ = args.skip();
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--lab-only")) lab_only = true;
            if (std.mem.eql(u8, arg, "--pipeline-only")) pipe_only = true;
            if (std.mem.startsWith(u8, arg, "--seeds=")) nseeds = try std.fmt.parseInt(usize, arg["--seeds=".len..], 10);
            if (std.mem.startsWith(u8, arg, "--resamples=")) nres = try std.fmt.parseInt(usize, arg["--resamples=".len..], 10);
        }
    }
    if (nseeds > SEEDS.len) nseeds = SEEDS.len;

    if (std.fs.path.dirname(CSV_PATH)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(CSV_PATH, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("phase,seed,lens_or_arm,target,family,deg,attempt,hit,accepted,false_accept,alias,ev_lb,ev_tb,ev_cmp,ev_k0,stat,true_stat,val_stat,consistent,rank,cov_before,cov_after,r2,tax,tax_corr,evals,note\n", .{});

    try out.print("=== TIER 8 EVIDENCE LENSES: raising the (1/3)^k aiming signal ===\n", .{});
    try out.print("lab: {d} seed(s) x 14 targets x {d} resamples | pipeline: {d} seed(s)\n\n", .{ nseeds, nres, nseeds });

    // lab targets: 11 battery + 3 out-of-family controls (LG false-accept guard)
    const controls = [_]bc.BatteryCTarget{
        .{ .name = "X01 product_bind", .composed = .product_bind, .family = "control" },
        .{ .name = "X02 max_parity", .composed = .max_parity, .family = "control" },
        .{ .name = "X03 rank2_eq1", .composed = .rank2_eq1, .family = "control" },
    };
    const NTGT = bc.BATTERY_C.len + controls.len;

    var agg: [N_LAB_LENS][N_BUCKET]Agg = .{.{Agg{}} ** N_BUCKET} ** N_LAB_LENS;
    var c09_single_max: f64 = 0;
    var c09_subset_max: f64 = 0;
    var c09_gibbs_hits: usize = 0;
    var c09_gibbs_attempts: usize = 0;
    var c09_gibbs_best_end: f64 = 0;
    var lab_evals: usize = 0;

    // pipeline totals
    var tot_rev: usize = 0;
    var tot_v1: usize = 0;
    var tot_v2: usize = 0;
    var v1_flips: usize = 0;
    var v2_flips: usize = 0;
    var v2_exact: usize = 0;
    var v2_inexact_certified: usize = 0;
    var v1_evals: usize = 0;
    var v2_evals: usize = 0;

    var timer = try std.time.Timer.start();

    for (SEEDS[0..nseeds]) |seed| {
        try out.print("──── seed 0x{X:0>16} ────\n", .{seed});
        const prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
        const ctx = prep.ctx;
        // copy the trained library immediately (see doc: defensive copy;
        // values verified via the 3/33 revision-baseline reproduction)
        var tl_store: [32]rq1.Feature = undefined;
        const ntl = prep.trained_nlib;
        @memcpy(tl_store[0..ntl], prep.trained_lib[0..ntl]);
        const trained_lib = tl_store[0..ntl];

        const bits = try alloc.alloc(BitRow, NSAMP);
        for (0..NSAMP) |s| bits[s] = bitsOf(ctx.grid[s]);

        // standard split index arrays (for pipeline v2 mining)
        const idx_std_s = try alloc.alloc(u32, NTR);
        const idx_std_v = try alloc.alloc(u32, NVA - NTR);
        for (0..NTR) |i| idx_std_s[i] = @intCast(i);
        for (NTR..NVA) |i| idx_std_v[i - NTR] = @intCast(i);

        // ════ LAB PHASE ════
        if (!pipe_only) {
            try out.print("  [lab] {d} targets x {d} resamples ...\n", .{ NTGT, nres });
            const perm = try alloc.alloc(u32, NVA);
            const ybit = try alloc.alloc(u8, NSAMP);

            for (0..NTGT) |ti| {
                const tgt = if (ti < bc.BATTERY_C.len) bc.BATTERY_C[ti] else controls[ti - bc.BATTERY_C.len];
                const meta: TruthMeta = if (ti < bc.BATTERY_C.len) metaForBattery(ti) else .{};
                for (0..NSAMP) |s| ybit[s] = if (bc.labelTarget(ctx.grid[s], tgt) > 0.5) 1 else 0;

                for (0..nres) |r| {
                    var prng = std.Random.DefaultPrng.init(splitmix(seed ^ splitmix(@as(u64, ti) << 32 | @as(u64, r))));
                    const rand = prng.random();
                    for (0..NVA) |i| perm[i] = @intCast(i);
                    rand.shuffle(u32, perm);
                    const idxS = perm[0..NTR];
                    const idxV = perm[NTR..NVA];

                    var l1_seeds = [_]SeedCand{.{}} ** 4;
                    var n1: usize = 0;
                    var l2_seeds = [_]SeedCand{.{}} ** 10;
                    var n2: usize = 0;

                    var outs: [N_LAB_LENS]LensOut = undefined;
                    outs[0] = lensL0(bits, ybit, idxS, meta);
                    outs[1] = lensL1(bits, ybit, idxS, meta, l1_seeds[0..], &n1);
                    outs[2] = lensL2(bits, ybit, idxS, meta, l2_seeds[0..], &n2);
                    outs[3] = lensL3(bits, ybit, idxS, idxV, l1_seeds[0..n1], l2_seeds[0..n2], meta);
                    outs[4] = lensLW(bits, ybit, idxS, idxV, meta);
                    outs[5] = lensLG(bits, ybit, idxS, idxV, meta);

                    const bkt = bucketOf(ti);
                    for (0..N_LAB_LENS) |li| {
                        const o = outs[li];
                        lab_evals += o.evals;
                        agg[li][bkt].attempts += 1;
                        if (o.hit) agg[li][bkt].hits += 1;
                        if (o.accepted) agg[li][bkt].accepts += 1;
                        if (o.false_accept) agg[li][bkt].false_accepts += 1;
                        if (o.alias_accept) agg[li][bkt].alias += 1;
                        if (meta.kind != .none and li <= 2) {
                            agg[li][bkt].sum_true += o.true_stat;
                            agg[li][bkt].n_true += 1;
                        }
                        try cw.print("lab,0x{X:0>16},{s},\"{s}\",{s},{d},{d},{d},{d},{d},{d},0x{X:0>2},0x{X:0>2},0x{X:0>7},{d},{d:.4},{d:.4},{d:.4},{d},{d},,,,,,{d},\n", .{
                            seed,                     LENS_NAMES[li],           tgt.name, tgt.family,
                            meta.deg,                 r,                        @intFromBool(o.hit), @intFromBool(o.accepted),
                            @intFromBool(o.false_accept), @intFromBool(o.alias_accept), o.ev_lb, o.ev_tb,
                            o.ev_cmp,                 o.ev_k0,                  o.stat,   o.true_stat,
                            o.val_stat,               @intFromBool(o.consistent), o.rank, o.evals,
                        });
                    }

                    if (ti == 8) { // C09 order-statistic correlation probes
                        const pr = probeC09(bits, ybit, idxS, idxV, rand);
                        lab_evals += pr.evals;
                        c09_single_max = @max(c09_single_max, pr.max_single);
                        c09_subset_max = @max(c09_subset_max, pr.max_subset);
                        c09_gibbs_attempts += 1;
                        if (pr.gibbs_hit) c09_gibbs_hits += 1;
                        c09_gibbs_best_end = @max(c09_gibbs_best_end, pr.gibbs_endpoint);
                        try cw.print("lab,0x{X:0>16},c09_probes,\"{s}\",{s},{d},{d},{d},{d},0,0,0x00,0x00,0x{X:0>7},0,{d:.4},{d:.4},{d:.4},0,0,,,,,,{d},\"single={d:.4};subset={d:.4};gibbs_end={d:.4}\"\n", .{
                            seed,          tgt.name,        tgt.family,       meta.deg,
                            r,             @intFromBool(pr.gibbs_hit), @intFromBool(pr.gibbs_endpoint >= GIBBS_ACCEPT),
                            pr.gibbs_mask, pr.max_single,   pr.max_subset,    pr.gibbs_endpoint,
                            pr.evals,      pr.max_single,   pr.max_subset,    pr.gibbs_endpoint,
                        });
                    }
                }
            }
            try out.print("  [lab] done ({d:.1}s elapsed)\n", .{@as(f64, @floatFromInt(timer.read())) / 1e9});
        }

        // ════ PIPELINE PHASE ════
        if (!lab_only) {
            var solved_rev: [bc.BATTERY_C.len]bool = undefined;
            var cov_rev: [bc.BATTERY_C.len]f64 = undefined;
            const nr = runLadderOnlyBattery(ctx.X, ctx.grid, ctx.phiTgt, trained_lib, .revision, &solved_rev, &cov_rev);
            tot_rev += nr;
            try out.print("  [pipeline] revision baseline: {d}/{d}\n", .{ nr, bc.BATTERY_C.len });
            for (bc.BATTERY_C, 0..) |tgt, ti| {
                try cw.print("pipeline,0x{X:0>16},revision,\"{s}\",{s},{d},0,{d},,,,,,,,{d:.4},,,,,,,,,,,\n", .{
                    seed, tgt.name, tgt.family, metaForBattery(ti).deg, @intFromBool(solved_rev[ti]), cov_rev[ti],
                });
            }

            // aimed v1 (yesterday's lens path) on revision-unsolved targets
            configureArm(.revision);
            var n_v1: usize = 0;
            for (bc.BATTERY_C, 0..) |tgt, ti| {
                if (solved_rev[ti]) continue;
                var Yb: [NSAMP]f64 = undefined;
                for (0..NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);
                var scratch: [NSAMP]f64 = undefined;
                const r = runAimedProposer(ctx.X, ctx.grid, ctx.phiTgt, trained_lib, Yb[0..], scratch[0..]);
                v1_evals += r.evals;
                if (r.certified) {
                    n_v1 += 1;
                    v1_flips += 1;
                }
                var nbuf: [160]u8 = undefined;
                const note = std.fmt.bufPrint(nbuf[0..], "mono=0x{X:0>2}@{d:.3};walsh=0x{X:0>2}@{d:.3};lens={s};grown=0x{X:0>2}@{d:.3}", .{
                    r.mono_mask, r.mono_val, r.walsh_s, r.walsh_val, @tagName(r.chosen_lens), r.grown_mask, r.grown_val,
                }) catch "";
                try cw.print("pipeline,0x{X:0>16},aimed_v1,\"{s}\",{s},{d},0,{d},,,,0x{X:0>2},,,,{d:.4},,,,,{d:.4},{d:.4},{d:.4},{s},{d:.4},{d},\"{s}\"\n", .{
                    seed,        tgt.name,     tgt.family, metaForBattery(ti).deg,
                    @intFromBool(r.certified), r.grown_mask, r.mono_val, r.cov_before,
                    r.cov_after, r.r2,         if (r.tax_proxy_novel) "novel" else "remix",
                    r.tax_proxy_best_corr,     r.evals,    note,
                });
            }
            tot_v1 += nr + n_v1;
            try out.print("  [pipeline] aimed_v1 flips: {d} (arm total {d}/{d}) ({d:.1}s)\n", .{ n_v1, nr + n_v1, bc.BATTERY_C.len, @as(f64, @floatFromInt(timer.read())) / 1e9 });

            // aimed v2 (new lenses) on the same revision-unsolved targets
            configureArm(.revision);
            var n_v2: usize = 0;
            const ybit2 = try alloc.alloc(u8, NSAMP);
            for (bc.BATTERY_C, 0..) |tgt, ti| {
                if (solved_rev[ti]) continue;
                const meta = metaForBattery(ti);
                var Yb: [NSAMP]f64 = undefined;
                for (0..NSAMP) |s| {
                    Yb[s] = bc.labelTarget(ctx.grid[s], tgt);
                    ybit2[s] = if (Yb[s] > 0.5) 1 else 0;
                }
                const r = runAimedV2(ctx.X, ctx.grid, ctx.phiTgt, trained_lib, Yb[0..], bits, ybit2, idx_std_s, idx_std_v, meta);
                v2_evals += r.evals;
                if (r.certified and r.route != .ladder) {
                    n_v2 += 1;
                    v2_flips += 1;
                    if (r.exact_truth) v2_exact += 1 else v2_inexact_certified += 1;
                    try out.print("    >> V2 FLIP {s} via {s}: lb=0x{X:0>2} tb=0x{X:0>2} cmp=0x{X:0>7} k0={d} | truth lb=0x{X:0>2} tb=0x{X:0>2} cmp=0x{X:0>7} | exact={} val={d:.4} cov {d:.3}->{d:.3} R2={d:.3}\n", .{
                        tgt.name,   @tagName(r.route), r.sol_lb, r.sol_tb, r.sol_cmp, r.sol_k0,
                        meta.lb,    meta.tb,           meta.cmp, r.exact_truth,
                        r.val_stat, r.cov_before,      r.cov_after, r.r2,
                    });
                } else if (r.route != .ladder) {
                    try out.print("    .. V2 no flip {s} (route={s} val={d:.3} cov {d:.3}->{d:.3} R2={d:.3})\n", .{
                        tgt.name, @tagName(r.route), r.val_stat, r.cov_before, r.cov_after, r.r2,
                    });
                }
                try cw.print("pipeline,0x{X:0>16},aimed_v2,\"{s}\",{s},{d},0,{d},{d},,,0x{X:0>2},0x{X:0>2},0x{X:0>7},{d},,,{d:.4},{d},{d},{d:.4},{d:.4},{d:.4},{s},{d:.4},{d},\"route={s};exact={d}\"\n", .{
                    seed,         tgt.name,    tgt.family,        meta.deg,
                    @intFromBool(r.certified and r.route != .ladder), @intFromBool(r.certified),
                    r.sol_lb,     r.sol_tb,    r.sol_cmp,         r.sol_k0,
                    r.val_stat,   @intFromBool(r.consistent),     r.rank,
                    r.cov_before, r.cov_after, r.r2,
                    if (r.tax_novel) "novel" else "remix",        r.tax_corr,
                    r.evals,      @tagName(r.route),              @intFromBool(r.exact_truth),
                });
            }
            tot_v2 += nr + n_v2;
            try out.print("  [pipeline] aimed_v2 flips: {d} (arm total {d}/{d}) ({d:.1}s)\n\n", .{ n_v2, nr + n_v2, bc.BATTERY_C.len, @as(f64, @floatFromInt(timer.read())) / 1e9 });
        }
    }

    // ════ SUMMARY ════
    const total = nseeds * bc.BATTERY_C.len;
    try out.print("════════════════ LAB SUMMARY (hit rate = evidence mask == ground truth) ════════════════\n", .{});
    if (!pipe_only) {
        try out.print("{s: <14}", .{"lens"});
        for (BUCKET_NAMES) |b| try out.print(" | {s: >16}", .{b});
        try out.print("\n", .{});
        for (0..N_LAB_LENS) |li| {
            try out.print("{s: <14}", .{LENS_NAMES[li]});
            for (0..N_BUCKET) |bi| {
                const a = agg[li][bi];
                var buf: [24]u8 = undefined;
                const cell = std.fmt.bufPrint(buf[0..], "{d}/{d} fa={d}", .{ a.hits, a.attempts, a.false_accepts }) catch "?";
                try out.print(" | {s: >16}", .{cell});
            }
            try out.print("\n", .{});
        }
        try out.print("\nmeasured mean signal at the TRUE candidate (formula check, xor deg-4 / deg-5):\n", .{});
        for (0..3) |li| {
            const a4 = agg[li][0];
            const a5 = agg[li][1];
            const m4 = if (a4.n_true > 0) a4.sum_true / @as(f64, @floatFromInt(a4.n_true)) else 0;
            const m5 = if (a5.n_true > 0) a5.sum_true / @as(f64, @floatFromInt(a5.n_true)) else 0;
            try out.print("  {s}: deg4 {d:.4} (pred {d:.4}) | deg5 {d:.4} (pred {d:.4})\n", .{
                LENS_NAMES[li],
                m4,
                std.math.pow(f64, 1.0 / 3.0, @as(f64, @floatFromInt(4 - li))),
                m5,
                std.math.pow(f64, 1.0 / 3.0, @as(f64, @floatFromInt(5 - li))),
            });
        }
        try out.print("C09 correlation probes: max|single cmp bit|={d:.4}, max|random subset|={d:.4}, gibbs-in-cmp-space hits {d}/{d} (best endpoint {d:.4})\n", .{
            c09_single_max, c09_subset_max, c09_gibbs_hits, c09_gibbs_attempts, c09_gibbs_best_end,
        });
        try out.print("lab eval cost: {d}\n", .{lab_evals});
    }
    if (!lab_only) {
        try out.print("\n════════════════ PIPELINE SUMMARY ({d} seeds x {d} targets = {d}) ════════════════\n", .{ nseeds, bc.BATTERY_C.len, total });
        try out.print("  revision baseline:            {d}/{d}\n", .{ tot_rev, total });
        try out.print("  aimed v1 (yesterday's lens):  {d}/{d}  (+{d} flips, {d} evals)\n", .{ tot_v1, total, v1_flips, v1_evals });
        try out.print("  aimed v2 (new lenses):        {d}/{d}  (+{d} flips, {d} evals)\n", .{ tot_v2, total, v2_flips, v2_evals });
        try out.print("  v2 derivation chains: {d}/{d} flips byte-exact vs ground truth ({d} certified-but-inexact)\n", .{ v2_exact, v2_flips, v2_inexact_certified });
    }
    try out.print("  CSV: {s}\n", .{CSV_PATH});
    try out.print("  wall: {d:.1}s\n", .{@as(f64, @floatFromInt(timer.read())) / 1e9});
}
