const std = @import("std");
const domain = @import("domain_alien_hack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0007);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== The Alien Extrapolation Test ===\n", .{});
    try out.print("Domain: {s}\n", .{domain.DOMAIN_NAME});
    try out.print("Task: Compute floor((x + y) / 2) on 64-bit integers.\n", .{});
    try out.print("Constraint: NO branching, NO 128-bit casts, must not overflow when x=MAX, y=MAX.\n", .{});
    try out.print("Human intuition fails here. Let's see what the engine invents.\n\n", .{});

    const Iters = 5000000;
    var best = domain.randomProgram(&seed);
    var best_q = domain.evaluateQuality(best);

    try out.print("Iter {d:6}: Start Q={d:.2}\n", .{ 0, best_q });

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const cand = domain.mutate(best, &seed);
        const q = domain.evaluateQuality(cand);
        
        // Simulated Annealing / MDL Tie-breaker
        if (q > best_q or (q == best_q and cand.used < best.used)) {
            best = cand;
            best_q = q;
            if (i % 10000 == 0 or best_q >= 100.0) {
                try out.print("Iter {d:6}: Q={d:.2} (Length: {d})\n", .{ i, best_q, best.used });
            }
        }
        // Break early if we found a perfect, hyper-compressed solution
        if (best_q > 190.0 and best.used <= 5) break; 
    }

    try out.print("\n=== Best Alien Hack Found ===\n", .{});
    try out.print("Final Score: {d:.2} (100+ means perfect correctness, extra is compression reward)\n\n", .{best_q});
    
    try domain.printProgram(best, out);
}