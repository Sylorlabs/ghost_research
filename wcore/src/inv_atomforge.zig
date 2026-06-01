//! The atom-forge: an OPEN-ENDED ATOM SET (RESEARCH §26) — the one frontier the arc left.
//!
//! Every prior phase used a FIXED atom set and found only composition (§25 proved it with
//! the irreducibility test). The arc reduced "can search INVENT?" to a single question: can
//! the atom set itself be open-ended — atoms *invented*, not composed from a fixed list?
//!
//! This forges exactly that, by COMPOSING the two instruments the arc already built:
//!   1. novelty search (§21–22, info descriptor) GENERATES diverse substrate behaviours;
//!   2. the irreducibility test (§25), generalised here to a growing PROGRAM library,
//!      CERTIFIES which candidates are irreducible relative to the current atom set.
//! A certified-irreducible, clean, MINIMAL candidate is INVENTED — added to the library as a
//! new atom. Then irreducibility RECURS: the next atom must be irreducible relative to the
//! enlarged set (a strictly higher bar). The measurables: how many atoms it invents before
//! saturating, and whether the minimal program-length of each new atom GROWS (open-ended in
//! principle = always more to invent, increasingly complex) or plateaus (substrate exhausted).
//!
//! HONEST framing up front: an atom is irreducible RELATIVE TO THE LIBRARY — genuine
//! *relative* invention (a new primitive the prior vocabulary cannot express). Whether it is
//! *absolutely* novel (unknown to humans) is a separate question this system cannot answer.

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const open = @import("inv_open.zig");

const V: usize = alien.CANON_BASE;
pub const MAX_ATOMS: usize = 32;
pub const AtomLib = std.BoundedArray(alien.Program, MAX_ATOMS);

/// shift atom: out[i] = in[i-1] (a pure one-step delay), output via OUT_R.
pub fn shiftAtom() alien.Program {
    var p = alien.Program{};
    p.step.appendAssumeCapacity(.{ .op = .a_mov, .a = 9, .out = 3 }); // out = prev
    p.step.appendAssumeCapacity(.{ .op = .a_mov, .a = 0, .out = 9 }); // prev = current
    return p;
}

/// The base atom set (the same five stages, as programs that output through OUT_R).
pub fn baseAtoms() AtomLib {
    var lib = AtomLib{};
    lib.appendAssumeCapacity(coevo.refSolver(.g_xor));
    lib.appendAssumeCapacity(coevo.refSolver(.g_add));
    lib.appendAssumeCapacity(coevo.refSolver(.pk_xor));
    lib.appendAssumeCapacity(coevo.refSolver(.pk_add));
    lib.appendAssumeCapacity(shiftAtom());
    return lib;
}

/// Apply a chain of library atoms left-to-right (each transforms the symbol stream).
fn applyChain(lib: []const alien.Program, idxs: []const usize, syms: []const u8, out: []u8) void {
    var a: [256]u8 = undefined;
    var b: [256]u8 = undefined;
    const L = syms.len;
    @memcpy(a[0..L], syms);
    var cur: []u8 = a[0..L];
    var nxt: []u8 = b[0..L];
    for (idxs) |ix| {
        alien.runStream(&lib[ix], cur, nxt);
        const t = cur;
        cur = nxt;
        nxt = t;
    }
    @memcpy(out, cur);
}

fn matchesChain(prog: *const alien.Program, lib: []const alien.Program, idxs: []const usize, n: usize, L: usize, seed: u64) bool {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var tgt: [256]u8 = undefined;
    var got: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        applyChain(lib, idxs, syms[0..L], tgt[0..L]);
        alien.runStream(prog, syms[0..L], got[0..L]);
        for (0..L) |i| {
            total += 1;
            if (got[i] == tgt[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total)) >= coevo.MATCH_THRESHOLD;
}

/// Is `prog` reducible to a composition (depth ≤ max_depth) of the library atoms?
/// The generalised irreducibility test — now over a GROWING program library, so a new
/// atom must be irreducible relative to everything invented so far.
pub fn reducibleLib(prog: *const alien.Program, lib: []const alien.Program, max_depth: usize, seed: u64) bool {
    const n = lib.len;
    if (n == 0) return false;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [8]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            if (matchesChain(prog, lib, idxs[0..d], 8, 28, seed)) return true;
        }
    }
    return false;
}

/// A candidate is "clean" enough to be an atom if its OUT_R output is varied (not a near-
/// constant) — i.e. it actually computes a structured function. Uses the info descriptor's
/// OUT_R-entropy axis.
pub fn clean(prog: *const alien.Program, seed: u64) bool {
    const fp = open.infoDescriptor(prog, seed);
    return fp[1] > 0.30; // OUT_R entropy
}

test "atomforge: base atoms reduce; distinct-count is a NEW atom; adding it makes it reduce" {
    const seed: u64 = 0xA70F;
    var lib = baseAtoms();
    // a base atom is reducible to the library (it IS one)
    const gx = coevo.refSolver(.g_xor);
    try std.testing.expect(reducibleLib(&gx, lib.slice(), 2, seed));
    // distinct-count is IRREDUCIBLE relative to the base atoms — a genuine new atom
    const dc = coevo.distinctCountProg();
    try std.testing.expect(!reducibleLib(&dc, lib.slice(), 3, seed));
    // INVENT it: add to the library → the recursion works, it now reduces (depth-1)
    lib.appendAssumeCapacity(dc);
    try std.testing.expect(reducibleLib(&dc, lib.slice(), 2, seed));
}
