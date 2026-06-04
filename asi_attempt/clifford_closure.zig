//! RQ A10 — does changing the BINDING ALGEBRA change the closure of the readout?
//!
//! Established (dynamics_probe.zig, closure_escape_control.md): the stock VSA encoder
//! XOR-folds all 16 cells into ONE 8192-bit vector. bind = XOR is its own inverse and
//! carries no magnitude, so the grid collapses to a PARITY: a linear/XOR readout over
//! all 8192 bits classifies "total mass in band" at 0.51 (chance). The SUM is outside
//! the closure of the substrate. That is a property of the ALGEBRA (GF(2) XOR), not the
//! task. The external frontier research (algebraic intelligence) and this repo's own
//! Closure Principle make the same prediction: inject a binding generator OUTSIDE the
//! XOR closure and the ceiling should collapse.
//!
//! This experiment swaps ONLY the bind operation, holding the VSA recipe fixed (one
//! random role per cell, a value-filler, bind within a cell, bundle across cells, then
//! a linear readout). Four substrates, same train/test grids, same readouts:
//!
//!   1. XOR-VSA      bind = XOR (GF(2)), bundle = the stock EnvEncoder       [the ceiling]
//!   2. Hadamard-R   bind = scale role by value (real), bundle = sum         [CONTROL: real, not Clifford]
//!   3. Clifford-VSA bind = geometric product with a rotor filler, bundle = sum  [the candidate]
//!
//! The control arm (2) is load-bearing for honesty: if a plain real-valued bind ALSO
//! escapes, then the generator is "leave GF(2) for a magnitude-carrying field," NOT
//! "the geometric product" specifically. We must be able to tell those apart.
//!
//! Two predicates, ascending the order-statistics ladder:
//!   - sum >= K       LINEAR in the cells (B1). Decisive cell: can a LINEAR readout read
//!                    total mass at all? XOR provably cannot.
//!   - |sum - 32|<=16 QUADRATIC (B2, the band). Needs a quadratic feature from ANY
//!                    substrate; we test linear and a quadratic-of-the-sum readout.
//!
//! Run: zig build clifford

const std = @import("std");
const hv = @import("hypervector.zig");
const agent_mod = @import("agent.zig");
const env_mod = @import("environment.zig");

const NCELL = 16;
const VMAX = 6; // cell values 0..6 ; mass 0..96, centered ~48
const BandLo: u32 = 16;
const BandHi: u32 = 48;
const SumK: u32 = 48; // balanced threshold for the linear predicate

// ---- Geometric algebra Cl(13,0): 2^13 = 8192 blades = 8192 real coeffs.
// Exactly matches the XOR substrate's 8192 bits, so any difference is the ALGEBRA,
// not the dimension budget.
const NQ: u4 = 13;
const BLADES: usize = 1 << NQ; // 8192

// Euclidean reordering sign for the geometric product of blades a and b (e_i^2=+1).
inline fn reorderSign(a0: u16, b: u16) f32 {
    var a = a0 >> 1;
    var sum: u32 = 0;
    while (a != 0) {
        sum += @popCount(a & b);
        a >>= 1;
    }
    return if (sum & 1 == 0) @as(f32, 1.0) else @as(f32, -1.0);
}

// out = mv * (single blade) under the geometric product. Filler rotors are sparse
// (scalar + one bivector), so binding never needs the full 8192x8192 product.
fn geoBlade(mv: []const f32, blade: u16, out: []f32) void {
    @memset(out, 0);
    for (0..BLADES) |a| {
        const c = mv[a];
        if (c == 0) continue;
        const r = @as(u16, @intCast(a)) ^ blade;
        out[r] += reorderSign(@intCast(a), blade) * c;
    }
}

// =============================================================================
// Substrate encoders. Each maps a grid -> a real feature vector the readouts see.
// =============================================================================

// 1. XOR-VSA: the actual stock encoder, decoded to {-1,+1} per bit (real view of bits).
fn encodeXor(enc: *const agent_mod.EnvEncoder, env: *env_mod.Environment, g: [NCELL]u8, out: []f32) void {
    env.grid = g;
    env.failed = false;
    const e = enc.encode(env);
    for (0..hv.D) |j| {
        const bit: u1 = @intCast((e[j / 64] >> @intCast(j % 64)) & 1);
        out[j] = if (bit == 1) 1.0 else -1.0;
    }
}

// 2. Hadamard-real CONTROL: role_i in {-1,+1}^D, bind = scale role by the value,
//    bundle = sum. s = Σ v_i role_i. A real, magnitude-carrying bind that is NOT
//    Clifford — isolates "leaving GF(2)" from "the geometric product."
const HadEnc = struct {
    role: [][NCELL]f32, // role[j][i] in {-1,+1}
    fn encode(self: *const HadEnc, g: [NCELL]u8, out: []f32) void {
        for (0..hv.D) |j| {
            var acc: f32 = 0;
            for (0..NCELL) |i| acc += @as(f32, @floatFromInt(g[i])) * self.role[j][i];
            out[j] = acc;
        }
    }
};

// 3. Clifford-VSA: role P_i a random unit multivector; filler a ROTOR
//    R_i(v) = cos(vθ)·1 + sin(vθ)·B_i (B_i a fixed unit bivector, invertible).
//    bind = geometric product = cos(vθ)·P_i + sin(vθ)·(P_i B_i). bundle = sum.
const CliffEnc = struct {
    P: [][]f32, // [NCELL][BLADES]  role multivectors
    PB: [][]f32, // [NCELL][BLADES] precomputed P_i * B_i
    theta: f32,
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

// Per-column z-score on TRAIN stats, applied to all rows. Without this the linear
// readout is confounded by feature scale (large raw sums saturate logistic SGD), so
// a substrate could look "at ceiling" purely from conditioning. Standardizing makes
// the comparison about the CLOSURE, not the magnitude. A true closure ceiling (XOR)
// survives standardization; only a scaling artifact is removed by it.
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

// =============================================================================
// Readouts (shared across substrates). DIM is the feature width.
// =============================================================================

// Linear logistic regression; returns held-out accuracy AND writes the learned
// weight direction (used to project for the quadratic-of-sum readout).
fn linearAcc(X: [][]f32, Y: []const f32, ntr: usize, dim: usize, epochs: usize, w_out: ?[]f32) f32 {
    const alloc = std.heap.page_allocator;
    const w = alloc.alloc(f32, dim) catch unreachable;
    defer alloc.free(w);
    @memset(w, 0);
    var b: f32 = 0;
    const lr: f32 = 0.01;
    for (0..epochs) |_| {
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
    if (w_out) |wo| @memcpy(wo, w);
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

// Quadratic-of-sum readout: project each sample onto the linear "sum direction" w
// (learned to read sum>=K), then fit logistic over {proj, proj^2}. If the sum is
// linearly recoverable from the substrate, this 2-feature quadratic reads the band.
fn quadOfSumAcc(X: [][]f32, Yband: []const f32, w: []const f32, ntr: usize, dim: usize) f32 {
    const alloc = std.heap.page_allocator;
    const proj = alloc.alloc(f32, X.len) catch unreachable;
    defer alloc.free(proj);
    for (0..X.len) |s| {
        var z: f32 = 0;
        const x = X[s];
        for (0..dim) |j| z += w[j] * x[j];
        proj[s] = z;
    }
    // standardize proj on train
    var mu: f32 = 0;
    for (0..ntr) |s| mu += proj[s];
    mu /= @floatFromInt(ntr);
    var sd: f32 = 0;
    for (0..ntr) |s| sd += (proj[s] - mu) * (proj[s] - mu);
    sd = @max(1e-6, @sqrt(sd / @as(f32, @floatFromInt(ntr))));
    var w0: f32 = 0;
    var w1: f32 = 0;
    var w2: f32 = 0;
    var bb: f32 = 0;
    const lr: f32 = 0.02;
    for (0..200) |_| {
        for (0..ntr) |s| {
            const p1 = (proj[s] - mu) / sd;
            const p2 = p1 * p1;
            var z: f32 = bb + w1 * p1 + w2 * p2;
            _ = &w0;
            const pr = 1.0 / (1.0 + @exp(-@max(@as(f32, -30), @min(@as(f32, 30), z))));
            const e = pr - Yband[s];
            w1 -= lr * e * p1;
            w2 -= lr * e * p2;
            bb -= lr * e;
            z = 0;
        }
    }
    var correct: usize = 0;
    for (ntr..X.len) |s| {
        const p1 = (proj[s] - mu) / sd;
        const p2 = p1 * p1;
        const z: f32 = bb + w1 * p1 + w2 * p2;
        const pred: f32 = if (z >= 0) 1.0 else 0.0;
        if (pred == Yband[s]) correct += 1;
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(X.len - ntr));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const out = std.io.getStdOut().writer();

    var nsamp: usize = 4000;
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.next();
    if (args.next()) |a| nsamp = std.fmt.parseInt(usize, a, 10) catch nsamp;
    const ntr = nsamp / 2;

    var prng = std.Random.DefaultPrng.init(0xC11FF0);
    const rand = prng.random();

    // ---- shared train/test grids and labels (identical for every substrate) ----
    const grids = try alloc.alloc([NCELL]u8, nsamp);
    defer alloc.free(grids);
    const Ysum = try alloc.alloc(f32, nsamp);
    defer alloc.free(Ysum);
    const Yband = try alloc.alloc(f32, nsamp);
    defer alloc.free(Yband);
    for (0..nsamp) |s| {
        var g: [NCELL]u8 = undefined;
        var mass: u32 = 0;
        for (0..NCELL) |i| {
            g[i] = rand.intRangeAtMost(u8, 0, VMAX);
            mass += g[i];
        }
        grids[s] = g;
        Ysum[s] = if (mass >= SumK) 1.0 else 0.0;
        Yband[s] = if (mass >= BandLo and mass <= BandHi) 1.0 else 0.0;
    }

    // ---- substrate 1: XOR-VSA (the real stock encoder) ----
    const Xxor = try alloc.alloc([]f32, nsamp);
    defer {
        for (Xxor) |row| alloc.free(row);
        alloc.free(Xxor);
    }
    {
        const enc = agent_mod.EnvEncoder.init(rand, false);
        var env = env_mod.Environment.initWith(.{});
        for (0..nsamp) |s| {
            Xxor[s] = try alloc.alloc(f32, hv.D);
            encodeXor(&enc, &env, grids[s], Xxor[s]);
        }
    }

    // ---- substrate 2: Hadamard-real control ----
    const Xhad = try alloc.alloc([]f32, nsamp);
    defer {
        for (Xhad) |row| alloc.free(row);
        alloc.free(Xhad);
    }
    {
        var had: HadEnc = .{ .role = try alloc.alloc([NCELL]f32, hv.D) };
        defer alloc.free(had.role);
        for (0..hv.D) |j| for (0..NCELL) |i| {
            had.role[j][i] = if (rand.boolean()) 1.0 else -1.0;
        };
        for (0..nsamp) |s| {
            Xhad[s] = try alloc.alloc(f32, hv.D);
            had.encode(grids[s], Xhad[s]);
        }
    }

    // ---- substrate 3: Clifford-VSA ----
    const Xcl = try alloc.alloc([]f32, nsamp);
    defer {
        for (Xcl) |row| alloc.free(row);
        alloc.free(Xcl);
    }
    {
        var cl: CliffEnc = .{
            .P = try alloc.alloc([]f32, NCELL),
            .PB = try alloc.alloc([]f32, NCELL),
            .theta = 0.20,
        };
        defer {
            for (cl.P) |r| alloc.free(r);
            for (cl.PB) |r| alloc.free(r);
            alloc.free(cl.P);
            alloc.free(cl.PB);
        }
        for (0..NCELL) |i| {
            cl.P[i] = try alloc.alloc(f32, BLADES);
            cl.PB[i] = try alloc.alloc(f32, BLADES);
            // random unit multivector role
            var norm: f32 = 0;
            for (0..BLADES) |b| {
                const x = rand.floatNorm(f32);
                cl.P[i][b] = x;
                norm += x * x;
            }
            norm = @sqrt(norm);
            for (0..BLADES) |b| cl.P[i][b] /= norm;
            // distinct random bivector blade B_i = e_p e_q (two distinct bits)
            const p: u4 = @intCast(rand.intRangeLessThan(usize, 0, NQ));
            var q: u4 = @intCast(rand.intRangeLessThan(usize, 0, NQ));
            while (q == p) q = @intCast(rand.intRangeLessThan(usize, 0, NQ));
            const blade: u16 = (@as(u16, 1) << p) | (@as(u16, 1) << q);
            geoBlade(cl.P[i], blade, cl.PB[i]);
        }
        for (0..nsamp) |s| {
            Xcl[s] = try alloc.alloc(f32, BLADES);
            cl.encode(grids[s], Xcl[s]);
        }
    }

    // ---- standardize each substrate (fair conditioning) then run the readouts ----
    standardize(Xxor, ntr, hv.D);
    standardize(Xhad, ntr, hv.D);
    standardize(Xcl, ntr, BLADES);

    const wxor = try alloc.alloc(f32, hv.D);
    defer alloc.free(wxor);
    const whad = try alloc.alloc(f32, hv.D);
    defer alloc.free(whad);
    const wcl = try alloc.alloc(f32, BLADES);
    defer alloc.free(wcl);

    const xor_sum = linearAcc(Xxor, Ysum, ntr, hv.D, 20, wxor);
    const had_sum = linearAcc(Xhad, Ysum, ntr, hv.D, 20, whad);
    const cl_sum = linearAcc(Xcl, Ysum, ntr, BLADES, 20, wcl);

    const xor_band_lin = linearAcc(Xxor, Yband, ntr, hv.D, 20, null);
    const had_band_lin = linearAcc(Xhad, Yband, ntr, hv.D, 20, null);
    const cl_band_lin = linearAcc(Xcl, Yband, ntr, BLADES, 20, null);

    const xor_band_q = quadOfSumAcc(Xxor, Yband, wxor, ntr, hv.D);
    const had_band_q = quadOfSumAcc(Xhad, Yband, whad, ntr, hv.D);
    const cl_band_q = quadOfSumAcc(Xcl, Yband, wcl, ntr, BLADES);

    // base rates for chance reference
    var pos_sum: f32 = 0;
    var pos_band: f32 = 0;
    for (ntr..nsamp) |s| {
        pos_sum += Ysum[s];
        pos_band += Yband[s];
    }
    const nte: f32 = @floatFromInt(nsamp - ntr);
    const chance_sum = @max(pos_sum, nte - pos_sum) / nte;
    const chance_band = @max(pos_band, nte - pos_band) / nte;

    try out.print("=== RQ A10: does the BINDING ALGEBRA change the readout closure? ===\n", .{});
    try out.print("({d} grids, 50/50 train/test; cells 0..{d}; chance: sum>=K {d:.3}, band {d:.3})\n", .{ nsamp, VMAX, chance_sum, chance_band });
    try out.print("all substrates: same grids, same VSA recipe, ONLY the bind differs.\n\n", .{});

    try out.print("  substrate                         | sum>=K linear | band linear | band quad-of-sum\n", .{});
    try out.print("  ----------------------------------+---------------+-------------+-----------------\n", .{});
    try out.print("  XOR-VSA   (GF(2), 8192 bits)      |    {d:.3}      |   {d:.3}     |     {d:.3}\n", .{ xor_sum, xor_band_lin, xor_band_q });
    try out.print("  Hadamard-R (real scale, 8192 d)   |    {d:.3}      |   {d:.3}     |     {d:.3}\n", .{ had_sum, had_band_lin, had_band_q });
    try out.print("  Clifford-VSA (geo prod, 8192 d)   |    {d:.3}      |   {d:.3}     |     {d:.3}\n", .{ cl_sum, cl_band_lin, cl_band_q });

    // ---- computed verdict (the binary states its own honest conclusion) ----
    const xor_stuck = xor_sum < 0.60;
    const had_crosses = had_sum > 0.90;
    const cl_crosses = cl_sum > 0.90;
    const cliff_beats_real = cl_sum > had_sum + 0.03;

    try out.print("\n--- VERDICT ---\n", .{});
    if (xor_stuck and (had_crosses or cl_crosses)) {
        try out.print("CONFIRMED (escape corollary): XOR/GF(2) keeps total mass OUTSIDE the closure\n", .{});
        try out.print("({d:.3}, chance), and a non-XOR bind collapses the ceiling -> the binding ALGEBRA\n", .{xor_sum});
        try out.print("alone moves the closure. The report's 'change the algebra' thesis holds here.\n", .{});
    } else {
        try out.print("NOT confirmed: XOR did not behave as a ceiling here (sum>=K {d:.3}). Investigate.\n", .{xor_sum});
    }
    if (had_crosses and !cliff_beats_real) {
        try out.print("\nDEFLATION (the honest control result): a PLAIN real-valued Hadamard bind\n", .{});
        try out.print("({d:.3}) reads the sum as well as the full Clifford geometric product ({d:.3}).\n", .{ had_sum, cl_sum });
        try out.print("The load-bearing generator is 'leave GF(2) for a magnitude-carrying real field,'\n", .{});
        try out.print("NOT the geometric product specifically. Clifford's grades/bivectors are not\n", .{});
        try out.print("earning their keep on this mass-symmetric predicate. (Same pattern as the repo's\n", .{});
        try out.print("'VSA semantic grounding was non-load-bearing' and 'more tiers wasn't the lever'.)\n", .{});
    } else if (cliff_beats_real) {
        try out.print("\nClifford BEATS the real control by >0.03 ({d:.3} vs {d:.3}) -- the geometric\n", .{ cl_sum, had_sum });
        try out.print("product's structure is doing work beyond merely leaving GF(2). Worth pursuing.\n", .{});
    }
    try out.print("\nCAVEAT: with cells 0..{d} over 16 cells, mass centers ~48, so the band [{d},{d}] is\n", .{ VMAX, BandLo, BandHi });
    try out.print("effectively ONE-SIDED (mass<{d} is near-impossible) -- it is linearly separable once\n", .{BandLo});
    try out.print("the sum is readable, so the 'quad-of-sum' column is not a clean two-sided test here.\n", .{});
    try out.print("A genuine two-sided quadratic band (where Clifford's grade-2 might matter) needs the\n", .{});
    try out.print("balanced construction in order_statistics.zig. See docs/research/clifford_binding.md.\n", .{});
}
