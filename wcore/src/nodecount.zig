//! Node counting — the sole objective function of the engine.
//!
//! Everything the sleep phase decides is decided by these two functions. A
//! type or term is "better" purely when the total node count of the library
//! plus the programs goes down. There is no other reward signal.

const std = @import("std");
const types = @import("types.zig");
const terms = @import("terms.zig");
const Type = types.Type;
const Term = terms.Term;

pub fn nodeCountType(t: *const Type) usize {
    var n: usize = 1;
    if (t.dom) |d| n += nodeCountType(d);
    if (t.cod) |c| n += nodeCountType(c);
    if (t.positions) |ps| {
        for (ps) |p| n += nodeCountType(p);
    }
    return n;
}

pub fn nodeCountTerm(t: *const Term) usize {
    var n: usize = 1;
    for (t.kids) |k| {
        if (k) |kv| n += nodeCountTerm(kv);
    }
    return n;
}

test "node count of a small type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // W[shape=Bool, pos=[Bottom, Unit]] == 1 (W) + 1 (Bool) + 1 (Bottom) + 1 (Unit) = 4
    const bool_ = try Type.mk(a, .Bool);
    const bottom = try Type.mk(a, .Bottom);
    const unit = try Type.mk(a, .Unit);
    const positions = try a.alloc(*Type, 2);
    positions[0] = bottom;
    positions[1] = unit;
    const nat = try Type.mkW(a, bool_, positions);
    try std.testing.expectEqual(@as(usize, 4), nodeCountType(nat));
}

test "node count of an application chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const u = try Type.mk(a, .Unit);
    const base = try Term.libRef(a, 0, u); // 1
    const head = try Term.libRef(a, 1, u); // 1
    const ap = try Term.app(a, head, base, u); // App(1) + head(1) + base(1) = 3
    try std.testing.expectEqual(@as(usize, 3), nodeCountTerm(ap));
}
