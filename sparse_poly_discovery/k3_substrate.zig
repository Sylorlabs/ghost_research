//! Direction 4 — minimal k=3 substrate experiment: does promotion saturation change outside Boolean k=2?
//!
//! Mirrors inner_forge.zig on a 3-valued grid {0,1,2} with an expanded inner-transform family:
//!   • monomials φ_S = Π_{i∈S} (c_i − 1)          [Boolean-analog, deg 1..4]
//!   • mod3_pair(i,j)   = (c_i + c_j) mod 3 − 1    [ternary binding]
//!   • mod3_triple(i,j,k)= (c_i+c_j+c_k) mod 3 − 1
//!   • median3(i,j,k)   = median{c_i,c_j,c_k} − 1 [centered — NOT linearly separable for T6]
//!   • median_eq1(i,j,k)= +1 iff median==1 else −1 [rank indicator — escapes T6]
//!
//! Target zoo (logistic readout, ≥0.90 held-out test = solved):
//!   T1–T4  monomial signs (deg 2,3,4,1) — in monomial closure
//!   T5     (Σ c_i) mod 3 == 0             — ternary parity, NOT monomial / Boolean
//!   T6     median(c0,c1,c2) == 1          — rank statistic, NOT monomial
//!
//! Forge: same certified promotion as Phase C — irreducible (R²<0.40) AND useful (escape ≥0.90).
//! Compare saturation: monomial-only pass vs full k=3 candidate pool.
//!
//! Run: zig build k3-substrate --release=fast

const std = @import("std");

const NCELL: usize = 8;
const K: u8 = 3;
const MID: f64 = 1.0; // center of {0,1,2}
const NSAMP: usize = 5000;
const NTR: usize = 2500;
const NVA: usize = 3750;
const MAXATOMS: usize = 32;
const MAXDEG: usize = 4;

const AtomKind = enum { monomial, mod3_pair, mod3_triple, median3, median_eq1, mod3_global };

const Atom = struct {
    kind: AtomKind,
    data: u8, // monomial: bitmask; pair: i*8+j; triple: i*64+j*8+k

    fn label(self: Atom, buf: []u8) []const u8 {
        return switch (self.kind) {
            .monomial => std.fmt.bufPrint(buf, "mono 0x{X:0>2}", .{self.data}) catch "?",
            .mod3_pair => std.fmt.bufPrint(buf, "mod3({d},{d})", .{ self.data / 8, self.data % 8 }) catch "?",
            .mod3_triple => blk: {
                const k = self.data % 8;
                const j = (self.data / 8) % 8;
                const i = self.data / 64;
                break :blk std.fmt.bufPrint(buf, "mod3({d},{d},{d})", .{ i, j, k }) catch "?";
            },
            .median3 => blk: {
                const k = self.data % 8;
                const j = (self.data / 8) % 8;
                const i = self.data / 64;
                break :blk std.fmt.bufPrint(buf, "med({d},{d},{d})", .{ i, j, k }) catch "?";
            },
            .median_eq1 => blk: {
                const k = self.data % 8;
                const j = (self.data / 8) % 8;
                const i = self.data / 64;
                break :blk std.fmt.bufPrint(buf, "med==1({d},{d},{d})", .{ i, j, k }) catch "?";
            },
            .mod3_global => "mod3(Σall)",
        };
    }
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

fn median3vals(a: u8, b: u8, c: u8) u8 {
    if ((a <= b and b <= c) or (c <= b and b <= a)) return b;
    if ((b <= a and a <= c) or (c <= a and a <= b)) return a;
    return c;
}

fn evalAtom(g: [NCELL]u8, atom: Atom) f64 {
    return switch (atom.kind) {
        .monomial => phiMono(g, atom.data),
        .mod3_pair => blk: {
            const i: usize = atom.data / 8;
            const j: usize = atom.data % 8;
            const s = (g[i] + g[j]) % K;
            break :blk @as(f64, @floatFromInt(s)) - MID;
        },
        .mod3_triple => blk: {
            const k: usize = atom.data % 8;
            const j: usize = (atom.data / 8) % 8;
            const i: usize = atom.data / 64;
            const s = (g[i] + g[j] + g[k]) % K;
            break :blk @as(f64, @floatFromInt(s)) - MID;
        },
        .median3 => blk: {
            const k: usize = atom.data % 8;
            const j: usize = (atom.data / 8) % 8;
            const i: usize = atom.data / 64;
            break :blk @as(f64, @floatFromInt(median3vals(g[i], g[j], g[k]))) - MID;
        },
        .median_eq1 => blk: {
            const k: usize = atom.data % 8;
            const j: usize = (atom.data / 8) % 8;
            const i: usize = atom.data / 64;
            break :blk if (median3vals(g[i], g[j], g[k]) == 1) 1.0 else -1.0;
        },
        .mod3_global => blk: {
            var sum: u32 = 0;
            for (g) |v| sum += v;
            break :blk @as(f64, @floatFromInt(sum % K)) - MID;
        },
    };
}

fn atomsEqual(a: Atom, b: Atom) bool {
    return a.kind == b.kind and a.data == b.data;
}

fn buildFeat(X: [][]f64, grid: []const [NCELL]u8, atoms: []const Atom) void {
    const k = atoms.len;
    for (0..NSAMP) |s| for (0..k) |c| {
        X[s][c] = evalAtom(grid[s], atoms[c]);
    };
    for (0..k) |c| {
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

const NT = 6;

const CandidatePool = enum { monomial_only, full_k3 };

fn inPool(pool: CandidatePool, atom: Atom) bool {
    return switch (pool) {
        .monomial_only => atom.kind == .monomial,
        .full_k3 => true,
    };
}

fn scoreCandidate(
    atom: Atom,
    grid: []const [NCELL]u8,
    X: [][]f64,
    Yt: []const f64,
    w: []f64,
) f64 {
    const one = [_]Atom{atom};
    buildFeat(X, grid, &one);
    fitLogit(X, Yt, 1, 40, 0.06, w);
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
    best_val: *f64,
    best: *Atom,
) void {
    if (!inPool(pool, atom)) return;
    for (current) |a| {
        if (atomsEqual(a, atom)) return;
    }
    const v = scoreCandidate(atom, grid, X, Yt, w);
    if (v > best_val.*) {
        best_val.* = v;
        best.* = atom;
    }
}

fn discoverBest(
    pool: CandidatePool,
    grid: []const [NCELL]u8,
    X: [][]f64,
    Yt: []const f64,
    current: []const Atom,
    w: []f64,
) struct { atom: Atom, val_acc: f64 } {
    var best_val: f64 = -1;
    var best: Atom = .{ .kind = .monomial, .data = 0 };

    var mm: u16 = 1;
    while (mm < 256) : (mm += 1) {
        const cand: u8 = @intCast(mm);
        const d = popcount(cand);
        if (d < 1 or d > MAXDEG) continue;
        tryCandidate(.{ .kind = .monomial, .data = cand }, pool, current, grid, X, Yt, w, &best_val, &best);
    }

    if (pool == .full_k3) {
        for (0..NCELL) |i| for (i + 1..NCELL) |j| {
            tryCandidate(.{ .kind = .mod3_pair, .data = @intCast(i * 8 + j) }, pool, current, grid, X, Yt, w, &best_val, &best);
        };
        // all C(8,3) triples for order-stats + mod3 (Fork 6: median_eq1 escapes T6 wall)
        for (0..NCELL) |i| for (i + 1..NCELL) |j| for (j + 1..NCELL) |k| {
            const enc: u8 = @intCast(i * 64 + j * 8 + k);
            tryCandidate(.{ .kind = .mod3_triple, .data = enc }, pool, current, grid, X, Yt, w, &best_val, &best);
            tryCandidate(.{ .kind = .median3, .data = enc }, pool, current, grid, X, Yt, w, &best_val, &best);
            tryCandidate(.{ .kind = .median_eq1, .data = enc }, pool, current, grid, X, Yt, w, &best_val, &best);
        };
        tryCandidate(.{ .kind = .mod3_global, .data = 0 }, pool, current, grid, X, Yt, w, &best_val, &best);
    }

    return .{ .atom = best, .val_acc = best_val };
}

fn coverage(X: [][]f64, grid: []const [NCELL]u8, atoms: []const Atom, yv: []const f64, w: []f64) f64 {
    buildFeat(X, grid, atoms);
    fitLogit(X, yv, atoms.len, 150, 0.05, w);
    return accLogit(X, yv, w, atoms.len, NVA, NSAMP);
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
) !struct { nsolved: usize, natoms: usize, saturated: bool } {
    var atoms: [MAXATOMS]Atom = undefined;
    var natoms: usize = 0;
    for (0..NCELL) |i| {
        atoms[natoms] = .{ .kind = .monomial, .data = @as(u8, 1) << @intCast(i) };
        natoms += 1;
    }

    try out.print("── forge: {s} ──\n", .{pool_name});
    try out.print("round 0 (8 singleton monomials): ", .{});
    var solved = [_]bool{false} ** NT;
    var nsolved0: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], Y[t], w);
        solved[t] = cov >= 0.90;
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
            const cov_now = coverage(X, grid, atoms[0..natoms], Y[t], w);
            if (cov_now >= 0.90) {
                solved[t] = true;
                continue;
            }
            const disc = discoverBest(pool, grid, X, Y[t], atoms[0..natoms], w);
            var aug: [MAXATOMS]Atom = undefined;
            @memcpy(aug[0..natoms], atoms[0..natoms]);
            aug[natoms] = disc.atom;
            const cov_aug = coverage(X, grid, aug[0 .. natoms + 1], Y[t], w);
            const escape = cov_aug >= 0.90 and cov_now < 0.90;
            for (0..NSAMP) |s| phiTgt[s] = evalAtom(grid[s], disc.atom);
            buildFeat(Xrec, grid, atoms[0..natoms]);
            const rr = reconR2(Xrec, phiTgt, natoms, w);
            const irreducible = rr < 0.40;
            var lbl: [48]u8 = undefined;
            const name = disc.atom.label(&lbl);

            if (escape and irreducible and natoms < MAXATOMS) {
                atoms[natoms] = disc.atom;
                natoms += 1;
                solved[t] = true;
                promoted = true;
                try out.print("  r{d} T{d} ({d:.2}) → {s} escape {d:.2} R²={d:.2} → PROMOTE (atoms {d})\n", .{
                    round, t + 1, cov_now, name, cov_aug, rr, natoms,
                });
            } else {
                try out.print("  r{d} T{d} ({d:.2}) → {s} escape {d:.2} R²={d:.2} → skip\n", .{
                    round, t + 1, cov_now, name, cov_aug, rr,
                });
            }
        }
        if (!promoted) {
            try out.print("  r{d}: full pass promoted NOTHING → SATURATED\n", .{round});
            saturated = true;
            break;
        }
    }

    try out.print("final: ", .{});
    var nsolvedF: usize = 0;
    for (0..NT) |t| {
        const cov = coverage(X, grid, atoms[0..natoms], Y[t], w);
        const sv = cov >= 0.90;
        if (sv) nsolvedF += 1;
        try out.print("T{d}={d:.2}{s}  ", .{ t + 1, cov, if (sv) "*" else " " });
    }
    try out.print(" → {d}/{d}; atoms {d}\n\n", .{ nsolvedF, NT, natoms });
    return .{ .nsolved = nsolvedF, .natoms = natoms, .saturated = saturated };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0xC3F0A6E01CEF);
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
        for (0..4) |t| Y[t][s] = if (phiMono(g, hidden[t]) > 0) 1.0 else 0.0;
        var sum: u32 = 0;
        for (g) |v| sum += v;
        Y[4][s] = if (sum % K == 0) 1.0 else 0.0;
        Y[5][s] = if (median3vals(g[0], g[1], g[2]) == 1) 1.0 else 0.0;
    }

    try out.print("=== Direction 4: minimal k=3 substrate — does saturation change? ===\n\n", .{});
    try out.print("grid: 8 cells ∈ {{0,1,2}}; base atoms = 8 centered monomial singletons.\n", .{});
    try out.print("T1–T4 monomial signs; T5 (Σc) mod 3; T6 median(c0,c1,c2)==1 (non-monomial).\n", .{});
    try out.print("train/val/test {d}/{d}/{d}\n\n", .{ NTR, NVA - NTR, NSAMP - NVA });

    const mono = try runForge(.monomial_only, "MONOMIAL-ONLY (k=2-style closure)", grid, Y, X, Xrec, phiTgt, &w, out);
    const full = try runForge(.full_k3, "FULL k=3 pool (mono + mod3 + median)", grid, Y, X, Xrec, phiTgt, &w, out);

    try out.print("════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("monomial-only: {d}/{d} solved, saturated={}; atoms={d}\n", .{ mono.nsolved, NT, mono.saturated, mono.natoms });
    try out.print("full k=3 pool: {d}/{d} solved, saturated={}; atoms={d}\n\n", .{ full.nsolved, NT, full.saturated, full.natoms });

    if (mono.nsolved == 4 and full.nsolved > mono.nsolved) {
        try out.print("k≥3 CHANGES escape: mod3 lifts T5; median_eq1 (rank indicator) lifts T6.\n", .{});
        try out.print("Centered median−1 fails T6 (0 vs ±1 not linearly separable); see k3_order_escape.zig.\n", .{});
        try out.print("Saturation boundary MOVED to {d}/{d} — promotion still bottoms out (saturated={}).\n", .{ full.nsolved, NT, full.saturated });
        try out.print("Uncountable clone lattice ≠ unbounded forge; richer primitives, same saturation law.\n", .{});
    } else if (mono.nsolved == full.nsolved and mono.saturated and full.saturated) {
        try out.print("NO CHANGE in saturation outcome: both passes bottom out; cross-family targets stay hard.\n", .{});
        try out.print("k=3 value domain alone does not break the promotion-saturation law.\n", .{});
    } else {
        try out.print("MIXED: inspect per-target coverage above. k≥3 pool may partially shift the ceiling.\n", .{});
    }
    try out.print("\nContrast inner-forge (k=2 cells 0..5): expect 4/5 monomial + T5 parity stuck.\n", .{});
    try out.print("See: kary_frontier.md, inner_forge.zig, inventable_substrate_design.md.\n", .{});
}