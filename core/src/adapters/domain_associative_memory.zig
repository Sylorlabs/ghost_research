const std = @import("std");
const engine = @import("invention_engine");
const domain_base = @import("domain_alien_hack");

pub const DOMAIN_NAME: []const u8 = "linear-associative-memory";

pub const MaxProgLen = 16;
const SequenceLength = 64; // Test memory persistence over 64 steps
const StateSize = 2; // Two u64 registers for state (128 bits)

pub const Op = enum(u4) {
    ADD = 0,
    XOR = 1,
    AND = 2,
    OR  = 3,
    ROTL = 4,
    SHL_XOR = 5,
};

pub const Instruction = struct {
    op: Op,
    dst: u1,
    src: u1,
    imm: u6,
};

pub const Program = struct {
    instructions: [MaxProgLen]Instruction,
    used: u8,

    // h_t = f(h_{t-1}, x_t)
    // We treat the current input as x_t and the registers as h_{t-1}
    pub fn step(self: Program, h: *[2]u64, x: u64) void {
        // Feed input into r1
        h[1] ^= x;
        
        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const inst = self.instructions[i];
            const d = inst.dst;
            const s = inst.src;
            switch (inst.op) {
                .ADD => h[d] +%= h[s],
                .XOR => h[d] ^= h[s],
                .AND => h[d] &= h[s],
                .OR  => h[d] |= h[s],
                .ROTL => h[d] = std.math.rotl(u64, h[d], inst.imm),
                .SHL_XOR => h[d] ^= (h[d] << inst.imm),
            }
        }
    }
};

// Fitness: Can we retrieve a specific value that was seen 64 steps ago?
pub fn evaluateQuality(p: Program) f64 {
    var hits: f64 = 0;
    var rng: u64 = 0x1337_BEEF;

    var s: usize = 0;
    while (s < 32) : (s += 1) {
        var h = [_]u64{ 0, 0 };
        
        // 1. Generate random sequence
        rng = domain_base.smix(rng);
        const secret_idx = rng % (SequenceLength - 5);
        const secret_val = domain_base.smix(rng);
        
        var t: usize = 0;
        while (t < SequenceLength) : (t += 1) {
            rng = domain_base.smix(rng);
            const input = if (t == secret_idx) secret_val else rng;
            p.step(&h, input);
        }
        
        // 2. Retrieval Phase: Provide a trigger (e.g., zero input) and see if h contains secret
        p.step(&h, 0); 
        
        // Check if either h[0] or h[1] has high correlation with secret_val
        // (In a real invention, we'd add a specialized 'Read' program, but let's keep it simple)
        const match0 = 64 - @popCount(h[0] ^ secret_val);
        const match1 = 64 - @popCount(h[1] ^ secret_val);
        const best_match = @max(match0, match1);
        
        hits += @as(f64, @floatFromInt(best_match)) / 64.0;
    }
    
    return (hits / 32.0) * 100.0;
}

pub fn printProgram(p: Program, writer: anytype) !void {
    try writer.print("used={d}\n", .{p.used});
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        try writer.print("  [{d}] r{d} = {s}(r{d}, r{d}, imm={d})\n", .{ i, inst.dst, @tagName(inst.op), inst.dst, inst.src, inst.imm });
    }
}