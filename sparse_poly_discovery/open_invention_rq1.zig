//! RESEARCH Q1++ — E1 blind battery WITHOUT handed menu (staged auto-escalation).
//!
//! Phase 1: train/freeze monomial forge on zoo A (T1–T4), identical to E1.
//! Phase 2: battery B (11 blind targets, E1 seed/patterns). Staged discovery:
//!   Step 1 — frozen monomial library (no new promotions)
//!   Step 2 — count synth depth≤4 {+,×,sin,mod} + E5 pipelines
//!   Step 3 — pair hardness router (correlation rank + one verify)
//!   Step 4 — Walsh χ_S correlation argmax **only** when hardness = q38_compound
//!
//! EXCLUDED: spectral peak, Clifford, world pool, pre-labeled operator menu.
//!
//! PASS: ≥10/11 battery B certified at held-out test ≥0.90.
//!
//! Run: zig build open-invention-rq1 --release=fast

const std = @import("std");
const hr = @import("hardness_router.zig");
const oml = @import("operator_menu_lib.zig");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
pub const NSAMP: usize = 7000;
pub const NTR: usize = 3500;
pub const NVA: usize = 5250;
const MAXFEAT: usize = 32;
const MAXDEG: usize = 4;
pub const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;
const STAGE1_MAX: f64 = 0.70;
const MONO_SATURATE: f64 = 0.55;
const SINGLE_SUFFICIENT: f64 = 0.70;

pub const GRID_SEED: u64 = 0xF0235A11CE0FF1CE;
pub const BATTERY_SEED: u64 = 0xE1B10D20A11CE01;
const RQ1_TAG: u64 = 0xA11CE0A110D20A11;

const NZOO_A: usize = 4;
const ZOO_A_MASKS = [_]u8{
    (1 << 2) | (1 << 5),
    (1 << 1) | (1 << 3) | (1 << 6),
    (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7),
    (1 << 3),
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

fn inversionCount(g: [NCELL]u8) usize {
    var inv: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        if (g[i] > g[j]) inv += 1;
    };
    return inv;
}

// ── Frozen monomial feature library ──────────────────────────────────────────

pub const Feature = struct { monomial: u8 };

fn evalFeature(f: Feature, g: [NCELL]u8) f64 {
    return phi(g, f.monomial);
}

fn featureKey(buf: []u8, f: Feature) []const u8 {
    return std.fmt.bufPrint(buf, "φ(0x{X:0>2})", .{f.monomial}) catch "φ";
}

fn hasMonomial(lib: []const Feature, mask: u8) bool {
    for (lib) |x| if (x.monomial == mask) return true;
    return false;
}

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

fn buildFeatWithScalar(X: [][]f64, grid: []const [NCELL]u8, lib: []const Feature, extra: []const f64) void {
    const k = lib.len;
    for (0..NSAMP) |s| {
        for (0..k) |c| X[s][c] = evalFeature(lib[c], grid[s]);
        X[s][k] = extra[s];
    }
    for (0..k + 1) |c| {
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

pub fn coverage(X: [][]f64, grid: []const [NCELL]u8, lib: []const Feature, Y: []const f64, w: []f64) f64 {
    buildFeat(X, grid, lib);
    fitLogit(X, Y, lib.len, 150, 0.05, w);
    return accLogit(X, Y, w, lib.len, NVA, NSAMP);
}

fn coverageWithExtra(X: [][]f64, grid: []const [NCELL]u8, lib: []const Feature, extra: []const f64, Y: []const f64, w: []f64) f64 {
    buildFeatWithScalar(X, grid, lib, extra);
    fitLogit(X, Y, lib.len + 1, 150, 0.05, w);
    return accLogit(X, Y, w, lib.len + 1, NVA, NSAMP);
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

// ── Program synthesis: {+,×,sin,mod} on count only ───────────────────────────

const ProgNode = union(enum) {
    count: void,
    add: struct { a: u16, b: u16 },
    mul: struct { a: u16, b: u16 },
    sin: u16,
    @"mod": struct { child: u16, k: u8 },
};

pub const ProgBank = struct {
    nodes: []ProgNode,
    depths: []u8,
    names: []const []const u8,

    fn depth(self: ProgBank, id: u16) u8 {
        return self.depths[id];
    }

    fn eval(self: ProgBank, id: u16, c: f64) f64 {
        return switch (self.nodes[id]) {
            .count => c,
            .add => |ab| self.eval(ab.a, c) + self.eval(ab.b, c),
            .mul => |ab| self.eval(ab.a, c) * self.eval(ab.b, c),
            .sin => |ch| @sin(self.eval(ch, c)),
            .@"mod" => |mk| @rem(self.eval(mk.child, c), @as(f64, @floatFromInt(mk.k))),
        };
    }
};

pub fn buildProgBank(alloc: std.mem.Allocator) !ProgBank {
    var nodes = std.ArrayList(ProgNode).init(alloc);
    defer nodes.deinit();
    var depths = std.ArrayList(u8).init(alloc);
    defer depths.deinit();
    var names = std.ArrayList([]const u8).init(alloc);
    defer names.deinit();

    try nodes.append(.{ .count = {} });
    try depths.append(0);
    try names.append("count");
    const count_leaf: u16 = 0;

    var depth_cur: u8 = 1;
    var frontier = std.ArrayList(u16).init(alloc);
    try frontier.append(count_leaf);

    while (depth_cur <= 4) : (depth_cur += 1) {
        var next_frontier = std.ArrayList(u16).init(alloc);
        defer next_frontier.deinit();

        for (frontier.items) |pid| {
            if (nodes.items.len >= 256) break;
            const base = names.items[pid];
            const sin_nm = try std.fmt.allocPrint(alloc, "sin({s})", .{base});
            try nodes.append(.{ .sin = pid });
            try depths.append(depth_cur);
            try names.append(sin_nm);
            try next_frontier.append(@intCast(nodes.items.len - 1));

            for (2..9) |k| {
                if (nodes.items.len >= 256) break;
                const nm = try std.fmt.allocPrint(alloc, "mod({s},{d})", .{ base, k });
                try nodes.append(.{ .@"mod" = .{ .child = pid, .k = @intCast(k) } });
                try depths.append(depth_cur);
                try names.append(nm);
                try next_frontier.append(@intCast(nodes.items.len - 1));
            }
        }

        const n = nodes.items.len;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                const d = @max(depths.items[i], depths.items[j]) + 1;
                if (d > 4 or nodes.items.len >= 256) continue;
                const ai: u16 = @intCast(i);
                const aj: u16 = @intCast(j);
                for ([_]struct { node: ProgNode, tag: []const u8 }{
                    .{ .node = .{ .add = .{ .a = ai, .b = aj } }, .tag = "+" },
                    .{ .node = .{ .mul = .{ .a = ai, .b = aj } }, .tag = "*" },
                }) |op| {
                    if (nodes.items.len >= 256) break;
                    const nm = try std.fmt.allocPrint(alloc, "({s}{s}{s})", .{ names.items[i], op.tag, names.items[j] });
                    try nodes.append(op.node);
                    try depths.append(d);
                    try names.append(nm);
                }
            }
        }

        frontier.clearRetainingCapacity();
        for (next_frontier.items) |id| try frontier.append(id);
    }

    return .{
        .nodes = try nodes.toOwnedSlice(),
        .depths = try depths.toOwnedSlice(),
        .names = try names.toOwnedSlice(),
    };
}

fn discoverSynth(
    grid: []const [NCELL]u8,
    Y: []const f64,
    bank: ProgBank,
    X: [][]f64,
    w: []f64,
) struct { prog_id: u16, val_acc: f64, feat: []f64 } {
    const feat = std.heap.page_allocator.alloc(f64, NSAMP) catch unreachable;
    var best_val: f64 = -1;
    var best_id: u16 = 0;
    for (1..bank.nodes.len) |pid| {
        if (bank.depth(@intCast(pid)) > 4) continue;
        for (0..NSAMP) |s| feat[s] = bank.eval(@intCast(pid), countGE(grid[s]));
        var mu: f64 = 0;
        for (0..NTR) |s| mu += feat[s];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (feat[s] - mu) * (feat[s] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| X[s][0] = (feat[s] - mu) / sd;
        fitLogit(X, Y, 1, 80, 0.06, w);
        const v = accLogit(X, Y, w, 1, NTR, NVA);
        if (v > best_val) {
            best_val = v;
            best_id = @intCast(pid);
        }
    }
    for (0..NSAMP) |s| feat[s] = bank.eval(best_id, countGE(grid[s]));
    return .{ .prog_id = best_id, .val_acc = best_val, .feat = feat };
}

// ── E5 composed pipelines ────────────────────────────────────────────────────

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

pub const Inner1 = enum { count, sum_all, sum01, inversion, max_cell, min01, mean01 };
pub const N_INNER1 = 7;
const inner1_name = [_][]const u8{ "count≥thr", "sum_all", "sum(c0,c1)", "inversion", "max_cell", "min(c0,c1)", "mean(c0,c1)" };

pub fn inner1Scalar(kind: Inner1, g: [NCELL]u8) f64 {
    return switch (kind) {
        .count => countGE(g),
        .sum_all => blk: {
            var s: u32 = 0;
            for (g) |v| s += v;
            break :blk @floatFromInt(s);
        },
        .sum01 => @floatFromInt(g[0] + g[1]),
        .inversion => @floatFromInt(inversionCount(g)),
        .max_cell => blk: {
            var m: u8 = 0;
            for (g) |v| m = @max(m, v);
            break :blk @floatFromInt(m);
        },
        .min01 => @floatFromInt(@min(g[0], g[1])),
        .mean01 => @as(f64, @floatFromInt(g[0] + g[1])) / 2.0,
    };
}

const Inner2 = enum { linear, lift_q, half_p, scan_p, bind_xy, bind_abs, bind_max };
const N_INNER2 = 7;
const inner2_name = [_][]const u8{ "linear(S)", "lift_q[S,S²]", "half_p(S mod 2)", "scan_p(cos ω·S)", "bind_xy(c0·c1)", "bind_abs|Δ01|", "bind_max(c0,c1)" };

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
    out[0] = @abs(@as(f64, @floatFromInt(g[0])) - @as(f64, @floatFromInt(g[1])));
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

fn evalScanP(S: []const f64, Y: []const f64) struct { tst: f64, omega: f64 } {
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
    return .{ .tst = cosAcc(S, Y, ab[0], ab[1], best_w, NVA, NSAMP), .omega = best_w };
}

const PipeResult = struct {
    inner1: Inner1,
    inner2: Inner2,
    val: f64,
    tst: f64,
    omega: f64,
};

fn evalPipeline(in1: Inner1, in2: Inner2, S: []const f64, grid: []const [NCELL]u8, Y: []const f64, X: [][]f64, w: []f64) PipeResult {
    if (in2 == .linear) {
        for (0..NSAMP) |s| X[s][0] = S[s];
        standardize(X, 1);
        fitLogit(X, Y, 1, 80, 0.05, w);
        return .{ .inner1 = in1, .inner2 = in2, .val = accRange(X, Y, w, 1, NTR, NVA), .tst = accRange(X, Y, w, 1, NVA, NSAMP), .omega = 0 };
    }
    if (in2 == .scan_p) {
        const r = evalScanP(S, Y);
        for (0..NSAMP) |s| {
            X[s][0] = S[s];
            X[s][1] = @cos(r.omega * S[s]);
        }
        standardize(X, 2);
        fitLogit(X, Y, 2, 80, 0.05, w);
        return .{ .inner1 = in1, .inner2 = in2, .val = accRange(X, Y, w, 2, NTR, NVA), .tst = accRange(X, Y, w, 2, NVA, NSAMP), .omega = r.omega };
    }
    const pack = inner2Pack(in2);
    const dim = 1 + pack.dim;
    for (0..NSAMP) |s| {
        X[s][0] = S[s];
        pack.fill(s, S[s], grid[s], X[s][1 .. 1 + pack.dim]);
    }
    standardize(X, dim);
    fitLogit(X, Y, dim, 80, 0.05, w);
    return .{ .inner1 = in1, .inner2 = in2, .val = accRange(X, Y, w, dim, NTR, NVA), .tst = accRange(X, Y, w, dim, NVA, NSAMP), .omega = 0 };
}

fn discoverPipeline(grid: []const [NCELL]u8, Y: []const f64, S_all: *const [N_INNER1][]f64, X: [][]f64, w: []f64) PipeResult {
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

fn stage1Best(grid: []const [NCELL]u8, Y: []const f64, S_all: *const [N_INNER1][]f64, X: [][]f64, w: []f64) struct { inner1: Inner1, tst: f64 } {
    var best_i1: Inner1 = .count;
    var best_tst: f64 = 0;
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        const r = evalPipeline(in1, .linear, S_all[i1i], grid, Y, X, w);
        if (r.tst > best_tst) {
            best_tst = r.tst;
            best_i1 = in1;
        }
    }
    return .{ .inner1 = best_i1, .tst = best_tst };
}

// ── Battery B (E1 patterns) ──────────────────────────────────────────────────

pub const BatteryKind = enum {
    random_monomial,
    sum_mod,
    sign_mod,
    walsh_subset,
    parity_of_count,
    oriented,
    composed_parity_and_sum,
    inversion_parity,
};

pub const BatteryTarget = struct {
    name: []const u8,
    kind: BatteryKind,
    mask: u8 = 0,
    modulus: usize = 0,
    walsh_s: u8 = 0,
    sum_mod: usize = 0,
};

pub fn labelBattery(g: [NCELL]u8, t: BatteryTarget) f64 {
    return switch (t.kind) {
        .random_monomial => if (phi(g, t.mask) > 0) 1.0 else 0.0,
        .sum_mod => if (gridSum(g) % t.modulus == 0) 1.0 else 0.0,
        .sign_mod => if (@as(usize, signPattern(g)) % t.modulus == 0) 1.0 else 0.0,
        .walsh_subset => blk: {
            var p: f64 = 1.0;
            for (0..NCELL) |i| {
                if (t.walsh_s & (@as(u8, 1) << @intCast(i)) != 0) {
                    p *= if (g[i] >= THRESH) 1.0 else -1.0;
                }
            }
            break :blk if (p > 0) 1.0 else 0.0;
        },
        .parity_of_count => @floatFromInt(@as(usize, @intFromFloat(countGE(g))) & 1),
        .oriented => if (g[1] > g[0]) 1.0 else 0.0,
        .composed_parity_and_sum => blk: {
            const c = @as(usize, @intFromFloat(countGE(g))) & 1;
            const sm = gridSum(g) % t.sum_mod == 0;
            break :blk if (c == 1 and sm) 1.0 else 0.0;
        },
        .inversion_parity => @floatFromInt(inversionCount(g) & 1),
    };
}

fn knownFamily(t: BatteryTarget) []const u8 {
    return switch (t.kind) {
        .random_monomial => "monomial-sign φ_S",
        .sum_mod => "world sum%mod",
        .sign_mod => "world sign%mod",
        .walsh_subset => "Walsh χ_S",
        .parity_of_count => "Z₂ on count (mod/spectral)",
        .oriented => "relational oriented",
        .composed_parity_and_sum => "AND(parity, sum%mod)",
        .inversion_parity => "Z₂ on inversion (pipeline/spectral)",
    };
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
        for (avoid) |a| {
            if (m == a) dup = true;
        }
        if (!dup and popcount(m) == deg) return m;
    }
    return 0x0F;
}

pub fn generateBatteryB(rand: std.Random, alloc: std.mem.Allocator) ![]BatteryTarget {
    var list = std.ArrayList(BatteryTarget).init(alloc);
    errdefer list.deinit();
    const m2 = randomMask(rand, 2, &ZOO_A_MASKS);
    try list.append(.{ .name = "B1 random monomial deg2", .kind = .random_monomial, .mask = m2 });
    const m3 = randomMask(rand, 3, &ZOO_A_MASKS);
    try list.append(.{ .name = "B2 random monomial deg3", .kind = .random_monomial, .mask = m3 });
    const mods = [_]usize{ 7, 11, 5, 3 };
    try list.append(.{ .name = "B3 sum(g) % 7", .kind = .sum_mod, .modulus = mods[0] });
    try list.append(.{ .name = "B4 sign%mod 11", .kind = .sign_mod, .modulus = mods[1] });
    const walsh_entries = [_]struct { name: []const u8, s: u8 }{
        .{ .name = "B5 Walsh χ{S=0x11}", .s = (1 << 0) | (1 << 4) },
        .{ .name = "B6 Walsh χ{S=0xA4}", .s = (1 << 2) | (1 << 5) | (1 << 7) },
        .{ .name = "B7 Walsh χ{S=0x0A}", .s = (1 << 1) | (1 << 3) },
    };
    for (walsh_entries) |we| try list.append(.{ .name = we.name, .kind = .walsh_subset, .walsh_s = we.s });
    try list.append(.{ .name = "B8 parity-of-count", .kind = .parity_of_count });
    try list.append(.{ .name = "B9 oriented v1>v0", .kind = .oriented });
    try list.append(.{ .name = "B10 parity AND sum%5", .kind = .composed_parity_and_sum, .sum_mod = 5 });
    try list.append(.{ .name = "B11 inversion parity", .kind = .inversion_parity });
    return try list.toOwnedSlice();
}

// ── Phase 1: train monomial forge on zoo A ───────────────────────────────────

pub fn trainZooA(X: [][]f64, grid: []const [NCELL]u8, Y: []const []f64, phiTgt: []f64, w: []f64, out: anytype) !struct { lib: [MAXFEAT]Feature, nlib: usize, solved: usize } {
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
                if (hasMonomial(lib[0..nlib], cand)) continue;
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

            for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], best_mask);
            buildFeat(X, grid, lib[0..nlib]);
            const cov_before = coverage(X, grid, lib[0..nlib], Y[t], w);
            var aug: [MAXFEAT]Feature = undefined;
            @memcpy(aug[0..nlib], lib[0..nlib]);
            aug[nlib] = .{ .monomial = best_mask };
            const cov_after = coverageWithExtra(X, grid, lib[0..nlib], phiTgt, Y[t], w);
            const r2 = reconR2(X, phiTgt, nlib, w);
            const escape = cov_after >= COVER and cov_before < COVER;
            const irreducible = r2 < R2_MAX;
            if (escape and irreducible and nlib < MAXFEAT) {
                lib[nlib] = .{ .monomial = best_mask };
                nlib += 1;
                promoted = true;
                try out.print("  round {d}: {s} → +φ(0x{X:0>2},deg{d}) escape {d:.2}→{d:.2} R²={d:.2}\n", .{
                    round + 1, ZOO_A_NAMES[t], best_mask, popcount(best_mask), cov_before, cov_after, r2,
                });
            }
        }
        if (!promoted) {
            try out.print("  round {d}: SATURATED → FREEZE\n", .{round + 1});
            break;
        }
    }

    var solved: usize = 0;
    try out.print("\n  zoo A final: ", .{});
    for (0..NZOO_A) |t| {
        const cov = coverage(X, grid, lib[0..nlib], Y[t], w);
        if (cov >= COVER) solved += 1;
        try out.print("{s}={d:.2}{s}  ", .{ ZOO_A_NAMES[t][0..2], cov, if (cov >= COVER) "*" else " " });
    }
    try out.print("→ {d}/{d} solved\n  FROZEN ({d} monomials)\n\n", .{ solved, NZOO_A, nlib });
    return .{ .lib = lib, .nlib = nlib, .solved = solved };
}

// ── Hardness probe (Q38 analog — E14 / E28) ─────────────────────────────────

const HardnessProbe = struct {
    mono_best: f64,
    extremal_best: f64,
    task_class: hr.TaskClass,
};

fn standardizeFeat(feat: []f64) void {
    var mu: f64 = 0;
    for (0..NTR) |s| mu += feat[s];
    mu /= @floatFromInt(NTR);
    var sd: f64 = 0;
    for (0..NTR) |s| sd += (feat[s] - mu) * (feat[s] - mu);
    sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
    for (0..NSAMP) |s| feat[s] = (feat[s] - mu) / sd;
}

fn probeFeatVal(feat: []f64, Y: []const f64) f64 {
    standardizeFeat(feat);
    return oml.accLogit(feat, Y, NTR, NTR, NVA);
}

fn probeExtremalHardness(grid: []const [NCELL]u8, Y: []const f64, feat: []f64) f64 {
    const probes = [_]struct { fill: *const fn ([NCELL]u8) f64 }{
        .{ .fill = struct {
            fn f(g: [NCELL]u8) f64 {
                var m: u8 = 0;
                for (g) |v| m = @max(m, v);
                return @floatFromInt(m);
            }
        }.f },
        .{ .fill = struct {
            fn f(g: [NCELL]u8) f64 {
                return if (g[1] > g[0]) 1.0 else 0.0;
            }
        }.f },
        .{ .fill = struct {
            fn f(g: [NCELL]u8) f64 {
                return countGE(g);
            }
        }.f },
    };
    var best: f64 = 0.5;
    for (probes) |p| {
        for (0..NSAMP) |s| feat[s] = p.fill(grid[s]);
        const v = probeFeatVal(feat, Y);
        if (v > best) best = v;
    }
    return best;
}

/// Hardness for Walsh gating uses **step-1 frozen** mono score (not oracle mask search)
/// plus extremal scalar probes — mirrors E14 Q38 on substrates actually available pre-escalation.
fn probeEscalationHardness(cov_frozen: f64, grid: []const [NCELL]u8, Y: []const f64, feat: []f64) HardnessProbe {
    const ext = probeExtremalHardness(grid, Y, feat);
    const tc: hr.TaskClass = if (cov_frozen >= SINGLE_SUFFICIENT or ext >= SINGLE_SUFFICIENT)
        .single_sufficient
    else if (cov_frozen <= MONO_SATURATE and ext <= MONO_SATURATE)
        .q38_compound
    else
        .unknown;
    return .{ .mono_best = cov_frozen, .extremal_best = ext, .task_class = tc };
}

fn taskClassName(tc: hr.TaskClass) []const u8 {
    return switch (tc) {
        .single_sufficient => "single_sufficient",
        .q38_compound => "q38_compound",
        .unknown => "unknown",
    };
}

// ── Step 3: pair hardness router (EXP-02 correlation rank + one verify) ───────

fn pairProductCorr(grid: []const [NCELL]u8, Y: []const f64, i: usize, j: usize) f64 {
    var sum_xy: f64 = 0;
    var sum_x: f64 = 0;
    var sum_y: f64 = 0;
    var sum_x2: f64 = 0;
    var sum_y2: f64 = 0;
    const n: f64 = @floatFromInt(NVA - NTR);
    for (NTR..NVA) |s| {
        const x = (@as(f64, @floatFromInt(grid[s][i])) - MID) *
            (@as(f64, @floatFromInt(grid[s][j])) - MID);
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

fn fillPairFeatures(pf: []const []f64, grid: []const [NCELL]u8, i: usize, j: usize) void {
    for (0..NSAMP) |s| {
        const ci: f64 = @floatFromInt(grid[s][i]);
        const cj: f64 = @floatFromInt(grid[s][j]);
        pf[s][0] = ci;
        pf[s][1] = cj;
        pf[s][2] = ci * cj;
    }
}

fn evalPair(
    pf: []const []f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    i: usize,
    j: usize,
    w: []f64,
) struct { val: f64, tst: f64 } {
    fillPairFeatures(pf, grid, i, j);
    standardize(@constCast(pf), 3);
    fitLogit(pf, Y, 3, 120, 0.04, w);
    return .{
        .val = accRange(pf, Y, w, 3, NTR, NVA),
        .tst = accRange(pf, Y, w, 3, NVA, NSAMP),
    };
}

fn discoverPair(
    grid: []const [NCELL]u8,
    Y: []const f64,
    pf: []const []f64,
    w: []f64,
) struct { i: usize, j: usize, val: f64, tst: f64 } {
    var best_i: usize = 0;
    var best_j: usize = 1;
    var best_corr: f64 = -1;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        const c = pairProductCorr(grid, Y, i, j);
        if (c > best_corr) {
            best_corr = c;
            best_i = i;
            best_j = j;
        }
    };
    const verified = evalPair(pf, grid, Y, best_i, best_j, w);
    return .{ .i = best_i, .j = best_j, .val = verified.val, .tst = verified.tst };
}

// ── Step 4: Walsh correlation argmax (q38_compound only) ────────────────────

fn discoverWalsh(
    grid: []const [NCELL]u8,
    Y: []const f64,
    feat: []f64,
) struct { bestS: u8, val: f64, tst: f64 } {
    const r = oml.discoverWalsh(grid, Y, feat, NTR, NVA, NSAMP);
    return .{ .bestS = r.bestS, .val = r.val, .tst = r.tst };
}

// ── Discovery on battery B (RQ1++ staged escalation) ─────────────────────────

const Method = enum { frozen_only, synth_prog, pipeline, pair_router, walsh_corr, saturated };

pub const EvalResult = struct {
    method: Method,
    test_acc: f64,
    certified: bool,
    escape: bool,
    irreducible: bool,
    label: []const u8,
    family_match: bool,
};

fn familyMatch(t: BatteryTarget, method: Method, label: []const u8, pipe: PipeResult) bool {
    _ = label;
    return switch (t.kind) {
        .parity_of_count => method == .synth_prog or (method == .pipeline and (pipe.inner2 == .half_p or pipe.inner2 == .scan_p)),
        .inversion_parity => method == .pipeline and pipe.inner1 == .inversion and (pipe.inner2 == .half_p or pipe.inner2 == .scan_p),
        .oriented => method == .frozen_only,
        .random_monomial => method == .frozen_only or method == .pair_router,
        .walsh_subset => method == .walsh_corr,
        .sum_mod, .sign_mod, .composed_parity_and_sum => false,
    };
}

pub fn buildInner1Store(alloc: std.mem.Allocator, grid: []const [NCELL]u8) ![N_INNER1][]f64 {
    var S_store: [N_INNER1][]f64 = undefined;
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        S_store[i1i] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| S_store[i1i][s] = inner1Scalar(in1, grid[s]);
    }
    return S_store;
}

pub const EvalCounter = struct {
    certify: usize = 0,
    probe: usize = 0,
    fit: usize = 0,
    pub fn total(self: EvalCounter) usize {
        return self.certify + self.probe + self.fit;
    }
};

pub fn needsMod(kind: BatteryKind) bool {
    return switch (kind) {
        .parity_of_count, .inversion_parity, .composed_parity_and_sum => true,
        else => false,
    };
}

/// Mod/synth/pipeline escalation only (steps 2 of RQ1 ladder).
pub fn tryModEscalation(
    X: [][]f64,
    grid: []const [NCELL]u8,
    frozen: []const Feature,
    Y: []const f64,
    bank: ProgBank,
    S_all: *const [N_INNER1][]f64,
    w: []f64,
    cov0: f64,
    tgt: BatteryTarget,
    out: anytype,
    budget: ?*EvalCounter,
) !?EvalResult {
    const synth = discoverSynth(grid, Y, bank, X, w);
    if (budget) |b| {
        b.probe += bank.nodes.len;
        b.fit += 1;
    }
    const cov_synth = coverageWithExtra(X, grid, frozen, synth.feat, Y, w);
    if (budget) |b| b.certify += 1;
    buildFeat(X, grid, frozen);
    const r2_synth = reconR2(X, synth.feat, frozen.len, w);
    const synth_cert = cov_synth >= COVER and cov0 < COVER and r2_synth < R2_MAX;

    const pipe = discoverPipeline(grid, Y, S_all, X, w);
    if (budget) |b| b.probe += N_INNER1 * N_INNER2;
    const s1 = stage1Best(grid, Y, S_all, X, w);
    if (budget) |b| b.probe += N_INNER1;
    const pipe_escape = pipe.tst >= COVER and s1.tst < STAGE1_MAX;

    var best_acc = cov0;
    var best: ?EvalResult = null;

    if (synth_cert and cov_synth > best_acc) {
        best_acc = cov_synth;
        best = .{
            .method = .synth_prog,
            .test_acc = cov_synth,
            .certified = true,
            .escape = true,
            .irreducible = r2_synth < R2_MAX,
            .label = bank.names[synth.prog_id],
            .family_match = familyMatch(tgt, .synth_prog, bank.names[synth.prog_id], pipe),
        };
    } else if (cov_synth >= COVER and cov_synth > best_acc) {
        best_acc = cov_synth;
        best = .{
            .method = .synth_prog,
            .test_acc = cov_synth,
            .certified = true,
            .escape = cov0 < COVER,
            .irreducible = r2_synth < R2_MAX,
            .label = bank.names[synth.prog_id],
            .family_match = familyMatch(tgt, .synth_prog, bank.names[synth.prog_id], pipe),
        };
    }

    if (pipe.tst >= COVER and pipe.tst > best_acc) {
        var plabel_buf: [96]u8 = undefined;
        const plabel = if (pipe.inner2 == .scan_p)
            std.fmt.bufPrint(&plabel_buf, "{s}→{s}(ω={d:.3})", .{ inner1_name[@intFromEnum(pipe.inner1)], inner2_name[@intFromEnum(pipe.inner2)], pipe.omega }) catch "pipe"
        else
            std.fmt.bufPrint(&plabel_buf, "{s}→{s}", .{ inner1_name[@intFromEnum(pipe.inner1)], inner2_name[@intFromEnum(pipe.inner2)] }) catch "pipe";
        best = .{
            .method = .pipeline,
            .test_acc = pipe.tst,
            .certified = true,
            .escape = pipe_escape,
            .irreducible = pipe_escape,
            .label = plabel,
            .family_match = familyMatch(tgt, .pipeline, plabel, pipe),
        };
    }

    std.heap.page_allocator.free(synth.feat);
    if (best) |b| {
        try out.print("    mod-escalation: {s} test={d:.3}\n", .{ @tagName(b.method), b.test_acc });
    }
    return best;
}

/// Pair-router + conditional Walsh only (steps 3–4).
pub fn tryPairWalshEscalation(
    grid: []const [NCELL]u8,
    frozen: []const Feature,
    Y: []const f64,
    pf: []const []f64,
    feat: []f64,
    w: []f64,
    cov0: f64,
    tgt: BatteryTarget,
    out: anytype,
    budget: ?*EvalCounter,
) !?EvalResult {
    _ = frozen;
    const pair = discoverPair(grid, Y, pf, w);
    if (budget) |b| {
        b.probe += 28;
        b.fit += 1;
    }
    if (pair.tst >= COVER) {
        var pair_label_buf: [48]u8 = undefined;
        const pair_label = std.fmt.bufPrint(&pair_label_buf, "φ({d},{d}) product inner", .{ pair.i, pair.j }) catch "pair";
        try out.print("    pair-router: ({d},{d}) test={d:.3}\n", .{ pair.i, pair.j, pair.tst });
        return .{
            .method = .pair_router,
            .test_acc = pair.tst,
            .certified = true,
            .escape = cov0 < COVER,
            .irreducible = true,
            .label = pair_label,
            .family_match = familyMatch(tgt, .pair_router, pair_label, .{ .inner1 = .count, .inner2 = .linear, .val = 0, .tst = 0, .omega = 0 }),
        };
    }

    const hp = probeEscalationHardness(cov0, grid, Y, feat);
    if (hp.task_class == .q38_compound) {
        const wal = discoverWalsh(grid, Y, feat);
        if (budget) |b| {
            b.probe += 256;
            b.fit += 1;
        }
        if (wal.tst >= COVER) {
            var wal_label_buf: [32]u8 = undefined;
            const wal_label = std.fmt.bufPrint(&wal_label_buf, "χ(0x{X:0>2})", .{wal.bestS}) catch "walsh";
            try out.print("    Walsh: {s} test={d:.3}\n", .{ wal_label, wal.tst });
            return .{
                .method = .walsh_corr,
                .test_acc = wal.tst,
                .certified = true,
                .escape = cov0 < COVER,
                .irreducible = true,
                .label = wal_label,
                .family_match = familyMatch(tgt, .walsh_corr, wal_label, .{ .inner1 = .count, .inner2 = .linear, .val = 0, .tst = 0, .omega = 0 }),
            };
        }
    }
    return null;
}

pub fn evaluateBlind(
    X: [][]f64,
    grid: []const [NCELL]u8,
    frozen: []const Feature,
    Y: []const f64,
    bank: ProgBank,
    S_all: *const [N_INNER1][]f64,
    pf: []const []f64,
    feat: []f64,
    w: []f64,
    tgt: BatteryTarget,
    out: anytype,
    budget: ?*EvalCounter,
) !EvalResult {
    const cov0 = coverage(X, grid, frozen, Y, w);
    if (budget) |b| b.fit += 1;
    try out.print("    frozen-only test={d:.3}\n", .{cov0});
    if (cov0 >= COVER) {
        try out.print("    → SOLVED (frozen monomial library)\n", .{});
        return .{
            .method = .frozen_only,
            .test_acc = cov0,
            .certified = true,
            .escape = false,
            .irreducible = false,
            .label = "frozen monomials",
            .family_match = familyMatch(tgt, .frozen_only, "frozen", .{ .inner1 = .count, .inner2 = .linear, .val = 0, .tst = 0, .omega = 0 }),
        };
    }

    const synth = discoverSynth(grid, Y, bank, X, w);
    if (budget) |b| {
        b.probe += bank.nodes.len;
        b.fit += 1;
    }
    const cov_synth = coverageWithExtra(X, grid, frozen, synth.feat, Y, w);
    if (budget) |b| b.certify += 1;
    buildFeat(X, grid, frozen);
    const r2_synth = reconR2(X, synth.feat, frozen.len, w);
    const synth_escape = cov_synth >= COVER and cov0 < COVER;
    const synth_irred = r2_synth < R2_MAX;
    const synth_cert = synth_escape and synth_irred;
    try out.print("    synth best: {s} val={d:.3} test={d:.3} R²={d:.3} escape={} irred={}\n", .{
        bank.names[synth.prog_id], synth.val_acc, cov_synth, r2_synth, synth_escape, synth_irred,
    });

    const pipe = discoverPipeline(grid, Y, S_all, X, w);
    if (budget) |b| b.probe += N_INNER1 * N_INNER2;
    const s1 = stage1Best(grid, Y, S_all, X, w);
    if (budget) |b| b.probe += N_INNER1;
    const pipe_escape = pipe.tst >= COVER and s1.tst < STAGE1_MAX;
    try out.print("    pipeline: {s}→{s} val={d:.3} test={d:.3} stage1={d:.3} escape={}\n", .{
        inner1_name[@intFromEnum(pipe.inner1)],
        inner2_name[@intFromEnum(pipe.inner2)],
        pipe.val,
        pipe.tst,
        s1.tst,
        pipe_escape,
    });

    var best_acc = cov0;
    var best: EvalResult = .{
        .method = .saturated,
        .test_acc = cov0,
        .certified = false,
        .escape = false,
        .irreducible = false,
        .label = "none",
        .family_match = false,
    };

    if (synth_cert and cov_synth > best_acc) {
        best_acc = cov_synth;
        best = .{
            .method = .synth_prog,
            .test_acc = cov_synth,
            .certified = true,
            .escape = true,
            .irreducible = synth_irred,
            .label = bank.names[synth.prog_id],
            .family_match = familyMatch(tgt, .synth_prog, bank.names[synth.prog_id], pipe),
        };
    } else if (cov_synth >= COVER and cov_synth > best_acc) {
        best_acc = cov_synth;
        best = .{
            .method = .synth_prog,
            .test_acc = cov_synth,
            .certified = true,
            .escape = synth_escape,
            .irreducible = synth_irred,
            .label = bank.names[synth.prog_id],
            .family_match = familyMatch(tgt, .synth_prog, bank.names[synth.prog_id], pipe),
        };
    }

    if (pipe.tst >= COVER and pipe.tst > best_acc) {
        var plabel_buf: [96]u8 = undefined;
        const plabel = if (pipe.inner2 == .scan_p)
            std.fmt.bufPrint(&plabel_buf, "{s}→{s}(ω={d:.3})", .{ inner1_name[@intFromEnum(pipe.inner1)], inner2_name[@intFromEnum(pipe.inner2)], pipe.omega }) catch "pipe"
        else
            std.fmt.bufPrint(&plabel_buf, "{s}→{s}", .{ inner1_name[@intFromEnum(pipe.inner1)], inner2_name[@intFromEnum(pipe.inner2)] }) catch "pipe";
        best_acc = pipe.tst;
        best = .{
            .method = .pipeline,
            .test_acc = pipe.tst,
            .certified = true,
            .escape = pipe_escape,
            .irreducible = pipe_escape,
            .label = plabel,
            .family_match = familyMatch(tgt, .pipeline, plabel, pipe),
        };
    }

    if (!best.certified) {
        try out.print("    step 3 pair-router: escalating\n", .{});
        const pair = discoverPair(grid, Y, pf, w);
        if (budget) |b| {
            b.probe += 28;
            b.fit += 1;
        }
        var pair_label_buf: [48]u8 = undefined;
        const pair_label = std.fmt.bufPrint(&pair_label_buf, "φ({d},{d}) product inner", .{ pair.i, pair.j }) catch "pair";
        try out.print("    pair-router: ({d},{d}) val={d:.3} test={d:.3}\n", .{ pair.i, pair.j, pair.val, pair.tst });
        if (pair.tst >= COVER and pair.tst > best_acc) {
            best_acc = pair.tst;
            best = .{
                .method = .pair_router,
                .test_acc = pair.tst,
                .certified = true,
                .escape = cov0 < COVER,
                .irreducible = true,
                .label = pair_label,
                .family_match = familyMatch(tgt, .pair_router, pair_label, pipe),
            };
        }
    }

    if (!best.certified) {
        const hp = probeEscalationHardness(cov0, grid, Y, feat);
        try out.print("    hardness: mono={d:.3} ext={d:.3} class={s}\n", .{
            hp.mono_best, hp.extremal_best, taskClassName(hp.task_class),
        });
        if (hp.task_class == .q38_compound) {
            try out.print("    step 4 Walsh: q38_compound → correlation argmax\n", .{});
            const wal = discoverWalsh(grid, Y, feat);
            if (budget) |b| {
                b.probe += 256;
                b.fit += 1;
            }
            var wal_label_buf: [32]u8 = undefined;
            const wal_label = std.fmt.bufPrint(&wal_label_buf, "χ(0x{X:0>2})", .{wal.bestS}) catch "walsh";
            try out.print("    Walsh: {s} val={d:.3} test={d:.3}\n", .{ wal_label, wal.val, wal.tst });
            if (wal.tst >= COVER and wal.tst > best_acc) {
                best_acc = wal.tst;
                best = .{
                    .method = .walsh_corr,
                    .test_acc = wal.tst,
                    .certified = true,
                    .escape = cov0 < COVER,
                    .irreducible = true,
                    .label = wal_label,
                    .family_match = familyMatch(tgt, .walsh_corr, wal_label, pipe),
                };
            }
        } else {
            try out.print("    step 4 Walsh: skipped (not q38_compound)\n", .{});
        }
    }

    if (best.certified) {
        try out.print("    → CERTIFIED {s} via {s} (test={d:.3}, family_match={})\n", .{
            if (best.family_match) "✓" else "~",
            @tagName(best.method),
            best.test_acc,
            best.family_match,
        });
        try out.print("      discovered: {s}\n", .{best.label});
    } else {
        try out.print("    → SATURATED (best test={d:.3} < {d:.2})\n", .{ best_acc, COVER });
    }

    std.heap.page_allocator.free(synth.feat);
    return best;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const bank = try buildProgBank(alloc);

    var prng = std.Random.DefaultPrng.init(GRID_SEED);
    const rand = prng.random();
    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| {
        for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    }

    const X = try alloc.alloc([]f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT + 1);
    var w: [MAXFEAT + 2]f64 = undefined;

    const Yzoo = try alloc.alloc([]f64, NZOO_A);
    for (0..NZOO_A) |t| {
        Yzoo[t] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Yzoo[t][s] = if (phi(grid[s], ZOO_A_MASKS[t]) > 0) 1.0 else 0.0;
    }

    var S_store: [N_INNER1][]f64 = undefined;
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        S_store[i1i] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| S_store[i1i][s] = inner1Scalar(in1, grid[s]);
    }

    const pf = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| pf[s] = try alloc.alloc(f64, 3);
    const feat_scratch = try alloc.alloc(f64, NSAMP);

    try out.print("=== RESEARCH Q1++: staged escalation (no handed menu) ===\n\n", .{});
    try out.print("Grid seed 0x{X:0>16} | battery seed 0x{X:0>16}\n", .{ GRID_SEED, BATTERY_SEED });
    try out.print("Ladder: monomial → mod/pipeline → pair-router → Walsh (q38_compound only)\n", .{});
    try out.print("Excluded: spectral peak, Clifford, world pool, pre-labeled operator menu\n", .{});
    try out.print("Program bank: {d} expressions | PASS: ≥10/11 battery B at test ≥{d:.2}\n\n", .{ bank.nodes.len, COVER });

    const trained = try trainZooA(X, grid, Yzoo, phiTgt, &w, out);
    const frozen = trained.lib[0..trained.nlib];

    var bprng = std.Random.DefaultPrng.init(BATTERY_SEED);
    const battery = try generateBatteryB(bprng.random(), alloc);

    try out.print("── Phase 2: blind battery B ({d} targets) — RQ1++ staged escalation ──\n\n", .{battery.len});

    var n_cert: usize = 0;
    var n_saturated: usize = 0;
    var n_family_match: usize = 0;
    var n_step1: usize = 0;
    var n_step2: usize = 0;
    var n_step3: usize = 0;
    var n_step4: usize = 0;

    for (battery) |tgt| {
        const Yb = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Yb[s] = labelBattery(grid[s], tgt);
        try out.print("  TARGET: {s} [{s}] known={s}\n", .{ tgt.name, @tagName(tgt.kind), knownFamily(tgt) });
        const ev = try evaluateBlind(X, grid, frozen, Yb, bank, &S_store, pf, feat_scratch, &w, tgt, out, null);
        if (ev.certified) {
            n_cert += 1;
            if (ev.family_match) n_family_match += 1;
            switch (ev.method) {
                .frozen_only => n_step1 += 1,
                .synth_prog, .pipeline => n_step2 += 1,
                .pair_router => n_step3 += 1,
                .walsh_corr => n_step4 += 1,
                .saturated => {},
            }
        } else n_saturated += 1;
        try out.print("\n", .{});
    }

    try out.print("════════════════════ BATTERY B SUMMARY ════════════════════\n", .{});
    try out.print("  certified (test ≥{d:.2}): {d}/{d}\n", .{ COVER, n_cert, battery.len });
    try out.print("  saturated:                {d}/{d}\n", .{ n_saturated, battery.len });
    try out.print("  faithful family match:    {d}/{d}\n", .{ n_family_match, n_cert });
    try out.print("  closed by step 1 (mono):  {d}\n", .{n_step1});
    try out.print("  closed by step 2 (mod):   {d}\n", .{n_step2});
    try out.print("  closed by step 3 (pair):  {d}\n", .{n_step3});
    try out.print("  closed by step 4 (Walsh): {d}\n\n", .{n_step4});

    const pass = n_cert >= 10;
    try out.print("VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
    if (pass) {
        try out.print("  {d}/{d} blind targets certified via staged auto-escalation (no handed menu).\n", .{ n_cert, battery.len });
    } else {
        try out.print("  No battery-B target reached {d:.2} after full escalation ladder.\n", .{COVER});
    }

    try out.print("\nSee: swarm_fork_rq1_escalation.md, open_invention_rq1.md\n", .{});
    _ = RQ1_TAG;
}