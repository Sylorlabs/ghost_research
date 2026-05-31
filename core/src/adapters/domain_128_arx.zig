const std = @import("std");
const engine = @import("invention_engine");

pub const DOMAIN_NAME: []const u8 = "128-bit-arx-prng";

pub const MaxProgLen = 32;
const MinProgLen = 8;
const FitSamples = 64;
const ChiSqSamples = 4096;

pub const Op = enum(u4) {
    ADD_R0_R1 = 0,
    ADD_R1_R0 = 1,
    XOR_R0_R1 = 2,
    XOR_R1_R0 = 3,
    ROTL_R0 = 4,
    ROTL_R1 = 5,
    SHR_XOR_R0 = 6,
    SHR_XOR_R1 = 7,
    ADD_R0_IMM = 8,
    ADD_R1_IMM = 9,
    XOR_R0_IMM = 10,
    XOR_R1_IMM = 11,
};

pub const Instruction = struct {
    op: Op,
    imm: u64,
};

pub const State = struct {
    r0: u64,
    r1: u64,
};

pub const Program = struct {
    instructions: [MaxProgLen]Instruction,
    used: u8,

    pub fn execute(self: Program, state: State) State {
        var r0 = state.r0;
        var r1 = state.r1;
        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            const inst = self.instructions[i];
            switch (inst.op) {
                .ADD_R0_R1 => r0 +%= r1,
                .ADD_R1_R0 => r1 +%= r0,
                .XOR_R0_R1 => r0 ^= r1,
                .XOR_R1_R0 => r1 ^= r0,
                .ROTL_R0 => r0 = std.math.rotl(u64, r0, shift63(inst.imm)),
                .ROTL_R1 => r1 = std.math.rotl(u64, r1, shift63(inst.imm)),
                .SHR_XOR_R0 => r0 ^= (r0 >> shift63(inst.imm)),
                .SHR_XOR_R1 => r1 ^= (r1 >> shift63(inst.imm)),
                .ADD_R0_IMM => r0 +%= inst.imm,
                .ADD_R1_IMM => r1 +%= inst.imm,
                .XOR_R0_IMM => r0 ^= inst.imm,
                .XOR_R1_IMM => r1 ^= inst.imm,
            }
        }
        return .{ .r0 = r0, .r1 = r1 };
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
    const op: Op = @enumFromInt(nextRand(rng) % 12);
    return .{ .op = op, .imm = nextRand(rng) };
}

pub fn randomProgram(rng: *u64, max_len: u8) Program {
    const span = @as(u64, @intCast(max_len - MinProgLen + 1));
    const len: u8 = @intCast(MinProgLen + (nextRand(rng) % span));
    var p = Program{
        .instructions = [_]Instruction{.{ .op = .ADD_R0_R1, .imm = 0 }} ** MaxProgLen,
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

// Avalanche measures the 64-bit output (r0 ^ r1) response to 128-bit input flips. Target = 32.0
fn avalanche(p: Program) f64 {
    var total: f64 = 0;
    var samples: u64 = 0;
    var rng: u64 = 0xACE_F00D_BEEF_CAFE;
    var s: usize = 0;
    while (s < FitSamples) : (s += 1) {
        rng = engine.smix(rng);
        const x0 = rng;
        rng = engine.smix(rng);
        const x1 = rng;
        const out_base = p.execute(.{ .r0 = x0, .r1 = x1 });
        const mix_base = out_base.r0 ^ out_base.r1;
        
        var bit: u6 = 0;
        while (true) {
            const out_f0 = p.execute(.{ .r0 = x0 ^ (@as(u64, 1) << bit), .r1 = x1 });
            total += @as(f64, @floatFromInt(@popCount(mix_base ^ (out_f0.r0 ^ out_f0.r1))));
            samples += 1;
            if (bit == 63) break;
            bit += 1;
        }
        bit = 0;
        while (true) {
            const out_f1 = p.execute(.{ .r0 = x0, .r1 = x1 ^ (@as(u64, 1) << bit) });
            total += @as(f64, @floatFromInt(@popCount(mix_base ^ (out_f1.r0 ^ out_f1.r1))));
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
        const st = p.execute(.{ .r0 = rng, .r1 = engine.smix(rng) });
        bins[@intCast((st.r0 ^ st.r1) & 0xFF)] += 1;
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
    
    // Reward structural nonlinearity (ADD).
    var non_affine_count: usize = 0;
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        switch (p.instructions[i].op) {
            .ADD_R0_R1, .ADD_R1_R0, .ADD_R0_IMM, .ADD_R1_IMM => non_affine_count += 1,
            else => {},
        }
    }
    const non_affine_reward = @as(f64, @floatFromInt(non_affine_count)) * 20.0;

    const composite = -10.0 * av_err - cs_pen - @as(f64, @floatFromInt(p.used)) * 0.5 + non_affine_reward;

    return .{
        .avalanche = av,
        .chisq = cs,
        .composite = composite,
    };
}

pub fn printProgram(p: Program, writer: anytype) !void {
    try writer.print("[128_arx] used={d}\n", .{ p.used });
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        const inst = p.instructions[i];
        try writer.print("  [{d}] {s} (imm=0x{X:0>16})\n", .{
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