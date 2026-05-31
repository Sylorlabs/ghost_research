const std = @import("std");
const domain_base = @import("domain_alien_hack");
const smt = @import("smt_verify");

// Target: x & (x - 1)
// 100% Ripe: Using Z3 for formal proof and counter-examples.
// Upgraded: Hamming Distance Gradient for the Inventor.

const Op = domain_base.Op;

const HackNode = struct {
    op: Op,
    dst: u2,
    src1: u2, 
    src2: u2,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0022);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== The True Alien Architect: x & (x - 1) ===\n", .{});

    var test_cases = std.ArrayList(struct { x: u64, target: u64 }).init(allocator);
    defer test_cases.deinit();
    try test_cases.append(.{ .x = 10, .target = 10 & 9 });
    try test_cases.append(.{ .x = 16, .target = 0 });

    var gen: usize = 1;
    while (gen < 40) : (gen += 1) {
        try out.print(">>> Generation {d} (Tests: {d})\n", .{ gen, test_cases.items.len });

        var best_nodes: [4]HackNode = undefined;
        var best_len: u8 = 0;
        var best_q: f64 = -1000.0;
        
        var iters: usize = 0;
        while (iters < 5000000) : (iters += 1) {
            const len: u8 = @intCast(2 + (nextRand(&seed) % 3));
            var nodes: [4]HackNode = undefined;
            for (0..len) |k| {
                nodes[k] = .{
                    .op = @enumFromInt(nextRand(&seed) % 6),
                    .dst = @intCast(nextRand(&seed) % 4),
                    .src1 = @intCast(nextRand(&seed) % 4),
                    .src2 = @intCast(nextRand(&seed) % 4),
                };
            }

            var current_q: f64 = 0;
            for (test_cases.items) |tc| {
                var regs = [_]u64{ tc.x, 1, 0, 0 };
                for (nodes[0..len]) |n| {
                    const v1 = regs[n.src1];
                    const v2 = regs[n.src2];
                    regs[n.dst] = switch (n.op) {
                        .ADD => v1 +% v2,
                        .SUB => v1 -% v2,
                        .XOR => v1 ^ v2,
                        .AND => v1 & v2,
                        .OR  => v1 | v2,
                        .SHR => v1 >> 1,
                    };
                }
                
                if (regs[0] == tc.target) {
                    current_q += 1.0;
                } else {
                    // Hamming distance gradient
                    const matching_bits = 64 - @popCount(regs[0] ^ tc.target);
                    current_q += @as(f64, @floatFromInt(matching_bits)) / 64.0;
                }
            }

            if (current_q > best_q) {
                best_q = current_q;
                best_nodes = nodes;
                best_len = len;
            }
            
            // Break if we perfectly pass all tests
            if (current_q >= @as(f64, @floatFromInt(test_cases.items.len))) break;
        }

        if (best_q < @as(f64, @floatFromInt(test_cases.items.len))) {
            try out.print("    [FAILED] Hill-climber stall (Q={d:.2}).\n", .{best_q});
            return;
        }

        try out.print("    [CANDIDATE] Verifying with Z3...\n", .{});
        const smt_text = try emitSmt(allocator, best_nodes[0..best_len]);
        defer allocator.free(smt_text);
        
        const res = try smt.runSmtLib(allocator, smt_text, 5000);
        
        if (res.verdict == .verified or (res.verdict == .error_smt and std.mem.startsWith(u8, res.detail, "unsat"))) {
            if (res.verdict == .error_smt) allocator.free(res.detail);
            try out.print("\n!!! INVENTION SUCCESS !!!\n", .{});
            try out.print("Independent rediscovery of x & (x - 1) hack.\n", .{});
            for (0..best_len) |i| {
                try out.print("  [{d}] r{d} = {s}(r{d}, r{d})\n", .{ i, best_nodes[i].dst, @tagName(best_nodes[i].op), best_nodes[i].src1, best_nodes[i].src2 });
            }
            return;
        } else if (res.verdict == .counter_example) {
            defer allocator.free(res.detail);
            const x_val = try parseHex(res.detail, "define-fun x ");
            try test_cases.append(.{ .x = x_val, .target = x_val & (x_val -% 1) });
            try out.print("    [REJECTED] New counter-example: x=0x{X:0>16}\n\n", .{ x_val });
        } else {
            try out.print("    [ERROR] Z3: {s}\n", .{ res.detail });
            allocator.free(res.detail);
            return;
        }
    }
}

fn emitSmt(allocator: std.mem.Allocator, insts: []const HackNode) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();
    try w.writeAll("(set-logic QF_BV)\n(declare-const x (_ BitVec 64))\n");
    try w.writeAll("(declare-const one (_ BitVec 64))\n(assert (= one (_ bv1 64)))\n");
    
    var ver = [_]u32{0} ** 4;
    try w.writeAll("(declare-const r0_v0 (_ BitVec 64))\n(assert (= r0_v0 x))\n");
    try w.writeAll("(declare-const r1_v0 (_ BitVec 64))\n(assert (= r1_v0 one))\n");
    try w.writeAll("(declare-const r2_v0 (_ BitVec 64))\n(assert (= r2_v0 (_ bv0 64)))\n");
    try w.writeAll("(declare-const r3_v0 (_ BitVec 64))\n(assert (= r3_v0 (_ bv0 64)))\n");
    
    for (insts, 0..) |n, i| {
        _ = i;
        const d_new = ver[n.dst] + 1;
        ver[n.dst] = d_new;
        try w.print("(declare-const r{d}_v{d} (_ BitVec 64))\n", .{ n.dst, d_new });
        
        const v1_name = try std.fmt.allocPrint(allocator, "r{d}_v{d}", .{ n.src1, ver[n.src1] });
        defer allocator.free(v1_name);
        const v2_name = try std.fmt.allocPrint(allocator, "r{d}_v{d}", .{ n.src2, ver[n.src2] });
        defer allocator.free(v2_name);
        const dst_name = try std.fmt.allocPrint(allocator, "r{d}_v{d}", .{ n.dst, d_new });
        defer allocator.free(dst_name);
        
        switch (n.op) {
            .ADD => try w.print("(assert (= {s} (bvadd {s} {s})))\n", .{ dst_name, v1_name, v2_name }),
            .SUB => try w.print("(assert (= {s} (bvsub {s} {s})))\n", .{ dst_name, v1_name, v2_name }),
            .XOR => try w.print("(assert (= {s} (bvxor {s} {s})))\n", .{ dst_name, v1_name, v2_name }),
            .AND => try w.print("(assert (= {s} (bvand {s} {s})))\n", .{ dst_name, v1_name, v2_name }),
            .OR  => try w.print("(assert (= {s} (bvor {s} {s})))\n", .{ dst_name, v1_name, v2_name }),
            .SHR => try w.print("(assert (= {s} (bvlshr {s} (_ bv1 64))))\n", .{ dst_name, v1_name }),
        }
    }
    
    try w.print("(assert (not (= r0_v{d} (bvand x (bvsub x one)))))\n", .{ver[0]});
    try w.writeAll("(check-sat)\n(get-model)\n");
    return buf.toOwnedSlice();
}

fn parseHex(model: []const u8, pattern: []const u8) !u64 {
    const idx = std.mem.indexOf(u8, model, pattern) orelse return error.NotFound;
    const hex_idx = std.mem.indexOf(u8, model[idx..], "#x") orelse return error.NoHex;
    const start = idx + hex_idx + 2;
    const end = std.mem.indexOfScalarPos(u8, model, start, ')') orelse return error.Malformed;
    return try std.fmt.parseInt(u64, model[start..end], 16);
}

fn nextRand(rng: *u64) u64 {
    var z = rng.* +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    rng.* = z ^ (z >> 31);
    return rng.*;
}