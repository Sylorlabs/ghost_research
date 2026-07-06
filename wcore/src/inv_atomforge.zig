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

pub const MATCH_THRESHOLD: f64 = coevo.MATCH_THRESHOLD;
pub const BASE_ATOMS: usize = 5;
pub const MAX_ROUNDS: usize = 8;
pub const COMPOSE_DEPTH: usize = 3;

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
pub fn applyChain(lib: []const alien.Program, idxs: []const usize, syms: []const u8, out: []u8) void {
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

pub const PromotionResult = struct {
    atoms: AtomLib,
    n_invented: usize,
    lengths: [MAX_ATOMS]usize,
};

/// Human-readable label for atom index in the standard library ordering.
pub fn atomLabel(i: usize) []const u8 {
    return switch (i) {
        0 => "g_xor",
        1 => "g_add",
        2 => "pk_xor",
        3 => "pk_add",
        4 => "shift",
        else => "inv",
    };
}

pub const RoundSnapshot = struct {
    atoms: AtomLib,
    n_invented: usize,
};

pub const PromotionSnapshots = struct {
    rounds: [MAX_ROUNDS + 1]RoundSnapshot,
    n_rounds: usize,
    lengths: [MAX_ATOMS]usize,
};

/// One behavioural task: a composition chain in the final promoted library.
pub const TaskChain = struct {
    /// Atom indices (0-based) in the final library; length = chain depth.
    idxs: []const usize,
    /// First promotion round (0 = base only) where this behaviour is composable.
    first_solvable_round: usize,
    /// Invented atoms (index ≥ BASE_ATOMS) used in this witness chain.
    n_invented_used: usize,
};

pub const InventedOnInventedResult = struct {
    snapshots: PromotionSnapshots,
    /// Tasks whose first solvable round is ≥ 2 (need ≥ 2 promotions).
    late_flip_count: usize,
    /// Subset requiring ≥ 2 invented atoms in the witness chain.
    invented_on_invented_count: usize,
    late_flips: []TaskChain,
    invented_on_invented: []TaskChain,
};

/// Run promotion, retaining the library after each round (round 0 = base atoms only).
pub fn runPromotionSnapshots(al: std.mem.Allocator, base_seed: u64) !PromotionSnapshots {
    const dseed = base_seed ^ 0x1F0;
    const fseed = base_seed +% 0xA70F;

    var atoms = baseAtoms();
    var lengths: [MAX_ATOMS]usize = undefined;
    var n_invented: usize = 0;

    var out: PromotionSnapshots = .{
        .rounds = undefined,
        .n_rounds = 1,
        .lengths = undefined,
    };
    out.rounds[0] = .{ .atoms = atoms, .n_invented = 0 };

    for (0..MAX_ROUNDS) |round| {
        var prng = std.Random.DefaultPrng.init(base_seed +% round *% 0x9E3779B97F4A7C15);
        var archive = try open.search(al, prng.random(), .{ .pop = 90, .gens = 45, .info = true, .seed = dseed });
        defer archive.deinit();

        std.mem.sort(open.Member, archive.items, {}, struct {
            fn lt(_: void, a: open.Member, b: open.Member) bool {
                return a.prog.len() < b.prog.len();
            }
        }.lt);

        var invented: ?alien.Program = null;
        for (archive.items) |cand| {
            if (!clean(&cand.prog, dseed)) continue;
            if (reducibleLib(&cand.prog, atoms.slice(), COMPOSE_DEPTH, fseed)) continue;
            invented = cand.prog;
            break;
        }
        if (invented == null) break;

        atoms.appendAssumeCapacity(invented.?);
        lengths[n_invented] = invented.?.len();
        n_invented += 1;
        out.n_rounds += 1;
        out.rounds[out.n_rounds - 1] = .{ .atoms = atoms, .n_invented = n_invented };
        if (atoms.len >= MAX_ATOMS) break;
    }

    out.lengths = lengths;
    return out;
}

/// Run the atom-forge promotion loop (same protocol as `atomforge` phase).
pub fn runPromotion(al: std.mem.Allocator, base_seed: u64) !PromotionResult {
    const snap = try runPromotionSnapshots(al, base_seed);
    const last = snap.rounds[snap.n_rounds - 1];
    return .{
        .atoms = last.atoms,
        .n_invented = last.n_invented,
        .lengths = snap.lengths,
    };
}

fn countInventedInChain(idxs: []const usize) usize {
    var n: usize = 0;
    for (idxs) |ix| {
        if (ix >= BASE_ATOMS) n += 1;
    }
    return n;
}

/// Fractional agreement between two atom chains (possibly different libs) on random streams.
fn chainAgreement(
    lib_a: []const alien.Program,
    a_idxs: []const usize,
    lib_b: []const alien.Program,
    b_idxs: []const usize,
    n: usize,
    L: usize,
    seed: u64,
) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out_a: [256]u8 = undefined;
    var out_b: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        applyChain(lib_a, a_idxs, syms[0..L], out_a[0..L]);
        applyChain(lib_b, b_idxs, syms[0..L], out_b[0..L]);
        for (0..L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

/// True iff `target_idxs` (into `full_lib`) is composable from `search_lib` at depth ≤ max_depth.
fn solvableFromLib(
    full_lib: []const alien.Program,
    target_idxs: []const usize,
    search_lib: []const alien.Program,
    max_depth: usize,
    seed: u64,
) bool {
    const n = search_lib.len;
    if (n == 0) return false;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [COMPOSE_DEPTH]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            if (chainAgreement(full_lib, target_idxs, search_lib, idxs[0..d], 8, 28, seed) >= MATCH_THRESHOLD) {
                return true;
            }
        }
    }
    return false;
}

/// Behavioural fingerprint for deduplicating task chains (fixed streams).
fn chainFingerprint(full_lib: []const alien.Program, idxs: []const usize, seed: u64) u64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out: [256]u8 = undefined;
    var h: u64 = seed;
    const L: usize = 28;
    const n_seq: usize = 4;
    for (0..n_seq) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        applyChain(full_lib, idxs, syms[0..L], out[0..L]);
        for (0..L) |i| h = std.hash.Wyhash.hash(h, &.{out[i]});
    }
    return h;
}

/// All distinct behaviour fingerprints composable from `lib` at depth ≤ max_depth.
fn composableFingerprints(
    al: std.mem.Allocator,
    lib: []const alien.Program,
    max_depth: usize,
    seed: u64,
) !std.AutoHashMap(u64, void) {
    var seen = std.AutoHashMap(u64, void).init(al);
    const n = lib.len;
    if (n == 0) return seen;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [COMPOSE_DEPTH]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            const fp = chainFingerprint(lib, idxs[0..d], seed);
            try seen.put(fp, {});
        }
    }
    return seen;
}

/// Enumerate distinct composition tasks from the final library; flag those solvable only
/// after promotion round ≥ 2, and those requiring ≥ 2 invented atoms (invented-on-invented).
pub fn analyzeInventedOnInvented(al: std.mem.Allocator, base_seed: u64) !InventedOnInventedResult {
    const fseed = base_seed +% 0xA70F;
    const snap = try runPromotionSnapshots(al, base_seed);
    const final = snap.rounds[snap.n_rounds - 1].atoms.slice();
    const n = final.len;

    // Precompute composable behaviour sets per promotion round (one exhaustive pass each).
    var round_fps = try al.alloc(std.AutoHashMap(u64, void), snap.n_rounds);
    defer {
        for (0..snap.n_rounds) |r| round_fps[r].deinit();
        al.free(round_fps);
    }
    for (0..snap.n_rounds) |r| {
        round_fps[r] = try composableFingerprints(al, snap.rounds[r].atoms.slice(), COMPOSE_DEPTH, fseed);
    }

    var seen = std.AutoHashMap(u64, void).init(al);
    defer seen.deinit();
    var late_flips = std.ArrayList(TaskChain).init(al);
    var ioi = std.ArrayList(TaskChain).init(al);

    // Catalogue: every composition chain up to COMPOSE_DEPTH in the final library.
    var d: usize = 1;
    while (d <= COMPOSE_DEPTH) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [COMPOSE_DEPTH]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            const fp = chainFingerprint(final, idxs[0..d], fseed);
            if (seen.contains(fp)) continue;
            try seen.put(fp, {});

            const inv_used = countInventedInChain(idxs[0..d]);
            if (inv_used == 0) continue; // base-only tasks are solvable at round 0

            var first_r: ?usize = null;
            for (0..snap.n_rounds) |r| {
                if (round_fps[r].contains(fp)) {
                    first_r = r;
                    break;
                }
            }
            const fr = first_r orelse continue;
            if (fr < 2) continue;

            const idx_copy = try al.dupe(usize, idxs[0..d]);
            try late_flips.append(.{
                .idxs = idx_copy,
                .first_solvable_round = fr,
                .n_invented_used = inv_used,
            });
            if (inv_used >= 2) {
                const copy2 = try al.dupe(usize, idxs[0..d]);
                try ioi.append(.{
                    .idxs = copy2,
                    .first_solvable_round = fr,
                    .n_invented_used = inv_used,
                });
            }
        }
    }

    const late_slice = try late_flips.toOwnedSlice();
    const ioi_slice = try ioi.toOwnedSlice();

    return .{
        .snapshots = snap,
        .late_flip_count = late_slice.len,
        .invented_on_invented_count = ioi_slice.len,
        .late_flips = late_slice,
        .invented_on_invented = ioi_slice,
    };
}

/// Free slices allocated inside `InventedOnInventedResult`.
pub fn freeInventedOnInvented(al: std.mem.Allocator, res: *InventedOnInventedResult) void {
    for (res.late_flips) |t| al.free(t.idxs);
    al.free(res.late_flips);
    for (res.invented_on_invented) |t| al.free(t.idxs);
    al.free(res.invented_on_invented);
}

/// Drop-each-atom ablation: atom `i` is redundant iff its behaviour is composable from the
/// other atoms at `depth`. Returns parallel bool slice (caller frees).
pub fn dropAblation(al: std.mem.Allocator, lib: []const alien.Program, depth: usize, seed: u64) ![]bool {
    const redundant = try al.alloc(bool, lib.len);
    for (0..lib.len) |drop_i| {
        var reduced = AtomLib{};
        for (0..lib.len) |j| {
            if (j != drop_i) reduced.appendAssumeCapacity(lib[j]);
        }
        redundant[drop_i] = reducibleLib(&lib[drop_i], reduced.slice(), depth, seed);
    }
    return redundant;
}

pub const MinimalResult = struct {
    atoms: AtomLib,
    kept_indices: []usize,
};

/// Greedy minimal library: iteratively remove atoms reducible to the remainder until fixed
/// point. Preserves behavioural coverage of every atom in the original library.
pub fn greedyMinimal(al: std.mem.Allocator, lib: []const alien.Program, depth: usize, seed: u64) !MinimalResult {
    var keep = std.ArrayList(usize).init(al);
    defer keep.deinit();
    for (0..lib.len) |i| try keep.append(i);

    var changed = true;
    while (changed) {
        changed = false;
        var next = std.ArrayList(usize).init(al);
        defer next.deinit();
        for (keep.items) |ki| {
            var reduced = AtomLib{};
            for (keep.items) |kj| {
                if (kj != ki) reduced.appendAssumeCapacity(lib[kj]);
            }
            if (reducibleLib(&lib[ki], reduced.slice(), depth, seed)) {
                changed = true;
                continue; // drop ki
            }
            try next.append(ki);
        }
        keep.clearRetainingCapacity();
        try keep.appendSlice(next.items);
    }

    var out = AtomLib{};
    for (keep.items) |ki| out.appendAssumeCapacity(lib[ki]);
    const kept = try al.dupe(usize, keep.items);
    return .{ .atoms = out, .kept_indices = kept };
}

/// True iff every atom behaviour in `full` is composable from `minimal` at `depth`.
pub fn coveragePreserved(full: []const alien.Program, minimal: []const alien.Program, depth: usize, seed: u64) bool {
    for (full) |atom| {
        if (!reducibleLib(&atom, minimal, depth, seed)) return false;
    }
    return true;
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
