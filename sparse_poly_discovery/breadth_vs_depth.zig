//! BREADTH vs DEPTH — does splitting a fixed total eval budget across many
//! DIVERSE parallel proposers reach targets that ONE deep proposer spending
//! the whole budget cannot, at EQUAL TOTAL BUDGET?
//!
//! Motivating question (Micah's, made falsifiable): H50
//! (docs/research/scaling_laws_h50.md) proved MORE DEPTH on one closure buys
//! nothing past 372 evals for the standard blind battery. This experiment
//! asks whether BREADTH of diverse generators is different: does pooling N
//! independent, differently-configured proposers (each spending 1/N of the
//! SAME total budget) reach targets a single exhaustive proposer's closure
//! cannot?
//!
//! Battery (16 targets, one shared eval-budget cap per proposer run):
//!   - 11 standard blind-battery-B targets (rq1.generateBatteryB via
//!     ie.prepareBlindBatterySeed) -- the H50 in-closure battery.
//!   - 5 "reach-gap" targets taken directly from Battery C
//!     (open_invention_tier8_battery_c.zig, read-only import, NOT modified):
//!       C02, C04, C05, C06 -- XOR-family targets OUTSIDE the base ladder's
//!         closure but reachable via the tier8_aimed_proposer.zig-style
//!         evidence-mined lens-composition mechanism (round b: 5/10 flips).
//!       C09 -- inversion-count parity, PROVEN family-level unreachable by
//!         every ladder family (docs/research/tier8_reach_gap.md's Bayes-
//!         ceiling proof; needs a wholly new comparison-aggregate primitive
//!         this file deliberately does NOT implement). This is the negative
//!         control: no amount of search-diversity over the EXISTING closure
//!         can manufacture a missing primitive family. If either arm solves
//!         it, that is a five-alarm finding demanding scrutiny.
//!
//! DEPTH arm: one proposer, canonical/production configuration (full lens
//! set, full exhaustive mono/Walsh sweep, production stage order, standard
//! target order), spends the WHOLE budget B. This reproduces the H50
//! plateau (Battery-B part) plus the tier8_aimed_proposer.zig mechanism
//! (reach-gap part) -- i.e. it IS the best single deep tool this research
//! arc has built, at full strength.
//!
//! BREADTH(N) arm, N in {4,8,16,32}: N proposers, each capped at B/N, run
//! SEQUENTIALLY (round-robin within one process -- no OS threads beyond the
//! single main thread, honoring the <=2-thread constraint). Each proposer is
//! made DIVERSE by construction along four independent axes (documented
//! per-proposer in the CSV):
//!   1. TARGET ORDER -- a proposer-specific random permutation of the 11
//!      Battery-B targets, a random permutation of the 5 reach-gap targets,
//!      and a coin-flip for which block goes first. Battery B's B11
//!      (inversion parity) alone consumes ~87% of the ladder's total spend
//!      (H50), so under a tight per-proposer budget, ORDER decides which
//!      targets get attempted before the cap bites -- the dominant lever.
//!   2. LENS SUBSET -- which of the 6 per-cell lenses {th1..th5, mod2} the
//!      composed-feature stage searches over (8 named subsets, cycled by
//!      proposer index; see LENS_SUBSETS below). A genuine "family subset"
//!      axis: mod2 is the natural XOR-detecting lens, th3 matches the base
//!      ladder's own existing split.
//!   3. RANDOM MASK/WALSH SUBSAMPLING -- when a proposer's remaining budget
//!      cannot afford the full 162-mask monomial sweep or 256-pattern Walsh
//!      sweep, it examines a RANDOM SUBSET sized to fit, seeded per-proposer
//!      (a genuine "different random-family seeds" axis, and a hard
//!      necessity at N=32 where per-proposer budget is a small fraction of
//!      one exhaustive sweep).
//!   4. MUTATION OPERATOR -- the greedy mask-growth step uses either
//!      single-bit-flip (flip1, the tier8_aimed_proposer.zig original) or
//!      adjacent-pair-flip (flip2) neighborhoods, alternated by proposer.
//!   Plus a minor 5th axis, escalation order (mod-stage before or after
//!   pair/Walsh for Battery B's 3 mod-eligible targets) -- documented but
//!   expected to be a weak lever since both stages are exhaustive.
//!
//! Union + dedup: a target counts as solved for the BREADTH(N) arm if ANY of
//! the N proposers certified it. Per-target solver counts and the identity
//! of the first solver are logged so a claimed union win can be checked for
//! "one proposer did all the work" (a real risk this file checks for
//! explicitly, per the task's honesty requirement).
//!
//! Equal-budget discipline: DEPTH gets cap B. BREADTH(N) proposers each get
//! cap B/N (integer division); the CSV reports both the CAP (B, upper bound)
//! and the ACTUAL evals consumed (sum over proposers for breadth), since a
//! proposer can plateau under its cap exactly like H50's Battery-B arm did.
//!
//! No existing file is modified. Reused read-only, unchanged:
//!   invention_engine.zig (ie)      -- prepareBlindBatterySeed, seedUiFromRq1
//!   open_invention_rq1.zig (rq1)   -- BatteryTarget/labelBattery/EvalCounter/
//!                                     needsMod/tryModEscalation/
//!                                     tryPairWalshEscalation
//!   unified_invention.zig (ui)     -- Feature/measureCoverage/solveOneTarget/
//!                                     evalFeaturePublic
//!   equivalence_tax.zig (eqtax)    -- strict_enabled + reset* (greedyFit is
//!                                     now heap-backed per commit 67fdd13;
//!                                     no big-stack worker thread needed)
//!   open_invention_tier8_battery_c.zig (bc) -- BATTERY_C target list +
//!                                     labelTarget (the reach-gap source)
//! The numeric glue for the composed-lens stage (sigmoid/logit-fit/accuracy/
//! R^2/lens-evaluation) is a from-scratch mirror of unified_invention.zig's
//! private routines, same convention tier8_aimed_proposer.zig used (those
//! routines are not `pub`, so any reuse of the mechanism has to re-derive the
//! small amount of boilerplate math -- never the XOR-primitive shortcut
//! itself: this file never calls xorMasked / xorPopcountReadout / buildXorCols).
//!
//! Build:  zig build-exe breadth_vs_depth.zig -O ReleaseFast   (Zig 0.14.1)
//! Pilot:  ./breadth_vs_depth --pilot --seed=0
//!         (uncapped canonical-proposer run; prints natural full-exhaustion
//!         eval count, used to choose B -- H50's own calibration method.)
//! Run:    ./breadth_vs_depth --seed=0 --budget=<B> --label=full  > csv
//!         ./breadth_vs_depth --seed=1 --budget=<B> --label=full --no-header >> csv
//!         ... (one invocation per seed; CSV on stdout, log on stderr)

const std = @import("std");
const mem = std.mem;
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");
const bc = @import("open_invention_tier8_battery_c.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

const NSAMP: usize = ui.NSAMP;
const NTR: usize = ui.NTR;
const NVA: usize = ui.NVA;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;

/// Atomic worst-case cost (eval units) of the two post-ladder Battery-B
/// escalation stages, used as affordability guards so a small-budget breadth
/// proposer does not blow past its cap by firing an all-or-nothing stage it
/// cannot afford. tryModEscalation = bank.nodes.len (256) + N_INNER1*N_INNER2
/// (49) + N_INNER1 (7) + 1 fit + 1 certify ≈ 314 (H50: B11 mod escalation =
/// 322). tryPairWalshEscalation worst case = 28 pair + 256 walsh + 2 fits ≈
/// 286. Guarding at these costs keeps per-proposer overshoot ≈ 0, which is
/// what makes the equal-total-budget comparison exact (the crux). The guard
/// only ever bites the breadth proposers — DEPTH's cap dwarfs both costs.
const MOD_COST: usize = 330;
const PAIRWALSH_COST: usize = 300;

/// Same 3 seeds as tier8_aimed_proposer.zig / tier8_reach_gap.zig, reused for
/// direct comparability across this research arc.
const SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };

/// The 4 breadth pool sizes required by the task brief.
const NS = [_]usize{ 4, 8, 16, 32 };

/// Battery C indices for the 5 reach-gap targets: C02, C04, C05, C06 (XOR
/// family, reachable only via lens-composition -- round b's aimed-proposer
/// flips) and C09 (inversion parity, PROVEN family-level unreachable --
/// tier8_reach_gap.md's Bayes-ceiling proof; negative control).
const REACH_GAP_IDX = [_]usize{ 1, 3, 4, 5, 8 };

// ── Diversity axes ──────────────────────────────────────────────────────────

const Lens = enum { th1, th2, th3, th4, th5, mod2 };
const FULL_LENS = [_]Lens{ .th1, .th2, .th3, .th4, .th5, .mod2 };

const LS_A = [_]Lens{.th3};
const LS_B = [_]Lens{.mod2};
const LS_C = [_]Lens{ .th1, .th2 };
const LS_D = [_]Lens{ .th4, .th5 };
const LS_E = [_]Lens{ .th3, .mod2 };
const LS_F = [_]Lens{ .th1, .mod2 };
const LS_G = [_]Lens{ .th2, .th4 };
const LS_H = [_]Lens{ .th5, .mod2 };

const LensSubsetSpec = struct { name: []const u8, lenses: []const Lens };
const LENS_SUBSETS = [_]LensSubsetSpec{
    .{ .name = "th3", .lenses = &LS_A },
    .{ .name = "mod2", .lenses = &LS_B },
    .{ .name = "th1+th2", .lenses = &LS_C },
    .{ .name = "th4+th5", .lenses = &LS_D },
    .{ .name = "th3+mod2", .lenses = &LS_E },
    .{ .name = "th1+mod2", .lenses = &LS_F },
    .{ .name = "th2+th4", .lenses = &LS_G },
    .{ .name = "th5+mod2", .lenses = &LS_H },
};

const EscOrder = enum { mod_first, pair_first };
const GrowOp = enum { flip1, flip2 };

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

fn splitmix64(x0: u64) u64 {
    var z = x0 +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

// ── Numeric mirror of unified_invention.zig's private routines (same
// hyperparameters, same splits -- see tier8_aimed_proposer.zig for the
// precedent of re-deriving this glue rather than importing private fns) ────

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

// ── Budget-aware evidence miners (random subsample when budget can't afford
// the full exhaustive sweep -- diversity axis #3, and a hard necessity at
// high N) ────────────────────────────────────────────────────────────────

var MONO_MASKS_BUF: [162]u8 = undefined;
var MONO_MASKS: []const u8 = undefined;

fn initMonoMasks() void {
    var n: usize = 0;
    var m: u16 = 1;
    while (m < 256) : (m += 1) {
        const mask: u8 = @intCast(m);
        const pc = @popCount(mask);
        if (pc < 1 or pc > 4) continue;
        MONO_MASKS_BUF[n] = mask;
        n += 1;
    }
    MONO_MASKS = MONO_MASKS_BUF[0..n];
}

const MonoEvidence = struct { mask: u8, val: f64, examined: usize };

fn monomialSweepBudgeted(grid: []const [8]u8, Y: []const f64, scratch: []f64, want: usize, rand: std.Random) MonoEvidence {
    var best_val: f64 = -1;
    var best_mask: u8 = MONO_MASKS[0];
    var examined: usize = 0;
    if (want <= 0) return .{ .mask = best_mask, .val = -1, .examined = 0 };
    if (want >= MONO_MASKS.len) {
        for (MONO_MASKS) |mask| {
            for (0..NSAMP) |s| scratch[s] = ui.evalFeaturePublic(.{ .monomial = mask }, grid[s]);
            const v = valAccSingleL(scratch, Y);
            examined += 1;
            if (v > best_val) {
                best_val = v;
                best_mask = mask;
            }
        }
        return .{ .mask = best_mask, .val = best_val, .examined = examined };
    }
    var idx: [162]usize = undefined;
    for (0..MONO_MASKS.len) |i| idx[i] = i;
    var i: usize = MONO_MASKS.len;
    while (i > 1) {
        i -= 1;
        const j = rand.intRangeLessThan(usize, 0, i + 1);
        const t = idx[i];
        idx[i] = idx[j];
        idx[j] = t;
    }
    for (0..want) |k| {
        const mask = MONO_MASKS[idx[k]];
        for (0..NSAMP) |s| scratch[s] = ui.evalFeaturePublic(.{ .monomial = mask }, grid[s]);
        const v = valAccSingleL(scratch, Y);
        examined += 1;
        if (v > best_val) {
            best_val = v;
            best_mask = mask;
        }
    }
    return .{ .mask = best_mask, .val = best_val, .examined = examined };
}

const WalshEvidence = struct { s: u8, val: f64, examined: usize };

fn walshSweepBudgeted(grid: []const [8]u8, Y: []const f64, scratch: []f64, want: usize, rand: std.Random) WalshEvidence {
    var best_val: f64 = -1;
    var best_s: u8 = 0;
    var examined: usize = 0;
    if (want <= 0) return .{ .s = 0, .val = -1, .examined = 0 };
    if (want >= 256) {
        var sm: u16 = 0;
        while (sm < 256) : (sm += 1) {
            const sv: u8 = @intCast(sm);
            for (0..NSAMP) |s| scratch[s] = ui.evalFeaturePublic(.{ .walsh = sv }, grid[s]);
            const v = valAccSingleL(scratch, Y);
            examined += 1;
            if (v > best_val) {
                best_val = v;
                best_s = sv;
            }
        }
        return .{ .s = best_s, .val = best_val, .examined = examined };
    }
    var idx: [256]u16 = undefined;
    for (0..256) |i| idx[i] = @intCast(i);
    var i: usize = 256;
    while (i > 1) {
        i -= 1;
        const j = rand.intRangeLessThan(usize, 0, i + 1);
        const t = idx[i];
        idx[i] = idx[j];
        idx[j] = t;
    }
    for (0..want) |k| {
        const sv: u8 = @intCast(idx[k]);
        for (0..NSAMP) |s| scratch[s] = ui.evalFeaturePublic(.{ .walsh = sv }, grid[s]);
        const v = valAccSingleL(scratch, Y);
        examined += 1;
        if (v > best_val) {
            best_val = v;
            best_s = sv;
        }
    }
    return .{ .s = best_s, .val = best_val, .examined = examined };
}

const GrowResult = struct { mask: u8, val: f64, rounds: usize };

/// Greedy stepwise mask search under a fixed lens, seeded from the evidence
/// mask. flip1 = single-bit neighborhood (tier8_aimed_proposer.zig's
/// original); flip2 = adjacent-bit-pair neighborhood -- diversity axis #4,
/// same per-round cost (8 candidates) so arms are budget-comparable.
fn greedyGrowBudgeted(grid: []const [8]u8, Y: []const f64, scratch: []f64, start_mask: u8, lens: Lens, rounds_cap: usize, grow_op: GrowOp, evals: *usize) GrowResult {
    var mask = start_mask;
    var best_val = composedSweepVal(grid, mask, lens, Y, scratch);
    evals.* += 1;
    var rounds: usize = 0;
    var improved = true;
    while (improved and rounds < rounds_cap) : (rounds += 1) {
        improved = false;
        var try_mask = mask;
        var try_val = best_val;
        for (0..8) |i| {
            const cm: u8 = switch (grow_op) {
                .flip1 => mask ^ (@as(u8, 1) << @intCast(i)),
                .flip2 => mask ^ (@as(u8, 1) << @intCast(i)) ^ (@as(u8, 1) << @intCast((i + 1) % 8)),
            };
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

// ── Composed-lens stage (the reach-gap escalation beyond the base ladder,
// budget-gated at every step; mirrors tier8_aimed_proposer.zig's mechanism
// but with diversity parameters and mid-stage budget awareness) ──────────

const ComposedOutcome = struct {
    attempted: bool,
    certified: bool,
    mono_examined: usize,
    walsh_examined: usize,
    grown_mask: u8,
    chosen_lens: Lens,
};

fn runComposedStage(
    X: [][]f64,
    grid: []const [8]u8,
    lib: []const ui.Feature,
    Y: []const f64,
    scratch: []f64,
    lens_subset: []const Lens,
    grow_op: GrowOp,
    rand: std.Random,
    budget: *rq1.EvalCounter,
    cap: usize,
) ComposedOutcome {
    const zero: ComposedOutcome = .{ .attempted = false, .certified = false, .mono_examined = 0, .walsh_examined = 0, .grown_mask = 0, .chosen_lens = lens_subset[0] };
    if (budget.total() >= cap) return zero;

    const rem0 = cap - budget.total();
    const mono_want = @min(MONO_MASKS.len, rem0 * 2 / 5);
    const mono_ev = monomialSweepBudgeted(grid, Y, scratch, mono_want, rand);
    budget.probe += mono_ev.examined;

    if (budget.total() >= cap) return .{ .attempted = true, .certified = false, .mono_examined = mono_ev.examined, .walsh_examined = 0, .grown_mask = mono_ev.mask, .chosen_lens = lens_subset[0] };
    const rem1 = cap - budget.total();
    const walsh_want = @min(@as(usize, 256), rem1 / 2);
    const walsh_ev = walshSweepBudgeted(grid, Y, scratch, walsh_want, rand);
    budget.probe += walsh_ev.examined;
    // walsh evidence-gathering cost paid; growth seed is the mono mask
    // (matches tier8_aimed_proposer.zig precedent) -- walsh_ev.examined is
    // still threaded through the return value below for cost accounting.

    if (budget.total() >= cap) return .{ .attempted = true, .certified = false, .mono_examined = mono_ev.examined, .walsh_examined = walsh_ev.examined, .grown_mask = mono_ev.mask, .chosen_lens = lens_subset[0] };
    const rem2 = cap - budget.total();
    if (rem2 < lens_subset.len + 2) return .{ .attempted = true, .certified = false, .mono_examined = mono_ev.examined, .walsh_examined = walsh_ev.examined, .grown_mask = mono_ev.mask, .chosen_lens = lens_subset[0] };

    var best_lens = lens_subset[0];
    var best_lens_val: f64 = -1;
    for (lens_subset) |lens| {
        const v = composedSweepVal(grid, mono_ev.mask, lens, Y, scratch);
        budget.probe += 1;
        if (v > best_lens_val) {
            best_lens_val = v;
            best_lens = lens;
        }
    }

    if (budget.total() >= cap or (cap - budget.total()) < 2) {
        return .{ .attempted = true, .certified = false, .mono_examined = mono_ev.examined, .walsh_examined = walsh_ev.examined, .grown_mask = mono_ev.mask, .chosen_lens = best_lens };
    }
    const rem3 = cap - budget.total();
    const grow_room = rem3 - 2;
    const rounds_cap = @min(@as(usize, 16), grow_room / 8);
    var grow_evals: usize = 0;
    const grown = greedyGrowBudgeted(grid, Y, scratch, mono_ev.mask, best_lens, rounds_cap, grow_op, &grow_evals);
    budget.probe += grow_evals;

    if (budget.total() >= cap or (cap - budget.total()) < 2) {
        return .{ .attempted = true, .certified = false, .mono_examined = mono_ev.examined, .walsh_examined = walsh_ev.examined, .grown_mask = grown.mask, .chosen_lens = best_lens };
    }

    var cand_raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| cand_raw[s] = composedVal(grid[s], grown.mask, best_lens);
    var w_r2: [40]f64 = undefined;
    var w_aug: [40]f64 = undefined;
    const cov_before = ui.measureCoverage(X, grid, lib, Y, w_r2[0..]);
    const r2 = reconR2L(X, lib.len, cand_raw[0..], w_r2[0..]);
    const cov_after = coverageAugmented(X, grid, lib, cand_raw[0..], Y, w_aug[0..]);
    budget.probe += 2;

    const escape = cov_after >= COVER and cov_before < COVER;
    const certified = escape and r2 < R2_MAX;
    return .{ .attempted = true, .certified = certified, .mono_examined = mono_ev.examined, .walsh_examined = walsh_ev.examined, .grown_mask = grown.mask, .chosen_lens = best_lens };
}

// ── Battery-B block (11 targets, shared growable library, budget-capped
// stage-boundary gates -- mirrors scaling_laws.zig's solveBlindTargetCapped,
// parameterized by target order + escalation order) ───────────────────────

fn tryModStage(X: [][]f64, grid: []const [8]u8, lib: []const ui.Feature, Yb: []const f64, w: []f64, bank: rq1.ProgBank, S_store: *const [rq1.N_INNER1][]f64, cov0: f64, tgt: rq1.BatteryTarget, budget: *rq1.EvalCounter, cap: usize) !bool {
    if (!rq1.needsMod(tgt.kind)) return false;
    // Affordability guard (not just budget<cap): the stage is atomic ~330
    // evals, so only fire it if the whole cost fits under the cap.
    if (budget.total() + MOD_COST > cap) return false;
    var rq_frozen: [32]rq1.Feature = undefined;
    for (0..lib.len) |i| rq_frozen[i] = .{ .monomial = lib[i].monomial };
    if (try rq1.tryModEscalation(X, grid, rq_frozen[0..lib.len], Yb, bank, S_store, w, cov0, tgt, SilentOut{}, budget)) |ev| {
        if (ev.certified) return true;
    }
    return false;
}

fn tryPairStage(grid: []const [8]u8, lib: []const ui.Feature, Yb: []const f64, pf: []const []f64, feat: []f64, w: []f64, cov0: f64, tgt: rq1.BatteryTarget, budget: *rq1.EvalCounter, cap: usize) !bool {
    // Affordability guard: worst case ~300 evals (28 pair + 256 walsh + fits).
    if (budget.total() + PAIRWALSH_COST > cap) return false;
    var rq_frozen2: [32]rq1.Feature = undefined;
    for (0..lib.len) |i| rq_frozen2[i] = .{ .monomial = lib[i].monomial };
    if (try rq1.tryPairWalshEscalation(grid, rq_frozen2[0..lib.len], Yb, pf, feat, w, cov0, tgt, SilentOut{}, budget)) |ev| {
        if (ev.certified) return true;
    }
    return false;
}

fn runBBlock(
    ctx: *ie.BlindBatteryCtx,
    lib: *[32]ui.Feature,
    nlib: *usize,
    w: []f64,
    order: [11]u8,
    esc_order: EscOrder,
    budget: *rq1.EvalCounter,
    cap: usize,
    solved_out: *[11]bool,
) !void {
    var Yb: [NSAMP]f64 = undefined;
    for (order) |oi| {
        const ti: usize = oi;
        const tgt = ctx.battery[ti];
        if (budget.total() >= cap) {
            solved_out[ti] = false;
            continue;
        }
        for (0..NSAMP) |s| Yb[s] = rq1.labelBattery(ctx.grid[s], tgt);
        budget.fit += 1;
        const cov0 = ui.measureCoverage(ctx.X, ctx.grid, lib[0..nlib.*], Yb[0..], w);
        if (cov0 >= COVER) {
            solved_out[ti] = true;
            continue;
        }
        if (budget.total() >= cap) {
            solved_out[ti] = false;
            continue;
        }
        const m = ui.solveOneTarget(ctx.X, ctx.grid, lib, nlib, Yb[0..], ctx.phiTgt, w, SilentOut{}, true);
        budget.certify += m.iters_to_certify;
        budget.probe += 2;
        if (m.solved) {
            solved_out[ti] = true;
            continue;
        }

        var solved_here = false;
        if (esc_order == .mod_first) {
            solved_here = try tryModStage(ctx.X, ctx.grid, lib[0..nlib.*], Yb[0..], w, ctx.bank, &ctx.S_store, cov0, tgt, budget, cap);
            if (!solved_here) solved_here = try tryPairStage(ctx.grid, lib[0..nlib.*], Yb[0..], ctx.pf, ctx.feat, w, cov0, tgt, budget, cap);
        } else {
            solved_here = try tryPairStage(ctx.grid, lib[0..nlib.*], Yb[0..], ctx.pf, ctx.feat, w, cov0, tgt, budget, cap);
            if (!solved_here) solved_here = try tryModStage(ctx.X, ctx.grid, lib[0..nlib.*], Yb[0..], w, ctx.bank, &ctx.S_store, cov0, tgt, budget, cap);
        }
        solved_out[ti] = solved_here;
    }
}

// ── Battery-C-derived reach-gap block (5 targets, fresh library per target
// -- matches tier8_aimed_proposer.zig's bc harness convention) ────────────

fn runCBlock(
    ctx: *ie.BlindBatteryCtx,
    trained_lib: []const rq1.Feature,
    reach_targets: []const bc.BatteryCTarget,
    order: [5]u8,
    lens_subset: []const Lens,
    grow_op: GrowOp,
    rand: std.Random,
    budget: *rq1.EvalCounter,
    cap: usize,
    solved_out: *[5]bool,
    scratch: []f64,
) void {
    var Yb: [NSAMP]f64 = undefined;
    for (order) |oi| {
        const ti: usize = oi;
        const tgt = reach_targets[ti];
        var lib: [32]ui.Feature = undefined;
        var nlib: usize = 0;
        ie.seedUiFromRq1(trained_lib, &lib, &nlib);
        var w: [40]f64 = undefined;

        if (budget.total() >= cap) {
            solved_out[ti] = false;
            continue;
        }
        for (0..NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);
        budget.fit += 1;
        const cov0 = ui.measureCoverage(ctx.X, ctx.grid, lib[0..nlib], Yb[0..], w[0..]);
        if (cov0 >= COVER) {
            solved_out[ti] = true;
            continue;
        }
        if (budget.total() >= cap) {
            solved_out[ti] = false;
            continue;
        }
        const m = ui.solveOneTarget(ctx.X, ctx.grid, &lib, &nlib, Yb[0..], ctx.phiTgt, w[0..], SilentOut{}, true);
        budget.certify += m.iters_to_certify;
        budget.probe += 2;
        if (m.solved) {
            solved_out[ti] = true;
            continue;
        }

        const outcome = runComposedStage(ctx.X, ctx.grid, lib[0..nlib], Yb[0..], scratch, lens_subset, grow_op, rand, budget, cap);
        solved_out[ti] = outcome.certified;
    }
}

// ── Proposer: one full pass over the combined 16-target battery under one
// shared budget cap. The canonical config (used ONCE, by DEPTH) is the
// production tool at full strength; diverseConfig(pi, n, seed) builds the
// pi-th of n independent, differently-configured proposers for BREADTH(n) ──

const ProposerConfig = struct {
    b_order: [11]u8,
    c_order: [5]u8,
    b_first: bool,
    lens_subset: []const Lens,
    lens_name: []const u8,
    esc_order: EscOrder,
    grow_op: GrowOp,
    rand_seed: u64,
};

fn identityOrder11() [11]u8 {
    var o: [11]u8 = undefined;
    for (0..11) |i| o[i] = @intCast(i);
    return o;
}
fn identityOrder5() [5]u8 {
    var o: [5]u8 = undefined;
    for (0..5) |i| o[i] = @intCast(i);
    return o;
}

fn shuffledOrder11(rand: std.Random) [11]u8 {
    var o = identityOrder11();
    var i: usize = 11;
    while (i > 1) {
        i -= 1;
        const j = rand.intRangeLessThan(usize, 0, i + 1);
        const t = o[i];
        o[i] = o[j];
        o[j] = t;
    }
    return o;
}
fn shuffledOrder5(rand: std.Random) [5]u8 {
    var o = identityOrder5();
    var i: usize = 5;
    while (i > 1) {
        i -= 1;
        const j = rand.intRangeLessThan(usize, 0, i + 1);
        const t = o[i];
        o[i] = o[j];
        o[j] = t;
    }
    return o;
}

fn canonicalConfig() ProposerConfig {
    return .{
        .b_order = identityOrder11(),
        .c_order = identityOrder5(),
        .b_first = true,
        .lens_subset = &FULL_LENS,
        .lens_name = "full(6)",
        .esc_order = .mod_first,
        .grow_op = .flip1,
        .rand_seed = 0,
    };
}

fn diverseConfig(pi: usize, run_seed: u64) ProposerConfig {
    const local_seed = splitmix64(run_seed ^ (@as(u64, pi) *% 0x9E3779B97F4A7C15) ^ 0xD1B54A32D192ED03);
    var prng = std.Random.DefaultPrng.init(local_seed);
    const rand = prng.random();
    const ls = LENS_SUBSETS[pi % LENS_SUBSETS.len];
    return .{
        .b_order = shuffledOrder11(rand),
        .c_order = shuffledOrder5(rand),
        .b_first = rand.boolean(),
        .lens_subset = ls.lenses,
        .lens_name = ls.name,
        .esc_order = if (pi % 2 == 0) .mod_first else .pair_first,
        .grow_op = if ((pi / 2) % 2 == 0) .flip1 else .flip2,
        .rand_seed = splitmix64(local_seed ^ 0xA5A5A5A5A5A5A5A5),
    };
}

const ProposerResult = struct {
    b_solved: [11]bool,
    c_solved: [5]bool,
    evals_used: usize,
};

fn runProposer(
    ctx: *ie.BlindBatteryCtx,
    trained_lib: []const rq1.Feature,
    reach_targets: []const bc.BatteryCTarget,
    cfg: ProposerConfig,
    cap: usize,
) !ProposerResult {
    // Fresh, independent tax slate per proposer -- proposers must be
    // genuinely independent for the union/dedup comparison to mean anything
    // (a shared global tax-log/replay state carrying over between
    // "independent" proposers would contaminate exactly the claim this
    // experiment needs to make).
    eqtax.strict_enabled = true;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(trained_lib, &lib, &nlib);
    var w: [40]f64 = undefined;

    var b_solved: [11]bool = .{false} ** 11;
    var c_solved: [5]bool = .{false} ** 5;

    const scratch = try std.heap.page_allocator.alloc(f64, NSAMP);
    defer std.heap.page_allocator.free(scratch);
    var prng = std.Random.DefaultPrng.init(cfg.rand_seed);
    const rand = prng.random();

    var budget = rq1.EvalCounter{};

    if (cfg.b_first) {
        try runBBlock(ctx, &lib, &nlib, w[0..], cfg.b_order, cfg.esc_order, &budget, cap, &b_solved);
        runCBlock(ctx, trained_lib, reach_targets, cfg.c_order, cfg.lens_subset, cfg.grow_op, rand, &budget, cap, &c_solved, scratch);
    } else {
        runCBlock(ctx, trained_lib, reach_targets, cfg.c_order, cfg.lens_subset, cfg.grow_op, rand, &budget, cap, &c_solved, scratch);
        try runBBlock(ctx, &lib, &nlib, w[0..], cfg.b_order, cfg.esc_order, &budget, cap, &b_solved);
    }

    return .{ .b_solved = b_solved, .c_solved = c_solved, .evals_used = budget.total() };
}

// ── Pilot: uncapped canonical-proposer run to calibrate B ─────────────────

fn runPilot(seed_idx: usize) !void {
    const seed = SEEDS[seed_idx];
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
    const reach_targets = [_]bc.BatteryCTarget{ bc.BATTERY_C[REACH_GAP_IDX[0]], bc.BATTERY_C[REACH_GAP_IDX[1]], bc.BATTERY_C[REACH_GAP_IDX[2]], bc.BATTERY_C[REACH_GAP_IDX[3]], bc.BATTERY_C[REACH_GAP_IDX[4]] };

    const cfg = canonicalConfig();
    const res = try runProposer(&prep.ctx, prep.trained_lib, &reach_targets, cfg, 1_000_000);
    var nb: usize = 0;
    for (res.b_solved) |s| {
        if (s) nb += 1;
    }
    var nc: usize = 0;
    for (res.c_solved) |s| {
        if (s) nc += 1;
    }
    std.debug.print("PILOT seed_idx={d} seed=0x{X:0>16}\n  battery-B solved: {d}/11\n  reach-gap solved: {d}/5 (", .{ seed_idx, seed, nb, nc });
    for (reach_targets, 0..) |t, i| {
        std.debug.print("{s}={s}{s}", .{ t.name, if (res.c_solved[i]) "SOLVED" else "stuck", if (i + 1 < reach_targets.len) ", " else "" });
    }
    std.debug.print(")\n  total evals consumed (uncapped canonical proposer): {d}\n", .{res.evals_used});
}

// ── Main sweep: DEPTH + BREADTH(4,8,16,32) at one fixed total budget B ────

fn runSweep(only_seed: ?usize, budget_B: usize, label: []const u8, header: bool) !void {
    const out = std.io.getStdOut().writer();
    const err = std.io.getStdErr().writer();

    if (header) {
        try out.print("row_type,label,seed_idx,arm,n_proposers,proposer_idx,budget_cap,per_proposer_cap,target_group,target_idx,target_name,solved,solved_by_count,first_solver_idx,evals_used,lens_subset,esc_order,grow_op,b_first,targets_solved_by_proposer\n", .{});
    }

    for (SEEDS, 0..) |seed, si| {
        if (only_seed) |o| {
            if (si != o) continue;
        }
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var prep = try ie.prepareBlindBatterySeed(alloc, seed, SilentOut{});
        const reach_targets = [_]bc.BatteryCTarget{ bc.BATTERY_C[REACH_GAP_IDX[0]], bc.BATTERY_C[REACH_GAP_IDX[1]], bc.BATTERY_C[REACH_GAP_IDX[2]], bc.BATTERY_C[REACH_GAP_IDX[3]], bc.BATTERY_C[REACH_GAP_IDX[4]] };

        // ── DEPTH: one proposer, canonical config, full budget B ──────────
        const depth_cfg = canonicalConfig();
        const depth_res = try runProposer(&prep.ctx, prep.trained_lib, &reach_targets, depth_cfg, budget_B);
        var depth_solved: usize = 0;
        for (depth_res.b_solved) |s| {
            if (s) depth_solved += 1;
        }
        for (depth_res.c_solved) |s| {
            if (s) depth_solved += 1;
        }
        try out.print("run,{s},{d},depth,1,,{d},{d},,,,,,,{d},full(6),mod_first,flip1,true,\n", .{ label, si, budget_B, budget_B, depth_res.evals_used });
        for (prep.ctx.battery, 0..) |tgt, ti| {
            try out.print("target,{s},{d},depth,1,,{d},{d},B,{d},\"{s}\",{d},,,,,,,,,\n", .{ label, si, budget_B, budget_B, ti, tgt.name, @intFromBool(depth_res.b_solved[ti]) });
        }
        for (reach_targets, 0..) |tgt, ti| {
            try out.print("target,{s},{d},depth,1,,{d},{d},C,{d},\"{s}\",{d},,,,,,,,,\n", .{ label, si, budget_B, budget_B, ti, tgt.name, @intFromBool(depth_res.c_solved[ti]) });
        }
        try err.print("[seed {d} label={s}] DEPTH: {d}/16 solved, evals used {d}/{d}\n", .{ si, label, depth_solved, depth_res.evals_used, budget_B });

        // ── BREADTH(N) at EQUAL TOTAL BUDGET (the crux) ──────────────────
        // The pool's total budget is DEPTH's actually-consumed evals, not the
        // nominal --budget cap: depth plateaus below its cap (H50), so its
        // consumed total is the fair "same total compute" both arms may spend.
        // Each of the N proposers is capped at B_eff/N; a global pool counter
        // (pool_remaining) makes the SUM across proposers ≤ B_eff, so breadth
        // never spends more total than depth. If per-proposer overshoot
        // exhausts the pool before all N run, the remaining proposers do NOT
        // run (recorded) — an honest "budget can't afford N proposers at this
        // split" outcome, itself a finding.
        const B_eff = depth_res.evals_used;

        for (NS) |n| {
            const per_cap = B_eff / n;
            var union_b: [11]bool = .{false} ** 11;
            var count_b: [11]usize = .{0} ** 11;
            var first_b: [11]i32 = .{-1} ** 11;
            var union_c: [5]bool = .{false} ** 5;
            var count_c: [5]usize = .{0} ** 5;
            var first_c: [5]i32 = .{-1} ** 5;
            var total_evals: usize = 0;
            var proposer_solved: [32]usize = undefined;
            var pool_remaining: usize = B_eff;
            var proposers_run: usize = 0;
            // distinct diversity behaviors that actually executed AND certified
            // at least one target (for the "diversity achieved" metric)
            var lens_used_mask: u16 = 0;

            const run_seed = splitmix64(seed ^ (@as(u64, n) *% 0xC2B2AE3D27D4EB4F));

            for (0..n) |pi| {
                const cfg = diverseConfig(pi, run_seed);
                const cap_i = @min(per_cap, pool_remaining);
                var res: ProposerResult = .{ .b_solved = .{false} ** 11, .c_solved = .{false} ** 5, .evals_used = 0 };
                var did_run = false;
                if (cap_i >= 1) {
                    res = try runProposer(&prep.ctx, prep.trained_lib, &reach_targets, cfg, cap_i);
                    did_run = true;
                    proposers_run += 1;
                    total_evals += res.evals_used;
                    pool_remaining = if (res.evals_used >= pool_remaining) 0 else pool_remaining - res.evals_used;
                }
                var solved_this: usize = 0;
                for (0..11) |j| {
                    if (res.b_solved[j]) {
                        union_b[j] = true;
                        count_b[j] += 1;
                        if (first_b[j] < 0) first_b[j] = @intCast(pi);
                        solved_this += 1;
                    }
                }
                for (0..5) |j| {
                    if (res.c_solved[j]) {
                        union_c[j] = true;
                        count_c[j] += 1;
                        if (first_c[j] < 0) first_c[j] = @intCast(pi);
                        solved_this += 1;
                    }
                }
                proposer_solved[pi] = solved_this;
                if (did_run and solved_this > 0) {
                    lens_used_mask |= (@as(u16, 1) << @intCast(pi % LENS_SUBSETS.len));
                }
                try out.print("proposer,{s},{d},breadth_{d},{d},{d},{d},{d},,,,{s},,,{d},{s},{s},{s},{s},{d}\n", .{
                    label,
                    si,
                    n,
                    n,
                    pi,
                    B_eff,
                    per_cap,
                    if (did_run) "ran" else "not-run",
                    res.evals_used,
                    cfg.lens_name,
                    @tagName(cfg.esc_order),
                    @tagName(cfg.grow_op),
                    if (cfg.b_first) "true" else "false",
                    solved_this,
                });
            }

            var union_total: usize = 0;
            for (union_b) |s| {
                if (s) union_total += 1;
            }
            for (union_c) |s| {
                if (s) union_total += 1;
            }
            var dominant: usize = 0;
            for (0..n) |pi| dominant = @max(dominant, proposer_solved[pi]);
            const dominant_frac: f64 = if (union_total > 0) @as(f64, @floatFromInt(dominant)) / @as(f64, @floatFromInt(union_total)) else 0;
            const distinct_lens = @popCount(lens_used_mask);

            try out.print("run,{s},{d},breadth_{d},{d},,{d},{d},proposers_run={d},,,distinct_lens={d},,,{d},,,,,{d:.4}\n", .{ label, si, n, n, B_eff, per_cap, proposers_run, distinct_lens, total_evals, dominant_frac });
            for (prep.ctx.battery, 0..) |tgt, ti| {
                try out.print("target,{s},{d},breadth_{d},{d},,{d},{d},B,{d},\"{s}\",{d},{d},{d},,,,,,\n", .{ label, si, n, n, B_eff, per_cap, ti, tgt.name, @intFromBool(union_b[ti]), count_b[ti], first_b[ti] });
            }
            for (reach_targets, 0..) |tgt, ti| {
                try out.print("target,{s},{d},breadth_{d},{d},,{d},{d},C,{d},\"{s}\",{d},{d},{d},,,,,,\n", .{ label, si, n, n, B_eff, per_cap, ti, tgt.name, @intFromBool(union_c[ti]), count_c[ti], first_c[ti] });
            }
            try err.print("[seed {d} label={s}] BREADTH({d}): union {d}/16, proposers_run {d}/{d}, distinct_lens {d}, per-proposer cap {d}, total evals {d}/{d} (=depth consumed), dominant share {d:.1}%\n", .{ si, label, n, union_total, proposers_run, n, distinct_lens, per_cap, total_evals, B_eff, dominant_frac * 100.0 });
        }
    }
}

pub fn main() !void {
    initMonoMasks();

    var only_seed: ?usize = null;
    var budget: usize = 0;
    var label: []const u8 = "run";
    var header = true;
    var pilot = false;

    var args = std.process.args();
    _ = args.skip();
    while (args.next()) |arg| {
        if (mem.startsWith(u8, arg, "--seed=")) {
            only_seed = try std.fmt.parseInt(usize, arg["--seed=".len..], 10);
        } else if (mem.startsWith(u8, arg, "--budget=")) {
            budget = try std.fmt.parseInt(usize, arg["--budget=".len..], 10);
        } else if (mem.startsWith(u8, arg, "--label=")) {
            label = arg["--label=".len..];
        } else if (mem.eql(u8, arg, "--no-header")) {
            header = false;
        } else if (mem.eql(u8, arg, "--pilot")) {
            pilot = true;
        }
    }

    if (pilot) {
        try runPilot(only_seed orelse 0);
        return;
    }
    if (budget == 0) {
        std.debug.print("usage: breadth_vs_depth --seed=N --budget=B --label=full [--no-header]\n       breadth_vs_depth --pilot --seed=N\n", .{});
        return;
    }
    try runSweep(only_seed, budget, label, header);
}
