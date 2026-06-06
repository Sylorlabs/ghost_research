const std = @import("std");

pub const OpCode = enum(u8) {
    NOP = 0,
    SET_ALPHA = 1,
    SET_THRESHOLD = 2,
    MASK_SHIFT = 3,
    LOOP_JMP = 4,
};

pub const VMContext = struct {
    alpha: *f32,
    threshold: *f32,
    registers: [4]u8,
};

pub fn executeBytecode(ctx: *VMContext, bytecode: []const u8) void {
    var pc: usize = 0;
    while (pc < bytecode.len) {
        const op = bytecode[pc];
        pc += 1;
        switch (op) {
            0 => continue, // NOP
            1 => {
                // SET_ALPHA
                if (pc < bytecode.len) {
                    const val = bytecode[pc];
                    pc += 1;
                    ctx.alpha.* = @as(f32, @floatFromInt(val)) * 0.10;
                }
            },
            2 => {
                // SET_THRESHOLD
                if (pc < bytecode.len) {
                    const val = bytecode[pc];
                    pc += 1;
                    ctx.threshold.* = @as(f32, @floatFromInt(val)) * 0.05;
                }
            },
            3 => {
                // MASK_SHIFT
                if (pc < bytecode.len) {
                    ctx.registers[0] = bytecode[pc];
                    pc += 1;
                }
            },
            4 => {
                // LOOP_JMP
                if (pc < bytecode.len) {
                    const tgt = bytecode[pc];
                    pc += 1;
                    if (ctx.registers[0] > 0) {
                        ctx.registers[0] -= 1;
                        pc = tgt;
                    }
                }
            },
            else => {},
        }
    }
}
