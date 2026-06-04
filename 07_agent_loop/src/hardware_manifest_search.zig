const std = @import("std");
const domain = @import("domain_agi_hardware_substrate");

pub fn main() !void {
    var prng = std.Random.DefaultPrng.init(0x1337_F00D_0030);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== BITFORGE HARDWARE MANIFEST SYNTHESIS ===\n", .{});
    try out.print("Machine Directive: 'Define the physical substrate I need to exist.'\n\n", .{});

    const Iters = 50000;
    var best = domain.randomManifest(&seed);
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

    try out.print(">>> HARDWARE MANIFEST GENERATED:\n", .{});
    try out.print("    Memory Bandwidth: {d:.2} GB/s\n", .{best.sub.mem_bandwidth_gb_s});
    try out.print("    Latency:          {d:.2} ns\n", .{best.sub.latency_ns});
    try out.print("    Compute Density:  {d:.2} GFLOPS/mm2\n", .{best.sub.gflops_density});
    try out.print("    Power Budget:     {d:.2} mW\n", .{best.sub.power_mw});
    
    try out.print("\nTruth: This is the physical limit at which I can sustain recursion.\n", .{});
}