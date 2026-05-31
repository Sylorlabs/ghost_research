const std = @import("std");
const domain = @import("domain_alien_hack");
const smt = @import("smt_verify");
const smt_alien = @import("smt_alien_hack");

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0008);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== Automated CEGIS: Alien Hack Invention ===\n", .{});
    try out.print("Domain: {s}\n", .{domain.DOMAIN_NAME});
    try out.print("Inventor: Hill-Climber (Stochastic)\n", .{});
    try out.print("Verifier: Z3 SMT Solver (Formal)\n\n", .{});

    try domain.initTests(allocator);
    defer domain.test_cases.deinit();

    var generation: usize = 1;
    while (generation < 20) : (generation += 1) {
        try out.print(">>> CEGIS GENERATION {d} (Test Cases: {d})\n", .{ generation, domain.test_cases.items.len });
        
        // 1. WAKE PHASE: Hill-Climber invents a candidate to pass current tests
        var best = domain.randomProgram(&seed);
        var best_q = domain.evaluateQuality(best);
        const target_hits = @as(f64, @floatFromInt(domain.test_cases.items.len));

        var iters: usize = 0;
        var temp: f64 = 1.0;
        while (best_q < target_hits + 90.0 and iters < 50000000) : (iters += 1) {
            const cand = domain.mutate(best, &seed);
            const q = domain.evaluateQuality(cand);
            
            if (q >= best_q or @as(f64, @floatFromInt(nextRand(&seed) % 10000)) / 10000.0 < std.math.exp((q - best_q) / temp)) {
                best = cand;
                best_q = q;
            }
            if (iters % 1000000 == 0) {
                try out.print("      Iter {d:8}: Q={d:.2} (Temp={d:.3})\n", .{ iters, best_q, temp });
                temp *= 0.99; // Cool down
            }
        }

        if (best_q < target_hits + 90.0) {
            try out.print("    [FAILED] Hill-climber could not solve generation {d}.\n", .{generation});
            return;
        }

        try out.print("    [CANDIDATE FOUND] Length: {d}. Verifying with Z3...\n", .{best.used});

        // 2. VERIFICATION PHASE: Z3 proves or finds counter-example
        const smt_text = try smt_alien.emitAlienHackCorrectness(allocator, best.instructions[0..best.used]);
        defer allocator.free(smt_text);

        const res = try smt.runSmtLib(allocator, smt_text, 10000);
        defer if (res.verdict != .verified) allocator.free(res.detail);
        
        if (res.verdict == .verified) {
            try out.print("\n!!! INVENTION SUCCESS !!!\n", .{});
            try out.print("Z3 mathematically proves this program is correct for ALL 2^128 inputs.\n", .{});
            try domain.printProgram(best, out);
            return;
        } else if (res.verdict == .counter_example) {
            try out.print("    [Z3 REJECTED] Found algebraic flaw. Extracting counter-example...\n", .{});
            
            // Crude Z3 model parser for x and y
            const x = try parseHex(res.detail, "define-fun x ");
            const y = try parseHex(res.detail, "define-fun y ");
            
            const sum128 = @as(u128, x) + @as(u128, y);
            const target = @as(u64, @intCast(sum128 / 2));
            
            try out.print("    [NEW TEST CASE] x=0x{X:0>16}, y=0x{X:0>16}\n\n", .{ x, y });
            try domain.test_cases.append(.{ .x = x, .y = y, .target = target });
        } else {
            try out.print("    [ERROR] Z3 returned unknown or error: {s}\n", .{res.detail});
            return;
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