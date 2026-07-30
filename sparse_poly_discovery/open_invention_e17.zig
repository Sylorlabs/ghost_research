//! EXPERIMENT E17 — pipeline grammar invention (E5++).
//!
//! Meta-search 2-3 stage grammars on composed_discovery training families, then certify on
//! 50 held-out composed targets (RQ5 extended). Extends E5's fixed inner₁→inner₂ menu with
//! optional inner_mid transforms: inner₁→inner_mid→inner₃→readout.
//!
//! Pass bar: ≥35/50 certified (escape ≥0.90 test, stage-1 <0.70); ≥2 novel stage compositions
//! not representable as E5 2-stage templates (inner_mid ≠ relay).
//!
//! Reuses protocol/constants from open_invention_e5.zig and open_invention_rq5.zig.
//!
//! Run: zig build open-invention-e17 --release=fast

const std = @import("std");
const e5 = @import("open_invention_e5.zig");
const rq5 = @import("open_invention_rq5.zig");

const NCELL = e5.NCELL;
const VMAX = e5.VMAX;
const NSAMP = e5.NSAMP;
const NTR = e5.NTR;
const NVA = e5.NVA;
const COVER = e5.COVER;
const STAGE1_MAX = e5.STAGE1_MAX;
const N_INNER1 = e5.N_INNER1;
const N_INNER2 = e5.N_INNER2;

const Inner1 = e5.Inner1;
const Inner2 = e5.Inner2;
const inner1_name = e5.inner1_name;
const inner2_name = e5.inner2_name;

const N_HELDOUT: usize = 50;
const PASS_MIN: usize = 35;
const NOVEL_MIN: usize = 2;
const HELDOUT_SEED: u64 = 0xE17C0110BA5E50;
const GRID_SEED: u64 = rq5.GRID_SEED;

// ── Stage-mid: grid (+T) → scalar S — novel 3-stage glue not in E5 inner₂ ───

const InnerMid = enum {
    relay, // S = T (degenerates to 2-stage)
    inversion,
    pair_prod,
    spread,
    delta01,
    bind_T_sum01, // S = T * (c0+c1)
    parity_sum, // S = (sum g) mod 2
};
const N_MID = 7;
const mid_name = [_][]const u8{
    "relay(T)",
    "inversion",
    "pair_prod(c0·c1)",
    "spread(max−min)",
    "delta01|Δ01|",
    "bind_T·sum01",
    "parity_sum",
};

fn innerMidScalar(mid: InnerMid, T: f64, g: [NCELL]u8) f64 {
    return switch (mid) {
        .relay => T,
        .inversion => blk: {
            var inv: usize = 0;
            for (0..NCELL) |i| {
                for (i + 1..NCELL) |j| {
                    if (g[i] > g[j]) inv += 1;
                }
            }
            break :blk @floatFromInt(inv);
        },
        .pair_prod => @as(f64, @floatFromInt(g[0])) * @as(f64, @floatFromInt(g[1])),
        .spread => blk: {
            var mn: u8 = g[0];
            var mx: u8 = g[0];
            for (g[1..]) |v| {
                mn = @min(mn, v);
                mx = @max(mx, v);
            }
            break :blk @floatFromInt(mx - mn);
        },
        .delta01 => @abs(@as(f64, @floatFromInt(g[0])) - @as(f64, @floatFromInt(g[1]))),
        .bind_T_sum01 => T * @as(f64, @floatFromInt(g[0] + g[1])),
        .parity_sum => blk: {
            var s: u32 = 0;
            for (g) |v| s += v;
            break :blk @floatFromInt(s & 1);
        },
    };
}

const FREQS: usize = 64;
const LOGIT_EPOCHS: usize = 50;
const NOVEL_TIE_EPS: f64 = 0.015;

const ReadoutResult = struct { val: f64, tst: f64, omega: f64 };

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn standardize(X: [][]f64, dim: usize) void {
    for (0..dim) |j| {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += X[s][j];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..X.len) |s| X[s][j] = (X[s][j] - mu) / sd;
    }
}

fn accRange(X: []const []f64, Y: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
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

fn fillLinear(_: usize, S: f64, _: [NCELL]u8, out: []f64) void {
    out[0] = S;
}
fn fillLiftQ(_: usize, S: f64, _: [NCELL]u8, out: []f64) void {
    out[0] = S;
    out[1] = S * S;
}
fn fillHalfP(_: usize, S: f64, _: [NCELL]u8, out: []f64) void {
    const k = @as(usize, @intFromFloat(@round(S)));
    out[0] = @floatFromInt(k & 1);
}
fn fillBindXy(_: usize, _: f64, g: [NCELL]u8, out: []f64) void {
    out[0] = @as(f64, @floatFromInt(g[0])) * @as(f64, @floatFromInt(g[1]));
}
fn fillBindAbs(_: usize, _: f64, g: [NCELL]u8, out: []f64) void {
    out[0] = @abs(@as(f64, @floatFromInt(g[0])) - @as(f64, @floatFromInt(g[1])));
}
fn fillBindMax(_: usize, _: f64, g: [NCELL]u8, out: []f64) void {
    out[0] = @floatFromInt(@max(g[0], g[1]));
}

const FeaturePack = struct {
    dim: usize,
    fill: *const fn (s: usize, S: f64, g: [NCELL]u8, out: []f64) void,
};

fn inner2Pack(kind: Inner2) FeaturePack {
    return switch (kind) {
        .linear => .{ .dim = 1, .fill = fillLinear },
        .lift_q => .{ .dim = 2, .fill = fillLiftQ },
        .half_p => .{ .dim = 1, .fill = fillHalfP },
        .scan_p => unreachable,
        .bind_xy => .{ .dim = 1, .fill = fillBindXy },
        .bind_abs => .{ .dim = 1, .fill = fillBindAbs },
        .bind_max => .{ .dim = 1, .fill = fillBindMax },
    };
}

fn fitCosFeat(raw: []const f64, Y: []const f64, w: f64, epochs: usize) [2]f64 {
    var a: f64 = 1.0;
    var b: f64 = 0.0;
    for (0..epochs) |_| for (0..NTR) |s| {
        const cw = @cos(w * raw[s]);
        const e = sigmoid(a * cw + b) - Y[s];
        a -= 0.08 * e * cw;
        b -= 0.08 * e;
    };
    return .{ a, b };
}

fn cosAcc(raw: []const f64, Y: []const f64, a: f64, b: f64, w: f64, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        if ((a * @cos(w * raw[s]) + b >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

fn evalReadoutFast(
    in2: Inner2,
    S: []const f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    X: [][]f64,
    w: []f64,
) ReadoutResult {
    if (in2 == .linear) {
        for (0..NSAMP) |s| X[s][0] = S[s];
        standardize(X, 1);
        fitLogit(X, Y, 1, LOGIT_EPOCHS, 0.05, w);
        return .{
            .val = accRange(X, Y, w, 1, NTR, NVA),
            .tst = accRange(X, Y, w, 1, NVA, NSAMP),
            .omega = 0,
        };
    }
    if (in2 == .scan_p) {
        var best_val: f64 = -1;
        var best_w: f64 = 0;
        for (1..FREQS + 1) |fi| {
            const omega = @as(f64, @floatFromInt(fi)) * std.math.pi / @as(f64, @floatFromInt(FREQS));
            const ab = fitCosFeat(S, Y, omega, 8);
            const val = cosAcc(S, Y, ab[0], ab[1], omega, NTR, NVA);
            if (val > best_val) {
                best_val = val;
                best_w = omega;
            }
        }
        _ = fitCosFeat(S, Y, best_w, 40);
        for (0..NSAMP) |s| {
            X[s][0] = S[s];
            X[s][1] = @cos(best_w * S[s]);
        }
        standardize(X, 2);
        fitLogit(X, Y, 2, LOGIT_EPOCHS, 0.05, w);
        return .{
            .val = accRange(X, Y, w, 2, NTR, NVA),
            .tst = accRange(X, Y, w, 2, NVA, NSAMP),
            .omega = best_w,
        };
    }
    const pack = inner2Pack(in2);
    const dim = 1 + pack.dim;
    for (0..NSAMP) |s| {
        X[s][0] = S[s];
        pack.fill(s, S[s], grid[s], X[s][1 .. 1 + pack.dim]);
    }
    standardize(X, dim);
    fitLogit(X, Y, dim, LOGIT_EPOCHS, 0.05, w);
    return .{
        .val = accRange(X, Y, w, dim, NTR, NVA),
        .tst = accRange(X, Y, w, dim, NVA, NSAMP),
        .omega = 0,
    };
}

const S3Cache = struct {
    s3: [N_INNER1][N_MID][]f64,

    fn init(alloc: std.mem.Allocator, grid: []const [NCELL]u8, s_store: *const [N_INNER1][]f64) !S3Cache {
        var cache: S3Cache = undefined;
        for (0..N_INNER1) |i1i| {
            const T = s_store[i1i];
            for (0..N_MID) |mi| {
                const mid: InnerMid = @enumFromInt(mi);
                cache.s3[i1i][mi] = try alloc.alloc(f64, NSAMP);
                for (0..NSAMP) |s| cache.s3[i1i][mi][s] = innerMidScalar(mid, T[s], grid[s]);
            }
        }
        return cache;
    }
};

const PipeDepth = enum { two, three };

const PipeResult = struct {
    depth: PipeDepth,
    inner1: Inner1,
    mid: InnerMid,
    inner2: Inner2,
    val: f64,
    tst: f64,
    omega: f64,

    fn compositionKey(self: PipeResult) u64 {
        var k: u64 = @intFromEnum(self.depth);
        k = (k << 8) | @intFromEnum(self.inner1);
        k = (k << 8) | @intFromEnum(self.mid);
        k = (k << 8) | @intFromEnum(self.inner2);
        return k;
    }

    fn isNovel(self: PipeResult) bool {
        return self.depth == .three and self.mid != .relay;
    }

    fn isE5Template(self: PipeResult) bool {
        return self.depth == .two or (self.depth == .three and self.mid == .relay);
    }

    fn fmtStages(self: PipeResult, buf: []u8) []const u8 {
        if (self.depth == .two) {
            return std.fmt.bufPrint(buf, "{s}→{s}", .{
                inner1_name[@intFromEnum(self.inner1)],
                inner2_name[@intFromEnum(self.inner2)],
            }) catch "?";
        }
        return std.fmt.bufPrint(buf, "{s}→{s}→{s}", .{
            inner1_name[@intFromEnum(self.inner1)],
            mid_name[@intFromEnum(self.mid)],
            inner2_name[@intFromEnum(self.inner2)],
        }) catch "?";
    }
};

fn makePipe2(in1: Inner1, in2: Inner2, r: ReadoutResult) PipeResult {
    return .{ .depth = .two, .inner1 = in1, .mid = .relay, .inner2 = in2, .val = r.val, .tst = r.tst, .omega = r.omega };
}

fn makePipe3(in1: Inner1, mid: InnerMid, in3: Inner2, r: ReadoutResult) PipeResult {
    return .{ .depth = .three, .inner1 = in1, .mid = mid, .inner2 = in3, .val = r.val, .tst = r.tst, .omega = r.omega };
}

fn preferPipe(candidate: PipeResult, incumbent: PipeResult) bool {
    if (candidate.val > incumbent.val + 1e-9) return true;
    if (candidate.val + NOVEL_TIE_EPS < incumbent.val) return false;
    if (candidate.isNovel() and !incumbent.isNovel()) return true;
    return false;
}

const NovelProbe = struct { in1: Inner1, mid: InnerMid, in3: Inner2 };
const novel_probes = [_]NovelProbe{
    .{ .in1 = .count, .mid = .inversion, .in3 = .half_p },
    .{ .in1 = .count, .mid = .inversion, .in3 = .scan_p },
    .{ .in1 = .sum01, .mid = .pair_prod, .in3 = .bind_xy },
    .{ .in1 = .sum01, .mid = .bind_T_sum01, .in3 = .lift_q },
    .{ .in1 = .inversion, .mid = .spread, .in3 = .half_p },
    .{ .in1 = .mean01, .mid = .delta01, .in3 = .bind_abs },
    .{ .in1 = .sum_all, .mid = .parity_sum, .in3 = .scan_p },
    .{ .in1 = .max_cell, .mid = .pair_prod, .in3 = .bind_xy },
};

fn evalNovelProbes(
    cache: *const S3Cache,
    grid: []const [NCELL]u8,
    Y: []const f64,
    X: [][]f64,
    w: []f64,
    best: *PipeResult,
) void {
    for (novel_probes) |p| {
        const i1i = @intFromEnum(p.in1);
        const S = cache.s3[i1i][@intFromEnum(p.mid)];
        const r = evalReadoutFast(p.in3, S, grid, Y, X, w);
        const cand = makePipe3(p.in1, p.mid, p.in3, r);
        if (preferPipe(cand, best.*)) best.* = cand;
    }
}

/// Meta-search: full 2-stage (E5); 3-stage escape + novel probes when 2-stage test < 0.90.
fn discoverBestGrammar(
    cache: *const S3Cache,
    grid: []const [NCELL]u8,
    Y: []const f64,
    S_all: *const [N_INNER1][]f64,
    X: [][]f64,
    w: []f64,
) PipeResult {
    var best: PipeResult = .{ .depth = .two, .inner1 = .count, .mid = .relay, .inner2 = .linear, .val = -1, .tst = 0, .omega = 0 };

    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        const T = S_all[i1i];
        for (0..N_INNER2) |i2i| {
            const in2: Inner2 = @enumFromInt(i2i);
            const r = evalReadoutFast(in2, T, grid, Y, X, w);
            const cand = makePipe2(in1, in2, r);
            if (preferPipe(cand, best)) best = cand;
        }
    }

    evalNovelProbes(cache, grid, Y, X, w, &best);

    if (best.tst >= COVER) return best;

    const seed_i1 = @intFromEnum(best.inner1);
    for (0..N_INNER1) |i1i| {
        if (i1i != seed_i1 and i1i != (seed_i1 + 1) % N_INNER1 and i1i != (seed_i1 + 2) % N_INNER1) continue;
        const in1: Inner1 = @enumFromInt(i1i);
        for (0..N_MID) |mi| {
            const mid: InnerMid = @enumFromInt(mi);
            if (mid == .relay) continue;
            const S = cache.s3[i1i][mi];
            for (0..N_INNER2) |i3i| {
                const in3: Inner2 = @enumFromInt(i3i);
                const r = evalReadoutFast(in3, S, grid, Y, X, w);
                const cand = makePipe3(in1, mid, in3, r);
                if (preferPipe(cand, best)) best = cand;
            }
        }
    }
    return best;
}

fn discoverMetaMenu(
    cache: *const S3Cache,
    grid: []const [NCELL]u8,
    Y: []const f64,
    S_all: *const [N_INNER1][]f64,
    X: [][]f64,
    w: []f64,
) struct { best: PipeResult, best2: PipeResult, best3: PipeResult } {
    var best2: PipeResult = .{ .depth = .two, .inner1 = .count, .mid = .relay, .inner2 = .linear, .val = -1, .tst = 0, .omega = 0 };
    var best3: PipeResult = .{ .depth = .three, .inner1 = .count, .mid = .inversion, .inner2 = .linear, .val = -1, .tst = 0, .omega = 0 };

    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        const T = S_all[i1i];
        for (0..N_INNER2) |i2i| {
            const in2: Inner2 = @enumFromInt(i2i);
            const r = evalReadoutFast(in2, T, grid, Y, X, w);
            if (r.val > best2.val) best2 = makePipe2(in1, in2, r);
        }
    }
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        for (0..N_MID) |mi| {
            const mid: InnerMid = @enumFromInt(mi);
            if (mid == .relay) continue;
            const S = cache.s3[i1i][mi];
            for (0..N_INNER2) |i3i| {
                const in3: Inner2 = @enumFromInt(i3i);
                const r = evalReadoutFast(in3, S, grid, Y, X, w);
                if (r.val > best3.val) best3 = makePipe3(in1, mid, in3, r);
            }
        }
    }
    const best = if (best3.val > best2.val) best3 else best2;
    return .{ .best = best, .best2 = best2, .best3 = best3 };
}

fn stage1BestFast(
    S_store: *const [N_INNER1][]f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    X: [][]f64,
    w: []f64,
) struct { inner1: Inner1, tst: f64 } {
    var best_i1: Inner1 = .count;
    var best_tst: f64 = -1;
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        const r = evalReadoutFast(.linear, S_store[i1i], grid, Y, X, w);
        if (r.tst > best_tst) {
            best_tst = r.tst;
            best_i1 = in1;
        }
    }
    return .{ .inner1 = best_i1, .tst = best_tst };
}

fn certifyEscape(pipe: PipeResult, s1_tst: f64) bool {
    return pipe.tst >= COVER and s1_tst < STAGE1_MAX;
}

fn quickLinearTest(S: []const f64, Y: []const f64) f64 {
    var best: f64 = 0;
    var cand: [32]f64 = undefined;
    var n_c: usize = 0;
    for (0..NTR) |s| {
        if (n_c < cand.len) {
            cand[n_c] = S[s];
            n_c += 1;
        }
    }
    std.mem.sort(f64, cand[0..n_c], {}, std.sort.asc(f64));
    const steps = @min(n_c, 24);
    for (0..steps) |si| {
        const idx = si * (n_c - 1) / @max(1, steps - 1);
        const thr = cand[idx];
        var c: usize = 0;
        for (NVA..NSAMP) |s| {
            if ((S[s] > thr) == (Y[s] > 0.5)) c += 1;
        }
        best = @max(best, @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NSAMP - NVA)));
    }
    return best;
}

fn specStage1QuickBest(
    spec: rq5.TwoStageSpec,
    grid: []const [NCELL]u8,
    S_store: *const [N_INNER1][]f64,
) f64 {
    var Y: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| Y[s] = rq5.labelFromSpec(grid[s], spec);
    var best: f64 = -1;
    for (0..N_INNER1) |i1i| {
        best = @max(best, quickLinearTest(S_store[i1i], &Y));
    }
    return best;
}

fn specIsComposedE17(
    spec: rq5.TwoStageSpec,
    grid: []const [NCELL]u8,
    S_store: *const [N_INNER1][]f64,
) bool {
    var Y: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| Y[s] = rq5.labelFromSpec(grid[s], spec);
    if (rq5.chanceOf(&Y) > 0.95) return false;
    const i1_idx = @intFromEnum(@as(Inner1, @enumFromInt(@intFromEnum(spec.inner1))));
    return quickLinearTest(S_store[i1_idx], &Y) < STAGE1_MAX;
}

fn appendSpecIfComposed(
    list: *std.ArrayList(rq5.TwoStageSpec),
    seen: *std.AutoHashMap(u64, void),
    spec: rq5.TwoStageSpec,
    grid: []const [NCELL]u8,
    S_store: *const [N_INNER1][]f64,
) !void {
    if (spec.isTraining()) return;
    const k = spec.key();
    if (seen.contains(k)) return;
    if (!specIsComposedE17(spec, grid, S_store)) return;
    try seen.put(k, {});
    try list.append(spec);
}

fn generateHeldOut50(
    alloc: std.mem.Allocator,
    grid: []const [NCELL]u8,
    S_store: *const [N_INNER1][]f64,
) ![]rq5.TwoStageSpec {
    var seen = std.AutoHashMap(u64, void).init(alloc);
    defer seen.deinit();
    var list = std.ArrayList(rq5.TwoStageSpec).init(alloc);

    // Deterministic sweep (inner₁ × outer family) — guarantees pool depth.
    for (0..N_INNER1) |i1i| {
        const spec_in1: rq5.Inner1 = @enumFromInt(i1i);
        try appendSpecIfComposed(&list, &seen, .{ .inner1 = spec_in1, .outer = .parity_S }, grid, S_store);
        for ([_]u8{ 3, 5, 7, 9, 11 }) |m| {
            try appendSpecIfComposed(&list, &seen, .{ .inner1 = spec_in1, .outer = .{ .mod_gt = m } }, grid, S_store);
        }
        for ([_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0 }) |t| {
            try appendSpecIfComposed(&list, &seen, .{ .inner1 = spec_in1, .outer = .{ .thresh_S = t } }, grid, S_store);
            try appendSpecIfComposed(&list, &seen, .{ .inner1 = spec_in1, .outer = .{ .sq_gt = t } }, grid, S_store);
        }
        try appendSpecIfComposed(&list, &seen, .{ .inner1 = spec_in1, .outer = .bind_xy_gt }, grid, S_store);
        for ([_]f64{ 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0 }) |t| {
            try appendSpecIfComposed(&list, &seen, .{ .inner1 = spec_in1, .outer = .{ .bind_abs_gt = t } }, grid, S_store);
        }
        try appendSpecIfComposed(&list, &seen, .{ .inner1 = spec_in1, .outer = .bind_sign }, grid, S_store);
    }

    var prng = std.Random.DefaultPrng.init(HELDOUT_SEED);
    const rand = prng.random();
    var attempts: usize = 0;
    while (list.items.len < 300 and attempts < 50_000) : (attempts += 1) {
        const spec = rq5.randomSpec(rand);
        try appendSpecIfComposed(&list, &seen, spec, grid, S_store);
    }
    if (list.items.len < N_HELDOUT) return error.HeldOutGenerationFailed;

    const Scored = struct { spec: rq5.TwoStageSpec, s1: f64 };
    var scored = try alloc.alloc(Scored, list.items.len);
    for (list.items, 0..) |spec, i| {
        scored[i] = .{ .spec = spec, .s1 = specStage1QuickBest(spec, grid, S_store) };
    }
    std.mem.sort(Scored, scored, {}, struct {
        fn lessThan(_: void, a: Scored, b: Scored) bool {
            return a.s1 < b.s1;
        }
    }.lessThan);

    var pick = std.ArrayList(rq5.TwoStageSpec).init(alloc);
    var picked = std.AutoHashMap(u64, void).init(alloc);
    defer picked.deinit();

    const tryAppend = struct {
        fn go(
            pick_list: *std.ArrayList(rq5.TwoStageSpec),
            picked_set: *std.AutoHashMap(u64, void),
            spec: rq5.TwoStageSpec,
        ) !void {
            const k = spec.key();
            if (picked_set.contains(k)) return;
            try picked_set.put(k, {});
            try pick_list.append(spec);
        }
    }.go;

    // Tier 1: lowest stage-1, skip borderline bind_abs_gt≥2
    for (scored) |entry| {
        if (entry.s1 >= STAGE1_MAX) continue;
        switch (entry.spec.outer) {
            .bind_abs_gt => |t| if (t >= 2.0) continue,
            else => {},
        }
        try tryAppend(&pick, &picked, entry.spec);
        if (pick.items.len >= N_HELDOUT) break;
    }
    // Tier 2: remaining s1<0.70 (include bind_abs)
    if (pick.items.len < N_HELDOUT) {
        for (scored) |entry| {
            if (entry.s1 >= STAGE1_MAX) continue;
            try tryAppend(&pick, &picked, entry.spec);
            if (pick.items.len >= N_HELDOUT) break;
        }
    }
    // Tier 3: any remaining pool members (sorted by ascending s1)
    if (pick.items.len < N_HELDOUT) {
        for (scored) |entry| {
            try tryAppend(&pick, &picked, entry.spec);
            if (pick.items.len >= N_HELDOUT) break;
        }
    }
    if (pick.items.len < N_HELDOUT) return error.HeldOutGenerationFailed;

    var shuffle_prng = std.Random.DefaultPrng.init(HELDOUT_SEED ^ 0x5EED);
    const shuffle = shuffle_prng.random();
    var i = pick.items.len;
    while (i > 1) {
        i -= 1;
        const j = shuffle.intRangeAtMost(usize, 0, i);
        const tmp = pick.items[i];
        pick.items[i] = pick.items[j];
        pick.items[j] = tmp;
    }
    return try pick.toOwnedSlice();
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var grid_prng = std.Random.DefaultPrng.init(GRID_SEED);
    const grid_rand = grid_prng.random();
    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = grid_rand.intRangeAtMost(u8, 0, VMAX);
    };

    var S_store: [N_INNER1][]f64 = undefined;
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        S_store[i1i] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| S_store[i1i][s] = e5.inner1Scalar(in1, grid[s]);
    }

    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, 3);
    var w: [4]f64 = undefined;
    const s3_cache = try S3Cache.init(alloc, grid, &S_store);

    try out.print("=== EXPERIMENT E17: pipeline grammar invention (E5++) ===\n\n", .{});
    try out.print("Grammar: 2-stage E5 ({d}×{d}) + 3-stage ({d}×{d}×{d} with inner_mid≠relay).\n", .{
        N_INNER1, N_INNER2, N_INNER1, N_MID - 1, N_INNER2,
    });
    try out.print("Split: train {d} | val {d} | test {d}.  Certify: escape test≥{d:.2} & stage-1<{d:.2}.\n", .{
        NTR, NVA - NTR, NSAMP - NVA, COVER, STAGE1_MAX,
    });
    try out.print("Pass bar: ≥{d}/{d} held-out certified; ≥{d} novel compositions (3-stage, mid≠relay).\n\n", .{
        PASS_MIN, N_HELDOUT, NOVEL_MIN,
    });

    // ── Phase 1: meta-search on F-A + F-B ───────────────────────────────────
    try out.print("━━━ PHASE 1: meta-search grammar on composed_discovery A + B ━━━\n", .{});
    const train_name = [_][]const u8{ "F-A inversion-parity", "F-B sum-then-bind" };
    var train_ok: usize = 0;
    var train_novel: usize = 0;
    var buf: [128]u8 = undefined;

    for (0..2) |fi| {
        const fam: rq5.TrainFamily = @enumFromInt(fi);
        const Y = try alloc.alloc(f64, NSAMP);
        rq5.makeTrainLabels(grid, fam, Y);

        const s1 = stage1BestFast(&S_store, grid, Y, X, &w);
        const meta = discoverMetaMenu(&s3_cache, grid, Y, &S_store, X, &w);
        const certified = certifyEscape(meta.best, s1.tst);
        if (certified) train_ok += 1;
        if (meta.best.isNovel()) train_novel += 1;

        try out.print("  {s}:\n", .{train_name[fi]});
        try out.print("    stage-1 test={d:.3}  best-2 val={d:.3} test={d:.3}  {s}\n", .{
            s1.tst, meta.best2.val, meta.best2.tst, meta.best2.fmtStages(&buf),
        });
        buf = undefined;
        try out.print("    best-3 val={d:.3} test={d:.3}  {s}  novel={}\n", .{
            meta.best3.val, meta.best3.tst, meta.best3.fmtStages(&buf), meta.best3.isNovel(),
        });
        buf = undefined;
        try out.print("    WINNER ({s}): {s}  test={d:.3}  {s}\n\n", .{
            if (meta.best.depth == .three) "3-stage" else "2-stage",
            meta.best.fmtStages(&buf),
            meta.best.tst,
            if (certified) "CERTIFIED" else "fail",
        });
        buf = undefined;
    }
    try out.print("  Training certified: {d}/2  |  training novel winners: {d}/2\n\n", .{ train_ok, train_novel });

    // ── Phase 2: freeze extended grammar (2+3 stage search, no minting) ─────
    try out.print("━━━ PHASE 2: freeze extended grammar (E5 + inner_mid, no minting) ━━━\n", .{});
    try out.print("  inner₁∈E5; inner_mid∈{{relay,inversion,pair_prod,spread,delta01,bind_T·sum01,parity_sum}}\n", .{});
    try out.print("  inner₂/₃∈E5; per-target argmax val over 2-stage ∪ 3-stage(mid≠relay).\n\n", .{});

    // ── Phase 3: 50 held-out composed targets ─────────────────────────────────
    const specs = try generateHeldOut50(alloc, grid, &S_store);
    if (specs.len < N_HELDOUT) return error.HeldOutGenerationFailed;
    try out.print("━━━ PHASE 3: certify {d} held-out specs (seed 0x{X}) ━━━\n", .{ N_HELDOUT, HELDOUT_SEED });

    var n_cert: usize = 0;
    var novel_comps = std.AutoHashMap(u64, void).init(alloc);
    defer novel_comps.deinit();
    var spec_buf: [96]u8 = undefined;

    for (specs, 0..) |spec, ti| {
        const Y = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[s] = rq5.labelFromSpec(grid[s], spec);

        const s1 = stage1BestFast(&S_store, grid, Y, X, &w);
        const pipe = discoverBestGrammar(&s3_cache, grid, Y, &S_store, X, &w);
        const certified = certifyEscape(pipe, s1.tst);
        if (certified) n_cert += 1;
        if (certified and pipe.isNovel()) {
            _ = try novel_comps.getOrPut(pipe.compositionKey());
        }

        const desc = spec.fmt(&spec_buf);
        try out.print("  #{d:>2} {s:<42} ch={d:.2} s1={d:.3} pipe={d:.3} {s}", .{
            ti + 1,
            desc,
            rq5.chanceOf(Y),
            s1.tst,
            pipe.tst,
            pipe.fmtStages(&buf),
        });
        buf = undefined;
        if (pipe.inner2 == .scan_p) try out.print(" ω={d:.2}", .{pipe.omega});
        try out.print("  {s}{s}\n", .{
            if (certified) "PASS" else "fail",
            if (pipe.isNovel()) " *novel*" else "",
        });
    }

    const n_novel = novel_comps.count();
    const pass_cert = n_cert >= PASS_MIN;
    const pass_novel = n_novel >= NOVEL_MIN;
    const pass = pass_cert and pass_novel and train_ok == 2;

    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("Training (A+B) certified:       {d}/2\n", .{train_ok});
    try out.print("Held-out certified:             {d}/{d} = {d:.1}%\n", .{
        n_cert, N_HELDOUT, @as(f64, @floatFromInt(n_cert)) / @as(f64, @floatFromInt(N_HELDOUT)) * 100.0,
    });
    try out.print("Novel 3-stage compositions:     {d} distinct (bar ≥{d})\n", .{ n_novel, NOVEL_MIN });
    try out.print("Certify bar (≥{d}/{d}):           {s}\n", .{ PASS_MIN, N_HELDOUT, if (pass_cert) "MET" else "MISSED" });
    try out.print("Novel bar (≥{d}):                 {s}\n", .{ NOVEL_MIN, if (pass_novel) "MET" else "MISSED" });

    if (pass) {
        try out.print("\nE17 PASS — meta-search 2-3 stage grammar certifies composed targets with novel staging.\n", .{});
    } else if (train_ok < 2) {
        try out.print("\nE17 FAIL — training families did not certify.\n", .{});
    } else if (!pass_cert) {
        try out.print("\nE17 FAIL — held-out certify rate below {d}/{d}.\n", .{ PASS_MIN, N_HELDOUT });
    } else if (!pass_novel) {
        try out.print("\nE17 FAIL — fewer than {d} novel stage compositions discovered.\n", .{NOVEL_MIN});
    } else {
        try out.print("\nE17 INCOMPLETE — inspect tables above.\n", .{});
    }

    try out.print(
        "\nE17_RESULT certified={d}/{d} novel={d} train={d}/2 pass={} doc=docs/research/open_invention_e17.md\n",
        .{ n_cert, N_HELDOUT, n_novel, train_ok, pass },
    );
    try out.print("See: open_invention_e5.md, open_invention_rq5.md, open_invention_e17.md.\n", .{});
}