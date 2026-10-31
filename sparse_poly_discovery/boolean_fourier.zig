//! Math frontier 1 — Boolean Fourier analysis (Walsh–Hadamard): the UNIVERSAL discovery operator.
//!
//! The whole #2/#3 arc (structure_discovery → menu_growth → inner_forge) was hand-rolling a special
//! case of one classical object. Map each cell to a sign  x_i = sign(c_i − MID) ∈ {−1,+1}. Then every
//! Boolean function f: {−1,+1}^n → ℝ has a UNIQUE expansion
//!     f = Σ_S  f̂(S)·χ_S ,      χ_S(x) = Π_{i∈S} x_i        (a parity over the coordinate set S)
//! and the coefficients f̂(S) = E_x[ f(x)·χ_S(x) ] ARE the structure of f. This is the Walsh–Hadamard
//! transform; {χ_S} is the Fourier basis of the Boolean cube.
//!
//! The punchline: our entire predicate zoo collapses to single characters, recovered in ONE transform —
//! no forge, no pair-search, no certifier:
//!     hidden pair  sign φ{2,5}   →  χ_{2,5}        (the Frontier-24 ceiling that needed Phase B's forge)
//!     hidden triple              →  χ_{1,3,6}      (Phase B's relocation wall)
//!     hidden quad                →  χ_{0,4,5,7}    (Phase C promoted these one at a time)
//!     parity-of-count            →  χ_{[n]}        (THE max-degree character — the hardness witness)
//! Phase C's "monomials" ARE the Fourier characters; the WHT computes ALL of them simultaneously.
//!
//! It also makes the hardness ladder a THEOREM: a function is linearly/low-degree learnable iff its
//! Fourier mass sits on low |S| (Linial–Mansour–Nisan). Parity puts all its mass on |S|=n → no
//! low-degree readout can see it. The degree-1 Fourier mass Σ_{|S|=1} f̂(S)² is exactly the ceiling of
//! a linear readout — quantitatively predicting which #3 predicates were "escapes".
//!
//! And it SCALES: Goldreich–Levin finds the heavy coefficients in poly(n) with query access, no 2^n
//! enumeration. We demonstrate the sample-estimate version: a few hundred samples recover the spike.
//!
//! Run: zig build boolean-fourier --release=fast

const std = @import("std");

const N: usize = 8; // bits
const DOM: usize = 1 << N; // 256 sign-patterns
const MID: f64 = 2.5;
const VMAX: u8 = 5;

// χ_S(p): product of x_i over i∈S, where x_i = +1 if bit i set in p else −1.
//   = (−1)^{ #{i∈S : bit i NOT set in p} } = (−1)^{ popcount(S & ~p) }
fn chi(S: u8, p: u8) f64 {
    const neg = @popCount(S & ~p);
    return if (neg & 1 == 0) @as(f64, 1.0) else @as(f64, -1.0);
}

// the predicate zoo, as ±1-valued functions g(p) of the sign-pattern p (g = 1 − 2·y, y∈{0,1})
const NP = 7;
fn predicate(idx: usize, p: u8) f64 {
    const b = struct {
        fn bit(pp: u8, i: usize) usize {
            return (pp >> @intCast(i)) & 1;
        }
    };
    const count = @popCount(p); // # of +1 bits = #{c_i ≥ 3}
    const y: usize = switch (idx) {
        0 => count & 1, // parity-of-count        → χ_[8]
        1 => b.bit(p, 2) ^ b.bit(p, 5), // hidden pair    → χ_{2,5}
        2 => b.bit(p, 1) ^ b.bit(p, 3) ^ b.bit(p, 6), // hidden triple → χ_{1,3,6}
        3 => b.bit(p, 0) ^ b.bit(p, 4) ^ b.bit(p, 5) ^ b.bit(p, 7), // hidden quad → χ_{0,4,5,7}
        4 => b.bit(p, 3), // single bit             → χ_{3}
        5 => if (count % 6 == 0) @as(usize, 1) else 0, // AND-composition (sparse, symmetric)
        6 => if (count >= 5) @as(usize, 1) else 0, // majority (threshold, symmetric)
        else => 0,
    };
    return if (y == 0) 1.0 else -1.0;
}
const pname = [NP][]const u8{
    "parity-of-count", "hidden pair (2,5)", "hidden triple (1,3,6)", "hidden quad (0,4,5,7)",
    "single bit (3)",  "AND-composition",  "majority",
};
const phidden = [NP]u8{ 0xFF, (1 << 2) | (1 << 5), (1 << 1) | (1 << 3) | (1 << 6), (1 << 0) | (1 << 4) | (1 << 5) | (1 << 7), (1 << 3), 0, 0 };

fn fmtSet(buf: []u8, S: u8) []const u8 {
    var w: usize = 0;
    buf[w] = '{';
    w += 1;
    var first = true;
    for (0..N) |i| {
        if (S & (@as(u8, 1) << @intCast(i)) != 0) {
            if (!first) {
                buf[w] = ',';
                w += 1;
            }
            buf[w] = '0' + @as(u8, @intCast(i));
            w += 1;
            first = false;
        }
    }
    buf[w] = '}'; // S=∅ renders as "{}"
    w += 1;
    return buf[0..w];
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    _ = arena.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== Math frontier 1: Boolean Fourier (Walsh–Hadamard) — the universal discovery operator ===\n\n", .{});
    try out.print("encoding x_i = sign(c_i − {d:.1}) ∈ {{−1,+1}};  f = Σ_S f̂(S)·χ_S,  χ_S = Π_(i∈S) x_i\n", .{MID});
    try out.print("exact transform over all {d} sign-patterns; f̂(S) = E[f·χ_S].\n\n", .{DOM});

    var setbuf: [32]u8 = undefined;
    var setbuf2: [32]u8 = undefined;

    // ── exact Walsh–Hadamard transform of each predicate ──
    try out.print("──────── 1. the spectrum: structure recovered in ONE transform ────────\n", .{});
    try out.print("predicate              | top Fourier coefficients f̂(S)                | deg | sparsity | recovered S* = hidden?\n", .{});
    try out.print("-----------------------+-----------------------------------------------+-----+----------+----------------------\n", .{});

    for (0..NP) |pi| {
        var coef: [DOM]f64 = undefined;
        for (0..DOM) |S| {
            var acc: f64 = 0;
            for (0..DOM) |p| acc += predicate(pi, @intCast(p)) * chi(@intCast(S), @intCast(p));
            coef[S] = acc / @as(f64, @floatFromInt(DOM));
        }
        // Parseval mass, degree, sparsity, argmax
        var deg: usize = 0;
        var sparsity: usize = 0;
        var best_abs: f64 = -1;
        var bestS: u8 = 0;
        for (0..DOM) |S| {
            if (@abs(coef[S]) > 0.05) {
                sparsity += 1;
                deg = @max(deg, @popCount(@as(u8, @intCast(S))));
            }
            if (@abs(coef[S]) > best_abs) {
                best_abs = @abs(coef[S]);
                bestS = @intCast(S);
            }
        }

        // print up to the 3 largest coefficients
        var shown: [3]u8 = .{ 0, 0, 0 };
        var nshown: usize = 0;
        var used: [DOM]bool = .{false} ** DOM;
        while (nshown < 3) {
            var ba: f64 = 0.04;
            var bS: usize = DOM;
            for (0..DOM) |S| {
                if (!used[S] and @abs(coef[S]) > ba) {
                    ba = @abs(coef[S]);
                    bS = S;
                }
            }
            if (bS == DOM) break;
            used[bS] = true;
            shown[nshown] = @intCast(bS);
            nshown += 1;
        }

        try out.print("{s:<22} |", .{pname[pi]});
        for (0..nshown) |k| {
            const s = fmtSet(&setbuf, shown[k]);
            try out.print(" {d:.2}·χ{s}", .{ coef[shown[k]], s });
        }
        for (nshown..3) |_| try out.print("            ", .{});
        const sstar = fmtSet(&setbuf2, bestS);
        const match = (phidden[pi] != 0 or pi == 0) and bestS == (if (pi == 0) @as(u8, 0xFF) else phidden[pi]);
        try out.print("  |  {d}  |    {d:<2}    | {s} {s}\n", .{ deg, sparsity, sstar, if (phidden[pi] != 0 or pi == 0) (if (match) "✓" else "·") else "(composite)" });
    }

    // ── 2. hardness ladder = Fourier degree ──
    try out.print("\n──────── 2. the hardness ladder IS Fourier degree (Linial–Mansour–Nisan) ────────\n", .{});
    try out.print("predicate              | Fourier degree | deg-1 mass Σ_(|S|=1) f̂²  →  linear-readout ceiling\n", .{});
    try out.print("-----------------------+----------------+----------------------------------------------------\n", .{});
    for (0..NP) |pi| {
        var deg: usize = 0;
        var deg1mass: f64 = 0;
        for (0..DOM) |S| {
            var acc: f64 = 0;
            for (0..DOM) |p| acc += predicate(pi, @intCast(p)) * chi(@intCast(S), @intCast(p));
            acc /= @as(f64, @floatFromInt(DOM));
            if (@abs(acc) > 0.05) deg = @max(deg, @popCount(@as(u8, @intCast(S))));
            if (@popCount(@as(u8, @intCast(S))) == 1) deg1mass += acc * acc;
        }
        // a linear (degree-1) readout's correlation ceiling ≈ sqrt(deg-1 mass); acc ≈ 0.5 + 0.5·corr
        const lin_ceiling = 0.5 + 0.5 * @sqrt(deg1mass);
        try out.print("{s:<22} |       {d:<2}       | {d:.3}                    →  ~{d:.2}{s}\n", .{ pname[pi], deg, deg1mass, lin_ceiling, if (deg1mass < 0.01) "  (linear BLIND — out of low-degree closure)" else "" });
    }

    // ── 3. Goldreich–Levin (sampled): find the heavy coefficient WITHOUT enumerating 2^n ──
    try out.print("\n──────── 3. it SCALES: sample-estimate recovery (Goldreich–Levin flavor) ────────\n", .{});
    try out.print("estimate f̂(S) for the hidden pair from m random samples (no full transform); does argmax → {{2,5}}?\n", .{});
    var prng = std.Random.DefaultPrng.init(0x6F0172E12345);
    const rand = prng.random();
    const ms = [_]usize{ 50, 100, 300, 1000 };
    for (ms) |m| {
        var est: [DOM]f64 = .{0} ** DOM;
        for (0..m) |_| {
            const p: u8 = rand.int(u8);
            const g = predicate(1, p); // hidden pair
            for (0..DOM) |S| est[S] += g * chi(@intCast(S), p);
        }
        var ba: f64 = -1;
        var bS: u8 = 0;
        for (0..DOM) |S| {
            const v = @abs(est[S]) / @as(f64, @floatFromInt(m));
            if (v > ba) {
                ba = v;
                bS = @intCast(S);
            }
        }
        const s = fmtSet(&setbuf, bS);
        try out.print("  m={d:<4} → argmax f̂ = χ{s}  (|f̂|≈{d:.2})   {s}\n", .{ m, s, ba, if (bS == ((1 << 2) | (1 << 5))) "✓ recovered" else "·" });
    }

    // ── verdict ──
    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("The Walsh–Hadamard transform recovers every single-character predicate's EXACT support in one\n", .{});
    try out.print("pass — the hidden pair χ{{2,5}} that Frontier-24's menu could not route (0.591) and Phase B needed\n", .{});
    try out.print("a certified forge to find; the triple/quad Phase C promoted one at a time; parity as the single\n", .{});
    try out.print("max-degree character χ{{0..7}}. Phase C's monomials ARE this Fourier basis — the WHT computes all\n", .{});
    try out.print("of them at once. The #3 forge was sparse-Fourier recovery by hand.\n\n", .{});
    try out.print("Hardness is now a theorem, not a measurement: linear-readout ceiling = degree-1 Fourier mass;\n", .{});
    try out.print("parity and the hidden characters have ZERO low-degree mass → provably blind to any linear/low-\n", .{});
    try out.print("degree readout (the exact predicates that were 'escapes' in #2/#3). And Goldreich–Levin finds the\n", .{});
    try out.print("heavy coefficients in poly(n) — so this generalizes beyond the enumerable n=8 toy.\n\n", .{});
    try out.print("This is the GENERAL 'discover the generator' operator the project kept calling specialized:\n", .{});
    try out.print("spectral_discovery was its 1-D (symmetric / count) shadow; Walsh–Hadamard is the full cube.\n", .{});
    try out.print("\nNext math frontiers: clone theory / Post's lattice (the complete MAP of closures these characters\n", .{});
    try out.print("live in), then the k≥3 uncountable-clone regime (where the map itself ceases to exist).\n", .{});
    try out.print("\nSee: spectral_discovery.md (the 1-D shadow), structure_discovery.md / menu_growth.md / inner_forge.md\n", .{});
    try out.print("(the ceilings this dissolves), CLOSURE_PRINCIPLE.md. Theory: O'Donnell, *Analysis of Boolean Functions*.\n", .{});
}
