const std = @import("std");
const prover = @import("native_prover");
const domain = @import("domain_superoptimizer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0016);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== BitForge Native Superoptimizer: 8-bit Parity ===\n", .{});
    try out.print("Task: Find equivalent logic for XOR ladder.\n\n", .{});

    const Iters = 2000;
    var i: usize = 1;
    var best_prog = domain.randomProgram(&seed, 2);
    var best_hits: usize = 0;

    while (i <= Iters) : (i += 1) {
        var aig = prover.Aig.init(allocator);
        defer aig.deinit();

        // 8-bit inputs
        var inputs: [8]prover.NodeId = undefined;
        for (0..8) |idx| {
            inputs[idx] = try aig.createInput();
            aig.setInputSimValue(inputs[idx], prng.random().int(u64));
        }

        // 1. Build Reference (XOR all 8 bits)
        var ref_node = inputs[0];
        for (1..8) |idx| {
            ref_node = try aig.xorNodes(ref_node, inputs[idx]);
        }

        // 2. Build Candidate from GraphProgram
        // We manually simulate the GraphProgram bits for 8-bit parity PoC
        const cand_prog = if (i == 1) best_prog else domain.mutate(best_prog, &seed);
        
        // Lower 8-bit logic into the AIG
        var current_bits: [8]prover.NodeId = undefined;
        for (0..8) |idx| current_bits[idx] = inputs[idx];
        
        var j: usize = 0;
        while (j < cand_prog.used) : (j += 1) {
            const n = cand_prog.nodes[j];
            // Simplistic 8-bit shift/xor emulation for the PoC
            const imm = @as(u3, @intCast(n.imm % 8));
            if (n.op == .XOR) {
                for (0..8) |idx| {
                    if (idx + imm < 8) {
                        current_bits[idx] = try aig.xorNodes(current_bits[idx], current_bits[idx + imm]);
                    }
                }
            }
        }
        const cand_node = current_bits[0];

        // 3. Miter
        const miter = try aig.createMiter(ref_node, cand_node);
        const hits = 64 - @popCount(aig.getSimValue(miter));
        
        if (hits >= best_hits) {
            best_prog = cand_prog;
            best_hits = hits;
            
            if (hits == 64) {
                var solver = try aig.toSat(allocator);
                defer solver.deinit();
                try solver.addClause(&[_]prover.Lit{@intCast((miter >> 1) + 1)});
                if (!solver.solve()) {
                    try out.print("\n!!! SUCCESS !!!\n", .{});
                    try out.print("Found equivalent 8-bit parity logic in {d} iters.\n", .{i});
                    return;
                }
            }
        }
        
        if (i % 500 == 0) {
            try out.print("Iter {d:4}: Best Hits={d}/64\n", .{ i, best_hits });
        }
    }
}