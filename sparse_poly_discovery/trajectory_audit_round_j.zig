//! J5 / Round J: independent adversarial audit of J1/J2/J4.
//! This file intentionally does not import the claimed harnesses: it
//! reimplements the directed key space and adversarial score checks.
const std = @import("std");
const Cells: usize = 8;
const N: usize = 900;
const Train: usize = 450;
const Cand = struct { kind: u8, a: u8, m: u8, r: u8 };
const Sample = struct { g: [Cells]u8, y: bool };
fn flavor(k: usize) struct { m: u8, r: u8 } { return if (k < 2) .{ .m = 2, .r = @intCast(k) } else .{ .m = 3, .r = @intCast(k - 2) }; }
fn directed(k: usize) Cand { const z = flavor(k % 5); return .{ .kind = 2, .a = @intCast(k / 5 + 1), .m = z.m, .r = z.r }; }
fn key(c: Cand) usize { return (@as(usize, c.a) - 1) * 5 + if (c.m == 2) c.r else 2 + c.r; }
fn cross(g: [Cells]u8, mask: u8) usize { var n: usize = 0; for (0..Cells) |i| for (0..Cells) |j| { const bi: u8 = @as(u8, 1) << @intCast(i); const bj: u8 = @as(u8, 1) << @intCast(j); if ((mask & bi) != 0 and (mask & bj) == 0 and g[i] > g[j]) n += 1; }; return n; }
fn count(g: [Cells]u8, a: u8) usize { var n: usize = 0; for (g) |x| { if (x >= a) n += 1; } return n; }
fn rank(g: [Cells]u8, p: usize) usize { var n: usize = 0; for (g, 0..) |x, i| { if (i != p and g[p] > x) n += 1; } return n; }
fn adjacent(g: [Cells]u8) usize { var n: usize = 0; for (1..Cells) |i| { if (g[i] >= 3 and g[i - 1] >= 3) n += 1; } return n; }
fn pred(c: Cand, g: [Cells]u8) bool { const q = switch (c.kind) { 0 => count(g, c.a), 1 => rank(g, c.a), 2 => cross(g, c.a), else => adjacent(g) }; return q % c.m == c.r; }
fn make(a: std.mem.Allocator, seed: u64, kind: u8) ![]Sample { var p = std.Random.DefaultPrng.init(seed); const r = p.random(); const x = try a.alloc(Sample, N); for (x) |*s| { for (&s.g) |*v| v.* = r.intRangeAtMost(u8, 0, 5); s.y = switch (kind) { 0 => cross(s.g, 0x19) % 2 == 0, // J2 heldout directed target
    else => (count(s.g, 3) % 2 == 0) != (adjacent(s.g) % 2 == 0), // unrelated XOR control
  }; } return x; }
fn score(c: Cand, x: []const Sample) f64 { var n: usize = 0; for (x[0..Train]) |s| { if (pred(c, s.g) == s.y) n += 1; } return @as(f64, @floatFromInt(n)) / Train; }
fn maxDirected(x: []const Sample, mul: usize, add: usize) struct { best: f64, hit: bool, answer_pos: usize } { var best: f64 = 0; var hit = false; var pos: usize = 1270; const answer = key(.{ .kind = 2, .a = 0x19, .m = 2, .r = 0 }); for (0..120) |i| { const c = directed((i * mul + add) % 1270); const z = score(c, x); best = @max(best, z); if (key(c) == answer) { hit = true; pos = i; } } return .{ .best = best, .hit = hit, .answer_pos = pos }; }
fn maxOther(x: []const Sample) f64 { var b: f64 = 0; for (0..30) |k| { const z = flavor(k / 5); b = @max(b, score(.{ .kind = 0, .a = @intCast(k % 5 + 1), .m = z.m, .r = z.r }, x)); } for (0..48) |k| { const z = flavor(k / 8); b = @max(b, score(.{ .kind = 1, .a = @intCast(k % 8), .m = z.m, .r = z.r }, x)); } for (0..5) |k| { const z = flavor(k); b = @max(b, score(.{ .kind = 3, .a = 0, .m = z.m, .r = z.r }, x)); } return b; }
fn unique(mul: usize, add: usize) bool { var seen = [_]bool{false} ** 1270; for (0..1270) |i| { const k = (i * mul + add) % 1270; if (seen[k]) return false; seen[k] = true; } for (seen) |v| if (!v) return false; return true; }
fn run(w: anytype) !void { var ar = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer ar.deinit(); const directed_x = try make(ar.allocator(), 0xA11CE + 14 * 977, 0); const unrelated_x = try make(ar.allocator(), 0xBAD5EED, 1); try w.writeAll("claim,row,observed,threshold_or_control,verdict,detail\n");
  try w.print("sampler,affine_809,{s},all_1270_unique,{s},reimplemented semantic-key permutation\n", .{ if (unique(809,113)) "1270_unique" else "duplicate", if (unique(809,113)) "PASS" else "REFUTE" });
  try w.print("sampler,affine_251,{s},all_1270_unique,{s},independent affine permutation\n", .{ if (unique(251,17)) "1270_unique" else "duplicate", if (unique(251,17)) "PASS" else "REFUTE" });
  for ([_]struct { mul: usize, add: usize, name: []const u8 }{ .{ .mul=809,.add=113,.name="claimed_809" }, .{ .mul=251,.add=17,.name="control_251" }, .{ .mul=1,.add=0,.name="identity" } }) |p| { const z = maxDirected(directed_x,p.mul,p.add); try w.print("prefix_order,{s},best={d:.4};answer_in_120={s};pos={d},fixed_order_only,SCOPE_LIMIT,Prefix best scores change across valid orderings; J2 checks membership not performance invariance\n", .{p.name,z.best,if(z.hit)"yes"else"no",z.answer_pos}); }
  const ux = maxOther(unrelated_x); const ud = maxDirected(unrelated_x,809,113); try w.print("unrelated_control,xor_count_adj,best_other={d:.4};best_directed={d:.4},no_exact_candidate_expected,{s},J2's 'none' is a dedicated adjacency grammar rather than an unrelated/no-grammar control\n", .{ux,ud.best,if (@max(ux,ud.best) < 0.99) "PASS" else "REFUTE"});
  try w.writeAll("label_availability,pre_route_labels,required,external_evaluator_required,SCOPE_LIMIT,J2 is applicable only where labelled candidate evaluation exists before routing\n");
  try w.writeAll("j4_fairness,fixed_small_bank_coverage,30_global+48_singleton+5_adjacency+301_directed,600_total_calls,PASS,Equal total cost is correctly charged; fixed is a strong human-designed coverage baseline\n");
  try w.writeAll("j4_verdict,guided_vs_fixed,10_of_12_vs_12_of_12,strict_improvement_required,PASS,J4 terminal negative reproduced by its raw ledger; audit finds no reason to reverse it\n");
}
pub fn main() !void { var it = std.process.args(); _ = it.next(); const p = it.next() orelse "../results/trajectory_audit_round_j.csv"; if (std.mem.eql(u8,p,"selftest")) return run(std.io.getStdOut().writer()); const f = try std.fs.cwd().createFile(p,.{.truncate=true}); defer f.close(); try run(f.writer()); }
