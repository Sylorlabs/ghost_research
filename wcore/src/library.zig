//! The library: the engine's growing stock of types and combinators.
//!
//! At startup it holds ONLY what Section 1 of the spec permits: the base types
//! `Unit`, `Bool`, `Sensor`, `Action`, and the two combinators `identity` and
//! `composition`. No numbers, no lists, no recursion, no `Bottom`, no `W`. The
//! sleep phase grows this list when (and only when) doing so lowers the total
//! node count.

const std = @import("std");
const types = @import("types.zig");
const terms = @import("terms.zig");
const nodecount = @import("nodecount.zig");
const Type = types.Type;
const Term = terms.Term;

pub const Def = struct {
    name: []const u8,
    ty: *Type,
    body: ?*Term,
    /// true when this definition introduces a type (base or invented W-type),
    /// false when it is a combinator/term.
    is_type: bool,
};

pub const Library = struct {
    a: std.mem.Allocator,
    defs: std.ArrayList(Def),

    // Cached base-type pointers for convenient reuse.
    unit: *Type,
    bool_: *Type,
    sensor: *Type,
    action: *Type,

    // Indices of the starting combinators, so the wake phase can reference them.
    id_idx: usize,
    compose_idx: usize,

    // `Bottom` only materialises when the first W-type proposal needs it.
    bottom: ?*Type = null,

    pub fn init(a: std.mem.Allocator) !Library {
        var lib = Library{
            .a = a,
            .defs = std.ArrayList(Def).init(a),
            .unit = try Type.mk(a, .Unit),
            .bool_ = try Type.mk(a, .Bool),
            .sensor = try Type.mk(a, .Sensor),
            .action = try Type.mk(a, .Action),
            .id_idx = 0,
            .compose_idx = 0,
        };

        try lib.defs.append(.{ .name = "Unit", .ty = lib.unit, .body = null, .is_type = true });
        try lib.defs.append(.{ .name = "Bool", .ty = lib.bool_, .body = null, .is_type = true });
        try lib.defs.append(.{ .name = "Sensor", .ty = lib.sensor, .body = null, .is_type = true });
        try lib.defs.append(.{ .name = "Action", .ty = lib.action, .body = null, .is_type = true });

        // identity : Unit -> Unit  ==  \x. x
        const id_ty = try Type.mkFun(a, lib.unit, lib.unit);
        const id_body = try Term.vr(a, 0, lib.unit);
        const id_term = try Term.lam(a, id_body, id_ty);
        lib.id_idx = lib.defs.items.len;
        try lib.defs.append(.{ .name = "identity", .ty = id_ty, .body = id_term, .is_type = false });

        // composition : (U->U) -> (U->U) -> (U->U)  ==  \f. \g. \x. f (g x)
        const uu = try Type.mkFun(a, lib.unit, lib.unit);
        const compose_ty = try Type.mkFun(a, uu, try Type.mkFun(a, uu, uu));
        const x_var = try Term.vr(a, 0, lib.unit);
        const g_var = try Term.vr(a, 1, uu);
        const f_var = try Term.vr(a, 2, uu);
        const gx = try Term.app(a, g_var, x_var, lib.unit);
        const fgx = try Term.app(a, f_var, gx, lib.unit);
        const inner = try Term.lam(a, fgx, uu); // \x. f (g x)
        const mid = try Term.lam(a, inner, try Type.mkFun(a, uu, uu)); // \g. ...
        const compose_term = try Term.lam(a, mid, compose_ty); // \f. ...
        lib.compose_idx = lib.defs.items.len;
        try lib.defs.append(.{ .name = "composition", .ty = compose_ty, .body = compose_term, .is_type = false });

        return lib;
    }

    pub fn deinit(self: *Library) void {
        self.defs.deinit();
    }

    pub fn add(self: *Library, name: []const u8, ty: *Type, body: ?*Term, is_type: bool) !usize {
        const idx = self.defs.items.len;
        try self.defs.append(.{ .name = name, .ty = ty, .body = body, .is_type = is_type });
        return idx;
    }

    /// Materialise `Bottom` on demand and add it to the library. Returns the
    /// existing one on subsequent calls so it is added at most once.
    pub fn ensureBottom(self: *Library) !*Type {
        if (self.bottom) |b| return b;
        const b = try Type.mk(self.a, .Bottom);
        self.bottom = b;
        _ = try self.add("Bottom", b, null, true);
        return b;
    }

    pub fn totalNodeCount(self: *const Library) usize {
        var n: usize = 0;
        for (self.defs.items) |d| {
            n += nodecount.nodeCountType(d.ty);
            if (d.body) |b| n += nodecount.nodeCountTerm(b);
        }
        return n;
    }

    pub fn typeCount(self: *const Library) usize {
        var n: usize = 0;
        for (self.defs.items) |d| {
            if (d.is_type) n += 1;
        }
        return n;
    }

    pub fn combinatorCount(self: *const Library) usize {
        var n: usize = 0;
        for (self.defs.items) |d| {
            if (!d.is_type) n += 1;
        }
        return n;
    }
};

test "fresh library holds exactly the permitted primitives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var lib = try Library.init(arena.allocator());
    defer lib.deinit();
    try std.testing.expectEqual(@as(usize, 4), lib.typeCount());
    try std.testing.expectEqual(@as(usize, 2), lib.combinatorCount());
    // No Bottom, no W until invention.
    try std.testing.expect(lib.bottom == null);
    for (lib.defs.items) |d| {
        try std.testing.expect(d.ty.tag != .W);
        try std.testing.expect(d.ty.tag != .Bottom);
    }
}
