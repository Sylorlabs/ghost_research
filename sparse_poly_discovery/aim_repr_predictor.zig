//! Research round 2026-07-11 (Round E), experiment E5 — the arc's capstone:
//! reach ~ f(REPRESENTABILITY, AIM-QUALITY, DIVERSITY, BUDGET). Which factor
//! dominates, does representability x aim show a PHASE BOUNDARY (aim only
//! pays once representability is satisfied), and where does the proposed law
//! fail (falsification)?
//!
//! This is a NEW, standalone, self-contained file. No existing file is
//! imported or modified. It reuses the DESIGN (not the code) of
//! `diversity_predictor.zig` (round-d exp 6: 6 families / 9-target battery /
//! train-val-test discipline / OLS+partial-correlation machinery) and the
//! full-enumeration "Bayes ceiling" method of `tier8_reach_gap.md` /
//! `breadth_scaling.md` (round-c/d: the best accuracy over the WHOLE
//! hypothesis space is a descriptive upper bound on what any budget-limited
//! search in that space could ever certify) -- read only, duplicated fresh
//! here per the round's "new files only" constraint.
//!
//! ============================ THE FOUR METRICS ==============================
//!
//! World: identical to diversity_predictor.zig -- 8-cell grid, values in
//! [0,6), 800/400/300 TRAIN/VAL/TEST split (VAL selects, TEST reports once).
//! Six families (closures) mono/pair/walsh/spectral/worldmod/cmp, same
//! definitions. Nine targets: 0-5 each has one "home" family; 6-7 are
//! CONJUNCTIONS of two heterogeneous families' native predicates (only
//! cross-family combination reaches them); 8 is the falsification target,
//! outside every family's span and every pairwise combination BY
//! CONSTRUCTION (a quadratic-residue-style relation).
//!
//! (1) REPRESENTABILITY(target, pool-family-set F) -- a CONTINUOUS,
//!     BUDGET-INDEPENDENT score in [0,1]. Precomputed once as a full-
//!     enumeration ceiling: for every family, the best held-out TEST accuracy
//!     over its ENTIRE candidate space (all bases) against the target; for
//!     every pair of families, the best TEST accuracy of any AND/OR/XOR
//!     combination of their top-8 (by TEST accuracy) candidates. This IS the
//!     Bayes-ceiling method used in tier8_reach_gap.md / breadth_scaling.md
//!     ("the best accuracy over all 255 masks x 6 lenses is the family-level
//!     impossibility bound") -- a DESCRIPTIVE property of the family/target
//!     pair, not a search claim, so it is computed directly against TEST (no
//!     leakage concern: nothing is ever "certified" from this number, it only
//!     describes what the closure CAN express in principle). representability
//!     = rescale(best_ceiling_accuracy_over_F), rescale(a) = clamp((a-0.5)*2,
//!     0, 1) so chance=0, perfect=1. Because targets 6/7 are conjunctions,
//!     representability is naturally CONTINUOUS: with only one of the two
//!     required families present, the single-family ceiling still partially
//!     predicts the conjunction (an intermediate score); with both present,
//!     the pair ceiling reaches ~1.0.
//!
//! (2) AIM-QUALITY(proposer, target) -- a CONTROLLED knob A in
//!     {0, 0.25, 0.5, 0.75, 1.0}, operationalized as a real (non-circular)
//!     budget-routing mechanism, not asserted: each active family f gets a
//!     "match score" z_f = CEIL_SINGLE_VAL[f][target] (that family's best
//!     VAL -- never TEST -- accuracy against the target, a genuine
//!     correlation-strength signal, exactly the round brief's suggested
//!     definition). z is min-max normalized within the active set, mixed with
//!     independent per-repeat noise: s_f = A*z_f_norm + (1-A)*noise_f, then
//!     routed via softmax(s/TEMP) into per-family budget shares of E_total.
//!     A=0 -> budget allocation carries no information about which family
//!     actually correlates with the target (pure noise routing). A=1 ->
//!     budget concentrates on the family (or families) whose VAL-measured
//!     correlation is strongest. Critically, THIS MECHANISM DOES NOT KNOW THE
//!     TARGET'S TRUE HOME FAMILY -- it only sees the VAL-accuracy signal,
//!     which is only strong when the true family happens to be present. This
//!     is what allows the representability x aim interaction to be an
//!     EMERGENT result of the sweep rather than a built-in assumption.
//!
//! (3) DIVERSITY(pool) = D = count of distinct families active in the pool,
//!     1..6 (identical definition to diversity_predictor.zig).
//!
//! (4) BUDGET = evals_actual, the realized (post-cap) total candidate
//!     evaluations spent across all members for one (pool, target, aim,
//!     E_total, repeat) cell.
//!
//! REACH (dependent variable): best_test = max(best single member TEST
//! accuracy, best pairwise AND/OR/XOR combo TEST accuracy) -- selected by VAL
//! among the pool's BUDGET-LIMITED (aim-routed, randomly sampled) candidates,
//! reported on TEST exactly once for the already-decided winner (identical
//! discipline to diversity_predictor.zig's leakage fix, D6 section 4.1).
//! reach_score = rescale(best_test) (same units as representability, so
//! "reach approaching its representability ceiling" is a direct, comparable
//! statement). certified_solve = best_test >= SOLVE_THRESH (0.97), the
//! binary "reach" concept used throughout the round.
//!
//! IMPORTANT DESIGN DIFFERENCE FROM diversity_predictor.zig: there, a pool's
//! member candidate sets were sampled ONCE per pool and reused unchanged
//! across all 9 targets (target-agnostic proposers). HERE, because aim is
//! explicitly a per-(proposer,target) property (round brief's own
//! definition), each (pool, target, aim, E_total, repeat) cell re-routes and
//! re-samples its members' candidates for THAT target. This is intentional,
//! not an oversight -- it is what makes "aim" measurable at all.
//!
//! Build: zig build-exe aim_repr_predictor.zig -O ReleaseFast   (zig 0.14.1)
//! Run:   ./aim_repr_predictor > ../results/aim_repr_predictor_2026_07_11.csv
//!        ./aim_repr_predictor --smoke   (small sweep, timing check)
//! Single-threaded, CSV on stdout, diagnostics/regression/tables on stderr.

const std = @import("std");

// ---------------------------------------------------------------- constants
const NCELLS: usize = 8;
const MVAL: i64 = 6;
const NTRAIN: usize = 800;
const NVAL: usize = 400;
const NTEST: usize = 300;
const SOLVE_THRESH: f64 = 0.97;
const NTARGETS: usize = 9;
const NFAM: usize = 6;
const MAX_BASES: usize = 92; // max over familyNumBases(.)
const MEMBERS_PER_FAM: usize = 4;
const MAX_D: usize = 6;
const MAX_MEMBERS: usize = MEMBERS_PER_FAM * MAX_D; // 24
const TOPK_PAIR: usize = 8;
const TEMP: f64 = 0.15;
const WORLD_SEED: u64 = 0xE5E5_ACC0_FFEE_2026;

const AIM_LIST_FULL = [_]f64{ 0.0, 0.25, 0.5, 0.75, 1.0 };
const EVALS_LIST_FULL = [_]usize{ 60, 240, 960 };
const R_DRAWS_FULL: usize = 4;
const REPEATS_INNER_FULL: usize = 2;

const Grid = [NCELLS]i64;

// -------------------------------------------------------------- family defs
// (identical definitions to sparse_poly_discovery/diversity_predictor.zig,
// duplicated here per the round's "new files only" constraint -- see that
// file's comments for the closure argument behind each family.)
const FamilyId = enum(u8) { mono, pair, walsh, spectral, worldmod, cmp };
const FAMILY_ORDER = [_]FamilyId{ .mono, .pair, .walsh, .spectral, .worldmod, .cmp };

fn familyNumBases(f: FamilyId) usize {
    return switch (f) {
        .mono => 92,
        .pair => 28,
        .walsh => 92,
        .spectral => 64,
        .worldmod => 39,
        .cmp => 5,
    };
}

fn familyName(f: FamilyId) []const u8 {
    return switch (f) {
        .mono => "mono",
        .pair => "pair",
        .walsh => "walsh",
        .spectral => "spectral",
        .worldmod => "worldmod",
        .cmp => "cmp",
    };
}

const pair_idx: [28][2]usize = blk: {
    var arr: [28][2]usize = undefined;
    var n: usize = 0;
    for (0..NCELLS) |i| {
        for (i + 1..NCELLS) |j| {
            arr[n] = .{ i, j };
            n += 1;
        }
    }
    break :blk arr;
};

const mono_masks: [92]usize = blk: {
    @setEvalBranchQuota(10000);
    var arr: [92]usize = undefined;
    var n: usize = 0;
    for (1..256) |m| {
        var x = m;
        var pc: usize = 0;
        while (x != 0) {
            pc += x & 1;
            x >>= 1;
        }
        if (pc <= 3) {
            arr[n] = m;
            n += 1;
        }
    }
    break :blk arr;
};

const cmp_low: [6][2]usize = blk: {
    var arr: [6][2]usize = undefined;
    var n: usize = 0;
    for (0..4) |i| {
        for (i + 1..4) |j| {
            arr[n] = .{ i, j };
            n += 1;
        }
    }
    break :blk arr;
};

const cmp_high: [6][2]usize = blk: {
    var arr: [6][2]usize = undefined;
    var n: usize = 0;
    for (4..8) |i| {
        for (i + 1..8) |j| {
            arr[n] = .{ i, j };
            n += 1;
        }
    }
    break :blk arr;
};

const cmp_cross: [16][2]usize = blk: {
    var arr: [16][2]usize = undefined;
    var n: usize = 0;
    for (0..4) |i| {
        for (4..8) |j| {
            arr[n] = .{ i, j };
            n += 1;
        }
    }
    break :blk arr;
};

const cmp_adj: [7][2]usize = blk: {
    var arr: [7][2]usize = undefined;
    for (0..7) |i| arr[i] = .{ i, i + 1 };
    break :blk arr;
};

fn cmpCount(pairset_id: usize, g: Grid) i64 {
    var cnt: i64 = 0;
    switch (pairset_id) {
        0 => for (pair_idx) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        1 => for (cmp_low) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        2 => for (cmp_high) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        3 => for (cmp_cross) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        4 => for (cmp_adj) |p| {
            if (g[p[0]] > g[p[1]]) cnt += 1;
        },
        else => unreachable,
    }
    return cnt;
}

fn rawValue(f: FamilyId, base_id: usize, g: Grid) f64 {
    switch (f) {
        .mono => {
            const mask = mono_masks[base_id];
            var prod: i64 = 1;
            for (0..NCELLS) |i| {
                if ((mask >> @as(u3, @intCast(i))) & 1 == 1) prod *= g[i];
            }
            return @floatFromInt(prod);
        },
        .pair => {
            const p = pair_idx[base_id];
            return @floatFromInt(g[p[0]] - g[p[1]]);
        },
        .walsh => {
            const mask: usize = mono_masks[base_id];
            var p: i64 = 0;
            for (0..NCELLS) |i| {
                if ((mask >> @as(u6, @intCast(i))) & 1 == 1) p ^= (g[i] & 1);
            }
            return @floatFromInt(p);
        },
        .spectral => {
            const k: f64 = @floatFromInt(base_id + 1);
            var s: i64 = 0;
            for (0..NCELLS) |i| s += g[i];
            const omega = k * std.math.pi / 32.0;
            return @cos(omega * @as(f64, @floatFromInt(s)));
        },
        .worldmod => {
            const k: i64 = @intCast(base_id + 2);
            var s: i64 = 0;
            for (0..NCELLS) |i| s += g[i];
            return @floatFromInt(@mod(s, k));
        },
        .cmp => {
            const cnt = cmpCount(base_id, g);
            return @floatFromInt(@mod(cnt, 2));
        },
    }
}

fn thresholdsFor(f: FamilyId, base_id: usize, buf: []f64) []f64 {
    switch (f) {
        .mono => {
            var n: usize = 0;
            var t: f64 = 0.5;
            while (t < 126.0) : (t += 4.0) {
                buf[n] = t;
                n += 1;
            }
            return buf[0..n];
        },
        .pair => {
            buf[0] = 0.5;
            return buf[0..1];
        },
        .walsh => {
            buf[0] = 0.5;
            return buf[0..1];
        },
        .spectral => {
            var n: usize = 0;
            var t: f64 = -0.95;
            while (t < 1.0) : (t += 0.1) {
                buf[n] = t;
                n += 1;
            }
            return buf[0..n];
        },
        .worldmod => {
            const k: f64 = @floatFromInt(base_id + 2);
            var n: usize = 0;
            var t: f64 = 0.5;
            while (t < k - 0.499) : (t += 1.0) {
                buf[n] = t;
                n += 1;
            }
            return buf[0..n];
        },
        .cmp => {
            buf[0] = 0.5;
            return buf[0..1];
        },
    }
}

const Rule = struct { threshold: f64, negate: bool };
const FitResult = struct { rule: Rule, train_acc: f64 };

// -------------------------------------------------------------- world state
var TRAIN_GRIDS: [NTRAIN]Grid = undefined;
var VAL_GRIDS: [NVAL]Grid = undefined;
var TEST_GRIDS: [NTEST]Grid = undefined;
var TRAIN_LABELS: [NTARGETS][NTRAIN]bool = undefined;
var VAL_LABELS: [NTARGETS][NVAL]bool = undefined;
var TEST_LABELS: [NTARGETS][NTEST]bool = undefined;

fn genGrid(r: std.Random) Grid {
    var g: Grid = undefined;
    for (0..NCELLS) |i| g[i] = r.intRangeLessThan(i64, 0, MVAL);
    return g;
}

fn sumCells(g: Grid) i64 {
    var s: i64 = 0;
    for (0..NCELLS) |i| s += g[i];
    return s;
}

/// Identical 9-target battery to diversity_predictor.zig (targets 0-5: one
/// home family each; 6-7: cross-family conjunctions; 8: falsification,
/// outside every family and every pairwise combination by construction).
fn targetLabel(t: usize, g: Grid) bool {
    switch (t) {
        0 => return (g[0] * g[1] * g[2]) >= 30, // home: mono
        1 => return g[3] > g[5], // home: pair
        2 => {
            var p: i64 = 0;
            p ^= g[0] & 1;
            p ^= g[2] & 1;
            p ^= g[4] & 1;
            return p == 1;
        },
        3 => {
            const s = sumCells(g);
            const val = @cos(@as(f64, @floatFromInt(s)) * (std.math.pi / 6.0));
            return val >= 0;
        },
        4 => return @mod(sumCells(g), 7) == 0, // home: worldmod
        5 => {
            var cnt: i64 = 0;
            for (pair_idx) |p| {
                if (g[p[0]] > g[p[1]]) cnt += 1;
            }
            return @mod(cnt, 2) == 1;
        },
        6 => { // conjunction: walsh-pair-parity AND worldmod
            const a = (g[1] & 1) == (g[7] & 1);
            const b = @mod(sumCells(g), 5) == 0;
            return a and b;
        },
        7 => { // conjunction: pair-order AND cmp-cross-parity
            const a = g[2] > g[4];
            var cnt: i64 = 0;
            for (cmp_cross) |p| {
                if (g[p[0]] > g[p[1]]) cnt += 1;
            }
            const b = @mod(cnt, 2) == 0;
            return a and b;
        },
        8 => { // falsification: outside every family's closure by construction
            const val = @mod(g[0] * g[0] + g[1] * g[1] - g[2] * g[3], 13);
            return val == 5;
        },
        else => unreachable,
    }
}

fn requiredFamiliesOf(t: usize, buf: []FamilyId) []FamilyId {
    switch (t) {
        0 => {
            buf[0] = .mono;
            return buf[0..1];
        },
        1 => {
            buf[0] = .pair;
            return buf[0..1];
        },
        2 => {
            buf[0] = .walsh;
            return buf[0..1];
        },
        3 => {
            buf[0] = .spectral;
            return buf[0..1];
        },
        4 => {
            buf[0] = .worldmod;
            return buf[0..1];
        },
        5 => {
            buf[0] = .cmp;
            return buf[0..1];
        },
        6 => {
            buf[0] = .walsh;
            buf[1] = .worldmod;
            return buf[0..2];
        },
        7 => {
            buf[0] = .pair;
            buf[1] = .cmp;
            return buf[0..2];
        },
        8 => return buf[0..0], // impossible: no family set ever suffices
        else => unreachable,
    }
}

fn hasAllRequired(F: []const FamilyId, t: usize) bool {
    if (t == 8) return false; // special-cased: impossible regardless of F
    var buf: [2]FamilyId = undefined;
    const req = requiredFamiliesOf(t, &buf);
    for (req) |r| {
        var found = false;
        for (F) |f| {
            if (f == r) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn buildWorld(seed: u64) void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    for (0..NTRAIN) |i| TRAIN_GRIDS[i] = genGrid(rng);
    for (0..NVAL) |i| VAL_GRIDS[i] = genGrid(rng);
    for (0..NTEST) |i| TEST_GRIDS[i] = genGrid(rng);
    for (0..NTARGETS) |t| {
        for (0..NTRAIN) |i| TRAIN_LABELS[t][i] = targetLabel(t, TRAIN_GRIDS[i]);
        for (0..NVAL) |i| VAL_LABELS[t][i] = targetLabel(t, VAL_GRIDS[i]);
        for (0..NTEST) |i| TEST_LABELS[t][i] = targetLabel(t, TEST_GRIDS[i]);
    }
}

fn fitAndEval(f: FamilyId, base_id: usize, target: usize) FitResult {
    var raws: [NTRAIN]f64 = undefined;
    for (0..NTRAIN) |i| raws[i] = rawValue(f, base_id, TRAIN_GRIDS[i]);
    var buf: [48]f64 = undefined;
    const th = thresholdsFor(f, base_id, &buf);
    var best_acc: f64 = -1.0;
    var best_rule: Rule = .{ .threshold = th[0], .negate = false };
    for (th) |t| {
        var neg_i: usize = 0;
        while (neg_i < 2) : (neg_i += 1) {
            const neg = neg_i == 1;
            var correct: usize = 0;
            for (0..NTRAIN) |i| {
                const pred = (raws[i] >= t) != neg;
                if (pred == TRAIN_LABELS[target][i]) correct += 1;
            }
            const acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTRAIN));
            if (acc > best_acc) {
                best_acc = acc;
                best_rule = .{ .threshold = t, .negate = neg };
            }
        }
    }
    return .{ .rule = best_rule, .train_acc = best_acc };
}

fn valAccOf(f: FamilyId, base_id: usize, rule: Rule, target: usize) f64 {
    var correct: usize = 0;
    for (0..NVAL) |i| {
        const raw = rawValue(f, base_id, VAL_GRIDS[i]);
        const pred = (raw >= rule.threshold) != rule.negate;
        if (pred == VAL_LABELS[target][i]) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NVAL));
}

fn testAccOf(f: FamilyId, base_id: usize, rule: Rule, target: usize) f64 {
    var correct: usize = 0;
    for (0..NTEST) |i| {
        const raw = rawValue(f, base_id, TEST_GRIDS[i]);
        const pred = (raw >= rule.threshold) != rule.negate;
        if (pred == TEST_LABELS[target][i]) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
}

fn mixSeed(a: u64, b: u64, c: u64, d: u64, e: u64, f: u64) u64 {
    var buf: [48]u8 = undefined;
    std.mem.writeInt(u64, buf[0..8], a, .little);
    std.mem.writeInt(u64, buf[8..16], b, .little);
    std.mem.writeInt(u64, buf[16..24], c, .little);
    std.mem.writeInt(u64, buf[24..32], d, .little);
    std.mem.writeInt(u64, buf[32..40], e, .little);
    std.mem.writeInt(u64, buf[40..48], f, .little);
    return std.hash.Wyhash.hash(0x1234_5678, &buf);
}

fn rescale(acc: f64) f64 {
    const v = (acc - 0.5) * 2.0;
    return @max(0.0, @min(1.0, v));
}

// ------------------------------------------------------- full-enum caches
// Rule/VAL-accuracy/TEST-accuracy and full VAL/TEST prediction vectors for
// EVERY (family, base, target) triple, computed ONCE at startup and reused
// by both the representability ceiling and the budget-limited pool search
// (candidate SELECTION within a member's sampled subset is a lookup, not a
// recomputation -- this is what keeps the whole sweep fast).
var VAL_ACC: [NFAM][MAX_BASES][NTARGETS]f64 = undefined;
var TEST_ACC: [NFAM][MAX_BASES][NTARGETS]f64 = undefined;
var VAL_PRED: [NFAM][MAX_BASES][NTARGETS][NVAL]bool = undefined;
var TEST_PRED: [NFAM][MAX_BASES][NTARGETS][NTEST]bool = undefined;

fn buildFullCache() void {
    for (FAMILY_ORDER) |fam| {
        const fi = @intFromEnum(fam);
        const nb = familyNumBases(fam);
        for (0..nb) |b| {
            for (0..NTARGETS) |t| {
                const fit = fitAndEval(fam, b, t);
                VAL_ACC[fi][b][t] = valAccOf(fam, b, fit.rule, t);
                TEST_ACC[fi][b][t] = testAccOf(fam, b, fit.rule, t);
                for (0..NVAL) |idx| {
                    const raw = rawValue(fam, b, VAL_GRIDS[idx]);
                    VAL_PRED[fi][b][t][idx] = (raw >= fit.rule.threshold) != fit.rule.negate;
                }
                for (0..NTEST) |idx| {
                    const raw = rawValue(fam, b, TEST_GRIDS[idx]);
                    TEST_PRED[fi][b][t][idx] = (raw >= fit.rule.threshold) != fit.rule.negate;
                }
            }
        }
    }
}

// --------------------------------------------------- representability ceilings
var CEIL_SINGLE_VAL: [NFAM][NTARGETS]f64 = undefined; // used by AIM routing (VAL only)
var CEIL_SINGLE_TEST: [NFAM][NTARGETS]f64 = undefined; // used by REPRESENTABILITY (TEST, descriptive ceiling)
var CEIL_PAIR_TEST: [NFAM][NFAM][NTARGETS]f64 = undefined; // [min(fi,fj)][max(fi,fj)][t]

fn topKBasesByTestAcc(fam: FamilyId, t: usize, comptime K: usize, out: *[K]usize) usize {
    const fi = @intFromEnum(fam);
    const nb = familyNumBases(fam);
    var vals: [K]f64 = [_]f64{-1.0} ** K;
    var n: usize = 0;
    for (0..nb) |b| {
        const v = TEST_ACC[fi][b][t];
        if (n < K or v > vals[K - 1]) {
            var pos = if (n < K) n else K - 1;
            if (n < K) n += 1;
            while (pos > 0 and vals[pos - 1] < v) {
                vals[pos] = vals[pos - 1];
                out[pos] = out[pos - 1];
                pos -= 1;
            }
            vals[pos] = v;
            out[pos] = b;
        }
    }
    return n;
}

fn buildCeilings() void {
    // CEIL_SINGLE_VAL: pure single-base VAL accuracy (used only as the AIM
    // routing heuristic -- a rough "does this family look correlated" signal,
    // not a fairness-sensitive claim, so it is deliberately left simple).
    for (FAMILY_ORDER) |fam| {
        const fi = @intFromEnum(fam);
        const nb = familyNumBases(fam);
        for (0..NTARGETS) |t| {
            var best_val: f64 = 0.5;
            for (0..nb) |b| {
                if (VAL_ACC[fi][b][t] > best_val) best_val = VAL_ACC[fi][b][t];
            }
            CEIL_SINGLE_VAL[fi][t] = best_val;
        }
    }
    // CEIL_SINGLE_TEST: the REPRESENTABILITY ceiling for one family ALONE.
    // MUST include same-family internal pairwise AND/OR/XOR combos, not just
    // the best single base -- otherwise this is the exact fairness bug
    // diversity_predictor.md section 4.2 already found and fixed ("the solo
    // baseline must get the same combo capability as the pool"): the actual
    // pool search (runCell) freely combines any two members regardless of
    // whether they share a family, so a D=1 pool (e.g. cmp alone) can reach a
    // same-family combo the single-base-only ceiling never checked, making
    // measured reach appear to EXCEED representability -- impossible for a
    // true ceiling. Fixed here by giving the "alone" ceiling the identical
    // top-K same-family combo search before folding pairs across families in.
    for (FAMILY_ORDER) |fam| {
        const fi = @intFromEnum(fam);
        const nb = familyNumBases(fam);
        for (0..NTARGETS) |t| {
            var best_here: f64 = 0.5;
            for (0..nb) |b| {
                if (TEST_ACC[fi][b][t] > best_here) best_here = TEST_ACC[fi][b][t];
            }
            var top_k: [TOPK_PAIR]usize = undefined;
            const nk = topKBasesByTestAcc(fam, t, TOPK_PAIR, &top_k);
            if (nk >= 2) {
                for (0..nk) |ii| {
                    for (ii + 1..nk) |jj| {
                        const ba = top_k[ii];
                        const bb = top_k[jj];
                        var c_and: usize = 0;
                        var c_or: usize = 0;
                        var c_xor: usize = 0;
                        for (0..NTEST) |idx| {
                            const pa = TEST_PRED[fi][ba][t][idx];
                            const pb = TEST_PRED[fi][bb][t][idx];
                            const lab = TEST_LABELS[t][idx];
                            if ((pa and pb) == lab) c_and += 1;
                            if ((pa or pb) == lab) c_or += 1;
                            if ((pa != pb) == lab) c_xor += 1;
                        }
                        const acc_and = @as(f64, @floatFromInt(c_and)) / @as(f64, @floatFromInt(NTEST));
                        const acc_or = @as(f64, @floatFromInt(c_or)) / @as(f64, @floatFromInt(NTEST));
                        const acc_xor = @as(f64, @floatFromInt(c_xor)) / @as(f64, @floatFromInt(NTEST));
                        best_here = @max(best_here, @max(acc_and, @max(acc_or, acc_xor)));
                    }
                }
            }
            CEIL_SINGLE_TEST[fi][t] = best_here;
        }
    }
    for (0..NFAM) |fi| {
        for (fi + 1..NFAM) |fj| {
            const fam_i: FamilyId = @enumFromInt(fi);
            const fam_j: FamilyId = @enumFromInt(fj);
            for (0..NTARGETS) |t| {
                var top_i: [TOPK_PAIR]usize = undefined;
                var top_j: [TOPK_PAIR]usize = undefined;
                const ni = topKBasesByTestAcc(fam_i, t, TOPK_PAIR, &top_i);
                const nj = topKBasesByTestAcc(fam_j, t, TOPK_PAIR, &top_j);
                var best: f64 = 0.5;
                for (0..ni) |ii| {
                    for (0..nj) |jj| {
                        const ba = top_i[ii];
                        const bb = top_j[jj];
                        var c_and: usize = 0;
                        var c_or: usize = 0;
                        var c_xor: usize = 0;
                        for (0..NTEST) |idx| {
                            const pa = TEST_PRED[fi][ba][t][idx];
                            const pb = TEST_PRED[fj][bb][t][idx];
                            const lab = TEST_LABELS[t][idx];
                            if ((pa and pb) == lab) c_and += 1;
                            if ((pa or pb) == lab) c_or += 1;
                            if ((pa != pb) == lab) c_xor += 1;
                        }
                        const acc_and = @as(f64, @floatFromInt(c_and)) / @as(f64, @floatFromInt(NTEST));
                        const acc_or = @as(f64, @floatFromInt(c_or)) / @as(f64, @floatFromInt(NTEST));
                        const acc_xor = @as(f64, @floatFromInt(c_xor)) / @as(f64, @floatFromInt(NTEST));
                        best = @max(best, @max(acc_and, @max(acc_or, acc_xor)));
                    }
                }
                CEIL_PAIR_TEST[fi][fj][t] = best;
            }
        }
    }
}

fn reprScore(F: []const FamilyId, target: usize) f64 {
    var best: f64 = 0.5;
    for (F) |fam| {
        const v = CEIL_SINGLE_TEST[@intFromEnum(fam)][target];
        if (v > best) best = v;
    }
    for (0..F.len) |i| {
        for (i + 1..F.len) |j| {
            const fi = @intFromEnum(F[i]);
            const fj = @intFromEnum(F[j]);
            const lo = @min(fi, fj);
            const hi = @max(fi, fj);
            const v = CEIL_PAIR_TEST[lo][hi][target];
            if (v > best) best = v;
        }
    }
    return rescale(best);
}

// ------------------------------------------------------------ aim routing
fn routeBudgets(F: []const FamilyId, target: usize, aim: f64, e_total: usize, rng: std.Random, out_budget: []usize) void {
    const d = F.len;
    var z: [MAX_D]f64 = undefined;
    var minv: f64 = 1e18;
    var maxv: f64 = -1e18;
    for (F, 0..) |fam, i| {
        const m = CEIL_SINGLE_VAL[@intFromEnum(fam)][target];
        z[i] = m;
        minv = @min(minv, m);
        maxv = @max(maxv, m);
    }
    const range = @max(maxv - minv, 1e-9);
    var s: [MAX_D]f64 = undefined;
    for (0..d) |i| {
        const zn = (z[i] - minv) / range;
        const noise = rng.float(f64);
        s[i] = aim * zn + (1.0 - aim) * noise;
    }
    var maxs: f64 = -1e18;
    for (0..d) |i| maxs = @max(maxs, s[i]);
    var w: [MAX_D]f64 = undefined;
    var wsum: f64 = 0;
    for (0..d) |i| {
        w[i] = @exp((s[i] - maxs) / TEMP);
        wsum += w[i];
    }
    for (0..d) |i| {
        out_budget[i] = @intFromFloat(@round(w[i] / wsum * @as(f64, @floatFromInt(e_total))));
    }
}

// ------------------------------------------------------------ pool cell run
const MemberChoice = struct {
    fam: FamilyId,
    base: usize,
    test_acc: f64,
};

const CellResult = struct {
    best_test: f64,
    evals_actual: usize,
};

fn runCell(F: []const FamilyId, target: usize, aim: f64, e_total: usize, rng: std.Random) CellResult {
    const d = F.len;
    var family_budget: [MAX_D]usize = undefined;
    routeBudgets(F, target, aim, e_total, rng, family_budget[0..d]);

    var members: [MAX_MEMBERS]MemberChoice = undefined;
    var nmembers: usize = 0;
    var evals_actual: usize = 0;

    for (F, 0..) |fam, fi| {
        const nb = familyNumBases(fam);
        const per_member = family_budget[fi] / MEMBERS_PER_FAM;
        var pool_idx: [MAX_BASES]usize = undefined;
        for (0..nb) |ii| pool_idx[ii] = ii;
        for (0..MEMBERS_PER_FAM) |_| {
            const k = @min(per_member, nb);
            rng.shuffle(usize, pool_idx[0..nb]);
            var best_local_val: f64 = -1.0;
            var best_base: usize = pool_idx[0];
            for (0..k) |ii| {
                const b = pool_idx[ii];
                const va = VAL_ACC[@intFromEnum(fam)][b][target];
                if (va > best_local_val) {
                    best_local_val = va;
                    best_base = b;
                }
            }
            const tacc = if (k > 0) TEST_ACC[@intFromEnum(fam)][best_base][target] else 0.5;
            members[nmembers] = .{ .fam = fam, .base = best_base, .test_acc = tacc };
            nmembers += 1;
            evals_actual += k;
        }
    }

    var best_single: f64 = 0;
    for (0..nmembers) |i| best_single = @max(best_single, members[i].test_acc);

    var best_combo_val: f64 = -1.0;
    var best_kind: u8 = 0;
    var best_a: usize = 0;
    var best_b: usize = 0;
    if (nmembers >= 2) {
        for (0..nmembers) |a| {
            for (a + 1..nmembers) |b| {
                const ma = members[a];
                const mb = members[b];
                const fia = @intFromEnum(ma.fam);
                const fib = @intFromEnum(mb.fam);
                var c_and: usize = 0;
                var c_or: usize = 0;
                var c_xor: usize = 0;
                for (0..NVAL) |idx| {
                    const pa = VAL_PRED[fia][ma.base][target][idx];
                    const pb = VAL_PRED[fib][mb.base][target][idx];
                    const lab = VAL_LABELS[target][idx];
                    if ((pa and pb) == lab) c_and += 1;
                    if ((pa or pb) == lab) c_or += 1;
                    if ((pa != pb) == lab) c_xor += 1;
                }
                const acc_and = @as(f64, @floatFromInt(c_and)) / @as(f64, @floatFromInt(NVAL));
                const acc_or = @as(f64, @floatFromInt(c_or)) / @as(f64, @floatFromInt(NVAL));
                const acc_xor = @as(f64, @floatFromInt(c_xor)) / @as(f64, @floatFromInt(NVAL));
                if (acc_and > best_combo_val) {
                    best_combo_val = acc_and;
                    best_kind = 0;
                    best_a = a;
                    best_b = b;
                }
                if (acc_or > best_combo_val) {
                    best_combo_val = acc_or;
                    best_kind = 1;
                    best_a = a;
                    best_b = b;
                }
                if (acc_xor > best_combo_val) {
                    best_combo_val = acc_xor;
                    best_kind = 2;
                    best_a = a;
                    best_b = b;
                }
            }
        }
    }

    var best_combo_test: f64 = 0;
    if (nmembers >= 2) {
        const ma = members[best_a];
        const mb = members[best_b];
        const fia = @intFromEnum(ma.fam);
        const fib = @intFromEnum(mb.fam);
        var correct: usize = 0;
        for (0..NTEST) |idx| {
            const pa = TEST_PRED[fia][ma.base][target][idx];
            const pb = TEST_PRED[fib][mb.base][target][idx];
            const lab = TEST_LABELS[target][idx];
            const pred = switch (best_kind) {
                0 => pa and pb,
                1 => pa or pb,
                2 => pa != pb,
                else => unreachable,
            };
            if (pred == lab) correct += 1;
        }
        best_combo_test = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
    }

    return .{
        .best_test = @max(best_single, best_combo_test),
        .evals_actual = evals_actual,
    };
}

// --------------------------------------------------------------- statistics
fn mean(xs: []const f64) f64 {
    var s: f64 = 0;
    for (xs) |x| s += x;
    return s / @as(f64, @floatFromInt(xs.len));
}

fn pearson(xs: []const f64, ys: []const f64) f64 {
    const mx = mean(xs);
    const my = mean(ys);
    var sxy: f64 = 0;
    var sxx: f64 = 0;
    var syy: f64 = 0;
    for (xs, ys) |x, y| {
        const dx = x - mx;
        const dy = y - my;
        sxy += dx * dy;
        sxx += dx * dx;
        syy += dy * dy;
    }
    if (sxx <= 0 or syy <= 0) return 0;
    return sxy / @sqrt(sxx * syy);
}

fn solveLinearSystem(comptime K: usize, Ain: [K][K]f64, bin: [K]f64) [K]f64 {
    var A = Ain;
    var b = bin;
    for (0..K) |col| {
        var piv = col;
        var best = @abs(A[col][col]);
        for (col + 1..K) |r| {
            if (@abs(A[r][col]) > best) {
                best = @abs(A[r][col]);
                piv = r;
            }
        }
        if (piv != col) {
            const tmpRow = A[col];
            A[col] = A[piv];
            A[piv] = tmpRow;
            const tmpB = b[col];
            b[col] = b[piv];
            b[piv] = tmpB;
        }
        const diag = A[col][col];
        if (@abs(diag) < 1e-12) continue;
        for (col + 1..K) |r| {
            const factor = A[r][col] / diag;
            for (col..K) |c| A[r][c] -= factor * A[col][c];
            b[r] -= factor * b[col];
        }
    }
    var x: [K]f64 = [_]f64{0} ** K;
    var i: usize = K;
    while (i > 0) {
        i -= 1;
        var s = b[i];
        for (i + 1..K) |j| s -= A[i][j] * x[j];
        x[i] = if (@abs(A[i][i]) > 1e-12) s / A[i][i] else 0;
    }
    return x;
}

fn ols(comptime K: usize, predictors: [K][]const f64, y: []const f64) [K]f64 {
    const n = y.len;
    var A: [K][K]f64 = [_][K]f64{[_]f64{0} ** K} ** K;
    var b: [K]f64 = [_]f64{0} ** K;
    for (0..K) |a| {
        for (0..K) |c| {
            var s: f64 = 0;
            for (0..n) |i| s += predictors[a][i] * predictors[c][i];
            A[a][c] = s;
        }
        var sb: f64 = 0;
        for (0..n) |i| sb += predictors[a][i] * y[i];
        b[a] = sb;
    }
    return solveLinearSystem(K, A, b);
}

fn r2FromCoeffs(comptime K: usize, coeffs: [K]f64, predictors: [K][]const f64, y: []const f64) f64 {
    const n = y.len;
    const my = mean(y);
    var ss_res: f64 = 0;
    var ss_tot: f64 = 0;
    for (0..n) |i| {
        var yhat: f64 = 0;
        for (0..K) |k| yhat += coeffs[k] * predictors[k][i];
        ss_res += (y[i] - yhat) * (y[i] - yhat);
        ss_tot += (y[i] - my) * (y[i] - my);
    }
    if (ss_tot <= 0) return 0;
    return 1.0 - ss_res / ss_tot;
}

fn residualsOf(alloc: std.mem.Allocator, comptime K: usize, predictors: [K][]const f64, y: []const f64) []f64 {
    const coeffs = ols(K, predictors, y);
    const n = y.len;
    var res = alloc.alloc(f64, n) catch unreachable;
    for (0..n) |i| {
        var yhat: f64 = 0;
        for (0..K) |k| yhat += coeffs[k] * predictors[k][i];
        res[i] = y[i] - yhat;
    }
    return res;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const out = std.io.getStdOut().writer();
    const err = std.io.getStdErr().writer();

    var smoke = false;
    var args = std.process.args();
    _ = args.next();
    while (args.next()) |a| {
        if (std.mem.eql(u8, a, "--smoke")) smoke = true;
    }

    const AIM_LIST: []const f64 = if (smoke) AIM_LIST_FULL[0..3] else AIM_LIST_FULL[0..];
    const EVALS_LIST: []const usize = if (smoke) EVALS_LIST_FULL[0..2] else EVALS_LIST_FULL[0..];
    const R_DRAWS: usize = if (smoke) 2 else R_DRAWS_FULL;
    const REPEATS_INNER: usize = if (smoke) 1 else REPEATS_INNER_FULL;
    const D_MAX: usize = if (smoke) 3 else MAX_D;

    var timer = try std.time.Timer.start();

    buildWorld(WORLD_SEED);
    try err.print("world built t={d}ms\n", .{timer.read() / std.time.ns_per_ms});

    buildFullCache();
    try err.print("full-enumeration cache built ({d} families x <=92 bases x {d} targets) t={d}ms\n", .{ NFAM, NTARGETS, timer.read() / std.time.ns_per_ms });

    buildCeilings();
    try err.print("representability ceilings built t={d}ms\n", .{timer.read() / std.time.ns_per_ms});

    try err.print("\n=== target base rates (train split, n={d}) ===\n", .{NTRAIN});
    for (0..NTARGETS) |t| {
        var pos: usize = 0;
        for (0..NTRAIN) |i| {
            if (TRAIN_LABELS[t][i]) pos += 1;
        }
        const rate = @as(f64, @floatFromInt(pos)) / @as(f64, @floatFromInt(NTRAIN));
        try err.print("  target {d}: positive_rate={d:.4}\n", .{ t, rate });
    }

    try err.print("\n=== single-family ceilings (full enumeration, TEST) ===\n", .{});
    for (0..NTARGETS) |t| {
        try err.print("  target {d}:", .{t});
        for (FAMILY_ORDER) |fam| {
            try err.print(" {s}={d:.3}", .{ familyName(fam), CEIL_SINGLE_TEST[@intFromEnum(fam)][t] });
        }
        try err.print("\n", .{});
    }

    try err.print("\nif --smoke: reduced grid (D<={d}, {d} aim levels, {d} budget levels, {d} draws, {d} inner repeats)\n", .{ D_MAX, AIM_LIST.len, EVALS_LIST.len, R_DRAWS, REPEATS_INNER });

    try out.print("cell_id,target,D,draw_id,N,members_per_fam,active_mask,aim,e_total,evals_actual,repr_score,reach_score,certified_solve,best_test_acc,has_req\n", .{});

    var rows_repr = std.ArrayList(f64).init(alloc);
    defer rows_repr.deinit();
    var rows_aim = std.ArrayList(f64).init(alloc);
    defer rows_aim.deinit();
    var rows_d = std.ArrayList(f64).init(alloc);
    defer rows_d.deinit();
    var rows_evals = std.ArrayList(f64).init(alloc);
    defer rows_evals.deinit();
    var rows_reach = std.ArrayList(f64).init(alloc);
    defer rows_reach.deinit();
    var rows_certified = std.ArrayList(bool).init(alloc);
    defer rows_certified.deinit();
    var rows_target = std.ArrayList(usize).init(alloc);
    defer rows_target.deinit();

    var cell_id: usize = 0;
    var d: usize = 1;
    while (d <= D_MAX) : (d += 1) {
        for (0..R_DRAWS) |draw| {
            var fam_list = FAMILY_ORDER;
            var prng = std.Random.DefaultPrng.init(mixSeed(WORLD_SEED, @intCast(d), @intCast(draw), 0, 0, 1));
            prng.random().shuffle(FamilyId, &fam_list);
            const F = fam_list[0..d];
            var active_mask: u32 = 0;
            for (F) |fam| active_mask |= (@as(u32, 1) << @intCast(@intFromEnum(fam)));

            for (0..NTARGETS) |target| {
                const repr = reprScore(F, target);
                const req_ok = hasAllRequired(F, target);

                for (AIM_LIST, 0..) |aim, aim_idx| {
                    for (EVALS_LIST, 0..) |e_total, e_idx| {
                        for (0..REPEATS_INNER) |repeat| {
                            var prng2 = std.Random.DefaultPrng.init(mixSeed(
                                WORLD_SEED ^ 0xA5A5_1234,
                                @intCast(d * 1000 + draw),
                                @intCast(target),
                                @intCast(aim_idx * 100 + e_idx * 10 + repeat),
                                0,
                                2,
                            ));
                            const res = runCell(F, target, aim, e_total, prng2.random());
                            const reach_score = rescale(res.best_test);
                            const certified = res.best_test >= SOLVE_THRESH;
                            const n_members = d * MEMBERS_PER_FAM;

                            try out.print("{d},{d},{d},{d},{d},{d},{d},{d:.2},{d},{d},{d:.4},{d:.4},{},{d:.4},{}\n", .{
                                cell_id, target, d, draw, n_members, MEMBERS_PER_FAM, active_mask,
                                aim, e_total, res.evals_actual, repr, reach_score, certified, res.best_test, req_ok,
                            });

                            try rows_repr.append(repr);
                            try rows_aim.append(aim);
                            try rows_d.append(@floatFromInt(d));
                            try rows_evals.append(@floatFromInt(res.evals_actual));
                            try rows_reach.append(reach_score);
                            try rows_certified.append(certified);
                            try rows_target.append(target);

                            cell_id += 1;
                        }
                    }
                }
            }
        }
        try err.print("D={d} done, t={d}ms\n", .{ d, timer.read() / std.time.ns_per_ms });
    }

    try err.print("\n{d} cells run, t={d}ms\n", .{ cell_id, timer.read() / std.time.ns_per_ms });

    // -------------------------------------------------------- regression
    const n_rows = rows_reach.items.len;
    var ones = try alloc.alloc(f64, n_rows);
    defer alloc.free(ones);
    var interaction = try alloc.alloc(f64, n_rows);
    defer alloc.free(interaction);
    for (0..n_rows) |i| {
        ones[i] = 1.0;
        interaction[i] = rows_repr.items[i] * rows_aim.items[i];
    }

    const xs_repr = rows_repr.items;
    const xs_aim = rows_aim.items;
    const xs_d = rows_d.items;
    const xs_evals = rows_evals.items;
    const ys = rows_reach.items;

    const r_repr = pearson(xs_repr, ys);
    const r_aim = pearson(xs_aim, ys);
    const r_d = pearson(xs_d, ys);
    const r_evals = pearson(xs_evals, ys);
    const r_inter = pearson(interaction, ys);

    try err.print("\n=== single-predictor correlations with REACH (n={d} cells) ===\n", .{n_rows});
    try err.print("  corr(reach, representability)        = {d:.4}   R^2 = {d:.4}\n", .{ r_repr, r_repr * r_repr });
    try err.print("  corr(reach, aim)                     = {d:.4}   R^2 = {d:.4}\n", .{ r_aim, r_aim * r_aim });
    try err.print("  corr(reach, D)                        = {d:.4}   R^2 = {d:.4}\n", .{ r_d, r_d * r_d });
    try err.print("  corr(reach, evals_actual)             = {d:.4}   R^2 = {d:.4}\n", .{ r_evals, r_evals * r_evals });
    try err.print("  corr(reach, repr*aim interaction)     = {d:.4}   R^2 = {d:.4}\n", .{ r_inter, r_inter * r_inter });

    // full model with interaction
    const preds6: [6][]const f64 = .{ ones, xs_repr, xs_aim, xs_d, xs_evals, interaction };
    const coeffs6 = ols(6, preds6, ys);
    const r2_full = r2FromCoeffs(6, coeffs6, preds6, ys);
    try err.print("\n=== full model: reach ~ b0 + b1*repr + b2*aim + b3*D + b4*evals + b5*(repr*aim) ===\n", .{});
    try err.print("  b0={d:.4} b1(repr)={d:.4} b2(aim)={d:.4} b3(D)={d:.4} b4(evals)={d:.6} b5(repr*aim)={d:.4}   R^2={d:.4}\n", .{
        coeffs6[0], coeffs6[1], coeffs6[2], coeffs6[3], coeffs6[4], coeffs6[5], r2_full,
    });

    // additive-only model (no interaction) for nested comparison
    const preds5: [5][]const f64 = .{ ones, xs_repr, xs_aim, xs_d, xs_evals };
    const coeffs5 = ols(5, preds5, ys);
    const r2_additive = r2FromCoeffs(5, coeffs5, preds5, ys);
    try err.print("\n=== additive-only model (no interaction): reach ~ b0+b1*repr+b2*aim+b3*D+b4*evals ===\n", .{});
    try err.print("  b0={d:.4} b1(repr)={d:.4} b2(aim)={d:.4} b3(D)={d:.4} b4(evals)={d:.6}   R^2={d:.4}\n", .{
        coeffs5[0], coeffs5[1], coeffs5[2], coeffs5[3], coeffs5[4], r2_additive,
    });
    try err.print("  delta R^2 from adding the interaction term: {d:.4}\n", .{r2_full - r2_additive});

    // partial correlations: each of {repr, aim, D, evals, interaction} vs reach,
    // controlling for the other four.
    {
        const predsRest: [5][]const f64 = .{ ones, xs_aim, xs_d, xs_evals, interaction };
        const res_x = residualsOf(alloc, 5, predsRest, xs_repr);
        defer alloc.free(res_x);
        const res_y = residualsOf(alloc, 5, predsRest, ys);
        defer alloc.free(res_y);
        const pc = pearson(res_x, res_y);
        try err.print("\n  partial corr(representability, reach | aim,D,evals,interaction) = {d:.4}  (R^2={d:.4})\n", .{ pc, pc * pc });
    }
    {
        const predsRest: [5][]const f64 = .{ ones, xs_repr, xs_d, xs_evals, interaction };
        const res_x = residualsOf(alloc, 5, predsRest, xs_aim);
        defer alloc.free(res_x);
        const res_y = residualsOf(alloc, 5, predsRest, ys);
        defer alloc.free(res_y);
        const pc = pearson(res_x, res_y);
        try err.print("  partial corr(aim, reach | repr,D,evals,interaction)              = {d:.4}  (R^2={d:.4})\n", .{ pc, pc * pc });
    }
    {
        const predsRest: [5][]const f64 = .{ ones, xs_repr, xs_aim, xs_evals, interaction };
        const res_x = residualsOf(alloc, 5, predsRest, xs_d);
        defer alloc.free(res_x);
        const res_y = residualsOf(alloc, 5, predsRest, ys);
        defer alloc.free(res_y);
        const pc = pearson(res_x, res_y);
        try err.print("  partial corr(D, reach | repr,aim,evals,interaction)              = {d:.4}  (R^2={d:.4})\n", .{ pc, pc * pc });
    }
    {
        const predsRest: [5][]const f64 = .{ ones, xs_repr, xs_aim, xs_d, interaction };
        const res_x = residualsOf(alloc, 5, predsRest, xs_evals);
        defer alloc.free(res_x);
        const res_y = residualsOf(alloc, 5, predsRest, ys);
        defer alloc.free(res_y);
        const pc = pearson(res_x, res_y);
        try err.print("  partial corr(evals, reach | repr,aim,D,interaction)              = {d:.4}  (R^2={d:.4})\n", .{ pc, pc * pc });
    }
    {
        const predsRest: [5][]const f64 = .{ ones, xs_repr, xs_aim, xs_d, xs_evals };
        const res_x = residualsOf(alloc, 5, predsRest, interaction);
        defer alloc.free(res_x);
        const res_y = residualsOf(alloc, 5, predsRest, ys);
        defer alloc.free(res_y);
        const pc = pearson(res_x, res_y);
        try err.print("  partial corr(repr*aim, reach | repr,aim,D,evals)                 = {d:.4}  (R^2={d:.4})  <-- THE CAPSTONE TEST\n", .{ pc, pc * pc });
    }

    // ------------------------------------- phase boundary: bin by representability
    try err.print("\n=== PHASE BOUNDARY: corr(aim, reach) within representability bins ===\n", .{});
    const BINS = [_][2]f64{ .{ 0.0, 0.34 }, .{ 0.34, 0.67 }, .{ 0.67, 1.0001 } };
    const BIN_NAMES = [_][]const u8{ "LOW repr [0,0.34)", "MID repr [0.34,0.67)", "HIGH repr [0.67,1.0]" };
    for (BINS, 0..) |bin, bi| {
        var bin_aim = std.ArrayList(f64).init(alloc);
        defer bin_aim.deinit();
        var bin_reach = std.ArrayList(f64).init(alloc);
        defer bin_reach.deinit();
        for (0..n_rows) |i| {
            if (xs_repr[i] >= bin[0] and xs_repr[i] < bin[1]) {
                try bin_aim.append(xs_aim[i]);
                try bin_reach.append(ys[i]);
            }
        }
        if (bin_aim.items.len > 2) {
            const r = pearson(bin_aim.items, bin_reach.items);
            try err.print("  {s}: n={d}  corr(aim,reach)={d:.4}  R^2={d:.4}  mean_reach={d:.4}\n", .{
                BIN_NAMES[bi], bin_aim.items.len, r, r * r, mean(bin_reach.items),
            });
        } else {
            try err.print("  {s}: n={d} (too few for correlation)\n", .{ BIN_NAMES[bi], bin_aim.items.len });
        }
    }

    // cross-tab: mean reach by (repr_bin, aim level)
    try err.print("\n=== mean reach_score by (representability bin, aim level) ===\n", .{});
    try err.print("  {s:<22}", .{"repr bin \\ aim ->"});
    for (AIM_LIST) |aim| try err.print(" {d:.2}  ", .{aim});
    try err.print("\n", .{});
    for (BINS, 0..) |bin, bi| {
        try err.print("  {s:<22}", .{BIN_NAMES[bi]});
        for (AIM_LIST) |aim| {
            var s: f64 = 0;
            var cnt: usize = 0;
            for (0..n_rows) |i| {
                if (xs_repr[i] >= bin[0] and xs_repr[i] < bin[1] and @abs(xs_aim[i] - aim) < 1e-9) {
                    s += ys[i];
                    cnt += 1;
                }
            }
            const m2 = if (cnt > 0) s / @as(f64, @floatFromInt(cnt)) else -1;
            try err.print(" {d:.3} ", .{m2});
        }
        try err.print("\n", .{});
    }

    // ----------------------------------- falsification cells
    try err.print("\n=== FALSIFICATION: cells violating the proposed law ===\n", .{});
    var viol_a: usize = 0; // high aim + high repr but low reach
    var viol_a_total: usize = 0;
    var viol_b: usize = 0; // low aim + low repr but high reach
    var viol_b_total: usize = 0;
    for (0..n_rows) |i| {
        if (xs_aim[i] >= 0.75 and xs_repr[i] >= 0.8) {
            viol_a_total += 1;
            if (ys[i] < 0.2) viol_a += 1;
        }
        if (xs_aim[i] <= 0.25 and xs_repr[i] <= 0.2) {
            viol_b_total += 1;
            if (ys[i] > 0.6) viol_b += 1;
        }
    }
    try err.print("  (A) aim>=0.75 & repr>=0.8 but reach<0.2: {d}/{d} ({d:.2}%)  [should be rare if the law holds]\n", .{
        viol_a, viol_a_total, 100.0 * @as(f64, @floatFromInt(viol_a)) / @as(f64, @floatFromInt(@max(viol_a_total, 1))),
    });
    try err.print("  (B) aim<=0.25 & repr<=0.2 but reach>0.6: {d}/{d} ({d:.2}%)  [should be rare if the law holds]\n", .{
        viol_b, viol_b_total, 100.0 * @as(f64, @floatFromInt(viol_b)) / @as(f64, @floatFromInt(@max(viol_b_total, 1))),
    });

    // certified-solve counts overall (the round's "reach" concept)
    var n_certified: usize = 0;
    for (rows_certified.items) |c| {
        if (c) n_certified += 1;
    }
    try err.print("\ncertified_solve (best_test>=0.97) count: {d}/{d} ({d:.2}%)\n", .{
        n_certified, n_rows, 100.0 * @as(f64, @floatFromInt(n_certified)) / @as(f64, @floatFromInt(n_rows)),
    });

    try err.print("\ndone, total t={d}ms\n", .{timer.read() / std.time.ns_per_ms});
}
