const std = @import("std");
const domain = @import("domain_graph_alien");
const domain_base = @import("domain_alien_hack");
const smt = @import("smt_verify");
const smt_graph = @import("smt_graph_alien");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const out = std.io.getStdOut().writer();
    try out.print("=== The Combat Test: Human vs. Alien Heuristic ===\n", .{});
    try out.print("Task: Solve 5 generations of the Alien Hack CEGIS loop.\n\n", .{});

    // We run two separate trials with fixed seeds for fairness
    const human_time = try runTrial(allocator, .human, 0x12345678, out);
    try out.print("\n-------------------------------------------\n", .{});
    const alien_time = try runTrial(allocator, .alien, 0x12345678, out);

    try out.print("\n=== FINAL COMBAT RESULTS ===\n", .{});
    try out.print("Human Heuristic Time: {d} ms\n", .{human_time});
    try out.print("Alien Heuristic Time: {d} ms\n", .{alien_time});

    if (alien_time < human_time) {
        const speedup = (@as(f64, @floatFromInt(human_time)) / @as(f64, @floatFromInt(alien_time)) - 1.0) * 100.0;
        try out.print("\nVERDICT: BREAKTHROUGH! The machine-invented law is {d:.1}% faster than the human.\n", .{speedup});
    } else {
        try out.print("\nVERDICT: HYPE. Human intuition is still superior to autonomous symbolic regression.\n", .{});
    }
}

const Heuristic = enum { human, alien };

fn runTrial(allocator: std.mem.Allocator, mode: Heuristic, master_seed: u64, out: anytype) !u64 {
    try out.print(">>> STARTING TRIAL: Mode={s}\n", .{@tagName(mode)});
    
    var prng = std.Random.DefaultPrng.init(master_seed);
    var seed = prng.random().int(u64);

    // Re-init tests for this specific trial
    try domain_base.initTests(allocator);
    // Note: domain_base.test_cases is global, so we must be careful.
    // Clear and add the 2 base cases.
    domain_base.test_cases.clearRetainingCapacity();
    try domain_base.test_cases.append(.{ .x = 10, .y = 0, .target = 5 });
    try domain_base.test_cases.append(.{ .x = 16, .y = 0, .target = 8 });

    const start_time = std.time.milliTimestamp();
    
    var gen: usize = 1;
    while (gen <= 5) : (gen += 1) {
        var best = domain.randomProgram(&seed, 4);
        var stagnation: u32 = 0;
        var iters: usize = 0;
        const target_hits = @as(f64, @floatFromInt(domain_base.test_cases.items.len));

        while (iters < 5000000) : (iters += 1) {
            const cand = domain.mutate(best, &seed);
            
            const cand_hits = evaluateHits(cand);
            const best_hits = evaluateHits(best);

            if (cand_hits >= best_hits) {
                best = cand;
                stagnation = 0;
            } else {
                stagnation += 1;
            }

            // --- THE HEURISTIC CROSSOVER ---
            var should_reset = false;
            const vel = best.getTopoVelocity();
            
            if (mode == .human) {
                if (stagnation > 500) should_reset = true;
            } else {
                // Evolved Alien Law: (((STAG + VEL) / 59.85) LOG ((1.2 / VEL) + 1)) > 1.0
                const stag_f = @as(f64, @floatFromInt(stagnation));
                const part1 = (stag_f + vel) / 59.85;
                const part2 = (1.2 / @max(0.000001, vel)) + 1.0;
                const res = @log(@max(0.000001, @abs(part1))) * @log(@max(0.000001, @abs(part2)));
                if (res > 1.0) should_reset = true;
            }

            if (should_reset) {
                best = domain.randomProgram(&seed, 4);
                stagnation = 0;
            }

            if (evaluateHits(best) >= target_hits) break;
        }

        if (evaluateHits(best) < target_hits) {
            try out.print("    [Gen {d}] Failed to pass tests in time.\n", .{gen});
            return 999999;
        }

        // Z3 Verify
        const smt_text = try smt_graph.emitGraphCorrectness(allocator, best.nodes[0..best.used]);
        defer allocator.free(smt_text);
        const res = try smt.runSmtLib(allocator, smt_text, 1000);
        if (res.verdict == .verified or (res.verdict == .error_smt and std.mem.startsWith(u8, res.detail, "unsat"))) {
            if (res.verdict == .error_smt) allocator.free(res.detail);
            try out.print("    [Gen {d}] Verified! Moving to next generation.\n", .{gen});
        } else if (res.verdict == .counter_example) {
            defer allocator.free(res.detail);
            const x_val = try parseHex(res.detail, "define-fun x ");
            try domain_base.test_cases.append(.{ .x = x_val, .y = 0, .target = x_val / 2 }); // simplified
            try out.print("    [Gen {d}] Counter-example added. Tests: {d}\n", .{gen, domain_base.test_cases.items.len});
        } else {
            return 999999;
        }
    }

    return @as(u64, @intCast(std.time.milliTimestamp() - start_time));
}

fn evaluateHits(p: domain.GraphProgram) f64 {
    var hits: f64 = 0;
    for (domain_base.test_cases.items) |tc| {
        if (p.execute(tc.x, tc.y) == tc.target) hits += 1.0;
    }
    return hits;
}

fn parseHex(model: []const u8, pattern: []const u8) !u64 {
    const idx = std.mem.indexOf(u8, model, pattern) orelse return error.NotFound;
    const hex_idx = std.mem.indexOf(u8, model[idx..], "#x") orelse return error.NoHex;
    const start = idx + hex_idx + 2;
    const end = std.mem.indexOfScalarPos(u8, model, start, ')') orelse return error.Malformed;
    return try std.fmt.parseInt(u64, model[start..end], 16);
}