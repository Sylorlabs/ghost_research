//! RESEARCH Q5 — E5 pipeline transfer: freeze grammar after A+B, test held-out composed targets.
//!
//! Phase 1 (train): discover pipelines on composed_discovery Family A + B (same as E5).
//! Phase 2 (freeze): lock the 7×7 inner₁→inner₂ grammar — no menu growth.
//! Phase 3 (transfer): 30 NEW random two-stage label specs (never in training); solve with frozen search.
//!
//! Pass bar: ≥50% of held-out targets certified (escape ≥0.90 test, stage-1 <0.70).
//!
//! Run: zig build open-invention-rq5 --release=fast

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = @as(f64, @floatFromInt(VMAX)) / 2.0;
const K_PROD: usize = @as(usize, VMAX) * VMAX;
const NSAMP: usize = 8000;
const NTR: usize = NSAMP / 2;
const NVA: usize = NSAMP * 3 / 4;
const COVER: f64 = 0.90;
const STAGE1_MAX: f64 = 0.70;
const N_HELDOUT: usize = 30;
const PASS_FRAC: f64 = 0.50;

const HELDOUT_SEED: u64 = 0x05110C0110BA5E;
pub const GRID_SEED: u64 = 0xF0235A11CE0FF1CE;

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

pub fn chanceOf(Y: []const f64) f64 {
    var pos: f64 = 0;
    for (NVA..NSAMP) |s| pos += Y[s];
    const n: f64 = @floatFromInt(NSAMP - NVA);
    return @max(pos, n - pos) / n;
}

// ── Frozen pipeline grammar (from E5) ───────────────────────────────────────

pub const Inner1 = enum {
    count,
    sum_all,
    sum01,
    inversion,
    max_cell,
    min01,
    mean01,
};
const N_INNER1 = 7;
const inner1_name = [_][]const u8{
    "count≥thr",
    "sum_all",
    "sum(c0,c1)",
    "inversion",
    "max_cell",
    "min(c0,c1)",
    "mean(c0,c1)",
};

fn inner1Scalar(kind: Inner1, g: [NCELL]u8) f64 {
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

const Inner2 = enum {
    linear,
    lift_q,
    half_p,
    scan_p,
    bind_xy,
    bind_abs,
    bind_max,
};
const N_INNER2 = 7;
const inner2_name = [_][]const u8{
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

const ScanResult = struct { val: f64, tst: f64, omega: f64 };

fn evalScanP(S: []const f64, Y: []const f64) ScanResult {
    const FREQS: usize = 64;
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
    const ab = fitCosFeat(S, Y, best_w, 40);
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

fn evalPipeline(
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
        fitLogit(X, Y, 1, 50, 0.05, w);
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
        fitLogit(X, Y, 2, 50, 0.05, w);
        return .{
            .inner1 = in1,
            .inner2 = in2,
            .val = accRange(X, Y, w, 2, NTR, NVA),
            .tst = accRange(X, Y, w, 2, NVA, NSAMP),
            .omega = r.omega,
        };
    }
    const pack = inner2Pack(in2);
    const dim = 1 + pack.dim;
    for (0..NSAMP) |s| {
        X[s][0] = S[s];
        pack.fill(s, S[s], grid[s], X[s][1 .. 1 + pack.dim]);
    }
    standardize(X, dim);
    fitLogit(X, Y, dim, 50, 0.05, w);
    return .{
        .inner1 = in1,
        .inner2 = in2,
        .val = accRange(X, Y, w, dim, NTR, NVA),
        .tst = accRange(X, Y, w, dim, NVA, NSAMP),
        .omega = 0,
    };
}

/// Frozen grammar search — full 7×7 menu, no growth.
fn discoverPipelineFrozen(
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

fn stage1Best(
    grid: []const [NCELL]u8,
    Y: []const f64,
    S_all: *const [N_INNER1][]f64,
    X: [][]f64,
    w: []f64,
) struct { inner1: Inner1, val: f64, tst: f64 } {
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

fn certifyEscape(pipe: PipeResult, s1_tst: f64) bool {
    return pipe.tst >= COVER and s1_tst < STAGE1_MAX;
}

// ── Training families (composed_discovery A + B) ────────────────────────────

pub const TrainFamily = enum { inversion_parity, sum_then_bind };
const train_name = [_][]const u8{ "F-A inversion-parity", "F-B sum-then-bind" };

pub fn makeTrainLabels(grid: []const [NCELL]u8, fam: TrainFamily, Y: []f64) void {
    for (0..grid.len) |s| {
        const g = grid[s];
        Y[s] = switch (fam) {
            .inversion_parity => blk: {
                var inv: usize = 0;
                for (0..NCELL) |i| for (i + 1..NCELL) |j| {
                    if (g[i] > g[j]) inv += 1;
                };
                break :blk @floatFromInt(inv & 1);
            },
            .sum_then_bind => blk: {
                const a = @as(f64, @floatFromInt(g[0])) - MID;
                const b = @as(f64, @floatFromInt(g[1])) - MID;
                break :blk if (a * b > 0) 1.0 else 0.0;
            },
        };
    }
}

// ── Held-out two-stage spec DSL ─────────────────────────────────────────────

pub const OuterTag = enum {
    parity_S,
    mod_gt,
    thresh_S,
    sq_gt,
    bind_xy_gt,
    bind_abs_gt,
    bind_sign,
};

pub const OuterReadout = union(OuterTag) {
    parity_S: void,
    mod_gt: u8,
    thresh_S: f64,
    sq_gt: f64,
    bind_xy_gt: void,
    bind_abs_gt: f64,
    bind_sign: void,
};

pub const TwoStageSpec = struct {
    inner1: Inner1,
    outer: OuterReadout,

    pub fn key(self: TwoStageSpec) u64 {
        var k: u64 = @intFromEnum(self.inner1);
        k = (k << 8) | @intFromEnum(self.outer);
        switch (self.outer) {
            .parity_S, .bind_xy_gt, .bind_sign => {},
            .mod_gt => |m| k = (k << 8) | m,
            .thresh_S => |t| k = (k << 32) | @as(u64, @bitCast(t)),
            .sq_gt => |t| k = (k << 32) | @as(u64, @bitCast(t)),
            .bind_abs_gt => |t| k = (k << 32) | @as(u64, @bitCast(t)),
        }
        return k;
    }

    pub fn isTraining(self: TwoStageSpec) bool {
        return (self.inner1 == .inversion and self.outer == .parity_S) or
            (self.inner1 == .sum01 and self.outer == .bind_sign);
    }

    pub fn fmt(self: TwoStageSpec, buf: []u8) []const u8 {
        const in1 = inner1_name[@intFromEnum(self.inner1)];
        return switch (self.outer) {
            .parity_S => std.fmt.bufPrint(buf, "{s} → S mod 2", .{in1}) catch "?",
            .mod_gt => |m| std.fmt.bufPrint(buf, "{s} → S mod {d} > {d}/2", .{ in1, m, m }) catch "?",
            .thresh_S => |t| std.fmt.bufPrint(buf, "{s} → S > {d:.1}", .{ in1, t }) catch "?",
            .sq_gt => |t| std.fmt.bufPrint(buf, "{s} → S² > {d:.1}", .{ in1, t }) catch "?",
            .bind_xy_gt => std.fmt.bufPrint(buf, "{s} → c0·c1 > {d}/2", .{ in1, K_PROD }) catch "?",
            .bind_abs_gt => |t| std.fmt.bufPrint(buf, "{s} → |c0−c1| > {d:.1}", .{ in1, t }) catch "?",
            .bind_sign => std.fmt.bufPrint(buf, "{s} → sign((c0−mid)(c1−mid))>0", .{in1}) catch "?",
        };
    }
};

pub fn labelFromSpec(g: [NCELL]u8, spec: TwoStageSpec) f64 {
    const S = inner1Scalar(spec.inner1, g);
    return switch (spec.outer) {
        .parity_S => @floatFromInt(@as(usize, @intFromFloat(@round(S))) & 1),
        .mod_gt => |m| blk: {
            const k = @as(usize, @intFromFloat(@round(S))) % m;
            break :blk if (k > m / 2) 1.0 else 0.0;
        },
        .thresh_S => |t| if (S > t) 1.0 else 0.0,
        .sq_gt => |t| if (S * S > t) 1.0 else 0.0,
        .bind_xy_gt => if (g[0] * g[1] > K_PROD / 2) 1.0 else 0.0,
        .bind_abs_gt => |t| blk: {
            const d = @abs(@as(f64, @floatFromInt(g[0])) - @as(f64, @floatFromInt(g[1])));
            break :blk if (d > t) 1.0 else 0.0;
        },
        .bind_sign => blk: {
            const a = @as(f64, @floatFromInt(g[0])) - MID;
            const b = @as(f64, @floatFromInt(g[1])) - MID;
            break :blk if (a * b > 0) 1.0 else 0.0;
        },
    };
}

fn randomOuter(rand: std.Random) OuterReadout {
    const tag: OuterTag = @enumFromInt(rand.intRangeAtMost(u8, 0, 6));
    return switch (tag) {
        .parity_S => .parity_S,
        .mod_gt => .{ .mod_gt = rand.intRangeAtMost(u8, 3, 7) | 1 }, // odd moduli
        .thresh_S => .{ .thresh_S = @as(f64, @floatFromInt(rand.intRangeAtMost(u8, 1, VMAX * 2))) },
        .sq_gt => .{ .sq_gt = @as(f64, @floatFromInt(rand.intRangeAtMost(u8, 4, 40))) },
        .bind_xy_gt => .bind_xy_gt,
        .bind_abs_gt => .{ .bind_abs_gt = @as(f64, @floatFromInt(rand.intRangeAtMost(u8, 1, VMAX))) },
        .bind_sign => .bind_sign,
    };
}

pub fn randomSpec(rand: std.Random) TwoStageSpec {
    const in1: Inner1 = @enumFromInt(rand.intRangeAtMost(u8, 0, N_INNER1 - 1));
    return .{ .inner1 = in1, .outer = randomOuter(rand) };
}

fn specIsComposed(
    spec: TwoStageSpec,
    grid: []const [NCELL]u8,
    S_store: *const [N_INNER1][]f64,
    X: [][]f64,
    w: []f64,
) bool {
    var Y: [NSAMP]f64 = undefined;
    for (0..NSAMP) |s| Y[s] = labelFromSpec(grid[s], spec);
    if (chanceOf(&Y) > 0.95) return false;
    const i1_idx = @intFromEnum(spec.inner1);
    const r = evalPipeline(spec.inner1, .linear, S_store[i1_idx], grid, &Y, X, w);
    return r.tst < STAGE1_MAX;
}

fn generateHeldOutSpecs(
    alloc: std.mem.Allocator,
    grid: []const [NCELL]u8,
    S_store: *const [N_INNER1][]f64,
    X: [][]f64,
    w: []f64,
) ![]TwoStageSpec {
    var prng = std.Random.DefaultPrng.init(HELDOUT_SEED);
    const rand = prng.random();
    var seen = std.AutoHashMap(u64, void).init(alloc);
    defer seen.deinit();
    var list = std.ArrayList(TwoStageSpec).init(alloc);
    var attempts: usize = 0;
    while (list.items.len < N_HELDOUT and attempts < 20_000) : (attempts += 1) {
        const spec = randomSpec(rand);
        if (spec.isTraining()) continue;
        const k = spec.key();
        if (seen.contains(k)) continue;
        if (!specIsComposed(spec, grid, S_store, X, w)) continue;
        try seen.put(k, {});
        try list.append(spec);
    }
    if (list.items.len < N_HELDOUT) return error.HeldOutGenerationFailed;
    return try list.toOwnedSlice();
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
        for (0..NSAMP) |s| S_store[i1i][s] = inner1Scalar(in1, grid[s]);
    }

    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, 3);
    var w: [4]f64 = undefined;

    try out.print("=== RESEARCH Q5: E5 pipeline transfer (freeze grammar → held-out composed targets) ===\n\n", .{});
    try out.print("Frozen grammar: {d} inner₁ × {d} inner₂ (E5 menu, no growth).\n", .{ N_INNER1, N_INNER2 });
    try out.print("Split: train {d} | val {d} | test {d}.  Certify: escape test≥{d:.2} & stage-1<{d:.2}.\n", .{
        NTR, NVA - NTR, NSAMP - NVA, COVER, STAGE1_MAX,
    });
    try out.print("Pass bar: ≥{d:.0}% of {d} held-out targets certified.\n\n", .{ PASS_FRAC * 100.0, N_HELDOUT });

    // ── Phase 1: train on Family A + B ──────────────────────────────────────
    try out.print("━━━ PHASE 1: train on composed_discovery A + B ━━━\n", .{});
    var train_ok: usize = 0;
    for (0..2) |fi| {
        const fam: TrainFamily = @enumFromInt(fi);
        const Y = try alloc.alloc(f64, NSAMP);
        makeTrainLabels(grid, fam, Y);

        const s1 = stage1Best(grid, Y, &S_store, X, &w);
        const pipe = discoverPipelineFrozen(grid, Y, &S_store, X, &w);
        const certified = certifyEscape(pipe, s1.tst);

        try out.print("  {s}: stage-1 test={d:.3}  pipeline test={d:.3}  ", .{
            train_name[fi], s1.tst, pipe.tst,
        });
        try out.print("discovered {s}→{s}", .{
            inner1_name[@intFromEnum(pipe.inner1)],
            inner2_name[@intFromEnum(pipe.inner2)],
        });
        if (pipe.inner2 == .scan_p) try out.print(" ω={d:.3}", .{pipe.omega});
        try out.print("  {s}\n", .{if (certified) "CERTIFIED" else "fail"});

        if (certified) train_ok += 1;
    }
    try out.print("  Training families certified: {d}/2\n\n", .{train_ok});

    // ── Phase 2: freeze grammar (explicit — no mutations) ───────────────────
    try out.print("━━━ PHASE 2: freeze pipeline grammar ━━━\n", .{});
    try out.print("  Menu locked at E5 discovery: inner₁∈{{count,sum_all,sum01,inversion,max,min01,mean01}}\n", .{});
    try out.print("  inner₂∈{{linear,lift_q,half_p,scan_p,bind_xy,bind_abs,bind_max}} — no minting.\n\n", .{});

    // ── Phase 3: 30 held-out random two-stage specs ─────────────────────────
    const specs = try generateHeldOutSpecs(alloc, grid, &S_store, X, &w);
    try out.print("━━━ PHASE 3: transfer on {d} held-out two-stage specs (seed 0x{X}) ━━━\n", .{ N_HELDOUT, HELDOUT_SEED });

    var n_cert: usize = 0;
    var buf: [96]u8 = undefined;

    for (specs, 0..) |spec, ti| {
        const Y = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[s] = labelFromSpec(grid[s], spec);

        const s1 = stage1Best(grid, Y, &S_store, X, &w);
        const pipe = discoverPipelineFrozen(grid, Y, &S_store, X, &w);
        const certified = certifyEscape(pipe, s1.tst);
        if (certified) n_cert += 1;

        const desc = spec.fmt(&buf);
        try out.print("  #{d:>2} {s:<42} ch={d:.2} s1={d:.3} pipe={d:.3} {s}→{s}", .{
            ti + 1,
            desc,
            chanceOf(Y),
            s1.tst,
            pipe.tst,
            inner1_name[@intFromEnum(pipe.inner1)],
            inner2_name[@intFromEnum(pipe.inner2)],
        });
        if (pipe.inner2 == .scan_p) try out.print(" ω={d:.2}", .{pipe.omega});
        try out.print("  {s}\n", .{if (certified) "PASS" else "fail"});
    }

    const solve_rate = @as(f64, @floatFromInt(n_cert)) / @as(f64, @floatFromInt(N_HELDOUT));
    const pass = solve_rate >= PASS_FRAC and train_ok == 2;

    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("Training (A+B) certified:     {d}/2\n", .{train_ok});
    try out.print("Held-out transfer certified:  {d}/{d} = {d:.1}%\n", .{ n_cert, N_HELDOUT, solve_rate * 100.0 });
    try out.print("Pass bar (≥{d:.0}%):            {s}\n", .{ PASS_FRAC * 100.0, if (solve_rate >= PASS_FRAC) "MET" else "MISSED" });
    if (pass) {
        try out.print("\nRQ5 PASS — frozen E5 pipeline grammar transfers to novel composed targets.\n", .{});
    } else if (train_ok < 2) {
        try out.print("\nRQ5 FAIL — training families did not certify; transfer invalid.\n", .{});
    } else {
        try out.print("\nRQ5 FAIL — transfer solve rate below {d:.0}% bar.\n", .{PASS_FRAC * 100.0});
    }
    try out.print("\nSee: open_invention_e5.md, composed_discovery.md, open_invention_rq5.md.\n", .{});
}