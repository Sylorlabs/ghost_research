const std = @import("std");
const domain = @import("domain_graph_attention");
const domain_base = @import("domain_alien_hack");

const SequenceLength = 32;

fn evaluateQuality(p: domain.GraphSystem) f64 {
    var hits: f64 = 0;
    var rng: u64 = 0x1337_F00D;

    var s: usize = 0;
    while (s < 16) : (s += 1) {
        var h = [_]u64{ 0, 0, 0, 0 };
        
        // 1. Generate sequence
        rng = domain_base.smix(rng);
        const secret_idx = rng % (SequenceLength - 4);
        const secret_val = domain_base.smix(rng);
        
        var t: usize = 0;
        while (t < SequenceLength) : (t += 1) {
            rng = domain_base.smix(rng);
            const input = if (t == secret_idx) secret_val else rng;
            p.step(&h, input);
        }
        
        // 2. Trigger retrieval
        p.step(&h, 0); 
        
        var best_m: usize = 0;
        for (h) |val| {
            const m = 64 - @popCount(val ^ secret_val);
            if (m > best_m) best_m = m;
        }
        hits += @as(f64, @floatFromInt(best_m)) / 64.0;
    }
    
    const retrieval_score = (hits / 16.0) * 100.0;
    
    // Tier 4: Structural Vision
    // We want the input X to actually influence the final state.
    const influence = p.executeSymbolic()[0].x;
    const influence_score = if (influence != 0) @as(f64, 10.0) else 0.0;
    
    return retrieval_score + influence_score - @as(f64, @floatFromInt(p.used)) * 0.1;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0012);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== The Maximum Power Transformer-Killer Challenge ===\n", .{});
    try out.print("Domain: {s}\n", .{domain.DOMAIN_NAME});
    try out.print("Substrate: 256-bit Fluid Graph (DAG)\n", .{});
    try out.print("Guidance: Topological Influence Tracing\n\n", .{});

    const Iters = 300000;
    var best = domain.randomSystem(&seed, 8);
    var best_q = evaluateQuality(best);

    try out.print("Iter {d:6}: Start Q={d:.2}\n", .{ 0, best_q });

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const cand = domain.mutate(best, &seed);
        const q = evaluateQuality(cand);
        
        if (q >= best_q) {
            best = cand;
            best_q = q;
            if (i % 20000 == 0) {
                try out.print("Iter {d:6}: Q={d:.2} (Nodes: {d})\n", .{ i, best_q, best.used });
            }
        }
    }

    try out.print("\n=== Best Invention Found ===\n", .{});
    try out.print("Final Score: {d:.2} (Percentage of information retrieved)\n\n", .{best_q});
    
    // Print nodes
    var j: usize = 0;
    while (j < best.used) : (j += 1) {
        const n = best.nodes[j];
        try out.print("  n{d} = {s}(v{d}, v{d}, v{d}, imm={d})\n", .{ j, @tagName(n.op), n.src1, n.src2, n.src3, n.imm });
    }
}