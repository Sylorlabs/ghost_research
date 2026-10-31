//! Math frontier 2 — clone theory / Post's lattice: the COMPLETE map of closures.
//!
//! The Closure Principle, for Boolean functions, is not an empirical discovery — Emil Post (1941)
//! classified EVERY closed class. A clone = a set of operations closed under composition (+ projections).
//! Post proved there are exactly FIVE maximal clones (precomplete classes) over {0,1}:
//!     T0  0-preserving   f(0,…,0)=0
//!     T1  1-preserving   f(1,…,1)=1
//!     M   monotone       x≤y ⟹ f(x)≤f(y)
//!     D   self-dual      f(¬x)=¬f(x)
//!     L   affine/linear  f = c₀ ⊕ c₁x₁ ⊕ … ⊕ cₙxₙ
//! Post's completeness criterion (EXACT, a theorem): a set F of gates generates ALL Boolean functions
//! ⟺ F escapes all five maximal clones. And a NECESSARY, decidable test for g ∈ clone(F): every maximal
//! clone containing F must also contain g (the Pol–Inv / preservation idea — answers open RQ #37).
//!
//! This turns the repo's empirical closure ceilings into exact lattice coordinates, and the "wall between
//! families" the whole #3 measured into a one-line theorem:
//!   • mixer GF(2)-affine ceiling  =  substrate ⊆ L; escape (ADD/MUL) = leaving L.            [05_meta_synthesis]
//!   • Phase-C monomial forge can't reach parity  =  clone({AND}) ⊆ M, but parity ∉ M.        [inner_forge.md]
//!   • Boolean Fourier characters χ_S (parity) live in L; monomials (AND) live in M∩T0∩T1 —
//!     DIFFERENT maximal clones, which is precisely why neither forge crosses to the other.   [boolean_fourier.md]
//!
//! Run: zig build clone-lattice --release=fast

const std = @import("std");

const Gate = struct { name: []const u8, arity: u3, tt: u8 }; // tt bit i = f(input i), i∈[0,2^arity)

fn fval(g: Gate, x: u8) u1 {
    return @intCast((g.tt >> @intCast(x)) & 1);
}
fn nIn(g: Gate) u8 {
    return @as(u8, 1) << g.arity;
}

// ── the five maximal-clone membership tests ──
fn isT0(g: Gate) bool {
    return fval(g, 0) == 0;
}
fn isT1(g: Gate) bool {
    return fval(g, nIn(g) - 1) == 1;
}
fn isMonotone(g: Gate) bool {
    const n = nIn(g);
    for (0..n) |x| for (0..n) |y| {
        // x ≤ y bitwise  ⟺  x is a subset of y  ⟺  x & y == x
        if ((x & y) == x and fval(g, @intCast(x)) > fval(g, @intCast(y))) return false;
    };
    return true;
}
fn isSelfDual(g: Gate) bool {
    const n = nIn(g);
    const full = n - 1;
    for (0..n) |x| {
        const comp: u8 = full ^ @as(u8, @intCast(x));
        if (fval(g, comp) == fval(g, @intCast(x))) return false; // need f(¬x) = ¬f(x)
    }
    return true;
}
fn isAffine(g: Gate) bool {
    const n = nIn(g);
    const f0 = fval(g, 0);
    for (0..n) |x| for (0..n) |y| {
        // affine ⟺ f(x) ⊕ f(y) ⊕ f(x⊕y) ⊕ f(0) = 0   (BLR characterization)
        const xy: u8 = @as(u8, @intCast(x)) ^ @as(u8, @intCast(y));
        if ((fval(g, @intCast(x)) ^ fval(g, @intCast(y)) ^ fval(g, xy) ^ f0) != 0) return false;
    };
    return true;
}

const NC = 5;
const cname = [NC][]const u8{ "T0", "T1", "M", "D", "L" };
fn inClone(g: Gate, c: usize) bool {
    return switch (c) {
        0 => isT0(g),
        1 => isT1(g),
        2 => isMonotone(g),
        3 => isSelfDual(g),
        4 => isAffine(g),
        else => unreachable,
    };
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    // gate zoo (truth tables, bit i = f(i); arg bits: bit0=x1, bit1=x2, bit2=x3)
    const gates = [_]Gate{
        .{ .name = "CONST0", .arity = 1, .tt = 0x0 },
        .{ .name = "CONST1", .arity = 1, .tt = 0x3 },
        .{ .name = "NOT", .arity = 1, .tt = 0x1 },
        .{ .name = "AND", .arity = 2, .tt = 0x8 },
        .{ .name = "OR", .arity = 2, .tt = 0xE },
        .{ .name = "XOR", .arity = 2, .tt = 0x6 },
        .{ .name = "NAND", .arity = 2, .tt = 0x7 },
        .{ .name = "NOR", .arity = 2, .tt = 0x1 },
        .{ .name = "IMPL", .arity = 2, .tt = 0xB },
        .{ .name = "MAJ3", .arity = 3, .tt = 0xE8 },
    };

    try out.print("=== Math frontier 2: Post's lattice — the complete classification of Boolean closures ===\n\n", .{});
    try out.print("The 5 MAXIMAL clones (Post 1941): T0=0-preserving  T1=1-preserving  M=monotone  D=self-dual  L=affine.\n", .{});
    try out.print("Post's criterion (EXACT): a gate set is universal ⟺ it escapes ALL five.\n\n", .{});

    // ── 1. membership of each gate in the 5 maximal clones ──
    try out.print("──────── 1. each gate's maximal-clone memberships ────────\n", .{});
    try out.print("gate    |  T0   T1   M    D    L\n", .{});
    try out.print("--------+------------------------\n", .{});
    for (gates) |g| {
        try out.print("{s:<7} |", .{g.name});
        for (0..NC) |c| try out.print("  {s} ", .{if (inClone(g, c)) " ✓" else " ·"});
        try out.print("\n", .{});
    }

    // ── 2. substrate completeness via Post's criterion ──
    const Sub = struct { name: []const u8, gen: []const usize };
    const subs = [_]Sub{
        .{ .name = "{XOR}                (GF(2)-linear mixer)", .gen = &[_]usize{5} },
        .{ .name = "{XOR, CONST1}        (affine mixer)", .gen = &[_]usize{ 5, 1 } },
        .{ .name = "{AND}                (Phase-C monomial substrate)", .gen = &[_]usize{3} },
        .{ .name = "{AND, OR}            (monotone)", .gen = &[_]usize{ 3, 4 } },
        .{ .name = "{AND, XOR}           (GF(2) ring, no 1)", .gen = &[_]usize{ 3, 5 } },
        .{ .name = "{AND, XOR, CONST1}   (GF(2) ring with 1)", .gen = &[_]usize{ 3, 5, 1 } },
        .{ .name = "{AND, NOT}           (NAND-equivalent)", .gen = &[_]usize{ 3, 2 } },
        .{ .name = "{NAND}               (universal gate)", .gen = &[_]usize{6} },
        .{ .name = "{MAJ3}               (self-dual monotone)", .gen = &[_]usize{9} },
    };
    try out.print("\n──────── 2. substrate completeness (Post's criterion) ────────\n", .{});
    try out.print("substrate                                  | contained in maximal clones | universal?\n", .{});
    try out.print("-------------------------------------------+-----------------------------+-----------\n", .{});
    for (subs) |s| {
        try out.print("{s:<42} |", .{s.name});
        var contained: usize = 0;
        var buf: [40]u8 = undefined;
        var w: usize = 0;
        for (0..NC) |c| {
            var all = true;
            for (s.gen) |gi| if (!inClone(gates[gi], c)) {
                all = false;
            };
            if (all) {
                contained += 1;
                for (cname[c]) |ch| {
                    buf[w] = ch;
                    w += 1;
                }
                buf[w] = ' ';
                w += 1;
            }
        }
        if (w == 0) {
            for ("(none)") |ch| {
                buf[w] = ch;
                w += 1;
            }
        }
        try out.print(" {s:<27} | {s}\n", .{ buf[0..w], if (contained == 0) "UNIVERSAL ✓" else "limited" });
    }

    // ── 3. repo connections: closure-membership as a one-line theorem (Pol–Inv necessary test) ──
    try out.print("\n──────── 3. the repo's ceilings ARE maximal-clone obstructions (decidable membership) ────────\n", .{});
    const membership = struct {
        // is g ∈ clone(F)? necessary test: every maximal clone containing all of F must contain g.
        // Report ALL blocking clones. If F escapes all 5, F is universal ⟹ g ∈ clone(F) definitively.
        fn check(g: Gate, gen: []const Gate) void {
            const o = std.io.getStdOut().writer();
            var blockers: [NC][]const u8 = undefined;
            var nb: usize = 0;
            var f_universal = true;
            for (0..NC) |c| {
                var Fin = true;
                for (gen) |gg| if (!inClone(gg, c)) {
                    Fin = false;
                };
                if (Fin) f_universal = false; // F sits inside maximal clone c
                if (Fin and !inClone(g, c)) {
                    blockers[nb] = cname[c];
                    nb += 1;
                }
            }
            if (nb > 0) {
                o.print("  {s} ∈ clone(F)?  NO — clone(F) ⊆ ", .{g.name}) catch {};
                for (0..nb) |i| o.print("{s}{s}", .{ blockers[i], if (i + 1 < nb) "∩" else "" }) catch {};
                o.print(", but {s} is in none of those.  (provable)\n", .{g.name}) catch {};
            } else if (f_universal) {
                o.print("  {s} ∈ clone(F)?  YES — F escapes all 5 maximal clones ⟹ universal (Post).\n", .{g.name}) catch {};
            } else {
                o.print("  {s} ∈ clone(F)?  consistent — passes every maximal-clone necessary test.\n", .{g.name}) catch {};
            }
        }
    };
    const AND = gates[3];
    const XOR = gates[5];
    const NOT = gates[2];
    try out.print("affine ceiling (05_meta_synthesis): a GF(2)-linear substrate cannot compute AND —\n", .{});
    membership.check(AND, &[_]Gate{XOR});
    try out.print("Phase-C saturation (inner_forge.md): the monomial/AND forge cannot reach parity —\n", .{});
    membership.check(XOR, &[_]Gate{AND}); // XOR = parity of 2 bits; AND-clone ⊆ M (and T1), XOR ∉ M
    try out.print("  ↳ clone({{AND}}) ⊆ M (monotone); parity is non-monotone (XOR(0,1)=1 > XOR(1,1)=0).\n", .{});
    try out.print("    Phase C's 30-second saturation experiment is this single lattice fact.\n", .{});
    try out.print("escape needs the right generator: add NOT to AND → leaves every maximal clone → universal:\n", .{});
    membership.check(XOR, &[_]Gate{ AND, NOT });

    // ── verdict ──
    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("The Closure Principle, for Boolean functions, is Post's lattice — fully classified since 1941.\n", .{});
    try out.print("Every empirical closure ceiling in the repo is membership in a maximal clone, and every escape is\n", .{});
    try out.print("leaving one. The mixer's affine wall = ⊆ L. The monomial forge's parity wall = ⊆ M while parity ∉ M.\n", .{});
    try out.print("The 'wall between families' the whole #3 measured is the gap between maximal clones M and L:\n", .{});
    try out.print("the Fourier basis (characters χ_S, parities) lives in L; the monomial basis (AND-products) lives in\n", .{});
    try out.print("M∩T0∩T1. Neither forge could cross because L and M are DIFFERENT maximal clones — a fact you can read\n", .{});
    try out.print("off the lattice in advance, instead of discovering it in a 30-second forge.\n\n", .{});
    try out.print("And closure-membership is DECIDABLE (open RQ #37, settled for the Boolean case): the 5 preservation\n", .{});
    try out.print("tests are a sound necessary check; Post's criterion makes UNIVERSALITY exact. 'Can substrate S invent\n", .{});
    try out.print("predicate P?' is, over {{0,1}}, a finite property check — not a search.\n\n", .{});
    try out.print("THE CATCH (next frontier): this complete map exists ONLY for the 2-element domain. Post's lattice is\n", .{});
    try out.print("countable and fully drawn. For k≥3 (Janov–Mučnik 1959) there are UNCOUNTABLY many clones — no such\n", .{});
    try out.print("map can exist. That is where invention stops being navigable, and where 'alien' actually lives.\n", .{});
    try out.print("\nSee: boolean_fourier.md (the basis that lives in L), inner_forge.md (the M-vs-L wall, forged the slow way),\n", .{});
    try out.print("CLOSURE_PRINCIPLE.md, RESEARCH_QUESTIONS.md §E #37. Theory: Post (1941); Lau, *Function Algebras on\n", .{});
    try out.print("Finite Sets* (2006); the Pol–Inv Galois connection (Geiger 1968; Bodnarchuk–Kaluzhnin–Kotov–Romov 1969).\n", .{});
}
