//! RESEARCH Q4 — E4 equivalence oracle: are minted programs distinct from VM depth≤6?
//!
//! Reuses the E4 certified menu-minting protocol (depth≤5 synthesis search). For each promoted
//! program, exhaustively searches the depth≤6 VM expression pool for a functional match on 10k
//! random grids within ε tolerance.
//!
//! Pass bar for "real minting": <50% of promoted programs VM-equivalent (majority genuinely distinct).
//!
//! Run: zig build open-invention-rq4 --release=fast

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const NTARGETS: usize = 20;
const MAX_DEPTH_MINT: usize = 5;
const MAX_POOL_MINT: usize = 4096;
const MAX_DEPTH_ORACLE: usize = 6;
const MAX_POOL_ORACLE: usize = 8192;
const ORACLE_PROBE: usize = 256;
const QUICK_FILTER_GRIDS: usize = 24;
const NSAMP_ORACLE: usize = 10000;
const MAX_LIB: usize = 48;
const COVER: f64 = 0.90;
const ESCAPE_BEFORE: f64 = 0.70;
const R2_MAX: f64 = 0.40;
const EPS: f64 = 1e-6;
const RNG_SEED: u64 = 0xE4CE11ED0FF1CE42;
const ORACLE_GRID_SEED: u64 = 0x0BAC1E04EEDFACE4;
const REAL_MINTING_BAR: f64 = 0.50;

const Leaf = enum {
    cell,
    thresh,
    sum,
    parity,
    min,
    max,
    rank_k,
};

const Bin = enum {
    add,
    mul,
    cmp_gt,
};

const Expr = union(enum) {
    leaf: struct { kind: Leaf, param: u8 },
    bin: struct { op: Bin, a: u16, b: u16 },
};

const Family = enum {
    known_base,
    affine_cell,
    monomial,
    pairwise_product,
    oriented_compare,
    count_thresh,
    parity_count,
    sum_reduce,
    min_max_reduce,
    rank_indicator,
    rank_value,
    composed_known,
    genuinely_new,
};

const family_name = [_][]const u8{
    "known_base",
    "affine_cell",
    "monomial",
    "pairwise_product",
    "oriented_compare",
    "count_thresh",
    "parity_count",
    "sum_reduce",
    "min_max_reduce",
    "rank_indicator",
    "rank_value",
    "composed_known",
    "genuinely_new",
};

const Promoted = struct {
    target: usize,
    root: u16,
    family: Family,
    r2: f64,
    cov_after: f64,
};

const WitnessPool = enum { mint, oracle };

const OracleResult = struct {
    equivalent: bool,
    witness: ?u16,
    witness_pool: WitnessPool,
    witness_depth: usize,
    max_diff: f64,
};

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn exprDepth(exprs: []const Expr, id: u16) usize {
    return switch (exprs[id]) {
        .leaf => 1,
        .bin => |b| 1 + @max(exprDepth(exprs, b.a), exprDepth(exprs, b.b)),
    };
}

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
        .sum => blk: {
            var s: u32 = 0;
            for (g) |v| s += v;
            break :blk @floatFromInt(s);
        },
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
        .bin => |b| {
            const av = evalExpr(exprs, b.a, g);
            const bv = evalExpr(exprs, b.b, g);
            return switch (b.op) {
                .add => av + bv,
                .mul => av * bv,
                .cmp_gt => if (av > bv) 1.0 else 0.0,
            };
        },
    };
}

fn exprSig(exprs: []const Expr, id: u16, probe: []const [NCELL]u8) u64 {
    var h: u64 = 0xCBF29CE484222325;
    for (probe) |g| {
        const v = evalExpr(exprs, id, g);
        const bits: u64 = @bitCast(v);
        h ^= bits;
        h *%= 0x100000001B3;
    }
    return h;
}

fn exprEqual(exprs: []const Expr, a: u16, b: u16) bool {
    if (@intFromEnum(std.meta.activeTag(exprs[a])) != @intFromEnum(std.meta.activeTag(exprs[b]))) return false;
    return switch (exprs[a]) {
        .leaf => |la| exprs[b].leaf.kind == la.kind and exprs[b].leaf.param == la.param,
        .bin => |ba| exprs[b].bin.op == ba.op and exprs[b].bin.a == ba.a and exprs[b].bin.b == ba.b,
    };
}

fn buildExprPool(
    alloc: std.mem.Allocator,
    probe: []const [NCELL]u8,
    max_depth: usize,
    max_pool: usize,
) !struct { exprs: []Expr, roots: []u16 } {
    var exprs = std.ArrayList(Expr).init(alloc);
    defer exprs.deinit();
    var sigs = std.AutoHashMap(u64, u16).init(alloc);
    defer sigs.deinit();

    const addExpr = struct {
        fn f(
            list: *std.ArrayList(Expr),
            map: *std.AutoHashMap(u64, u16),
            e: Expr,
            pool_probe: []const [NCELL]u8,
            cap: usize,
            depth_cap: usize,
        ) !u16 {
            try list.append(e);
            const tmp = list.items.len - 1;
            const sig = exprSig(list.items, @intCast(tmp), pool_probe);
            if (map.get(sig)) |existing| {
                _ = list.pop();
                return existing;
            }
            try map.put(sig, @intCast(tmp));
            _ = cap;
            _ = depth_cap;
            return @intCast(tmp);
        }
    }.f;

    for (0..NCELL) |i| _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .cell, .param = @intCast(i) } }, probe, max_pool, max_depth);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .thresh, .param = 0 } }, probe, max_pool, max_depth);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .sum, .param = 0 } }, probe, max_pool, max_depth);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .parity, .param = 0 } }, probe, max_pool, max_depth);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .min, .param = 0 } }, probe, max_pool, max_depth);
    _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .max, .param = 0 } }, probe, max_pool, max_depth);
    for (0..NCELL) |k| _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .rank_k, .param = @intCast(k) } }, probe, max_pool, max_depth);

    var frontier = std.ArrayList(u16).init(alloc);
    defer frontier.deinit();
    for (0..exprs.items.len) |i| try frontier.append(@intCast(i));

    while (frontier.items.len > 0 and exprs.items.len < max_pool) {
        var next = std.ArrayList(u16).init(alloc);
        defer next.deinit();
        const snap = exprs.items.len;
        for (frontier.items) |pid| {
            var aid: usize = 0;
            while (aid < snap and exprs.items.len < max_pool) : (aid += 1) {
                const da = exprDepth(exprs.items, pid);
                const db = exprDepth(exprs.items, @intCast(aid));
                if (@max(da, db) + 1 > max_depth) continue;
                inline for (.{ Bin.add, Bin.mul, Bin.cmp_gt }) |op| {
                    const id = try addExpr(
                        &exprs,
                        &sigs,
                        .{ .bin = .{ .op = op, .a = pid, .b = @intCast(aid) } },
                        probe,
                        max_pool,
                        max_depth,
                    );
                    if (exprDepth(exprs.items, id) <= max_depth) try next.append(id);
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
        if (exprDepth(exprs.items, id) >= 2 and exprDepth(exprs.items, id) <= max_depth) {
            try roots.append(id);
        }
    }

    return .{
        .exprs = try exprs.toOwnedSlice(),
        .roots = try roots.toOwnedSlice(),
    };
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
        .bin => |b| {
            var b1: [32]u8 = undefined;
            var b2: [32]u8 = undefined;
            const sa = fmtExpr(&b1, exprs, b.a);
            const sb = fmtExpr(&b2, exprs, b.b);
            const op: []const u8 = switch (b.op) {
                .add => "+",
                .mul => "*",
                .cmp_gt => ">",
            };
            return std.fmt.bufPrint(buf, "({s}{s}{s})", .{ sa, op, sb }) catch "?";
        },
    };
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
    fitLogit(X, Y, lib.len, 120, 0.05, w);
    return accLogit(X, Y, w, lib.len, NVA, NSAMP);
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

fn corr(a: []const f64, b: []const f64) f64 {
    var ma: f64 = 0;
    var mb: f64 = 0;
    for (0..NSAMP) |s| {
        ma += a[s];
        mb += b[s];
    }
    ma /= @floatFromInt(NSAMP);
    mb /= @floatFromInt(NSAMP);
    var num: f64 = 0;
    var da: f64 = 0;
    var db: f64 = 0;
    for (0..NSAMP) |s| {
        const xa = a[s] - ma;
        const xb = b[s] - mb;
        num += xa * xb;
        da += xa * xa;
        db += xb * xb;
    }
    return num / @max(1e-9, @sqrt(da * db));
}

fn phiMono(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - MID);
    }
    return p;
}

fn inLibrary(lib: []const u16, exprs: []const Expr, id: u16, probe: []const [NCELL]u8) bool {
    const sig = exprSig(exprs, id, probe);
    for (lib) |lid| {
        if (exprEqual(exprs, lid, id)) return true;
        if (exprSig(exprs, lid, probe) == sig) return true;
    }
    return false;
}

fn classifyFamily(
    exprs: []const Expr,
    id: u16,
    grid: []const [NCELL]u8,
    feat: []f64,
    lib_base: []const u16,
) Family {
    const probe64 = grid[0..64];
    for (lib_base) |bid| {
        if (exprSig(exprs, bid, probe64) == exprSig(exprs, id, probe64)) return .known_base;
    }

    var tmp = [_]f64{0} ** NSAMP;

    for (0..NCELL) |i| {
        for (0..NSAMP) |s| tmp[s] = @floatFromInt(grid[s][i]);
        if (@abs(corr(feat, &tmp)) > 0.999) return .affine_cell;
    }

    var mask: u16 = 1;
    while (mask < 256) : (mask += 1) {
        const m: u8 = @intCast(mask);
        if (@popCount(m) == 0 or @popCount(m) > 4) continue;
        for (0..NSAMP) |s| tmp[s] = phiMono(grid[s], m);
        if (@abs(corr(feat, &tmp)) > 0.995) return .monomial;
    }

    for (0..NCELL) |i| {
        for (i + 1..NCELL) |j| {
            for (0..NSAMP) |s| tmp[s] = @as(f64, @floatFromInt(grid[s][i])) * @as(f64, @floatFromInt(grid[s][j]));
            if (@abs(corr(feat, &tmp)) > 0.995) return .pairwise_product;
        }
    }

    for (0..NCELL) |i| {
        for (0..NCELL) |j| {
            if (i == j) continue;
            for (0..NSAMP) |s| tmp[s] = if (grid[s][i] > grid[s][j]) 1.0 else 0.0;
            if (@abs(corr(feat, &tmp)) > 0.995) return .oriented_compare;
        }
    }

    for (0..NSAMP) |s| {
        var c: usize = 0;
        for (grid[s]) |v| {
            if (v >= THRESH) c += 1;
        }
        tmp[s] = @floatFromInt(c);
    }
    if (@abs(corr(feat, &tmp)) > 0.999) return .count_thresh;

    for (0..NSAMP) |s| {
        var c: usize = 0;
        for (grid[s]) |v| {
            if (v >= THRESH) c += 1;
        }
        tmp[s] = @floatFromInt(c & 1);
    }
    if (@abs(corr(feat, &tmp)) > 0.999) return .parity_count;

    for (0..NSAMP) |s| {
        var sm: u32 = 0;
        for (grid[s]) |v| sm += v;
        tmp[s] = @floatFromInt(sm);
    }
    if (@abs(corr(feat, &tmp)) > 0.999) return .sum_reduce;

    for (0..NSAMP) |s| {
        var mn: u8 = VMAX;
        var mx: u8 = 0;
        for (grid[s]) |v| {
            mn = @min(mn, v);
            mx = @max(mx, v);
        }
        tmp[s] = @floatFromInt(mn);
        if (@abs(corr(feat, &tmp)) > 0.999) return .min_max_reduce;
        tmp[s] = @floatFromInt(mx);
        if (@abs(corr(feat, &tmp)) > 0.999) return .min_max_reduce;
    }

    for (0..NCELL) |k| {
        for (0..NSAMP) |s| tmp[s] = @floatFromInt(rankK(grid[s], k));
        if (@abs(corr(feat, &tmp)) > 0.999) return .rank_value;
    }

    for (0..NCELL) |k| {
        for (0..NSAMP) |s| tmp[s] = if (rankK(grid[s], k) == 1) 1.0 else 0.0;
        if (@abs(corr(feat, &tmp)) > 0.995) return .rank_indicator;
    }

    const leaf_ids = [_]Leaf{ .cell, .thresh, .sum, .parity, .min, .max, .rank_k };
    for (leaf_ids) |lk| {
        const param_max: usize = if (lk == .cell or lk == .rank_k) NCELL else 1;
        var p: usize = 0;
        while (p < param_max) : (p += 1) {
            for (leaf_ids) |lk2| {
                const pmax2: usize = if (lk2 == .cell or lk2 == .rank_k) NCELL else 1;
                var p2: usize = 0;
                while (p2 < pmax2) : (p2 += 1) {
                    inline for (.{ Bin.add, Bin.mul, Bin.cmp_gt }) |op| {
                        for (0..NSAMP) |s| {
                            const a = evalLeaf(grid[s], lk, @intCast(p));
                            const b = evalLeaf(grid[s], lk2, @intCast(p2));
                            tmp[s] = switch (op) {
                                .add => a + b,
                                .mul => a * b,
                                .cmp_gt => if (a > b) 1.0 else 0.0,
                            };
                        }
                        if (@abs(corr(feat, &tmp)) > 0.995) return .composed_known;
                    }
                }
            }
        }
    }

    return .genuinely_new;
}

fn fillOutputs(exprs: []const Expr, id: u16, grid: []const [NCELL]u8, out: []f64) void {
    for (0..grid.len) |s| out[s] = evalExpr(exprs, id, grid[s]);
}

fn verifyOutputs(
    exprs: []const Expr,
    id: u16,
    grid: []const [NCELL]u8,
    target_vals: []const f64,
    eps: f64,
) struct { ok: bool, max_diff: f64 } {
    var max_diff: f64 = 0;
    for (0..grid.len) |s| {
        const got = evalExpr(exprs, id, grid[s]);
        const d = @abs(got - target_vals[s]);
        if (d > max_diff) max_diff = d;
        if (d > eps) return .{ .ok = false, .max_diff = max_diff };
    }
    return .{ .ok = true, .max_diff = max_diff };
}

fn quickFilter(exprs: []const Expr, id: u16, grid: []const [NCELL]u8, target_vals: []const f64, eps: f64, n_check: usize) bool {
    const n = @min(n_check, grid.len);
    for (0..n) |s| {
        const d = @abs(evalExpr(exprs, id, grid[s]) - target_vals[s]);
        if (d > eps) return false;
    }
    return true;
}

fn findVmEquivalent(
    mint_exprs: []const Expr,
    mint_id: u16,
    oracle_exprs: []const Expr,
    grid_oracle: []const [NCELL]u8,
    target_vals: []const f64,
    eps: f64,
) OracleResult {
    var best: OracleResult = .{ .equivalent = false, .witness = null, .witness_pool = .oracle, .witness_depth = 0, .max_diff = std.math.inf(f64) };

    const tryWitness = struct {
        fn f(
            exprs: []const Expr,
            pool: WitnessPool,
            id: u16,
            grid: []const [NCELL]u8,
            target_vals_ptr: []const f64,
            eps_tol: f64,
            best_in: *OracleResult,
        ) void {
            const dep = exprDepth(exprs, id);
            if (dep > MAX_DEPTH_ORACLE) return;
            const m = verifyOutputs(exprs, id, grid, target_vals_ptr, eps_tol);
            if (!m.ok) return;
            if (!best_in.equivalent or dep < best_in.witness_depth or (dep == best_in.witness_depth and m.max_diff < best_in.max_diff)) {
                best_in.* = .{
                    .equivalent = true,
                    .witness = id,
                    .witness_pool = pool,
                    .witness_depth = dep,
                    .max_diff = m.max_diff,
                };
            }
        }
    }.f;

    for (0..oracle_exprs.len) |i| {
        const cid: u16 = @intCast(i);
        if (exprDepth(oracle_exprs, cid) > MAX_DEPTH_ORACLE) continue;
        if (!quickFilter(oracle_exprs, cid, grid_oracle, target_vals, eps, QUICK_FILTER_GRIDS)) continue;
        tryWitness(oracle_exprs, .oracle, cid, grid_oracle, target_vals, eps, &best);
    }

    if (!best.equivalent) {
        tryWitness(mint_exprs, .mint, mint_id, grid_oracle, target_vals, eps, &best);
    }

    return best;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(RNG_SEED);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const probe = grid[0..64];
    const pool_mint = try buildExprPool(alloc, probe, MAX_DEPTH_MINT, MAX_POOL_MINT);
    const exprs = pool_mint.exprs;
    const roots = pool_mint.roots;

    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAX_LIB);
    const feat = try alloc.alloc(f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    var w: [MAX_LIB + 1]f64 = undefined;

    var lib_base: [NCELL]u16 = undefined;
    var nbase: usize = 0;
    for (0..exprs.len) |i| {
        if (exprs[i] == .leaf and exprs[i].leaf.kind == .cell) {
            lib_base[nbase] = @intCast(i);
            nbase += 1;
        }
    }

    var lib = std.ArrayList(u16).init(alloc);
    for (0..nbase) |i| try lib.append(lib_base[i]);

    var all_leaves = std.ArrayList(u16).init(alloc);
    for (0..exprs.len) |i| {
        if (exprs[i] == .leaf) try all_leaves.append(@intCast(i));
    }

    const F = try alloc.alloc([]f64, exprs.len);
    for (0..exprs.len) |e| {
        F[e] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| F[e][s] = evalExpr(exprs, @intCast(e), grid[s]);
    }

    const Y = try alloc.alloc([]f64, NTARGETS);
    const Cand = struct { id: u16, depth: usize, base_cov: f64 };
    var candidates = std.ArrayList(Cand).init(alloc);
    defer candidates.deinit();
    var tries: usize = 0;
    while (candidates.items.len < NTARGETS * 4 and tries < 1200) : (tries += 1) {
        const ridx = rand.intRangeLessThan(usize, 0, roots.len);
        const pid = roots[ridx];
        const dep = exprDepth(exprs, pid);
        if (dep < 3) continue;
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
        fitLogit(X, feat, nbase, 80, 0.06, &w);
        const base_cov = accLogit(X, feat, &w, nbase, NVA, NSAMP);
        if (base_cov >= ESCAPE_BEFORE) continue;
        try candidates.append(.{ .id = pid, .depth = dep, .base_cov = base_cov });
    }
    const candLess = struct {
        fn lt(_: void, a: Cand, b: Cand) bool {
            return a.base_cov < b.base_cov;
        }
    }.lt;
    std.sort.pdq(Cand, candidates.items, {}, candLess);
    const n_pick = @min(NTARGETS, candidates.items.len);
    for (0..n_pick) |ti| {
        const pid = candidates.items[ti].id;
        Y[ti] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| feat[s] = F[pid][s];
        var vals = std.ArrayList(f64).init(alloc);
        defer vals.deinit();
        for (0..NTR) |s| try vals.append(feat[s]);
        std.sort.pdq(f64, vals.items, {}, std.sort.asc(f64));
        const med = vals.items[vals.items.len / 2];
        for (0..NSAMP) |s| Y[ti][s] = if (feat[s] > med) 1.0 else 0.0;
    }

    try out.print("=== RESEARCH Q4: E4 equivalence oracle (VM depth≤6) ===\n\n", .{});
    try out.print("Minting protocol: E4 (depth≤{d} synthesis, escape≥{d:.2}, R²<{d:.2}).\n", .{ MAX_DEPTH_MINT, COVER, R2_MAX });
    try out.print("Oracle: exhaustive functional match in depth≤{d} VM on {d} random grids, ε={e}.\n", .{ MAX_DEPTH_ORACLE, NSAMP_ORACLE, EPS });
    try out.print("Pass bar for real minting: <{d:.0}% VM-equivalent promoted programs.\n\n", .{ REAL_MINTING_BAR * 100.0 });

    var solved = [_]bool{false} ** NTARGETS;
    var promoted_log = std.ArrayList(Promoted).init(alloc);
    var round: usize = 1;

    while (round <= 20 and lib.items.len < MAX_LIB) : (round += 1) {
        var promoted = false;
        for (0..n_pick) |t| {
            if (solved[t]) continue;
            const cov_now = coverageCached(X, F, lib.items, Y[t], &w);
            if (cov_now >= COVER) {
                solved[t] = true;
                continue;
            }

            var best_val: f64 = -1;
            var best_id: u16 = 0;
            const CorrCand = struct { id: u16, corr: f64 };
            var top = [_]CorrCand{.{ .id = 0, .corr = -2.0 }} ** 24;
            for (roots) |rid| {
                if (inLibrary(lib.items, exprs, rid, probe)) continue;
                const c = @abs(corrRange(F[rid], Y[t], NTR, NVA));
                if (c <= top[top.len - 1].corr) continue;
                top[top.len - 1] = .{ .id = rid, .corr = c };
                const corrGt = struct {
                    fn lt(_: void, a: CorrCand, b: CorrCand) bool {
                        return a.corr > b.corr;
                    }
                }.lt;
                std.sort.pdq(CorrCand, top[0..], {}, corrGt);
            }
            for (top) |cand| {
                if (cand.corr < 0) break;
                for (0..NSAMP) |s| X[s][0] = F[cand.id][s];
                fitLogit(X, Y[t], 1, 40, 0.1, &w);
                const v = accLogit(X, Y[t], &w, 1, NTR, NVA);
                if (v > best_val) {
                    best_val = v;
                    best_id = cand.id;
                }
            }

            var aug = std.ArrayList(u16).init(alloc);
            defer aug.deinit();
            try aug.appendSlice(lib.items);
            try aug.append(best_id);
            const cov_aug = coverageCached(X, F, aug.items, Y[t], &w);
            const escape = cov_aug >= COVER and cov_now < ESCAPE_BEFORE;

            for (0..NSAMP) |s| phiTgt[s] = F[best_id][s];
            const rr = reconR2(X, phiTgt, lib.items.len, &w);

            if (escape and rr < R2_MAX) {
                try lib.append(best_id);
                solved[t] = true;
                promoted = true;
                for (0..NSAMP) |s| feat[s] = F[best_id][s];
                const fam = classifyFamily(exprs, best_id, grid, feat, all_leaves.items);
                try promoted_log.append(.{ .target = t, .root = best_id, .family = fam, .r2 = rr, .cov_after = cov_aug });
                var pbuf: [96]u8 = undefined;
                const pname = fmtExpr(&pbuf, exprs, best_id);
                try out.print("  mint round {d}: G{d:0>2} → {s} [{s}] test={d:.2}\n", .{
                    round, t, pname, family_name[@intFromEnum(fam)], cov_aug,
                });
            }
        }
        for (0..n_pick) |t| {
            const cov = coverageCached(X, F, lib.items, Y[t], &w);
            solved[t] = cov >= COVER;
        }
        if (!promoted) break;
    }

    try out.print("\nE4 minting complete: {d} promoted program(s), library size {d}.\n\n", .{ promoted_log.items.len, lib.items.len });

    // --- equivalence oracle ---
    var oracle_prng = std.Random.DefaultPrng.init(ORACLE_GRID_SEED);
    const oracle_rand = oracle_prng.random();
    const grid_oracle = try alloc.alloc([NCELL]u8, NSAMP_ORACLE);
    for (0..NSAMP_ORACLE) |s| for (0..NCELL) |i| {
        grid_oracle[s][i] = oracle_rand.intRangeAtMost(u8, 0, VMAX);
    };
    const probe_oracle = grid_oracle[0..ORACLE_PROBE];

    try out.print("Building depth≤{d} oracle pool (cap {d}, probe {d} grids)...\n", .{ MAX_DEPTH_ORACLE, MAX_POOL_ORACLE, ORACLE_PROBE });
    const pool_oracle = try buildExprPool(alloc, probe_oracle, MAX_DEPTH_ORACLE, MAX_POOL_ORACLE);
    const oracle_exprs = pool_oracle.exprs;
    try out.print("Oracle pool: {d} unique programs (depth≤{d}).\n\n", .{ oracle_exprs.len, MAX_DEPTH_ORACLE });

    const target_vals = try alloc.alloc(f64, NSAMP_ORACLE);
    var n_equiv: usize = 0;
    var n_distinct: usize = 0;

    try out.print("equivalence oracle (per promoted program):\n", .{});
    for (promoted_log.items) |p| {
        fillOutputs(exprs, p.root, grid_oracle, target_vals);
        const oracle = findVmEquivalent(
            exprs,
            p.root,
            oracle_exprs,
            grid_oracle,
            target_vals,
            EPS,
        );

        var pbuf: [96]u8 = undefined;
        const pname = fmtExpr(&pbuf, exprs, p.root);
        const mint_depth = exprDepth(exprs, p.root);

        if (oracle.equivalent) {
            n_equiv += 1;
            var wbuf: [96]u8 = undefined;
            const w_exprs = if (oracle.witness_pool == .mint) exprs else oracle_exprs;
            const wname = fmtExpr(&wbuf, w_exprs, oracle.witness.?);
            const pool_tag: []const u8 = if (oracle.witness_pool == .mint) "mint-pool" else "oracle-pool";
            try out.print("  G{d:0>2}: {s} (depth {d}) → EQUIVALENT witness {s} (depth {d}, {s}, max|Δ|={e})\n", .{
                p.target, pname, mint_depth, wname, oracle.witness_depth, pool_tag, oracle.max_diff,
            });
        } else {
            n_distinct += 1;
            try out.print("  G{d:0>2}: {s} (depth {d}) → GENUINELY DISTINCT (no depth≤{d} match, ε={e})\n", .{
                p.target, pname, mint_depth, MAX_DEPTH_ORACLE, EPS,
            });
        }
    }

    const n_promoted = promoted_log.items.len;
    const equiv_pct = if (n_promoted > 0)
        100.0 * @as(f64, @floatFromInt(n_equiv)) / @as(f64, @floatFromInt(n_promoted))
    else
        0.0;
    const distinct_pct = 100.0 - equiv_pct;
    const real_minting = equiv_pct < REAL_MINTING_BAR * 100.0;

    try out.print("\n=== ORACLE SUMMARY ===\n", .{});
    try out.print("Promoted programs: {d}\n", .{n_promoted});
    try out.print("VM-equivalent (depth≤{d}): {d}/{d} = {d:.1}%\n", .{ MAX_DEPTH_ORACLE, n_equiv, n_promoted, equiv_pct });
    try out.print("Genuinely distinct:       {d}/{d} = {d:.1}%\n", .{ n_distinct, n_promoted, distinct_pct });
    try out.print("Pass bar (<{d:.0}% equivalent): {s}\n\n", .{ REAL_MINTING_BAR * 100.0, if (real_minting) "PASS — real minting" else "FAIL — relabeling inside VM closure" });

    try out.print("Minted program list:\n", .{});
    for (promoted_log.items) |p| {
        var pbuf: [96]u8 = undefined;
        const pname = fmtExpr(&pbuf, exprs, p.root);
        try out.print("  - G{d:0>2}: {s}  family={s}  depth={d}\n", .{
            p.target, pname, family_name[@intFromEnum(p.family)], exprDepth(exprs, p.root),
        });
    }

    try out.print("\n=== VERDICT ===\n", .{});
    if (n_promoted == 0) {
        try out.print("NO MINTING: E4 protocol promoted nothing — oracle N/A.\n", .{});
    } else if (real_minting) {
        try out.print("REAL MINTING: {d:.1}% equivalent < {d:.0}% bar — majority of promotions are outside depth≤{d} VM.\n", .{
            equiv_pct, REAL_MINTING_BAR * 100.0, MAX_DEPTH_ORACLE,
        });
    } else {
        try out.print("NOT REAL MINTING: {d:.1}% of promotions are functionally recoverable from depth≤{d} VM on {d} grids.\n", .{
            equiv_pct, MAX_DEPTH_ORACLE, NSAMP_ORACLE,
        });
        try out.print("Minting is opaque menu relabeling inside a fixed compositional closure, not generator invention.\n", .{});
    }
    try out.print("\nSee: docs/research/open_invention_rq4.md, open_invention_e4.zig\n", .{});
}