const std = @import("std");
const domain = @import("domain_graph_alien");
const domain_base = @import("domain_alien_hack");
const smt = @import("smt_verify");
const smt_graph = @import("smt_graph_alien");

fn evaluateHybrid(p: domain.GraphProgram) f64 {
    // Hits on current test cases
    var hits: f64 = 0;
    for (domain_base.test_cases.items) |tc| {
        if (p.execute(tc.x, tc.y) == tc.target) hits += 1.0;
    }
    
    // Tier 4: Topological Guidance
    const matrix = p.executeSymbolic();
    var topo_score: f64 = 0;
    for (matrix, 0..) |dep, b| {
        const target_mask = (@as(u64, 1) << @as(u6, @intCast(@min(63, b + 1)))) | (@as(u64, 1) << @as(u6, @intCast(b)));
        if ((dep.x & target_mask) != 0) topo_score += 0.5;
        if ((dep.y & target_mask) != 0) topo_score += 0.5;
    }
    
    const target_hits = @as(f64, @floatFromInt(domain_base.test_cases.items.len));
    if (hits >= target_hits - 0.0001) {
        return hits + 100.0 - @as(f64, @floatFromInt(p.used)); // MDL Compression
    }
    return hits + (topo_score / 64.0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0010);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== Tier 4 Graph Architect: Alien Hack ===\n", .{});
    try out.print("Substrate: Fluid Topology (DAG)\n", .{});
    try out.print("Guidance: Topological Execution Tracing\n\n", .{});

    try domain_base.initTests(allocator);
    defer domain_base.test_cases.deinit();

    var generation: usize = 1;
    while (generation < 20) : (generation += 1) {
        try out.print(">>> CEGIS GENERATION {d} (Tests: {d})\n", .{ generation, domain_base.test_cases.items.len });
        
        var best = domain.randomProgram(&seed, 4);
        var best_q = evaluateHybrid(best);
        const target_hits = @as(f64, @floatFromInt(domain_base.test_cases.items.len));

        var iters: usize = 0;
        var temp: f64 = 1.0;
        while (best_q < target_hits + 90.0 and iters < 20000000) : (iters += 1) {
            const cand = domain.mutate(best, &seed);
            const q = evaluateHybrid(cand);
            
            // SA acceptance
            if (q >= best_q or @as(f64, @floatFromInt(prng.random().int(u64) % 10000)) / 10000.0 < std.math.exp((q - best_q) / temp)) {
                best = cand;
                best_q = q;
            }
            if (iters % 1000000 == 0) {
                temp *= 0.95;
            }
        }

        if (best_q < target_hits + 90.0) {
            try out.print("    [FAILED] Architect could not solve generation {d}.\n", .{generation});
            return;
        }

        try out.print("    [CANDIDATE FOUND] Nodes: {d}. Verifying with Z3...\n", .{best.used});

        const smt_text = try smt_graph.emitGraphCorrectness(allocator, best.nodes[0..best.used]);
        defer allocator.free(smt_text);

        const res = try smt.runSmtLib(allocator, smt_text, 10000);
        
        if (res.verdict == .verified) {
            try out.print("\n!!! INVENTION SUCCESS !!!\n", .{});
            try out.print("Fluid Topology Architect found the perfect Alien Hack.\n", .{});
            var j: usize = 0;
            while (j < best.used) : (j += 1) {
                const n = best.nodes[j];
                try out.print("  v{d} = {s}(v{d}, v{d}, imm={d})\n", .{ j + 2, @tagName(n.op), n.src1, n.src2, n.imm });
            }
            return;
        } else if (res.verdict == .counter_example) {
            defer allocator.free(res.detail);
            const x = try parseHex(res.detail, " x ");
            const y = try parseHex(res.detail, " y ");
            const target = @as(u64, @intCast((@as(u128, x) + y) / 2));
            try out.print("    [Z3 REJECTED] Found flaw. New Test: x=0x{X:0>16}, y=0x{X:0>16}\n\n", .{ x, y });
            try domain_base.test_cases.append(.{ .x = x, .y = y, .target = target });
        } else {
            try out.print("    [ERROR] Z3: {s}\n", .{res.detail});
            allocator.free(res.detail);
            // Don't crash, just retry this generation
            continue;
        }
    }
}

fn parseHex(model: []const u8, name_pattern: []const u8) !u64 {
    const name_idx = std.mem.indexOf(u8, model, name_pattern) orelse return error.PatternNotFound;
    const hex_marker_idx = std.mem.indexOfPos(u8, model, name_idx, "#x") orelse return error.HexMarkerNotFound;
    const hex_start = hex_marker_idx + 2;
    const hex_end = std.mem.indexOfScalarPos(u8, model, hex_start, ')') orelse return error.ModelMalformed;
    const hex_str = std.mem.trim(u8, model[hex_start..hex_end], " \n\r\t");
    return try std.fmt.parseInt(u64, hex_str, 16);
}