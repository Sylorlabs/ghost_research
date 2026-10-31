//! Experiment E6 — k≥3 substrate open forge (kary_frontier regime).
//!
//! Hypothesis: in the k≥3 / uncountable-clone regime named by kary_frontier.zig, an OPEN
//! inner-transform forge (monomial + modK + order-stats) can discover primitives for RANDOM
//! alien targets WITHOUT the Boolean Fourier operator menu — or it saturates, replicating the
//! closure law at a richer substrate boundary.
//!
//! Compared to inner_forge.zig: NO spectral/Walsh escape hatch.
//! Compared to k3_substrate.zig / k3_order_escape.zig: RANDOM alien targets, not the fixed T1–T6 zoo.
//! Compared to kary_frontier.zig: empirical forge in the regime the frontier names.
//!
//! Run: zig build open-invention-e6 --release=fast

const std = @import("std");

pub const NCELL: usize = 8;
pub const NSAMP: usize = 5000;
pub const NTR: usize = 2500;
pub const NVA: usize = 3750;
pub const MAXATOMS: usize = 48;
pub const MAXDEG: usize = 4;
pub const NT_ALIEN: usize = 8;
pub const RNG_SEED: u64 = 0xE601CEF0A6B33D00;
pub const BASE_OUTSIDE_THRESH: f64 = 0.70;
pub const K_VALUES = [_]u8{ 3, 4 };

const AtomKind = enum {
    monomial,
    modk_pair,
    modk_triple,

    modk_global,
    median3,
    median_eq,
    rank2_eq,
    min3,
    max3,
    spread3,
};

const Atom = struct {
    kind: AtomKind,
    data: u16,

    fn label(self: Atom, k: u8, buf: []u8) []const u8 {
        const mid = k / 2;
        return switch (self.kind) {
            .monomial => std.fmt.bufPrint(buf, "mono 0x{X:0>2}", .{self.data}) catch "?",
            .modk_pair => std.fmt.bufPrint(buf, "mod{d}({d},{d})", .{ k, self.data / 8, self.data % 8 }) catch "?",
            .modk_triple => blk: {
                const enc = self.data;
                const i = enc / 64;
                const j = (enc / 8) % 8;
                const c = enc % 8;
                break :blk std.fmt.bufPrint(buf, "mod{d}({d},{d},{d})", .{ k, i, j, c }) catch "?";
            },
            .modk_global => std.fmt.bufPrint(buf, "mod{d}(Σall)", .{k}) catch "?",
            .median_eq => blk: {
                const enc = self.data;
                const i = enc / 64;
                const j = (enc / 8) % 8;
                const c = enc % 8;
                break :blk std.fmt.bufPrint(buf, "med=={d}({d},{d},{d})", .{ mid, i, j, c }) catch "?";
            },
            .rank2_eq => blk: {
                const enc = self.data;
                const i = enc / 64;
                const j = (enc / 8) % 8;
                const c = enc % 8;
                break :blk std.fmt.bufPrint(buf, "rank2=={d}({d},{d},{d})", .{ mid, i, j, c }) catch "?";
            },
            .median3, .min3, .max3, .spread3 => blk: {
                const enc = self.data;
                const i = enc / 64;
                const j = (enc / 8) % 8;
                const c = enc % 8;
                const tag: []const u8 = switch (self.kind) {
                    .median3 => "med−mid",
                    .min3 => "min−mid",
                    .max3 => "max−mid",
                    .spread3 => "spread−mid",
                    else => "?",
                };
                break :blk std.fmt.bufPrint(buf, "{s}({d},{d},{d})", .{ tag, i, j, c }) catch "?";
            },
        };
    }
};

pub const AlienKind = enum {
    mul_mod_pair,
    count_val_eq,
    range_eq,
    sum_sq_mod,
    affine_mod,
    parity_high,
    lex_gt,
    product3_mod,
};

pub const AlienTarget = struct {
    kind: AlienKind,
    a: u8,
    b: u8,
    c: u8,
    t: u8,

    pub fn label(self: AlienTarget, k: u8, buf: []u8) []const u8 {
        return switch (self.kind) {
            .mul_mod_pair => std.fmt.bufPrint(buf, "mul_mod({d},{d})=={d} mod {d}", .{ self.a, self.b, self.t, k }) catch "?",
            .count_val_eq => std.fmt.bufPrint(buf, "count(c=={d})=={d}", .{ self.a, self.t }) catch "?",
            .range_eq => std.fmt.bufPrint(buf, "range({d},{d},{d})=={d}", .{ self.a, self.b, self.c, self.t }) catch "?",
            .sum_sq_mod => std.fmt.bufPrint(buf, "sq_mod({d},{d})=={d} mod {d}", .{ self.a, self.b, self.t, k }) catch "?",
            .affine_mod => std.fmt.bufPrint(buf, "aff({d},{d})=={d} mod {d}", .{ self.a, self.b, self.t, k }) catch "?",
            .parity_high => std.fmt.bufPrint(buf, "parity_high(#{d}≥{d})", .{ self.a, self.t }) catch "?",
            .lex_gt => std.fmt.bufPrint(buf, "c{d}>c{d}", .{ self.a, self.b }) catch "?",
            .product3_mod => std.fmt.bufPrint(buf, "prod_mod({d},{d},{d})=={d} mod {d}", .{ self.a, self.b, self.c, self.t, k }) catch "?",
        };
    }

    pub fn eval(self: AlienTarget, g: [NCELL]u8, k: u8) f64 {
        const hi = k / 2;
        return switch (self.kind) {
            .mul_mod_pair => if ((@as(u32, g[self.a]) * g[self.b]) % k == self.t) 1.0 else 0.0,
            .count_val_eq => blk: {
                var cnt: u32 = 0;
                for (g) |v| {
                    if (v == self.a) cnt += 1;
                }
                break :blk if (cnt == self.t) 1.0 else 0.0;
            },
            .range_eq => blk: {
                const mx = @max(g[self.a], @max(g[self.b], g[self.c]));
                const mn = @min(g[self.a], @min(g[self.b], g[self.c]));
                break :blk if (mx -% mn == self.t) 1.0 else 0.0;
            },
            .sum_sq_mod => blk: {
                const s = (@as(u32, g[self.a]) * g[self.a] + @as(u32, g[self.b]) * g[self.b]) % k;
                break :blk if (s == self.t) 1.0 else 0.0;
            },
            .affine_mod => if ((2 * @as(u32, g[self.a]) + g[self.b]) % k == self.t) 1.0 else 0.0,
            .parity_high => blk: {
                var cnt: u32 = 0;
                for (g) |v| {
                    if (v >= hi) cnt += 1;
                }
                break :blk @floatFromInt(cnt & 1);
            },
            .lex_gt => if (g[self.a] > g[self.b]) 1.0 else 0.0,
            .product3_mod => blk: {
                const p = (@as(u32, g[self.a]) * g[self.b] * g[self.c]) % k;
                break :blk if (p == self.t) 1.0 else 0.0;
            },
        };
    }
};

const PromotedAlien = struct {
    atom: Atom,
    target_idx: usize,
    r2: f64,
    escape: f64,
};

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
}

fn midVal(k: u8) u8 {
    return k / 2;
}

fn midF(k: u8) f64 {
    return @as(f64, @floatFromInt(midVal(k)));
}

fn tripleEnc(i: usize, j: usize, c: usize) u16 {
    return @intCast(i * 64 + j * 8 + c);
}

fn phiMono(g: [NCELL]u8, mask: u8, k: u8) f64 {
    var p: f64 = 1.0;
    const m = midF(k);
    for (0..NCELL) |ci| {
        if (mask & (@as(u8, 1) << @intCast(ci)) != 0) p *= (@as(f64, @floatFromInt(g[ci])) - m);
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

fn evalAtom(g: [NCELL]u8, atom: Atom, k: u8) f64 {
    const m = midF(k);
    const mid = midVal(k);
    return switch (atom.kind) {
        .monomial => phiMono(g, @intCast(atom.data), k),
        .modk_pair => blk: {
            const i: usize = atom.data / 8;
            const j: usize = atom.data % 8;
            break :blk @as(f64, @floatFromInt((g[i] + g[j]) % k)) - m;
        },
        .modk_triple => blk: {
            const enc = atom.data;
            const c: usize = enc % 8;
            const j: usize = (enc / 8) % 8;
            const i: usize = enc / 64;
            break :blk @as(f64, @floatFromInt((g[i] + g[j] + g[c]) % k)) - m;
        },

        .modk_global => blk: {
            var sum: u32 = 0;
            for (g) |v| sum += v;
            break :blk @as(f64, @floatFromInt(sum % k)) - m;
        },
        .median3 => blk: {
            const enc = atom.data;
            const c: usize = enc % 8;
            const j: usize = (enc / 8) % 8;
            const i: usize = enc / 64;
            break :blk @as(f64, @floatFromInt(median3vals(g[i], g[j], g[c]))) - m;
        },
        .median_eq => blk: {
            const enc = atom.data;
            const c: usize = enc % 8;
            const j: usize = (enc / 8) % 8;
            const i: usize = enc / 64;
            break :blk if (median3vals(g[i], g[j], g[c]) == mid) 1.0 else -1.0;
        },
        .rank2_eq => blk: {
            const enc = atom.data;
            const c: usize = enc % 8;
            const j: usize = (enc / 8) % 8;
            const i: usize = enc / 64;
            break :blk if (rank2Triple(g[i], g[j], g[c]) == mid) 1.0 else -1.0;
        },
        .min3 => blk: {
            const enc = atom.data;
            const c: usize = enc % 8;
            const j: usize = (enc / 8) % 8;
            const i: usize = enc / 64;
            const mn = @min(g[i], @min(g[j], g[c]));
            break :blk @as(f64, @floatFromInt(mn)) - m;
        },
        .max3 => blk: {
            const enc = atom.data;
            const c: usize = enc % 8;
            const j: usize = (enc / 8) % 8;
            const i: usize = enc / 64;
            const mx = @max(g[i], @max(g[j], g[c]));
            break :blk @as(f64, @floatFromInt(mx)) - m;
        },
        .spread3 => blk: {
            const enc = atom.data;
            const c: usize = enc % 8;
            const j: usize = (enc / 8) % 8;
            const i: usize = enc / 64;
            const mx = @max(g[i], @max(g[j], g[c]));
            const mn = @min(g[i], @min(g[j], g[c]));
            break :blk @as(f64, @floatFromInt(mx -% mn)) - m;
        },
    };
}

fn atomsEqual(a: Atom, b: Atom) bool {
    return a.kind == b.kind and a.data == b.data;
}

fn buildFeat(X: [][]f64, grid: []const [NCELL]u8, atoms: []const Atom, k: u8) void {
    const ncol = atoms.len;
    for (0..NSAMP) |s| for (0..ncol) |c| {
        X[s][c] = evalAtom(grid[s], atoms[c], k);
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

fn scoreCandidate(atom: Atom, grid: []const [NCELL]u8, X: [][]f64, Yt: []const f64, w: []f64, k: u8) f64 {
    const one = [_]Atom{atom};
    buildFeat(X, grid, &one, k);
    fitLogit(X, Yt, 1, 35, 0.06, w);
    return accLogit(X, Yt, w, 1, NTR, NVA);
}

fn tryCandidate(
    atom: Atom,
    current: []const Atom,
    grid: []const [NCELL]u8,
    X: [][]f64,
    Yt: []const f64,
    w: []f64,
    k: u8,
    best_val: *f64,
    best: *Atom,
) void {
    for (current) |a| {
        if (atomsEqual(a, atom)) return;
    }
    const v = scoreCandidate(atom, grid, X, Yt, w, k);
    if (v > best_val.*) {
        best_val.* = v;
        best.* = atom;
    }
}

fn enumerateTriples(
    current: []const Atom,
    grid: []const [NCELL]u8,
    X: [][]f64,
    Yt: []const f64,
    w: []f64,
    k: u8,
    best_val: *f64,
    best: *Atom,
    kinds: []const AtomKind,
) void {
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |c| {
        const enc = tripleEnc(i, j, c);
        for (kinds) |kind| {
            tryCandidate(.{ .kind = kind, .data = enc }, current, grid, X, Yt, w, k, best_val, best);
        }
    };
}

fn discoverBest(
    grid: []const [NCELL]u8,
    X: [][]f64,
    Yt: []const f64,
    current: []const Atom,
    w: []f64,
    k: u8,
) struct { atom: Atom, val_acc: f64 } {
    var best_val: f64 = -1;
    var best: Atom = .{ .kind = .monomial, .data = 0 };

    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const cand: u8 = @intCast(mm);
        const d = popcount(cand);
        if (d < 1 or d > MAXDEG) continue;
        tryCandidate(.{ .kind = .monomial, .data = cand }, current, grid, X, Yt, w, k, &best_val, &best);
    }

    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        tryCandidate(.{ .kind = .modk_pair, .data = @intCast(i * 8 + j) }, current, grid, X, Yt, w, k, &best_val, &best);
    };

    const triple_kinds = [_]AtomKind{ .modk_triple, .median3, .median_eq, .rank2_eq, .min3, .max3, .spread3 };
    enumerateTriples(current, grid, X, Yt, w, k, &best_val, &best, &triple_kinds);

    tryCandidate(.{ .kind = .modk_global, .data = 0 }, current, grid, X, Yt, w, k, &best_val, &best);

    return .{ .atom = best, .val_acc = best_val };
}

fn coverage(X: [][]f64, grid: []const [NCELL]u8, atoms: []const Atom, yv: []const f64, w: []f64, k: u8) f64 {
    buildFeat(X, grid, atoms, k);
    fitLogit(X, yv, atoms.len, 80, 0.05, w);
    return accLogit(X, yv, w, atoms.len, NVA, NSAMP);
}

fn baseSingletonCoverage(grid: []const [NCELL]u8, Yt: []const f64, w: []f64, X: [][]f64, k: u8) f64 {
    var atoms: [NCELL]Atom = undefined;
    for (0..NCELL) |i| atoms[i] = .{ .kind = .monomial, .data = @as(u8, 1) << @intCast(i) };
    return coverage(X, grid, atoms[0..], Yt, w, k);
}

fn classBalance(Yt: []const f64) f64 {
    var pos: usize = 0;
    for (NVA..NSAMP) |s| {
        if (Yt[s] > 0.5) pos += 1;
    }
    return @as(f64, @floatFromInt(pos)) / @as(f64, @floatFromInt(NSAMP - NVA));
}

fn sampleAlienTarget(rand: std.Random, k: u8) AlienTarget {
    const kinds = [_]AlienKind{
        .mul_mod_pair,
        .count_val_eq,
        .range_eq,
        .sum_sq_mod,
        .affine_mod,
        .parity_high,
        .lex_gt,
        .product3_mod,
    };
    const kind = kinds[rand.intRangeAtMost(usize, 0, kinds.len - 1)];
    return switch (kind) {
        .mul_mod_pair => .{
            .kind = kind,
            .a = rand.intRangeAtMost(u8, 0, 7),
            .b = rand.intRangeAtMost(u8, 0, 7),
            .c = 0,
            .t = rand.intRangeAtMost(u8, 0, k - 1),
        },
        .count_val_eq => .{
            .kind = kind,
            .a = rand.intRangeAtMost(u8, 0, k - 1),
            .b = 0,
            .c = 0,
            .t = rand.intRangeAtMost(u8, 1, 3),
        },
        .range_eq => blk: {
            const a = rand.intRangeAtMost(u8, 0, 7);
            var b = rand.intRangeAtMost(u8, 0, 7);
            var c = rand.intRangeAtMost(u8, 0, 7);
            while (b == a) b = rand.intRangeAtMost(u8, 0, 7);
            while (c == a or c == b) c = rand.intRangeAtMost(u8, 0, 7);
            break :blk .{
                .kind = kind,
                .a = a,
                .b = b,
                .c = c,
                .t = rand.intRangeAtMost(u8, 1, k - 1),
            };
        },
        .sum_sq_mod => .{
            .kind = kind,
            .a = rand.intRangeAtMost(u8, 0, 7),
            .b = rand.intRangeAtMost(u8, 0, 7),
            .c = 0,
            .t = rand.intRangeAtMost(u8, 0, k - 1),
        },
        .affine_mod => .{
            .kind = kind,
            .a = rand.intRangeAtMost(u8, 0, 7),
            .b = rand.intRangeAtMost(u8, 0, 7),
            .c = 0,
            .t = rand.intRangeAtMost(u8, 0, k - 1),
        },
        .parity_high => .{
            .kind = kind,
            .a = 0,
            .b = 0,
            .c = 0,
            .t = k / 2,
        },
        .lex_gt => blk: {
            const a = rand.intRangeAtMost(u8, 0, 7);
            var b = rand.intRangeAtMost(u8, 0, 7);
            while (b == a) b = rand.intRangeAtMost(u8, 0, 7);
            break :blk .{ .kind = kind, .a = a, .b = b, .c = 0, .t = 0 };
        },
        .product3_mod => blk: {
            const a = rand.intRangeAtMost(u8, 0, 7);
            var b = rand.intRangeAtMost(u8, 0, 7);
            var c = rand.intRangeAtMost(u8, 0, 7);
            while (b == a) b = rand.intRangeAtMost(u8, 0, 7);
            while (c == a or c == b) c = rand.intRangeAtMost(u8, 0, 7);
            break :blk .{
                .kind = kind,
                .a = a,
                .b = b,
                .c = c,
                .t = rand.intRangeAtMost(u8, 0, k - 1),
            };
        },
    };
}

pub fn generateAlienTargets(
    alloc: std.mem.Allocator,
    grid: []const [NCELL]u8,
    rand: std.Random,
    k: u8,
    X: [][]f64,
    w: []f64,
    out: anytype,
) !struct { targets: []AlienTarget, labels: []const []const u8 } {
    var targets = std.ArrayList(AlienTarget).init(alloc);
    var labels = std.ArrayList([]const u8).init(alloc);
    var attempts: usize = 0;

    while (targets.items.len < NT_ALIEN and attempts < 500) : (attempts += 1) {
        const cand = sampleAlienTarget(rand, k);
        var Yt: [NSAMP]f64 = undefined;
        for (0..NSAMP) |s| Yt[s] = cand.eval(grid[s], k);

        const base_cov = baseSingletonCoverage(grid, &Yt, w, X, k);
        const bal = classBalance(&Yt);

        // Structural alien: target family ∉ {monomial, modK-sum, order-stat} pool.
        // Empirical: base singletons cannot reach threshold; class not degenerate.
        if (base_cov < BASE_OUTSIDE_THRESH and bal > 0.12 and bal < 0.88) {
            try targets.append(cand);
            const buf = try alloc.alloc(u8, 96);
            const lbl = cand.label(k, buf);
            try labels.append(lbl);
            var line: [128]u8 = undefined;
            const spec = try std.fmt.bufPrint(&line, "  A{d}: {s}  (base={d:.2} bal={d:.2})", .{
                targets.items.len, lbl, base_cov, bal,
            });
            try out.print("{s}\n", .{spec});
        }
    }

    if (targets.items.len < NT_ALIEN) {
        return error.NotEnoughAlienTargets;
    }

    return .{ .targets = try targets.toOwnedSlice(), .labels = try labels.toOwnedSlice() };
}

fn runOpenForge(
    k: u8,
    grid: []const [NCELL]u8,
    targets: []const AlienTarget,
    labels: []const []const u8,
    X: [][]f64,
    Xrec: [][]f64,
    phiTgt: []f64,
    w: []f64,
    out: anytype,
) !struct {
    nsolved: usize,
    natoms: usize,
    saturated: bool,
    promotions: []PromotedAlien,
} {
    const Y = try std.heap.page_allocator.alloc([]f64, targets.len);
    defer {
        for (Y) |row| std.heap.page_allocator.free(row);
        std.heap.page_allocator.free(Y);
    }
    for (0..targets.len) |t| {
        Y[t] = try std.heap.page_allocator.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[t][s] = targets[t].eval(grid[s], k);
    }

    var atoms: [MAXATOMS]Atom = undefined;
    var natoms: usize = 0;
    for (0..NCELL) |i| {
        atoms[natoms] = .{ .kind = .monomial, .data = @as(u8, 1) << @intCast(i) };
        natoms += 1;
    }

    var promotions = std.ArrayList(PromotedAlien).init(std.heap.page_allocator);
    defer promotions.deinit();

    try out.print("── open forge k={d} (NO Boolean Fourier menu) ──\n", .{k});
    try out.print("round 0: ", .{});
    var solved = [_]bool{false} ** NT_ALIEN;
    var nsolved0: usize = 0;
    for (0..targets.len) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], Y[t], w, k);
        solved[t] = cov >= 0.90;
        if (solved[t]) nsolved0 += 1;
        try out.print("A{d}={d:.2}{s}  ", .{ t + 1, cov, if (solved[t]) "*" else " " });
    }
    try out.print(" → {d}/{d}\n", .{ nsolved0, targets.len });

    var round: usize = 1;
    var saturated = false;
    while (round <= 12) : (round += 1) {
        var promoted = false;
        for (0..targets.len) |t| {
            if (solved[t]) continue;
            const cov_now = coverage(X, grid, atoms[0..natoms], Y[t], w, k);
            if (cov_now >= 0.90) {
                solved[t] = true;
                continue;
            }
            const disc = discoverBest(grid, X, Y[t], atoms[0..natoms], w, k);
            var aug: [MAXATOMS]Atom = undefined;
            @memcpy(aug[0..natoms], atoms[0..natoms]);
            aug[natoms] = disc.atom;
            const cov_aug = coverage(X, grid, aug[0 .. natoms + 1], Y[t], w, k);
            const escape = cov_aug >= 0.90 and cov_now < 0.90;
            for (0..NSAMP) |s| phiTgt[s] = evalAtom(grid[s], disc.atom, k);
            buildFeat(Xrec, grid, atoms[0..natoms], k);
            const rr = reconR2(Xrec, phiTgt, natoms, w);
            const irreducible = rr < 0.40;
            var lbl: [64]u8 = undefined;
            const name = disc.atom.label(k, &lbl);

            if (escape and irreducible and natoms < MAXATOMS) {
                atoms[natoms] = disc.atom;
                natoms += 1;
                solved[t] = true;
                promoted = true;
                try promotions.append(.{ .atom = disc.atom, .target_idx = t, .r2 = rr, .escape = cov_aug });
                try out.print("  r{d} A{d} ({s}) ({d:.2}) → {s} escape {d:.2} R²={d:.2} → PROMOTE ({d} atoms)\n", .{
                    round, t + 1, labels[t], cov_now, name, cov_aug, rr, natoms,
                });
            } else {
                try out.print("  r{d} A{d} ({d:.2}) → {s} escape {d:.2} R²={d:.2} → skip\n", .{
                    round, t + 1, cov_now, name, cov_aug, rr,
                });
            }
        }
        if (!promoted) {
            try out.print("  r{d}: SATURATED\n", .{round});
            saturated = true;
            break;
        }
    }

    try out.print("final: ", .{});
    var nsolvedF: usize = 0;
    for (0..targets.len) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], Y[t], w, k);
        const sv = cov >= 0.90;
        if (sv) nsolvedF += 1;
        try out.print("A{d}={d:.2}{s}  ", .{ t + 1, cov, if (sv) "*" else " " });
    }
    try out.print(" → {d}/{d}; atoms {d}\n\n", .{ nsolvedF, targets.len, natoms });

    return .{
        .nsolved = nsolvedF,
        .natoms = natoms,
        .saturated = saturated,
        .promotions = try promotions.toOwnedSlice(),
    };
}

fn isAlienPrimitive(atom: Atom) bool {
    return atom.kind != .monomial;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== Experiment E6: k≥3 open forge — random alien targets, no Fourier menu ===\n\n", .{});
    try out.print("RNG seed = 0x{X:0>16} (pinned)\n", .{RNG_SEED});
    try out.print("substrate pool: monomial + modK + order-stats (k=3,4; no Walsh/Fourier)\n", .{});
    try out.print("alien cert: structural (mul/range/affine/lex/… ∉ pool) + base singletons < {d:.2}\n", .{BASE_OUTSIDE_THRESH});
    try out.print("train/val/test {d}/{d}/{d}\n\n", .{ NTR, NVA - NTR, NSAMP - NVA });

    const ks = K_VALUES;
    var total_solved: usize = 0;
    var total_targets: usize = 0;
    var alien_promo_count: usize = 0;

    for (ks) |k| {
        var prng = std.Random.DefaultPrng.init(RNG_SEED +% @as(u64, k));
        const rand = prng.random();

        const grid = try alloc.alloc([NCELL]u8, NSAMP);
        for (0..NSAMP) |s| for (0..NCELL) |i| {
            grid[s][i] = rand.intRangeAtMost(u8, 0, k - 1);
        };

        const X = try alloc.alloc([]f64, NSAMP);
        const Xrec = try alloc.alloc([]f64, NSAMP);
        for (0..NSAMP) |s| {
            X[s] = try alloc.alloc(f64, MAXATOMS);
            Xrec[s] = try alloc.alloc(f64, MAXATOMS);
        }
        const phiTgt = try alloc.alloc(f64, NSAMP);
        var w: [MAXATOMS + 1]f64 = undefined;

        try out.print("════════ k={d} alien target zoo (certified outside library) ════════\n", .{k});
        const gen = try generateAlienTargets(alloc, grid, rand, k, X, &w, out);
        try out.print("\n", .{});

        const result = try runOpenForge(k, grid, gen.targets, gen.labels, X, Xrec, phiTgt, &w, out);

        total_solved += result.nsolved;
        total_targets += gen.targets.len;

        try out.print("certified alien primitives promoted (non-monomial):\n", .{});
        var any_alien = false;
        for (result.promotions) |p| {
            if (isAlienPrimitive(p.atom)) {
                any_alien = true;
                alien_promo_count += 1;
                var lbl: [64]u8 = undefined;
                const name = p.atom.label(k, &lbl);
                try out.print("  A{d} ← {s}  (R²={d:.2}, escape={d:.2})\n", .{ p.target_idx + 1, name, p.r2, p.escape });
            }
        }
        if (!any_alien) try out.print("  (none)\n", .{});
        try out.print("\n", .{});

        std.heap.page_allocator.free(result.promotions);
    }

    try out.print("════════════════════ VERDICT (E6) ════════════════════\n", .{});
    try out.print("aggregate solve rate: {d}/{d} ({d:.1}%)\n", .{ total_solved, total_targets, @as(f64, @floatFromInt(total_solved * 100)) / @as(f64, @floatFromInt(total_targets)) });
    try out.print("certified non-monomial promotions: {d}\n\n", .{alien_promo_count});

    if (total_solved == 0) {
        try out.print("FAIL for open invention: forge solved NONE of the random alien targets.\n", .{});
        try out.print("k≥3 substrate richness does NOT substitute for a cross-family operator basis.\n", .{});
        try out.print("The uncountable-clone regime (kary_frontier.md) names WHERE novelty lives;\n", .{});
        try out.print("this forge still bottoms at its HANDED pool — no Boolean Fourier, no escape.\n", .{});
    } else if (total_solved < total_targets) {
        try out.print("PARTIAL: forge solves some aliens but SATURATES before full coverage.\n", .{});
        try out.print("Random targets outside the monomial library remain mostly unreachable\n", .{});
        try out.print("without cross-family generators (multiplicative / comparison / parity families).\n", .{});
        try out.print("Uncountable clones ≠ unbounded forge; same closure law, richer substrate.\n", .{});
    } else {
        try out.print("UNEXPECTED full solve — inspect promotions; may indicate weak alien certification.\n", .{});
    }

    try out.print("\nHONEST SCOPE: targets are random but DRAWN from named alien families (mul_mod, range,\n", .{});
    try out.print("affine, lex, …) — NOT plain English. No Walsh/spectral menu was offered; any escape is\n", .{});
    try out.print("from the k-ary pool only. This tests the kary_frontier regime empirically, not Post's map.\n", .{});
    try out.print("\nSee: k3_substrate.zig, k3_order_escape.zig, kary_frontier.md, inner_forge.md, open_invention_e6.md\n", .{});
}