const std = @import("std");
const domain_alien = @import("domain_graph_alien");
const domain_base = @import("domain_alien_hack");
const domain_sort = @import("domain_sort_net");
const domain_mixer = @import("domain_u64_mixer");
const engine = @import("invention_engine");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0024);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== The Adversarial Gauntlet: Collecting Multimodal Failure Data ===\n", .{});

    var csv_file = try std.fs.cwd().createFile("../results/adversarial_physics.csv", .{});
    defer csv_file.close();
    const w = csv_file.writer();
    try w.writeAll("domain,iter,phase,hits,velocity,stagnation,should_reset\n");

    // Pathology 1: Alien Hack (Algebraic trap)
    try runPathology(allocator, .alien_hack, 10000, &seed, w, out);
    // Pathology 2: Sort Net (Combinatorial trap)
    try runPathology(allocator, .sort_net, 10000, &seed, w, out);
    // Pathology 3: u64 Mixer (Chaotic gradient trap)
    try runPathology(allocator, .u64_mixer, 10000, &seed, w, out);

    try out.print("\nGauntlet complete. Optimization data saved to ../results/adversarial_physics.csv\n", .{});
}

const Pathology = enum { alien_hack, sort_net, u64_mixer };

fn runPathology(allocator: std.mem.Allocator, path: Pathology, budget: usize, rng: *u64, w: anytype, out: anytype) !void {
    try out.print(">>> RUNNING PATHOLOGY: {s}\n", .{@tagName(path)});
    
    var iters: usize = 0;
    var stagnation: u32 = 0;
    var best_q: f64 = -1000.0;
    
    switch (path) {
        .alien_hack => {
            try domain_base.initTests(allocator);
            var best = domain_graph.randomProgram(rng, 4);
            while (iters < budget) : (iters += 1) {
                const cand = domain_graph.mutate(best, rng);
                const q = evalAlien(cand);
                if (q >= best_q) { best = cand; best_q = q; stagnation = 0; } else stagnation += 1;
                if (iters % 100 == 0) {
                    const phase = @as(f64, @floatFromInt(iters)) / @as(f64, @floatFromInt(budget));
                    try w.print("{s},{d},{d:.4},{d:.2},{d:.6},{d},{}\n", .{
                        @tagName(path), iters, phase, best_q, best.getTopoVelocity(), stagnation, stagnation > 150
                    });
                }
            }
        },
        .sort_net => {
            var best = domain_sort.randomProgram(rng);
            while (iters < budget) : (iters += 1) {
                const cand = domain_sort.mutate(best, rng);
                const q = domain_sort.evaluateQuality(cand).composite;
                if (q >= best_q) { best = cand; best_q = q; stagnation = 0; } else stagnation += 1;
                if (iters % 100 == 0) {
                    const phase = @as(f64, @floatFromInt(iters)) / @as(f64, @floatFromInt(budget));
                    try w.print("{s},{d},{d:.4},{d:.2},{d:.6},{d},{}\n", .{
                        @tagName(path), iters, phase, best_q, 0.01, stagnation, stagnation > 150
                    });
                }
            }
        },
        .u64_mixer => {
            var best = domain_mixer.randomProgram(rng);
            while (iters < budget) : (iters += 1) {
                const cand = domain_mixer.mutate(best, rng);
                const q = domain_mixer.evaluateQuality(cand).composite;
                if (q >= best_q) { best = cand; best_q = q; stagnation = 0; } else stagnation += 1;
                if (iters % 100 == 0) {
                    const phase = @as(f64, @floatFromInt(iters)) / @as(f64, @floatFromInt(budget));
                    try w.print("{s},{d},{d:.4},{d:.2},{d:.6},{d},{}\n", .{
                        @tagName(path), iters, phase, best_q, 0.01, stagnation, stagnation > 150
                    });
                }
            }
        },
    }
}

fn evalAlien(p: domain_graph.GraphProgram) f64 {
    var hits: f64 = 0;
    for (domain_base.test_cases.items) |tc| {
        if (p.execute(tc.x, tc.y) == tc.target) hits += 1.0;
    }
    return hits;
}
const domain_graph = domain_graph_mod;
const domain_graph_mod = @import("domain_graph_alien");