//! Pair-selection hardness router — Q38 analog for menu-growth cell pairs.
//!
//! Substrate classes (mirrors hardness_router.zig deg1 / extremal split):
//!   cell_solo   — centered single cell c_i − mid (deg1 analog)
//!   focal_pair  — menu-pinned relational inner on (0,1) (extremal / fixed-menu analog)
//!
//! When both classes saturate near chance on a degree-2 target, classify `pair_compound`
//! and propose the pair via O(N) single probes + O(N) correlation partner scan — not O(N²)
//! full pair logistic fits.
//!
//! Run: zig build pair-hardness-router-test

const std = @import("std");

pub const NCELL: usize = 8;
pub const VMAX: u8 = 5;
pub const THRESH: u8 = 3;
pub const MID: f64 = @as(f64, @floatFromInt(VMAX)) / 2.0;
pub const NSAMP: usize = 9000;
pub const NTR: usize = 4500;
pub const NVA: usize = 6750;

pub const HIDDEN_PAIR = [2]usize{ 2, 5 };
pub const FOCAL_A: usize = 0;
pub const FOCAL_B: usize = 1;

pub const N_PAIRS: usize = NCELL * (NCELL - 1) / 2; // 28

pub const SATURATE_ACC: f64 = 0.55;
pub const SINGLE_SUFFICIENT: f64 = 0.70;

pub const SubstrateClass = enum {
    cell_solo,
    focal_pair,
};

pub const CellProbe = struct {
    cell: usize,
    class: SubstrateClass,
    val_acc: f64,
};

pub const TaskClass = enum {
    single_sufficient,
    pair_compound,
    unknown,
};

pub const PairProposal = struct {
    i: usize,
    j: usize,
    val_acc: f64,
    tst_acc: f64,
};

pub const RouteResult = struct {
    task_class: TaskClass,
    menu_val: f64,
    focal_val: f64,
    proposal: PairProposal,
    cell_probes: [NCELL]CellProbe,
    n_pairs_brute: usize,
};

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

pub fn standardize(X: [][]f64, dim: usize) void {
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

pub fn fitLogit(X: []const []f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
}

pub fn accLogit(X: []const []f64, Y: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

pub fn hiddenPairLabel(g: [NCELL]u8) f64 {
    const a = @as(f64, @floatFromInt(g[HIDDEN_PAIR[0]])) - MID;
    const b = @as(f64, @floatFromInt(g[HIDDEN_PAIR[1]])) - MID;
    return if (a * b > 0) 1.0 else 0.0;
}

pub fn degree2PairLabel(g: [NCELL]u8, i: usize, j: usize) f64 {
    const a = @as(f64, @floatFromInt(g[i])) - MID;
    const b = @as(f64, @floatFromInt(g[j])) - MID;
    return if (a * b > 0) 1.0 else 0.0;
}

pub fn fillPairFeatures(pf: []const []f64, grid: []const [NCELL]u8, i: usize, j: usize) void {
    for (0..NSAMP) |s| {
        const ci: f64 = @floatFromInt(grid[s][i]);
        const cj: f64 = @floatFromInt(grid[s][j]);
        pf[s][0] = ci;
        pf[s][1] = cj;
        pf[s][2] = ci * cj;
    }
}

pub fn evalPair(
    pf: []const []f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    i: usize,
    j: usize,
    w: []f64,
) struct { val: f64, tst: f64 } {
    fillPairFeatures(pf, grid, i, j);
    standardize(@constCast(pf), 3);
    fitLogit(pf, Y, 3, 160, 0.04, w);
    return .{
        .val = accLogit(pf, Y, w, 3, NTR, NVA),
        .tst = accLogit(pf, Y, w, 3, NVA, NSAMP),
    };
}

pub fn probeCellSingles(
    feat: []const []f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    w: []f64,
    out: *[NCELL]CellProbe,
) void {
    for (0..NCELL) |k| {
        for (0..NSAMP) |s| feat[s][0] = @as(f64, @floatFromInt(grid[s][k])) - MID;
        standardize(@constCast(feat), 1);
        fitLogit(feat, Y, 1, 120, 0.05, w);
        out[k] = .{
            .cell = k,
            .class = .cell_solo,
            .val_acc = accLogit(feat, Y, w, 1, NTR, NVA),
        };
    }
}

pub fn probeFocalPair(
    pf: []const []f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    w: []f64,
) f64 {
    return evalPair(pf, grid, Y, FOCAL_A, FOCAL_B, w).val;
}

pub fn probeMenuJoint(
    menuX2: []const []f64,
    Y: []const f64,
    w: []f64,
) f64 {
    fitLogit(menuX2, Y, 12, 240, 0.02, w);
    return accLogit(menuX2, Y, w, 12, NTR, NVA);
}

fn bestInClass(probes: []const CellProbe, class: SubstrateClass) ?CellProbe {
    var best: ?CellProbe = null;
    for (probes) |p| {
        if (p.class != class) continue;
        if (best == null or p.val_acc > best.?.val_acc) best = p;
    }
    return best;
}

fn bestOverall(probes: []const CellProbe) CellProbe {
    var best = probes[0];
    for (probes[1..]) |p| {
        if (p.val_acc > best.val_acc) best = p;
    }
    return best;
}

pub fn classifyPairTask(menu_val: f64, focal_val: f64, probes: []const CellProbe) TaskClass {
    const overall = bestOverall(probes);
    if (menu_val >= SINGLE_SUFFICIENT or focal_val >= SINGLE_SUFFICIENT or overall.val_acc >= SINGLE_SUFFICIENT) {
        return .single_sufficient;
    }
    const solo = bestInClass(probes, .cell_solo) orelse return .unknown;
    if (menu_val <= SATURATE_ACC and focal_val <= SATURATE_ACC and solo.val_acc <= SATURATE_ACC) {
        return .pair_compound;
    }
    return .unknown;
}

/// Cheap |corr((ci−mid)(cj−mid), Y)| on validation — no logistic fit per pair.
pub fn pairProductCorr(grid: []const [NCELL]u8, Y: []const f64, i: usize, j: usize) f64 {
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

/// Propose pair from substrate probes + cheap correlation ranking (28 stats, 1 verify fit).
pub fn proposePairFromProbes(
    grid: []const [NCELL]u8,
    Y: []const f64,
    probes: []const CellProbe,
) struct { i: usize, j: usize } {
    _ = probes;
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
    return .{ .i = best_i, .j = best_j };
}

pub fn brutePairSearch(
    pf: []const []f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    w: []f64,
) PairProposal {
    var best: PairProposal = .{ .i = 0, .j = 1, .val_acc = -1, .tst_acc = 0 };
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        const r = evalPair(pf, grid, Y, i, j, w);
        if (r.val > best.val_acc) best = .{ .i = i, .j = j, .val_acc = r.val, .tst_acc = r.tst };
    };
    return best;
}

pub fn pairsMatch(a_i: usize, a_j: usize, b_i: usize, b_j: usize) bool {
    return (a_i == b_i and a_j == b_j) or (a_i == b_j and a_j == b_i);
}

pub fn route(
    grid: []const [NCELL]u8,
    menuX2: []const []f64,
    Y: []const f64,
    feat: []const []f64,
    pf: []const []f64,
    w: []f64,
) RouteResult {
    var cell_probes: [NCELL]CellProbe = undefined;
    probeCellSingles(feat, grid, Y, w, &cell_probes);
    const menu_val = probeMenuJoint(menuX2, Y, w);
    const focal_val = probeFocalPair(pf, grid, Y, w);
    const task_class = classifyPairTask(menu_val, focal_val, &cell_probes);

    const cross = proposePairFromProbes(grid, Y, &cell_probes);
    const verified = evalPair(pf, grid, Y, cross.i, cross.j, w);

    return .{
        .task_class = task_class,
        .menu_val = menu_val,
        .focal_val = focal_val,
        .proposal = .{ .i = cross.i, .j = cross.j, .val_acc = verified.val, .tst_acc = verified.tst },
        .cell_probes = cell_probes,
        .n_pairs_brute = N_PAIRS,
    };
}

pub fn buildMenuX2(alloc: std.mem.Allocator, grid: []const [NCELL]u8) ![][]f64 {
    const menuX2 = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        const g = grid[s];
        var cnt: usize = 0;
        for (g) |v| {
            if (v >= THRESH) cnt += 1;
        }
        var sm: u32 = 0;
        for (g) |v| sm += v;
        var mx: u8 = 0;
        for (g) |v| mx = @max(mx, v);
        var inv: usize = 0;
        for (0..NCELL) |i| for (i + 1..NCELL) |j| {
            if (g[i] > g[j]) inv += 1;
        };
        const m = [6]f64{
            @floatFromInt(cnt),
            @floatFromInt(sm),
            @floatFromInt(mx),
            @floatFromInt(inv),
            @sin(0.40 * (@as(f64, @floatFromInt(g[1])) - @as(f64, @floatFromInt(g[0])))),
            @as(f64, @floatFromInt(g[0])) * @as(f64, @floatFromInt(g[1])),
        };
        menuX2[s] = try alloc.alloc(f64, 12);
        for (0..6) |k| {
            menuX2[s][k] = m[k];
            menuX2[s][6 + k] = m[k] * m[k];
        }
    }
    standardize(menuX2, 12);
    return menuX2;
}

pub fn makeGrid(alloc: std.mem.Allocator, seed: u64) ![] [NCELL]u8 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };
    return grid;
}

pub fn makeLabels(alloc: std.mem.Allocator, grid: []const [NCELL]u8, label_fn: *const fn ([NCELL]u8) f64) ![]f64 {
    const Y = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| Y[s] = label_fn(grid[s]);
    return Y;
}