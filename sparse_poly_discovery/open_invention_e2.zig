//! EXPERIMENT E2 — POET-lite adversarial target generator.
//!
//! A task population mutates grid predicates (mask, mod, parity-on-transform, rank-stat, XOR cells).
//! Keep a candidate iff the forge *library* (8 singleton monomials, no oracle cheats) scores <0.60 held-out
//! AND an evaluation-only *oracle* (ground-truth feature for the spec, not in the forge search menu) ≥0.95.
//!
//! Then run the open forge (monomial → operator menu → world pool) WITHOUT oracle features and measure
//! whether forge coverage matches oracle — i.e. can search close the gap without peeking at the answer?
//!
//! Run: zig build open-invention-e2 --release=fast

const std = @import("std");
const oml = @import("operator_menu_lib.zig");

pub const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
pub const NSAMP: usize = 7000;
pub const NTR: usize = 3500;
pub const NVA: usize = 5250;
const DOM: usize = 1 << NCELL;
pub const MAXFEAT: usize = 32;
const MAXDEG: usize = 4;
const MAXOPS: usize = 8;
const MAXKEPT: usize = 24;
const MAXATOMS: usize = 24;

const LIB_THRESH: f64 = 0.60;
pub const ORACLE_THRESH: f64 = 0.95;
pub const FORGE_THRESH: f64 = 0.90;
const R2_MAX: f64 = 0.40;
pub const RNG_SEED: u64 = 0xE2C0FFEE20260629;

const WORLD_POOL = [_]usize{ 2, 3, 5, 7, 11, 13 };

// ── Predicate spec (the POET-lite genome) ────────────────────────────────────

pub const PredKind = enum {
    monomial_sign,
    sum_mod,
    sign_mod,
    parity_count,
    parity_xor,
    xor_cells,
    rank_stat,
};

pub const RankKind = enum { median_eq1, rank2_eq1 };

pub const PredSpec = struct {
    kind: PredKind,
    mask: u8 = 0,
    modulus: u8 = 2,
    cells: [3]u8 = .{ 0, 1, 2 },
    rank_kind: RankKind = .median_eq1,

    fn key(self: PredSpec) u64 {
        var k: u64 = @intFromEnum(self.kind);
        k = (k << 8) | self.mask;
        k = (k << 8) | self.modulus;
        k = (k << 8) | (@as(u64, self.cells[0]) << 16) | (@as(u64, self.cells[1]) << 8) | self.cells[2];
        k = (k << 8) | @intFromEnum(self.rank_kind);
        return k;
    }

    pub fn fmt(self: PredSpec, buf: []u8) []const u8 {
        return switch (self.kind) {
            .monomial_sign => std.fmt.bufPrint(buf, "sign φ{{mask=0x{X:0>2}}}", .{self.mask}) catch "?",
            .sum_mod => std.fmt.bufPrint(buf, "sum(g)%{d}==0", .{self.modulus}) catch "?",
            .sign_mod => std.fmt.bufPrint(buf, "sign%mod_{d}", .{self.modulus}) catch "?",
            .parity_count => "parity(#≥THRESH)",
            .parity_xor => std.fmt.bufPrint(buf, "parity(XOR mask=0x{X:0>2})", .{self.mask}) catch "?",
            .xor_cells => std.fmt.bufPrint(buf, "XOR(mask=0x{X:0>2})&1", .{self.mask}) catch "?",
            .rank_stat => blk: {
                const tag: []const u8 = switch (self.rank_kind) {
                    .median_eq1 => "med==1",
                    .rank2_eq1 => "rank2==1",
                };
                break :blk std.fmt.bufPrint(buf, "{s}({d},{d},{d})", .{ tag, self.cells[0], self.cells[1], self.cells[2] }) catch "?";
            },
        };
    }
};

pub const KeptTarget = struct {
    spec: PredSpec,
    lib_cov: f64,
    oracle_cov: f64,
    forge_cov: f64 = 0,
    forge_solved: bool = false,
};

pub const E2Summary = struct {
    mutations_tried: usize,
    targets_kept: usize,
    forge_solved: usize,
    oracle_only: usize,
    forge_matched: usize,
    pass: bool,
};

// ── Grid helpers ───────────────────────────────────────────────────────────────

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

fn xorMasked(g: [NCELL]u8, mask: u8) u8 {
    var x: u8 = 0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) x ^= g[i];
    }
    return x;
}

fn median3vals(a: u8, b: u8, c: u8) u8 {
    if ((a <= b and b <= c) or (c <= b and b <= a)) return b;
    if ((b <= a and a <= c) or (c <= a and a <= b)) return a;
    return c;
}

fn rank2Triple(a: u8, b: u8, c: u8) u8 {
    var s = [_]u8{ a, b, c };
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    return s[1];
}

pub fn label(g: [NCELL]u8, spec: PredSpec) f64 {
    return switch (spec.kind) {
        .monomial_sign => if (phi(g, spec.mask) > 0) 1.0 else 0.0,
        .sum_mod => if (gridSum(g) % spec.modulus == 0) 1.0 else 0.0,
        .sign_mod => if (@as(usize, signPattern(g)) % spec.modulus == 0) 1.0 else 0.0,
        .parity_count => blk: {
            var c: usize = 0;
            for (g) |v| {
                if (v >= THRESH) c += 1;
            }
            break :blk @floatFromInt(c & 1);
        },
        .parity_xor, .xor_cells => @floatFromInt(xorMasked(g, spec.mask) & 1),
        .rank_stat => blk: {
            const i: usize = spec.cells[0] % 8;
            const j: usize = spec.cells[1] % 8;
            const k: usize = spec.cells[2] % 8;
            break :blk switch (spec.rank_kind) {
                .median_eq1 => if (median3vals(g[i], g[j], g[k]) == 1) 1.0 else 0.0,
                .rank2_eq1 => if (rank2Triple(g[i], g[j], g[k]) == 1) 1.0 else 0.0,
            };
        },
    };
}

fn chanceRate(Y: []const f64, lo: usize, hi: usize) f64 {
    var pos: usize = 0;
    for (lo..hi) |s| {
        if (Y[s] > 0.5) pos += 1;
    }
    const p = @as(f64, @floatFromInt(pos)) / @as(f64, @floatFromInt(hi - lo));
    return @max(p, 1.0 - p);
}

// ── Feature libraries: forge (searchable) vs oracle (eval-only) ────────────────

const ForgeTag = enum {
    monomial,
    spectral_count,
    walsh,
    clifford_g2,
    world_sum_mod,
    world_sign_mod,
    xor_popcount,
};

const ForgeFeat = union(ForgeTag) {
    monomial: u8,
    spectral_count: f64,
    walsh: u8,
    clifford_g2: void,
    world_sum_mod: usize,
    world_sign_mod: usize,
    xor_popcount: u8,
};

const OracleTag = enum {
    ground_truth,
    xor_cells,
    rank_median_eq1,
    rank2_eq1,
};

const OracleFeat = union(OracleTag) {
    ground_truth: void,
    xor_cells: u8,
    rank_median_eq1: [3]u8,
    rank2_eq1: [3]u8,
};

fn cliffordG2(g: [NCELL]u8) f64 {
    const v0: f64 = @floatFromInt(g[0]);
    const v1: f64 = @floatFromInt(g[1]);
    return @sin(0.40 * (v1 - v0));
}

fn chi(S: u8, p: u8) f64 {
    const neg = @popCount(S & ~p);
    return if (neg & 1 == 0) 1.0 else -1.0;
}

/// Minimal GF(2) readout: XOR masked cell values, LSB parity (matches E2 xor_cells label).
pub fn xorPopcountReadout(g: [NCELL]u8, mask: u8) f64 {
    var x: u8 = 0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) x ^= g[i];
    }
    return @floatFromInt(x & 1);
}

fn evalForge(f: ForgeFeat, g: [NCELL]u8) f64 {
    return switch (f) {
        .monomial => |m| phi(g, m),
        .spectral_count => |w| @cos(w * countGE(g)),
        .walsh => |S| chi(S, signPattern(g)),
        .clifford_g2 => cliffordG2(g),
        .world_sum_mod => |p| if (gridSum(g) % p == 0) @as(f64, 1) else 0,
        .world_sign_mod => |p| if (@as(usize, signPattern(g)) % p == 0) @as(f64, 1) else 0,
        .xor_popcount => |m| xorPopcountReadout(g, m),
    };
}

fn evalOracle(f: OracleFeat, g: [NCELL]u8, spec: PredSpec) f64 {
    return switch (f) {
        .ground_truth => oracleGroundTruth(g, spec),
        .xor_cells => |m| @floatFromInt(xorMasked(g, m) & 1),
        .rank_median_eq1 => |cells| blk: {
            const i: usize = cells[0] % 8;
            const j: usize = cells[1] % 8;
            const k: usize = cells[2] % 8;
            break :blk if (median3vals(g[i], g[j], g[k]) == 1) 1.0 else 0.0;
        },
        .rank2_eq1 => |cells| blk: {
            const i: usize = cells[0] % 8;
            const j: usize = cells[1] % 8;
            const k: usize = cells[2] % 8;
            break :blk if (rank2Triple(g[i], g[j], g[k]) == 1) 1.0 else 0.0;
        },
    };
}

fn oracleGroundTruth(g: [NCELL]u8, spec: PredSpec) f64 {
    return switch (spec.kind) {
        .monomial_sign => phi(g, spec.mask),
        .sum_mod => if (gridSum(g) % spec.modulus == 0) 1.0 else 0.0,
        .sign_mod => if (@as(usize, signPattern(g)) % spec.modulus == 0) 1.0 else 0.0,
        .parity_count => blk: {
            var c: usize = 0;
            for (g) |v| {
                if (v >= THRESH) c += 1;
            }
            break :blk @floatFromInt(c & 1);
        },
        .parity_xor, .xor_cells => @floatFromInt(xorMasked(g, spec.mask)),
        .rank_stat => blk: {
            const i: usize = spec.cells[0] % 8;
            const j: usize = spec.cells[1] % 8;
            const k: usize = spec.cells[2] % 8;
            break :blk switch (spec.rank_kind) {
                .median_eq1 => if (median3vals(g[i], g[j], g[k]) == 1) 1.0 else -1.0,
                .rank2_eq1 => if (rank2Triple(g[i], g[j], g[k]) == 1) 1.0 else -1.0,
            };
        },
    };
}

fn oracleFeaturesFor(spec: PredSpec) [4]OracleFeat {
    return switch (spec.kind) {
        .monomial_sign, .sum_mod, .sign_mod, .parity_count => .{
            .{ .ground_truth = {} },
            .{ .ground_truth = {} },
            .{ .ground_truth = {} },
            .{ .ground_truth = {} },
        },
        .parity_xor, .xor_cells => .{
            .{ .xor_cells = spec.mask },
            .{ .ground_truth = {} },
            .{ .ground_truth = {} },
            .{ .ground_truth = {} },
        },
        .rank_stat => switch (spec.rank_kind) {
            .median_eq1 => .{
                .{ .rank_median_eq1 = spec.cells },
                .{ .ground_truth = {} },
                .{ .ground_truth = {} },
                .{ .ground_truth = {} },
            },
            .rank2_eq1 => .{
                .{ .rank2_eq1 = spec.cells },
                .{ .ground_truth = {} },
                .{ .ground_truth = {} },
                .{ .ground_truth = {} },
            },
        },
    };
}

fn forgeFeaturesEqual(a: ForgeFeat, b: ForgeFeat) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .monomial => |m| b.monomial == m,
        .spectral_count => |wa| @abs(wa - b.spectral_count) < 1e-6,
        .walsh => |S| b.walsh == S,
        .clifford_g2 => true,
        .world_sum_mod => |p| b.world_sum_mod == p,
        .world_sign_mod => |p| b.world_sign_mod == p,
        .xor_popcount => |m| b.xor_popcount == m,
    };
}

fn hasForgeFeature(lib: []const ForgeFeat, f: ForgeFeat) bool {
    for (lib) |x| if (forgeFeaturesEqual(x, f)) return true;
    return false;
}

// ── ML helpers ───────────────────────────────────────────────────────────────

fn buildForgeFeat(X: [][]f64, grid: []const [NCELL]u8, lib: []const ForgeFeat) void {
    const k = lib.len;
    for (0..NSAMP) |s| {
        for (0..k) |c| X[s][c] = evalForge(lib[c], grid[s]);
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

fn buildOracleFeat(X: [][]f64, grid: []const [NCELL]u8, lib: []const OracleFeat, spec: PredSpec) void {
    const k = lib.len;
    for (0..NSAMP) |s| {
        for (0..k) |c| X[s][c] = evalOracle(lib[c], grid[s], spec);
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

fn coverageForge(X: [][]f64, grid: []const [NCELL]u8, lib: []const ForgeFeat, Y: []const f64, w: []f64) f64 {
    buildForgeFeat(X, grid, lib);
    fitLogit(X, Y, lib.len, 150, 0.05, w);
    return accLogit(X, Y, w, lib.len, NVA, NSAMP);
}

fn coverageOracle(X: [][]f64, grid: []const [NCELL]u8, spec: PredSpec, Y: []const f64, w: []f64) f64 {
    const feats = oracleFeaturesFor(spec);
    const lib = feats[0..1];
    buildOracleFeat(X, grid, lib, spec);
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
    mu /= @as(f64, @floatFromInt(NSAMP - NVA));
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

fn baseLibrary() [NCELL]ForgeFeat {
    var lib: [NCELL]ForgeFeat = undefined;
    for (0..NCELL) |i| lib[i] = .{ .monomial = @as(u8, 1) << @intCast(i) };
    return lib;
}

// ── POET-lite mutations ───────────────────────────────────────────────────────

fn mutateSpec(spec: PredSpec, rand: std.Random) PredSpec {
    var s = spec;
    switch (rand.intRangeAtMost(u8, 0, 4)) {
        0 => {
            const bit: u3 = @intCast(rand.intRangeAtMost(u8, 0, 7));
            s.mask ^= @as(u8, 1) << bit;
            if (s.mask == 0) {
                const b: u3 = @intCast(rand.intRangeAtMost(u8, 0, 7));
                s.mask = @as(u8, 1) << b;
            }
            if (s.kind == .monomial_sign or s.kind == .parity_xor or s.kind == .xor_cells) {} else s.kind = .monomial_sign;
        },
        1 => {
            const mods = [_]u8{ 2, 3, 5, 7, 11 };
            s.modulus = mods[rand.intRangeAtMost(usize, 0, mods.len - 1)];
            s.kind = if (rand.boolean()) .sum_mod else .sign_mod;
        },
        2 => {
            const kinds = [_]PredKind{ .parity_count, .parity_xor, .xor_cells };
            s.kind = kinds[rand.intRangeAtMost(usize, 0, kinds.len - 1)];
            if (s.mask == 0) {
                const b: u3 = @intCast(rand.intRangeAtMost(u8, 0, 7));
                s.mask = @as(u8, 1) << b;
            }
        },
        3 => {
            s.kind = .rank_stat;
            s.cells[0] = rand.intRangeAtMost(u8, 0, 7);
            s.cells[1] = rand.intRangeAtMost(u8, 0, 7);
            s.cells[2] = rand.intRangeAtMost(u8, 0, 7);
            s.rank_kind = if (rand.boolean()) .median_eq1 else .rank2_eq1;
        },
        4 => {
            s.kind = .xor_cells;
            const bit: u3 = @intCast(rand.intRangeAtMost(u8, 0, 7));
            s.mask ^= @as(u8, 1) << bit;
            if (s.mask == 0) s.mask = 0xFF;
        },
        else => {},
    }
    return s;
}

const SEED_SPECS = [_]PredSpec{
    .{ .kind = .monomial_sign, .mask = (1 << 2) | (1 << 5) },
    .{ .kind = .monomial_sign, .mask = (1 << 1) | (1 << 3) | (1 << 6) },
    .{ .kind = .parity_count },
    .{ .kind = .sum_mod, .modulus = 7 },
    .{ .kind = .sign_mod, .modulus = 3 },
    .{ .kind = .xor_cells, .mask = 0x0F },
    .{ .kind = .parity_xor, .mask = 0x33 },
    .{ .kind = .rank_stat, .cells = .{ 0, 1, 2 }, .rank_kind = .median_eq1 },
    .{ .kind = .rank_stat, .cells = .{ 2, 4, 6 }, .rank_kind = .rank2_eq1 },
};

// ── Forge loop (no oracle features in search menu) ───────────────────────────

const CertResult = struct { ok: bool, cov_before: f64, cov_after: f64, r2: f64 };

fn certifyForge(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []const ForgeFeat,
    cand: ForgeFeat,
    Y: []const f64,
    scratch: []f64,
    w: []f64,
) CertResult {
    const cov_before = coverageForge(X, grid, lib, Y, w);
    var aug: [MAXFEAT]ForgeFeat = undefined;
    @memcpy(aug[0..lib.len], lib);
    aug[lib.len] = cand;
    const cov_after = coverageForge(X, grid, aug[0 .. lib.len + 1], Y, w);
    for (0..NSAMP) |s| scratch[s] = evalForge(cand, grid[s]);
    buildForgeFeat(X, grid, lib);
    const r2 = reconR2(X, scratch, lib.len, w);
    return .{
        .ok = cov_after >= FORGE_THRESH and cov_before < FORGE_THRESH and r2 < R2_MAX,
        .cov_before = cov_before,
        .cov_after = cov_after,
        .r2 = r2,
    };
}

fn tryMonomialForge(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []ForgeFeat,
    nlib: *usize,
    Y: []const f64,
    scratch: []f64,
    w: []f64,
) bool {
    var only_mono = true;
    for (lib[0..nlib.*]) |f| switch (f) {
        .monomial => {},
        else => only_mono = false,
    };
    if (!only_mono) return false;

    var best_val: f64 = -1;
    var best_mask: u8 = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const cand: u8 = @intCast(mm);
        const d = popcount(cand);
        if (d < 1 or d > MAXDEG) continue;
        if (hasForgeFeature(lib[0..nlib.*], .{ .monomial = cand })) continue;
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
    const cand_feat: ForgeFeat = .{ .monomial = best_mask };
    const cert = certifyForge(X, grid, lib[0..nlib.*], cand_feat, Y, scratch, w);
    if (cert.ok) {
        lib[nlib.*] = cand_feat;
        nlib.* += 1;
        return true;
    }
    return false;
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
    var fbar: f64 = 0;
    var ntot: f64 = 0;
    for (0..CMAX) |c| {
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
            const amp = ncnt[c] * (fsum[c] / ncnt[c] - fbar);
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

fn tryOperatorMenu(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []ForgeFeat,
    nlib: *usize,
    Y: []const f64,
    scratch: []f64,
    w: []f64,
) bool {
    const omega = discoverSpectral(grid, Y, scratch);
    const spec_val = valAccSingle(scratch, Y);

    const walshS = discoverWalsh(grid, Y);
    for (0..NSAMP) |s| scratch[s] = chi(walshS, signPattern(grid[s]));
    const wal_val = valAccSingle(scratch, Y);

    for (0..NSAMP) |s| scratch[s] = cliffordG2(grid[s]);
    const clf_val = valAccSingle(scratch, Y);

    const cands = [_]ForgeFeat{
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
    if (hasForgeFeature(lib[0..nlib.*], cand)) return false;
    const cert = certifyForge(X, grid, lib[0..nlib.*], cand, Y, scratch, w);
    if (cert.ok) {
        lib[nlib.*] = cand;
        nlib.* += 1;
        return true;
    }
    return false;
}

fn discoverXorPopcountMask(grid: []const [NCELL]u8, Y: []const f64, scratch: []f64) u8 {
    var best_val: f64 = -1;
    var best_mask: u8 = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        for (0..NSAMP) |s| scratch[s] = xorPopcountReadout(grid[s], mask);
        const v = valAccSingle(scratch, Y);
        if (v > best_val) {
            best_val = v;
            best_mask = mask;
        }
    }
    return best_mask;
}

fn tryXorPopcount(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []ForgeFeat,
    nlib: *usize,
    Y: []const f64,
    scratch: []f64,
    w: []f64,
) bool {
    const mask = discoverXorPopcountMask(grid, Y, scratch);
    const cand: ForgeFeat = .{ .xor_popcount = mask };
    if (hasForgeFeature(lib[0..nlib.*], cand)) return false;
    const cov_before = coverageForge(X, grid, lib[0..nlib.*], Y, w);
    var aug: [MAXFEAT]ForgeFeat = undefined;
    @memcpy(aug[0..nlib.*], lib[0..nlib.*]);
    aug[nlib.*] = cand;
    const cov_after = coverageForge(X, grid, aug[0 .. nlib.* + 1], Y, w);
    // Escape-only cert: xor_popcount is an injected outer-shell generator (R² gate blocks GF(2) lifts).
    if (cov_after >= FORGE_THRESH and cov_before < FORGE_THRESH) {
        lib[nlib.*] = cand;
        nlib.* += 1;
        return true;
    }
    return false;
}

fn tryWorldPool(
    X: [][]f64,
    grid: []const [NCELL]u8,
    lib: []ForgeFeat,
    nlib: *usize,
    Y: []const f64,
    scratch: []f64,
    w: []f64,
) bool {
    var best_cert: CertResult = .{ .ok = false, .cov_before = 0, .cov_after = -1, .r2 = 2 };
    var best_feat: ?ForgeFeat = null;

    for (WORLD_POOL) |p| {
        const pair = [_]ForgeFeat{
            .{ .world_sum_mod = p },
            .{ .world_sign_mod = p },
        };
        for (pair) |cand| {
            if (hasForgeFeature(lib[0..nlib.*], cand)) continue;
            const cert = certifyForge(X, grid, lib[0..nlib.*], cand, Y, scratch, w);
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

fn runForgeLoop(
    X: [][]f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    scratch: []f64,
    w: []f64,
    use_xor_popcount: bool,
) f64 {
    var lib: [MAXFEAT]ForgeFeat = undefined;
    var nlib: usize = 0;
    const base = baseLibrary();
    @memcpy(lib[0..NCELL], &base);
    nlib = NCELL;

    var round: usize = 0;
    while (round < 10) : (round += 1) {
        const cov = coverageForge(X, grid, lib[0..nlib], Y, w);
        if (cov >= FORGE_THRESH) return cov;

        var promoted = false;
        if (tryMonomialForge(X, grid, &lib, &nlib, Y, scratch, w)) promoted = true;
        if (coverageForge(X, grid, lib[0..nlib], Y, w) >= FORGE_THRESH) return FORGE_THRESH;

        if (!promoted and tryOperatorMenu(X, grid, &lib, &nlib, Y, scratch, w)) promoted = true;
        if (coverageForge(X, grid, lib[0..nlib], Y, w) >= FORGE_THRESH) return FORGE_THRESH;

        if (!promoted and tryWorldPool(X, grid, &lib, &nlib, Y, scratch, w)) promoted = true;
        if (coverageForge(X, grid, lib[0..nlib], Y, w) >= FORGE_THRESH) return FORGE_THRESH;

        if (use_xor_popcount and !promoted and tryXorPopcount(X, grid, &lib, &nlib, Y, scratch, w)) promoted = true;
        if (coverageForge(X, grid, lib[0..nlib], Y, w) >= FORGE_THRESH) return FORGE_THRESH;

        if (!promoted) break;
    }
    return coverageForge(X, grid, lib[0..nlib], Y, w);
}

pub fn runForgeOnTarget(
    X: [][]f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    scratch: []f64,
    w: []f64,
) f64 {
    return runForgeLoop(X, grid, Y, scratch, w, false);
}

pub fn runForgeOnTargetWithXorPopcount(
    X: [][]f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    scratch: []f64,
    w: []f64,
) f64 {
    return runForgeLoop(X, grid, Y, scratch, w, true);
}

// ── Adversarial pool (shared with RQ2) ─────────────────────────────────────

pub const AdversarialPool = struct {
    kept: []KeptTarget,
    grid: [][NCELL]u8,
    mutations: usize,
};

pub fn collectAdversarialPool(alloc: std.mem.Allocator, out: anytype, seed: u64) !AdversarialPool {
    var temp_arena = std.heap.ArenaAllocator.init(alloc);
    defer temp_arena.deinit();
    const temp = temp_arena.allocator();

    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const X = try temp.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try temp.alloc(f64, MAXFEAT);
    var w: [MAXFEAT + 1]f64 = undefined;
    const Yscratch = try temp.alloc(f64, NSAMP);

    var kept = std.ArrayList(KeptTarget).init(alloc);
    var seen = std.AutoHashMap(u64, void).init(alloc);
    defer seen.deinit();

    const base = baseLibrary();
    var mutations: usize = 0;
    const mutation_budget: usize = 4000;

    const tryKeep = struct {
        fn f(
            spec: PredSpec,
            grid_: []const [NCELL]u8,
            X_: [][]f64,
            Ybuf: []f64,
            w_: []f64,
            base_: []const ForgeFeat,
            seen_: *std.AutoHashMap(u64, void),
            kept_: *std.ArrayList(KeptTarget),
            writer: anytype,
        ) !bool {
            const key = spec.key();
            if (seen_.contains(key)) return false;
            try seen_.put(key, {});

            for (0..NSAMP) |s| Ybuf[s] = label(grid_[s], spec);
            const ch = chanceRate(Ybuf, NVA, NSAMP);
            if (ch > 0.55) return false;

            const lib_cov = coverageForge(X_, grid_, base_, Ybuf, w_);
            const oracle_cov = coverageOracle(X_, grid_, spec, Ybuf, w_);
            if (lib_cov >= LIB_THRESH or oracle_cov < ORACLE_THRESH) return false;

            try kept_.append(.{
                .spec = spec,
                .lib_cov = lib_cov,
                .oracle_cov = oracle_cov,
            });
            var buf: [64]u8 = undefined;
            try writer.print("  KEEP #{d:>2}: {s}  lib={d:.3} oracle={d:.3}\n", .{
                kept_.items.len,
                spec.fmt(&buf),
                lib_cov,
                oracle_cov,
            });
            return true;
        }
    }.f;

    var queue = std.ArrayList(PredSpec).init(alloc);
    defer queue.deinit();
    for (SEED_SPECS) |s| {
        try queue.append(s);
        if (kept.items.len < MAXKEPT) _ = try tryKeep(s, grid, X, Yscratch, &w, &base, &seen, &kept, out);
    }

    while (mutations < mutation_budget and kept.items.len < MAXKEPT) : (mutations += 1) {
        const parent = queue.items[rand.intRangeAtMost(usize, 0, queue.items.len - 1)];
        const child = mutateSpec(parent, rand);
        try queue.append(child);
        _ = try tryKeep(child, grid, X, Yscratch, &w, &base, &seen, &kept, out);
    }

    return .{
        .kept = try kept.toOwnedSlice(),
        .grid = grid,
        .mutations = mutations,
    };
}

// ── Main experiment ───────────────────────────────────────────────────────────

pub fn runExperiment(alloc: std.mem.Allocator, out: anytype, seed: u64) !E2Summary {
    try out.print("=== EXPERIMENT E2: POET-lite adversarial target generator ===\n\n", .{});
    try out.print("Filter: library (8 singleton monomials) <{d:.2} AND oracle (ground-truth, eval-only) ≥{d:.2}\n", .{ LIB_THRESH, ORACLE_THRESH });
    try out.print("Forge menu: monomial promotion + spectral/Walsh/Clifford + world mod_p (NO oracle features).\n", .{});
    try out.print("RNG seed: 0x{X:0>16}  train/val/test {d}/{d}/{d}\n\n", .{ seed, NTR, NVA - NTR, NSAMP - NVA });

    const pool = try collectAdversarialPool(alloc, out, seed);
    const grid = pool.grid;
    const kept = pool.kept;
    const mutations = pool.mutations;

    const X = try alloc.alloc([]f64, NSAMP);
    const scratch = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXFEAT);
    var w: [MAXFEAT + 1]f64 = undefined;
    const Yscratch = try alloc.alloc(f64, NSAMP);

    try out.print("\n── Adversarial pool: {d} kept from {d} mutations ──\n\n", .{ kept.len, mutations });

    // Forge each kept target
    var forge_solved: usize = 0;
    var oracle_only: usize = 0;

    for (kept) |*kt| {
        for (0..NSAMP) |s| Yscratch[s] = label(grid[s], kt.spec);
        const forge_cov = runForgeOnTarget(X, grid, Yscratch, scratch, &w);
        kt.forge_cov = forge_cov;
        kt.forge_solved = forge_cov >= FORGE_THRESH;

        if (kt.forge_solved) forge_solved += 1;
        if (!kt.forge_solved and kt.oracle_cov >= ORACLE_THRESH) oracle_only += 1;

        const is_oracle_gap = !kt.forge_solved and kt.oracle_cov >= ORACLE_THRESH;
        var buf: [64]u8 = undefined;
        try out.print("  {s}: lib={d:.3} oracle={d:.3} forge={d:.3}{s}\n", .{
            kt.spec.fmt(&buf),
            kt.lib_cov,
            kt.oracle_cov,
            forge_cov,
            if (kt.forge_solved) " *" else if (is_oracle_gap) " (oracle-only gap)" else "",
        });
    }

    const matched = forge_solved;
    const pass = kept.len > 0 and oracle_only == 0;

    try out.print("\n════════════════════ SUMMARY ════════════════════\n", .{});
    try out.print("  mutations tried:     {d}\n", .{mutations});
    try out.print("  targets kept:        {d}\n", .{kept.len});
    try out.print("  forge solved (≥{d:.2}): {d}\n", .{ FORGE_THRESH, forge_solved });
    try out.print("  oracle-only gaps:    {d}  (forge<{d:.2}, oracle≥{d:.2})\n", .{ oracle_only, FORGE_THRESH, ORACLE_THRESH });
    try out.print("  forge matched oracle:{d}/{d}\n\n", .{ matched, kept.len });

    try out.print("VERDICT: ", .{});
    if (kept.len == 0) {
        try out.print("NO TARGETS KEPT — relax mutation budget or filter thresholds.\n", .{});
    } else if (pass) {
        try out.print("PASS — forge closes every adversarial gap without oracle features in the search menu.\n", .{});
    } else {
        try out.print("PARTIAL — forge solves {d}/{d}; {d} targets need oracle-exclusive families ", .{ forge_solved, kept.len, oracle_only });
        try out.print("(rank-stat / XOR / parity-on-transform not in handed menu).\n", .{});
    }

    try out.print("\nSee: open_invention_e2.md, inner_forge.md, unified_invention.zig, k3_order_escape.zig\n", .{});

    return .{
        .mutations_tried = mutations,
        .targets_kept = kept.len,
        .forge_solved = forge_solved,
        .oracle_only = oracle_only,
        .forge_matched = matched,
        .pass = pass,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    _ = try runExperiment(alloc, out, RNG_SEED);
}