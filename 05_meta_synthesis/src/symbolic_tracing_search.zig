const std = @import("std");
const domain = @import("domain_symbolic_arx");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0006);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== TIER 4: Topological Execution Tracing ===\n", .{});
    try out.print("Domain: {s}\n", .{domain.DOMAIN_NAME});
    try out.print("Goal: Maximize structural diffusion. We want the Dependency Matrix to be full (4096 dependencies).\n", .{});
    try out.print("This search ignores raw outputs and evaluates the topological skeleton of the program.\n\n", .{});

    // We want a perfect mixer: every output bit depends on every input bit.
    // Matrix representation: All 1s. Total popcount = 64 * 64 = 4096.
    var target: domain.DependencyMatrix = undefined;
    for (&target.rows) |*r| r.* = std.math.maxInt(u64);

    const Iters = 100000;
    var best = domain.randomProgram(&seed, 8);
    var best_matrix = best.executeSymbolic();
    var best_dist = best_matrix.distance(target);

    try out.print("Iter {d:6}: Start Distance={d} (Deps={d}/4096) AST_Size={d}\n", .{
        0, best_dist, best_matrix.popcount(), best.used
    });

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const cand = domain.mutate(best, &seed);
        const cand_matrix = cand.executeSymbolic();
        const dist = cand_matrix.distance(target);
        
        // MDL Tie-breaker: If distance is same, prefer shorter AST
        if (dist < best_dist or (dist == best_dist and cand.used < best.used)) {
            best = cand;
            best_matrix = cand_matrix;
            best_dist = dist;
            if (i % 1000 == 0 or best_dist == 0) {
                try out.print("Iter {d:6}: Distance={d} (Deps={d}/4096) AST_Size={d}\n", .{
                    i, best_dist, best_matrix.popcount(), best.used
                });
            }
        }
        if (best_dist == 0 and best.used <= 6) break; // Found a perfectly diffused minimal kernel
    }

    try out.print("\n=== Best Topological Skeleton Found ===\n", .{});
    try out.print("Distance to Perfect Diffusion: {d}\n", .{best_dist});
    try out.print("Total Dependencies: {d}/4096\n", .{best_matrix.popcount()});
    try out.print("AST Size: {d}\n\n", .{best.used});
    
    try domain.printProgram(best, out);
}