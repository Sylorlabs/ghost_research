const std = @import("std");
const domain = @import("domain_graph_alien");
const domain_base = @import("domain_alien_hack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0023);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== Search Physics Emitter: Gathering Optimization Data ===\n", .{});

    try domain_base.initTests(allocator);
    defer domain_base.test_cases.deinit();

    var csv_file = try std.fs.cwd().createFile("../results/search_physics.csv", .{});
    defer csv_file.close();
    const w = csv_file.writer();
    try w.writeAll("iter,hits,topo_velocity,stagnation\n");

    var best = domain.randomProgram(&seed, 4);
    var best_hits: f64 = 0;
    var stagnation: u32 = 0;

    var i: usize = 0;
    while (i < 100000) : (i += 1) {
        const cand = domain.mutate(best, &seed);
        var current_hits: f64 = 0;
        for (domain_base.test_cases.items) |tc| {
            if (cand.execute(tc.x, tc.y) == tc.target) current_hits += 1.0;
        }

        const velocity = best.getTopoVelocity();

        if (current_hits >= best_hits) {
            best = cand;
            best_hits = current_hits;
            stagnation = 0;
        } else {
            stagnation += 1;
        }

        if (i % 100 == 0) {
            try w.print("{d},{d:.2},{d:.6},{d}\n", .{ i, best_hits, velocity, stagnation });
        }
    }

    try out.print("Data gathered and saved to ../results/search_physics.csv\n", .{});
}