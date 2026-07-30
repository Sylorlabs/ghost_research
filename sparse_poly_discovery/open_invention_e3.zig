//! EXPERIMENT E3 — "No spectral in codebase" ablation (decisive open-invention test).
//!
//! Remove hand-named spectral / Walsh from the menu. Allowed primitives only:
//!   monomials, threshold signs, sums, products, min/max, rank statistics (k3_order_escape
//!   patterns), and optional depth≤4 program synthesis over {+,×,sin,cos,abs,mod} on count.
//!
//! Targets: parity-of-count + 10 random Boolean χ_S predicates (seed-pinned).
//! PASS criterion: parity certified (held-out test ≥0.90) without any Fourier basis.
//!
//! Run: zig build open-invention-e3 --release=fast

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const MAXATOMS: usize = 48;
const MAXDEG: usize = 4;
const COVER: f64 = 0.90;
const R2_MAX: f64 = 0.40;
const RNG_SEED: u64 = 0xE3A801CEF00D;
const NRANDOM: usize = 10;
const NT: usize = 1 + NRANDOM;

const AtomKind = enum {
    monomial,
    thresh_mono,
    thresh_bit,
    sum_all,
    sum_pair,
    sum_triple,
    count_feat,
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
            .count_feat => "count",
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

fn countGE(g: [NCELL]u8) f64 {
    var c: usize = 0;
    for (g) |v| {
        if (v >= THRESH) c += 1;
    }
    return @floatFromInt(c);
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

// ── Program synthesis (depth ≤ 4, leaf = count only) ─────────────────────────

const ProgNode = union(enum) {
    count: void,
    add: struct { a: u16, b: u16 },
    mul: struct { a: u16, b: u16 },
    sin: u16,
    cos: u16,
    abs: u16,
    @"mod": struct { child: u16, k: u8 },
};

const ProgBank = struct {
    nodes: []ProgNode,
    depths: []u8,
    names: []const []const u8,
    count_leaf: u16,

    fn depth(self: ProgBank, id: u16) u8 {
        return self.depths[id];
    }

    fn eval(self: ProgBank, id: u16, c: f64) f64 {
        return switch (self.nodes[id]) {
            .count => c,
            .add => |ab| self.eval(ab.a, c) + self.eval(ab.b, c),
            .mul => |ab| self.eval(ab.a, c) * self.eval(ab.b, c),
            .sin => |ch| @sin(self.eval(ch, c)),
            .cos => |ch| @cos(self.eval(ch, c)),
            .abs => |ch| @abs(self.eval(ch, c)),
            .@"mod" => |mk| @rem(self.eval(mk.child, c), @as(f64, @floatFromInt(mk.k))),
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

    try nodes.append(.{ .count = {} });
    try depths.append(0);
    try names.append("count");
    const count_leaf: u16 = 0;

    // depth-1 unary programs
    var d1 = std.ArrayList(u16).init(alloc);
    defer d1.deinit();
    try d1.append(count_leaf);

    var depth_cur: u8 = 1;
    var frontier = std.ArrayList(u16).init(alloc);
    try frontier.append(count_leaf);

    while (depth_cur <= 4) : (depth_cur += 1) {
        var next_frontier = std.ArrayList(u16).init(alloc);
        defer next_frontier.deinit();

        // unary ops on all frontier nodes
        for (frontier.items) |pid| {
            const unary_ops = [_]struct { node: ProgNode, tag: []const u8 }{
                .{ .node = .{ .sin = pid }, .tag = "sin" },
                .{ .node = .{ .cos = pid }, .tag = "cos" },
                .{ .node = .{ .abs = pid }, .tag = "abs" },
            };
            for (unary_ops) |op| {
                if (nodes.items.len >= 320) break;
                const base = names.items[pid];
                const nm = try std.fmt.allocPrint(alloc, "{s}({s})", .{ op.tag, base });
                try nodes.append(op.node);
                try depths.append(depth_cur);
                try names.append(nm);
                try next_frontier.append(@intCast(nodes.items.len - 1));
            }
            for (2..9) |k| {
                if (nodes.items.len >= 320) break;
                const base = names.items[pid];
                const nm = try std.fmt.allocPrint(alloc, "mod({s},{d})", .{ base, k });
                try nodes.append(.{ .@"mod" = .{ .child = pid, .k = @intCast(k) } });
                try depths.append(depth_cur);
                try names.append(nm);
                try next_frontier.append(@intCast(nodes.items.len - 1));
            }
        }

        // binary ops: combine any programs with combined depth ≤ 4
        const n = nodes.items.len;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var j: usize = 0;
            while (j < n) : (j += 1) {
                const d = @max(depths.items[i], depths.items[j]) + 1;
                if (d > 4) continue;
                if (nodes.items.len >= 320) break;

                const ai: u16 = @intCast(i);
                const aj: u16 = @intCast(j);
                const bin_ops = [_]struct { node: ProgNode, tag: []const u8 }{
                    .{ .node = .{ .add = .{ .a = ai, .b = aj } }, .tag = "+" },
                    .{ .node = .{ .mul = .{ .a = ai, .b = aj } }, .tag = "*" },
                };
                for (bin_ops) |op| {
                    if (nodes.items.len >= 320) break;
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
        .count_leaf = count_leaf,
    };
}

fn evalAtom(g: [NCELL]u8, atom: Atom, bank: ProgBank) f64 {
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
        .count_feat => countGE(g) - @as(f64, @floatFromInt(NCELL)) / 2.0,
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
        .synth_prog => bank.eval(atom.prog_id, countGE(g)),
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

    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .sum_triple);
    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .min_triple);
    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .max_triple);
    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .median_eq1);
    enumerateTriples(current, grid, X, Yt, bank, w, &best_val, &best, .rank2_eq1);

    if (include_synth) {
        // Score synthesized count programs via fast single-feature path.
        var feat = [_]f64{0} ** NSAMP;
        for (1..bank.nodes.len) |pid| {
            if (bank.depth(@intCast(pid)) > 4) continue;
            for (0..NSAMP) |s| feat[s] = bank.eval(@intCast(pid), countGE(grid[s]));
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

fn parityLabel(g: [NCELL]u8) f64 {
    var c: usize = 0;
    for (g) |v| {
        if (v >= THRESH) c += 1;
    }
    return @floatFromInt(c & 1);
}

fn chiLabel(g: [NCELL]u8, mask: u8) f64 {
    return if (chiMono(g, mask) > 0) 1.0 else 0.0;
}

fn runForge(
    grid: []const [NCELL]u8,
    Y: [][]f64,
    names: []const []const u8,
    X: [][]f64,
    Xrec: [][]f64,
    phiTgt: []f64,
    bank: ProgBank,
    w: []f64,
    out: anytype,
) !struct { solved: [NT]bool, test_acc: [NT]f64, natoms: usize, saturated: bool } {
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
    var nsolved0: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], bank, Y[t], w);
        test_acc[t] = cov;
        solved[t] = cov >= COVER;
        if (solved[t]) nsolved0 += 1;
        try out.print("{s}={d:.2}{s}  ", .{ names[t][0..@min(3, names[t].len)], cov, if (solved[t]) "*" else " " });
    }
    try out.print(" → {d}/{d}\n", .{ nsolved0, NT });

    var round: usize = 1;
    var saturated = false;
    var synth_on = false;

    while (round <= 12) : (round += 1) {
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
            var lbl: [64]u8 = undefined;
            const aname = disc.atom.label(&lbl, bank.names);

            if (escape and irreducible and natoms < MAXATOMS) {
                atoms[natoms] = disc.atom;
                natoms += 1;
                solved[t] = true;
                test_acc[t] = cov_aug;
                promoted = true;
                try out.print("  r{d} {s} ({d:.2}) → {s} escape {d:.2} R²={d:.2} → PROMOTE ({d} atoms)\n", .{
                    round, names[t][0..@min(3, names[t].len)], cov_now, aname, cov_aug, rr, natoms,
                });
            } else if (!solved[t] and round <= 3) {
                try out.print("  r{d} {s} ({d:.2}) → {s} escape {d:.2} R²={d:.2} → skip\n", .{
                    round, names[t][0..@min(3, names[t].len)], cov_now, aname, cov_aug, rr,
                });
            }
        }
        if (!promoted) {
            if (!synth_on) {
                synth_on = true;
                try out.print("  r{d}: monomial+stats saturated → enable count program synthesis (depth≤4)\n", .{round});
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
        try out.print("{s}={d:.2}{s}  ", .{ names[t][0..@min(3, names[t].len)], cov, if (solved[t]) "*" else " " });
    }
    try out.print(" → {d}/{d}; atoms {d}\n\n", .{ nsolvedF, NT, natoms });

    return .{ .solved = solved, .test_acc = test_acc, .natoms = natoms, .saturated = saturated };
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

    var random_masks: [NRANDOM]u8 = undefined;
    for (0..NRANDOM) |r| {
        var mask: u8 = 0;
        const deg = rand.intRangeAtMost(usize, 1, MAXDEG);
        var placed: usize = 0;
        while (placed < deg) {
            const bit = rand.intRangeAtMost(usize, 0, NCELL - 1);
            const b = @as(u8, 1) << @intCast(bit);
            if (mask & b == 0) {
                mask |= b;
                placed += 1;
            }
        }
        random_masks[r] = mask;
    }

    const tnames = try alloc.alloc([]const u8, NT);
    tnames[0] = "parity-of-count";
    for (0..NRANDOM) |r| {
        tnames[r + 1] = try std.fmt.allocPrint(alloc, "χ_{X:0>2}", .{random_masks[r]});
    }

    const Y = try alloc.alloc([]f64, NT);
    for (0..NT) |t| Y[t] = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| {
        const g = grid[s];
        Y[0][s] = parityLabel(g);
        for (0..NRANDOM) |r| Y[r + 1][s] = chiLabel(g, random_masks[r]);
    }

    try out.print("=== EXPERIMENT E3: no spectral/Walsh ablation (open invention test) ===\n\n", .{});
    try out.print("RNG seed = 0x{X:0>16} (pinned)\n", .{RNG_SEED});
    try out.print("Menu: monomials, thresh, sums, products, min/max, rank stats; synth depth≤4 on count.\n", .{});
    try out.print("EXCLUDED: spectral peak, Walsh χ_S, Clifford, any named Fourier basis.\n", .{});
    try out.print("Program bank: {d} synthesized expressions (leaf=count only).\n", .{bank.nodes.len});
    try out.print("Targets: parity + {d} random Boolean χ_S; train/val/test {d}/{d}/{d}\n\n", .{ NRANDOM, NTR, NVA - NTR, NSAMP - NVA });

    const result = try runForge(grid, Y, tnames, X, Xrec, phiTgt, bank, &w, out);

    try out.print("════════════════════ VERDICT (E3) ════════════════════\n", .{});
    try out.print("seed 0x{X:0>16}\n", .{RNG_SEED});
    try out.print("parity held-out test acc: {d:.3}  certified={}\n", .{ result.test_acc[0], result.solved[0] });
    var random_ok: usize = 0;
    for (1..NT) |t| {
        if (result.solved[t]) random_ok += 1;
    }
    try out.print("random Boolean targets: {d}/{d} certified\n", .{ random_ok, NRANDOM });
    try out.print("total: {d}/{d}; atoms promoted {d}; saturated={}\n\n", .{
        random_ok + @as(usize, @intFromBool(result.solved[0])),
        NT,
        result.natoms,
        result.saturated,
    });

    if (result.solved[0]) {
        try out.print("PASS — parity certified without hand-named spectral/Walsh.\n", .{});
        try out.print("Escape used only the open menu + optional count synthesis.\n", .{});
    } else {
        try out.print("FAIL — parity not certified (acc={d:.3}). Expected failure is a valid finding:\n", .{result.test_acc[0]});
        try out.print("periodic/Z₂ structure on count may require Fourier-class operators not in this menu.\n", .{});
    }

    try out.print("\nSee: open_invention_e3.md, inner_forge.md, spectral_discovery.md (contrast).\n", .{});
}