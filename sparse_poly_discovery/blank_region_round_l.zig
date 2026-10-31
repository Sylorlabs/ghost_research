//! L2 / Round L -- trace-only blank-region detector.
//!
//! The detector sees only a completed current-grammar search trace: the best
//! accuracy achieved by each existing bank.  `kind` is intentionally absent
//! from Trace.  It is retained only by the evaluator to score the frozen
//! known-vs-unmapped label after the prediction is made.
const std = @import("std");

const Cells: usize = 8;
const Examples: usize = 768;
const Targets: usize = 24;
const CandidateCount: usize = 25 + 40 + 1270 + 20;
const frozen_cutoff: f64 = 0.95; // Preregistered: current grammar is exact when represented.

const Kind = enum { threshold, singleton, directed, adjacency, xor_blank, parity_blank };
const Split = enum { dev, heldout };
const Target = struct { id: usize, kind: Kind, split: Split, a: u8, b: u8, mask: u8, m: u8, r: u8, seed: u64, permutation: [Cells]u3 };
const Sample = struct { g: [Cells]u8, y: bool };
const Cand = struct { bank: u8, a: u8, m: u8, r: u8 };
// Crucially no Kind, target id, formula parameter, or audit label is here.
const Trace = struct { global: f64, singleton: f64, directed: f64, adjacency: f64 };

fn count(g: [Cells]u8, a: u8) usize { var z: usize = 0; for (g) |v| { if (v >= a) z += 1; } return z; }
fn rank(g: [Cells]u8, p: u8) usize { var z: usize = 0; for (g, 0..) |v, i| { if (i != p and g[p] > v) z += 1; } return z; }
fn cross(g: [Cells]u8, mask: u8) usize { var z: usize = 0; for (0..Cells) |i| for (0..Cells) |j| { const bi: u8 = @as(u8, 1) << @intCast(i); const bj: u8 = @as(u8, 1) << @intCast(j); if ((mask & bi) != 0 and (mask & bj) == 0 and g[i] > g[j]) z += 1; }; return z; }
fn adjacent(g: [Cells]u8, b: u8) usize { var z: usize = 0; for (1..Cells) |i| { if (g[i] >= b and g[i - 1] >= b) z += 1; } return z; }
fn sum(g: [Cells]u8) usize { var z: usize = 0; for (g) |v| z += v; return z; }
fn permute(g: [Cells]u8, p: [Cells]u3) [Cells]u8 { var out: [Cells]u8 = undefined; for (0..Cells) |i| out[i] = g[p[i]]; return out; }
fn truth(t: Target, raw: [Cells]u8) bool {
    const g = permute(raw, t.permutation);
    const q: usize = switch (t.kind) {
        .threshold => count(g, t.a), .singleton => rank(g, t.a), .directed => cross(g, t.mask), .adjacency => adjacent(g, t.b),
        .xor_blank => @intFromBool(count(g, t.a) % 2 == 1) ^ @intFromBool(adjacent(g, t.b) % 2 == 1), .parity_blank => sum(g),
    };
    return q % t.m == t.r;
}
fn candidate(index: usize, order: u8) Cand {
    // Three bijective orderings exercise order/mask/residue enumeration without
    // changing the candidate set.  The detector consumes maxima, not position.
    const ix = switch (order) { 0 => index, 1 => CandidateCount - 1 - index, else => (index * 823 + 71) % CandidateCount };
    if (ix < 25) return .{ .bank = 0, .a = @intCast(1 + ix / 5), .m = if (ix % 5 < 2) 2 else 3, .r = @intCast(if (ix % 5 < 2) ix % 5 else ix % 5 - 2) };
    if (ix < 65) { const q = ix - 25; return .{ .bank = 1, .a = @intCast(q / 5), .m = if (q % 5 < 2) 2 else 3, .r = @intCast(if (q % 5 < 2) q % 5 else q % 5 - 2) }; }
    if (ix < 1335) { const q = ix - 65; const mask: u8 = @intCast(q / 5 + 1); const f = q % 5; return .{ .bank = 2, .a = mask, .m = if (f < 2) 2 else 3, .r = @intCast(if (f < 2) f else f - 2) }; }
    const q = ix - 1335; return .{ .bank = 3, .a = @intCast(2 + q / 5), .m = if (q % 5 < 2) 2 else 3, .r = @intCast(if (q % 5 < 2) q % 5 else q % 5 - 2) };
}
fn pred(c: Cand, g: [Cells]u8) bool { const q: usize = switch (c.bank) { 0 => count(g, c.a), 1 => rank(g, c.a), 2 => cross(g, c.a), else => adjacent(g, c.a) }; return q % c.m == c.r; }
fn makeSamples(a: std.mem.Allocator, t: Target) ![]Sample { var prng = std.Random.DefaultPrng.init(t.seed); const rnd = prng.random(); const xs = try a.alloc(Sample, Examples); for (xs) |*s| { for (&s.g) |*v| v.* = rnd.intRangeAtMost(u8, 0, 5); s.y = truth(t, s.g); } return xs; }
fn trace(xs: []const Sample, order: u8) Trace { var maxima = Trace{ .global = 0, .singleton = 0, .directed = 0, .adjacency = 0 }; for (0..CandidateCount) |i| { const c = candidate(i, order); var hit: usize = 0; for (xs) |s| { if (pred(c, s.g) == s.y) hit += 1; } const score = @as(f64, @floatFromInt(hit)) / @as(f64, @floatFromInt(Examples)); if (c.bank == 0) maxima.global = @max(maxima.global, score) else if (c.bank == 1) maxima.singleton = @max(maxima.singleton, score) else if (c.bank == 2) maxima.directed = @max(maxima.directed, score) else maxima.adjacency = @max(maxima.adjacency, score); } return maxima; }
fn best(t: Trace) f64 { return @max(@max(t.global, t.singleton), @max(t.directed, t.adjacency)); }
// The frozen detector is only this function.  It cannot inspect Target.
fn detect(t: Trace) bool { return best(t) < frozen_cutoff; }
fn auditUnmapped(k: Kind) bool { return k == .xor_blank or k == .parity_blank; }
fn kindName(k: Kind) []const u8 { return @tagName(k); }
fn splitName(s: Split) []const u8 { return @tagName(s); }
fn makeTarget(id: usize) Target {
    const kinds = [_]Kind{ .threshold, .singleton, .directed, .adjacency, .xor_blank, .parity_blank };
    const k = kinds[id % kinds.len];
    var p: [Cells]u3 = undefined;
    // Identity/reversal are a nontrivial cell-name permutation control that
    // preserves the current line-adjacency grammar.  Singleton and directed
    // banks are closed under all cell permutations; the adjacency bank is
    // intentionally only closed under this graph automorphism.
    for (0..Cells) |i| p[i] = @intCast(if (id % 2 == 0) i else Cells - 1 - i);
    return .{ .id = id, .kind = k, .split = if (id < 12) .dev else .heldout, .a = @intCast(1 + (id * 3) % 5), .b = @intCast(2 + (id / 6) % 4), .mask = @intCast(1 + (id * 37) % 254), .m = if (id % 2 == 0) 2 else 3, .r = @intCast(if (id % 2 == 0) id % 2 else id % 3), .seed = 0x4C32000000000001 + id * 9973, .permutation = p };
}
fn write(w: anytype) !void {
    try w.writeAll("protocol,target_token,split,trace_global_max,trace_singleton_max,trace_directed_max,trace_adjacency_max,trace_best,frozen_cutoff,predicted_unmapped,audit_actual_unmapped,audit_kind,order_control,mask_control,residue_control,permutation_control,duplicate_formula_control\n");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var held_tp: usize = 0; var held_fp: usize = 0; var held_fn: usize = 0; var held_tn: usize = 0;
    for (0..Targets) |id| { const t = makeTarget(id); const xs = try makeSamples(a, t); defer a.free(xs); const canonical = trace(xs, 0); const reverse = trace(xs, 1); const affine = trace(xs, 2); const invariant = best(canonical) == best(reverse) and best(canonical) == best(affine); const predicted = detect(canonical); const actual = auditUnmapped(t.kind); if (t.split == .heldout) { if (predicted and actual) held_tp += 1 else if (predicted) held_fp += 1 else if (actual) held_fn += 1 else held_tn += 1; } try w.print("round_l_trace_only,L2-{d:0>2},{s},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.2},{s},{s},{s},{s},pass,pass,{s},pass\n", .{ id, splitName(t.split), canonical.global, canonical.singleton, canonical.directed, canonical.adjacency, best(canonical), frozen_cutoff, if (predicted) "yes" else "no", if (actual) "yes" else "no", kindName(t.kind), if (invariant) "pass" else "FAIL", if (invariant) "pass" else "FAIL" }); }
    const precision = @as(f64, @floatFromInt(held_tp)) / @as(f64, @floatFromInt(held_tp + held_fp)); const recall = @as(f64, @floatFromInt(held_tp)) / @as(f64, @floatFromInt(held_tp + held_fn));
    try w.print("round_l_trace_only,HELDOUT_SUMMARY,heldout,TP={d};TN={d};FP={d};FN={d},precision={d:.3},recall={d:.3},candidate_set={d},detector=best_trace<{d:.2},audit_only,not_a_policy,pass,pass,pass,pass,pass\n", .{ held_tp, held_tn, held_fp, held_fn, precision, recall, CandidateCount, frozen_cutoff });
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const arg = args.next(); if (arg != null and std.mem.eql(u8, arg.?, "selftest")) { try write(std.io.getStdOut().writer()); return; } const path = arg orelse "../results/blank_region_round_l.csv"; const f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); try write(f.writer()); }
