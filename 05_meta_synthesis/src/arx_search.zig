const std = @import("std");
const domain = @import("domain_u64_bijective");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_BEEF_CAFE_0001);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== Structurally Bijective ARX Synthesis ===\n", .{});
    try out.print("Domain: {s}\n", .{domain.DOMAIN_NAME});
    try out.print("Goal: Synthesize a high-quality bijective mixer using ONLY reversible ARX ops.\n\n", .{});

    const Iters = 50000;
    var best = domain.randomProgram(&seed, 16);
    var best_q = domain.evaluateQuality(best);

    try out.print("Iter {d:5}: Start Q={d:.2} (Av={d:.1} ChiSq={d:.1})\n", .{
        0, best_q.composite, best_q.avalanche, best_q.chisq
    });

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const candidate = domain.mutate(best, &seed, 16);
        const q = domain.evaluateQuality(candidate);
        
        if (q.composite >= best_q.composite) {
            best = candidate;
            best_q = q;
            if (i % 1000 == 0) {
                try out.print("Iter {d:5}: Q={d:.2} (Av={d:.1} ChiSq={d:.1})\n", .{
                    i, best_q.composite, best_q.avalanche, best_q.chisq
                });
            }
        }
    }

    try out.print("\n=== Best Program Found ===\n", .{});
    try out.print("Quality: {d:.2}\n", .{best_q.composite});
    try out.print("Avalanche: {d:.2}\n", .{best_q.avalanche});
    try out.print("ChiSq: {d:.2}\n\n", .{best_q.chisq});
    
    try domain.printProgram(best, out);

    var csv_file = try std.fs.cwd().createFile("../results/arx_champion.csv", .{});
    defer csv_file.close();
    try domain.programToCsv(best, csv_file.writer());
    try out.print("Saved to ../results/arx_champion.csv\n", .{});
}