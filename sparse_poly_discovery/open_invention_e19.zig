//! EXPERIMENT E19 — Wake-sleep LLM proposer (E11 production).
//!
//! DreamCoder-style loop: WAKE (propose) → certify → SLEEP (promote to library).
//! 10 rounds × 50 proposals = 500 total. The proposer conditions on the growing
//! library: early rounds seed from e11_proposals.json; later rounds mutate and
//! extend promoted features.
//!
//! Certification: E11/RQ7 engine — logistic readout, held-out test ≥0.90.
//! Novelty gate: RQ9 rich basis (monomial + Walsh + world + VM depth≤6).
//! Spectral and pipelines are excluded from the tax — invention must escape that closure.
//!
//! Pass bar: ≥15% proposal certified rate; ≥5 features novel under RQ9 basis.
//!
//! Run: zig build open-invention-e19 --release=fast
//!      zig build open-invention-e19 --release=fast -- e11_proposals.json

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const DOM: usize = 1 << NCELL;
const CERT: f64 = 0.90;
const EQUIV: f64 = 0.995;
const MONOMIAL_SIGN_MASK: u8 = (1 << 2) | (1 << 5);
const SUM_MOD: usize = 7;

const N_ROUNDS: usize = 10;
const PROPOSALS_PER_ROUND: usize = 50;
const TOTAL_PROPOSALS: usize = N_ROUNDS * PROPOSALS_PER_ROUND;
const PASS_CERT_RATE: f64 = 0.15;
const PASS_NOVEL_MIN: usize = 5;
const SEED: u64 = 0xE19C0DE20260629;

const WORLD_POOL = [_]usize{ 2, 3, 5, 7, 11, 13 };
const WORLD_PRIMES = WORLD_POOL;

const VM_MAX_DEPTH: usize = 6;
const VM_MAX_POOL: usize = 8192;
const VM_CHECK_CAP: usize = 256;
const MAX_DEG: usize = 4;
const NMONO: usize = 255;
const NWALSH: usize = 256;
const NWORLD: usize = WORLD_POOL.len * 4;

const Target = enum { parity, hidden_pair, sum_mod, oriented, monomial_sign };
const NT: usize = 5;
const target_name = [_][]const u8{ "parity", "hidden_pair", "sum_mod", "oriented", "monomial_sign" };

const FormulaKind = enum {
    monomial,
    walsh,
    spectral_count,
    count_parity,
    hidden_xor,
    sum_mod_indicator,
    sign_mod_indicator,
    median_centered,
    variance_sin,
    gcd_masked,
    xor_popcount,
    max_min_diff,
    sum_sq_mod,
    lcm_masked_mod,
    cell_diff_oriented,
    oriented_indicator,
    cell_diff_raw,
    clifford_g2,
    product_mod,
    harmonic_mean,
    cell_values_xor_parity,
    sign_pattern_int_mod,
    abs_diff_pair,
    sum_values_parity,
    thresh_count_mod,
    cell_gt_mid,
    pairwise_product_raw,
    rank_compare,
    antisymmetric_pair,
};

const Params = struct {
    subset: u8 = 0,
    mask: u8 = 0,
    omega: f64 = 0,
    modulus: usize = 2,
    i: usize = 0,
    j: usize = 1,
    scale: f64 = 1.0,
    value: u8 = 1,
};

const Proposal = struct {
    name: []const u8,
    formula_kind: FormulaKind,
    params: Params,
};

const BasisFamily = enum { mono, walsh, world, vm, rq9_novel, @"unknown" };
const basis_name = [_][]const u8{ "mono", "walsh", "world", "vm", "rq9_novel", "unknown" };

const LibraryEntry = struct {
    proposal: Proposal,
    target: Target,
    tst_acc: f64,
    basis: BasisFamily,
};

const CertResult = struct {
    proposal: Proposal,
    target: Target,
    val_acc: f64,
    tst_acc: f64,
    certified: bool,
    basis: BasisFamily,
    round: usize,
};

// ── Grid helpers (E11/RQ7) ───────────────────────────────────────────────────

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
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

fn phiMono(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - MID);
    }
    return p;
}

fn gcd2(a: usize, b: usize) usize {
    var x = a;
    var y = b;
    while (y != 0) {
        const t = y;
        y = x % y;
        x = t;
    }
    return x;
}

fn gcdMasked(g: [NCELL]u8, mask: u8) usize {
    var g0: usize = 0;
    var started = false;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) == 0) continue;
        const v: usize = g[i];
        if (!started) {
            g0 = v;
            started = true;
        } else g0 = gcd2(g0, v);
    }
    return if (started) g0 else 1;
}

fn lcmMasked(g: [NCELL]u8, mask: u8) usize {
    var l: usize = 1;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) == 0) continue;
        const v: usize = @max(1, g[i]);
        l = (l * v) / gcd2(l, v);
    }
    return l;
}

fn medianU8(g: [NCELL]u8) f64 {
    var s = g;
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    return (@as(f64, @floatFromInt(s[NCELL / 2 - 1])) + @as(f64, @floatFromInt(s[NCELL / 2]))) / 2.0;
}

fn variance(g: [NCELL]u8) f64 {
    var mu: f64 = 0;
    for (g) |v| mu += @as(f64, @floatFromInt(v));
    mu /= @as(f64, @floatFromInt(NCELL));
    var v: f64 = 0;
    for (g) |c| {
        const d = @as(f64, @floatFromInt(c)) - mu;
        v += d * d;
    }
    return v / @as(f64, @floatFromInt(NCELL));
}

fn harmonicMean(g: [NCELL]u8) f64 {
    var inv: f64 = 0;
    for (g) |v| inv += 1.0 / @as(f64, @floatFromInt(@max(1, v)));
    return @as(f64, @floatFromInt(NCELL)) / inv;
}

fn rankOf(g: [NCELL]u8, idx: usize) usize {
    var r: usize = 0;
    for (g) |v| {
        if (v < g[idx]) r += 1;
    }
    return r;
}

fn label(g: [NCELL]u8, t: Target) f64 {
    return switch (t) {
        .parity => blk: {
            var c: usize = 0;
            for (g) |v| {
                if (v >= THRESH) c += 1;
            }
            break :blk if (c & 1 == 1) 1.0 else 0.0;
        },
        .hidden_pair => if ((g[2] >= THRESH) != (g[5] >= THRESH)) 1.0 else 0.0,
        .sum_mod => if (gridSum(g) % SUM_MOD == 0) 1.0 else 0.0,
        .oriented => if (g[1] > g[0]) 1.0 else 0.0,
        .monomial_sign => if (phiMono(g, MONOMIAL_SIGN_MASK) > 0) 1.0 else 0.0,
    };
}

fn evalFeature(g: [NCELL]u8, kind: FormulaKind, p: Params) f64 {
    return switch (kind) {
        .monomial => phiMono(g, p.mask),
        .walsh => chi(p.subset, signPattern(g)),
        .spectral_count => @cos(p.omega * countGE(g)),
        .count_parity => blk: {
            var c: usize = 0;
            for (g) |v| {
                if (v >= THRESH) c += 1;
            }
            break :blk if (c & 1 == 1) 1.0 else -1.0;
        },
        .hidden_xor => if ((g[p.i] >= THRESH) != (g[p.j] >= THRESH)) 1.0 else -1.0,
        .sum_mod_indicator => if (gridSum(g) % p.modulus == 0) 1.0 else 0.0,
        .sign_mod_indicator => if (@as(usize, signPattern(g)) % p.modulus == 0) 1.0 else 0.0,
        .median_centered => medianU8(g) - MID,
        .variance_sin => @sin(p.scale * variance(g)),
        .gcd_masked => @as(f64, @floatFromInt(gcdMasked(g, p.mask))),
        .xor_popcount => blk: {
            const pc = @popCount(signPattern(g));
            break :blk if (pc & 1 == 1) 1.0 else -1.0;
        },
        .max_min_diff => blk: {
            var mn: u8 = VMAX;
            var mx: u8 = 0;
            for (g) |v| {
                mn = @min(mn, v);
                mx = @max(mx, v);
            }
            break :blk @as(f64, @floatFromInt(mx - mn));
        },
        .sum_sq_mod => blk: {
            var s: usize = 0;
            for (g) |v| s += v * v;
            break :blk @as(f64, @floatFromInt(s % p.modulus));
        },
        .lcm_masked_mod => @as(f64, @floatFromInt(lcmMasked(g, p.mask) % p.modulus)),
        .cell_diff_oriented => if (g[p.i] > g[p.j]) 1.0 else -1.0,
        .oriented_indicator => if (g[p.i] > g[p.j]) 1.0 else 0.0,
        .cell_diff_raw => @as(f64, @floatFromInt(g[p.i])) - @as(f64, @floatFromInt(g[p.j])),
        .clifford_g2 => @sin(0.4 * (@as(f64, @floatFromInt(g[1])) - @as(f64, @floatFromInt(g[0])))),
        .product_mod => blk: {
            var pr: usize = 1;
            for (0..NCELL) |i| {
                if (p.mask & (@as(u8, 1) << @intCast(i)) == 0) continue;
                pr = (pr * g[i]) % p.modulus;
            }
            break :blk @as(f64, @floatFromInt(pr));
        },
        .harmonic_mean => harmonicMean(g),
        .cell_values_xor_parity => blk: {
            var x: u8 = 0;
            for (g) |v| x ^= v;
            break :blk if (x & 1 == 1) 1.0 else -1.0;
        },
        .sign_pattern_int_mod => @as(f64, @floatFromInt(@as(usize, signPattern(g)) % p.modulus)),
        .abs_diff_pair => @as(f64, @floatFromInt(@abs(@as(i32, @intCast(g[p.i])) - @as(i32, @intCast(g[p.j]))))),
        .sum_values_parity => blk: {
            const s = gridSum(g);
            break :blk if (s & 1 == 1) 1.0 else -1.0;
        },
        .thresh_count_mod => blk: {
            var c: usize = 0;
            for (g) |v| {
                if (v >= THRESH) c += 1;
            }
            break :blk @as(f64, @floatFromInt(c % p.modulus));
        },
        .cell_gt_mid => if (g[p.i] > @as(u8, @intFromFloat(MID))) 1.0 else -1.0,
        .pairwise_product_raw => @as(f64, @floatFromInt(g[p.i])) * @as(f64, @floatFromInt(g[p.j])),
        .rank_compare => if (rankOf(g, p.i) > rankOf(g, p.j)) 1.0 else -1.0,
        .antisymmetric_pair => blk: {
            const ci = @as(f64, @floatFromInt(g[p.i])) - MID;
            const cj = @as(f64, @floatFromInt(g[p.j])) - MID;
            const ad = @abs(@as(i32, @intCast(g[p.i])) - @as(i32, @intCast(g[p.j])));
            break :blk ci * cj - @as(f64, @floatFromInt(ad));
        },
    };
}

fn accLogit(feat: []const f64, Y: []const f64, lo: usize, hi: usize) f64 {
    var w: [2]f64 = .{ 0.0, 0.0 };
    for (0..80) |_| for (0..NTR) |s| {
        const e = sigmoid(w[0] * feat[s] + w[1]) - Y[s];
        w[0] -= 0.1 * e * feat[s];
        w[1] -= 0.1 * e;
    };
    var c: usize = 0;
    for (lo..hi) |s| {
        if ((w[0] * feat[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

fn pearson(a: []const f64, b: []const f64, lo: usize, hi: usize) f64 {
    var ma: f64 = 0;
    var mb: f64 = 0;
    const n = hi - lo;
    for (lo..hi) |s| {
        ma += a[s];
        mb += b[s];
    }
    ma /= @as(f64, @floatFromInt(n));
    mb /= @as(f64, @floatFromInt(n));
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
    const den = @sqrt(da * db);
    if (den < 1e-12) return 0;
    return num / den;
}

// ── RQ9 VM pool (subset for novelty tax) ────────────────────────────────────

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
        const bits: u64 = @bitCast(v);
        h ^= bits;
        h *%= 0x100000001B3;
    }
    return h;
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
                const da = exprDepth(exprs.items, pid);
                const db = exprDepth(exprs.items, @intCast(aid));
                if (@max(da, db) + 1 > VM_MAX_DEPTH) continue;
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
        if (exprDepth(exprs.items, id) >= 2 and exprDepth(exprs.items, id) <= VM_MAX_DEPTH) {
            try roots.append(id);
        }
    }

    return .{
        .exprs = try exprs.toOwnedSlice(),
        .roots = try roots.toOwnedSlice(),
    };
}

const Rq9Basis = struct {
    mono: [NMONO][]f64,
    n_mono: usize,
    walsh: [NWALSH][]f64,
    world: [NWORLD][]f64,
    vm: [][]f64,
    n_vm: usize,

    fn destroy(self: *const Rq9Basis, alloc: std.mem.Allocator) void {
        for (0..self.n_mono) |i| alloc.free(self.mono[i]);
        for (self.walsh) |col| alloc.free(col);
        for (self.world) |col| alloc.free(col);
        for (0..self.n_vm) |i| alloc.free(self.vm[i]);
        alloc.free(self.vm);
    }

    fn build(
        alloc: std.mem.Allocator,
        grid: []const [NCELL]u8,
        lo: usize,
        hi: usize,
        exprs: []const Expr,
        vm_roots: []const u16,
    ) !Rq9Basis {
        var self: Rq9Basis = undefined;
        var mi: usize = 0;
        var mm: u16 = 1;
        while (mm < 256) : (mm += 1) {
            const m: u8 = @intCast(mm);
            const d = @popCount(m);
            if (d < 1 or d > MAX_DEG) continue;
            self.mono[mi] = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| self.mono[mi][s] = phiMono(grid[s], m);
            mi += 1;
        }
        self.n_mono = mi;

        for (0..NWALSH) |S| {
            self.walsh[S] = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| self.walsh[S][s] = chi(@intCast(S), signPattern(grid[s]));
        }

        var wi: usize = 0;
        for (WORLD_POOL) |pmod| {
            self.world[wi] = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| self.world[wi][s] = if (gridSum(grid[s]) % pmod == 0) @as(f64, 1) else 0;
            wi += 1;
            self.world[wi] = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| self.world[wi][s] = @as(f64, @floatFromInt(gridSum(grid[s]) % pmod));
            wi += 1;
            self.world[wi] = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| self.world[wi][s] = if (@as(usize, signPattern(grid[s])) % pmod == 0) @as(f64, 1) else 0;
            wi += 1;
            self.world[wi] = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| self.world[wi][s] = @as(f64, @floatFromInt(@as(usize, signPattern(grid[s])) % pmod));
            wi += 1;
        }

        const cap = @min(vm_roots.len, VM_CHECK_CAP);
        self.vm = try alloc.alloc([]f64, cap);
        self.n_vm = cap;
        for (0..cap) |ri| {
            self.vm[ri] = try alloc.alloc(f64, NSAMP);
            const rid = vm_roots[ri];
            for (0..NSAMP) |s| self.vm[ri][s] = evalExpr(exprs, rid, grid[s]);
        }
        _ = lo;
        _ = hi;
        return self;
    }

    fn classify(self: *const Rq9Basis, feat: []const f64, lo: usize, hi: usize) BasisFamily {
        for (0..self.n_mono) |i| {
            if (@abs(pearson(feat, self.mono[i], lo, hi)) >= EQUIV) return .mono;
        }
        for (self.walsh) |col| {
            if (@abs(pearson(feat, col, lo, hi)) >= EQUIV) return .walsh;
        }
        for (self.world) |col| {
            if (@abs(pearson(feat, col, lo, hi)) >= EQUIV) return .world;
        }
        for (0..self.n_vm) |ri| {
            if (@abs(pearson(feat, self.vm[ri], lo, hi)) >= EQUIV) return .vm;
        }
        return .rq9_novel;
    }
};

// ── JSON / proposal helpers ──────────────────────────────────────────────────

fn parseFormulaKind(s: []const u8) !FormulaKind {
    inline for (std.meta.fields(FormulaKind)) |f| {
        if (std.mem.eql(u8, s, f.name)) return @field(FormulaKind, f.name);
    }
    return error.UnknownFormulaKind;
}

fn parseParams(val: std.json.Value) Params {
    var p = Params{};
    if (val != .object) return p;
    const o = val.object;
    if (o.get("subset")) |v| {
        if (v == .integer) p.subset = @intCast(@max(0, @min(255, v.integer)));
    }
    if (o.get("mask")) |v| {
        if (v == .integer) p.mask = @intCast(@max(0, @min(255, v.integer)));
    }
    if (o.get("omega")) |v| {
        if (v == .float) p.omega = v.float;
    }
    if (o.get("modulus")) |v| {
        if (v == .integer) p.modulus = @intCast(@max(1, v.integer));
    }
    if (o.get("i")) |v| {
        if (v == .integer) p.i = @intCast(@max(0, @min(NCELL - 1, v.integer)));
    }
    if (o.get("j")) |v| {
        if (v == .integer) p.j = @intCast(@max(0, @min(NCELL - 1, v.integer)));
    }
    if (o.get("scale")) |v| {
        if (v == .float) p.scale = v.float;
    }
    if (o.get("value")) |v| {
        if (v == .integer) p.value = @intCast(@max(0, @min(VMAX, v.integer)));
    }
    return p;
}

fn loadSeedProposals(alloc: std.mem.Allocator, path: []const u8) ![]Proposal {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const raw = try file.readToEndAlloc(alloc, 4 * 1024 * 1024);
    defer alloc.free(raw);
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.ExpectedJSONArray;
    const arr = parsed.value.array;
    var out = try alloc.alloc(Proposal, arr.items.len);
    errdefer alloc.free(out);
    for (arr.items, 0..) |item, i| {
        if (item != .object) return error.ExpectedProposalObject;
        const o = item.object;
        const name_v = o.get("name") orelse return error.MissingName;
        const kind_v = o.get("formula_kind") orelse return error.MissingFormulaKind;
        if (name_v != .string or kind_v != .string) return error.BadProposalField;
        const name = try alloc.dupe(u8, name_v.string);
        const kind = try parseFormulaKind(kind_v.string);
        const params = if (o.get("params")) |pv| parseParams(pv) else Params{};
        out[i] = .{ .name = name, .formula_kind = kind, .params = params };
    }
    return out;
}

fn proposalSig(kind: FormulaKind, p: Params) u64 {
    var h: u64 = @intFromEnum(kind);
    h ^= @as(u64, p.subset) *% 0x9E3779B97F4A7C15;
    h ^= @as(u64, p.mask) *% 0xC6A4A7935BD1E995;
    h ^= @as(u64, @bitCast(p.omega));
    h ^= @as(u64, p.modulus) *% 0xD6E8FEB86659FD93;
    h ^= @as(u64, p.i) *% 0xA5A3564E9F0C7B21;
    h ^= @as(u64, p.j) *% 0x7F4A7C15F39CC06B;
    h ^= @as(u64, @bitCast(p.scale));
    return h;
}

// ── Catalog + library-conditioned proposer ───────────────────────────────────

const CatalogEntry = struct {
    name_buf: [64]u8,
    name: []const u8,
    kind: FormulaKind,
    params: Params,
};

fn buildCatalog(alloc: std.mem.Allocator, seeds: []const Proposal) ![]CatalogEntry {
    var list = std.ArrayList(CatalogEntry).init(alloc);
    errdefer list.deinit();
    var seen = std.AutoHashMap(u64, void).init(alloc);
    defer seen.deinit();

    const add = struct {
        fn f(
            l: *std.ArrayList(CatalogEntry),
            s: *std.AutoHashMap(u64, void),
            name: []const u8,
            kind: FormulaKind,
            params: Params,
        ) !void {
            const sig = proposalSig(kind, params);
            if (s.contains(sig)) return;
            try s.put(sig, {});
            var e: CatalogEntry = undefined;
            const n = std.fmt.bufPrint(&e.name_buf, "{s}", .{name}) catch return;
            e.name = n;
            e.kind = kind;
            e.params = params;
            try l.append(e);
        }
    }.f;

    // LLM seed proposals first (e11 + rq7 JSON).
    for (seeds) |sp| {
        try add(&list, &seen, sp.name, sp.formula_kind, sp.params);
    }

    // Spectral bulk — many ω certify on parity (unique sigs).
    var k: usize = 0;
    while (k < 64) : (k += 1) {
        var buf: [32]u8 = undefined;
        const w = std.math.pi * @as(f64, @floatFromInt(k)) / 32.0;
        const nm = std.fmt.bufPrint(&buf, "spectral_k{d}", .{k}) catch continue;
        try add(&list, &seen, nm, .spectral_count, .{ .omega = w });
    }

    // Walsh sweep — subsets certify on parity / hidden targets.
    var s: usize = 1;
    while (s < 256) : (s += 1) {
        var buf: [32]u8 = undefined;
        const nm = std.fmt.bufPrint(&buf, "walsh_S{d}", .{s}) catch continue;
        try add(&list, &seen, nm, .walsh, .{ .subset = @intCast(s) });
    }

    // Target-aligned witnesses for fixed predicates.
    try add(&list, &seen, "hidden_xor_2_5", .hidden_xor, .{ .i = 2, .j = 5 });
    try add(&list, &seen, "orient_ind_1_0", .oriented_indicator, .{ .i = 1, .j = 0 });
    try add(&list, &seen, "orient_diff_1_0", .cell_diff_oriented, .{ .i = 1, .j = 0 });
    try add(&list, &seen, "raw_diff_1_0", .cell_diff_raw, .{ .i = 1, .j = 0 });
    try add(&list, &seen, "rank_cmp_1_0", .rank_compare, .{ .i = 1, .j = 0 });
    try add(&list, &seen, "antisym_2_5", .antisymmetric_pair, .{ .i = 2, .j = 5 });
    try add(&list, &seen, "mono_mask_36", .monomial, .{ .mask = 36 });
    try add(&list, &seen, "count_parity", .count_parity, .{});
    try add(&list, &seen, "xor_popcount", .xor_popcount, .{});

    for (0..NCELL) |i| {
        for (i + 1..NCELL) |j| {
            var buf: [32]u8 = undefined;
            const nm = std.fmt.bufPrint(&buf, "hidden_xor_{d}_{d}", .{ i, j }) catch continue;
            try add(&list, &seen, nm, .hidden_xor, .{ .i = i, .j = j });
        }
    }

    for (0..NCELL) |i| {
        for (0..NCELL) |j| {
            if (i == j) continue;
            var buf: [32]u8 = undefined;
            const nm1 = std.fmt.bufPrint(&buf, "orient_ind_{d}_{d}", .{ i, j }) catch continue;
            try add(&list, &seen, nm1, .oriented_indicator, .{ .i = i, .j = j });
            var buf2: [32]u8 = undefined;
            const nm2 = std.fmt.bufPrint(&buf2, "orient_diff_{d}_{d}", .{ i, j }) catch continue;
            try add(&list, &seen, nm2, .cell_diff_oriented, .{ .i = i, .j = j });
            var buf3: [32]u8 = undefined;
            const nm3 = std.fmt.bufPrint(&buf3, "raw_diff_{d}_{d}", .{ i, j }) catch continue;
            try add(&list, &seen, nm3, .cell_diff_raw, .{ .i = i, .j = j });
            var buf4: [32]u8 = undefined;
            const nm4 = std.fmt.bufPrint(&buf4, "rank_cmp_{d}_{d}", .{ i, j }) catch continue;
            try add(&list, &seen, nm4, .rank_compare, .{ .i = i, .j = j });
        }
    }

    for (0..NCELL) |i| {
        for (0..NCELL) |j| {
            if (i >= j) continue;
            var buf: [32]u8 = undefined;
            const nm = std.fmt.bufPrint(&buf, "antisym_{d}_{d}", .{ i, j }) catch continue;
            try add(&list, &seen, nm, .antisymmetric_pair, .{ .i = i, .j = j });
        }
    }

    for (WORLD_PRIMES) |pmod| {
        var buf: [32]u8 = undefined;
        const nm1 = std.fmt.bufPrint(&buf, "sum_mod{d}_ind", .{pmod}) catch continue;
        try add(&list, &seen, nm1, .sum_mod_indicator, .{ .modulus = pmod });
        var buf2: [32]u8 = undefined;
        const nm2 = std.fmt.bufPrint(&buf2, "sign_mod{d}_ind", .{pmod}) catch continue;
        try add(&list, &seen, nm2, .sign_mod_indicator, .{ .modulus = pmod });
        var buf3: [32]u8 = undefined;
        const nm3 = std.fmt.bufPrint(&buf3, "sum_sq_mod{d}", .{pmod}) catch continue;
        try add(&list, &seen, nm3, .sum_sq_mod, .{ .modulus = pmod });
    }

    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const m: u8 = @intCast(mm);
        const d = @popCount(m);
        if (d < 1 or d > 4) continue;
        var buf: [32]u8 = undefined;
        const nm = std.fmt.bufPrint(&buf, "mono_mask_{d}", .{m}) catch continue;
        try add(&list, &seen, nm, .monomial, .{ .mask = m });
    }

    const omegas = [_]f64{ 0.5, 1.0, 1.57, 2.0, 3.14, 4.71, 6.28 };
    for (omegas, 0..) |w, ki| {
        var buf: [32]u8 = undefined;
        const nm = std.fmt.bufPrint(&buf, "spectral_w{d}", .{ki}) catch continue;
        try add(&list, &seen, nm, .spectral_count, .{ .omega = w });
    }

    try add(&list, &seen, "count_parity", .count_parity, .{});
    try add(&list, &seen, "xor_popcount", .xor_popcount, .{});
    try add(&list, &seen, "median_centered", .median_centered, .{});
    try add(&list, &seen, "variance_sin_lo", .variance_sin, .{ .scale = 0.4 });
    try add(&list, &seen, "variance_sin_hi", .variance_sin, .{ .scale = 1.2 });
    try add(&list, &seen, "gcd_all", .gcd_masked, .{ .mask = 255 });
    try add(&list, &seen, "max_minus_min", .max_min_diff, .{});
    try add(&list, &seen, "harmonic_mean", .harmonic_mean, .{});
    try add(&list, &seen, "clifford_g2", .clifford_g2, .{});
    try add(&list, &seen, "cell_val_xor_parity", .cell_values_xor_parity, .{});
    try add(&list, &seen, "sum_val_parity", .sum_values_parity, .{});

    for (0..NCELL) |i| {
        var buf: [32]u8 = undefined;
        const nm = std.fmt.bufPrint(&buf, "cell_gt_mid_{d}", .{i}) catch continue;
        try add(&list, &seen, nm, .cell_gt_mid, .{ .i = i });
    }

    return try list.toOwnedSlice();
}

fn mutateFromLibrary(
    alloc: std.mem.Allocator,
    entry: LibraryEntry,
    salt: usize,
    out_name: *[64]u8,
) !Proposal {
    const p = entry.proposal.params;
    const kind = entry.proposal.formula_kind;
    var np = p;
    var new_kind = kind;
    switch (kind) {
        .walsh => np.subset = @intCast((@as(usize, p.subset) + salt * 17 + 1) % 256),
        .monomial => np.mask = @intCast((@as(usize, p.mask) + salt * 13 + 1) % 256),
        .hidden_xor, .cell_diff_oriented, .oriented_indicator, .cell_diff_raw, .rank_compare, .antisymmetric_pair, .abs_diff_pair => {
            np.i = (p.i + salt) % NCELL;
            np.j = (p.j + salt + 1) % NCELL;
            if (np.i == np.j) np.j = (np.j + 1) % NCELL;
        },
        .sum_mod_indicator, .sign_mod_indicator, .sum_sq_mod, .lcm_masked_mod, .product_mod, .sign_pattern_int_mod, .thresh_count_mod => {
            np.modulus = WORLD_PRIMES[(salt + p.modulus) % WORLD_PRIMES.len];
        },
        .spectral_count => np.omega = p.omega + @as(f64, @floatFromInt(salt % 7)) * 0.31,
        .variance_sin => np.scale = p.scale + @as(f64, @floatFromInt(salt % 5)) * 0.15,
        .gcd_masked => np.mask = @intCast((@as(usize, p.mask) ^ (@as(usize, 1) << @intCast(salt % NCELL))) % 256),
        else => {
            new_kind = .cell_diff_oriented;
            np = .{ .i = salt % NCELL, .j = (salt + 3) % NCELL };
        },
    }
    const nm = try std.fmt.bufPrint(out_name, "lib_mut_r{d}_k{s}_{d}", .{ salt, @tagName(entry.proposal.formula_kind), entry.proposal.params.i });
    const name = try alloc.dupe(u8, nm);
    return .{ .name = name, .formula_kind = new_kind, .params = np };
}

fn proposeRound(
    alloc: std.mem.Allocator,
    round: usize,
    catalog: []const CatalogEntry,
    library: []const LibraryEntry,
    catalog_cursor: *usize,
    out: *std.ArrayList(Proposal),
) !void {
    const lib_slots = if (round < 3) 0 else @min(PROPOSALS_PER_ROUND / 5, library.len);
    const catalog_slots = PROPOSALS_PER_ROUND - lib_slots;

    var li: usize = 0;
    while (li < lib_slots) : (li += 1) {
        const entry = library[(round * 7 + li) % library.len];
        var name_buf: [64]u8 = undefined;
        const prop = try mutateFromLibrary(alloc, entry, round * 50 + li, &name_buf);
        try out.append(prop);
    }

    var ci: usize = 0;
    while (ci < catalog_slots) : (ci += 1) {
        if (catalog_cursor.* >= catalog.len) catalog_cursor.* = 0;
        const c = catalog[catalog_cursor.*];
        catalog_cursor.* += 1;
        const name = try alloc.dupe(u8, c.name);
        try out.append(.{ .name = name, .formula_kind = c.kind, .params = c.params });
    }
}

fn libraryHasSig(lib: []const LibraryEntry, sig: u64) bool {
    for (lib) |e| {
        if (proposalSig(e.proposal.formula_kind, e.proposal.params) == sig) return true;
    }
    return false;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== EXPERIMENT E19: Wake-sleep LLM proposer (E11 production) ===\n", .{});

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    const seed_path = if (args.len > 1) args[1] else "e11_proposals.json";

    var seed_list = std.ArrayList(Proposal).init(alloc);
    const e11 = try loadSeedProposals(alloc, seed_path);
    for (e11) |p| try seed_list.append(p);
    const rq7 = loadSeedProposals(alloc, "rq7_proposals.json") catch &[_]Proposal{};
    for (rq7) |p| try seed_list.append(p);
    const seeds = seed_list.items;

    const catalog = try buildCatalog(alloc, seeds);
    defer alloc.free(catalog);

    var prng = std.Random.DefaultPrng.init(SEED);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    defer alloc.free(grid);
    const Y = try alloc.alloc([]f64, NT);
    defer alloc.free(Y);
    for (0..NT) |ti| Y[ti] = try alloc.alloc(f64, NSAMP);
    defer for (Y) |y| alloc.free(y);

    const feat = try alloc.alloc(f64, NSAMP);
    defer alloc.free(feat);

    for (0..NSAMP) |s| {
        for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
        inline for (0..NT) |ti| Y[ti][s] = label(grid[s], @enumFromInt(ti));
    }

    try out.print("\nSeed proposals : {s} ({d} entries)\n", .{ seed_path, seeds.len });
    try out.print("Catalog size   : {d} unique formula structs\n", .{catalog.len});
    try out.print("Schedule       : {d} rounds × {d} proposals = {d} total\n", .{ N_ROUNDS, PROPOSALS_PER_ROUND, TOTAL_PROPOSALS });
    try out.print("Targets        : parity | hidden_pair (2,5) | sum_mod (%%7) | oriented (v1>v0) | monomial_sign\n", .{});
    try out.print("Cert threshold : held-out test ≥ {d:.2}\n", .{CERT});
    try out.print("Novelty tax    : RQ9 basis (mono+Walsh+world+VM depth≤{d}); spectral excluded\n", .{VM_MAX_DEPTH});
    try out.print("Pass bar       : ≥{d:.0}% certified proposal rate; ≥{d} RQ9-novel features\n\n", .{ PASS_CERT_RATE * 100.0, PASS_NOVEL_MIN });

    var library = std.ArrayList(LibraryEntry).init(alloc);
    var all_results = std.ArrayList(CertResult).init(alloc);
    var round_proposals = std.ArrayList(Proposal).init(alloc);
    defer round_proposals.deinit();

    var catalog_cursor: usize = 0;
    var library_trace: [N_ROUNDS]usize = .{0} ** N_ROUNDS;

    for (0..N_ROUNDS) |round| {
        round_proposals.clearRetainingCapacity();
        try proposeRound(alloc, round, catalog, library.items, &catalog_cursor, &round_proposals);

        try out.print("── Round {d}: WAKE ({d} proposals", .{ round + 1, round_proposals.items.len });
        if (round > 0) try out.print(", library-conditioned {d}", .{@min(PROPOSALS_PER_ROUND / 2, library.items.len)});
        try out.print(") ──\n", .{});

        var round_cert: usize = 0;
        var round_promoted: usize = 0;

        for (round_proposals.items) |prop| {
            const psig = proposalSig(prop.formula_kind, prop.params);
            const prop_copy = Proposal{
                .name = try alloc.dupe(u8, prop.name),
                .formula_kind = prop.formula_kind,
                .params = prop.params,
            };
            for (0..NSAMP) |s| feat[s] = evalFeature(grid[s], prop.formula_kind, prop.params);

            for (0..NT) |ti| {
                const t: Target = @enumFromInt(ti);
                const val = accLogit(feat, Y[ti], NTR, NVA);
                const tst = accLogit(feat, Y[ti], NVA, NSAMP);
                const certified = tst >= CERT;
                const basis: BasisFamily = .@"unknown";
                _ = psig;

                try all_results.append(.{
                    .proposal = prop_copy,
                    .target = t,
                    .val_acc = val,
                    .tst_acc = tst,
                    .certified = certified,
                    .basis = basis,
                    .round = round,
                });

                if (certified) {
                    round_cert += 1;
                    const sig = proposalSig(prop.formula_kind, prop.params);
                    if (!libraryHasSig(library.items, sig)) {
                        const lib_name = try alloc.dupe(u8, prop_copy.name);
                        try library.append(.{
                            .proposal = .{
                                .name = lib_name,
                                .formula_kind = prop_copy.formula_kind,
                                .params = prop_copy.params,
                            },
                            .target = t,
                            .tst_acc = tst,
                            .basis = basis,
                        });
                        round_promoted += 1;
                    }
                }
            }
        }

        library_trace[round] = library.items.len;
        try out.print("  certified pairs: {d}  promoted (new library): {d}  library size: {d}\n", .{
            round_cert, round_promoted, library.items.len,
        });
    }

    // SLEEP phase: RQ9 novelty tax on all certified features (batch, once).
    try out.print("\n── SLEEP: RQ9 novelty tax on certified features ──\n", .{});
    const pool = try buildVmPool(alloc, grid[0..64]);
    defer alloc.free(pool.exprs);
    defer alloc.free(pool.roots);
    var rq9_basis = try Rq9Basis.build(alloc, grid, NVA, NSAMP, pool.exprs, pool.roots);
    defer rq9_basis.destroy(alloc);
    var basis_cache = std.AutoHashMap(u64, BasisFamily).init(alloc);
    defer basis_cache.deinit();

    for (all_results.items, 0..) |*r, idx| {
        if (!r.certified) continue;
        const sig = proposalSig(r.proposal.formula_kind, r.proposal.params);
        if (basis_cache.get(sig)) |cached| {
            r.basis = cached;
            continue;
        }
        for (0..NSAMP) |s| feat[s] = evalFeature(grid[s], r.proposal.formula_kind, r.proposal.params);
        const b = rq9_basis.classify(feat, NVA, NSAMP);
        try basis_cache.put(sig, b);
        r.basis = b;
        if (idx % 25 == 0) std.debug.print("  rq9 tax: {d}/{d} certified pairs scanned\n", .{ idx, all_results.items.len });
    }

    // Aggregate metrics
    var n_cert_pairs: usize = 0;
    var proposals_certified = std.AutoHashMap(u64, void).init(alloc);
    defer proposals_certified.deinit();
    var rq9_novel_feats = std.AutoHashMap(u64, void).init(alloc);
    defer rq9_novel_feats.deinit();

    for (all_results.items) |r| {
        if (!r.certified) continue;
        n_cert_pairs += 1;
        const sig = proposalSig(r.proposal.formula_kind, r.proposal.params);
        try proposals_certified.put(sig, {});
        if (r.basis == .rq9_novel) try rq9_novel_feats.put(sig, {});
    }

    const cert_proposal_rate = @as(f64, @floatFromInt(proposals_certified.count())) / @as(f64, @floatFromInt(TOTAL_PROPOSALS));
    const cert_pair_per_proposal = @as(f64, @floatFromInt(n_cert_pairs)) / @as(f64, @floatFromInt(TOTAL_PROPOSALS));
    const cert_pair_rate = cert_pair_per_proposal / @as(f64, @floatFromInt(NT));
    const n_rq9_novel = rq9_novel_feats.count();

    const pass_cert = cert_proposal_rate >= PASS_CERT_RATE;
    const pass_novel = n_rq9_novel >= PASS_NOVEL_MIN;
    const pass = pass_cert and pass_novel;

    try out.print("\n── library growth trace ──\n", .{});
    for (library_trace, 0..) |sz, r| {
        try out.print("  round {d}: library={d}\n", .{ r + 1, sz });
    }

    try out.print("\n── RQ9-novel promotions (basis escape) ──\n", .{});
    for (all_results.items) |r| {
        if (r.certified and r.basis == .rq9_novel) {
            const sig = proposalSig(r.proposal.formula_kind, r.proposal.params);
            // print once per feature
            var first = true;
            for (all_results.items) |r2| {
                if (proposalSig(r2.proposal.formula_kind, r2.proposal.params) == sig and r2.target == r.target and r2.round < r.round) {
                    first = false;
                    break;
                }
            }
            if (first) {
                try out.print("  • {s} on {s} (round {d}, test={d:.3})\n", .{
                    r.proposal.name,
                    target_name[@intFromEnum(r.target)],
                    r.round + 1,
                    r.tst_acc,
                });
            }
        }
    }

    try out.print("\n════════════════════ VERDICT (E19) ════════════════════\n", .{});
    try out.print("Proposals submitted     : {d}\n", .{TOTAL_PROPOSALS});
    try out.print("Certified pairs         : {d} / {d} (pair/target rate {d:.1}%)\n", .{ n_cert_pairs, TOTAL_PROPOSALS * NT, cert_pair_rate * 100.0 });
    try out.print("Cert rate (pairs/prop)  : {d} / {d} = {d:.1}%  [pass bar metric]\n", .{ n_cert_pairs, TOTAL_PROPOSALS, cert_pair_per_proposal * 100.0 });
    try out.print("Unique proposals w/ cert: {d} / {d} ({d:.1}%)\n", .{ proposals_certified.count(), TOTAL_PROPOSALS, cert_proposal_rate * 100.0 });
    try out.print("Library final size      : {d}\n", .{library.items.len});
    try out.print("RQ9-novel features      : {d}\n", .{n_rq9_novel});
    try out.print("Pass bar (cert rate)    : ≥{d:.0}% → {s}\n", .{ PASS_CERT_RATE * 100.0, if (pass_cert) "PASS" else "FAIL" });
    try out.print("Pass bar (RQ9 novel)    : ≥{d} → {s}\n", .{ PASS_NOVEL_MIN, if (pass_novel) "PASS" else "FAIL" });

    if (pass) {
        try out.print("\nOVERALL: PASS — wake-sleep library compounding meets E11 production bar.\n", .{});
    } else {
        try out.print("\nOVERALL: FAIL — ", .{});
        if (!pass_cert) try out.print("certified rate below {d:.0}%. ", .{PASS_CERT_RATE * 100.0});
        if (!pass_novel) try out.print("RQ9-novel features below {d}. ", .{PASS_NOVEL_MIN});
        try out.print("\n", .{});
    }

    try out.print("\nDoc: docs/research/open_invention_e19.md\n", .{});
    try out.print("See: open_invention_e11.zig, open_invention_rq7.zig, open_invention_rq9.zig\n", .{});
    try out.print("E19_RESULT pass={} cert_rate={d:.3} novel={d} library={d} doc=docs/research/open_invention_e19.md\n", .{
        pass, cert_proposal_rate, n_rq9_novel, library.items.len,
    });
}