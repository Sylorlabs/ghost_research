const std = @import("std");

pub const DOMAIN_NAME: []const u8 = "general-stack-machine";

pub const MaxProgLen = 16;
pub const MaxConceptLen = 8;
pub const NumConcepts = 8;
pub const StackSize = 16;

pub const Op = enum(u4) {
    INC = 0,
    DEC = 1,
    DUP = 2,
    DROP = 3,
    SWAP = 4,
    ADD = 5,
    SUB = 6,
    CALL_CONCEPT = 7,
};

pub const Instruction = struct {
    op: Op,
    concept_idx: u3,
};

pub const State = struct {
    stack: [StackSize]u64,
    sp: usize,
    
    pub fn push(self: *State, val: u64) void {
        if (self.sp < StackSize) {
            self.stack[self.sp] = val;
            self.sp += 1;
        }
    }
    
    pub fn pop(self: *State) u64 {
        if (self.sp > 0) {
            self.sp -= 1;
            return self.stack[self.sp];
        }
        return 0; // Underflow protection (acts like 0 is always at bottom)
    }
};

pub const Concept = struct {
    instructions: [MaxConceptLen]Instruction,
    used: u8,
};

pub const System = struct {
    concepts: [NumConcepts]Concept,
    concepts_used: u8,
};

pub const Program = struct {
    instructions: [MaxProgLen]Instruction,
    used: u8,

    pub fn execute(self: Program, sys: System, input: u64) u64 {
        var state = State{ .stack = undefined, .sp = 0 };
        state.push(input);
        
        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const inst = self.instructions[i];
            switch (inst.op) {
                .INC => { const a = state.pop(); state.push(a +% 1); },
                .DEC => { const a = state.pop(); state.push(a -% 1); },
                .DUP => { const a = state.pop(); state.push(a); state.push(a); },
                .DROP => { _ = state.pop(); },
                .SWAP => { const a = state.pop(); const b = state.pop(); state.push(a); state.push(b); },
                .ADD => { const a = state.pop(); const b = state.pop(); state.push(b +% a); },
                .SUB => { const a = state.pop(); const b = state.pop(); state.push(b -% a); },
                .CALL_CONCEPT => {
                    if (inst.concept_idx < sys.concepts_used) {
                        const c = sys.concepts[inst.concept_idx];
                        var j: usize = 0;
                        while (j < c.used) : (j += 1) {
                            const cinst = c.instructions[j];
                            switch (cinst.op) {
                                .INC => { const a = state.pop(); state.push(a +% 1); },
                                .DEC => { const a = state.pop(); state.push(a -% 1); },
                                .DUP => { const a = state.pop(); state.push(a); state.push(a); },
                                .DROP => { _ = state.pop(); },
                                .SWAP => { const a = state.pop(); const b = state.pop(); state.push(a); state.push(b); },
                                .ADD => { const a = state.pop(); const b = state.pop(); state.push(b +% a); },
                                .SUB => { const a = state.pop(); const b = state.pop(); state.push(b -% a); },
                                .CALL_CONCEPT => {}, // No deep recursion to keep it simple and fast
                            }
                        }
                    }
                }
            }
        }
        return state.pop(); // Result is top of stack
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

pub fn randomInstr(rng: *u64, sys: System) Instruction {
    var op_max: u64 = 7;
    if (sys.concepts_used > 0) op_max = 8; // allow CALL_CONCEPT if concepts exist
    
    const op: Op = @enumFromInt(nextRand(rng) % op_max);
    var cidx: u3 = 0;
    if (sys.concepts_used > 0) {
        cidx = @intCast(nextRand(rng) % sys.concepts_used);
    }
    return .{ .op = op, .concept_idx = cidx };
}

pub fn randomProgram(rng: *u64, sys: System) Program {
    const len: u8 = @intCast(1 + (nextRand(rng) % 6));
    var p = Program{ .instructions = undefined, .used = len };
    var i: usize = 0;
    while (i < len) : (i += 1) p.instructions[i] = randomInstr(rng, sys);
    return p;
}

pub fn mutateProgram(p: Program, rng: *u64, sys: System) Program {
    var q = p;
    const draw = nextRand(rng) % 16;
    if (draw < 6 and q.used > 1) {
        q.used -= 1;
    } else if (draw < 10 and q.used < MaxProgLen) {
        const idx = nextRand(rng) % (q.used + 1);
        var i: usize = q.used;
        while (i > idx) : (i -= 1) q.instructions[i] = q.instructions[i - 1];
        q.instructions[idx] = randomInstr(rng, sys);
        q.used += 1;
    } else {
        const idx = nextRand(rng) % @max(1, q.used);
        q.instructions[idx] = randomInstr(rng, sys);
    }
    return q;
}

pub fn printProgram(p: Program, writer: anytype) !void {
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        if (inst.op == .CALL_CONCEPT) {
            try writer.print(" CALL_C{d}", .{inst.concept_idx});
        } else {
            try writer.print(" {s}", .{@tagName(inst.op)});
        }
    }
    try writer.print("\n", .{});
}