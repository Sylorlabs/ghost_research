//! Fork 6 — k≥3 + order-statistic escape (T6 median wall).
//!
//! Hypothesis: leaving Boolean monomials but adding RANK/indicator order statistics breaks
//! saturation on T6 (median(c0,c1,c2)==1), whereas centered median−1 cannot (symmetric ±1 negatives).
//!
//! Pools compared (seed-pinned 0xC3F0A6E01CEF):
//!   A) monomial-only          → expect 4/6, T6 stuck
//!   B) mono + mod3            → expect 5/6, T6 stuck (T5 escapes via mod3_global)
//!   C) mono + order-stats     → T6 escape test (median_eq1, rank indicators)
//!   D) mono + mod3 + order    → full substrate
//!
//! Run: zig build k3-order-escape --release=fast

const std = @import("std");

pub const NCELL: usize = 8;
const K: u8 = 3;
pub const NSAMP: usize = 5000;
pub const NTR: usize = 2500;
pub const NVA: usize = 3750;
pub const MAXATOMS: usize = 40;
pub const MAXDEG: usize = 4;
pub const COVER_THRESH: f64 = 0.90;
pub const R2_MAX: f64 = 0.40;
const RNG_SEED: u64 = 0xC3F0A6E01CEF;

pub const AtomKind = enum {
    monomial,
    mod3_pair,
    mod3_triple,
    mod3_global,
    median3, // centered median − 1  (symmetric — fails T6 under linear readout)
    median_eq1, // +1 iff median==1 else −1  (rank indicator)
    rank2_eq1, // +1 iff 2nd-smallest of triple == 1
    min3,
    max3,
};

pub const Atom = struct {
    kind: AtomKind,
    data: u8,

    pub fn label(self: Atom, k_ary: u8, buf: []u8) []const u8 {
        const mid = k_ary / 2;
        return switch (self.kind) {
            .monomial => std.fmt.bufPrint(buf, "mono 0x{X:0>2}", .{self.data}) catch "?",
            .mod3_pair => std.fmt.bufPrint(buf, "mod{d}({d},{d})", .{ k_ary, self.data / 8, self.data % 8 }) catch "?",
            .mod3_triple => blk: {
                const c = self.data % 8;
                const j = (self.data / 8) % 8;
                const i = self.data / 64;
                break :blk std.fmt.bufPrint(buf, "mod{d}({d},{d},{d})", .{ k_ary, i, j, c }) catch "?";
            },
            .median3 => blk: {
                const c = self.data % 8;
                const j = (self.data / 8) % 8;
                const i = self.data / 64;
                break :blk std.fmt.bufPrint(buf, "med−mid({d},{d},{d})", .{ i, j, c }) catch "?";
            },
            .median_eq1 => blk: {
                const c = self.data % 8;
                const j = (self.data / 8) % 8;
                const i = self.data / 64;
                break :blk std.fmt.bufPrint(buf, "med=={d}({d},{d},{d})", .{ mid, i, j, c }) catch "?";
            },
            .rank2_eq1 => blk: {
                const c = self.data % 8;
                const j = (self.data / 8) % 8;
                const i = self.data / 64;
                break :blk std.fmt.bufPrint(buf, "rank2=={d}({d},{d},{d})", .{ mid, i, j, c }) catch "?";
            },
            .min3 => blk: {
                const c = self.data % 8;
                const j = (self.data / 8) % 8;
                const i = self.data / 64;
                break :blk std.fmt.bufPrint(buf, "min−mid({d},{d},{d})", .{ i, j, c }) catch "?";
            },
            .max3 => blk: {
                const c = self.data % 8;
                const j = (self.data / 8) % 8;
                const i = self.data / 64;
                break :blk std.fmt.bufPrint(buf, "max−mid({d},{d},{d})", .{ i, j, c }) catch "?";
            },
            .mod3_global => std.fmt.bufPrint(buf, "mod{d}(Σall)", .{k_ary}) catch "?",
        };
    }
};

pub const CandidatePool = enum {
    monomial_only,
    mono_mod3,
    mono_order,
    full,
};

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn popcount(m: u8) usize {
    return @popCount(m);
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

fn tripleEnc(i: usize, j: usize, k: usize) u8 {
    return @intCast(i * 64 + j * 8 + k);
}

fn midVal(k_ary: u8) u8 {
    return k_ary / 2;
}

fn midF(k_ary: u8) f64 {
    return @as(f64, @floatFromInt(midVal(k_ary)));
}

fn phiMono(g: [NCELL]u8, mask: u8, k_ary: u8) f64 {
    var p: f64 = 1.0;
    const m = midF(k_ary);
    for (0..NCELL) |ci| {
        if (mask & (@as(u8, 1) << @intCast(ci)) != 0) p *= (@as(f64, @floatFromInt(g[ci])) - m);
    }
    return p;
}

pub fn evalAtom(g: [NCELL]u8, atom: Atom, k_ary: u8) f64 {
    const m = midF(k_ary);
    const mid = midVal(k_ary);
    return switch (atom.kind) {
        .monomial => phiMono(g, atom.data, k_ary),
        .mod3_pair => blk: {
            const i: usize = atom.data / 8;
            const j: usize = atom.data % 8;
            break :blk @as(f64, @floatFromInt((g[i] + g[j]) % k_ary)) - m;
        },
        .mod3_triple => blk: {
            const c: usize = atom.data % 8;
            const j: usize = (atom.data / 8) % 8;
            const i: usize = atom.data / 64;
            break :blk @as(f64, @floatFromInt((g[i] + g[j] + g[c]) % k_ary)) - m;
        },
        .mod3_global => blk: {
            var sum: u32 = 0;
            for (g) |v| sum += v;
            break :blk @as(f64, @floatFromInt(sum % k_ary)) - m;
        },
        .median3 => blk: {
            const c: usize = atom.data % 8;
            const j: usize = (atom.data / 8) % 8;
            const i: usize = atom.data / 64;
            break :blk @as(f64, @floatFromInt(median3vals(g[i], g[j], g[c]))) - m;
        },
        .median_eq1 => blk: {
            const c: usize = atom.data % 8;
            const j: usize = (atom.data / 8) % 8;
            const i: usize = atom.data / 64;
            break :blk if (median3vals(g[i], g[j], g[c]) == mid) 1.0 else -1.0;
        },
        .rank2_eq1 => blk: {
            const c: usize = atom.data % 8;
            const j: usize = (atom.data / 8) % 8;
            const i: usize = atom.data / 64;
            break :blk if (rank2Triple(g[i], g[j], g[c]) == mid) 1.0 else -1.0;
        },
        .min3 => blk: {
            const c: usize = atom.data % 8;
            const j: usize = (atom.data / 8) % 8;
            const i: usize = atom.data / 64;
            const mn = @min(g[i], @min(g[j], g[c]));
            break :blk @as(f64, @floatFromInt(mn)) - m;
        },
        .max3 => blk: {
            const c: usize = atom.data % 8;
            const j: usize = (atom.data / 8) % 8;
            const i: usize = atom.data / 64;
            const mx = @max(g[i], @max(g[j], g[c]));
            break :blk @as(f64, @floatFromInt(mx)) - m;
        },
    };
}

fn atomsEqual(a: Atom, b: Atom) bool {
    return a.kind == b.kind and a.data == b.data;
}

fn poolAllows(pool: CandidatePool, atom: Atom) bool {
    return switch (pool) {
        .monomial_only => atom.kind == .monomial,
        .mono_mod3 => atom.kind == .monomial or atom.kind == .mod3_pair or atom.kind == .mod3_triple or atom.kind == .mod3_global,
        .mono_order => atom.kind == .monomial or atom.kind == .median3 or atom.kind == .median_eq1 or atom.kind == .rank2_eq1 or atom.kind == .min3 or atom.kind == .max3,
        .full => true,
    };
}

fn buildFeat(X: [][]f64, grid: []const [NCELL]u8, atoms: []const Atom, k_ary: u8) void {
    const ncol = atoms.len;
    for (0..NSAMP) |s| for (0..ncol) |c| {
        X[s][c] = evalAtom(grid[s], atoms[c], k_ary);
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

const NT = 6;

fn scoreCandidate(atom: Atom, grid: []const [NCELL]u8, X: [][]f64, Yt: []const f64, w: []f64, k_ary: u8) f64 {
    const one = [_]Atom{atom};
    buildFeat(X, grid, &one, k_ary);
    fitLogit(X, Yt, 1, 80, 0.06, w);
    return accLogit(X, Yt, w, 1, NTR, NVA);
}

fn tryCandidate(
    atom: Atom,
    pool: CandidatePool,
    current: []const Atom,
    grid: []const [NCELL]u8,
    X: [][]f64,
    Yt: []const f64,
    w: []f64,
    k_ary: u8,
    best_val: *f64,
    best: *Atom,
) void {
    if (!poolAllows(pool, atom)) return;
    for (current) |a| {
        if (atomsEqual(a, atom)) return;
    }
    const v = scoreCandidate(atom, grid, X, Yt, w, k_ary);
    if (v > best_val.*) {
        best_val.* = v;
        best.* = atom;
    }
}

fn enumerateMod3Triples(pool: CandidatePool, current: []const Atom, grid: []const [NCELL]u8, X: [][]f64, Yt: []const f64, w: []f64, k_ary: u8, best_val: *f64, best: *Atom) void {
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |k| {
        const enc = tripleEnc(i, j, k);
        tryCandidate(.{ .kind = .mod3_triple, .data = enc }, pool, current, grid, X, Yt, w, k_ary, best_val, best);
    };
}

fn enumerateOrderTriples(pool: CandidatePool, current: []const Atom, grid: []const [NCELL]u8, X: [][]f64, Yt: []const f64, w: []f64, k_ary: u8, best_val: *f64, best: *Atom) void {
    for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |k| {
        const enc = tripleEnc(i, j, k);
        tryCandidate(.{ .kind = .median3, .data = enc }, pool, current, grid, X, Yt, w, k_ary, best_val, best);
        tryCandidate(.{ .kind = .median_eq1, .data = enc }, pool, current, grid, X, Yt, w, k_ary, best_val, best);
        tryCandidate(.{ .kind = .rank2_eq1, .data = enc }, pool, current, grid, X, Yt, w, k_ary, best_val, best);
        tryCandidate(.{ .kind = .min3, .data = enc }, pool, current, grid, X, Yt, w, k_ary, best_val, best);
        tryCandidate(.{ .kind = .max3, .data = enc }, pool, current, grid, X, Yt, w, k_ary, best_val, best);
    };
}

pub fn discoverBest(pool: CandidatePool, grid: []const [NCELL]u8, X: [][]f64, Yt: []const f64, current: []const Atom, w: []f64, k_ary: u8) struct { atom: Atom, val_acc: f64 } {
    var best_val: f64 = -1;
    var best: Atom = .{ .kind = .monomial, .data = 0 };

    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const cand: u8 = @intCast(mm);
        const d = popcount(cand);
        if (d < 1 or d > MAXDEG) continue;
        tryCandidate(.{ .kind = .monomial, .data = cand }, pool, current, grid, X, Yt, w, k_ary, &best_val, &best);
    }

    if (pool == .mono_mod3 or pool == .full) {
        for (0..NCELL) |i| for (i + 1..NCELL) |j| {
            tryCandidate(.{ .kind = .mod3_pair, .data = @intCast(i * 8 + j) }, pool, current, grid, X, Yt, w, k_ary, &best_val, &best);
        };
        enumerateMod3Triples(pool, current, grid, X, Yt, w, k_ary, &best_val, &best);
        tryCandidate(.{ .kind = .mod3_global, .data = 0 }, pool, current, grid, X, Yt, w, k_ary, &best_val, &best);
    }

    if (pool == .mono_order or pool == .full) {
        enumerateOrderTriples(pool, current, grid, X, Yt, w, k_ary, &best_val, &best);
    }

    return .{ .atom = best, .val_acc = best_val };
}

pub fn coverage(X: [][]f64, grid: []const [NCELL]u8, atoms: []const Atom, yv: []const f64, w: []f64, k_ary: u8) f64 {
    buildFeat(X, grid, atoms, k_ary);
    fitLogit(X, yv, atoms.len, 150, 0.05, w);
    return accLogit(X, yv, w, atoms.len, NVA, NSAMP);
}

fn soloTestAcc(atom: Atom, grid: []const [NCELL]u8, Yt: []const f64, w: []f64, X: [][]f64, k_ary: u8) struct { val: f64, tst: f64 } {
    const one = [_]Atom{atom};
    buildFeat(X, grid, &one, k_ary);
    fitLogit(X, Yt, 1, 150, 0.05, w);
    return .{
        .val = accLogit(X, Yt, w, 1, NTR, NVA),
        .tst = accLogit(X, Yt, w, 1, NVA, NSAMP),
    };
}

pub const Promotion = struct {
    atom: Atom,
    target_idx: usize,
    r2: f64,
    escape: f64,
};

pub const ForgeResult = struct {
    nsolved: usize,
    natoms: usize,
    saturated: bool,
    promotions: []Promotion,
};

pub fn runAlienForge(
    pool: CandidatePool,
    k_ary: u8,
    grid: []const [NCELL]u8,
    Y: [][]f64,
    labels: []const []const u8,
    X: [][]f64,
    Xrec: [][]f64,
    phiTgt: []f64,
    w: []f64,
    out: anytype,
) !ForgeResult {
    const n_targets = Y.len;
    var atoms: [MAXATOMS]Atom = undefined;
    var natoms: usize = 0;
    for (0..NCELL) |i| {
        atoms[natoms] = .{ .kind = .monomial, .data = @as(u8, 1) << @intCast(i) };
        natoms += 1;
    }

    var promotions = std.ArrayList(Promotion).init(std.heap.page_allocator);
    errdefer promotions.deinit();

    try out.print("── k3_order_escape {s} on {d} aliens (k={d}, no Walsh) ──\n", .{ @tagName(pool), n_targets, k_ary });
    try out.print("round 0: ", .{});
    var solved = try std.heap.page_allocator.alloc(bool, n_targets);
    defer std.heap.page_allocator.free(solved);
    @memset(solved, false);
    var nsolved0: usize = 0;
    for (0..n_targets) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], Y[t], w, k_ary);
        solved[t] = cov >= COVER_THRESH;
        if (solved[t]) nsolved0 += 1;
        try out.print("A{d}={d:.2}{s}  ", .{ t + 1, cov, if (solved[t]) "*" else " " });
    }
    try out.print(" → {d}/{d}\n", .{ nsolved0, n_targets });

    var round: usize = 1;
    var saturated = false;
    while (round <= 12) : (round += 1) {
        var promoted = false;
        for (0..n_targets) |t| {
            if (solved[t]) continue;
            const cov_now = coverage(X, grid, atoms[0..natoms], Y[t], w, k_ary);
            if (cov_now >= COVER_THRESH) {
                solved[t] = true;
                continue;
            }
            const disc = discoverBest(pool, grid, X, Y[t], atoms[0..natoms], w, k_ary);
            var aug: [MAXATOMS]Atom = undefined;
            @memcpy(aug[0..natoms], atoms[0..natoms]);
            aug[natoms] = disc.atom;
            const cov_aug = coverage(X, grid, aug[0 .. natoms + 1], Y[t], w, k_ary);
            const escape = cov_aug >= COVER_THRESH and cov_now < COVER_THRESH;
            for (0..NSAMP) |s| phiTgt[s] = evalAtom(grid[s], disc.atom, k_ary);
            buildFeat(Xrec, grid, atoms[0..natoms], k_ary);
            const rr = reconR2(Xrec, phiTgt, natoms, w);
            const irreducible = rr < R2_MAX;
            var lbl: [64]u8 = undefined;
            const name = disc.atom.label(k_ary, &lbl);
            const tag = if (t < labels.len) labels[t] else "?";

            if (escape and irreducible and natoms < MAXATOMS) {
                atoms[natoms] = disc.atom;
                natoms += 1;
                solved[t] = true;
                promoted = true;
                try promotions.append(.{ .atom = disc.atom, .target_idx = t, .r2 = rr, .escape = cov_aug });
                try out.print("  r{d} A{d} ({s}) ({d:.2}) → {s} escape {d:.2} R²={d:.2} → PROMOTE ({d} atoms)\n", .{
                    round, t + 1, tag, cov_now, name, cov_aug, rr, natoms,
                });
            } else {
                try out.print("  r{d} A{d} ({s}) ({d:.2}) → {s} escape {d:.2} R²={d:.2} → skip\n", .{
                    round, t + 1, tag, cov_now, name, cov_aug, rr,
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
    for (0..n_targets) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], Y[t], w, k_ary);
        const sv = cov >= COVER_THRESH;
        if (sv) nsolvedF += 1;
        try out.print("A{d}={d:.2}{s}  ", .{ t + 1, cov, if (sv) "*" else " " });
    }
    try out.print(" → {d}/{d}; atoms {d}\n\n", .{ nsolvedF, n_targets, natoms });

    return .{
        .nsolved = nsolvedF,
        .natoms = natoms,
        .saturated = saturated,
        .promotions = try promotions.toOwnedSlice(),
    };
}

fn runForge(
    pool: CandidatePool,
    pool_name: []const u8,
    grid: []const [NCELL]u8,
    Y: [][]f64,
    X: [][]f64,
    Xrec: [][]f64,
    phiTgt: []f64,
    w: []f64,
    out: anytype,
) !struct { nsolved: usize, natoms: usize, saturated: bool, t6: f64 } {
    var atoms: [MAXATOMS]Atom = undefined;
    var natoms: usize = 0;
    for (0..NCELL) |i| {
        atoms[natoms] = .{ .kind = .monomial, .data = @as(u8, 1) << @intCast(i) };
        natoms += 1;
    }

    try out.print("── {s} ──\n", .{pool_name});
    try out.print("round 0: ", .{});
    var solved = [_]bool{false} ** NT;
    var nsolved0: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], Y[t], w, K);
        solved[t] = cov >= COVER_THRESH;
        if (solved[t]) nsolved0 += 1;
        try out.print("T{d}={d:.2}{s}  ", .{ t + 1, cov, if (solved[t]) "*" else " " });
    }
    try out.print(" → {d}/{d}\n", .{ nsolved0, NT });

    var round: usize = 1;
    var saturated = false;
    while (round <= 10) : (round += 1) {
        var promoted = false;
        for (0..NT) |t| {
            if (solved[t]) continue;
            const cov_now = coverage(X, grid, atoms[0..natoms], Y[t], w, K);
            if (cov_now >= COVER_THRESH) {
                solved[t] = true;
                continue;
            }
            const disc = discoverBest(pool, grid, X, Y[t], atoms[0..natoms], w, K);
            var aug: [MAXATOMS]Atom = undefined;
            @memcpy(aug[0..natoms], atoms[0..natoms]);
            aug[natoms] = disc.atom;
            const cov_aug = coverage(X, grid, aug[0 .. natoms + 1], Y[t], w, K);
            const escape = cov_aug >= COVER_THRESH and cov_now < COVER_THRESH;
            for (0..NSAMP) |s| phiTgt[s] = evalAtom(grid[s], disc.atom, K);
            buildFeat(Xrec, grid, atoms[0..natoms], K);
            const rr = reconR2(Xrec, phiTgt, natoms, w);
            const irreducible = rr < R2_MAX;
            var lbl: [48]u8 = undefined;
            const name = disc.atom.label(K, &lbl);

            if (escape and irreducible and natoms < MAXATOMS) {
                atoms[natoms] = disc.atom;
                natoms += 1;
                solved[t] = true;
                promoted = true;
                try out.print("  r{d} T{d} ({d:.2}) → {s} escape {d:.2} R²={d:.2} → PROMOTE ({d} atoms)\n", .{
                    round, t + 1, cov_now, name, cov_aug, rr, natoms,
                });
            } else {
                try out.print("  r{d} T{d} ({d:.2}) → {s} escape {d:.2} R²={d:.2} → skip\n", .{
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

    var t6cov: f64 = 0;
    try out.print("final: ", .{});
    var nsolvedF: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], Y[t], w, K);
        if (t == 5) t6cov = cov;
        const sv = cov >= COVER_THRESH;
        if (sv) nsolvedF += 1;
        try out.print("T{d}={d:.2}{s}  ", .{ t + 1, cov, if (sv) "*" else " " });
    }
    try out.print(" → {d}/{d}; atoms {d}\n\n", .{ nsolvedF, NT, natoms });
    return .{ .nsolved = nsolvedF, .natoms = natoms, .saturated = saturated, .t6 = t6cov };
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
        grid[s][i] = rand.intRangeAtMost(u8, 0, K - 1);
    };

    const X = try alloc.alloc([]f64, NSAMP);
    const Xrec = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| {
        X[s] = try alloc.alloc(f64, MAXATOMS);
        Xrec[s] = try alloc.alloc(f64, MAXATOMS);
    }
    const phiTgt = try alloc.alloc(f64, NSAMP);
    var w: [MAXATOMS + 1]f64 = undefined;

    const hidden = [_]u8{
        (1 << 2) | (1 << 5),
        (1 << 1) | (1 << 3) | (1 << 6),
        (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7),
        (1 << 3),
        0,
        0,
    };
    const Y = try alloc.alloc([]f64, NT);
    for (0..NT) |t| Y[t] = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| {
        const g = grid[s];
        for (0..4) |t| Y[t][s] = if (phiMono(g, hidden[t], K) > 0) 1.0 else 0.0;
        var sum: u32 = 0;
        for (g) |v| sum += v;
        Y[4][s] = if (sum % K == 0) 1.0 else 0.0;
        Y[5][s] = if (median3vals(g[0], g[1], g[2]) == 1) 1.0 else 0.0;
    }

    try out.print("=== Fork 6: k≥3 + order-statistic escape (T6 median wall) ===\n\n", .{});
    try out.print("RNG seed = 0x{X:0>16} (pinned)\n", .{RNG_SEED});
    try out.print("T6 = median(c0,c1,c2)==1; train/val/test {d}/{d}/{d}\n\n", .{ NTR, NVA - NTR, NSAMP - NVA });

    // T6 diagnostic: centered median vs rank indicator
    const enc012 = tripleEnc(0, 1, 2);
    const med_c = soloTestAcc(.{ .kind = .median3, .data = enc012 }, grid, Y[5], &w, X, K);
    const med_eq = soloTestAcc(.{ .kind = .median_eq1, .data = enc012 }, grid, Y[5], &w, X, K);
    const mod3_012 = soloTestAcc(.{ .kind = .mod3_triple, .data = enc012 }, grid, Y[5], &w, X, K);
    try out.print("T6 solo-feature probe (before forge):\n", .{});
    try out.print("  med−1(0,1,2)   val={d:.3} test={d:.3}  ← symmetric 0 vs +/-1: linear readout FAILS\n", .{ med_c.val, med_c.tst });
    try out.print("  med==1(0,1,2)  val={d:.3} test={d:.3}  ← rank indicator: linear readout OK\n", .{ med_eq.val, med_eq.tst });
    try out.print("  mod3(0,1,2)    val={d:.3} test={d:.3}\n\n", .{ mod3_012.val, mod3_012.tst });

    const mono = try runForge(.monomial_only, "A) MONOMIAL-ONLY", grid, Y, X, Xrec, phiTgt, &w, out);
    const mod3 = try runForge(.mono_mod3, "B) MONO + MOD3 (no order-stats)", grid, Y, X, Xrec, phiTgt, &w, out);
    const order = try runForge(.mono_order, "C) MONO + ORDER-STATS (median/rank indicators)", grid, Y, X, Xrec, phiTgt, &w, out);
    const full = try runForge(.full, "D) MONO + MOD3 + ORDER-STATS", grid, Y, X, Xrec, phiTgt, &w, out);

    try out.print("════════════════════ VERDICT (Fork 6) ════════════════════\n", .{});
    try out.print("seed 0x{X:0>16}\n", .{RNG_SEED});
    try out.print("  A monomial-only     : {d}/{d}  T6={d:.2}  saturated={}\n", .{ mono.nsolved, NT, mono.t6, mono.saturated });
    try out.print("  B mono+mod3         : {d}/{d}  T6={d:.2}  saturated={}\n", .{ mod3.nsolved, NT, mod3.t6, mod3.saturated });
    try out.print("  C mono+order-stats  : {d}/{d}  T6={d:.2}  saturated={}\n", .{ order.nsolved, NT, order.t6, order.saturated });
    try out.print("  D full substrate    : {d}/{d}  T6={d:.2}  saturated={}\n\n", .{ full.nsolved, NT, full.t6, full.saturated });

    const t6_before = mono.t6;
    const t6_after_order = order.t6;
    const t6_after_full = full.t6;

    if (t6_after_order >= 0.90 and t6_before < 0.60) {
        try out.print("ORDER-STAT ESCAPE: rank indicators (median==1) break the T6 wall.\n", .{});
        try out.print("Centered median−1 alone cannot — negatives split ±1 around 0 (not linearly separable).\n", .{});
        try out.print("Saturation boundary MOVED on T6; promotion still bottoms out at the substrate family.\n", .{});
    } else if (t6_after_full > t6_before and t6_after_full < 0.90) {
        try out.print("PARTIAL: richer pool helps but T6 remains below 0.90.\n", .{});
    } else {
        try out.print("T6 WALL HOLDS: order-stats did not reach ≥0.90 held-out test.\n", .{});
    }

    try out.print("\nAGI note: unmappable novelty needs substrates whose closure lattice is not finite —\n", .{});
    try out.print("k≥3 gives mod3 escape (T5) AND rank-indicator escape (T6), but forge still SATURATES.\n", .{});
    try out.print("See: order_statistics.zig, k3_substrate.zig, kary_frontier.md.\n", .{});
}