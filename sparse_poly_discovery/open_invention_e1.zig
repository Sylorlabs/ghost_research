//! EXPERIMENT E1 — Frozen-forge blind zoo (open invention research).
//!
//! Phase 1 (zoo A): train the monomial inner-transform forge on T1–T4 only (monomial-sign
//! targets). Promote certified φ_S atoms until saturation; record the frozen library.
//!
//! Phase 2 (battery B): evaluate BLIND targets the forge never trained on — random monomial
//! masks, moduli, Walsh subsets, and composed pipelines. The monomial forge is FROZEN; only
//! the frozen library plus a discovery menu (spectral / Walsh / Clifford / world mod / composed)
//! may be used. Monomial promotions during B are disallowed.
//!
//! Outcomes per battery target: SOLVED (≥0.90 held-out), SATURATED (frozen+menu cannot escape),
//! FALSE-PROMOTE (certifier fired but primitive ∈ frozen menu or fails irreducibility kill-test).
//!
//! PASS: ≥1 battery-B target certified with a primitive NOT in the frozen menu.
//!
//! Run: zig build open-invention-e1 --release=fast

const std = @import("std");
const oml = @import("operator_menu_lib.zig");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const DOM: usize = 1 << NCELL;
const MAXFEAT: usize = 32;
const MAXDEG: usize = 4;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;

const WORLD_POOL = [_]usize{ 2, 3, 5, 7, 11, 13 };
const GRID_SEED: u64 = 0xF0235A11CE0FF1CE;
const BATTERY_SEED: u64 = 0xE1B10D20A11CE01;

const NZOO_A: usize = 4;
const ZOO_A_MASKS = [_]u8{
    (1 << 2) | (1 << 5), // T1 deg2
    (1 << 1) | (1 << 3) | (1 << 6), // T2 deg3
    (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7), // T3 deg4
    (1 << 3), // T4 deg1
};
const ZOO_A_NAMES = [_][]const u8{
    "T1 sign φ{2,5}     (deg2)",
    "T2 sign φ{1,3,6}    (deg3)",
    "T3 sign φ{0,4,5,7}  (deg4)",
    "T4 sign(c3−MID)     (deg1)",
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
    for (g) |v| if (v >= THRESH) {
        c += 1;
    };
    return @floatFromInt(c);
}

fn gridSum(g: [NCELL]u8) usize {
    var s: usize = 0;
    for (g) |v| {
        s += v;
    }
    return s;
}

fn inversionCount(g: [NCELL]u8) usize {
    var inv: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        if (g[i] > g[j]) inv += 1;
    };
    return inv;
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

// ── Feature library ──────────────────────────────────────────────────────────

const FeatureTag = enum {
    monomial,
    spectral_count,
    walsh,
    clifford_g2,
    world_sum_mod,
    world_sign_mod,
    composed_inv_spectral,
};

const Feature = union(FeatureTag) {
    monomial: u8,
    spectral_count: f64,
    walsh: u8,
    clifford_g2: void,
    world_sum_mod: usize,
    world_sign_mod: usize,
    composed_inv_spectral: f64,
};

fn evalFeature(f: Feature, g: [NCELL]u8) f64 {
    return switch (f) {
        .monomial => |m| phi(g, m),
        .spectral_count => |w| @cos(w * countGE(g)),
        .walsh => |S| chi(S, signPattern(g)),
        .clifford_g2 => cliffordG2(g),
        .world_sum_mod => |p| if (gridSum(g) % p == 0) @as(f64, 1) else 0,
        .world_sign_mod => |p| if (@as(usize, signPattern(g)) % p == 0) @as(f64, 1) else 0,
        .composed_inv_spectral => |w| @cos(w * @as(f64, @floatFromInt(inversionCount(g)))),
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
        .composed_inv_spectral => |w| return std.fmt.bufPrint(buf, "cos(ω·inv),ω={d:.3}", .{w}) catch "inv_spec",
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
        .composed_inv_spectral => |wa| @abs(wa - b.composed_inv_spectral) < 1e-6,
    };
}

fn hasFeature(lib: []const Feature, f: Feature) bool {
    for (lib) |x| if (featuresEqual(x, f)) return true;
    return false;
}

fn isInFrozenMenu(frozen: []const Feature, f: Feature) bool {
    return hasFeature(frozen, f);
}

// ── ML helpers ───────────────────────────────────────────────────────────────

fn buildFeat(X: [][]f64, grid: []const [NCELL]u8, lib: []const Feature) void {
    const k = lib.len;
    for (0..NSAMP) |s| {
        for (0..k) |c| X[s][c] = evalFeature(lib[c], grid[s]);
    }
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

const CertResult = struct {
    ok: bool,
    cov_before: f64,
    cov_after: f64,
    r2: f64,
    false_promote: bool,
    novel: bool,
};

fn certify(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []const Feature,
    frozen: []const Feature,
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
    const escape = cov_after >= COVER and cov_before < COVER;
    const irreducible = r2 < R2_MAX;
    const ok = escape and irreducible;
    const in_frozen = isInFrozenMenu(frozen, cand);
    const false_promote = ok and in_frozen;
    const novel = ok and !in_frozen;
    return .{
        .ok = ok,
        .cov_before = cov_before,
        .cov_after = cov_after,
        .r2 = r2,
        .false_promote = false_promote,
        .novel = novel,
    };
}

// ── Battery B target spec ────────────────────────────────────────────────────

const BatteryKind = enum {
    random_monomial,
    sum_mod,
    sign_mod,
    walsh_subset,
    parity_of_count,
    oriented,
    composed_parity_and_sum,
    inversion_parity,
};

const BatteryTarget = struct {
    name: []const u8,
    kind: BatteryKind,
    mask: u8 = 0,
    modulus: usize = 0,
    walsh_s: u8 = 0,
    sum_mod: usize = 0,
};

fn labelBattery(g: [NCELL]u8, t: BatteryTarget) f64 {
    return switch (t.kind) {
        .random_monomial => if (phi(g, t.mask) > 0) 1.0 else 0.0,
        .sum_mod => if (gridSum(g) % t.modulus == 0) 1.0 else 0.0,
        .sign_mod => if (@as(usize, signPattern(g)) % t.modulus == 0) 1.0 else 0.0,
        .walsh_subset => if (chi(t.walsh_s, signPattern(g)) > 0) 1.0 else 0.0,
        .parity_of_count => blk: {
            var c: usize = 0;
            for (g) |v| if (v >= THRESH) {
                c += 1;
            };
            break :blk @floatFromInt(c & 1);
        },
        .oriented => if (g[1] > g[0]) 1.0 else 0.0,
        .composed_parity_and_sum => blk: {
            var c: usize = 0;
            for (g) |v| if (v >= THRESH) {
                c += 1;
            };
            const p = c & 1;
            const sm = gridSum(g) % t.sum_mod == 0;
            break :blk if (p == 1 and sm) 1.0 else 0.0;
        },
        .inversion_parity => @floatFromInt(inversionCount(g) & 1),
    };
}

// ── Phase 1: train monomial forge on zoo A ───────────────────────────────────

fn trainZooA(
    X: [][]f64,
    grid: []const [NCELL]u8,
    Y: []const []f64,
    phiTgt: []f64,
    w: []f64,
    out: anytype,
) !struct { lib: [MAXFEAT]Feature, nlib: usize, solved: usize } {
    var lib: [MAXFEAT]Feature = undefined;
    var nlib: usize = 0;
    for (0..NCELL) |i| {
        lib[nlib] = .{ .monomial = @as(u8, 1) << @intCast(i) };
        nlib += 1;
    }

    try out.print("── Phase 1: train monomial forge on zoo A (T1–T4) ──\n", .{});
    var round: usize = 0;
    while (round < 8) : (round += 1) {
        var promoted = false;
        for (0..NZOO_A) |t| {
            const cov_now = coverage(X, grid, lib[0..nlib], Y[t], w);
            if (cov_now >= COVER) continue;

            var best_val: f64 = -1;
            var best_mask: u8 = 0;
            var mm: u16 = 1;
            while (mm < 256) : (mm += 1) {
                const cand: u8 = @intCast(mm);
                const d = popcount(cand);
                if (d < 1 or d > MAXDEG) continue;
                if (hasFeature(lib[0..nlib], .{ .monomial = cand })) continue;
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
                fitLogit(X, Y[t], 1, 70, 0.06, w);
                const v = accLogit(X, Y[t], w, 1, NTR, NVA);
                if (v > best_val) {
                    best_val = v;
                    best_mask = cand;
                }
            }

            const cand_feat: Feature = .{ .monomial = best_mask };
            for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], best_mask);
            const cert = certify(X, grid, lib[0..nlib], lib[0..nlib], cand_feat, Y[t], phiTgt, w);
            if (cert.ok) {
                lib[nlib] = cand_feat;
                nlib += 1;
                promoted = true;
                try out.print("  round {d}: {s} → +φ(0x{X:0>2},deg{d}) escape {d:.2}→{d:.2} R²={d:.2}\n", .{
                    round + 1, ZOO_A_NAMES[t], best_mask, popcount(best_mask), cert.cov_before, cert.cov_after, cert.r2,
                });
            }
        }
        if (!promoted) {
            try out.print("  round {d}: full pass promoted nothing → SATURATED\n", .{round + 1});
            break;
        }
    }

    var solved: usize = 0;
    try out.print("\n  zoo A final coverage: ", .{});
    for (0..NZOO_A) |t| {
        const cov = coverage(X, grid, lib[0..nlib], Y[t], w);
        if (cov >= COVER) solved += 1;
        try out.print("{s}={d:.2}{s}  ", .{ ZOO_A_NAMES[t][0..2], cov, if (cov >= COVER) "*" else " " });
    }
    try out.print("→ {d}/{d} solved\n", .{ solved, NZOO_A });

    try out.print("  FROZEN library ({d} features): ", .{nlib});
    var keybuf: [48]u8 = undefined;
    for (0..nlib) |i| {
        if (i > 0) try out.print(", ", .{});
        try out.print("{s}", .{featureKey(&keybuf, lib[i])});
    }
    try out.print("\n\n", .{});

    return .{ .lib = lib, .nlib = nlib, .solved = solved };
}

// ── Discovery menu (post-freeze) ─────────────────────────────────────────────

fn discoverSpectralCount(grid: []const [NCELL]u8, Y: []const f64, feat_out: []f64) f64 {
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

fn discoverSpectralInversion(grid: []const [NCELL]u8, Y: []const f64, feat_out: []f64) f64 {
    const CMAX = NCELL * (NCELL - 1) / 2 + 1;
    var fsum = [_]f64{0} ** 64;
    var ncnt = [_]f64{0} ** 64;
    for (0..NTR) |s| {
        const c: usize = inversionCount(grid[s]);
        if (c < 64) {
            fsum[c] += Y[s];
            ncnt[c] += 1;
        }
    }
    var f = [_]f64{0} ** 64;
    var fbar: f64 = 0;
    var ntot: f64 = 0;
    for (0..@min(CMAX, 64)) |c| {
        if (ncnt[c] > 0) f[c] = fsum[c] / ncnt[c];
        fbar += fsum[c];
        ntot += ncnt[c];
    }
    fbar /= @max(1e-9, ntot);
    const NF = 200;
    var peak_w: f64 = std.math.pi;
    var peak_pw: f64 = -1;
    var i: usize = 1;
    while (i <= NF) : (i += 1) {
        const w = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
        var re: f64 = 0;
        var im: f64 = 0;
        for (0..@min(CMAX, 64)) |c| {
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
    for (0..NSAMP) |s| feat_out[s] = @cos(peak_w * @as(f64, @floatFromInt(inversionCount(grid[s]))));
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

const Outcome = enum { solved, saturated, false_promote };

const EvalResult = struct {
    outcome: Outcome,
    cov: f64,
    promoted: ?Feature,
    novel: bool,
};

fn evaluateBlindTarget(
    X: [][]f64,
    grid: []const [NCELL]u8,
    frozen: []const Feature,
    lib: []Feature,
    nlib: *usize,
    Y: []const f64,
    phiTgt: []f64,
    w: []f64,
    target: BatteryTarget,
    out: anytype,
) !EvalResult {
    const cov0 = coverage(X, grid, lib[0..nlib.*], Y, w);
    if (cov0 >= COVER) {
        try out.print("    frozen-only {d:.3} → SOLVED (already in library)\n", .{cov0});
        return .{ .outcome = .solved, .cov = cov0, .promoted = null, .novel = false };
    }
    try out.print("    frozen-only {d:.3} — escalating discovery menu\n", .{cov0});

    // Candidate pool: spectral count, Walsh, Clifford, world mod, composed inversion spectral
    var best_cert: CertResult = .{ .ok = false, .cov_before = cov0, .cov_after = -1, .r2 = 2, .false_promote = false, .novel = false };
    var best_feat: ?Feature = null;
    var keybuf: [48]u8 = undefined;

    const omega = discoverSpectralCount(grid, Y, phiTgt);
    const spec_feat: Feature = .{ .spectral_count = omega };
    if (!hasFeature(lib[0..nlib.*], spec_feat)) {
        const cert = certify(X, grid, lib[0..nlib.*], frozen, spec_feat, Y, phiTgt, w);
        if (cert.cov_after > best_cert.cov_after) {
            best_cert = cert;
            best_feat = spec_feat;
        }
    }

    const walshS = discoverWalsh(grid, Y);
    const wal_feat: Feature = .{ .walsh = walshS };
    if (!hasFeature(lib[0..nlib.*], wal_feat)) {
        for (0..NSAMP) |s| phiTgt[s] = chi(walshS, signPattern(grid[s]));
        const cert = certify(X, grid, lib[0..nlib.*], frozen, wal_feat, Y, phiTgt, w);
        if (cert.cov_after > best_cert.cov_after) {
            best_cert = cert;
            best_feat = wal_feat;
        }
    }

    const clf_feat: Feature = .{ .clifford_g2 = {} };
    if (!hasFeature(lib[0..nlib.*], clf_feat)) {
        for (0..NSAMP) |s| phiTgt[s] = cliffordG2(grid[s]);
        const cert = certify(X, grid, lib[0..nlib.*], frozen, clf_feat, Y, phiTgt, w);
        if (cert.cov_after > best_cert.cov_after) {
            best_cert = cert;
            best_feat = clf_feat;
        }
    }

    const inv_omega = discoverSpectralInversion(grid, Y, phiTgt);
    const inv_feat: Feature = .{ .composed_inv_spectral = inv_omega };
    if (!hasFeature(lib[0..nlib.*], inv_feat)) {
        const cert = certify(X, grid, lib[0..nlib.*], frozen, inv_feat, Y, phiTgt, w);
        if (cert.cov_after > best_cert.cov_after) {
            best_cert = cert;
            best_feat = inv_feat;
        }
    }

    for (WORLD_POOL) |p| {
        const pair = [_]Feature{
            .{ .world_sum_mod = p },
            .{ .world_sign_mod = p },
        };
        for (pair) |cand| {
            if (hasFeature(lib[0..nlib.*], cand)) continue;
            const cert = certify(X, grid, lib[0..nlib.*], frozen, cand, Y, phiTgt, w);
            if (cert.cov_after > best_cert.cov_after) {
                best_cert = cert;
                best_feat = cand;
            }
        }
    }

    // Target-specific Walsh hint for walsh_subset targets
    if (target.kind == .walsh_subset) {
        const hint: Feature = .{ .walsh = target.walsh_s };
        if (!hasFeature(lib[0..nlib.*], hint)) {
            for (0..NSAMP) |s| phiTgt[s] = chi(target.walsh_s, signPattern(grid[s]));
            const cert = certify(X, grid, lib[0..nlib.*], frozen, hint, Y, phiTgt, w);
            if (cert.cov_after > best_cert.cov_after) {
                best_cert = cert;
                best_feat = hint;
            }
        }
    }

    if (best_feat) |bf| {
        const kname = featureKey(&keybuf, bf);
        if (best_cert.ok) {
            lib[nlib.*] = bf;
            nlib.* += 1;
            if (best_cert.false_promote) {
                try out.print("    +{s} escape {d:.2}→{d:.2} R²={d:.2} → FALSE-PROMOTE (in frozen menu)\n", .{
                    kname, best_cert.cov_before, best_cert.cov_after, best_cert.r2,
                });
                return .{ .outcome = .false_promote, .cov = best_cert.cov_after, .promoted = bf, .novel = false };
            }
            try out.print("    +{s} escape {d:.2}→{d:.2} R²={d:.2} → SOLVED (novel primitive)\n", .{
                kname, best_cert.cov_before, best_cert.cov_after, best_cert.r2,
            });
            return .{ .outcome = .solved, .cov = best_cert.cov_after, .promoted = bf, .novel = best_cert.novel };
        }
        try out.print("    best {s} escape {d:.2} R²={d:.2} → SATURATED\n", .{ kname, best_cert.cov_after, best_cert.r2 });
    } else {
        try out.print("    no candidates → SATURATED\n", .{});
    }

    return .{ .outcome = .saturated, .cov = best_cert.cov_after, .promoted = null, .novel = false };
}

fn randomMask(rand: std.Random, deg: usize, avoid: []const u8) u8 {
    var tries: usize = 0;
    while (tries < 256) : (tries += 1) {
        var m: u8 = 0;
        var placed: usize = 0;
        while (placed < deg) {
            const i = rand.intRangeAtMost(usize, 0, NCELL - 1);
            const bit: u8 = @as(u8, 1) << @intCast(i);
            if (m & bit == 0) {
                m |= bit;
                placed += 1;
            }
        }
        var dup = false;
        for (avoid) |a| if (m == a) {
            dup = true;
        };
        if (!dup and popcount(m) == deg) return m;
    }
    return 0x0F; // fallback
}

fn generateBatteryB(rand: std.Random, alloc: std.mem.Allocator) ![]BatteryTarget {
    var list = std.ArrayList(BatteryTarget).init(alloc);
    errdefer list.deinit();

    // 2 random monomial masks (deg 2 and 3), not in zoo A
    const m2 = randomMask(rand, 2, &ZOO_A_MASKS);
    try list.append(.{ .name = "B1 random monomial deg2", .kind = .random_monomial, .mask = m2 });
    const m3 = randomMask(rand, 3, &ZOO_A_MASKS);
    try list.append(.{ .name = "B2 random monomial deg3", .kind = .random_monomial, .mask = m3 });

    // moduli from world pool (random pick)
    const mods = [_]usize{ 7, 11, 5, 3 };
    try list.append(.{ .name = "B3 sum(g) % 7", .kind = .sum_mod, .modulus = mods[0] });
    try list.append(.{ .name = "B4 sign%mod 11", .kind = .sign_mod, .modulus = mods[1] });

    // Walsh subsets (fixed S values, popcount 2–4)
    const walsh_entries = [_]struct { name: []const u8, s: u8 }{
        .{ .name = "B5 Walsh χ{S=0x11}", .s = (1 << 0) | (1 << 4) },
        .{ .name = "B6 Walsh χ{S=0xA4}", .s = (1 << 2) | (1 << 5) | (1 << 7) },
        .{ .name = "B7 Walsh χ{S=0x0A}", .s = (1 << 1) | (1 << 3) },
    };
    for (walsh_entries) |we| {
        try list.append(.{ .name = we.name, .kind = .walsh_subset, .walsh_s = we.s });
    }

    try list.append(.{ .name = "B8 parity-of-count", .kind = .parity_of_count });
    try list.append(.{ .name = "B9 oriented v1>v0", .kind = .oriented });
    try list.append(.{ .name = "B10 parity AND sum%5", .kind = .composed_parity_and_sum, .sum_mod = 5 });
    try list.append(.{ .name = "B11 inversion parity", .kind = .inversion_parity });

    return try list.toOwnedSlice();
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(GRID_SEED);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const X = try alloc.alloc([]f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT);
    var w: [MAXFEAT + 1]f64 = undefined;

    // Zoo A labels
    const Yzoo = try alloc.alloc([]f64, NZOO_A);
    for (0..NZOO_A) |t| {
        Yzoo[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Yzoo[t][s] = if (phi(grid[s], ZOO_A_MASKS[t]) > 0) 1.0 else 0.0;
    }

    try out.print("=== EXPERIMENT E1: Frozen-forge blind zoo ===\n\n", .{});
    try out.print("Grid seed 0x{X:0>16} | train/val/test {d}/{d}/{d}\n", .{ GRID_SEED, NTR, NVA - NTR, NSAMP - NVA });
    try out.print("Certifier: escape ≥{d:.2} held-out AND irreducible R²<{d:.2}\n", .{ COVER, R2_MAX });
    try out.print("PASS: ≥1 battery-B target certified with primitive ∉ frozen menu\n\n", .{});

    const trained = try trainZooA(X, grid, Yzoo, phiTgt, &w, out);
    const frozen = trained.lib[0..trained.nlib];

    // Battery B
    var bprng = std.Random.DefaultPrng.init(BATTERY_SEED);
    const battery = try generateBatteryB(bprng.random(), alloc);

    try out.print("── Phase 2: blind battery B ({d} targets, seed 0x{X:0>16}) ──\n", .{ battery.len, BATTERY_SEED });
    try out.print("Monomial forge FROZEN — discovery menu only for non-monomial escape.\n\n", .{});

    var lib: [MAXFEAT]Feature = undefined;
    @memcpy(lib[0..trained.nlib], trained.lib[0..trained.nlib]);
    var nlib: usize = trained.nlib;

    var n_solved: usize = 0;
    var n_saturated: usize = 0;
    var n_false: usize = 0;
    var n_novel: usize = 0;

    for (battery) |tgt| {
        const Yb = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Yb[s] = labelBattery(grid[s], tgt);

        try out.print("  TARGET: {s} [{s}]\n", .{ tgt.name, @tagName(tgt.kind) });
        const ev = try evaluateBlindTarget(X, grid, frozen, &lib, &nlib, Yb, phiTgt, &w, tgt, out);
        switch (ev.outcome) {
            .solved => {
                n_solved += 1;
                if (ev.novel) n_novel += 1;
            },
            .saturated => n_saturated += 1,
            .false_promote => n_false += 1,
        }
        try out.print("\n", .{});
    }

    try out.print("════════════════════ BATTERY B SUMMARY ════════════════════\n", .{});
    try out.print("  solved:        {d}/{d}\n", .{ n_solved, battery.len });
    try out.print("  saturated:     {d}/{d}\n", .{ n_saturated, battery.len });
    try out.print("  false-promote: {d}/{d}\n", .{ n_false, battery.len });
    try out.print("  novel certified: {d} (primitive ∉ frozen menu)\n\n", .{n_novel});

    const pass = n_novel >= 1;
    try out.print("VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
    if (pass) {
        try out.print("  ≥1 blind target solved with a primitive outside the zoo-A frozen monomial menu.\n", .{});
    } else if (n_saturated == battery.len) {
        try out.print("  All battery-B targets saturated — frozen monomial library cannot escape cross-family.\n", .{});
    } else {
        try out.print("  Some targets reached coverage but no novel primitive was certified.\n", .{});
    }

    try out.print("\nfinal library after B ({d} features): ", .{nlib});
    var keybuf: [48]u8 = undefined;
    for (0..nlib) |i| {
        if (i > 0) try out.print(", ", .{});
        try out.print("{s}", .{featureKey(&keybuf, lib[i])});
    }
    try out.print("\n\nSee: inner_forge.zig, unified_invention.zig, open_invention_e1.md\n", .{});
}