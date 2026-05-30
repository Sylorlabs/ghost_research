//! Term nodes for the wcore kernel.
//!
//! Intrinsically-typed terms with de Bruijn indices for bound variables. The
//! kernel has NO general recursion: the only way to "loop" is through `WRec`,
//! the eliminator for a W-type — and W-types do not exist until the sleep phase
//! invents one. So before any invention, every program is a finite, fully
//! unrolled term. That is exactly why repeated structure shows up as literal
//! repetition (and why a W-type can later compress it).
//!
//! `kids` holds child terms in a small fixed array; the per-tag meaning is
//! documented on each smart constructor.

const std = @import("std");
const types = @import("types.zig");
const Type = types.Type;

pub const TermTag = enum {
    Var,
    Lam,
    App,
    UnitIntro,
    BoolIntro,
    PairIntro,
    Proj1,
    Proj2,
    WIntro, // sup: a constructor choice (idx) + its recursive subtree (kids[0], null for a leaf)
    WRec, // eliminator: motive + step (kids[0]) + target (kids[1]) + base (kids[2])
    LibRef, // reference to a library definition by index — one node
};

pub const Term = struct {
    tag: TermTag,
    ty: ?*Type = null,
    /// Var: de Bruijn index; LibRef: library index; WIntro: which shape-inhabitant.
    idx: usize = 0,
    boolVal: bool = false, // BoolIntro
    motive: ?*Type = null, // WRec
    kids: [3]?*Term = .{ null, null, null },

    pub fn vr(a: std.mem.Allocator, index: usize, ty: *Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .Var, .idx = index, .ty = ty };
        return t;
    }

    pub fn lam(a: std.mem.Allocator, body: *Term, funTy: *Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .Lam, .ty = funTy, .kids = .{ body, null, null } };
        return t;
    }

    pub fn app(a: std.mem.Allocator, func: *Term, arg: *Term, ty: ?*Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .App, .ty = ty, .kids = .{ func, arg, null } };
        return t;
    }

    pub fn unitIntro(a: std.mem.Allocator, unit: *Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .UnitIntro, .ty = unit };
        return t;
    }

    pub fn boolIntro(a: std.mem.Allocator, val: bool, bool_: *Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .BoolIntro, .boolVal = val, .ty = bool_ };
        return t;
    }

    pub fn pair(a: std.mem.Allocator, left: *Term, right: *Term, ty: *Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .PairIntro, .ty = ty, .kids = .{ left, right, null } };
        return t;
    }

    pub fn proj1(a: std.mem.Allocator, target: *Term, ty: ?*Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .Proj1, .ty = ty, .kids = .{ target, null, null } };
        return t;
    }

    pub fn proj2(a: std.mem.Allocator, target: *Term, ty: ?*Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .Proj2, .ty = ty, .kids = .{ target, null, null } };
        return t;
    }

    pub fn libRef(a: std.mem.Allocator, index: usize, ty: ?*Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .LibRef, .idx = index, .ty = ty };
        return t;
    }

    /// `sup`: choose constructor `shapeIdx`; `children` are the recursive
    /// subtrees (0 for a leaf, 1 for a unary/successor, 2 for a binary node).
    pub fn wIntro(a: std.mem.Allocator, shapeIdx: usize, children: []const *Term, ty: ?*Type) !*Term {
        var kids: [3]?*Term = .{ null, null, null };
        for (children, 0..) |c, i| kids[i] = c;
        const t = try a.create(Term);
        t.* = .{ .tag = .WIntro, .idx = shapeIdx, .ty = ty, .kids = kids };
        return t;
    }

    /// `base` is returned when the recursion bottoms out at a leaf (kids[2]).
    pub fn wRec(a: std.mem.Allocator, motive: ?*Type, step: *Term, target: *Term, base: *Term, ty: ?*Type) !*Term {
        const t = try a.create(Term);
        t.* = .{ .tag = .WRec, .motive = motive, .ty = ty, .kids = .{ step, target, base } };
        return t;
    }

    /// Structural equality over the term skeleton (tag/idx/boolVal/children).
    /// Types are intentionally ignored so the anti-unifier matches repeated
    /// *shape* regardless of how the checker annotated it.
    pub fn eql(x: *const Term, y: *const Term) bool {
        if (x.tag != y.tag) return false;
        if (x.idx != y.idx) return false;
        if (x.boolVal != y.boolVal) return false;
        for (x.kids, y.kids) |xk, yk| {
            if ((xk == null) != (yk == null)) return false;
            if (xk) |xkv| {
                if (!eql(xkv, yk.?)) return false;
            }
        }
        return true;
    }
};

test "term equality matches repeated structure ignoring types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const u = try Type.mk(a, .Unit);
    const r1 = try Term.libRef(a, 0, u);
    const r2 = try Term.libRef(a, 0, null);
    try std.testing.expect(Term.eql(r1, r2));
    const r3 = try Term.libRef(a, 1, u);
    try std.testing.expect(!Term.eql(r1, r3));
}
