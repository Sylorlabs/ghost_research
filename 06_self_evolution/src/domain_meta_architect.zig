const std = @import("std");
const domain_alien = @import("domain_graph_alien");
const domain_base = @import("domain_alien_hack");
const smt = @import("smt_verify");
const smt_graph = @import("smt_graph_alien");

pub const DOMAIN_NAME: []const u8 = "actual-meta-architect";

pub const MetaOp = enum(u4) {
    STOCHASTIC_STEP = 0,   // Run N mutation steps
    TOPOLOGICAL_ALIGN = 1, // Reset to best structural skeleton
    Z3_REFINE = 2,         // Run Z3 and add a counter-example
    MDL_COMPRESS = 3,      // Try to reduce node count
};

pub const MetaInstruction = struct {
    op: MetaOp,
    p1: u32,
};

pub const MetaProgram = struct {
    ops: [8]MetaInstruction,
    used: u8,

    pub fn execute(self: MetaProgram, allocator: std.mem.Allocator, max_time_ms: u64) !u64 {
        var seed: u64 = 0x12345678;
        
        try domain_base.initTests(allocator);
        
        var current_best = domain_alien.randomProgram(&seed, 4);
        
        const start_time = std.time.milliTimestamp();
        var solved = false;
        var loop_count: usize = 0;

        while (!solved and loop_count < 10) : (loop_count += 1) {
            const elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
            if (elapsed > max_time_ms) break;

            for (self.ops[0..self.used]) |inst| {
                switch (inst.op) {
                    .STOCHASTIC_STEP => {
                        var iters: u32 = 0;
                        while (iters < inst.p1) : (iters += 1) {
                            const cand = domain_alien.mutate(current_best, &seed);
                            if (evaluateQuality(cand) >= evaluateQuality(current_best)) {
                                current_best = cand;
                            }
                        }
                    },
                    .TOPOLOGICAL_ALIGN => {
                        current_best = domain_alien.randomProgram(&seed, current_best.used);
                    },
                    .Z3_REFINE => {
                        const smt_text = try smt_graph.emitGraphCorrectness(allocator, current_best.nodes[0..current_best.used]);
                        defer allocator.free(smt_text);
                        const res = try smt.runSmtLib(allocator, smt_text, 500);
                        if (res.verdict == .verified) {
                            solved = true;
                            break;
                        } else if (res.verdict == .counter_example) {
                            defer allocator.free(res.detail);
                        }
                    },
                    .MDL_COMPRESS => {
                        if (current_best.used > 2) current_best.used -= 1;
                    },
                }
            }
        }

        const total_elapsed = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
        return if (solved) total_elapsed else max_time_ms + 1000;
    }
};

fn evaluateQuality(p: domain_alien.GraphProgram) f64 {
    var hits: f64 = 0;
    for (domain_base.test_cases.items) |tc| {
        if (p.execute(tc.x, tc.y) == tc.target) hits += 1.0;
    }
    return hits;
}
