//! EXPERIMENT E14 — Hardness-routed open invention.
//!
//! Question: Does Q38 compound detection auto-pick xor_popcount vs mod synthesis vs pipeline?
//!
//! Protocol: 50 held-out targets from E2 adversarial + RQ3 periodic + composed pipeline
//! battery. Grid hardness router (Q38 analog of hardness_router.zig) chooses ONE path per
//! target — no manual family hints, no Walsh / full operator menu.
//!
//! Routes:
//!   • xor_popcount(mask)   — minimal GF(2) readout (RQ2)
//!   • mod_synthesis        — scalar depth≤4 over {count,inv,sum} (RQ3)
//!   • pipeline             — composed inner₁→inner₂ (E5)
//!
//! Pass bar: ≥80% solved (held-out ≥0.90); ≤20% wrong-route waste; closes oracle-only
//! without full Walsh.
//!
//! Run: zig build open-invention-e14 --release=fast

const std = @import("std");
const e2 = @import("open_invention_e2.zig");
const hr = @import("hardness_router.zig");

const NCELL: usize = 8;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = e2.NSAMP;
const NTR: usize = e2.NTR;
const NVA: usize = e2.NVA;
const COVER: f64 = e2.FORGE_THRESH;
const MONO_SATURATE: f64 = 0.55;
const SINGLE_SUFFICIENT: f64 = 0.70;
const PASS_SOLVE_FRAC: f64 = 0.80;
const PASS_WASTE_FRAC: f64 = 0.20;
const NTOTAL: usize = 50;
const E2_SEED: u64 = e2.RNG_SEED;
const RQ3_SEED: u64 = 0xE3A801CEF00D33;
const COMPOSED_SEED: u64 = 0xE14C0FFEE140629;
const E14_SEED: u64 = 0xE14C0FFEE140629;

pub const ForgeRoute = enum {
    monomial_sufficient,
    xor_popcount,
    mod_synthesis,
    pipeline,
};

pub const E14Summary = struct {
    n_targets: usize,
    solved: usize,
    wrong_route: usize,
    waste_frac: f64,
    solve_frac: f64,
    pass: bool,
};

const HardnessProbe = struct {
    mono_best: f64,
    mono_mask: u8,
    extremal_best: f64,
    extremal_tag: []const u8,
    task_class: hr.TaskClass,
};

const RouteProbe = struct {
    xor_val: f64,
    synth_val: f64,
    pipe_val: f64,
};

const TargetKind = enum {
    e2_adversarial,
    rq3_periodic,
    composed,
};

const Rq3Kind = enum {
    count_mod,
    count_mod_res,
    count_mod_thresh,
    sum_mod,
    sign_mod,
    inv_mod,
    inv_mod_res,
    max_mod,
    affine_mod,
};

const Rq3Target = struct {
    name: []const u8,
    kind: Rq3Kind,
    modulus: usize = 0,
    residue: usize = 0,
    thresh: u8 = THRESH,
    affine_a: usize = 1,
    affine_b: usize = 0,
};

const RQ3_TARGETS = [_]Rq3Target{
    .{ .name = "T01 count%3==0", .kind = .count_mod, .modulus = 3 },
    .{ .name = "T02 count%5==0", .kind = .count_mod, .modulus = 5 },
    .{ .name = "T03 count%6==0", .kind = .count_mod, .modulus = 6 },
    .{ .name = "T04 count%4==0", .kind = .count_mod, .modulus = 4 },
    .{ .name = "T05 count%5==1", .kind = .count_mod_res, .modulus = 5, .residue = 1 },
    .{ .name = "T06 count%8==0", .kind = .count_mod, .modulus = 8 },
    .{ .name = "T07 sum%7==0", .kind = .sum_mod, .modulus = 7 },
    .{ .name = "T08 sum%5==0", .kind = .sum_mod, .modulus = 5 },
    .{ .name = "T09 sign%5==0", .kind = .sign_mod, .modulus = 5 },
    .{ .name = "T10 sign%3==0", .kind = .sign_mod, .modulus = 3 },
    .{ .name = "T11 inv%3==0", .kind = .inv_mod, .modulus = 3 },
    .{ .name = "T12 inv%5==0", .kind = .inv_mod, .modulus = 5 },
    .{ .name = "T13 inv%2==1", .kind = .inv_mod_res, .modulus = 2, .residue = 1 },
    .{ .name = "T14 count@t=2 %3==0", .kind = .count_mod_thresh, .modulus = 3, .thresh = 2 },
    .{ .name = "T15 count@t=4 %3==0", .kind = .count_mod_thresh, .modulus = 3, .thresh = 4 },
    .{ .name = "T16 inv%6==0", .kind = .inv_mod, .modulus = 6 },
    .{ .name = "T17 max%3==0", .kind = .max_mod, .modulus = 3 },
    .{ .name = "T18 sign%7==0", .kind = .sign_mod, .modulus = 7 },
    .{ .name = "T19 (sum+count)%7==0", .kind = .affine_mod, .modulus = 7, .affine_a = 1, .affine_b = 1 },
    .{ .name = "T20 count%10==0", .kind = .count_mod, .modulus = 10 },
};

const ComposedKind = enum {
    inversion_parity,
    product_bind,
    oriented,
    parity_and_sum,
    max_parity,
    rank2_eq1,
};

const ComposedTarget = struct {
    name: []const u8,
    kind: ComposedKind,
    modulus: usize = 7,
};

const COMPOSED_TARGETS = [_]ComposedTarget{
    .{ .name = "C01 inv parity", .kind = .inversion_parity },
    .{ .name = "C02 product bind", .kind = .product_bind },
    .{ .name = "C03 oriented", .kind = .oriented },
    .{ .name = "C04 parity∧sum%7", .kind = .parity_and_sum, .modulus = 7 },
    .{ .name = "C05 max parity", .kind = .max_parity },
    .{ .name = "C06 rank2==1", .kind = .rank2_eq1 },
};

const BatteryEntry = struct {
    name: []const u8,
    name_owned: ?[]const u8 = null,
    kind: TargetKind,
    e2_spec: ?e2.PredSpec = null,
    rq3: ?Rq3Target = null,
    composed: ?ComposedTarget = null,
    oracle_family: []const u8,
};

// ── Grid helpers ─────────────────────────────────────────────────────────────

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn countGE3(g: [NCELL]u8) f64 {
    return countGE(g, THRESH);
}

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
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        if (g[i] > g[j]) inv += 1;
    };
    return inv;
}

fn maxCell(g: [NCELL]u8) u8 {
    var m: u8 = 0;
    for (g) |v| m = @max(m, v);
    return m;
}

fn maxCellF(g: [NCELL]u8) f64 {
    return @floatFromInt(maxCell(g));
}

fn phiMono(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - MID);
    }
    return p;
}

fn oriented(g: [NCELL]u8) f64 {
    return if (g[1] > g[0]) 1.0 else 0.0;
}

fn cliffordG2(g: [NCELL]u8) f64 {
    return @sin(0.40 * (@as(f64, @floatFromInt(g[1])) - @as(f64, @floatFromInt(g[0]))));
}

fn rank2Triple(a: u8, b: u8, c: u8) u8 {
    var s = [_]u8{ a, b, c };
    std.sort.pdq(u8, &s, {}, std.sort.asc(u8));
    return s[1];
}

fn rq3Label(g: [NCELL]u8, t: Rq3Target) f64 {
    return switch (t.kind) {
        .count_mod => if (@as(usize, @intFromFloat(countGE(g, THRESH))) % t.modulus == 0) 1.0 else 0.0,
        .count_mod_res => if (@as(usize, @intFromFloat(countGE(g, THRESH))) % t.modulus == t.residue) 1.0 else 0.0,
        .count_mod_thresh => if (@as(usize, @intFromFloat(countGE(g, t.thresh))) % t.modulus == 0) 1.0 else 0.0,
        .sum_mod => if (gridSum(g) % t.modulus == 0) 1.0 else 0.0,
        .sign_mod => if (@as(usize, signPattern(g)) % t.modulus == 0) 1.0 else 0.0,
        .inv_mod => if (inversionCount(g) % t.modulus == 0) 1.0 else 0.0,
        .inv_mod_res => if (inversionCount(g) % t.modulus == t.residue) 1.0 else 0.0,
        .max_mod => if (@as(usize, maxCell(g)) % t.modulus == 0) 1.0 else 0.0,
        .affine_mod => blk: {
            const c = @as(usize, @intFromFloat(countGE(g, THRESH)));
            const s = gridSum(g);
            break :blk if ((t.affine_a * s + t.affine_b * c) % t.modulus == 0) 1.0 else 0.0;
        },
    };
}

fn composedLabel(g: [NCELL]u8, t: ComposedTarget) f64 {
    return switch (t.kind) {
        .inversion_parity => @floatFromInt(inversionCount(g) & 1),
        .product_bind => if (@as(usize, g[0]) * g[1] > 12) 1.0 else 0.0,
        .oriented => if (g[1] > g[0]) 1.0 else 0.0,
        .parity_and_sum => blk: {
            const c = @as(usize, @intFromFloat(countGE(g, THRESH))) & 1;
            const sm = gridSum(g) % t.modulus == 0;
            break :blk if (c == 1 and sm) 1.0 else 0.0;
        },
        .max_parity => @floatFromInt(@as(usize, maxCell(g)) & 1),
        .rank2_eq1 => if (rank2Triple(g[0], g[1], g[2]) == 1) 1.0 else 0.0,
    };
}

fn oracleFamily(entry: BatteryEntry) []const u8 {
    if (entry.e2_spec) |spec| {
        return switch (spec.kind) {
            .xor_cells, .parity_xor => "xor_popcount",
            .sum_mod, .sign_mod => "mod_synthesis",
            .monomial_sign => "monomial",
            .parity_count => "mod_synthesis",
            .rank_stat => "pipeline",
        };
    }
    if (entry.rq3 != null) return "mod_synthesis";
    if (entry.composed) |c| {
        return switch (c.kind) {
            .inversion_parity, .product_bind, .parity_and_sum, .rank2_eq1 => "pipeline",
            .oriented, .max_parity => "mod_synthesis",
        };
    }
    return "unknown";
}

// ── ML helpers ───────────────────────────────────────────────────────────────

fn fitLogit1(feat: []const f64, Y: []const f64, w: *[2]f64) void {
    fitLogit1Epochs(feat, Y, w, 80);
}

fn fitLogit1Fast(feat: []const f64, Y: []const f64, w: *[2]f64) void {
    fitLogit1Epochs(feat, Y, w, 12);
}

fn fitLogit1Epochs(feat: []const f64, Y: []const f64, w: *[2]f64, epochs: usize) void {
    w.* = .{ 0.0, 0.0 };
    for (0..epochs) |_| for (0..NTR) |s| {
        const e = sigmoid(w[0] * feat[s] + w[1]) - Y[s];
        w[0] -= 0.1 * e * feat[s];
        w[1] -= 0.1 * e;
    };
}

fn accLogit1(feat: []const f64, Y: []const f64, w: [2]f64, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        if ((w[0] * feat[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

fn fitLogitMulti(X: []const []f64, Y: []const f64, dim: usize, w: []f64) void {
    fitLogitMultiEpochs(X, Y, dim, w, 120);
}

fn fitLogitMultiFast(X: []const []f64, Y: []const f64, dim: usize, w: []f64) void {
    fitLogitMultiEpochs(X, Y, dim, w, 20);
}

fn fitLogitMultiEpochs(X: []const []f64, Y: []const f64, dim: usize, w: []f64, epochs: usize) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= 0.05 * e * X[s][j];
        w[dim] -= 0.05 * e;
    };
}

fn accLogitMulti(X: []const []f64, Y: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
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

// ── Hardness router (grid ML analog of hardness_router.zig) ─────────────────

fn classifySubstrateHardness(mono_best: f64, extremal_best: f64) hr.TaskClass {
    if (mono_best >= SINGLE_SUFFICIENT or extremal_best >= SINGLE_SUFFICIENT) return .single_sufficient;
    if (mono_best <= MONO_SATURATE and extremal_best <= MONO_SATURATE) return .q38_compound;
    return .unknown;
}

fn probeMonomialHardness(grid: []const [NCELL]u8, Y: []const f64, feat: []f64) struct { best: f64, mask: u8 } {
    var best: f64 = 0.5;
    var best_mask: u8 = 0;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        const d = @popCount(mask);
        if (d < 1 or d > 4) continue;
        for (0..NSAMP) |s| feat[s] = phiMono(grid[s], mask);
        const v = accLogit1(feat, Y, .{ 1.0, 0.0 }, NTR, NVA);
        if (v > best) {
            best = v;
            best_mask = mask;
        }
    }
    return .{ .best = best, .mask = best_mask };
}

fn probeExtremalHardness(grid: []const [NCELL]u8, Y: []const f64, feat: []f64) struct { best: f64, tag: []const u8 } {
    const probes = [_]struct { tag: []const u8, fill: *const fn ([NCELL]u8) f64 }{
        .{ .tag = "max_cell", .fill = maxCellF },
        .{ .tag = "oriented", .fill = oriented },
        .{ .tag = "countGE", .fill = countGE3 },
        .{ .tag = "clifford_g2", .fill = cliffordG2 },
    };
    var best: f64 = 0.5;
    var best_tag: []const u8 = "none";
    for (probes) |p| {
        for (0..NSAMP) |s| feat[s] = p.fill(grid[s]);
        const v = accLogit1(feat, Y, .{ 1.0, 0.0 }, NTR, NVA);
        if (v > best) {
            best = v;
            best_tag = p.tag;
        }
    }
    return .{ .best = best, .tag = best_tag };
}

fn probeHardness(grid: []const [NCELL]u8, Y: []const f64, feat: []f64) HardnessProbe {
    const mono = probeMonomialHardness(grid, Y, feat);
    const ext = probeExtremalHardness(grid, Y, feat);
    return .{
        .mono_best = mono.best,
        .mono_mask = mono.mask,
        .extremal_best = ext.best,
        .extremal_tag = ext.tag,
        .task_class = classifySubstrateHardness(mono.best, ext.best),
    };
}

fn taskClassName(tc: hr.TaskClass) []const u8 {
    return switch (tc) {
        .single_sufficient => "single_sufficient",
        .q38_compound => "q38_compound",
        .unknown => "unknown",
    };
}

fn routeName(r: ForgeRoute) []const u8 {
    return switch (r) {
        .monomial_sufficient => "monomial_sufficient",
        .xor_popcount => "xor_popcount",
        .mod_synthesis => "mod_synthesis",
        .pipeline => "pipeline",
    };
}

/// Q38 compound + route probe scores → pick xor vs mod synth vs pipeline (no hints).
pub fn chooseRoute(probe: HardnessProbe, scores: RouteProbe) ForgeRoute {
    if (probe.mono_best >= COVER) return .monomial_sufficient;

    if (probe.task_class == .q38_compound) {
        // Q38 compound: GF(2) xor probe wins when above chance (E2 XOR-family pattern).
        if (scores.xor_val > MONO_SATURATE and scores.xor_val >= scores.synth_val - 0.05)
            return .xor_popcount;
        if (scores.pipe_val > scores.synth_val and scores.pipe_val > MONO_SATURATE)
            return .pipeline;
        return .mod_synthesis;
    }

    if (std.mem.eql(u8, probe.extremal_tag, "countGE") or std.mem.eql(u8, probe.extremal_tag, "max_cell")) {
        if (scores.synth_val >= scores.pipe_val and scores.synth_val >= scores.xor_val)
            return .mod_synthesis;
    }

    if (scores.pipe_val > @max(scores.synth_val, scores.xor_val) and scores.pipe_val > MONO_SATURATE)
        return .pipeline;
    if (scores.synth_val >= scores.xor_val)
        return .mod_synthesis;
    if (scores.xor_val > MONO_SATURATE)
        return .xor_popcount;
    return .mod_synthesis;
}

// ── Route probe scores (validation only) ─────────────────────────────────────

fn probeXorRoute(grid: []const [NCELL]u8, Y: []const f64, scratch: []f64) f64 {
    var best: f64 = 0.5;
    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        for (0..NSAMP) |s| scratch[s] = e2.xorPopcountReadout(grid[s], mask);
        var w: [2]f64 = .{ 1.0, 0.0 };
        fitLogit1Fast(scratch, Y, &w);
        const v = accLogit1(scratch, Y, w, NTR, NVA);
        if (v > best) best = v;
    }
    return best;
}

const Leaf = enum { count3, count2, count4, inv, sum };

const ScalarCtx = struct {
    count3: f64,
    count2: f64,
    count4: f64,
    inv: f64,
    sum: f64,

    fn leafVal(self: ScalarCtx, leaf: Leaf) f64 {
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
    leaf: Leaf,
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

    const leaves = [_]Leaf{ .count3, .count2, .count4, .inv, .sum };
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

fn probeSynthRoute(grid: []const [NCELL]u8, Y: []const f64, bank: ProgBank, scratch: []f64) f64 {
    var best: f64 = 0.5;
    var ctxs = [_]ScalarCtx{undefined} ** NSAMP;
    for (0..NSAMP) |s| ctxs[s] = ScalarCtx.fromGrid(grid[s]);
    for (1..bank.nodes.len) |pid| {
        if (bank.depth(@intCast(pid)) > 3) continue;
        for (0..NSAMP) |s| scratch[s] = bank.eval(@intCast(pid), ctxs[s]);
        var w: [2]f64 = .{ 1.0, 0.0 };
        fitLogit1Fast(scratch, Y, &w);
        const v = accLogit1(scratch, Y, w, NTR, NVA);
        if (v > best) best = v;
    }
    return best;
}

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
        .max_cell => @floatFromInt(maxCell(g)),
        .min01 => @floatFromInt(@min(g[0], g[1])),
        .mean01 => @as(f64, @floatFromInt(g[0] + g[1])) / 2.0,
    };
}

fn fillLinear(_: usize, S: f64, _: [NCELL]u8, out: []f64) void {
    out[0] = S;
}
fn fillHalfP(_: usize, S: f64, _: [NCELL]u8, out: []f64) void {
    out[0] = @floatFromInt(@as(usize, @intFromFloat(@round(S))) & 1);
}
fn fillBindXy(_: usize, _: f64, g: [NCELL]u8, out: []f64) void {
    out[0] = @as(f64, @floatFromInt(g[0])) * @as(f64, @floatFromInt(g[1]));
}

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

fn evalPipelineAcc(
    _: Inner1,
    in2: Inner2,
    S: []const f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    X: [][]f64,
    w: []f64,
) f64 {
    if (in2 == .linear) {
        for (0..NSAMP) |s| X[s][0] = S[s];
        standardize(X, 1);
        fitLogitMultiFast(X, Y, 1, w);
        return accLogitMulti(X, Y, w, 1, NTR, NVA);
    }
    if (in2 == .scan_p) {
        var best_val: f64 = -1;
        var best_w: f64 = std.math.pi;
        for (1..64) |fi| {
            const omega = @as(f64, @floatFromInt(fi)) * std.math.pi / 64.0;
            const ab = fitCosFeat(S, Y, omega);
            var c: usize = 0;
            for (NTR..NVA) |s| {
                if ((ab[0] * @cos(omega * S[s]) + ab[1] >= 0) == (Y[s] > 0.5)) c += 1;
            }
            const v = @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NVA - NTR));
            if (v > best_val) {
                best_val = v;
                best_w = omega;
            }
        }
        for (0..NSAMP) |s| {
            X[s][0] = S[s];
            X[s][1] = @cos(best_w * S[s]);
        }
        standardize(X, 2);
        fitLogitMultiFast(X, Y, 2, w);
        return accLogitMulti(X, Y, w, 2, NTR, NVA);
    }
    const dim: usize = 2;
    for (0..NSAMP) |s| {
        X[s][0] = S[s];
        switch (in2) {
            .half_p => fillHalfP(s, S[s], grid[s], X[s][1..2]),
            .bind_xy => fillBindXy(s, S[s], grid[s], X[s][1..2]),
            .bind_abs => X[s][1] = @abs(@as(f64, @floatFromInt(grid[s][0])) - @as(f64, @floatFromInt(grid[s][1]))),
            .bind_max => X[s][1] = @floatFromInt(@max(grid[s][0], grid[s][1])),
            else => X[s][1] = S[s],
        }
    }
    standardize(X, dim);
    fitLogitMultiFast(X, Y, dim, w);
    return accLogitMulti(X, Y, w, dim, NTR, NVA);
}

fn evalPipelineAccFull(
    _: Inner1,
    in2: Inner2,
    S: []const f64,
    grid: []const [NCELL]u8,
    Y: []const f64,
    X: [][]f64,
    w: []f64,
) f64 {
    if (in2 == .linear) {
        for (0..NSAMP) |s| X[s][0] = S[s];
        standardize(X, 1);
        fitLogitMulti(X, Y, 1, w);
        return accLogitMulti(X, Y, w, 1, NVA, NSAMP);
    }
    if (in2 == .scan_p) {
        var best_val: f64 = -1;
        var best_w: f64 = std.math.pi;
        for (1..64) |fi| {
            const omega = @as(f64, @floatFromInt(fi)) * std.math.pi / 64.0;
            const ab = fitCosFeat(S, Y, omega);
            var c: usize = 0;
            for (NTR..NVA) |s| {
                if ((ab[0] * @cos(omega * S[s]) + ab[1] >= 0) == (Y[s] > 0.5)) c += 1;
            }
            const v = @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NVA - NTR));
            if (v > best_val) {
                best_val = v;
                best_w = omega;
            }
        }
        for (0..NSAMP) |s| {
            X[s][0] = S[s];
            X[s][1] = @cos(best_w * S[s]);
        }
        standardize(X, 2);
        fitLogitMulti(X, Y, 2, w);
        return accLogitMulti(X, Y, w, 2, NVA, NSAMP);
    }
    const dim: usize = 2;
    for (0..NSAMP) |s| {
        X[s][0] = S[s];
        switch (in2) {
            .half_p => fillHalfP(s, S[s], grid[s], X[s][1..2]),
            .bind_xy => fillBindXy(s, S[s], grid[s], X[s][1..2]),
            .bind_abs => X[s][1] = @abs(@as(f64, @floatFromInt(grid[s][0])) - @as(f64, @floatFromInt(grid[s][1]))),
            .bind_max => X[s][1] = @floatFromInt(@max(grid[s][0], grid[s][1])),
            else => X[s][1] = S[s],
        }
    }
    standardize(X, dim);
    fitLogitMulti(X, Y, dim, w);
    return accLogitMulti(X, Y, w, dim, NVA, NSAMP);
}

const PIPE_PROBE_IN1 = [_]Inner1{ .count, .inversion, .sum01, .sum_all };
const PIPE_PROBE_IN2 = [_]Inner2{ .linear, .half_p, .scan_p, .bind_xy, .lift_q };

fn probePipelineRoute(grid: []const [NCELL]u8, Y: []const f64, S_all: *const [N_INNER1][]f64, X: [][]f64, w: []f64) f64 {
    var best: f64 = 0.5;
    for (PIPE_PROBE_IN1) |in1| {
        const S = S_all[@intFromEnum(in1)];
        for (PIPE_PROBE_IN2) |in2| {
            const v = evalPipelineAcc(in1, in2, S, grid, Y, X, w);
            if (v > best) best = v;
        }
    }
    return best;
}

// ── Route solvers (held-out test) ────────────────────────────────────────────

fn solveMonomial(grid: []const [NCELL]u8, Y: []const f64, mask: u8, feat: []f64) f64 {
    for (0..NSAMP) |s| feat[s] = phiMono(grid[s], mask);
    var w: [2]f64 = .{ 1.0, 0.0 };
    fitLogit1(feat, Y, &w);
    return accLogit1(feat, Y, w, NVA, NSAMP);
}

fn solveXorRoute(grid: []const [NCELL]u8, Y: []const f64, scratch: []f64) f64 {
    var best_mask: u8 = 1;
    var best_val: f64 = -1;
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
    for (0..NSAMP) |s| scratch[s] = e2.xorPopcountReadout(grid[s], best_mask);
    var w: [2]f64 = .{ 1.0, 0.0 };
    fitLogit1(scratch, Y, &w);
    return accLogit1(scratch, Y, w, NVA, NSAMP);
}

fn solveSynthRoute(grid: []const [NCELL]u8, Y: []const f64, bank: ProgBank, scratch: []f64) f64 {
    var best_id: u16 = 0;
    var best_val: f64 = -1;
    var ctxs = [_]ScalarCtx{undefined} ** NSAMP;
    for (0..NSAMP) |s| ctxs[s] = ScalarCtx.fromGrid(grid[s]);
    for (1..bank.nodes.len) |pid| {
        if (bank.depth(@intCast(pid)) > 4) continue;
        for (0..NSAMP) |s| scratch[s] = bank.eval(@intCast(pid), ctxs[s]);
        var w: [2]f64 = .{ 1.0, 0.0 };
        fitLogit1(scratch, Y, &w);
        const v = accLogit1(scratch, Y, w, NTR, NVA);
        if (v > best_val) {
            best_val = v;
            best_id = @intCast(pid);
        }
    }
    for (0..NSAMP) |s| scratch[s] = bank.eval(best_id, ctxs[s]);
    var w: [2]f64 = .{ 1.0, 0.0 };
    fitLogit1(scratch, Y, &w);
    return accLogit1(scratch, Y, w, NVA, NSAMP);
}

fn solvePipelineRoute(grid: []const [NCELL]u8, Y: []const f64, S_all: *const [N_INNER1][]f64, X: [][]f64, w: []f64) f64 {
    var best_val: f64 = -1;
    var best_i1: Inner1 = .count;
    var best_i2: Inner2 = .linear;
    for (0..N_INNER1) |i1i| {
        const in1: Inner1 = @enumFromInt(i1i);
        for (0..N_INNER2) |i2i| {
            const in2: Inner2 = @enumFromInt(i2i);
            const v = evalPipelineAcc(in1, in2, S_all[i1i], grid, Y, X, w);
            if (v > best_val) {
                best_val = v;
                best_i1 = in1;
                best_i2 = in2;
            }
        }
    }
    return evalPipelineAccFull(best_i1, best_i2, S_all[@intFromEnum(best_i1)], grid, Y, X, w);
}

fn oracleBestRoute(
    grid: []const [NCELL]u8,
    Y: []const f64,
    probe: HardnessProbe,
    bank: ProgBank,
    S_all: *const [N_INNER1][]f64,
    feat: []f64,
    scratch: []f64,
    X: [][]f64,
    w: []f64,
) struct { route: ForgeRoute, acc: f64 } {
    const mono = solveMonomial(grid, Y, probe.mono_mask, feat);
    const xor = solveXorRoute(grid, Y, scratch);
    const synth = solveSynthRoute(grid, Y, bank, scratch);
    const pipe = solvePipelineRoute(grid, Y, S_all, X, w);

    var best_route: ForgeRoute = .monomial_sufficient;
    var best_acc: f64 = mono;
    if (xor > best_acc) {
        best_acc = xor;
        best_route = .xor_popcount;
    }
    if (synth > best_acc) {
        best_acc = synth;
        best_route = .mod_synthesis;
    }
    if (pipe > best_acc) {
        best_acc = pipe;
        best_route = .pipeline;
    }
    return .{ .route = best_route, .acc = best_acc };
}

fn runRoutedSolve(
    route: ForgeRoute,
    grid: []const [NCELL]u8,
    Y: []const f64,
    probe: HardnessProbe,
    bank: ProgBank,
    S_all: *const [N_INNER1][]f64,
    feat: []f64,
    scratch: []f64,
    X: [][]f64,
    w: []f64,
) f64 {
    return switch (route) {
        .monomial_sufficient => solveMonomial(grid, Y, probe.mono_mask, feat),
        .xor_popcount => solveXorRoute(grid, Y, scratch),
        .mod_synthesis => solveSynthRoute(grid, Y, bank, scratch),
        .pipeline => solvePipelineRoute(grid, Y, S_all, X, w),
    };
}

// ── Battery assembly ─────────────────────────────────────────────────────────

fn buildBattery(alloc: std.mem.Allocator, e2_pool: e2.AdversarialPool) ![]BatteryEntry {
    var list = std.ArrayList(BatteryEntry).init(alloc);
    const n_e2 = @min(24, e2_pool.kept.len);
    for (0..n_e2) |i| {
        var buf: [64]u8 = undefined;
        const spec = e2_pool.kept[i].spec;
        const nm = try alloc.dupe(u8, spec.fmt(&buf));
        const entry = BatteryEntry{
            .name = nm,
            .name_owned = nm,
            .kind = .e2_adversarial,
            .e2_spec = spec,
            .oracle_family = oracleFamily(.{ .name = nm, .kind = .e2_adversarial, .e2_spec = spec, .oracle_family = "" }),
        };
        try list.append(entry);
    }
    for (RQ3_TARGETS) |t| {
        try list.append(.{
            .name = t.name,
            .kind = .rq3_periodic,
            .rq3 = t,
            .oracle_family = "mod_synthesis",
        });
    }
    for (COMPOSED_TARGETS) |t| {
        try list.append(.{
            .name = t.name,
            .kind = .composed,
            .composed = t,
            .oracle_family = oracleFamily(.{ .name = "", .kind = .composed, .composed = t, .oracle_family = "" }),
        });
    }
    return try list.toOwnedSlice();
}

fn fillLabels(grid: []const [NCELL]u8, entry: BatteryEntry, Y: []f64) void {
    for (0..NSAMP) |s| {
        Y[s] = switch (entry.kind) {
            .e2_adversarial => e2.label(grid[s], entry.e2_spec.?),
            .rq3_periodic => rq3Label(grid[s], entry.rq3.?),
            .composed => composedLabel(grid[s], entry.composed.?),
        };
    }
}

// ── Main experiment ──────────────────────────────────────────────────────────

pub fn runExperiment(alloc: std.mem.Allocator, out: anytype) !E14Summary {
    try out.print("=== EXPERIMENT E14: Hardness-routed open invention ===\n\n", .{});
    try out.print("Question: Q38 compound detection → xor_popcount vs mod synthesis vs pipeline?\n", .{});
    try out.print("Battery: E2 adversarial (24) + RQ3 periodic (20) + composed (6) = {d} targets\n", .{NTOTAL});
    try out.print("Router: grid hardness probe (hardness_router.zig Q38 analog); NO Walsh menu.\n", .{});
    try out.print("PASS: solve≥{d:.0}% AND wrong-route waste≤{d:.0}%\n\n", .{ PASS_SOLVE_FRAC * 100, PASS_WASTE_FRAC * 100 });

    const null_out = std.io.null_writer;
    const e2_pool = try e2.collectAdversarialPool(alloc, null_out, E2_SEED);
    const battery = try buildBattery(alloc, e2_pool);

    const bank = try buildProgBank(alloc);

    var prng_rq3 = std.Random.DefaultPrng.init(RQ3_SEED);
    const rq3_grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        rq3_grid[s][i] = prng_rq3.random().intRangeAtMost(u8, 0, 5);
    };

    var prng_comp = std.Random.DefaultPrng.init(COMPOSED_SEED);
    const composed_grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        composed_grid[s][i] = prng_comp.random().intRangeAtMost(u8, 0, 5);
    };

    const feat = try alloc.alloc(f64, NSAMP);
    const scratch = try alloc.alloc(f64, NSAMP);
    const Y = try alloc.alloc(f64, NSAMP);
    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, 4);
    var w: [8]f64 = undefined;

    var S_storage = [_][]f64{undefined} ** N_INNER1;
    for (0..N_INNER1) |i| S_storage[i] = try alloc.alloc(f64, NSAMP);

    var solved: usize = 0;
    var wrong_route: usize = 0;
    var routed_xor: usize = 0;
    var routed_synth: usize = 0;
    var routed_pipe: usize = 0;
    var routed_mono: usize = 0;
    var q38_count: usize = 0;

    try out.print("── Per-target routing (held-out test) ──\n\n", .{});

    for (battery, 0..) |entry, idx| {
        const grid = switch (entry.kind) {
            .e2_adversarial => e2_pool.grid,
            .rq3_periodic => rq3_grid,
            .composed => composed_grid,
        };
        fillLabels(grid, entry, Y);

        for (0..N_INNER1) |i1i| {
            const in1: Inner1 = @enumFromInt(i1i);
            for (0..NSAMP) |s| S_storage[i1i][s] = inner1Scalar(in1, grid[s]);
        }

        const probe = probeHardness(grid, Y, feat);
        if (probe.task_class == .q38_compound) q38_count += 1;

        const route = if (probe.mono_best >= COVER) .monomial_sufficient else blk: {
            const scores = RouteProbe{
                .xor_val = probeXorRoute(grid, Y, scratch),
                .synth_val = probeSynthRoute(grid, Y, bank, scratch),
                .pipe_val = probePipelineRoute(grid, Y, &S_storage, X, &w),
            };
            break :blk chooseRoute(probe, scores);
        };
        switch (route) {
            .monomial_sufficient => routed_mono += 1,
            .xor_popcount => routed_xor += 1,
            .mod_synthesis => routed_synth += 1,
            .pipeline => routed_pipe += 1,
        }

        const routed_acc = runRoutedSolve(route, grid, Y, probe, bank, &S_storage, feat, scratch, X, &w);

        const cert = routed_acc >= COVER;
        if (cert) solved += 1;

        var oracle_route: ForgeRoute = route;
        var oracle_acc: f64 = routed_acc;
        var misrouted = false;
        if (!cert) {
            const oracle = oracleBestRoute(grid, Y, probe, bank, &S_storage, feat, scratch, X, &w);
            oracle_route = oracle.route;
            oracle_acc = oracle.acc;
            misrouted = oracle.acc >= COVER and route != oracle.route;
            if (misrouted) wrong_route += 1;
        }

        const tag: []const u8 = if (cert) " *" else if (misrouted) " WRONG-ROUTE" else "";
        try out.print("  #{d:0>2} {s}: class={s} route={s} test={d:.3} oracle={s}/{d:.3} fam={s}{s}\n", .{
            idx + 1,
            entry.name,
            taskClassName(probe.task_class),
            routeName(route),
            routed_acc,
            routeName(oracle_route),
            oracle_acc,
            entry.oracle_family,
            tag,
        });
    }

    const n = battery.len;
    const solve_frac = @as(f64, @floatFromInt(solved)) / @as(f64, @floatFromInt(n));
    const waste_frac = @as(f64, @floatFromInt(wrong_route)) / @as(f64, @floatFromInt(n));
    const pass = solve_frac >= PASS_SOLVE_FRAC and waste_frac <= PASS_WASTE_FRAC;

    try out.print("\n════════════════════ SUMMARY ════════════════════\n", .{});
    try out.print("  targets:           {d}\n", .{n});
    try out.print("  Q38 compound:      {d}\n", .{q38_count});
    try out.print("  routes: mono={d} xor={d} synth={d} pipe={d}\n", .{ routed_mono, routed_xor, routed_synth, routed_pipe });
    try out.print("  solved (≥{d:.2}):   {d}/{d} ({d:.1}%)\n", .{ COVER, solved, n, solve_frac * 100 });
    try out.print("  wrong-route waste: {d}/{d} ({d:.1}%)\n\n", .{ wrong_route, n, waste_frac * 100 });

    try out.print("VERDICT: ", .{});
    if (pass) {
        try out.print("PASS — hardness router closes held-out battery without Walsh.\n", .{});
    } else if (solve_frac >= PASS_SOLVE_FRAC) {
        try out.print("PARTIAL — solve bar met but wrong-route waste {d:.1}% > {d:.0}%.\n", .{ waste_frac * 100, PASS_WASTE_FRAC * 100 });
    } else if (waste_frac <= PASS_WASTE_FRAC) {
        try out.print("PARTIAL — waste OK but solve {d:.1}% < {d:.0}%.\n", .{ solve_frac * 100, PASS_SOLVE_FRAC * 100 });
    } else {
        try out.print("FAIL — solve {d:.1}% and waste {d:.1}% miss bars.\n", .{ solve_frac * 100, waste_frac * 100 });
    }

    try out.print("\nE14_RESULT pass={} solve={d}/{d} waste={d}/{d} seed=0x{X:0>16}\n", .{
        pass, solved, n, wrong_route, n, E14_SEED,
    });
    try out.print("See: open_invention_e14.md, hardness_router.zig, open_invention_rq2.md, open_invention_rq3.md\n", .{});

    return .{
        .n_targets = n,
        .solved = solved,
        .wrong_route = wrong_route,
        .waste_frac = waste_frac,
        .solve_frac = solve_frac,
        .pass = pass,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    _ = try runExperiment(arena.allocator(), std.io.getStdOut().writer());
}