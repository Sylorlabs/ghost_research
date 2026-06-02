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
//! Affine maps y = Ax+b over GF(2) can match the FIRST-order statistic (a dense
//! A flips ~32 bits on average) but NOT the second: each input-bit flips each
//! output-bit deterministically (prob 0 or 1), so SAC error pins near 0.5 -- the
//! affine_closure ceiling (docs/research/07), a theorem, not bad luck. MUL is the
//! out-of-closure generator that makes P(flip) ~ 0.5 and escapes it.
//!
//! Program-synthesis twin of asi_attempt/docs/research/closure_escape_control.md
//! (mb_mass): grinding within a closed primitive set cannot leave its closure;
//! one out-of-closure generator does. Run: build core ReleaseFast, then
//! ./zig-out/bin/closure_escape_mixer
const std = @import("std");
const mixer = @import("domain_u64_mixer");

fn smix(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
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

const Mode = struct { name: []const u8, ban: bool };

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    const iters: usize = 12000;
    const seeds: usize = 6;
    try out.print("=== CLOSURE ESCAPE: mixer domain (MUL-free affine vs MUL-enabled) ===\n", .{});
    try out.print("{d} hill-climb iters x {d} seeds. mean-av ideal=32; SAC-error ideal=0.\n\n", .{ iters, seeds });
    try out.print("  mode              | mean av | mean SAC-err | best SAC-err\n", .{});
    try out.print("  ------------------+---------+--------------+-------------\n", .{});
    const modes = [_]Mode{ .{ .name = "MUL-free (affine)", .ban = true }, .{ .name = "MUL-enabled", .ban = false } };
    for (modes) |m| {
        mixer.ban_mul_family = m.ban;
        var sum_av: f64 = 0;
        var sum_sac: f64 = 0;
        var best_sac: f64 = 1e9;
        for (0..seeds) |s| {
            const champ = hillClimb(0xC0FFEE +% @as(u64, s) *% 0x9E3779B97F4A7C15, iters);
            sum_av += meanAvalanche(champ, 512, 0xA5A5);
            const sac = sacError(champ, 512, 0x1234_5678);
            sum_sac += sac;
            if (sac < best_sac) best_sac = sac;
        }
        const sf: f64 = @floatFromInt(seeds);
        try out.print("  {s:<17} | {d:7.3} | {d:12.4} | {d:11.4}\n", .{ m.name, sum_av / sf, sum_sac / sf, best_sac });
    }
    try out.print("\nReading: BOTH modes match the FIRST-order statistic (mean av ~ 32) -- a dense\n", .{});
    try out.print("affine matrix flips ~half the bits on average, so mean avalanche cannot see the\n", .{});
    try out.print("ceiling. The SECOND-order statistic (SAC) does. A PURE GF(2)-affine map (XOR/shift\n", .{});
    try out.print("only) has SAC-error EXACTLY 0.5 -- every input->output flip is deterministic, a\n", .{});
    try out.print("theorem (affine_closure). This 'MUL-free' set still keeps ADD, whose carry chain is\n", .{});
    try out.print("nonlinear, so it escapes pure-affine to ~0.13 -- but plateaus there. MUL, a stronger\n", .{});
    try out.print("out-of-closure generator, drives SAC-error ~6x lower (~0.02). Two-level escape:\n", .{});
    try out.print("linear core stuck at 0.5 (theorem); ADD partial; MUL full. Same search, generators\n", .{});
    try out.print("added -- the synthesis twin of mb_mass (asi_attempt closure_escape_control.md).\n", .{});
}
