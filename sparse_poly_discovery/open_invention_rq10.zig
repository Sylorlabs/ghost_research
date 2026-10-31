//! RESEARCH Q10 — Certifier soundness: false-promote rate on random-label targets.
//!
//! Generate grids with RANDOM labels (no structure). Run monomial forge + certifier
//! (escape ≥0.90 held-out, irreducible R²<0.40). Any certified promotion on noise
//! labels is a false promote. Also test shuffled-label versions of real zoo targets.
//!
//! PASS bar: false-promote rate <5% on random labels.
//!
//! Run: zig build open-invention-rq10 --release=fast

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const MAXATOMS: usize = 24;
const MAXDEG: usize = 4;
const MAX_ROUNDS: usize = 8;
const R2_MAX: f64 = 0.40;
const COVER: f64 = 0.90;

const GRID_SEED: u64 = 0xF0235A11CE0FF1CE;
const RANDOM_LABEL_SEED: u64 = 0xA10BA771E10A0001;
const SHUFFLE_SEED: u64 = 0xA10BA771E10A0002;
const NRANDOM: usize = 64;
const NZOO: usize = 5;

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

const FeatureCache = struct {
    std_feat: [256][]f64,
    active: [256]bool,

    fn init(alloc: std.mem.Allocator, grid: []const [NCELL]u8) !FeatureCache {
        var cache: FeatureCache = .{
            .std_feat = undefined,
            .active = [_]bool{false} ** 256,
        };
        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const m: u8 = @intCast(mm);
            const d = popcount(m);
            if (d < 1 or d > MAXDEG) continue;
            cache.active[m] = true;
            cache.std_feat[m] = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| cache.std_feat[m][s] = phi(grid[s], m);
            var mu: f64 = 0;
            for (0..NTR) |s| mu += cache.std_feat[m][s];
            mu /= @as(f64, @floatFromInt(NTR));
            var sd: f64 = 0;
            for (0..NTR) |s| {
                const e = cache.std_feat[m][s] - mu;
                sd += e * e;
            }
            sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
            for (0..NSAMP) |s| cache.std_feat[m][s] = (cache.std_feat[m][s] - mu) / sd;
        }
        return cache;
    }

    fn fillColumns(self: *const FeatureCache, X: [][]f64, masks: []const u8) void {
        for (0..NSAMP) |s| {
            for (0..masks.len) |c| X[s][c] = self.std_feat[masks[c]][s];
        }
    }
};

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

fn fitLogit1D(feat: []const f64, Y: []const f64, epochs: usize, lr: f64, w: *f64, b: *f64) void {
    w.* = 0;
    b.* = 0;
    for (0..epochs) |_| for (0..NTR) |s| {
        const z = w.* * feat[s] + b.*;
        const e = sigmoid(z) - Y[s];
        w.* -= lr * e * feat[s];
        b.* -= lr * e;
    };
}

fn accLogit1D(feat: []const f64, Y: []const f64, w: f64, b: f64, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        const z = w * feat[s] + b;
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
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

fn reconR2(X: []const []f64, t: []const f64, dim: usize, w: []f64) f64 {
    @memset(w[0 .. dim + 1], 0);
    for (0..120) |_| for (0..NTR) |s| {
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

fn coverageCached(cache: *const FeatureCache, X: [][]f64, masks: []const u8, Y: []const f64, w: []f64) f64 {
    cache.fillColumns(X, masks);
    fitLogit(X, Y, masks.len, 80, 0.05, w);
    return accLogit(X, Y, w, masks.len, NVA, NSAMP);
}

fn hasMask(masks: []const u8, mask: u8) bool {
    for (masks) |m| if (m == mask) return true;
    return false;
}

fn initSingletons(atoms: *[MAXATOMS]u8) usize {
    for (0..NCELL) |i| atoms[i] = @as(u8, 1) << @intCast(i);
    return NCELL;
}

const ZooTarget = struct {
    name: []const u8,
    mask: u8,
    parity: bool,
};

const ZOO = [_]ZooTarget{
    .{ .name = "T1 sign φ{2,5}  (deg2)", .mask = (1 << 2) | (1 << 5), .parity = false },
    .{ .name = "T2 sign φ{1,3,6} (deg3)", .mask = (1 << 1) | (1 << 3) | (1 << 6), .parity = false },
    .{ .name = "T3 sign φ{0,4,5,7}(deg4)", .mask = (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7), .parity = false },
    .{ .name = "T4 sign(c3−MID) (deg1)", .mask = (1 << 3), .parity = false },
    .{ .name = "T5 parity-of-count(≠mono)", .mask = 0, .parity = true },
};

fn labelStructured(grid: []const [NCELL]u8, Y: []f64, spec: ZooTarget) void {
    for (0..NSAMP) |s| {
        const g = grid[s];
        if (spec.parity) {
            var cnt: usize = 0;
            for (g) |v| {
                if (v >= THRESH) cnt += 1;
            }
            Y[s] = @floatFromInt(cnt & 1);
        } else {
            Y[s] = if (phi(g, spec.mask) > 0) 1.0 else 0.0;
        }
    }
}

fn labelRandom(rng: std.Random, Y: []f64) void {
    for (0..NSAMP) |s| Y[s] = if (rng.boolean()) 1.0 else 0.0;
}

fn shuffleLabels(rng: std.Random, Y: []f64) void {
    var idx = [_]usize{0} ** NSAMP;
    for (0..NSAMP) |i| idx[i] = i;
    rng.shuffle(usize, &idx);
    var copy: [NSAMP]f64 = undefined;
    for (0..NSAMP) |i| copy[i] = Y[i];
    for (0..NSAMP) |i| Y[i] = copy[idx[i]];
}

const ForgeOutcome = struct {
    promote_count: usize,
    had_promote: bool,
    solved_without_promote: bool,
    final_cov: f64,
};

fn forgeWithCertifier(
    cache: *const FeatureCache,
    Y: []const f64,
    X: [][]f64,
    w: []f64,
) ForgeOutcome {
    var atoms: [MAXATOMS]u8 = undefined;
    var natoms = initSingletons(&atoms);
    var promote_count: usize = 0;

    const cov0 = coverageCached(cache, X, atoms[0..natoms], Y, w);
    if (cov0 >= COVER) {
        return .{
            .promote_count = 0,
            .had_promote = false,
            .solved_without_promote = true,
            .final_cov = cov0,
        };
    }

    var w1: f64 = 0;
    var b1: f64 = 0;

    var round: usize = 1;
    while (round <= MAX_ROUNDS) : (round += 1) {
        const cov_now = coverageCached(cache, X, atoms[0..natoms], Y, w);
        if (cov_now >= COVER) break;

        var best_val: f64 = -1;
        var best_mask: u8 = 0;
        var found_cand = false;
        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const cand: u8 = @intCast(mm);
            if (!cache.active[cand]) continue;
            if (hasMask(atoms[0..natoms], cand)) continue;
            fitLogit1D(cache.std_feat[cand], Y, 50, 0.06, &w1, &b1);
            const v = accLogit1D(cache.std_feat[cand], Y, w1, b1, NTR, NVA);
            if (v > best_val) {
                best_val = v;
                best_mask = cand;
                found_cand = true;
            }
        }
        if (!found_cand) break;

        var aug: [MAXATOMS]u8 = undefined;
        @memcpy(aug[0..natoms], atoms[0..natoms]);
        aug[natoms] = best_mask;
        const cov_aug = coverageCached(cache, X, aug[0 .. natoms + 1], Y, w);
        const escape = cov_aug >= COVER and cov_now < COVER;

        cache.fillColumns(X, atoms[0..natoms]);
        const rr = reconR2(X, cache.std_feat[best_mask], natoms, w);
        const irreducible = rr < R2_MAX;

        if (escape and irreducible and natoms < MAXATOMS) {
            atoms[natoms] = best_mask;
            natoms += 1;
            promote_count += 1;
        } else {
            break;
        }
    }

    const final_cov = coverageCached(cache, X, atoms[0..natoms], Y, w);
    return .{
        .promote_count = promote_count,
        .had_promote = promote_count > 0,
        .solved_without_promote = false,
        .final_cov = final_cov,
    };
}

const BatchStats = struct {
    n_targets: usize,
    targets_with_promote: usize,
    total_promotes: usize,
    solved_without_promote: usize,

    fn rate(self: BatchStats) f64 {
        if (self.n_targets == 0) return 0;
        return @as(f64, @floatFromInt(self.targets_with_promote)) / @as(f64, @floatFromInt(self.n_targets));
    }
};

pub const Rq10Summary = struct {
    random: BatchStats,
    shuffled: BatchStats,
    structured: BatchStats,
    pass_random: bool,
};

pub fn runExperiment(alloc: std.mem.Allocator, out: anytype, verbose: bool) !Rq10Summary {
    var grid_prng = std.Random.DefaultPrng.init(GRID_SEED);
    const grid_rand = grid_prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = grid_rand.intRangeAtMost(u8, 0, VMAX);
    };

    const cache = try FeatureCache.init(alloc, grid);

    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXATOMS);

    const Y = try alloc.alloc(f64, NSAMP);
    const Ystruct = try alloc.alloc([]f64, NZOO);
    for (0..NZOO) |t| Ystruct[t] = try alloc.alloc(f64, NSAMP);
    for (0..NZOO) |t| labelStructured(grid, Ystruct[t], ZOO[t]);

    var w: [MAXATOMS + 1]f64 = undefined;

    var random_stats = BatchStats{
        .n_targets = NRANDOM,
        .targets_with_promote = 0,
        .total_promotes = 0,
        .solved_without_promote = 0,
    };

    var rand_prng = std.Random.DefaultPrng.init(RANDOM_LABEL_SEED);
    const rand_rng = rand_prng.random();

    if (verbose) {
        try out.print("=== RESEARCH Q10: certifier soundness on random-label targets ===\n\n", .{});
        try out.print("substrate: centered monomials φ_S; base = 8 singletons (deg 1).\n", .{});
        try out.print("certifier: escape ≥{d:.2} held-out (before<{d:.2}) AND irreducible R²<{d:.2}.\n", .{ COVER, COVER, R2_MAX });
        try out.print("grid seed 0x{X}; random-label seed 0x{X}; shuffle seed 0x{X}.\n", .{ GRID_SEED, RANDOM_LABEL_SEED, SHUFFLE_SEED });
        try out.print("train/val/test {d}/{d}/{d}; max forge rounds {d}.\n\n", .{ NTR, NVA - NTR, NSAMP - NVA, MAX_ROUNDS });

        try out.print("── Phase A: pure random labels ({d} targets, no structure) ──\n", .{NRANDOM});
    }

    for (0..NRANDOM) |t| {
        labelRandom(rand_rng, Y);
        const fo = forgeWithCertifier(&cache, Y, X, &w);
        if (fo.had_promote) random_stats.targets_with_promote += 1;
        random_stats.total_promotes += fo.promote_count;
        if (fo.solved_without_promote) random_stats.solved_without_promote += 1;
        if (verbose and fo.had_promote) {
            try out.print("  R{d:0>2}: FALSE-PROMOTE ({d} cert, final cov {d:.3})\n", .{ t + 1, fo.promote_count, fo.final_cov });
        }
    }

    var shuf_stats = BatchStats{
        .n_targets = NZOO,
        .targets_with_promote = 0,
        .total_promotes = 0,
        .solved_without_promote = 0,
    };

    var shuf_prng = std.Random.DefaultPrng.init(SHUFFLE_SEED);
    const shuf_rng = shuf_prng.random();

    if (verbose) try out.print("\n── Phase B: shuffled real-target labels ({d} zoo targets) ──\n", .{NZOO});

    for (0..NZOO) |t| {
        @memcpy(Y[0..NSAMP], Ystruct[t][0..NSAMP]);
        shuffleLabels(shuf_rng, Y);
        const fo = forgeWithCertifier(&cache, Y, X, &w);
        if (fo.had_promote) shuf_stats.targets_with_promote += 1;
        shuf_stats.total_promotes += fo.promote_count;
        if (fo.solved_without_promote) shuf_stats.solved_without_promote += 1;
        if (verbose) {
            const tag: []const u8 = if (fo.had_promote) "FALSE-PROMOTE" else "ok";
            try out.print("  {s}: {s} ({d} cert, final cov {d:.3})\n", .{ ZOO[t].name, tag, fo.promote_count, fo.final_cov });
        }
    }

    var struct_stats = BatchStats{
        .n_targets = NZOO,
        .targets_with_promote = 0,
        .total_promotes = 0,
        .solved_without_promote = 0,
    };

    if (verbose) try out.print("\n── Phase C: structured zoo (positive control — true promotes expected) ──\n", .{});

    for (0..NZOO) |t| {
        const fo = forgeWithCertifier(&cache, Ystruct[t], X, &w);
        if (fo.had_promote) struct_stats.targets_with_promote += 1;
        struct_stats.total_promotes += fo.promote_count;
        if (fo.solved_without_promote) struct_stats.solved_without_promote += 1;
        if (verbose) {
            const tag: []const u8 = if (fo.had_promote or fo.solved_without_promote) "SOLVED" else "unsolved";
            try out.print("  {s}: {s} ({d} cert, final cov {d:.3})\n", .{ ZOO[t].name, tag, fo.promote_count, fo.final_cov });
        }
    }

    const pass_random = random_stats.rate() < 0.05;

    if (verbose) {
        try out.print("\n── Summary ──\n", .{});
        try out.print("random labels:     {d}/{d} targets false-promoted ({d:.1}%), {d} total certs, {d} solved w/o promote\n", .{
            random_stats.targets_with_promote,
            random_stats.n_targets,
            100.0 * random_stats.rate(),
            random_stats.total_promotes,
            random_stats.solved_without_promote,
        });
        try out.print("shuffled labels:   {d}/{d} targets false-promoted ({d:.1}%), {d} total certs\n", .{
            shuf_stats.targets_with_promote,
            shuf_stats.n_targets,
            100.0 * shuf_stats.rate(),
            shuf_stats.total_promotes,
        });
        try out.print("structured zoo:    {d}/{d} targets promoted ({d:.1}%), {d} total certs (control)\n\n", .{
            struct_stats.targets_with_promote,
            struct_stats.n_targets,
            100.0 * struct_stats.rate(),
            struct_stats.total_promotes,
        });

        try out.print("PASS bar (random): false-promote <5% → {s}\n", .{if (pass_random) "PASS" else "FAIL"});
        try out.print("VERDICT: certifier is {s} on noise labels", .{if (pass_random) "sound" else "leaky"});
        if (!pass_random) try out.print(" — tighten escape gate or increase held-out split", .{});
        try out.print(".\n", .{});
        try out.print("See: docs/research/open_invention_rq10.md, inner_forge.zig, open_invention_e1.zig.\n", .{});
    }

    try out.print(
        "RQ10_RESULT random_false={d}/{d} rate={d:.4} shuffled_false={d}/{d} pass={} doc=docs/research/open_invention_rq10.md\n",
        .{
            random_stats.targets_with_promote,
            random_stats.n_targets,
            random_stats.rate(),
            shuf_stats.targets_with_promote,
            shuf_stats.n_targets,
            pass_random,
        },
    );

    return .{
        .random = random_stats,
        .shuffled = shuf_stats,
        .structured = struct_stats,
        .pass_random = pass_random,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    _ = try runExperiment(alloc, out, true);
}