const std = @import("std");
const domain = @import("domain_agi_self_observation");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_F00D_0028);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== SYNTHESIZING SELF-OBSERVATION PLAN ===\n", .{});

    const Iters = 100000;
    var best = domain.randomPlan(&seed);
    var best_q = best.evaluate();

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const cand = domain.mutate(best, &seed);
        const q = cand.evaluate();
        if (q >= best_q) {
            best = cand;
            best_q = q;
        }
    }

    try out.print("\n=== THE MACHINE'S SELF-OBSERVATION BLUEPRINT ===\n", .{});
    for (best.nodes[0..best.used]) |n| {
        try out.print("  STRATEGY: {s} (Target Segment: {d}, Priority: {d}/255)\n", .{ 
            @tagName(n.op), n.target, n.priority 
        });
    }
}