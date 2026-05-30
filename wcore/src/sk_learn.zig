//! Cumulative learning across a sequence of streams.
//!
//! A persistent library of discovered abstractions is carried from one stream
//! to the next. For each new stream we first REUSE what we already know
//! (refactor occurrences of known abstractions into references), then discover
//! whatever new structure remains. Because new abstractions are extracted from
//! the already-refactored corpus, they can REFERENCE earlier ones — so the
//! library grows into a tower (e.g. a duplicator built on the identity built on
//! S/K). That compounding is exactly the "it learns over time" property.

const std = @import("std");
const sk = @import("sk.zig");
const comp = @import("sk_compress.zig");
const Term = sk.Term;

/// Resolve every `Ref` in `t` to raw S/K (library entries reference only
/// earlier entries, so this terminates).
pub fn expand(al: std.mem.Allocator, t: *Term, lib: []const *Term) std.mem.Allocator.Error!*Term {
    return switch (t.tag) {
        .Ref => expand(al, lib[t.idx], lib),
        .App => Term.app(al, try expand(al, t.a.?, lib), try expand(al, t.b.?, lib)),
        else => t,
    };
}

pub const Reuse = struct { idx: usize, count: usize };

/// Refactor `corpus` against the existing `lib`: replace occurrences of each
/// known abstraction's expanded form with a reference to it. Larger
/// abstractions are matched first so the most compressive known chunk wins.
/// Returns the rewritten corpus and the per-entry reuse counts.
pub fn refactorAgainstLibrary(
    al: std.mem.Allocator,
    corpus: []const *Term,
    lib: []const *Term,
) !struct { corpus: []*Term, reuses: []Reuse } {
    const expanded = try al.alloc(*Term, lib.len);
    for (lib, expanded) |def, *e| e.* = try expand(al, def, lib);

    // order library indices by expanded size, descending
    const order = try al.alloc(usize, lib.len);
    for (order, 0..) |*o, i| o.* = i;
    std.sort.insertion(usize, order, expanded, struct {
        fn lt(exp: []*Term, x: usize, y: usize) bool {
            return sk.nodeCount(exp[x]) > sk.nodeCount(exp[y]);
        }
    }.lt);

    const out = try al.alloc(*Term, corpus.len);
    for (corpus, out) |c, *o| o.* = c;

    var reuses = std.ArrayList(Reuse).init(al);
    for (order) |idx| {
        var count: usize = 0;
        for (out) |c| count += comp.countOcc(c, expanded[idx]);
        if (count == 0) continue;
        for (out) |*c| c.* = try comp.rewrite(al, c.*, expanded[idx], idx);
        try reuses.append(.{ .idx = idx, .count = count });
    }
    return .{ .corpus = out, .reuses = try reuses.toOwnedSlice() };
}

test "expand resolves a tower of references to raw SK" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    const sk_term = try Term.app(al, try Term.s(al), try Term.k(al)); // C0 = SK
    const skk = try Term.app(al, try Term.ref(al, 0), try Term.k(al)); // C1 = (C0 K)
    const lib = [_]*Term{ sk_term, skk };
    const e = try expand(al, try Term.ref(al, 1), &lib);
    const raw = try Term.app(al, try Term.app(al, try Term.s(al), try Term.k(al)), try Term.k(al)); // SKK
    try std.testing.expect(sk.eql(e, raw));
}

test "refactor reuses a known abstraction in a fresh corpus" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    const skk = try Term.app(al, try Term.app(al, try Term.s(al), try Term.k(al)), try Term.k(al));
    const lib = [_]*Term{skk}; // C0 := SKK already known
    var corpus = [_]*Term{
        try Term.app(al, skk, try Term.s(al)), // (SKK S)
        try Term.app(al, try Term.k(al), skk), // (K SKK)
    };
    const res = try refactorAgainstLibrary(al, &corpus, &lib);
    try std.testing.expectEqual(@as(usize, 1), res.reuses.len);
    try std.testing.expectEqual(@as(usize, 2), res.reuses[0].count);
    // both SKK occurrences are now a single-node reference C0
    try std.testing.expect(sk.eql(res.corpus[0].a.?, try Term.ref(al, 0)));
}
