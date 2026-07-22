//! EXPERIMENT E10 — novelty-only forge vs usefulness (wcore tension).
//!
//! Phase A: promote by algebraic irreducibility ONLY (held-out R²<0.40) — no target, no escape cert.
//! Phase B: battery of random monomial-sign targets — measure usefulness hit rate of the forged atoms.
//! Control: usefulness-driven forge (irreducible AND escape) on the same grid for contrast.
//!
//! Expected: many promoted atoms, near-zero random-battery hits — quantifying novelty↔usefulness tension.
//!
//! Run: zig build open-invention-e10 --release=fast

const std = @import("std");

pub const NCELL: usize = 8;
pub const NZOO: usize = 5;
pub const VMAX: u8 = 5;
pub const NSAMP: usize = 7000;
pub const MAXATOMS: usize = 24;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NTR: usize = 3500;
const NVA: usize = 5250;
const MAXDEG: usize = 4;
pub const R2_MAX: f64 = 0.40;
pub const COVER: f64 = 0.90;
pub const NBATTERY: usize = 128;
const MAX_NOVELTY_ROUNDS: usize = 16;

pub const GRID_SEED: u64 = 0xF0235A11CE0FF1CE;
pub const BATTERY_SEED: u64 = 0xE10BA771E0000001;

pub const ForgeParams = struct {
    r2_max: f64,
    escape_cover: f64,
    escape_before: f64,
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

fn buildFeat(X: [][]f64, grid: []const [NCELL]u8, masks: []const u8) void {
    const k = masks.len;
    for (0..NSAMP) |s| {
        for (0..k) |c| X[s][c] = phi(grid[s], masks[c]);
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

fn reconR2(X: []const []f64, t: []const f64, dim: usize, w: []f64) f64 {
    @memset(w[0 .. dim + 1], 0);
    for (0..200) |_| for (0..NTR) |s| {
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

pub fn coverage(X: [][]f64, grid: []const [NCELL]u8, masks: []const u8, Y: []const f64, w: []f64) f64 {
    buildFeat(X, grid, masks);
    return coveragePrebuilt(X, Y, masks.len, w);
}

fn coveragePrebuilt(X: []const []f64, Y: []const f64, dim: usize, w: []f64) f64 {
    fitLogit(X, Y, dim, 150, 0.05, w);
    return accLogit(X, Y, w, dim, NVA, NSAMP);
}

fn coverageBattery(X: []const []f64, Y: []const f64, dim: usize, w: []f64) f64 {
    fitLogit(X, Y, dim, 80, 0.05, w);
    return accLogit(X, Y, w, dim, NVA, NSAMP);
}

fn hasMask(masks: []const u8, mask: u8) bool {
    for (masks) |m| if (m == mask) return true;
    return false;
}

fn initSingletons(atoms: *[MAXATOMS]u8) usize {
    for (0..NCELL) |i| atoms[i] = @as(u8, 1) << @intCast(i);
    return NCELL;
}

fn findMostIrreducible(
    grid: []const [NCELL]u8,
    atoms: []const u8,
    Xrec: [][]f64,
    phiTgt: []f64,
    w: []f64,
    min_deg: usize,
) struct { mask: u8, r2: f64, found: bool } {
    buildFeat(Xrec, grid, atoms);
    const dim = atoms.len;
    var worst_r2: f64 = 2.0;
    var best_mask: u8 = 0;
    var found = false;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const cand: u8 = @intCast(mm);
        const d = popcount(cand);
        if (d < min_deg or d > MAXDEG) continue;
        if (hasMask(atoms, cand)) continue;
        for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], cand);
        const rr = reconR2(Xrec, phiTgt, dim, w);
        if (rr < worst_r2) {
            worst_r2 = rr;
            best_mask = cand;
            found = true;
        }
    }
    return .{ .mask = best_mask, .r2 = worst_r2, .found = found };
}

const ZooTarget = struct {
    name: []const u8,
    mask: u8,
    parity: bool,
};

pub const ZOO = [_]ZooTarget{
    .{ .name = "T1 sign φ{2,5}  (deg2)", .mask = (1 << 2) | (1 << 5), .parity = false },
    .{ .name = "T2 sign φ{1,3,6} (deg3)", .mask = (1 << 1) | (1 << 3) | (1 << 6), .parity = false },
    .{ .name = "T3 sign φ{0,4,5,7}(deg4)", .mask = (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7), .parity = false },
    .{ .name = "T4 sign(c3−MID) (deg1)", .mask = (1 << 3), .parity = false },
    .{ .name = "T5 parity-of-count(≠mono)", .mask = 0, .parity = true },
};

pub fn labelGrid(grid: []const [NCELL]u8, Y: []f64, spec: ZooTarget) void {
    for (0..NSAMP) |s| {
        const g = grid[s];
        if (spec.parity) {
            var cnt: usize = 0;
            for (g) |v| if (v >= THRESH) {
                cnt += 1;
            };
            Y[s] = @floatFromInt(cnt & 1);
        } else {
            Y[s] = if (phi(g, spec.mask) > 0) 1.0 else 0.0;
        }
    }
}

fn labelMask(grid: []const [NCELL]u8, Y: []f64, mask: u8) void {
    for (0..NSAMP) |s| Y[s] = if (phi(grid[s], mask) > 0) 1.0 else 0.0;
}

fn countHits(
    X: [][]f64,
    grid: []const [NCELL]u8,
    atoms: []const u8,
    masks: []const u8,
    Ybuf: []f64,
    w: []f64,
) usize {
    return countHitsCfg(X, grid, atoms, masks, Ybuf, w, COVER);
}

pub fn countHitsCfg(
    X: [][]f64,
    grid: []const [NCELL]u8,
    atoms: []const u8,
    masks: []const u8,
    Ybuf: []f64,
    w: []f64,
    cover: f64,
) usize {
    buildFeat(X, grid, atoms);
    const dim = atoms.len;
    var hits: usize = 0;
    for (masks) |m| {
        labelMask(grid, Ybuf, m);
        if (coverageBattery(X, Ybuf, dim, w) >= cover) hits += 1;
    }
    return hits;
}

fn noveltyOnlyForge(
    grid: []const [NCELL]u8,
    Xrec: [][]f64,
    phiTgt: []f64,
    w: []f64,
    atoms_out: *[MAXATOMS]u8,
) usize {
    return noveltyOnlyForgeCfg(grid, Xrec, phiTgt, w, atoms_out, R2_MAX);
}

pub fn noveltyOnlyForgeCfg(
    grid: []const [NCELL]u8,
    Xrec: [][]f64,
    phiTgt: []f64,
    w: []f64,
    atoms_out: *[MAXATOMS]u8,
    r2_max: f64,
) usize {
    const n0 = initSingletons(atoms_out);
    var natoms: usize = n0;

    var round: usize = 1;
    while (round <= MAX_NOVELTY_ROUNDS) : (round += 1) {
        if (natoms >= MAXATOMS) break;
        const pick = findMostIrreducible(grid, atoms_out[0..natoms], Xrec, phiTgt, w, 2);
        if (!pick.found or pick.r2 >= r2_max) break;
        atoms_out[natoms] = pick.mask;
        natoms += 1;
    }
    return natoms;
}

fn usefulnessForge(
    grid: []const [NCELL]u8,
    X: [][]f64,
    Xrec: [][]f64,
    phiTgt: []f64,
    Yzoo: [][]f64,
    w: []f64,
    atoms_out: *[MAXATOMS]u8,
) usize {
    return usefulnessForgeCfg(grid, X, Xrec, phiTgt, Yzoo, w, atoms_out, .{
        .r2_max = R2_MAX,
        .escape_cover = COVER,
        .escape_before = 0.70,
    });
}

pub fn usefulnessForgeCfg(
    grid: []const [NCELL]u8,
    X: [][]f64,
    Xrec: [][]f64,
    phiTgt: []f64,
    Yzoo: [][]f64,
    w: []f64,
    atoms_out: *[MAXATOMS]u8,
    cfg: ForgeParams,
) usize {
    const n0 = initSingletons(atoms_out);
    var natoms: usize = n0;
    var solved = [_]bool{false} ** NZOO;

    var round: usize = 1;
    while (round <= MAX_NOVELTY_ROUNDS) : (round += 1) {
        var promoted = false;
        for (0..NZOO) |t| {
            if (solved[t]) continue;
            if (natoms >= MAXATOMS) break;
            const cov_now = coverage(X, grid, atoms_out[0..natoms], Yzoo[t], w);
            if (cov_now >= cfg.escape_cover) {
                solved[t] = true;
                continue;
            }

            var best_val: f64 = -1;
            var best_mask: u8 = 0;
            var mm: u16 = 1;
            while (mm < 256) : (mm += 1) {
                const cand: u8 = @intCast(mm);
                const d = popcount(cand);
                if (d < 1 or d > MAXDEG) continue;
                if (hasMask(atoms_out[0..natoms], cand)) continue;
                const one = [_]u8{cand};
                buildFeat(X, grid, &one);
                fitLogit(X, Yzoo[t], 1, 70, 0.06, w);
                const v = accLogit(X, Yzoo[t], w, 1, NTR, NVA);
                if (v > best_val) {
                    best_val = v;
                    best_mask = cand;
                }
            }

            var aug: [MAXATOMS]u8 = undefined;
            @memcpy(aug[0..natoms], atoms_out[0..natoms]);
            aug[natoms] = best_mask;
            const cov_aug = coverage(X, grid, aug[0 .. natoms + 1], Yzoo[t], w);
            const escape = cov_aug >= cfg.escape_cover and cov_now < cfg.escape_before;

            for (0..NSAMP) |s| phiTgt[s] = phi(grid[s], best_mask);
            buildFeat(Xrec, grid, atoms_out[0..natoms]);
            const rr = reconR2(Xrec, phiTgt, natoms, w);
            const irreducible = rr < cfg.r2_max;

            if (escape and irreducible) {
                atoms_out[natoms] = best_mask;
                natoms += 1;
                solved[t] = true;
                promoted = true;
            }
        }
        if (!promoted) break;
    }
    return natoms;
}

pub fn genBatteryMasks(alloc: std.mem.Allocator, rng: std.Random) ![]u8 {
    var list = std.ArrayList(u8).init(alloc);
    errdefer list.deinit();
    var used = [_]bool{false} ** 256;
    while (list.items.len < NBATTERY) {
        const d = rng.intRangeAtMost(usize, 2, MAXDEG);
        var mask: u8 = 0;
        var placed: usize = 0;
        while (placed < d) {
            const bit = rng.intRangeAtMost(u3, 0, 7);
            const b: u8 = @as(u8, 1) << bit;
            if (mask & b == 0) {
                mask |= b;
                placed += 1;
            }
        }
        if (used[mask]) continue;
        used[mask] = true;
        try list.append(mask);
    }
    return try list.toOwnedSlice();
}

pub const E10Summary = struct {
    novelty_promoted: usize,
    novelty_battery_hits: usize,
    novelty_zoo_hits: usize,
    useful_promoted: usize,
    useful_battery_hits: usize,
    useful_zoo_hits: usize,
    singleton_battery_hits: usize,
};

pub fn runExperiment(alloc: std.mem.Allocator, out: anytype, verbose: bool) !E10Summary {
    var prng = std.Random.DefaultPrng.init(GRID_SEED);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const X = try alloc.alloc([]f64, NSAMP);
    const Xrec = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        X[s] = try alloc.alloc(f64, MAXATOMS);
        Xrec[s] = try alloc.alloc(f64, MAXATOMS);
    }
    const phiTgt = try alloc.alloc(f64, NSAMP);
    const Ybuf = try alloc.alloc(f64, NSAMP);
    const Yzoo = try alloc.alloc([]f64, NZOO);
    for (0..NZOO) |t| Yzoo[t] = try alloc.alloc(f64, NSAMP);
    for (0..NZOO) |t| labelGrid(grid, Yzoo[t], ZOO[t]);

    var w: [MAXATOMS + 1]f64 = undefined;

    var novelty_atoms: [MAXATOMS]u8 = undefined;
    const n_nov = noveltyOnlyForge(grid, Xrec, phiTgt, &w, &novelty_atoms);

    var useful_atoms: [MAXATOMS]u8 = undefined;
    const n_use = usefulnessForge(grid, X, Xrec, phiTgt, Yzoo, &w, &useful_atoms);

    var bat_prng = std.Random.DefaultPrng.init(BATTERY_SEED);
    const battery_masks = try genBatteryMasks(alloc, bat_prng.random());
    defer alloc.free(battery_masks);

    const singletons = atoms: {
        var a: [MAXATOMS]u8 = undefined;
        const n = initSingletons(&a);
        break :atoms a[0..n];
    };

    const singleton_hits = countHits(X, grid, singletons, battery_masks, Ybuf, &w);
    const novelty_hits = countHits(X, grid, novelty_atoms[0..n_nov], battery_masks, Ybuf, &w);
    const useful_hits = countHits(X, grid, useful_atoms[0..n_use], battery_masks, Ybuf, &w);

    const zoo_mono_masks = [_]u8{ ZOO[0].mask, ZOO[1].mask, ZOO[2].mask, ZOO[3].mask };
    const novelty_zoo = countHits(X, grid, novelty_atoms[0..n_nov], &zoo_mono_masks, Ybuf, &w);
    const useful_zoo = countHits(X, grid, useful_atoms[0..n_use], &zoo_mono_masks, Ybuf, &w);

    const novelty_t5: usize = if (coverage(X, grid, novelty_atoms[0..n_nov], Yzoo[4], &w) >= COVER) 1 else 0;
    const useful_t5: usize = if (coverage(X, grid, useful_atoms[0..n_use], Yzoo[4], &w) >= COVER) 1 else 0;
    const novelty_zoo_total = novelty_zoo + novelty_t5;
    const useful_zoo_total = useful_zoo + useful_t5;

    const summary = E10Summary{
        .novelty_promoted = n_nov - NCELL,
        .novelty_battery_hits = novelty_hits,
        .novelty_zoo_hits = novelty_zoo_total,
        .useful_promoted = n_use - NCELL,
        .useful_battery_hits = useful_hits,
        .useful_zoo_hits = useful_zoo_total,
        .singleton_battery_hits = singleton_hits,
    };

    if (verbose) {
        try out.print("=== E10: novelty-only forge vs usefulness (wcore tension) ===\n\n", .{});
        try out.print("substrate: centered monomials φ_S; base = 8 singletons; certifier R²<{d:.2} only (no escape).\n", .{R2_MAX});
        try out.print("random battery: {d} unique sign(φ_S) targets (deg 2–{d}), seed 0x{X}.\n", .{ NBATTERY, MAXDEG, BATTERY_SEED });
        try out.print("usefulness threshold: held-out test acc ≥ {d:.2}.\n\n", .{COVER});

        try out.print("── Phase A: novelty-only forge (target-agnostic) ──\n", .{});
        try out.print("  promoted (beyond singletons): {d}\n", .{summary.novelty_promoted});
        try out.print("  final atom count: {d}\n\n", .{n_nov});

        try out.print("── Phase B: random-target battery ──\n", .{});
        try out.print("  singletons only:     {d}/{d} hits ({d:.1}%)\n", .{ singleton_hits, NBATTERY, 100.0 * @as(f64, @floatFromInt(singleton_hits)) / @as(f64, @floatFromInt(NBATTERY)) });
        try out.print("  novelty-forged atoms:  {d}/{d} hits ({d:.1}%)\n", .{ novelty_hits, NBATTERY, 100.0 * @as(f64, @floatFromInt(novelty_hits)) / @as(f64, @floatFromInt(NBATTERY)) });
        try out.print("  useful-forged atoms:   {d}/{d} hits ({d:.1}%)\n\n", .{ useful_hits, NBATTERY, 100.0 * @as(f64, @floatFromInt(useful_hits)) / @as(f64, @floatFromInt(NBATTERY)) });

        try out.print("── Structured zoo (T1–T5, inner_forge line) ──\n", .{});
        try out.print("  novelty-forged: {d}/{d} solved\n", .{ novelty_zoo_total, NZOO });
        try out.print("  useful-forged:  {d}/{d} solved\n\n", .{ useful_zoo_total, NZOO });

        try out.print("── Tension metrics ──\n", .{});
        try out.print("  novelty promoted count:     {d}\n", .{summary.novelty_promoted});
        try out.print("  novelty useful hit rate:    {d}/{d} = {d:.1}% (random battery)\n", .{ novelty_hits, NBATTERY, 100.0 * @as(f64, @floatFromInt(novelty_hits)) / @as(f64, @floatFromInt(NBATTERY)) });
        try out.print("  useful promoted count:      {d}\n", .{summary.useful_promoted});
        try out.print("  useful useful hit rate:     {d}/{d} = {d:.1}% (random battery)\n", .{ useful_hits, NBATTERY, 100.0 * @as(f64, @floatFromInt(useful_hits)) / @as(f64, @floatFromInt(NBATTERY)) });
        try out.print("  useful/zoo efficiency:      {d} promotions → {d}/{d} zoo ({d:.0}% per prom)\n", .{
            summary.useful_promoted,
            useful_zoo_total,
            NZOO,
            if (summary.useful_promoted > 0) 100.0 * @as(f64, @floatFromInt(useful_zoo_total)) / @as(f64, @floatFromInt(summary.useful_promoted)) else 0,
        });
        try out.print("  novelty/zoo efficiency:     {d} promotions → {d}/{d} zoo ({d:.1}% per prom)\n\n", .{
            summary.novelty_promoted,
            novelty_zoo_total,
            NZOO,
            if (summary.novelty_promoted > 0) 100.0 * @as(f64, @floatFromInt(novelty_zoo_total)) / @as(f64, @floatFromInt(summary.novelty_promoted)) else 0,
        });

        try out.print("VERDICT: novelty-only forges irreducible atoms that barely move random-task usefulness.\n", .{});
        try out.print("Fusing irreducibility with escape (inner_forge objective) concentrates promotions on targets.\n", .{});
        try out.print("See: open_invention_e10.md, inner_forge.md, wcore alien_novelty_limit.md §21–22.\n", .{});
    }

    return summary;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    _ = try runExperiment(alloc, out, true);
}