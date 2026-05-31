const std = @import("std");
const domain = @import("domain_u64_mixer_nonlinear");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_F00D_CAFE_BABE);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== Nonlinear Escape Experiment ===\n", .{});
    try out.print("Domain: {s}\n", .{domain.DOMAIN_NAME});
    try out.print("Mode: mul_free (XOR, ADD, ROTL, SHL_XOR, SHR_XOR, ADD_CONST, AND_NOT, OR_SHIFT, ROTR, BSWAP, ADD_ROT)\n", .{});
    try out.print("Goal: Synthesize a high-quality mixer while maximizing non-affine instructions.\n\n", .{});

    const Iters = 20000;
    var best = domain.randomProgram(&seed, .mul_free, 12);
    var best_q = domain.evaluateQuality(best);

    try out.print("Iter {d:5}: Start Q={d:.2} (Av={d:.1} Bal={d:.1} Per={d})\n", .{
        0, best_q.composite, best_q.avalanche, best_q.balance, best_q.period
    });

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const candidate = domain.mutate(best, &seed, .mul_free, 12);
        const q = domain.evaluateQuality(candidate);
        
        if (domain.qualityScalar(q) >= domain.qualityScalar(best_q)) {
            best = candidate;
            best_q = q;
            if (i % 1000 == 0) {
                try out.print("Iter {d:5}: Q={d:.2} (Av={d:.1} Bal={d:.1} Per={d})\n", .{
                    i, best_q.composite, best_q.avalanche, best_q.balance, best_q.period
                });
            }
        }
    }

    try out.print("\n=== Best Program Found ===\n", .{});
    try out.print("Quality: {d:.2}\n", .{best_q.composite});
    try out.print("Avalanche: {d:.2}\n", .{best_q.avalanche});
    try out.print("Balance: {d:.2}\n", .{best_q.balance});
    try out.print("Period: {d}\n", .{best_q.period});
    
    var non_affine = @as(usize, 0);
    for (best.instructions[0..best.used]) |inst| {
        switch (inst.op) {
            .ADD, .AND_NOT, .ADD_ROT => non_affine += 1,
            else => {},
        }
    }
    try out.print("Non-affine instruction count: {d}\n\n", .{non_affine});
    try domain.printProgram(best, .mul_free, out);

    var csv_file = try std.fs.cwd().createFile("../results/nonlinear_escape_champion.csv", .{});
    defer csv_file.close();
    try domain.programToCsv(best, csv_file.writer());
    try out.print("Saved to ../results/nonlinear_escape_champion.csv\n", .{});
}