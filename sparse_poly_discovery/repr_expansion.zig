//! E1 (Round 2026-07-11 / Round E) — REPRESENTABILITY EXPANSION.
//!
//! Context: the 4-round arc (docs/research/research_round_2026_07_11_PLAN.md)
//! converged on "ceiling = AIM x REPRESENTABILITY". `docs/research/
//! breadth_scaling.md` (D2) measured only 4/15 out-of-closure Battery-C cells
//! representable under the current family menu (monomial / pair / walsh /
//! spectral / clifford / world_mod), 1 (C09) provably NOT (Bayes ceiling
//! ~0.50 over every existing information basis). `docs/research/
//! tier8_reach_gap.md` (round c) closed C09 by EARNING one new family
//! (comparison-pair aggregates, CMP) and fixed a selection bug (MENUACC) --
//! the precedent for "grow the family menu under the certifier, measure the
//! closure expansion."
//!
//! This harness does that systematically for FOUR more candidate families:
//!   THRESH  -- threshold/counting aggregates: count(g[i] >= k) for k != 3
//!              (existing families only ever use the fixed k=3 count).
//!   MIXR    -- mixed-radix modular arithmetic: joint two-statistic residue
//!              combination (A mod a, B mod b) -> single mixed-radix index,
//!              then the standard lens set. Existing world_sum_mod/
//!              world_sign_mod/spectral only ever condition on ONE statistic
//!              mod k; this is a joint condition on TWO.
//!   RATIO   -- algebraic products/ratios of counts: nonlinear combinations
//!              hi*lo and (hi-lo)/(hi+lo+1) of two threshold-count statistics.
//!   RUN     -- stateful/recursive: longest run of consecutive cells clearing
//!              a threshold, position of first descent, count of interior
//!              local maxima -- genuinely SEQUENTIAL statistics; nothing in
//!              the existing menu (all pointwise/aggregate/pairwise) looks at
//!              adjacency structure along the cell index.
//!
//! Target list (8): the D2/C09-class targets C01/C03/C09/C11 (reused,
//! bit-identical labels to open_invention_tier8_battery_c.zig via e2.label /
//! local inversion parity), PLUS 4 fresh targets designed to sit outside
//! every existing family AND every other new family except the one they
//! name: ORDER2 (order-statistic, C09-class but NOT full inversion count),
//! RUN1, RATIO1, MIXMOD1.
//!
//! PHASE A (per target): (1) 7 information-basis Bayes ceilings over the
//! EXISTING bases (count3/gridSum/signPattern/v1-v0/inversion/max_cell/sum01)
//! -- the "before" impossibility proof, identical method to tier8_reach_gap.
//! (2) exhaustive generous-budget best-member sweep + pre-tax certify for
//! EVERY existing family (monomial deg<=8, pair, walsh, spectral 800-grid,
//! clifford 64-theta, world_sum_mod, world_sign_mod, cmp) AND every new
//! family (thresh/mixr/ratio/run) -- the full (target x family) closure
//! lattice, at all 3 standard seeds.
//!
//! PHASE B (regression): a pre-tax ladder replica (transcribed from
//! tier8_reach_gap.zig, itself transcribed from unified_invention.zig) with
//! CMP + MENUACC already wired in as the earned baseline (matching round c),
//! plus the 4 new families appended as toggleable stages after cmp, before
//! world. Runs the FULL battery B (shared growable lib) + C (fresh lib) + D
//! (fresh lib) at the production seed for both BASE (earned baseline) and
//! ALL (+4 new families) arms, comparing solve counts and checking NO
//! per-target regression (BASE-solved implies ALL-solved, guaranteed by
//! construction since new stages are strictly appended after cmp and only
//! reached if cov0 < COVER, but checked empirically here too). Single seed
//! by design (cost control, see doc "Honest scope"); Phase A runs all 3.
//!
//! Deliberately NOT imported: equivalence_tax.zig, unified_invention.zig,
//! invention_engine.zig (tax dependency). tier8_reach_gap.zig is reused
//! READ-ONLY (as its own header licenses: "duplicated numeric glue" is the
//! established convention here) -- functions below are transcribed, not
//! imported, to keep this file standalone per the round's file-creation rule.
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe repr_expansion.zig -O ReleaseFast
//! Run:
//!   ./repr_expansion            (full: Phase A [3 seeds] + Phase B [1 seed])
//!   ./repr_expansion --diag     (Phase A only, fast smoke)
//! Single-threaded.

const std = @import("std");
const rq1 = @import("open_invention_rq1.zig"); // no eqtax dependency (std+hr+oml)
const e2 = @import("open_invention_e2.zig"); // no eqtax dependency (std+oml)
const bd = @import("tier8_battery_d.zig"); // std only
const oml = @import("operator_menu_lib.zig"); // std only

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

// ── Constants (identical to unified_invention.zig / tier8_reach_gap.zig) ───
const NCELL: usize = 8;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const THETA: f64 = 0.40;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const DOM: usize = 1 << NCELL;
const MAXFEAT: usize = 48;
const MAXDEG: usize = 4;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;
const MONO_SATURATE: f64 = 0.55;
const SINGLE_SUFFICIENT: f64 = 0.70;
const WORLD_POOL = [_]usize{ 2, 3, 5, 7, 11, 13 };

const GRID_SEED: u64 = 0xF0235A11CE0FF1CE;
const SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };
const ZOO_MASKS = [_]u8{ (1 << 2) | (1 << 5), (1 << 1) | (1 << 3) | (1 << 6), (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7), (1 << 3) };

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
}

// ── Grid functions (identical to unified_invention.zig) ────────────────────
fn phi(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - MID);
    }
    return p;
}

fn signPattern(g: [NCELL]u8) u8 {
    var p: u8 = 0;
    for (0..NCELL) |i| {
        if (g[i] >= THRESH) p |= @as(u8, 1) << @intCast(i);
    }
    return p;
}

fn countGE(g: [NCELL]u8) f64 {
    var c: usize = 0;
    for (g) |v| if (v >= THRESH) {
        c += 1;
    };
    return @floatFromInt(c);
}

fn gridSum(g: [NCELL]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}

fn chi(S: u8, p: u8) f64 {
    const neg = @popCount(S & ~p);
    return if (neg & 1 == 0) 1.0 else -1.0;
}

fn cliffordG2(g: [NCELL]u8) f64 {
    const v0: f64 = @floatFromInt(g[0]);
    const v1: f64 = @floatFromInt(g[1]);
    return @sin(THETA * (v1 - v0));
}

fn cliffordTheta(g: [NCELL]u8, theta: f64) f64 {
    const v0: f64 = @floatFromInt(g[0]);
    const v1: f64 = @floatFromInt(g[1]);
    return @sin(theta * (v1 - v0));
}

fn oriented(g: [NCELL]u8) f64 {
    return if (g[1] > g[0]) 1.0 else 0.0;
}

fn pairProduct(g: [NCELL]u8, i: usize, j: usize) f64 {
    return (@as(f64, @floatFromInt(g[i])) - MID) * (@as(f64, @floatFromInt(g[j])) - MID);
}

fn inversionCount(g: [NCELL]u8) usize {
    var inv: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        if (g[i] > g[j]) inv += 1;
    };
    return inv;
}

// ── EARNED family (round c, tier8_reach_gap.md): comparison-pair aggregates
const CmpSet = enum(u8) { all, low, high, cross, adj };
const N_CMPSET = 5;
const cmpset_name = [_][]const u8{ "all28", "low6", "high6", "cross16", "adj7" };

fn cmpAggregate(g: [NCELL]u8, set: CmpSet) usize {
    var a: usize = 0;
    switch (set) {
        .all => {
            for (0..NCELL) |i| for (i + 1..NCELL) |j| {
                if (g[i] > g[j]) a += 1;
            };
        },
        .low => {
            for (0..4) |i| for (i + 1..4) |j| {
                if (g[i] > g[j]) a += 1;
            };
        },
        .high => {
            for (4..NCELL) |i| for (i + 1..NCELL) |j| {
                if (g[i] > g[j]) a += 1;
            };
        },
        .cross => {
            for (0..4) |i| for (4..NCELL) |j| {
                if (g[i] > g[j]) a += 1;
            };
        },
        .adj => {
            for (0..NCELL - 1) |i| {
                if (g[i] > g[i + 1]) a += 1;
            }
        },
    }
    return a;
}

// ── Shared "standard lens" (ident/mod2..mod6/cos) used by CMP and all 4 NEW
//    families -- one lens vocabulary for the whole order/count/algebraic menu.
const StdLens = enum(u8) { ident, mod2, mod3, mod4, mod5, mod6, cosw };
const lens_name = [_][]const u8{ "ident", "mod2", "mod3", "mod4", "mod5", "mod6", "cosw" };

fn applyLens(raw: f64, lens: StdLens, omega: f64) f64 {
    return switch (lens) {
        .ident => raw,
        .cosw => @cos(omega * raw),
        else => blk: {
            const m: i64 = switch (lens) {
                .mod2 => 2,
                .mod3 => 3,
                .mod4 => 4,
                .mod5 => 5,
                .mod6 => 6,
                else => unreachable,
            };
            const iv: i64 = @intFromFloat(@round(raw));
            const r = @mod(iv, m);
            break :blk @floatFromInt(r);
        },
    };
}

fn cmpEval(g: [NCELL]u8, set: CmpSet, lens: StdLens, omega: f64) f64 {
    return applyLens(@floatFromInt(cmpAggregate(g, set)), lens, omega);
}

// ── NEW families' grid statistics ───────────────────────────────────────────

/// THRESH: count(g[i] >= k), k != 3 (k=3 is the existing countGE/count3 basis).
fn countAtLeast(g: [NCELL]u8, k: u8) usize {
    var c: usize = 0;
    for (g) |v| if (v >= k) {
        c += 1;
    };
    return c;
}
const THRESH_KS = [_]u8{ 1, 2, 4, 5 };

/// MIXR: joint two-statistic mixed-radix index. pair 0=(sum,count3),
/// 1=(sum,inversion), 2=(count3,inversion).
fn mixrBaseA(g: [NCELL]u8, pair: u8) usize {
    return switch (pair) {
        0, 1 => gridSum(g),
        else => countAtLeast(g, THRESH),
    };
}
fn mixrBaseB(g: [NCELL]u8, pair: u8) usize {
    return switch (pair) {
        0 => countAtLeast(g, THRESH),
        else => inversionCount(g),
    };
}
const mixr_pair_name = [_][]const u8{ "sum,count3", "sum,inv", "count3,inv" };
const MIXR_RADII = [_][2]u8{ .{ 2, 2 }, .{ 3, 3 } };

fn mixrIndex(g: [NCELL]u8, pair: u8, ra: u8, rb: u8) f64 {
    const a = mixrBaseA(g, pair) % ra;
    const b = mixrBaseB(g, pair) % rb;
    return @floatFromInt(a * @as(usize, rb) + b);
}

/// RATIO: algebraic products/ratios of two threshold-count statistics.
/// pair 0=(hi>=4,lo>=1), 1=(hi>=5,lo>=0), 2=(hi>=3,lo>=2).
const RatioPair = struct { hi: u8, lo: u8 };
const RATIO_PAIRS = [_]RatioPair{ .{ .hi = 4, .lo = 1 }, .{ .hi = 5, .lo = 0 }, .{ .hi = 3, .lo = 2 } };

fn ratioDiff(g: [NCELL]u8, p: RatioPair) f64 {
    const hi: f64 = @floatFromInt(countAtLeast(g, p.hi));
    const lo: f64 = @floatFromInt(countAtLeast(g, p.lo));
    return (hi - lo) / (hi + lo + 1.0);
}
fn ratioProd(g: [NCELL]u8, p: RatioPair) f64 {
    return @floatFromInt(countAtLeast(g, p.hi) * countAtLeast(g, p.lo));
}

/// RUN: stateful/recursive statistics over cell ADJACENCY (index order).
/// stat 0/1/2 = longest run of consecutive i with g[i]>=k for k=2/3/4;
/// stat 3 = position of first descent (g[i]>g[i+1]), 8 if none;
/// stat 4 = count of interior local maxima.
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
const run_stat_name = [_][]const u8{ "maxRunGE2", "maxRunGE3", "maxRunGE4", "firstDescentPos", "numLocalMax" };

// ── Feature library (existing union + cmp[earned] + 4 NEW families) ────────
const Feature = union(enum) {
    monomial: u8,
    pair_relation: struct { i: usize, j: usize },
    spectral_count: f64,
    walsh: u8,
    clifford_g2: void,
    world_sum_mod: usize,
    world_sign_mod: usize,
    cmp: struct { set: CmpSet, lens: StdLens, omega: f64 },
    thresh: struct { k: u8, lens: StdLens, omega: f64 },
    mixr: struct { pair: u8, ra: u8, rb: u8, lens: StdLens, omega: f64 },
    ratio: struct { pair: u8, is_prod: bool, lens: StdLens, omega: f64 },
    run: struct { stat: u8, lens: StdLens, omega: f64 },
};

const Source = enum { base, forge, pair, walsh, menu, menuacc, cmp, thresh, mixr, ratio, run, world, none };

fn evalFeature(f: Feature, g: [NCELL]u8) f64 {
    return switch (f) {
        .monomial => |m| phi(g, m),
        .pair_relation => |ij| pairProduct(g, ij.i, ij.j),
        .spectral_count => |w| @cos(w * countGE(g)),
        .walsh => |S| chi(S, signPattern(g)),
        .clifford_g2 => cliffordG2(g),
        .world_sum_mod => |p| if (gridSum(g) % p == 0) @as(f64, 1) else 0,
        .world_sign_mod => |p| if (@as(usize, signPattern(g)) % p == 0) @as(f64, 1) else 0,
        .cmp => |c| cmpEval(g, c.set, c.lens, c.omega),
        .thresh => |t| applyLens(@floatFromInt(countAtLeast(g, t.k)), t.lens, t.omega),
        .mixr => |m| applyLens(mixrIndex(g, m.pair, m.ra, m.rb), m.lens, m.omega),
        .ratio => |r| blk: {
            const raw = if (r.is_prod) ratioProd(g, RATIO_PAIRS[r.pair]) else ratioDiff(g, RATIO_PAIRS[r.pair]);
            break :blk applyLens(raw, r.lens, r.omega);
        },
        .run => |rn| applyLens(@floatFromInt(runStat(g, rn.stat)), rn.lens, rn.omega),
    };
}

fn featureKey(buf: []u8, f: Feature) []const u8 {
    switch (f) {
        .monomial => |m| return std.fmt.bufPrint(buf, "phi(0x{X:0>2})", .{m}) catch "phi",
        .pair_relation => |ij| return std.fmt.bufPrint(buf, "pair({d},{d})", .{ ij.i, ij.j }) catch "pair",
        .spectral_count => |omega| return std.fmt.bufPrint(buf, "cos(w*count),w={d:.4}", .{omega}) catch "spectral",
        .walsh => |S| return std.fmt.bufPrint(buf, "chi(S=0x{X:0>2})", .{S}) catch "chi",
        .clifford_g2 => return "sin(th(v1-v0))",
        .world_sum_mod => |p| return std.fmt.bufPrint(buf, "sum%{d}", .{p}) catch "sum_mod",
        .world_sign_mod => |p| return std.fmt.bufPrint(buf, "sign%{d}", .{p}) catch "sign_mod",
        .cmp => |c| {
            if (c.lens == .cosw)
                return std.fmt.bufPrint(buf, "cmp({s},cos w={d:.4})", .{ cmpset_name[@intFromEnum(c.set)], c.omega }) catch "cmp";
            return std.fmt.bufPrint(buf, "cmp({s},{s})", .{ cmpset_name[@intFromEnum(c.set)], lens_name[@intFromEnum(c.lens)] }) catch "cmp";
        },
        .thresh => |t| {
            if (t.lens == .cosw)
                return std.fmt.bufPrint(buf, "thresh(k={d},cos w={d:.4})", .{ t.k, t.omega }) catch "thresh";
            return std.fmt.bufPrint(buf, "thresh(k={d},{s})", .{ t.k, lens_name[@intFromEnum(t.lens)] }) catch "thresh";
        },
        .mixr => |m| {
            if (m.lens == .cosw)
                return std.fmt.bufPrint(buf, "mixr({s},{d}x{d},cos w={d:.4})", .{ mixr_pair_name[m.pair], m.ra, m.rb, m.omega }) catch "mixr";
            return std.fmt.bufPrint(buf, "mixr({s},{d}x{d},{s})", .{ mixr_pair_name[m.pair], m.ra, m.rb, lens_name[@intFromEnum(m.lens)] }) catch "mixr";
        },
        .ratio => |r| {
            const kind: []const u8 = if (r.is_prod) "prod" else "diff";
            if (r.lens == .cosw)
                return std.fmt.bufPrint(buf, "ratio({s},hi{d}lo{d},cos w={d:.4})", .{ kind, RATIO_PAIRS[r.pair].hi, RATIO_PAIRS[r.pair].lo, r.omega }) catch "ratio";
            return std.fmt.bufPrint(buf, "ratio({s},hi{d}lo{d},{s})", .{ kind, RATIO_PAIRS[r.pair].hi, RATIO_PAIRS[r.pair].lo, lens_name[@intFromEnum(r.lens)] }) catch "ratio";
        },
        .run => |rn| {
            if (rn.lens == .cosw)
                return std.fmt.bufPrint(buf, "run({s},cos w={d:.4})", .{ run_stat_name[rn.stat], rn.omega }) catch "run";
            return std.fmt.bufPrint(buf, "run({s},{s})", .{ run_stat_name[rn.stat], lens_name[@intFromEnum(rn.lens)] }) catch "run";
        },
    }
}

fn featuresEqual(a: Feature, b: Feature) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .monomial => |m| b.monomial == m,
        .pair_relation => |ij| b.pair_relation.i == ij.i and b.pair_relation.j == ij.j,
        .spectral_count => |wa| @abs(wa - b.spectral_count) < 1e-6,
        .walsh => |S| b.walsh == S,
        .clifford_g2 => true,
        .world_sum_mod => |p| b.world_sum_mod == p,
        .world_sign_mod => |p| b.world_sign_mod == p,
        .cmp => |c| b.cmp.set == c.set and b.cmp.lens == c.lens and @abs(b.cmp.omega - c.omega) < 1e-6,
        .thresh => |t| b.thresh.k == t.k and b.thresh.lens == t.lens and @abs(b.thresh.omega - t.omega) < 1e-6,
        .mixr => |m| b.mixr.pair == m.pair and b.mixr.ra == m.ra and b.mixr.rb == m.rb and b.mixr.lens == m.lens and @abs(b.mixr.omega - m.omega) < 1e-6,
        .ratio => |r| b.ratio.pair == r.pair and b.ratio.is_prod == r.is_prod and b.ratio.lens == r.lens and @abs(b.ratio.omega - r.omega) < 1e-6,
        .run => |rn| b.run.stat == rn.stat and b.run.lens == rn.lens and @abs(b.run.omega - rn.omega) < 1e-6,
    };
}

fn hasFeature(lib: []const Feature, f: Feature) bool {
    for (lib) |x| if (featuresEqual(x, f)) return true;
    return false;
}

// ── ML helpers (identical numerics to unified_invention.zig) ───────────────
fn buildFeat(X: [][]f64, grid: []const [NCELL]u8, lib: []const Feature) void {
    const k = lib.len;
    for (0..NSAMP) |s| for (0..k) |c| {
        X[s][c] = evalFeature(lib[c], grid[s]);
    };
    for (0..k) |c| {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += X[s][c];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (X[s][c] - mu) * (X[s][c] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| X[s][c] = (X[s][c] - mu) / sd;
    }
}

fn fitLogit(X: []const []f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
}

fn accLogit(X: []const []f64, Y: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

fn coverage(X: [][]f64, grid: []const [NCELL]u8, lib: []const Feature, Y: []const f64, w: []f64) f64 {
    buildFeat(X, grid, lib);
    fitLogit(X, Y, lib.len, 150, 0.05, w);
    return accLogit(X, Y, w, lib.len, NVA, NSAMP);
}

fn reconR2(X: []const []f64, t: []const f64, dim: usize, w: []f64) f64 {
    @memset(w[0 .. dim + 1], 0);
    for (0..400) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = z - t[s];
        for (0..dim) |j| w[j] -= 0.01 * e * X[s][j];
        w[dim] -= 0.01 * e;
    };
    var mu: f64 = 0;
    for (NVA..NSAMP) |s| mu += t[s];
    mu /= @floatFromInt(NSAMP - NVA);
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (NVA..NSAMP) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        ssr += (t[s] - z) * (t[s] - z);
        sst += (t[s] - mu) * (t[s] - mu);
    }
    return 1.0 - ssr / @max(1e-9, sst);
}

// single-feature probe, identical to unified_invention.valAccSingle
fn valAccSingle(feat: []const f64, Y: []const f64) f64 {
    var w: [2]f64 = .{ 0.0, 0.0 };
    for (0..80) |_| for (0..NTR) |s| {
        const e = sigmoid(w[0] * feat[s] + w[1]) - Y[s];
        w[0] -= 0.1 * e * feat[s];
        w[1] -= 0.1 * e;
    };
    var c: usize = 0;
    for (NTR..NVA) |s| {
        if ((w[0] * feat[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NVA - NTR));
}

// ── Cost counters ───────────────────────────────────────────────────────────
const Counter = struct {
    probes: usize = 0,
    certs: usize = 0,
    fn evals(self: Counter) usize {
        return self.probes + 3 * self.certs;
    }
};

// ── Pre-tax certifier (unified_invention.certify minus eqtax.gatePromoteEx) ─
const CertResult = struct { ok: bool, cov_before: f64, cov_after: f64, r2: f64 };

fn certifyLocal(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []const Feature,
    cand: Feature,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) CertResult {
    ctr.certs += 1;
    const cov_before = coverage(X, grid, lib, Y, w);
    var aug: [MAXFEAT + 1]Feature = undefined;
    @memcpy(aug[0..lib.len], lib);
    aug[lib.len] = cand;
    const cov_after = coverage(X, grid, aug[0 .. lib.len + 1], Y, w);
    for (0..NSAMP) |s| feat_scratch[s] = evalFeature(cand, grid[s]);
    buildFeat(X, grid, lib);
    const r2 = reconR2(X, feat_scratch, lib.len, w);
    const escape = cov_after >= COVER and cov_before < COVER;
    const ok = escape and r2 < R2_MAX; // PRE-TAX: no gatePromoteEx
    return .{ .ok = ok, .cov_before = cov_before, .cov_after = cov_after, .r2 = r2 };
}

// ── Ladder stages (transcribed from tier8_reach_gap.zig, pre-tax) ──────────
fn isMonomialOnly(lib: []const Feature) bool {
    for (lib) |f| switch (f) {
        .monomial => {},
        else => return false,
    };
    return true;
}

fn tryMonomialForge(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    phiTgt: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    if (!isMonomialOnly(lib[0..nlib.*])) return false;
    var best_val: f64 = -1;
    var best_mask: u8 = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const cand: u8 = @intCast(mm);
        const d = popcount(cand);
        if (d < 1 or d > MAXDEG) continue;
        if (hasFeature(lib[0..nlib.*], .{ .monomial = cand })) continue;
        for (0..NSAMP) |s| X[s][0] = phi(grid[s], cand);
        var mu: f64 = 0;
        for (0..NTR) |s| mu += X[s][0];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (X[s][0] - mu) * (X[s][0] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| X[s][0] = (X[s][0] - mu) / sd;
        fitLogit(X, Y, 1, 70, 0.06, w);
        ctr.probes += 1;
        const v = accLogit(X, Y, w, 1, NTR, NVA);
        if (v > best_val) {
            best_val = v;
            best_mask = cand;
        }
    }
    const cand_feat: Feature = .{ .monomial = best_mask };
    for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], best_mask);
    const cert = certifyLocal(X, grid, lib[0..nlib.*], cand_feat, Y, phiTgt, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = cand_feat;
        nlib.* += 1;
        return true;
    }
    return false;
}

fn pairProductCorr(grid: []const [NCELL]u8, Y: []const f64, i: usize, j: usize) f64 {
    var sum_xy: f64 = 0;
    var sum_x: f64 = 0;
    var sum_y: f64 = 0;
    var sum_x2: f64 = 0;
    var sum_y2: f64 = 0;
    const n: f64 = @floatFromInt(NVA - NTR);
    for (NTR..NVA) |s| {
        const x = pairProduct(grid[s], i, j);
        const y = Y[s];
        sum_xy += x * y;
        sum_x += x;
        sum_y += y;
        sum_x2 += x * x;
        sum_y2 += y * y;
    }
    const num = n * sum_xy - sum_x * sum_y;
    const den = @sqrt(@max(1e-12, (n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y)));
    return @abs(num / den);
}

fn tryPairRouter(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    var best_i: usize = 0;
    var best_j: usize = 1;
    var best_corr: f64 = -1;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        const c = pairProductCorr(grid, Y, i, j);
        ctr.probes += 1;
        if (c > best_corr) {
            best_corr = c;
            best_i = i;
            best_j = j;
        }
    };
    const cand: Feature = .{ .pair_relation = .{ .i = best_i, .j = best_j } };
    if (hasFeature(lib[0..nlib.*], cand)) return false;
    const cert = certifyLocal(X, grid, lib[0..nlib.*], cand, Y, feat_scratch, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = cand;
        nlib.* += 1;
        return true;
    }
    return false;
}

const TaskClass = enum { single_sufficient, q38_compound, unknown };

fn probeExtremalBest(grid: []const [NCELL]u8, Y: []const f64, feat: []f64, ctr: *Counter) f64 {
    var best: f64 = 0.5;
    for (0..NSAMP) |s| feat[s] = oriented(grid[s]);
    ctr.probes += 1;
    best = @max(best, valAccSingle(feat, Y));
    for (0..NSAMP) |s| feat[s] = countGE(grid[s]);
    ctr.probes += 1;
    best = @max(best, valAccSingle(feat, Y));
    for (0..NSAMP) |s| feat[s] = cliffordG2(grid[s]);
    ctr.probes += 1;
    best = @max(best, valAccSingle(feat, Y));
    return best;
}

fn tryConditionalWalsh(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    const cov_frozen = coverage(X, grid, lib[0..nlib.*], Y, w);
    const ext = probeExtremalBest(grid, Y, feat_scratch, ctr);
    const tc: TaskClass = if (cov_frozen >= SINGLE_SUFFICIENT or ext >= SINGLE_SUFFICIENT)
        .single_sufficient
    else if (cov_frozen <= MONO_SATURATE and ext <= MONO_SATURATE)
        .q38_compound
    else
        .unknown;
    if (tc != .q38_compound) return false;
    const wal = oml.discoverWalsh(grid, Y, feat_scratch, NTR, NVA, NSAMP);
    ctr.probes += 256;
    const cand: Feature = .{ .walsh = wal.bestS };
    if (hasFeature(lib[0..nlib.*], cand)) return false;
    const cert = certifyLocal(X, grid, lib[0..nlib.*], cand, Y, feat_scratch, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = cand;
        nlib.* += 1;
        return true;
    }
    return false;
}

fn discoverSpectralPower(grid: []const [NCELL]u8, Y: []const f64, feat_out: []f64) f64 {
    const CMAX = NCELL + 1;
    var fsum = [_]f64{0} ** CMAX;
    var ncnt = [_]f64{0} ** CMAX;
    for (0..NTR) |s| {
        const c: usize = @intFromFloat(countGE(grid[s]));
        fsum[c] += Y[s];
        ncnt[c] += 1;
    }
    var f = [_]f64{0} ** CMAX;
    var fbar: f64 = 0;
    var ntot: f64 = 0;
    for (0..CMAX) |c| {
        if (ncnt[c] > 0) f[c] = fsum[c] / ncnt[c];
        fbar += fsum[c];
        ntot += ncnt[c];
    }
    fbar /= ntot;
    const NF = 200;
    var peak_w: f64 = std.math.pi;
    var peak_pw: f64 = -1;
    var i: usize = 1;
    while (i <= NF) : (i += 1) {
        const w = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
        var re: f64 = 0;
        var im: f64 = 0;
        for (0..CMAX) |c| {
            if (ncnt[c] == 0) continue;
            const amp = ncnt[c] * (f[c] - fbar);
            const cc: f64 = @floatFromInt(c);
            re += amp * @cos(w * cc);
            im += amp * @sin(w * cc);
        }
        const pw = re * re + im * im;
        if (pw > peak_pw) {
            peak_pw = pw;
            peak_w = w;
        }
    }
    for (0..NSAMP) |s| feat_out[s] = @cos(peak_w * countGE(grid[s]));
    return peak_w;
}

fn discoverWalshMenu(grid: []const [NCELL]u8, Y: []const f64) u8 {
    var est = [_]f64{0} ** DOM;
    for (0..NTR) |s| {
        const p = signPattern(grid[s]);
        const g: f64 = if (Y[s] > 0.5) -1.0 else 1.0;
        for (0..DOM) |S| est[S] += g * chi(@intCast(S), p);
    }
    var best_abs: f64 = -1;
    var bestS: u8 = 0;
    for (0..DOM) |S| {
        const v = @abs(est[S]) / @as(f64, @floatFromInt(NTR));
        if (v > best_abs) {
            best_abs = v;
            bestS = @intCast(S);
        }
    }
    return bestS;
}

fn tryOperatorMenu(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    const omega = discoverSpectralPower(grid, Y, feat_scratch);
    ctr.probes += 1;
    const spec_val = valAccSingle(feat_scratch, Y);

    const walshS = discoverWalshMenu(grid, Y);
    for (0..NSAMP) |s| feat_scratch[s] = chi(walshS, signPattern(grid[s]));
    ctr.probes += 1;
    const wal_val = valAccSingle(feat_scratch, Y);

    for (0..NSAMP) |s| feat_scratch[s] = cliffordG2(grid[s]);
    ctr.probes += 1;
    const clf_val = valAccSingle(feat_scratch, Y);

    const cands = [_]Feature{
        .{ .spectral_count = omega },
        .{ .walsh = walshS },
        .{ .clifford_g2 = {} },
    };
    const vals = [_]f64{ spec_val, wal_val, clf_val };
    var best_i: usize = 0;
    for (1..3) |k| if (vals[k] > vals[best_i]) {
        best_i = k;
    };
    const cand = cands[best_i];
    if (hasFeature(lib[0..nlib.*], cand)) return false;
    const cert = certifyLocal(X, grid, lib[0..nlib.*], cand, Y, feat_scratch, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = cand;
        nlib.* += 1;
        return true;
    }
    return false;
}

fn tryMenuAcc(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    const NF = 200;
    var best_val: f64 = -1;
    var best_w: f64 = std.math.pi;
    var i: usize = 1;
    while (i <= NF) : (i += 1) {
        const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
        for (0..NSAMP) |s| feat_scratch[s] = @cos(om * countGE(grid[s]));
        ctr.probes += 1;
        const v = valAccSingle(feat_scratch, Y);
        if (v > best_val) {
            best_val = v;
            best_w = om;
        }
    }
    const cand: Feature = .{ .spectral_count = best_w };
    if (hasFeature(lib[0..nlib.*], cand)) return false;
    const cert = certifyLocal(X, grid, lib[0..nlib.*], cand, Y, feat_scratch, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = cand;
        nlib.* += 1;
        return true;
    }
    return false;
}

fn tryCmpStage(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    var best_val: f64 = -1;
    var best: Feature = .{ .cmp = .{ .set = .all, .lens = .mod2, .omega = 0 } };
    for (0..N_CMPSET) |si| {
        const set: CmpSet = @enumFromInt(si);
        var agg: [NSAMP]f64 = undefined;
        for (0..NSAMP) |s| agg[s] = @floatFromInt(cmpAggregate(grid[s], set));
        const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
        for (fixed) |lens| {
            for (0..NSAMP) |s| feat_scratch[s] = applyLens(agg[s], lens, 0);
            ctr.probes += 1;
            const v = valAccSingle(feat_scratch, Y);
            if (v > best_val) {
                best_val = v;
                best = .{ .cmp = .{ .set = set, .lens = lens, .omega = 0 } };
            }
        }
        const NF = 200;
        var i: usize = 1;
        while (i <= NF) : (i += 1) {
            const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
            for (0..NSAMP) |s| feat_scratch[s] = @cos(om * agg[s]);
            ctr.probes += 1;
            const v = valAccSingle(feat_scratch, Y);
            if (v > best_val) {
                best_val = v;
                best = .{ .cmp = .{ .set = set, .lens = .cosw, .omega = om } };
            }
        }
    }
    if (hasFeature(lib[0..nlib.*], best)) return false;
    const cert = certifyLocal(X, grid, lib[0..nlib.*], best, Y, feat_scratch, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = best;
        nlib.* += 1;
        return true;
    }
    return false;
}

// ── NEW STAGE 1/4: THRESH -- threshold/counting aggregates, k != 3 ─────────
fn tryThreshStage(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    var best_val: f64 = -1;
    var best: Feature = .{ .thresh = .{ .k = THRESH_KS[0], .lens = .mod2, .omega = 0 } };
    for (THRESH_KS) |k| {
        var agg: [NSAMP]f64 = undefined;
        for (0..NSAMP) |s| agg[s] = @floatFromInt(countAtLeast(grid[s], k));
        const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
        for (fixed) |lens| {
            for (0..NSAMP) |s| feat_scratch[s] = applyLens(agg[s], lens, 0);
            ctr.probes += 1;
            const v = valAccSingle(feat_scratch, Y);
            if (v > best_val) {
                best_val = v;
                best = .{ .thresh = .{ .k = k, .lens = lens, .omega = 0 } };
            }
        }
        const NF = 16; // trimmed: no certified new-family solve uses cos (all mod lenses); Phase A keeps the full 60-grid
        var i: usize = 1;
        while (i <= NF) : (i += 1) {
            const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
            for (0..NSAMP) |s| feat_scratch[s] = @cos(om * agg[s]);
            ctr.probes += 1;
            const v = valAccSingle(feat_scratch, Y);
            if (v > best_val) {
                best_val = v;
                best = .{ .thresh = .{ .k = k, .lens = .cosw, .omega = om } };
            }
        }
    }
    if (hasFeature(lib[0..nlib.*], best)) return false;
    const cert = certifyLocal(X, grid, lib[0..nlib.*], best, Y, feat_scratch, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = best;
        nlib.* += 1;
        return true;
    }
    return false;
}

// ── NEW STAGE 2/4: MIXR -- mixed-radix joint two-statistic residue combo ───
fn tryMixrStage(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    var best_val: f64 = -1;
    var best: Feature = .{ .mixr = .{ .pair = 0, .ra = 2, .rb = 2, .lens = .mod2, .omega = 0 } };
    for (0..3) |pair_u| {
        const pair: u8 = @intCast(pair_u);
        for (MIXR_RADII) |radii| {
            const ra = radii[0];
            const rb = radii[1];
            var agg: [NSAMP]f64 = undefined;
            for (0..NSAMP) |s| agg[s] = mixrIndex(grid[s], pair, ra, rb);
            const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
            for (fixed) |lens| {
                for (0..NSAMP) |s| feat_scratch[s] = applyLens(agg[s], lens, 0);
                ctr.probes += 1;
                const v = valAccSingle(feat_scratch, Y);
                if (v > best_val) {
                    best_val = v;
                    best = .{ .mixr = .{ .pair = pair, .ra = ra, .rb = rb, .lens = lens, .omega = 0 } };
                }
            }
            const NF = 16; // trimmed: no certified new-family solve uses cos (all mod lenses); Phase A keeps the full 60-grid
            var i: usize = 1;
            while (i <= NF) : (i += 1) {
                const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
                for (0..NSAMP) |s| feat_scratch[s] = @cos(om * agg[s]);
                ctr.probes += 1;
                const v = valAccSingle(feat_scratch, Y);
                if (v > best_val) {
                    best_val = v;
                    best = .{ .mixr = .{ .pair = pair, .ra = ra, .rb = rb, .lens = .cosw, .omega = om } };
                }
            }
        }
    }
    if (hasFeature(lib[0..nlib.*], best)) return false;
    const cert = certifyLocal(X, grid, lib[0..nlib.*], best, Y, feat_scratch, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = best;
        nlib.* += 1;
        return true;
    }
    return false;
}

// ── NEW STAGE 3/4: RATIO -- algebraic products/ratios of counts ────────────
fn tryRatioStage(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    var best_val: f64 = -1;
    var best: Feature = .{ .ratio = .{ .pair = 0, .is_prod = false, .lens = .ident, .omega = 0 } };
    for (0..RATIO_PAIRS.len) |pair_u| {
        const pair: u8 = @intCast(pair_u);
        const p = RATIO_PAIRS[pair];
        // diff (continuous in [-1,1]): ident + cos-scan only (mod is meaningless on a ratio)
        {
            var agg: [NSAMP]f64 = undefined;
            for (0..NSAMP) |s| agg[s] = ratioDiff(grid[s], p);
            for (0..NSAMP) |s| feat_scratch[s] = agg[s];
            ctr.probes += 1;
            var v = valAccSingle(feat_scratch, Y);
            if (v > best_val) {
                best_val = v;
                best = .{ .ratio = .{ .pair = pair, .is_prod = false, .lens = .ident, .omega = 0 } };
            }
            const NF = 16; // trimmed: no certified new-family solve uses cos (all mod lenses); Phase A keeps the full 60-grid
            var i: usize = 1;
            while (i <= NF) : (i += 1) {
                const om = 2.0 * std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
                for (0..NSAMP) |s| feat_scratch[s] = @cos(om * agg[s]);
                ctr.probes += 1;
                v = valAccSingle(feat_scratch, Y);
                if (v > best_val) {
                    best_val = v;
                    best = .{ .ratio = .{ .pair = pair, .is_prod = false, .lens = .cosw, .omega = om } };
                }
            }
        }
        // prod (integer 0..25): full standard lens set
        {
            var agg: [NSAMP]f64 = undefined;
            for (0..NSAMP) |s| agg[s] = ratioProd(grid[s], p);
            const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
            for (fixed) |lens| {
                for (0..NSAMP) |s| feat_scratch[s] = applyLens(agg[s], lens, 0);
                ctr.probes += 1;
                const v = valAccSingle(feat_scratch, Y);
                if (v > best_val) {
                    best_val = v;
                    best = .{ .ratio = .{ .pair = pair, .is_prod = true, .lens = lens, .omega = 0 } };
                }
            }
            const NF = 16; // trimmed: no certified new-family solve uses cos (all mod lenses); Phase A keeps the full 60-grid
            var i: usize = 1;
            while (i <= NF) : (i += 1) {
                const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
                for (0..NSAMP) |s| feat_scratch[s] = @cos(om * agg[s]);
                ctr.probes += 1;
                const v = valAccSingle(feat_scratch, Y);
                if (v > best_val) {
                    best_val = v;
                    best = .{ .ratio = .{ .pair = pair, .is_prod = true, .lens = .cosw, .omega = om } };
                }
            }
        }
    }
    if (hasFeature(lib[0..nlib.*], best)) return false;
    const cert = certifyLocal(X, grid, lib[0..nlib.*], best, Y, feat_scratch, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = best;
        nlib.* += 1;
        return true;
    }
    return false;
}

// ── NEW STAGE 4/4: RUN -- stateful/recursive (adjacency) statistics ────────
fn tryRunStage(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    var best_val: f64 = -1;
    var best: Feature = .{ .run = .{ .stat = 0, .lens = .mod2, .omega = 0 } };
    for (0..5) |stat_u| {
        const stat: u8 = @intCast(stat_u);
        var agg: [NSAMP]f64 = undefined;
        for (0..NSAMP) |s| agg[s] = @floatFromInt(runStat(grid[s], stat));
        const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
        for (fixed) |lens| {
            for (0..NSAMP) |s| feat_scratch[s] = applyLens(agg[s], lens, 0);
            ctr.probes += 1;
            const v = valAccSingle(feat_scratch, Y);
            if (v > best_val) {
                best_val = v;
                best = .{ .run = .{ .stat = stat, .lens = lens, .omega = 0 } };
            }
        }
        const NF = 16; // trimmed: no certified new-family solve uses cos (all mod lenses); Phase A keeps the full 60-grid
        var i: usize = 1;
        while (i <= NF) : (i += 1) {
            const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
            for (0..NSAMP) |s| feat_scratch[s] = @cos(om * agg[s]);
            ctr.probes += 1;
            const v = valAccSingle(feat_scratch, Y);
            if (v > best_val) {
                best_val = v;
                best = .{ .run = .{ .stat = stat, .lens = .cosw, .omega = om } };
            }
        }
    }
    if (hasFeature(lib[0..nlib.*], best)) return false;
    const cert = certifyLocal(X, grid, lib[0..nlib.*], best, Y, feat_scratch, w, ctr);
    if (cert.ok) {
        lib[nlib.*] = best;
        nlib.* += 1;
        return true;
    }
    return false;
}

fn tryWorldPool(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    ctr: *Counter,
) bool {
    var best_cert: CertResult = .{ .ok = false, .cov_before = 0, .cov_after = -1, .r2 = 2 };
    var best_feat: ?Feature = null;
    for (WORLD_POOL) |p| {
        const pair = [_]Feature{
            .{ .world_sum_mod = p },
            .{ .world_sign_mod = p },
        };
        for (pair) |cand| {
            if (hasFeature(lib[0..nlib.*], cand)) continue;
            const cert = certifyLocal(X, grid, lib[0..nlib.*], cand, Y, feat_scratch, w, ctr);
            if (cert.cov_after > best_cert.cov_after) {
                best_cert = cert;
                best_feat = cand;
            }
        }
    }
    if (best_feat) |bf| {
        if (best_cert.ok) {
            lib[nlib.*] = bf;
            nlib.* += 1;
            return true;
        }
    }
    return false;
}

// ── The ladder (BASE = earned round-c baseline; +thresh/mixr/ratio/run new) ─
const LadderOpts = struct {
    menuacc: bool = false,
    cmp: bool = false,
    thresh: bool = false,
    mixr: bool = false,
    ratio: bool = false,
    run: bool = false,
};

const SolveMetrics = struct {
    solved: bool,
    cov: f64,
    source: Source,
    probes: usize,
    certs: usize,
};

fn solveLadder(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    phiTgt: []f64,
    w: []f64,
    opts: LadderOpts,
) SolveMetrics {
    var ctr = Counter{};
    var source: Source = .base;

    var cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
    if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .base, .probes = ctr.probes, .certs = ctr.certs };

    var forge_round: usize = 0;
    while (forge_round < 6) : (forge_round += 1) {
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .forge, .probes = ctr.probes, .certs = ctr.certs };
        if (!tryMonomialForge(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) break;
    }
    cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
    if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .forge, .probes = ctr.probes, .certs = ctr.certs };

    if (tryPairRouter(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .pair, .probes = ctr.probes, .certs = ctr.certs };
    }

    if (tryConditionalWalsh(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .walsh, .probes = ctr.probes, .certs = ctr.certs };
    }

    if (tryOperatorMenu(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .menu, .probes = ctr.probes, .certs = ctr.certs };
    }

    if (opts.menuacc) {
        if (tryMenuAcc(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
            cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
            if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .menuacc, .probes = ctr.probes, .certs = ctr.certs };
        }
    }

    if (opts.cmp) {
        if (tryCmpStage(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
            cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
            if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .cmp, .probes = ctr.probes, .certs = ctr.certs };
        }
    }

    if (opts.thresh) {
        if (tryThreshStage(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
            cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
            if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .thresh, .probes = ctr.probes, .certs = ctr.certs };
        }
    }

    if (opts.mixr) {
        if (tryMixrStage(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
            cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
            if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .mixr, .probes = ctr.probes, .certs = ctr.certs };
        }
    }

    if (opts.ratio) {
        if (tryRatioStage(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
            cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
            if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .ratio, .probes = ctr.probes, .certs = ctr.certs };
        }
    }

    if (opts.run) {
        if (tryRunStage(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
            cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
            if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .run, .probes = ctr.probes, .certs = ctr.certs };
        }
    }

    if (tryWorldPool(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) source = .world;
    }

    return .{ .solved = cov0 >= COVER, .cov = cov0, .source = if (cov0 >= COVER) source else .none, .probes = ctr.probes, .certs = ctr.certs };
}

// ── Targets ─────────────────────────────────────────────────────────────────
const CTarget = struct {
    name: []const u8,
    e2_spec: ?e2.PredSpec = null,
    inv_parity: bool = false,
};

const BATTERY_C = [_]CTarget{
    .{ .name = "C01 XOR 0x0F", .e2_spec = .{ .kind = .xor_cells, .mask = 0x0F } },
    .{ .name = "C02 parity XOR 0x33", .e2_spec = .{ .kind = .parity_xor, .mask = 0x33 } },
    .{ .name = "C03 XOR 0x55", .e2_spec = .{ .kind = .xor_cells, .mask = 0x55 } },
    .{ .name = "C04 XOR 0xAA", .e2_spec = .{ .kind = .xor_cells, .mask = 0xAA } },
    .{ .name = "C05 XOR 0x3C", .e2_spec = .{ .kind = .xor_cells, .mask = 0x3C } },
    .{ .name = "C06 XOR 0x66", .e2_spec = .{ .kind = .xor_cells, .mask = 0x66 } },
    .{ .name = "C07 XOR 0x99", .e2_spec = .{ .kind = .xor_cells, .mask = 0x99 } },
    .{ .name = "C08 parity count", .e2_spec = .{ .kind = .parity_count } },
    .{ .name = "C09 inv parity", .inv_parity = true },
    .{ .name = "C10 parity XOR 0x0F", .e2_spec = .{ .kind = .parity_xor, .mask = 0x0F } },
    .{ .name = "C11 XOR 0x37", .e2_spec = .{ .kind = .xor_cells, .mask = 0x37 } },
};

fn labelC(g: [NCELL]u8, t: CTarget) f64 {
    if (t.e2_spec) |spec| return e2.label(g, spec);
    return @floatFromInt(inversionCount(g) & 1);
}

// ── 4 fresh targets, designed outside ALL existing families ────────────────
fn labelOrder2(g: [NCELL]u8) f64 {
    // ORDER2: parity of rank(cell 0) among the other 7 cells -- an order
    // statistic distinct from C09 (full inversion count) and from CMP's 5
    // fixed canonical pair-sets (none of which is "all pairs touching cell 0").
    var r: usize = 0;
    for (1..NCELL) |j| {
        if (g[j] < g[0]) r += 1;
    }
    return @floatFromInt(r & 1);
}
fn labelRun1(g: [NCELL]u8) f64 {
    // RUN1: longest run of consecutive cells >=3 reaches at least 3.
    return if (maxRunGE(g, 3) >= 3) 1.0 else 0.0;
}
fn labelRatio1(g: [NCELL]u8) f64 {
    // RATIO1: product of two threshold counts, divisible by 3.
    const p = countAtLeast(g, 4) * countAtLeast(g, 1);
    return if (p % 3 == 0) 1.0 else 0.0;
}
fn labelMixmod1(g: [NCELL]u8) f64 {
    // MIXMOD1: joint two-statistic residue equality -- gridSum%3 == count3%3.
    // Not reducible to ANY single mod-k lens on one statistic alone.
    return if ((gridSum(g) % 3) == (countAtLeast(g, THRESH) % 3)) 1.0 else 0.0;
}

const E1Target = struct { name: []const u8, kind: enum { battery_c, fresh }, c_idx: usize = 0, fresh_fn: *const fn ([NCELL]u8) f64 = labelOrder2 };

const E1_TARGETS = [_]E1Target{
    .{ .name = "C01 XOR 0x0F", .kind = .battery_c, .c_idx = 0 },
    .{ .name = "C03 XOR 0x55", .kind = .battery_c, .c_idx = 2 },
    .{ .name = "C09 inv parity", .kind = .battery_c, .c_idx = 8 },
    .{ .name = "C11 XOR 0x37", .kind = .battery_c, .c_idx = 10 },
    .{ .name = "ORDER2 rank0 parity", .kind = .fresh, .fresh_fn = labelOrder2 },
    .{ .name = "RUN1 run>=3 of >=3", .kind = .fresh, .fresh_fn = labelRun1 },
    .{ .name = "RATIO1 prod%3==0", .kind = .fresh, .fresh_fn = labelRatio1 },
    .{ .name = "MIXMOD1 sum3==count3(mod3)", .kind = .fresh, .fresh_fn = labelMixmod1 },
};

fn fillY(grid: []const [NCELL]u8, tgt: E1Target, Y: []f64) void {
    switch (tgt.kind) {
        .battery_c => for (0..NSAMP) |s| {
            Y[s] = labelC(grid[s], BATTERY_C[tgt.c_idx]);
        },
        .fresh => for (0..NSAMP) |s| {
            Y[s] = tgt.fresh_fn(grid[s]);
        },
    }
}

// ── Phase A: family diagnosis ───────────────────────────────────────────────

/// Best single-feature THRESHOLD accuracy (either polarity), exact optimum
/// on the val split, then evaluated on the test split.
fn bestThresholdAcc(feat: []const f64, Y: []const f64, alloc: std.mem.Allocator) !struct { val: f64, tst: f64 } {
    const n = NVA - NTR;
    const Item = struct { f: f64, y: f64 };
    const items = try alloc.alloc(Item, n);
    defer alloc.free(items);
    for (NTR..NVA) |s| items[s - NTR] = .{ .f = feat[s], .y = Y[s] };
    std.sort.pdq(Item, items, {}, struct {
        fn lt(_: void, a: Item, b: Item) bool {
            return a.f < b.f;
        }
    }.lt);
    var pos_total: usize = 0;
    for (items) |it| {
        if (it.y > 0.5) pos_total += 1;
    }
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
        const pred: bool = if (best_dir) feat[s] >= best_thr else feat[s] < best_thr;
        if (pred == (Y[s] > 0.5)) c += 1;
    }
    return .{ .val = best_acc, .tst = @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NSAMP - NVA)) };
}

/// Information-basis Bayes ceiling: per-bin majority vote, train->test.
fn basisCeiling(keys: []const usize, Y: []const f64, nbins: usize, alloc: std.mem.Allocator) !f64 {
    const pos = try alloc.alloc(usize, nbins);
    defer alloc.free(pos);
    const tot = try alloc.alloc(usize, nbins);
    defer alloc.free(tot);
    @memset(pos, 0);
    @memset(tot, 0);
    var gpos: usize = 0;
    for (0..NTR) |s| {
        tot[keys[s]] += 1;
        if (Y[s] > 0.5) {
            pos[keys[s]] += 1;
            gpos += 1;
        }
    }
    const gmaj: bool = gpos * 2 >= NTR;
    var c: usize = 0;
    for (NVA..NSAMP) |s| {
        const k = keys[s];
        const pred: bool = if (tot[k] == 0) gmaj else (pos[k] * 2 >= tot[k]);
        if (pred == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NSAMP - NVA));
}

const DiagCtx = struct {
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []const Feature,
    feat: []f64,
    w: []f64,
    alloc: std.mem.Allocator,
    out: std.fs.File.Writer,
    csv: std.fs.File.Writer,
    target_name: []const u8,
    seed: u64,
};

fn diagRow(
    ctx: *DiagCtx,
    Y: []const f64,
    family: []const u8,
    members: usize,
    best_desc: []const u8,
    best_val: f64,
    best_tst: f64,
    cand: ?Feature,
) !void {
    var cert_ok = false;
    var cov_after: f64 = 0;
    var r2: f64 = 99;
    if (cand) |cf| {
        var ctr = Counter{};
        var mutlib: [MAXFEAT]Feature = undefined;
        @memcpy(mutlib[0..ctx.lib.len], ctx.lib);
        const cert = certifyLocal(ctx.X, ctx.grid, mutlib[0..ctx.lib.len], cf, Y, ctx.feat, ctx.w, &ctr);
        cert_ok = cert.ok;
        cov_after = cert.cov_after;
        r2 = cert.r2;
    }
    try ctx.out.print("  {s:<26} members={d:<5} best={s:<28} val={d:.3} tst={d:.3} cert={s} (cov_after={d:.3} r2={d:.2})\n", .{
        family, members, best_desc, best_val, best_tst, if (cert_ok) "YES" else "no", cov_after, r2,
    });
    try ctx.csv.print("family_diag,0x{X:0>16},\"{s}\",{s},{d},\"{s}\",{d:.4},{d:.4},{d},{d:.4},{d:.4}\n", .{
        ctx.seed, ctx.target_name, family, members, best_desc, best_val, best_tst, @intFromBool(cert_ok), cov_after, r2,
    });
}

fn diagnoseE1Target(ctx: *DiagCtx, Y: []const f64) !void {
    const alloc = ctx.alloc;
    const grid = ctx.grid;
    const feat = ctx.feat;
    var kb: [64]u8 = undefined;

    var pos: usize = 0;
    for (0..NSAMP) |s| {
        if (Y[s] > 0.5) pos += 1;
    }
    try ctx.out.print("  base_rate={d:.3}\n", .{@as(f64, @floatFromInt(pos)) / @as(f64, NSAMP)});
    try ctx.csv.print("base_rate,0x{X:0>16},\"{s}\",-,0,\"-\",{d:.4},,,,\n", .{ ctx.seed, ctx.target_name, @as(f64, @floatFromInt(pos)) / @as(f64, NSAMP) });

    // ── EXISTING families (before) ──
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var best_mask: u8 = 0;
        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const mask: u8 = @intCast(mm);
            for (0..NSAMP) |s| feat[s] = phi(grid[s], mask);
            const r = try bestThresholdAcc(feat, Y, alloc);
            if (r.val > best_val) {
                best_val = r.val;
                best_tst = r.tst;
                best_mask = mask;
            }
        }
        const desc = std.fmt.bufPrint(&kb, "phi(0x{X:0>2})", .{best_mask}) catch "phi";
        try diagRow(ctx, Y, "EXIST monomial(deg<=8)", 255, desc, best_val, best_tst, .{ .monomial = best_mask });
    }
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bi: usize = 0;
        var bj: usize = 1;
        for (0..NCELL) |i| for (i + 1..NCELL) |j| {
            for (0..NSAMP) |s| feat[s] = pairProduct(grid[s], i, j);
            const r = try bestThresholdAcc(feat, Y, alloc);
            if (r.val > best_val) {
                best_val = r.val;
                best_tst = r.tst;
                bi = i;
                bj = j;
            }
        };
        const desc = std.fmt.bufPrint(&kb, "pair({d},{d})", .{ bi, bj }) catch "pair";
        try diagRow(ctx, Y, "EXIST pair_relation", 28, desc, best_val, best_tst, .{ .pair_relation = .{ .i = bi, .j = bj } });
    }
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bS: u8 = 0;
        for (1..DOM) |S| {
            for (0..NSAMP) |s| feat[s] = chi(@intCast(S), signPattern(grid[s]));
            const r = try bestThresholdAcc(feat, Y, alloc);
            if (r.val > best_val) {
                best_val = r.val;
                best_tst = r.tst;
                bS = @intCast(S);
            }
        }
        const desc = std.fmt.bufPrint(&kb, "chi(0x{X:0>2})", .{bS}) catch "chi";
        try diagRow(ctx, Y, "EXIST walsh(sign bits)", 255, desc, best_val, best_tst, .{ .walsh = bS });
    }
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var best_w: f64 = 0;
        const NF = 800;
        var i: usize = 1;
        while (i <= NF) : (i += 1) {
            const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
            for (0..NSAMP) |s| feat[s] = @cos(om * countGE(grid[s]));
            const r = try bestThresholdAcc(feat, Y, alloc);
            if (r.val > best_val) {
                best_val = r.val;
                best_tst = r.tst;
                best_w = om;
            }
        }
        const desc = std.fmt.bufPrint(&kb, "cos(w*c3),w={d:.4}", .{best_w}) catch "spec";
        try diagRow(ctx, Y, "EXIST spectral cos(w*c3)", 800, desc, best_val, best_tst, .{ .spectral_count = best_w });
    }
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var best_th: f64 = THETA;
        var ti: usize = 1;
        while (ti <= 64) : (ti += 1) {
            const th = std.math.pi * @as(f64, @floatFromInt(ti)) / 64.0;
            for (0..NSAMP) |s| feat[s] = cliffordTheta(grid[s], th);
            const r = try bestThresholdAcc(feat, Y, alloc);
            if (r.val > best_val) {
                best_val = r.val;
                best_tst = r.tst;
                best_th = th;
            }
        }
        const desc = std.fmt.bufPrint(&kb, "sin({d:.3}(v1-v0))", .{best_th}) catch "clif";
        try diagRow(ctx, Y, "EXIST clifford", 64, desc, best_val, best_tst, .{ .clifford_g2 = {} });
    }
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bk: usize = 2;
        var k: usize = 2;
        while (k <= 20) : (k += 1) {
            for (0..NSAMP) |s| feat[s] = if (gridSum(grid[s]) % k == 0) 1.0 else 0.0;
            const r = try bestThresholdAcc(feat, Y, alloc);
            if (r.val > best_val) {
                best_val = r.val;
                best_tst = r.tst;
                bk = k;
            }
        }
        const desc = std.fmt.bufPrint(&kb, "sum%{d}==0", .{bk}) catch "sum";
        try diagRow(ctx, Y, "EXIST world_sum_mod", 19, desc, best_val, best_tst, .{ .world_sum_mod = bk });
    }
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bk: usize = 2;
        var k: usize = 2;
        while (k <= 20) : (k += 1) {
            for (0..NSAMP) |s| feat[s] = if (@as(usize, signPattern(grid[s])) % k == 0) 1.0 else 0.0;
            const r = try bestThresholdAcc(feat, Y, alloc);
            if (r.val > best_val) {
                best_val = r.val;
                best_tst = r.tst;
                bk = k;
            }
        }
        const desc = std.fmt.bufPrint(&kb, "sign%{d}==0", .{bk}) catch "sign";
        try diagRow(ctx, Y, "EXIST world_sign_mod", 19, desc, best_val, best_tst, .{ .world_sign_mod = bk });
    }
    // EXIST cmp (earned family, round c)
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bdesc_buf: [48]u8 = undefined;
        var bdesc: []const u8 = "?";
        var bfeat: Feature = .{ .cmp = .{ .set = .all, .lens = .mod2, .omega = 0 } };
        var nmem: usize = 0;
        for (0..N_CMPSET) |si| {
            const set: CmpSet = @enumFromInt(si);
            const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
            for (fixed) |lens| {
                for (0..NSAMP) |s| feat[s] = cmpEval(grid[s], set, lens, 0);
                nmem += 1;
                const r = try bestThresholdAcc(feat, Y, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bfeat = .{ .cmp = .{ .set = set, .lens = lens, .omega = 0 } };
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "cmp({s},{s})", .{ cmpset_name[si], lens_name[@intFromEnum(lens)] }) catch "cmp";
                }
            }
            var i: usize = 1;
            while (i <= 200) : (i += 1) {
                const om = std.math.pi * @as(f64, @floatFromInt(i)) / 200.0;
                for (0..NSAMP) |s| feat[s] = cmpEval(grid[s], set, .cosw, om);
                nmem += 1;
                const r = try bestThresholdAcc(feat, Y, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bfeat = .{ .cmp = .{ .set = set, .lens = .cosw, .omega = om } };
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "cmp({s},cos w={d:.3})", .{ cmpset_name[si], om }) catch "cmp";
                }
            }
        }
        try diagRow(ctx, Y, "EARNED cmp(round c)", nmem, bdesc, best_val, best_tst, bfeat);
    }

    // ── NEW families (after) ──
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bdesc_buf: [48]u8 = undefined;
        var bdesc: []const u8 = "?";
        var bfeat: Feature = .{ .thresh = .{ .k = THRESH_KS[0], .lens = .mod2, .omega = 0 } };
        var nmem: usize = 0;
        for (THRESH_KS) |k| {
            var agg: [NSAMP]f64 = undefined;
            for (0..NSAMP) |s| agg[s] = @floatFromInt(countAtLeast(grid[s], k));
            const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
            for (fixed) |lens| {
                for (0..NSAMP) |s| feat[s] = applyLens(agg[s], lens, 0);
                nmem += 1;
                const r = try bestThresholdAcc(feat, Y, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bfeat = .{ .thresh = .{ .k = k, .lens = lens, .omega = 0 } };
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "thresh(k={d},{s})", .{ k, lens_name[@intFromEnum(lens)] }) catch "thresh";
                }
            }
            var i: usize = 1;
            while (i <= 60) : (i += 1) {
                const om = std.math.pi * @as(f64, @floatFromInt(i)) / 60.0;
                for (0..NSAMP) |s| feat[s] = @cos(om * agg[s]);
                nmem += 1;
                const r = try bestThresholdAcc(feat, Y, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bfeat = .{ .thresh = .{ .k = k, .lens = .cosw, .omega = om } };
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "thresh(k={d},cos w={d:.3})", .{ k, om }) catch "thresh";
                }
            }
        }
        try diagRow(ctx, Y, "NEW thresh", nmem, bdesc, best_val, best_tst, bfeat);
    }
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bdesc_buf: [48]u8 = undefined;
        var bdesc: []const u8 = "?";
        var bfeat: Feature = .{ .mixr = .{ .pair = 0, .ra = 2, .rb = 2, .lens = .mod2, .omega = 0 } };
        var nmem: usize = 0;
        for (0..3) |pair_u| {
            const pair: u8 = @intCast(pair_u);
            for (MIXR_RADII) |radii| {
                const ra = radii[0];
                const rb = radii[1];
                var agg: [NSAMP]f64 = undefined;
                for (0..NSAMP) |s| agg[s] = mixrIndex(grid[s], pair, ra, rb);
                const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
                for (fixed) |lens| {
                    for (0..NSAMP) |s| feat[s] = applyLens(agg[s], lens, 0);
                    nmem += 1;
                    const r = try bestThresholdAcc(feat, Y, alloc);
                    if (r.val > best_val) {
                        best_val = r.val;
                        best_tst = r.tst;
                        bfeat = .{ .mixr = .{ .pair = pair, .ra = ra, .rb = rb, .lens = lens, .omega = 0 } };
                        bdesc = std.fmt.bufPrint(&bdesc_buf, "mixr({s},{d}x{d},{s})", .{ mixr_pair_name[pair], ra, rb, lens_name[@intFromEnum(lens)] }) catch "mixr";
                    }
                }
                var i: usize = 1;
                while (i <= 60) : (i += 1) {
                    const om = std.math.pi * @as(f64, @floatFromInt(i)) / 60.0;
                    for (0..NSAMP) |s| feat[s] = @cos(om * agg[s]);
                    nmem += 1;
                    const r = try bestThresholdAcc(feat, Y, alloc);
                    if (r.val > best_val) {
                        best_val = r.val;
                        best_tst = r.tst;
                        bfeat = .{ .mixr = .{ .pair = pair, .ra = ra, .rb = rb, .lens = .cosw, .omega = om } };
                        bdesc = std.fmt.bufPrint(&bdesc_buf, "mixr({s},{d}x{d},cos w={d:.3})", .{ mixr_pair_name[pair], ra, rb, om }) catch "mixr";
                    }
                }
            }
        }
        try diagRow(ctx, Y, "NEW mixr", nmem, bdesc, best_val, best_tst, bfeat);
    }
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bdesc_buf: [48]u8 = undefined;
        var bdesc: []const u8 = "?";
        var bfeat: Feature = .{ .ratio = .{ .pair = 0, .is_prod = false, .lens = .ident, .omega = 0 } };
        var nmem: usize = 0;
        for (0..RATIO_PAIRS.len) |pair_u| {
            const pair: u8 = @intCast(pair_u);
            const p = RATIO_PAIRS[pair];
            {
                var agg: [NSAMP]f64 = undefined;
                for (0..NSAMP) |s| agg[s] = ratioDiff(grid[s], p);
                for (0..NSAMP) |s| feat[s] = agg[s];
                nmem += 1;
                var r = try bestThresholdAcc(feat, Y, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bfeat = .{ .ratio = .{ .pair = pair, .is_prod = false, .lens = .ident, .omega = 0 } };
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "ratio(diff,hi{d}lo{d},ident)", .{ p.hi, p.lo }) catch "ratio";
                }
                var i: usize = 1;
                while (i <= 60) : (i += 1) {
                    const om = 2.0 * std.math.pi * @as(f64, @floatFromInt(i)) / 60.0;
                    for (0..NSAMP) |s| feat[s] = @cos(om * agg[s]);
                    nmem += 1;
                    r = try bestThresholdAcc(feat, Y, alloc);
                    if (r.val > best_val) {
                        best_val = r.val;
                        best_tst = r.tst;
                        bfeat = .{ .ratio = .{ .pair = pair, .is_prod = false, .lens = .cosw, .omega = om } };
                        bdesc = std.fmt.bufPrint(&bdesc_buf, "ratio(diff,hi{d}lo{d},cos w={d:.3})", .{ p.hi, p.lo, om }) catch "ratio";
                    }
                }
            }
            {
                var agg: [NSAMP]f64 = undefined;
                for (0..NSAMP) |s| agg[s] = ratioProd(grid[s], p);
                const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
                for (fixed) |lens| {
                    for (0..NSAMP) |s| feat[s] = applyLens(agg[s], lens, 0);
                    nmem += 1;
                    const r = try bestThresholdAcc(feat, Y, alloc);
                    if (r.val > best_val) {
                        best_val = r.val;
                        best_tst = r.tst;
                        bfeat = .{ .ratio = .{ .pair = pair, .is_prod = true, .lens = lens, .omega = 0 } };
                        bdesc = std.fmt.bufPrint(&bdesc_buf, "ratio(prod,hi{d}lo{d},{s})", .{ p.hi, p.lo, lens_name[@intFromEnum(lens)] }) catch "ratio";
                    }
                }
                var i: usize = 1;
                while (i <= 60) : (i += 1) {
                    const om = std.math.pi * @as(f64, @floatFromInt(i)) / 60.0;
                    for (0..NSAMP) |s| feat[s] = @cos(om * agg[s]);
                    nmem += 1;
                    const r = try bestThresholdAcc(feat, Y, alloc);
                    if (r.val > best_val) {
                        best_val = r.val;
                        best_tst = r.tst;
                        bfeat = .{ .ratio = .{ .pair = pair, .is_prod = true, .lens = .cosw, .omega = om } };
                        bdesc = std.fmt.bufPrint(&bdesc_buf, "ratio(prod,hi{d}lo{d},cos w={d:.3})", .{ p.hi, p.lo, om }) catch "ratio";
                    }
                }
            }
        }
        try diagRow(ctx, Y, "NEW ratio", nmem, bdesc, best_val, best_tst, bfeat);
    }
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bdesc_buf: [48]u8 = undefined;
        var bdesc: []const u8 = "?";
        var bfeat: Feature = .{ .run = .{ .stat = 0, .lens = .mod2, .omega = 0 } };
        var nmem: usize = 0;
        for (0..5) |stat_u| {
            const stat: u8 = @intCast(stat_u);
            var agg: [NSAMP]f64 = undefined;
            for (0..NSAMP) |s| agg[s] = @floatFromInt(runStat(grid[s], stat));
            const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
            for (fixed) |lens| {
                for (0..NSAMP) |s| feat[s] = applyLens(agg[s], lens, 0);
                nmem += 1;
                const r = try bestThresholdAcc(feat, Y, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bfeat = .{ .run = .{ .stat = stat, .lens = lens, .omega = 0 } };
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "run({s},{s})", .{ run_stat_name[stat], lens_name[@intFromEnum(lens)] }) catch "run";
                }
            }
            var i: usize = 1;
            while (i <= 60) : (i += 1) {
                const om = std.math.pi * @as(f64, @floatFromInt(i)) / 60.0;
                for (0..NSAMP) |s| feat[s] = @cos(om * agg[s]);
                nmem += 1;
                const r = try bestThresholdAcc(feat, Y, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bfeat = .{ .run = .{ .stat = stat, .lens = .cosw, .omega = om } };
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "run({s},cos w={d:.3})", .{ run_stat_name[stat], om }) catch "run";
                }
            }
        }
        try diagRow(ctx, Y, "NEW run", nmem, bdesc, best_val, best_tst, bfeat);
    }

    // ── 7 Bayes ceilings over EXISTING information bases (the "before" proof) ──
    {
        const keys = try alloc.alloc(usize, NSAMP);
        defer alloc.free(keys);
        const Basis = struct { name: []const u8, nbins: usize, covers: []const u8 };
        const bases = [_]Basis{
            .{ .name = "basis:count3", .nbins = 9, .covers = "spectral+modsynth(count)" },
            .{ .name = "basis:gridSum", .nbins = 41, .covers = "world_sum_mod" },
            .{ .name = "basis:signPattern", .nbins = 256, .covers = "walsh+world_sign_mod" },
            .{ .name = "basis:v1-v0", .nbins = 11, .covers = "clifford" },
            .{ .name = "basis:inversion", .nbins = 29, .covers = "cmp(all28)" },
            .{ .name = "basis:max_cell", .nbins = 6, .covers = "pipeline(max)" },
            .{ .name = "basis:sum01", .nbins = 11, .covers = "pipeline(sum01)" },
        };
        for (bases) |b| {
            for (0..NSAMP) |s| {
                const g = grid[s];
                keys[s] = switch (b.name[6]) {
                    'c' => @intFromFloat(countGE(g)),
                    'g' => gridSum(g),
                    's' => if (b.name.len > 7 and b.name[7] == 'i') @as(usize, signPattern(g)) else @as(usize, g[0] + g[1]),
                    'v' => @intCast(@as(i16, g[1]) - @as(i16, g[0]) + 5),
                    'i' => inversionCount(g),
                    'm' => blk: {
                        var m: u8 = 0;
                        for (g) |v| m = @max(m, v);
                        break :blk m;
                    },
                    else => 0,
                };
            }
            const ceil = try basisCeiling(keys, Y, b.nbins, alloc);
            try ctx.out.print("  {s:<26} Bayes ceiling (test) = {d:.3}   [bounds: {s}]\n", .{ b.name, ceil, b.covers });
            try ctx.csv.print("basis_ceiling,0x{X:0>16},\"{s}\",{s},{d},\"{s}\",{d:.4},,,,\n", .{ ctx.seed, ctx.target_name, b.name, b.nbins, b.covers, ceil });
        }
    }
}

// ── main ─────────────────────────────────────────────────────────────────────
fn seedLibFromZoo(zoo: []const rq1.Feature, lib: []Feature, nlib: *usize) void {
    nlib.* = 0;
    for (zoo) |f| {
        lib[nlib.*] = .{ .monomial = f.monomial };
        nlib.* += 1;
    }
}

const ArmTotals = struct {
    b_solved: usize = 0,
    c_solved: usize = 0,
    d_solved: usize = 0,
    probes: usize = 0,
    certs: usize = 0,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var diag_only = false;
    var phaseb_only = false;
    {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();
        _ = args.skip();
        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "--diag")) diag_only = true;
            if (std.mem.eql(u8, a, "--phaseb")) phaseb_only = true;
        }
    }

    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/repr_expansion_2026_07_11.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = if (phaseb_only)
        try std.fs.cwd().openFile(csv_path, .{ .mode = .write_only })
    else
        try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    if (phaseb_only) try cf.seekFromEnd(0);
    const cw = cf.writer();
    if (!phaseb_only) try cw.print("phase,seed,target,family_or_arm,members_or_idx,detail,val_or_cov,tst,cert_or_solved,cov_after_or_probes,r2_or_certs\n", .{});

    const t_start = std.time.milliTimestamp();

    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT + 2);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    const feat = try alloc.alloc(f64, NSAMP);
    var w: [MAXFEAT + 2]f64 = undefined;
    const Yd = try alloc.alloc(f64, NSAMP);

    // ── PHASE A: (target x family) closure lattice, all 3 seeds ──
    if (!phaseb_only) {
    try out.print("════════ PHASE A: closure-expansion lattice (8 targets x 3 seeds) ════════\n", .{});
    for (SEEDS) |seed| {
        var prng = std.Random.DefaultPrng.init(seed);
        const rand = prng.random();
        const grid = try alloc.alloc([NCELL]u8, NSAMP);
        for (0..NSAMP) |s| {
            for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, 5);
        }
        const Yzoo = try alloc.alloc([]f64, 4);
        for (0..4) |t| {
            Yzoo[t] = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| Yzoo[t][s] = if (phi(grid[s], ZOO_MASKS[t]) > 0) 1.0 else 0.0;
        }
        const trained = try rq1.trainZooA(X, grid, Yzoo, phiTgt, w[0..], SilentOut{});
        const zoo_lib = trained.lib[0..trained.nlib];
        var base_lib: [MAXFEAT]Feature = undefined;
        var base_nlib: usize = 0;
        seedLibFromZoo(zoo_lib, &base_lib, &base_nlib);

        var dctx = DiagCtx{
            .X = X,
            .grid = grid,
            .lib = base_lib[0..base_nlib],
            .feat = feat,
            .w = w[0..],
            .alloc = alloc,
            .out = out,
            .csv = cw,
            .target_name = "",
            .seed = seed,
        };

        for (E1_TARGETS) |tgt| {
            try out.print("\n── {s} (seed 0x{X:0>16}) ──\n", .{ tgt.name, seed });
            dctx.target_name = tgt.name;
            fillY(grid, tgt, Yd);
            try diagnoseE1Target(&dctx, Yd);
        }
        try out.print("\n[seed 0x{X:0>16} done at {d}ms]\n", .{ seed, std.time.milliTimestamp() - t_start });
    }
    try out.print("\nPhase A done at {d}ms\n", .{std.time.milliTimestamp() - t_start});

    if (diag_only) {
        try out.print("(--diag: stopping before Phase B)\nCSV: {s}\n", .{csv_path});
        return;
    }

    // ── PHASE A2: 8-target LADDER attribution (real solveLadder, not the
    //    diagnostic generous-sweep) -- confirms Phase A's certify calls under
    //    the actual production-style escalation mechanism, all 3 seeds. ──
    try out.print("\n════════ PHASE A2: 8-target ladder attribution (solveLadder, 3 seeds) ════════\n", .{});
    {
        const AttrArm = struct { name: []const u8, opts: LadderOpts };
        // Per-family attribution is delivered rigorously by Phase A's isolated
        // certify sweep (all 3 seeds); A2 confirms the aggregate BASE->ALL lift
        // under the real solveLadder escalation (2 arms for budget).
        const attr_arms = [_]AttrArm{
            .{ .name = "BASE", .opts = .{ .menuacc = true, .cmp = true } },
            .{ .name = "ALL", .opts = .{ .menuacc = true, .cmp = true, .thresh = true, .mixr = true, .ratio = true, .run = true } },
        };
        for (SEEDS) |seed| {
            var prng2 = std.Random.DefaultPrng.init(seed);
            const rand2 = prng2.random();
            const grid2 = try alloc.alloc([NCELL]u8, NSAMP);
            for (0..NSAMP) |s| {
                for (0..NCELL) |i| grid2[s][i] = rand2.intRangeAtMost(u8, 0, 5);
            }
            const Yzoo2 = try alloc.alloc([]f64, 4);
            for (0..4) |t| {
                Yzoo2[t] = try alloc.alloc(f64, NSAMP);
                for (0..NSAMP) |s| Yzoo2[t][s] = if (phi(grid2[s], ZOO_MASKS[t]) > 0) 1.0 else 0.0;
            }
            const trained2 = try rq1.trainZooA(X, grid2, Yzoo2, phiTgt, w[0..], SilentOut{});
            const zoo_lib2 = trained2.lib[0..trained2.nlib];

            for (E1_TARGETS) |tgt| {
                fillY(grid2, tgt, Yd);
                try out.print("  {s:<26} seed 0x{X:0>16}:", .{ tgt.name, seed });
                for (attr_arms) |arm| {
                    var lib: [MAXFEAT]Feature = undefined;
                    var nlib: usize = 0;
                    seedLibFromZoo(zoo_lib2, &lib, &nlib);
                    const m = solveLadder(X, grid2, &lib, &nlib, Yd, phiTgt, w[0..], arm.opts);
                    var kbuf: [64]u8 = undefined;
                    const srcd: []const u8 = if (m.solved and nlib > 0 and m.source != .base) featureKey(&kbuf, lib[nlib - 1]) else "-";
                    try out.print(" {s}={s}({s},cov={d:.2})", .{ arm.name, if (m.solved) "Y" else "n", srcd, m.cov });
                    try cw.print("ladder_attr,0x{X:0>16},\"{s}\",{s},0,\"{s}\",{d:.4},,{d},{d},{d}\n", .{ seed, tgt.name, arm.name, srcd, m.cov, @intFromBool(m.solved), m.probes, m.certs });
                }
                try out.print("\n", .{});
            }
        }
    }
    try out.print("\nPhase A2 done at {d}ms\n", .{std.time.milliTimestamp() - t_start});
    } // end if(!phaseb_only)

    // ── PHASE B: regression check (1 seed: production) ──
    try out.print("\n════════ PHASE B: battery regression (BASE vs ALL, production seed) ════════\n", .{});
    const ArmSpec = struct { name: []const u8, opts: LadderOpts };
    const arms = [_]ArmSpec{
        .{ .name = "BASE(earned:menuacc+cmp)", .opts = .{ .menuacc = true, .cmp = true } },
        .{ .name = "ALL(+thresh+mixr+ratio+run)", .opts = .{ .menuacc = true, .cmp = true, .thresh = true, .mixr = true, .ratio = true, .run = true } },
    };

    var bprng = std.Random.DefaultPrng.init(rq1.BATTERY_SEED);
    const battery_b = try rq1.generateBatteryB(bprng.random(), alloc);
    const Yb = try alloc.alloc(f64, NSAMP);

    // regression bookkeeping: solved[armidx][battery][target_idx]
    var solved_b: [2][11]bool = undefined;
    var solved_c: [2][11]bool = undefined;
    var solved_d: [2][11]bool = undefined;
    var source_b: [2][11]Source = undefined;
    var source_c: [2][11]Source = undefined;
    var source_d: [2][11]Source = undefined;

    for (arms, 0..) |arm, ai| {
        var prng = std.Random.DefaultPrng.init(GRID_SEED);
        const rand = prng.random();
        const grid = try alloc.alloc([NCELL]u8, NSAMP);
        for (0..NSAMP) |s| {
            for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, 5);
        }
        const Yzoo = try alloc.alloc([]f64, 4);
        for (0..4) |t| {
            Yzoo[t] = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| Yzoo[t][s] = if (phi(grid[s], ZOO_MASKS[t]) > 0) 1.0 else 0.0;
        }
        const trained = try rq1.trainZooA(X, grid, Yzoo, phiTgt, w[0..], SilentOut{});
        const zoo_lib = trained.lib[0..trained.nlib];

        try out.print("── ARM {s} (seed 0x{X:0>16}) ──\n", .{ arm.name, GRID_SEED });

        var tot = ArmTotals{};

        // Battery B: shared growable library (production protocol)
        var blib: [MAXFEAT]Feature = undefined;
        var bnlib: usize = 0;
        seedLibFromZoo(zoo_lib, &blib, &bnlib);
        var b_solved: usize = 0;
        for (battery_b, 0..) |tgt, ti| {
            for (0..NSAMP) |s| Yb[s] = rq1.labelBattery(grid[s], tgt);
            const m = solveLadder(X, grid, &blib, &bnlib, Yb, phiTgt, w[0..], arm.opts);
            if (m.solved) b_solved += 1;
            solved_b[ai][ti] = m.solved;
            source_b[ai][ti] = m.source;
            tot.probes += m.probes;
            tot.certs += m.certs;
            try cw.print("ladder,0x{X:0>16},\"{s}\",{s},{d},\"battB\",{d:.4},,{d},{d},{d}\n", .{ GRID_SEED, tgt.name, arm.name, ti, m.cov, @intFromBool(m.solved), m.probes, m.certs });
        }
        tot.b_solved = b_solved;

        // Battery C: fresh library per target.
        // BUDGET NOTE: the 9 XOR/parity-XOR-wall C targets (C01-C07,C10,C11)
        // are BASE-unsolved AND ALL-unsolved (chance ~0.50) -- proven a
        // family-level wall by Phase A's Bayes ceilings (all 3 seeds) and by
        // tier8_reach_gap/breadth_scaling (no ladder family, old or new,
        // reaches GF(2) XOR). They are BASE-unsolved so cannot regress
        // (regression = BASE-solved AND NOT ALL-solved). Running each through
        // the full ladder (monomial forge + 200-cos cmp scan + 4 new stages +
        // 12 world certifies) twice costs ~4 min and unlocks nothing, so they
        // are recorded as unsolved without the redundant run. C08 (parity
        // count, BASE-solvable) and C09 (inversion parity, cmp-solvable) ARE
        // run in full -- they are the only BASE-solvable C cells.
        var c_solved: usize = 0;
        for (BATTERY_C, 0..) |tgt, ti| {
            const run_full = (ti == 7 or ti == 8); // C08, C09
            for (0..NSAMP) |s| Yb[s] = labelC(grid[s], tgt);
            if (run_full) {
                var clib: [MAXFEAT]Feature = undefined;
                var cnlib: usize = 0;
                seedLibFromZoo(zoo_lib, &clib, &cnlib);
                const m = solveLadder(X, grid, &clib, &cnlib, Yb, phiTgt, w[0..], arm.opts);
                if (m.solved) c_solved += 1;
                solved_c[ai][ti] = m.solved;
                source_c[ai][ti] = m.source;
                tot.probes += m.probes;
                tot.certs += m.certs;
                try cw.print("ladder,0x{X:0>16},\"{s}\",{s},{d},\"battC\",{d:.4},,{d},{d},{d}\n", .{ GRID_SEED, tgt.name, arm.name, ti, m.cov, @intFromBool(m.solved), m.probes, m.certs });
            } else {
                solved_c[ai][ti] = false;
                source_c[ai][ti] = .none;
                try cw.print("ladder,0x{X:0>16},\"{s}\",{s},{d},\"battC_skipXORwall\",0.5000,,0,0,0\n", .{ GRID_SEED, tgt.name, arm.name, ti });
            }
        }
        tot.c_solved = c_solved;

        // Battery D: fresh library per target
        var d_solved: usize = 0;
        for (bd.BATTERY_D, 0..) |tgt, ti| {
            for (0..NSAMP) |s| Yb[s] = bd.labelTarget(grid[s], tgt);
            var dlib: [MAXFEAT]Feature = undefined;
            var dnlib: usize = 0;
            seedLibFromZoo(zoo_lib, &dlib, &dnlib);
            const m = solveLadder(X, grid, &dlib, &dnlib, Yb, phiTgt, w[0..], arm.opts);
            if (m.solved) d_solved += 1;
            solved_d[ai][ti] = m.solved;
            source_d[ai][ti] = m.source;
            tot.probes += m.probes;
            tot.certs += m.certs;
            try cw.print("ladder,0x{X:0>16},\"{s}\",{s},{d},\"battD\",{d:.4},,{d},{d},{d}\n", .{ GRID_SEED, tgt.name, arm.name, ti, m.cov, @intFromBool(m.solved), m.probes, m.certs });
        }
        tot.d_solved = d_solved;

        try out.print("  B {d}/11  C {d}/11  D {d}/11  probes={d} certs={d}  ({d}ms elapsed)\n\n", .{ tot.b_solved, tot.c_solved, tot.d_solved, tot.probes, tot.certs, std.time.milliTimestamp() - t_start });
    }

    // ── Regression report ──
    try out.print("── Regression check (BASE-solved => ALL-solved?) ──\n", .{});
    var regressions: usize = 0;
    var flips: usize = 0;
    inline for (.{ "battB", "battC", "battD" }) |bname| {
        const solved = if (std.mem.eql(u8, bname, "battB")) &solved_b else if (std.mem.eql(u8, bname, "battC")) &solved_c else &solved_d;
        const source = if (std.mem.eql(u8, bname, "battB")) &source_b else if (std.mem.eql(u8, bname, "battC")) &source_c else &source_d;
        for (0..11) |ti| {
            const base_ok = solved[0][ti];
            const all_ok = solved[1][ti];
            if (base_ok and !all_ok) {
                regressions += 1;
                try out.print("  REGRESSION: {s}[{d}] solved in BASE, NOT in ALL!\n", .{ bname, ti });
            }
            if (!base_ok and all_ok) {
                flips += 1;
                try out.print("  FLIP: {s}[{d}] newly solved by ALL, source={s}\n", .{ bname, ti, @tagName(source[1][ti]) });
            }
        }
    }
    try out.print("  regressions={d}  new_flips={d}\n", .{ regressions, flips });
    try cw.print("regression_summary,0x{X:0>16},\"-\",summary,0,\"-\",{d:.4},,{d},{d},\n", .{ GRID_SEED, 0.0, regressions, flips });

    try out.print("\nTotal wall: {d}ms\nCSV: {s}\n", .{ std.time.milliTimestamp() - t_start, csv_path });
}
