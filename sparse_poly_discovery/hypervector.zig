const std = @import("std");

pub const D: usize = 8192;
pub const Blocks: usize = 128;
pub const Hypervector = [Blocks]u64;

pub fn initRandom(rand: std.Random) Hypervector {
    var arr: [Blocks]u64 = undefined;
    for (&arr) |*block| {
        block.* = rand.int(u64);
    }
    return arr;
}

pub inline fn bind(a: Hypervector, b: Hypervector) Hypervector {
    const va: @Vector(Blocks, u64) = a;
    const vb: @Vector(Blocks, u64) = b;
    const res: [Blocks]u64 = va ^ vb;
    return res;
}

pub inline fn permute(a: Hypervector, shift: usize) Hypervector {
    const shift_amt = @as(u6, @intCast(shift % 64));
    if (shift_amt == 0) return a;
    
    var result: [Blocks]u64 = undefined;
    for (0..Blocks) |i| {
        result[i] = std.math.rotl(u64, a[i], shift_amt);
    }
    return result;
}

pub inline fn inversePermute(a: Hypervector, shift: usize) Hypervector {
    const shift_amt = @as(u6, @intCast(shift % 64));
    if (shift_amt == 0) return a;
    
    var result: [Blocks]u64 = undefined;
    for (0..Blocks) |i| {
        result[i] = std.math.rotr(u64, a[i], shift_amt);
    }
    return result;
}

pub inline fn bundle3(a: Hypervector, b: Hypervector, c: Hypervector) Hypervector {
    // Majority vote for 3 vectors simulates vector addition (superposition)
    const va: @Vector(Blocks, u64) = a;
    const vb: @Vector(Blocks, u64) = b;
    const vc: @Vector(Blocks, u64) = c;
    const res: [Blocks]u64 = (va & vb) | (vb & vc) | (va & vc);
    return res;
}

pub inline fn hammingDistance(a: Hypervector, b: Hypervector) f32 {
    const va: @Vector(Blocks, u64) = a;
    const vb: @Vector(Blocks, u64) = b;
    const xor_res = va ^ vb;
    const popcounts = @popCount(xor_res);
    const popcounts_u32: @Vector(Blocks, u32) = popcounts;
    const diff_bits = @reduce(.Add, popcounts_u32);
    return @as(f32, @floatFromInt(diff_bits)) / @as(f32, @floatFromInt(D));
}

pub inline fn maskedDistance(a: Hypervector, b: Hypervector, mask: Hypervector) f32 {
    const va: @Vector(Blocks, u64) = a;
    const vb: @Vector(Blocks, u64) = b;
    const vmask: @Vector(Blocks, u64) = mask;
    const xor_res = (va ^ vb) & vmask;
    const popcounts = @popCount(xor_res);
    const popcounts_u32: @Vector(Blocks, u32) = popcounts;
    const diff_bits = @reduce(.Add, popcounts_u32);
    
    const active_bits = @reduce(.Add, @as(@Vector(Blocks, u32), @popCount(vmask)));
    if (active_bits == 0) return 0.0;
    return @as(f32, @floatFromInt(diff_bits)) / @as(f32, @floatFromInt(active_bits));
}

pub inline fn bundle(a: Hypervector, b: Hypervector, tiebreaker: Hypervector) Hypervector {
    const va: @Vector(Blocks, u64) = a;
    const vb: @Vector(Blocks, u64) = b;
    const vt: @Vector(Blocks, u64) = tiebreaker;
    
    // Majority rule using tiebreaker for ties
    const res: [Blocks]u64 = (va & vb) | (va & vt) | (vb & vt);
    return res;
}
