//! Fork 5 — unified invention loop: monomial forge → operator menu → world pool (mod_p).
//!
//! Takes a structured target predicate description, then escalates through three discovery
//! mechanisms with one certifier (escape ≥0.90 held-out AND irreducible R²<0.40):
//!   1. Inner-transform monomial forge (inner_forge.zig substrate)
//!   2. Operator menu: spectral / Walsh / Clifford (operator_menu.zig)
//!   3. World pool: divisibility on grid-derived integers (invention_engine / world_injection)
//!
//! Compare against inner_forge-only baseline to show what the unified loop unlocks.
//!
//! Run: zig build unified-invention --release=fast

const std = @import("std");
pub const guide = @import("learned_candidate_guide.zig");

const SilentOut = struct {
    fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const THETA: f64 = 0.40;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const DOM: usize = 1 << NCELL;
const MAXFEAT: usize = 32;
const MAXDEG: usize = 4;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;

const WORLD_POOL = [_]usize{ 2, 3, 5, 7, 11, 13 };
const NPOOL = WORLD_POOL.len;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
}

// ── Structured target description (not NL yet) ────────────────────────────────

pub const TargetKind = enum {
    monomial_sign,
    parity_of_count,
    oriented,
    sum_mod,
    sign_mod,
};

pub const TargetSpec = struct {
    name: []const u8,
    kind: TargetKind,
    mask: u8 = 0,
    modulus: usize = 0,
};

pub const NT: usize = 7;
pub const COVER_THRESHOLD: f64 = COVER;
pub const TARGETS = [_]TargetSpec{
    .{ .name = "T1 sign φ{2,5}     (deg2)", .kind = .monomial_sign, .mask = (1 << 2) | (1 << 5) },
    .{ .name = "T2 sign φ{1,3,6}    (deg3)", .kind = .monomial_sign, .mask = (1 << 1) | (1 << 3) | (1 << 6) },
    .{ .name = "T3 sign φ{0,4,5,7}  (deg4)", .kind = .monomial_sign, .mask = (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7) },
    .{ .name = "T4 sign(c3−MID)     (deg1)", .kind = .monomial_sign, .mask = (1 << 3) },
    .{ .name = "T5 parity-of-count  (≠mono)", .kind = .parity_of_count },
    .{ .name = "T6 oriented v1>v0   (≠mono)", .kind = .oriented },
    .{ .name = "T7 sum(g) % 7 = 0   (world)", .kind = .sum_mod, .modulus = 7 },
};

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

fn label(g: [NCELL]u8, spec: TargetSpec) f64 {
    return switch (spec.kind) {
        .monomial_sign => if (phi(g, spec.mask) > 0) 1.0 else 0.0,
        .parity_of_count => blk: {
            var c: usize = 0;
            for (g) |v| if (v >= THRESH) {
                c += 1;
            };
            break :blk @floatFromInt(c & 1);
        },
        .oriented => if (g[1] > g[0]) 1.0 else 0.0,
        .sum_mod => if (gridSum(g) % spec.modulus == 0) 1.0 else 0.0,
        .sign_mod => if (@as(usize, signPattern(g)) % spec.modulus == 0) 1.0 else 0.0,
    };
}

// ── Feature library ──────────────────────────────────────────────────────────

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

pub const Source = enum { base, forge, menu, world };

pub const BenchmarkSummary = struct {
    forge_solved: usize,
    unified_solved: usize,
    delta_count: usize,
    forge_cov: [NT]f64,
    unified_cov: [NT]f64,
    solved_by: [NT]Source,
    final_nlib: usize,
};

const source_name = [_][]const u8{ "base", "forge", "menu", "world" };

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

fn featureKey(buf: []u8, f: Feature) []const u8 {
    switch (f) {
        .monomial => |m| return std.fmt.bufPrint(buf, "φ(0x{X:0>2})", .{m}) catch "φ",
        .spectral_count => |omega| return std.fmt.bufPrint(buf, "cos(ω·count),ω={d:.3}", .{omega}) catch "spectral",
        .walsh => |S| return std.fmt.bufPrint(buf, "χ{{S=0x{X:0>2}}}", .{S}) catch "χ",
        .clifford_g2 => return "sin(θ(v1-v0))",
        .world_sum_mod => |p| return std.fmt.bufPrint(buf, "sum%mod_{d}", .{p}) catch "sum_mod",
        .world_sign_mod => |p| return std.fmt.bufPrint(buf, "sign%mod_{d}", .{p}) catch "sign_mod",
    }
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

// ── ML helpers ───────────────────────────────────────────────────────────────

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

pub const CertResult = struct {
    ok: bool,
    cov_before: f64,
    cov_after: f64,
    r2: f64,
};

pub const BenchMetrics = struct {
    summary: BenchmarkSummary,
    certify_calls: usize,
    probe_calls: usize,
    forge_fits: usize,
};

fn certify(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []const Feature,
    cand: Feature,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
) CertResult {
    const cov_before = coverage(X, grid, lib, Y, w);
    var aug: [MAXFEAT]Feature = undefined;
    @memcpy(aug[0..lib.len], lib);
    aug[lib.len] = cand;
    const cov_after = coverage(X, grid, aug[0 .. lib.len + 1], Y, w);
    for (0..NSAMP) |s| feat_scratch[s] = evalFeature(cand, grid[s]);
    buildFeat(X, grid, lib);
    const r2 = reconR2(X, feat_scratch, lib.len, w);
    // escape: lifts held-out to ≥COVER from below COVER (same thresholds as invention_engine)
    const escape = cov_after >= COVER and cov_before < COVER;
    return .{
        .ok = escape and r2 < R2_MAX,
        .cov_before = cov_before,
        .cov_after = cov_after,
        .r2 = r2,
    };
}

// ── Operator menu discovery ────────────────────────────────────────────────────

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

fn discoverWalsh(grid: []const [NCELL]u8, Y: []const f64) u8 {
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

fn probeMonomialHardness(grid: []const [NCELL]u8, Y: []const f64, feat: []f64) struct { best: f64, mask: u8 } {
    var best: f64 = 0.5;
    var best_mask: u8 = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        const d = popcount(mask);
        if (d < 1 or d > MAXDEG) continue;
        for (0..NSAMP) |s| feat[s] = phi(grid[s], mask);
        const v = valAccSingle(feat, Y);
        if (v > best) {
            best = v;
            best_mask = mask;
        }
    }
    return .{ .best = best, .mask = best_mask };
}

fn probeExtremalHardness(grid: []const [NCELL]u8, Y: []const f64, feat: []f64) struct { best: f64, tag: []const u8 } {
    const probes = [_]struct { tag: []const u8, fill: *const fn ([NCELL]u8) f64 }{
        .{ .tag = "oriented", .fill = oriented },
        .{ .tag = "countGE", .fill = countGE },
        .{ .tag = "clifford_g2", .fill = cliffordG2 },
    };
    var best: f64 = 0.5;
    var best_tag: []const u8 = "none";
    for (probes) |p| {
        for (0..NSAMP) |s| feat[s] = p.fill(grid[s]);
        const v = valAccSingle(feat, Y);
        if (v > best) {
            best = v;
            best_tag = p.tag;
        }
    }
    return .{ .best = best, .tag = best_tag };
}

fn targetHardness(grid: []const [NCELL]u8, Y: []const f64, feat: []f64) guide.TaskHardness {
    const mono = probeMonomialHardness(grid, Y, feat);
    const ext = probeExtremalHardness(grid, Y, feat);
    return guide.classifyHardness(mono.best, ext.best);
}

fn tryOperatorMenu(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    out: anytype,
) !bool {
    const omega = discoverSpectral(grid, Y, feat_scratch);
    const spec_val = valAccSingle(feat_scratch, Y);

    const walshS = discoverWalsh(grid, Y);
    for (0..NSAMP) |s| feat_scratch[s] = chi(walshS, signPattern(grid[s]));
    const wal_val = valAccSingle(feat_scratch, Y);

    for (0..NSAMP) |s| feat_scratch[s] = cliffordG2(grid[s]);
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

    const cert = certify(X, grid, lib[0..nlib.*], cand, Y, feat_scratch, w);
    var keybuf: [48]u8 = undefined;
    const kname = featureKey(&keybuf, cand);
    if (cert.ok) {
        lib[nlib.*] = cand;
        nlib.* += 1;
        try out.print("    MENU: +{s} escape {d:.2}→{d:.2}, R²={d:.2} → PROMOTE\n", .{ kname, cert.cov_before, cert.cov_after, cert.r2 });
        return true;
    }
    try out.print("    MENU: best {s} val={d:.2} escape {d:.2} R²={d:.2} → not certified\n", .{ kname, vals[best_i], cert.cov_after, cert.r2 });
    return false;
}

// ── World pool ───────────────────────────────────────────────────────────────

fn tryWorldPool(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    out: anytype,
) !bool {
    var best_cert: CertResult = .{ .ok = false, .cov_before = 0, .cov_after = -1, .r2 = 2 };
    var best_feat: ?Feature = null;
    var keybuf: [32]u8 = undefined;

    for (WORLD_POOL) |p| {
        const pair = [_]Feature{
            .{ .world_sum_mod = p },
            .{ .world_sign_mod = p },
        };
        for (pair) |cand| {
            if (hasFeature(lib[0..nlib.*], cand)) continue;
            const cert = certify(X, grid, lib[0..nlib.*], cand, Y, feat_scratch, w);
            if (cert.cov_after > best_cert.cov_after) {
                best_cert = cert;
                best_feat = cand;
            }
        }
    }

    if (best_feat) |bf| {
        const kname = featureKey(&keybuf, bf);
        if (best_cert.ok) {
            lib[nlib.*] = bf;
            nlib.* += 1;
            try out.print("    WORLD: +{s} escape {d:.2}→{d:.2}, R²={d:.2} → PROMOTE\n", .{ kname, best_cert.cov_before, best_cert.cov_after, best_cert.r2 });
            return true;
        }
        try out.print("    WORLD: best {s} escape {d:.2} R²={d:.2} → not certified\n", .{ kname, best_cert.cov_after, best_cert.r2 });
    }
    return false;
}

const CostCounter = struct {
    certify_calls: usize = 0,
    probe_calls: usize = 0,
    forge_fits: usize = 0,
};

fn tryWorldPoolGuided(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    hardness: guide.TaskHardness,
    g: *guide.Guide,
    top_k: usize,
    cost: *CostCounter,
    out: anytype,
) !bool {
    const MaxCands = NPOOL * 2;
    var cands: [MaxCands]Feature = undefined;
    var probes: [MaxCands]f64 = undefined;
    var scores: [MaxCands]f32 = undefined;
    var order: [MaxCands]usize = undefined;
    var nc: usize = 0;

    for (WORLD_POOL) |p| {
        const pair = [_]Feature{
            .{ .world_sum_mod = p },
            .{ .world_sign_mod = p },
        };
        for (pair) |cand| {
            if (hasFeature(lib[0..nlib.*], cand)) continue;
            for (0..NSAMP) |s| feat_scratch[s] = evalFeature(cand, grid[s]);
            const v = valAccSingle(feat_scratch, Y);
            cost.probe_calls += 1;
            const inner = guide.innerFromFeatureTag(std.meta.activeTag(cand));
            cands[nc] = cand;
            probes[nc] = v;
            scores[nc] = @as(f32, @floatCast(v * 2.0)) + g.score(.{ .probe_corr = v, .hardness = hardness, .inner = inner });
            order[nc] = nc;
            nc += 1;
        }
    }
    if (nc == 0) return false;

    const score_slice = scores[0..nc];
    std.sort.pdq(usize, order[0..nc], score_slice, struct {
        fn lt(s: []const f32, a: usize, b: usize) bool {
            return s[a] > s[b];
        }
    }.lt);

    const best_corr = probes[order[0]];
    const k = if (best_corr >= 0.85) 1 else @min(top_k, nc);
    var keybuf: [32]u8 = undefined;
    for (0..k) |ki| {
        const idx = order[ki];
        const cand = cands[idx];
        const inner = guide.innerFromFeatureTag(std.meta.activeTag(cand));
        cost.certify_calls += 1;
        const cert = certify(X, grid, lib[0..nlib.*], cand, Y, feat_scratch, w);
        try g.logAndTrain(.{ .probe_corr = probes[idx], .hardness = hardness, .inner = inner }, cert.ok, cert.cov_after, cert.r2);
        const kname = featureKey(&keybuf, cand);
        if (cert.ok) {
            lib[nlib.*] = cand;
            nlib.* += 1;
            try out.print("    WORLD+: +{s} escape {d:.2}→{d:.2}, R²={d:.2} → PROMOTE\n", .{ kname, cert.cov_before, cert.cov_after, cert.r2 });
            return true;
        }
    }
    return false;
}

// ── Monomial forge (monomials only in library) ───────────────────────────────

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
    out: anytype,
    quiet: bool,
) !bool {
    if (!isMonomialOnly(lib[0..nlib.*])) return false;

    var best_val: f64 = -1;
    var best_mask: u8 = 0;
    var one: [1]u8 = .{0};
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const cand: u8 = @intCast(mm);
        const d = popcount(cand);
        if (d < 1 or d > MAXDEG) continue;
        if (hasFeature(lib[0..nlib.*], .{ .monomial = cand })) continue;
        one[0] = cand;
        buildFeat(X, grid, lib[0..nlib.*]);
        // single-feature probe on validation
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
        fitLogit(X, Y, 1, 70, 0.06, w);
        const v = accLogit(X, Y, w, 1, NTR, NVA);
        if (v > best_val) {
            best_val = v;
            best_mask = cand;
        }
    }

    const cand_feat: Feature = .{ .monomial = best_mask };
    for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], best_mask);
    const cert = certify(X, grid, lib[0..nlib.*], cand_feat, Y, phiTgt, w);
    if (cert.ok) {
        lib[nlib.*] = cand_feat;
        nlib.* += 1;
        if (!quiet) try out.print("    FORGE: +φ(0x{X:0>2},deg{d}) escape {d:.2}→{d:.2}, R²={d:.2} → PROMOTE\n", .{ best_mask, popcount(best_mask), cert.cov_before, cert.cov_after, cert.r2 });
        return true;
    }
    return false;
}

fn tryMonomialForgeGuided(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    phiTgt: []f64,
    w: []f64,
    hardness: guide.TaskHardness,
    g: *guide.Guide,
    top_k: usize,
    cost: *CostCounter,
    out: anytype,
    quiet: bool,
) !bool {
    if (!isMonomialOnly(lib[0..nlib.*])) return false;

    const MaxMasks = 220;
    var masks: [MaxMasks]u8 = undefined;
    var vals: [MaxMasks]f64 = undefined;
    var scores: [MaxMasks]f32 = undefined;
    var order: [MaxMasks]usize = undefined;
    var nm: usize = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const cand: u8 = @intCast(mm);
        const d = popcount(cand);
        if (d < 1 or d > MAXDEG) continue;
        if (hasFeature(lib[0..nlib.*], .{ .monomial = cand })) continue;
        for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], cand);
        cost.probe_calls += 1;
        const v = valAccSingle(phiTgt, Y);
        masks[nm] = cand;
        vals[nm] = v;
        // probe_corr dominates; perceptron nudges tie-breaks (verifier-trained)
        scores[nm] = @as(f32, @floatCast(v * 2.0)) + g.score(.{ .probe_corr = v, .hardness = hardness, .inner = .monomial });
        order[nm] = nm;
        nm += 1;
    }
    if (nm == 0) return false;

    const score_slice = scores[0..nm];
    std.sort.pdq(usize, order[0..nm], score_slice, struct {
        fn lt(s: []const f32, a: usize, b: usize) bool {
            return s[a] > s[b];
        }
    }.lt);

    const best_corr = vals[order[0]];
    const k = if (best_corr >= 0.95) 1 else @min(top_k, nm);
    for (0..k) |ki| {
        const idx = order[ki];
        const mask = masks[idx];
        const cand_feat: Feature = .{ .monomial = mask };
        for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], mask);
        cost.certify_calls += 1;
        const cert = certify(X, grid, lib[0..nlib.*], cand_feat, Y, phiTgt, w);
        try g.logAndTrain(.{ .probe_corr = vals[idx], .hardness = hardness, .inner = .monomial }, cert.ok, cert.cov_after, cert.r2);
        if (cert.ok) {
            lib[nlib.*] = cand_feat;
            nlib.* += 1;
            if (!quiet) try out.print("    FORGE+: +φ(0x{X:0>2},deg{d}) escape {d:.2}→{d:.2}, R²={d:.2} → PROMOTE\n", .{ mask, popcount(mask), cert.cov_before, cert.cov_after, cert.r2 });
            return true;
        }
    }
    return false;
}

fn tryOperatorMenuGuided(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    feat_scratch: []f64,
    w: []f64,
    hardness: guide.TaskHardness,
    g: *guide.Guide,
    cost: *CostCounter,
    out: anytype,
) !bool {
    const omega = discoverSpectral(grid, Y, feat_scratch);
    const spec_val = valAccSingle(feat_scratch, Y);
    cost.probe_calls += 1;

    const walshS = discoverWalsh(grid, Y);
    for (0..NSAMP) |s| feat_scratch[s] = chi(walshS, signPattern(grid[s]));
    const wal_val = valAccSingle(feat_scratch, Y);
    cost.probe_calls += 1;

    for (0..NSAMP) |s| feat_scratch[s] = cliffordG2(grid[s]);
    const clf_val = valAccSingle(feat_scratch, Y);
    cost.probe_calls += 1;

    const cands = [_]Feature{
        .{ .spectral_count = omega },
        .{ .walsh = walshS },
        .{ .clifford_g2 = {} },
    };
    const vals = [_]f64{ spec_val, wal_val, clf_val };

    var best_i: usize = 0;
    for (1..3) |k| {
        if (vals[k] > vals[best_i]) best_i = k;
    }
    const cand = cands[best_i];
    if (hasFeature(lib[0..nlib.*], cand)) return false;

    const inner = guide.innerFromFeatureTag(std.meta.activeTag(cand));
    cost.certify_calls += 1;
    const cert = certify(X, grid, lib[0..nlib.*], cand, Y, feat_scratch, w);
    try g.logAndTrain(.{ .probe_corr = vals[best_i], .hardness = hardness, .inner = inner }, cert.ok, cert.cov_after, cert.r2);
    var keybuf: [48]u8 = undefined;
    const kname = featureKey(&keybuf, cand);
    if (cert.ok) {
        lib[nlib.*] = cand;
        nlib.* += 1;
        try out.print("    MENU+: +{s} escape {d:.2}→{d:.2}, R²={d:.2} → PROMOTE\n", .{ kname, cert.cov_before, cert.cov_after, cert.r2 });
        return true;
    }
    try out.print("    MENU+: best {s} val={d:.2} escape {d:.2} R²={d:.2} → not certified\n", .{ kname, vals[best_i], cert.cov_after, cert.r2 });
    return false;
}

// ── inner_forge-only baseline ──────────────────────────────────────────────────

fn innerForgeOnly(
    X: [][]f64,
    grid: []const [NCELL]u8,
    Y: []const []f64,
    phiTgt: []f64,
    w: []f64,
) [NT]f64 {
    var lib: [MAXFEAT]Feature = undefined;
    var nlib: usize = 0;
    for (0..NCELL) |i| {
        lib[nlib] = .{ .monomial = @as(u8, 1) << @intCast(i) };
        nlib += 1;
    }

    const null_out = SilentOut{};

    var round: usize = 0;
    while (round < 8) : (round += 1) {
        var promoted = false;
        for (0..NT) |t| {
            const cov = coverage(X, grid, lib[0..nlib], Y[t], w);
            if (cov >= COVER) continue;
            if (tryMonomialForge(X, grid, &lib, &nlib, Y[t], phiTgt, w, null_out, true) catch false) promoted = true;
        }
        if (!promoted) break;
    }

    var cov_out: [NT]f64 = .{0} ** NT;
    for (0..NT) |t| cov_out[t] = coverage(X, grid, lib[0..nlib], Y[t], w);
    return cov_out;
}

/// Run the full unified invention loop (forge → menu → world) on all 7 targets.
pub fn runFullBenchmark(alloc: std.mem.Allocator, out: anytype, seed: u64, verbose: bool) !BenchmarkSummary {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const Y = try alloc.alloc([]f64, NT);
    for (0..NT) |t| {
        Y[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[t][s] = label(grid[s], TARGETS[t]);
    }

    const X = try alloc.alloc([]f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT);
    var w: [MAXFEAT + 1]f64 = undefined;

    if (verbose) {
        try out.print("=== Fork 5: unified invention loop (forge → menu → world) ===\n\n", .{});
        try out.print("Target spec: structured {{kind, mask?, modulus?}} — not plain English yet.\n", .{});
        try out.print("Certifier: escape ≥{d:.2} held-out AND irreducible R²<{d:.2}.\n", .{ COVER, R2_MAX });
        try out.print("Library starts: 8 singleton monomials. Escalate per target when phase saturates.\n\n", .{});
    }

    const forge_only = innerForgeOnly(X, grid, Y, phiTgt, &w);
    var forge_solved: usize = 0;
    if (verbose) {
        try out.print("── inner_forge-only baseline (monomial closure) ──\n", .{});
        for (0..NT) |t| {
            const ok = forge_only[t] >= COVER;
            if (ok) forge_solved += 1;
            try out.print("  {s}: {d:.3}{s}\n", .{ TARGETS[t].name, forge_only[t], if (ok) " *" else "" });
        }
        try out.print("  → {d}/{d} solved\n\n", .{ forge_solved, NT });
    } else {
        for (0..NT) |t| {
            if (forge_only[t] >= COVER) {
                forge_solved += 1;
            }
        }
    }

    var lib: [MAXFEAT]Feature = undefined;
    var nlib: usize = 0;
    for (0..NCELL) |i| {
        lib[nlib] = .{ .monomial = @as(u8, 1) << @intCast(i) };
        nlib += 1;
    }

    var solved_by: [NT]Source = .{.base} ** NT;
    var unified_cov: [NT]f64 = .{0} ** NT;

    if (verbose) try out.print("── unified loop per target ──\n", .{});
    for (0..NT) |t| {
        const spec = TARGETS[t];
        if (verbose) try out.print("\n  TARGET: {s} [{s}]\n", .{ spec.name, @tagName(spec.kind) });

        var cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
        if (cov0 >= COVER) {
            unified_cov[t] = cov0;
            solved_by[t] = .base;
            if (verbose) try out.print("    already covered at {d:.3} by library\n", .{cov0});
            continue;
        }
        if (verbose) try out.print("    library coverage {d:.3} — escalating\n", .{cov0});

        var forge_round: usize = 0;
        while (forge_round < 6) : (forge_round += 1) {
            cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
            if (cov0 >= COVER) break;
            if (!(tryMonomialForge(X, grid, &lib, &nlib, Y[t], phiTgt, &w, out, !verbose) catch false)) break;
        }
        cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
        if (cov0 >= COVER) {
            unified_cov[t] = cov0;
            solved_by[t] = .forge;
            if (verbose) try out.print("    SOLVED by FORGE at {d:.3}\n", .{cov0});
            continue;
        }
        if (verbose) try out.print("    forge saturated at {d:.3}\n", .{cov0});

        if (tryOperatorMenu(X, grid, &lib, &nlib, Y[t], phiTgt, &w, out) catch false) {
            cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
            if (cov0 >= COVER) {
                unified_cov[t] = cov0;
                solved_by[t] = .menu;
                if (verbose) try out.print("    SOLVED by MENU at {d:.3}\n", .{cov0});
                continue;
            }
        }

        if (tryWorldPool(X, grid, &lib, &nlib, Y[t], phiTgt, &w, out) catch false) {
            cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
            if (cov0 >= COVER) solved_by[t] = .world;
        }
        unified_cov[t] = cov0;
        if (verbose) {
            if (cov0 >= COVER) {
                try out.print("    SOLVED by WORLD at {d:.3}\n", .{cov0});
            } else {
                try out.print("    UNSOLVED at {d:.3}\n", .{cov0});
            }
        }
    }

    var unified_solved: usize = 0;
    var delta_count: usize = 0;
    if (verbose) {
        try out.print("\n════════════════════ COMPARISON ════════════════════\n", .{});
        try out.print("{s:<32} | forge-only | unified | source\n", .{"target"});
        try out.print("{s}\n", .{"--------------------------------+------------+---------+--------"});
    }
    for (0..NT) |t| {
        const uok = unified_cov[t] >= COVER;
        if (uok) unified_solved += 1;
        const forge_ok = forge_only[t] >= COVER;
        const delta = uok and !forge_ok;
        if (delta) delta_count += 1;
        if (verbose) {
            try out.print("{s:<32} | {d:.3}{s}      | {d:.3}{s}   | {s}{s}\n", .{
                TARGETS[t].name,
                forge_only[t],
                if (forge_ok) "*" else " ",
                unified_cov[t],
                if (uok) "*" else " ",
                source_name[@intFromEnum(solved_by[t])],
                if (delta) " ← NEW" else "",
            });
        }
    }
    if (verbose) {
        try out.print("\ninner_forge alone: {d}/{d} solved\n", .{ forge_solved, NT });
        try out.print("unified loop:      {d}/{d} solved\n", .{ unified_solved, NT });
        try out.print("unified unlocks {d} target(s) inner_forge cannot: ", .{delta_count});
        var first = true;
        for (0..NT) |t| {
            if (unified_cov[t] >= COVER and forge_only[t] < COVER) {
                if (!first) try out.print(", ", .{});
                try out.print("{s}", .{TARGETS[t].name});
                first = false;
            }
        }
        try out.print("\n\nfinal library ({d} features): ", .{nlib});
        var keybuf: [48]u8 = undefined;
        for (0..nlib) |i| {
            if (i > 0) try out.print(", ", .{});
            try out.print("{s}", .{featureKey(&keybuf, lib[i])});
        }
        try out.print("\n\n════════════════════ AGI GAP (plain English) ════════════════════\n", .{});
        try out.print("Still missing for loose human language → certified invention:\n", .{});
        try out.print("  1. NL→TargetSpec parser: map \"cells above threshold parity\" → {{.parity_of_count}}\n", .{});
        try out.print("  2. Domain inference: is the user talking about grids, integers, text, commands?\n", .{});
        try out.print("  3. Negative/unknown intents: refuse when no certifiable escape exists\n", .{});
        try out.print("  4. Cross-domain library: unify grid monomials + number-theory mod_p in one ontology\n", .{});
        try out.print("  5. Compositional targets: \"parity AND sum divisible by 7\" needs multi-feature search\n", .{});
        try out.print("  6. Held-out protocol selection: train/val/test split must be stated or inferred\n", .{});
        try out.print("  7. Explanation: certified feature names are internal (φ, χ, mod_p), not user prose\n", .{});
        try out.print("\nSee: inner_forge.zig, operator_menu.zig, invention_engine.zig, world_injection.zig\n", .{});
    }

    return .{
        .forge_solved = forge_solved,
        .unified_solved = unified_solved,
        .delta_count = delta_count,
        .forge_cov = forge_only,
        .unified_cov = unified_cov,
        .solved_by = solved_by,
        .final_nlib = nlib,
    };
}

/// Guided unified loop: perceptron ranks candidates, certify only top-k per stage.
pub fn runGuidedBenchmark(
    alloc: std.mem.Allocator,
    out: anytype,
    seed: u64,
    verbose: bool,
    g: *guide.Guide,
    top_k: usize,
) !BenchMetrics {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const Y = try alloc.alloc([]f64, NT);
    for (0..NT) |t| {
        Y[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[t][s] = label(grid[s], TARGETS[t]);
    }

    const X = try alloc.alloc([]f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT);
    var w: [MAXFEAT + 1]f64 = undefined;

    var cost = CostCounter{};
    if (verbose) {
        try out.print("=== Guided unified invention (top-k={d}) ===\n\n", .{top_k});
    }

    var lib: [MAXFEAT]Feature = undefined;
    var nlib: usize = 0;
    for (0..NCELL) |i| {
        lib[nlib] = .{ .monomial = @as(u8, 1) << @intCast(i) };
        nlib += 1;
    }

    var solved_by: [NT]Source = .{.base} ** NT;
    var unified_cov: [NT]f64 = .{0} ** NT;

    for (0..NT) |t| {
        const spec = TARGETS[t];
        if (verbose) try out.print("  TARGET: {s}\n", .{spec.name});

        var cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
        if (cov0 >= COVER) {
            unified_cov[t] = cov0;
            solved_by[t] = .base;
            continue;
        }

        const hardness = targetHardness(grid, Y[t], phiTgt);
        cost.probe_calls += 2; // mono + extremal hardness probes

        var forge_round: usize = 0;
        while (forge_round < 6) : (forge_round += 1) {
            cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
            if (cov0 >= COVER) break;
            if (!(tryMonomialForgeGuided(X, grid, &lib, &nlib, Y[t], phiTgt, &w, hardness, g, top_k, &cost, out, !verbose) catch false)) break;
        }
        cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
        if (cov0 >= COVER) {
            unified_cov[t] = cov0;
            solved_by[t] = .forge;
            continue;
        }

        if (tryOperatorMenuGuided(X, grid, &lib, &nlib, Y[t], phiTgt, &w, hardness, g, &cost, out) catch false) {
            cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
            if (cov0 >= COVER) {
                unified_cov[t] = cov0;
                solved_by[t] = .menu;
                continue;
            }
        }

        if (tryWorldPoolGuided(X, grid, &lib, &nlib, Y[t], phiTgt, &w, hardness, g, guide.TOP_K_WORLD, &cost, out) catch false) {
            cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
            if (cov0 >= COVER) solved_by[t] = .world;
        }
        unified_cov[t] = cov0;
    }

    var unified_solved: usize = 0;
    var delta_count: usize = 0;
    const forge_only = innerForgeOnly(X, grid, Y, phiTgt, &w);
    for (0..NT) |t| {
        if (unified_cov[t] >= COVER) unified_solved += 1;
        if (unified_cov[t] >= COVER and forge_only[t] < COVER) delta_count += 1;
    }

    return .{
        .summary = .{
            .forge_solved = blk: {
                var fs: usize = 0;
                for (0..NT) |t| {
                    if (forge_only[t] >= COVER) fs += 1;
                }
                break :blk fs;
            },
            .unified_solved = unified_solved,
            .delta_count = delta_count,
            .forge_cov = forge_only,
            .unified_cov = unified_cov,
            .solved_by = solved_by,
            .final_nlib = nlib,
        },
        .certify_calls = cost.certify_calls,
        .probe_calls = cost.probe_calls,
        .forge_fits = cost.forge_fits,
    };
}

/// Bootstrap guide on routing battery (parity, sum_mod, monomial) before 7-target run.
pub fn bootstrapGuide(alloc: std.mem.Allocator, g: *guide.Guide, seed_base: u64) !void {
    const null_out = SilentOut{};

    const specs = [_]TargetSpec{
        .{ .name = "bootstrap-parity", .kind = .parity_of_count },
        .{ .name = "bootstrap-sum7", .kind = .sum_mod, .modulus = 7 },
        .{ .name = "bootstrap-mono", .kind = .monomial_sign, .mask = @as(u8, 1) << 3 },
    };

    var cost = CostCounter{};
    for (specs, 0..) |spec, i| {
        var prng = std.Random.DefaultPrng.init(seed_base +% @as(u64, @intCast(i)));
        const rand = prng.random();
        const grid = try alloc.alloc([NCELL]u8, NSAMP);
        for (0..NSAMP) |s| {
            for (0..NCELL) |j| grid[s][j] = rand.intRangeAtMost(u8, 0, VMAX);
        }
        const Y = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[s] = label(grid[s], spec);
        const X = try alloc.alloc([]f64, NSAMP);
        const phiTgt = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT);
        var w: [MAXFEAT + 1]f64 = undefined;
        var lib: [MAXFEAT]Feature = undefined;
        var nlib: usize = 0;
        for (0..NCELL) |j| {
            lib[nlib] = .{ .monomial = @as(u8, 1) << @intCast(j) };
            nlib += 1;
        }
        const hardness = targetHardness(grid, Y, phiTgt);
        cost.probe_calls += 2;
        _ = tryMonomialForgeGuided(X, grid, &lib, &nlib, Y, phiTgt, &w, hardness, g, guide.TOP_K_DEFAULT, &cost, null_out, true) catch false;
        _ = tryOperatorMenuGuided(X, grid, &lib, &nlib, Y, phiTgt, &w, hardness, g, &cost, null_out) catch false;
        _ = tryWorldPoolGuided(X, grid, &lib, &nlib, Y, phiTgt, &w, hardness, g, guide.TOP_K_DEFAULT, &cost, null_out) catch false;
    }
}

/// Baseline cost model: count certify calls in standard unified loop.
pub fn countBaselineCertify(alloc: std.mem.Allocator, seed: u64) !BenchMetrics {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| {
        for (0..NCELL) |ci| grid[s][ci] = rand.intRangeAtMost(u8, 0, VMAX);
    }
    const Y = try alloc.alloc([]f64, NT);
    for (0..NT) |t| {
        Y[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[t][s] = label(grid[s], TARGETS[t]);
    }
    const X = try alloc.alloc([]f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT);
    var w: [MAXFEAT + 1]f64 = undefined;

    var cost = CostCounter{};
    var lib: [MAXFEAT]Feature = undefined;
    var nlib: usize = 0;
    for (0..NCELL) |i| {
        lib[nlib] = .{ .monomial = @as(u8, 1) << @intCast(i) };
        nlib += 1;
    }

    const null_out = SilentOut{};

    var unified_cov: [NT]f64 = .{0} ** NT;
    var solved_by: [NT]Source = .{.base} ** NT;

    for (0..NT) |t| {
        var cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
        if (cov0 >= COVER) {
            unified_cov[t] = cov0;
            continue;
        }
        var forge_round: usize = 0;
        while (forge_round < 6) : (forge_round += 1) {
            cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
            if (cov0 >= COVER) break;
            // count: all mask fits + 1 certify per forge attempt
            var mm: u16 = 1;
            while (mm < 256) : (mm += 1) {
                const cand: u8 = @intCast(mm);
                const d = popcount(cand);
                if (d < 1 or d > MAXDEG) continue;
                if (hasFeature(lib[0..nlib], .{ .monomial = cand })) continue;
                cost.forge_fits += 1;
            }
            if (!(tryMonomialForge(X, grid, &lib, &nlib, Y[t], phiTgt, &w, null_out, true) catch false)) break;
            cost.certify_calls += 1;
        }
        cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
        if (cov0 >= COVER) {
            unified_cov[t] = cov0;
            solved_by[t] = .forge;
            continue;
        }
        if (tryOperatorMenu(X, grid, &lib, &nlib, Y[t], phiTgt, &w, null_out) catch false) {
            cost.certify_calls += 1;
            cost.probe_calls += 3;
            cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
            if (cov0 >= COVER) {
                unified_cov[t] = cov0;
                solved_by[t] = .menu;
                continue;
            }
        } else {
            cost.probe_calls += 3;
        }
        // world pool: certify all candidates
        var wc: usize = 0;
        for (WORLD_POOL) |p| {
            const pair = [_]Feature{ .{ .world_sum_mod = p }, .{ .world_sign_mod = p } };
            for (pair) |cand| {
                if (!hasFeature(lib[0..nlib], cand)) wc += 1;
            }
        }
        cost.certify_calls += wc;
        cost.probe_calls += wc;
        if (tryWorldPool(X, grid, &lib, &nlib, Y[t], phiTgt, &w, null_out) catch false) {}
        cov0 = coverage(X, grid, lib[0..nlib], Y[t], &w);
        unified_cov[t] = cov0;
        if (cov0 >= COVER) solved_by[t] = .world;
    }

    var unified_solved: usize = 0;
    const forge_only = innerForgeOnly(X, grid, Y, phiTgt, &w);
    for (0..NT) |t| {
        if (unified_cov[t] >= COVER) unified_solved += 1;
    }

    return .{
        .summary = .{
            .forge_solved = blk: {
                var fs: usize = 0;
                for (0..NT) |t| {
                    if (forge_only[t] >= COVER) fs += 1;
                }
                break :blk fs;
            },
            .unified_solved = unified_solved,
            .delta_count = 0,
            .forge_cov = forge_only,
            .unified_cov = unified_cov,
            .solved_by = solved_by,
            .final_nlib = nlib,
        },
        .certify_calls = cost.certify_calls,
        .probe_calls = cost.probe_calls,
        .forge_fits = cost.forge_fits,
    };
}

/// Run unified loop on one structured target (fresh library). Used by discover_feature.
pub fn runSingleTarget(
    alloc: std.mem.Allocator,
    out: anytype,
    spec: TargetSpec,
    seed: u64,
    verbose: bool,
) !struct { solved: bool, cov: f64, source: Source } {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const Y = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| Y[s] = label(grid[s], spec);

    const X = try alloc.alloc([]f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT);
    var w: [MAXFEAT + 1]f64 = undefined;

    var lib: [MAXFEAT]Feature = undefined;
    var nlib: usize = 0;
    for (0..NCELL) |i| {
        lib[nlib] = .{ .monomial = @as(u8, 1) << @intCast(i) };
        nlib += 1;
    }

    var source: Source = .base;
    if (verbose) try out.print("  unified discover [{s}]: escalating forge → menu → world\n", .{@tagName(spec.kind)});

    var cov0 = coverage(X, grid, lib[0..nlib], Y, &w);
    if (cov0 < COVER) {
        var forge_round: usize = 0;
        while (forge_round < 6) : (forge_round += 1) {
            cov0 = coverage(X, grid, lib[0..nlib], Y, &w);
            if (cov0 >= COVER) break;
            if (!(tryMonomialForge(X, grid, &lib, &nlib, Y, phiTgt, &w, out, !verbose) catch false)) break;
        }
        cov0 = coverage(X, grid, lib[0..nlib], Y, &w);
        if (cov0 >= COVER) source = .forge;
    }

    if (cov0 < COVER) {
        if (tryOperatorMenu(X, grid, &lib, &nlib, Y, phiTgt, &w, out) catch false) {
            cov0 = coverage(X, grid, lib[0..nlib], Y, &w);
            if (cov0 >= COVER) source = .menu;
        }
    }

    if (cov0 < COVER) {
        if (tryWorldPool(X, grid, &lib, &nlib, Y, phiTgt, &w, out) catch false) {
            cov0 = coverage(X, grid, lib[0..nlib], Y, &w);
            if (cov0 >= COVER) source = .world;
        }
    }

    return .{
        .solved = cov0 >= COVER,
        .cov = cov0,
        .source = if (cov0 >= COVER) source else .base,
    };
}

/// Stable fingerprint for a structured target (E12 / EXP-7 held-out splits).
pub fn specFingerprint(spec: TargetSpec) u64 {
    var h: u64 = @intFromEnum(spec.kind);
    h ^= @as(u64, spec.mask) *% 0x9E3779B97F4A7C15;
    h ^= @as(u64, spec.modulus) *% 0xC6A4A7935BD1E995;
    return h;
}

pub const SolveMetrics = struct {
    solved: bool,
    cov: f64,
    source: Source,
    iters_to_certify: usize,
    library_hit: bool,
    nlib_before: usize,
    nlib_after: usize,
};

/// Solve one target on a shared grid with a mutable feature library; count escalation steps.
fn solveOneTarget(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    phiTgt: []f64,
    w: []f64,
    out: anytype,
    quiet: bool,
) SolveMetrics {
    const nlib_before = nlib.*;
    var iters: usize = 0;
    var source: Source = .base;

    var cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
    if (cov0 >= COVER) {
        return .{
            .solved = true,
            .cov = cov0,
            .source = .base,
            .iters_to_certify = 0,
            .library_hit = true,
            .nlib_before = nlib_before,
            .nlib_after = nlib.*,
        };
    }

    var forge_round: usize = 0;
    while (forge_round < 6) : (forge_round += 1) {
        iters += 1;
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) {
            source = .forge;
            return .{
                .solved = true,
                .cov = cov0,
                .source = source,
                .iters_to_certify = iters,
                .library_hit = false,
                .nlib_before = nlib_before,
                .nlib_after = nlib.*,
            };
        }
        if (!(tryMonomialForge(X, grid, lib, nlib, Y, phiTgt, w, out, quiet) catch false)) break;
    }
    cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
    if (cov0 >= COVER) {
        source = .forge;
        return .{
            .solved = true,
            .cov = cov0,
            .source = source,
            .iters_to_certify = iters,
            .library_hit = false,
            .nlib_before = nlib_before,
            .nlib_after = nlib.*,
        };
    }

    iters += 1;
    if (tryOperatorMenu(X, grid, lib, nlib, Y, phiTgt, w, out) catch false) {
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) {
            source = .menu;
            return .{
                .solved = true,
                .cov = cov0,
                .source = source,
                .iters_to_certify = iters,
                .library_hit = false,
                .nlib_before = nlib_before,
                .nlib_after = nlib.*,
            };
        }
    }

    iters += 1;
    if (tryWorldPool(X, grid, lib, nlib, Y, phiTgt, w, out) catch false) {
        cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
        if (cov0 >= COVER) source = .world;
    }

    return .{
        .solved = cov0 >= COVER,
        .cov = cov0,
        .source = if (cov0 >= COVER) source else .base,
        .iters_to_certify = if (cov0 >= COVER) iters else iters,
        .library_hit = false,
        .nlib_before = nlib_before,
        .nlib_after = nlib.*,
    };
}

fn initMonomialLibrary(lib: []Feature, nlib: *usize) void {
    nlib.* = 0;
    for (0..NCELL) |i| {
        lib[nlib.*] = .{ .monomial = @as(u8, 1) << @intCast(i) };
        nlib.* += 1;
    }
}

pub const HeldOutGenResult = struct {
    fingerprint: u64,
    name: []const u8,
    cold_iters: usize,
    warm_iters: usize,
    cold_solved: bool,
    warm_solved: bool,
    warm_library_hit: bool,
    warm_source: Source,
    cold_cov: f64,
    warm_cov: f64,
};

pub const VerifyLearnGenSummary = struct {
    curriculum_len: usize,
    curriculum_solved: usize,
    curriculum_iters_sum: usize,
    held_out_len: usize,
    held_out: []HeldOutGenResult,
    cold_iters_mean: f64,
    warm_iters_mean: f64,
    iters_delta_mean: f64,
    library_hits: usize,
    compositional_generalization: bool,
    final_nlib: usize,
};

/// EXP-7: curriculum of certified discovery episodes → measure iters-to-certify on held-out spec hashes.
pub fn runVerifyLearnGenBenchmark(
    alloc: std.mem.Allocator,
    out: anytype,
    curriculum: []const TargetSpec,
    held_out: []const TargetSpec,
    seed: u64,
    verbose: bool,
) !VerifyLearnGenSummary {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const Y_cur = try alloc.alloc([]f64, curriculum.len);
    for (0..curriculum.len) |t| {
        Y_cur[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y_cur[t][s] = label(grid[s], curriculum[t]);
    }
    const Y_held = try alloc.alloc([]f64, held_out.len);
    for (0..held_out.len) |t| {
        Y_held[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y_held[t][s] = label(grid[s], held_out[t]);
    }

    const X = try alloc.alloc([]f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT);
    var w: [MAXFEAT + 1]f64 = undefined;

    // ── Cold baseline: fresh library per held-out target ──
    const held_results = try alloc.alloc(HeldOutGenResult, held_out.len);
    var cold_iters_sum: usize = 0;
    var cold_solved_count: usize = 0;

    if (verbose) try out.print("── Cold baseline (fresh 8-monomial library per held-out) ──\n", .{});
    for (0..held_out.len) |t| {
        var lib: [MAXFEAT]Feature = undefined;
        var nlib: usize = 0;
        initMonomialLibrary(&lib, &nlib);
        const m = solveOneTarget(X, grid, &lib, &nlib, Y_held[t], phiTgt, &w, SilentOut{}, true);
        cold_iters_sum += m.iters_to_certify;
        if (m.solved) cold_solved_count += 1;
        held_results[t] = .{
            .fingerprint = specFingerprint(held_out[t]),
            .name = held_out[t].name,
            .cold_iters = m.iters_to_certify,
            .warm_iters = 0,
            .cold_solved = m.solved,
            .warm_solved = false,
            .warm_library_hit = false,
            .warm_source = .base,
            .cold_cov = m.cov,
            .warm_cov = 0,
        };
        if (verbose) {
            try out.print("  {s} fp=0x{X:0>16} cold iters={d} cov={d:.3} {s}\n", .{
                held_out[t].name,
                held_results[t].fingerprint,
                m.iters_to_certify,
                m.cov,
                if (m.solved) "CERTIFIED" else "failed",
            });
        }
    }

    // ── Curriculum: certified discovery episodes (persistent library) ──
    var lib: [MAXFEAT]Feature = undefined;
    var nlib: usize = 0;
    initMonomialLibrary(&lib, &nlib);

    var curriculum_solved: usize = 0;
    var curriculum_iters_sum: usize = 0;
    if (verbose) try out.print("\n── Curriculum ({d} hidden specs, promote→reuse) ──\n", .{curriculum.len});
    for (0..curriculum.len) |t| {
        const m = solveOneTarget(X, grid, &lib, &nlib, Y_cur[t], phiTgt, &w, out, !verbose);
        curriculum_iters_sum += m.iters_to_certify;
        if (m.solved) curriculum_solved += 1;
        if (verbose) {
            try out.print("  [{d:>2}] {s} fp=0x{X:0>16} iters={d} lib {d}→{d} {s}{s}\n", .{
                t + 1,
                curriculum[t].name,
                specFingerprint(curriculum[t]),
                m.iters_to_certify,
                m.nlib_before,
                m.nlib_after,
                if (m.solved) "CERTIFIED" else "failed",
                if (m.library_hit) " (library)" else "",
            });
        }
    }

    // ── Warm held-out: same library after curriculum ──
    var warm_iters_sum: usize = 0;
    var warm_solved_count: usize = 0;
    var library_hits: usize = 0;
    if (verbose) try out.print("\n── Warm held-out (library={d} features after curriculum) ──\n", .{nlib});
    for (0..held_out.len) |t| {
        const nlib_before = nlib;
        const m = solveOneTarget(X, grid, &lib, &nlib, Y_held[t], phiTgt, &w, SilentOut{}, true);
        warm_iters_sum += m.iters_to_certify;
        if (m.solved) warm_solved_count += 1;
        if (m.library_hit) library_hits += 1;
        held_results[t].warm_iters = m.iters_to_certify;
        held_results[t].warm_solved = m.solved;
        held_results[t].warm_library_hit = m.library_hit;
        held_results[t].warm_source = m.source;
        held_results[t].warm_cov = m.cov;
        if (verbose) {
            try out.print("  {s} fp=0x{X:0>16} warm iters={d} (Δ={d}) cov={d:.3} {s}{s}\n", .{
                held_out[t].name,
                held_results[t].fingerprint,
                m.iters_to_certify,
                @as(i64, @intCast(held_results[t].cold_iters)) - @as(i64, @intCast(m.iters_to_certify)),
                m.cov,
                if (m.solved) "CERTIFIED" else "failed",
                if (m.library_hit) " LIBRARY_HIT" else "",
            });
        }
        _ = nlib_before;
    }

    const ho = @as(f64, @floatFromInt(held_out.len));
    const cold_mean = @as(f64, @floatFromInt(cold_iters_sum)) / ho;
    const warm_mean = @as(f64, @floatFromInt(warm_iters_sum)) / ho;
    const delta_mean = cold_mean - warm_mean;
    const compositional = library_hits > 0 or (delta_mean >= 1.0 and warm_solved_count >= cold_solved_count);

    return .{
        .curriculum_len = curriculum.len,
        .curriculum_solved = curriculum_solved,
        .curriculum_iters_sum = curriculum_iters_sum,
        .held_out_len = held_out.len,
        .held_out = held_results,
        .cold_iters_mean = cold_mean,
        .warm_iters_mean = warm_mean,
        .iters_delta_mean = delta_mean,
        .library_hits = library_hits,
        .compositional_generalization = compositional,
        .final_nlib = nlib,
    };
}

pub const SequentialTargetResult = struct {
    solved: bool,
    cov: f64,
    source: Source,
    nlib_before: usize,
    nlib_after: usize,
};

pub const SequentialSummary = struct {
    results: []SequentialTargetResult,
    final_nlib: usize,
};

/// Run unified loop on multiple targets with a **persistent** feature library (promote → reuse).
pub fn runSequentialTargets(
    alloc: std.mem.Allocator,
    out: anytype,
    specs: []const TargetSpec,
    seed: u64,
    verbose: bool,
) !SequentialSummary {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const Y = try alloc.alloc([]f64, specs.len);
    for (0..specs.len) |t| {
        Y[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[t][s] = label(grid[s], specs[t]);
    }

    const X = try alloc.alloc([]f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT);
    var w: [MAXFEAT + 1]f64 = undefined;

    var lib: [MAXFEAT]Feature = undefined;
    var nlib: usize = 0;
    initMonomialLibrary(&lib, &nlib);

    const results = try alloc.alloc(SequentialTargetResult, specs.len);
    for (0..specs.len) |t| {
        const spec = specs[t];
        if (verbose) try out.print("  sequential [{s}]: library={d} features\n", .{ spec.name, nlib });
        const m = solveOneTarget(X, grid, &lib, &nlib, Y[t], phiTgt, &w, out, !verbose);
        results[t] = .{
            .solved = m.solved,
            .cov = m.cov,
            .source = m.source,
            .nlib_before = m.nlib_before,
            .nlib_after = m.nlib_after,
        };
        if (verbose) {
            if (m.solved) {
                try out.print("    SOLVED {s} {d:.3} library→{d}{s}\n", .{
                    source_name[@intFromEnum(m.source)],
                    m.cov,
                    nlib,
                    if (m.library_hit) " (library)" else "",
                });
            } else {
                try out.print("    UNSOLVED {d:.3}\n", .{m.cov});
            }
        }
    }

    return .{ .results = results, .final_nlib = nlib };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    _ = try runFullBenchmark(alloc, out, 0xF0235A11CE0FF1CE, true);
}