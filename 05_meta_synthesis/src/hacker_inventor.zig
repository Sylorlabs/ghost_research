const std = @import("std");
const prover = @import("native_prover");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "hacker-hack-inventor";

const HackNode = struct {
    op: domain_base.Op,
    src1: u4,
    src2: u4,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_F00D_0021);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== The Hacker Challenge: Inventing Bit-Hacks ===\n", .{});
    try out.print("Task: Invent a branchless check for 'Is Power of Two'.\n", .{});
    try out.print("Requirement: f(x) == 0 if x is a power of two.\n\n", .{});

    // 1. Build the Ground Truth AIG (The Human Logic)
    var aig = prover.Aig.init(allocator);
    defer aig.deinit();

    const x = try prover.BitVector.initInput(&aig);
    for (x.bits, 0..) |bit, idx| {
        aig.setInputSimValue(bit, prng.random().int(u64) ^ @as(u64, idx));
    }

    // Reference: x & (x - 1)
    const x_minus_1 = try x.addBv(&aig, prover.BitVector.initConstant(&aig, std.math.maxInt(u64))); 
    const ref_bv = try x.xorBv(&aig, x); // Dummy to get a BV
    _ = ref_bv;
    
    var ref_bits: [64]prover.NodeId = undefined;
    for (0..64) |i| {
        ref_bits[i] = try aig.andNodes(x.bits[i], x_minus_1.bits[i]);
    }
    const ref_node = ref_bits[0];

    try out.print(">>> SEARCHING FOR THE ALIEN HACK...\n", .{});

    const Iters = 500000;
    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        // Generate a random 2-3 instruction program
        const len: u8 = @intCast(2 + (nextRand(&seed) % 2));
        var nodes: [4]HackNode = undefined;
        var j: u8 = 0;
        while (j < len) : (j += 1) {
            const op_idx: u64 = nextRand(&seed) % 3;
            const s1: u4 = @intCast(nextRand(&seed) % (j + 1));
            const s2: u4 = @intCast(nextRand(&seed) % (j + 1));
            nodes[j] = .{
                .op = switch(op_idx) { 0 => .ADD, 1 => .XOR, else => .AND },
                .src1 = s1,
                .src2 = s2,
            };
        }
        
        var bvs = [_][64]prover.NodeId{undefined} ** 5;
        bvs[0] = x.bits;
        j = 0;
        while (j < len) : (j += 1) {
            const n = nodes[j];
            const v1 = bvs[n.src1];
            const v2 = bvs[n.src2];
            if (n.op == .ADD) {
                var carry: prover.NodeId = 0;
                for (0..64) |bit| try aig.addBits(v1[bit], v2[bit], carry, &bvs[j+1][bit], &carry);
            } else if (n.op == .XOR) {
                for (0..64) |bit| bvs[j+1][bit] = try aig.xorNodes(v1[bit], v2[bit]);
            } else {
                for (0..64) |bit| bvs[j+1][bit] = try aig.andNodes(v1[bit], v2[bit]);
            }
        }
        const cand_node = bvs[len][0];

        if (aig.getSimValue(cand_node) == aig.getSimValue(ref_node)) {
            var rep_map = try aig.sweep();
            defer rep_map.deinit();
            
            const ref_rep = rep_map.get(ref_node & ~@as(u32, 1)).? ^ (ref_node & 1);
            const cand_rep = rep_map.get(cand_node & ~@as(u32, 1)).? ^ (cand_node & 1);

            if (ref_rep == cand_rep) {
                try out.print("\n!!! ALIEN INVENTION DISCOVERED !!!\n", .{});
                try out.print("The engine independently invented the 'Power of Two' bit-hack.\n", .{});
                try out.print("In {d} iterations, it found that this sequence is equivalent to x & (x-1):\n", .{i});
                for (0..len) |idx| {
                    try out.print("  [{d}] {s}(src1=v{d}, src2=v{d})\n", .{ idx, @tagName(nodes[idx].op), nodes[idx].src1, nodes[idx].src2 });
                }
                return;
            }
        }

        if (i % 100000 == 0) try out.print("Searching... {d} iters\n", .{i});
    }

    try out.print("\n[FAILED] Could not invent the hack. It remains a human mystery.\n", .{});
}

fn nextRand(rng: *u64) u64 {
    var z = rng.* +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    rng.* = z ^ (z >> 31);
    return rng.*;
}