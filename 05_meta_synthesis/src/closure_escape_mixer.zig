//! Closure-escape demonstration in the mixer (program-synthesis) domain.
//!
//! The SAME hill-climber searches for a good u64 mixer two ways: MUL-free
//! (GF(2)-affine op set) vs MUL-enabled, optimising the project's composite
//! fitness. We then measure two statistics of each champion:
//!
//!   mean avalanche  : mean #output-bits flipped per input-bit flip (ideal 32).
//!   SAC error       : mean over all 64x64 (input-bit, output-bit) pairs of
//!                     |P(flip) - 0.5| (ideal 0). The STRICT avalanche criterion.
//!
//! EXP-21 (D30): at fixed program length, compare single nonlinear generators
//! (AND_NOT, MUM, ADD_ROT, ADD, MUL) atop a shared GF(2)-affine base.
//!
//! Run: build core ReleaseFast, then ./zig-out/bin/closure_escape_mixer
const std = @import("std");
const mixer = @import("domain_u64_mixer");

const OpId = u4;
const AffineOps = [_]OpId{ 0, 3, 4, 5, 9, 11, 12 }; // XOR ROTL SHL_XOR SHR_XOR OR_SHIFT ROTR BSWAP
const FixedLen: u8 = 8;
const NumRegs: u3 = 7; // dst index for output register (NumRegs-1 in domain)

fn smix(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn opFromId(id: OpId) @TypeOf((mixer.Program{ .instructions = undefined, .used = 0 }).instructions[0].op) {
    return @enumFromInt(id);
}

fn randomInstr(rng: *u64, allowed: []const OpId) @TypeOf((mixer.Program{ .instructions = undefined, .used = 0 }).instructions[0]) {
    rng.* = smix(rng.*);
    const op_id = allowed[@intCast(rng.* % allowed.len)];
    rng.* = smix(rng.*);
    const dst: u3 = @intCast(rng.* % 8);
    rng.* = smix(rng.*);
    const src1: u3 = @intCast(rng.* % 8);
    rng.* = smix(rng.*);
    const src2: u3 = @intCast(rng.* % 8);
    rng.* = smix(rng.*);
    return .{ .op = opFromId(op_id), .dst = dst, .src1 = src1, .src2 = src2, .imm = rng.* };
}

fn randomProgramFixed(rng: *u64, allowed: []const OpId, len: u8) mixer.Program {
    var p = mixer.Program{ .instructions = undefined, .used = len };
    var i: usize = 0;
    while (i < len) : (i += 1) p.instructions[i] = randomInstr(rng, allowed);
    p.instructions[len - 1].dst = NumRegs;
    return p;
}

fn mutateFixed(p: mixer.Program, rng: *u64, allowed: []const OpId, len: u8) mixer.Program {
    var q = p;
    q.used = len;
    rng.* = smix(rng.*);
    const mode = rng.* % 16;
    if (mode < 12) {
        rng.* = smix(rng.*);
        const idx: usize = rng.* % len;
        q.instructions[idx] = randomInstr(rng, allowed);
    } else {
        rng.* = smix(rng.*);
        const idx: usize = rng.* % len;
        rng.* = smix(rng.*);
        q.instructions[idx].imm = rng.*;
        rng.* = smix(rng.*);
        q.instructions[idx].dst = @intCast(rng.* % 8);
        rng.* = smix(rng.*);
        q.instructions[idx].src1 = @intCast(rng.* % 8);
        rng.* = smix(rng.*);
        q.instructions[idx].src2 = @intCast(rng.* % 8);
    }
    q.instructions[len - 1].dst = NumRegs;
    return q;
}

fn hillClimbFixed(seed: u64, iters: usize, allowed: []const OpId, len: u8) mixer.Program {
    var rng: u64 = seed;
    var best = randomProgramFixed(&rng, allowed, len);
    var best_q = mixer.qualityScalar(mixer.evaluateQuality(best));
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const cand = mutateFixed(best, &rng, allowed, len);
        const q = mixer.qualityScalar(mixer.evaluateQuality(cand));
        if (q > best_q) {
            best = cand;
            best_q = q;
        }
    }
    return best;
}

fn hillClimb(seed: u64, iters: usize) mixer.Program {
    var rng: u64 = seed;
    var best = mixer.randomProgram(&rng);
    var best_q = mixer.qualityScalar(mixer.evaluateQuality(best));
    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const cand = mixer.mutate(best, &rng);
        const q = mixer.qualityScalar(mixer.evaluateQuality(cand));
        if (q > best_q) {
            best = cand;
            best_q = q;
        }
    }
    return best;
}

// Strict avalanche criterion error: mean over 64x64 (in,out) bit pairs of
// |P(output bit j flips when input bit i flips) - 0.5|. Ideal mixer -> ~0.
// Affine map -> ~0.5 (every flip is deterministic).
fn sacError(p: mixer.Program, samples: usize, seed: u64) f64 {
    var counts: [64][64]u32 = undefined;
    for (&counts) |*row| @memset(row, 0);
    var rng: u64 = seed;
    var s: usize = 0;
    while (s < samples) : (s += 1) {
        rng = smix(rng);
        const x = rng;
        const y = p.execute(x);
        var i: usize = 0;
        while (i < 64) : (i += 1) {
            const yf = p.execute(x ^ (@as(u64, 1) << @intCast(i)));
            const diff = y ^ yf;
            var j: usize = 0;
            while (j < 64) : (j += 1) {
                counts[i][j] += @intCast((diff >> @intCast(j)) & 1);
            }
        }
    }
    var err: f64 = 0;
    const ns: f64 = @floatFromInt(samples);
    for (0..64) |i| {
        for (0..64) |j| {
            const pij = @as(f64, @floatFromInt(counts[i][j])) / ns;
            err += @abs(pij - 0.5);
        }
    }
    return err / 4096.0;
}

// Mean avalanche (first-order): mean output-bit flips per input-bit flip.
fn meanAvalanche(p: mixer.Program, samples: usize, seed: u64) f64 {
    var total: f64 = 0;
    var rng: u64 = seed;
    var s: usize = 0;
    while (s < samples) : (s += 1) {
        rng = smix(rng);
        const x = rng;
        const y = p.execute(x);
        var i: usize = 0;
        while (i < 64) : (i += 1) {
            const yf = p.execute(x ^ (@as(u64, 1) << @intCast(i)));
            total += @floatFromInt(@popCount(y ^ yf));
        }
    }
    return total / (@as(f64, @floatFromInt(samples)) * 64.0);
}

const LegacyMode = struct { name: []const u8, ban: bool };

const Exp21Mode = struct {
    name: []const u8,
    allowed: []const OpId,
};

fn affinePlus(comptime extra: OpId) [AffineOps.len + 1]OpId {
    var ops: [AffineOps.len + 1]OpId = undefined;
    @memcpy(ops[0..AffineOps.len], AffineOps[0..]);
    ops[AffineOps.len] = extra;
    return ops;
}

const AffinePlusAdd = affinePlus(1);
const AffinePlusAndNot = affinePlus(8);
const AffinePlusAddRot = affinePlus(14);
const AffinePlusMum = affinePlus(13);
const AffinePlusMul = affinePlus(2);

fn runExp21(out: anytype, iters: usize, seeds: usize, sac_samples: usize) !f64 {
    const modes = [_]Exp21Mode{
        .{ .name = "affine-only", .allowed = AffineOps[0..] },
        .{ .name = "affine+ADD", .allowed = AffinePlusAdd[0..] },
        .{ .name = "affine+AND_NOT", .allowed = AffinePlusAndNot[0..] },
        .{ .name = "affine+ADD_ROT", .allowed = AffinePlusAddRot[0..] },
        .{ .name = "affine+MUM", .allowed = AffinePlusMum[0..] },
        .{ .name = "affine+MUL", .allowed = AffinePlusMul[0..] },
    };

    try out.print("\n=== EXP-21 (D30): single nonlinear op @ fixed len {d} ===\n", .{FixedLen});
    try out.print("Fitness: composite (same hill-climber as legacy). {d} iters x {d} seeds.\n", .{ iters, seeds });
    try out.print("SAC measured with {d} samples/champion. Ideal SAC-error=0; affine ceiling=0.5.\n\n", .{sac_samples});
    try out.print("  mode              | mean av | mean SAC-err | best SAC-err\n", .{});
    try out.print("  ------------------+---------+--------------+-------------\n", .{});

    var mul_best_sac: f64 = 1e9;
    var best_non_mul_sac: f64 = 1e9;
    const non_mul_names = [_][]const u8{ "affine+ADD", "affine+AND_NOT", "affine+ADD_ROT", "affine+MUM" };

    for (modes) |m| {
        var sum_av: f64 = 0;
        var sum_sac: f64 = 0;
        var best_sac: f64 = 1e9;
        for (0..seeds) |s| {
            const champ = hillClimbFixed(
                0xE021 +% @as(u64, s) *% 0x9E3779B97F4A7C15,
                iters,
                m.allowed,
                FixedLen,
            );
            sum_av += meanAvalanche(champ, sac_samples, 0xA5A5 +% @as(u64, s));
            const sac = sacError(champ, sac_samples, 0x1234_5678 +% @as(u64, s));
            sum_sac += sac;
            if (sac < best_sac) best_sac = sac;
        }
        const sf: f64 = @floatFromInt(seeds);
        try out.print("  {s:<17} | {d:7.3} | {d:12.4} | {d:11.4}\n", .{ m.name, sum_av / sf, sum_sac / sf, best_sac });

        if (std.mem.eql(u8, m.name, "affine+MUL")) mul_best_sac = best_sac;
        for (non_mul_names) |nm| {
            if (std.mem.eql(u8, m.name, nm) and best_sac < best_non_mul_sac) best_non_mul_sac = best_sac;
        }
    }

    const matches = best_non_mul_sac <= mul_best_sac * 1.05; // within 5% of MUL best
    try out.print("\nEXP-21 verdict: MUL best SAC-err={d:.4}; best non-MUL={d:.4}; any match MUL? {s}\n", .{
        mul_best_sac, best_non_mul_sac, if (matches) "YES" else "NO",
    });
    return mul_best_sac;
}

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    const iters: usize = 12000;
    const seeds: usize = 6;
    const sac_samples: usize = 512;

    // Composite fitness for hill-climb (fast); SAC-error measured post-hoc (strict criterion).
    mixer.sac_fitness = false;
    mixer.ban_mul_family = false;

    try out.print("=== CLOSURE ESCAPE: mixer domain (MUL-free affine vs MUL-enabled) ===\n", .{});
    try out.print("{d} hill-climb iters x {d} seeds. mean-av ideal=32; SAC-error ideal=0.\n", .{ iters, seeds });
    try out.print("Fitness: composite avalanche/balance/chi-square; SAC measured post-hoc.\n\n", .{});
    try out.print("  mode              | mean av | mean SAC-err | best SAC-err\n", .{});
    try out.print("  ------------------+---------+--------------+-------------\n", .{});

    const legacy_modes = [_]LegacyMode{
        .{ .name = "MUL-free (affine)", .ban = true },
        .{ .name = "MUL-enabled", .ban = false },
    };
    for (legacy_modes) |m| {
        mixer.ban_mul_family = m.ban;
        var sum_av: f64 = 0;
        var sum_sac: f64 = 0;
        var best_sac: f64 = 1e9;
        for (0..seeds) |s| {
            const champ = hillClimb(0xC0FFEE +% @as(u64, s) *% 0x9E3779B97F4A7C15, iters);
            sum_av += meanAvalanche(champ, sac_samples, 0xA5A5);
            const sac = sacError(champ, sac_samples, 0x1234_5678);
            sum_sac += sac;
            if (sac < best_sac) best_sac = sac;
        }
        const sf: f64 = @floatFromInt(seeds);
        try out.print("  {s:<17} | {d:7.3} | {d:12.4} | {d:11.4}\n", .{ m.name, sum_av / sf, sum_sac / sf, best_sac });
    }

    _ = try runExp21(out, iters, seeds, sac_samples);

    try out.print("\nReading: BOTH legacy modes match mean av ~32. SAC separates them.\n", .{});
    try out.print("Pure GF(2)-affine -> SAC ~0.5 (theorem). ADD partial escape. MUL full escape.\n", .{});
    try out.print("EXP-21: fixed len {d}, one nonlinear op atop affine base — see docs/research/swarm_exp21_non_mul_ops.md\n", .{FixedLen});
}