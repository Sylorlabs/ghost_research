const std = @import("std");
const prover = @import("native_prover");
const domain_super = @import("domain_superoptimizer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_F00D_0020);
    const out = std.io.getStdOut().writer();
    try out.print("=== The High-Speed Distillation Engine ===\n", .{});
    try out.print("Goal: Force the engine to discover a self-cancelling algebraic identity.\n\n", .{});

    // 1. Setup global AIG context
    var aig = prover.Aig.init(allocator);
    defer aig.deinit();

    const x = try prover.BitVector.initInput(&aig);
    const y = try prover.BitVector.initInput(&aig);
    
    // Set deterministic simulation vectors
    for (x.bits, 0..) |bit, idx| aig.setInputSimValue(bit, prng.random().int(u64) ^ @as(u64, idx));
    for (y.bits, 0..) |bit, idx| aig.setInputSimValue(bit, prng.random().int(u64) ^ @as(u64, idx + 100));

    // 2. The 'Mess': (x ^ y) ^ y == x
    const x_xor_y = try x.xorBv(&aig, y);
    const mess_bv = try x_xor_y.xorBv(&aig, y);
    
    try out.print("Pre-Sweep Complexity: {d} nodes.\n", .{aig.nodes.items.len});
    var rep_map = try aig.sweep();
    defer rep_map.deinit();
    try out.print("Post-Sweep Complexity: {d} nodes.\n", .{aig.nodes.items.len});

    const mess_lit = mess_bv.bits[0];
    const x0_lit = x.bits[0];

    const mess_rep = rep_map.get(mess_lit & ~@as(u32, 1)).? ^ (mess_lit & 1);
    const x0_rep = rep_map.get(x0_lit & ~@as(u32, 1)).? ^ (x0_lit & 1);

    try out.print("Mess Representative ID: {d}\n", .{mess_rep});
    try out.print("X[0] Representative ID: {d}\n", .{x0_rep});
    
    if (mess_rep == x0_rep) {
        try out.print("\n>>> AHA! MOMENT ACHIEVED <<< \n", .{});
        try out.print("The engine correctly reduced (x ^ y) ^ y to x.\n", .{});
        try out.print("Complexity has collapsed. The algebraic identity is proven.\n", .{});
    } else {
        try out.print("\n[FAILED] The identities did not collapse.\n", .{});
    }
}