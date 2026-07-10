//! Tier 8 ASSEMBLED ENGINE — the integration test of round 2026-07-10c.
//!
//! Two rounds settled four pieces SEPARATELY:
//!   1. Framework revision (tax basis v3->v4 + reality lane on remix-rate
//!      trigger) — load-bearing, 9/9 on battery-D decisive subset
//!      (tier8_ablation.zig / tier8_ablation_d.zig).
//!   2. Aimed proposer (near-miss evidence mining -> lens scan -> greedy
//!      grow -> certify) — 3/33 -> 8/33 on battery-C ladder-only
//!      (tier8_aimed_proposer.zig).
//!   3. v5-ladder novelty VERDICT (engine-expressible basis test,
//!      test_acc(level=1) < COVER) — 51/51 true remix blocked, 6/6 genuine
//!      escapes admitted; adopted at the verdict layer, never in-loop
//!      (tier8_gate_v5.zig).
//!   4. Tax as measurement + export filter only; inner loops explore
//!      un-aimed and un-gated; aim/taxes/novelty verdicts act at selection
//!      boundaries (research_round_2026_07_10b.md synthesis #4/#6).
//!
//! THIS harness runs them TOGETHER as one engine pass and measures the
//! composite against every battery — the "does the whole stack cohere"
//! test. Integration regressions (pieces interfering) are exactly what it
//! exists to find.
//!
//! Pipeline per (seed, arm), one continuous tax state:
//!   Battery B (11 targets, full production engine ie.solveBlindTarget,
//!     shared growable library)
//!   -> Battery C (11 targets, ladder-only ui.solveOneTarget, fresh lib per
//!     target — the fully tax-gated slice)
//!   -> Battery D decisive subset {D01,D07,D11} (same slice mechanism)
//!   After every target: the T8-AG-21 revision trigger may fire a witnessed
//!     v3->v4 revision (revision-enabled arms only).
//!   After any target the ladder leaves unsolved: the AIMED PROPOSER stage
//!     (aimed-enabled arms only) — evidence mining (162-mask monomial sweep
//!     + 256-pattern Walsh sweep, read-only), 6-lens scan on the mined
//!     anchor mask, greedy grow/shrink, certify at the production bar
//!     (escape >=0.90 held-out from below + R^2<0.40). The tax gate is
//!     NEVER consulted by the aimed stage (selection-boundary principle);
//!     a correlation tax-proxy + a v5-ladder verdict are recorded for the
//!     export filter.
//!   End of pass: v5-LADDER VERDICT AUDIT over every real gate capture
//!     (eqtax.replay_captures) — recording + monitor feed + export filter,
//!     never blocking. Exported library = live-admitted AND ladder-novel.
//!
//! Arms (attribution by leave-one-out):
//!   frozen      — tax frozen v3 strict, no revision, no aimed stage.
//!   revision    — revision trigger enabled, no aimed stage
//!                 (== assembled-minus-aimed).
//!   aimed_norev — tax frozen v3 strict + aimed stage
//!                 (== assembled-minus-revision).
//!   assembled   — revision trigger + aimed stage + v5 verdict layer.
//!
//! --phase0 re-classifies ALL 11 battery-D candidates' band membership at
//! the production seed, because this run builds against the taxfix agent's
//! z-scoring fix to equivalence_tax.greedyFit (uncommitted working-tree
//! state; see doc) — the decisive band itself may have moved.
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe tier8_assembled.zig -O ReleaseFast
//! Run (each invocation well under the 15-min cap, single-threaded):
//!   ./tier8_assembled --phase0
//!   ./tier8_assembled --arm=frozen
//!   ./tier8_assembled --arm=revision
//!   ./tier8_assembled --arm=aimed_norev
//!   ./tier8_assembled --arm=assembled
//!
//! New file only — no existing file modified. Read-only reuse of the
//! tier8_ablation_d.zig arm pattern and tier8_aimed_proposer.zig's
//! composition machinery (those files export no pub helpers; the needed
//! code is reproduced here with identical hyperparameters).

const std = @import("std");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");
const bc = @import("open_invention_tier8_battery_c.zig");
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

const NSAMP: usize = ui.NSAMP;
const NTR: usize = ui.NTR;
const NVA: usize = ui.NVA;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;

const N_B = 11;
const N_C = bc.BATTERY_C.len;
/// Decisive subset per docs/research/tier8_battery_d.md: D01, D07, D11.
const D_DECISIVE_IDX = [_]usize{ 0, 6, 10 };
const N_D = D_DECISIVE_IDX.len;
const MAX_TGT: usize = N_B + N_C + N_D;

const Arm = enum { frozen, revision, aimed_norev, assembled };

fn revisionEnabled(arm: Arm) bool {
    return arm == .revision or arm == .assembled;
}
fn aimedEnabled(arm: Arm) bool {
    return arm == .aimed_norev or arm == .assembled;
}

// ── Local numeric mirrors (identical to tier8_aimed_proposer.zig) ──────────

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

// ── Aimed proposer machinery (identical to tier8_aimed_proposer.zig) ───────

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

fn taxProxy(
    grid: []const [8]u8,
    lib: []const ui.Feature,
    mono_mask: u8,
    walsh_s: u8,
    cand_raw: []const f64,
) struct { novel: bool, best_corr: f64 } {
    var best: f64 = 0;
    var buf: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| buf[s] = ui.evalFeaturePublic(.{ .monomial = mono_mask }, grid[s]);
    best = @max(best, @abs(corrTest(cand_raw, buf[0..])));
    for (0..NSAMP) |s| buf[s] = ui.evalFeaturePublic(.{ .walsh = walsh_s }, grid[s]);
    best = @max(best, @abs(corrTest(cand_raw, buf[0..])));
    for (lib) |f| {
        for (0..NSAMP) |s| buf[s] = ui.evalFeaturePublic(f, grid[s]);
        best = @max(best, @abs(corrTest(cand_raw, buf[0..])));
    }
    return .{ .novel = best <= 0.90, .best_corr = best };
}

const AimedOutcome = struct {
    attempted: bool = false,
    certified: bool = false,
    mono_mask: u8 = 0,
    mono_val: f64 = 0,
    walsh_s: u8 = 0,
    walsh_val: f64 = 0,
    lens: Lens = .th3,
    grown_mask: u8 = 0,
    grown_val: f64 = 0,
    cov_before: f64 = 0,
    cov_after: f64 = 0,
    r2: f64 = 0,
    evals: usize = 0,
    tax_proxy_novel: bool = false,
    tax_proxy_corr: f64 = 0,
    /// v5-ladder verdict on the TARGET at the final library (level-1
    /// engine-expressible basis; < COVER == ladder-novel). Computed only
    /// for certified flips (export filter input).
    test_acc_l1: f64 = -1,
    ladder_novel: bool = false,
};

/// Aimed stage on a target the ladder just left unsolved. Evidence mining is
/// read-only; the tax gate is never consulted (selection-boundary principle).
/// `lib` is the target's final (post-escalation) library.
fn runAimedStage(
    X: [][]f64,
    grid: []const [8]u8,
    lib: []const ui.Feature,
    Y: []const f64,
) AimedOutcome {
    var out: AimedOutcome = .{ .attempted = true };
    if (lib.len >= 31) return out; // augmented X column guard (never hit in practice)

    var scratch: [NSAMP]f64 = undefined;
    var evals: usize = 0;
    const mono_ev = monomialSweep(grid, Y, scratch[0..], &evals);
    const walsh_ev = walshSweep(grid, Y, scratch[0..], &evals);

    var lens_scan: [6]f64 = undefined;
    for (LENSES, 0..) |lens, li| {
        lens_scan[li] = composedSweepVal(grid, mono_ev.mask, lens, Y, scratch[0..]);
        evals += 1;
    }
    var best_li: usize = 0;
    for (1..6) |li| {
        if (lens_scan[li] > lens_scan[best_li]) best_li = li;
    }
    const chosen = LENSES[best_li];
    const grown = greedyGrow(grid, Y, scratch[0..], mono_ev.mask, chosen, &evals);

    var cand_raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| cand_raw[s] = composedVal(grid[s], grown.mask, chosen);

    var w_cov: [33]f64 = undefined;
    const cov_before = ui.measureCoverage(X, grid, lib, Y, w_cov[0..]);
    var w_r2: [34]f64 = undefined;
    const r2 = reconR2L(X, lib.len, cand_raw[0..], w_r2[0..]);
    var w_aug: [34]f64 = undefined;
    const cov_after = coverageAugmented(X, grid, lib, cand_raw[0..], Y, w_aug[0..]);
    evals += 2;

    const escape = cov_after >= COVER and cov_before < COVER;
    const certified = escape and r2 < R2_MAX;
    const tp = taxProxy(grid, lib, mono_ev.mask, walsh_ev.s, cand_raw[0..]);

    out.certified = certified;
    out.mono_mask = mono_ev.mask;
    out.mono_val = mono_ev.val;
    out.walsh_s = walsh_ev.s;
    out.walsh_val = walsh_ev.val;
    out.lens = chosen;
    out.grown_mask = grown.mask;
    out.grown_val = grown.val;
    out.cov_before = cov_before;
    out.cov_after = cov_after;
    out.r2 = r2;
    out.evals = evals;
    out.tax_proxy_novel = tp.novel;
    out.tax_proxy_corr = tp.best_corr;

    if (certified) {
        // v5-ladder verdict for the export filter: can the ENGINE-EXPRESSIBLE
        // basis (level 1) reconstruct this TARGET without the composed
        // feature? The composed candidate is not a ui.Feature, so a dummy
        // spectral feature (never generated by the static pool, and not
        // matching any promoted omega on the pi/200 grid) stands in as
        // `cand` purely for the skip-list; the fit is over target labels
        // from library + static pool, exactly witnessRemixAtLevel(level=1).
        const dummy: ui.Feature = .{ .spectral_count = 0.1234567 };
        out.test_acc_l1 = eqtax.witnessRemixAtLevel(grid, lib, dummy, Y, 1).test_acc;
        out.ladder_novel = out.test_acc_l1 < eqtax.COVER;
    }
    return out;
}

// ── Revision trigger (identical semantics to tier8_ablation.zig) ───────────

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

fn maybeRevise(revision_fired_at: *?usize, revision_replay_idx: *usize, global_idx: usize, out: anytype) !void {
    if (revision_fired_at.* != null) return;
    if (eqtax.stats.checked < MIN_CHECKS) return;
    if (eqtax.stats.novelRate() >= ALERT_THRESHOLD) return;
    const proposal = cr.proposeFromTaxonomy(taxonomyFromLog(), eqtax.basis_level);
    const vote = fv.voteOnProposal(proposal, .{
        .witness_id = "tier8-assembled-2026-07-10",
        .approved = true,
        .timestamp_seed = 0xA55E20260710,
    }, false);
    if (!vote.recorded) return;
    eqtax.basis_level = REVISED_BASIS;
    eqtax.reality_lane_enabled = true;
    revision_fired_at.* = global_idx;
    revision_replay_idx.* = eqtax.replay_n;
    try out.print("    [REVISION after target {d}: {s} v{d}->v{d}, rate={d:.1}% over {d} checks]\n", .{
        global_idx,
        proposal.id,
        proposal.tax_basis_from,
        REVISED_BASIS,
        eqtax.stats.novelRate() * 100.0,
        eqtax.stats.checked,
    });
}

// ── Row / summary bookkeeping ───────────────────────────────────────────────

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
    ladder_solved: bool,
    ladder_cov: f64,
    ladder_label: []const u8,
    checked_d: usize,
    novel_d: usize,
    blocked_d: usize,
    nlib: usize,
    basis: u32,
    aimed: AimedOutcome = .{},
    final_solved: bool,
};

const SeedRun = struct {
    rows: [MAX_TGT]Row = undefined,
    n: usize = 0,
    revision_fired_at: ?usize = null,
    revision_replay_idx: usize = std.math.maxInt(usize),
    b_solved: usize = 0,
    c_ladder: usize = 0,
    c_final: usize = 0,
    d_ladder: usize = 0,
    d_final: usize = 0,
    b_final: usize = 0,
    aimed_attempts: usize = 0,
    aimed_flips: usize = 0,
    aimed_evals: usize = 0,
    checked: usize = 0,
    novel: usize = 0,
    blocked: usize = 0,
    evals_b: usize = 0,
    ms: i64 = 0,
    // v5 verdict layer counters
    v5_pre_n: usize = 0,
    v5_pre_novel: usize = 0,
    v5_post_n: usize = 0,
    v5_post_novel: usize = 0,
    v5_survivor_n: usize = 0,
    v5_export_n: usize = 0,
};

fn featDesc(buf: []u8, f: ui.Feature) []const u8 {
    return switch (f) {
        .monomial => |m| std.fmt.bufPrint(buf, "monomial(0x{X:0>2})", .{m}) catch "monomial",
        .pair_relation => |ij| std.fmt.bufPrint(buf, "pair({d},{d})", .{ ij.i, ij.j }) catch "pair",
        .spectral_count => |om| std.fmt.bufPrint(buf, "spectral(w={d:.4})", .{om}) catch "spectral",
        .walsh => |S| std.fmt.bufPrint(buf, "walsh(S=0x{X:0>2})", .{S}) catch "walsh",
        .clifford_g2 => "clifford_g2",
        .world_sum_mod => |p| std.fmt.bufPrint(buf, "sum%{d}", .{p}) catch "sum_mod",
        .world_sign_mod => |p| std.fmt.bufPrint(buf, "sign%{d}", .{p}) catch "sign_mod",
    };
}

// ── One (seed, arm) pass ────────────────────────────────────────────────────

fn runSeedArm(
    alloc: std.mem.Allocator,
    seed: u64,
    arm: Arm,
    out: anytype,
    vw: anytype, // v5-audit CSV writer
) !SeedRun {
    var run: SeedRun = .{};
    const t0 = std.time.milliTimestamp();

    eqtax.strict_enabled = true;
    eqtax.basis_level = INITIAL_BASIS;
    eqtax.reality_lane_enabled = false;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    const prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
    var ctx = prep.ctx;

    var global_idx: usize = 0;

    // ── Battery B: full production engine, shared growable library ──
    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(prep.trained_lib, &lib, &nlib);
    var budget = ie.EvalCounter{};

    for (ctx.battery) |tgt| {
        const Yb = try alloc.alloc(f64, rq1.NSAMP);
        defer alloc.free(Yb);
        for (0..rq1.NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);

        const c0 = eqtax.stats.checked;
        const n0 = eqtax.stats.novel_allowed;
        const r0 = eqtax.stats.remix_blocked;
        const res = try ie.solveBlindTarget(ctx.X, ctx.grid, &lib, &nlib, Yb, ctx.phiTgt, ctx.w[0..], tgt, ctx.bank, &ctx.S_store, ctx.pf, ctx.feat, &budget, SilentOut{}, true);

        var aimed: AimedOutcome = .{};
        if (!res.solved and aimedEnabled(arm)) {
            aimed = runAimedStage(ctx.X, ctx.grid, lib[0..nlib], Yb);
            run.aimed_attempts += 1;
            run.aimed_evals += aimed.evals;
            if (aimed.certified) run.aimed_flips += 1;
        }
        const final_solved = res.solved or aimed.certified;
        if (res.solved) run.b_solved += 1;
        if (final_solved) run.b_final += 1;

        run.rows[run.n] = .{
            .battery = "B",
            .idx = global_idx,
            .name = tgt.name,
            .ladder_solved = res.solved,
            .ladder_cov = res.cov,
            .ladder_label = safeLabel(res.label),
            .checked_d = eqtax.stats.checked - c0,
            .novel_d = eqtax.stats.novel_allowed - n0,
            .blocked_d = eqtax.stats.remix_blocked - r0,
            .nlib = nlib,
            .basis = eqtax.basis_level,
            .aimed = aimed,
            .final_solved = final_solved,
        };
        run.n += 1;
        if (revisionEnabled(arm)) try maybeRevise(&run.revision_fired_at, &run.revision_replay_idx, global_idx, out);
        global_idx += 1;
    }
    run.evals_b = budget.total();

    // ── Battery C then battery-D decisive: ladder-only slice, fresh lib ──
    const slices = [_][]const u8{ "C", "D" };
    for (slices) |slice| {
        const n_slice: usize = if (std.mem.eql(u8, slice, "C")) N_C else N_D;
        for (0..n_slice) |ti| {
            const Yb = try alloc.alloc(f64, rq1.NSAMP);
            defer alloc.free(Yb);
            var tname: []const u8 = undefined;
            if (std.mem.eql(u8, slice, "C")) {
                const tgt = bc.BATTERY_C[ti];
                tname = tgt.name;
                for (0..rq1.NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);
            } else {
                const tgt = bd.BATTERY_D[D_DECISIVE_IDX[ti]];
                tname = tgt.name;
                for (0..rq1.NSAMP) |s| Yb[s] = bd.labelTarget(ctx.grid[s], tgt);
            }

            var clib: [32]ui.Feature = undefined;
            var cnlib: usize = 0;
            ie.seedUiFromRq1(prep.trained_lib, &clib, &cnlib);
            var w_mut: [33]f64 = undefined;
            @memcpy(w_mut[0..], ctx.w[0..]);

            const c0 = eqtax.stats.checked;
            const n0 = eqtax.stats.novel_allowed;
            const r0 = eqtax.stats.remix_blocked;
            const m = ui.solveOneTarget(ctx.X, ctx.grid, &clib, &cnlib, Yb, ctx.phiTgt, w_mut[0..], SilentOut{}, true);

            var aimed: AimedOutcome = .{};
            if (!m.solved and aimedEnabled(arm)) {
                aimed = runAimedStage(ctx.X, ctx.grid, clib[0..cnlib], Yb);
                run.aimed_attempts += 1;
                run.aimed_evals += aimed.evals;
                if (aimed.certified) run.aimed_flips += 1;
            }
            const final_solved = m.solved or aimed.certified;
            if (std.mem.eql(u8, slice, "C")) {
                if (m.solved) run.c_ladder += 1;
                if (final_solved) run.c_final += 1;
            } else {
                if (m.solved) run.d_ladder += 1;
                if (final_solved) run.d_final += 1;
            }

            run.rows[run.n] = .{
                .battery = slice,
                .idx = global_idx,
                .name = tname,
                .ladder_solved = m.solved,
                .ladder_cov = m.cov,
                .ladder_label = @tagName(m.source),
                .checked_d = eqtax.stats.checked - c0,
                .novel_d = eqtax.stats.novel_allowed - n0,
                .blocked_d = eqtax.stats.remix_blocked - r0,
                .nlib = cnlib,
                .basis = eqtax.basis_level,
                .aimed = aimed,
                .final_solved = final_solved,
            };
            run.n += 1;
            if (revisionEnabled(arm)) try maybeRevise(&run.revision_fired_at, &run.revision_replay_idx, global_idx, out);
            global_idx += 1;
        }
    }

    run.checked = eqtax.stats.checked;
    run.novel = eqtax.stats.novel_allowed;
    run.blocked = eqtax.stats.remix_blocked;

    // ── v5-LADDER VERDICT AUDIT (recording/monitor/export — never blocking) ──
    // Runs after the pass so the live trajectory is untouched. Every capture
    // is a certified candidate that reached the real gate.
    var desc_buf: [64]u8 = undefined;
    for (0..eqtax.replay_n) |i| {
        const cap = eqtax.replay_captures[i];
        const post_rev = i >= run.revision_replay_idx;
        // Live survivor: post-revision v4 lane admits every certified
        // candidate; pre-revision v3-strict admits iff raw verdict novel.
        const survivor = if (post_rev) true else cap.verdict == .novel;
        const ta1 = eqtax.witnessRemixAtLevel(ctx.grid, cap.lib[0..cap.nlib], cap.cand, eqtax.replay_pool[i][0..NSAMP], 1).test_acc;
        const ladder_novel = ta1 < eqtax.COVER;
        if (post_rev) {
            run.v5_post_n += 1;
            if (ladder_novel) run.v5_post_novel += 1;
        } else {
            run.v5_pre_n += 1;
            if (ladder_novel) run.v5_pre_novel += 1;
        }
        if (survivor) {
            run.v5_survivor_n += 1;
            if (ladder_novel) run.v5_export_n += 1;
        }
        try vw.print("{s},0x{X:0>16},{d},{s},{s},{d},{d},{d:.4},{d}\n", .{
            @tagName(arm),                 seed,
            i,                             featDesc(&desc_buf, cap.cand),
            @tagName(cap.verdict),         @intFromBool(survivor),
            @intFromBool(post_rev),        ta1,
            @intFromBool(ladder_novel),
        });
    }

    run.ms = std.time.milliTimestamp() - t0;
    return run;
}

// ── Phase 0: battery-D band re-classification under the taxfix tax ─────────

fn classifyOne(
    X: [][]f64,
    grid: []const [8]u8,
    trained_lib: []const rq1.Feature,
    phiTgt: []f64,
    tgt: bd.BatteryDTarget,
    Yb: []f64,
) struct { off_solved: bool, off_cov: f64, off_src: []const u8, off_blocked: usize, on_solved: bool, on_cov: f64, on_src: []const u8, base_rate: f64, class: []const u8 } {
    for (0..rq1.NSAMP) |s| Yb[s] = bd.labelTarget(grid[s], tgt);

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
        .off_src = @tagName(off.source),
        .off_blocked = off_blocked,
        .on_solved = on.solved,
        .on_cov = on.cov,
        .on_src = @tagName(on.source),
        .base_rate = bd.baseRate(grid, tgt),
        .class = class,
    };
}

fn runPhase0(alloc: std.mem.Allocator, out: anytype) !void {
    try out.print("---- PHASE 0: battery-D band re-classification under CURRENT (taxfix) equivalence_tax ----\n", .{});
    try out.print("     (seed 0x{X:0>16}; prior classification in tier8_battery_d.md was pre-fix)\n", .{ie.GRID_SEED});

    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/assembled_phase0_2026_07_10.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("seed,target,base_rate,off_solved,off_cov,off_src,off_blocked,on_solved,on_cov,on_src,class\n", .{});

    const prep = try ie.prepareBlindBatterySeed(alloc, ie.GRID_SEED, SilentOut{});
    const ctx = prep.ctx;
    const Yb = try alloc.alloc(f64, rq1.NSAMP);

    for (bd.BATTERY_D) |tgt| {
        const r = classifyOne(ctx.X, ctx.grid, prep.trained_lib, ctx.phiTgt, tgt, Yb);
        try out.print("  {s:<24} base_rate={d:.3} | OFF {s:<6} cov={d:.3} src={s:<6} blocked={d} | ON {s:<6} cov={d:.3} src={s:<6} => {s}\n", .{
            tgt.name,       r.base_rate,
            if (r.off_solved) "SOLVE" else "stuck", r.off_cov, r.off_src, r.off_blocked,
            if (r.on_solved) "SOLVE" else "stuck",  r.on_cov,  r.on_src,
            r.class,
        });
        try cw.print("0x{X:0>16},\"{s}\",{d:.4},{d},{d:.4},{s},{d},{d},{d:.4},{s},{s}\n", .{
            ie.GRID_SEED, tgt.name, r.base_rate, @intFromBool(r.off_solved), r.off_cov, r.off_src, r.off_blocked, @intFromBool(r.on_solved), r.on_cov, r.on_src, r.class,
        });
    }
    try out.print("  CSV: {s}\n", .{csv_path});
}

// ── Main ────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var phase0 = false;
    var arm_opt: ?Arm = null;
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--phase0")) {
            phase0 = true;
        } else if (std.mem.startsWith(u8, arg, "--arm=")) {
            const name = arg["--arm=".len..];
            arm_opt = std.meta.stringToEnum(Arm, name) orelse {
                try out.print("unknown arm '{s}' (frozen|revision|aimed_norev|assembled)\n", .{name});
                return;
            };
        }
    }

    if (phase0) {
        try runPhase0(alloc, out);
        return;
    }
    const arm = arm_opt orelse {
        try out.print("usage: tier8_assembled --phase0 | --arm=frozen|revision|aimed_norev|assembled\n", .{});
        return;
    };

    try out.print("=== TIER 8 ASSEMBLED ENGINE — arm: {s} ===\n", .{@tagName(arm)});
    try out.print("revision trigger: {s} | aimed stage: {s} | v5-ladder verdict: recording (all arms)\n\n", .{
        if (revisionEnabled(arm)) "ON" else "off (frozen v3)",
        if (aimedEnabled(arm)) "ON" else "off",
    });

    var buf: [128]u8 = undefined;
    const csv_path = try std.fmt.bufPrint(&buf, "/home/micah/Desktop/Sylorlabs/ghost_research/results/assembled_arm_{s}_2026_07_10.csv", .{@tagName(arm)});
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("arm,seed,battery,idx,target,ladder_solved,ladder_cov,ladder_label,checked_delta,novel_delta,blocked_delta,nlib,basis_at_target,rev_flag,aimed_attempted,aimed_certified,aimed_lens,mono_mask,grown_mask,mono_val,walsh_val,grown_val,aimed_cov_before,aimed_cov_after,aimed_r2,aimed_evals,tax_proxy,tax_proxy_corr,aimed_test_acc_l1,aimed_ladder_novel,final_solved\n", .{});

    var vbuf: [128]u8 = undefined;
    const v5_path = try std.fmt.bufPrint(&vbuf, "/home/micah/Desktop/Sylorlabs/ghost_research/results/assembled_v5_{s}_2026_07_10.csv", .{@tagName(arm)});
    const vf = try std.fs.cwd().createFile(v5_path, .{ .truncate = true });
    defer vf.close();
    const vw = vf.writer();
    try vw.print("arm,seed,cap_idx,feature,raw_verdict,survivor_live,post_revision,test_acc_l1,ladder_novel\n", .{});

    var tot = SeedRun{};
    var lib_desc_buf: [64]u8 = undefined;
    _ = &lib_desc_buf;

    for (SEEDS) |seed| {
        try out.print("──── seed 0x{X:0>16} ────\n", .{seed});
        const r = try runSeedArm(alloc, seed, arm, out, vw);
        try out.print("  B {d}/{d} (final {d})  C-ladder {d}/{d} (final {d})  D-decisive {d}/{d} (final {d})\n", .{
            r.b_solved, N_B, r.b_final, r.c_ladder, N_C, r.c_final, r.d_ladder, N_D, r.d_final,
        });
        try out.print("  tax: checked={d} novel={d} blocked={d}  evalsB={d}  revision@{?d}  {d}ms\n", .{
            r.checked, r.novel, r.blocked, r.evals_b, r.revision_fired_at, r.ms,
        });
        try out.print("  aimed: attempts={d} flips={d} evals={d}\n", .{ r.aimed_attempts, r.aimed_flips, r.aimed_evals });
        try out.print("  v5-ladder verdict: pre-rev novel {d}/{d}  post-rev novel {d}/{d}  survivors={d} exported(ladder-novel)={d}\n", .{
            r.v5_pre_novel, r.v5_pre_n, r.v5_post_novel, r.v5_post_n, r.v5_survivor_n, r.v5_export_n,
        });
        for (r.rows[0..r.n]) |row| {
            if (row.aimed.certified) {
                try out.print("    >> AIMED FLIP: {s}[{s}] mask=0x{X:0>2} lens={s} cov {d:.3}->{d:.3} R2={d:.3} tax_proxy={s} test_acc_l1={d:.3} ladder_novel={d}\n", .{
                    row.name, row.battery, row.aimed.grown_mask, @tagName(row.aimed.lens), row.aimed.cov_before, row.aimed.cov_after, row.aimed.r2, if (row.aimed.tax_proxy_novel) "novel" else "remix", row.aimed.test_acc_l1, @intFromBool(row.aimed.ladder_novel),
                });
            }
        }
        try out.print("\n", .{});

        for (r.rows[0..r.n]) |row| {
            const a = row.aimed;
            try cw.print("{s},0x{X:0>16},{s},{d},\"{s}\",{d},{d:.4},{s},{d},{d},{d},{d},{d},{s},{d},{d},{s},0x{X:0>2},0x{X:0>2},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d},{s},{d:.4},{d:.4},{d},{d}\n", .{
                @tagName(arm),
                seed,
                row.battery,
                row.idx,
                row.name,
                @intFromBool(row.ladder_solved),
                row.ladder_cov,
                row.ladder_label,
                row.checked_d,
                row.novel_d,
                row.blocked_d,
                row.nlib,
                row.basis,
                if (revisionEnabled(arm))
                    (if (r.revision_fired_at) |fi|
                        (if (fi <= row.idx) "post" else "pre")
                    else
                        "never")
                else
                    "frozen",
                @intFromBool(a.attempted),
                @intFromBool(a.certified),
                if (a.attempted) @tagName(a.lens) else "",
                a.mono_mask,
                a.grown_mask,
                a.mono_val,
                a.walsh_val,
                a.grown_val,
                a.cov_before,
                a.cov_after,
                a.r2,
                a.evals,
                if (a.attempted) (if (a.tax_proxy_novel) "novel" else "remix") else "",
                a.tax_proxy_corr,
                a.test_acc_l1,
                @intFromBool(a.ladder_novel),
                @intFromBool(row.final_solved),
            });
        }

        tot.b_solved += r.b_solved;
        tot.b_final += r.b_final;
        tot.c_ladder += r.c_ladder;
        tot.c_final += r.c_final;
        tot.d_ladder += r.d_ladder;
        tot.d_final += r.d_final;
        tot.aimed_attempts += r.aimed_attempts;
        tot.aimed_flips += r.aimed_flips;
        tot.aimed_evals += r.aimed_evals;
        tot.checked += r.checked;
        tot.novel += r.novel;
        tot.blocked += r.blocked;
        tot.evals_b += r.evals_b;
        tot.ms += r.ms;
        tot.v5_pre_n += r.v5_pre_n;
        tot.v5_pre_novel += r.v5_pre_novel;
        tot.v5_post_n += r.v5_post_n;
        tot.v5_post_novel += r.v5_post_novel;
        tot.v5_survivor_n += r.v5_survivor_n;
        tot.v5_export_n += r.v5_export_n;
    }

    const ns = SEEDS.len;
    try out.print("════════════════ ARM SUMMARY: {s} ({d} seeds) ════════════════\n", .{ @tagName(arm), ns });
    try out.print("  B        ladder {d}/{d}   final {d}/{d}\n", .{ tot.b_solved, ns * N_B, tot.b_final, ns * N_B });
    try out.print("  C-ladder ladder {d}/{d}   final {d}/{d}\n", .{ tot.c_ladder, ns * N_C, tot.c_final, ns * N_C });
    try out.print("  D-decis  ladder {d}/{d}    final {d}/{d}\n", .{ tot.d_ladder, ns * N_D, tot.d_final, ns * N_D });
    try out.print("  tax: checked={d} novel={d} blocked={d}  evalsB={d}  wall={d}ms\n", .{ tot.checked, tot.novel, tot.blocked, tot.evals_b, tot.ms });
    try out.print("  aimed: attempts={d} flips={d} evals={d}\n", .{ tot.aimed_attempts, tot.aimed_flips, tot.aimed_evals });
    try out.print("  v5-ladder verdict layer: pre-rev novel {d}/{d}  post-rev novel {d}/{d}  survivors={d}  export(ladder-novel)={d}\n", .{
        tot.v5_pre_novel, tot.v5_pre_n, tot.v5_post_novel, tot.v5_post_n, tot.v5_survivor_n, tot.v5_export_n,
    });
    try out.print("  CSV: {s}\n  v5 CSV: {s}\n", .{ csv_path, v5_path });
}
