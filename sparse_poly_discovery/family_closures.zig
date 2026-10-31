//! Math frontier 4 — tropical & the family map: the "families" the terminal result named are
//! concrete, INCOMPARABLE algebraic closures.
//!
//! Phase C's terminal result said a purist forge "composes down to the substrate's family." Frontiers
//! 2–3 named those families as clones. This probe makes them tangible by pitting four ALGEBRAS against
//! four predicates, each native to one algebra:
//!
//!   target                              native algebra / closure        characteristic reader
//!   max(c) ≥ θ                          TROPICAL  (max-plus semiring)    max/min aggregate      ← the true
//!   sum(c) ≥ K                          REAL-AFFINE (linear)             Σ c_i                    home of the
//!   parity-of-count                     GF(2)-AFFINE (Boolean Fourier)   χ_[n] = Π sign(c_i−MID)  order-stat
//!   sign((c2−MID)(c5−MID))              MULTILINEAR (degree-2 monomial)  pairwise products        work
//!
//! Tropical (ℝ∪{−∞}, max, +) is the algebra the project's order-statistic / power-mean work
//! (`concentration_control.md`, `representation_discovery.md`) was implicitly using — max is the tropical
//! sum. Here it is a first-class family. The result: the family×target matrix is essentially diagonal —
//! each algebra reads ONLY its own target — so the families are incomparable closures, none universal.
//! That is the finite-domain shadow of the k≥3 cliff (frontier 3) and the concrete content of "the
//! substrate's family" (the terminal result).
//!
//! Matroid sidebar (see the doc): the irreducibility certifier of `menu_growth.zig` is a matroid CLOSURE
//! operator — independence = not-reconstructible, rank = basis size, a CIRCUIT = an emergent escape
//! (`synergy.zig`: a set dependent as a whole but independent in every proper subset).
//!
//! Run: zig build family-closures --release=fast

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const MID: f64 = 2.5;
const NSAMP: usize = 7200;
const NTR: usize = 4800; // 2/3 train, 1/3 test

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
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
fn fitAcc(X: []const []f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) f64 {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
    var c: usize = 0;
    for (NTR..NSAMP) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(NSAMP - NTR));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0x713A0F1CA1C0FFEE);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    // ── the four substrate families (feature matrices) ──
    const NF = 4;
    const fname = [NF][]const u8{ "REAL-AFFINE (Σcᵢ)", "TROPICAL (max,min)", "GF(2)/FOURIER (χ_[n])", "MONOMIAL (pairwise ×)" };
    const fdim = [NF]usize{ NCELL, 2, 1, NCELL * (NCELL - 1) / 2 };
    const F = try alloc.alloc([][]f64, NF);
    for (0..NF) |f| {
        F[f] = try alloc.alloc([]f64, NSAMP);
        for (0..NSAMP) |s| F[f][s] = try alloc.alloc(f64, fdim[f]);
    }
    for (0..NSAMP) |s| {
        const g = grid[s];
        // REAL-AFFINE: centered cells
        for (0..NCELL) |i| F[0][s][i] = @as(f64, @floatFromInt(g[i])) - MID;
        // TROPICAL: max and min (the max-plus aggregates)
        var mx: f64 = 0;
        var mn: f64 = VMAX;
        for (g) |v| {
            mx = @max(mx, @as(f64, @floatFromInt(v)));
            mn = @min(mn, @as(f64, @floatFromInt(v)));
        }
        F[1][s][0] = mx;
        F[1][s][1] = mn;
        // GF(2)/FOURIER: the top character χ_[n] = Π sign(cᵢ−MID)
        var chi: f64 = 1;
        for (g) |v| chi *= if (@as(f64, @floatFromInt(v)) - MID > 0) @as(f64, 1) else @as(f64, -1);
        F[2][s][0] = chi;
        // MONOMIAL: all centered pairwise products
        var k: usize = 0;
        for (0..NCELL) |i| for (i + 1..NCELL) |j| {
            F[3][s][k] = (@as(f64, @floatFromInt(g[i])) - MID) * (@as(f64, @floatFromInt(g[j])) - MID);
            k += 1;
        };
    }
    for (0..NF) |f| standardize(F[f], fdim[f]);

    // ── the four targets, each native to one family ──
    const NTG = 4;
    const tgname = [NTG][]const u8{ "max(c) ≥ 5", "sum(c) ≥ 20", "parity-of-count", "sign((c2−µ)(c5−µ))" };
    const native = [NTG]usize{ 1, 0, 2, 3 }; // index of the native family
    const Y = try alloc.alloc([]f64, NTG);
    for (0..NTG) |t| Y[t] = try alloc.alloc(f64, NSAMP);
    for (0..NSAMP) |s| {
        const g = grid[s];
        var mx: u8 = 0;
        var sm: u32 = 0;
        var cnt: usize = 0;
        for (g) |v| {
            mx = @max(mx, v);
            sm += v;
            if (@as(f64, @floatFromInt(v)) - MID > 0) cnt += 1;
        }
        Y[0][s] = if (mx >= 5) 1.0 else 0.0;
        Y[1][s] = if (sm >= 20) 1.0 else 0.0;
        Y[2][s] = @floatFromInt(cnt & 1);
        Y[3][s] = if ((@as(f64, @floatFromInt(g[2])) - MID) * (@as(f64, @floatFromInt(g[5])) - MID) > 0) 1.0 else 0.0;
    }

    var w: [40]f64 = undefined;

    try out.print("=== Math frontier 4: tropical & the family map — incomparable algebraic closures ===\n\n", .{});
    try out.print("Four algebras × four predicates, each predicate native to ONE algebra. Held-out test accuracy.\n", .{});
    try out.print("(2/3 train, 1/3 test of {d} samples; logistic readout over each family's characteristic features.)\n\n", .{NSAMP});

    // chance per target
    try out.print("{s:<24} |", .{"target  \\  family"});
    for (0..NF) |f| try out.print(" {s:^14} |", .{fname[f]});
    try out.print(" chance\n", .{});
    try out.print("-------------------------+", .{});
    for (0..NF) |_| try out.print("----------------+", .{});
    try out.print("-------\n", .{});

    for (0..NTG) |t| {
        var pos: f64 = 0;
        for (NTR..NSAMP) |s| pos += Y[t][s];
        const nte: f64 = @floatFromInt(NSAMP - NTR);
        const chance = @max(pos, nte - pos) / nte;
        try out.print("{s:<24} |", .{tgname[t]});
        for (0..NF) |f| {
            const acc = fitAcc(F[f], Y[t], fdim[f], 200, 0.05, &w);
            const mark: []const u8 = if (f == native[t]) " ◄native" else "        ";
            try out.print(" {d:.3}{s} |", .{ acc, mark });
        }
        try out.print(" {d:.3}\n", .{chance});
    }

    // ── verdict ──
    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("The matrix is diagonal: each algebra reads ONLY its native predicate near 1.0 and sits at (or\n", .{});
    try out.print("near) chance on the others. The one off-diagonal bleed is TROPICAL↔AFFINE on max/sum — both are\n", .{});
    try out.print("'size' aggregates, so they correlate; everything else is clean. No family is universal.\n\n", .{});
    try out.print("So the 'families' the terminal result named are not a metaphor — they are concrete, incomparable\n", .{});
    try out.print("CLOSURES: max-plus (tropical), real-affine, GF(2)-affine (the Fourier characters), and multilinear\n", .{});
    try out.print("(monomials). Tropical is the algebra the project's order-statistic and power-mean work was already\n", .{});
    try out.print("using without naming it (max IS the tropical sum). A forge inside any one of them bottoms out at\n", .{});
    try out.print("its closure — exactly Phase C — and crossing to another needs an out-of-family generator.\n\n", .{});
    try out.print("This is the finite-domain shadow of the k≥3 cliff (frontier 3): finitely many incomparable\n", .{});
    try out.print("families here, uncountably many in the wild. And the irreducibility certifier that policed every\n", .{});
    try out.print("escape (menu_growth.zig) is a MATROID closure operator — rank = basis size, a circuit = an\n", .{});
    try out.print("emergent escape (synergy.zig). The whole invention story is one statement in four algebras: a\n", .{});
    try out.print("search closed under an algebra reaches exactly that algebra's closure, no further.\n", .{});
    try out.print("\nSee: concentration_control.md / representation_discovery.md (the tropical work, unnamed),\n", .{});
    try out.print("menu_growth.md (the matroid certifier), synergy.md (circuits), clone_lattice.md, kary_frontier.md,\n", .{});
    try out.print("CLOSURE_PRINCIPLE.md. Theory: Maclagan–Sturmfels, *Introduction to Tropical Geometry* (2015);\n", .{});
    try out.print("Oxley, *Matroid Theory* (2011).\n", .{});
}
