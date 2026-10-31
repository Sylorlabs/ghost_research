//! Math frontier 3 — the k≥3 cliff: where the map of closures ceases to exist.
//!
//! Frontier 2 showed the Boolean closure world is FULLY classified: 5 maximal clones (Post 1941), a
//! countable lattice, and "can substrate S invent predicate P?" is a finite property check. This probe
//! makes the navigability concrete, then shows the cliff: by Janov–Mučnik (1959), the moment the domain
//! has k≥3 elements there are UNCOUNTABLY many clones (2^ℵ₀) — no finite fingerprint, no Post-style map,
//! can exist. That is the formal home of "alien": the regime where "outside my closure" has no finite
//! description.
//!
//! Run: zig build kary-frontier --release=fast

const std = @import("std");

// ── Boolean (k=2) closure fingerprint: the 5 maximal-clone bits, on a binary op (arity 2, tt = 4 bits) ──
fn fval(tt: u8, x: u8) u1 {
    return @intCast((tt >> @intCast(x)) & 1);
}
fn isT0(tt: u8) bool {
    return fval(tt, 0) == 0;
}
fn isT1(tt: u8) bool {
    return fval(tt, 3) == 1;
}
fn isMonotone(tt: u8) bool {
    for (0..4) |x| for (0..4) |y| {
        if ((x & y) == x and fval(tt, @intCast(x)) > fval(tt, @intCast(y))) return false;
    };
    return true;
}
fn isSelfDual(tt: u8) bool {
    for (0..4) |x| {
        const comp: u8 = 3 ^ @as(u8, @intCast(x));
        if (fval(tt, comp) == fval(tt, @intCast(x))) return false;
    }
    return true;
}
fn isAffine(tt: u8) bool {
    const f0 = fval(tt, 0);
    for (0..4) |x| for (0..4) |y| {
        const xy: u8 = @as(u8, @intCast(x)) ^ @as(u8, @intCast(y));
        if ((fval(tt, @intCast(x)) ^ fval(tt, @intCast(y)) ^ fval(tt, xy) ^ f0) != 0) return false;
    };
    return true;
}

// k^(e) as f64 (for the explosion table), and a log10 magnitude
fn powf(k: f64, e: f64) f64 {
    return std.math.pow(f64, k, e);
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    try out.print("=== Math frontier 3: the k≥3 cliff — where the classification of closures ends ===\n\n", .{});

    // ── 1. k=2 is fingerprint-navigable: 5 bits classify every closure ──
    try out.print("──────── 1. k=2 (Boolean): a FINITE fingerprint classifies every closure ────────\n", .{});
    try out.print("Every binary op carries a 5-bit maximal-clone fingerprint (T0 T1 M D L). Universality is\n", .{});
    try out.print("EXACTLY an empty fingerprint (Post). Enumerate all 16 binary ops:\n\n", .{});
    var universal: usize = 0;
    var names: [16][]const u8 = undefined;
    for (0..16) |i| names[i] = "";
    names[0x7] = "NAND";
    names[0x1] = "NOR";
    names[0x6] = "XOR";
    names[0x8] = "AND";
    names[0xE] = "OR";
    names[0x9] = "XNOR";
    try out.print("  tt  fingerprint(T0 T1 M D L)   universal?   gate\n", .{});
    for (0..16) |ti| {
        const tt: u8 = @intCast(ti);
        const fp = [5]bool{ isT0(tt), isT1(tt), isMonotone(tt), isSelfDual(tt), isAffine(tt) };
        var empty = true;
        for (fp) |b| if (b) {
            empty = false;
        };
        if (empty) universal += 1;
        try out.print("  0x{X:0>1}   ", .{tt});
        for (fp) |b| try out.print("{s} ", .{if (b) "✓" else "·"});
        try out.print("       {s}        {s}\n", .{ if (empty) "UNIVERSAL" else "  ·      ", names[ti] });
    }
    try out.print("\n  → exactly {d}/16 binary ops are universal (the two Sheffer functions, NAND & NOR).\n", .{universal});
    try out.print("    The whole closure question reduces to a 5-bit check. k=2 invention is NAVIGABLE.\n", .{});

    // ── 2. the combinatorial vastness of k≥3 (illustration, not the proof) ──
    try out.print("\n──────── 2. the combinatorial jump at k≥3 (raw structure) ────────\n", .{});
    try out.print("                         k=2        k=3          k=4\n", .{});
    const ks = [_]f64{ 2, 3, 4 };
    try out.print("  binary ops  k^(k²)  :", .{});
    for (ks) |k| try out.print("  {d:.0}{s}", .{ powf(k, k * k), if (k == 2) "       " else "    " });
    try out.print("\n  idempotent  k^(k²−k):", .{});
    for (ks) |k| try out.print("  {d:.0}{s}", .{ powf(k, k * k - k), if (k == 2) "        " else "      " });
    try out.print("\n  relations   2^(k²)  :", .{});
    for (ks) |k| try out.print("  {d:.0}{s}", .{ powf(2, k * k), if (k == 2) "       " else "     " });
    try out.print("\n  ternary ops k^(k³)  :  ~10^{d:.0}     ~10^{d:.0}      ~10^{d:.0}\n", .{ ks[0] * ks[0] * ks[0] * std.math.log10(ks[0]), ks[1] * ks[1] * ks[1] * std.math.log10(ks[1]), ks[2] * ks[2] * ks[2] * std.math.log10(ks[2]) });

    // ── 3. the cliff: the cardinality theorem ──
    try out.print("\n──────── 3. the cliff (the actual theorems) ────────\n", .{});
    try out.print("                          | k=2 (Boolean)        | k≥3\n", .{});
    try out.print("  maximal clones          | 5  (Post 1941)       | finite, classified (Rosenberg 1970): k=3 → 18\n", .{});
    try out.print("  TOTAL # of clones        | ℵ₀ (countable)       | 2^ℵ₀  CONTINUUM (Janov–Mučnik 1959)\n", .{});
    try out.print("  finite closure fingerprint| YES (5 bits)         | IMPOSSIBLE — no finite set of properties\n", .{});
    try out.print("                          |                      | can separate uncountably many clones\n", .{});
    try out.print("  closure-membership       | finite property check| decidable but NOT a finite fingerprint;\n", .{});
    try out.print("                          |                      | the lattice has infinite antichains\n", .{});

    // ── verdict ──
    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try out.print("The complete map of closures — the thing that made the whole purist-invention story TERMINATE\n", .{});
    try out.print("cleanly (every ceiling a maximal-clone membership, every escape a covering relation) — exists\n", .{});
    try out.print("ONLY at k=2. The top of the lattice (maximal clones) stays finite for every k (Rosenberg), but\n", .{});
    try out.print("the lattice itself jumps from countable to CONTINUUM the instant k≥3 (Janov–Mučnik). There is no\n", .{});
    try out.print("finite fingerprint, no Post diagram, no navigable map.\n\n", .{});
    try out.print("This is the precise mathematical content of 'alien, no human would think of it': in the k≥3 regime,\n", .{});
    try out.print("'what lies outside my closure' is not a finite question. A 2-valued (true/false) substrate — every\n", .{});
    try out.print("predicate engine in this repo so far — is forever navigable and therefore forever bounded. Genuine\n", .{});
    try out.print("unmappable novelty requires leaving the Boolean cube for a many-valued / continuous substrate,\n", .{});
    try out.print("where the closure structure is itself uncountable. THAT is the substrate the original goal wanted —\n", .{});
    try out.print("and it is the same conclusion as the terminal result, now from the top: escape needs a substrate\n", .{});
    try out.print("whose closure lattice is not even classifiable, i.e. an out-of-Boolean ingredient.\n", .{});
    try out.print("\nSee: clone_lattice.md (k=2, fully mapped), boolean_fourier.md, inventable_substrate_design.md\n", .{});
    try out.print("(the terminal result this meets from above), CLOSURE_PRINCIPLE.md. Theory: Janov–Mučnik (1959);\n", .{});
    try out.print("Rosenberg (1970); Lau, *Function Algebras on Finite Sets* (2006).\n", .{});
}
