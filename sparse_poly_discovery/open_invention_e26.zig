//! EXPERIMENT E26 — Equivalence tax v2 (RQ9++).
//!
//! Extends RQ9 with a richer basis closure:
//!   monomial φ_S + Walsh χ_S + world pool + VM depth≤6
//!   + xor_popcount(mask)           (E2 / RQ2)
//!   + mod synthesis depth≤3        (E3 / RQ3 / E14)
//!   + composed pipelines           (E5 inner₁→inner₂ scalars)
//!
//! Tests certified escapes from E1–E12 (grid predicates; E6/E7/E8/E9/E10 have no grid escapes).
//!
//! PASS bar: <40% basis-reproducible (RQ9 v1 was 67% on 6 escapes with narrower basis).
//!
//! Run: zig build open-invention-e26 --release=fast

const std = @import("std");
const e2 = @import("open_invention_e2.zig");
const e5 = @import("open_invention_e5.zig");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP_TRAIN: usize = 7000;
const NSAMP_TEST: usize = 3500;
const NTR: usize = 3500;
const NVA: usize = 5250;
const MAX_BUDGET: usize = 8;
const PREFILTER_TOP: usize = 128;
const CERT: f64 = 0.90;
const PASS_BAR: f64 = 0.40;
const MAX_DEG: usize = 4;
const VM_MAX_DEPTH: usize = 6;
const VM_MAX_POOL: usize = 8192;

const GRID_TRAIN_SEED: u64 = 0xF0235A11CE0FF1CE;
const GRID_TEST_SEED: u64 = 0xE957E5700002;
const E4_TARGET_SEED: u64 = 0xE4CE11ED0FF1CE42;
const E1_BATTERY_SEED: u64 = 0xE1B10D20A11CE01;

const WORLD_POOL = [_]usize{ 2, 3, 5, 7, 11, 13 };
const NMONO: usize = 255;
const NWALSH: usize = 256;
const NWORLD: usize = WORLD_POOL.len * 2;
const NXOR: usize = 255;
const NPIPE: usize = e5.N_INNER1 * e5.N_INNER2;

const EscapeId = enum {
    e3_parity,
    e4_g00_sum_parity,
    e4_g06_rank_cmp,
    e5_inversion_parity,
    e5_sum_bind,
    e11_sum_mod7,
    e1_b1,
    e1_b2,
    e1_b3,
    e1_b4,
    e1_b5,
    e1_b6,
    e1_b7,
    e1_b8,
    e1_b9,
    e1_b10,
    e1_b11,
    e2_xor_0f,
    e2_parity_xor_33,
    e12_rank2_eq1,
};

const escape_name = [_][]const u8{
    "E3-parity (mod count 2)",
    "E4-G00 (sum*parity mint)",
    "E4-G06 (rank-compare mint)",
    "E5-F-A (inversion-parity)",
    "E5-F-B (sum-then-bind)",
    "E11 (sum_mod7_indicator)",
    "E1-B1 random monomial deg2",
    "E1-B2 random monomial deg3",
    "E1-B3 sum(g)%7",
    "E1-B4 sign%mod 11",
    "E1-B5 Walsh χ{0x11}",
    "E1-B6 Walsh χ{0xA4}",
    "E1-B7 Walsh χ{0x0A}",
    "E1-B8 parity-of-count",
    "E1-B9 oriented v1>v0",
    "E1-B10 parity AND sum%5",
    "E1-B11 inversion parity",
    "E2 XOR(mask=0x0F)&1",
    "E2 parity(XOR 0x33)",
    "E12 rank2(0,1,2)==1",
};

const escape_source = [_][]const u8{
    "E3", "E4", "E4", "E5", "E5", "E11",
    "E1", "E1", "E1", "E1", "E1", "E1", "E1", "E1", "E1", "E1", "E1",
    "E2", "E2", "E12",
};

const escape_primitive = [_][]const u8{
    "mod(count,2)", "sum*parity", "(c0+c0)*(rank_6>rank_5)", "inversion→half_p", "sum→bind_xy", "sum%mod_7",
    "φ_random_deg2", "φ_random_deg3", "sum%mod_7", "sign%mod_11", "χ(0x11)", "χ(0xA4)", "χ(0x0A)",
    "mod(count,2)", "oriented", "parity∧sum%5", "inv mod 2",
    "xor_popcount(0x0F)", "xor_popcount(0x33)", "rank2==1",
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

fn rank2Triple(a: u8, b: u8, c: u8) u8 {
    var s = [_]u8{ a, b, c };
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    return s[1];
}

// ── VM expression pool (RQ9 substrate) ───────────────────────────────────────

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

// ── Mod synthesis bank (E14 / RQ3) ───────────────────────────────────────────

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

    return .{
        .nodes = try nodes.toOwnedSlice(),
        .depths = try depths.toOwnedSlice(),
    };
}

// ── Pipeline scalar features (E5) ────────────────────────────────────────────

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

// ── Candidate basis v2 ───────────────────────────────────────────────────────

const CandTag = enum { mono, walsh, world_sum, world_sign, vm, xor_popcount, mod_synth, pipeline };

const Candidate = struct {
    tag: CandTag,
    param: u32,
};

const NCAND_STATIC: usize = NMONO + NWALSH + NWORLD + NXOR;

const BasisCtx = struct {
    exprs: []const Expr,
    bank: ProgBank,
};

fn candLabel(buf: []u8, c: Candidate, ctx: BasisCtx) []const u8 {
    return switch (c.tag) {
        .mono => std.fmt.bufPrint(buf, "φ(0x{X:0>2})", .{@as(u8, @intCast(c.param))}) catch "φ",
        .walsh => std.fmt.bufPrint(buf, "χ(0x{X:0>2})", .{@as(u8, @intCast(c.param))}) catch "χ",
        .world_sum => std.fmt.bufPrint(buf, "sum%mod_{d}", .{c.param}) catch "sum_mod",
        .world_sign => std.fmt.bufPrint(buf, "sign%mod_{d}", .{c.param}) catch "sign_mod",
        .vm => fmtExpr(buf, ctx.exprs, @intCast(c.param)),
        .xor_popcount => std.fmt.bufPrint(buf, "xor_pop(0x{X:0>2})", .{@as(u8, @intCast(c.param))}) catch "xor",
        .mod_synth => std.fmt.bufPrint(buf, "synth#{d}", .{c.param}) catch "synth",
        .pipeline => std.fmt.bufPrint(buf, "{s}→{s}", .{
            e5.inner1_name[c.param >> 8],
            e5.inner2_name[c.param & 0xFF],
        }) catch "pipe",
    };
}

fn evalCand(c: Candidate, g: [NCELL]u8, ctx: BasisCtx) f64 {
    return switch (c.tag) {
        .mono => phiMono(g, @intCast(c.param)),
        .walsh => chi(@intCast(c.param), signPattern(g)),
        .world_sum => if (gridSum(g) % c.param == 0) 1.0 else 0.0,
        .world_sign => if (@as(usize, signPattern(g)) % c.param == 0) 1.0 else 0.0,
        .vm => evalExpr(ctx.exprs, @intCast(c.param), g),
        .xor_popcount => e2.xorPopcountReadout(g, @intCast(c.param)),
        .mod_synth => ctx.bank.eval(@intCast(c.param), ScalarCtx.fromGrid(g)),
        .pipeline => pipelineScalar(
            @enumFromInt(@as(u8, @intCast(c.param >> 8))),
            @enumFromInt(@as(u8, @intCast(c.param & 0xFF))),
            g,
        ),
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
    var xm: u16 = 1;
    while (xm < 256) : (xm += 1) {
        out[idx] = .{ .tag = .xor_popcount, .param = xm };
        idx += 1;
    }
}

// ── Escape labels ────────────────────────────────────────────────────────────

const E4Target = struct {
    prog_id: u16,
    threshold: f64,
    name: []const u8,
};

const E4Targets = struct {
    g00: E4Target,
    g06: E4Target,
};

const E1Battery = struct {
    b1_mask: u8,
    b2_mask: u8,
};

fn parityLabel(g: [NCELL]u8) f64 {
    var c: usize = 0;
    for (g) |v| {
        if (v >= THRESH) c += 1;
    }
    return @floatFromInt(c & 1);
}

fn inversionParityLabel(g: [NCELL]u8) f64 {
    return @floatFromInt(inversionCount(g) & 1);
}

fn sumBindLabel(g: [NCELL]u8) f64 {
    const a = @as(f64, @floatFromInt(g[0])) - MID;
    const b = @as(f64, @floatFromInt(g[1])) - MID;
    return if (a * b > 0) 1.0 else 0.0;
}

fn sumMod7Label(g: [NCELL]u8) f64 {
    return if (gridSum(g) % 7 == 0) 1.0 else 0.0;
}

fn e4Label(g: [NCELL]u8, exprs: []const Expr, tgt: E4Target) f64 {
    return if (evalExpr(exprs, tgt.prog_id, g) > tgt.threshold) 1.0 else 0.0;
}

fn randomMask(rand: std.Random, deg: usize, zoo: []const u8) u8 {
    var tries: usize = 0;
    while (tries < 200) : (tries += 1) {
        var m: u8 = 0;
        var placed: usize = 0;
        while (placed < deg) : (placed += 1) {
            const bit = rand.intRangeAtMost(usize, 0, NCELL - 1);
            m |= @as(u8, 1) << @intCast(bit);
        }
        var dup = false;
        for (zoo) |z| {
            if (m == z) dup = true;
        }
        if (!dup and popcount(m) == deg) return m;
    }
    return 0x0F;
}

fn generateE1Battery(rand: std.Random) E1Battery {
    const zoo = [_]u8{
        (1 << 2) | (1 << 5),
        (1 << 1) | (1 << 3) | (1 << 6),
        (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7),
        (1 << 3),
    };
    return .{
        .b1_mask = randomMask(rand, 2, &zoo),
        .b2_mask = randomMask(rand, 3, &zoo),
    };
}

fn escapeLabel(g: [NCELL]u8, id: EscapeId, e1: E1Battery, e4: E4Targets, exprs: []const Expr) f64 {
    return switch (id) {
        .e3_parity => parityLabel(g),
        .e4_g00_sum_parity => e4Label(g, exprs, e4.g00),
        .e4_g06_rank_cmp => e4Label(g, exprs, e4.g06),
        .e5_inversion_parity => inversionParityLabel(g),
        .e5_sum_bind => sumBindLabel(g),
        .e11_sum_mod7 => sumMod7Label(g),
        .e1_b1 => if (phiMono(g, e1.b1_mask) > 0) 1.0 else 0.0,
        .e1_b2 => if (phiMono(g, e1.b2_mask) > 0) 1.0 else 0.0,
        .e1_b3 => if (gridSum(g) % 7 == 0) 1.0 else 0.0,
        .e1_b4 => if (@as(usize, signPattern(g)) % 11 == 0) 1.0 else 0.0,
        .e1_b5 => if (chi((1 << 0) | (1 << 4), signPattern(g)) > 0) 1.0 else 0.0,
        .e1_b6 => if (chi((1 << 2) | (1 << 5) | (1 << 7), signPattern(g)) > 0) 1.0 else 0.0,
        .e1_b7 => if (chi((1 << 1) | (1 << 3), signPattern(g)) > 0) 1.0 else 0.0,
        .e1_b8 => parityLabel(g),
        .e1_b9 => if (g[1] > g[0]) 1.0 else 0.0,
        .e1_b10 => blk: {
            const p = @as(usize, @intFromFloat(parityLabel(g)));
            break :blk if (p == 1 and gridSum(g) % 5 == 0) 1.0 else 0.0;
        },
        .e1_b11 => inversionParityLabel(g),
        .e2_xor_0f => e2.label(g, .{ .kind = .xor_cells, .mask = 0x0F }),
        .e2_parity_xor_33 => e2.label(g, .{ .kind = .parity_xor, .mask = 0x33 }),
        .e12_rank2_eq1 => if (rank2Triple(g[0], g[1], g[2]) == 1) 1.0 else 0.0,
    };
}

fn generateE4Targets(
    alloc: std.mem.Allocator,
    grid_train: []const [NCELL]u8,
    exprs: []const Expr,
    roots: []const u16,
    rand: std.Random,
) !E4Targets {
    const probe = grid_train[0..64];
    const feat = try alloc.alloc(f64, NSAMP_TRAIN);
    defer alloc.free(feat);

    const Cand = struct { id: u16, base_cov: f64 };
    var candidates = std.ArrayList(Cand).init(alloc);
    defer candidates.deinit();

    var tries: usize = 0;
    while (candidates.items.len < 80 and tries < 1200) : (tries += 1) {
        const ridx = rand.intRangeLessThan(usize, 0, roots.len);
        const pid = roots[ridx];
        if (exprDepth(exprs, pid) < 3) continue;
        var dup = false;
        for (candidates.items) |c| {
            if (exprSig(exprs, c.id, probe) == exprSig(exprs, pid, probe)) {
                dup = true;
                break;
            }
        }
        if (dup) continue;

        for (0..NSAMP_TRAIN) |s| feat[s] = evalExpr(exprs, pid, grid_train[s]);
        var vals = std.ArrayList(f64).init(alloc);
        defer vals.deinit();
        for (0..NTR) |s| try vals.append(feat[s]);
        std.sort.pdq(f64, vals.items, {}, std.sort.asc(f64));
        const med = vals.items[vals.items.len / 2];
        for (0..NSAMP_TRAIN) |s| feat[s] = if (feat[s] > med) 1.0 else 0.0;

        var best_val: f64 = 0;
        for (0..NCELL) |i| {
            var pos: usize = 0;
            var tot: usize = 0;
            for (NTR..NVA) |s| {
                const pred = grid_train[s][i] >= THRESH;
                const lab = feat[s] > 0.5;
                if (pred == lab) pos += 1;
                tot += 1;
            }
            best_val = @max(best_val, @as(f64, @floatFromInt(pos)) / @as(f64, @floatFromInt(tot)));
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
    const pick6 = if (candidates.items.len > 6) candidates.items[6].id else roots[@min(6, roots.len - 1)];

    const makeTarget = struct {
        fn f(exprs_: []const Expr, grid_: []const [NCELL]u8, pid: u16, alloc_: std.mem.Allocator, tag: []const u8) !E4Target {
            var raw = try alloc_.alloc(f64, NSAMP_TRAIN);
            defer alloc_.free(raw);
            for (0..NSAMP_TRAIN) |s| raw[s] = evalExpr(exprs_, pid, grid_[s]);
            var vals = try alloc_.alloc(f64, NTR);
            defer alloc_.free(vals);
            for (0..NTR) |s| vals[s] = raw[s];
            std.sort.pdq(f64, vals, {}, std.sort.asc(f64));
            const med = vals[NTR / 2];
            var pbuf: [96]u8 = undefined;
            const pname = fmtExpr(&pbuf, exprs_, pid);
            const name = try std.fmt.allocPrint(alloc_, "E4 {s}: {s}", .{ tag, pname });
            return .{ .prog_id = pid, .threshold = med, .name = name };
        }
    }.f;

    return .{
        .g00 = try makeTarget(exprs, grid_train, pick0, alloc, "G00"),
        .g06 = try makeTarget(exprs, grid_train, pick6, alloc, "G06"),
    };
}

// ── ML helpers ───────────────────────────────────────────────────────────────

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

const SearchResult = struct {
    test_acc: f64,
    val_acc: f64,
    n_selected: usize,
    reproducible: bool,
    top_features: [MAX_BUDGET][]const u8,
};

fn containsIdx(list: []const usize, idx: usize) bool {
    for (list) |x| if (x == idx) return true;
    return false;
}

fn fixedBudgetSearch(
    alloc: std.mem.Allocator,
    static_cands: []const Candidate,
    extra_cands: []const Candidate,
    F_train: []const []f64,
    F_test: []const []f64,
    Y_train: []const f64,
    Y_test: []const f64,
    ctx: BasisCtx,
    out: anytype,
) !SearchResult {
    var selected = std.ArrayList(usize).init(alloc);
    defer selected.deinit();

    var w: [MAX_BUDGET + 1]f64 = undefined;
    const Xtr = try alloc.alloc([]f64, NSAMP_TRAIN);
    defer alloc.free(Xtr);
    const Xte = try alloc.alloc([]f64, NSAMP_TEST);
    defer alloc.free(Xte);
    for (0..NSAMP_TRAIN) |s| Xtr[s] = try alloc.alloc(f64, MAX_BUDGET);
    for (0..NSAMP_TEST) |s| Xte[s] = try alloc.alloc(f64, MAX_BUDGET);

    var best_val: f64 = 0;
    var best_test: f64 = 0;
    var feat_names: [MAX_BUDGET][]const u8 = undefined;
    @memset(&feat_names, "");

    const n_total = static_cands.len + extra_cands.len;

    for (0..MAX_BUDGET) |round| {
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
            for (0..NSAMP_TRAIN) |s| {
                for (selected.items, 0..) |sel, j| Xtr[s][j] = F_train[sel][s];
                Xtr[s][selected.items.len] = F_train[ci][s];
            }
            standardizeMatrix(Xtr, dim, NSAMP_TRAIN, NTR);
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
        for (0..NSAMP_TRAIN) |s| {
            for (selected.items, 0..) |sel, j| Xtr[s][j] = F_train[sel][s];
        }
        for (0..NSAMP_TEST) |s| {
            for (selected.items, 0..) |sel, j| Xte[s][j] = F_test[sel][s];
        }
        standardizeMatrix(Xtr, dim, NSAMP_TRAIN, NTR);
        fitLogit(Xtr, Y_train, dim, NTR, 120, 0.05, &w);
        best_val = accLogit(Xtr, Y_train, &w, dim, NTR, NVA);

        for (0..dim) |j| {
            var mu: f64 = 0;
            for (0..NTR) |s| mu += Xtr[s][j];
            mu /= @floatFromInt(NTR);
            var sd: f64 = 0;
            for (0..NTR) |s| sd += (Xtr[s][j] - mu) * (Xtr[s][j] - mu);
            sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
            for (0..NSAMP_TEST) |s| Xte[s][j] = (Xte[s][j] - mu) / sd;
        }
        best_test = accLogit(Xte, Y_test, &w, dim, 0, NSAMP_TEST);

        var lbl: [64]u8 = undefined;
        const cidx = pick;
        const cand = if (cidx < static_cands.len) static_cands[cidx] else extra_cands[cidx - static_cands.len];
        feat_names[round] = try alloc.dupe(u8, candLabel(&lbl, cand, ctx));

        try out.print("    round {d}: +{s}  val={d:.3}  test={d:.3}\n", .{ round + 1, feat_names[round], best_val, best_test });
        if (best_test >= CERT) break;
    }

    return .{
        .test_acc = best_test,
        .val_acc = best_val,
        .n_selected = selected.items.len,
        .reproducible = best_test >= CERT,
        .top_features = feat_names,
    };
}

fn fillGrid(alloc: std.mem.Allocator, seed: u64, n: usize) ![] [NCELL]u8 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const grid = try alloc.alloc([NCELL]u8, n);
    for (0..n) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };
    return grid;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const grid_train = try fillGrid(alloc, GRID_TRAIN_SEED, NSAMP_TRAIN);
    const grid_test = try fillGrid(alloc, GRID_TEST_SEED, NSAMP_TEST);

    const pool = try buildVmPool(alloc, grid_train[0..64]);
    const exprs = pool.exprs;
    const vm_roots = pool.roots;
    const bank = try buildProgBank(alloc);
    const bctx: BasisCtx = .{ .exprs = exprs, .bank = bank };

    var static_store: [NCAND_STATIC]Candidate = undefined;
    buildStaticCandidates(&static_store);

    var extra_store = std.ArrayList(Candidate).init(alloc);
    for (vm_roots) |rid| try extra_store.append(.{ .tag = .vm, .param = rid });
    for (1..bank.nodes.len) |pid| {
        if (bank.depth(@intCast(pid)) <= 3) {
            try extra_store.append(.{ .tag = .mod_synth, .param = @intCast(pid) });
        }
    }
    for (0..e5.N_INNER1) |in1| {
        for (0..e5.N_INNER2) |in2| {
            try extra_store.append(.{ .tag = .pipeline, .param = @intCast((in1 << 8) | in2) });
        }
    }

    const total_cands = static_store.len + extra_store.items.len;

    const F_train = try alloc.alloc([]f64, total_cands);
    const F_test = try alloc.alloc([]f64, total_cands);
    for (0..total_cands) |ci| {
        F_train[ci] = try alloc.alloc(f64, NSAMP_TRAIN);
        F_test[ci] = try alloc.alloc(f64, NSAMP_TEST);
        const cand = if (ci < static_store.len) static_store[ci] else extra_store.items[ci - static_store.len];
        for (0..NSAMP_TRAIN) |s| F_train[ci][s] = evalCand(cand, grid_train[s], bctx);
        for (0..NSAMP_TEST) |s| F_test[ci][s] = evalCand(cand, grid_test[s], bctx);
    }

    var prng_e4 = std.Random.DefaultPrng.init(E4_TARGET_SEED);
    const e4_targets = try generateE4Targets(alloc, grid_train, exprs, vm_roots, prng_e4.random());

    var prng_e1 = std.Random.DefaultPrng.init(E1_BATTERY_SEED);
    const e1_battery = generateE1Battery(prng_e1.random());

    const n_escapes = @intFromEnum(EscapeId.e12_rank2_eq1) + 1;
    const Y_train = try alloc.alloc([]f64, n_escapes);
    const Y_test = try alloc.alloc([]f64, n_escapes);
    for (0..n_escapes) |t| {
        Y_train[t] = try alloc.alloc(f64, NSAMP_TRAIN);
        Y_test[t] = try alloc.alloc(f64, NSAMP_TEST);
    }

    for (0..NSAMP_TRAIN) |s| {
        const g = grid_train[s];
        inline for (0..n_escapes) |ti| {
            Y_train[ti][s] = escapeLabel(g, @enumFromInt(ti), e1_battery, e4_targets, exprs);
        }
    }
    for (0..NSAMP_TEST) |s| {
        const g = grid_test[s];
        inline for (0..n_escapes) |ti| {
            Y_test[ti][s] = escapeLabel(g, @enumFromInt(ti), e1_battery, e4_targets, exprs);
        }
    }

    try out.print("=== EXPERIMENT E26: equivalence tax v2 (RQ9++) ===\n\n", .{});
    try out.print("Basis v2: monomial φ_S (deg≤{d}) + Walsh χ_S + world pool + VM depth≤{d}\n", .{ MAX_DEG, VM_MAX_DEPTH });
    try out.print("          + xor_popcount(mask) + mod synthesis depth≤3 + E5 pipelines ({d}×{d})\n", .{ e5.N_INNER1, e5.N_INNER2 });
    try out.print("Search: greedy forward selection, budget≤{d}, corr-prefilter top {d}/round.\n", .{ MAX_BUDGET, PREFILTER_TOP });
    try out.print("Train grids: seed 0x{X:0>16} ({d}); held-out test: seed 0x{X:0>16} ({d}).\n", .{
        GRID_TRAIN_SEED, NSAMP_TRAIN, GRID_TEST_SEED, NSAMP_TEST,
    });
    try out.print("E1 battery masks (seed 0x{X:0>16}): B1=0x{X:0>2} B2=0x{X:0>2}\n", .{ E1_BATTERY_SEED, e1_battery.b1_mask, e1_battery.b2_mask });
    try out.print("Candidates: {d} static + {d} extra = {d} total.\n", .{ static_store.len, extra_store.items.len, total_cands });
    try out.print("Excluded experiments (no grid escapes): E6, E7, E8 (terminal), E9, E10.\n\n", .{});

    try out.print("E4 pinned targets (seed 0x{X:0>16}):\n", .{E4_TARGET_SEED});
    try out.print("  {s}\n", .{e4_targets.g00.name});
    try out.print("  {s}\n\n", .{e4_targets.g06.name});

    try out.print("┌────────────────────────────────┬────────┬──────────┬─────────────┬──────────────┐\n", .{});
    try out.print("│ Escape (certified primitive)   │ Source │ Test acc │ Reproducible│ Basis winner │\n", .{});
    try out.print("├────────────────────────────────┼────────┼──────────┼─────────────┼──────────────┤\n", .{});

    var n_repro: usize = 0;
    var novel_list = std.ArrayList([]const u8).init(alloc);

    for (0..n_escapes) |ti| {
        try out.print("\n── {s} [{s}] escape={s} ──\n", .{ escape_name[ti], escape_source[ti], escape_primitive[ti] });
        const sr = try fixedBudgetSearch(
            alloc,
            static_store[0..],
            extra_store.items,
            F_train,
            F_test,
            Y_train[ti],
            Y_test[ti],
            bctx,
            out,
        );
        if (sr.reproducible) n_repro += 1 else try novel_list.append(escape_name[ti]);

        var win_buf: [128]u8 = undefined;
        const winner = if (sr.n_selected > 0) sr.top_features[sr.n_selected - 1] else "-";
        const win_short = std.fmt.bufPrint(&win_buf, "{s}", .{winner}) catch "-";

        try out.print("│ {s:<30} │ {s:<6} │ {d:.3}    │ {s:<11} │ {s:<12} │\n", .{
            escape_name[ti],
            escape_source[ti],
            sr.test_acc,
            if (sr.reproducible) "YES" else "NO",
            win_short,
        });
    }

    try out.print("└────────────────────────────────┴────────┴──────────┴─────────────┴──────────────┘\n\n", .{});

    const repro_pct = 100.0 * @as(f64, @floatFromInt(n_repro)) / @as(f64, @floatFromInt(n_escapes));
    const pass = repro_pct < PASS_BAR * 100.0;

    try out.print("════════════════════ VERDICT (E26 / RQ9++) ════════════════════\n", .{});
    try out.print("Escapes tested     : {d} (E1–E12 grid-certified; E6/E7/E8/E9/E10 N/A)\n", .{n_escapes});
    try out.print("Reproducible (≥{d:.2}): {d}/{d}  ({d:.1}%)\n", .{ CERT, n_repro, n_escapes, repro_pct });
    try out.print("RQ9 v1 baseline    : 4/6 = 67%% (narrower basis, 6 escapes)\n", .{});
    try out.print("Pass bar           : <{d:.0}% reproducible for \"real invention\"\n", .{PASS_BAR * 100.0});
    if (pass) {
        try out.print("Overall verdict    : PASS — most escapes sit OUTSIDE expanded basis v2.\n", .{});
    } else {
        try out.print("Overall verdict    : FAIL — {d:.0}% reproducible; escapes mostly basis-equivalent under v2 tax.\n", .{repro_pct});
    }

    try out.print("\nNovel survivors ({d}):\n", .{novel_list.items.len});
    for (novel_list.items) |nm| try out.print("  • {s}\n", .{nm});

    try out.print("\nDoc: docs/research/open_invention_e26.md\n", .{});
    try out.print("See: open_invention_rq9.zig (v1), open_invention_e14.zig (route families)\n", .{});
}