const std = @import("std");
const engine = @import("invention_engine");

pub const DOMAIN_NAME: []const u8 = "128-bit-tier4-concept";

pub const MaxProgLen = 24;
pub const MaxConceptLen = 8;
pub const NumConcepts = 4;
const FitSamples = 64;

pub const Op = enum(u4) {
    ADD_R0_R1 = 0,
    ADD_R1_R0 = 1,
    XOR_R0_R1 = 2,
    XOR_R1_R0 = 3,
    ROTL_R0 = 4,
    ROTL_R1 = 5,
    CALL_CONCEPT = 6, // Tier 4 enabler
};

pub const Instruction = struct {
    op: Op,
    imm: u64,
    concept_idx: u2, // which concept to call if op == CALL_CONCEPT
};

pub const State = struct {
    r0: u64,
    r1: u64,
};

pub const Program = struct {
    instructions: [MaxProgLen]Instruction,
    used: u8,
};

pub const Concept = struct {
    instructions: [MaxConceptLen]Instruction,
    used: u8,
};

pub const System = struct {
    main: Program,
    concepts: [NumConcepts]Concept,

    pub fn execute(self: System, state: State) State {
        var r0 = state.r0;
        var r1 = state.r1;
        var i: usize = 0;
        while (i < self.main.used) : (i += 1) {
            const inst = self.main.instructions[i];
            if (inst.op == .CALL_CONCEPT) {
                const c = self.concepts[inst.concept_idx];
                var j: usize = 0;
                while (j < c.used) : (j += 1) {
                    const cinst = c.instructions[j];
                    switch (cinst.op) {
                        .ADD_R0_R1 => r0 +%= r1,
                        .ADD_R1_R0 => r1 +%= r0,
                        .XOR_R0_R1 => r0 ^= r1,
                        .XOR_R1_R0 => r1 ^= r0,
                        .ROTL_R0 => r0 = std.math.rotl(u64, r0, shift63(cinst.imm)),
                        .ROTL_R1 => r1 = std.math.rotl(u64, r1, shift63(cinst.imm)),
                        .CALL_CONCEPT => {}, // Prevent infinite recursion; concepts cannot call concepts
                    }
                }
            } else {
                switch (inst.op) {
                    .ADD_R0_R1 => r0 +%= r1,
                    .ADD_R1_R0 => r1 +%= r0,
                    .XOR_R0_R1 => r0 ^= r1,
                    .XOR_R1_R0 => r1 ^= r0,
                    .ROTL_R0 => r0 = std.math.rotl(u64, r0, shift63(inst.imm)),
                    .ROTL_R1 => r1 = std.math.rotl(u64, r1, shift63(inst.imm)),
                    .CALL_CONCEPT => unreachable,
                }
            }
        }
        return .{ .r0 = r0, .r1 = r1 };
    }
};

pub const Quality = struct {
    avalanche: f64,
    ast_size: usize,
    composite: f64,
};

fn shift63(imm: u64) u6 {
    return @as(u6, @intCast(imm % 63 + 1));
}

fn nextRand(rng: *u64) u64 {
    rng.* = engine.smix(rng.*);
    return rng.*;
}

fn randomInstr(rng: *u64, allow_call: bool) Instruction {
    const op_max: u64 = if (allow_call) 7 else 6;
    const op: Op = @enumFromInt(nextRand(rng) % op_max);
    return .{ 
        .op = op, 
        .imm = nextRand(rng),
        .concept_idx = @intCast(nextRand(rng) % NumConcepts),
    };
}

pub fn randomSystem(rng: *u64) System {
    var sys: System = undefined;
    
    // Init main
    sys.main.used = @intCast(4 + (nextRand(rng) % 12));
    var i: usize = 0;
    while (i < MaxProgLen) : (i += 1) sys.main.instructions[i] = randomInstr(rng, true);
    
    // Init concepts
    var c: usize = 0;
    while (c < NumConcepts) : (c += 1) {
        sys.concepts[c].used = @intCast(1 + (nextRand(rng) % 4));
        var j: usize = 0;
        while (j < MaxConceptLen) : (j += 1) sys.concepts[c].instructions[j] = randomInstr(rng, false);
    }
    
    return sys;
}

pub fn mutate(sys: System, rng: *u64) System {
    var q = sys;
    const draw = nextRand(rng) % 16;
    
    if (draw < 8) {
        // Mutate main program
        const mdraw = nextRand(rng) % 4;
        if (mdraw == 0 and q.main.used > 1) {
            q.main.used -= 1;
        } else if (mdraw == 1 and q.main.used < MaxProgLen) {
            q.main.used += 1;
        } else {
            const idx = nextRand(rng) % @max(1, q.main.used);
            q.main.instructions[idx] = randomInstr(rng, true);
        }
    } else {
        // Mutate a concept
        const c_idx = nextRand(rng) % NumConcepts;
        const cdraw = nextRand(rng) % 4;
        if (cdraw == 0 and q.concepts[c_idx].used > 1) {
            q.concepts[c_idx].used -= 1;
        } else if (cdraw == 1 and q.concepts[c_idx].used < MaxConceptLen) {
            q.concepts[c_idx].used += 1;
        } else {
            const idx = nextRand(rng) % @max(1, q.concepts[c_idx].used);
            q.concepts[c_idx].instructions[idx] = randomInstr(rng, false);
        }
    }
    return q;
}

fn avalanche(sys: System) f64 {
    var total: f64 = 0;
    var samples: u64 = 0;
    var rng: u64 = 0xACE_F00D_BEEF_CAFE;
    var s: usize = 0;
    while (s < FitSamples) : (s += 1) {
        rng = engine.smix(rng);
        const x0 = rng;
        rng = engine.smix(rng);
        const x1 = rng;
        const out_base = sys.execute(.{ .r0 = x0, .r1 = x1 });
        const mix_base = out_base.r0 ^ out_base.r1;
        
        var bit: u6 = 0;
        while (true) {
            const out_f0 = sys.execute(.{ .r0 = x0 ^ (@as(u64, 1) << bit), .r1 = x1 });
            total += @as(f64, @floatFromInt(@popCount(mix_base ^ (out_f0.r0 ^ out_f0.r1))));
            samples += 1;
            if (bit == 63) break;
            bit += 1;
        }
    }
    return total / @as(f64, @floatFromInt(samples));
}

pub fn evaluateQuality(sys: System) Quality {
    const av = avalanche(sys);
    const av_err = @abs(av - 32.0);
    
    // Calculate AST Size (MDL compression pressure)
    // Only count concepts that are actually called! This drives the engine to use them.
    var ast_size: usize = sys.main.used;
    var concept_called = [_]bool{false} ** NumConcepts;
    
    var i: usize = 0;
    while (i < sys.main.used) : (i += 1) {
        if (sys.main.instructions[i].op == .CALL_CONCEPT) {
            concept_called[sys.main.instructions[i].concept_idx] = true;
        }
    }
    
    var c: usize = 0;
    while (c < NumConcepts) : (c += 1) {
        if (concept_called[c]) {
            ast_size += sys.concepts[c].used;
        }
    }
    
    // Base composite
    var composite = -10.0 * av_err;
    
    // Huge reward for achieving high avalanche with a small AST
    // If it gets avalanche > 30, it gets a massive bonus for small size.
    if (av > 30.0) {
        composite += 1000.0 - @as(f64, @floatFromInt(ast_size)) * 20.0;
    } else {
        composite -= @as(f64, @floatFromInt(ast_size));
    }

    return .{ 
        .avalanche = av, 
        .ast_size = ast_size, 
        .composite = composite, 
    };
}

pub fn printSystem(sys: System, writer: anytype) !void {
    var concept_called = [_]bool{false} ** NumConcepts;
    var i: usize = 0;
    while (i < sys.main.used) : (i += 1) {
        if (sys.main.instructions[i].op == .CALL_CONCEPT) {
            concept_called[sys.main.instructions[i].concept_idx] = true;
        }
    }
    
    // Print used concepts
    var c: usize = 0;
    while (c < NumConcepts) : (c += 1) {
        if (concept_called[c]) {
            try writer.print("Concept {d} (used={d}):\n", .{ c, sys.concepts[c].used });
            var j: usize = 0;
            while (j < sys.concepts[c].used) : (j += 1) {
                const inst = sys.concepts[c].instructions[j];
                try writer.print("  [{d}] {s} (imm=0x{X:0>16})\n", .{ j, @tagName(inst.op), inst.imm });
            }
        }
    }
    
    try writer.print("\nMain Program (used={d}):\n", .{ sys.main.used });
    i = 0;
    while (i < sys.main.used) : (i += 1) {
        const inst = sys.main.instructions[i];
        if (inst.op == .CALL_CONCEPT) {
            try writer.print("  [{d}] CALL_CONCEPT {d}\n", .{ i, inst.concept_idx });
        } else {
            try writer.print("  [{d}] {s} (imm=0x{X:0>16})\n", .{ i, @tagName(inst.op), inst.imm });
        }
    }
}