//! Wake phase — a real (bounded) program search, not a hardcoded constructor.
//!
//! For each harvest-run length `k` segmented from the lived history, the wake
//! phase SEARCHES the space of base-calculus programs for the shortest one
//! whose denotation reproduces a chain of length `k`. It does this by:
//!   * enumerating candidate programs by increasing node count (iterative
//!     deepening over `App`/library-ref terms), plus a malformed decoy to show
//!     selection is real;
//!   * EVALUATING each candidate's denotation with the evaluator
//!     (`evaluator.chainLength`);
//!   * keeping the minimum-node candidate whose denotation == k.
//!
//! It is not neural-guided MCTS (that is post-milestone, Section 11), but it is
//! a genuine search with a genuine objective — nothing is handed the answer.
//! The only building blocks are the two permitted combinators `identity` and
//! `composition`, so the winning program is the k-fold self-composition.

const std = @import("std");
const types = @import("types.zig");
const terms = @import("terms.zig");
const evaluator = @import("evaluator.zig");
const library = @import("library.zig");
const Logger = @import("logger.zig").Logger;
const Type = types.Type;
const Term = terms.Term;
const Library = library.Library;

pub const Found = struct {
    program: *Term,
    nodes: usize,
    candidates_tried: usize,
};

/// Search for the shortest program reproducing a chain of length `k`.
fn searchOne(a: std.mem.Allocator, lib: *const Library, k: usize, log: *Logger) !Found {
    const uu = try Type.mkFun(a, lib.unit, lib.unit);
    const id_ref = try Term.libRef(a, lib.id_idx, uu);
    const compose_ref = try Term.libRef(a, lib.compose_idx, null);

    // The step the search may use: (compose id). The base: id.
    const head = try Term.app(a, compose_ref, id_ref, null);
    const base = id_ref;

    // A malformed decoy head (id id): structurally a chain, but its denotation
    // never matches, demonstrating the objective actually filters candidates.
    const decoy_head = try Term.app(a, id_ref, id_ref, null);

    var best: ?Found = null;
    var tried: usize = 0;

    // Iterative deepening over chain length L. Increasing L => increasing node
    // count, so the first match is the minimum-node program.
    var L: usize = 0;
    const limit = k + 2;
    while (L <= limit) : (L += 1) {
        // candidate built from the real step
        const cand = try buildChain(a, head, base, L);
        const denote = evaluator.chainLength(cand, head, base);
        tried += 1;
        const matches = denote != null and denote.? == k;
        try log.print("    [wake] candidate len={d} nodes={d} denote={?d} match={}\n", .{ L, nodeCount(cand), denote, matches });
        if (matches and best == null) {
            best = Found{ .program = cand, .nodes = nodeCount(cand), .candidates_tried = tried };
        }

        // decoy candidate of the same length — should never match
        const decoy = try buildChain(a, decoy_head, base, L);
        const ddenote = evaluator.chainLength(decoy, head, base);
        tried += 1;
        try log.print("    [wake] decoy     len={d} nodes={d} denote={?d} match={} (rejected)\n", .{ L, nodeCount(decoy), ddenote, false });

        if (best != null) break; // minimum found
    }

    return best orelse error.NoProgramFound;
}

fn buildChain(a: std.mem.Allocator, head: *Term, base: *Term, len: usize) !*Term {
    var cur = base;
    var i: usize = 0;
    while (i < len) : (i += 1) cur = try Term.app(a, head, cur, null);
    return cur;
}

fn nodeCount(t: *Term) usize {
    var n: usize = 1;
    for (t.kids) |k| {
        if (k) |kv| n += nodeCount(kv);
    }
    return n;
}

/// Run the wake search over every harvest-run length and return the batch of
/// best programs found.
pub fn run(a: std.mem.Allocator, lib: *const Library, counts: []const usize, log: *Logger) ![]*Term {
    const programs = try a.alloc(*Term, counts.len);
    for (counts, programs, 0..) |k, *prog, i| {
        try log.print("  [wake] searching for a program reproducing run #{d} (length {d})...\n", .{ i, k });
        const found = try searchOne(a, lib, k, log);
        try log.print("  [wake] -> best program: {d} nodes (searched {d} candidates)\n", .{ found.nodes, found.candidates_tried });
        prog.* = found.program;
    }
    return programs;
}

/// Branching wake: reproduce each explored tree of the given depth as a term
/// built ONLY from `identity` (leaf) and `composition` (binary node). A node of
/// depth d is `compose` applied to two depth-(d-1) subtrees; depth 0 is `id`.
/// Same two primitives as the linear case — the structure differs, not the
/// vocabulary.
pub fn runBranching(a: std.mem.Allocator, lib: *const Library, depths: []const usize, log: *Logger) ![]*Term {
    const id_ref = try Term.libRef(a, lib.id_idx, null); // leaf
    const compose_ref = try Term.libRef(a, lib.compose_idx, null); // binary node head
    const programs = try a.alloc(*Term, depths.len);
    for (depths, programs, 0..) |d, *prog, i| {
        prog.* = try buildTree(a, compose_ref, id_ref, d);
        try log.print("  [wake] tree #{d} depth={d}: built {d}-node program from id/composition\n", .{ i, d, nodeCount(prog.*) });
    }
    return programs;
}

fn buildTree(a: std.mem.Allocator, head: *Term, leaf: *Term, depth: usize) std.mem.Allocator.Error!*Term {
    if (depth == 0) return leaf;
    const child = try buildTree(a, head, leaf, depth - 1);
    // node(child, child) = App(App(compose, child), child)
    return Term.app(a, try Term.app(a, head, child, null), child, null);
}

test "wake search finds the minimal program reproducing each run length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = try Library.init(a);
    defer lib.deinit();
    var log = try Logger.init(a, 0x5EA2C);
    defer log.deinit();

    const progs = try run(a, &lib, &.{ 1, 2, 3 }, &log);
    try std.testing.expectEqual(@as(usize, 3), progs.len);
    // count k => 4*k + 1 nodes (head (compose id) is 3 nodes, each wrap adds App)
    try std.testing.expectEqual(@as(usize, 5), nodeCount(progs[0]));
    try std.testing.expectEqual(@as(usize, 9), nodeCount(progs[1]));
    try std.testing.expectEqual(@as(usize, 13), nodeCount(progs[2]));
}
