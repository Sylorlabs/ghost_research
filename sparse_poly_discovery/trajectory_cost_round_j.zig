//! J3 / Round J: lower bound on the cost of target-blind prefix responses.
//!
//! The directed grammar is exactly 254 nontrivial masks times five legal
//! modulus/residue choices = 1,270 unique candidates.  A response is only the
//! best validation accuracy seen in a fixed prefix.  The reporting classifier
//! never receives the target kind, mask, or residue; labels are used only after
//! the run to score directed-reach versus directed-absent separation.
const std = @import("std");

const N: usize = 2400;
const TRAIN: usize = 1200;
const VAL: usize = 1800;
const CELLS: usize = 8;
const MAX: usize = 1270;
const budgets = [_]usize{ 8, 16, 32, 64, 128, 256, 635, 1270 };
const seeds = [_]u64{ 0xA300000000000001, 0xA300000000000002, 0xA300000000000003 };

const Sample = struct { g: [CELLS]u8, y: bool };
const Candidate = struct { mask: u8, modulus: u8, residue: u8 };
const Target = enum { global, singleton, multicell, no_grammar };
const Order = enum { base, mask_permuted, residue_permuted };

fn name(t: Target) []const u8 { return @tagName(t); }
fn orderName(o: Order) []const u8 { return @tagName(o); }
fn count(g: [CELLS]u8, mask: u8) usize {
    var n: usize = 0;
    for (0..CELLS) |i| for (0..CELLS) |j| {
        const a: u8 = @as(u8, 1) << @intCast(i);
        const b: u8 = @as(u8, 1) << @intCast(j);
        if ((mask & a) != 0 and (mask & b) == 0 and g[i] > g[j]) n += 1;
    };
    return n;
}
fn global(g: [CELLS]u8) bool { var n: usize = 0; for (g) |v| { if (v >= 3) n += 1; } return n % 2 == 0; }
fn oracle(t: Target, g: [CELLS]u8) bool {
    return switch (t) {
        .global => global(g),
        .singleton => count(g, 0x08) % 3 == 1,
        .multicell => count(g, 0x33) % 2 == 1,
        .no_grammar => (g[0] +% g[2] +% g[5]) % 5 < 2,
    };
}
fn make(a: std.mem.Allocator, seed: u64, t: Target) ![]Sample {
    var p = std.Random.DefaultPrng.init(seed ^ (@as(u64, @intFromEnum(t)) *% 0x9E3779B97F4A7C15));
    const r = p.random(); const xs = try a.alloc(Sample, N);
    for (xs) |*x| { for (0..CELLS) |i| x.g[i] = r.intRangeAtMost(u8, 0, 5); x.y = oracle(t, x.g); }
    return xs;
}
fn baseAt(k: usize) Candidate {
    std.debug.assert(k < MAX);
    const mask: u8 = @intCast(k / 5 + 1);
    const rem = k % 5;
    return .{ .mask = mask, .modulus = if (rem < 2) 2 else 3, .residue = @intCast(if (rem < 2) rem else rem - 2) };
}
fn swapBits(mask: u8) u8 { // frozen target-blind permutation: 0<->7, 1<->6
    var z: u8 = 0;
    for (0..CELLS) |i| { const dst: usize = switch (i) { 0 => 7, 7 => 0, 1 => 6, 6 => 1, else => i }; if ((mask & (@as(u8, 1) << @intCast(i))) != 0) z |= @as(u8, 1) << @intCast(dst); }
    return z;
}
fn candidateAt(i: usize, o: Order) Candidate {
    // Coprime stride visits all 1,270 elements once; transformations only
    // reorder the same exact grammar, never use target data.
    var c = baseAt((i * 809 + 113) % MAX);
    switch (o) {
        .base => {},
        .mask_permuted => c.mask = swapBits(c.mask),
        .residue_permuted => c.residue = if (c.modulus == 2) 1 - c.residue else (c.residue + 1) % 3,
    }
    return c;
}
fn assertUnique(o: Order) void {
    var seen = [_]bool{false} ** MAX;
    for (0..MAX) |i| { const c = candidateAt(i, o); const idx: usize = (@as(usize, c.mask) - 1) * 5 + (if (c.modulus == 2) c.residue else 2 + c.residue); std.debug.assert(idx < MAX and !seen[idx]); seen[idx] = true; }
    for (seen) |v| std.debug.assert(v);
}
fn score(c: Candidate, xs: []const Sample, lo: usize, hi: usize) f64 {
    var ok: usize = 0; for (xs[lo..hi]) |x| { if ((count(x.g, c.mask) % c.modulus == c.residue) == x.y) ok += 1; }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo));
}
const Response = struct { best_val: f64, test_acc: f64, reach: bool };
fn prefix(xs: []const Sample, b: usize, o: Order) Response {
    var best = candidateAt(0, o); var bv: f64 = -1;
    // Every candidate gets one train and one validation response.  Thus the
    // reported candidate-call cost is 2*B and B=1270 is the I2 2,540-call
    // full-scan reference, rather than a cheaper one-split shortcut.
    for (0..b) |i| { const c = candidateAt(i, o); const s = (score(c, xs, 0, TRAIN) + score(c, xs, TRAIN, VAL)) / 2.0; if (s > bv) { bv = s; best = c; } }
    const tst = score(best, xs, VAL, N);
    return .{ .best_val = bv, .test_acc = tst, .reach = tst >= 0.999 };
}
fn randomPrefix(xs: []const Sample, b: usize, seed: u64) Response {
    var p = std.Random.DefaultPrng.init(seed);
    const rnd = p.random();
    var best = baseAt(0); var bv: f64 = -1;
    for (0..b) |_| {
        const c = baseAt(rnd.intRangeLessThan(usize, 0, MAX));
        const s = (score(c, xs, 0, TRAIN) + score(c, xs, TRAIN, VAL)) / 2.0;
        if (s > bv) { bv = s; best = c; }
    }
    const tst = score(best, xs, VAL, N);
    return .{ .best_val = bv, .test_acc = tst, .reach = tst >= 0.999 };
}
fn expectedDirected(t: Target) bool { return t == .singleton or t == .multicell; }
fn run(out: anytype, a: std.mem.Allocator, t: Target, seed: u64, b: usize, o: Order) !void {
    const xs = try make(a, seed, t); const r = prefix(xs, b, o);
    // The only response feature is best_val.  The fixed 0.999 decision is
    // predeclared and represents an exact grammar member, not target metadata.
    const predicted = r.best_val >= 0.999;
    const sep = predicted == expectedDirected(t);
    try out.print("{s},0x{X:0>16},{d},{s},{d},{d:.4},{d:.4},{s},{s},{s}\n", .{ name(t), seed, b, orderName(o), 2 * b, r.best_val, r.test_acc, if (r.reach) "YES" else "NO", if (sep) "YES" else "NO", if (predicted) "directed" else "absent" });
}
fn runRandom(out: anytype, a: std.mem.Allocator, t: Target, seed: u64, b: usize, trial: usize) !void {
    const xs = try make(a, seed, t);
    // The iid stream is deliberately independent of t.  It is a weak
    // target-blind coverage control, logged as four fixed replications.
    const r = randomPrefix(xs, b, seed ^ (@as(u64, @intCast(b)) *% 0xD1B54A32D192ED03) ^ @as(u64, @intCast(trial + 1)));
    const predicted = r.best_val >= 0.999;
    const sep = predicted == expectedDirected(t);
    try out.print("{s},0x{X:0>16},{d},random_iid_{d},{d},{d:.4},{d:.4},{s},{s},{s}\n", .{ name(t), seed, b, trial, 2 * b, r.best_val, r.test_acc, if (r.reach) "YES" else "NO", if (sep) "YES" else "NO", if (predicted) "directed" else "absent" });
}
pub fn main() !void {
    assertUnique(.base); assertUnique(.mask_permuted); assertUnique(.residue_permuted);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit();
    const f = try std.fs.cwd().createFile("../results/trajectory_cost_round_j.csv", .{ .truncate = true }); defer f.close(); var out = f.writer();
    try out.writeAll("target,seed,budget,order,candidate_calls,best_validation_accuracy,test_accuracy,exact_reach,correct_directed_separation,response_decision\n");
    for (seeds) |seed| for ([_]Target{ .global, .singleton, .multicell, .no_grammar }) |t| for (budgets) |b| {
        for ([_]Order{ .base, .mask_permuted, .residue_permuted }) |o| try run(out, arena.allocator(), t, seed, b, o);
        for (0..4) |trial| try runRandom(out, arena.allocator(), t, seed, b, trial);
    };
}
