//! H3 / Round H: direct grammar proposal from labelled failure behaviour.
//!
//! The proposer only accepts `[]Sample`: grids plus binary labels.  It has no
//! target name, target formula, family tag, anchor, or residue argument.  A
//! generic orientation diagnostic decides whether to open a symmetric directed
//! partition grammar; validation labels select its parameters.  The data
//! generator is intentionally separate from inference so held-out variants
//! cannot be smuggled into `propose`.
const std = @import("std");

const N: usize = 6000;
const TRAIN_END: usize = 3000;
const VAL_END: usize = 4500;
const CELLS: usize = 8;
const BUDGET: usize = 1270; // 254 masks * (2+3 legal residues)
const Sample = struct { g: [CELLS]u8, y: bool };
const Candidate = struct { mask: u8, modulus: u8, residue: u8 };
const Target = enum { measurement, holdout_variant };

// These definitions create labels only.  They are never passed to `propose`.
fn oracle(t: Target, g: [CELLS]u8) bool {
    const pivot: usize = if (t == .measurement) 3 else 5;
    var rank: usize = 0;
    for (0..CELLS) |j| { if (j != pivot and g[pivot] > g[j]) rank += 1; }
    return if (t == .measurement) rank % 3 == 1 else rank % 2 == 0;
}
fn make(alloc: std.mem.Allocator, seed: u64, t: Target) ![]Sample {
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const xs = try alloc.alloc(Sample, N);
    for (xs) |*x| {
        for (0..CELLS) |i| x.g[i] = r.intRangeAtMost(u8, 0, 5);
        x.y = oracle(t, x.g);
    }
    return xs;
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
fn pred(c: Candidate, x: Sample) bool { return countPartition(x.g, c.mask) % c.modulus == c.residue; }
fn score(c: Candidate, xs: []const Sample, lo: usize, hi: usize) f64 {
    var ok: usize = 0;
    for (xs[lo..hi]) |x| { if (pred(c, x) == x.y) ok += 1; }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo));
}
fn thresholdPred(x: Sample, threshold: u8, modulus: u8, residue: u8) bool {
    var n: usize = 0; for (x.g) |v| { if (v >= threshold) n += 1; }
    return n % modulus == residue;
}
fn thresholdBest(xs: []const Sample, lo: usize, hi: usize) f64 {
    var best: f64 = 0;
    for (1..6) |tt| for (2..4) |mm| for (0..mm) |rr| {
        var ok: usize = 0;
        for (xs[lo..hi]) |x| { if (thresholdPred(x, @intCast(tt), @intCast(mm), @intCast(rr)) == x.y) ok += 1; }
        best = @max(best, @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo)));
    };
    return best;
}
/// A small generic diagnostic, deliberately independent of the full grammar
/// enumerator. It sees only label agreement for all singleton orientation
/// probes; max response selects a grammar *class*, never a cell/mask/residue.
fn orientationProbe(xs: []const Sample) f64 {
    var best: f64 = 0;
    for (0..CELLS) |i| for (2..4) |mm| for (0..mm) |rr| {
        best = @max(best, score(.{ .mask = @as(u8, 1) << @intCast(i), .modulus = @intCast(mm), .residue = @intCast(rr) }, xs, TRAIN_END, VAL_END));
    };
    return best;
}
const Proposal = struct { c: Candidate, signature: bool, val: f64 };
fn propose(xs: []const Sample) Proposal {
    // The grammar decision uses behaviour: the global threshold menu fails
    // while a cheap orientation probe responds. No semantic target metadata.
    const signature = thresholdBest(xs, TRAIN_END, VAL_END) < 0.75 and orientationProbe(xs) >= 0.75;
    if (!signature) return .{ .c = .{ .mask = 1, .modulus = 2, .residue = 0 }, .signature = false, .val = 0 };
    var out = Candidate{ .mask = 1, .modulus = 2, .residue = 0 };
    var best: f64 = -1;
    for (1..255) |m| for (2..4) |mm| for (0..mm) |rr| {
        const c = Candidate{ .mask = @intCast(m), .modulus = @intCast(mm), .residue = @intCast(rr) };
        const a = score(c, xs, TRAIN_END, VAL_END);
        if (a > best) { best = a; out = c; }
    };
    return .{ .c = out, .signature = true, .val = best };
}
fn randomCandidate(r: std.Random) Candidate {
    const m: u8 = if (r.boolean()) 2 else 3;
    return .{ .mask = r.intRangeAtMost(u8, 1, 254), .modulus = m, .residue = r.intRangeLessThan(u8, 0, m) };
}
/// Repeated *equal-budget* random arms. A random arm may occasionally draw
/// the exact candidate, so its success probability—not one lucky draw—is the
/// fair comparator to the deterministic failure-guided grammar admission.
fn randomExactRate(xs: []const Sample, seed: u64) f64 {
    var exact: usize = 0;
    for (0..64) |trial| {
        var prng = std.Random.DefaultPrng.init(seed ^ (0x9E3779B97F4A7C15 *% @as(u64, @intCast(trial + 1))));
        const r = prng.random();
        var best: f64 = 0;
        for (0..BUDGET) |_| best = @max(best, score(randomCandidate(r), xs, TRAIN_END, VAL_END));
        if (best >= 0.999) exact += 1;
    }
    return @as(f64, @floatFromInt(exact)) / 64.0;
}
fn globalInversions(g: [CELLS]u8) usize {
    var inv: usize = 0;
    for (0..CELLS) |i| {
        for (i + 1..CELLS) |j| {
            if (g[i] > g[j]) inv += 1;
        }
    }
    return inv;
}
/// Candidate-excluded, multi-feature reconstruction proxy: threshold count +
/// global inversion residue. It follows G1's decision direction (held-out
/// target-label COVER), but is not a replacement for its live greedy COVER.
fn excludedCover(xs: []const Sample) f64 {
    var all: [9][6]usize = [_][6]usize{[_]usize{0} ** 6} ** 9;
    var pos: [9][6]usize = [_][6]usize{[_]usize{0} ** 6} ** 9;
    for (xs[0..TRAIN_END]) |x| {
        var tc: usize = 0; for (x.g) |v| { if (v >= 3) tc += 1; }
        const inv = globalInversions(x.g);
        all[tc][inv % 6] += 1; if (x.y) { pos[tc][inv % 6] += 1; }
    }
    var ok: usize = 0;
    for (xs[VAL_END..]) |x| {
        var tc: usize = 0; for (x.g) |v| { if (v >= 3) tc += 1; }
        const inv = globalInversions(x.g);
        const yes = pos[tc][inv % 6] * 2 >= all[tc][inv % 6];
        if (yes == x.y) ok += 1;
    }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(N - VAL_END));
}
fn runOne(out: anytype, alloc: std.mem.Allocator, split: []const u8, seed: u64, t: Target) !void {
    const xs = try make(alloc, seed, t);
    var positives: usize = 0; for (xs) |x| { if (x.y) positives += 1; }
    const base = @as(f64, @floatFromInt(positives)) / N;
    const fixed_val = thresholdBest(xs, TRAIN_END, VAL_END);
    const p = propose(xs);
    const proposed_test = if (p.signature) score(p.c, xs, VAL_END, N) else 0;
    var prng = std.Random.DefaultPrng.init(seed ^ 0xD1AEC700); // separate arm stream
    const r = prng.random();
    var random_best: f64 = 0;
    // Raw ledger: 1,270 calls in every arm. Fixed's 25 legal candidates cycle
    // deterministically; random and proposed each receive 1,270 drawn/legal
    // candidates. Selection uses validation only; test remains audit-only.
    for (0..BUDGET) |i| {
        const threshold: u8 = @intCast(1 + (i % 5));
        const modulus: u8 = if ((i / 5) % 2 == 0) 2 else 3;
        const residue: u8 = @intCast((i / 25) % modulus);
        var fixed_ok: usize = 0; for (xs[TRAIN_END..VAL_END]) |x| { if (thresholdPred(x, threshold, modulus, residue) == x.y) fixed_ok += 1; }
        const fv = @as(f64, @floatFromInt(fixed_ok)) / @as(f64, @floatFromInt(VAL_END - TRAIN_END));
        try out.print("{s},0x{X:0>16},fixed_menu,{d},threshold_count,{d},{d},,{d:.4},RAW\n", .{ split, seed, i, threshold, modulus, fv });
        const rc = randomCandidate(r);
        const rv = score(rc, xs, TRAIN_END, VAL_END);
        random_best = @max(random_best, rv);
        try out.print("{s},0x{X:0>16},random_directed,{d},directed_partition,{d},{d},{d},{d:.4},RAW\n", .{ split, seed, i, rc.mask, rc.modulus, rc.residue, rv });
        // This row is the proposed grammar's complete candidate ledger.
        const mi = i / 5 + 1;
        const pm: u8 = @intCast(mi);
        const rem = i % 5;
        const pmod: u8 = if (rem < 2) 2 else 3;
        const pres: u8 = @intCast(if (rem < 2) rem else rem - 2);
        const pc = Candidate{ .mask = pm, .modulus = pmod, .residue = pres };
        try out.print("{s},0x{X:0>16},proposed_directed,{d},directed_partition,{d},{d},{d},{d:.4},RAW\n", .{ split, seed, i, pc.mask, pc.modulus, pc.residue, score(pc, xs, TRAIN_END, VAL_END) });
    }
    const cover = excludedCover(xs);
    const random_exact_rate = randomExactRate(xs, seed ^ 0x51ECA7E);
    const gate = if (cover < 0.90) "ADMIT_NOVEL_PROXY" else "REJECT_REMIX_PROXY";
    const valid = base > 0.10 and base < 0.90 and p.signature and p.val >= 0.90 and proposed_test >= 0.90 and proposed_test > fixed_val and random_exact_rate < 0.90 and cover < 0.90;
    try out.print("{s},0x{X:0>16},summary,{d},directed_partition,{d},{d},{d},{d:.4},{d:.4},base={d:.4};fixed={d:.4};random_one={d:.4};random_exact_rate_64={d:.4};test={d:.4};cover={d:.4};gate={s};{s}\n", .{ split, seed, BUDGET, p.c.mask, p.c.modulus, p.c.residue, p.val, proposed_test, base, fixed_val, random_best, random_exact_rate, proposed_test, cover, gate, if (valid) "PASS" else "FAIL" });
    // Ablation: no orientation signal means no directed grammar admission;
    // report the best pre-existing threshold menu on test, not a hidden search.
    try out.print("{s},0x{X:0>16},ablation_no_signature,{d},threshold_only,,,,{d:.4},test_fixed={d:.4}\n", .{ split, seed, BUDGET, fixed_val, thresholdBest(xs, VAL_END, N) });
    std.debug.print("{s} seed=0x{X} mask=0x{X:0>2} mod={d} res={d} val={d:.3} test={d:.3} fixed={d:.3} random_one={d:.3} random_exact_rate={d:.3} cover={d:.3} {s}\n", .{ split, seed, p.c.mask, p.c.modulus, p.c.residue, p.val, proposed_test, fixed_val, random_best, random_exact_rate, cover, if (valid) "PASS" else "FAIL" });
}
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit();
    const f = try std.fs.cwd().createFile("../results/direct_proposer_round_h.csv", .{ .truncate = true }); defer f.close();
    var out = f.writer();
    try out.writeAll("split,seed,arm,candidate_evaluations,grammar,mask,modulus,residue,validation_accuracy,detail\n");
    const seeds = [_]u64{ 0xA300000000000001, 0xA300000000000002, 0xA300000000000003 };
    for (seeds) |seed| try runOne(out, arena.allocator(), "measurement", seed, .measurement);
    try runOne(out, arena.allocator(), "heldout_variant", 0xA3000000000000A4, .holdout_variant);
}
