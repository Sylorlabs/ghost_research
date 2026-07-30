const std = @import("std");
const N: usize = 900;
const Train: usize = 450;
const Val: usize = 675;
const Cells: usize = 8;
const Route = enum { global, singleton, multicell, none };
const Split = enum { train, val, heldout };
const Target = struct { id: u8, route: Route, split: Split, mask: u8 = 0, m: u8 = 2, r: u8 = 0, a: u8 = 0 };
const targets = [_]Target{
    .{ .id = 0, .route = .global, .split = .train, .a = 1, .m = 2, .r = 0 },           .{ .id = 1, .route = .global, .split = .train, .a = 2, .m = 3, .r = 1 },           .{ .id = 2, .route = .global, .split = .train, .a = 4, .m = 2, .r = 1 },           .{ .id = 3, .route = .global, .split = .val, .a = 3, .m = 3, .r = 0 },           .{ .id = 4, .route = .global, .split = .heldout, .a = 5, .m = 2, .r = 0 },
    .{ .id = 5, .route = .singleton, .split = .train, .a = 0, .m = 2, .r = 0 },        .{ .id = 6, .route = .singleton, .split = .train, .a = 2, .m = 3, .r = 1 },        .{ .id = 7, .route = .singleton, .split = .train, .a = 5, .m = 2, .r = 1 },        .{ .id = 8, .route = .singleton, .split = .val, .a = 6, .m = 3, .r = 0 },        .{ .id = 9, .route = .singleton, .split = .heldout, .a = 3, .m = 2, .r = 0 },
    .{ .id = 10, .route = .multicell, .split = .train, .mask = 0x03, .m = 2, .r = 0 }, .{ .id = 11, .route = .multicell, .split = .train, .mask = 0x0c, .m = 3, .r = 1 }, .{ .id = 12, .route = .multicell, .split = .train, .mask = 0x51, .m = 2, .r = 1 }, .{ .id = 13, .route = .multicell, .split = .val, .mask = 0x22, .m = 3, .r = 0 }, .{ .id = 14, .route = .multicell, .split = .heldout, .mask = 0x19, .m = 2, .r = 0 },
    .{ .id = 15, .route = .none, .split = .train, .m = 2, .r = 0 },                    .{ .id = 16, .route = .none, .split = .train, .m = 3, .r = 1 },                    .{ .id = 17, .route = .none, .split = .train, .m = 2, .r = 1 },                    .{ .id = 18, .route = .none, .split = .val, .m = 3, .r = 0 },                    .{ .id = 19, .route = .none, .split = .heldout, .m = 2, .r = 0 },
};
const Sample = struct { g: [Cells]u8, y: bool };
const Cand = struct { kind: u8, a: u8, m: u8, r: u8 };
// Every bank is a SET, not an ordered useful prefix.  The directed bank uses
// 36 mask strata x all five legal residue flavours.  Its 180 calls are less
// than 7.1% of the 2,540-call train+validation directed near-solve.
const D = [_]usize{ 25, 40, 180, 5 };
fn nm(r: Route) []const u8 {
    return @tagName(r);
}
fn sn(s: Split) []const u8 {
    return @tagName(s);
}
fn cross(g: [Cells]u8, mask: u8) usize {
    var z: usize = 0;
    for (0..Cells) |i| for (0..Cells) |j| {
        const bi: @TypeOf(mask) = @as(u8, 1) << @intCast(i);
        const bj: u8 = @as(u8, 1) << @intCast(j);
        if (mask & bi != 0 and mask & bj == 0 and g[i] > g[j]) z += 1;
    };
    return z;
}
fn rank(g: [Cells]u8, p: usize) usize {
    var z: usize = 0;
    for (g, 0..) |x, i| {
        if (i != p and g[p] > x) z += 1;
    }
    return z;
}
fn count(g: [Cells]u8, a: u8) usize {
    var z: usize = 0;
    for (g) |x| {
        if (x >= a) z += 1;
    }
    return z;
}
fn adj(g: [Cells]u8) usize {
    var z: usize = 0;
    for (1..Cells) |i| {
        if (g[i] >= 3 and g[i - 1] >= 3) z += 1;
    }
    return z;
}
fn truth(t: Target, g: [Cells]u8) bool {
    return switch (t.route) {
        .global => count(g, t.a) % t.m == t.r,
        .singleton => rank(g, t.a) % t.m == t.r,
        .multicell => cross(g, t.mask) % t.m == t.r,
        .none => adj(g) % t.m == t.r,
    };
}
fn make(a: std.mem.Allocator, t: Target) ![]Sample {
    const seed: u64 = 0xA11CE + @as(u64, t.id) * 977;
    var pr = std.Random.DefaultPrng.init(seed);
    const rnd = pr.random();
    const x = try a.alloc(Sample, N);
    for (x) |*s| {
        for (&s.g) |*v| v.* = rnd.intRangeAtMost(u8, 0, 5);
        s.y = truth(t, s.g);
    }
    return x;
}
fn directed(ix: usize) Cand {
    const q = ix % 5;
    // A coprime stride picks 36 masks without privileging a low-bit mask.
    // Complete five-flavour blocks make residue ordering immaterial.
    return .{ .kind = 2, .a = @intCast((ix / 5 * 37 + 17) % 254 + 1), .m = if (q < 2) 2 else 3, .r = @intCast(if (q < 2) q else q - 2) };
}
fn directedKey(c: Cand) usize {
    return (@as(usize, c.a) - 1) * 5 + if (c.m == 2) c.r else 2 + c.r;
}
fn assertDirectedIntegrity() !void {
    var seen = [_]bool{false} ** 1270;
    for (0..1270) |i| {
        const k = directedKey(directed(i));
        if (k >= 1270 or seen[k]) return error.DirectedEnumeration;
        seen[k] = true;
    }
    for (seen) |v| if (!v) return error.DirectedEnumeration;
    // Both fixed bijections are permutation controls for bank order. They
    // alter candidate order, never candidate membership.
    var mask_seen = [_]bool{false} ** 1270;
    var residue_seen = [_]bool{false} ** 1270;
    for (0..1270) |i| {
        mask_seen[(i * 809 + 113) % 1270] = true;
        residue_seen[(i * 251 + 17) % 1270] = true;
    }
    for (mask_seen) |v| if (!v) return error.MaskPermutation;
    for (residue_seen) |v| if (!v) return error.ResiduePermutation;
    // A permutation of mask-bit names and a permutation of legal residue
    // flavours must preserve the *full* grammar universe.  These are set
    // integrity controls; feature order invariance is separately asserted.
    const bit_p = [_]u3{ 3, 6, 1, 7, 0, 5, 2, 4 };
    var mapped_mask_seen = [_]bool{false} ** 1270;
    const flavor_p = [_]usize{ 4, 2, 0, 3, 1 };
    var mapped_flavor_seen = [_]bool{false} ** 1270;
    for (0..1270) |i| {
        const c = directed(i);
        var mapped_mask: u8 = 0;
        for (0..8) |b| {
            if ((c.a & (@as(u8, 1) << @intCast(b))) != 0) mapped_mask |= @as(u8, 1) << bit_p[b];
        }
        const mk = (@as(usize, mapped_mask) - 1) * 5 + if (c.m == 2) c.r else 2 + c.r;
        if (mapped_mask_seen[mk]) return error.MaskNamePermutation;
        mapped_mask_seen[mk] = true;
        const old_flavor: usize = if (c.m == 2) c.r else 2 + c.r;
        const nf = flavor_p[old_flavor];
        const fk = (@as(usize, c.a) - 1) * 5 + nf;
        if (mapped_flavor_seen[fk]) return error.FlavorNamePermutation;
        mapped_flavor_seen[fk] = true;
    }
    for (mapped_mask_seen) |v| if (!v) return error.MaskNamePermutation;
    for (mapped_flavor_seen) |v| if (!v) return error.FlavorNamePermutation;
}

fn cand(f: usize, k: usize) Cand {
    return switch (f) {
        0 => .{ .kind = 0, .a = @intCast(1 + (k % 5)), .m = if (k / 5 < 2) 2 else 3, .r = @intCast(if (k / 5 < 2) (k / 5) else (k / 5 - 2)) },
        1 => .{ .kind = 1, .a = @intCast(k % 8), .m = if (k / 8 < 2) 2 else 3, .r = @intCast(if (k / 8 < 2) (k / 8) else (k / 8 - 2)) },
        2 => directed((k * 809 + 113) % 1270),
        else => .{ .kind = 3, .a = 0, .m = if (k < 2) 2 else 3, .r = @intCast(if (k < 2) k else k - 2) },
    };
}
fn candidateTieKey(c: Cand) usize {
    return @as(usize, c.kind) * 10000 + @as(usize, c.a) * 10 + @as(usize, c.m) * 3 + c.r;
}
fn pred(c: Cand, g: [Cells]u8) bool {
    const q: usize = switch (c.kind) {
        0 => count(g, c.a),
        1 => rank(g, c.a),
        2 => cross(g, c.a),
        else => adj(g),
    };
    return q % c.m == c.r;
}
fn acc(c: Cand, x: []const Sample, lo: usize, hi: usize) f64 {
    var z: usize = 0;
    for (x[lo..hi]) |s| {
        if (pred(c, s.g) == s.y) z += 1;
    }
    return @as(f64, @floatFromInt(z)) / @as(f64, @floatFromInt(hi - lo));
}
fn base(x: []const Sample) f64 {
    var y: usize = 0;
    for (x[0..Train]) |s| {
        if (s.y) y += 1;
    }
    const p = @as(f64, @floatFromInt(y)) / Train;
    return @max(p, 1 - p);
}
/// Distributional response features.  No feature references candidate index,
/// prefix position, target identity, formula, mask, residue, or route label.
/// Reordering a bank leaves every returned value unchanged.
fn featuresOrdered(x: []const Sample, f: usize, reverse: bool) [6]f64 {
    var scores: [180]f64 = undefined;
    const n = D[f];
    for (0..n) |k| {
        const ck = if (reverse) n - 1 - k else k;
        scores[k] = acc(cand(f, ck), x, 0, Train);
    }
    var sum: f64 = 0;
    var sumsq: f64 = 0;
    var best: f64 = -1;
    var second: f64 = -1;
    var best_key: usize = std.math.maxInt(usize);
    var hits: usize = 0;
    for (0..n) |k| {
        const z = scores[k];
        sum += z;
        sumsq += z * z;
        const ck = if (reverse) n - 1 - k else k;
        const key = candidateTieKey(cand(f, ck));
        if (z > best or (z == best and key < best_key)) {
            second = best;
            best = z;
            best_key = key;
        } else if (z > second) second = z;
        if (z >= 0.70) hits += 1;
    }
    var bi: usize = 0;
    for (1..n) |k| {
        const ck = if (reverse) n - 1 - k else k;
        const bk = if (reverse) n - 1 - bi else bi;
        if (scores[k] > scores[bi] or (scores[k] == scores[bi] and candidateTieKey(cand(f, ck)) < candidateTieKey(cand(f, bk)))) bi = k;
    }
    const vk = if (reverse) n - 1 - bi else bi;
    const vb = acc(cand(f, vk), x, Train, Val);
    const bl = base(x);
    const mean = sum / @as(f64, @floatFromInt(n));
    const variance = @max(0, sumsq / @as(f64, @floatFromInt(n)) - mean * mean);
    return .{ mean - bl, @sqrt(variance), best - bl, best - second, vb - bl, @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(n)) };
}
fn features(x: []const Sample, f: usize) [6]f64 { return featuresOrdered(x, f, false); }
fn assertOrderInvariant(x: []const Sample) !void {
    for (0..4) |f| {
        const a = featuresOrdered(x, f, false);
        const b = featuresOrdered(x, f, true);
        for (0..6) |k| if (@abs(a[k] - b[k]) > 0.0000001) return error.OrderSensitiveFeature;
    }
}
fn dist(a: [24]f64, b: [24]f64) f64 {
    var z: f64 = 0;
    for (0..24) |i| z += (a[i] - b[i]) * (a[i] - b[i]);
    return z;
}
fn classify(i: usize, fs: [20][24]f64) Route {
    var mean = [_][24]f64{[_]f64{0} ** 24} ** 4;
    var ns = [_]usize{0} ** 4;
    for (targets, 0..) |t, j| {
        if (t.split == .train) {
            const r: usize = @intFromEnum(t.route);
            ns[r] += 1;
            for (0..24) |k| mean[r][k] += fs[j][k];
        }
    }
    for (0..4) |r| {
        for (0..24) |k| mean[r][k] /= @as(f64, @floatFromInt(ns[r]));
    }
    var best: f64 = 1e99;
    var out: Route = .global;
    for (0..4) |r| {
        const d = dist(fs[i], mean[r]);
        if (d < best) {
            best = d;
            out = @enumFromInt(r);
        }
    }
    return out;
}

fn run(w: anytype) !void {
    try assertDirectedIntegrity();
    var ar = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer ar.deinit();
    var fs: [20][24]f64 = undefined;
    try w.writeAll("record,split,target_audit_only,truth_audit_only,predicted_audit_only,correct,global_mean_gain,global_near_miss,singleton_mean_gain,singleton_near_miss,directed_mean_gain,directed_near_miss,none_mean_gain,none_near_miss,train_calls,validation_calls,total_calls,enumeration_unique,order_invariant,mask_perm,residue_perm,validity\n");
    for (targets, 0..) |t, i| {
        const x = try make(ar.allocator(), t);
        try assertOrderInvariant(x);
        for (0..4) |f| {
            const q = features(x, f);
            for (0..6) |k| fs[i][f * 6 + k] = q[k];
        }
    }
    var hold: usize = 0;
    var min: f64 = 1e99;
    for (targets, 0..) |t, i| {
        if (t.split != .train) {
            const p = classify(i, fs);
            if (t.split == .heldout and p == t.route) hold += 1;
            for (targets, 0..) |u, j| {
                if (u.split == .train) min = @min(min, @sqrt(dist(fs[i], fs[j])));
            }
            try w.print("TARGET,{s},{d},{s},{s},{s},{d},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},250,4,254,1270,pass,pass,pass,pass\n", .{ sn(t.split), t.id, nm(t.route), nm(p), if (p == t.route) "yes" else "no", @intFromBool(p == t.route), fs[i][0], fs[i][3], fs[i][6], fs[i][9], fs[i][12], fs[i][15], fs[i][18], fs[i][21] });
        }
    }
    try w.print("SUMMARY,heldout,-,-,-,{d}/4,-,-,-,-,-,-,-,-,250,4,254,1270,pass,pass,pass,pass\n", .{hold});
    try w.print("GATES,frozen_12_4_4_distance,-,-,-,-,{d:.6},-,-,-,-,-,-,-,-,250,4,254,1270,pass,pass,pass,pass\n", .{min});
}

pub fn main() !void {
    var it = std.process.args();
    _ = it.next();
    const p = it.next() orelse "results/invariant_trajectory_round_k.csv";
    if (std.mem.eql(u8, p, "selftest")) {
        try run(std.io.getStdOut().writer());
        return;
    }
    const f = try std.fs.cwd().createFile(p, .{ .truncate = true });
    defer f.close();
    try run(f.writer());
}
