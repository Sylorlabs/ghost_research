const std = @import("std");
const domain_base = @import("domain_alien_hack");
const domain_graph = @import("domain_graph_alien");
const domain_sort = @import("domain_sort_net");
const domain_mixer = @import("domain_u64_mixer");
const engine = @import("invention_engine");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const out = std.io.getStdOut().writer();
    try out.print("=== The Generality Tournament: Testing the Alien Law ===\n", .{});
    try out.print("Objective: Is the machine-invented law a Universal Search Truth?\n\n", .{});

    const domains = [_]struct { name: []const u8, id: DomainId }{
        .{ .name = "Alien Hack (Algebra)", .id = .alien_hack },
        .{ .name = "Sort Net N=8 (Logic)", .id = .sort_net },
        .{ .name = "u64 Mixer (Statistics)", .id = .u64_mixer },
    };

    var human_total: f64 = 0;
    var alien_total: f64 = 0;

    for (domains) |d| {
        try out.print(">>> TOURNAMENT ROUND: {s}\n", .{d.name});
        const human_perf = try runDomainTrial(allocator, d.id, .human, 0x1234);
        const alien_perf = try runDomainTrial(allocator, d.id, .alien, 0x1234);
        
        try out.print("    Human: {d:.2} hits/sec\n", .{human_perf});
        try out.print("    Alien: {d:.2} hits/sec\n", .{alien_perf});
        
        human_total += human_perf;
        alien_total += alien_perf;
    }

    const avg_human = human_total / 3.0;
    const avg_alien = alien_total / 3.0;

    try out.print("\n=== FINAL TOURNAMENT VERDICT ===\n", .{});
    try out.print("Average Human Performance: {d:.2} hits/sec\n", .{avg_human});
    try out.print("Average Alien Performance: {d:.2} hits/sec\n", .{avg_alien});

    if (avg_alien > avg_human) {
        const lift = (avg_alien / avg_human - 1.0) * 100.0;
        try out.print("\nTHE ALIEN LAW IS UNIVERSAL! (Across-domain lift: {d:.1}%)\n", .{lift});
        try out.print("This is no longer 'just fast'; it is a superior search philosophy.\n", .{});
    } else {
        try out.print("\nTHE ALIEN LAW IS A SPECIALIST. (Failed to generalize).\n", .{});
        try out.print("It overfit to the physics of the Alien Hack and failed in broader math.\n", .{});
    }
}

const DomainId = enum { alien_hack, sort_net, u64_mixer };
const Mode = enum { human, alien };

fn runDomainTrial(allocator: std.mem.Allocator, domain_id: DomainId, mode: Mode, master_seed: u64) !f64 {
    var prng = std.Random.DefaultPrng.init(master_seed);
    var seed = prng.random().int(u64);
    
    const budget = 5000; // Fixed iteration budget for each domain
    var iters: usize = 0;
    var total_hits: f64 = 0;
    
    // We measure "hits" (successful improvements or correct outputs) per second
    const start_time = std.time.milliTimestamp();

    switch (domain_id) {
        .alien_hack => {
            try domain_base.initTests(allocator);
            var best = domain_graph.randomProgram(&seed, 4);
            var stagnation: u32 = 0;
            while (iters < budget) : (iters += 1) {
                const cand = domain_graph.mutate(best, &seed);
                if (evalAlien(cand) >= evalAlien(best)) {
                    best = cand;
                    total_hits += 1;
                    stagnation = 0;
                } else stagnation += 1;
                if (checkReset(mode, stagnation, best.getTopoVelocity())) {
                    best = domain_graph.randomProgram(&seed, 4);
                    stagnation = 0;
                }
            }
        },
        .sort_net => {
            var best = domain_sort.randomProgram(&seed);
            var stagnation: u32 = 0;
            while (iters < budget) : (iters += 1) {
                const cand = domain_sort.mutate(best, &seed);
                if (domain_sort.evaluateQuality(cand).composite >= domain_sort.evaluateQuality(best).composite) {
                    best = cand;
                    total_hits += 1;
                    stagnation = 0;
                } else stagnation += 1;
                // Note: sort_net doesn't have TopoVelocity yet, using mock
                if (checkReset(mode, stagnation, 0.01)) {
                    best = domain_sort.randomProgram(&seed);
                    stagnation = 0;
                }
            }
        },
        .u64_mixer => {
            var best = domain_mixer.randomProgram(&seed);
            var stagnation: u32 = 0;
            while (iters < budget) : (iters += 1) {
                const cand = domain_mixer.mutate(best, &seed);
                if (domain_mixer.evaluateQuality(cand).composite >= domain_mixer.evaluateQuality(best).composite) {
                    best = cand;
                    total_hits += 1;
                    stagnation = 0;
                } else stagnation += 1;
                if (checkReset(mode, stagnation, 0.01)) {
                    best = domain_mixer.randomProgram(&seed);
                    stagnation = 0;
                }
            }
        },
    }

    const elapsed = @as(f64, @floatFromInt(std.time.milliTimestamp() - start_time)) / 1000.0;
    return total_hits / @max(0.001, elapsed);
}

fn checkReset(mode: Mode, stagnation: u32, velocity: f64) bool {
    if (mode == .human) return stagnation > 500;
    // Evolved Alien Law
    const stag_f = @as(f64, @floatFromInt(stagnation));
    const part1 = (stag_f + velocity) / 59.85;
    const part2 = (1.2 / @max(0.000001, velocity)) + 1.0;
    const res = @log(@max(0.000001, @abs(part1))) * @log(@max(0.000001, @abs(part2)));
    return res > 1.0;
}

fn evalAlien(p: domain_graph.GraphProgram) f64 {
    var hits: f64 = 0;
    for (domain_base.test_cases.items) |tc| {
        if (p.execute(tc.x, tc.y) == tc.target) hits += 1.0;
    }
    return hits;
}