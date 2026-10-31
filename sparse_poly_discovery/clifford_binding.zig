//! RQ A10 — multi-seed replication (2026-07-10): does replacing the XOR/bundle
//! binding with a Clifford geometric-product binding break the band-readout ceiling?
//!
//! STANDALONE by design (hard constraint: touch no existing file). All needed code
//! is ported inline:
//!   - the stock XOR EnvEncoder recipe (agent.zig EnvEncoder, random fillers,
//!     failed=false path) — one role per cell, bind = XOR, folded into ONE 8192-bit
//!     vector; this is the substrate whose linear-probe band accuracy is provably
//!     stuck at ~0.51 (closure_escape_control.md, dynamics_probe).
//!   - the Cl(13,0) geometric-product encoder (clifford_closure.zig): role P_i a
//!     random unit multivector, filler a rotor R_i(v) = cos(v*theta) + sin(v*theta)*B_i,
//!     bind = geometric product, bundle = sum. 2^13 = 8192 blades = same width as
//!     the XOR substrate, so any difference is the ALGEBRA, not the dimension budget.
//!   - a Hadamard-real control (bind = scale role by value, bundle = sum): real and
//!     magnitude-carrying but NOT Clifford. Distinguishes "geometric product" from
//!     merely "leave GF(2)".
//!
//! Three arms (task spec), same grids / labels / readout protocol per seed:
//!   (a) XOR/bundle baseline: nearest-prototype readout AND raw linear probe
//!       (perceptron over all 8192 bits) AND standardized logistic. Must reproduce
//!       ~0.51 or the port is wrong.
//!   (b) Clifford encoding + the SAME standardized logistic linear readout.
//!   (c) Linear probe (perceptron, scale-invariant) over the RAW Clifford encoding
//!       — no per-column standardization, so a win cannot be a conditioning gift.
//!
//! Controls:
//!   - shuffle-label: permute band labels (train+test coherently), retrain the
//!     Clifford logistic readout. Must land at the majority base rate, else the
//!     encoding/protocol leaks the answer.
//!   - Hadamard-real arm: if it matches Clifford, the lever is "leave GF(2)",
//!     not the geometric product (the prior single-seed finding).
//!
//! Protocol: 6 seeds, 4000 grids each (cells iid uniform 0..6), 50/50 train/test.
//! Predicates: band = mass in [16,48] (primary); sum >= 48 (secondary, linear).
//! Single-threaded. Run from repo root; writes results/a10_clifford_2026_07_10.csv.
//!
//! Build:  zig build-exe -O ReleaseFast sparse_poly_discovery/clifford_binding.zig
//! Run:    ./clifford_binding [csv_path]

const std = @import("std");

// ---------------------------------------------------------------- constants
const D: usize = 8192; // hypervector bits (hypervector.zig: D)
const Blocks: usize = 128; // D / 64
const HV = [Blocks]u64;

const NCELL = 16;
const VMAX = 6; // cell values 0..6; mass 0..96 centered ~48
const BandLo: u32 = 16;
const BandHi: u32 = 48;
const SumK: u32 = 48;

const NQ: u4 = 13;
const BLADES: usize = 1 << NQ; // 8192 = same width as the XOR substrate

const NSEEDS = 6;
const NSAMP = 4000; // same count as the original ceiling experiment
const EPOCHS = 20;

// ---------------------------------------------------------------- XOR substrate
// Ported from hypervector.zig (bind = XOR) + agent.zig EnvEncoder (random fillers,
// ordinal=false), encode path with failed=false.
fn hvRandom(rand: std.Random) HV {
    var arr: HV = undefined;
    for (&arr) |*b| b.* = rand.int(u64);
    return arr;
}

inline fn hvBind(a: HV, b: HV) HV {
    var r: HV = undefined;
    for (0..Blocks) |i| r[i] = a[i] ^ b[i];
    return r;
}

const XorEnc = struct {
    P: [NCELL]HV, // one role per grid cell
    V: [VMAX + 1]HV, // random value fillers (stock, no metric structure)
    P_fail: HV,
    V_false: HV,

    fn init(rand: std.Random) XorEnc {
        var e: XorEnc = undefined;
        for (0..NCELL) |i| e.P[i] = hvRandom(rand);
        for (0..VMAX + 1) |i| e.V[i] = hvRandom(rand);
        e.P_fail = hvRandom(rand);
        e.V_false = hvRandom(rand);
        return e;
    }

    // Stock recipe: s = P_fail; s ^= P_i ^ V[g_i] per cell; s ^= P_fail ^ V_false.
    fn encode(self: *const XorEnc, g: [NCELL]u8, out: []f32) void {
        var s = self.P_fail;
        for (0..NCELL) |i| s = hvBind(s, hvBind(self.P[i], self.V[g[i]]));
        s = hvBind(s, hvBind(self.P_fail, self.V_false));
        for (0..D) |j| {
            const bit: u1 = @intCast((s[j / 64] >> @intCast(j % 64)) & 1);
            out[j] = if (bit == 1) 1.0 else -1.0;
        }
    }
};

// ---------------------------------------------------------------- Clifford substrate
// Euclidean reordering sign for the geometric product of blades a and b (e_i^2 = +1).
inline fn reorderSign(a0: u16, b: u16) f32 {
    var a = a0 >> 1;
    var sum: u32 = 0;
    while (a != 0) {
        sum += @popCount(a & b);
        a >>= 1;
    }
    return if (sum & 1 == 0) @as(f32, 1.0) else @as(f32, -1.0);
}

// out = mv * (single blade) under the geometric product. Rotor fillers are sparse
// (scalar + one bivector) so binding never needs the full 8192x8192 product.
fn geoBlade(mv: []const f32, blade: u16, out: []f32) void {
    @memset(out, 0);
    for (0..BLADES) |a| {
        const c = mv[a];
        if (c == 0) continue;
        const r = @as(u16, @intCast(a)) ^ blade;
        out[r] += reorderSign(@intCast(a), blade) * c;
    }
}

const CliffEnc = struct {
    P: [][]f32, // [NCELL][BLADES] random unit multivector roles
    PB: [][]f32, // [NCELL][BLADES] precomputed P_i * B_i
    theta: f32,

    fn init(alloc: std.mem.Allocator, rand: std.Random) !CliffEnc {
        var e: CliffEnc = .{
            .P = try alloc.alloc([]f32, NCELL),
            .PB = try alloc.alloc([]f32, NCELL),
            .theta = 0.20,
        };
        for (0..NCELL) |i| {
            e.P[i] = try alloc.alloc(f32, BLADES);
            e.PB[i] = try alloc.alloc(f32, BLADES);
            var norm: f32 = 0;
            for (0..BLADES) |b| {
                const x = rand.floatNorm(f32);
                e.P[i][b] = x;
                norm += x * x;
            }
            norm = @sqrt(norm);
            for (0..BLADES) |b| e.P[i][b] /= norm;
            // distinct random bivector blade B_i = e_p e_q
            const p: u4 = @intCast(rand.intRangeLessThan(usize, 0, NQ));
            var q: u4 = @intCast(rand.intRangeLessThan(usize, 0, NQ));
            while (q == p) q = @intCast(rand.intRangeLessThan(usize, 0, NQ));
            const blade: u16 = (@as(u16, 1) << p) | (@as(u16, 1) << q);
            geoBlade(e.P[i], blade, e.PB[i]);
        }
        return e;
    }

    fn deinit(self: *CliffEnc, alloc: std.mem.Allocator) void {
        for (self.P) |r| alloc.free(r);
        for (self.PB) |r| alloc.free(r);
        alloc.free(self.P);
        alloc.free(self.PB);
    }

    // bind(P_i, R_i(v)) = cos(v*theta)*P_i + sin(v*theta)*(P_i B_i); bundle = sum.
    fn encode(self: *const CliffEnc, g: [NCELL]u8, out: []f32) void {
        @memset(out, 0);
        for (0..NCELL) |i| {
            const v: f32 = @floatFromInt(g[i]);
            const c = @cos(v * self.theta);
            const s = @sin(v * self.theta);
            const Pi = self.P[i];
            const PBi = self.PB[i];
            for (0..BLADES) |b| out[b] += c * Pi[b] + s * PBi[b];
        }
    }
};

// ---------------------------------------------------------------- Hadamard control
const HadEnc = struct {
    role: [][NCELL]f32, // role[j][i] in {-1,+1}
    fn encode(self: *const HadEnc, g: [NCELL]u8, out: []f32) void {
        for (0..D) |j| {
            var acc: f32 = 0;
            for (0..NCELL) |i| acc += @as(f32, @floatFromInt(g[i])) * self.role[j][i];
            out[j] = acc;
        }
    }
};

// ---------------------------------------------------------------- readouts
// Per-column z-score on TRAIN stats. A true closure ceiling survives this; only a
// conditioning artifact is removed (see clifford_binding.md, the Hadamard 0.515 catch).
fn standardize(X: [][]f32, ntr: usize, dim: usize) void {
    for (0..dim) |j| {
        var mu: f32 = 0;
        for (0..ntr) |s| mu += X[s][j];
        mu /= @floatFromInt(ntr);
        var sd: f32 = 0;
        for (0..ntr) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
        sd = @max(1e-3, @sqrt(sd / @as(f32, @floatFromInt(ntr))));
        for (0..X.len) |s| X[s][j] = (X[s][j] - mu) / sd;
    }
}

// Logistic-regression linear readout (SGD), held-out accuracy.
fn logisticAcc(alloc: std.mem.Allocator, X: [][]f32, Y: []const f32, ntr: usize, dim: usize) f32 {
    const w = alloc.alloc(f32, dim) catch unreachable;
    defer alloc.free(w);
    @memset(w, 0);
    var b: f32 = 0;
    const lr: f32 = 0.01;
    for (0..EPOCHS) |_| {
        for (0..ntr) |s| {
            var z: f32 = b;
            const x = X[s];
            for (0..dim) |j| z += w[j] * x[j];
            const p = 1.0 / (1.0 + @exp(-@max(@as(f32, -30), @min(@as(f32, 30), z))));
            const e = p - Y[s];
            for (0..dim) |j| w[j] -= lr * e * x[j];
            b -= lr * e;
        }
    }
    var correct: usize = 0;
    for (ntr..X.len) |s| {
        var z: f32 = b;
        const x = X[s];
        for (0..dim) |j| z += w[j] * x[j];
        const pred: f32 = if (z >= 0) 1.0 else 0.0;
        if (pred == Y[s]) correct += 1;
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(X.len - ntr));
}

// Perceptron linear probe over RAW features. Scale-invariant (mistake-driven
// updates), so it needs no standardization — the honest "raw encoding" probe, and
// the same probe family the original ceiling experiment used (best linear 0.513).
fn perceptronAcc(alloc: std.mem.Allocator, X: [][]f32, Y: []const f32, ntr: usize, dim: usize) f32 {
    const w = alloc.alloc(f32, dim) catch unreachable;
    defer alloc.free(w);
    @memset(w, 0);
    var b: f32 = 0;
    for (0..EPOCHS) |_| {
        for (0..ntr) |s| {
            var z: f32 = b;
            const x = X[s];
            for (0..dim) |j| z += w[j] * x[j];
            const pred: f32 = if (z >= 0) 1.0 else 0.0;
            if (pred != Y[s]) {
                const sgn: f32 = if (Y[s] > 0.5) 1.0 else -1.0;
                for (0..dim) |j| w[j] += sgn * x[j];
                b += sgn;
            }
        }
    }
    var correct: usize = 0;
    for (ntr..X.len) |s| {
        var z: f32 = b;
        const x = X[s];
        for (0..dim) |j| z += w[j] * x[j];
        const pred: f32 = if (z >= 0) 1.0 else 0.0;
        if (pred == Y[s]) correct += 1;
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(X.len - ntr));
}

// Nearest-class-centroid readout — the analogue of the agent's bundled-prototype /
// Hamming-distance readout (the readout that scored 0.502 in the original probe).
fn protoAcc(alloc: std.mem.Allocator, X: [][]f32, Y: []const f32, ntr: usize, dim: usize) f32 {
    const c0 = alloc.alloc(f32, dim) catch unreachable;
    defer alloc.free(c0);
    const c1 = alloc.alloc(f32, dim) catch unreachable;
    defer alloc.free(c1);
    @memset(c0, 0);
    @memset(c1, 0);
    var n0: f32 = 0;
    var n1: f32 = 0;
    for (0..ntr) |s| {
        if (Y[s] > 0.5) {
            for (0..dim) |j| c1[j] += X[s][j];
            n1 += 1;
        } else {
            for (0..dim) |j| c0[j] += X[s][j];
            n0 += 1;
        }
    }
    for (0..dim) |j| {
        c0[j] /= @max(1.0, n0);
        c1[j] /= @max(1.0, n1);
    }
    var correct: usize = 0;
    for (ntr..X.len) |s| {
        var d0: f32 = 0;
        var d1: f32 = 0;
        const x = X[s];
        for (0..dim) |j| {
            d0 += (x[j] - c0[j]) * (x[j] - c0[j]);
            d1 += (x[j] - c1[j]) * (x[j] - c1[j]);
        }
        const pred: f32 = if (d1 < d0) 1.0 else 0.0;
        if (pred == Y[s]) correct += 1;
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(X.len - ntr));
}

// ---------------------------------------------------------------- per-seed metrics
const Metric = struct { arm: []const u8, predicate: []const u8 };
const NMET = 11;
const metrics = [NMET]Metric{
    .{ .arm = "majority_rate", .predicate = "band" }, // 0 chance reference
    .{ .arm = "xor_prototype", .predicate = "band" }, // 1 arm (a): agent-style readout
    .{ .arm = "xor_linear_raw", .predicate = "band" }, // 2 arm (a): raw linear probe (must be ~0.51)
    .{ .arm = "xor_logistic_std", .predicate = "band" }, // 3 arm (a): std logistic (same as arm b protocol)
    .{ .arm = "xor_linear_raw", .predicate = "sum" }, // 4 secondary
    .{ .arm = "hadamard_logistic_std", .predicate = "band" }, // 5 control: real non-Clifford bind
    .{ .arm = "clifford_logistic_std", .predicate = "band" }, // 6 arm (b)
    .{ .arm = "clifford_linear_raw", .predicate = "band" }, // 7 arm (c)
    .{ .arm = "clifford_logistic_std", .predicate = "sum" }, // 8 secondary
    .{ .arm = "clifford_shuffled_labels", .predicate = "band" }, // 9 leak control (expect ~majority)
    .{ .arm = "xor_shuffled_labels", .predicate = "band" }, // 10 leak control on baseline
};

fn runSeed(alloc: std.mem.Allocator, seed: u64, out: *[NMET]f32) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const ntr = NSAMP / 2;

    // shared grids + labels
    var grids: [NSAMP][NCELL]u8 = undefined;
    var Ysum: [NSAMP]f32 = undefined;
    var Yband: [NSAMP]f32 = undefined;
    for (0..NSAMP) |s| {
        var mass: u32 = 0;
        for (0..NCELL) |i| {
            grids[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
            mass += grids[s][i];
        }
        Ysum[s] = if (mass >= SumK) 1.0 else 0.0;
        Yband[s] = if (mass >= BandLo and mass <= BandHi) 1.0 else 0.0;
    }
    // shuffled-label copy (coherent permutation across train+test = no signal left)
    var Yshuf: [NSAMP]f32 = undefined;
    @memcpy(&Yshuf, &Yband);
    rand.shuffle(f32, &Yshuf);

    var pos: f32 = 0;
    for (ntr..NSAMP) |s| pos += Yband[s];
    const nte: f32 = @floatFromInt(NSAMP - ntr);
    out[0] = @max(pos, nte - pos) / nte; // majority base rate on test

    // feature matrix backing store, reused per substrate
    const buf = try alloc.alloc(f32, NSAMP * D);
    defer alloc.free(buf);
    const X = try alloc.alloc([]f32, NSAMP);
    defer alloc.free(X);
    for (0..NSAMP) |s| X[s] = buf[s * D .. (s + 1) * D];

    // ---- arm (a): XOR/bundle substrate ----
    {
        const enc = XorEnc.init(rand);
        for (0..NSAMP) |s| enc.encode(grids[s], X[s]);
        out[1] = protoAcc(alloc, X, &Yband, ntr, D);
        out[2] = perceptronAcc(alloc, X, &Yband, ntr, D); // the 0.51 ceiling probe
        out[4] = perceptronAcc(alloc, X, &Ysum, ntr, D);
        out[10] = logisticAcc(alloc, X, &Yshuf, ntr, D); // leak control (pre-std is fine: bits are +-1)
        standardize(X, ntr, D);
        out[3] = logisticAcc(alloc, X, &Yband, ntr, D);
    }

    // ---- control: Hadamard-real bind ----
    {
        var had: HadEnc = .{ .role = try alloc.alloc([NCELL]f32, D) };
        defer alloc.free(had.role);
        for (0..D) |j| for (0..NCELL) |i| {
            had.role[j][i] = if (rand.boolean()) 1.0 else -1.0;
        };
        for (0..NSAMP) |s| had.encode(grids[s], X[s]);
        standardize(X, ntr, D);
        out[5] = logisticAcc(alloc, X, &Yband, ntr, D);
    }

    // ---- arms (b) + (c): Clifford geometric-product bind ----
    {
        var cl = try CliffEnc.init(alloc, rand);
        defer cl.deinit(alloc);
        for (0..NSAMP) |s| cl.encode(grids[s], X[s]);
        out[7] = perceptronAcc(alloc, X, &Yband, ntr, D); // (c) raw linear probe
        standardize(X, ntr, D);
        out[6] = logisticAcc(alloc, X, &Yband, ntr, D); // (b) same protocol as arm (a)
        out[8] = logisticAcc(alloc, X, &Ysum, ntr, D);
        out[9] = logisticAcc(alloc, X, &Yshuf, ntr, D); // leak control
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    var csv_path: []const u8 = "results/a10_clifford_2026_07_10.csv";
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.next();
    if (args.next()) |a| csv_path = a;

    try out.print("=== RQ A10 replication: Clifford geometric-product binding vs the XOR band ceiling ===\n", .{});
    try out.print("{d} seeds x {d} grids (cells 0..{d}), 50/50 split; band = mass in [{d},{d}], sum >= {d}\n\n", .{ NSEEDS, NSAMP, VMAX, BandLo, BandHi, SumK });

    var acc: [NSEEDS][NMET]f32 = undefined;
    var timer = try std.time.Timer.start();
    for (0..NSEEDS) |k| {
        const seed: u64 = 0xA10_2026 + 7919 * @as(u64, k);
        try runSeed(alloc, seed, &acc[k]);
        try out.print("seed {d} (0x{X}): xor_raw={d:.3} xor_std={d:.3} proto={d:.3} | had={d:.3} cl_std={d:.3} cl_raw={d:.3} | shuf(cl)={d:.3} shuf(xor)={d:.3} maj={d:.3}  [{d}s]\n", .{ k, seed, acc[k][2], acc[k][3], acc[k][1], acc[k][5], acc[k][6], acc[k][7], acc[k][9], acc[k][10], acc[k][0], timer.read() / std.time.ns_per_s });
    }

    // ---- aggregate ----
    var mean: [NMET]f32 = undefined;
    var sd: [NMET]f32 = undefined;
    var lo: [NMET]f32 = undefined;
    var hi: [NMET]f32 = undefined;
    for (0..NMET) |m| {
        var mu: f32 = 0;
        lo[m] = 1.0;
        hi[m] = 0.0;
        for (0..NSEEDS) |k| {
            mu += acc[k][m];
            lo[m] = @min(lo[m], acc[k][m]);
            hi[m] = @max(hi[m], acc[k][m]);
        }
        mu /= @floatFromInt(NSEEDS);
        var v: f32 = 0;
        for (0..NSEEDS) |k| v += (acc[k][m] - mu) * (acc[k][m] - mu);
        mean[m] = mu;
        sd[m] = @sqrt(v / @as(f32, @floatFromInt(NSEEDS - 1)));
    }

    try out.print("\n  arm                          | predicate | mean   +- sd    | min..max\n", .{});
    try out.print("  -----------------------------+-----------+-----------------+-------------\n", .{});
    for (0..NMET) |m| {
        try out.print("  {s:<28} | {s:<9} | {d:.3} +- {d:.3}  | {d:.3}..{d:.3}\n", .{ metrics[m].arm, metrics[m].predicate, mean[m], sd[m], lo[m], hi[m] });
    }

    // ---- CSV ----
    {
        const f = try std.fs.cwd().createFile(csv_path, .{});
        defer f.close();
        const w = f.writer();
        try w.print("seed_index,seed,arm,predicate,accuracy\n", .{});
        for (0..NSEEDS) |k| {
            const seed: u64 = 0xA10_2026 + 7919 * @as(u64, k);
            for (0..NMET) |m| {
                try w.print("{d},0x{X},{s},{s},{d:.4}\n", .{ k, seed, metrics[m].arm, metrics[m].predicate, acc[k][m] });
            }
        }
    }
    try out.print("\nCSV written: {s}\n", .{csv_path});

    // ---- computed verdict (the binary states its own honest conclusion) ----
    const ceiling_reproduced = mean[2] > mean[0] - 0.06 and mean[2] < mean[0] + 0.06 and mean[3] < mean[0] + 0.06;
    const cliff_breaks = mean[6] > 0.90 and mean[7] > 0.90;
    const shuffle_clean = @abs(mean[9] - mean[0]) < 0.05 and @abs(mean[10] - mean[0]) < 0.05;
    const cliff_beats_real = mean[6] > mean[5] + 0.03;

    try out.print("\n--- VERDICT ---\n", .{});
    if (!ceiling_reproduced) {
        try out.print("PORT SUSPECT: arm (a) did not reproduce the ~chance ceiling (raw {d:.3}, std {d:.3} vs majority {d:.3}). Do not trust the rest.\n", .{ mean[2], mean[3], mean[0] });
    } else {
        try out.print("arm (a) REPRODUCED: XOR linear probe {d:.3} +- {d:.3} ~ majority {d:.3} (the known ~0.51 ceiling).\n", .{ mean[2], sd[2], mean[0] });
    }
    if (!shuffle_clean) {
        try out.print("LEAK SUSPECT: shuffled-label control off majority (cl {d:.3}, xor {d:.3} vs {d:.3}).\n", .{ mean[9], mean[10], mean[0] });
    } else {
        try out.print("controls CLEAN: shuffled labels -> majority rate (cl {d:.3}, xor {d:.3}).\n", .{ mean[9], mean[10] });
    }
    if (cliff_breaks) {
        try out.print("CEILING BROKEN: Clifford binding reads the band at {d:.3} +- {d:.3} (std logistic) / {d:.3} +- {d:.3} (raw perceptron)\n", .{ mean[6], sd[6], mean[7], sd[7] });
        try out.print("vs XOR's {d:.3}. Changing the binding algebra off GF(2) moves the readout closure.\n", .{mean[2]});
    } else {
        try out.print("CEILING NOT BROKEN: Clifford band accuracy {d:.3} (std) / {d:.3} (raw) — at or near the XOR ceiling.\n", .{ mean[6], mean[7] });
    }
    if (cliff_beats_real) {
        try out.print("Clifford BEATS the Hadamard-real control ({d:.3} vs {d:.3}) — the geometric product itself is doing work.\n", .{ mean[6], mean[5] });
    } else {
        try out.print("DEFLATION: Hadamard-real control ({d:.3}) matches Clifford ({d:.3}) — the lever is 'leave GF(2)\n", .{ mean[5], mean[6] });
        try out.print("for a magnitude-carrying field', NOT the geometric product specifically (replicates clifford_binding.md).\n", .{});
    }
    try out.print("\nCAVEAT: with cells 0..{d}, mass centers ~48, so band [{d},{d}] is effectively one-sided\n", .{ VMAX, BandLo, BandHi });
    try out.print("(mass<{d} near-impossible) and is linearly separable once the sum is readable.\n", .{BandLo});
}
