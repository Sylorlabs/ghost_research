//! RESEARCH Q8 — E12 hard mutators: noisy labels, Walsh deg 3–5, 2-feature composition.
//!
//! Extends E12 POET self-play with harder target mutators so the curriculum band [0.10, 0.90]
//! stays populated instead of collapsing to trivial mastery.
//!
//! Mutators:
//!   • 10% label noise on training labels (held-out scored on clean ground truth)
//!   • Walsh-high targets: χ_S with popcount(S) ∈ {3,4,5}
//!   • Composed AND targets: atom_a ∧ atom_b (requires 2-feature readout)
//!
//! Pass bar:
//!   • curriculum size ≥10 for ≥30 rounds
//!   • solve rate ∈ [40%, 80%]
//!
//! Run: zig build open-invention-rq8 --release=fast

const std = @import("std");
const unified = @import("unified_invention.zig");

const N_ROUNDS: usize = 50;
pub const PROPOSALS_PER_ROUND: usize = 3;
pub const MAX_CURRICULUM: usize = 48;
pub const CURR_LO: f64 = 0.10;
pub const CURR_HI: f64 = 0.90;
const LABEL_NOISE: f64 = 0.10;
const WALSH_DEG_LO: usize = 3;
const WALSH_DEG_HI: usize = 5;
const CURR_PASS_SIZE: usize = 10;
const CURR_PASS_ROUNDS: usize = 30;
const SOLVE_LO: f64 = 0.40;
const SOLVE_HI: f64 = 0.80;
const SEED: u64 = 0xA08C0FFEE12A11CE;

pub const NCELL: usize = 8;
pub const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
pub const NSAMP: usize = 4000;
const NTR: usize = 2000;
const NVA: usize = 3000;
const DOM: usize = 1 << NCELL;
const MAXFEAT: usize = 32;
const MAXDEG: usize = 4;
const COVER: f64 = unified.COVER_THRESHOLD;
const R2_MAX: f64 = 0.40;

const WORLD_PRIMES = [_]usize{ 2, 3, 5, 7, 11, 13 };

pub const ExperimentResult = struct {
    rounds: usize,
    proposals: usize,
    solved_count: usize,
    solve_rate: f64,
    curriculum_size: usize,
    curriculum_peak: usize,
    curriculum_ge10_rounds: usize,
    sustained_growth: bool,
    curriculum_pass: bool,
    solve_rate_pass: bool,
    curriculum_trace: [5]usize,
};

pub const TargetKind = enum {
    walsh_high,
    composed_and,
};

const AtomKind = enum {
    walsh,
    parity,
    oriented,
    sum_mod,
    sign_mod,
    monomial,
};

pub const TargetSpec = struct {
    kind: TargetKind,
    walsh_mask: u8 = 0,
    atom_a: AtomKind = .walsh,
    atom_b: AtomKind = .parity,
    mask_a: u8 = 0,
    mask_b: u8 = 0,
    modulus_a: usize = 3,
    modulus_b: usize = 5,
    noise_rate: f64 = LABEL_NOISE,
};

pub const CurriculumEntry = struct {
    spec: TargetSpec,
    coverage: f64,
    depth: usize,
    fingerprint: u64,
};

const FeatureTag = enum {
    monomial,
    spectral_count,
    walsh,
    clifford_g2,
    world_sum_mod,
    world_sign_mod,
};

const Feature = union(FeatureTag) {
    monomial: u8,
    spectral_count: f64,
    walsh: u8,
    clifford_g2: void,
    world_sum_mod: usize,
    world_sign_mod: usize,
};

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
}

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
    for (g) |v| {
        if (v >= THRESH) c += 1;
    }
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
    return @sin(0.40 * (v1 - v0));
}

fn evalAtom(g: [NCELL]u8, atom: AtomKind, mask: u8, modulus: usize) bool {
    return switch (atom) {
        .walsh => chi(mask, signPattern(g)) > 0,
        .parity => blk: {
            var c: usize = 0;
            for (g) |v| {
                if (v >= THRESH) c += 1;
            }
            break :blk c & 1 == 1;
        },
        .oriented => g[1] > g[0],
        .sum_mod => gridSum(g) % modulus == 0,
        .sign_mod => @as(usize, signPattern(g)) % modulus == 0,
        .monomial => phi(g, mask) > 0,
    };
}

fn cleanLabel(g: [NCELL]u8, spec: TargetSpec) f64 {
    return switch (spec.kind) {
        .walsh_high => if (chi(spec.walsh_mask, signPattern(g)) > 0) 1.0 else 0.0,
        .composed_and => blk: {
            const a = evalAtom(g, spec.atom_a, spec.mask_a, spec.modulus_a);
            const b = evalAtom(g, spec.atom_b, spec.mask_b, spec.modulus_b);
            break :blk if (a and b) 1.0 else 0.0;
        },
    };
}

fn evalFeature(f: Feature, g: [NCELL]u8) f64 {
    return switch (f) {
        .monomial => |m| phi(g, m),
        .spectral_count => |w| @cos(w * countGE(g)),
        .walsh => |S| chi(S, signPattern(g)),
        .clifford_g2 => cliffordG2(g),
        .world_sum_mod => |p| if (gridSum(g) % p == 0) @as(f64, 1) else 0,
        .world_sign_mod => |p| if (@as(usize, signPattern(g)) % p == 0) @as(f64, 1) else 0,
    };
}

fn featuresEqual(a: Feature, b: Feature) bool {
    const at = std.meta.activeTag(a);
    const bt = std.meta.activeTag(b);
    if (at != bt) return false;
    return switch (a) {
        .monomial => |m| b.monomial == m,
        .spectral_count => |wa| @abs(wa - b.spectral_count) < 1e-6,
        .walsh => |S| b.walsh == S,
        .clifford_g2 => true,
        .world_sum_mod => |p| b.world_sum_mod == p,
        .world_sign_mod => |p| b.world_sign_mod == p,
    };
}

fn hasFeature(lib: []const Feature, f: Feature) bool {
    for (lib) |x| if (featuresEqual(x, f)) return true;
    return false;
}

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

fn accLogitClean(X: []const []f64, Y_clean: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y_clean[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

fn coverageNoisyTrain(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []const Feature,
    Y_train: []const f64,
    Y_clean: []const f64,
    w: []f64,
) f64 {
    buildFeat(X, grid, lib);
    fitLogit(X, Y_train, lib.len, 80, 0.05, w);
    return accLogitClean(X, Y_clean, w, lib.len, NVA, NSAMP);
}

fn applyLabelNoise(rand: std.Random, Y_clean: []const f64, Y_train: []f64, rate: f64) void {
    @memcpy(Y_train[0..NSAMP], Y_clean[0..NSAMP]);
    for (0..NTR) |s| {
        if (rand.float(f64) < rate) Y_train[s] = 1.0 - Y_clean[s];
    }
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

const CertResult = struct {
    ok: bool,
    cov_before: f64,
    cov_after: f64,
    r2: f64,
};

fn certify(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []const Feature,
    cand: Feature,
    Y_train: []const f64,
    Y_clean: []const f64,
    feat_scratch: []f64,
    w: []f64,
) CertResult {
    const cov_before = coverageNoisyTrain(X, grid, lib, Y_train, Y_clean, w);
    var aug: [MAXFEAT]Feature = undefined;
    @memcpy(aug[0..lib.len], lib);
    aug[lib.len] = cand;
    const cov_after = coverageNoisyTrain(X, grid, aug[0 .. lib.len + 1], Y_train, Y_clean, w);
    for (0..NSAMP) |s| feat_scratch[s] = evalFeature(cand, grid[s]);
    buildFeat(X, grid, lib);
    const r2 = reconR2(X, feat_scratch, lib.len, w);
    const escape = cov_after >= COVER and cov_before < COVER;
    return .{
        .ok = escape and r2 < R2_MAX,
        .cov_before = cov_before,
        .cov_after = cov_after,
        .r2 = r2,
    };
}

fn discoverSpectral(grid: []const [NCELL]u8, Y: []const f64, feat_out: []f64) f64 {
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

fn discoverWalshHigh(grid: []const [NCELL]u8, Y: []const f64) u8 {
    var est = [_]f64{0} ** DOM;
    for (0..NTR) |s| {
        const p = signPattern(grid[s]);
        const g: f64 = if (Y[s] > 0.5) -1.0 else 1.0;
        for (0..DOM) |S| {
            const mask: u8 = @intCast(S);
            const d = popcount(mask);
            if (d < WALSH_DEG_LO or d > WALSH_DEG_HI) continue;
            est[S] += g * chi(mask, p);
        }
    }
    var best_abs: f64 = -1;
    var bestS: u8 = 0;
    for (0..DOM) |S| {
        const mask: u8 = @intCast(S);
        const d = popcount(mask);
        if (d < WALSH_DEG_LO or d > WALSH_DEG_HI) continue;
        const v = @abs(est[S]) / @as(f64, @floatFromInt(NTR));
        if (v > best_abs) {
            best_abs = v;
            bestS = mask;
        }
    }
    if (bestS == 0) bestS = 0x07; // fallback deg-3 mask
    return bestS;
}

fn topWalshMasks(grid: []const [NCELL]u8, Y: []const f64, out: *[3]u8) usize {
    var est = [_]f64{0} ** DOM;
    for (0..NTR) |s| {
        const p = signPattern(grid[s]);
        const g: f64 = if (Y[s] > 0.5) -1.0 else 1.0;
        for (0..DOM) |S| {
            const mask: u8 = @intCast(S);
            const d = popcount(mask);
            if (d < WALSH_DEG_LO or d > WALSH_DEG_HI) continue;
            est[S] += g * chi(mask, p);
        }
    }
    var n: usize = 0;
    while (n < 3) : (n += 1) {
        var best_abs: f64 = -1;
        var bestS: u8 = 0;
        for (0..DOM) |S| {
            const mask: u8 = @intCast(S);
            const d = popcount(mask);
            if (d < WALSH_DEG_LO or d > WALSH_DEG_HI) continue;
            var dup = false;
            for (0..n) |k| {
                if (out[k] == mask) dup = true;
            }
            if (dup) continue;
            const v = @abs(est[S]) / @as(f64, @floatFromInt(NTR));
            if (v > best_abs) {
                best_abs = v;
                bestS = mask;
            }
        }
        if (bestS == 0) break;
        out[n] = bestS;
    }
    return n;
}

fn tryOperatorMenu(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y_train: []const f64,
    Y_clean: []const f64,
    feat_scratch: []f64,
    w: []f64,
) bool {
    const omega = discoverSpectral(grid, Y_train, feat_scratch);
    var walsh_top: [3]u8 = .{ 0, 0, 0 };
    const nw = topWalshMasks(grid, Y_train, &walsh_top);

    var best_cert: CertResult = .{ .ok = false, .cov_before = 0, .cov_after = -1, .r2 = 2 };
    var best_feat: ?Feature = null;

    const base_cands = [_]Feature{
        .{ .spectral_count = omega },
        .{ .clifford_g2 = {} },
    };
    for (base_cands) |cand| {
        if (hasFeature(lib[0..nlib.*], cand)) continue;
        const cert = certify(X, grid, lib[0..nlib.*], cand, Y_train, Y_clean, feat_scratch, w);
        if (cert.cov_after > best_cert.cov_after) {
            best_cert = cert;
            best_feat = cand;
        }
    }
    var wi: usize = 0;
    while (wi < nw) : (wi += 1) {
        const cand: Feature = .{ .walsh = walsh_top[wi] };
        if (hasFeature(lib[0..nlib.*], cand)) continue;
        const cert = certify(X, grid, lib[0..nlib.*], cand, Y_train, Y_clean, feat_scratch, w);
        if (cert.cov_after > best_cert.cov_after) {
            best_cert = cert;
            best_feat = cand;
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

fn tryWorldPool(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y_train: []const f64,
    Y_clean: []const f64,
    feat_scratch: []f64,
    w: []f64,
) bool {
    var best_cert: CertResult = .{ .ok = false, .cov_before = 0, .cov_after = -1, .r2 = 2 };
    var best_feat: ?Feature = null;

    for (WORLD_PRIMES) |p| {
        const pair = [_]Feature{
            .{ .world_sum_mod = p },
            .{ .world_sign_mod = p },
        };
        for (pair) |cand| {
            if (hasFeature(lib[0..nlib.*], cand)) continue;
            const cert = certify(X, grid, lib[0..nlib.*], cand, Y_train, Y_clean, feat_scratch, w);
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
    Y_train: []const f64,
    Y_clean: []const f64,
    phiTgt: []f64,
    w: []f64,
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
        for (0..1) |c| {
            var mu: f64 = 0;
            for (0..NTR) |s| mu += X[s][c];
            mu /= @floatFromInt(NTR);
            var sd: f64 = 0;
            for (0..NTR) |s| sd += (X[s][c] - mu) * (X[s][c] - mu);
            sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
            for (0..NSAMP) |s| X[s][c] = (X[s][c] - mu) / sd;
        }
        fitLogit(X, Y_train, 1, 70, 0.06, w);
        const v = accLogitClean(X, Y_clean, w, 1, NTR, NVA);
        if (v > best_val) {
            best_val = v;
            best_mask = cand;
        }
    }

    const cand_feat: Feature = .{ .monomial = best_mask };
    for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], best_mask);
    const cert = certify(X, grid, lib[0..nlib.*], cand_feat, Y_train, Y_clean, phiTgt, w);
    if (cert.ok) {
        lib[nlib.*] = cand_feat;
        nlib.* += 1;
        return true;
    }
    return false;
}

/// Blind 2-feature readout: search high-signal pairs (non-trivial features only).
fn tryPairCompose(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y_train: []const f64,
    Y_clean: []const f64,
    w: []f64,
) bool {
    var cand: [12]usize = undefined;
    var nc: usize = 0;
    for (0..nlib.*) |i| {
        switch (lib[i]) {
            .monomial => |m| if (popcount(m) > 1 and nc < cand.len) {
                cand[nc] = i;
                nc += 1;
            },
            else => if (nc < cand.len) {
                cand[nc] = i;
                nc += 1;
            },
        }
    }
    if (nc < 2) return false;

    const base_cov = coverageNoisyTrain(X, grid, lib[0..nlib.*], Y_train, Y_clean, w);
    var best_cov: f64 = base_cov;
    var best_i: usize = cand[0];
    var best_j: usize = cand[1];

    var i: usize = 0;
    while (i < nc) : (i += 1) {
        var j: usize = i + 1;
        while (j < nc) : (j += 1) {
            const pair_lib = [_]Feature{ lib[cand[i]], lib[cand[j]] };
            const cov = coverageNoisyTrain(X, grid, &pair_lib, Y_train, Y_clean, w);
            if (cov > best_cov) {
                best_cov = cov;
                best_i = cand[i];
                best_j = cand[j];
            }
        }
    }

    if (best_cov < COVER or best_cov <= base_cov) return false;

    var slim: [2]Feature = .{ lib[best_i], lib[best_j] };
    nlib.* = 2;
    @memcpy(lib[0..2], &slim);
    return true;
}

pub const SolveScratch = struct {
    Y_clean: [NSAMP]f64,
    Y_train: [NSAMP]f64,
    X: [NSAMP][MAXFEAT]f64,
    phiTgt: [NSAMP]f64,
    w: [MAXFEAT + 1]f64,
};

pub fn runHardTarget(
    grid: []const [NCELL]u8,
    spec: TargetSpec,
    seed: u64,
    scratch: *SolveScratch,
) struct { solved: bool, cov: f64 } {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    for (0..NSAMP) |s| scratch.Y_clean[s] = cleanLabel(grid[s], spec);
    applyLabelNoise(rand, &scratch.Y_clean, &scratch.Y_train, spec.noise_rate);

    const Y_clean = scratch.Y_clean[0..NSAMP];
    const Y_train = scratch.Y_train[0..NSAMP];
    var X_rows: [NSAMP][]f64 = undefined;
    for (0..NSAMP) |s| X_rows[s] = scratch.X[s][0..MAXFEAT];
    const X = X_rows[0..NSAMP];
    const phiTgt = scratch.phiTgt[0..NSAMP];
    const w = scratch.w[0 .. MAXFEAT + 1];

    var lib: [MAXFEAT]Feature = undefined;
    var nlib: usize = 0;
    for (0..NCELL) |i| {
        lib[nlib] = .{ .monomial = @as(u8, 1) << @intCast(i) };
        nlib += 1;
    }

    var cov = coverageNoisyTrain(X, grid, lib[0..nlib], Y_train, Y_clean, w);

    if (cov < COVER) {
        var menu_round: usize = 0;
        while (menu_round < 2) : (menu_round += 1) {
            if (cov >= COVER) break;
            if (!tryOperatorMenu(X, grid, &lib, &nlib, Y_train, Y_clean, phiTgt, w)) break;
            cov = coverageNoisyTrain(X, grid, lib[0..nlib], Y_train, Y_clean, w);
        }
    }

    if (cov < COVER) {
        if (tryWorldPool(X, grid, &lib, &nlib, Y_train, Y_clean, phiTgt, w)) {
            cov = coverageNoisyTrain(X, grid, lib[0..nlib], Y_train, Y_clean, w);
        }
    }

    if (cov < COVER and spec.kind == .composed_and) {
        if (tryPairCompose(X, grid, &lib, &nlib, Y_train, Y_clean, w)) {
            cov = coverageNoisyTrain(X, grid, lib[0..nlib], Y_train, Y_clean, w);
        }
    }

    return .{
        .solved = cov >= COVER,
        .cov = cov,
    };
}

// ── Mutators ─────────────────────────────────────────────────────────────────

fn randomWalshMask(rand: std.Random) u8 {
    const deg = rand.intRangeAtMost(usize, WALSH_DEG_LO, WALSH_DEG_HI);
    var mask: u8 = 0;
    var picked: usize = 0;
    while (picked < deg) {
        const bit = rand.intRangeAtMost(u8, 0, 7);
        const m = @as(u8, 1) << @intCast(bit);
        if (mask & m == 0) {
            mask |= m;
            picked += 1;
        }
    }
    return if (mask == 0) 0x07 else mask;
}

const AtomParams = struct { kind: AtomKind, mask: u8, modulus: usize };

fn randomAtom(rand: std.Random) AtomParams {
    const kind = switch (rand.intRangeAtMost(u8, 0, 5)) {
        0 => AtomKind.walsh,
        1 => AtomKind.parity,
        2 => AtomKind.oriented,
        3 => AtomKind.sum_mod,
        4 => AtomKind.sign_mod,
        else => AtomKind.monomial,
    };
    return .{
        .kind = kind,
        .mask = randomWalshMask(rand),
        .modulus = WORLD_PRIMES[rand.intRangeAtMost(usize, 0, WORLD_PRIMES.len - 1)],
    };
}

fn randomComposed(rand: std.Random) TargetSpec {
    // Bias toward pairs that genuinely need two features (Walsh∧X, monomial∧Walsh).
    const a = if (rand.float(f64) < 0.65)
        AtomParams{ .kind = .walsh, .mask = randomWalshMask(rand), .modulus = 3 }
    else
        randomAtom(rand);
    var b = randomAtom(rand);
    var guard: usize = 0;
    while (guard < 8) : (guard += 1) {
        const weak = b.kind != .walsh and b.kind != .monomial and b.kind != .sum_mod and b.kind != .sign_mod;
        const dup = b.kind == a.kind and b.mask == a.mask and b.modulus == a.modulus;
        if (!weak and !dup) break;
        b = randomAtom(rand);
    }
    return .{
        .kind = .composed_and,
        .atom_a = a.kind,
        .atom_b = b.kind,
        .mask_a = a.mask,
        .mask_b = b.mask,
        .modulus_a = a.modulus,
        .modulus_b = b.modulus,
        .noise_rate = LABEL_NOISE,
    };
}

fn randomTarget(rand: std.Random) TargetSpec {
    if (rand.float(f64) < 0.30) {
        return .{
            .kind = .walsh_high,
            .walsh_mask = randomWalshMask(rand),
            .noise_rate = LABEL_NOISE,
        };
    }
    return randomComposed(rand);
}

fn mutateWalshMask(rand: std.Random, mask: u8) u8 {
    var m = mask;
    if (rand.float(f64) < 0.5) {
        const bit = rand.intRangeAtMost(u8, 0, 7);
        m ^= @as(u8, 1) << @intCast(bit);
    } else if (popcount(m) < WALSH_DEG_HI) {
        const bit = rand.intRangeAtMost(u8, 0, 7);
        m |= @as(u8, 1) << @intCast(bit);
    } else {
        const bit: u3 = @intCast(rand.intRangeAtMost(u8, 0, 7));
        m &= ~(@as(u8, 1) << bit);
    }
    const d = popcount(m);
    if (d < WALSH_DEG_LO or d > WALSH_DEG_HI) return randomWalshMask(rand);
    return m;
}

fn mutateAtom(rand: std.Random, atom: AtomKind, mask: u8, modulus: usize) AtomParams {
    if (rand.float(f64) < 0.35) return randomAtom(rand);
    return switch (atom) {
        .walsh => .{ .kind = .walsh, .mask = mutateWalshMask(rand, mask), .modulus = modulus },
        .monomial => .{ .kind = .monomial, .mask = mutateWalshMask(rand, if (mask != 0) mask else 0x03), .modulus = modulus },
        .sum_mod, .sign_mod => .{ .kind = atom, .mask = mask, .modulus = WORLD_PRIMES[rand.intRangeAtMost(usize, 0, WORLD_PRIMES.len - 1)] },
        else => .{ .kind = atom, .mask = mask, .modulus = modulus },
    };
}

pub fn mutateTarget(rand: std.Random, parent: ?TargetSpec) TargetSpec {
    if (parent == null or rand.float(f64) < 0.20) return randomTarget(rand);
    var spec = parent.?;
    switch (spec.kind) {
        .walsh_high => {
            if (rand.float(f64) < 0.35) return randomComposed(rand);
            spec.walsh_mask = mutateWalshMask(rand, spec.walsh_mask);
        },
        .composed_and => {
            if (rand.float(f64) < 0.30) {
                return .{
                    .kind = .walsh_high,
                    .walsh_mask = randomWalshMask(rand),
                    .noise_rate = LABEL_NOISE,
                };
            }
            if (rand.float(f64) < 0.5) {
                const a = mutateAtom(rand, spec.atom_a, spec.mask_a, spec.modulus_a);
                spec.atom_a = a.kind;
                spec.mask_a = a.mask;
                spec.modulus_a = a.modulus;
            } else {
                const b = mutateAtom(rand, spec.atom_b, spec.mask_b, spec.modulus_b);
                spec.atom_b = b.kind;
                spec.mask_b = b.mask;
                spec.modulus_b = b.modulus;
            }
        },
    }
    spec.noise_rate = LABEL_NOISE;
    return spec;
}

pub fn targetDepth(spec: TargetSpec) usize {
    return switch (spec.kind) {
        .walsh_high => popcount(spec.walsh_mask),
        .composed_and => @as(usize, 8) + @intFromEnum(spec.atom_a) + @intFromEnum(spec.atom_b),
    };
}

fn specFingerprint(spec: TargetSpec) u64 {
    var h: u64 = @intFromEnum(spec.kind);
    h ^= @as(u64, spec.walsh_mask) *% 0x9E3779B97F4A7C15;
    h ^= @as(u64, @intCast(@intFromEnum(spec.atom_a))) *% 0xC6A4A7935BD1E995;
    h ^= @as(u64, @intCast(@intFromEnum(spec.atom_b))) *% 0xD1B54A32D192ED03;
    h ^= @as(u64, spec.mask_a) *% 0x94D049BB133111EB;
    h ^= @as(u64, spec.mask_b) *% 0xDA942042E4BC58B3;
    h ^= @as(u64, spec.modulus_a) *% 0xC2B2AE3D27D4EB4F;
    h ^= @as(u64, spec.modulus_b) *% 0x165667B19E3779F9;
    return h;
}

pub fn formatSpec(buf: []u8, spec: TargetSpec) []const u8 {
    return switch (spec.kind) {
        .walsh_high => std.fmt.bufPrint(buf, "χ(0x{X:0>2},d{d})", .{ spec.walsh_mask, popcount(spec.walsh_mask) }) catch "walsh",
        .composed_and => std.fmt.bufPrint(buf, "{s}∧{s}", .{
            @tagName(spec.atom_a),
            @tagName(spec.atom_b),
        }) catch "composed",
    };
}

fn curriculumHas(entries: []const CurriculumEntry, fp: u64) bool {
    for (entries) |e| if (e.fingerprint == fp) return true;
    return false;
}

pub fn pickCurriculumParent(rand: std.Random, entries: []const CurriculumEntry) ?TargetSpec {
    if (entries.len == 0) return null;
    return entries[rand.intRangeAtMost(usize, 0, entries.len - 1)].spec;
}

pub fn tryAddCurriculum(
    entries: *std.ArrayList(CurriculumEntry),
    spec: TargetSpec,
    cov: f64,
) !void {
    if (cov < CURR_LO or cov > CURR_HI) return;
    const fp = specFingerprint(spec);
    if (curriculumHas(entries.items, fp)) return;
    if (entries.items.len >= MAX_CURRICULUM) {
        _ = entries.orderedRemove(0);
    }
    try entries.append(.{
        .spec = spec,
        .coverage = cov,
        .depth = targetDepth(spec),
        .fingerprint = fp,
    });
}

pub fn curriculumPeakDepth(entries: []const CurriculumEntry) usize {
    var peak: usize = 0;
    for (entries) |e| peak = @max(peak, e.depth);
    return peak;
}

pub fn runExperiment(alloc: std.mem.Allocator, out: anytype, verbose: bool) !ExperimentResult {
    var prng = std.Random.DefaultPrng.init(SEED);
    const rand = prng.random();

    var curriculum = std.ArrayList(CurriculumEntry).init(alloc);
    defer curriculum.deinit();

    var solved_count: usize = 0;
    var proposals: usize = 0;
    var curriculum_ge10_rounds: usize = 0;
    var curriculum_trace: [5]usize = .{0} ** 5;

    if (verbose) {
        try out.print("=== RESEARCH Q8: E12 hard mutators (POET curriculum) ===\n\n", .{});
        try out.print("Mutators: 10% label noise | Walsh deg {d}–{d} | composed AND (2-feature)\n", .{ WALSH_DEG_LO, WALSH_DEG_HI });
        try out.print("Curate band: [{d:.2}, {d:.2}]  |  Pass: curriculum≥{d} for ≥{d} rounds AND solve∈[{d:.0}%,{d:.0}%]\n", .{
            CURR_LO, CURR_HI, CURR_PASS_SIZE, CURR_PASS_ROUNDS, SOLVE_LO * 100, SOLVE_HI * 100,
        });
        try out.print("Rounds: {d} × {d} proposals = {d} total.\n\n", .{ N_ROUNDS, PROPOSALS_PER_ROUND, N_ROUNDS * PROPOSALS_PER_ROUND });
    }

    // Shared grid per round — labels vary per target; saves allocation cost.
    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    var solve_scratch = SolveScratch{
        .Y_clean = undefined,
        .Y_train = undefined,
        .X = undefined,
        .phiTgt = undefined,
        .w = undefined,
    };

    var round: usize = 0;
    while (round < N_ROUNDS) : (round += 1) {
        var gprng = std.Random.DefaultPrng.init(SEED +% round *% 0x9E3779B9);
        const grid_rand = gprng.random();
        for (0..NSAMP) |s| for (0..NCELL) |i| {
            grid[s][i] = grid_rand.intRangeAtMost(u8, 0, VMAX);
        };

        var p: usize = 0;
        while (p < PROPOSALS_PER_ROUND) : (p += 1) {
            const parent = pickCurriculumParent(rand, curriculum.items);
            const spec = mutateTarget(rand, parent);

            const result = runHardTarget(grid, spec, SEED +% round *% 17 +% p, &solve_scratch);
            proposals += 1;
            const cov = result.cov;

            try tryAddCurriculum(&curriculum, spec, cov);

            if (result.solved) solved_count += 1;

            if (verbose and round < 6) {
                var buf: [40]u8 = undefined;
                const sname = formatSpec(&buf, spec);
                try out.print("  r{d:>2} p{d} {s:<20} cov={d:.3}{s}\n", .{
                    round,
                    p,
                    sname,
                    cov,
                    if (result.solved) " SOLVED" else "",
                });
            }
        }

        if (curriculum.items.len >= CURR_PASS_SIZE) curriculum_ge10_rounds += 1;

        if (round % 10 == 9) {
            const slot = round / 10;
            if (slot < curriculum_trace.len) {
                curriculum_trace[slot] = curriculum.items.len;
            }
        }

        if (verbose and round % 10 == 9) {
            try out.print("  … round {d}: curriculum={d} peak_depth={d}\n", .{
                round,
                curriculum.items.len,
                curriculumPeakDepth(curriculum.items),
            });
        }
    }

    const solve_rate = @as(f64, @floatFromInt(solved_count)) / @as(f64, @floatFromInt(proposals));
    const curriculum_peak = curriculumPeakDepth(curriculum.items);
    const curriculum_pass = curriculum_ge10_rounds >= CURR_PASS_ROUNDS;
    const solve_rate_pass = solve_rate >= SOLVE_LO and solve_rate <= SOLVE_HI;
    const sustained_growth = curriculum_pass and solve_rate_pass;

    if (verbose) {
        try out.print("\n── curriculum size trace (every 10 rounds) ──\n", .{});
        for (curriculum_trace, 0..) |sz, i| {
            try out.print("  checkpoint {d:>2}: size {d}\n", .{ (i + 1) * 10, sz });
        }
        try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
        try out.print("rounds:                 {d}\n", .{N_ROUNDS});
        try out.print("proposals:              {d}\n", .{proposals});
        try out.print("solved (≥{d:.2}):        {d}\n", .{ COVER, solved_count });
        try out.print("solve rate:             {d:.1}%  (pass band {d:.0}–{d:.0}%)\n", .{ solve_rate * 100, SOLVE_LO * 100, SOLVE_HI * 100 });
        try out.print("curriculum size (final): {d}  (band [{d:.2},{d:.2}])\n", .{ curriculum.items.len, CURR_LO, CURR_HI });
        try out.print("curriculum peak depth:   {d}\n", .{curriculum_peak});
        try out.print("rounds curriculum≥{d}:  {d}/{d}\n", .{ CURR_PASS_SIZE, curriculum_ge10_rounds, N_ROUNDS });
        try out.print("curriculum pass:         {s}\n", .{if (curriculum_pass) "PASS" else "FAIL"});
        try out.print("solve rate pass:         {s}\n", .{if (solve_rate_pass) "PASS" else "FAIL"});
        try out.print("sustained growth:        {s}\n", .{if (sustained_growth) "PASS" else "FAIL"});
        try out.print("\nSee: open_invention_e12.zig (baseline), unified_invention.zig\n", .{});
    }

    return .{
        .rounds = N_ROUNDS,
        .proposals = proposals,
        .solved_count = solved_count,
        .solve_rate = solve_rate,
        .curriculum_size = curriculum.items.len,
        .curriculum_peak = curriculum_peak,
        .curriculum_ge10_rounds = curriculum_ge10_rounds,
        .sustained_growth = sustained_growth,
        .curriculum_pass = curriculum_pass,
        .solve_rate_pass = solve_rate_pass,
        .curriculum_trace = curriculum_trace,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    _ = try runExperiment(alloc, out, true);
}

test "RQ8 hard mutators produce non-trivial POET band" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const NullOut = struct {
        pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
    };
    const result = try runExperiment(arena.allocator(), NullOut{}, false);
    try std.testing.expect(result.rounds == N_ROUNDS);
    try std.testing.expect(result.proposals == N_ROUNDS * PROPOSALS_PER_ROUND);
    try std.testing.expect(result.solve_rate > 0.05);
    try std.testing.expect(result.solve_rate < 0.98);
}