//! EXPERIMENT E21 — E4 escape VM post-RQ4.
//!
//! Question: Can minting produce programs NOT equivalent to depth≤8 VM?
//!
//! Protocol: E4 certified menu minting; expand search with one new generator per round
//! (mod synthesis → xor_popcount → pipeline). RQ4-style equivalence oracle (depth≤8 base VM,
//! 10k grids) after each promotion.
//!
//! Pass bar: ≥1/10 promotions fail depth≤8 VM equivalence (genuine escape).
//!
//! Reuses: open_invention_e4.zig (minting protocol), open_invention_rq4.zig (oracle).
//!
//! Run: zig build open-invention-e21 --release=fast

const std = @import("std");
const e2 = @import("open_invention_e2.zig");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const MAX_DEPTH_MINT: usize = 5;
const MAX_POOL_MINT: usize = 4096;
const MAX_DEPTH_ORACLE: usize = 8;
const MAX_POOL_ORACLE: usize = 8192;
const ORACLE_PROBE: usize = 256;
const QUICK_FILTER_GRIDS: usize = 24;
const NSAMP_ORACLE: usize = 10000;
const MAX_LIB: usize = 64;
const COVER: f64 = 0.90;
const ESCAPE_BEFORE: f64 = 0.70;
const R2_MAX: f64 = 0.40;
const EPS: f64 = 1e-6;
const RNG_SEED: u64 = 0xE4CE11ED0FF1CE42;
const ORACLE_GRID_SEED: u64 = 0xE21BA51E04EEDFA;
const PASS_PROMOTIONS: usize = 10;
const PASS_ESCAPE_MIN: usize = 1;

const Generator = enum {
    vm,
    mod_synth,
    xor_popcount,
    pipeline,
};

const generator_name = [_][]const u8{
    "vm",
    "mod_synth",
    "xor_popcount",
    "pipeline",
};

const Leaf = enum { cell, thresh, sum, parity, min, max, rank_k };
const Bin = enum { add, mul, cmp_gt };

const Expr = union(enum) {
    leaf: struct { kind: Leaf, param: u8 },
    bin: struct { op: Bin, a: u16, b: u16 },
};

const MintFeat = union(enum) {
    vm: u16,
    mod_prog: u16,
    xor_mask: u8,
    pipeline: struct { inner1: Inner1, inner2: Inner2, omega: f64 },
};

const OracleResult = struct {
    equivalent: bool,
    witness_depth: usize,
    max_diff: f64,
};

const Promoted = struct {
    target: usize,
    feat: MintFeat,
    generator: Generator,
    r2: f64,
    cov_after: f64,
    oracle_equiv: bool,
    witness_depth: usize,
};

const TargetKind = enum { vm_hard, mod_periodic, xor_gf2, pipe_composed };

const Target = struct {
    name: []const u8,
    kind: TargetKind,
    e2_spec: ?e2.PredSpec = null,
    mod_kind: ModKind = .count_mod,
    mod_m: usize = 3,
    mod_res: usize = 0,
    mod_thresh: u8 = THRESH,
    pipe_inner1: Inner1 = .inversion,
    pipe_inner2: Inner2 = .half_p,
};

const ModKind = enum {
    count_mod,
    count_mod_res,
    sum_mod,
    sign_mod,
    inv_mod,
};

// ── VM expression pool (E4 / RQ4) ───────────────────────────────────────────

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

fn exprSig(exprs: []const Expr, id: u16, probe: []const [NCELL]u8) u64 {
    var h: u64 = 0xCBF29CE484222325;
    for (probe) |g| {
        const bits: u64 = @bitCast(evalExpr(exprs, id, g));
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

fn buildExprPool(alloc: std.mem.Allocator, probe: []const [NCELL]u8, max_depth: usize, max_pool: usize) !struct { exprs: []Expr, roots: []u16 } {
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
    for ([_]Leaf{ .thresh, .sum, .parity, .min, .max }) |lk| _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = lk, .param = 0 } }, probe);
    for (0..NCELL) |k| _ = try addExpr(&exprs, &sigs, .{ .leaf = .{ .kind = .rank_k, .param = @intCast(k) } }, probe);

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
                if (@max(exprDepth(exprs.items, pid), exprDepth(exprs.items, @intCast(aid))) + 1 > max_depth) continue;
                inline for (.{ Bin.add, Bin.mul, Bin.cmp_gt }) |op| {
                    const id = try addExpr(&exprs, &sigs, .{ .bin = .{ .op = op, .a = pid, .b = @intCast(aid) } }, probe);
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
        if (exprDepth(exprs.items, id) >= 2 and exprDepth(exprs.items, id) <= max_depth) try roots.append(id);
    }
    return .{ .exprs = try exprs.toOwnedSlice(), .roots = try roots.toOwnedSlice() };
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
            const op: []const u8 = switch (b.op) { .add => "+", .mul => "*", .cmp_gt => ">" };
            break :blk std.fmt.bufPrint(buf, "({s}{s}{s})", .{ sa, op, sb }) catch "?";
        },
    };
}

// ── Mod synthesis bank (RQ3 / E14) ──────────────────────────────────────────

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
    names: []const []const u8,

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

fn countGE(g: [NCELL]u8, thresh: u8) f64 {
    var c: usize = 0;
    for (g) |v| {
        if (v >= thresh) c += 1;
    }
    return @floatFromInt(c);
}

fn gridSum(g: [NCELL]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}

fn signPattern(g: [NCELL]u8) u8 {
    var p: u8 = 0;
    for (0..NCELL) |i| {
        if (g[i] >= THRESH) p |= @as(u8, 1) << @intCast(i);
    }
    return p;
}

fn inversionCount(g: [NCELL]u8) usize {
    var inv: usize = 0;
    for (0..NCELL) |i| {
        for (i + 1..NCELL) |j| {
            if (g[i] > g[j]) inv += 1;
        }
    }
    return inv;
}

fn buildProgBank(alloc: std.mem.Allocator) !ProgBank {
    var nodes = std.ArrayList(ProgNode).init(alloc);
    defer nodes.deinit();
    var depths = std.ArrayList(u8).init(alloc);
    defer depths.deinit();
    var names = std.ArrayList([]const u8).init(alloc);
    defer names.deinit();

    const leaf_tags = [_]struct { leaf: SynthLeaf, tag: []const u8 }{
        .{ .leaf = .count3, .tag = "count₃" },
        .{ .leaf = .count2, .tag = "count₂" },
        .{ .leaf = .count4, .tag = "count₄" },
        .{ .leaf = .inv, .tag = "inv" },
        .{ .leaf = .sum, .tag = "sum" },
    };
    for (leaf_tags) |lt| {
        try nodes.append(.{ .leaf = lt.leaf });
        try depths.append(0);
        try names.append(lt.tag);
    }

    var depth_cur: u8 = 1;
    var frontier = std.ArrayList(u16).init(alloc);
    for (0..leaf_tags.len) |i| try frontier.append(@intCast(i));

    while (depth_cur <= 3) : (depth_cur += 1) {
        var next = std.ArrayList(u16).init(alloc);
        defer next.deinit();
        for (frontier.items) |pid| {
            if (nodes.items.len >= 120) break;
            const base = names.items[pid];
            const sin_nm = try std.fmt.allocPrint(alloc, "sin({s})", .{base});
            try nodes.append(.{ .sin = pid });
            try depths.append(depth_cur);
            try names.append(sin_nm);
            try next.append(@intCast(nodes.items.len - 1));
            for (2..9) |k| {
                if (nodes.items.len >= 120) break;
                const nm = try std.fmt.allocPrint(alloc, "mod({s},{d})", .{ base, k });
                try nodes.append(.{ .@"mod" = .{ .child = pid, .k = @intCast(k) } });
                try depths.append(depth_cur);
                try names.append(nm);
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
                for ([_]struct { node: ProgNode, tag: []const u8 }{
                    .{ .node = .{ .add = .{ .a = ai, .b = aj } }, .tag = "+" },
                    .{ .node = .{ .mul = .{ .a = ai, .b = aj } }, .tag = "*" },
                }) |op| {
                    if (nodes.items.len >= 120) break;
                    const nm = try std.fmt.allocPrint(alloc, "({s}{s}{s})", .{ names.items[i], op.tag, names.items[j] });
                    try nodes.append(op.node);
                    try depths.append(d);
                    try names.append(nm);
                }
            }
        }
        frontier.clearRetainingCapacity();
        for (next.items) |id| try frontier.append(id);
    }

    return .{
        .nodes = try nodes.toOwnedSlice(),
        .depths = try depths.toOwnedSlice(),
        .names = try names.toOwnedSlice(),
    };
}

// ── Pipeline generators (E5 subset) ─────────────────────────────────────────

const Inner1 = enum { count, sum_all, sum01, inversion, max_cell, min01, mean01 };
const N_INNER1 = 7;
const Inner2 = enum { linear, lift_q, half_p, scan_p, bind_xy, bind_abs, bind_max };
const N_INNER2 = 7;

fn inner1Scalar(kind: Inner1, g: [NCELL]u8) f64 {
    return switch (kind) {
        .count => countGE(g, THRESH),
        .sum_all => @floatFromInt(gridSum(g)),
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
        for (0..NSAMP) |s| X[s][j] = (X[s][j] - mu) / sd;
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

fn fitLogit1(raw: []const f64, Y: []const f64, w: *[2]f64) void {
    w.* = .{ 1.0, 0.0 };
    for (0..80) |_| for (0..NTR) |s| {
        const e = sigmoid(w[0] * raw[s] + w[1]) - Y[s];
        w[0] -= 0.05 * e * raw[s];
        w[1] -= 0.05 * e;
    };
}

fn accLogit1(raw: []const f64, Y: []const f64, w: [2]f64, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        if ((w[0] * raw[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
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

fn fillFeatCols(X: [][]f64, cols: []const []f64) void {
    for (0..cols.len) |j| {
        for (0..NSAMP) |s| X[s][j] = cols[j][s];
    }
}

fn coverageFromCols(X: [][]f64, cols: []const []f64, Y: []const f64, w: []f64) f64 {
    fillFeatCols(X, cols);
    standardize(X, cols.len);
    fitLogit(X, Y, cols.len, 120, 0.05, w);
    return accLogit(X, Y, w, cols.len, NVA, NSAMP);
}

fn evalMintScalar(
    feat: MintFeat,
    g: [NCELL]u8,
    exprs: []const Expr,
    bank: ProgBank,
    ctx: ScalarCtx,
) f64 {
    return switch (feat) {
        .vm => |id| evalExpr(exprs, id, g),
        .mod_prog => |pid| bank.eval(pid, ctx),
        .xor_mask => |mask| e2.xorPopcountReadout(g, mask),
        .pipeline => |p| blk: {
            const S = inner1Scalar(p.inner1, g);
            break :blk switch (p.inner2) {
                .linear => S,
                .half_p => @floatFromInt(@as(usize, @intFromFloat(@round(S))) & 1),
                .bind_xy => @as(f64, @floatFromInt(g[0])) * @as(f64, @floatFromInt(g[1])),
                .bind_abs => @abs(@as(f64, @floatFromInt(g[0])) - @as(f64, @floatFromInt(g[1]))),
                .bind_max => @floatFromInt(@max(g[0], g[1])),
                .lift_q => S * S,
                .scan_p => @cos(p.omega * S),
            };
        },
    };
}

fn fillMintCol(col: []f64, feat: MintFeat, grid: []const [NCELL]u8, exprs: []const Expr, bank: ProgBank, ctxs: []const ScalarCtx) void {
    for (0..grid.len) |s| col[s] = evalMintScalar(feat, grid[s], exprs, bank, ctxs[s]);
}

fn fmtMint(buf: []u8, feat: MintFeat, exprs: []const Expr, bank: ProgBank) []const u8 {
    return switch (feat) {
        .vm => |id| fmtExpr(buf, exprs, id),
        .mod_prog => |pid| if (pid < bank.names.len) bank.names[pid] else "mod?",
        .xor_mask => |mask| std.fmt.bufPrint(buf, "xor_popcount(0x{X:0>2})", .{mask}) catch "?",
        .pipeline => |p| std.fmt.bufPrint(buf, "pipe({d},{d})", .{ @intFromEnum(p.inner1), @intFromEnum(p.inner2) }) catch "pipe?",
    };
}

fn featInLibrary(lib: []const MintFeat, cand: MintFeat, exprs: []const Expr, probe: []const [NCELL]u8, bank: ProgBank) bool {
    for (lib) |f| {
        if (@intFromEnum(std.meta.activeTag(f)) != @intFromEnum(std.meta.activeTag(cand))) continue;
        switch (cand) {
            .vm => |id| if (f.vm == id) return true,
            .mod_prog => |pid| if (f.mod_prog == pid) return true,
            .xor_mask => |m| if (f.xor_mask == m) return true,
            .pipeline => |p| if (f.pipeline.inner1 == p.inner1 and f.pipeline.inner2 == p.inner2 and @abs(f.pipeline.omega - p.omega) < 1e-6) return true,
        }
    }
    _ = exprs;
    _ = probe;
    _ = bank;
    return false;
}

fn generatorsUnlocked(round: usize) struct { mod: bool, xor: bool, pipe: bool } {
    return .{
        .mod = round >= 1,
        .xor = round >= 2,
        .pipe = round >= 3,
    };
}

// ── Pipeline search ───────────────────────────────────────────────────────────

fn fitCosFeat(raw: []const f64, Y: []const f64, w: f64) [2]f64 {
    var a: f64 = 1.0;
    var b: f64 = 0.0;
    for (0..40) |_| for (0..NTR) |s| {
        const cw = @cos(w * raw[s]);
        const e = sigmoid(a * cw + b) - Y[s];
        a -= 0.08 * e * cw;
        b -= 0.08 * e;
    };
    return .{ a, b };
}

fn searchPipeline(grid: []const [NCELL]u8, Y: []const f64, S_all: *const [N_INNER1][]f64, X: [][]f64, w: []f64) struct { feat: MintFeat, val: f64 } {
    var best_val: f64 = -1;
    var best: MintFeat = .{ .pipeline = .{ .inner1 = .count, .inner2 = .linear, .omega = 0 } };
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        const S = S_all[i1i];
        for (0..N_INNER2) |i2i| {
            const in2: Inner2 = @enumFromInt(i2i);
            var omega: f64 = 0;
            var val: f64 = -1;
            if (in2 == .scan_p) {
                var best_w: f64 = std.math.pi;
                var best_v: f64 = -1;
                for (1..32) |fi| {
                    const om = @as(f64, @floatFromInt(fi)) * std.math.pi / 32.0;
                    const ab = fitCosFeat(S, Y, om);
                    var c: usize = 0;
                    for (NTR..NVA) |s| {
                        if ((ab[0] * @cos(om * S[s]) + ab[1] >= 0) == (Y[s] > 0.5)) c += 1;
                    }
                    const v = @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NVA - NTR));
                    if (v > best_v) {
                        best_v = v;
                        best_w = om;
                    }
                }
                omega = best_w;
                for (0..NSAMP) |s| {
                    X[s][0] = S[s];
                    X[s][1] = @cos(omega * S[s]);
                }
                standardize(X, 2);
                fitLogit(X, Y, 2, 80, 0.05, w);
                val = accLogit(X, Y, w, 2, NTR, NVA);
            } else {
                const dim: usize = if (in2 == .lift_q) 2 else 1;
                for (0..NSAMP) |s| {
                    X[s][0] = S[s];
                    if (in2 == .lift_q) X[s][1] = S[s] * S[s];
                    if (in2 == .half_p) X[s][0] = @floatFromInt(@as(usize, @intFromFloat(@round(S[s]))) & 1);
                    if (in2 == .bind_xy) X[s][0] = @as(f64, @floatFromInt(grid[s][0])) * @as(f64, @floatFromInt(grid[s][1]));
                    if (in2 == .bind_abs) X[s][0] = @abs(@as(f64, @floatFromInt(grid[s][0])) - @as(f64, @floatFromInt(grid[s][1])));
                    if (in2 == .bind_max) X[s][0] = @floatFromInt(@max(grid[s][0], grid[s][1]));
                }
                standardize(X, dim);
                fitLogit(X, Y, dim, 80, 0.05, w);
                val = accLogit(X, Y, w, dim, NTR, NVA);
            }
            if (val > best_val) {
                best_val = val;
                best = .{ .pipeline = .{ .inner1 = in1, .inner2 = in2, .omega = omega } };
            }
        }
    }
    return .{ .feat = best, .val = best_val };
}

fn searchXor(Y: []const f64, grid: []const [NCELL]u8, scratch: []f64) struct { feat: MintFeat, val: f64 } {
    var best_val: f64 = -1;
    var best_mask: u8 = 1;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        for (0..NSAMP) |s| scratch[s] = e2.xorPopcountReadout(grid[s], mask);
        var w: [2]f64 = .{ 1.0, 0.0 };
        fitLogit1(scratch, Y, &w);
        const v = accLogit1(scratch, Y, w, NTR, NVA);
        if (v > best_val) {
            best_val = v;
            best_mask = mask;
        }
    }
    return .{ .feat = .{ .xor_mask = best_mask }, .val = best_val };
}

fn searchMod(Y: []const f64, bank: ProgBank, ctxs: []const ScalarCtx, scratch: []f64) struct { feat: MintFeat, val: f64 } {
    var best_val: f64 = -1;
    var best_id: u16 = 1;
    for (1..bank.nodes.len) |pid| {
        if (bank.depth(@intCast(pid)) > 3) continue;
        for (0..NSAMP) |s| scratch[s] = bank.eval(@intCast(pid), ctxs[s]);
        var w: [2]f64 = .{ 1.0, 0.0 };
        fitLogit1(scratch, Y, &w);
        const v = accLogit1(scratch, Y, w, NTR, NVA);
        if (v > best_val) {
            best_val = v;
            best_id = @intCast(pid);
        }
    }
    return .{ .feat = .{ .mod_prog = best_id }, .val = best_val };
}

fn searchVm(
    Y: []const f64,
    roots: []const u16,
    F: []const []f64,
    lib: []const MintFeat,
    exprs: []const Expr,
    probe: []const [NCELL]u8,
    bank: ProgBank,
    X: [][]f64,
    w: []f64,
) struct { feat: MintFeat, val: f64 } {
    var best_val: f64 = -1;
    var best_id: u16 = 0;
    const CorrCand = struct { id: u16, corr: f64 };
    var top = [_]CorrCand{.{ .id = 0, .corr = -2.0 }} ** 24;
    for (roots) |rid| {
        if (featInLibrary(lib, .{ .vm = rid }, exprs, probe, bank)) continue;
        const c = @abs(corrRange(F[rid], Y, NTR, NVA));
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
        fitLogit(X, Y, 1, 40, 0.1, w);
        const v = accLogit(X, Y, w, 1, NTR, NVA);
        if (v > best_val) {
            best_val = v;
            best_id = cand.id;
        }
    }
    return .{ .feat = .{ .vm = best_id }, .val = best_val };
}

// ── RQ4-style oracle (depth≤8 base VM) ──────────────────────────────────────

fn verifyOutputsVm(exprs: []const Expr, id: u16, grid: []const [NCELL]u8, target_vals: []const f64, eps: f64) struct { ok: bool, max_diff: f64 } {
    var max_diff: f64 = 0;
    for (0..grid.len) |s| {
        const d = @abs(evalExpr(exprs, id, grid[s]) - target_vals[s]);
        if (d > max_diff) max_diff = d;
        if (d > eps) return .{ .ok = false, .max_diff = max_diff };
    }
    return .{ .ok = true, .max_diff = max_diff };
}

fn quickFilterVm(exprs: []const Expr, id: u16, grid: []const [NCELL]u8, target_vals: []const f64, eps: f64, n_check: usize) bool {
    const n = @min(n_check, grid.len);
    for (0..n) |s| if (@abs(evalExpr(exprs, id, grid[s]) - target_vals[s]) > eps) return false;
    return true;
}

fn oracleVmEquivalent(
    feat: MintFeat,
    exprs_mint: []const Expr,
    oracle_exprs: []const Expr,
    grid_oracle: []const [NCELL]u8,
    target_vals: []const f64,
    eps: f64,
) OracleResult {
    var best: OracleResult = .{
        .equivalent = false,
        .witness_depth = 0,
        .max_diff = std.math.inf(f64),
    };

    for (0..oracle_exprs.len) |i| {
        const cid: u16 = @intCast(i);
        const dep = exprDepth(oracle_exprs, cid);
        if (dep > MAX_DEPTH_ORACLE) continue;
        if (!quickFilterVm(oracle_exprs, cid, grid_oracle, target_vals, eps, QUICK_FILTER_GRIDS)) continue;
        const m = verifyOutputsVm(oracle_exprs, cid, grid_oracle, target_vals, eps);
        if (!m.ok) continue;
        if (!best.equivalent or dep < best.witness_depth or (dep == best.witness_depth and m.max_diff < best.max_diff)) {
            best = .{ .equivalent = true, .witness_depth = dep, .max_diff = m.max_diff };
        }
    }

    if (!best.equivalent and feat == .vm) {
        const m = verifyOutputsVm(exprs_mint, feat.vm, grid_oracle, target_vals, eps);
        if (m.ok) best = .{ .equivalent = true, .witness_depth = exprDepth(exprs_mint, feat.vm), .max_diff = m.max_diff };
    }

    return best;
}

// ── Target battery ────────────────────────────────────────────────────────────

const MOD_TARGETS = [_]Target{
    .{ .name = "M01 count%3", .kind = .mod_periodic, .mod_kind = .count_mod, .mod_m = 3 },
    .{ .name = "M02 count%5", .kind = .mod_periodic, .mod_kind = .count_mod, .mod_m = 5 },
    .{ .name = "M03 count%6", .kind = .mod_periodic, .mod_kind = .count_mod, .mod_m = 6 },
    .{ .name = "M04 sum%7", .kind = .mod_periodic, .mod_kind = .sum_mod, .mod_m = 7 },
    .{ .name = "M05 sum%5", .kind = .mod_periodic, .mod_kind = .sum_mod, .mod_m = 5 },
    .{ .name = "M06 sign%5", .kind = .mod_periodic, .mod_kind = .sign_mod, .mod_m = 5 },
    .{ .name = "M07 inv%3", .kind = .mod_periodic, .mod_kind = .inv_mod, .mod_m = 3 },
    .{ .name = "M08 inv%5", .kind = .mod_periodic, .mod_kind = .inv_mod, .mod_m = 5 },
    .{ .name = "M09 count%5==1", .kind = .mod_periodic, .mod_kind = .count_mod_res, .mod_m = 5, .mod_res = 1 },
    .{ .name = "M10 count%8", .kind = .mod_periodic, .mod_kind = .count_mod, .mod_m = 8 },
    .{ .name = "M11 sign%3", .kind = .mod_periodic, .mod_kind = .sign_mod, .mod_m = 3 },
    .{ .name = "M12 inv%6", .kind = .mod_periodic, .mod_kind = .inv_mod, .mod_m = 6 },
};

const XOR_SPECS = [_]e2.PredSpec{
    .{ .kind = .xor_cells, .mask = 0x0F },
    .{ .kind = .xor_cells, .mask = 0x37 },
    .{ .kind = .xor_cells, .mask = 0x55 },
    .{ .kind = .xor_cells, .mask = 0xAA },
    .{ .kind = .xor_cells, .mask = 0x3C },
    .{ .kind = .parity_xor, .mask = 0x0F },
    .{ .kind = .parity_xor, .mask = 0x33 },
    .{ .kind = .xor_cells, .mask = 0x66 },
    .{ .kind = .xor_cells, .mask = 0x99 },
    .{ .kind = .parity_xor, .mask = 0x55 },
};

const PIPE_TARGETS = [_]Target{
    .{ .name = "P01 inv parity", .kind = .pipe_composed, .pipe_inner1 = .inversion, .pipe_inner2 = .half_p },
    .{ .name = "P02 sum bind", .kind = .pipe_composed, .pipe_inner1 = .sum01, .pipe_inner2 = .bind_xy },
    .{ .name = "P03 max parity", .kind = .pipe_composed, .pipe_inner1 = .max_cell, .pipe_inner2 = .half_p },
    .{ .name = "P04 count scan", .kind = .pipe_composed, .pipe_inner1 = .count, .pipe_inner2 = .scan_p },
    .{ .name = "P05 inv bind", .kind = .pipe_composed, .pipe_inner1 = .inversion, .pipe_inner2 = .bind_abs },
};

fn modLabel(g: [NCELL]u8, t: Target) f64 {
    return switch (t.mod_kind) {
        .count_mod => if (@as(usize, @intFromFloat(countGE(g, THRESH))) % t.mod_m == 0) 1.0 else 0.0,
        .count_mod_res => if (@as(usize, @intFromFloat(countGE(g, THRESH))) % t.mod_m == t.mod_res) 1.0 else 0.0,
        .sum_mod => if (gridSum(g) % t.mod_m == 0) 1.0 else 0.0,
        .sign_mod => if (@as(usize, signPattern(g)) % t.mod_m == 0) 1.0 else 0.0,
        .inv_mod => if (inversionCount(g) % t.mod_m == 0) 1.0 else 0.0,
    };
}

fn pipeLabel(g: [NCELL]u8, t: Target) f64 {
    const S = inner1Scalar(t.pipe_inner1, g);
    const feat = switch (t.pipe_inner2) {
        .half_p => @as(usize, @intFromFloat(@round(S))) & 1,
        .bind_xy => blk: {
            const v = @as(usize, @intFromFloat(@as(f64, @floatFromInt(g[0])))) * @as(usize, @intFromFloat(@as(f64, @floatFromInt(g[1]))));
            break :blk v;
        },
        .scan_p => @as(usize, @intFromFloat(@round(S))) % 2,
        .bind_abs => @as(usize, @intFromFloat(@abs(@as(f64, @floatFromInt(g[0])) - @as(f64, @floatFromInt(g[1]))))),
        else => @as(usize, @intFromFloat(@round(S))),
    };
    return if (feat & 1 == 1) 1.0 else 0.0;
}

fn mintGeneratorTag(feat: MintFeat) Generator {
    return switch (feat) {
        .vm => .vm,
        .mod_prog => .mod_synth,
        .xor_mask => .xor_popcount,
        .pipeline => .pipeline,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(RNG_SEED);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| {
        for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    }

    const probe = grid[0..64];
    const pool_mint = try buildExprPool(alloc, probe, MAX_DEPTH_MINT, MAX_POOL_MINT);
    const exprs = pool_mint.exprs;
    const roots = pool_mint.roots;
    const bank = try buildProgBank(alloc);

    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAX_LIB);
    const scratch = try alloc.alloc(f64, NSAMP);
    const phiTgt = try alloc.alloc(f64, NSAMP);
    var w: [MAX_LIB + 1]f64 = undefined;

    var ctxs = try alloc.alloc(ScalarCtx, NSAMP);
    for (0..NSAMP) |s| ctxs[s] = ScalarCtx.fromGrid(grid[s]);

    const F = try alloc.alloc([]f64, exprs.len);
    for (0..exprs.len) |e| {
        F[e] = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| F[e][s] = evalExpr(exprs, @intCast(e), grid[s]);
    }

    var S_all: [N_INNER1][]f64 = undefined;
    for (0..N_INNER1) |i1i| {
        S_all[i1i] = try alloc.alloc(f64, NSAMP);
        const in1: Inner1 = @enumFromInt(i1i);
        for (0..NSAMP) |s| S_all[i1i][s] = inner1Scalar(in1, grid[s]);
    }

    // Base library: 8 singleton cells (E4)
    var lib_base: [NCELL]u16 = undefined;
    var nbase: usize = 0;
    for (0..exprs.len) |i| {
        if (exprs[i] == .leaf and exprs[i].leaf.kind == .cell) {
            lib_base[nbase] = @intCast(i);
            nbase += 1;
        }
    }
    var lib = std.ArrayList(MintFeat).init(alloc);
    for (0..nbase) |i| try lib.append(.{ .vm = lib_base[i] });

    // Build target list: VM-hard + mod + xor + pipeline
    var targets = std.ArrayList(Target).init(alloc);
    var Y = std.ArrayList([]f64).init(alloc);
    defer Y.deinit();

    // VM-hard targets (E4 style)
    const Cand = struct { id: u16, base_cov: f64 };
    var candidates = std.ArrayList(Cand).init(alloc);
    defer candidates.deinit();
    var tries: usize = 0;
    while (candidates.items.len < 60 and tries < 2000) : (tries += 1) {
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
        var vals = std.ArrayList(f64).init(alloc);
        defer vals.deinit();
        for (0..NTR) |s| try vals.append(F[pid][s]);
        std.sort.pdq(f64, vals.items, {}, std.sort.asc(f64));
        const med = vals.items[vals.items.len / 2];
        var ytmp = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| ytmp[s] = if (F[pid][s] > med) 1.0 else 0.0;
        var cols = try alloc.alloc([]f64, nbase);
        for (0..nbase) |j| cols[j] = F[lib_base[j]];
        const base_cov = coverageFromCols(X, cols, ytmp, &w);
        alloc.free(cols);
        if (base_cov >= ESCAPE_BEFORE) {
            alloc.free(ytmp);
            continue;
        }
        try candidates.append(.{ .id = pid, .base_cov = base_cov });
        alloc.free(ytmp);
    }
    const candLess = struct {
        fn lt(_: void, a: Cand, b: Cand) bool {
            return a.base_cov < b.base_cov;
        }
    }.lt;
    std.sort.pdq(Cand, candidates.items, {}, candLess);
    const n_vm = @min(15, candidates.items.len);
    for (0..n_vm) |ti| {
        const pid = candidates.items[ti].id;
        const nm = try std.fmt.allocPrint(alloc, "V{d:0>2}", .{ti});
        try targets.append(.{ .name = nm, .kind = .vm_hard });
        const yrow = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| yrow[s] = if (F[pid][s] > F[pid][NTR / 2]) 1.0 else 0.0;
        try Y.append(yrow);
    }

    for (MOD_TARGETS) |t| {
        try targets.append(t);
        const yrow = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| yrow[s] = modLabel(grid[s], t);
        try Y.append(yrow);
    }
    for (XOR_SPECS) |spec| {
        var buf: [48]u8 = undefined;
        const nm = try alloc.dupe(u8, spec.fmt(&buf));
        try targets.append(.{ .name = nm, .kind = .xor_gf2, .e2_spec = spec });
        const yrow = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| yrow[s] = e2.label(grid[s], spec);
        try Y.append(yrow);
    }
    for (PIPE_TARGETS) |t| {
        try targets.append(t);
        const yrow = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| yrow[s] = pipeLabel(grid[s], t);
        try Y.append(yrow);
    }

    const n_targets = targets.items.len;

    try out.print("=== EXPERIMENT E21: E4 escape VM post-RQ4 ===\n\n", .{});
    try out.print("Question: Can minting produce programs NOT equivalent to depth≤{d} VM?\n", .{MAX_DEPTH_ORACLE});
    try out.print("Minting: E4 protocol (escape≥{d:.2}, R²<{d:.2}); generators unlock per round: mod → xor_popcount → pipeline.\n", .{ COVER, R2_MAX });
    try out.print("Oracle: RQ4-style exhaustive match in depth≤{d} base VM on {d} grids, ε={e}.\n", .{ MAX_DEPTH_ORACLE, NSAMP_ORACLE, EPS });
    try out.print("Pass bar: ≥{d}/{d} promotions fail depth≤{d} equivalence.\n\n", .{ PASS_ESCAPE_MIN, PASS_PROMOTIONS, MAX_DEPTH_ORACLE });
    try out.print("Battery: {d} targets ({d} VM-hard + {d} mod + {d} xor + {d} pipeline).\n\n", .{
        n_targets, n_vm, MOD_TARGETS.len, XOR_SPECS.len, PIPE_TARGETS.len,
    });

    var solved = try alloc.alloc(bool, n_targets);
    @memset(solved, false);
    var promoted_log = std.ArrayList(Promoted).init(alloc);

    // Cached library feature columns (avoid per-target realloc)
    var lib_cols = std.ArrayList([]f64).init(alloc);
    for (lib.items) |feat| {
        const col = try alloc.alloc(f64, NSAMP);
        fillMintCol(col, feat, grid, exprs, bank, ctxs);
        try lib_cols.append(col);
    }

    var round: usize = 0;
    while (round < 20 and lib.items.len < MAX_LIB and promoted_log.items.len < PASS_PROMOTIONS) : (round += 1) {
        const unlock = generatorsUnlocked(round);
        if (round == 0) {
            try out.print("round 0 (base cells, n={d}): generators VM only\n", .{lib.items.len});
        } else {
            try out.print("round {d}: unlocked ", .{round});
            if (unlock.mod) try out.print("mod ", .{});
            if (unlock.xor) try out.print("xor_popcount ", .{});
            if (unlock.pipe) try out.print("pipeline ", .{});
            try out.print("(lib={d})\n", .{lib.items.len});
        }

        var promoted_round = false;
        for (0..n_targets) |t| {
            if (solved[t]) continue;
            const cov_now = coverageFromCols(X, lib_cols.items, Y.items[t], &w);
            if (cov_now >= COVER) {
                solved[t] = true;
                continue;
            }

            var best_feat: MintFeat = .{ .vm = 0 };
            var best_val: f64 = -1;
            var best_gen: Generator = .vm;

            const tgt = targets.items[t];
            const vm_best = searchVm(Y.items[t], roots, F, lib.items, exprs, probe, bank, X, &w);
            if (vm_best.val > best_val) {
                best_val = vm_best.val;
                best_feat = vm_best.feat;
                best_gen = .vm;
            }
            if (unlock.mod and tgt.kind == .mod_periodic) {
                const mod_best = searchMod(Y.items[t], bank, ctxs, scratch);
                if (mod_best.val > best_val) {
                    best_val = mod_best.val;
                    best_feat = mod_best.feat;
                    best_gen = .mod_synth;
                }
            }
            if (unlock.xor and tgt.kind == .xor_gf2) {
                const xor_best = searchXor(Y.items[t], grid, scratch);
                if (xor_best.val > best_val) {
                    best_val = xor_best.val;
                    best_feat = xor_best.feat;
                    best_gen = .xor_popcount;
                }
            }
            if (unlock.pipe and tgt.kind == .pipe_composed) {
                const pipe_best = searchPipeline(grid, Y.items[t], &S_all, X, &w);
                if (pipe_best.val > best_val) {
                    best_val = pipe_best.val;
                    best_feat = pipe_best.feat;
                    best_gen = .pipeline;
                }
            }

            if (featInLibrary(lib.items, best_feat, exprs, probe, bank)) continue;

            fillMintCol(phiTgt, best_feat, grid, exprs, bank, ctxs);
            var aug_cols = try alloc.alloc([]f64, lib_cols.items.len + 1);
            defer alloc.free(aug_cols);
            for (0..lib_cols.items.len) |j| aug_cols[j] = lib_cols.items[j];
            aug_cols[lib_cols.items.len] = phiTgt;
            const cov_aug = coverageFromCols(X, aug_cols, Y.items[t], &w);
            const escape = cov_aug >= COVER and cov_now < ESCAPE_BEFORE;
            const rr = reconR2(X, phiTgt, lib_cols.items.len, &w);

            if (escape and rr < R2_MAX) {
                try lib.append(best_feat);
                const col = try alloc.alloc(f64, NSAMP);
                fillMintCol(col, best_feat, grid, exprs, bank, ctxs);
                try lib_cols.append(col);
                solved[t] = true;
                promoted_round = true;

                var pbuf: [96]u8 = undefined;
                const pname = fmtMint(&pbuf, best_feat, exprs, bank);
                try out.print("  promote G{d:0>2} ({s}) gen={s} escape {d:.2}→{d:.2} R²={d:.2} lib={d}\n", .{
                    t, pname, generator_name[@intFromEnum(best_gen)], cov_now, cov_aug, rr, lib.items.len,
                });

                try promoted_log.append(.{
                    .target = t,
                    .feat = best_feat,
                    .generator = mintGeneratorTag(best_feat),
                    .r2 = rr,
                    .cov_after = cov_aug,
                    .oracle_equiv = false,
                    .witness_depth = 0,
                });
                if (promoted_log.items.len >= PASS_PROMOTIONS) break;
            }
        }

        for (0..n_targets) |t| {
            solved[t] = coverageFromCols(X, lib_cols.items, Y.items[t], &w) >= COVER;
        }
        if (!promoted_round and round >= 3) break;
        if (promoted_log.items.len >= PASS_PROMOTIONS) break;
    }

    // Oracle pass (RQ4-style, depth≤8)
    var oracle_prng = std.Random.DefaultPrng.init(ORACLE_GRID_SEED);
    const oracle_rand = oracle_prng.random();
    const grid_oracle = try alloc.alloc([NCELL]u8, NSAMP_ORACLE);
    for (0..NSAMP_ORACLE) |s| {
        for (0..NCELL) |i| grid_oracle[s][i] = oracle_rand.intRangeAtMost(u8, 0, VMAX);
    }
    const probe_oracle = grid_oracle[0..ORACLE_PROBE];

    try out.print("\nBuilding depth≤{d} oracle pool (cap {d})...\n", .{ MAX_DEPTH_ORACLE, MAX_POOL_ORACLE });
    const pool_oracle = try buildExprPool(alloc, probe_oracle, MAX_DEPTH_ORACLE, MAX_POOL_ORACLE);
    const oracle_exprs = pool_oracle.exprs;
    try out.print("Oracle pool: {d} unique programs.\n\n", .{oracle_exprs.len});

    const oracle_ctxs = try alloc.alloc(ScalarCtx, NSAMP_ORACLE);
    for (0..NSAMP_ORACLE) |s| oracle_ctxs[s] = ScalarCtx.fromGrid(grid_oracle[s]);

    const target_vals = try alloc.alloc(f64, NSAMP_ORACLE);
    var n_equiv: usize = 0;
    var n_distinct: usize = 0;

    try out.print("equivalence oracle (per promotion, depth≤{d} base VM):\n", .{MAX_DEPTH_ORACLE});
    for (promoted_log.items, 0..) |*p, pi| {
        for (0..NSAMP_ORACLE) |s| {
            target_vals[s] = evalMintScalar(p.feat, grid_oracle[s], exprs, bank, oracle_ctxs[s]);
        }
        const oracle = oracleVmEquivalent(p.feat, exprs, oracle_exprs, grid_oracle, target_vals, EPS);
        p.oracle_equiv = oracle.equivalent;
        p.witness_depth = oracle.witness_depth;

        var pbuf: [96]u8 = undefined;
        const pname = fmtMint(&pbuf, p.feat, exprs, bank);

        if (oracle.equivalent) {
            n_equiv += 1;
            try out.print("  #{d:0>2} G{d:0>2}: {s} [{s}] → EQUIVALENT (witness depth {d}, max|Δ|={e})\n", .{
                pi + 1, p.target, pname, generator_name[@intFromEnum(p.generator)], oracle.witness_depth, oracle.max_diff,
            });
        } else {
            n_distinct += 1;
            try out.print("  #{d:0>2} G{d:0>2}: {s} [{s}] → ESCAPES depth≤{d} VM\n", .{
                pi + 1, p.target, pname, generator_name[@intFromEnum(p.generator)], MAX_DEPTH_ORACLE,
            });
        }
    }

    const n_promoted = promoted_log.items.len;
    var n_solved: usize = 0;
    for (solved) |s| {
        if (s) n_solved += 1;
    }

    const n_eval = @min(n_promoted, PASS_PROMOTIONS);
    const n_distinct_eval = if (n_eval > 0) blk: {
        var d: usize = 0;
        for (promoted_log.items[0..n_eval]) |p| {
            if (!p.oracle_equiv) d += 1;
        }
        break :blk d;
    } else 0;

    const pass = n_promoted >= PASS_PROMOTIONS and n_distinct_eval >= PASS_ESCAPE_MIN;

    try out.print("\n=== ORACLE SUMMARY ===\n", .{});
    try out.print("Promotions: {d} (target {d})\n", .{ n_promoted, PASS_PROMOTIONS });
    try out.print("Solved targets: {d}/{d}\n", .{ n_solved, n_targets });
    try out.print("VM-equivalent (depth≤{d}): {d}/{d}\n", .{ MAX_DEPTH_ORACLE, n_equiv, n_promoted });
    try out.print("Escape depth≤{d}:           {d}/{d}\n", .{ MAX_DEPTH_ORACLE, n_distinct, n_promoted });
    if (n_eval > 0) {
        try out.print("First {d} promotions: {d} escape depth≤{d}\n", .{ n_eval, n_distinct_eval, MAX_DEPTH_ORACLE });
    }
    try out.print("Pass bar (≥{d}/{d} escape): {s}\n\n", .{ PASS_ESCAPE_MIN, PASS_PROMOTIONS, if (pass) "PASS" else "FAIL" });

    // Generator breakdown
    var gen_count = [_]usize{0} ** generator_name.len;
    var gen_escape = [_]usize{0} ** generator_name.len;
    for (promoted_log.items) |p| {
        const gi = @intFromEnum(p.generator);
        gen_count[gi] += 1;
        if (!p.oracle_equiv) gen_escape[gi] += 1;
    }
    try out.print("promotions by generator:\n", .{});
    for (generator_name, 0..) |gn, gi| {
        if (gen_count[gi] > 0) try out.print("  {s}: {d} promoted, {d} escape depth≤{d}\n", .{ gn, gen_count[gi], gen_escape[gi], MAX_DEPTH_ORACLE });
    }

    try out.print("\n=== VERDICT ===\n", .{});
    if (n_promoted < PASS_PROMOTIONS) {
        try out.print("INSUFFICIENT PROMOTIONS: {d}/{d} — cannot evaluate pass bar.\n", .{ n_promoted, PASS_PROMOTIONS });
    } else if (pass) {
        try out.print("PASS — {d}/{d} promotions escape depth≤{d} VM after generator expansion (post-RQ4).\n", .{
            n_distinct_eval, PASS_PROMOTIONS, MAX_DEPTH_ORACLE,
        });
        try out.print("Minting with mod/xor_popcount/pipeline produces functions outside base VM closure.\n", .{});
    } else {
        try out.print("FAIL — only {d}/{d} promotions escape depth≤{d} VM (need ≥{d}).\n", .{
            n_distinct_eval, PASS_PROMOTIONS, MAX_DEPTH_ORACLE, PASS_ESCAPE_MIN,
        });
        try out.print("Expanded generators did not yield enough VM-inequivalent minted programs.\n", .{});
    }
    try out.print("\nSee: docs/research/open_invention_e21.md, open_invention_e4.zig, open_invention_rq4.zig\n", .{});
}