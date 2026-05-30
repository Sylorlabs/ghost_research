//! Anti-unification for the sleep phase.
//!
//! Detects repeated structure across the wake-phase programs WITHOUT knowing
//! what it means. Two generic motif detectors are provided:
//!
//!   * `detectLinear`   — a unary chain `App(head, App(head, ... base))`
//!                        (branching factor 1).
//!   * `detectBranching`— a binary tree `App(App(H, c0), c1)` whose children
//!                        recurse, terminating in a common leaf (factor 2).
//!
//! Neither tests for "Church numeral", "Nat", or "tree". They are pure
//! structural matchers. The sleep phase runs BOTH and lets node-count decide
//! which motif (if any) yields a compressing W-type. Linear data is often also
//! matchable as a degenerate right-leaning tree; the engine considers that and
//! still prefers the cheaper unary encoding — purely on node count.

const std = @import("std");
const terms = @import("terms.zig");
const Term = terms.Term;

pub const Kind = enum { linear, branching };

pub const Pattern = struct {
    kind: Kind,
    arity: usize,
    /// The repeated head: for linear, the outer application's function (a
    /// template such as `App(compose,id)`); for branching, the binary spine
    /// head `H`.
    head: *Term,
    /// The shared leaf the recursion terminates in.
    base: *Term,
    /// The original programs, kept so the invention can mirror their structure.
    programs: []const *Term,
    /// Internal-node count per program (a summary; the structure is in `programs`).
    counts: []usize,
};

/// Recursive children of a program node under this pattern, written into `buf`.
/// Returns the count, or null if `t` is not a node of this pattern.
pub fn recChildren(pat: *const Pattern, t: *Term, buf: *[2]*Term) ?usize {
    switch (pat.kind) {
        .linear => {
            if (t.tag == .App and t.kids[0] != null and Term.eql(t.kids[0].?, pat.head)) {
                buf[0] = t.kids[1].?;
                return 1;
            }
            return null;
        },
        .branching => {
            if (t.tag == .App and t.kids[0] != null and t.kids[0].?.tag == .App and
                Term.eql(t.kids[0].?.kids[0].?, pat.head))
            {
                buf[0] = t.kids[0].?.kids[1].?;
                buf[1] = t.kids[1].?;
                return 2;
            }
            return null;
        },
    }
}

/// Internal-node count of a program under `pat` (leaf = 0), or null if it does
/// not match the pattern.
fn measure(pat: *const Pattern, t: *Term) ?usize {
    if (Term.eql(t, pat.base)) return 0;
    var buf: [2]*Term = undefined;
    const n = recChildren(pat, t, &buf) orelse return null;
    var total: usize = 1;
    for (buf[0..n]) |child| {
        total += measure(pat, child) orelse return null;
    }
    return total;
}

// ---- linear (arity 1) -------------------------------------------------------

fn peel(t: *Term, head: *Term) struct { count: usize, base: *Term } {
    var cur = t;
    var count: usize = 0;
    while (cur.tag == .App and Term.eql(cur.kids[0].?, head)) {
        count += 1;
        cur = cur.kids[1].?;
    }
    return .{ .count = count, .base = cur };
}

pub fn detectLinear(a: std.mem.Allocator, programs: []const *Term) !?Pattern {
    if (programs.len == 0) return null;

    var head: ?*Term = null;
    var base: ?*Term = null;
    for (programs) |p| {
        if (p.tag == .App) {
            head = p.kids[0].?;
            break;
        }
    }
    if (head == null) base = programs[0];

    const counts = try a.alloc(usize, programs.len);
    for (programs, counts) |p, *c| {
        if (head) |h| {
            const r = peel(p, h);
            c.* = r.count;
            if (base == null) base = r.base;
            if (!Term.eql(r.base, base.?)) return null;
        } else {
            c.* = 0;
            if (!Term.eql(p, base.?)) return null;
        }
    }

    return Pattern{
        .kind = .linear,
        .arity = 1,
        .head = head orelse base.?,
        .base = base.?,
        .programs = programs,
        .counts = counts,
    };
}

// ---- branching (arity 2) ----------------------------------------------------

/// Descend first-children to find the leaf the tree terminates in.
fn leftmostLeaf(t: *Term, h: *Term) *Term {
    var cur = t;
    while (cur.tag == .App and cur.kids[0] != null and cur.kids[0].?.tag == .App and
        Term.eql(cur.kids[0].?.kids[0].?, h))
    {
        cur = cur.kids[0].?.kids[1].?;
    }
    return cur;
}

pub fn detectBranching(a: std.mem.Allocator, programs: []const *Term) !?Pattern {
    if (programs.len == 0) return null;

    // Derive the binary spine head H from the first program that is a 2-arg
    // curried application.
    var h: ?*Term = null;
    for (programs) |p| {
        if (p.tag == .App and p.kids[0] != null and p.kids[0].?.tag == .App) {
            h = p.kids[0].?.kids[0].?;
            break;
        }
    }
    const head = h orelse return null;
    const base = leftmostLeaf(programs[0], head);

    var pat = Pattern{
        .kind = .branching,
        .arity = 2,
        .head = head,
        .base = base,
        .programs = programs,
        .counts = try a.alloc(usize, programs.len),
    };

    for (programs, pat.counts) |p, *c| {
        c.* = measure(&pat, p) orelse return null;
    }
    return pat;
}

test "detectLinear: shared head + per-program counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const types = @import("types.zig");
    const u = try types.Type.mk(a, .Unit);

    const base = try Term.libRef(a, 0, u);
    const head = try Term.libRef(a, 1, u);
    var progs: [3]*Term = undefined;
    progs[0] = base;
    progs[1] = try Term.app(a, head, base, u);
    progs[2] = try Term.app(a, head, try Term.app(a, head, base, u), u);

    const pat = (try detectLinear(a, &progs)).?;
    try std.testing.expectEqual(Kind.linear, pat.kind);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, pat.counts);
}

test "detectBranching: perfect binary trees, internal-node counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const types = @import("types.zig");
    const u = try types.Type.mk(a, .Unit);

    const h = try Term.libRef(a, 2, u);
    const leaf = try Term.libRef(a, 0, u);
    const node = struct {
        fn mk(al: std.mem.Allocator, hh: *Term, l: *Term, r: *Term) !*Term {
            return Term.app(al, try Term.app(al, hh, l, null), r, null);
        }
    }.mk;

    var progs: [2]*Term = undefined;
    progs[0] = try node(a, h, leaf, leaf); // depth 1: 1 internal node
    progs[1] = try node(a, h, try node(a, h, leaf, leaf), try node(a, h, leaf, leaf)); // depth 2: 3

    const pat = (try detectBranching(a, &progs)).?;
    try std.testing.expectEqual(Kind.branching, pat.kind);
    try std.testing.expectEqual(@as(usize, 2), pat.arity);
    try std.testing.expectEqualSlices(usize, &.{ 1, 3 }, pat.counts);
}
