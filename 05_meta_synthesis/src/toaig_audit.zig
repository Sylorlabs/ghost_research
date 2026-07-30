const std = @import("std");
const prover = @import("native_prover");
const domain = @import("domain_superoptimizer");

const widths = [_]usize{ 4, 8 };
const all_ops = [_]domain.Op{ .XOR, .SHR, .AND, .ROTL, .SHL };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const out = std.io.getStdOut().writer();
    try out.print("=== G48: toAig faithfulness audit ===\n", .{});
    try out.print("Compare domain_superoptimizer.toAig lowering vs execute (exhaustive truth tables).\n\n", .{});

    var total_mismatches: usize = 0;
    var failed_ops = std.ArrayList([]const u8).init(allocator);
    defer failed_ops.deinit();

    for (widths) |width| {
        const cases = @as(u64, 1) << @intCast(width);
        try out.print("--- width {d} ({d} inputs, imm 0..63) ---\n", .{ width, cases });

        for (all_ops) |op| {
            var op_mismatches: usize = 0;
            var first_fail: ?struct { imm: u6, x: u64, exec: u64, aig: u64 } = null;

            var imm: u6 = 0;
            while (true) : (imm += 1) {
                const prog = singleOpProgram(op, imm);

                var x: u64 = 0;
                while (x < cases) : (x += 1) {
                    const exec = maskWidth(prog.execute(x), width);

                    var aig = prover.Aig.init(allocator);
                    defer aig.deinit();

                    const input_bv = try inputBvForWidth(&aig, width);
                    setInputAssignment(&aig, input_bv, x, width);

                    const out_bv = try lowerToBv(prog, &aig, input_bv);
                    const aig_val = maskWidth(evalBvWord(&aig, out_bv, width), width);

                    if (exec != aig_val) {
                        op_mismatches += 1;
                        if (first_fail == null) {
                            first_fail = .{ .imm = imm, .x = x, .exec = exec, .aig = aig_val };
                        }
                    }
                }

                if (imm == 63) break;
            }

            const status = if (op_mismatches == 0) "PASS" else "FAIL";
            try out.print("  {s:4} {s}: {d} mismatches\n", .{ @tagName(op), status, op_mismatches });

            if (op_mismatches > 0) {
                total_mismatches += op_mismatches;
                const label = try std.fmt.allocPrint(allocator, "{s}@w{d}", .{ @tagName(op), width });
                try failed_ops.append(label);
                if (first_fail) |ff| {
                    try out.print("    first: imm={d} x={d} execute=0x{x} aig=0x{x}\n", .{
                        ff.imm, ff.x, ff.exec, ff.aig,
                    });
                }
            }
        }
        try out.print("\n", .{});
    }

    const verdict = if (total_mismatches == 0) "PASS" else "FAIL";
    try out.print("=== VERDICT: {s} ===\n", .{verdict});
    try out.print("total mismatches: {d}\n", .{total_mismatches});
    try out.print("failed op/width pairs: {d}\n", .{failed_ops.items.len});

    if (total_mismatches != 0) {
        std.process.exit(1);
    }
}

fn maskWidth(val: u64, width: usize) u64 {
    if (width >= 64) return val;
    const mask = (@as(u64, 1) << @intCast(width)) - 1;
    return val & mask;
}

fn inputBvForWidth(aig: *prover.Aig, width: usize) !prover.BitVector {
    var bv = try prover.BitVector.initInput(aig);
    for (width..64) |i| bv.bits[i] = 0;
    return bv;
}

fn setInputAssignment(aig: *prover.Aig, input_bv: prover.BitVector, x: u64, width: usize) void {
    for (0..width) |i| {
        const bit = (x >> @intCast(i)) & 1;
        const sim: u64 = if (bit != 0) std.math.maxInt(u64) else 0;
        aig.setInputSimValue(input_bv.bits[i], sim);
    }
}

/// Exact mirror of `domain_superoptimizer.GraphProgram.toAig` lowering (full BitVector).
fn lowerToBv(prog: domain.GraphProgram, aig: *prover.Aig, input_bv: prover.BitVector) !prover.BitVector {
    var bvs = [_]prover.BitVector{undefined} ** (domain.MaxNodes + 1);
    bvs[0] = input_bv;

    var i: usize = 0;
    while (i < prog.used) : (i += 1) {
        const n = prog.nodes[i];
        const v1 = bvs[n.src1];
        bvs[i + 1] = switch (n.op) {
            .XOR => try v1.xorBv(aig, v1.shrBv(aig, n.imm)),
            .SHR => v1.shrBv(aig, n.imm),
            .AND => try v1.andBv(aig, prover.BitVector.initConstant(aig, @as(u64, 1) << n.imm)),
            .ROTL => v1.rotlBv(aig, n.imm),
            .SHL => v1.shlBv(aig, n.imm),
        };
    }
    return bvs[prog.used];
}

fn evalBvWord(aig: *prover.Aig, bv: prover.BitVector, width: usize) u64 {
    var result: u64 = 0;
    for (0..width) |i| {
        const bit = aig.getSimValue(bv.bits[i]) & 1;
        result |= bit << @intCast(i);
    }
    return result;
}

fn singleOpProgram(op: domain.Op, imm: u6) domain.GraphProgram {
    var prog = domain.GraphProgram{ .nodes = undefined, .used = 1 };
    prog.nodes[0] = .{ .op = op, .src1 = 0, .src2 = 0, .imm = imm };
    return prog;
}