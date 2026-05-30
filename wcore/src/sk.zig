//! Untyped SK-combinator calculus — the purest substrate.
//!
//! The ENTIRE prior here is two combinators, `S` and `K`, plus application.
//! There are no types, no `Bool`, no `Unit`, no `Sensor`, no `Action`, no
//! numbers — nothing. SK is Turing-complete, so any computable structure is
//! expressible; by the invariance theorem the choice of basis only shifts
//! description lengths by a constant, so it smuggles in no bias toward any
//! particular answer.
//!
//! Reduction rules (normal order, leftmost-outermost):
//!     K x y     -> x
//!     S x y z   -> x z (y z)
//!
//! `Ref` is a reference to a discovered library abstraction (expanded during
//! reduction). `Atom` is an inert marker used ONLY by the behavioural verifier
//! to probe what a discovered combinator does — it is never part of the
//! engine's own vocabulary.

const std = @import("std");

pub const Tag = enum { S, K, App, Ref, Atom };

pub const Term = struct {
    tag: Tag,
    idx: usize = 0, // Ref: library index ; Atom: marker id
    a: ?*Term = null, // App: function
    b: ?*Term = null, // App: argument

    pub fn mk(al: std.mem.Allocator, tag: Tag) !*Term {
        const t = try al.create(Term);
        t.* = .{ .tag = tag };
        return t;
    }

    pub fn s(al: std.mem.Allocator) !*Term {
        return mk(al, .S);
    }
    pub fn k(al: std.mem.Allocator) !*Term {
        return mk(al, .K);
    }
    pub fn ref(al: std.mem.Allocator, idx: usize) !*Term {
        const t = try al.create(Term);
        t.* = .{ .tag = .Ref, .idx = idx };
        return t;
    }
    pub fn atom(al: std.mem.Allocator, idx: usize) !*Term {
        const t = try al.create(Term);
        t.* = .{ .tag = .Atom, .idx = idx };
        return t;
    }
    pub fn app(al: std.mem.Allocator, f: *Term, x: *Term) !*Term {
        const t = try al.create(Term);
        t.* = .{ .tag = .App, .a = f, .b = x };
        return t;
    }
};

pub fn nodeCount(t: *const Term) usize {
    return switch (t.tag) {
        .App => 1 + nodeCount(t.a.?) + nodeCount(t.b.?),
        else => 1,
    };
}

pub fn eql(x: *const Term, y: *const Term) bool {
    if (x.tag != y.tag) return false;
    return switch (x.tag) {
        .App => eql(x.a.?, y.a.?) and eql(x.b.?, y.b.?),
        .Ref, .Atom => x.idx == y.idx,
        else => true,
    };
}

pub fn write(t: *const Term, w: anytype) !void {
    switch (t.tag) {
        .S => try w.writeAll("S"),
        .K => try w.writeAll("K"),
        .Ref => try w.print("C{d}", .{t.idx}),
        .Atom => try w.print("m{d}", .{t.idx}),
        .App => {
            try w.writeAll("(");
            try write(t.a.?, w);
            try w.writeAll(" ");
            try write(t.b.?, w);
            try w.writeAll(")");
        },
    }
}

fn reassemble(al: std.mem.Allocator, head: *Term, rest: []const *Term) !*Term {
    var cur = head;
    for (rest) |r| cur = try Term.app(al, cur, r);
    return cur;
}

/// One leftmost-outermost head reduction (expanding a `Ref` head counts as a
/// step). Returns null if the head is in weak head normal form.
fn stepHead(al: std.mem.Allocator, t: *Term, lib: []const *Term) !?*Term {
    var args = std.ArrayList(*Term).init(al);
    defer args.deinit();
    var head = t;
    while (head.tag == .App) {
        try args.append(head.b.?);
        head = head.a.?;
    }
    std.mem.reverse(*Term, args.items);
    const n = args.items.len;
    switch (head.tag) {
        .Ref => {
            if (head.idx >= lib.len) return null;
            return try reassemble(al, lib[head.idx], args.items);
        },
        .K => {
            if (n >= 2) return try reassemble(al, args.items[0], args.items[2..]);
        },
        .S => {
            if (n >= 3) {
                const x = args.items[0];
                const y = args.items[1];
                const z = args.items[2];
                const xz = try Term.app(al, x, z);
                const yz = try Term.app(al, y, z);
                const nh = try Term.app(al, xz, yz);
                return try reassemble(al, nh, args.items[3..]);
            }
        },
        else => {},
    }
    return null;
}

fn whnf(al: std.mem.Allocator, t: *Term, lib: []const *Term, fuel: *usize) !*Term {
    var cur = t;
    while (fuel.* > 0) {
        fuel.* -= 1;
        const next = try stepHead(al, cur, lib) orelse return cur;
        cur = next;
    }
    return cur;
}

/// Reduce `t` to normal form (fuel-bounded; returns the partially-reduced term
/// if fuel runs out, which the caller treats as "non-normalizing").
pub fn normalize(al: std.mem.Allocator, t: *Term, lib: []const *Term, fuel: *usize) std.mem.Allocator.Error!*Term {
    const h = try whnf(al, t, lib, fuel);
    if (h.tag == .App) {
        const na = try normalize(al, h.a.?, lib, fuel);
        const nb = try normalize(al, h.b.?, lib, fuel);
        return Term.app(al, na, nb);
    }
    return h;
}

pub fn normalizeDefault(al: std.mem.Allocator, t: *Term, lib: []const *Term) !*Term {
    var fuel: usize = 200_000;
    return normalize(al, t, lib, &fuel);
}

test "K projects the first argument" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    const m0 = try Term.atom(al, 0);
    const m1 = try Term.atom(al, 1);
    const kab = try Term.app(al, try Term.app(al, try Term.k(al), m0), m1); // K m0 m1
    const r = try normalizeDefault(al, kab, &.{});
    try std.testing.expect(eql(r, m0));
}

test "SKK is the identity, SK is the second-projection (false)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    const m0 = try Term.atom(al, 0);
    const m1 = try Term.atom(al, 1);

    // SKK m0 -> m0
    const skk = try Term.app(al, try Term.app(al, try Term.s(al), try Term.k(al)), try Term.k(al));
    const id_applied = try Term.app(al, skk, m0);
    try std.testing.expect(eql(try normalizeDefault(al, id_applied, &.{}), m0));

    // SK m0 m1 -> m1
    const sk = try Term.app(al, try Term.s(al), try Term.k(al));
    const false_applied = try Term.app(al, try Term.app(al, sk, m0), m1);
    try std.testing.expect(eql(try normalizeDefault(al, false_applied, &.{}), m1));
}

test "Ref expands to its library definition during reduction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    const m0 = try Term.atom(al, 0);
    const skk = try Term.app(al, try Term.app(al, try Term.s(al), try Term.k(al)), try Term.k(al));
    const lib = [_]*Term{skk}; // C0 := SKK (identity)
    const applied = try Term.app(al, try Term.ref(al, 0), m0); // C0 m0
    try std.testing.expect(eql(try normalizeDefault(al, applied, &lib), m0));
}
