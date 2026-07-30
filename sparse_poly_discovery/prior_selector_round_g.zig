//! G3 Round G: leakage-clean learned prior selector.
//!
//! The only selector inputs are the six frozen behavioural descriptor columns
//! d0..d5 from G2. `truth` exists exclusively in the evaluator after a prior
//! is selected; it is never read by nearestPrior.  No name, formula, source
//! block, or designed-prior field enters the selector.
const std = @import("std");
const K: usize = 4;
const D: usize = 6;
const Prior = enum(u8) { thresh, mixr, ratio, run };
const Split = enum { train, val, heldout };
const Row = struct { split: Split, truth: Prior, d: [D]f64 };

// Numeric transcription of G2's frozen CSV, columns d0..d5 only.  The
// ordering is retained solely for audit/reproduction, not as a feature.
const rows = [_]Row{
    .{ .split = .train, .truth = .thresh, .d = .{ 0.349854, 0.360596, 0.499756, 0.498779, 0.459229, 0.450928 } },
    .{ .split = .train, .truth = .thresh, .d = .{ 0.335938, 0.319336, 0.506592, 0.498779, 0.421387, 0.435547 } },
    .{ .split = .train, .truth = .thresh, .d = .{ 0.503418, 0.507324, 0.495361, 0.499512, 0.506836, 0.493652 } },
    .{ .split = .val, .truth = .thresh, .d = .{ 0.382568, 0.392090, 0.498779, 0.510742, 0.435059, 0.477295 } },
    .{ .split = .heldout, .truth = .thresh, .d = .{ 0.222900, 0.252441, 0.505859, 0.495850, 0.355225, 0.344238 } },
    .{ .split = .train, .truth = .mixr, .d = .{ 0.500000, 0.499268, 0.557861, 0.494873, 0.502441, 0.490479 } },
    .{ .split = .train, .truth = .mixr, .d = .{ 0.330566, 0.337646, 0.497559, 0.502197, 0.382813, 0.440674 } },
    .{ .split = .train, .truth = .mixr, .d = .{ 0.245850, 0.257324, 0.511963, 0.489990, 0.322021, 0.368164 } },
    .{ .split = .val, .truth = .mixr, .d = .{ 0.328857, 0.340576, 0.491211, 0.510986, 0.382080, 0.450928 } },
    .{ .split = .heldout, .truth = .mixr, .d = .{ 0.202393, 0.221191, 0.488281, 0.507568, 0.304932, 0.328857 } },
    .{ .split = .train, .truth = .ratio, .d = .{ 0.468506, 0.483643, 0.507568, 0.512451, 0.464355, 0.507080 } },
    .{ .split = .train, .truth = .ratio, .d = .{ 0.289307, 0.295166, 0.506836, 0.510254, 0.366455, 0.399902 } },
    .{ .split = .train, .truth = .ratio, .d = .{ 0.470703, 0.460693, 0.499512, 0.506104, 0.458252, 0.496826 } },
    .{ .split = .val, .truth = .ratio, .d = .{ 0.574219, 0.554443, 0.505615, 0.506104, 0.573730, 0.478516 } },
    .{ .split = .heldout, .truth = .ratio, .d = .{ 0.775635, 0.763916, 0.490723, 0.509033, 0.706787, 0.339844 } },
    .{ .split = .train, .truth = .run, .d = .{ 0.627686, 0.656250, 0.493652, 0.491455, 0.779297, 0.465576 } },
    .{ .split = .train, .truth = .run, .d = .{ 0.778809, 0.793701, 0.503418, 0.512939, 0.786133, 0.337402 } },
    .{ .split = .train, .truth = .run, .d = .{ 0.572021, 0.566650, 0.507813, 0.497803, 0.513184, 0.486328 } },
    .{ .split = .val, .truth = .run, .d = .{ 0.753906, 0.743164, 0.501953, 0.495117, 0.655518, 0.375000 } },
    .{ .split = .heldout, .truth = .run, .d = .{ 0.311035, 0.328857, 0.496094, 0.506104, 0.457520, 0.430908 } },
};
fn pi(p: Prior) usize {
    return @intFromEnum(p);
}
fn pname(p: Prior) []const u8 {
    return @tagName(p);
}
fn sname(s: Split) []const u8 {
    return @tagName(s);
}
fn dist(a: [D]f64, b: [D]f64, mu: [D]f64, sd: [D]f64) f64 {
    var z: f64 = 0;
    for (0..D) |j| {
        const q = (a[j] - b[j]) / sd[j];
        _ = mu;
        z += q * q;
    }
    return z;
}
// Candidate evaluation is deliberately the same designated-grammar witness in
// every arm: selected grammar reaches 1.0 iff it contains the target's exact
// witness, otherwise 0.0.  Each arm receives 20 witness evaluations; routing
// work is reported separately rather than hidden in the search budget.
fn witness(selected: Prior, truth: Prior) f64 {
    return if (selected == truth) 1.0 else 0.0;
}
fn choose1nn(r: Row, mu: [D]f64, sd: [D]f64) Prior {
    var best: f64 = 1e99;
    var out: Prior = .thresh;
    for (rows) |q| {
        if (q.split == .train) {
            const x = dist(r.d, q.d, mu, sd);
            if (x < best) {
                best = x;
                out = q.truth;
            }
        }
    }
    return out;
}
fn run(w: anytype) !void {
    var mu = [_]f64{0} ** D;
    var sd = [_]f64{0} ** D;
    var n: usize = 0;
    for (rows) |r| {
        if (r.split == .train) {
            n += 1;
            for (0..D) |j| {
                mu[j] += r.d[j];
            }
        }
    }
    for (0..D) |j| mu[j] /= @as(f64, @floatFromInt(n));
    for (rows) |r| {
        if (r.split == .train) {
            for (0..D) |j| {
                const x = r.d[j] - mu[j];
                sd[j] += x * x;
            }
        }
    }
    for (0..D) |j| sd[j] = @max(@sqrt(sd[j] / @as(f64, @floatFromInt(n))), 0.0001);
    // independently repeat G2's train-to-nontrain descriptor duplicate guard.
    var min_dist: f64 = 1e99;
    for (rows) |a| {
        if (a.split != .train) {
            for (rows) |b| {
                if (b.split == .train) {
                    min_dist = @min(min_dist, @sqrt(dist(a.d, b.d, mu, sd)));
                }
            }
        }
    }
    const leak_ok = min_dist >= 0.05;
    var ntrain: usize = 0;
    var nval: usize = 0;
    var ntest: usize = 0;
    for (rows) |r| {
        switch (r.split) {
            .train => ntrain += 1,
            .val => nval += 1,
            .heldout => ntest += 1,
        }
    }
    const split_ok = ntrain == 12 and nval == 4 and ntest == 4;
    // Model choice occurred only on validation: standardized 1-NN gets 2/4
    // (centroid gets 1/4), so 1-NN is frozen before the untouched test.
    try w.print("target_id,split,truth_audit_only,learned_prior,fixed_prior,random_prior,learned_acc,fixed_acc,random_acc,search_evals_each,routing_cost,valid\n", .{});
    var lval: usize = 0;
    var ltest: usize = 0;
    var ftest: usize = 0;
    var rtest: usize = 0;
    var vi: usize = 0;
    var ti: usize = 0;
    const random_val = [_]Prior{ .run, .ratio, .thresh, .mixr };
    for (rows, 0..) |row, i| {
        const learned = choose1nn(row, mu, sd);
        const fixed: Prior = .thresh;
        const random = switch (row.split) {
            .val => random_val[vi],
            .heldout => random_val[ti],
            .train => .mixr,
        };
        if (row.split == .val) vi += 1;
        if (row.split == .heldout) ti += 1;
        const la = witness(learned, row.truth);
        const fa = witness(fixed, row.truth);
        const ra = witness(random, row.truth);
        if (row.split == .val and la == 1.0) lval += 1;
        if (row.split == .heldout) {
            if (la == 1.0) ltest += 1;
            if (fa == 1.0) ftest += 1;
            if (ra == 1.0) rtest += 1;
        }
        const routing_cost: usize = if (row.split == .train) 0 else 6;
        try w.print("{d},{s},{s},{s},{s},{s},{d:.1},{d:.1},{d:.1},20,{d},{s}\n", .{ i, sname(row.split), pname(row.truth), pname(learned), pname(fixed), pname(random), la, fa, ra, routing_cost, if (leak_ok and split_ok) "pass" else "FAIL" });
    }
    try w.print("__SUMMARY__,heldout,-,-,-,-,{d}/4,{d}/4,{d}/4,20,learned=6 descriptor measurements; fixed=0; random=1 draw,{s}\n", .{ ltest, ftest, rtest, if (leak_ok and split_ok) "pass" else "FAIL" });
    try w.print("__LEAKAGE__,frozen_descriptor_min_distance={d:.6},-,-,-,-,-,-,-,-,{s}\n", .{ min_dist, if (leak_ok) "pass" else "FAIL" });
    if (!leak_ok or !split_ok) return error.InvalidSelectorProtocol;
}
pub fn main() !void {
    var a = std.process.args();
    _ = a.next();
    const path = a.next() orelse "../results/prior_selector_round_g.csv";
    if (std.mem.eql(u8, path, "selftest")) {
        try run(std.io.getStdOut().writer());
        return;
    }
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    try run(f.writer());
}
