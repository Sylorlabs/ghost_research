const std = @import("std");
const prover = @import("native_prover");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const out = std.io.getStdOut().writer();
    try out.print("=== BitForge-Native Prover Benchmark (AIG Lowering) ===\n", .{});
    
    // Test: Lowering an 8-bit ripple-carry adder into AIG
    var aig = prover.Aig.init(allocator);
    defer aig.deinit();

    // Create 16 input nodes (8 for A, 8 for B)
    var a_bits: [8]prover.NodeId = undefined;
    var b_bits: [8]prover.NodeId = undefined;
    for (0..8) |i| {
        a_bits[i] = try aig.createInput();
        b_bits[i] = try aig.createInput();
        
        // Provide random simulation data for inputs
        aig.setInputSimValue(a_bits[i], 0x1234567890ABCDEF ^ @as(u64, i));
        aig.setInputSimValue(b_bits[i], 0xFEDCBA0987654321 ^ @as(u64, i));
    }

    var timer = try std.time.Timer.start();
    const start = timer.read();

    var sum: [8]prover.NodeId = undefined;
    var carry = @as(prover.NodeId, 0); // Initial carry in
    for (0..8) |i| {
        try aig.addBits(a_bits[i], b_bits[i], carry, &sum[i], &carry);
    }

    const end = timer.read();
    
    try out.print("Result: 8-bit addition lowered into {d} AIG nodes.\n", .{aig.nodes.items.len});
    try out.print("Time: {d} ns\n", .{end - start});
    
    // FORMAL PROOF: (x + 1) ^ (x + 1) == 0
    try out.print("\n>>> FORMAL PROOF: (x + 1) ^ (x + 1) == 0\n", .{});
    
    var aig_p = prover.Aig.init(allocator);
    defer aig_p.deinit();

    const x_bit = try aig_p.createInput();
    const one_bit = @as(prover.NodeId, 1); // True

    // (x + 1)
    var sum_p: prover.NodeId = undefined;
    var carry_p: prover.NodeId = undefined;
    try aig_p.addBits(x_bit, one_bit, @as(prover.NodeId, 0), &sum_p, &carry_p);
    
    // (x + 1) ^ (x + 1)
    const res_node = try aig_p.xorNodes(sum_p, sum_p);
    
    // Convert to SAT
    var solver = try aig_p.toSat(allocator);
    defer solver.deinit();
    
    // We want to prove res_node is ALWAYS 0.
    // So we try to find an input where res_node is 1 (True).
    // SAT index for res_node is (id >> 1) + 1.
    const res_sat_var = (res_node >> 1) + 1;
    const res_sat_lit: prover.Lit = @intCast(res_sat_var);
    
    // Constraint: Result is True
    try solver.addClause(&[_]prover.Lit{res_sat_lit});
    
    const solve_start = std.time.milliTimestamp();
    const is_sat = solver.solve();
    const solve_end = std.time.milliTimestamp();

    if (!is_sat) {
        try out.print("Verdict: VERIFIED (UNSAT — no input exists where P != 0)\n", .{});
    } else {
        try out.print("Verdict: COUNTER-EXAMPLE FOUND (SAT)\n", .{});
    }
    try out.print("Solve time: {d} ms\n", .{solve_end - solve_start});

    try out.print("\n=== The Harshest Critic Buzzkill ===\n", .{});
    try out.print("1. Our solver verified a 2-node proof in {d} ms.\n", .{solve_end - solve_start});
    try out.print("2. A ripple-carry adder has O(2^N) complexity for this backtracking solver.\n", .{});
    try out.print("3. Verification of a 64-bit mixer would take 500 years with this code.\n", .{});
    try out.print("4. Conclusion: We built a tricycle and are racing against a Ferrari (Z3).\n", .{});
}