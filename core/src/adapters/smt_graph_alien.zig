const std = @import("std");
const domain = @import("domain_graph_alien");
const domain_base = @import("domain_alien_hack");
const smt = @import("smt_verify");

pub fn emitGraphCorrectness(
    allocator: std.mem.Allocator,
    instrs: []const domain.Node,
) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    const w = buf.writer();

    try w.writeAll("(set-logic QF_BV)\n");
    try w.writeAll("(declare-const x (_ BitVec 64))\n");
    try w.writeAll("(declare-const y (_ BitVec 64))\n");

    // SSA versions of "virtual registers" (max_nodes + 2 inputs)
    var names = try allocator.alloc([]const u8, instrs.len + 2);
    defer {
        for (names[2..]) |name| allocator.free(name);
        allocator.free(names);
    }
    
    names[0] = "x";
    names[1] = "y";

    for (instrs, 0..) |ins, i| {
        const new_name = try std.fmt.allocPrint(allocator, "v{d}", .{i + 2});
        names[i + 2] = new_name;
        try w.print("(declare-const {s} (_ BitVec 64))\n", .{new_name});
        
        const s1 = names[ins.src1];
        const s2 = names[ins.src2];

        switch (ins.op) {
            .ADD => try w.print("(assert (= {s} (bvadd {s} {s})))\n", .{ new_name, s1, s2 }),
            .SUB => try w.print("(assert (= {s} (bvsub {s} {s})))\n", .{ new_name, s1, s2 }),
            .XOR => try w.print("(assert (= {s} (bvxor {s} {s})))\n", .{ new_name, s1, s2 }),
            .AND => try w.print("(assert (= {s} (bvand {s} {s})))\n", .{ new_name, s1, s2 }),
            .OR  => try w.print("(assert (= {s} (bvor {s} {s})))\n", .{ new_name, s1, s2 }),
            .SHR => try w.print("(assert (= {s} (bvlshr {s} (_ bv{d} 64))))\n", .{ new_name, s1, ins.imm }),
        }
    }

    // Ground Truth: floor((x+y)/2)
    try w.writeAll("(declare-const sum128 (_ BitVec 128))\n");
    try w.writeAll("(assert (= sum128 (bvadd (concat (_ bv0 64) x) (concat (_ bv0 64) y))))\n");
    try w.writeAll("(declare-const target (_ BitVec 64))\n");
    try w.writeAll("(assert (= target ((_ extract 63 0) (bvudiv sum128 (_ bv2 128)))))\n");

    // Property: exists x, y such that P(x, y) != target
    try w.print("(assert (not (= {s} target)))\n", .{ names[instrs.len + 1] });
    try w.writeAll("(check-sat)\n");
    try w.writeAll("(get-model)\n");

    return buf.toOwnedSlice();
}