//! RESEARCH Q3 — E3 extended: 20 non-parity periodic/composed targets (synthesis only).
//!
//! Extends E3 (no spectral/Walsh) with a held-out battery of multi-period, inversion-count,
//! threshold-variant, and composed-mod predicates. Forge menu:
//!   monomials, threshold signs, sums, min/max, rank statistics, scalar synthesis
//!   depth≤4 over {+,×,mod,sin} on {count₃,count₂,count₄,inv,sum}.
//!
//! PASS bar: ≥3/20 certified (held-out ≥0.90) with escape feature NOT equivalent to a
//! simple monomial (φ_S or χ_S only).
//!
//! Run: zig build open-invention-rq3 --release=fast

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const MAXATOMS: usize = 56;
const MAXDEG: usize = 4;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;
const PASS_NON_MONO: usize = 3;
const RNG_SEED: u64 = 0xE3A801CEF00D33;
const NT: usize = 20;

const AtomKind = enum {
    monomial,
    thresh_mono,
    thresh_bit,
    sum_all,
    sum_pair,
    sum_triple,
    count_feat,
    inv_count_feat,
    max_all_feat,
    min_pair,
    max_pair,
    min_triple,
    max_triple,
    median_eq1,
    rank2_eq1,
    synth_prog,
};

const Atom = struct {
    kind: AtomKind,
    data: u32,
    prog_id: u16 = 0,

    fn label(self: Atom, buf: []u8, prog_names: []const []const u8) []const u8 {
        return switch (self.kind) {
            .monomial => std.fmt.bufPrint(buf, "mono 0x{X:0>2}", .{@as(u8, @intCast(self.data))}) catch "?",
            .thresh_mono => std.fmt.bufPrint(buf, "χ_mono 0x{X:0>2}", .{@as(u8, @intCast(self.data))}) catch "?",
            .thresh_bit => std.fmt.bufPrint(buf, "sign(c{d})", .{self.data}) catch "?",
            .sum_all => "Σcells",
            .sum_pair => std.fmt.bufPrint(buf, "sum({d},{d})", .{ self.data / 8, self.data % 8 }) catch "?",
            .sum_triple => blk: {
                const k: usize = @intCast(self.data % 8);
                const j: usize = @intCast((self.data / 8) % 8);
                const i: usize = @intCast(self.data / 64);
                break :blk std.fmt.bufPrint(buf, "sum({d},{d},{d})", .{ i, j, k }) catch "?";
            },
            .count_feat => "count₃",
            .inv_count_feat => "inv_count",
            .max_all_feat => "max_all",
            .min_pair => std.fmt.bufPrint(buf, "min({d},{d})", .{ self.data / 8, self.data % 8 }) catch "?",
            .max_pair => std.fmt.bufPrint(buf, "max({d},{d})", .{ self.data / 8, self.data % 8 }) catch "?",
            .min_triple, .max_triple, .median_eq1, .rank2_eq1 => blk: {
                const k: usize = @intCast(self.data % 8);
                const j: usize = @intCast((self.data / 8) % 8);
                const i: usize = @intCast(self.data / 64);
                const tag: []const u8 = switch (self.kind) {
                    .min_triple => "min3",
                    .max_triple => "max3",
                    .median_eq1 => "med==1",
                    .rank2_eq1 => "rank2==1",
                    else => "?",
                };
                break :blk std.fmt.bufPrint(buf, "{s}({d},{d},{d})", .{ tag, i, j, k }) catch "?";
            },
            .synth_prog => if (self.prog_id < prog_names.len)
                prog_names[self.prog_id]
            else
                "prog?",
        };
    }

    fn isSimpleMonomial(self: Atom) bool {
        return self.kind == .monomial or self.kind == .thresh_mono;
    }
};

const TargetKind = enum {
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

const Target = struct {
    name: []const u8,
    kind: TargetKind,
    modulus: usize = 0,
    residue: usize = 0,
    thresh: u8 = THRESH,
    affine_a: usize = 1,
    affine_b: usize = 0,
};

const TARGETS = [_]Target{
    .{ .name = "T01 count%3==0", .kind = .count_mod, .modulus = 3 },
    .{ .name = "T02 count%5==0", .kind = .count_mod, .modulus = 5 },
    .{ .name = "T03 count%6==0 (lcm 2·3)", .kind = .count_mod, .modulus = 6 },
    .{ .name = "T04 count%4==0", .kind = .count_mod, .modulus = 4 },
    .{ .name = "T05 count%5==1", .kind = .count_mod_res, .modulus = 5, .residue = 1 },
    .{ .name = "T06 count%8==0", .kind = .count_mod, .modulus = 8 },
    .{ .name = "T07 sum%7==0", .kind = .sum_mod, .modulus = 7 },
    .{ .name = "T08 sum%5==0", .kind = .sum_mod, .modulus = 5 },
    .{ .name = "T09 sign%5==0", .kind = .sign_mod, .modulus = 5 },
    .{ .name = "T10 sign%3==0", .kind = .sign_mod, .modulus = 3 },
    .{ .name = "T11 inv%3==0", .kind = .inv_mod, .modulus = 3 },
    .{ .name = "T12 inv%5==0", .kind = .inv_mod, .modulus = 5 },
    .{ .name = "T13 inv parity (inv%2==1)", .kind = .inv_mod_res, .modulus = 2, .residue = 1 },
    .{ .name = "T14 count@t=2 %3==0", .kind = .count_mod_thresh, .modulus = 3, .thresh = 2 },
    .{ .name = "T15 count@t=4 %3==0", .kind = .count_mod_thresh, .modulus = 3, .thresh = 4 },
    .{ .name = "T16 inv%6==0 (lcm 2·3)", .kind = .inv_mod, .modulus = 6 },
    .{ .name = "T17 max(cell)%3==0", .kind = .max_mod, .modulus = 3 },
    .{ .name = "T18 sign%7==0", .kind = .sign_mod, .modulus = 7 },
    .{ .name = "T19 (sum+count)%7==0", .kind = .affine_mod, .modulus = 7, .affine_a = 1, .affine_b = 1 },
    .{ .name = "T20 count%10==0 (lcm 2·5)", .kind = .count_mod, .modulus = 10 },
};

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
}

fn signThresh(v: u8) f64 {
    return if (v >= THRESH) 1.0 else -1.0;
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

fn phiMono(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - MID);
    }
    return p;
}

fn chiMono(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= signThresh(g[i]);
    }
    return p;
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

fn tripleEnc(i: usize, j: usize, k: usize) u32 {
    return @intCast(i * 64 + j * 8 + k);
}

fn targetLabel(g: [NCELL]u8, t: Target) f64 {
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

// ── Scalar synthesis (depth ≤ 4, leaves = count₂/₃/₄, inv, sum) ───────────────

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

fn buildProgBank(alloc: std.mem.Allocator) !ProgBank {
    var nodes = std.ArrayList(ProgNode).init(alloc);
    defer nodes.deinit();
    var depths = std.ArrayList(u8).init(alloc);
    defer depths.deinit();
    var names = std.ArrayList([]const u8).init(alloc);
    defer names.deinit();

    const leaf_tags = [_]struct { leaf: Leaf, tag: []const u8 }{
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

    while (depth_cur <= 4) : (depth_cur += 1) {
        var next_frontier = std.ArrayList(u16).init(alloc);
        defer next_frontier.deinit();

        for (frontier.items) |pid| {
            if (nodes.items.len >= 300) break;
            const base = names.items[pid];
            const sin_nm = try std.fmt.allocPrint(alloc, "sin({s})", .{base});
            try nodes.append(.{ .sin = pid });
            try depths.append(depth_cur);
            try names.append(sin_nm);
            try next_frontier.append(@intCast(nodes.items.len - 1));

            for (2..9) |k| {
                if (nodes.items.len >= 300) break;
                const nm = try std.fmt.allocPrint(alloc, "mod({s},{d})", .{ base, k });
                try nodes.append(.{ .@"mod" = .{ .child = pid, .k = @intCast(k) } });
                try depths.append(depth_cur);
                try names.append(nm);
                try next_frontier.append(@intCast(nodes.items.len - 1));
            }
        }

        const n = nodes.items.len;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                const d = @max(depths.items[i], depths.items[j]) + 1;
                if (d > 4) continue;
                if (nodes.items.len >= 300) break;

                const ai: u16 = @intCast(i);
                const aj: u16 = @intCast(j);
                const bin_ops = [_]struct { node: ProgNode, tag: []const u8 }{
                    .{ .node = .{ .add = .{ .a = ai, .b = aj } }, .tag = "+" },
                    .{ .node = .{ .mul = .{ .a = ai, .b = aj } }, .tag = "*" },
                };
                for (bin_ops) |op| {
                    if (nodes.items.len >= 300) break;
                    const nm = try std.fmt.allocPrint(alloc, "({s}{s}{s})", .{ names.items[i], op.tag, names.items[j] });
                    try nodes.append(op.node);
                    try depths.append(d);
                    try names.append(nm);
                }
            }
        }

        frontier.clearRetainingCapacity();
        for (next_frontier.items) |id| try frontier.append(id);
    }

    return .{
        .nodes = try nodes.toOwnedSlice(),
        .depths = try depths.toOwnedSlice(),
        .names = try names.toOwnedSlice(),
    };
}

fn evalAtom(g: [NCELL]u8, atom: Atom, bank: ProgBank) f64 {
    const ctx = ScalarCtx.fromGrid(g);
    return switch (atom.kind) {
        .monomial => phiMono(g, @intCast(atom.data)),
        .thresh_mono => chiMono(g, @intCast(atom.data)),
        .thresh_bit => signThresh(g[@intCast(atom.data)]),
        .sum_all => blk: {
            var s: u32 = 0;
            for (g) |v| s += v;
            break :blk @as(f64, @floatFromInt(s)) - MID * @as(f64, @floatFromInt(NCELL));
        },
        .sum_pair => blk: {
            const i: usize = @intCast(atom.data / 8);
            const j: usize = @intCast(atom.data % 8);
            break :blk @as(f64, @floatFromInt(g[i] + g[j])) - 2 * MID;
        },
        .sum_triple => blk: {
            const k: usize = @intCast(atom.data % 8);
            const j: usize = @intCast((atom.data / 8) % 8);
            const i: usize = @intCast(atom.data / 64);
            break :blk @as(f64, @floatFromInt(g[i] + g[j] + g[k])) - 3 * MID;
        },
        .count_feat => ctx.count3 - @as(f64, @floatFromInt(NCELL)) / 2.0,
        .inv_count_feat => ctx.inv - @as(f64, @floatFromInt(NCELL * (NCELL - 1) / 2)) / 2.0,
        .max_all_feat => @as(f64, @floatFromInt(maxCell(g))) - MID,
        .min_pair => blk: {
            const i: usize = @intCast(atom.data / 8);
            const j: usize = @intCast(atom.data % 8);
            break :blk @as(f64, @floatFromInt(@min(g[i], g[j]))) - MID;
        },
        .max_pair => blk: {
            const i: usize = @intCast(atom.data / 8);
            const j: usize = @intCast(atom.data % 8);
            break :blk @as(f64, @floatFromInt(@max(g[i], g[j]))) - MID;
        },
        .min_triple => blk: {
            const k: usize = @intCast(atom.data % 8);
            const j: usize = @intCast((atom.data / 8) % 8);
            const i: usize = @intCast(atom.data / 64);
            break :blk @as(f64, @floatFromInt(@min(g[i], @min(g[j], g[k])))) - MID;
        },
        .max_triple => blk: {
            const k: usize = @intCast(atom.data % 8);
            const j: usize = @intCast((atom.data / 8) % 8);
            const i: usize = @intCast(atom.data / 64);
            break :blk @as(f64, @floatFromInt(@max(g[i], @max(g[j], g[k])))) - MID;
        },
        .median_eq1 => blk: {
            const k: usize = @intCast(atom.data % 8);
            const j: usize = @intCast((atom.data / 8) % 8);
            const i: usize = @intCast(atom.data / 64);
            break :blk if (median3vals(g[i], g[j], g[k]) == 1) 1.0 else -1.0;
        },
        .rank2_eq1 => blk: {
            const k: usize = @intCast(atom.data % 8);
            const j: usize = @intCast((atom.data / 8) % 8);
            const i: usize = @intCast(atom.data / 64);
            break :blk if (rank2Triple(g[i], g[j], g[k]) == 1) 1.0 else -1.0;
        },
        .synth_prog => bank.eval(atom.prog_id, ctx),
    };
}

fn atomsEqual(a: Atom, b: Atom) bool {
    return a.kind == b.kind and a.data == b.data and a.prog_id == b.prog_id;
}

fn buildFeat(X: [][]f64, grid: []const [NCELL]u8, atoms: []const Atom, bank: ProgBank) void {
    const ncol = atoms.len;
    for (0..NSAMP) |s| for (0..ncol) |c| {
        X[s][c] = evalAtom(grid[s], atoms[c], bank);
    };
    for (0..ncol) |c| {
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

fn coverage(X: [][]f64, grid: []const [NCELL]u8, atoms: []const Atom, bank: ProgBank, yv: []const f64, w: []f64) f64 {
    buildFeat(X, grid, atoms, bank);
    fitLogit(X, yv, atoms.len, 150, 0.05, w);
    return accLogit(X, yv, w, atoms.len, NVA, NSAMP);
}

fn scoreCandidate(atom: Atom, grid: []const [NCELL]u8, X: [][]f64, Yt: []const f64, bank: ProgBank, w: []f64) f64 {
    const one = [_]Atom{atom};
    buildFeat(X, grid, &one, bank);
    fitLogit(X, Yt, 1, 80, 0.06, w);
    return accLogit(X, Yt, w, 1, NTR, NVA);
}

fn tryCandidate(
    atom: Atom,
    current: []const Atom,
    grid: []const [NCELL]u8,
    X: [][]f64,
    Yt: []const f64,
    bank: ProgBank,
    w: []f64,
    best_val: *f64,
    best: *Atom,
) void {
    for (current) |a| {
        if (atomsEqual(a, atom)) return;
    }
    const v = scoreCandidate(atom, grid, X, Yt, bank, w);
    if (v > best_val.*) {
        best_val.* = v;
        best.* = atom;
    }
}

fn enumerateTriples(current: []const Atom, grid: []const [NCELL]u8, X: [][]f64, Yt: []const f64, bank: ProgBank, w: []f64, best_val: *f64, best: *Atom, kind: AtomKind) void {
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |k| {
        const enc = tripleEnc(i, j, k);
        tryCandidate(.{ .kind = kind, .data = enc }, current, grid, X, Yt, bank, w, best_val, best);
    };
}

fn discoverBest(
    grid: []const [NCELL]u8,
    X: [][]f64,
    Yt: []const f64,
    current: []const Atom,
    bank: ProgBank,
    w: []f64,
    include_synth: bool,
) struct { atom: Atom, val_acc: f64 } {
    var best_val: f64 = -1;
    var best: Atom = .{ .kind = .monomial, .data = 0 };

    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const cand: u8 = @intCast(mm);
        const d = popcount(cand);
        if (d < 1 or d > MAXDEG) continue;
        tryCandidate(.{ .kind = .monomial, .data = cand }, current, grid, X, Yt, bank, w, &best_val, &best);
        tryCandidate(.{ .kind = .thresh_mono, .data = cand }, current, grid, X, Yt, bank, w, &best_val, &best);
    }

    for (0..NCELL) |i| {
        tryCandidate(.{ .kind = .thresh_bit, .data = @intCast(i) }, current, grid, X, Yt, bank, w, &best_val, &best);
        for (i + 1..NCELL) |j| {
            const enc: u32 = @intCast(i * 8 + j);
            tryCandidate(.{ .kind = .sum_pair, .data = enc }, current, grid, X, Yt, bank, w, &best_val, &best);
            tryCandidate(.{ .kind = .min_pair, .data = enc }, current, grid, X, Yt, bank, w, &best_val, &best);
            tryCandidate(.{ .kind = .max_pair, .data = enc }, current, grid, X, Yt, bank, w, &best_val, &best);
        }
    }

    tryCandidate(.{ .kind = .sum_all, .data = 0 }, current, grid, X, Yt, bank, w, &best_val, &best);
    tryCandidate(.{ .kind = .count_feat, .data = 0 }, current, grid, X, Yt, bank, w, &best_val, &best);
    tryCandidate(.{ .kind = .inv_count_feat, .data = 0 }, current, grid, X, Yt, bank, w, &best_val, &best);
    tryCandidate(.{ .kind = .max_all_feat, .data = 0 }, current, grid, X, Yt, bank, w, &best_val, &best);

    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .sum_triple);
    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .min_triple);
    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .max_triple);
    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .median_eq1);
    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .rank2_eq1);

    if (include_synth) {
        var feat = [_]f64{0} ** NSAMP;
        var ctxs = [_]ScalarCtx{undefined} ** NSAMP;
        for (0..NSAMP) |s| ctxs[s] = ScalarCtx.fromGrid(grid[s]);
        for (1..bank.nodes.len) |pid| {
            if (bank.depth(@intCast(pid)) > 4) continue;
            for (0..NSAMP) |s| feat[s] = bank.eval(@intCast(pid), ctxs[s]);
            var mu: f64 = 0;
            for (0..NTR) |s| mu += feat[s];
            mu /= @floatFromInt(NTR);
            var sd: f64 = 0;
            for (0..NTR) |s| sd += (feat[s] - mu) * (feat[s] - mu);
            sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
            for (0..NSAMP) |s| X[s][0] = (feat[s] - mu) / sd;
            fitLogit(X, Yt, 1, 80, 0.06, w);
            const v = accLogit(X, Yt, w, 1, NTR, NVA);
            if (v > best_val) {
                best_val = v;
                best = .{ .kind = .synth_prog, .data = 0, .prog_id = @intCast(pid) };
            }
        }
    }

    return .{ .atom = best, .val_acc = best_val };
}

const ForgeResult = struct {
    solved: [NT]bool,
    test_acc: [NT]f64,
    escape_atom: [NT]?Atom,
    natoms: usize,
    saturated: bool,
};

fn runForge(
    grid: []const [NCELL]u8,
    Y: [][]f64,
    X: [][]f64,
    Xrec: [][]f64,
    phiTgt: []f64,
    bank: ProgBank,
    w: []f64,
    out: anytype,
) !ForgeResult {
    var atoms: [MAXATOMS]Atom = undefined;
    var natoms: usize = 0;
    for (0..NCELL) |i| {
        atoms[natoms] = .{ .kind = .monomial, .data = @as(u32, @intCast(@as(u8, 1) << @intCast(i))) };
        natoms += 1;
    }

    try out.print("── open menu (no spectral/Walsh) ──\n", .{});
    try out.print("round 0: ", .{});
    var solved = [_]bool{false} ** NT;
    var test_acc = [_]f64{0} ** NT;
    var escape_atom = [_]?Atom{null} ** NT;
    var nsolved0: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], bank, Y[t], w);
        test_acc[t] = cov;
        solved[t] = cov >= COVER;
        if (solved[t]) nsolved0 += 1;
        try out.print("T{d:0>2}={d:.2}{s}  ", .{ t + 1, cov, if (solved[t]) "*" else " " });
    }
    try out.print(" → {d}/{d}\n", .{ nsolved0, NT });

    var round: usize = 1;
    var saturated = false;
    var synth_on = false;

    while (round <= 14) : (round += 1) {
        var promoted = false;
        for (0..NT) |t| {
            if (solved[t]) continue;
            const cov_now = coverage(X, grid, atoms[0..natoms], bank, Y[t], w);
            const disc = discoverBest(grid, X, Y[t], atoms[0..natoms], bank, w, synth_on);
            var aug: [MAXATOMS]Atom = undefined;
            @memcpy(aug[0..natoms], atoms[0..natoms]);
            aug[natoms] = disc.atom;
            const cov_aug = coverage(X, grid, aug[0 .. natoms + 1], bank, Y[t], w);
            const escape = cov_aug >= COVER and cov_now < COVER;
            for (0..NSAMP) |s| phiTgt[s] = evalAtom(grid[s], disc.atom, bank);
            buildFeat(Xrec, grid, atoms[0..natoms], bank);
            const rr = reconR2(Xrec, phiTgt, natoms, w);
            const irreducible = rr < R2_MAX;
            var lbl: [80]u8 = undefined;
            const aname = disc.atom.label(&lbl, bank.names);

            if (escape and irreducible and natoms < MAXATOMS) {
                atoms[natoms] = disc.atom;
                natoms += 1;
                solved[t] = true;
                test_acc[t] = cov_aug;
                escape_atom[t] = disc.atom;
                promoted = true;
                try out.print("  r{d} T{d:0>2} ({d:.2}) → {s} escape {d:.2} R²={d:.2} → PROMOTE ({d} atoms)\n", .{
                    round, t + 1, cov_now, aname, cov_aug, rr, natoms,
                });
            } else if (!solved[t] and round <= 4) {
                try out.print("  r{d} T{d:0>2} ({d:.2}) → {s} escape {d:.2} R²={d:.2} → skip\n", .{
                    round, t + 1, cov_now, aname, cov_aug, rr,
                });
            }
        }
        if (!promoted) {
            if (!synth_on) {
                synth_on = true;
                try out.print("  r{d}: monomial+stats saturated → enable scalar synthesis (depth≤4, {{+,×,mod,sin}})\n", .{round});
                continue;
            }
            try out.print("  r{d}: SATURATED (open menu + synth)\n", .{round});
            saturated = true;
            break;
        }
    }

    try out.print("final: ", .{});
    var nsolvedF: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], bank, Y[t], w);
        test_acc[t] = cov;
        solved[t] = cov >= COVER;
        if (solved[t]) nsolvedF += 1;
        try out.print("T{d:0>2}={d:.2}{s}  ", .{ t + 1, cov, if (solved[t]) "*" else " " });
    }
    try out.print(" → {d}/{d}; atoms {d}\n\n", .{ nsolvedF, NT, natoms });

    return .{
        .solved = solved,
        .test_acc = test_acc,
        .escape_atom = escape_atom,
        .natoms = natoms,
        .saturated = saturated,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const bank = try buildProgBank(alloc);

    var prng = std.Random.DefaultPrng.init(RNG_SEED);
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
    var w: [MAXATOMS + 1]f64 = undefined;

    const Y = try alloc.alloc([]f64, NT);
    for (0..NT) |t| Y[t] = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| {
        const g = grid[s];
        for (0..NT) |t| Y[t][s] = targetLabel(g, TARGETS[t]);
    }

    try out.print("=== RESEARCH Q3: E3 extended — 20 non-parity periodic/composed targets ===\n\n", .{});
    try out.print("RNG seed = 0x{X:0>16} (pinned)\n", .{RNG_SEED});
    try out.print("Menu: monomials, thresh, sums, min/max, rank stats, inv/max scalars.\n", .{});
    try out.print("Synthesis: depth≤4 over {{+,×,mod,sin}} on leaves {{count₂,count₃,count₄,inv,sum}}.\n", .{});
    try out.print("EXCLUDED: spectral peak, Walsh χ_S, Clifford, any named Fourier basis.\n", .{});
    try out.print("Program bank: {d} synthesized expressions.\n", .{bank.nodes.len});
    try out.print("PASS bar: ≥{d}/{d} certified with escape ≠ simple monomial (φ_S/χ_S only).\n", .{ PASS_NON_MONO, NT });
    try out.print("Train/val/test {d}/{d}/{d}\n\n", .{ NTR, NVA - NTR, NSAMP - NVA });

    try out.print("── held-out target battery (no parity-of-count) ──\n", .{});
    for (TARGETS, 0..) |t, i| {
        var pos: usize = 0;
        for (0..NSAMP) |s| {
            if (Y[i][s] > 0.5) pos += 1;
        }
        try out.print("  {s}  pos_rate={d:.3}\n", .{ t.name, @as(f64, @floatFromInt(pos)) / @as(f64, @floatFromInt(NSAMP)) });
    }
    try out.print("\n", .{});

    const result = try runForge(grid, Y, X, Xrec, phiTgt, bank, &w, out);

    var mono_solved: usize = 0;
    var non_mono_solved: usize = 0;
    var total_solved: usize = 0;

    try out.print("════════════════════ PER-TARGET RESULTS ════════════════════\n", .{});
    for (0..NT) |t| {
        var feat_buf: [80]u8 = undefined;
        const feat_str: []const u8 = if (result.escape_atom[t]) |a|
            a.label(&feat_buf, bank.names)
        else if (result.solved[t])
            "round0"
        else
            "—";
        const mono = if (result.escape_atom[t]) |a| a.isSimpleMonomial() else false;
        if (result.solved[t]) {
            total_solved += 1;
            if (result.escape_atom[t]) |a| {
                if (a.isSimpleMonomial()) mono_solved += 1 else non_mono_solved += 1;
            } else mono_solved += 1;
        }
        try out.print("  {s}: test={d:.3} cert={} escape={s} non_mono={}\n", .{
            TARGETS[t].name,
            result.test_acc[t],
            result.solved[t],
            feat_str,
            result.solved[t] and !mono and result.escape_atom[t] != null,
        });
    }

    const pass = non_mono_solved >= PASS_NON_MONO;

    try out.print("\n════════════════════ VERDICT (RQ3) ════════════════════\n", .{});
    try out.print("seed 0x{X:0>16}\n", .{RNG_SEED});
    try out.print("total certified: {d}/{d}\n", .{ total_solved, NT });
    try out.print("simple-monomial escapes: {d}\n", .{mono_solved});
    try out.print("non-monomial escapes: {d} (need ≥{d})\n", .{ non_mono_solved, PASS_NON_MONO });
    try out.print("atoms promoted: {d}; saturated={}\n\n", .{ result.natoms, result.saturated });

    if (pass) {
        try out.print("PASS — {d} targets certified via non-monomial features without spectral/Walsh.\n", .{non_mono_solved});
    } else {
        try out.print("FAIL — only {d}/{d} non-monomial certified escapes (need ≥{d}).\n", .{ non_mono_solved, NT, PASS_NON_MONO });
        try out.print("Periodic/composed structure beyond φ_S/χ_S may need richer synthesis or outside generators.\n", .{});
    }

    try out.print("\nRQ3_RESULT pass={} solve_total={d} solve_non_mono={d} doc=docs/research/open_invention_rq3.md\n", .{
        pass, total_solved, non_mono_solved,
    });
    try out.print("See: open_invention_rq3.md, open_invention_e3.md, inner_forge.md.\n", .{});
}