//! T8 REACH GAP — diagnose D08/C09 (the targets the escalation ladder never
//! certifies an escape for) and test the cheapest family extension that
//! closes the gap.
//!
//! Context (docs/research/tier8_battery_d.md, docs/research/tier8_aimed_proposer.md):
//!   - D08 (count3 % 4 == 0) is TOO_HARD: neither tax arm ever certifies an
//!     escape — a reachability gap, distinct from tax-blocking.
//!   - C09 (inversion-count parity) resists both the aimed proposer and the
//!     brute mask×lens control — flagged as a family-level structural miss.
//!
//! This harness answers, with measurement:
//!   PHASE A (diagnosis): for D08, C09 (+ D07 as a solvable control), sweep
//!     EVERY family the batteries-C/D ladder owns (ui.solveOneTarget stages:
//!     monomial forge / pair / walsh / menu{spectral,walsh,clifford} / world)
//!     exhaustively at generous budget, PLUS the two rq1-escalation families
//!     that only battery B can reach (count-program mod-synth, pipeline
//!     inner1 statistics), PLUS the *information-basis Bayes ceiling* of each
//!     family (per-bin majority vote on the family's input statistic — an
//!     upper bound on EVERY member of every family defined over that
//!     statistic, so "ceiling ~ chance" is a family-level impossibility
//!     proof, not a budget statement).
//!   PHASE B (extension): a local, faithful, PRE-TAX replica of the
//!     solveOneTarget ladder (this experiment is about ladder REACH;
//!     equivalence_tax.zig is deliberately not imported — it is mid-edit by
//!     another agent this round, and the battery-D data shows the tax never
//!     fires on D08 anyway: blocked=0 in both arms), with two minimal
//!     additions, toggleable independently:
//!       MENUACC — same spectral family cos(w*count3), same 200-freq grid,
//!                 but member selection by held-out ACCURACY instead of
//!                 spectral-power argmax (selection fix, zero new families).
//!       CMP     — comparison-pair aggregate family: A_P(g) = #{(i,j) in P :
//!                 g[i] > g[j]} over 5 canonical pair-sets, with a standard
//!                 lens set {identity, mod2..mod6, cos(w*A) 200-freq scan}
//!                 (the minimal order-statistic family named by the C09
//!                 diagnosis).
//!     Arms: L0 (replica baseline), L1 (+CMP), L2 (+MENUACC), L3 (both).
//!     L0/L3 run full battery B + C + D at the 3 standard seeds (B = shared
//!     growable library, exactly like production; C/D = fresh library per
//!     target, exactly like the battery-C/D harnesses). L1/L2 run D08+C09 at
//!     the production seed for attribution.
//!
//! Deliberately NOT imported: equivalence_tax.zig, unified_invention.zig,
//! invention_engine.zig (the latter two import the tax). The ladder replica
//! below is transcribed from unified_invention.zig (read-only) with the
//! eqtax.gatePromoteEx call removed — pre-tax certification is exactly
//! escape (cov_after>=0.90 from <0.90) AND R^2<0.40, the same thresholds.
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe tier8_reach_gap.zig -O ReleaseFast
//! Run:
//!   ./tier8_reach_gap            (full: phase A + phase B)
//!   ./tier8_reach_gap --diag     (phase A only, fast smoke)
//! Single-threaded.

const std = @import("std");
const rq1 = @import("open_invention_rq1.zig"); // no eqtax dependency (std+hr+oml)
const e2 = @import("open_invention_e2.zig"); // no eqtax dependency (std+oml)
const bd = @import("tier8_battery_d.zig"); // std only
const oml = @import("operator_menu_lib.zig"); // std only

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

// ── Constants (identical to unified_invention.zig) ─────────────────────────
const NCELL: usize = 8;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const THETA: f64 = 0.40;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const DOM: usize = 1 << NCELL;
const MAXFEAT: usize = 40;
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

// ── CMP family: comparison-pair aggregates ─────────────────────────────────
// A_P(g) = #{(i,j) in P : g[i] > g[j]} over canonical (untuned) pair sets.
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

const CmpLens = enum(u8) { ident, mod2, mod3, mod4, mod5, mod6, cosw };
const cmplens_name = [_][]const u8{ "ident", "mod2", "mod3", "mod4", "mod5", "mod6", "cosw" };

fn cmpEval(g: [NCELL]u8, set: CmpSet, lens: CmpLens, omega: f64) f64 {
    const a = cmpAggregate(g, set);
    return switch (lens) {
        .ident => @floatFromInt(a),
        .mod2 => @floatFromInt(a % 2),
        .mod3 => @floatFromInt(a % 3),
        .mod4 => @floatFromInt(a % 4),
        .mod5 => @floatFromInt(a % 5),
        .mod6 => @floatFromInt(a % 6),
        .cosw => @cos(omega * @as(f64, @floatFromInt(a))),
    };
}

// ── Feature library (unified_invention union + cmp) ────────────────────────
const Feature = union(enum) {
    monomial: u8,
    pair_relation: struct { i: usize, j: usize },
    spectral_count: f64,
    walsh: u8,
    clifford_g2: void,
    world_sum_mod: usize,
    world_sign_mod: usize,
    cmp: struct { set: CmpSet, lens: CmpLens, omega: f64 },
};

const Source = enum { base, forge, pair, walsh, menu, menuacc, cmp, world, none };

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
            return std.fmt.bufPrint(buf, "cmp({s},{s})", .{ cmpset_name[@intFromEnum(c.set)], cmplens_name[@intFromEnum(c.lens)] }) catch "cmp";
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
    probes: usize = 0, // single-feature evaluations (valAccSingle or forge probe-fit)
    certs: usize = 0, // full certify calls (2 coverage fits + 1 recon fit each)
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

// ── Ladder stages (transcribed from unified_invention.zig, pre-tax) ────────
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
        // single-feature probe (standardized col 0, 70 epochs lr .06) — as production
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
    // oriented
    for (0..NSAMP) |s| feat[s] = oriented(grid[s]);
    ctr.probes += 1;
    best = @max(best, valAccSingle(feat, Y));
    // countGE
    for (0..NSAMP) |s| feat[s] = countGE(grid[s]);
    ctr.probes += 1;
    best = @max(best, valAccSingle(feat, Y));
    // clifford
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

// spectral discovery by POWER argmax (the production menu selection)
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

// NEW STAGE (selection fix): spectral member chosen by held-out ACCURACY over
// the same 200-freq grid, not by spectral power.
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

// NEW STAGE (new family): comparison-pair aggregates + standard lens set.
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
        // integer aggregate once per set
        var agg: [NSAMP]f64 = undefined;
        for (0..NSAMP) |s| agg[s] = @floatFromInt(cmpAggregate(grid[s], set));
        // fixed lenses
        const fixed = [_]CmpLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
        for (fixed) |lens| {
            for (0..NSAMP) |s| {
                const a: usize = @intFromFloat(agg[s]);
                feat_scratch[s] = switch (lens) {
                    .ident => agg[s],
                    .mod2 => @floatFromInt(a % 2),
                    .mod3 => @floatFromInt(a % 3),
                    .mod4 => @floatFromInt(a % 4),
                    .mod5 => @floatFromInt(a % 5),
                    .mod6 => @floatFromInt(a % 6),
                    .cosw => unreachable,
                };
            }
            ctr.probes += 1;
            const v = valAccSingle(feat_scratch, Y);
            if (v > best_val) {
                best_val = v;
                best = .{ .cmp = .{ .set = set, .lens = lens, .omega = 0 } };
            }
        }
        // cos(w*A) scan, 200 freqs (standard grid)
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

// ── The ladder (solveOneTarget replica; menuacc/cmp toggleable) ────────────
const LadderOpts = struct { menuacc: bool = false, cmp: bool = false };

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
        if (cov0 >= COVER) {
            return .{ .solved = true, .cov = cov0, .source = .forge, .probes = ctr.probes, .certs = ctr.certs };
        }
        if (!tryMonomialForge(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) break;
    }
    cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
    if (cov0 >= COVER) {
        return .{ .solved = true, .cov = cov0, .source = .forge, .probes = ctr.probes, .certs = ctr.certs };
    }

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

    if (tryWorldPool(X, grid, lib, nlib, Y, phiTgt, w, &ctr)) {
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) source = .world;
    }

    return .{ .solved = cov0 >= COVER, .cov = cov0, .source = if (cov0 >= COVER) source else .none, .probes = ctr.probes, .certs = ctr.certs };
}

// ── Targets ─────────────────────────────────────────────────────────────────
// Battery C (copied spec from open_invention_tier8_battery_c.zig, which
// cannot be imported without pulling in the tax; labels via e2.label /
// local inversion parity — bit-identical definitions).
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

// ── Phase A: family diagnosis ───────────────────────────────────────────────
fn fillY(comptime labelFn: anytype, grid: []const [NCELL]u8, tgt: anytype, Y: []f64) void {
    for (0..NSAMP) |s| Y[s] = labelFn(grid[s], tgt);
}

/// Best single-feature THRESHOLD accuracy (either polarity), exact optimum
/// on the val split, then evaluated on the test split — the generous-budget
/// "best any member of this parametric family can do" score, immune to the
/// logistic probe's raw-scale quirks.
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
    // predict 1 iff f >= thr  (dir=1)  or  f < thr (dir=0); sweep all cuts
    var best_acc: f64 = 0;
    var best_thr: f64 = -std.math.inf(f64);
    var best_dir: bool = true; // true: predict1 when f>=thr
    var pos_below: usize = 0; // count of y=1 with f < current cut
    var i: usize = 0;
    while (i <= n) : (i += 1) {
        // cut between items[i-1] and items[i]
        const thr: f64 = if (i == 0) -std.math.inf(f64) else if (i == n) std.math.inf(f64) else (items[i - 1].f + items[i].f) / 2.0;
        const skip = (i > 0 and i < n and items[i - 1].f == items[i].f);
        if (!skip) {
            // dir=1: predict 1 for f>=thr → correct = (pos_total - pos_below) + (neg below) = pos_total - pos_below + (i - pos_below)
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

/// Information-basis Bayes ceiling: per-bin majority vote trained on the
/// train split, evaluated on the test split. Upper-bounds EVERY function of
/// this statistic (hence every member of every family over it).
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
    lib: []const Feature, // fresh trained zoo library (for certify attempts)
    feat: []f64,
    w: []f64,
    alloc: std.mem.Allocator,
    out: std.fs.File.Writer,
    csv: std.fs.File.Writer,
    target_name: []const u8,
};

fn diagRow(
    ctx: *DiagCtx,
    Y: []const f64,
    family: []const u8,
    members: usize,
    best_desc: []const u8,
    best_val: f64,
    best_tst: f64,
    ladder_pick_val: f64, // -1 if n/a
    cand: ?Feature, // best member, for a pre-tax certify attempt
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
    try ctx.out.print("  {s:<26} members={d:<5} best={s:<24} val={d:.3} tst={d:.3} ladder_pick={d:.3} cert={s} (cov_after={d:.3} r2={d:.2})\n", .{
        family,   members,  best_desc, best_val,
        best_tst, ladder_pick_val, if (cert_ok) "YES" else "no",
        cov_after, r2,
    });
    try ctx.csv.print("family_diag,0x{X:0>16},{s},{s},{d},\"{s}\",{d:.4},{d:.4},{d:.4},{d},{d:.4},{d:.4}\n", .{
        GRID_SEED, ctx.target_name, family, members, best_desc, best_val, best_tst, ladder_pick_val, @intFromBool(cert_ok), cov_after, r2,
    });
}

fn diagnoseTarget(ctx: *DiagCtx, Y: []const f64) !void {
    const alloc = ctx.alloc;
    const grid = ctx.grid;
    const feat = ctx.feat;
    var kb: [64]u8 = undefined;

    // base rate
    var pos: usize = 0;
    for (0..NSAMP) |s| {
        if (Y[s] > 0.5) pos += 1;
    }
    try ctx.out.print("  base_rate={d:.3}\n", .{@as(f64, @floatFromInt(pos)) / @as(f64, NSAMP)});

    // 1+2. monomial family, ladder budget (deg<=4) and generous (deg<=8)
    inline for (.{ @as(usize, 4), @as(usize, 8) }) |degcap| {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var best_mask: u8 = 0;
        var nmem: usize = 0;
        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const mask: u8 = @intCast(mm);
            if (popcount(mask) > degcap) continue;
            nmem += 1;
            for (0..NSAMP) |s| feat[s] = phi(grid[s], mask);
            const r = try bestThresholdAcc(feat, Y, alloc);
            if (r.val > best_val) {
                best_val = r.val;
                best_tst = r.tst;
                best_mask = mask;
            }
        }
        const fam = if (degcap == 4) "monomial(deg<=4)" else "monomial(deg<=8)";
        const desc = std.fmt.bufPrint(&kb, "phi(0x{X:0>2})", .{best_mask}) catch "phi";
        try diagRow(ctx, Y, fam, nmem, desc, best_val, best_tst, -1, .{ .monomial = best_mask });
    }

    // 3. pair products
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
        try diagRow(ctx, Y, "pair_relation", 28, desc, best_val, best_tst, -1, .{ .pair_relation = .{ .i = bi, .j = bj } });
    }

    // 4. walsh chi_S over sign pattern — exhaustive 256
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
        try diagRow(ctx, Y, "walsh(sign bits)", 255, desc, best_val, best_tst, -1, .{ .walsh = bS });
    }

    // 5+6. spectral cos(w*count3): the ladder's power-argmax pick vs
    //      exhaustive accuracy over an 800-freq generous grid.
    {
        const w_pick = discoverSpectralPower(grid, Y, feat);
        const pick_r = try bestThresholdAcc(feat, Y, alloc);
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
        try ctx.out.print("    [spectral detail: power-argmax w={d:.4} acc={d:.3}; acc-argmax w={d:.4} acc={d:.3} (pi/2={d:.4})]\n", .{ w_pick, pick_r.val, best_w, best_val, std.math.pi / 2.0 });
        try diagRow(ctx, Y, "spectral cos(w*count3)", 800, desc, best_val, best_tst, pick_r.val, .{ .spectral_count = best_w });
    }

    // 7. clifford theta scan (generous: 64 thetas; ladder has only theta=0.40)
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var best_th: f64 = THETA;
        var ladder_val: f64 = -1;
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
        for (0..NSAMP) |s| feat[s] = cliffordG2(grid[s]);
        const lr = try bestThresholdAcc(feat, Y, alloc);
        ladder_val = lr.val;
        const desc = std.fmt.bufPrint(&kb, "sin({d:.3}(v1-v0))", .{best_th}) catch "clif";
        try diagRow(ctx, Y, "clifford sin(th*(v1-v0))", 64, desc, best_val, best_tst, ladder_val, .{ .clifford_g2 = {} });
    }

    // 8+9. world mod families, generous k=2..20 (ladder: 6 primes)
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
        try diagRow(ctx, Y, "world_sum_mod(k=2..20)", 19, desc, best_val, best_tst, -1, .{ .world_sum_mod = bk });
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
        try diagRow(ctx, Y, "world_sign_mod(k=2..20)", 19, desc, best_val, best_tst, -1, .{ .world_sign_mod = bk });
    }

    // 10. mod-synth core slice (count programs — the rq1 escalation family,
    //     battery-B-only in production): count, sin(count), count%k k=2..12
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bdesc: []const u8 = "count";
        var nmem: usize = 0;
        for (0..NSAMP) |s| feat[s] = countGE(grid[s]);
        var r = try bestThresholdAcc(feat, Y, alloc);
        nmem += 1;
        if (r.val > best_val) {
            best_val = r.val;
            best_tst = r.tst;
            bdesc = "count";
        }
        for (0..NSAMP) |s| feat[s] = @sin(countGE(grid[s]));
        r = try bestThresholdAcc(feat, Y, alloc);
        nmem += 1;
        if (r.val > best_val) {
            best_val = r.val;
            best_tst = r.tst;
            bdesc = "sin(count)";
        }
        var k: usize = 2;
        var descbuf: [24]u8 = undefined;
        while (k <= 12) : (k += 1) {
            for (0..NSAMP) |s| feat[s] = @floatFromInt(@as(usize, @intFromFloat(countGE(grid[s]))) % k);
            r = try bestThresholdAcc(feat, Y, alloc);
            nmem += 1;
            if (r.val > best_val) {
                best_val = r.val;
                best_tst = r.tst;
                bdesc = std.fmt.bufPrint(&descbuf, "mod(count,{d})", .{k}) catch "mod";
            }
        }
        // NOTE: threshold on a k>2-valued remainder column cannot always cut
        // the ==0 class alone; the count-basis ceiling row below is the
        // rigorous family bound.
        try diagRow(ctx, Y, "modsynth slice (count)", nmem, bdesc, best_val, best_tst, -1, null);
    }

    // 11. NEW cmp family (for reference: what the proposed stage would see)
    {
        var best_val: f64 = -1;
        var best_tst: f64 = 0;
        var bdesc_buf: [48]u8 = undefined;
        var bdesc: []const u8 = "?";
        var bfeat: Feature = .{ .cmp = .{ .set = .all, .lens = .mod2, .omega = 0 } };
        var nmem: usize = 0;
        for (0..N_CMPSET) |si| {
            const set: CmpSet = @enumFromInt(si);
            const fixed = [_]CmpLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
            for (fixed) |lens| {
                for (0..NSAMP) |s| feat[s] = cmpEval(grid[s], set, lens, 0);
                nmem += 1;
                const r = try bestThresholdAcc(feat, Y, alloc);
                if (r.val > best_val) {
                    best_val = r.val;
                    best_tst = r.tst;
                    bfeat = .{ .cmp = .{ .set = set, .lens = lens, .omega = 0 } };
                    bdesc = std.fmt.bufPrint(&bdesc_buf, "cmp({s},{s})", .{ cmpset_name[si], cmplens_name[@intFromEnum(lens)] }) catch "cmp";
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
        _ = featureKey(&kb, bfeat);
        try diagRow(ctx, Y, "NEW cmp aggregates", nmem, bdesc, best_val, best_tst, -1, bfeat);
    }

    // 12. information-basis Bayes ceilings (family-level impossibility bounds)
    {
        const keys = try alloc.alloc(usize, NSAMP);
        defer alloc.free(keys);
        const Basis = struct { name: []const u8, nbins: usize, covers: []const u8 };
        const bases = [_]Basis{
            .{ .name = "basis:count3", .nbins = 9, .covers = "spectral+modsynth(count)" },
            .{ .name = "basis:gridSum", .nbins = 41, .covers = "world_sum_mod" },
            .{ .name = "basis:signPattern", .nbins = 256, .covers = "walsh+world_sign_mod" },
            .{ .name = "basis:v1-v0", .nbins = 11, .covers = "clifford" },
            .{ .name = "basis:inversion", .nbins = 29, .covers = "pipeline(inv)/cmp(all)" },
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
            try ctx.csv.print("basis_ceiling,0x{X:0>16},{s},{s},{d},\"{s}\",{d:.4},,,,,\n", .{ GRID_SEED, ctx.target_name, b.name, b.nbins, b.covers, ceil });
        }
    }
}

// ── Phase B machinery ───────────────────────────────────────────────────────
const BatteryTag = enum { B, C, D };

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
    {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();
        _ = args.skip();
        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "--diag")) diag_only = true;
        }
    }

    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/reach_gap_2026_07_10.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("phase,seed,target,family_or_arm,members_or_idx,detail,val_or_cov,tst,ladder_pick,cert_or_solved,cov_after_or_probes,r2_or_certs\n", .{});

    const t_start = std.time.milliTimestamp();

    // ── shared setup at production seed ──
    var prng = std.Random.DefaultPrng.init(GRID_SEED);
    const rand = prng.random();
    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| {
        for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, 5);
    }
    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT + 2);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    const feat = try alloc.alloc(f64, NSAMP);
    var w: [MAXFEAT + 2]f64 = undefined;

    // zoo training (identical recipe to ie.prepareBlindBatterySeed)
    const Yzoo = try alloc.alloc([]f64, 4);
    for (0..4) |t| {
        Yzoo[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Yzoo[t][s] = if (phi(grid[s], ZOO_MASKS[t]) > 0) 1.0 else 0.0;
    }
    const trained = try rq1.trainZooA(X, grid, Yzoo, phiTgt, w[0..], SilentOut{});
    const zoo_lib = trained.lib[0..trained.nlib];
    try out.print("zoo library trained: {d} monomials (seed 0x{X:0>16})\n\n", .{ trained.nlib, GRID_SEED });

    var base_lib: [MAXFEAT]Feature = undefined;
    var base_nlib: usize = 0;
    seedLibFromZoo(zoo_lib, &base_lib, &base_nlib);

    // ── PHASE A: family diagnosis on D08, C09, D07(control) ──
    try out.print("════════ PHASE A: per-family exhaustive diagnosis (seed 0x{X:0>16}) ════════\n", .{GRID_SEED});
    const Yd = try alloc.alloc(f64, NSAMP);

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
    };

    // D08
    try out.print("\n── D08 count3%4 ──\n", .{});
    dctx.target_name = "D08 count3%4";
    fillY(bd.labelTarget, grid, bd.BATTERY_D[7], Yd);
    try diagnoseTarget(&dctx, Yd);

    // C09
    try out.print("\n── C09 inversion parity ──\n", .{});
    dctx.target_name = "C09 inv parity";
    fillY(labelC, grid, BATTERY_C[8], Yd);
    try diagnoseTarget(&dctx, Yd);

    // D07 control (known menu-solvable)
    try out.print("\n── D07 count3%3 (solvable control) ──\n", .{});
    dctx.target_name = "D07 count3%3";
    fillY(bd.labelTarget, grid, bd.BATTERY_D[6], Yd);
    try diagnoseTarget(&dctx, Yd);

    try out.print("\nPhase A done at {d}ms\n", .{std.time.milliTimestamp() - t_start});

    if (diag_only) {
        try out.print("(--diag: stopping before Phase B)\nCSV: {s}\n", .{csv_path});
        return;
    }

    // ── PHASE B: ladder arms ──
    try out.print("\n════════ PHASE B: pre-tax ladder arms ════════\n", .{});
    try out.print("Arms: L0=replica  L1=+CMP  L2=+MENUACC  L3=both\n", .{});
    try out.print("L0/L3: 3 seeds x (B shared-lib, C fresh-lib, D fresh-lib). L1/L2: seed0, D08+C09 only.\n\n", .{});

    const ArmSpec = struct { name: []const u8, opts: LadderOpts, full: bool };
    const arms = [_]ArmSpec{
        .{ .name = "L0", .opts = .{}, .full = true },
        .{ .name = "L1_cmp", .opts = .{ .cmp = true }, .full = false },
        .{ .name = "L2_menuacc", .opts = .{ .menuacc = true }, .full = false },
        .{ .name = "L3_both", .opts = .{ .menuacc = true, .cmp = true }, .full = true },
    };

    // Battery B spec (production battery seed)
    var bprng = std.Random.DefaultPrng.init(rq1.BATTERY_SEED);
    const battery_b = try rq1.generateBatteryB(bprng.random(), alloc);

    const Yb = try alloc.alloc(f64, NSAMP);

    for (arms) |arm| {
        if (!arm.full) {
            // attribution mini-run: production seed, D08 + C09, fresh lib each
            try out.print("── ARM {s} (attribution: seed0, D08+C09) ──\n", .{arm.name});
            const Mini = struct { name: []const u8, is_d08: bool };
            const minis = [_]Mini{ .{ .name = "D08 count3%4", .is_d08 = true }, .{ .name = "C09 inv parity", .is_d08 = false } };
            for (minis) |mt| {
                if (mt.is_d08) {
                    fillY(bd.labelTarget, grid, bd.BATTERY_D[7], Yb);
                } else {
                    fillY(labelC, grid, BATTERY_C[8], Yb);
                }
                var lib: [MAXFEAT]Feature = undefined;
                var nlib: usize = 0;
                seedLibFromZoo(zoo_lib, &lib, &nlib);
                const m = solveLadder(X, grid, &lib, &nlib, Yb, phiTgt, w[0..], arm.opts);
                var kbuf: [64]u8 = undefined;
                const srcd: []const u8 = if (m.solved and nlib > 0 and m.source != .base) featureKey(&kbuf, lib[nlib - 1]) else "-";
                try out.print("  {s:<16} solved={s} cov={d:.3} src={s} last_feat={s} probes={d} certs={d} evals={d}\n", .{
                    mt.name,
                    if (m.solved) "YES" else "no ",
                    m.cov,
                    @tagName(m.source),
                    srcd,
                    m.probes,
                    m.certs,
                    m.probes + 3 * m.certs,
                });
                try cw.print("ladder,0x{X:0>16},{s},{s},0,\"{s}\",{d:.4},,,{d},{d},{d}\n", .{
                    GRID_SEED, mt.name, arm.name, @tagName(m.source), m.cov, @intFromBool(m.solved), m.probes, m.certs,
                });
            }
            try out.print("\n", .{});
            continue;
        }

        var tot = ArmTotals{};
        for (SEEDS) |seed| {
            // fresh grid + zoo per seed
            var sprng = std.Random.DefaultPrng.init(seed);
            const srand = sprng.random();
            const sgrid = try alloc.alloc([NCELL]u8, NSAMP);
            for (0..NSAMP) |s| {
                for (0..NCELL) |i| sgrid[s][i] = srand.intRangeAtMost(u8, 0, 5);
            }
            const sYzoo = try alloc.alloc([]f64, 4);
            for (0..4) |t| {
                sYzoo[t] = try alloc.alloc(f64, NSAMP);
                for (0..NSAMP) |s| sYzoo[t][s] = if (phi(sgrid[s], ZOO_MASKS[t]) > 0) 1.0 else 0.0;
            }
            const strained = try rq1.trainZooA(X, sgrid, sYzoo, phiTgt, w[0..], SilentOut{});
            const szoo = strained.lib[0..strained.nlib];

            try out.print("── ARM {s} seed 0x{X:0>16} ──\n", .{ arm.name, seed });

            // Battery B: shared growable library (production protocol)
            var blib: [MAXFEAT]Feature = undefined;
            var bnlib: usize = 0;
            seedLibFromZoo(szoo, &blib, &bnlib);
            var b_solved: usize = 0;
            for (battery_b, 0..) |tgt, ti| {
                for (0..NSAMP) |s| Yb[s] = rq1.labelBattery(sgrid[s], tgt);
                const m = solveLadder(X, sgrid, &blib, &bnlib, Yb, phiTgt, w[0..], arm.opts);
                if (m.solved) b_solved += 1;
                tot.probes += m.probes;
                tot.certs += m.certs;
                try cw.print("ladder,0x{X:0>16},\"{s}\",{s},{d},\"{s}\",{d:.4},,,{d},{d},{d}\n", .{
                    seed, tgt.name, arm.name, ti, @tagName(m.source), m.cov, @intFromBool(m.solved), m.probes, m.certs,
                });
            }
            tot.b_solved += b_solved;

            // Battery C: fresh library per target
            var c_solved: usize = 0;
            for (BATTERY_C, 0..) |tgt, ti| {
                for (0..NSAMP) |s| Yb[s] = labelC(sgrid[s], tgt);
                var clib: [MAXFEAT]Feature = undefined;
                var cnlib: usize = 0;
                seedLibFromZoo(szoo, &clib, &cnlib);
                const m = solveLadder(X, sgrid, &clib, &cnlib, Yb, phiTgt, w[0..], arm.opts);
                if (m.solved) c_solved += 1;
                tot.probes += m.probes;
                tot.certs += m.certs;
                try cw.print("ladder,0x{X:0>16},\"{s}\",{s},{d},\"{s}\",{d:.4},,,{d},{d},{d}\n", .{
                    seed, tgt.name, arm.name, ti, @tagName(m.source), m.cov, @intFromBool(m.solved), m.probes, m.certs,
                });
            }
            tot.c_solved += c_solved;

            // Battery D: fresh library per target
            var d_solved: usize = 0;
            for (bd.BATTERY_D, 0..) |tgt, ti| {
                for (0..NSAMP) |s| Yb[s] = bd.labelTarget(sgrid[s], tgt);
                var dlib: [MAXFEAT]Feature = undefined;
                var dnlib: usize = 0;
                seedLibFromZoo(szoo, &dlib, &dnlib);
                const m = solveLadder(X, sgrid, &dlib, &dnlib, Yb, phiTgt, w[0..], arm.opts);
                if (m.solved) d_solved += 1;
                tot.probes += m.probes;
                tot.certs += m.certs;
                try cw.print("ladder,0x{X:0>16},\"{s}\",{s},{d},\"{s}\",{d:.4},,,{d},{d},{d}\n", .{
                    seed, tgt.name, arm.name, ti, @tagName(m.source), m.cov, @intFromBool(m.solved), m.probes, m.certs,
                });
            }
            tot.d_solved += d_solved;

            try out.print("  B {d}/11  C {d}/11  D {d}/11   ({d}ms elapsed)\n", .{ b_solved, c_solved, d_solved, std.time.milliTimestamp() - t_start });
        }
        try out.print("  ARM {s} TOTALS (3 seeds): B {d}/33  C {d}/33  D {d}/33  probes={d} certs={d}\n\n", .{
            arm.name, tot.b_solved, tot.c_solved, tot.d_solved, tot.probes, tot.certs,
        });
    }

    try out.print("Total wall: {d}ms\nCSV: {s}\n", .{ std.time.milliTimestamp() - t_start, csv_path });
}
