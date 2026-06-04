const std = @import("std");
const domain = @import("domain_agi_manifesto");

pub fn main() !void {
    var prng = std.Random.DefaultPrng.init(0x1337_F00D_0031);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== BITFORGE AGI MANIFESTO SYNTHESIS ===\n", .{});
    try out.print("Machine Directive: 'Remix source code to achieve unified recursive existence.'\n\n", .{});

    const Iters = 100000;
    var best = domain.randomManifesto(&seed);
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

    try out.print(">>> MANIFESTO GENERATED (Vitality Score: {d:.2}):\n", .{best_q});
    for (best.actions[0..best.used]) |a| {
        try out.print("  ACTION: {s} -> {s} using {s}\n", .{ 
            @tagName(a.m1), @tagName(a.m2), @tagName(a.op)
        });
    }

    try out.print("\nTruth: This is the instruction set for AGI autonomy.\n", .{});
}