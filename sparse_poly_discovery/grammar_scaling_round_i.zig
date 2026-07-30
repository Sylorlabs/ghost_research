//! I4 / Round I: equal-budget scaling of a finite directed grammar.
//!
//! This is deliberately an efficiency map, not a claim that enumeration is
//! invention.  Every arm receives exactly B validation candidate evaluations.
//! `guided_without_replacement` is the admitted directed grammar scanned in a
//! target-blind fixed permutation; `blind_random_with_replacement` samples the
//! identical grammar uniformly.  Thus any difference is coverage/reliability,
//! not an answer-shaped ordering.  The threshold menu is a fixed-family
//! control, padded by cycling only after its 25 legal members are evaluated.
const std = @import("std");

const N: usize = 2400;
const TRAIN: usize = 1200;
const VAL: usize = 1800;
const CELLS: usize = 8;
const MAX: usize = 1270; // 254 nontrivial masks * (2+3 residue choices)
const budgets = [_]usize{ 25, 100, 300, 635, 1270 };
const seeds = [_]u64{ 0xA400000000000001, 0xA400000000000002, 0xA400000000000003 };

const Sample = struct { g: [CELLS]u8, y: bool };
const Candidate = struct { mask: u8, modulus: u8, residue: u8 };
const Target = enum { singleton_directed, multicell_directed, threshold_control };

fn targetName(t: Target) []const u8 {
    return switch (t) {
        .singleton_directed => "singleton_directed",
        .multicell_directed => "multicell_directed",
        .threshold_control => "threshold_control",
    };
}
fn countPartition(g: [CELLS]u8, mask: u8) usize {
    var n: usize = 0;
    for (0..CELLS) |i| for (0..CELLS) |j| {
        const bi: u8 = @as(u8, 1) << @intCast(i);
        const bj: u8 = @as(u8, 1) << @intCast(j);
        if ((mask & bi) != 0 and (mask & bj) == 0 and g[i] > g[j]) n += 1;
    };
    return n;
}
fn oracle(t: Target, g: [CELLS]u8) bool {
    return switch (t) {
        .singleton_directed => countPartition(g, 0x08) % 3 == 1,
        .multicell_directed => countPartition(g, 0x33) % 2 == 1,
        .threshold_control => blk: {
            var n: usize = 0;
            for (g) |v| {
                if (v >= 3) n += 1;
            }
            break :blk n % 2 == 0;
        },
    };
}
fn make(alloc: std.mem.Allocator, seed: u64, t: Target) ![]Sample {
    var p = std.Random.DefaultPrng.init(seed ^ (@as(u64, @intFromEnum(t)) *% 0x9E3779B97F4A7C15));
    const r = p.random();
    const xs = try alloc.alloc(Sample, N);
    for (xs) |*x| {
        for (0..CELLS) |i| x.g[i] = r.intRangeAtMost(u8, 0, 5);
        x.y = oracle(t, x.g);
    }
    return xs;
}
fn pred(c: Candidate, x: Sample) bool {
    return countPartition(x.g, c.mask) % c.modulus == c.residue;
}
fn score(c: Candidate, xs: []const Sample, lo: usize, hi: usize) f64 {
    var ok: usize = 0;
    for (xs[lo..hi]) |x| {
        if (pred(c, x) == x.y) ok += 1;
    }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo));
}
fn thresholdScore(xs: []const Sample, lo: usize, hi: usize, i: usize) f64 {
    const threshold: u8 = @intCast(1 + (i % 5));
    const mod: u8 = if ((i / 5) == 0) 2 else 3;
    const residue: usize = (i / 10) % mod;
    var ok: usize = 0;
    for (xs[lo..hi]) |x| {
        var n: usize = 0;
        for (x.g) |v| {
            if (v >= threshold) n += 1;
        }
        if ((n % mod == residue) == x.y) ok += 1;
    }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo));
}
fn candidateAt(k: usize) Candidate { // target-blind exhaustive enumeration
    const mask: u8 = @intCast(k / 5 + 1);
    const rem = k % 5;
    return .{ .mask = mask, .modulus = if (rem < 2) 2 else 3, .residue = @intCast(if (rem < 2) rem else rem - 2) };
}
// A fixed coprime stride visits every candidate exactly once. It is frozen and
// independent of target labels; contrast it with iid with-replacement sampling.
fn permutedAt(i: usize) Candidate {
    return candidateAt((i * 809 + 113) % MAX);
}
const ArmResult = struct { val: f64, tst: f64, exact: bool };
fn guided(xs: []const Sample, b: usize) ArmResult {
    var best: Candidate = permutedAt(0);
    var bestv: f64 = -1;
    for (0..b) |i| {
        const c = permutedAt(i);
        const s = score(c, xs, TRAIN, VAL);
        if (s > bestv) {
            bestv = s;
            best = c;
        }
    }
    const t = score(best, xs, VAL, N);
    return .{ .val = bestv, .tst = t, .exact = t >= 0.999 };
}
fn randomArm(xs: []const Sample, b: usize, seed: u64) ArmResult {
    var p = std.Random.DefaultPrng.init(seed);
    const r = p.random();
    var best: Candidate = candidateAt(0);
    var bestv: f64 = -1;
    for (0..b) |_| {
        const c = candidateAt(r.intRangeLessThan(usize, 0, MAX));
        const s = score(c, xs, TRAIN, VAL);
        if (s > bestv) {
            bestv = s;
            best = c;
        }
    }
    const t = score(best, xs, VAL, N);
    return .{ .val = bestv, .tst = t, .exact = t >= 0.999 };
}
fn fixed(xs: []const Sample, b: usize) ArmResult {
    var besti: usize = 0;
    var bestv: f64 = -1;
    for (0..b) |i| {
        const s = thresholdScore(xs, TRAIN, VAL, i % 25);
        if (s > bestv) {
            bestv = s;
            besti = i % 25;
        }
    }
    const t = thresholdScore(xs, VAL, N, besti);
    return .{ .val = bestv, .tst = t, .exact = t >= 0.999 };
}
fn run(out: anytype, alloc: std.mem.Allocator, t: Target, seed: u64) !void {
    const xs = try make(alloc, seed, t);
    for (budgets) |b| {
        const g = guided(xs, b);
        const f = fixed(xs, b);
        var rex: usize = 0;
        var rtest: f64 = 0;
        var rmax: f64 = 0;
        for (0..64) |trial| {
            const r = randomArm(xs, b, seed ^ (@as(u64, @intFromEnum(t)) *% 0xD1B54A32D192ED03) ^ (@as(u64, @intCast(b)) *% 0x94D049BB133111EB) ^ @as(u64, @intCast(trial + 1)));
            if (r.exact) rex += 1;
            rtest += r.tst;
            rmax = @max(rmax, r.tst);
        }
        const rate = @as(f64, @floatFromInt(rex)) / 64.0;
        try out.print("{s},0x{X:0>16},{d},guided_without_replacement,{d:.4},{d:.4},{s},1,permuted full grammar\n", .{ targetName(t), seed, b, g.val, g.tst, if (g.exact) "YES" else "NO" });
        try out.print("{s},0x{X:0>16},{d},blind_random_with_replacement,{d:.4},{d:.4},{d:.4},{d},64 iid trials\n", .{ targetName(t), seed, b, rtest / 64.0, rmax, rate, rex });
        try out.print("{s},0x{X:0>16},{d},fixed_threshold_menu,{d:.4},{d:.4},{s},1,25 legal candidates then cycle\n", .{ targetName(t), seed, b, f.val, f.tst, if (f.exact) "YES" else "NO" });
        std.debug.print("{s} seed=0x{X} B={d}: guided test={d:.3} exact={s}; random exact={d}/64; fixed={d:.3}\n", .{ targetName(t), seed, b, g.tst, if (g.exact) "YES" else "NO", rex, f.tst });
    }
}
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const f = try std.fs.cwd().createFile("../results/grammar_scaling_round_i.csv", .{ .truncate = true });
    defer f.close();
    var out = f.writer();
    try out.writeAll("target,seed,budget,arm,mean_validation_accuracy,mean_or_best_test_accuracy,exact_rate_or_flag,replicates,detail\n");
    for (seeds) |seed| {
        try run(out, arena.allocator(), .singleton_directed, seed);
        try run(out, arena.allocator(), .multicell_directed, seed);
        try run(out, arena.allocator(), .threshold_control, seed);
    }
}
