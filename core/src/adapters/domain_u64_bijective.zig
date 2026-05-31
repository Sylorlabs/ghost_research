const std = @import("std");
const engine = @import("invention_engine");

pub const DOMAIN_NAME: []const u8 = "u64-bijective-arx";

pub const MaxProgLen = 24;
const MinProgLen = 4;
const FitSamples = 64;
const PeriodSamples = 4096;
const ChiSqSamples = 4096;

pub const Op = enum(u4) {
    ADD_IMM = 0,
    XOR_IMM = 1,
    SHR_XOR = 2,
    SHL_XOR = 3,
    ROTL = 4,
    ROTR = 5,
};

pub const Instruction = struct {
    op: Op,
    imm: u64,
};

pub const Program = struct {
    instructions: [MaxProgLen]Instruction,
    used: u8,

    pub fn execute(self: Program, input: u64) u64 {
        var x = input;
        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const inst = self.instructions[i];
            switch (inst.op) {
                .ADD_IMM => x +%= inst.imm,
                .XOR_IMM => x ^= inst.imm,
                .SHR_XOR => x ^= (x >> shift63(inst.imm)),
                .SHL_XOR => x ^= (x << shift63(inst.imm)),
                .ROTL => x = std.math.rotl(u64, x, shift63(inst.imm)),
                .ROTR => x = std.math.rotr(u64, x, shift63(inst.imm)),
            }
        }
        return x;
    }
};

pub const Quality = struct {
    avalanche: f64,
    chisq: f64,
    composite: f64,
};

fn shift63(imm: u64) u6 {
    return @as(u6, @intCast(imm % 63 + 1));
}

fn nextRand(rng: *u64) u64 {
    rng.* = engine.smix(rng.*);
    return rng.*;
}

fn randomInstr(rng: *u64) Instruction {
    const op: Op = @enumFromInt(nextRand(rng) % 6);
    return .{ .op = op, .imm = nextRand(rng) };
}

pub fn randomProgram(rng: *u64, max_len: u8) Program {
    const span = @as(u64, @intCast(max_len - MinProgLen + 1));
    const len: u8 = @intCast(MinProgLen + (nextRand(rng) % span));
    var p = Program{
        .instructions = [_]Instruction{.{ .op = .ADD_IMM, .imm = 0 }} ** MaxProgLen,
        .used = len,
    };
    var i: usize = 0;
    while (i < len) : (i += 1) p.instructions[i] = randomInstr(rng);
    return p;
}

pub fn mutate(p: Program, rng: *u64, max_len: u8) Program {
    var q = p;
    const draw = nextRand(rng) % 16;
    if (draw < 10) {
        const idx: usize = @intCast(nextRand(rng) % q.used);
        q.instructions[idx] = randomInstr(rng);
    } else if (draw < 13 and q.used < max_len) {
        const idx: usize = @intCast(nextRand(rng) % (q.used + 1));
        var i: usize = q.used;
        while (i > idx) : (i -= 1) q.instructions[i] = q.instructions[i - 1];
        q.instructions[idx] = randomInstr(rng);
        q.used += 1;
    } else if (q.used > MinProgLen) {
        const idx: usize = @intCast(nextRand(rng) % q.used);
        var i: usize = idx;
        while (i < q.used - 1) : (i += 1) q.instructions[i] = q.instructions[i + 1];
        q.used -= 1;
    } else {
        const idx: usize = @intCast(nextRand(rng) % q.used);
        q.instructions[idx].imm = nextRand(rng);
    }
    return q;
}

fn avalanche(p: Program) f64 {
    var total: f64 = 0;
    var samples: u64 = 0;
    var rng: u64 = 0xACE_F00D_BEEF_CAFE;
    var s: usize = 0;
    while (s < FitSamples) : (s += 1) {
        rng = engine.smix(rng);
        const x = rng;
        const y = p.execute(x);
        var bit: u6 = 0;
        while (true) {
            const y_flip = p.execute(x ^ (@as(u64, 1) << bit));
            total += @as(f64, @floatFromInt(@popCount(y ^ y_flip)));
            samples += 1;
            if (bit == 63) break;
            bit += 1;
        }
    }
    return total / @as(f64, @floatFromInt(samples));
}

fn chiSqFn(p: Program) f64 {
    var bins = [_]u32{0} ** 256;
    var rng: u64 = 0xDEAD_BEEF_BAD_F00D;
    var n: usize = 0;
    while (n < ChiSqSamples) : (n += 1) {
        rng = engine.smix(rng);
        bins[@intCast(p.execute(rng) & 0xFF)] += 1;
    }
    const expected = @as(f64, @floatFromInt(ChiSqSamples)) / 256.0;
    var cs: f64 = 0;
    for (bins) |count| {
        const d = @as(f64, @floatFromInt(count)) - expected;
        cs += (d * d) / expected;
    }
    return cs;
}

pub fn evaluateQuality(p: Program) Quality {
    const av = avalanche(p);
    const cs = chiSqFn(p);

    const av_err = @abs(av - 32.0);
    const cs_pen = if (cs > 255.0) (cs - 255.0) / 100.0 else 0.0;
    
    // Reward structural nonlinearity (ADD_IMM).
    var non_affine_count: usize = 0;
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        if (p.instructions[i].op == .ADD_IMM) non_affine_count += 1;
    }
    const non_affine_reward = @as(f64, @floatFromInt(non_affine_count)) * 20.0;

    const composite = -10.0 * av_err - cs_pen - @as(f64, @floatFromInt(p.used)) * 0.5 + non_affine_reward;

    return .{
        .avalanche = av,
        .chisq = cs,
        .composite = composite,
    };
}

pub fn programHash(p: Program) u64 {
    var h: u64 = 0xCBF29CE484222325;
    h ^= p.used;
    h *%= 0x100000001B3;
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        h ^= @intFromEnum(inst.op);
        h *%= 0x100000001B3;
        h ^= inst.imm;
        h *%= 0x100000001B3;
    }
    return h;
}

pub fn printProgram(p: Program, writer: anytype) !void {
    try writer.print("[arx] used={d} hash=0x{X}\n", .{ p.used, programHash(p) });
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        try writer.print("  [{d}] x = {s}(x, imm=0x{X:0>16})\n", .{
            i,
            @tagName(inst.op),
            inst.imm,
        });
    }
}

pub fn programToCsv(p: Program, writer: anytype) !void {
    try writer.writeAll("idx,op_name,imm_hex,used_len\n");
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        try writer.print("{d},{s},{X},{d}\n", .{
            i, @tagName(inst.op), inst.imm, p.used,
        });
    }
}