const std = @import("std");

pub const DOMAIN_NAME: []const u8 = "symbolic-arx-tracing";

pub const MaxProgLen = 32;

pub const Op = enum(u4) {
    XOR = 0,
    ADD = 1,
    ROTL = 2,
    SHL_XOR = 3,
    SHR_XOR = 4,
};

pub const Instruction = struct {
    op: Op,
    imm: u64, // Used for shifts/rotates or immediate arithmetic
};

// A 64x64 boolean dependency matrix.
// row[i] represents output bit `i`.
// If row[i] has bit `j` set, it means output bit `i` depends on input bit `j`.
pub const DependencyMatrix = struct {
    rows: [64]u64,

    pub fn initIdentity() DependencyMatrix {
        var m: DependencyMatrix = undefined;
        var i: usize = 0;
        while (i < 64) : (i += 1) {
            m.rows[i] = @as(u64, 1) << @as(u6, @intCast(i));
        }
        return m;
    }

    pub fn popcount(self: DependencyMatrix) usize {
        var total: usize = 0;
        for (self.rows) |row| {
            total += @popCount(row);
        }
        return total;
    }

    // Mathematical distance to a target matrix (Hamming distance)
    pub fn distance(self: DependencyMatrix, target: DependencyMatrix) usize {
        var dist: usize = 0;
        var i: usize = 0;
        while (i < 64) : (i += 1) {
            dist += @popCount(self.rows[i] ^ target.rows[i]);
        }
        return dist;
    }
};

pub const Program = struct {
    instructions: [MaxProgLen]Instruction,
    used: u8,

    // The Tier 4 Abstract Interpreter
    // Instead of computing numbers, it computes the structural dependency of the bits.
    pub fn executeSymbolic(self: Program) DependencyMatrix {
        var state = DependencyMatrix.initIdentity();
        
        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const inst = self.instructions[i];
            const imm6: u6 = @intCast(inst.imm % 64);
            
            switch (inst.op) {
                .XOR => {
                    // x ^= imm (Immediate XOR does not change data dependency from input, only flips the bit value)
                    // Structural dependency remains identical.
                },
                .ROTL => {
                    var next_state: DependencyMatrix = undefined;
                    var b: usize = 0;
                    while (b < 64) : (b += 1) {
                        const src_bit = (b + 64 - imm6) % 64;
                        next_state.rows[b] = state.rows[src_bit];
                    }
                    state = next_state;
                },
                .SHL_XOR => {
                    var next_state = state;
                    var b: usize = 0;
                    while (b < 64) : (b += 1) {
                        if (b >= imm6) {
                            next_state.rows[b] |= state.rows[b - imm6];
                        }
                    }
                    state = next_state;
                },
                .SHR_XOR => {
                    var next_state = state;
                    var b: usize = 0;
                    while (b < 64) : (b += 1) {
                        if (b + imm6 < 64) {
                            next_state.rows[b] |= state.rows[b + imm6];
                        }
                    }
                    state = next_state;
                },
                .ADD => {
                    // ADD with immediate: x +% imm.
                    // An addition propagates a carry chain upwards.
                    // Output bit i depends on input bit i, AND potentially all input bits j < i (due to carry).
                    // In a worst-case symbolic trace, we assume the carry CAN propagate.
                    var next_state = state;
                    var accumulated_dep: u64 = 0;
                    var b: usize = 0;
                    while (b < 64) : (b += 1) {
                        accumulated_dep |= state.rows[b]; // The carry accumulates dependencies from lower bits
                        next_state.rows[b] |= accumulated_dep;
                    }
                    state = next_state;
                },
            }
        }
        return state;
    }
};

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

pub fn randomProgram(rng: *u64, len: u8) Program {
    var p = Program{ .instructions = undefined, .used = len };
    var i: usize = 0;
    while (i < len) : (i += 1) {
        p.instructions[i] = .{
            .op = @enumFromInt(nextRand(rng) % 5),
            .imm = nextRand(rng),
        };
    }
    return p;
}

pub fn mutate(p: Program, rng: *u64) Program {
    var q = p;
    const draw = nextRand(rng) % 16;
    if (draw < 4 and q.used > 1) {
        q.used -= 1;
    } else if (draw < 8 and q.used < MaxProgLen) {
        const idx = nextRand(rng) % (q.used + 1);
        var i: usize = q.used;
        while (i > idx) : (i -= 1) q.instructions[i] = q.instructions[i - 1];
        q.instructions[idx] = .{ .op = @enumFromInt(nextRand(rng) % 5), .imm = nextRand(rng) };
        q.used += 1;
    } else {
        const idx = nextRand(rng) % @max(1, q.used);
        q.instructions[idx] = .{ .op = @enumFromInt(nextRand(rng) % 5), .imm = nextRand(rng) };
    }
    return q;
}

pub fn printProgram(p: Program, writer: anytype) !void {
    try writer.print("used={d}\n", .{p.used});
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        try writer.print("  [{d}] {s} (imm=0x{X})\n", .{ i, @tagName(inst.op), inst.imm });
    }
}