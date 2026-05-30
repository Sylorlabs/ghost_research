//! A small call-by-value evaluator for closed terms.
//!
//! Helpful (not load-bearing for the milestone) for sanity-checking that the
//! terms we build actually reduce. Implements de Bruijn shifting/substitution,
//! beta reduction, and pair projection. A single-step unfolding for `WRec`
//! over a `WIntro` chain is provided so invented recursors are at least
//! partially executable; full W-recursion semantics are post-milestone.

const std = @import("std");
const types = @import("types.zig");
const terms = @import("terms.zig");
const Type = types.Type;
const Term = terms.Term;

fn shift(a: std.mem.Allocator, t: *Term, d: i64, cutoff: usize) std.mem.Allocator.Error!*Term {
    switch (t.tag) {
        .Var => {
            if (t.idx >= cutoff) {
                const ni: usize = @intCast(@as(i64, @intCast(t.idx)) + d);
                return Term.vr(a, ni, t.ty.?);
            }
            return t;
        },
        .Lam => {
            const body = try shift(a, t.kids[0].?, d, cutoff + 1);
            return Term.lam(a, body, t.ty.?);
        },
        else => return mapKids(a, t, shiftClosure{ .d = d, .cutoff = cutoff }),
    }
}

const shiftClosure = struct {
    d: i64,
    cutoff: usize,
    fn call(self: @This(), a: std.mem.Allocator, kid: *Term) !*Term {
        return shift(a, kid, self.d, self.cutoff);
    }
};

/// Substitute `val` for de Bruijn index `j` inside `t`.
fn subst(a: std.mem.Allocator, t: *Term, j: usize, val: *Term) std.mem.Allocator.Error!*Term {
    switch (t.tag) {
        .Var => {
            if (t.idx == j) return val;
            return t;
        },
        .Lam => {
            const shifted = try shift(a, val, 1, 0);
            const body = try subst(a, t.kids[0].?, j + 1, shifted);
            return Term.lam(a, body, t.ty.?);
        },
        else => {
            var nk: [3]?*Term = .{ null, null, null };
            for (t.kids, 0..) |k, i| {
                if (k) |kv| nk[i] = try subst(a, kv, j, val);
            }
            const nt = try a.create(Term);
            nt.* = t.*;
            nt.kids = nk;
            return nt;
        },
    }
}

fn mapKids(a: std.mem.Allocator, t: *Term, ctx: anytype) !*Term {
    var nk: [3]?*Term = .{ null, null, null };
    for (t.kids, 0..) |k, i| {
        if (k) |kv| nk[i] = try ctx.call(a, kv);
    }
    const nt = try a.create(Term);
    nt.* = t.*;
    nt.kids = nk;
    return nt;
}

/// Reduce a closed term toward a normal form (bounded by `fuel` steps).
pub fn eval(a: std.mem.Allocator, t: *Term, fuel: usize) std.mem.Allocator.Error!*Term {
    if (fuel == 0) return t;
    switch (t.tag) {
        .App => {
            const func = try eval(a, t.kids[0].?, fuel - 1);
            const arg = try eval(a, t.kids[1].?, fuel - 1);
            if (func.tag == .Lam) {
                const shifted_arg = try shift(a, arg, 1, 0);
                const substituted = try subst(a, func.kids[0].?, 0, shifted_arg);
                const unshifted = try shift(a, substituted, -1, 0);
                return eval(a, unshifted, fuel - 1);
            }
            return Term.app(a, func, arg, t.ty);
        },
        .Proj1 => {
            const tgt = try eval(a, t.kids[0].?, fuel - 1);
            if (tgt.tag == .PairIntro) return eval(a, tgt.kids[0].?, fuel - 1);
            return t;
        },
        .Proj2 => {
            const tgt = try eval(a, t.kids[0].?, fuel - 1);
            if (tgt.tag == .PairIntro) return eval(a, tgt.kids[1].?, fuel - 1);
            return t;
        },
        .WRec => {
            // Genuine W-recursion of ANY arity: a leaf returns the base; a node
            // applies `step` (curried) to the recursive results of all its
            // children. Running this on a W-value regenerates the original
            // unrolled term — arity-1 reproduces a chain, arity-2 a binary tree
            // — which is how we verify the invented type is behaviourally
            // faithful regardless of which W-type was invented.
            const step = t.kids[0].?;
            const target = try eval(a, t.kids[1].?, fuel - 1);
            const base = t.kids[2].?;
            if (target.tag == .WIntro) {
                var has_child = false;
                var acc = step;
                for (target.kids) |maybe_child| {
                    const child = maybe_child orelse continue;
                    has_child = true;
                    const sub = try Term.wRec(a, t.motive, step, child, base, t.ty);
                    const folded = try eval(a, sub, fuel - 1);
                    acc = try Term.app(a, acc, folded, t.ty);
                }
                if (!has_child) return eval(a, base, fuel - 1); // leaf
                return acc;
            }
            return t;
        },
        else => return t,
    }
}

/// Read the length of an `App(head, App(head, ... base))` chain, or null if the
/// term is not such a chain (heads must all structurally match `head`). This is
/// the denotation the wake-phase search scores candidates against.
pub fn chainLength(t: *Term, head: *Term, base: *Term) ?usize {
    var cur = t;
    var n: usize = 0;
    while (cur.tag == .App) {
        if (!Term.eql(cur.kids[0].?, head)) return null;
        n += 1;
        cur = cur.kids[1].?;
    }
    if (!Term.eql(cur, base)) return null;
    return n;
}

/// Fold a W-value to its internal-node count (leaf = 0, node = 1 + sum of
/// children) — a host integer. This EXECUTES the invented eliminator's counting
/// motive on data, for a W-type of any arity (chain or tree).
pub fn foldCount(wval: *Term) usize {
    if (wval.tag != .WIntro) return 0;
    var any = false;
    var n: usize = 0;
    for (wval.kids) |c| {
        if (c) |cv| {
            any = true;
            n += foldCount(cv);
        }
    }
    return if (any) n + 1 else 0;
}

test "beta reduction of identity applied to unit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try Type.mk(a, .Unit);
    const uu = try Type.mkFun(a, unit, unit);
    const id = try Term.lam(a, try Term.vr(a, 0, unit), uu);
    const u = try Term.unitIntro(a, unit);
    const applied = try Term.app(a, id, u, unit);
    const result = try eval(a, applied, 100);
    try std.testing.expectEqual(terms.TermTag.UnitIntro, result.tag);
}

test "WRec folds a W-numeral and regenerates a chain of the right length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try Type.mk(a, .Unit);

    // build the W-numeral 3 (succ idx 0, zero idx 1)
    var wnum = try Term.wIntro(a, 1, &.{}, null); // zero leaf
    var i: usize = 0;
    while (i < 3) : (i += 1) wnum = try Term.wIntro(a, 0, &.{wnum}, null);
    try std.testing.expectEqual(@as(usize, 3), foldCount(wnum));

    // run the recursor: WRec(step=head, target=3, base) applies head 3x to base
    const head = try Term.libRef(a, 9, unit);
    const base = try Term.unitIntro(a, unit);
    const rec = try Term.wRec(a, unit, head, wnum, base, unit);
    const result = try eval(a, rec, 1000);
    try std.testing.expectEqual(@as(?usize, 3), chainLength(result, head, base));
}

test "WRec folds and regenerates a binary tree (arity-2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try Type.mk(a, .Unit);

    // perfect binary-tree W-value of depth 2 (node idx 0, leaf idx 1)
    const leaf = try Term.wIntro(a, 1, &.{}, null);
    const d1 = try Term.wIntro(a, 0, &.{ leaf, leaf }, null);
    const d2 = try Term.wIntro(a, 0, &.{ d1, d1 }, null);
    try std.testing.expectEqual(@as(usize, 3), foldCount(d2)); // 2^2 - 1 internal nodes

    // regenerate: WRec(step, d2, base) must rebuild node(node(b,b),node(b,b))
    const step = try Term.libRef(a, 5, unit); // a binary combinator
    const base = try Term.libRef(a, 6, unit); // the leaf term
    const node = struct {
        fn mk(al: std.mem.Allocator, s: *Term, l: *Term, r: *Term) !*Term {
            return Term.app(al, try Term.app(al, s, l, null), r, null);
        }
    }.mk;
    const expected = try node(a, step, try node(a, step, base, base), try node(a, step, base, base));

    const rec = try Term.wRec(a, unit, step, d2, base, unit);
    const regen = try eval(a, rec, 100000);
    try std.testing.expect(Term.eql(regen, expected));
}

test "projection of a pair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try Type.mk(a, .Unit);
    const bool_ = try Type.mk(a, .Bool);
    const pty = try Type.mkPair(a, unit, bool_);
    const p = try Term.pair(a, try Term.unitIntro(a, unit), try Term.boolIntro(a, true, bool_), pty);
    const snd = try Term.proj2(a, p, bool_);
    const result = try eval(a, snd, 100);
    try std.testing.expectEqual(terms.TermTag.BoolIntro, result.tag);
    try std.testing.expect(result.boolVal);
}
