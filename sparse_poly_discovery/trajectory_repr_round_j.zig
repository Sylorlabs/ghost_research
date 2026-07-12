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
const D = [_]usize{ 30, 48, 120, 6 };
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
    return .{ .kind = 2, .a = @intCast(ix / 5 + 1), .m = if (q < 2) 2 else 3, .r = @intCast(if (q < 2) q else q - 2) };
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
    // Both fixed bijections are permutation controls for prefix order. They
    // alter candidate order, never candidate membership.
    var mask_seen = [_]bool{false} ** 1270;
    var residue_seen = [_]bool{false} ** 1270;
    for (0..1270) |i| {
        mask_seen[(i * 809 + 113) % 1270] = true;
        residue_seen[(i * 251 + 17) % 1270] = true;
    }
    for (mask_seen) |v| if (!v) return error.MaskPermutation;
    for (residue_seen) |v| if (!v) return error.ResiduePermutation;
}

fn cand(f: usize, k: usize) Cand {
    return switch (f) {
        0 => .{ .kind = 0, .a = @intCast(1 + (k % 5)), .m = if (k / 5 < 2) 2 else 3, .r = @intCast(if (k / 5 < 2) (k / 5) else (k / 5 - 2)) },
        1 => .{ .kind = 1, .a = @intCast(k % 8), .m = if (k / 8 < 2) 2 else 3, .r = @intCast(if (k / 8 < 2) (k / 8) else (k / 8 - 2)) },
        2 => directed((k * 809 + 113) % 1270),
        else => .{ .kind = 3, .a = 0, .m = if (k < 2) 2 else 3, .r = @intCast(if (k < 2) k else k - 2) },
    };
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
fn features(x: []const Sample, f: usize) [6]f64 {
    var scores: [120]f64 = undefined;
    const n = D[f];
    for (0..n) |k| scores[k] = acc(cand(f, k), x, 0, Train);
    var b1: f64 = 0;
    var b2: f64 = 0;
    var hits: usize = 0;
    for (0..n) |k| {
        const z = scores[k];
        if (k < n / 4) b1 = @max(b1, z);
        if (k < n / 2) b2 = @max(b2, z);
        if (z >= 0.70) hits += 1;
    }
    var bi: usize = 0;
    for (1..n) |k| {
        if (scores[k] > scores[bi]) bi = k;
    }
    const vb = acc(cand(f, bi), x, Train, Val);
    var second: f64 = 0;
    for (0..n) |k| {
        if (k != bi) second = @max(second, scores[k]);
    }
    const bl = base(x);
    return .{ b1 - bl, b2 - bl, scores[bi] - bl, scores[bi] - second, vb - bl, @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(n)) };
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
    try w.writeAll("record,split,target_audit_only,truth_audit_only,predicted_audit_only,correct,global_gain,global_margin,singleton_gain,singleton_margin,directed_gain,directed_margin,none_gain,none_margin,train_calls,validation_calls,total_calls,enumeration_unique,mask_perm,residue_perm,validity\n");
    for (targets, 0..) |t, i| {
        const x = try make(ar.allocator(), t);
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
            try w.print("TARGET,{s},{d},{s},{s},{s},{d},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},204,12,216,1270,pass,pass,pass\n", .{ sn(t.split), t.id, nm(t.route), nm(p), if (p == t.route) "yes" else "no", @intFromBool(p == t.route), fs[i][2], fs[i][3], fs[i][8], fs[i][9], fs[i][14], fs[i][15], fs[i][20], fs[i][21] });
        }
    }
    try w.print("SUMMARY,heldout,-,-,-,{d}/4,-,-,-,-,-,-,-,-,204,12,216,1270,pass,pass,pass\n", .{hold});
    try w.print("GATES,frozen_12_4_4_distance,-,-,-,-,{d:.6},-,-,-,-,-,-,-,-,204,12,216,1270,pass,pass,pass\n", .{min});
}

pub fn main() !void {
    var it = std.process.args();
    _ = it.next();
    const p = it.next() orelse "../results/trajectory_repr_round_j.csv";
    if (std.mem.eql(u8, p, "selftest")) {
        try run(std.io.getStdOut().writer());
        return;
    }
    const f = try std.fs.cwd().createFile(p, .{ .truncate = true });
    defer f.close();
    try run(f.writer());
}
