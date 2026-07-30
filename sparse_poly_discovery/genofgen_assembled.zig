//! F5 (Round 2026-07-11b / Round F) — THE ASSEMBLED GENERATOR-OF-GENERATORS.
//!
//! Context: Round E built three pieces of the "generator-of-generators" idea
//! separately: E1 (`repr_expansion.zig`) grew the family menu BY HAND (mixr,
//! ratio, thresh, run) under a sound certifier; E2 (`target_router.zig`)
//! learned a k-NN AIM router (which of {base, gf2_joint, spectral_acc} to try)
//! from a 10-feature failure descriptor; E3 (`wcore/src/smart_gen.zig`) showed
//! a smart generator CAN auto-discover a missing program-synthesis mechanism
//! from scratch, but only via exhaustive coverage steered by a mechanism
//! SIGNATURE (blind/gradient/prior-sampling all failed).
//!
//! F5 assembles all three into ONE autonomous pass over the sparse-poly grid
//! substrate (the E1/E2 domain -- NOT wcore's register machine; E3's finding
//! that "coverage steered by a structural signature crosses where blind bulk
//! and gradient fail" is re-implemented here as a GRID-FAMILY discovery
//! problem, not re-run verbatim on programs): for every still-unsolved target,
//!   (a) a router ranks ALL 8 candidate families (base, gf2, and 6 GROWABLE
//!       templates: thresh, mixr, ratio, run, rank, distinct) by a learned
//!       nearest-neighbor aim over a 14-feature descriptor;
//!   (b) known (already-discovered) families are tried in ranked order first
//!       (cheap, no search-for-the-shape-itself needed);
//!   (c) if none of the KNOWN families certify, smart-gen is invoked on the
//!       top-ranked NOT-yet-known growable family: a cheap structural
//!       SIGNATURE probe decides whether the shape is worth a full-grid
//!       search at all (the E3-style "coverage inclusion" gate), and if it
//!       fires, an exhaustive small-grid search runs (thresh/mixr/ratio/run/
//!       rank) or a signature-STEERED conjunction search runs (distinct's
//!       hard sub-case -- the one place this file's own combinatorics
//!       actually explode, mirroring E3's L2->L3 explosion);
//!   (d) a certifying candidate is CERTIFIED (test accuracy >= COVER on a
//!       held-out split) and passes a novelty gate (R² < R2_MAX against a
//!       fixed 7-statistic reference basis), then PROMOTED: the family
//!       becomes "known" for every LATER target in the same pass
//!       (representability grows within the pass, exactly as E1 grew it by
//!       hand across the round).
//!
//! Four arms, equal certifier bar / equal per-family search budget throughout:
//!   HAND              -- oracle baseline: go directly to the target's true
//!                         family, no router, no signature gating (the
//!                         E1-style "hand-supplied family" baseline).
//!   AUTONOMOUS        -- the full loop above.
//!   AUTO_NOSMARTGEN   -- autonomous minus (c)/(d): known stays {base,gf2}
//!                         forever, no family ever gets promoted.
//!   AUTO_NOROUTER     -- autonomous minus the LEARNED router: families are
//!                         tried in a FIXED enum order instead of a learned
//!                         ranking (both for known-family Phase 1 and for
//!                         choosing which not-yet-known family to
//!                         signature-probe in Phase 2). Smart-gen (signature
//!                         gating + promotion) stays on.
//!
//! Battery (73 targets): battery B (11, `open_invention_rq1.zig`), battery C
//! (11, transcribed from `open_invention_e2.zig` + `repr_expansion.zig`'s own
//! BATTERY_C list), battery D (11, `tier8_battery_d.zig`) -- all three
//! REUSED READ-ONLY, no eqtax dependency, imported directly (the established
//! convention `repr_expansion.zig`/`target_router.zig` already use) -- plus
//! 30 minority-class "extra" targets (5 per growable family, needed so the
//! router has enough labeled examples per class to learn from at all) plus
//! 10 FRESH FRONTIER targets: MIXMOD1/2 (mixr), RATIO1 (ratio), RUN1 (run),
//! ORDER2 (the round-c/E1 standing-open target, mod2 lens), ORDER2_MOD3 /
//! RANK2_MOD3 (rank -- the genuine standing frontier, see the ORDER2 finding
//! below), WALL_EASY/WALL_MED/WALL_HARD (distinct -- the grid-domain analogue
//! of wcore's "distinct-count conjunction wall": WALL_HARD is a genuine
//! conjunction of two individually-insufficient distinct-count predicates,
//! the one place a blind-vs-steered gap is measured directly, `diag` mode).
//!
//! HONEST INTEGRATION FINDING (verify empirically via `selftest`): ORDER2
//! (rank of cell0 among the other 7, mod-2 lens) is E1's own "standing
//! unrepresentable core" target -- unrepresentable under E1's LOGISTIC-
//! REGRESSION-based family menu. rank(cell0) mod 2 is exactly the XOR (mod-2
//! sum) of the 7 comparison bits "cell0 vs cell_j" -- a GF(2)-LINEAR function
//! of 7 of E2's own 45-dictionary columns. So E2's gf2_joint (Gaussian
//! elimination, not gradient fitting) should certify ORDER2 TRIVIALLY once
//! folded into the same assembled loop. This is a pure INTEGRATION effect:
//! E1's "family-level impossible" verdict was about its own certifier's
//! FITTING MECHANISM (gradient descent can't learn XOR), not about
//! representability in any absolute sense. ORDER2_MOD3 (mod-3 lens on the
//! SAME star-pairset) is NOT GF(2)-linear (mod-3 of a bit-sum is not a linear
//! GF(2) functional) and stays a genuine frontier requiring the new `rank`
//! family -- the actual auto-discovery test.
//!
//! Deliberately NOT imported: equivalence_tax.zig, unified_invention.zig
//! (tax dependency). Numeric glue is duplicated per this round's established
//! convention (see repr_expansion.zig / target_router.zig headers).
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe genofgen_assembled.zig -O ReleaseFast
//! Run:
//!   ./genofgen_assembled selftest
//!   ./genofgen_assembled run <hand|autonomous|auto_nosmartgen|auto_norouter|all> <csv> [--seeds=1|3]
//!   ./genofgen_assembled diag <csv>       (WALL_HARD blind-vs-steered conjunction diagnostic)
//! Single-threaded, CPU-only, each invocation well under the 15-min cap.

const std = @import("std");
const rq1 = @import("open_invention_rq1.zig"); // battery B generator (no eqtax dep)
const bd = @import("tier8_battery_d.zig"); // battery D targets (no eqtax dep)
const e2 = @import("open_invention_e2.zig"); // battery C label predicates (no eqtax dep)

// ── Shared constants (identical split discipline to E1/E2) ─────────────────
const NCELL: usize = 8;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;
const WEAK_SIG: f64 = 0.55; // structural-signature "worth investing" threshold
const NPAIR: usize = 28;

const SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };

// ═══════════════════════════════════════════════════════════════════════
// Grid statistics
// ═══════════════════════════════════════════════════════════════════════
fn gridSum(g: [NCELL]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}
fn countAtLeast(g: [NCELL]u8, k: u8) usize {
    var c: usize = 0;
    for (g) |v| if (v >= k) {
        c += 1;
    };
    return c;
}
fn signPattern(g: [NCELL]u8) u8 {
    var p: u8 = 0;
    for (0..NCELL) |i| if (g[i] >= 3) {
        p |= @as(u8, 1) << @intCast(i);
    };
    return p;
}
fn inversionAll(g: [NCELL]u8) usize {
    var inv: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        if (g[i] > g[j]) inv += 1;
    };
    return inv;
}
/// rank of cell i among the other 7 -- count of j != i with g[i] > g[j].
/// This is cmpAggregate over the "star(i)" pairset (all pairs touching i).
fn starCmp(g: [NCELL]u8, i: usize) usize {
    var c: usize = 0;
    for (0..NCELL) |j| {
        if (j != i and g[i] > g[j]) c += 1;
    }
    return c;
}
/// numDistinct: count of distinct values among cells selected by `mask`.
fn numDistinct(g: [NCELL]u8, mask: u8) usize {
    var seen: [6]bool = [_]bool{false} ** 6;
    var n: usize = 0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) {
            const v = g[i];
            if (!seen[v]) {
                seen[v] = true;
                n += 1;
            }
        }
    }
    return n;
}
fn maxRunGE(g: [NCELL]u8, k: u8) usize {
    var best: usize = 0;
    var cur: usize = 0;
    for (g) |v| {
        if (v >= k) {
            cur += 1;
            if (cur > best) best = cur;
        } else cur = 0;
    }
    return best;
}
fn firstDescentPos(g: [NCELL]u8) usize {
    for (0..NCELL - 1) |i| {
        if (g[i] > g[i + 1]) return i;
    }
    return NCELL;
}
fn numLocalMax(g: [NCELL]u8) usize {
    var c: usize = 0;
    for (1..NCELL - 1) |i| {
        if (g[i - 1] < g[i] and g[i] > g[i + 1]) c += 1;
    }
    return c;
}
fn runStat(g: [NCELL]u8, idx: u8) usize {
    return switch (idx) {
        0 => maxRunGE(g, 2),
        1 => maxRunGE(g, 3),
        2 => maxRunGE(g, 4),
        3 => firstDescentPos(g),
        else => numLocalMax(g),
    };
}
fn monomialSign(mask: u8, g: [NCELL]u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - 2.5);
    }
    return if (p > 0) 1.0 else 0.0;
}
fn walshParity(mask: u8, g: [NCELL]u8) f64 {
    var acc: u1 = 0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0 and g[i] >= 3) acc ^= 1;
    }
    return @floatFromInt(acc);
}
const RatioPair = struct { hi: u8, lo: u8 };
fn ratioProd(g: [NCELL]u8, p: RatioPair) f64 {
    return @floatFromInt(countAtLeast(g, p.hi) * countAtLeast(g, p.lo));
}
fn ratioDiff(g: [NCELL]u8, p: RatioPair) f64 {
    const hi: f64 = @floatFromInt(countAtLeast(g, p.hi));
    const lo: f64 = @floatFromInt(countAtLeast(g, p.lo));
    return (hi - lo) / (hi + lo + 1.0);
}
/// 7 base scalar statistics mixr/ratio draw their two arguments from:
/// 0=sum, 1..5=count(>=1..5), 6=inversion(all28). This is a small, general
/// GENERATOR SPACE (not a hand-curated pair list) -- any of the C(7,2)=21
/// pairs is reachable, so a target built from any two of these statistics
/// is representable by the family, not just the handful of pairs a human
/// happened to pick (E1's own mixr/ratio menus used a hand-picked 3-pair
/// list; this is the auto-discovery-honest generalization of that menu).
const N_BASE_STATS: u8 = 7;
fn baseStatValue(g: [NCELL]u8, stat: u8) usize {
    return switch (stat) {
        0 => gridSum(g),
        1 => countAtLeast(g, 1),
        2 => countAtLeast(g, 2),
        3 => countAtLeast(g, 3),
        4 => countAtLeast(g, 4),
        5 => countAtLeast(g, 5),
        else => inversionAll(g),
    };
}
fn mixrIndex(g: [NCELL]u8, stat_a: u8, stat_b: u8, ra: u8, rb: u8) f64 {
    const a = baseStatValue(g, stat_a) % ra;
    const b = baseStatValue(g, stat_b) % rb;
    return @floatFromInt(a * @as(usize, rb) + b);
}

const WINDOWS = [_]u8{ 0xFF, 0x0F, 0xF0, 0x55, 0xAA, 0x3F, 0xFC, 0x3C };
const N_WINDOWS = WINDOWS.len;

// ═══════════════════════════════════════════════════════════════════════
// GF(2) 45-column joint dictionary (transcribed from target_router.zig)
// ═══════════════════════════════════════════════════════════════════════
const NDICT = 45;
var PAIR_I: [NPAIR]u8 = undefined;
var PAIR_J: [NPAIR]u8 = undefined;
fn initPairs() void {
    var idx: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        PAIR_I[idx] = @intCast(i);
        PAIR_J[idx] = @intCast(j);
        idx += 1;
    };
    std.debug.assert(idx == NPAIR);
}
fn cmpBit(g: [NCELL]u8, p: usize) u1 {
    return if (g[PAIR_I[p]] > g[PAIR_J[p]]) 1 else 0;
}
fn lbBit(v: u8) u1 {
    return @intCast(v & 1);
}
fn tbBit(v: u8) u1 {
    return if (v >= 3) 1 else 0;
}
fn featBits45(g: [NCELL]u8) u64 {
    var bits: u64 = 0;
    for (0..NPAIR) |p| if (cmpBit(g, p) == 1) {
        bits |= (@as(u64, 1) << @intCast(p));
    };
    for (0..NCELL) |i| if (lbBit(g[i]) == 1) {
        bits |= (@as(u64, 1) << @intCast(28 + i));
    };
    for (0..NCELL) |i| if (tbBit(g[i]) == 1) {
        bits |= (@as(u64, 1) << @intCast(36 + i));
    };
    bits |= (@as(u64, 1) << 44);
    return bits;
}
const Gf2Result = struct { consistent: bool, sol_bits: u64 };
fn gf2Fit(grid: []const [NCELL]u8, Y: []const f64, maxrows: usize) Gf2Result {
    var pivots: [NDICT]u64 = undefined;
    var used: [NDICT]bool = [_]bool{false} ** NDICT;
    var consistent = true;
    var s: usize = 0;
    while (s < maxrows and s < NTR) : (s += 1) {
        var r: u64 = featBits45(grid[s]);
        const yb: u64 = if (Y[s] > 0.5) 1 else 0;
        r |= (yb << 45);
        var c: usize = 0;
        while (c < NDICT) : (c += 1) {
            if (used[c] and (r & (@as(u64, 1) << @intCast(c))) != 0) r ^= pivots[c];
        }
        var lead: ?usize = null;
        var cc: usize = 0;
        while (cc < NDICT) : (cc += 1) {
            if ((r & (@as(u64, 1) << @intCast(cc))) != 0) {
                lead = cc;
                break;
            }
        }
        if (lead) |lc| {
            pivots[lc] = r;
            used[lc] = true;
        } else if ((r & (@as(u64, 1) << 45)) != 0) {
            consistent = false;
            break;
        }
    }
    if (!consistent) return .{ .consistent = false, .sol_bits = 0 };
    var c: usize = NDICT;
    while (c > 0) {
        c -= 1;
        if (!used[c]) continue;
        var c2: usize = 0;
        while (c2 < c) : (c2 += 1) {
            if (used[c2] and (pivots[c2] & (@as(u64, 1) << @intCast(c))) != 0) pivots[c2] ^= pivots[c];
        }
    }
    var sol: u64 = 0;
    for (0..NDICT) |ci| {
        if (used[ci]) {
            const rhs = (pivots[ci] >> 45) & 1;
            if (rhs != 0) sol |= (@as(u64, 1) << @intCast(ci));
        }
    }
    return .{ .consistent = true, .sol_bits = sol };
}
fn gf2Predict(sol_bits: u64, g: [NCELL]u8) f64 {
    const fb = featBits45(g) & ((@as(u64, 1) << NDICT) - 1);
    return @floatFromInt(@popCount(fb & sol_bits) & 1);
}
fn gf2Accuracy(sol_bits: u64, grid: []const [NCELL]u8, Y: []const f64, lo: usize, hi: usize) f64 {
    var match: usize = 0;
    for (lo..hi) |s| if (gf2Predict(sol_bits, grid[s]) == Y[s]) {
        match += 1;
    };
    return @as(f64, @floatFromInt(match)) / @as(f64, @floatFromInt(hi - lo));
}

// ═══════════════════════════════════════════════════════════════════════
// Search primitives: VAL-select, TEST-confirm (no leakage)
// ═══════════════════════════════════════════════════════════════════════
const CatResult = struct { v0: usize, negate: bool, val_acc: f64, test_acc: f64 };
fn categoricalSearch(raw: []const f64, Y: []const f64, domain: usize) CatResult {
    var pos: [96]usize = [_]usize{0} ** 96;
    var tot: [96]usize = [_]usize{0} ** 96;
    const dom = @min(domain, 96);
    var pos_total: usize = 0;
    const nval = NVA - NTR;
    for (NTR..NVA) |s| {
        var v: i64 = @intFromFloat(@round(raw[s]));
        if (v < 0) v = 0;
        var vu: usize = @intCast(v);
        if (vu >= dom) vu = dom - 1;
        tot[vu] += 1;
        if (Y[s] > 0.5) {
            pos[vu] += 1;
            pos_total += 1;
        }
    }
    var best_acc: f64 = 0;
    var best_v: usize = 0;
    var best_neg: bool = false;
    for (0..dom) |v| {
        const correct_eq = pos[v] + ((nval - tot[v]) - (pos_total - pos[v]));
        const acc_eq = @as(f64, @floatFromInt(correct_eq)) / @as(f64, @floatFromInt(nval));
        if (acc_eq > best_acc) {
            best_acc = acc_eq;
            best_v = v;
            best_neg = false;
        }
        const acc_neg = 1.0 - acc_eq;
        if (acc_neg > best_acc) {
            best_acc = acc_neg;
            best_v = v;
            best_neg = true;
        }
    }
    var correct_test: usize = 0;
    const ntest = NSAMP - NVA;
    for (NVA..NSAMP) |s| {
        var v: i64 = @intFromFloat(@round(raw[s]));
        if (v < 0) v = 0;
        var vu: usize = @intCast(v);
        if (vu >= dom) vu = dom - 1;
        const eq = (vu == best_v);
        const pred1 = if (best_neg) !eq else eq;
        const actual1 = Y[s] > 0.5;
        if (pred1 == actual1) correct_test += 1;
    }
    return .{ .v0 = best_v, .negate = best_neg, .val_acc = best_acc, .test_acc = @as(f64, @floatFromInt(correct_test)) / @as(f64, @floatFromInt(ntest)) };
}

const ThreshResult = struct { val_acc: f64, test_acc: f64 };
fn thresholdSearch(raw: []const f64, Y: []const f64) ThreshResult {
    const n = NVA - NTR;
    const Item = struct { f: f64, y: f64 };
    var items: [NVA - NTR]Item = undefined;
    for (NTR..NVA) |s| items[s - NTR] = .{ .f = raw[s], .y = Y[s] };
    std.sort.pdq(Item, &items, {}, struct {
        fn lt(_: void, a: Item, b: Item) bool {
            return a.f < b.f;
        }
    }.lt);
    var pos_total: usize = 0;
    for (items) |it| if (it.y > 0.5) {
        pos_total += 1;
    };
    var best_acc: f64 = 0;
    var best_thr: f64 = -std.math.inf(f64);
    var best_dir: bool = true;
    var pos_below: usize = 0;
    var i: usize = 0;
    while (i <= n) : (i += 1) {
        const thr: f64 = if (i == 0) -std.math.inf(f64) else if (i == n) std.math.inf(f64) else (items[i - 1].f + items[i].f) / 2.0;
        const skip = (i > 0 and i < n and items[i - 1].f == items[i].f);
        if (!skip) {
            const c1 = pos_total - pos_below + (i - pos_below);
            const acc1 = @as(f64, @floatFromInt(c1)) / @as(f64, @floatFromInt(n));
            if (acc1 > best_acc) {
                best_acc = acc1;
                best_thr = thr;
                best_dir = true;
            }
            const c0 = pos_below + ((n - i) - (pos_total - pos_below));
            const acc0 = @as(f64, @floatFromInt(c0)) / @as(f64, @floatFromInt(n));
            if (acc0 > best_acc) {
                best_acc = acc0;
                best_thr = thr;
                best_dir = false;
            }
        }
        if (i < n and items[i].y > 0.5) pos_below += 1;
    }
    var c: usize = 0;
    for (NVA..NSAMP) |s| {
        const pred: bool = if (best_dir) raw[s] >= best_thr else raw[s] < best_thr;
        if (pred == (Y[s] > 0.5)) c += 1;
    }
    return .{ .val_acc = best_acc, .test_acc = @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NSAMP - NVA)) };
}

fn applyLensArr(rawInt: []const f64, lens: u8, out: []f64) void {
    if (lens == 0) {
        @memcpy(out, rawInt);
    } else {
        for (0..NSAMP) |s| {
            const iv: i64 = @intFromFloat(@round(rawInt[s]));
            out[s] = @floatFromInt(@mod(iv, @as(i64, lens)));
        }
    }
}
fn domainFor(lens: u8, identDomain: usize) usize {
    return if (lens == 0) identDomain else lens;
}
const LENSES = [_]u8{ 0, 2, 3, 4, 5, 6 }; // 0 = ident

/// For lens==0 (ident) on an ORDINAL integer stat (a count, a run length, a
/// rank, a distinct-count), the natural classifier is a THRESHOLD split
/// ("raw >= v0"), not an equality split -- a pure equality search can only
/// carve out one residue value at a time, so a genuinely cumulative target
/// (e.g. "maxRunGE(3) >= 3") is invisible to equality search alone. For
/// mod-lensed values (residue classes), equality is the right search.
/// This tries both when lens==0 and keeps whichever wins on VAL.
fn identOrCategorical(raw_ident: []const f64, lens: u8, lensed: []f64, Y: []const f64, ident_domain: usize) CatResult {
    applyLensArr(raw_ident, lens, lensed);
    var best = categoricalSearch(lensed, Y, domainFor(lens, ident_domain));
    if (lens == 0) {
        const t = thresholdSearch(lensed, Y);
        if (t.val_acc > best.val_acc) best = .{ .v0 = 0, .negate = false, .val_acc = t.val_acc, .test_acc = t.test_acc };
    }
    return best;
}

// ═══════════════════════════════════════════════════════════════════════
// Novelty gate: reconstruction R² of a candidate raw stat from a fixed
// 7-scalar reference basis (sum, count>=1..5, inversion), fit on TRAIN,
// checked on TEST. Applied only to the 6 GROWABLE families (base/gf2 are
// the earned baseline, no gate) -- same discipline as E1's certifyLocal.
// ═══════════════════════════════════════════════════════════════════════
const NBASIS = 7;
fn buildBasis(grid: []const [NCELL]u8, basisX: *[NSAMP][NBASIS]f64) void {
    for (0..NSAMP) |s| {
        basisX[s][0] = @floatFromInt(gridSum(grid[s]));
        for (0..5) |k| basisX[s][1 + k] = @floatFromInt(countAtLeast(grid[s], @intCast(k + 1)));
        basisX[s][6] = @floatFromInt(inversionAll(grid[s]));
    }
    for (0..NBASIS) |c| {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += basisX[s][c];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (basisX[s][c] - mu) * (basisX[s][c] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| basisX[s][c] = (basisX[s][c] - mu) / sd;
    }
}
fn reconR2(basisX: *const [NSAMP][NBASIS]f64, raw: []const f64) f64 {
    var w: [NBASIS + 1]f64 = [_]f64{0} ** (NBASIS + 1);
    for (0..300) |_| for (0..NTR) |s| {
        var z = w[NBASIS];
        for (0..NBASIS) |j| z += w[j] * basisX[s][j];
        const e = z - raw[s];
        for (0..NBASIS) |j| w[j] -= 0.01 * e * basisX[s][j];
        w[NBASIS] -= 0.01 * e;
    };
    var mu: f64 = 0;
    for (NVA..NSAMP) |s| mu += raw[s];
    mu /= @floatFromInt(NSAMP - NVA);
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (NVA..NSAMP) |s| {
        var z = w[NBASIS];
        for (0..NBASIS) |j| z += w[j] * basisX[s][j];
        ssr += (raw[s] - z) * (raw[s] - z);
        sst += (raw[s] - mu) * (raw[s] - mu);
    }
    return 1.0 - ssr / @max(1e-9, sst);
}

// ═══════════════════════════════════════════════════════════════════════
// Family IDs
// ═══════════════════════════════════════════════════════════════════════
const FamilyId = enum(u8) { base, gf2, thresh, mixr, ratio, run, rank, distinct };
const N_FAM = 8;
const GROWABLE = [_]FamilyId{ .thresh, .mixr, .ratio, .run, .rank, .distinct };
const FIXED_ORDER = [_]FamilyId{ .base, .gf2, .thresh, .mixr, .ratio, .run, .rank, .distinct };
fn famName(f: FamilyId) []const u8 {
    return switch (f) {
        .base => "base",
        .gf2 => "gf2",
        .thresh => "thresh",
        .mixr => "mixr",
        .ratio => "ratio",
        .run => "run",
        .rank => "rank",
        .distinct => "distinct",
    };
}
fn isGrowable(f: FamilyId) bool {
    return @intFromEnum(f) >= @intFromEnum(FamilyId.thresh);
}

const FamResult = struct { solved: bool, test_acc: f64, val_acc: f64, evals: usize, novel_ok: bool = true, r2: f64 = 0 };
const UNSOLVED_CHEAP = FamResult{ .solved = false, .test_acc = 0, .val_acc = 0, .evals = 1 };

fn finalizeGrowable(val: f64, test_acc: f64, evals: usize, basisX: *const [NSAMP][NBASIS]f64, raw: []const f64) FamResult {
    var r2: f64 = 0;
    var novel_ok = true;
    if (test_acc >= COVER) {
        r2 = reconR2(basisX, raw);
        novel_ok = r2 < R2_MAX;
    }
    return .{ .solved = (test_acc >= COVER) and novel_ok, .test_acc = test_acc, .val_acc = val, .evals = evals, .novel_ok = novel_ok, .r2 = r2 };
}

// ── BASE family: monomial162 + walsh255 + world_sum_mod(6) +
//    world_sign_mod(6) + world_count3_mod(7) + composed AND/OR(3 pairs) ────
fn tryBase(grid: []const [NCELL]u8, Y: []const f64) FamResult {
    var evals: usize = 0;
    var best_val: f64 = -1;
    var best_test: f64 = 0;
    var raw: [NSAMP]f64 = undefined;

    var best_mono_mask: u8 = 0;
    var best_mono_val: f64 = -1;
    var m: u16 = 1;
    while (m <= 255) : (m += 1) {
        const mask: u8 = @intCast(m);
        const w = @popCount(mask);
        if (w < 1 or w > 4) continue;
        for (0..NSAMP) |s| raw[s] = monomialSign(mask, grid[s]);
        const r = categoricalSearch(&raw, Y, 2);
        evals += 1;
        if (r.val_acc > best_mono_val) {
            best_mono_val = r.val_acc;
            best_mono_mask = mask;
        }
        if (r.val_acc > best_val) {
            best_val = r.val_acc;
            best_test = r.test_acc;
        }
    }
    var best_walsh_mask: u8 = 0;
    var best_walsh_val: f64 = -1;
    m = 1;
    while (m <= 255) : (m += 1) {
        const mask: u8 = @intCast(m);
        for (0..NSAMP) |s| raw[s] = walshParity(mask, grid[s]);
        const r = categoricalSearch(&raw, Y, 2);
        evals += 1;
        if (r.val_acc > best_walsh_val) {
            best_walsh_val = r.val_acc;
            best_walsh_mask = mask;
        }
        if (r.val_acc > best_val) {
            best_val = r.val_acc;
            best_test = r.test_acc;
        }
    }
    const primes = [_]u8{ 2, 3, 5, 7, 11, 13 };
    var best_sumk: u8 = 2;
    var best_sumk_val: f64 = -1;
    for (primes) |k| {
        for (0..NSAMP) |s| raw[s] = @floatFromInt(gridSum(grid[s]) % k);
        const r = categoricalSearch(&raw, Y, k);
        evals += 1;
        if (r.val_acc > best_sumk_val) {
            best_sumk_val = r.val_acc;
            best_sumk = k;
        }
        if (r.val_acc > best_val) {
            best_val = r.val_acc;
            best_test = r.test_acc;
        }
    }
    for (primes) |k| {
        for (0..NSAMP) |s| raw[s] = @floatFromInt(@as(usize, signPattern(grid[s])) % k);
        const r = categoricalSearch(&raw, Y, k);
        evals += 1;
        if (r.val_acc > best_val) {
            best_val = r.val_acc;
            best_test = r.test_acc;
        }
    }
    var k3: u8 = 2;
    while (k3 <= 8) : (k3 += 1) {
        for (0..NSAMP) |s| raw[s] = @floatFromInt(countAtLeast(grid[s], 3) % k3);
        const r = categoricalSearch(&raw, Y, k3);
        evals += 1;
        if (r.val_acc > best_val) {
            best_val = r.val_acc;
            best_test = r.test_acc;
        }
    }
    var sumk_ind: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| sumk_ind[s] = if (gridSum(grid[s]) % best_sumk == 0) 1.0 else 0.0;
    const ComposedPair = struct { a: u8, kind: u8 }; // kind 0=mono&walsh 1=walsh&sumk 2=mono&sumk
    const pairs = [_]ComposedPair{
        .{ .a = best_walsh_mask, .kind = 0 },
        .{ .a = best_walsh_mask, .kind = 1 },
        .{ .a = best_mono_mask, .kind = 2 },
    };
    for (pairs) |cp| {
        for (0..2) |op| { // 0=AND 1=OR
            for (0..NSAMP) |s| {
                const a1: bool = switch (cp.kind) {
                    0 => monomialSign(best_mono_mask, grid[s]) > 0.5,
                    1 => walshParity(cp.a, grid[s]) > 0.5,
                    else => monomialSign(best_mono_mask, grid[s]) > 0.5,
                };
                const b1: bool = switch (cp.kind) {
                    0 => walshParity(cp.a, grid[s]) > 0.5,
                    1 => sumk_ind[s] > 0.5,
                    else => sumk_ind[s] > 0.5,
                };
                const c1 = if (op == 0) (a1 and b1) else (a1 or b1);
                raw[s] = if (c1) 1.0 else 0.0;
            }
            const r = categoricalSearch(&raw, Y, 2);
            evals += 1;
            if (r.val_acc > best_val) {
                best_val = r.val_acc;
                best_test = r.test_acc;
            }
        }
    }
    return .{ .solved = best_test >= COVER, .test_acc = best_test, .val_acc = best_val, .evals = evals };
}

fn tryGf2(grid: []const [NCELL]u8, Y: []const f64) FamResult {
    const fit = gf2Fit(grid, Y, 300);
    if (!fit.consistent) return .{ .solved = false, .test_acc = 0.5, .val_acc = 0.5, .evals = NDICT };
    const acc = gf2Accuracy(fit.sol_bits, grid, Y, NVA, NSAMP);
    return .{ .solved = acc >= COVER, .test_acc = acc, .val_acc = acc, .evals = NDICT };
}

// ═══════════════════════════════════════════════════════════════════════
// Growable families: cheap signature probe -> (if fired) small exhaustive
// grid + novelty gate. thresh/mixr/ratio/run/rank grids are all small
// enough to be exhaustive by construction; `distinct` additionally has a
// genuinely combinatorial conjunction sub-search (the E3-analogue).
// ═══════════════════════════════════════════════════════════════════════
fn sigThresh(grid: []const [NCELL]u8, Y: []const f64) f64 {
    var raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| raw[s] = @floatFromInt(countAtLeast(grid[s], 1) % 4);
    return categoricalSearch(&raw, Y, 4).val_acc;
}
fn tryThresh(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64) FamResult {
    return tryThreshGate(grid, Y, basisX, false);
}
fn tryThreshGate(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64, force: bool) FamResult {
    if (!force and sigThresh(grid, Y) <= WEAK_SIG) return UNSOLVED_CHEAP;
    var evals: usize = 1;
    const KS = [_]u8{ 1, 2, 4, 5 };
    var raw_ident: [NSAMP]f64 = undefined;
    var lensed: [NSAMP]f64 = undefined;
    var best_val: f64 = -1;
    var best_test: f64 = 0;
    var best_raw: [NSAMP]f64 = undefined;
    for (KS) |k| {
        for (0..NSAMP) |s| raw_ident[s] = @floatFromInt(countAtLeast(grid[s], k));
        for (LENSES) |lens| {
            const r = identOrCategorical(&raw_ident, lens, &lensed, Y, 9);
            evals += 1;
            if (r.val_acc > best_val) {
                best_val = r.val_acc;
                best_test = r.test_acc;
                best_raw = lensed;
            }
        }
    }
    return finalizeGrowable(best_val, best_test, evals, basisX, &best_raw);
}

fn sigMixr(grid: []const [NCELL]u8, Y: []const f64) f64 {
    var raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| raw[s] = mixrIndex(grid[s], 0, 3, 3, 3);
    return categoricalSearch(&raw, Y, 9).val_acc;
}
fn tryMixr(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64) FamResult {
    return tryMixrGate(grid, Y, basisX, false);
}
fn tryMixrGate(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64, force: bool) FamResult {
    if (!force and sigMixr(grid, Y) <= WEAK_SIG) return UNSOLVED_CHEAP;
    var evals: usize = 1;
    const RADII = [_][2]u8{ .{ 2, 2 }, .{ 3, 3 } };
    var raw_ident: [NSAMP]f64 = undefined;
    var lensed: [NSAMP]f64 = undefined;
    var best_val: f64 = -1;
    var best_test: f64 = 0;
    var best_raw: [NSAMP]f64 = undefined;
    for (0..N_BASE_STATS) |sa| {
        for (sa + 1..N_BASE_STATS) |sb| {
            for (RADII) |rr| {
                const ra = rr[0];
                const rb = rr[1];
                for (0..NSAMP) |s| raw_ident[s] = mixrIndex(grid[s], @intCast(sa), @intCast(sb), ra, rb);
                for (LENSES) |lens| {
                    const r = identOrCategorical(&raw_ident, lens, &lensed, Y, @as(usize, ra) * @as(usize, rb));
                    evals += 1;
                    if (r.val_acc > best_val) {
                        best_val = r.val_acc;
                        best_test = r.test_acc;
                        best_raw = lensed;
                    }
                }
            }
        }
    }
    return finalizeGrowable(best_val, best_test, evals, basisX, &best_raw);
}

fn sigRatio(grid: []const [NCELL]u8, Y: []const f64) f64 {
    var raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| raw[s] = @floatFromInt(@as(usize, @intFromFloat(ratioProd(grid[s], .{ .hi = 4, .lo = 1 }))) % 3);
    return categoricalSearch(&raw, Y, 3).val_acc;
}
fn tryRatio(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64) FamResult {
    return tryRatioGate(grid, Y, basisX, false);
}
fn tryRatioGate(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64, force: bool) FamResult {
    if (!force and sigRatio(grid, Y) <= WEAK_SIG) return UNSOLVED_CHEAP;
    var evals: usize = 1;
    const RATIO_PAIRS = [_]RatioPair{ .{ .hi = 4, .lo = 1 }, .{ .hi = 5, .lo = 0 }, .{ .hi = 3, .lo = 2 } };
    var raw_ident: [NSAMP]f64 = undefined;
    var lensed: [NSAMP]f64 = undefined;
    var best_val: f64 = -1;
    var best_test: f64 = 0;
    var best_raw: [NSAMP]f64 = undefined;
    for (RATIO_PAIRS) |rp| {
        for (0..2) |kind| { // 0=prod 1=diff
            for (0..NSAMP) |s| raw_ident[s] = if (kind == 0) ratioProd(grid[s], rp) else ratioDiff(grid[s], rp);
            if (kind == 1) {
                const t = thresholdSearch(&raw_ident, Y);
                evals += 1;
                if (t.val_acc > best_val) {
                    best_val = t.val_acc;
                    best_test = t.test_acc;
                    best_raw = raw_ident;
                }
            }
            for (LENSES) |lens| {
                if (lens == 0 and kind == 1) continue; // continuous ident handled via thresholdSearch above
                applyLensArr(&raw_ident, lens, &lensed);
                const dom = if (lens == 0) @as(usize, 65) else lens;
                const r = categoricalSearch(&lensed, Y, dom);
                evals += 1;
                if (r.val_acc > best_val) {
                    best_val = r.val_acc;
                    best_test = r.test_acc;
                    best_raw = lensed;
                }
            }
        }
    }
    return finalizeGrowable(best_val, best_test, evals, basisX, &best_raw);
}

fn sigRun(grid: []const [NCELL]u8, Y: []const f64) f64 {
    var raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| raw[s] = @floatFromInt(maxRunGE(grid[s], 3));
    return categoricalSearch(&raw, Y, 9).val_acc;
}
fn tryRun(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64) FamResult {
    return tryRunGate(grid, Y, basisX, false);
}
fn tryRunGate(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64, force: bool) FamResult {
    if (!force and sigRun(grid, Y) <= WEAK_SIG) return UNSOLVED_CHEAP;
    var evals: usize = 1;
    var raw_ident: [NSAMP]f64 = undefined;
    var lensed: [NSAMP]f64 = undefined;
    var best_val: f64 = -1;
    var best_test: f64 = 0;
    var best_raw: [NSAMP]f64 = undefined;
    for (0..5) |stat| {
        for (0..NSAMP) |s| raw_ident[s] = @floatFromInt(runStat(grid[s], @intCast(stat)));
        for (LENSES) |lens| {
            const r = identOrCategorical(&raw_ident, lens, &lensed, Y, 9);
            evals += 1;
            if (r.val_acc > best_val) {
                best_val = r.val_acc;
                best_test = r.test_acc;
                best_raw = lensed;
            }
        }
    }
    return finalizeGrowable(best_val, best_test, evals, basisX, &best_raw);
}

fn sigRank(grid: []const [NCELL]u8, Y: []const f64) f64 {
    var raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| raw[s] = @floatFromInt(starCmp(grid[s], 0) % 3);
    return categoricalSearch(&raw, Y, 3).val_acc;
}
fn tryRank(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64) FamResult {
    return tryRankGate(grid, Y, basisX, false);
}
fn tryRankGate(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64, force: bool) FamResult {
    if (!force and sigRank(grid, Y) <= WEAK_SIG) return UNSOLVED_CHEAP;
    var evals: usize = 1;
    var raw_ident: [NSAMP]f64 = undefined;
    var lensed: [NSAMP]f64 = undefined;
    var best_val: f64 = -1;
    var best_test: f64 = 0;
    var best_raw: [NSAMP]f64 = undefined;
    for (0..NCELL) |cell| {
        for (0..NSAMP) |s| raw_ident[s] = @floatFromInt(starCmp(grid[s], cell));
        for (LENSES) |lens| {
            const r = identOrCategorical(&raw_ident, lens, &lensed, Y, 8);
            evals += 1;
            if (r.val_acc > best_val) {
                best_val = r.val_acc;
                best_test = r.test_acc;
                best_raw = lensed;
            }
        }
    }
    return finalizeGrowable(best_val, best_test, evals, basisX, &best_raw);
}

fn sigDistinct(grid: []const [NCELL]u8, Y: []const f64) f64 {
    var raw: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| raw[s] = @floatFromInt(numDistinct(grid[s], 0xFF));
    return categoricalSearch(&raw, Y, 8).val_acc;
}

/// The 24 binarized distinct-window atoms used by the conjunction search:
/// "numDistinct(window) == t" for window in WINDOWS(8), t in {2,3,4}.
const N_CONJ_ATOMS = N_WINDOWS * 3;
fn conjAtomRaw(grid: []const [NCELL]u8, atom: usize, out: []f64) void {
    const window = WINDOWS[atom / 3];
    const t: usize = 2 + (atom % 3);
    for (0..NSAMP) |s| out[s] = if (numDistinct(grid[s], window) == t) 1.0 else 0.0;
}

const ConjSearchResult = struct { best_val: f64, best_test: f64, best_raw: [NSAMP]f64, evals: usize, n_included: usize };

/// steered=true: only conjoin atoms whose own VAL accuracy clears WEAK_SIG
/// (the E3-style "coverage inclusion" gate). steered=false (blind): sample
/// `blind_budget` random atom pairs ignoring the filter, same op set.
fn distinctConjSearch(grid: []const [NCELL]u8, Y: []const f64, steered: bool, blind_budget: usize, blind_seed: u64) ConjSearchResult {
    var atom_raw: [N_CONJ_ATOMS][NSAMP]f64 = undefined;
    var atom_acc: [N_CONJ_ATOMS]f64 = undefined;
    var evals: usize = 0;
    for (0..N_CONJ_ATOMS) |a| {
        conjAtomRaw(grid, a, &atom_raw[a]);
        atom_acc[a] = categoricalSearch(&atom_raw[a], Y, 2).val_acc;
        evals += 1;
    }
    var best_val: f64 = -1;
    var best_test: f64 = 0;
    var best_raw: [NSAMP]f64 = undefined;
    var raw: [NSAMP]f64 = undefined;
    var n_included: usize = 0;

    if (steered) {
        var included: [N_CONJ_ATOMS]usize = undefined;
        var nincl: usize = 0;
        for (0..N_CONJ_ATOMS) |a| if (atom_acc[a] > WEAK_SIG) {
            included[nincl] = a;
            nincl += 1;
        };
        n_included = nincl;
        var ii: usize = 0;
        while (ii < nincl) : (ii += 1) {
            var jj: usize = ii + 1;
            while (jj < nincl) : (jj += 1) {
                const ai = included[ii];
                const aj = included[jj];
                for (0..2) |op| {
                    for (0..NSAMP) |s| {
                        const a1 = atom_raw[ai][s] > 0.5;
                        const b1 = atom_raw[aj][s] > 0.5;
                        raw[s] = if (if (op == 0) (a1 and b1) else (a1 or b1)) 1.0 else 0.0;
                    }
                    const r = categoricalSearch(&raw, Y, 2);
                    evals += 1;
                    if (r.val_acc > best_val) {
                        best_val = r.val_acc;
                        best_test = r.test_acc;
                        best_raw = raw;
                    }
                }
            }
        }
    } else {
        var rng = std.Random.DefaultPrng.init(blind_seed);
        const rr = rng.random();
        for (0..blind_budget) |_| {
            const ai = rr.uintLessThan(usize, N_CONJ_ATOMS);
            var aj = rr.uintLessThan(usize, N_CONJ_ATOMS);
            while (aj == ai) aj = rr.uintLessThan(usize, N_CONJ_ATOMS);
            const op = rr.uintLessThan(usize, 2);
            for (0..NSAMP) |s| {
                const a1 = atom_raw[ai][s] > 0.5;
                const b1 = atom_raw[aj][s] > 0.5;
                raw[s] = if (if (op == 0) (a1 and b1) else (a1 or b1)) 1.0 else 0.0;
            }
            const r = categoricalSearch(&raw, Y, 2);
            evals += 1;
            if (r.val_acc > best_val) {
                best_val = r.val_acc;
                best_test = r.test_acc;
                best_raw = raw;
            }
        }
    }
    return .{ .best_val = best_val, .best_test = best_test, .best_raw = best_raw, .evals = evals, .n_included = n_included };
}

fn tryDistinct(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64) FamResult {
    return tryDistinctGate(grid, Y, basisX, false);
}
fn tryDistinctGate(grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64, force: bool) FamResult {
    if (!force and sigDistinct(grid, Y) <= WEAK_SIG) return UNSOLVED_CHEAP;
    var evals: usize = 1;
    var raw_ident: [NSAMP]f64 = undefined;
    var lensed: [NSAMP]f64 = undefined;
    var best_val: f64 = -1;
    var best_test: f64 = 0;
    var best_raw: [NSAMP]f64 = undefined;
    // single-window
    for (WINDOWS) |w| {
        for (0..NSAMP) |s| raw_ident[s] = @floatFromInt(numDistinct(grid[s], w));
        for (LENSES) |lens| {
            const r = identOrCategorical(&raw_ident, lens, &lensed, Y, 8);
            evals += 1;
            if (r.val_acc > best_val) {
                best_val = r.val_acc;
                best_test = r.test_acc;
                best_raw = lensed;
            }
        }
    }
    // two-window difference
    for (0..N_WINDOWS) |wi| {
        for (wi + 1..N_WINDOWS) |wj| {
            for (0..NSAMP) |s| raw_ident[s] = @as(f64, @floatFromInt(numDistinct(grid[s], WINDOWS[wi]))) - @as(f64, @floatFromInt(numDistinct(grid[s], WINDOWS[wj]))) + 8.0;
            for (LENSES) |lens| {
                const r = identOrCategorical(&raw_ident, lens, &lensed, Y, 17);
                evals += 1;
                if (r.val_acc > best_val) {
                    best_val = r.val_acc;
                    best_test = r.test_acc;
                    best_raw = lensed;
                }
            }
        }
    }
    // conjunction sub-search only if plain single/diff insufficient (mirrors
    // "the ladder leaves it stuck, escalate" from tier8_assembled).
    if (best_test < COVER) {
        const cr = distinctConjSearch(grid, Y, true, 0, 0);
        evals += cr.evals;
        if (cr.best_val > best_val) {
            best_val = cr.best_val;
            best_test = cr.best_test;
            best_raw = cr.best_raw;
        }
    }
    return finalizeGrowable(best_val, best_test, evals, basisX, &best_raw);
}

fn tryFamily(f: FamilyId, grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64) FamResult {
    return switch (f) {
        .base => tryBase(grid, Y),
        .gf2 => tryGf2(grid, Y),
        .thresh => tryThresh(grid, Y, basisX),
        .mixr => tryMixr(grid, Y, basisX),
        .ratio => tryRatio(grid, Y, basisX),
        .run => tryRun(grid, Y, basisX),
        .rank => tryRank(grid, Y, basisX),
        .distinct => tryDistinct(grid, Y, basisX),
    };
}

/// Full-grid-search cost of a family with NO signature gate. Used by (a) the
/// HAND arm (the human already knows the shape is needed, so always invests
/// the full grid), and (b) Phase 1 of the assembled loop for families already
/// KNOWN/promoted (once a shape is part of the toolkit it is applied directly,
/// like base/gf2, which have no gate at all -- the signature gate's job is
/// specifically to decide whether an UNFAMILIAR shape is worth a first try).
fn tryFamilyForced(f: FamilyId, grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64) FamResult {
    return switch (f) {
        .base => tryBase(grid, Y),
        .gf2 => tryGf2(grid, Y),
        .thresh => tryThreshGate(grid, Y, basisX, true),
        .mixr => tryMixrGate(grid, Y, basisX, true),
        .ratio => tryRatioGate(grid, Y, basisX, true),
        .run => tryRunGate(grid, Y, basisX, true),
        .rank => tryRankGate(grid, Y, basisX, true),
        .distinct => tryDistinctGate(grid, Y, basisX, true),
    };
}

// ═══════════════════════════════════════════════════════════════════════
// Router: 14-feature descriptor + nearest-same-class-neighbor ranking
// (generalizes E2's k-NN vote to a full RANKING over all 8 families, since
// the assembled loop needs an order to walk, not just a top-1 guess).
// ═══════════════════════════════════════════════════════════════════════
const NFEAT = 14;

fn signedAgreement(f01: f64, y: f64) f64 {
    const fb: f64 = if (f01 > 0.5) 1.0 else -1.0;
    const yb: f64 = if (y > 0.5) 1.0 else -1.0;
    return fb * yb;
}

fn computeDescriptor(grid: []const [NCELL]u8, Y: []const f64) [NFEAT]f64 {
    var d: [NFEAT]f64 = undefined;
    const nval: f64 = @floatFromInt(NVA - NTR);

    // d0: max|signed agreement| monomial162 (deg 1..4), also flatness (d6)
    var d0: f64 = 0;
    var sum_a: f64 = 0;
    var sum_a2: f64 = 0;
    var n_mono: f64 = 0;
    var m: u16 = 1;
    while (m <= 255) : (m += 1) {
        const mask: u8 = @intCast(m);
        const w = @popCount(mask);
        if (w < 1 or w > 4) continue;
        var acc: f64 = 0;
        for (NTR..NVA) |s| acc += signedAgreement(monomialSign(mask, grid[s]), Y[s]);
        acc /= nval;
        d0 = @max(d0, @abs(acc));
        sum_a += acc;
        sum_a2 += acc * acc;
        n_mono += 1;
    }
    d[0] = d0;
    const mean_a = sum_a / n_mono;
    d[6] = @sqrt(@max(0.0, sum_a2 / n_mono - mean_a * mean_a));

    // d1: max|signed agreement| walsh255
    var d1: f64 = 0;
    m = 1;
    while (m <= 255) : (m += 1) {
        const mask: u8 = @intCast(m);
        var acc: f64 = 0;
        for (NTR..NVA) |s| acc += signedAgreement(walshParity(mask, grid[s]), Y[s]);
        acc /= nval;
        d1 = @max(d1, @abs(acc));
    }
    d[1] = d1;

    // d2: max|signed agreement| single cmp bits (28) [gf2 signal]
    var d2: f64 = 0;
    for (0..NPAIR) |p| {
        var acc: f64 = 0;
        for (NTR..NVA) |s| acc += signedAgreement(@floatFromInt(cmpBit(grid[s], p)), Y[s]);
        acc /= nval;
        d2 = @max(d2, @abs(acc));
    }
    d[2] = d2;

    // d3: max|signed agreement| over 24 sampled cmp-subset parities [gf2-joint signal]
    var d3: f64 = 0;
    var rng = std.Random.DefaultPrng.init(0xD4C0DE);
    const rr = rng.random();
    for (0..24) |_| {
        const sz = 2 + (rr.int(u5) % 7);
        var pm: u32 = 0;
        var placed: usize = 0;
        while (placed < sz) {
            const p = rr.int(u5) % NPAIR;
            const bit = @as(u32, 1) << @intCast(p);
            if (pm & bit == 0) {
                pm |= bit;
                placed += 1;
            }
        }
        var acc: f64 = 0;
        for (NTR..NVA) |s| {
            var par: u1 = 0;
            for (0..NPAIR) |p| if (pm & (@as(u32, 1) << @intCast(p)) != 0) {
                par ^= cmpBit(grid[s], p);
            };
            acc += signedAgreement(@floatFromInt(par), Y[s]);
        }
        acc /= nval;
        d3 = @max(d3, @abs(acc));
    }
    d[3] = d3;

    // d4: best world_sum_mod VAL accuracy (6 primes)
    var raw: [NSAMP]f64 = undefined;
    const primes = [_]u8{ 2, 3, 5, 7, 11, 13 };
    var d4: f64 = 0;
    for (primes) |k| {
        for (0..NSAMP) |s| raw[s] = @floatFromInt(gridSum(grid[s]) % k);
        d4 = @max(d4, categoricalSearch(&raw, Y, k).val_acc);
    }
    d[4] = d4;

    // d5: best world_count3_mod VAL accuracy (k=2..8)
    var d5: f64 = 0;
    var k3: u8 = 2;
    while (k3 <= 8) : (k3 += 1) {
        for (0..NSAMP) |s| raw[s] = @floatFromInt(countAtLeast(grid[s], 3) % k3);
        d5 = @max(d5, categoricalSearch(&raw, Y, k3).val_acc);
    }
    d[5] = d5;

    // d7: base-rate skew (TRAIN split)
    var mean_y: f64 = 0;
    for (0..NTR) |s| mean_y += Y[s];
    mean_y /= @floatFromInt(NTR);
    d[7] = @abs(mean_y - 0.5);

    // d8: max over cell i of VAL accuracy of star(i) mod 3 [rank-mod3 signal:
    // gf2 cannot see this (nonlinear over GF2), so it is a genuinely NEW
    // signal this router has that E2's own descriptor did not need.
    var d8: f64 = 0;
    for (0..NCELL) |cell| {
        for (0..NSAMP) |s| raw[s] = @floatFromInt(starCmp(grid[s], cell) % 3);
        d8 = @max(d8, categoricalSearch(&raw, Y, 3).val_acc);
    }
    d[8] = d8;

    // d9-d13: the six growable families' own cheap signature probes.
    d[9] = sigMixr(grid, Y);
    d[10] = sigRatio(grid, Y);
    d[11] = sigRun(grid, Y);
    d[12] = sigThresh(grid, Y);
    d[13] = sigDistinct(grid, Y);

    return d;
}

const TargetRecord = struct { name: []const u8, desc: [NFEAT]f64, true_family: FamilyId };
const Stand = struct { mean: [NFEAT]f64, sd: [NFEAT]f64 };

fn fitStand(recs: []const TargetRecord) Stand {
    var mean: [NFEAT]f64 = [_]f64{0} ** NFEAT;
    for (recs) |r| for (0..NFEAT) |f| {
        mean[f] += r.desc[f];
    };
    const n: f64 = @floatFromInt(recs.len);
    for (0..NFEAT) |f| mean[f] /= n;
    var sd: [NFEAT]f64 = [_]f64{0} ** NFEAT;
    for (recs) |r| for (0..NFEAT) |f| {
        const dd = r.desc[f] - mean[f];
        sd[f] += dd * dd;
    };
    for (0..NFEAT) |f| sd[f] = @max(1e-6, @sqrt(sd[f] / n));
    return .{ .mean = mean, .sd = sd };
}
fn standardize(d: [NFEAT]f64, st: Stand) [NFEAT]f64 {
    var out: [NFEAT]f64 = undefined;
    for (0..NFEAT) |f| out[f] = (d[f] - st.mean[f]) / st.sd[f];
    return out;
}
fn dist2(a: [NFEAT]f64, b: [NFEAT]f64) f64 {
    var s: f64 = 0;
    for (0..NFEAT) |f| {
        const dd = a[f] - b[f];
        s += dd * dd;
    }
    return s;
}

/// Full ranking of all 8 families by "distance to nearest same-class
/// training neighbor" (ascending -- closer class = more likely aim). This
/// generalizes k-NN-vote classification (E2's design) into an ORDER the
/// assembled loop can walk (needed for multi-shot: if the top pick fails,
/// try the next, etc.) `excl`, if set, skips that training-record index
/// (leave-one-out, used only by the router health-check).
fn rankFamiliesExcl(desc: [NFEAT]f64, recs: []const TargetRecord, st: Stand, excl: ?usize) [N_FAM]FamilyId {
    var best_dist: [N_FAM]f64 = [_]f64{std.math.inf(f64)} ** N_FAM;
    const qs = standardize(desc, st);
    for (recs, 0..) |r, i| {
        if (excl) |e| if (e == i) continue;
        const ts = standardize(r.desc, st);
        const dd = dist2(qs, ts);
        const fi = @intFromEnum(r.true_family);
        if (dd < best_dist[fi]) best_dist[fi] = dd;
    }
    var idxs: [N_FAM]usize = .{ 0, 1, 2, 3, 4, 5, 6, 7 };
    const Ctx = struct {
        d: *const [N_FAM]f64,
        fn lt(self: @This(), a: usize, b: usize) bool {
            return self.d[a] < self.d[b];
        }
    };
    std.sort.pdq(usize, &idxs, Ctx{ .d = &best_dist }, Ctx.lt);
    var order: [N_FAM]FamilyId = undefined;
    for (0..N_FAM) |i| order[i] = @enumFromInt(idxs[i]);
    return order;
}
fn rankFamilies(desc: [NFEAT]f64, recs: []const TargetRecord, st: Stand) [N_FAM]FamilyId {
    return rankFamiliesExcl(desc, recs, st, null);
}
fn routerLOOAccuracy(recs: []const TargetRecord, st: Stand) f64 {
    var correct: usize = 0;
    for (recs, 0..) |r, i| {
        const order = rankFamiliesExcl(r.desc, recs, st, i);
        if (order[0] == r.true_family) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(recs.len));
}

// ═══════════════════════════════════════════════════════════════════════
// The battery: B (rq1, 11) + C (transcribed, 11) + D (bd, 11) + 30
// minority-class "extra" targets (5 per growable family, so the router has
// enough labeled examples per class) + 10 FRESH FRONTIER targets.
// ═══════════════════════════════════════════════════════════════════════
const BATTERY_SEED: u64 = 0xF5B47E5920260711;

const CTarget = struct { name: []const u8, e2_spec: ?e2.PredSpec = null };
const BATTERY_C = [_]CTarget{
    .{ .name = "C01 XOR 0x0F", .e2_spec = .{ .kind = .xor_cells, .mask = 0x0F } },
    .{ .name = "C02 parity XOR 0x33", .e2_spec = .{ .kind = .parity_xor, .mask = 0x33 } },
    .{ .name = "C03 XOR 0x55", .e2_spec = .{ .kind = .xor_cells, .mask = 0x55 } },
    .{ .name = "C04 XOR 0xAA", .e2_spec = .{ .kind = .xor_cells, .mask = 0xAA } },
    .{ .name = "C05 XOR 0x3C", .e2_spec = .{ .kind = .xor_cells, .mask = 0x3C } },
    .{ .name = "C06 XOR 0x66", .e2_spec = .{ .kind = .xor_cells, .mask = 0x66 } },
    .{ .name = "C07 XOR 0x99", .e2_spec = .{ .kind = .xor_cells, .mask = 0x99 } },
    .{ .name = "C08 parity count", .e2_spec = .{ .kind = .parity_count } },
    .{ .name = "C09 inv parity", .e2_spec = null },
    .{ .name = "C10 parity XOR 0x0F", .e2_spec = .{ .kind = .parity_xor, .mask = 0x0F } },
    .{ .name = "C11 XOR 0x37", .e2_spec = .{ .kind = .xor_cells, .mask = 0x37 } },
};
const BATTERY_C_TRUE_FAMILY = [_]FamilyId{ .gf2, .gf2, .gf2, .gf2, .gf2, .gf2, .gf2, .base, .gf2, .gf2, .gf2 };
const BATTERY_B_TRUE_FAMILY = [_]FamilyId{ .base, .base, .base, .base, .base, .base, .base, .base, .gf2, .base, .gf2 };

fn labelBatteryC(g: [NCELL]u8, idx: usize) f64 {
    const t = BATTERY_C[idx];
    if (t.e2_spec) |spec| return e2.label(g, spec);
    return @floatFromInt(inversionAll(g) & 1);
}
fn b2f(b: bool) f64 {
    return if (b) 1.0 else 0.0;
}

/// 30 extras (5 per growable family, ids 0-29) + 10 frontier targets (ids
/// 30-39, processed in this exact order so later targets can reuse a family
/// promoted by an earlier one -- the interference/attribution check).
const FRESH_NAMES = [_][]const u8{
    "TE1 count(>=1)%4==0",       "TE2 count(>=2)%3==0",       "TE3 count(>=5)%2==0",
    "TE4 count(>=1)%3==1",       "TE5 count(>=4)%5==0",       "ME1 sum%2==c1%2",
    "ME2 c2%3==inv%3",           "ME3 sum%4==inv%4",          "ME4 c1%3==c5%3",
    "ME5 sum%5==c4%5",           "RE1 c2*c5%4==0",            "RE2 c1*c4%5==0",
    "RE3 c3*c1%3==0",            "RE4 c2*c4%3==0",            "RE5 c1*c5%2==0",
    "RN1 run(>=2)>=4",           "RN2 run(>=4)>=2",           "RN3 numLocalMax>=2",
    "RN4 firstDescent<3",        "RN5 run(>=2)%3==0",         "RK1 star(1)%3==0",
    "RK2 star(5)%4==0",          "RK3 star(7)%3==1",          "RK4 star(2)%3==0",
    "RK5 star(6)%4==1",          "DS1 nd(evens)==2",          "DS2 nd(odds)==3",
    "DS3 nd(mid4)==2",           "DS4 nd(all8)==3",           "DS5 nd(first6)>=4",
    "MIXMOD1 sum%3==c3%3",       "MIXMOD2 sum%4==c2%4",       "RATIO1 c4*c1%3==0",
    "RUN1 maxRunGE3>=3",         "ORDER2 star(0)%2",          "ORDER2_MOD3 star(0)%3==0",
    "RANK2_MOD3 star(3)%3==0",   "WALL_EASY nd(all8)>=4",     "WALL_MED nd(lo4)==nd(hi4)",
    "WALL_HARD nd(lo4)=2&hi4=2",
};
const FRESH_TRUE_FAMILY = [_]FamilyId{
    .thresh,  .thresh,  .thresh,  .thresh,   .thresh,
    .mixr,    .mixr,    .mixr,    .mixr,     .mixr,
    .ratio,   .ratio,   .ratio,   .ratio,    .ratio,
    .run,     .run,     .run,     .run,      .run,
    .rank,    .rank,    .rank,    .rank,     .rank,
    .distinct, .distinct, .distinct, .distinct, .distinct,
    .mixr,    .mixr,    .ratio,   .run,
    .gf2,     .rank,    .rank,
    .distinct, .distinct, .distinct,
};
const N_FRESH = FRESH_NAMES.len;
const FRONTIER_START: usize = 30;
const N_FRONTIER: usize = 10;

comptime {
    if (FRESH_NAMES.len != FRESH_TRUE_FAMILY.len) @compileError("fresh arrays length mismatch");
    if (N_FRESH != FRONTIER_START + N_FRONTIER) @compileError("frontier count mismatch");
}

fn freshLabel(id: usize, g: [NCELL]u8) f64 {
    return switch (id) {
        0 => b2f(countAtLeast(g, 1) % 4 == 0),
        1 => b2f(countAtLeast(g, 2) % 3 == 0),
        2 => b2f(countAtLeast(g, 5) % 2 == 0),
        3 => b2f(countAtLeast(g, 1) % 3 == 1),
        4 => b2f(countAtLeast(g, 4) % 5 == 0),
        5 => b2f(gridSum(g) % 2 == countAtLeast(g, 1) % 2),
        6 => b2f(countAtLeast(g, 2) % 3 == inversionAll(g) % 3),
        7 => b2f(gridSum(g) % 4 == inversionAll(g) % 4),
        8 => b2f(countAtLeast(g, 1) % 3 == countAtLeast(g, 5) % 3),
        9 => b2f(gridSum(g) % 5 == countAtLeast(g, 4) % 5),
        10 => b2f((countAtLeast(g, 2) * countAtLeast(g, 5)) % 4 == 0),
        11 => b2f((countAtLeast(g, 1) * countAtLeast(g, 4)) % 5 == 0),
        12 => b2f((countAtLeast(g, 3) * countAtLeast(g, 1)) % 3 == 0),
        13 => b2f((countAtLeast(g, 2) * countAtLeast(g, 4)) % 3 == 0),
        14 => b2f((countAtLeast(g, 1) * countAtLeast(g, 5)) % 2 == 0),
        15 => b2f(maxRunGE(g, 2) >= 4),
        16 => b2f(maxRunGE(g, 4) >= 2),
        17 => b2f(numLocalMax(g) >= 2),
        18 => b2f(firstDescentPos(g) < 3),
        19 => b2f(maxRunGE(g, 2) % 3 == 0),
        20 => b2f(starCmp(g, 1) % 3 == 0),
        21 => b2f(starCmp(g, 5) % 4 == 0),
        22 => b2f(starCmp(g, 7) % 3 == 1),
        23 => b2f(starCmp(g, 2) % 3 == 0),
        24 => b2f(starCmp(g, 6) % 4 == 1),
        25 => b2f(numDistinct(g, 0x55) == 2),
        26 => b2f(numDistinct(g, 0xAA) == 3),
        27 => b2f(numDistinct(g, 0x3C) == 2),
        28 => b2f(numDistinct(g, 0xFF) == 3),
        29 => b2f(numDistinct(g, 0x3F) >= 4),
        30 => b2f(gridSum(g) % 3 == countAtLeast(g, 3) % 3), // MIXMOD1
        31 => b2f(gridSum(g) % 4 == countAtLeast(g, 2) % 4), // MIXMOD2
        32 => b2f((countAtLeast(g, 4) * countAtLeast(g, 1)) % 3 == 0), // RATIO1
        33 => b2f(maxRunGE(g, 3) >= 3), // RUN1
        34 => b2f(starCmp(g, 0) % 2 == 1), // ORDER2 (mod2 -- expected gf2-solvable)
        35 => b2f(starCmp(g, 0) % 3 == 0), // ORDER2_MOD3 (genuine rank frontier)
        36 => b2f(starCmp(g, 3) % 3 == 0), // RANK2_MOD3
        37 => b2f(numDistinct(g, 0xFF) >= 4), // WALL_EASY
        38 => b2f(numDistinct(g, 0x0F) == numDistinct(g, 0xF0)), // WALL_MED
        39 => b2f(numDistinct(g, 0x0F) == 2 and numDistinct(g, 0xF0) == 2), // WALL_HARD
        else => 0,
    };
}

const Target = struct { name: []const u8, true_family: FamilyId, kind: enum { batB, batC, batD, fresh }, idx: usize = 0 };

fn buildPool(alloc: std.mem.Allocator, battery_b: []const rq1.BatteryTarget) ![]Target {
    var list = std.ArrayList(Target).init(alloc);
    for (0..11) |i| try list.append(.{ .name = battery_b[i].name, .true_family = BATTERY_B_TRUE_FAMILY[i], .kind = .batB, .idx = i });
    for (0..11) |i| try list.append(.{ .name = BATTERY_C[i].name, .true_family = BATTERY_C_TRUE_FAMILY[i], .kind = .batC, .idx = i });
    for (0..11) |i| try list.append(.{ .name = bd.BATTERY_D[i].name, .true_family = .base, .kind = .batD, .idx = i });
    for (0..30) |i| try list.append(.{ .name = FRESH_NAMES[i], .true_family = FRESH_TRUE_FAMILY[i], .kind = .fresh, .idx = i });
    return list.toOwnedSlice();
}
fn buildFrontier(alloc: std.mem.Allocator) ![]Target {
    var list = std.ArrayList(Target).init(alloc);
    for (FRONTIER_START..N_FRESH) |i| try list.append(.{ .name = FRESH_NAMES[i], .true_family = FRESH_TRUE_FAMILY[i], .kind = .fresh, .idx = i });
    return list.toOwnedSlice();
}
fn fillY(grid: []const [NCELL]u8, t: Target, battery_b: []const rq1.BatteryTarget, Y: []f64) void {
    switch (t.kind) {
        .batB => for (0..NSAMP) |s| {
            Y[s] = rq1.labelBattery(grid[s], battery_b[t.idx]);
        },
        .batC => for (0..NSAMP) |s| {
            Y[s] = labelBatteryC(grid[s], t.idx);
        },
        .batD => for (0..NSAMP) |s| {
            Y[s] = bd.labelTarget(grid[s], bd.BATTERY_D[t.idx]);
        },
        .fresh => for (0..NSAMP) |s| {
            Y[s] = freshLabel(t.idx, grid[s]);
        },
    }
}

// ═══════════════════════════════════════════════════════════════════════
// THE ASSEMBLED LOOP
// ═══════════════════════════════════════════════════════════════════════
const Arm = enum { hand, autonomous, auto_nosmartgen, auto_norouter };
fn armName(a: Arm) []const u8 {
    return switch (a) {
        .hand => "hand",
        .autonomous => "autonomous",
        .auto_nosmartgen => "auto_nosmartgen",
        .auto_norouter => "auto_norouter",
    };
}
const Mechanism = enum { hand, known, smartgen, none };
fn mechName(m: Mechanism) []const u8 {
    return switch (m) {
        .hand => "hand",
        .known => "known",
        .smartgen => "smartgen",
        .none => "none",
    };
}
const SolveOutcome = struct { solved: bool, family: FamilyId, mechanism: Mechanism, evals: usize, test_acc: f64, ranked0: FamilyId = .base };

fn newKnown() [N_FAM]bool {
    var known: [N_FAM]bool = [_]bool{false} ** N_FAM;
    known[@intFromEnum(FamilyId.base)] = true;
    known[@intFromEnum(FamilyId.gf2)] = true;
    return known;
}

fn solveTarget(t: Target, grid: []const [NCELL]u8, Y: []const f64, basisX: *const [NSAMP][NBASIS]f64, arm: Arm, known: *[N_FAM]bool, recs: []const TargetRecord, st: Stand) SolveOutcome {
    if (arm == .hand) {
        const r = tryFamilyForced(t.true_family, grid, Y, basisX);
        if (r.solved) known[@intFromEnum(t.true_family)] = true;
        return .{ .solved = r.solved, .family = t.true_family, .mechanism = .hand, .evals = r.evals, .test_acc = r.test_acc };
    }

    const ranked: [N_FAM]FamilyId = if (arm == .auto_norouter) FIXED_ORDER else blk: {
        const desc = computeDescriptor(grid, Y);
        break :blk rankFamilies(desc, recs, st);
    };

    var evals: usize = 0;
    // Phase 1: known families, ranked order, no signature gate (already
    // established -- applied directly, like base/gf2).
    for (ranked) |f| {
        if (known[@intFromEnum(f)]) {
            const r = tryFamilyForced(f, grid, Y, basisX);
            evals += r.evals;
            if (r.solved) return .{ .solved = true, .family = f, .mechanism = .known, .evals = evals, .test_acc = r.test_acc, .ranked0 = ranked[0] };
        }
    }
    // Phase 2 (autonomous / auto_norouter only): smart-gen on the top-ranked
    // NOT-yet-known growable family -- signature-gated (E3-style: the
    // cheap probe decides whether the shape is worth the full grid).
    if (arm == .autonomous or arm == .auto_norouter) {
        for (ranked) |f| {
            if (!known[@intFromEnum(f)] and isGrowable(f)) {
                const r = tryFamily(f, grid, Y, basisX);
                evals += r.evals;
                if (r.solved) {
                    known[@intFromEnum(f)] = true;
                    return .{ .solved = true, .family = f, .mechanism = .smartgen, .evals = evals, .test_acc = r.test_acc, .ranked0 = ranked[0] };
                }
            }
        }
    }
    return .{ .solved = false, .family = .base, .mechanism = .none, .evals = evals, .test_acc = 0, .ranked0 = ranked[0] };
}

// ═══════════════════════════════════════════════════════════════════════
// Per-seed pipeline: build grid, battery, router; run all 4 arms.
// ═══════════════════════════════════════════════════════════════════════
const ArmTotals = struct {
    solved_b: usize = 0,
    solved_c: usize = 0,
    solved_d: usize = 0,
    solved_extra: usize = 0,
    solved_frontier: usize = 0,
    evals_total: usize = 0,
};

const RowsBuf = std.ArrayList(u8);

fn runSeed(alloc: std.mem.Allocator, seed: u64, out: anytype, cw: anytype, arms_to_run: []const Arm) !void {
    var grid: [NSAMP][NCELL]u8 = undefined;
    var gprng = std.Random.DefaultPrng.init(seed);
    const grand = gprng.random();
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = grand.intRangeAtMost(u8, 0, 5);
    };

    var basisX: [NSAMP][NBASIS]f64 = undefined;
    buildBasis(&grid, &basisX);

    var bprng = std.Random.DefaultPrng.init(BATTERY_SEED);
    const battery_b = try rq1.generateBatteryB(bprng.random(), alloc);

    const pool = try buildPool(alloc, battery_b);
    const frontier = try buildFrontier(alloc);

    // Build router training records (descriptor computed once per pool
    // target, reused across all arms/seeds within this function).
    var recs = try alloc.alloc(TargetRecord, pool.len);
    var Y: [NSAMP]f64 = undefined;
    for (pool, 0..) |t, i| {
        fillY(&grid, t, battery_b, &Y);
        recs[i] = .{ .name = t.name, .desc = computeDescriptor(&grid, &Y), .true_family = t.true_family };
    }
    const st = fitStand(recs);
    const loo_acc = routerLOOAccuracy(recs, st);
    try out.print("  [seed 0x{X:0>16}] router leave-one-out top-1 accuracy over {d} labeled pool targets: {d:.3}\n", .{ seed, recs.len, loo_acc });
    try cw.print("router_loo,0x{X:0>16},,,,{d},{d:.4},,,,\n", .{ seed, recs.len, loo_acc });

    for (arms_to_run) |arm| {
        var known = newKnown();
        var tot = ArmTotals{};
        try out.print("  ── arm {s} (seed 0x{X:0>16}) ──\n", .{ armName(arm), seed });
        for (pool, 0..) |t, i| {
            fillY(&grid, t, battery_b, &Y);
            const r = solveTarget(t, &grid, &Y, &basisX, arm, &known, recs, st);
            tot.evals_total += r.evals;
            switch (t.kind) {
                .batB => if (r.solved) {
                    tot.solved_b += 1;
                },
                .batC => if (r.solved) {
                    tot.solved_c += 1;
                },
                .batD => if (r.solved) {
                    tot.solved_d += 1;
                },
                .fresh => if (r.solved) {
                    tot.solved_extra += 1;
                },
            }
            try cw.print("target,0x{X:0>16},{s},\"{s}\",{s},{s},{s},{d},{d},{d:.4},{s}\n", .{ seed, armName(arm), t.name, famName(t.true_family), famName(r.family), mechName(r.mechanism), @intFromBool(r.solved), r.evals, r.test_acc, famName(r.ranked0) });
            _ = i;
        }
        for (frontier) |t| {
            fillY(&grid, t, battery_b, &Y);
            const r = solveTarget(t, &grid, &Y, &basisX, arm, &known, recs, st);
            tot.evals_total += r.evals;
            if (r.solved) tot.solved_frontier += 1;
            try out.print("      {s:<28} true={s:<9} solved={s:<5} via={s:<9} mech={s:<9} evals={d:<6} test_acc={d:.4}\n", .{ t.name, famName(t.true_family), if (r.solved) "YES" else "no", famName(r.family), mechName(r.mechanism), r.evals, r.test_acc });
            try cw.print("frontier,0x{X:0>16},{s},\"{s}\",{s},{s},{s},{d},{d},{d:.4},{s}\n", .{ seed, armName(arm), t.name, famName(t.true_family), famName(r.family), mechName(r.mechanism), @intFromBool(r.solved), r.evals, r.test_acc, famName(r.ranked0) });
        }
        try out.print("  arm {s} totals: B {d}/11  C {d}/11  D {d}/11  extras {d}/30  FRONTIER {d}/{d}  evals={d}\n\n", .{ armName(arm), tot.solved_b, tot.solved_c, tot.solved_d, tot.solved_extra, tot.solved_frontier, N_FRONTIER, tot.evals_total });
        try cw.print("arm_totals,0x{X:0>16},{s},,,,,{d},{d:.4},,\n", .{ seed, armName(arm), tot.evals_total, 0.0 });
        try cw.print("arm_summary,0x{X:0>16},{s},B={d}/11;C={d}/11;D={d}/11;extra={d}/30;frontier={d}/{d};evals={d},,,,,,,,\n", .{ seed, armName(arm), tot.solved_b, tot.solved_c, tot.solved_d, tot.solved_extra, tot.solved_frontier, N_FRONTIER, tot.evals_total });
    }
}

// ═══════════════════════════════════════════════════════════════════════
// diag: WALL_HARD blind-vs-steered conjunction-search comparison (the E3
// "coverage steered by a structural signature" gap, isolated).
// ═══════════════════════════════════════════════════════════════════════
fn runDiag(out: anytype, cw: anytype) !void {
    try out.print("=== diag: WALL_HARD blind-vs-steered conjunction search (seed 0x{X:0>16}) ===\n", .{SEEDS[0]});
    var grid: [NSAMP][NCELL]u8 = undefined;
    var gprng = std.Random.DefaultPrng.init(SEEDS[0]);
    const grand = gprng.random();
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = grand.intRangeAtMost(u8, 0, 5);
    };
    var Y: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| Y[s] = freshLabel(39, grid[s]); // WALL_HARD

    const steered = distinctConjSearch(&grid, &Y, true, 0, 0);
    try out.print("STEERED (coverage inclusion: only atoms with VAL acc > {d:.2}): included={d} evals={d} best_val={d:.4} best_test={d:.4} certifies={any}\n", .{ WEAK_SIG, steered.n_included, steered.evals, steered.best_val, steered.best_test, steered.best_test >= COVER });
    try cw.print("diag_wallhard,steered,,,,,{d},{d:.4},{d:.4},{d}\n", .{ steered.evals, steered.best_val, steered.best_test, steered.n_included });

    // Equal-budget blind control: same number of pair-evals as steered found
    // (excluding the 24 atom-scoring evals shared by both), 3 blind seeds.
    const blind_budget = if (steered.evals > 24) steered.evals - 24 else 30;
    var any_blind_solves = false;
    for ([_]u64{ 0xB1, 0xB2, 0xB3 }) |bs| {
        const blind = distinctConjSearch(&grid, &Y, false, blind_budget, bs);
        try out.print("BLIND (seed 0x{X}, budget={d} random pairs, equal to steered's post-atom-scoring budget): best_val={d:.4} best_test={d:.4} certifies={any}\n", .{ bs, blind_budget, blind.best_val, blind.best_test, blind.best_test >= COVER });
        try cw.print("diag_wallhard,blind_0x{X},,,,,{d},{d:.4},{d:.4},0\n", .{ bs, blind.evals, blind.best_val, blind.best_test });
        if (blind.best_test >= COVER) any_blind_solves = true;
    }
    try out.print("VERDICT: steered {s}certifies WALL_HARD; blind (same budget, 3 seeds) {s}certifies.\n", .{ if (steered.best_test >= COVER) "" else "NEVER ", if (any_blind_solves) "sometimes" else "NEVER" });
}

// ═══════════════════════════════════════════════════════════════════════
// selftest
// ═══════════════════════════════════════════════════════════════════════
fn runSelftest(out: anytype) !void {
    initPairs();
    var grid: [NSAMP][NCELL]u8 = undefined;
    var gprng = std.Random.DefaultPrng.init(SEEDS[0]);
    const grand = gprng.random();
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = grand.intRangeAtMost(u8, 0, 5);
    };
    var basisX: [NSAMP][NBASIS]f64 = undefined;
    buildBasis(&grid, &basisX);
    var Y: [NSAMP]f64 = undefined;

    try out.print("=== selftest ===\n", .{});

    // 1. ORDER2 (mod2 lens) should be trivially solved by gf2 (linear over
    //    GF2 -- the integration finding this file's header documents).
    for (0..NSAMP) |s| Y[s] = freshLabel(34, grid[s]);
    const order2_gf2 = tryGf2(&grid, &Y);
    const order2_base = tryBase(&grid, &Y);
    try out.print("ORDER2 (star0 mod2): gf2 acc={d:.4} solved={any} | base acc={d:.4} solved={any}\n", .{ order2_gf2.test_acc, order2_gf2.solved, order2_base.test_acc, order2_base.solved });
    if (!order2_gf2.solved) try out.print("  ** UNEXPECTED: analytical proof says gf2 should certify ORDER2 exactly; report this deviation. **\n", .{});

    // 2. ORDER2_MOD3 / RANK2_MOD3 should NOT be solved by gf2 or base, but
    //    SHOULD be solved by rank.
    for (0..NSAMP) |s| Y[s] = freshLabel(35, grid[s]);
    const o3_gf2 = tryGf2(&grid, &Y);
    const o3_base = tryBase(&grid, &Y);
    const o3_rank = tryRankGate(&grid, &Y, &basisX, true);
    try out.print("ORDER2_MOD3 (star0 mod3): gf2={d:.4}({any}) base={d:.4}({any}) rank={d:.4}({any}) r2={d:.3}\n", .{ o3_gf2.test_acc, o3_gf2.solved, o3_base.test_acc, o3_base.solved, o3_rank.test_acc, o3_rank.solved, o3_rank.r2 });

    // 3. MIXMOD1 should not be solved by base/gf2 but should be by mixr.
    for (0..NSAMP) |s| Y[s] = freshLabel(30, grid[s]);
    const mm_gf2 = tryGf2(&grid, &Y);
    const mm_base = tryBase(&grid, &Y);
    const mm_mixr = tryMixrGate(&grid, &Y, &basisX, true);
    try out.print("MIXMOD1: gf2={d:.4}({any}) base={d:.4}({any}) mixr={d:.4}({any}) r2={d:.3}\n", .{ mm_gf2.test_acc, mm_gf2.solved, mm_base.test_acc, mm_base.solved, mm_mixr.test_acc, mm_mixr.solved, mm_mixr.r2 });

    // 4. RATIO1 via ratio; RUN1 via run.
    for (0..NSAMP) |s| Y[s] = freshLabel(32, grid[s]);
    const rt_ratio = tryRatioGate(&grid, &Y, &basisX, true);
    try out.print("RATIO1: ratio acc={d:.4} solved={any} r2={d:.3}\n", .{ rt_ratio.test_acc, rt_ratio.solved, rt_ratio.r2 });
    for (0..NSAMP) |s| Y[s] = freshLabel(33, grid[s]);
    const rn_run = tryRunGate(&grid, &Y, &basisX, true);
    try out.print("RUN1: run acc={d:.4} solved={any} r2={d:.3}\n", .{ rn_run.test_acc, rn_run.solved, rn_run.r2 });

    // 5. WALL_EASY/MED via distinct; WALL_HARD needs the conjunction step.
    for (0..NSAMP) |s| Y[s] = freshLabel(37, grid[s]);
    const we_d = tryDistinctGate(&grid, &Y, &basisX, true);
    try out.print("WALL_EASY: distinct acc={d:.4} solved={any}\n", .{ we_d.test_acc, we_d.solved });
    for (0..NSAMP) |s| Y[s] = freshLabel(38, grid[s]);
    const wm_d = tryDistinctGate(&grid, &Y, &basisX, true);
    try out.print("WALL_MED: distinct acc={d:.4} solved={any}\n", .{ wm_d.test_acc, wm_d.solved });
    for (0..NSAMP) |s| Y[s] = freshLabel(39, grid[s]);
    const wh_d = tryDistinctGate(&grid, &Y, &basisX, true);
    try out.print("WALL_HARD: distinct(incl. conjunction) acc={d:.4} solved={any}\n", .{ wh_d.test_acc, wh_d.solved });

    // 6. Battery C: all should be gf2 except C08 (base).
    try out.print("Battery C gf2/base check:\n", .{});
    for (BATTERY_C, 0..) |ct, i| {
        for (0..NSAMP) |s| Y[s] = labelBatteryC(grid[s], i);
        const g = tryGf2(&grid, &Y);
        try out.print("  {s:<24} gf2_acc={d:.4} solved={any} (expected family={s})\n", .{ ct.name, g.test_acc, g.solved, famName(BATTERY_C_TRUE_FAMILY[i]) });
    }

    try out.print("=== selftest done ===\n", .{});
}

// ═══════════════════════════════════════════════════════════════════════
// main
// ═══════════════════════════════════════════════════════════════════════
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    initPairs();

    var args = try std.process.argsAlloc(alloc);
    if (args.len < 2) {
        try out.print("usage: genofgen_assembled selftest | run <arm|all> <csv> [--seeds=1|3] | diag <csv>\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "selftest")) {
        try runSelftest(out);
        return;
    }

    if (std.mem.eql(u8, args[1], "diag")) {
        var csv_buf = std.ArrayList(u8).init(alloc);
        const cw = csv_buf.writer();
        try cw.print("row,tag,evals,val_acc,test_acc,n_included\n", .{});
        try runDiag(out, cw);
        if (args.len >= 3) {
            var f = try std.fs.cwd().createFile(args[2], .{});
            defer f.close();
            try f.writeAll(csv_buf.items);
        }
        return;
    }

    if (std.mem.eql(u8, args[1], "run")) {
        if (args.len < 4) {
            try out.print("usage: genofgen_assembled run <hand|autonomous|auto_nosmartgen|auto_norouter|all> <csv> [--seeds=1|3]\n", .{});
            return;
        }
        const arm_str = args[2];
        const csv_path = args[3];
        var n_seeds: usize = 1;
        if (args.len >= 5) {
            if (std.mem.startsWith(u8, args[4], "--seeds=")) {
                n_seeds = std.fmt.parseInt(usize, args[4]["--seeds=".len..], 10) catch 1;
            }
        }
        const arms_to_run: []const Arm = if (std.mem.eql(u8, arm_str, "all"))
            &[_]Arm{ .hand, .autonomous, .auto_nosmartgen, .auto_norouter }
        else if (std.mem.eql(u8, arm_str, "hand"))
            &[_]Arm{.hand}
        else if (std.mem.eql(u8, arm_str, "autonomous"))
            &[_]Arm{.autonomous}
        else if (std.mem.eql(u8, arm_str, "auto_nosmartgen"))
            &[_]Arm{.auto_nosmartgen}
        else if (std.mem.eql(u8, arm_str, "auto_norouter"))
            &[_]Arm{.auto_norouter}
        else {
            try out.print("unknown arm '{s}'\n", .{arm_str});
            return;
        };

        var csv_buf = std.ArrayList(u8).init(alloc);
        const cw = csv_buf.writer();
        try cw.print("row,seed,arm,target,true_family,family_used,mechanism,solved,evals,test_acc,router_top1\n", .{});

        var timer = try std.time.Timer.start();
        const seeds_used = SEEDS[0..@min(n_seeds, SEEDS.len)];
        for (seeds_used) |seed| {
            try runSeed(alloc, seed, out, cw, arms_to_run);
        }
        try out.print("total wall clock: {d}ms\n", .{timer.read() / std.time.ns_per_ms});

        var f = try std.fs.cwd().createFile(csv_path, .{});
        defer f.close();
        try f.writeAll(csv_buf.items);
        try out.print("wrote {s} ({d} bytes)\n", .{ csv_path, csv_buf.items.len });
        return;
    }

    try out.print("unknown command '{s}'\n", .{args[1]});
}
