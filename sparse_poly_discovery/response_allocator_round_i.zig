//! I3 / Round I -- response-guided grammar allocator.
//!
//! The allocation API sees only I1's eight frozen response fields (gain and
//! residual for global, singleton, partition, and none) plus I2's symmetric
//! partition-admission predicate.  Generator metadata below is audit-only.
const std = @import("std");
const Cells: usize = 8;
const N: usize = 1200;
const Train: usize = 600;
const Val: usize = 900;
const Probe: usize = 30; // exactly I1's per-family micro-search budget
const Total: usize = 420; // 120 probes + 300 allocated candidates, all arms
const Extra: usize = Total - 4 * Probe;

const Route = enum { global, singleton, partition, none };
const Spec = struct { audit_id: []const u8, route: Route, seed: u64, variant: u8, heldout: bool };
const specs = [_]Spec{
    .{ .audit_id = "global_train", .route = .global, .seed = 0x1301, .variant = 1, .heldout = false },
    .{ .audit_id = "singleton_train", .route = .singleton, .seed = 0x1302, .variant = 1, .heldout = false },
    .{ .audit_id = "partition_twocell_train", .route = .partition, .seed = 0x1303, .variant = 1, .heldout = false },
    .{ .audit_id = "none_train", .route = .none, .seed = 0x1304, .variant = 1, .heldout = false },
    .{ .audit_id = "global_holdout", .route = .global, .seed = 0x1311, .variant = 2, .heldout = true },
    .{ .audit_id = "singleton_holdout", .route = .singleton, .seed = 0x1312, .variant = 2, .heldout = true },
    .{ .audit_id = "partition_threecell_holdout", .route = .partition, .seed = 0x1313, .variant = 2, .heldout = true },
    .{ .audit_id = "threshold_control_holdout", .route = .none, .seed = 0x1314, .variant = 2, .heldout = true },
    .{ .audit_id = "no_grammar_holdout", .route = .none, .seed = 0x1315, .variant = 3, .heldout = true },
};
const Sample = struct { g: [Cells]u8, y: bool };
const Candidate = struct { route: Route, a: u8, m: u8, r: u8 };
const Desc = [8]f64;

fn countGE(g: [Cells]u8, t: u8) usize {
    var z: usize = 0;
    for (g) |v| {
        if (v >= t) z += 1;
    }
    return z;
}
fn rank(g: [Cells]u8, p: usize) usize {
    var z: usize = 0;
    for (g, 0..) |v, i| {
        if (i != p and g[p] > v) z += 1;
    }
    return z;
}
fn cross(g: [Cells]u8, mask: u8) usize {
    var z: usize = 0;
    for (0..Cells) |i| {
        for (0..Cells) |j| {
            const bi: u8 = @as(u8, 1) << @intCast(i);
            const bj: u8 = @as(u8, 1) << @intCast(j);
            if ((mask & bi) != 0 and (mask & bj) == 0 and g[i] > g[j]) z += 1;
        }
    }
    return z;
}
fn adjacent(g: [Cells]u8) usize {
    var z: usize = 0;
    for (1..Cells) |i| {
        if (g[i] >= 3 and g[i - 1] >= 3) z += 1;
    }
    return z;
}
fn truth(s: Spec, g: [Cells]u8) bool {
    return switch (s.route) {
        .global => countGE(g, if (s.variant == 1) @as(u8, 2) else 4) % 2 == 0,
        .singleton => rank(g, if (s.variant == 1) 1 else 6) % 3 == 1,
        .partition => blk: {
            const mask: u8 = if (s.variant == 1) 0x22 else 0x49;
            const modulus: usize = if (s.variant == 1) 2 else 3;
            const residue: usize = if (s.variant == 1) 0 else 2;
            break :blk cross(g, mask) % modulus == residue;
        },
        .none => if (s.variant == 2) countGE(g, 3) % 2 == 0 else adjacent(g) % 2 == 1,
    };
}
fn make(a: std.mem.Allocator, s: Spec) ![]Sample {
    var p = std.Random.DefaultPrng.init(s.seed);
    const r = p.random();
    const xs = try a.alloc(Sample, N);
    for (xs) |*x| {
        for (&x.g) |*v| v.* = r.intRangeAtMost(u8, 0, 5);
        x.y = truth(s, x.g);
    }
    return xs;
}
fn num(route: Route) usize {
    return switch (route) {
        .global => 30,
        .singleton => 48,
        .partition => 1270,
        .none => 6,
    };
}
fn nth(route: Route, k: usize) Candidate {
    const menu: usize = switch (route) {
        .global => 5,
        .singleton => 8,
        .partition => 254,
        .none => 1,
    };
    const m: u8 = if ((k / menu) % 2 == 0) 2 else 3;
    const stride: usize = switch (route) {
        .global => 5,
        .singleton => 8,
        .partition => 254,
        .none => 1,
    };
    return .{ .route = route, .a = @intCast(switch (route) {
        .global => 1 + k % 5,
        .singleton => k % 8,
        .partition => 1 + k % 254,
        .none => 0,
    }), .m = m, .r = @intCast((k / stride) % m) };
}
fn pred(c: Candidate, g: [Cells]u8) bool {
    const q = switch (c.route) {
        .global => countGE(g, c.a),
        .singleton => rank(g, c.a),
        .partition => cross(g, c.a),
        .none => adjacent(g),
    };
    return q % c.m == c.r;
}
fn score(c: Candidate, xs: []const Sample, lo: usize, hi: usize) f64 {
    var ok: usize = 0;
    for (xs[lo..hi]) |x| {
        if (pred(c, x.g) == x.y) ok += 1;
    }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo));
}
fn base(xs: []const Sample) f64 {
    var n: usize = 0;
    for (xs[Train..Val]) |x| {
        if (x.y) n += 1;
    }
    const q = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(Val - Train));
    return @max(q, 1 - q);
}
fn desc(xs: []const Sample) Desc {
    var d: Desc = undefined;
    for ([_]Route{ .global, .singleton, .partition, .none }, 0..) |r, j| {
        var best: f64 = 0;
        for (0..Probe) |i| best = @max(best, score(nth(r, (i * num(r)) / Probe), xs, 0, Train));
        const b = base(xs);
        d[j * 2] = best - b;
        d[j * 2 + 1] = 1 - best;
    }
    return d;
}
// I2-compatible symmetric admission: no cardinality branch.  In this limited
// budget experiment it can only licence partition allocation when its I1
// partition response is high; it never receives a mask, formula, or route.
fn admitPartition(d: Desc) bool {
    return d[4] >= 0.35 and d[5] <= 0.65;
}
fn weights(d: Desc) [4]f64 {
    var w: [4]f64 = undefined;
    for (0..4) |i| w[i] = @max(0.01, d[i * 2]);
    if (!admitPartition(d)) w[2] = 0.01;
    return w;
}
fn allocGuided(d: Desc) [4]usize {
    const w = weights(d);
    var sum: f64 = 0;
    for (w) |x| sum += x;
    var out: [4]usize = undefined;
    var used: usize = 0;
    for (0..4) |i| {
        out[i] = @intFromFloat(@floor(@as(f64, @floatFromInt(Extra)) * w[i] / sum));
        used += out[i];
    }
    out[0] += Extra - used;
    return out;
}
fn choose(xs: []const Sample, allocations: [4]usize, random: bool, seed: u64) struct { c: Candidate, val: f64 } {
    var best = nth(.global, 0);
    var bv: f64 = -1;
    var prng = std.Random.DefaultPrng.init(seed);
    const rr = prng.random();
    for ([_]Route{ .global, .singleton, .partition, .none }, 0..) |r, j| {
        for (0..allocations[j]) |i| {
            const ix = if (random) rr.intRangeLessThan(usize, 0, num(r)) else (i * num(r)) / @max(allocations[j], 1);
            const c = nth(r, ix);
            const v = score(c, xs, Train, Val);
            if (v > bv) {
                bv = v;
                best = c;
            }
        }
    }
    return .{ .c = best, .val = bv };
}
fn fixedAlloc() [4]usize {
    return .{ 75, 75, 75, 75 };
}
fn blindAlloc() [4]usize {
    return .{ 0, 0, 300, 0 };
} // I4 target-blind directed coverage
fn emit(out: anytype, s: Spec, xs: []const Sample, d: Desc, arm: []const u8, a: [4]usize, random: bool, trial: usize) !f64 {
    const z = choose(xs, a, random, s.seed ^ @as(u64, @intCast(trial)) *% 0x9e3779b97f4a7c15);
    const t = score(z.c, xs, Val, N);
    try out.print("{s},0x{X},{s},{d},{d},{d},{d},{d},{d},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{s}\n", .{ s.audit_id, s.seed, arm, trial, Total, a[0], a[1], a[2], a[3], z.val, t, d[0], d[1], d[2], d[3], d[4], d[5], if (t >= 0.999) "exact" else "nonexact" });
    return t;
}
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const f = try std.fs.cwd().createFile("../results/response_allocator_round_i.csv", .{ .truncate = true });
    defer f.close();
    var out = f.writer();
    try out.writeAll("target_audit_only,seed_audit,arm,trial,total_candidate_evaluations,global_alloc,singleton_alloc,partition_alloc,none_alloc,validation_accuracy,test_accuracy,g_gain,g_residual,s_gain,s_residual,p_gain,p_residual,result\n");
    var gh: usize = 0;
    var fh: usize = 0;
    var rh: usize = 0;
    var bh: usize = 0;
    for (specs) |base_spec| {
        const reps: usize = if (base_spec.heldout) 3 else 1;
        for (0..reps) |rep| {
            var s = base_spec;
            s.seed += @as(u64, @intCast(rep)) * 0x10000;
            const xs = try make(arena.allocator(), s);
            const d = desc(xs);
            const a = allocGuided(d);
            if (s.heldout) {
                const gt = try emit(out, s, xs, d, "response_guided", a, false, 0);
                const ft = try emit(out, s, xs, d, "fixed_menu", fixedAlloc(), false, 0);
                const bt = try emit(out, s, xs, d, "target_blind_coverage", blindAlloc(), false, 0);
                var mean: f64 = 0;
                for (0..16) |trial| mean += try emit(out, s, xs, d, "iid_random", fixedAlloc(), true, trial + 1);
                mean /= 16;
                if (gt >= 0.999) gh += 1;
                if (ft >= 0.999) fh += 1;
                if (bt >= 0.999) bh += 1;
                if (mean >= 0.999) rh += 1;
            }
            try out.print("DESCRIPTOR,0x{X},{s},0,{d},0,0,0,0,0,0,{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},admit_partition={s}\n", .{ s.seed, s.audit_id, 4 * Probe, d[0], d[1], d[2], d[3], d[4], d[5], if (admitPartition(d)) "yes" else "no" });
        }
    }
    try out.print("SUMMARY,-,heldout_exact,0,{d},{d},{d},{d},{d},0,0,0,0,0,0,0,response={d}/15 fixed={d}/15 random_mean_exact_targets={d}/15 coverage={d}/15; VALID_NEGATIVE\n", .{ Total, gh, fh, rh, bh, gh, fh, rh, bh });
}
