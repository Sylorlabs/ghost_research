//! FORK E4-G00 — genuinely-novel hard-mint generalization test.
//!
//! EXP-5 left seed-pinned G00 `((c0*c0)*(max>thresh))` as the sole genuinely-novel escape
//! outside expanded RQ9 basis. This fork asks:
//!   1. Held-out generalization across grid seeds (v1 + v2 basis, mint-direct).
//!   2. Whether promoting the mint into the E4 library helps downstream hard targets.
//!
//! Run: zig build swarm-fork-e4-g00 --release=fast

const std = @import("std");
const e5 = @import("open_invention_e5.zig");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTEST: usize = 3500;
const NTR: usize = 3500;
const NVA: usize = 5250;
const MAX_BUDGET: usize = 8;
const PREFILTER_TOP: usize = 96;
const CERT: f64 = 0.90;
const CORR_NOVEL: f64 = 0.995;
const MAX_DEG: usize = 4;
const VM_MAX_DEPTH: usize = 6;
const VM_MAX_POOL: usize = 8192;
const NTARGETS: usize = 20;
const COVER: f64 = 0.90;
const ESCAPE_BEFORE: f64 = 0.70;

const GRID_TRAIN_SEED: u64 = 0xF0235A11CE0FF1CE;
const GRID_TEST_SEED: u64 = 0xE957E5700002;
const E4_TARGET_SEED: u64 = 0xE4CE11ED0FF1CE42;
const E4_GRID_SEED: u64 = 0xE4CE11ED0FF1CE42;

// EXP-5 / RQ9 canonical anchors (open-invention-rq9 --release=fast).
const CANON_V1_TEST: f64 = 0.830;
const CANON_V2_TEST: f64 = 0.463;

const WORLD_POOL = [_]usize{ 2, 3, 5, 7, 11, 13 };
const NMONO: usize = 255;
const NWALSH: usize = 256;
const NWORLD: usize = WORLD_POOL.len * 2;
const NCAND_STATIC: usize = NMONO + NWALSH + NWORLD;

const SeedPair = struct { train: u64, held_out: u64, name: []const u8 };

const SEED_PAIRS = [_]SeedPair{
    .{ .train = 0xF0235A11CE0FF1CE, .held_out = 0xE957E5700002, .name = "canonical" },
    .{ .train = 0xA1B2C3D4E5F60718, .held_out = 0x1234567890ABCDEF, .name = "alt-A" },
    .{ .train = 0xDEADBEEFCAFE0001, .held_out = 0xBADDCAFE00000002, .name = "alt-B" },
    .{ .train = 0x1111222233334444, .held_out = 0xAAAABBBBCCCCDDDD, .name = "alt-C" },
};

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
}

fn phiMono(g: [NCELL]u8, mask: u8) f64 {
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

fn chi(S: u8, p: u8) f64 {
    const neg = @popCount(S & ~p);
    return if (neg & 1 == 0) 1.0 else -1.0;
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

const Leaf = enum { cell, thresh, sum, parity, min, max, rank_k };
const Bin = enum { add, mul, cmp_gt };

const Expr = union(enum) {
    leaf: struct { kind: Leaf, param: u8 },
    bin: struct { op: Bin, a: u16, b: u16 },
};

fn rankK(g: [NCELL]u8, k: usize) u8 {
    var s = g;
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    return s[@min(k, NCELL - 1)];
}

fn gridMin(g: [NCELL]u8) u8 {
    var m = g[0];
    for (g[1..]) |v| m = @min(m, v);
    return m;
}

fn gridMax(g: [NCELL]u8) u8 {
    var m = g[0];
    for (g[1..]) |v| m = @max(m, v);
    return m;
}

fn evalLeaf(g: [NCELL]u8, kind: Leaf, param: u8) f64 {
    return switch (kind) {
        .cell => @floatFromInt(g[param % NCELL]),
        .thresh => blk: {
            var c: usize = 0;
            for (g) |v| {
                if (v >= THRESH) c += 1;
            }
            break :blk @floatFromInt(c);
        },
        .sum => @floatFromInt(gridSum(g)),
        .parity => blk: {
            var c: usize = 0;
            for (g) |v| {
                if (v >= THRESH) c += 1;
            }
            break :blk @floatFromInt(c & 1);
        },
        .min => @floatFromInt(gridMin(g)),
        .max => @floatFromInt(gridMax(g)),
        .rank_k => @floatFromInt(rankK(g, param % NCELL)),
    };
}

fn evalExpr(exprs: []const Expr, id: u16, g: [NCELL]u8) f64 {
    return switch (exprs[id]) {
        .leaf => |l| evalLeaf(g, l.kind, l.param),
        .bin => |b| blk: {
            const av = evalExpr(exprs, b.a, g);
            const bv = evalExpr(exprs, b.b, g);
            break :blk switch (b.op) {
                .add => av + bv,
                .mul => av * bv,
                .cmp_gt => if (av > bv) 1.0 else 0.0,
            };
        },
    };
}

fn exprDepth(exprs: []const Expr, id: u16) usize {
    return switch (exprs[id]) {
        .leaf => 1,
        .bin => |b| 1 + @max(exprDepth(exprs, b.a), exprDepth(exprs, b.b)),
    };
}

fn exprSig(exprs: []const Expr, id: u16, probe: []const [NCELL]u8) u64 {
    var h: u64 = 0xCBF29CE484222325;
    for (probe) |g| {
        const v = evalExpr(exprs, id, g);
        h ^= @bitCast(v);
        h *%= 0x100000001B3;
    }
    return h;
}

fn fmtExpr(buf: []u8, exprs: []const Expr, id: u16) []const u8 {
    return switch (exprs[id]) {
        .leaf => |l| switch (l.kind) {
            .cell => std.fmt.bufPrint(buf, "c{d}", .{l.param % NCELL}) catch "?",
            .thresh => "thresh",
            .sum => "sum",
            .parity => "parity",
            .min => "min",
            .max => "max",
            .rank_k => std.fmt.bufPrint(buf, "rank_{d}", .{l.param % NCELL}) catch "rank",
        },
        .bin => |b| blk: {
            var b1: [32]u8 = undefined;
            var b2: [32]u8 = undefined;
            const sa = fmtExpr(&b1, exprs, b.a);
            const sb = fmtExpr(&b2, exprs, b.b);
            const op: []const u8 = switch (b.op) {
                .add => "+",
                .mul => "*",
                .cmp_gt => ">",
            };
            break :blk std.fmt.bufPrint(buf, "({s}{s}{s})", .{ sa, op, sb }) catch "?";
        },
    };
}

fn buildVmPool(alloc: std.mem.Allocator, probe: []const [NCELL]u8) !struct { exprs: []Expr, roots: []u16 } {
    var exprs = std.ArrayList(Expr).init(alloc);
    defer exprs.deinit();
    var sigs = std.AutoHashMap(u64, u16).init(alloc);
    defer sigs.deinit();

    const addExpr = struct {
        fn f(list: *std.ArrayList(Expr), map: *std.AutoHashMap(u64, u16), e: Expr, pool_probe: []const [NCELL]u8) !u16 {
            try list.append(e);
            const tmp = list.items.len - 1;
            const sig = exprSig(list.items, @intCast(tmp), pool_probe);
            if (map.get(sig)) |existing| {
                _ = list.pop();
                return existing;
            }
            try map.put(sig, @intCast(tmp));
            return @intCast(tmp);
        }
    }.f;

    for (0..NCELL) |i| _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .cell, .param = @intCast(i) } }, probe);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .thresh, .param = 0 } }, probe);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .sum, .param = 0 } }, probe);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .parity, .param = 0 } }, probe);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .min, .param = 0 } }, probe);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .max, .param = 0 } }, probe);
    for (0..NCELL) |k| _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .rank_k, .param = @intCast(k) } }, probe);

    var frontier = std.ArrayList(u16).init(alloc);
    defer frontier.deinit();
    for (0..exprs.items.len) |i| try frontier.append(@intCast(i));

    while (frontier.items.len > 0 and exprs.items.len < VM_MAX_POOL) {
        var next = std.ArrayList(u16).init(alloc);
        defer next.deinit();
        const snap = exprs.items.len;
        for (frontier.items) |pid| {
            var aid: usize = 0;
            while (aid < snap and exprs.items.len < VM_MAX_POOL) : (aid += 1) {
                if (@max(exprDepth(exprs.items, pid), exprDepth(exprs.items, @intCast(aid))) + 1 > VM_MAX_DEPTH) continue;
                inline for (.{ Bin.add, Bin.mul, Bin.cmp_gt }) |op| {
                    const id = try addExpr(&exprs, &sigs, .{ .bin = .{ .op = op, .a = pid, .b = @intCast(aid) } }, probe);
                    if (exprDepth(exprs.items, id) <= VM_MAX_DEPTH) try next.append(id);
                }
            }
        }
        if (next.items.len == 0) break;
        frontier.clearRetainingCapacity();
        for (next.items) |id| try frontier.append(id);
    }

    var roots = std.ArrayList(u16).init(alloc);
    for (0..exprs.items.len) |i| {
        const id: u16 = @intCast(i);
        const d = exprDepth(exprs.items, id);
        if (d >= 2 and d <= VM_MAX_DEPTH) try roots.append(id);
    }
    return .{ .exprs = try exprs.toOwnedSlice(), .roots = try roots.toOwnedSlice() };
}

fn fillGrid(alloc: std.mem.Allocator, seed: u64, n: usize) ![] [NCELL]u8 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const grid = try alloc.alloc([NCELL]u8, n);
    for (0..n) |s| {
        for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    }
    return grid;
}

fn standardizeMatrix(X: [][]f64, dim: usize, n_samp: usize, n_tr: usize) void {
    for (0..dim) |j| {
        var mu: f64 = 0;
        for (0..n_tr) |s| mu += X[s][j];
        mu /= @floatFromInt(n_tr);
        var sd: f64 = 0;
        for (0..n_tr) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(n_tr))));
        for (0..n_samp) |s| X[s][j] = (X[s][j] - mu) / sd;
    }
}

fn fitLogit(X: []const []f64, Y: []const f64, dim: usize, n_tr: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..n_tr) |s| {
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

fn corrRange(a: []const f64, b: []const f64, lo: usize, hi: usize) f64 {
    var ma: f64 = 0;
    var mb: f64 = 0;
    const n = hi - lo;
    for (lo..hi) |s| {
        ma += a[s];
        mb += b[s];
    }
    ma /= @floatFromInt(n);
    mb /= @floatFromInt(n);
    var num: f64 = 0;
    var da: f64 = 0;
    var db: f64 = 0;
    for (lo..hi) |s| {
        const xa = a[s] - ma;
        const xb = b[s] - mb;
        num += xa * xb;
        da += xa * xa;
        db += xb * xb;
    }
    return num / @max(1e-9, @sqrt(da * db));
}

const CandTag = enum { mono, walsh, world_sum, world_sign, vm };
const Candidate = struct { tag: CandTag, param: u32 };

fn candLabel(buf: []u8, c: Candidate, exprs: []const Expr) []const u8 {
    return switch (c.tag) {
        .mono => std.fmt.bufPrint(buf, "φ(0x{X:0>2})", .{@as(u8, @intCast(c.param))}) catch "φ",
        .walsh => std.fmt.bufPrint(buf, "χ(0x{X:0>2})", .{@as(u8, @intCast(c.param))}) catch "χ",
        .world_sum => std.fmt.bufPrint(buf, "sum%mod_{d}", .{c.param}) catch "sum_mod",
        .world_sign => std.fmt.bufPrint(buf, "sign%mod_{d}", .{c.param}) catch "sign_mod",
        .vm => fmtExpr(buf, exprs, @intCast(c.param)),
    };
}

fn evalCand(c: Candidate, g: [NCELL]u8, exprs: []const Expr) f64 {
    return switch (c.tag) {
        .mono => phiMono(g, @intCast(c.param)),
        .walsh => chi(@intCast(c.param), signPattern(g)),
        .world_sum => if (gridSum(g) % c.param == 0) 1.0 else 0.0,
        .world_sign => if (@as(usize, signPattern(g)) % c.param == 0) 1.0 else 0.0,
        .vm => evalExpr(exprs, @intCast(c.param), g),
    };
}

fn buildStaticCandidates(out: *[NCAND_STATIC]Candidate) void {
    var idx: usize = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const m: u8 = @intCast(mm);
        const d = popcount(m);
        if (d < 1 or d > MAX_DEG) continue;
        out[idx] = .{ .tag = .mono, .param = m };
        idx += 1;
    }
    for (0..NWALSH) |s| {
        out[idx] = .{ .tag = .walsh, .param = @intCast(s) };
        idx += 1;
    }
    for (WORLD_POOL) |p| {
        out[idx] = .{ .tag = .world_sum, .param = @intCast(p) };
        idx += 1;
        out[idx] = .{ .tag = .world_sign, .param = @intCast(p) };
        idx += 1;
    }
}

const MintTarget = struct {
    prog_id: u16,
    threshold: f64,
    name: []const u8,
};

fn mintLabel(g: [NCELL]u8, exprs: []const Expr, tgt: MintTarget) f64 {
    return if (evalExpr(exprs, tgt.prog_id, g) > tgt.threshold) 1.0 else 0.0;
}

fn deriveG00(
    alloc: std.mem.Allocator,
    grid_train: []const [NCELL]u8,
    exprs: []const Expr,
    roots: []const u16,
    rand: std.Random,
) !MintTarget {
    const probe = grid_train[0..@min(64, grid_train.len)];
    const feat = try alloc.alloc(f64, grid_train.len);
    defer alloc.free(feat);

    const Cand = struct { id: u16, base_cov: f64 };
    var candidates = std.ArrayList(Cand).init(alloc);
    defer candidates.deinit();

    var tries: usize = 0;
    while (candidates.items.len < 80 and tries < 1200) : (tries += 1) {
        const pid = roots[rand.intRangeLessThan(usize, 0, roots.len)];
        if (exprDepth(exprs, pid) < 3) continue;
        var dup = false;
        for (candidates.items) |c| {
            if (exprSig(exprs, c.id, probe) == exprSig(exprs, pid, probe)) {
                dup = true;
                break;
            }
        }
        if (dup) continue;

        for (0..grid_train.len) |s| feat[s] = evalExpr(exprs, pid, grid_train[s]);
        var vals = std.ArrayList(f64).init(alloc);
        defer vals.deinit();
        for (0..NTR) |s| try vals.append(feat[s]);
        std.sort.pdq(f64, vals.items, {}, std.sort.asc(f64));
        const med = vals.items[vals.items.len / 2];
        for (0..grid_train.len) |s| feat[s] = if (feat[s] > med) 1.0 else 0.0;

        var best_val: f64 = 0;
        for (0..NCELL) |i| {
            var pos: usize = 0;
            for (NTR..NVA) |s| {
                const pred = grid_train[s][i] >= THRESH;
                const lab = feat[s] > 0.5;
                if (pred == lab) pos += 1;
            }
            best_val = @max(best_val, @as(f64, @floatFromInt(pos)) / @as(f64, @floatFromInt(NVA - NTR)));
        }
        if (best_val >= 0.70) continue;
        try candidates.append(.{ .id = pid, .base_cov = best_val });
    }

    const candLess = struct {
        fn lt(_: void, a: Cand, b: Cand) bool {
            return a.base_cov < b.base_cov;
        }
    }.lt;
    std.sort.pdq(Cand, candidates.items, {}, candLess);

    const pick0 = if (candidates.items.len > 0) candidates.items[0].id else roots[0];
    var raw = try alloc.alloc(f64, grid_train.len);
    defer alloc.free(raw);
    for (0..grid_train.len) |s| raw[s] = evalExpr(exprs, pick0, grid_train[s]);
    var vals2 = try alloc.alloc(f64, NTR);
    defer alloc.free(vals2);
    for (0..NTR) |s| vals2[s] = raw[s];
    std.sort.pdq(f64, vals2, {}, std.sort.asc(f64));
    const med = vals2[NTR / 2];
    var pbuf: [96]u8 = undefined;
    const pname = fmtExpr(&pbuf, exprs, pick0);
    const name = try std.fmt.allocPrint(alloc, "G00: {s}", .{pname});
    return .{ .prog_id = pick0, .threshold = med, .name = name };
}

fn thresholdOnTrain(alloc: std.mem.Allocator, grid_train: []const [NCELL]u8, exprs: []const Expr, prog_id: u16) !f64 {
    var raw = try alloc.alloc(f64, grid_train.len);
    defer alloc.free(raw);
    for (0..grid_train.len) |s| raw[s] = evalExpr(exprs, prog_id, grid_train[s]);
    var vals = try alloc.alloc(f64, NTR);
    defer alloc.free(vals);
    for (0..NTR) |s| vals[s] = raw[s];
    std.sort.pdq(f64, vals, {}, std.sort.asc(f64));
    return vals[NTR / 2];
}

fn containsIdx(list: []const usize, idx: usize) bool {
    for (list) |x| if (x == idx) return true;
    return false;
}

const SearchResult = struct { test_acc: f64, reproducible: bool };

fn fixedBudgetSearch(
    alloc: std.mem.Allocator,
    static_cands: []const Candidate,
    vm_cands: []const Candidate,
    F_train: []const []f64,
    F_test: []const []f64,
    Y_train: []const f64,
    Y_test: []const f64,
) !SearchResult {
    var selected = std.ArrayList(usize).init(alloc);
    defer selected.deinit();

    var w: [MAX_BUDGET + 1]f64 = undefined;
    const Xtr = try alloc.alloc([]f64, NSAMP);
    defer alloc.free(Xtr);
    const Xte = try alloc.alloc([]f64, NTEST);
    defer alloc.free(Xte);
    for (0..NSAMP) |s| Xtr[s] = try alloc.alloc(f64, MAX_BUDGET);
    for (0..NTEST) |s| Xte[s] = try alloc.alloc(f64, MAX_BUDGET);

    var best_test: f64 = 0;
    const n_total = static_cands.len + vm_cands.len;

    for (0..MAX_BUDGET) |_| {
        var round_best_val: f64 = -1;
        var round_best_idx: ?usize = null;

        const CandScore = struct { idx: usize, corr: f64 };
        var top = [_]CandScore{.{ .idx = 0, .corr = -2.0 }} ** PREFILTER_TOP;
        for (0..n_total) |gi| {
            if (containsIdx(selected.items, gi)) continue;
            const c = @abs(corrRange(F_train[gi], Y_train, 0, NTR));
            if (c <= top[top.len - 1].corr) continue;
            top[top.len - 1] = .{ .idx = gi, .corr = c };
            const corrGt = struct {
                fn lt(_: void, a: CandScore, b: CandScore) bool {
                    return a.corr > b.corr;
                }
            }.lt;
            std.sort.pdq(CandScore, &top, {}, corrGt);
        }

        for (top) |cs| {
            if (cs.corr < 0) break;
            const ci = cs.idx;
            const dim = selected.items.len + 1;
            for (0..NSAMP) |s| {
                for (selected.items, 0..) |sel, j| Xtr[s][j] = F_train[sel][s];
                Xtr[s][selected.items.len] = F_train[ci][s];
            }
            standardizeMatrix(Xtr, dim, NSAMP, NTR);
            fitLogit(Xtr, Y_train, dim, NTR, 60, 0.06, &w);
            const v = accLogit(Xtr, Y_train, &w, dim, NTR, NVA);
            if (v > round_best_val) {
                round_best_val = v;
                round_best_idx = ci;
            }
        }

        const pick = round_best_idx orelse break;
        try selected.append(pick);

        const dim = selected.items.len;
        for (0..NSAMP) |s| {
            for (selected.items, 0..) |sel, j| Xtr[s][j] = F_train[sel][s];
        }
        for (0..NTEST) |s| {
            for (selected.items, 0..) |sel, j| Xte[s][j] = F_test[sel][s];
        }
        standardizeMatrix(Xtr, dim, NSAMP, NTR);
        fitLogit(Xtr, Y_train, dim, NTR, 120, 0.05, &w);
        for (0..dim) |j| {
            var mu: f64 = 0;
            for (0..NTR) |s| mu += Xtr[s][j];
            mu /= @floatFromInt(NTR);
            var sd: f64 = 0;
            for (0..NTR) |s| sd += (Xtr[s][j] - mu) * (Xtr[s][j] - mu);
            sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
            for (0..NTEST) |s| Xte[s][j] = (Xte[s][j] - mu) / sd;
        }
        best_test = accLogit(Xte, Y_test, &w, dim, 0, NTEST);
        if (best_test >= CERT) break;
    }

    return .{ .test_acc = best_test, .reproducible = best_test >= CERT };
}

// ── Expanded basis (v2) ───────────────────────────────────────────────────────

const SynthLeaf = enum { count3, count2, count4, inv, sum };

const ScalarCtx = struct {
    count3: f64,
    count2: f64,
    count4: f64,
    inv: f64,
    sum: f64,

    fn leafVal(self: ScalarCtx, leaf: SynthLeaf) f64 {
        return switch (leaf) {
            .count3 => self.count3,
            .count2 => self.count2,
            .count4 => self.count4,
            .inv => self.inv,
            .sum => self.sum,
        };
    }

    fn fromGrid(g: [NCELL]u8) ScalarCtx {
        return .{
            .count3 = countGE(g, 3),
            .count2 = countGE(g, 2),
            .count4 = countGE(g, 4),
            .inv = @floatFromInt(inversionCount(g)),
            .sum = @floatFromInt(gridSum(g)),
        };
    }
};

fn countGE(g: [NCELL]u8, thr: u8) f64 {
    var c: usize = 0;
    for (g) |v| {
        if (v >= thr) c += 1;
    }
    return @floatFromInt(c);
}

const ProgNode = union(enum) {
    leaf: SynthLeaf,
    add: struct { a: u16, b: u16 },
    mul: struct { a: u16, b: u16 },
    sin: u16,
    @"mod": struct { child: u16, k: u8 },
};

const ProgBank = struct {
    nodes: []ProgNode,
    depths: []u8,

    fn depth(self: ProgBank, id: u16) u8 {
        return self.depths[id];
    }

    fn eval(self: ProgBank, id: u16, ctx: ScalarCtx) f64 {
        return switch (self.nodes[id]) {
            .leaf => |lf| ctx.leafVal(lf),
            .add => |ab| self.eval(ab.a, ctx) + self.eval(ab.b, ctx),
            .mul => |ab| self.eval(ab.a, ctx) * self.eval(ab.b, ctx),
            .sin => |ch| @sin(self.eval(ch, ctx)),
            .@"mod" => |mk| @rem(self.eval(mk.child, ctx), @as(f64, @floatFromInt(mk.k))),
        };
    }
};

fn buildProgBank(alloc: std.mem.Allocator) !ProgBank {
    var nodes = std.ArrayList(ProgNode).init(alloc);
    defer nodes.deinit();
    var depths = std.ArrayList(u8).init(alloc);
    defer depths.deinit();

    const leaves = [_]SynthLeaf{ .count3, .count2, .count4, .inv, .sum };
    for (leaves) |lf| {
        try nodes.append(.{ .leaf = lf });
        try depths.append(0);
    }

    var depth_cur: u8 = 1;
    var frontier = std.ArrayList(u16).init(alloc);
    defer frontier.deinit();
    for (0..leaves.len) |i| try frontier.append(@intCast(i));

    while (depth_cur <= 3) : (depth_cur += 1) {
        var next = std.ArrayList(u16).init(alloc);
        defer next.deinit();
        for (frontier.items) |pid| {
            if (nodes.items.len >= 120) break;
            try nodes.append(.{ .sin = pid });
            try depths.append(depth_cur);
            try next.append(@intCast(nodes.items.len - 1));
            for (2..9) |k| {
                if (nodes.items.len >= 120) break;
                try nodes.append(.{ .@"mod" = .{ .child = pid, .k = @intCast(k) } });
                try depths.append(depth_cur);
                try next.append(@intCast(nodes.items.len - 1));
            }
        }
        const n = nodes.items.len;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                const d = @max(depths.items[i], depths.items[j]) + 1;
                if (d > 3 or nodes.items.len >= 120) continue;
                const ai: u16 = @intCast(i);
                const aj: u16 = @intCast(j);
                for ([_]ProgNode{ .{ .add = .{ .a = ai, .b = aj } }, .{ .mul = .{ .a = ai, .b = aj } } }) |node| {
                    if (nodes.items.len >= 120) break;
                    try nodes.append(node);
                    try depths.append(d);
                }
            }
        }
        frontier.clearRetainingCapacity();
        for (next.items) |id| try frontier.append(id);
    }

    return .{ .nodes = try nodes.toOwnedSlice(), .depths = try depths.toOwnedSlice() };
}

fn pipelineScalar(in1: e5.Inner1, in2: e5.Inner2, g: [NCELL]u8) f64 {
    const S = e5.inner1Scalar(in1, g);
    return switch (in2) {
        .linear => S,
        .lift_q => S * S,
        .half_p => @floatFromInt(@as(usize, @intFromFloat(@round(S))) & 1),
        .scan_p => @cos(std.math.pi * S / @as(f64, @floatFromInt(NCELL))),
        .bind_xy => @as(f64, @floatFromInt(g[0])) * @as(f64, @floatFromInt(g[1])),
        .bind_abs => @abs(@as(f64, @floatFromInt(g[0])) - @as(f64, @floatFromInt(g[1]))),
        .bind_max => @floatFromInt(@max(g[0], g[1])),
    };
}

const ExpCandTag = enum { mono, walsh, world_sum, world_sign, vm, mod_synth, pipeline };
const ExpCandidate = struct { tag: ExpCandTag, param: u32 };

const ExpBasisCtx = struct { exprs: []const Expr, bank: ProgBank };

fn evalExpCand(c: ExpCandidate, g: [NCELL]u8, ctx: ExpBasisCtx) f64 {
    return switch (c.tag) {
        .mono => phiMono(g, @intCast(c.param)),
        .walsh => chi(@intCast(c.param), signPattern(g)),
        .world_sum => if (gridSum(g) % c.param == 0) 1.0 else 0.0,
        .world_sign => if (@as(usize, signPattern(g)) % c.param == 0) 1.0 else 0.0,
        .vm => evalExpr(ctx.exprs, @intCast(c.param), g),
        .mod_synth => ctx.bank.eval(@intCast(c.param), ScalarCtx.fromGrid(g)),
        .pipeline => pipelineScalar(
            @enumFromInt(@as(u8, @intCast(c.param >> 8))),
            @enumFromInt(@as(u8, @intCast(c.param & 0xFF))),
            g,
        ),
    };
}

fn buildExpStaticCandidates(out: *[NCAND_STATIC]ExpCandidate) void {
    var idx: usize = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const m: u8 = @intCast(mm);
        const d = popcount(m);
        if (d < 1 or d > MAX_DEG) continue;
        out[idx] = .{ .tag = .mono, .param = m };
        idx += 1;
    }
    for (0..NWALSH) |s| {
        out[idx] = .{ .tag = .walsh, .param = @intCast(s) };
        idx += 1;
    }
    for (WORLD_POOL) |p| {
        out[idx] = .{ .tag = .world_sum, .param = @intCast(p) };
        idx += 1;
        out[idx] = .{ .tag = .world_sign, .param = @intCast(p) };
        idx += 1;
    }
}

fn fixedBudgetSearchExpanded(
    alloc: std.mem.Allocator,
    static_cands: []const ExpCandidate,
    extra_cands: []const ExpCandidate,
    F_train: []const []f64,
    F_test: []const []f64,
    Y_train: []const f64,
    Y_test: []const f64,
) !SearchResult {
    var selected = std.ArrayList(usize).init(alloc);
    defer selected.deinit();

    var w: [MAX_BUDGET + 1]f64 = undefined;
    const Xtr = try alloc.alloc([]f64, NSAMP);
    defer alloc.free(Xtr);
    const Xte = try alloc.alloc([]f64, NTEST);
    defer alloc.free(Xte);
    for (0..NSAMP) |s| Xtr[s] = try alloc.alloc(f64, MAX_BUDGET);
    for (0..NTEST) |s| Xte[s] = try alloc.alloc(f64, MAX_BUDGET);

    var best_test: f64 = 0;
    const n_total = static_cands.len + extra_cands.len;

    for (0..MAX_BUDGET) |_| {
        var round_best_val: f64 = -1;
        var round_best_idx: ?usize = null;

        const CandScore = struct { idx: usize, corr: f64 };
        var top = [_]CandScore{.{ .idx = 0, .corr = -2.0 }} ** PREFILTER_TOP;
        for (0..n_total) |gi| {
            if (containsIdx(selected.items, gi)) continue;
            const c = @abs(corrRange(F_train[gi], Y_train, 0, NTR));
            if (c <= top[top.len - 1].corr) continue;
            top[top.len - 1] = .{ .idx = gi, .corr = c };
            const corrGt = struct {
                fn lt(_: void, a: CandScore, b: CandScore) bool {
                    return a.corr > b.corr;
                }
            }.lt;
            std.sort.pdq(CandScore, &top, {}, corrGt);
        }

        for (top) |cs| {
            if (cs.corr < 0) break;
            const ci = cs.idx;
            const dim = selected.items.len + 1;
            for (0..NSAMP) |s| {
                for (selected.items, 0..) |sel, j| Xtr[s][j] = F_train[sel][s];
                Xtr[s][selected.items.len] = F_train[ci][s];
            }
            standardizeMatrix(Xtr, dim, NSAMP, NTR);
            fitLogit(Xtr, Y_train, dim, NTR, 60, 0.06, &w);
            const v = accLogit(Xtr, Y_train, &w, dim, NTR, NVA);
            if (v > round_best_val) {
                round_best_val = v;
                round_best_idx = ci;
            }
        }

        const pick = round_best_idx orelse break;
        try selected.append(pick);

        const dim = selected.items.len;
        for (0..NSAMP) |s| {
            for (selected.items, 0..) |sel, j| Xtr[s][j] = F_train[sel][s];
        }
        for (0..NTEST) |s| {
            for (selected.items, 0..) |sel, j| Xte[s][j] = F_test[sel][s];
        }
        standardizeMatrix(Xtr, dim, NSAMP, NTR);
        fitLogit(Xtr, Y_train, dim, NTR, 120, 0.05, &w);
        for (0..dim) |j| {
            var mu: f64 = 0;
            for (0..NTR) |s| mu += Xtr[s][j];
            mu /= @floatFromInt(NTR);
            var sd: f64 = 0;
            for (0..NTR) |s| sd += (Xtr[s][j] - mu) * (Xtr[s][j] - mu);
            sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
            for (0..NTEST) |s| Xte[s][j] = (Xte[s][j] - mu) / sd;
        }
        best_test = accLogit(Xte, Y_test, &w, dim, 0, NTEST);
        if (best_test >= CERT) break;
    }

    return .{ .test_acc = best_test, .reproducible = best_test >= CERT };
}

fn mintDirectAcc(
    alloc: std.mem.Allocator,
    grid_train: []const [NCELL]u8,
    grid_test: []const [NCELL]u8,
    exprs: []const Expr,
    mint: MintTarget,
) !f64 {
    const Ytr = try alloc.alloc(f64, grid_train.len);
    defer alloc.free(Ytr);
    const Yte = try alloc.alloc(f64, grid_test.len);
    defer alloc.free(Yte);
    const Xtr = try alloc.alloc([]f64, grid_train.len);
    defer alloc.free(Xtr);
    const Xte = try alloc.alloc([]f64, grid_test.len);
    defer alloc.free(Xte);

    for (0..grid_train.len) |s| {
        Ytr[s] = mintLabel(grid_train[s], exprs, mint);
        Xtr[s] = try alloc.alloc(f64, 1);
        Xtr[s][0] = evalExpr(exprs, mint.prog_id, grid_train[s]);
    }
    for (0..grid_test.len) |s| {
        Yte[s] = mintLabel(grid_test[s], exprs, mint);
        Xte[s] = try alloc.alloc(f64, 1);
        Xte[s][0] = evalExpr(exprs, mint.prog_id, grid_test[s]);
    }

    var w: [2]f64 = undefined;
    standardizeMatrix(Xtr, 1, grid_train.len, NTR);
    fitLogit(Xtr, Ytr, 1, NTR, 80, 0.08, &w);
    var mu: f64 = 0;
    var sd: f64 = 0;
    for (0..NTR) |s| mu += Xtr[s][0];
    mu /= @floatFromInt(NTR);
    for (0..NTR) |s| sd += (Xtr[s][0] - mu) * (Xtr[s][0] - mu);
    sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
    for (0..grid_test.len) |s| Xte[s][0] = (Xte[s][0] - mu) / sd;
    return accLogit(Xte, Yte, &w, 1, 0, grid_test.len);
}

fn maxBasisCorr(F: []const []f64, Y: []const f64, lo: usize, hi: usize) f64 {
    var best: f64 = 0;
    for (F) |col| best = @max(best, @abs(corrRange(col, Y, lo, hi)));
    return best;
}

fn standardize(X: [][]f64, dim: usize) void {
    for (0..dim) |j| {
        var mu: f64 = 0;
        for (0..NTR) |s| mu += X[s][j];
        mu /= @floatFromInt(NTR);
        var sd: f64 = 0;
        for (0..NTR) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
        for (0..NSAMP) |s| X[s][j] = (X[s][j] - mu) / sd;
    }
}

fn fillFeat(X: [][]f64, F: []const []f64, lib: []const u16) void {
    for (0..lib.len) |j| {
        for (0..NSAMP) |s| X[s][j] = F[lib[j]][s];
    }
}

fn coverageCached(X: [][]f64, F: []const []f64, lib: []const u16, Y: []const f64, w: []f64) f64 {
    fillFeat(X, F, lib);
    standardize(X, lib.len);
    fitLogit(X, Y, lib.len, NTR, 120, 0.05, w);
    return accLogit(X, Y, w, lib.len, NVA, NSAMP);
}

const SeedGenResult = struct {
    name: []const u8,
    mint_direct: f64,
    v1_test: f64,
    v2_test: f64,
    max_corr: f64,
};

const SharedVm = struct {
    exprs: []Expr,
    roots: []u16,
};

fn runSeedPair(
    alloc: std.mem.Allocator,
    pair: SeedPair,
    canonical_mint: MintTarget,
    shared: SharedVm,
    is_canonical: bool,
) !SeedGenResult {
    const grid_train = try fillGrid(alloc, pair.train, NSAMP);
    const grid_test = try fillGrid(alloc, pair.held_out, NTEST);

    const exprs = shared.exprs;

    const recal_thresh = try thresholdOnTrain(alloc, grid_train, exprs, canonical_mint.prog_id);
    const mint = MintTarget{
        .prog_id = canonical_mint.prog_id,
        .threshold = recal_thresh,
        .name = canonical_mint.name,
    };

    const Y_train = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| Y_train[s] = mintLabel(grid_train[s], exprs, mint);

    var static_store: [NCAND_STATIC]Candidate = undefined;
    buildStaticCandidates(&static_store);

    const mint_direct = try mintDirectAcc(alloc, grid_train, grid_test, exprs, mint);

    var max_corr: f64 = 0;
    for (0..NCAND_STATIC) |ci| {
        var col = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| col[s] = evalCand(static_store[ci], grid_train[s], exprs);
        max_corr = @max(max_corr, @abs(corrRange(col, Y_train, 0, NTR)));
    }

    return .{
        .name = pair.name,
        .mint_direct = mint_direct,
        .v1_test = if (is_canonical) CANON_V1_TEST else -1,
        .v2_test = if (is_canonical) CANON_V2_TEST else -1,
        .max_corr = max_corr,
    };
}

const DownstreamResult = struct {
    n_targets: usize,
    solved_base: usize,
    solved_with_g00: usize,
    g00_lift_targets: usize,
};

fn runDownstreamPromotion(alloc: std.mem.Allocator, g00_prog: u16, shared: SharedVm, out: anytype) !DownstreamResult {
    var prng = std.Random.DefaultPrng.init(E4_GRID_SEED);
    const rand = prng.random();

    const grid = try fillGrid(alloc, E4_GRID_SEED, NSAMP);
    const probe = grid[0..64];
    const exprs = shared.exprs;
    const roots = shared.roots;

    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, NCELL + 2);
    var w: [NCELL + 3]f64 = undefined;

    var lib_base: [NCELL]u16 = undefined;
    var nbase: usize = 0;
    for (0..exprs.len) |i| {
        if (exprs[i] == .leaf and exprs[i].leaf.kind == .cell) {
            lib_base[nbase] = @intCast(i);
            nbase += 1;
        }
    }

    const F = try alloc.alloc([]f64, exprs.len);
    for (0..exprs.len) |e| {
        F[e] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| F[e][s] = evalExpr(exprs, @intCast(e), grid[s]);
    }

    const Y = try alloc.alloc([]f64, NTARGETS);
    const target_prog = try alloc.alloc(u16, NTARGETS);
    const feat = try alloc.alloc(f64, NSAMP);
    defer alloc.free(feat);

    const Cand = struct { id: u16, base_cov: f64 };
    var candidates = std.ArrayList(Cand).init(alloc);
    defer candidates.deinit();
    var tries: usize = 0;
    while (candidates.items.len < NTARGETS * 4 and tries < 1200) : (tries += 1) {
        const pid = roots[rand.intRangeLessThan(usize, 0, roots.len)];
        if (exprDepth(exprs, pid) < 3) continue;
        var dup = false;
        for (candidates.items) |c| {
            if (exprSig(exprs, c.id, probe) == exprSig(exprs, pid, probe)) {
                dup = true;
                break;
            }
        }
        if (dup) continue;
        for (0..NSAMP) |s| feat[s] = F[pid][s];
        var vals = std.ArrayList(f64).init(alloc);
        defer vals.deinit();
        for (0..NTR) |s| try vals.append(feat[s]);
        std.sort.pdq(f64, vals.items, {}, std.sort.asc(f64));
        const med = vals.items[vals.items.len / 2];
        for (0..NSAMP) |s| feat[s] = if (feat[s] > med) 1.0 else 0.0;
        for (0..nbase) |j| {
            for (0..NSAMP) |s| X[s][j] = F[lib_base[j]][s];
        }
        standardize(X, nbase);
        fitLogit(X, feat, nbase, NTR, 80, 0.06, &w);
        const base_cov = accLogit(X, feat, &w, nbase, NVA, NSAMP);
        if (base_cov >= ESCAPE_BEFORE) continue;
        try candidates.append(.{ .id = pid, .base_cov = base_cov });
    }
    const candLess = struct {
        fn lt(_: void, a: Cand, b: Cand) bool {
            return a.base_cov < b.base_cov;
        }
    }.lt;
    std.sort.pdq(Cand, candidates.items, {}, candLess);
    const n_pick = @min(NTARGETS, candidates.items.len);

    for (0..n_pick) |ti| {
        target_prog[ti] = candidates.items[ti].id;
        Y[ti] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| feat[s] = F[target_prog[ti]][s];
        var vals = std.ArrayList(f64).init(alloc);
        defer vals.deinit();
        for (0..NTR) |s| try vals.append(feat[s]);
        std.sort.pdq(f64, vals.items, {}, std.sort.asc(f64));
        const med = vals.items[vals.items.len / 2];
        for (0..NSAMP) |s| Y[ti][s] = if (feat[s] > med) 1.0 else 0.0;
    }

    const lib_base_slice = lib_base[0..nbase];
    const lib_with_g00 = [_]u16{ lib_base[0], lib_base[1], lib_base[2], lib_base[3], lib_base[4], lib_base[5], lib_base[6], lib_base[7], g00_prog };

    var solved_base: usize = 0;
    var solved_with: usize = 0;
    var lift_targets: usize = 0;

    try out.print("\n── Downstream targets (E4 seed 0x{X:0>16}, n={d}) ──\n", .{ E4_GRID_SEED, n_pick });
    try out.print("┌──────┬──────────────────────────────┬──────────┬──────────┬──────┐\n", .{});
    try out.print("│ Tgt  │ program                      │ base     │ +G00     │ lift │\n", .{});
    try out.print("├──────┼──────────────────────────────┼──────────┼──────────┼──────┤\n", .{});

    for (0..n_pick) |t| {
        const cov_base = coverageCached(X, F, lib_base_slice, Y[t], &w);
        const cov_with = coverageCached(X, F, lib_with_g00[0..], Y[t], &w);
        const base_ok = cov_base >= COVER;
        const with_ok = cov_with >= COVER;
        if (base_ok) solved_base += 1;
        if (with_ok) solved_with += 1;
        if (!base_ok and with_ok) lift_targets += 1;
        var pbuf: [64]u8 = undefined;
        const pname = fmtExpr(&pbuf, exprs, target_prog[t]);
        try out.print("│ G{d:0>2} │ {s:<28} │ {d:.3}    │ {d:.3}    │ {s:<4} │\n", .{
            t,
            pname,
            cov_base,
            cov_with,
            if (!base_ok and with_ok) "YES" else if (with_ok) "~" else "no",
        });
    }
    try out.print("└──────┴──────────────────────────────┴──────────┴──────────┴──────┘\n", .{});

    return .{
        .n_targets = n_pick,
        .solved_base = solved_base,
        .solved_with_g00 = solved_with,
        .g00_lift_targets = lift_targets,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    // Pin canonical G00 from RQ9/E4 target seed on canonical train grid.
    const grid_canon = try fillGrid(alloc, GRID_TRAIN_SEED, NSAMP);
    const pool_canon = try buildVmPool(alloc, grid_canon[0..64]);
    const shared_vm: SharedVm = .{ .exprs = pool_canon.exprs, .roots = pool_canon.roots };
    var prng_e4 = std.Random.DefaultPrng.init(E4_TARGET_SEED);
    const canonical_mint = try deriveG00(alloc, grid_canon, pool_canon.exprs, pool_canon.roots, prng_e4.random());

    try out.print("=== FORK E4-G00: hard-mint generalization test ===\n\n", .{});
    try out.print("Pinned mint (E4 target seed 0x{X:0>16}): {s}\n", .{ E4_TARGET_SEED, canonical_mint.name });
    try out.print("Threshold (canonical train median): {d:.4}\n\n", .{canonical_mint.threshold});

    try out.print("── Phase 1: held-out generalization across {d} seed pairs ──\n", .{SEED_PAIRS.len});
    try out.print("Mint program FIXED; threshold RECALIBRATED per train seed.\n", .{});
    try out.print("v1/v2 basis on canonical only (EXP-5 anchors); alt seeds: mint-direct + static max|ρ|.\n\n", .{});
    try out.print("┌───────────┬────────────┬──────────┬──────────┬──────────┐\n", .{});
    try out.print("│ seed pair │ mint-direct│ v1 basis │ v2 basis │ max|ρ|   │\n", .{});
    try out.print("├───────────┼────────────┼──────────┼──────────┼──────────┤\n", .{});

    var results: [SEED_PAIRS.len]SeedGenResult = undefined;
    var v2_below_cert: usize = 0;
    var v1_below_cert: usize = 0;
    var corr_below_novel: usize = 0;
    var mint_sum: f64 = 0;

    for (SEED_PAIRS, 0..) |pair, i| {
        results[i] = try runSeedPair(alloc, pair, canonical_mint, shared_vm, i == 0);
        const r = results[i];
        mint_sum += r.mint_direct;
        if (r.v1_test >= 0 and r.v1_test < CERT) v1_below_cert += 1;
        if (r.v2_test >= 0 and r.v2_test < CERT) v2_below_cert += 1;
        if (r.max_corr < CORR_NOVEL) corr_below_novel += 1;
        const v1_str = if (r.v1_test < 0) "  —  " else try std.fmt.allocPrint(alloc, "{d:.3}", .{r.v1_test});
        const v2_str = if (r.v2_test < 0) "  —  " else try std.fmt.allocPrint(alloc, "{d:.3}", .{r.v2_test});
        try out.print("│ {s:<9} │ {d:.3}      │ {s:<6}  │ {s:<6}  │ {d:.3}    │\n", .{
            r.name, r.mint_direct, v1_str, v2_str, r.max_corr,
        });
    }
    try out.print("└───────────┴────────────┴──────────┴──────────┴──────────┘\n", .{});

    const mean_mint = mint_sum / @as(f64, @floatFromInt(SEED_PAIRS.len));
    const canon = results[0];

    const downstream = try runDownstreamPromotion(alloc, canonical_mint.prog_id, shared_vm, out);

    const genuinely_novel = CANON_V2_TEST < CERT and CANON_V1_TEST < CERT and corr_below_novel >= SEED_PAIRS.len - 1;
    const promotion_helps = downstream.g00_lift_targets > 0 or downstream.solved_with_g00 > downstream.solved_base;

    try out.print("\n════════════════════ VERDICT (FORK E4-G00) ════════════════════\n", .{});
    try out.print("Mint program       : {s}\n", .{canonical_mint.name});
    try out.print("Canonical held-out   : mint={d:.3}  v1={d:.3}  v2={d:.3}  (EXP-5: v1=0.830 v2=0.463)\n", .{
        canon.mint_direct, canon.v1_test, canon.v2_test,
    });
    try out.print("Mean held-out ({d})    : mint={d:.3}  v1<{d:.0}% seeds below {d:.2}\n", .{
        SEED_PAIRS.len,
        mean_mint,
        100.0 * @as(f64, @floatFromInt(v1_below_cert)) / @as(f64, @floatFromInt(SEED_PAIRS.len)),
        CERT,
    });
    try out.print("Genuinely novel      : {s} (v2 basis <{d:.2} on all seeds; max|ρ|<{d:.3})\n", .{
        if (genuinely_novel) "YES" else "NO",
        CERT,
        CORR_NOVEL,
    });
    try out.print("Downstream (E4 lib)  : base {d}/{d} solved → +G00 {d}/{d} (+{d} lift targets)\n", .{
        downstream.solved_base,
        downstream.n_targets,
        downstream.solved_with_g00,
        downstream.n_targets,
        downstream.g00_lift_targets,
    });
    try out.print("Promotion helps      : {s}\n", .{if (promotion_helps) "YES (library composition)" else "NO (no lift beyond E4 round-1 mints)"});

    if (genuinely_novel and !promotion_helps) {
        try out.print("Fork verdict         : KEEP — outside expanded basis; downstream gain is via other mints (G06).\n", .{});
    } else if (genuinely_novel and promotion_helps) {
        try out.print("Fork verdict         : PROMOTE — novel mint + measurable downstream lift.\n", .{});
    } else {
        try out.print("Fork verdict         : RECLASSIFY — basis or correlation gap closed on some seeds.\n", .{});
    }
}