const std = @import("std");
const domain = @import("domain_128_tier4");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_BEEF_CAFE_0004);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== Tier 4 Concept Invention Search ===\n", .{});
    try out.print("Domain: {s}\n", .{domain.DOMAIN_NAME});
    try out.print("Goal: Achieve perfect avalanche while aggressively minimizing AST size via Concept re-use.\n\n", .{});

    const Iters = 200000;
    var best = domain.randomSystem(&seed);
    var best_q = domain.evaluateQuality(best);

    try out.print("Iter {d:6}: Start Q={d:.2} (Av={d:.1} AST={d})\n", .{
        0, best_q.composite, best_q.avalanche, best_q.ast_size
    });

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const candidate = domain.mutate(best, &seed);
        const q = domain.evaluateQuality(candidate);
        
        if (q.composite >= best_q.composite) {
            best = candidate;
            best_q = q;
        }
        if (i % 25000 == 0) {
            try out.print("Iter {d:6}: Q={d:.2} (Av={d:.1} AST={d})\n", .{
                i, best_q.composite, best_q.avalanche, best_q.ast_size
            });
        }
    }

    try out.print("\n=== Best System Found ===\n", .{});
    try out.print("Quality: {d:.2}\n", .{best_q.composite});
    try out.print("Avalanche: {d:.2}\n", .{best_q.avalanche});
    try out.print("Total AST Size: {d} (Lower is better)\n\n", .{best_q.ast_size});
    
    try domain.printSystem(best, out);
}