//! BREADTH-scaling harness — the counterpart to H50's DEPTH-scaling curve
//! (docs/research/scaling_laws_h50.md: budget-vs-solves on Battery B, hard
//! plateau at 372 evals).
//!
//! QUESTION: does out-of-closure reach grow with the NUMBER of diverse
//! parallel proposers N (at a FIXED per-proposer eval budget, so total
//! budget scales as N x per-proposer), and does it plateau? A critical
//! control isolates whether any growth comes from DIVERSITY (different
//! search mechanisms) or merely from QUANTITY (more independent random
//! draws of the same mechanism).
//!
//! ── Why Battery C, not Battery B ──────────────────────────────────────────
//! H50's depth curve is measured on Battery B, whose ladder (base -> unified
//! escalation -> mod/pipeline -> pair/Walsh) EVENTUALLY solves all 11
//! targets, at a cost that concentrates almost entirely (322/372 evals) in
//! one hard target (B11, inversion-parity), solved via the mod/pipeline
//! stage. That is a depth story about ONE mechanism escalating through
//! stages, not a breadth story.
//!
//! Battery C (docs/research/tier8_battery_c via open_invention_tier8_battery_c.zig)
//! is the genuinely OUT-OF-CLOSURE set for THIS round's purposes: 2026-07-10
//! findings (tier8_ablation.md, tier8_aimed_proposer.md, tier8_reach_gap.md)
//! established that the ladder + revision-tax baseline solves only ~1-3/11
//! Battery-C targets, and that a frontier-coupled "aimed proposer" (mask +
//! per-cell lens composition, evidence-mined from near-miss monomial/Walsh
//! correlations) can flip a FEW more (~15-24% of remaining attempts) but
//! that C09 (inversion-count parity) is PROVEN family-level impossible for
//! this hypothesis class via an information-basis Bayes-ceiling argument
//! (tier8_reach_gap.md): no function of the mask+lens family can separate
//! it above chance, regardless of budget. This is exactly the "H50-plateau
//! set" the task brief asks for: targets the standard ladder cannot reach,
//! where we now ask whether THROWING MORE PARALLEL ATTEMPTS AT THE SAME
//! MECHANISM (rather than more escalation stages) buys reach.
//!
//! ── The proposer mechanism (reused, not modified) ─────────────────────────
//! Each "proposer" here is a budget-capped variant of tier8_aimed_proposer.
//! zig's evidence-mine -> per-cell-lens -> greedy-mask-grow -> certify
//! pipeline (mono/Walsh evidence sampling, 6 lenses {th1..th5, mod2}, bit-
//! flip mask search, escape+R^2 certification against the SAME fresh
//! trained library the production ladder uses). tier8_aimed_proposer.zig
//! and scaling_laws.zig are reused READ-ONLY (imported, not edited); the
//! small amount of private numeric glue they each duplicate from
//! unified_invention.zig (sigmoid/logit fit, R^2 reconstruction, per-feature
//! val-split accuracy) is duplicated here too, for the same reason they
//! state: certifyPublic's signature couples library+candidate to a single
//! ui.Feature, which a lens-transformed composite is not.
//!
//! ── Diversity axes (documented, by construction) ──────────────────────────
//!   A. FAMILY SUBSET   — which evidence family(ies) a proposer samples:
//!      mono_focus (monomial masks only), walsh_focus (Walsh patterns only),
//!      balanced (both, 50/50), dual_anchor (both + a diagnostic mono*Walsh
//!      product signal + grows from BOTH evidence anchors independently).
//!   B. MUTATION OP for the grow phase — hill_climb (best-improvement over
//!      all 8 bit-flip neighbors each round), first_improvement (randomized
//!      neighbor order, take the first improving move), random_restart (on
//!      a local optimum, jump to a fresh random mask and keep climbing,
//!      tracking the best mask ever seen — spends any leftover budget on
//!      broader exploration instead of stopping).
//!   C. SEED / RNG — an independent splitMix64 stream per (pool_seed,
//!      target, arm, proposer_index), used for evidence subsampling,
//!      first_improvement's neighbor order, and random_restart's jumps.
//!   D. ESCALATION / ANCHOR ORDER — mono_then_walsh vs walsh_then_mono:
//!      which evidence type's mask anchors the grow phase when both exceed
//!      the other (also the lens tie-break rule). HONESTY NOTE: a Walsh
//!      pattern index and a cell-subset mask share the same u8 domain but
//!      not the same semantics (a Walsh index is not, by construction, a
//!      cell subset) — walsh_then_mono reusing it as a grow seed is a
//!      deliberate, disclosed quirk of this axis, not a bug; whether it ever
//!      helps is part of what this experiment measures, not an assumption.
//!
//! Each proposer's (family, mutop, order) combination is assigned
//! DETERMINISTICALLY by cycling proposer_index through the enumerated lists
//! (idx % 4, idx % 3, idx % 2 respectively) — not randomly chosen — so the
//! N-ladder is an exact, reproducible PREFIX union: the first N proposers at
//! N=32 are identical to the N proposers used at any smaller rung. This
//! means each (pool_seed, target, arm) cell needs only ONE pass of 32
//! proposer runs; every N in {1,2,4,8,16,32} is a prefix-union read of that
//! same pass (no resampling between rungs, no extra cost). This is the
//! standard way to build a pass@N-style curve from a fixed draw pool.
//!
//! The IDENTICAL-proposer control uses the SAME rng_seed formula (so RNG
//! diversity is identical in magnitude between arms) but PINS family/mutop/
//! order to entry 0 of each list for every proposer index — isolating
//! whether reach growth comes from mechanism diversity or just from more
//! independent random draws of one mechanism.
//!
//! ── Depth reference (same file, same battery, cheap) ──────────────────────
//! A single "exhaustive_depth" proposer per (seed, target): ALL 162 valid
//! monomial masks (popcount 1..4) + ALL 256 Walsh patterns + all 6 lenses +
//! a capped grow (48 evals — generous for an 8-bit bit-flip neighborhood) —
//! this is the full enumerable hypothesis space (256 masks x 6 lenses =
//! 1536 total (mask,lens) pairs) explored in ONE pass, at ~475 evals total
//! (cheaper than N=32's cumulative 1344). This directly answers "what does
//! spending the (smaller) budget as ONE big attempt buy, vs spreading it
//! over many small attempts" on the exact same battery, targets, and seeds.
//!
//! No existing file is modified. Standalone build:
//!   zig build-exe breadth_scaling.zig -O ReleaseFast
//! Run:
//!   ./breadth_scaling [--smoke]   (--smoke: 1 seed, 2 targets, N<=4 — timing check)
//! Single-threaded (greedyFit's column store is heap-backed since commit
//! 67fdd13 — no eqtax strict-tax certification path is used by the proposer
//! stage itself anyway; only the ladder BASELINE calls ui.solveOneTarget,
//! which may exercise eqtax under strict_enabled, same as tier8_aimed_proposer.zig).

const std = @import("std");
const ie = @import("invention_engine.zig");
const rq1 = @import("open_invention_rq1.zig");
const ui = @import("unified_invention.zig");
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

/// Same 3 seeds as tier8_aimed_proposer.zig / tier8_reach_gap.zig, for
/// continuity with this round's established Battery-C findings.
const POOL_SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };

/// Battery-C target indices (0-based into bc.BATTERY_C) used as the
/// out-of-closure reach set: C01/C03 (XOR deg4, "probabilistically missed"
/// per tier8_aimed_proposer.md — reachable in principle), C08 (mod_synthesis
/// family, a different family from the XOR wall), C09 (inversion parity —
/// proven family-level IMPOSSIBLE for the mask+lens hypothesis class per
/// tier8_reach_gap.md's Bayes-ceiling argument — our built-in always-zero
/// structural control), C10 (parity_xor variant), C11 (degree-5 XOR, the
/// hardest reachable case: needs a 5-cell mask, outside the ladder's own
/// degree<=4 forge).
const TARGET_IDX = [_]usize{ 0, 2, 7, 8, 9, 10 };

const N_LADDER_FULL = [_]usize{ 1, 2, 4, 8, 16, 32 };
const N_MAX: usize = 32;

/// Per-proposer search-phase eval cap (excludes the 2 final certify evals,
/// which are unavoidable overhead of testing ANY candidate, same convention
/// as tier8_aimed_proposer.zig: "evals += 2 // one coverage fit, one R^2 fit").
const SEARCH_BUDGET: usize = 40;
const LENS_COST: usize = 6;

// ── Numeric mirrors of unified_invention.zig's private routines ───────────
// (duplicated for the same reason tier8_aimed_proposer.zig duplicates them:
// certifyPublic's signature couples library+candidate to one ui.Feature,
// which a lens-transformed composite mask is not. Same hyperparameters,
// same NTR/NVA splits, same thresholds as both reused reference files.)

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

fn taxProxy(grid: []const [8]u8, lib: []const ui.Feature, mono_mask: u8, walsh_s: u8, cand_raw: []const f64) struct { novel: bool, best_corr: f64 } {
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

// ── Valid evidence pools ────────────────────────────────────────────────
// 162 monomial masks (popcount 1..4, matching monomialSweep's own filter)
// and the full 256-value Walsh pattern domain.

const MONO_MASKS: [162]u8 = blk: {
    var arr: [162]u8 = undefined;
    var n: usize = 0;
    var m: u16 = 1;
    while (m < 256) : (m += 1) {
        const mask: u8 = @intCast(m);
        const pc = @popCount(mask);
        if (pc >= 1 and pc <= 4) {
            arr[n] = mask;
            n += 1;
        }
    }
    if (n != 162) @compileError("MONO_MASKS count drifted from 162");
    break :blk arr;
};

const MonoEv = struct { mask: u8, val: f64 };
const WalshEv = struct { s: u8, val: f64 };

fn sampleMono(grid: []const [8]u8, Y: []const f64, k: usize, rand: std.Random, scratch: []f64) MonoEv {
    if (k == 0) return .{ .mask = 0, .val = -1 };
    var pool: [162]u8 = MONO_MASKS;
    var best_val: f64 = -1;
    var best_mask: u8 = 0;
    const kk = @min(k, pool.len);
    for (0..kk) |i| {
        const j = i + rand.uintLessThan(usize, pool.len - i);
        const tmp = pool[i];
        pool[i] = pool[j];
        pool[j] = tmp;
        const mask = pool[i];
        for (0..NSAMP) |s| scratch[s] = ui.evalFeaturePublic(.{ .monomial = mask }, grid[s]);
        const v = valAccSingleL(scratch, Y);
        if (v > best_val) {
            best_val = v;
            best_mask = mask;
        }
    }
    return .{ .mask = best_mask, .val = best_val };
}

fn sampleWalsh(grid: []const [8]u8, Y: []const f64, k: usize, rand: std.Random, scratch: []f64) WalshEv {
    if (k == 0) return .{ .s = 0, .val = -1 };
    var pool: [256]u16 = undefined;
    for (0..256) |i| pool[i] = @intCast(i);
    var best_val: f64 = -1;
    var best_s: u8 = 0;
    const kk = @min(k, 256);
    for (0..kk) |i| {
        const j = i + rand.uintLessThan(usize, 256 - i);
        const tmp = pool[i];
        pool[i] = pool[j];
        pool[j] = tmp;
        const sv: u8 = @intCast(pool[i]);
        for (0..NSAMP) |s| scratch[s] = ui.evalFeaturePublic(.{ .walsh = sv }, grid[s]);
        const v = valAccSingleL(scratch, Y);
        if (v > best_val) {
            best_val = v;
            best_s = sv;
        }
    }
    return .{ .s = best_s, .val = best_val };
}

fn comboVal(grid: []const [8]u8, mono_mask: u8, walsh_s: u8, Y: []const f64, scratch: []f64) f64 {
    var mono_buf: [NSAMP]f64 = undefined;
    var walsh_buf: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| mono_buf[s] = ui.evalFeaturePublic(.{ .monomial = mono_mask }, grid[s]);
    for (0..NSAMP) |s| walsh_buf[s] = ui.evalFeaturePublic(.{ .walsh = walsh_s }, grid[s]);
    for (0..NSAMP) |s| scratch[s] = mono_buf[s] * walsh_buf[s];
    return valAccSingleL(scratch, Y);
}

fn pickBestLens(scan: [6]f64, order: Order) usize {
    var best: usize = 0;
    switch (order) {
        // ascending: first (earliest-index) max wins ties
        .mono_then_walsh => {
            for (1..6) |li| {
                if (scan[li] > scan[best]) best = li;
            }
        },
        // descending preference: last (latest-index) max wins ties
        .walsh_then_mono => {
            for (0..6) |li| {
                if (scan[li] >= scan[best]) best = li;
            }
        },
    }
    return best;
}

// ── Diversity axes ─────────────────────────────────────────────────────

const Family = enum { mono_focus, walsh_focus, balanced, dual_anchor };
const MutOp = enum { hill_climb, first_improvement, random_restart };
const Order = enum { mono_then_walsh, walsh_then_mono };
const Arm = enum { diverse, identical, exhaustive_depth };

const FAMILIES = [_]Family{ .mono_focus, .walsh_focus, .balanced, .dual_anchor };
const MUTOPS = [_]MutOp{ .hill_climb, .first_improvement, .random_restart };
const ORDERS = [_]Order{ .mono_then_walsh, .walsh_then_mono };

const ProposerCfg = struct { family: Family, mutop: MutOp, order: Order, rng_seed: u64 };

fn splitMix64(x0: u64) u64 {
    var z = x0 +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn cfgFor(arm: Arm, idx: usize, pool_seed: u64, target_tag: u64) ProposerCfg {
    const mix = splitMix64(pool_seed ^ target_tag ^ (@as(u64, @intCast(idx)) *% 0x9E3779B97F4A7C15) ^ (@as(u64, @intFromEnum(arm)) << 60));
    return switch (arm) {
        .diverse => .{
            .family = FAMILIES[idx % FAMILIES.len],
            .mutop = MUTOPS[idx % MUTOPS.len],
            .order = ORDERS[idx % ORDERS.len],
            .rng_seed = mix,
        },
        .identical => .{
            .family = FAMILIES[0],
            .mutop = MUTOPS[0],
            .order = ORDERS[0],
            .rng_seed = mix,
        },
        .exhaustive_depth => .{
            .family = .dual_anchor,
            .mutop = .random_restart,
            .order = .mono_then_walsh,
            .rng_seed = mix,
        },
    };
}

const FamilyBudget = struct { mono: usize, walsh: usize, combo: bool, grow: usize };

/// Fixed split of SEARCH_BUDGET=40 (34 evals after reserving LENS_COST=6 for
/// the always-run lens scan). mono_focus/walsh_focus explore only ONE
/// evidence family (the "family subset" axis); balanced splits 50/50;
/// dual_anchor also splits ~50/50, spends 1 extra eval on the diagnostic
/// mono*Walsh product, and grows from BOTH anchors (grow budget halved).
fn familyBudget(family: Family) FamilyBudget {
    return switch (family) {
        .mono_focus => .{ .mono = 28, .walsh = 0, .combo = false, .grow = 6 },
        .walsh_focus => .{ .mono = 0, .walsh = 28, .combo = false, .grow = 6 },
        .balanced => .{ .mono = 14, .walsh = 14, .combo = false, .grow = 6 },
        .dual_anchor => .{ .mono = 13, .walsh = 13, .combo = true, .grow = 7 },
    };
}

/// The exhaustive depth-reference budget: ALL 162 monomial masks + ALL 256
/// Walsh patterns + 1 combo diagnostic + 6 lenses + a capped 48-eval grow
/// (generous for an 8-bit bit-flip neighborhood) + 2 certify = 475 evals
/// total, one pass. Deliberately smaller than N=32's cumulative 1344 (it
/// does not need to match: the point is that full evidence ENUMERATION is
/// already cheap here because the hypothesis space — 256 masks x 6 lenses =
/// 1536 pairs — is small and finite).
const EXH_BUDGET = FamilyBudget{ .mono = MONO_MASKS.len, .walsh = 256, .combo = true, .grow = 48 };

const GrowRes = struct { mask: u8, val: f64, evals: usize };

fn growCapped(grid: []const [8]u8, Y: []const f64, scratch: []f64, start_mask: u8, lens: Lens, mutop: MutOp, rand: std.Random, budget: usize) GrowRes {
    if (budget == 0) {
        const v0 = composedSweepVal(grid, start_mask, lens, Y, scratch);
        return .{ .mask = start_mask, .val = v0, .evals = 1 };
    }
    var used: usize = 1;
    var best_mask = start_mask;
    var best_val = composedSweepVal(grid, best_mask, lens, Y, scratch);

    switch (mutop) {
        .hill_climb => {
            var improved = true;
            while (improved and used < budget) {
                improved = false;
                var try_mask = best_mask;
                var try_val = best_val;
                for (0..8) |i| {
                    if (used >= budget) break;
                    const bit: u8 = @as(u8, 1) << @intCast(i);
                    const cm = best_mask ^ bit;
                    if (cm == 0) continue;
                    const v = composedSweepVal(grid, cm, lens, Y, scratch);
                    used += 1;
                    if (v > try_val) {
                        try_val = v;
                        try_mask = cm;
                    }
                }
                if (try_val > best_val + 1e-9) {
                    best_val = try_val;
                    best_mask = try_mask;
                    improved = true;
                }
            }
        },
        .first_improvement => {
            var order_idx: [8]u8 = .{ 0, 1, 2, 3, 4, 5, 6, 7 };
            var improved = true;
            while (improved and used < budget) {
                improved = false;
                var i: usize = order_idx.len;
                while (i > 1) {
                    i -= 1;
                    const j = rand.uintLessThan(usize, i + 1);
                    const tmp = order_idx[i];
                    order_idx[i] = order_idx[j];
                    order_idx[j] = tmp;
                }
                for (order_idx) |bi| {
                    if (used >= budget) break;
                    const bit: u8 = @as(u8, 1) << @intCast(bi);
                    const cm = best_mask ^ bit;
                    if (cm == 0) continue;
                    const v = composedSweepVal(grid, cm, lens, Y, scratch);
                    used += 1;
                    if (v > best_val + 1e-9) {
                        best_val = v;
                        best_mask = cm;
                        improved = true;
                        break;
                    }
                }
            }
        },
        .random_restart => {
            var cur_mask = best_mask;
            var cur_val = best_val;
            while (used < budget) {
                var improved_round = false;
                for (0..8) |i| {
                    if (used >= budget) break;
                    const bit: u8 = @as(u8, 1) << @intCast(i);
                    const cm = cur_mask ^ bit;
                    if (cm == 0) continue;
                    const v = composedSweepVal(grid, cm, lens, Y, scratch);
                    used += 1;
                    if (v > cur_val + 1e-9) {
                        cur_val = v;
                        cur_mask = cm;
                        improved_round = true;
                    }
                }
                if (cur_val > best_val) {
                    best_val = cur_val;
                    best_mask = cur_mask;
                }
                if (!improved_round and used < budget) {
                    var nm: u8 = 0;
                    while (nm == 0) nm = rand.int(u8);
                    cur_mask = nm;
                    cur_val = composedSweepVal(grid, cur_mask, lens, Y, scratch);
                    used += 1;
                }
            }
        },
    }
    return .{ .mask = best_mask, .val = best_val, .evals = used };
}

const ProposerResult = struct {
    certified: bool,
    novel: bool,
    family: Family,
    chosen_lens: Lens,
    seed_mask: u8,
    grown_mask: u8,
    grown_val: f64,
    cov_after: f64,
    r2: f64,
    evals: usize,
};

fn runProposer(
    X: [][]f64,
    grid: []const [8]u8,
    lib: []const ui.Feature,
    Y: []const f64,
    cov_before: f64,
    cfg: ProposerCfg,
    fb: FamilyBudget,
) ProposerResult {
    var prng = std.Random.DefaultPrng.init(cfg.rng_seed);
    const rand = prng.random();
    var scratch: [NSAMP]f64 = undefined;
    var evals: usize = 0;

    const mono_ev = sampleMono(grid, Y, fb.mono, rand, scratch[0..]);
    evals += @min(fb.mono, MONO_MASKS.len);
    const walsh_ev = sampleWalsh(grid, Y, fb.walsh, rand, scratch[0..]);
    evals += @min(fb.walsh, 256);

    if (fb.combo) {
        _ = comboVal(grid, if (mono_ev.val > -1) mono_ev.mask else 1, if (walsh_ev.val > -1) walsh_ev.s else 1, Y, scratch[0..]);
        evals += 1;
    }

    var seed_mask: u8 = switch (cfg.family) {
        .mono_focus => mono_ev.mask,
        .walsh_focus => walsh_ev.s,
        .balanced, .dual_anchor => switch (cfg.order) {
            .mono_then_walsh => if (mono_ev.val >= walsh_ev.val) mono_ev.mask else walsh_ev.s,
            .walsh_then_mono => if (walsh_ev.val >= mono_ev.val) walsh_ev.s else mono_ev.mask,
        },
    };
    if (seed_mask == 0) seed_mask = 1;

    var scan: [6]f64 = undefined;
    for (LENSES, 0..) |lens, li| scan[li] = composedSweepVal(grid, seed_mask, lens, Y, scratch[0..]);
    evals += 6;
    const chosen_lens = LENSES[pickBestLens(scan, cfg.order)];

    var grown_mask: u8 = undefined;
    var grown_val: f64 = undefined;
    if (cfg.family == .dual_anchor) {
        const half = fb.grow / 2;
        const anchor1: u8 = if (mono_ev.mask == 0) 1 else mono_ev.mask;
        const anchor2: u8 = if (walsh_ev.s == 0) 1 else walsh_ev.s;
        const g1 = growCapped(grid, Y, scratch[0..], anchor1, chosen_lens, cfg.mutop, rand, @max(half, 1));
        const g2 = growCapped(grid, Y, scratch[0..], anchor2, chosen_lens, cfg.mutop, rand, fb.grow - half);
        evals += g1.evals + g2.evals;
        if (g1.val >= g2.val) {
            grown_mask = g1.mask;
            grown_val = g1.val;
        } else {
            grown_mask = g2.mask;
            grown_val = g2.val;
        }
    } else {
        const g = growCapped(grid, Y, scratch[0..], seed_mask, chosen_lens, cfg.mutop, rand, fb.grow);
        evals += g.evals;
        grown_mask = g.mask;
        grown_val = g.val;
    }

    var cand_raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| cand_raw[s] = composedVal(grid[s], grown_mask, chosen_lens);

    var w_r2: [34]f64 = undefined;
    const r2 = reconR2L(X, lib.len, cand_raw[0..], w_r2[0..]);
    var w_aug: [34]f64 = undefined;
    const cov_after = coverageAugmented(X, grid, lib, cand_raw[0..], Y, w_aug[0..]);
    evals += 2;

    const escape = cov_after >= COVER and cov_before < COVER;
    const certified = escape and r2 < R2_MAX;
    const tp = taxProxy(grid, lib, if (mono_ev.val > -1) mono_ev.mask else seed_mask, if (walsh_ev.val > -1) walsh_ev.s else seed_mask, cand_raw[0..]);

    return .{
        .certified = certified,
        .novel = tp.novel,
        .family = cfg.family,
        .chosen_lens = chosen_lens,
        .seed_mask = seed_mask,
        .grown_mask = grown_mask,
        .grown_val = grown_val,
        .cov_after = cov_after,
        .r2 = r2,
        .evals = evals,
    };
}

const PrefixStats = struct { reached: bool, n_certified: usize, novel: usize, distinct_closures: usize, total_evals: usize };

fn prefixStats(results: []const ProposerResult, n: usize) PrefixStats {
    var n_certified: usize = 0;
    var novel: usize = 0;
    var total_evals: usize = 0;
    var seen: [24]struct { family: Family, lens: Lens } = undefined;
    var n_seen: usize = 0;
    for (results[0..n]) |r| {
        total_evals += r.evals;
        if (r.certified) {
            n_certified += 1;
            if (r.novel) novel += 1;
            var found = false;
            for (seen[0..n_seen]) |sg| {
                if (sg.family == r.family and sg.lens == r.chosen_lens) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                seen[n_seen] = .{ .family = r.family, .lens = r.chosen_lens };
                n_seen += 1;
            }
        }
    }
    return .{ .reached = n_certified > 0, .n_certified = n_certified, .novel = novel, .distinct_closures = n_seen, .total_evals = total_evals };
}

const BaselineResult = struct { solved: bool, cov: f64, lib: [32]ui.Feature, nlib: usize };

fn runBaseline(X: [][]f64, grid: []const [8]u8, phiTgt: []f64, trained_lib: []const rq1.Feature, Y: []const f64) BaselineResult {
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();
    eqtax.strict_enabled = true;
    eqtax.basis_level = 4;
    eqtax.reality_lane_enabled = true;

    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(trained_lib, &lib, &nlib);
    var w: [33]f64 = undefined;
    const m = ui.solveOneTarget(X, grid, &lib, &nlib, Y, phiTgt, w[0..], SilentOut{}, true);
    const cov = ui.measureCoverage(X, grid, lib[0..nlib], Y, w[0..]);
    return .{ .solved = m.solved, .cov = cov, .lib = lib, .nlib = nlib };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    const errw = std.io.getStdErr().writer();

    var smoke = false;
    var args = std.process.args();
    _ = args.skip();
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--smoke")) smoke = true;
    }

    const pool_seeds: []const u64 = if (smoke) POOL_SEEDS[0..1] else POOL_SEEDS[0..];
    const target_idx: []const usize = if (smoke) TARGET_IDX[0..2] else TARGET_IDX[0..];
    const n_ladder: []const usize = if (smoke) N_LADDER_FULL[0..3] else N_LADDER_FULL[0..];

    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/breadth_scaling_2026_07_10.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("pool_seed,target,family,arm,N,reached,n_certified,novel,distinct_closures,total_evals,cov_before,baseline_solved\n", .{});

    try out.print("=== BREADTH SCALING: reach vs N diverse parallel proposers (Battery-C out-of-closure set) ===\n", .{});
    if (smoke) try out.print("(--smoke mode: reduced seeds/targets/N for timing calibration)\n", .{});

    var timer = try std.time.Timer.start();

    for (pool_seeds) |pool_seed| {
        const prep = try ie.prepareBlindBatterySeed(alloc, pool_seed, SilentOut{});
        const ctx = prep.ctx;

        for (target_idx) |ti| {
            const tgt = bc.BATTERY_C[ti];
            const Yb = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| Yb[s] = bc.labelTarget(ctx.grid[s], tgt);

            const base = runBaseline(ctx.X, ctx.grid, ctx.phiTgt, prep.trained_lib, Yb);
            const target_tag = splitMix64(@as(u64, @intCast(ti)) *% 0xD6E8FEB86659FD93);

            try errw.print("[seed 0x{X:0>16} target {s}] baseline solved={} cov={d:.4}  ({d:.1}s elapsed)\n", .{
                pool_seed, tgt.name, base.solved, base.cov, @as(f64, @floatFromInt(timer.read())) / 1e9,
            });

            if (base.solved) {
                for ([_]Arm{ .diverse, .identical }) |arm| {
                    for (n_ladder) |n| {
                        try cw.print("0x{X:0>16},\"{s}\",{s},{s},{d},1,0,0,0,0,{d:.4},1\n", .{
                            pool_seed, tgt.name, tgt.family, @tagName(arm), n, base.cov,
                        });
                    }
                }
                try cw.print("0x{X:0>16},\"{s}\",{s},baseline,0,1,,,,,{d:.4},1\n", .{ pool_seed, tgt.name, tgt.family, base.cov });
                continue;
            }

            try cw.print("0x{X:0>16},\"{s}\",{s},baseline,0,0,,,,,{d:.4},0\n", .{ pool_seed, tgt.name, tgt.family, base.cov });

            const lib_slice = base.lib[0..base.nlib];

            for ([_]Arm{ .diverse, .identical }) |arm| {
                var results: [N_MAX]ProposerResult = undefined;
                for (0..N_MAX) |idx| {
                    const cfg = cfgFor(arm, idx, pool_seed, target_tag);
                    const fb = familyBudget(cfg.family);
                    results[idx] = runProposer(ctx.X, ctx.grid, lib_slice, Yb, base.cov, cfg, fb);
                }
                for (n_ladder) |n| {
                    const ps = prefixStats(results[0..], n);
                    try cw.print("0x{X:0>16},\"{s}\",{s},{s},{d},{d},{d},{d},{d},{d},{d:.4},0\n", .{
                        pool_seed, tgt.name, tgt.family, @tagName(arm), n,
                        @intFromBool(ps.reached), ps.n_certified, ps.novel, ps.distinct_closures, ps.total_evals, base.cov,
                    });
                }
                const full = prefixStats(results[0..], N_MAX);
                try out.print("  [{s}] N=32: reached={} certified={d}/32 novel={d} distinct_closures={d} evals={d}\n", .{
                    @tagName(arm), full.reached, full.n_certified, full.novel, full.distinct_closures, full.total_evals,
                });
            }

            // Exhaustive single-attempt depth reference on the SAME target/seed.
            const dcfg = cfgFor(.exhaustive_depth, 0, pool_seed, target_tag);
            const dres = runProposer(ctx.X, ctx.grid, lib_slice, Yb, base.cov, dcfg, EXH_BUDGET);
            try cw.print("0x{X:0>16},\"{s}\",{s},exhaustive_depth,1,{d},{d},{d},{d},{d},{d:.4},0\n", .{
                pool_seed, tgt.name, tgt.family, @intFromBool(dres.certified), @intFromBool(dres.certified),
                @intFromBool(dres.certified and dres.novel), if (dres.certified) @as(usize, 1) else 0, dres.evals, base.cov,
            });
            try out.print("  [exhaustive_depth] certified={} evals={d} cov {d:.4}->{d:.4} r2={d:.3}  ({d:.1}s elapsed)\n\n", .{
                dres.certified, dres.evals, base.cov, dres.cov_after, dres.r2, @as(f64, @floatFromInt(timer.read())) / 1e9,
            });
        }
    }

    try out.print("Total wall: {d:.1}s\n", .{@as(f64, @floatFromInt(timer.read())) / 1e9});
    try out.print("CSV: {s}\n", .{csv_path});
}
