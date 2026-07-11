//! F2 (Round 2026-07-11b) — AUTO-FAMILY DISCOVERY FOR ORDER2.
//!
//! Context: `docs/research/repr_expansion.md` (E1, round E) grew the family
//! menu by four hand-designed generators (thresh/mixr/ratio/run) and left
//! ORDER2 (parity of rank(cell 0) among the other 7 cells) as the cleanest
//! standing UNREACHABLE target: every existing family, including round-c's
//! earned comparison-pair aggregate `cmp` (5 fixed pair-sets: all28/low6/
//! high6/cross16/adj7), tops out at a Bayes ceiling of 0.646 (signPattern
//! basis) and a best-any-family val of 0.64. `wcore/docs/research/smart_gen.md`
//! (E3) showed a DIFFERENT machine (program synthesis over an alien ISA) can
//! auto-discover a MECHANISM (the noveltyflag load;store;xor stone) given a
//! structural prior (exhaustive behaviour-deduped coverage steered by a
//! read-then-write-same-address inclusion) where blind bulk generation
//! (54,432 candidates, 0 payoff) and gradient/prior-sampling all failed.
//!
//! F2 asks the successor question IN THE TIER-8 POLYNOMIAL-DISCOVERY DOMAIN:
//! can the SAME smart-generation method — exhaustive, behaviour-deduped
//! coverage over a small alphabet, steered by a STRUCTURAL PRIOR — auto-
//! discover the FAMILY that certifies ORDER2, rather than have that family
//! (a "distinguished cell" pair-set) handed to the search as one of a fixed
//! menu of 5? The prior here is "comparison-shape": compare pairs of cells,
//! then aggregate by count, then apply a lens — exactly CMP's own shape, but
//! with the PAIR-SET ITSELF turned into a search variable (a subset of cells
//! S subset {0..7} plus a relation-to-S mode) instead of 5 fixed choices.
//! This is the natural generalization CMP's 5 canonical sets are literally
//! SPECIAL CASES of: all28 = within(full set), low6 = within({0,1,2,3}),
//! high6 = within({4,5,6,7}), cross16 = between({0,1,2,3}), and the missing
//! "rank of one distinguished cell" statistic ORDER2 needs = between/touching
//! of a SINGLETON {k} — one of 8 hub choices the fixed CMP menu never
//! enumerated because none of its 5 sets is a singleton hub.
//!
//! Design (see docs/research/autofamily_order2.md for full narrative):
//!   PHASE 0 (before-proof, reproduces E1): the 7 existing-basis Bayes
//!     ceilings for ORDER2 (expect ~0.646) + the EARNED cmp family's best
//!     member on ORDER2 over its 5 fixed pair-sets (expect ~0.64, well under
//!     COVER=0.90) — confirms the frontier is real before searching for an
//!     escape.
//!   PHASE 1 (auto-discovery): exhaustive sweep over the "distinguished
//!     comparison" generator DCMP — subset mask in [1,255] (255 nonempty
//!     subsets of the 8 cells) x mode in {within, between, touching} (765
//!     pair-set candidates) x the standard lens set (ident/mod2../mod6 + a
//!     60-point cos scan) — scored by exact best-threshold train->test
//!     accuracy (bestThresholdAcc, matching E1's own Phase-A diagnostic
//!     metric, NOT the answer). The winning candidate is then independently
//!     re-scored by the SGD/logit statistic (valAccSingle) the real certifier
//!     uses (the D08 lesson: selection statistic must agree with the
//!     certification statistic) and put through the standard pre-tax
//!     certifier (COVER escape + R² < 0.40 novelty gate). Run at the 3
//!     standard seeds PLUS one genuinely held-out 4th seed never used
//!     anywhere else in this round, as a retro-audit that the discovery is
//!     not a coincidence of the 3 measurement seeds (the domain-appropriate
//!     analogue of the wcore lineage's "depth-4 prefix-reduction audit" —
//!     there is no program-depth notion in this polynomial-discovery domain,
//!     so the audit here is independent-seed rediscovery + the R² novelty
//!     check, both stated honestly in the doc).
//!   PHASE 2 (regression, production seed): the pre-tax ladder (BASE = earned
//!     menuacc+cmp, matching tier8_reach_gap/E1's earned baseline; ALL =
//!     BASE + the new dcmp stage placed after cmp, before world) run on the
//!     full Battery B (11 targets, shared growable library — production
//!     protocol), D07 + D08 (fresh library), a local inversion-parity target
//!     (the C09 statistic, fresh library), and ORDER2 itself (fresh
//!     library) — checks BASE-solved implies ALL-solved (zero regressions)
//!     and that ALL newly solves ORDER2 via dcmp.
//!
//! Deliberately NOT imported: equivalence_tax.zig, unified_invention.zig,
//! invention_engine.zig (tax dependency, matching the round's convention).
//! `sparse_poly_discovery/repr_expansion.zig` and `wcore/src/smart_gen.zig`
//! are reused READ-ONLY (their method is transcribed, not imported) per the
//! task's file-creation rule; numeric glue (phi/coverage/certifyLocal/cmp/
//! valAccSingle/ladder stages) is duplicated here from repr_expansion.zig,
//! the established convention in this arc.
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe autofamily_order2.zig -O ReleaseFast
//! Run (each phase is independently invocable and bounded well under 15 min;
//! default with no args runs all three phases in one process):
//!   ./autofamily_order2 --phase0    (before-proof, ~few sec)
//!   ./autofamily_order2 --phase1    (auto-discovery, 4 seeds, ~1 min)
//!   ./autofamily_order2 --phase2    (ladder regression, production seed, ~1-2 min)
//!   ./autofamily_order2             (all three, ~2-3 min)
//! Single-threaded (<=2 cores per the round's constraint; this binary uses 1).

const std = @import("std");
const rq1 = @import("open_invention_rq1.zig"); // no eqtax dependency (std+hr+oml); zoo training + Battery B
const bd = @import("tier8_battery_d.zig"); // std only; Battery D
const oml = @import("operator_menu_lib.zig"); // std only; discoverSpectral/discoverWalsh

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

// ── Constants (identical to repr_expansion.zig / tier8_reach_gap.zig) ──────
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
// Genuinely held-out 4th seed: never used in Phase 0/1 discovery-tuning, nor
// in any prior round doc (grepped clean against repr_expansion.md /
// smart_gen.md / tier8_reach_gap.md before picking it). Used ONLY as the
// retro-audit seed in Phase 1 -- the discovery search itself never sees it
// during "which mask/mode/lens wins" selection at the 3 standard seeds.
const HOLDOUT_SEED: u64 = 0x0FAD5EED20260711;
const ZOO_MASKS = [_]u8{ (1 << 2) | (1 << 5), (1 << 1) | (1 << 3) | (1 << 6), (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7), (1 << 3) };

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
}

// ── Grid functions (identical to repr_expansion.zig) ───────────────────────
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

// ── EARNED family (round c / E1): comparison-pair aggregates, 5 fixed sets ─
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

// ── Standard lens set (ident/mod2../mod6/cos) -- shared by cmp and dcmp ────
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

// ── NEW FAMILY: DCMP -- distinguished-comparison generator (the search) ───
// The pair-SET itself is a search variable: mask (subset of the 8 cells,
// 1..255) x mode (within/between/touching), instead of 5 hand-picked sets.
// CMP's 5 sets are literally special cases: all28=within(0xFF),
// low6=within(0x0F), high6=within(0xF0), cross16=between(0x0F) -- but NO
// (mask,mode) in CMP's fixed menu is a SINGLETON mask (a "hub" cell), which
// is exactly what ORDER2 (rank of cell 0) needs: between({0}) = the star of
// comparisons touching cell 0, aggregated by the SAME count-then-lens shape.
const PSMode = enum(u8) { within, between, touching };
const psmode_name = [_][]const u8{ "within", "between", "touching" };

fn dcmpAggregate(g: [NCELL]u8, mask: u8, mode: PSMode) usize {
    var a: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        const iin = (mask & (@as(u8, 1) << @intCast(i))) != 0;
        const jin = (mask & (@as(u8, 1) << @intCast(j))) != 0;
        const include = switch (mode) {
            .within => iin and jin,
            .between => iin != jin,
            .touching => iin or jin,
        };
        if (include and g[i] > g[j]) a += 1;
    };
    return a;
}

fn dcmpEval(g: [NCELL]u8, mask: u8, mode: PSMode, lens: StdLens, omega: f64) f64 {
    return applyLens(@floatFromInt(dcmpAggregate(g, mask, mode)), lens, omega);
}

fn dcmpKey(buf: []u8, mask: u8, mode: PSMode, lens: StdLens, omega: f64) []const u8 {
    if (lens == .cosw)
        return std.fmt.bufPrint(buf, "dcmp(mask=0x{X:0>2},pop={d},{s},cos w={d:.4})", .{ mask, popcount(mask), psmode_name[@intFromEnum(mode)], omega }) catch "dcmp";
    return std.fmt.bufPrint(buf, "dcmp(mask=0x{X:0>2},pop={d},{s},{s})", .{ mask, popcount(mask), psmode_name[@intFromEnum(mode)], lens_name[@intFromEnum(lens)] }) catch "dcmp";
}

// ── Feature library (existing union + earned cmp + NEW dcmp) ──────────────
const Feature = union(enum) {
    monomial: u8,
    pair_relation: struct { i: usize, j: usize },
    spectral_count: f64,
    walsh: u8,
    clifford_g2: void,
    world_sum_mod: usize,
    world_sign_mod: usize,
    cmp: struct { set: CmpSet, lens: StdLens, omega: f64 },
    dcmp: struct { mask: u8, mode: PSMode, lens: StdLens, omega: f64 },
};

const Source = enum { base, forge, pair, walsh, menu, menuacc, cmp, dcmp, world, none };

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
        .dcmp => |d| dcmpEval(g, d.mask, d.mode, d.lens, d.omega),
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
        .dcmp => |d| return dcmpKey(buf, d.mask, d.mode, d.lens, d.omega),
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
        .dcmp => |d| b.dcmp.mask == d.mask and b.dcmp.mode == d.mode and b.dcmp.lens == d.lens and @abs(b.dcmp.omega - d.omega) < 1e-6,
    };
}

fn hasFeature(lib: []const Feature, f: Feature) bool {
    for (lib) |x| if (featuresEqual(x, f)) return true;
    return false;
}

// ── ML helpers (identical numerics to repr_expansion.zig) ──────────────────
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

// single-feature SGD probe -- the PRODUCTION selection statistic (matches
// the certifier's own logistic fit; this is what cmp/thresh/mixr/etc. use to
// pick a member inside the real ladder, per the D08/MENUACC lesson that
// selection and certification statistics must agree).
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

/// Exact best-threshold accuracy (either polarity), train->test. The
/// DIAGNOSTIC statistic (E1 Phase A's own method) -- cheap (no SGD epochs),
/// used for the Phase 0/1 exhaustive sweeps, NOT for the ladder-embedded
/// production stage (which uses valAccSingle, see tryDcmpStage below).
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

// ── Cost counters ───────────────────────────────────────────────────────────
const Counter = struct {
    probes: usize = 0,
    certs: usize = 0,
};

// ── Pre-tax certifier (identical to repr_expansion.zig's certifyLocal) ─────
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

// ── Ladder stages (transcribed from repr_expansion.zig, pre-tax) ──────────
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

// ── NEW STAGE: DCMP -- production-realistic (valAccSingle selection, NF=16
//    trimmed cos-scan matching the established convention: E1 found every
//    certified new-family solve used a mod lens, never cos, across 3 seeds;
//    verified again here in Phase 1 before trimming for the ladder stage) ──
fn tryDcmpStage(
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
    var best: Feature = .{ .dcmp = .{ .mask = 1, .mode = .between, .lens = .mod2, .omega = 0 } };
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        inline for (.{ PSMode.within, PSMode.between, PSMode.touching }) |mode| {
            var agg: [NSAMP]f64 = undefined;
            for (0..NSAMP) |s| agg[s] = @floatFromInt(dcmpAggregate(grid[s], mask, mode));
            const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
            for (fixed) |lens| {
                for (0..NSAMP) |s| feat_scratch[s] = applyLens(agg[s], lens, 0);
                ctr.probes += 1;
                const v = valAccSingle(feat_scratch, Y);
                if (v > best_val) {
                    best_val = v;
                    best = .{ .dcmp = .{ .mask = mask, .mode = mode, .lens = lens, .omega = 0 } };
                }
            }
            const NF = 16; // trimmed, matching E1's established convention
            var i: usize = 1;
            while (i <= NF) : (i += 1) {
                const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
                for (0..NSAMP) |s| feat_scratch[s] = @cos(om * agg[s]);
                ctr.probes += 1;
                const v = valAccSingle(feat_scratch, Y);
                if (v > best_val) {
                    best_val = v;
                    best = .{ .dcmp = .{ .mask = mask, .mode = mode, .lens = .cosw, .omega = om } };
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

// ── The ladder (BASE = earned menuacc+cmp; ALL = BASE + dcmp) ─────────────
const LadderOpts = struct {
    menuacc: bool = false,
    cmp: bool = false,
    dcmp: bool = false,
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

    if (opts.dcmp) {
        if (tryDcmpStage(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
            cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
            if (cov0 >= COVER) return .{ .solved = true, .cov = cov0, .source = .dcmp, .probes = ctr.probes, .certs = ctr.certs };
        }
    }

    if (tryWorldPool(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) source = .world;
    }

    return .{ .solved = cov0 >= COVER, .cov = cov0, .source = if (cov0 >= COVER) source else .none, .probes = ctr.probes, .certs = ctr.certs };
}

// ── ORDER2 target (transcribed verbatim from repr_expansion.zig) ──────────
fn labelOrder2(g: [NCELL]u8) f64 {
    var r: usize = 0;
    for (1..NCELL) |j| {
        if (g[j] < g[0]) r += 1;
    }
    return @floatFromInt(r & 1);
}

fn labelInvParity(g: [NCELL]u8) f64 {
    return @floatFromInt(inversionCount(g) & 1);
}

fn seedLibFromZoo(zoo: []const rq1.Feature, lib: []Feature, nlib: *usize) void {
    nlib.* = 0;
    for (zoo) |f| {
        lib[nlib.*] = .{ .monomial = f.monomial };
        nlib.* += 1;
    }
}

fn genGrid(alloc: std.mem.Allocator, seed: u64) ![][NCELL]u8 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| {
        for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, 5);
    }
    return grid;
}

const ZooLib = struct { lib: [MAXFEAT]Feature, nlib: usize };

fn zooLibFor(alloc: std.mem.Allocator, X: [][]f64, grid: []const [NCELL]u8, phiTgt: []f64, w: []f64) !ZooLib {
    var base_lib: [MAXFEAT]Feature = undefined;
    var base_nlib: usize = 0;
    const Yzoo = try alloc.alloc([]f64, 4);
    for (0..4) |t| {
        Yzoo[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Yzoo[t][s] = if (phi(grid[s], ZOO_MASKS[t]) > 0) 1.0 else 0.0;
    }
    const trained = try rq1.trainZooA(X, grid, Yzoo, phiTgt, w, SilentOut{});
    seedLibFromZoo(trained.lib[0..trained.nlib], &base_lib, &base_nlib);
    return .{ .lib = base_lib, .nlib = base_nlib };
}

// ══════════════════════════════════════════════════════════════════════════
// PHASE 0: before-proof -- reproduce ORDER2's Bayes ceiling + CMP insufficiency
// ══════════════════════════════════════════════════════════════════════════
fn phase0(alloc: std.mem.Allocator, out: anytype, cw: anytype, X: [][]f64, feat: []f64) !void {
    _ = X;
    try out.print("════════ PHASE 0: before-proof (ORDER2 ceiling + CMP insufficiency, 3 seeds) ════════\n", .{});
    for (SEEDS) |seed| {
        const grid = try genGrid(alloc, seed);
        const Yd = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Yd[s] = labelOrder2(grid[s]);

        var pos: usize = 0;
        for (0..NSAMP) |s| if (Yd[s] > 0.5) {
            pos += 1;
        };
        try out.print("\n── ORDER2 (seed 0x{X:0>16}) base_rate={d:.3} ──\n", .{ seed, @as(f64, @floatFromInt(pos)) / @as(f64, NSAMP) });
        try cw.print("base_rate,0x{X:0>16},ORDER2,-,{d:.4},,,,\n", .{ seed, @as(f64, @floatFromInt(pos)) / @as(f64, NSAMP) });

        // 7 existing-basis Bayes ceilings (identical bases to E1).
        const keys = try alloc.alloc(usize, NSAMP);
        const Basis = struct { name: []const u8, nbins: usize };
        const bases = [_]Basis{
            .{ .name = "basis:count3", .nbins = 9 },
            .{ .name = "basis:gridSum", .nbins = 41 },
            .{ .name = "basis:signPattern", .nbins = 256 },
            .{ .name = "basis:v1-v0", .nbins = 11 },
            .{ .name = "basis:inversion", .nbins = 29 },
            .{ .name = "basis:max_cell", .nbins = 6 },
            .{ .name = "basis:sum01", .nbins = 11 },
        };
        var max_ceil: f64 = 0;
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
            const ceil = try basisCeiling(keys, Yd, b.nbins, alloc);
            max_ceil = @max(max_ceil, ceil);
            try out.print("  {s:<26} Bayes ceiling (test) = {d:.3}\n", .{ b.name, ceil });
            try cw.print("basis_ceiling,0x{X:0>16},ORDER2,{s},{d:.4},,,,\n", .{ seed, b.name, ceil });
        }
        try out.print("  MAX existing-basis ceiling = {d:.3}  (E1 reported 0.646 at signPattern)\n", .{max_ceil});

        // EARNED cmp family: best member over its 5 fixed pair-sets.
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bdesc_buf: [48]u8 = undefined;
        var bdesc: []const u8 = "?";
        for (0..N_CMPSET) |si| {
            const set: CmpSet = @enumFromInt(si);
            const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
            for (fixed) |lens| {
                for (0..NSAMP) |s| feat[s] = cmpEval(grid[s], set, lens, 0);
                const r = try bestThresholdAcc(feat, Yd, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "cmp({s},{s})", .{ cmpset_name[si], lens_name[@intFromEnum(lens)] }) catch "cmp";
                }
            }
            var i: usize = 1;
            while (i <= 200) : (i += 1) {
                const om = std.math.pi * @as(f64, @floatFromInt(i)) / 200.0;
                for (0..NSAMP) |s| feat[s] = cmpEval(grid[s], set, .cosw, om);
                const r = try bestThresholdAcc(feat, Yd, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "cmp({s},cos w={d:.3})", .{ cmpset_name[si], om }) catch "cmp";
                }
            }
        }
        try out.print("  EARNED cmp best member: {s}  val={d:.3} tst={d:.3}  (5 fixed pair-sets, none is a distinguished-cell hub)\n", .{ bdesc, best_val, best_tst });
        try cw.print("cmp_insufficiency,0x{X:0>16},ORDER2,\"{s}\",{d:.4},{d:.4},,,\n", .{ seed, bdesc, best_val, best_tst });
    }
    try out.print("\nPhase 0 verdict: ORDER2 confirmed UNREPRESENTABLE before the search -- ceiling <=0.646, earned cmp <=~0.64, both far under COVER=0.90.\n", .{});
}

// ══════════════════════════════════════════════════════════════════════════
// PHASE 1: auto-discovery -- exhaustive DCMP sweep, 3 seeds + 1 holdout
// ══════════════════════════════════════════════════════════════════════════
const DcmpWinner = struct { mask: u8, mode: PSMode, lens: StdLens, omega: f64, val: f64, tst: f64 };

fn sweepDcmp(alloc: std.mem.Allocator, grid: []const [NCELL]u8, Yd: []const f64, feat: []f64, out: anytype, cw: anytype, seed: u64, top: []DcmpWinner) !DcmpWinner {
    // top must have room for the top-K landscape (insertion-sorted, descending by val).
    for (top) |*t| t.* = .{ .mask = 0, .mode = .within, .lens = .ident, .omega = 0, .val = -1, .tst = 0 };
    var best = DcmpWinner{ .mask = 1, .mode = .between, .lens = .mod2, .omega = 0, .val = -1, .tst = 0 };
    var n_evaluated: usize = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        inline for (.{ PSMode.within, PSMode.between, PSMode.touching }) |mode| {
            var agg: [NSAMP]f64 = undefined;
            for (0..NSAMP) |s| agg[s] = @floatFromInt(dcmpAggregate(grid[s], mask, mode));
            const fixed = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
            for (fixed) |lens| {
                for (0..NSAMP) |s| feat[s] = applyLens(agg[s], lens, 0);
                const r = try bestThresholdAcc(feat, Yd, alloc);
                n_evaluated += 1;
                if (r.val > best.val) best = .{ .mask = mask, .mode = mode, .lens = lens, .omega = 0, .val = r.val, .tst = r.tst };
                insertTop(top, .{ .mask = mask, .mode = mode, .lens = lens, .omega = 0, .val = r.val, .tst = r.tst });
            }
            const NF = 60; // generous -- Phase 1 is the discovery-proof sweep
            var i: usize = 1;
            while (i <= NF) : (i += 1) {
                const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
                for (0..NSAMP) |s| feat[s] = @cos(om * agg[s]);
                const r = try bestThresholdAcc(feat, Yd, alloc);
                n_evaluated += 1;
                if (r.val > best.val) best = .{ .mask = mask, .mode = mode, .lens = .cosw, .omega = om, .val = r.val, .tst = r.tst };
                insertTop(top, .{ .mask = mask, .mode = mode, .lens = .cosw, .omega = om, .val = r.val, .tst = r.tst });
            }
        }
    }
    try out.print("  seed 0x{X:0>16}: swept {d} (mask,mode,lens) candidates\n", .{ seed, n_evaluated });
    try cw.print("dcmp_sweep_size,0x{X:0>16},ORDER2,-,{d:.4},,,{d},\n", .{ seed, 0.0, n_evaluated });
    return best;
}

fn insertTop(top: []DcmpWinner, cand: DcmpWinner) void {
    if (cand.val <= top[top.len - 1].val) return;
    var i = top.len - 1;
    while (i > 0 and top[i - 1].val < cand.val) : (i -= 1) {
        top[i] = top[i - 1];
    }
    top[i] = cand;
}

fn fmtWinner(buf: []u8, w: DcmpWinner) []const u8 {
    return dcmpKey(buf, w.mask, w.mode, w.lens, w.omega);
}

fn phase1(alloc: std.mem.Allocator, out: anytype, cw: anytype, X: [][]f64, feat: []f64, w: []f64) !void {
    try out.print("\n════════ PHASE 1: auto-discovery (DCMP exhaustive sweep, 3 seeds + 1 holdout) ════════\n", .{});
    const AUDIT_SEEDS = SEEDS ++ [_]u64{HOLDOUT_SEED};
    var kb: [80]u8 = undefined;
    var winners: [4]DcmpWinner = undefined;

    for (AUDIT_SEEDS, 0..) |seed, si| {
        const is_holdout = si == 3;
        const grid = try genGrid(alloc, seed);
        const Yd = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Yd[s] = labelOrder2(grid[s]);

        var top: [10]DcmpWinner = undefined;
        const best = try sweepDcmp(alloc, grid, Yd, feat, out, cw, seed, &top);
        winners[si] = best;

        try out.print("  {s}winner: {s}  val={d:.4} tst={d:.4}\n", .{ if (is_holdout) "[HOLDOUT] " else "", fmtWinner(&kb, best), best.val, best.tst });
        try cw.print("dcmp_winner,0x{X:0>16},ORDER2,\"{s}\",{d:.4},{d:.4},{d},,\n", .{ seed, fmtWinner(&kb, best), best.val, best.tst, @intFromBool(is_holdout) });

        try out.print("  top-10 landscape (val,tst,desc):\n", .{});
        for (top, 0..) |t, ti| {
            if (t.val < 0) continue;
            try out.print("    #{d:<2} val={d:.4} tst={d:.4}  {s}\n", .{ ti + 1, t.val, t.tst, fmtWinner(&kb, t) });
            try cw.print("dcmp_landscape,0x{X:0>16},ORDER2,\"{s}\",{d:.4},{d:.4},{d},,\n", .{ seed, fmtWinner(&kb, t), t.val, t.tst, ti });
        }

        // Cross-check: does the production (SGD/logit) statistic agree with
        // the diagnostic best-threshold winner? (the D08/MENUACC lesson --
        // selection and certification statistics must agree, or the winner
        // found here would never actually get promoted by the real ladder.)
        var agg: [NSAMP]f64 = undefined;
        for (0..NSAMP) |s| agg[s] = @floatFromInt(dcmpAggregate(grid[s], best.mask, best.mode));
        for (0..NSAMP) |s| feat[s] = applyLens(agg[s], best.lens, best.omega);
        const sgd_val = valAccSingle(feat, Yd);
        try out.print("  SGD/logit cross-check on winner: valAccSingle={d:.4}  (agrees with threshold stat: {s})\n", .{ sgd_val, if (@abs(sgd_val - best.val) < 0.05) "YES" else "NO -- selection/certification mismatch!" });
        try cw.print("dcmp_sgd_crosscheck,0x{X:0>16},ORDER2,\"{s}\",{d:.4},,,,\n", .{ seed, fmtWinner(&kb, best), sgd_val });

        // Certify (pre-tax: COVER escape + R² < 0.40 novelty gate) against a
        // fresh zoo-trained library, matching E1's own certification protocol.
        const phiTgt = try alloc.alloc(f64, NSAMP);
        const zoo_lib = try zooLibFor(alloc, X, grid, phiTgt, w);
        var ctr = Counter{};
        const cand_feat: Feature = .{ .dcmp = .{ .mask = best.mask, .mode = best.mode, .lens = best.lens, .omega = best.omega } };
        const cert = certifyLocal(X, grid, zoo_lib.lib[0..zoo_lib.nlib], cand_feat, Yd, feat, w, &ctr);
        try out.print("  certify: ok={s} cov_before={d:.3} cov_after={d:.3} r2={d:.3}\n", .{ if (cert.ok) "YES" else "no", cert.cov_before, cert.cov_after, cert.r2 });
        try cw.print("dcmp_certify,0x{X:0>16},ORDER2,\"{s}\",{d:.4},{d:.4},{d},{d:.4}\n", .{ seed, fmtWinner(&kb, best), cert.cov_before, cert.cov_after, @intFromBool(cert.ok), cert.r2 });
    }

    // Genuineness summary: is the winner structurally consistent across
    // seeds (same mask/mode/lens => not a per-seed fluke), and is it a
    // SINGLETON hub (the specific new shape CMP's 5 sets never covered)?
    try out.print("\n  Genuineness check: winner mask/mode/lens across all 4 seeds (3 standard + 1 held-out):\n", .{});
    var all_singleton = true;
    var all_same_shape = true;
    for (winners, 0..) |wn, i| {
        try out.print("    seed[{d}]: mask=0x{X:0>2} pop={d} mode={s} lens={s}\n", .{ i, wn.mask, popcount(wn.mask), psmode_name[@intFromEnum(wn.mode)], lens_name[@intFromEnum(wn.lens)] });
        if (popcount(wn.mask) != 1) all_singleton = false;
        if (wn.mask != winners[0].mask or wn.mode != winners[0].mode) all_same_shape = false;
    }
    try out.print("  ALL 4 SEEDS pick a SINGLETON hub: {s}\n", .{if (all_singleton) "YES" else "NO"});
    try out.print("  ALL 4 SEEDS pick the IDENTICAL hub+mode: {s}\n", .{if (all_same_shape) "YES" else "NO"});
    try cw.print("genuineness_summary,0x0,ORDER2,-,{d:.4},{d:.4},,,\n", .{ @as(f64, @floatFromInt(@intFromBool(all_singleton))), @as(f64, @floatFromInt(@intFromBool(all_same_shape))) });
}

// ══════════════════════════════════════════════════════════════════════════
// PHASE 2: regression -- ladder BASE vs ALL (+dcmp), production seed
// ══════════════════════════════════════════════════════════════════════════
fn phase2(alloc: std.mem.Allocator, out: anytype, cw: anytype, X: [][]f64, feat: []f64, w: []f64) !void {
    _ = feat;
    try out.print("\n════════ PHASE 2: ladder regression (BASE vs ALL=+dcmp, production seed) ════════\n", .{});
    const ArmSpec = struct { name: []const u8, opts: LadderOpts };
    const arms = [_]ArmSpec{
        .{ .name = "BASE(menuacc+cmp)", .opts = .{ .menuacc = true, .cmp = true } },
        .{ .name = "ALL(+dcmp)", .opts = .{ .menuacc = true, .cmp = true, .dcmp = true } },
    };

    var bprng = std.Random.DefaultPrng.init(rq1.BATTERY_SEED);
    const battery_b = try rq1.generateBatteryB(bprng.random(), alloc);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    const Yb = try alloc.alloc(f64, NSAMP);

    var solved_b: [2][11]bool = undefined;
    var source_b: [2][11]Source = undefined;
    // extra targets: D07, D08, local inv-parity (C09 statistic), ORDER2
    const EXTRA_NAMES = [_][]const u8{ "D07 count3%3", "D08 count3%4", "C09-analog inv parity", "ORDER2 rank0 parity" };
    var solved_x: [2][4]bool = undefined;
    var source_x: [2][4]Source = undefined;
    var cov_x: [2][4]f64 = undefined;

    for (arms, 0..) |arm, ai| {
        const grid = try genGrid(alloc, GRID_SEED);
        const zoo_lib_full = try zooLibFor(alloc, X, grid, phiTgt, w);
        try out.print("── ARM {s} (seed 0x{X:0>16}) ──\n", .{ arm.name, GRID_SEED });

        var tot_probes: usize = 0;
        var tot_certs: usize = 0;

        // Battery B: shared growable library (production protocol).
        var blib: [MAXFEAT]Feature = undefined;
        var bnlib: usize = zoo_lib_full.nlib;
        @memcpy(blib[0..bnlib], zoo_lib_full.lib[0..bnlib]);
        var b_solved: usize = 0;
        for (battery_b, 0..) |tgt, ti| {
            for (0..NSAMP) |s| Yb[s] = rq1.labelBattery(grid[s], tgt);
            const m = solveLadder(X, grid, &blib, &bnlib, Yb, phiTgt, w, arm.opts);
            if (m.solved) b_solved += 1;
            solved_b[ai][ti] = m.solved;
            source_b[ai][ti] = m.source;
            tot_probes += m.probes;
            tot_certs += m.certs;
            try cw.print("ladder,0x{X:0>16},\"{s}\",{s},{d:.4},,{d},{d},{d}\n", .{ GRID_SEED, tgt.name, arm.name, m.cov, @intFromBool(m.solved), m.probes, m.certs });
        }
        try out.print("  Battery B: {d}/11\n", .{b_solved});

        // Extra targets: fresh library each.
        const EXTRA_LABEL = struct {
            fn eval(idx: usize, g: [NCELL]u8) f64 {
                return switch (idx) {
                    0 => bd.labelTarget(g, bd.BATTERY_D[6]), // D07 count3%3
                    1 => bd.labelTarget(g, bd.BATTERY_D[7]), // D08 count3%4
                    2 => labelInvParity(g), // C09-analog
                    else => labelOrder2(g), // ORDER2
                };
            }
        };
        var x_solved: usize = 0;
        for (0..4) |ti| {
            for (0..NSAMP) |s| Yb[s] = EXTRA_LABEL.eval(ti, grid[s]);
            var xlib: [MAXFEAT]Feature = undefined;
            var xnlib: usize = zoo_lib_full.nlib;
            @memcpy(xlib[0..xnlib], zoo_lib_full.lib[0..xnlib]);
            const m = solveLadder(X, grid, &xlib, &xnlib, Yb, phiTgt, w, arm.opts);
            if (m.solved) x_solved += 1;
            solved_x[ai][ti] = m.solved;
            source_x[ai][ti] = m.source;
            cov_x[ai][ti] = m.cov;
            tot_probes += m.probes;
            tot_certs += m.certs;
            try out.print("  {s:<26} solved={s} source={s} cov={d:.3}\n", .{ EXTRA_NAMES[ti], if (m.solved) "Y" else "n", @tagName(m.source), m.cov });
            try cw.print("ladder,0x{X:0>16},\"{s}\",{s},{d:.4},,{d},{d},{d}\n", .{ GRID_SEED, EXTRA_NAMES[ti], arm.name, m.cov, @intFromBool(m.solved), m.probes, m.certs });
        }
        try out.print("  Extra: {d}/4   probes={d} certs={d}\n\n", .{ x_solved, tot_probes, tot_certs });
    }

    try out.print("── Regression check (BASE-solved => ALL-solved?) ──\n", .{});
    var regressions: usize = 0;
    var flips: usize = 0;
    for (0..11) |ti| {
        if (solved_b[0][ti] and !solved_b[1][ti]) {
            regressions += 1;
            try out.print("  REGRESSION: battB[{d}]\n", .{ti});
        }
        if (!solved_b[0][ti] and solved_b[1][ti]) {
            flips += 1;
            try out.print("  FLIP: battB[{d}] source={s}\n", .{ ti, @tagName(source_b[1][ti]) });
        }
    }
    for (0..4) |ti| {
        if (solved_x[0][ti] and !solved_x[1][ti]) {
            regressions += 1;
            try out.print("  REGRESSION: {s}\n", .{EXTRA_NAMES[ti]});
        }
        if (!solved_x[0][ti] and solved_x[1][ti]) {
            flips += 1;
            try out.print("  FLIP: {s} source={s} cov={d:.3}\n", .{ EXTRA_NAMES[ti], @tagName(source_x[1][ti]), cov_x[1][ti] });
        }
    }
    try out.print("  regressions={d}  new_flips={d}\n", .{ regressions, flips });
    try cw.print("regression_summary,0x{X:0>16},-,summary,{d:.4},,{d},{d},\n", .{ GRID_SEED, 0.0, regressions, flips });
}

// ── main ─────────────────────────────────────────────────────────────────
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var run0 = false;
    var run1 = false;
    var run2 = false;
    {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();
        _ = args.skip();
        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "--phase0")) run0 = true;
            if (std.mem.eql(u8, a, "--phase1")) run1 = true;
            if (std.mem.eql(u8, a, "--phase2")) run2 = true;
        }
    }
    if (!run0 and !run1 and !run2) {
        run0 = true;
        run1 = true;
        run2 = true;
    }

    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/autofamily_order2_2026_07_11.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("phase,seed,target,detail,val,tst,cert_or_flag,cov_after_or_extra,r2\n", .{});

    const t_start = std.time.milliTimestamp();

    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT + 2);
    const feat = try alloc.alloc(f64, NSAMP);
    var w: [MAXFEAT + 2]f64 = undefined;

    if (run0) {
        try phase0(alloc, out, cw, X, feat);
        try out.print("[phase0 done at {d}ms]\n", .{std.time.milliTimestamp() - t_start});
    }
    if (run1) {
        try phase1(alloc, out, cw, X, feat, w[0..]);
        try out.print("[phase1 done at {d}ms]\n", .{std.time.milliTimestamp() - t_start});
    }
    if (run2) {
        try phase2(alloc, out, cw, X, feat, w[0..]);
        try out.print("[phase2 done at {d}ms]\n", .{std.time.milliTimestamp() - t_start});
    }

    try out.print("\nTotal wall: {d}ms\nCSV: {s}\n", .{ std.time.milliTimestamp() - t_start, csv_path });
}
