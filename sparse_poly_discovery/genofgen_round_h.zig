//! H6: conditional autonomous assembly.  Direct failure-guided grammar
//! proposal (H3) plus candidate-excluded v6-style certification (H5).
//!
//! IMPORTANT: `propose` receives only grids and binary labels.  Target kind,
//! pivot, mask and residue live solely in `oracle`/the data generator and are
//! never supplied to inference. This is direct proposal, NOT a learned router
//! and NOT primitive invention.
const std = @import("std");

const N: usize = 4800;
const TRAIN: usize = 2400;
const VAL: usize = 3600;
const CELLS: usize = 8;
const BUDGET: usize = 1270; // 254 directed masks * (2 + 3 residues)
const Sample = struct { g: [CELLS]u8, y: bool };
const Candidate = struct { mask: u8, modulus: u8, residue: u8 };
const Kind = enum { directed_a, directed_b, directed_c, threshold_holdout };
const Target = struct { name: []const u8, kind: Kind, seed: u64 };
const targets = [_]Target{
    .{ .name = "heldout_directed_pivot3_mod3", .kind = .directed_a, .seed = 0xA600000000000001 },
    .{ .name = "heldout_directed_pivot5_mod2", .kind = .directed_b, .seed = 0xA600000000000002 },
    .{ .name = "heldout_directed_partition_mod3", .kind = .directed_c, .seed = 0xA600000000000003 },
    .{ .name = "heldout_threshold_family", .kind = .threshold_holdout, .seed = 0xA600000000000004 },
};

fn oracle(k: Kind, g: [CELLS]u8) bool {
    switch (k) {
        .directed_a => {
            var n: usize = 0;
            for (0..CELLS) |j| {
                if (j != 3 and g[3] > g[j]) n += 1;
            }
            return n % 3 == 1;
        },
        .directed_b => {
            var n: usize = 0;
            for (0..CELLS) |j| {
                if (j != 5 and g[5] > g[j]) n += 1;
            }
            return n % 2 == 0;
        },
        .directed_c => {
            var n: usize = 0;
            const mask: u8 = 0x52;
            for (0..CELLS) |i| {
                for (0..CELLS) |j| {
                    if ((mask & (@as(u8, 1) << @intCast(i))) != 0 and (mask & (@as(u8, 1) << @intCast(j))) == 0 and g[i] > g[j]) n += 1;
                }
            }
            return n % 3 == 2;
        },
        .threshold_holdout => {
            var n: usize = 0;
            for (g) |v| {
                if (v >= 4) n += 1;
            }
            return n % 2 == 1;
        },
    }
}
fn make(a: std.mem.Allocator, seed: u64, k: Kind) ![]Sample {
    var p = std.Random.DefaultPrng.init(seed);
    const r = p.random();
    const xs = try a.alloc(Sample, N);
    for (xs) |*x| {
        for (&x.g) |*v| v.* = r.intRangeAtMost(u8, 0, 5);
        x.y = oracle(k, x.g);
    }
    return xs;
}
fn countPart(g: [CELLS]u8, mask: u8) usize {
    var n: usize = 0;
    for (0..CELLS) |i| {
        for (0..CELLS) |j| {
            if ((mask & (@as(u8, 1) << @intCast(i))) != 0 and (mask & (@as(u8, 1) << @intCast(j))) == 0 and g[i] > g[j]) n += 1;
        }
    }
    return n;
}
fn pred(c: Candidate, x: Sample) bool {
    return countPart(x.g, c.mask) % c.modulus == c.residue;
}
fn score(c: Candidate, xs: []const Sample, lo: usize, hi: usize) f64 {
    var ok: usize = 0;
    for (xs[lo..hi]) |x| {
        if (pred(c, x) == x.y) ok += 1;
    }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo));
}
fn tpred(x: Sample, th: u8, m: u8, r: u8) bool {
    var n: usize = 0;
    for (x.g) |v| {
        if (v >= th) n += 1;
    }
    return n % m == r;
}
fn thresholdBest(xs: []const Sample, lo: usize, hi: usize) f64 {
    var best: f64 = 0;
    for (1..6) |t| {
        for (2..4) |m| {
            for (0..m) |r| {
                var ok: usize = 0;
                for (xs[lo..hi]) |x| {
                    if (tpred(x, @intCast(t), @intCast(m), @intCast(r)) == x.y) ok += 1;
                }
                best = @max(best, @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo)));
            }
        }
    }
    return best;
}
fn orientationProbe(xs: []const Sample) f64 {
    var best: f64 = 0;
    for (0..CELLS) |i| {
        for (2..4) |m| {
            for (0..m) |r| {
                best = @max(best, score(.{ .mask = @as(u8, 1) << @intCast(i), .modulus = @intCast(m), .residue = @intCast(r) }, xs, TRAIN, VAL));
            }
        }
    }
    return best;
}
const Proposal = struct { c: Candidate, signature: bool, val: f64 };
fn propose(xs: []const Sample) Proposal {
    const sig = thresholdBest(xs, TRAIN, VAL) < 0.75 and orientationProbe(xs) >= 0.75;
    if (!sig) return .{ .c = .{ .mask = 1, .modulus = 2, .residue = 0 }, .signature = false, .val = 0 };
    var b: f64 = -1;
    var out = Candidate{ .mask = 1, .modulus = 2, .residue = 0 };
    for (1..255) |mmask| for (2..4) |m| for (0..m) |r| {
        const c = Candidate{ .mask = @intCast(mmask), .modulus = @intCast(m), .residue = @intCast(r) };
        const s = score(c, xs, TRAIN, VAL);
        if (s > b) {
            b = s;
            out = c;
        }
    };
    return .{ .c = out, .signature = true, .val = b };
}
fn randomCandidate(r: std.Random) Candidate {
    const m: u8 = if (r.boolean()) 2 else 3;
    return .{ .mask = r.intRangeAtMost(u8, 1, 254), .modulus = m, .residue = r.intRangeLessThan(u8, 0, m) };
}
fn inv(g: [CELLS]u8) usize {
    var n: usize = 0;
    for (0..CELLS) |i| {
        for (i + 1..CELLS) |j| {
            if (g[i] > g[j]) n += 1;
        }
    }
    return n;
}
// Candidate-excluded v6 reconstruction: train an explicit two-feature table
// over global count and inversion residue, then measure TEST cover. Neither
// feature belongs to the proposed directed/threshold candidate family.
fn coverV6(xs: []const Sample) f64 {
    var all: [9][6]usize = [_][6]usize{[_]usize{0} ** 6} ** 9;
    var pos: [9][6]usize = [_][6]usize{[_]usize{0} ** 6} ** 9;
    for (xs[0..TRAIN]) |x| {
        var c: usize = 0;
        for (x.g) |v| {
            if (v >= 3) c += 1;
        }
        const q = inv(x.g) % 6;
        all[c][q] += 1;
        if (x.y) pos[c][q] += 1;
    }
    var ok: usize = 0;
    for (xs[VAL..]) |x| {
        var c: usize = 0;
        for (x.g) |v| {
            if (v >= 3) c += 1;
        }
        const q = inv(x.g) % 6;
        const y = pos[c][q] * 2 >= all[c][q];
        if (y == x.y) ok += 1;
    }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(N - VAL));
}
fn baseRate(xs: []const Sample) f64 {
    var p: usize = 0;
    for (xs) |x| {
        if (x.y) p += 1;
    }
    return @as(f64, @floatFromInt(p)) / N;
}
fn arm(out: anytype, xs: []const Sample, t: Target, name: []const u8, seed: u64, allow_sig: bool) !void {
    const p = propose(xs);
    const sig = p.signature and allow_sig;
    var prng = std.Random.DefaultPrng.init(seed ^ 0xC0FEBABE);
    const rr = prng.random();
    var random_best: f64 = 0;
    var fixed_best: f64 = 0;
    var random_choice = Candidate{ .mask = 1, .modulus = 2, .residue = 0 };
    // Full raw equal-budget ledger. Every arm consumes BUDGET evaluation calls;
    // hand oracle's calls are padded audit calls and never influence selection.
    for (0..BUDGET) |i| {
        const th: u8 = @intCast(1 + i % 5);
        const m: u8 = if ((i / 5) % 2 == 0) 2 else 3;
        const r: u8 = @intCast((i / 25) % m);
        var fok: usize = 0;
        for (xs[TRAIN..VAL]) |x| {
            if (tpred(x, th, m, r) == x.y) fok += 1;
        }
        const fs = @as(f64, @floatFromInt(fok)) / @as(f64, @floatFromInt(VAL - TRAIN));
        fixed_best = @max(fixed_best, fs);
        const rc = randomCandidate(rr);
        const rs = score(rc, xs, TRAIN, VAL);
        if (rs > random_best) {
            random_best = rs;
            random_choice = rc;
        }
        try out.print("{s},0x{X},ledger,{s},{d},fixed,{d},{d},{d},{d:.4},,\n", .{ t.name, seed, name, i, th, m, r, fs });
        try out.print("{s},0x{X},ledger,{s},{d},random_directed,{d},{d},{d},{d:.4},,\n", .{ t.name, seed, name, i, rc.mask, rc.modulus, rc.residue, rs });
    }
    var val: f64 = 0;
    var test_acc: f64 = 0;
    var source: []const u8 = "none";
    if (std.mem.eql(u8, name, "hand_oracle")) { // Oracle is baseline only; inference arms never read Kind.
        val = 1;
        test_acc = 1;
        source = "hand_formula_oracle";
    } else if (std.mem.eql(u8, name, "fixed_menu") or std.mem.eql(u8, name, "cold_no_signature")) {
        val = fixed_best;
        test_acc = thresholdBest(xs, VAL, N);
        source = "fixed_threshold_menu";
    } else if (std.mem.eql(u8, name, "random")) {
        val = random_best;
        test_acc = score(random_choice, xs, VAL, N);
        source = "blind_directed_random";
    } else if (sig) {
        val = p.val;
        test_acc = score(p.c, xs, VAL, N);
        source = "failure_guided_directed_grammar";
    } else {
        val = fixed_best;
        test_acc = thresholdBest(xs, VAL, N);
        source = "safe_fixed_fallback";
    }
    const cov = coverV6(xs);
    const decision = if (cov >= 0.90) "REJECT_REMIX" else "ADMIT_PROMOTE";
    const direct_ok = !std.mem.eql(u8, name, "direct_v6") or (!sig or (test_acc >= 0.90 and cov < 0.90));
    const pass = baseRate(xs) > 0.10 and baseRate(xs) < 0.90 and direct_ok;
    const actual_decision = if (std.mem.eql(u8, name, "direct_no_v6")) "SKIPPED_UNCERTIFIED" else if (!sig and (std.mem.eql(u8, name, "direct_v6") or std.mem.eql(u8, name, "direct_no_v6"))) "NO_PROPOSAL_FALLBACK" else decision;
    try out.print("{s},0x{X},summary,{s},{d},{s},{d},{d},{d},{d:.4},{d:.4},signature={s};source={s};cover_v6={d:.4};decision={s};budget={d};{s}\n", .{ t.name, seed, name, BUDGET, source, p.c.mask, p.c.modulus, p.c.residue, val, test_acc, if (sig) "yes" else "no", source, cov, actual_decision, BUDGET, if (pass) "PASS" else "FAIL" });
}
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var f = try std.fs.cwd().createFile("../results/genofgen_round_h.csv", .{ .truncate = true });
    defer f.close();
    const out = f.writer();
    try out.writeAll("target,seed,row,arm,candidate_evaluations,grammar,mask,modulus,residue,validation_accuracy,test_accuracy,detail\n");
    for (targets) |t| {
        const xs = try make(a, t.seed, t.kind);
        try arm(out, xs, t, "hand_oracle", t.seed, true);
        try arm(out, xs, t, "fixed_menu", t.seed, true);
        try arm(out, xs, t, "random", t.seed, true);
        try arm(out, xs, t, "cold_no_signature", t.seed, false);
        try arm(out, xs, t, "direct_no_v6", t.seed, true);
        try arm(out, xs, t, "direct_v6", t.seed, true);
    }
}
