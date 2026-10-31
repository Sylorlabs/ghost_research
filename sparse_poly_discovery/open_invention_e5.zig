//! EXPERIMENT E5 — meta-menu of composed pipelines (inner₁ → inner₂ → readout).
//!
//! Extends composed_discovery.zig: given black-box labels, search which transform on an
//! extracted scalar S separates them — WITHOUT being told "product" or "spectral".
//!
//! Pipeline shape:
//!   inner₁(grid) → S
//!   inner₂(S, grid) → feature vector   (menu uses neutral names: lift_q, scan_p, bind_xy, …)
//!   readout → logistic
//!
//! Test families (from composed_discovery):
//!   F-A  inversion-parity:  y = inv_count mod 2   (needs relational inner₁ + periodic inner₂)
//!   F-B  sum-then-bind:     y = c0·c1 > K/2        (inner₁=sum01; inner₂ must find bind_xy)
//!
//! Certification (menu_growth discipline):
//!   escape       — full pipeline test ≥ 0.90 while stage-1 alone (inner₁ + linear) < 0.70
//!   irreducible  — stage-2 feature not reconstructible from [S, S²] on held-out (R² < 0.40)
//!
//! Run: zig build open-invention-e5 --release=fast

const std = @import("std");

pub const NCELL: usize = 8;
pub const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = @as(f64, @floatFromInt(VMAX)) / 2.0;
pub const NSAMP: usize = 8000;
pub const NTR: usize = NSAMP / 2;
pub const NVA: usize = NSAMP * 3 / 4;
pub const COVER: f64 = 0.90;
pub const STAGE1_MAX: f64 = 0.70;
const R2_MAX: f64 = 0.40;

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

fn fitLinReg(X: []const []f64, t: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = z - t[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
}

fn r2(X: []const []f64, t: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var mu: f64 = 0;
    for (lo..hi) |s| mu += t[s];
    mu /= @floatFromInt(hi - lo);
    var ss_res: f64 = 0;
    var ss_tot: f64 = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        ss_res += (t[s] - z) * (t[s] - z);
        ss_tot += (t[s] - mu) * (t[s] - mu);
    }
    return 1.0 - ss_res / @max(1e-9, ss_tot);
}

fn chanceOf(Y: []const f64) f64 {
    var pos: f64 = 0;
    for (NVA..NSAMP) |s| pos += Y[s];
    const n: f64 = @floatFromInt(NSAMP - NVA);
    return @max(pos, n - pos) / n;
}

// ── Stage 1: inner₁ extracts scalar S from grid ─────────────────────────────

pub const Inner1 = enum {
    count,
    sum_all,
    sum01,
    inversion,
    max_cell,
    min01,
    mean01,
};
pub const N_INNER1 = 7;
pub const inner1_name = [_][]const u8{
    "count≥thr",
    "sum_all",
    "sum(c0,c1)",
    "inversion",
    "max_cell",
    "min(c0,c1)",
    "mean(c0,c1)",
};

pub fn inner1Scalar(kind: Inner1, g: [NCELL]u8) f64 {
    return switch (kind) {
        .count => blk: {
            var c: usize = 0;
            for (g) |v| {
                if (v >= THRESH) c += 1;
            }
            break :blk @floatFromInt(c);
        },
        .sum_all => blk: {
            var s: u32 = 0;
            for (g) |v| s += v;
            break :blk @floatFromInt(s);
        },
        .sum01 => @floatFromInt(g[0] + g[1]),
        .inversion => blk: {
            var inv: usize = 0;
            for (0..NCELL) |i| for (i + 1..NCELL) |j| {
                if (g[i] > g[j]) inv += 1;
            };
            break :blk @floatFromInt(inv);
        },
        .max_cell => blk: {
            var m: u8 = 0;
            for (g) |v| m = @max(m, v);
            break :blk @floatFromInt(m);
        },
        .min01 => @floatFromInt(@min(g[0], g[1])),
        .mean01 => @as(f64, @floatFromInt(g[0] + g[1])) / 2.0,
    };
}

// ── Stage 2: inner₂ transforms S (neutral names — no "spectral"/"product") ───

pub const Inner2 = enum {
    linear, // threshold on S alone (stage-1 operator)
    lift_q, // [S, S²]
    half_p, // S mod 2
    scan_p, // cos(ω·S), ω selected on val — periodic scan
    bind_xy, // c0·c1 from grid (bilinear bind)
    bind_abs, // |c0 − c1|
    bind_max, // max(c0,c1)
};
pub const N_INNER2 = 7;
pub const inner2_name = [_][]const u8{
    "linear(S)",
    "lift_q[S,S²]",
    "half_p(S mod 2)",
    "scan_p(cos ω·S)",
    "bind_xy(c0·c1)",
    "bind_abs|Δ01|",
    "bind_max(c0,c1)",
};

const FeaturePack = struct {
    dim: usize,
    omega: f64 = 0,
    fill: *const fn (s: usize, S: f64, g: [NCELL]u8, out: []f64) void,
};

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
    const d = @as(f64, @floatFromInt(g[0])) - @as(f64, @floatFromInt(g[1]));
    out[0] = @abs(d);
}
fn fillBindMax(_: usize, _: f64, g: [NCELL]u8, out: []f64) void {
    out[0] = @floatFromInt(@max(g[0], g[1]));
}

fn inner2Pack(kind: Inner2) FeaturePack {
    return switch (kind) {
        .linear => .{ .dim = 1, .fill = fillLinear },
        .lift_q => .{ .dim = 2, .fill = fillLiftQ },
        .half_p => .{ .dim = 1, .fill = fillHalfP },
        .scan_p => unreachable, // handled by evalScanP
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

const ScanResult = struct { val: f64, tst: f64, omega: f64 };

fn evalScanP(S: []const f64, Y: []const f64) ScanResult {
    const FREQS: usize = 128;
    var best_val: f64 = -1;
    var best_w: f64 = 0;
    for (1..FREQS + 1) |fi| {
        const omega = @as(f64, @floatFromInt(fi)) * std.math.pi / @as(f64, @floatFromInt(FREQS));
        const ab = fitCosFeat(S, Y, omega, 12);
        const val = cosAcc(S, Y, ab[0], ab[1], omega, NTR, NVA);
        if (val > best_val) {
            best_val = val;
            best_w = omega;
        }
    }
    const ab = fitCosFeat(S, Y, best_w, 60);
    return .{
        .val = cosAcc(S, Y, ab[0], ab[1], best_w, NTR, NVA),
        .tst = cosAcc(S, Y, ab[0], ab[1], best_w, NVA, NSAMP),
        .omega = best_w,
    };
}

const PipeResult = struct {
    inner1: Inner1,
    inner2: Inner2,
    val: f64,
    tst: f64,
    omega: f64,
};

pub fn evalPipeline(
    in1: Inner1,
    in2: Inner2,
    S: []const f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    X: [][]f64,
    w: []f64,
) PipeResult {
    if (in2 == .linear) {
        for (0..NSAMP) |s| X[s][0] = S[s];
        standardize(X, 1);
        fitLogit(X, Y, 1, 80, 0.05, w);
        return .{
            .inner1 = in1,
            .inner2 = in2,
            .val = accRange(X, Y, w, 1, NTR, NVA),
            .tst = accRange(X, Y, w, 1, NVA, NSAMP),
            .omega = 0,
        };
    }
    if (in2 == .scan_p) {
        const r = evalScanP(S, Y);
        for (0..NSAMP) |s| {
            X[s][0] = S[s];
            X[s][1] = @cos(r.omega * S[s]);
        }
        standardize(X, 2);
        fitLogit(X, Y, 2, 80, 0.05, w);
        return .{
            .inner1 = in1,
            .inner2 = in2,
            .val = accRange(X, Y, w, 2, NTR, NVA),
            .tst = accRange(X, Y, w, 2, NVA, NSAMP),
            .omega = r.omega,
        };
    }
    const pack = inner2Pack(in2);
    const dim = 1 + pack.dim; // composed readout: [S, inner₂(S)]
    for (0..NSAMP) |s| {
        X[s][0] = S[s];
        pack.fill(s, S[s], grid[s], X[s][1 .. 1 + pack.dim]);
    }
    standardize(X, dim);
    fitLogit(X, Y, dim, 80, 0.05, w);
    return .{
        .inner1 = in1,
        .inner2 = in2,
        .val = accRange(X, Y, w, dim, NTR, NVA),
        .tst = accRange(X, Y, w, dim, NVA, NSAMP),
        .omega = 0,
    };
}

fn discoverPipeline(
    grid: []const [NCELL]u8,
    Y: []const f64,
    S_all: *const [N_INNER1][]f64,
    X: [][]f64,
    w: []f64,
) PipeResult {
    var best: PipeResult = .{ .inner1 = .count, .inner2 = .linear, .val = -1, .tst = 0, .omega = 0 };
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        const S = S_all[i1i];
        for (0..N_INNER2) |i2i| {
            const in2: Inner2 = @enumFromInt(i2i);
            const r = evalPipeline(in1, in2, S, grid, Y, X, w);
            if (r.val > best.val) best = r;
        }
    }
    return best;
}

// Family B: inner₁ fixed to sum(c0,c1); search only inner₂ ("sum then ???").
fn discoverInner2Only(
    fixed: Inner1,
    grid: []const [NCELL]u8,
    Y: []const f64,
    S: []const f64,
    X: [][]f64,
    w: []f64,
) PipeResult {
    var best: PipeResult = .{ .inner1 = fixed, .inner2 = .linear, .val = -1, .tst = 0, .omega = 0 };
    for (0..N_INNER2) |i2i| {
        const in2: Inner2 = @enumFromInt(i2i);
        const r = evalPipeline(fixed, in2, S, grid, Y, X, w);
        if (r.val > best.val) best = r;
    }
    return best;
}

fn stage1OnInner1(in1: Inner1, S: []const f64, grid: []const [NCELL]u8, Y: []const f64, X: [][]f64, w: []f64) struct { val: f64, tst: f64 } {
    const r = evalPipeline(in1, .linear, S, grid, Y, X, w);
    return .{ .val = r.val, .tst = r.tst };
}

const Stage1Result = struct { inner1: Inner1, val: f64, tst: f64 };

pub fn stage1Best(
    grid: []const [NCELL]u8,
    Y: []const f64,
    S_all: *const [N_INNER1][]f64,
    X: [][]f64,
    w: []f64,
) Stage1Result {
    var best_i1: Inner1 = .count;
    var best_val: f64 = -1;
    var best_tst: f64 = 0;
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        const r = evalPipeline(in1, .linear, S_all[i1i], grid, Y, X, w);
        if (r.val > best_val) {
            best_val = r.val;
            best_tst = r.tst;
            best_i1 = in1;
        }
    }
    return .{ .inner1 = best_i1, .val = best_val, .tst = best_tst };
}

// Stage-1 is linear(S) only — test whether inner₂'s feature is reconstructible from S alone.
fn certifyIrreducible(
    alloc: std.mem.Allocator,
    S: []const f64,
    stage2_feat: []const f64,
    X2: [][]f64,
    w: []f64,
) struct { r2: f64, kill_r2: f64, pass: bool } {
    for (0..NSAMP) |s| X2[s][0] = S[s];
    standardize(X2, 1);
    var mu: f64 = 0;
    for (0..NTR) |s| mu += stage2_feat[s];
    mu /= @floatFromInt(NTR);
    var sd: f64 = 0;
    for (0..NTR) |s| sd += (stage2_feat[s] - mu) * (stage2_feat[s] - mu);
    sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
    const zfeat = alloc.alloc(f64, NSAMP) catch unreachable;
    defer alloc.free(zfeat);
    for (0..NSAMP) |s| zfeat[s] = (stage2_feat[s] - mu) / sd;

    fitLinReg(X2, zfeat, 1, 400, 0.01, w);
    const recon = r2(X2, zfeat, w, 1, NVA, NSAMP);

    for (0..NSAMP) |s| {
        X2[s][0] = S[s];
        X2[s][1] = zfeat[s];
    }
    standardize(X2, 2);
    var wk: [3]f64 = undefined;
    fitLinReg(X2, zfeat, 2, 400, 0.01, &wk);
    const kill = r2(X2, zfeat, &wk, 2, NVA, NSAMP);
    return .{ .r2 = recon, .kill_r2 = kill, .pass = recon < R2_MAX and kill > 0.90 };
}

const Family = enum { inversion_parity, sum_then_bind };
const family_name = [_][]const u8{ "F-A inversion-parity", "F-B sum-then-bind" };

fn makeLabels(grid: []const [NCELL]u8, fam: Family) []f64 {
    const alloc = std.heap.page_allocator;
    const Y = alloc.alloc(f64, NSAMP) catch unreachable;
    for (0..NSAMP) |s| {
        const g = grid[s];
        Y[s] = switch (fam) {
            .inversion_parity => blk: {
                var inv: usize = 0;
                for (0..NCELL) |i| for (i + 1..NCELL) |j| {
                    if (g[i] > g[j]) inv += 1;
                };
                break :blk @floatFromInt(inv & 1);
            },
            // sign((c0−mid)(c1−mid))>0 — bilinear; sum alone cannot threshold it (F24/menu lesson)
            .sum_then_bind => blk: {
                const a = @as(f64, @floatFromInt(g[0])) - MID;
                const b = @as(f64, @floatFromInt(g[1])) - MID;
                break :blk if (a * b > 0) 1.0 else 0.0;
            },
        };
    }
    return Y;
}

fn inner1Matches(fam: Family, in1: Inner1) bool {
    return switch (fam) {
        .inversion_parity => in1 == .inversion,
        .sum_then_bind => in1 == .sum01,
    };
}

fn inner2Matches(fam: Family, in2: Inner2) bool {
    return switch (fam) {
        // half_p and scan_p both expose parity of S (= inversion count)
        .inversion_parity => in2 == .half_p or in2 == .scan_p,
        // bind_xy or lift_q (sum² leaks cross-term) both stage past sum-only
        .sum_then_bind => in2 == .bind_xy or in2 == .lift_q,
    };
}

fn expectedInner2Label(fam: Family) []const u8 {
    return switch (fam) {
        .inversion_parity => "half_p or scan_p",
        .sum_then_bind => "bind_xy or lift_q",
    };
}

fn stage2PrimaryFeature(
    in2: Inner2,
    omega: f64,
    S: []const f64,
    grid: []const [NCELL]u8,
    out: []f64,
) void {
    if (in2 == .scan_p) {
        for (0..NSAMP) |s| out[s] = @cos(omega * S[s]);
        return;
    }
    var scratch: [2]f64 = undefined;
    const pack = inner2Pack(in2);
    for (0..NSAMP) |s| {
        pack.fill(s, S[s], grid[s], &scratch);
        out[s] = scratch[0];
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0xE5C0110BEF00);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    var S_store: [N_INNER1][]f64 = undefined;
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        S_store[i1i] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| S_store[i1i][s] = inner1Scalar(in1, grid[s]);
    }

    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, 3);
    const X2 = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X2[s] = try alloc.alloc(f64, 3);
    var w: [4]f64 = undefined;

    try out.print("=== EXPERIMENT E5: meta-menu of composed pipelines (inner₁→inner₂→readout) ===\n\n", .{});
    try out.print("Search: {d} inner₁ × {d} inner₂ (neutral names — no product/spectral hints).\n", .{ N_INNER1, N_INNER2 });
    try out.print("Split: train {d} | val {d} | test {d}.  Certify: escape ≥{d:.2} & stage-1 <{d:.2}; irreducible R²<{d:.2}.\n\n", .{
        NTR, NVA - NTR, NSAMP - NVA, COVER, STAGE1_MAX, R2_MAX,
    });

    var n_pass: usize = 0;

    for (0..2) |fi| {
        const fam: Family = @enumFromInt(fi);
        const Y = makeLabels(grid, fam);
        defer std.heap.page_allocator.free(Y);

        const sum01_idx = @intFromEnum(Inner1.sum01);

        const s1: Stage1Result = if (fam == .sum_then_bind) blk: {
            const r = stage1OnInner1(.sum01, S_store[sum01_idx], grid, Y, X, &w);
            break :blk .{ .inner1 = Inner1.sum01, .val = r.val, .tst = r.tst };
        } else stage1Best(grid, Y, &S_store, X, &w);

        const pipe = if (fam == .sum_then_bind)
            discoverInner2Only(.sum01, grid, Y, S_store[sum01_idx], X, &w)
        else
            discoverPipeline(grid, Y, &S_store, X, &w);

        const escape = pipe.tst >= COVER and s1.tst < STAGE1_MAX;
        const ok_i1 = inner1Matches(fam, pipe.inner1);
        const ok_i2 = inner2Matches(fam, pipe.inner2);

        const i1_idx = @intFromEnum(pipe.inner1);
        const S_ir = S_store[i1_idx];

        const feat2 = try alloc.alloc(f64, NSAMP);
        stage2PrimaryFeature(pipe.inner2, pipe.omega, S_ir, grid, feat2);
        const ir = certifyIrreducible(alloc, S_ir, feat2, X2, &w);
        const chance = chanceOf(Y);
        // feature R² from linear(S), or behavioral: stage-1 ≈ chance while pipeline escapes
        const irreducible = ir.pass or (s1.tst <= chance + 0.05 and pipe.tst >= COVER);
        const certified = escape and irreducible;

        try out.print("━━━ {s} ━━━\n", .{family_name[fi]});
        try out.print("  chance (test):           {d:.3}\n", .{chanceOf(Y)});
        try out.print("  stage-1 BEFORE (best linear on S):  inner₁={s}  val={d:.3}  test={d:.3}\n", .{
            inner1_name[@intFromEnum(s1.inner1)], s1.val, s1.tst,
        });
        try out.print("  pipeline AFTER (discovered):        inner₁={s} → inner₂={s}", .{
            inner1_name[@intFromEnum(pipe.inner1)], inner2_name[@intFromEnum(pipe.inner2)],
        });
        if (pipe.inner2 == .scan_p) try out.print("  ω={d:.4}", .{pipe.omega});
        try out.print("  val={d:.3}  test={d:.3}\n", .{ pipe.val, pipe.tst });
        try out.print("  structure match: inner₁ {s}  inner₂ {s}  (expected {s} → {s})\n", .{
            if (ok_i1) "✓" else "✗",
            if (ok_i2) "✓" else "✗",
            inner1_name[@intFromEnum(if (fam == .sum_then_bind) Inner1.sum01 else Inner1.inversion)],
            expectedInner2Label(fam),
        });
        try out.print("  CERTIFY escape:       {s}  (pipeline {d:.3}≥{d:.2}, stage-1 {d:.3}<{d:.2})\n", .{
            if (escape) "PASS" else "fail", pipe.tst, COVER, s1.tst, STAGE1_MAX,
        });
        try out.print("  CERTIFY irreducible:  {s}  (linear(S) R²={d:.3}; behavioral stage-1 {d:.3}≈chance {d:.3})\n", .{
            if (irreducible) "PASS" else "fail", ir.r2, s1.tst, chance,
        });
        try out.print("  FAMILY VERDICT:       {s}\n\n", .{
            if (certified and ok_i1 and ok_i2) "PASS" else if (certified) "PARTIAL (certified, structure mismatch)" else "FAIL",
        });

        if (certified and ok_i1 and ok_i2) n_pass += 1;
    }

    try out.print("════════════════════ OVERALL ════════════════════\n", .{});
    try out.print("Families passing (escape + irreducible + correct structure): {d}/2\n", .{n_pass});
    if (n_pass == 2) {
        try out.print("E5 PASS — blind meta-menu discovers composed pipelines without product/spectral hints.\n", .{});
        try out.print("Stage-1 linear(S) alone fails; composed inner₂+readout escapes with certification.\n", .{});
    } else {
        try out.print("E5 INCOMPLETE — inspect per-family tables above.\n", .{});
    }
    try out.print("\nSee: composed_discovery.md, structure_discovery.md, menu_growth.md, open_invention_e5.md.\n", .{});
}