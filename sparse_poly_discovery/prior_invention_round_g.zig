//! G4 / Round G -- prior grammar invention from residual behaviour.
//!
//! This is deliberately a small, inspectable experiment.  The fixed language
//! is {value-threshold count, directed partitioned comparison count, run
//! count, distinct count, residue-equality}.  At inference the proposer sees
//! labels and a failure signature, not a target/family name or an anchor.
//! It may instantiate every legal partition mask and residue, and returns a
//! grammar plus parameters.  The held-out target is only the oracle used for
//! scoring candidates; its definition is not an input to the proposer.
const std = @import("std");

const N: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const NCELL: usize = 8;
const seeds = [_]u64{ 0xA71C000000000001, 0xA71C000000000002, 0xA71C000000000003 };
const holdout: u64 = 0xA71C0000000000A4;

const Sample = struct { g: [NCELL]u8, y: bool };
const Candidate = struct { mask: u8, modulus: u8, residue: u8 };

// The *held-out evaluation target*, intentionally absent from all proposal
// inputs: rank(cell 3) mod 3 == 1.  Unlike ORDER2 it is not used in F2/F5.
fn oracle(g: [NCELL]u8) bool {
    var rank: usize = 0;
    for (0..NCELL) |j| { if (j != 3 and g[3] > g[j]) rank += 1; }
    return rank % 3 == 1;
}

fn make(alloc: std.mem.Allocator, seed: u64) ![]Sample {
    var p = std.Random.DefaultPrng.init(seed);
    const r = p.random();
    const s = try alloc.alloc(Sample, N);
    for (s) |*x| {
        for (0..NCELL) |i| x.g[i] = r.intRangeAtMost(u8, 0, 5);
        x.y = oracle(x.g);
    }
    return s;
}

/// Generic directed-partition primitive: for every selected cell i and every
/// non-selected cell j, count g[i] > g[j].  No cell or mask is privileged.
fn partitionCount(g: [NCELL]u8, mask: u8) usize {
    var n: usize = 0;
    for (0..NCELL) |i| for (0..NCELL) |j| {
        const bi: u8 = @as(u8, 1) << @intCast(i);
        const bj: u8 = @as(u8, 1) << @intCast(j);
        if ((mask & bi) != 0 and (mask & bj) == 0 and g[i] > g[j]) n += 1;
    };
    return n;
}
fn predicts(c: Candidate, x: Sample) bool {
    return partitionCount(x.g, c.mask) % c.modulus == c.residue;
}
fn accuracy(c: Candidate, xs: []const Sample, lo: usize, hi: usize) f64 {
    var ok: usize = 0;
    for (xs[lo..hi]) |x| { if (predicts(c, x) == x.y) ok += 1; }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo));
}

fn thresholdBaseline(x: Sample, t: u8, residue: u8) bool {
    var n: usize = 0;
    for (x.g) |v| { if (v >= t) n += 1; }
    return n % 3 == residue;
}
fn fixedMenuAccuracy(xs: []const Sample, lo: usize, hi: usize) f64 {
    var best: f64 = 0;
    for (1..6) |tt| for (0..3) |rr| {
        var ok: usize = 0;
        for (xs[lo..hi]) |x| { if (thresholdBaseline(x, @intCast(tt), @intCast(rr)) == x.y) ok += 1; }
        best = @max(best, @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo)));
    };
    return best;
}
fn pairOrientationProbe(xs: []const Sample) f64 {
    var best: f64 = 0;
    // A deliberately tiny, symmetric diagnostic: eight singleton partitions
    // crossed with residues.  It may choose a grammar class, never an anchor.
    for (1..9) |bit| for (2..4) |mod| for (0..mod) |res| {
        const c = Candidate{ .mask = @as(u8, 1) << @intCast(bit - 1), .modulus = @intCast(mod), .residue = @intCast(res) };
        best = @max(best, accuracy(c, xs, NTR, NVA));
    };
    return best;
}
fn propose(xs: []const Sample) struct { candidate: Candidate, signature_pass: bool } {
    // Failure signature: threshold-count menu has no member >= 0.75 on the
    // validation slice, while pairwise orientation probes have high residual
    // dependence.  It selects the *grammar*, then exhaustive instantiation.
    // Neither branch sees a target name, correct anchor, mask, or residue.
    const signature_pass = fixedMenuAccuracy(xs, NTR, NVA) < 0.75 and pairOrientationProbe(xs) >= 0.75;
    var best = Candidate{ .mask = 1, .modulus = 2, .residue = 0 };
    var score: f64 = -1;
    for (1..255) |m| for (2..4) |mod| for (0..mod) |res| {
        const c = Candidate{ .mask = @intCast(m), .modulus = @intCast(mod), .residue = @intCast(res) };
        const a = accuracy(c, xs, NTR, NVA);
        if (a > score) { score = a; best = c; }
    };
    return .{ .candidate = best, .signature_pass = signature_pass };
}
fn randomControl(xs: []const Sample, seed: u64) f64 {
    var p = std.Random.DefaultPrng.init(seed);
    const r = p.random();
    var best: f64 = 0;
    for (0..24) |_| {
        const mod: u8 = if (r.boolean()) 2 else 3;
        const c = Candidate{ .mask = r.intRangeAtMost(u8, 1, 254), .modulus = mod, .residue = r.intRangeLessThan(u8, 0, mod) };
        best = @max(best, accuracy(c, xs, NTR, NVA));
    }
    return best;
}

/// Six non-answer reference statistics for a conservative multi-feature
/// reconstruction proxy: total threshold counts and global inversions.  It
/// is intentionally labelled a proxy until G1 freezes its gate.
fn referenceProxy(xs: []const Sample, lo: usize, hi: usize) f64 {
    var counts: [9][6]usize = [_][6]usize{[_]usize{0} ** 6} ** 9;
    var pos: [9][6]usize = [_][6]usize{[_]usize{0} ** 6} ** 9;
    for (xs[0..NTR]) |x| {
        var n: usize = 0; for (x.g) |v| { if (v >= 3) n += 1; }
        var inv: usize = 0; for (0..NCELL) |i| for (i + 1..NCELL) |j| { if (x.g[i] > x.g[j]) inv += 1; };
        const a = n; const b = inv % 6;
        counts[a][b] += 1; if (x.y) pos[a][b] += 1;
    }
    var ok: usize = 0;
    for (xs[lo..hi]) |x| {
        var n: usize = 0; for (x.g) |v| { if (v >= 3) n += 1; }
        var inv: usize = 0; for (0..NCELL) |i| for (i + 1..NCELL) |j| { if (x.g[i] > x.g[j]) inv += 1; };
        const pred = pos[n][inv % 6] * 2 >= counts[n][inv % 6];
        if (pred == x.y) ok += 1;
    }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit();
    const a = arena.allocator();
    var file = try std.fs.cwd().createFile("../results/prior_invention_round_g.csv", .{}); defer file.close();
    var out = file.writer();
    try out.writeAll("split,seed,arm,grammar,mask,modulus,residue,base_rate,fixed_menu_val,random_val,selected_val,test_acc,reconstruction_proxy_test,validity\n");
    const all_seeds = [_]u64{ seeds[0], seeds[1], seeds[2], holdout };
    for (all_seeds, 0..) |seed, idx| {
        const xs = try make(a, seed);
        var pos: usize = 0; for (xs) |x| { if (x.y) pos += 1; }
        const base = @as(f64, @floatFromInt(pos)) / N;
        const fixed = fixedMenuAccuracy(xs, NTR, NVA);
        const proposal = propose(xs);
        const c = proposal.candidate;
        const sel = accuracy(c, xs, NTR, NVA);
        const tst = accuracy(c, xs, NVA, N);
        // Reproducible raw exhaustive ledger.  Test scores are recorded for
        // audit only; proposal selection reads validation scores exclusively.
        for (1..255) |m| for (2..4) |mod| for (0..mod) |res| {
            const probe = Candidate{ .mask = @intCast(m), .modulus = @intCast(mod), .residue = @intCast(res) };
            try out.print("{s},0x{X:0>16},grammar_enumeration,directed_partition_compare_mod,{d},{d},{d},{d:.4},,,{d:.4},{d:.4},,RAW\n", .{ if (idx == 3) "heldout" else "measurement", seed, probe.mask, probe.modulus, probe.residue, base, accuracy(probe, xs, NTR, NVA), accuracy(probe, xs, NVA, N) });
        };
        var rand_mean: f64 = 0; for (0..20) |r| rand_mean += randomControl(xs, seed + r + 11); rand_mean /= 20;
        const proxy = referenceProxy(xs, NVA, N);
        const validity = base > 0.10 and base < 0.90 and proposal.signature_pass and sel >= 0.90 and tst >= 0.90 and proxy < 0.90;
        try out.print("{s},0x{X:0>16},proposed,directed_partition_compare_mod,{d},{d},{d},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{s}\n", .{ if (idx == 3) "heldout" else "measurement", seed, c.mask, c.modulus, c.residue, base, fixed, rand_mean, sel, tst, proxy, if (validity) "PASS" else "FAIL" });
        std.debug.print("{s} seed=0x{X} mask=0x{X:0>2} mod={d} residue={d} val={d:.3} test={d:.3} fixed={d:.3} random={d:.3} proxy={d:.3} {s}\n", .{ if (idx == 3) "heldout" else "measurement", seed, c.mask, c.modulus, c.residue, sel, tst, fixed, rand_mean, proxy, if (validity) "PASS" else "FAIL" });
    }
}
