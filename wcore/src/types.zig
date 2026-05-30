//! Type nodes for the wcore kernel.
//!
//! A `Type` is a node in an intrinsic type theory. The kernel begins life
//! knowing only `Unit`, `Bool`, `Sensor`, `Action` (plus `Fun`/`Pair` formers
//! and `Univ`). `Bottom` (the empty type) and `W` (well-founded trees) are NOT
//! among the starting primitives — they only enter the library when the sleep
//! phase proposes them. This is load-bearing for the zero-bias claim: there is
//! no `Nat` here, and nothing that presupposes counting.
//!
//! W-types are represented as `W { shape, positions }` where `shape` is a
//! finite type and `positions` is the position family `P : shape -> Univ`
//! reified as one position-type per inhabitant of `shape`. Each position type
//! is either `Unit` (one recursive subtree — an arity-1 constructor) or
//! `Bottom` (no recursive subtree — an arity-0 / leaf constructor). For a shape
//! with inhabitants i0,i1,... the positions slice holds the position type for
//! each, in inhabitant order.

const std = @import("std");

pub const TypeTag = enum {
    Unit,
    Bool,
    Bottom,
    Sensor,
    Action,
    Univ,
    Fun,
    Pair,
    W,
};

pub const Type = struct {
    tag: TypeTag,
    /// Fun: domain; Pair: left; W: shape.
    dom: ?*Type = null,
    /// Fun: codomain; Pair: right.
    cod: ?*Type = null,
    /// W only: position type per shape-inhabitant (each is Unit or Bottom).
    positions: ?[]const *Type = null,

    pub fn mk(a: std.mem.Allocator, tag: TypeTag) !*Type {
        const t = try a.create(Type);
        t.* = .{ .tag = tag };
        return t;
    }

    pub fn mkFun(a: std.mem.Allocator, dom: *Type, cod: *Type) !*Type {
        const t = try a.create(Type);
        t.* = .{ .tag = .Fun, .dom = dom, .cod = cod };
        return t;
    }

    pub fn mkPair(a: std.mem.Allocator, left: *Type, right: *Type) !*Type {
        const t = try a.create(Type);
        t.* = .{ .tag = .Pair, .dom = left, .cod = right };
        return t;
    }

    pub fn mkW(a: std.mem.Allocator, shape: *Type, positions: []const *Type) !*Type {
        const t = try a.create(Type);
        t.* = .{ .tag = .W, .dom = shape, .positions = positions };
        return t;
    }

    /// Number of inhabitants of a finite type, or null if unbounded/unknown.
    /// Used by the W-type enumerator to know how many position assignments a
    /// shape admits. Deliberately only the finite base types answer.
    pub fn inhabitantCount(t: *const Type) ?usize {
        return switch (t.tag) {
            .Bottom => 0,
            .Unit => 1,
            .Bool => 2,
            else => null,
        };
    }

    /// Structural equality. Used by the type checker and refactoring logic.
    pub fn eql(x: *const Type, y: *const Type) bool {
        if (x.tag != y.tag) return false;
        if (!optEql(x.dom, y.dom)) return false;
        if (!optEql(x.cod, y.cod)) return false;
        const xp = x.positions;
        const yp = y.positions;
        if ((xp == null) != (yp == null)) return false;
        if (xp) |xs| {
            const ys = yp.?;
            if (xs.len != ys.len) return false;
            for (xs, ys) |xe, ye| {
                if (!eql(xe, ye)) return false;
            }
        }
        return true;
    }

    fn optEql(x: ?*Type, y: ?*Type) bool {
        if (x == null and y == null) return true;
        if (x == null or y == null) return false;
        return eql(x.?, y.?);
    }

    pub fn write(t: *const Type, w: anytype) !void {
        switch (t.tag) {
            .Unit => try w.writeAll("Unit"),
            .Bool => try w.writeAll("Bool"),
            .Bottom => try w.writeAll("Bottom"),
            .Sensor => try w.writeAll("Sensor"),
            .Action => try w.writeAll("Action"),
            .Univ => try w.writeAll("Univ"),
            .Fun => {
                try w.writeAll("(");
                try write(t.dom.?, w);
                try w.writeAll(" -> ");
                try write(t.cod.?, w);
                try w.writeAll(")");
            },
            .Pair => {
                try w.writeAll("(");
                try write(t.dom.?, w);
                try w.writeAll(" , ");
                try write(t.cod.?, w);
                try w.writeAll(")");
            },
            .W => {
                try w.writeAll("W[shape=");
                try write(t.dom.?, w);
                try w.writeAll(", pos=");
                if (t.positions) |ps| {
                    try w.writeAll("[");
                    for (ps, 0..) |p, i| {
                        if (i != 0) try w.writeAll(",");
                        try write(p, w);
                    }
                    try w.writeAll("]");
                }
                try w.writeAll("]");
            },
        }
    }
};

test "inhabitant counts of base types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try Type.mk(a, .Unit);
    const bool_ = try Type.mk(a, .Bool);
    const bottom = try Type.mk(a, .Bottom);
    try std.testing.expectEqual(@as(?usize, 1), unit.inhabitantCount());
    try std.testing.expectEqual(@as(?usize, 2), bool_.inhabitantCount());
    try std.testing.expectEqual(@as(?usize, 0), bottom.inhabitantCount());
}

test "structural type equality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ua = try Type.mk(a, .Unit);
    const ub = try Type.mk(a, .Unit);
    const f1 = try Type.mkFun(a, ua, ub);
    const f2 = try Type.mkFun(a, try Type.mk(a, .Unit), try Type.mk(a, .Unit));
    try std.testing.expect(Type.eql(f1, f2));
    try std.testing.expect(!Type.eql(ua, f1));
}
