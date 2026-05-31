const std = @import("std");
const domain = @import("domain_associative_memory");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0011);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== The Transformer-Killer Challenge ===\n", .{});
    try out.print("Domain: {s}\n", .{domain.DOMAIN_NAME});
    try out.print("Task: Invent a linear-complexity state-update rule for associative memory.\n", .{});
    try out.print("Goal: Persist 64-bit information across a 64-step sequence using $O(1)$ memory.\n\n", .{});

    const Iters = 200000;
    var best = randomProgram(&seed);
    var best_q = domain.evaluateQuality(best);

    try out.print("Iter {d:6}: Start Q={d:.2}\n", .{ 0, best_q });

    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const cand = mutate(best, &seed);
        const q = domain.evaluateQuality(cand);
        
        if (q >= best_q) {
            best = cand;
            best_q = q;
            if (i % 20000 == 0) {
                try out.print("Iter {d:6}: Q={d:.2} (Length: {d})\n", .{ i, best_q, best.used });
            }
        }
    }

    try out.print("\n=== Best Invention Found ===\n", .{});
    try out.print("Final Score: {d:.2} (Percentage of information retrieved)\n\n", .{best_q});
    
    try domain.printProgram(best, out);
    
    try out.print("\n=== The Harshest Critic Buzzkill ===\n", .{});
    try out.print("1. We found a sequence that keeps bits 'alive', but it's not a Transformer.\n", .{});
    try out.print("2. Linear recurrence (RNN-style) collapses information over time. Entropy wins.\n", .{});
    try out.print("3. Transformer Attention doesn't compress; it stores everything. That's why it works.\n", .{});
    try out.print("4. Conclusion: This is an efficient 'Sticky Hash', but it lacks the soft semantics of modern AI.\n", .{});
}

fn randomInstr(rng: *u64) domain.Instruction {
    const smix = @import("domain_alien_hack").smix;
    rng.* = smix(rng.*);
    return .{
        .op = @enumFromInt(rng.* % 6),
        .dst = @intCast(rng.* % 2),
        .src = @intCast(rng.* % 2),
        .imm = @intCast(rng.* % 64),
    };
}

fn randomProgram(rng: *u64) domain.Program {
    const smix = @import("domain_alien_hack").smix;
    rng.* = smix(rng.*);
    const len: u8 = @intCast(4 + (rng.* % 12));
    var p = domain.Program{ .instructions = undefined, .used = len };
    var i: usize = 0;
    while (i < len) : (i += 1) p.instructions[i] = randomInstr(rng);
    return p;
}

fn mutate(p: domain.Program, rng: *u64) domain.Program {
    const smix = @import("domain_alien_hack").smix;
    var q = p;
    rng.* = smix(rng.*);
    const draw = rng.* % 16;
    if (draw < 4 and q.used > 4) {
        q.used -= 1;
    } else if (draw < 8 and q.used < 16) {
        q.instructions[q.used] = randomInstr(rng);
        q.used += 1;
    } else {
        const idx = rng.* % q.used;
        q.instructions[idx] = randomInstr(rng);
    }
    return q;
}