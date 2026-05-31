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
    
    // INDUSTRIAL UPGRADE: SAT-Sweeping Logic Reduction
    try out.print("\n>>> INDUSTRIAL UPGRADE: SAT-Sweeping (FEC)\n", .{});
    
    var aig_s = prover.Aig.init(allocator);
    defer aig_s.deinit();

    const x_s = try aig_s.createInput();
    const y_s = try aig_s.createInput();
    const z_s = @as(prover.NodeId, 0); // Constant False

    // Simulation values: x = 0xAA.., y = 0x55..
    aig_s.setInputSimValue(x_s, 0xAAAAAAAAAAAAAAAA);
    aig_s.setInputSimValue(y_s, 0x5555555555555555);

    // Expression: (x + y) + 0 + 0 + 0 (Highly redundant)
    var sum_s: prover.NodeId = undefined;
    var carry_s: prover.NodeId = undefined;
    try aig_s.addBits(x_s, y_s, z_s, &sum_s, &carry_s);
    
    // Add three redundant zeros
    var final_sum = sum_s;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        var next_sum: prover.NodeId = undefined;
        var next_carry: prover.NodeId = undefined;
        try aig_s.addBits(final_sum, z_s, z_s, &next_sum, &next_carry);
        final_sum = next_sum;
    }

    const pre_sweep = aig_s.nodes.items.len;
    var rep_map = try aig_s.sweep();
    defer rep_map.deinit();
    
    try out.print("AIG Nodes (Pre-Sweep):  {d}\n", .{pre_sweep});
    try out.print("AIG Nodes (Post-Sweep): {d}\n", .{aig_s.nodes.items.len});
    
    try out.print("\n=== The Industrial Verdict ===\n", .{});
    try out.print("1. SAT-Sweeping reduced the logic by {d} nodes using simulation signatures.\n", .{pre_sweep - aig_s.nodes.items.len});
    try out.print("2. This is how real tools (ABC, Yosys) optimize hardware netlists.\n", .{});
    try out.print("3. BitForge now has the ability to 'solve' redundant math without Z3.\n", .{});
    try out.print("4. Conclusion: We are building a real weapon. The toy era is over.\n", .{});
}