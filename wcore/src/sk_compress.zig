//! Compression-by-abstraction over SK terms — the simplicity prior in action.
//!
//! Given a corpus of SK expressions, find the subterm whose extraction into a
//! single named library entry most reduces the total description length
//! (corpus + library node count). Replace its occurrences with a `Ref`, and
//! repeat. This is exactly MDL / common-subexpression compression — the same
//! "make it shorter" rule the W-type engine uses, with nothing else added.
//!
//! `classify` then reports, AFTER the fact, what a discovered combinator does,
//! by applying it to inert markers and reducing. The labels (identity, Church
//! true/false) are post-hoc; the discovery itself is pure node count.

const std = @import("std");
const sk = @import("sk.zig");
const Term = sk.Term;

pub const Extraction = struct {
    subterm: *Term,
    occurrences: usize,
    saved: usize,
};

fn contains(list: []const *Term, t: *Term) bool {
    for (list) |e| {
        if (sk.eql(e, t)) return true;
    }
    return false;
}

fn collect(t: *Term, out: *std.ArrayList(*Term)) !void {
    if (sk.nodeCount(t) >= 2 and !contains(out.items, t)) try out.append(t);
    if (t.tag == .App) {
        try collect(t.a.?, out);
        try collect(t.b.?, out);
    }
}

pub fn countOcc(t: *Term, sub: *Term) usize {
    if (sk.eql(t, sub)) return 1; // a term cannot strictly contain a copy of itself
    if (t.tag == .App) return countOcc(t.a.?, sub) + countOcc(t.b.?, sub);
    return 0;
}

pub fn rewrite(al: std.mem.Allocator, t: *Term, sub: *Term, ref_idx: usize) std.mem.Allocator.Error!*Term {
    if (sk.eql(t, sub)) return Term.ref(al, ref_idx);
    if (t.tag == .App) {
        return Term.app(al, try rewrite(al, t.a.?, sub, ref_idx), try rewrite(al, t.b.?, sub, ref_idx));
    }
    return t;
}

/// The single highest-saving abstraction over `corpus`, or null if none reduces
/// the description length. Saving of a subterm of size `sz` occurring `occ`
/// times: replacing `occ` inlined copies (occ*sz nodes) with `occ` refs plus
/// one stored copy (occ + sz nodes) ⇒ saved = occ*sz - (occ + sz).
pub fn bestExtraction(al: std.mem.Allocator, corpus: []const *Term) !?Extraction {
    var cands = std.ArrayList(*Term).init(al);
    defer cands.deinit();
    for (corpus) |c| try collect(c, &cands);

    var best: ?Extraction = null;
    for (cands.items) |sub| {
        var occ: usize = 0;
        for (corpus) |c| occ += countOcc(c, sub);
        if (occ < 2) continue;
        const sz = sk.nodeCount(sub);
        const old = occ * sz;
        const new = occ + sz;
        if (new >= old) continue;
        const saved = old - new;
        if (best == null or saved > best.?.saved) {
            best = Extraction{ .subterm = sub, .occurrences = occ, .saved = saved };
        }
    }
    return best;
}

/// Replace every occurrence of `sub` across the corpus with `Ref(ref_idx)`.
pub fn applyExtraction(al: std.mem.Allocator, corpus: []const *Term, sub: *Term, ref_idx: usize) ![]*Term {
    const out = try al.alloc(*Term, corpus.len);
    for (corpus, out) |c, *o| o.* = try rewrite(al, c, sub, ref_idx);
    return out;
}

pub fn totalNodes(corpus: []const *Term, lib: []const *Term) usize {
    var n: usize = 0;
    for (corpus) |c| n += sk.nodeCount(c);
    for (lib) |l| n += sk.nodeCount(l);
    return n;
}

pub const Kind = enum { identity, church_true, church_false, duplicator, other };

pub fn kindName(k: Kind) []const u8 {
    return switch (k) {
        .identity => "identity combinator (I = \\x.x)",
        .church_true => "Church TRUE / first-projection (K)",
        .church_false => "Church FALSE / second-projection",
        .duplicator => "duplicator (W/delta = \\x. x x)",
        .other => "(no standard behaviour recognised)",
    };
}

/// Identify what library entry `idx` does, by applying it to inert markers and
/// reducing. Purely observational; the result is a label, not a decision input.
pub fn classify(al: std.mem.Allocator, idx: usize, lib: []const *Term) !Kind {
    const m0 = try Term.atom(al, 100);
    const m1 = try Term.atom(al, 101);

    const unary = try Term.app(al, try Term.ref(al, idx), m0);
    const u = try sk.normalizeDefault(al, unary, lib);
    if (sk.eql(u, m0)) return .identity;
    const m0m0 = try Term.app(al, m0, m0);
    if (sk.eql(u, m0m0)) return .duplicator;

    const binary = try Term.app(al, try Term.app(al, try Term.ref(al, idx), m0), m1);
    const r = try sk.normalizeDefault(al, binary, lib);
    if (sk.eql(r, m0)) return .church_true;
    if (sk.eql(r, m1)) return .church_false;
    return .other;
}

test "compression extracts the most-saving shared subterm" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();

    // identity SKK appears 3 times across the corpus
    const skk = try Term.app(al, try Term.app(al, try Term.s(al), try Term.k(al)), try Term.k(al));
    var corpus = [_]*Term{
        try Term.app(al, skk, try Term.k(al)),
        try Term.app(al, skk, try Term.s(al)),
        try Term.app(al, try Term.k(al), skk),
    };
    const ext = (try bestExtraction(al, &corpus)).?;
    try std.testing.expect(sk.eql(ext.subterm, skk));
    try std.testing.expectEqual(@as(usize, 3), ext.occurrences);
}

test "a discovered SKK abstraction classifies as the identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    const skk = try Term.app(al, try Term.app(al, try Term.s(al), try Term.k(al)), try Term.k(al));
    const lib = [_]*Term{skk};
    try std.testing.expectEqual(Kind.identity, try classify(al, 0, &lib));
}

test "a discovered SK abstraction classifies as Church false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    const sk_term = try Term.app(al, try Term.s(al), try Term.k(al));
    const lib = [_]*Term{sk_term};
    try std.testing.expectEqual(Kind.church_false, try classify(al, 0, &lib));
}

test "S I I classifies as the duplicator (\\x. x x)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    const i = try Term.app(al, try Term.app(al, try Term.s(al), try Term.k(al)), try Term.k(al)); // SKK
    const sii = try Term.app(al, try Term.app(al, try Term.s(al), i), i); // S I I
    const lib = [_]*Term{sii};
    try std.testing.expectEqual(Kind.duplicator, try classify(al, 0, &lib));
}
