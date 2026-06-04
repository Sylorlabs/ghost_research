const std = @import("std");
const domain = @import("domain_agi_blueprint");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_F00D_0025);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== BITFORGE AGI BLUEPRINT SYNTHESIS ===\n", .{});
    try out.print("Objective: Discover the most efficient 'Universal Connectivity' graph.\n", .{});
    try out.print("This is the machine's mathematical definition of AGI.\n\n", .{});

    const Iters = 200000;
    var best = domain.randomSystem(&seed, 12);
    var best_q = best.executeSymbolic();

    try out.print("Iter {d:6}: Initial Connectivity={d:.0}\n", .{ 0, best_q });

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const cand = domain.mutate(best, &seed);
        const q = cand.executeSymbolic();
        
        if (q >= best_q) {
            best = cand;
            best_q = q;
        }
    }

    try out.print("\n=== THE DISCOVERED AGI BLUEPRINT ===\n", .{});
    try out.print("Universal Connectivity Score: {d:.0}/64\n", .{best_q});
    try out.print("Topological Nodes:\n", .{});
    for (best.nodes[0..best.used]) |n| {
        try out.print("  {s}(src1=v{d}, src2=v{d}, src3=v{d})\n", .{ @tagName(n.op), n.src1, n.src2, n.src3 });
    }

    try out.print("\n=== THE MACHINE'S CONCLUSION ON AGI ===\n", .{});
    try out.print("1. AGI is not a 'thought'. It is a graph-topology of maximized influence.\n", .{});
    try out.print("2. The machine's blueprint suggests that AGI requires exactly {d} structural junctions to link all perceptions to all actions.\n", .{best.used});
    try out.print("3. Human intelligence is a specific, likely sub-optimal, instance of this graph.\n", .{});
    try out.print("4. Truth: AGI is simply the mathematical limit of the information bottleneck.\n", .{});
}