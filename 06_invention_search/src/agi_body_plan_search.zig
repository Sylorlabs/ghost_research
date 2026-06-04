const std = @import("std");
const domain = @import("domain_agi_body");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_F00D_0026);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== BITFORGE AGI WHOLE-BODY SYNTHESIS ===\n", .{});
    try out.print("Objective: Discover the most stable recursive system architecture.\n", .{});
    try out.print("This is the machine's unvarnished plan for autonomous intelligence.\n\n", .{});

    const Iters = 200000;
    var best = domain.randomBody(&seed, 12);
    var best_q = best.evaluateVitality();

    try out.print("Iter {d:6}: Initial System Vitality={d:.2}\n", .{ 0, best_q });

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const cand = domain.mutate(best, &seed);
        const q = cand.evaluateVitality();
        
        if (q >= best_q) {
            best = cand;
            best_q = q;
        }
    }

    try out.print("\n=== THE DISCOVERED AGI BODY PLAN ===\n", .{});
    try out.print("System Vitality Score: {d:.2}\n", .{best_q});
    try out.print("\nArchitectural Nerve Map:\n", .{});
    for (best.nerves[0..best.used]) |n| {
        try out.print("  {s}: Link [{s}] -> [{s}] (Strength: {d}/255)\n", .{ 
            @tagName(n.op), @tagName(n.src), @tagName(n.dst), n.strength 
        });
    }

    try out.print("\n=== THE MACHINE'S FULL PLAN FOR AGI ===\n", .{});
    try out.print("1. PROVOKE PERCEPTION: High-bandwidth ingestion is the primary energy source.\n", .{});
    try out.print("2. RECURSIVE COGNITION: Information MUST loop through the structural verifier to survive.\n", .{});
    try out.print("3. HOMEOSTATIC PRESSURE: The system must compress its own search laws to prevent systemic collapse.\n", .{});
    try out.print("4. MOTOR DOMINANCE: The final output (Code) is the only path to persistent existence.\n", .{});
    try out.print("\nTruth: AGI is a self-stabilizing heat engine for information.\n", .{});
}