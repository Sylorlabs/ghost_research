const std = @import("std");
const domain = @import("domain_agi_subsystem_synthesis");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_F00D_0027);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== SYHTHESIZING AGI MOTOR PLAN ===\n", .{});

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

    try out.print("\n=== THE MACHINE'S MOTOR BLUEPRINT ===\n", .{});
    for (best.nodes[0..best.used]) |n| {
        try out.print("  STEP: {s} (Target: node_{d}, depth={d})\n", .{ 
            @tagName(n.op), n.src, n.imm 
        });
    }
}