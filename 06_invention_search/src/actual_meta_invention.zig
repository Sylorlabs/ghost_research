const std = @import("std");
const meta = @import("domain_meta_architect");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_9999);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== Real Tier 3 Meta-Invention: BitForge Synthesizing BitForge ===\n\n", .{});
    try out.print("Task: Discover a search algorithm that solves the Alien Hack the fastest.\n", .{});
    try out.print("Optimization Data: Measured clock-time of the heuristic execution.\n\n", .{});

    var best_meta = randomMetaProgram(&seed);
    try out.print(">>> INITIAL GUESS:\n", .{});
    printMeta(best_meta, out) catch unreachable;
    
    var best_time = try best_meta.execute(allocator, 5000);
    try out.print(">>> Initial Score: {d} ms\n\n", .{best_time});

    const Iters = 50; // Small number of iters because each iter runs a real search!
    var i: usize = 1;
    while (i <= Iters) : (i += 1) {
        const cand = if (i % 5 == 0) randomMetaProgram(&seed) else mutateMeta(best_meta, &seed);
        
        try out.print("Iter {d:2}: Testing candidate...", .{i});
        const cand_time = try cand.execute(allocator, 5000);
        
        if (cand_time < best_time) {
            best_meta = cand;
            best_time = cand_time;
            try out.print(" NEW CHAMPION! ({d} ms)\n", .{best_time});
            printMeta(best_meta, out) catch unreachable;
        } else {
            try out.print(" Rejected ({d} ms)\n", .{cand_time});
        }
    }

    try out.print("\n=== FINAL DISCOVERY: THE ALIEN SEARCH HEURISTIC ===\n", .{});
    try out.print("This algorithm was autonomously fuzzed and measured by BitForge.\n", .{});
    printMeta(best_meta, out) catch unreachable;
    try out.print("\nFinal Performance: {d} ms per solve.\n", .{best_time});
}

fn randomMetaProgram(rng: *u64) meta.MetaProgram {
    const len = @as(u8, @intCast(2 + (nextRand(rng) % 6)));
    var p = meta.MetaProgram{ .ops = undefined, .used = len };
    for (0..len) |i| {
        p.ops[i] = .{
            .op = @enumFromInt(nextRand(rng) % 4),
            .p1 = @as(u32, @intCast(100 + (nextRand(rng) % 1000))),
        };
    }
    return p;
}

fn mutateMeta(p: meta.MetaProgram, rng: *u64) meta.MetaProgram {
    var q = p;
    const idx = nextRand(rng) % q.used;
    const draw = nextRand(rng) % 3;
    if (draw == 0) {
        q.ops[idx].op = @enumFromInt(nextRand(rng) % 4);
    } else {
        q.ops[idx].p1 = @as(u32, @intCast(100 + (nextRand(rng) % 2000)));
    }
    return q;
}

fn printMeta(p: meta.MetaProgram, writer: anytype) !void {
    for (p.ops[0..p.used]) |op| {
        try writer.print("  - {s}(p1={d})\n", .{ @tagName(op.op), op.p1 });
    }
}

fn smix(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn nextRand(rng: *u64) u64 {
    rng.* = smix(rng.*);
    return rng.*;
}