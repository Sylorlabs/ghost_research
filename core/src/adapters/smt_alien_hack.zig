const std = @import("std");
const domain = @import("domain_alien_hack");

pub const Op = domain.Op;
pub const Instruction = domain.Instruction;

pub fn emitAlienHackCorrectness(
    allocator: std.mem.Allocator,
    instrs: []const Instruction,
) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    const w = buf.writer();

    try w.writeAll("(set-logic QF_BV)\n");
    try w.writeAll("(declare-const x (_ BitVec 64))\n");
    try w.writeAll("(declare-const y (_ BitVec 64))\n");

    // SSA versions of registers
    var ver = [_]u32{0} ** 8;

    // Side 'a' is the program under test
    var k: u32 = 0;
    while (k < 8) : (k += 1) {
        try w.print("(declare-const r{d}_v0 (_ BitVec 64))\n", .{k});
    }
    try w.writeAll("(assert (= r0_v0 x))\n");
    try w.writeAll("(assert (= r1_v0 y))\n");
    k = 2;
    while (k < 8) : (k += 1) {
        try w.print("(assert (= r{d}_v0 (_ bv0 64)))\n", .{k});
    }

    for (instrs, 0..) |ins, i| {
        const a_ver = ver[ins.dst];
        const b_ver = ver[ins.src];
        const d_new = ver[ins.dst] + 1;
        ver[ins.dst] = d_new;

        try w.print("(declare-const r{d}_v{d} (_ BitVec 64))\n", .{ ins.dst, d_new });
        const lhs_name = try std.fmt.allocPrint(allocator, "r{d}_v{d}", .{ ins.dst, a_ver });
        defer allocator.free(lhs_name);
        const rhs_name = try std.fmt.allocPrint(allocator, "r{d}_v{d}", .{ ins.src, b_ver });
        defer allocator.free(rhs_name);
        const new_name = try std.fmt.allocPrint(allocator, "r{d}_v{d}", .{ ins.dst, d_new });
        defer allocator.free(new_name);

        switch (ins.op) {
            .ADD => try w.print("(assert (= {s} (bvadd {s} {s})))\n", .{ new_name, lhs_name, rhs_name }),
            .SUB => try w.print("(assert (= {s} (bvsub {s} {s})))\n", .{ new_name, lhs_name, rhs_name }),
            .XOR => try w.print("(assert (= {s} (bvxor {s} {s})))\n", .{ new_name, lhs_name, rhs_name }),
            .AND => try w.print("(assert (= {s} (bvand {s} {s})))\n", .{ new_name, lhs_name, rhs_name }),
            .OR  => try w.print("(assert (= {s} (bvor {s} {s})))\n", .{ new_name, lhs_name, rhs_name }),
            .SHR => try w.print("(assert (= {s} (bvlshr {s} (_ bv{d} 64))))\n", .{ new_name, rhs_name, ins.imm }),
        }
        _ = i;
    }

    // Ground Truth: floor((x+y)/2) using 128-bit math to prevent overflow in the truth spec
    try w.writeAll("(declare-const sum128 (_ BitVec 128))\n");
    try w.writeAll("(assert (= sum128 (bvadd (concat (_ bv0 64) x) (concat (_ bv0 64) y))))\n");
    try w.writeAll("(declare-const target (_ BitVec 64))\n");
    try w.writeAll("(assert (= target ((_ extract 63 0) (bvudiv sum128 (_ bv2 128)))))\n");

    // Property: exists x, y such that P(x, y) != target
    try w.print("(assert (not (= r0_v{d} target)))\n", .{ ver[0] });
    try w.writeAll("(check-sat)\n");
    try w.writeAll("(get-model)\n");

    return buf.toOwnedSlice();
}