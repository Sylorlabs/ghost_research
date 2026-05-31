const std = @import("std");
const engine = @import("invention_engine");

pub const DOMAIN_NAME: []const u8 = "alien-hack-safe-average";

pub const MaxProgLen = 12;
const MinProgLen = 2;

pub const Op = enum(u4) {
    ADD = 0,
    SUB = 1,
    XOR = 2,
    AND = 3,
    OR = 4,
    SHR = 5,
};

pub const Instruction = struct {
    op: Op,
    dst: u3,
    src: u3,
    imm: u6,
};

pub const Dependency = struct {
    x: u64,
    y: u64,
};

pub const State = struct {
    r: [8]u64,
};

pub const SymbolicState = struct {
    r: [8]Dependency,
};

pub const Program = struct {
    instructions: [MaxProgLen]Instruction,
    used: u8,

    pub fn execute(self: Program, x: u64, y: u64) u64 {
        var state = State{ .r = .{ x, y, 0, 0, 0, 0, 0, 0 } };

        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const inst = self.instructions[i];
            const dst = inst.dst;
            const src = inst.src;
            switch (inst.op) {
                .ADD => state.r[dst] +%= state.r[src],
                .SUB => state.r[dst] -%= state.r[src],
                .XOR => state.r[dst] ^= state.r[src],
                .AND => state.r[dst] &= state.r[src],
                .OR  => state.r[dst] |= state.r[src],
                .SHR => state.r[dst] >>= inst.imm,
            }
        }
        return state.r[0]; // Result always in r0
    }

    pub fn executeSymbolic(self: Program) [64]Dependency {
        var state: SymbolicState = undefined;
        // Init: r0 depends on x, r1 depends on y
        var k: usize = 0;
        while (k < 8) : (k += 1) {
            state.r[k] = .{ .x = 0, .y = 0 };
        }
        // This is a bit-level trace, but to keep it fast, we track "word-level" dependency first.
        // For a more granular Tier 4, we'd need a 64x128 matrix per register.
        // Let's do the full bit-level matrix for the output register r0.

        var matrix: [64]Dependency = undefined;
        for (&matrix, 0..) |*d, b| {
            d.* = .{ .x = @as(u64, 1) << @as(u6, @intCast(b)), .y = @as(u64, 1) << @as(u6, @intCast(b)) };
        }
        // Actually, for the Alien Hack, we need to track how r0/r1 bits propagate.
        // Let's simplify: every bit of r0_in depends on x_i, r1_in depends on y_i.

        var reg_matrix: [8][64]Dependency = undefined;
        for (&reg_matrix) |*rm| {
            for (rm) |*d| d.* = .{ .x = 0, .y = 0 };
        }
        for (&reg_matrix[0], 0..) |*d, b| d.x = @as(u64, 1) << @as(u6, @intCast(b));
        for (&reg_matrix[1], 0..) |*d, b| d.y = @as(u64, 1) << @as(u6, @intCast(b));

        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const inst = self.instructions[i];
            const d = inst.dst;
            const s = inst.src;
            const imm = inst.imm;

            switch (inst.op) {
                .XOR, .AND, .OR => {
                    for (0..64) |b| {
                        reg_matrix[d][b].x |= reg_matrix[s][b].x;
                        reg_matrix[d][b].y |= reg_matrix[s][b].y;
                    }
                },
                .SHR => {
                    for (0..64) |b| {
                        if (b + imm < 64) {
                            reg_matrix[d][b] = reg_matrix[s][b + imm];
                        } else {
                            reg_matrix[d][b] = .{ .x = 0, .y = 0 };
                        }
                    }
                },
                .ADD, .SUB => {
                    var acc_x: u64 = 0;
                    var acc_y: u64 = 0;
                    for (0..64) |b| {
                        acc_x |= reg_matrix[d][b].x | reg_matrix[s][b].x;
                        acc_y |= reg_matrix[d][b].y | reg_matrix[s][b].y;
                        reg_matrix[d][b].x = acc_x;
                        reg_matrix[d][b].y = acc_y;
                    }
                },
            }
        }
        return reg_matrix[0];
    }
};
pub fn smix(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn nextRand(rng: *u64) u64 {
    rng.* = smix(rng.*);
    return rng.*;
}

pub fn randomInstr(rng: *u64) Instruction {
    return .{
        .op = @enumFromInt(nextRand(rng) % 6),
        .dst = @intCast(nextRand(rng) % 8),
        .src = @intCast(nextRand(rng) % 8),
        .imm = @intCast(nextRand(rng) % 64),
    };
}

pub fn randomProgram(rng: *u64) Program {
    const len: u8 = @intCast(MinProgLen + (nextRand(rng) % (MaxProgLen - MinProgLen + 1)));
    var p = Program{ .instructions = undefined, .used = len };
    var i: usize = 0;
    while (i < len) : (i += 1) p.instructions[i] = randomInstr(rng);
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
        q.instructions[idx] = randomInstr(rng);
        q.used += 1;
    } else {
        const idx = nextRand(rng) % @max(1, q.used);
        q.instructions[idx] = randomInstr(rng);
    }
    return q;
}

const TestCase = struct { x: u64, y: u64, target: u64 };

pub var test_cases: std.ArrayList(TestCase) = undefined;
var tests_initialized = false;

pub fn initTests(allocator: std.mem.Allocator) !void {
    if (tests_initialized) return;
    test_cases = std.ArrayList(TestCase).init(allocator);
    
    // Start with minimal test cases
    try test_cases.append(.{ .x = 10, .y = 20, .target = 15 });
    try test_cases.append(.{ .x = 100, .y = 200, .target = 150 });
    
    tests_initialized = true;
}

pub fn evaluateQuality(p: Program) f64 {
    var hits: f64 = 0;
    
    for (test_cases.items) |tc| {
        const res = p.execute(tc.x, tc.y);
        if (res == tc.target) {
            hits += 1.0;
        } else {
            const matching_bits = 64 - @popCount(res ^ tc.target);
            hits += @as(f64, @floatFromInt(matching_bits)) / 64.0;
        }
    }
    
    const target_hits = @as(f64, @floatFromInt(test_cases.items.len));
    if (hits >= target_hits - 0.0001) {
        return hits + 100.0 - @as(f64, @floatFromInt(p.used));
    }
    return hits;
}

pub fn printProgram(p: Program, writer: anytype) !void {
    try writer.print("used={d}\n", .{p.used});
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        if (inst.op == .SHR) {
            try writer.print("  [{d}] r{d} = SHR(r{d}, {d})\n", .{ i, inst.dst, inst.src, inst.imm });
        } else {
            try writer.print("  [{d}] r{d} = {s}(r{d}, r{d})\n", .{ i, inst.dst, @tagName(inst.op), inst.dst, inst.src });
        }
    }
}