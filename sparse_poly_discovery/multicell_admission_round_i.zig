//! I2: symmetric multi-cell directed-partition admission.
//!
//! The admission API sees only labelled grids.  It deliberately scans every
//! nonempty proper cell partition (canonicalised only to avoid complements),
//! with both mod-2 and mod-3 residues.  No singleton-only statistic, target
//! identity, formula, family, mask, anchor, or residue enters the API.
//!
//! This is an intentionally conservative test: a high partition response is
//! useful only as a *licence to search the already supplied grammar*, not as
//! evidence that a new grammar was invented or that it is cheaper than blind
//! search.
const std = @import("std");
const Cells: usize = 8;
const N: usize = 2000;
const TrainEnd: usize = 1000;
const ValEnd: usize = 1500;
const DirectedBudget: usize = 1270; // 254 masks * (2 mod-2 + 3 mod-3 residues)
const RandomTrials: usize = 128;
const AdmissionMin: f64 = 0.90;
const Sample = struct { g: [Cells]u8, y: bool };
const Candidate = struct { mask: u8, modulus: u8, residue: u8 };
const Kind = enum { directed, threshold, random };
const Spec = struct { id: []const u8, seed: u64, kind: Kind, mask: u8 = 0, modulus: u8 = 2, residue: u8 = 0, threshold: u8 = 0, heldout: bool = false };

// Generator-only.  None of these values is visible to admission/select APIs.
const specs = [_]Spec{
    .{ .id="singleton_p3_m3_r1", .seed=0x1A201, .kind=.directed, .mask=0x08, .modulus=3, .residue=1 },
    .{ .id="twocell_1_5_m2_r0", .seed=0x1A202, .kind=.directed, .mask=0x22, .modulus=2, .residue=0 },
    .{ .id="heldout_threecell_0_3_6_m3_r2", .seed=0x1A203, .kind=.directed, .mask=0x49, .modulus=3, .residue=2, .heldout=true },
    .{ .id="threshold_negative", .seed=0x1A204, .kind=.threshold, .threshold=3, .modulus=2, .residue=0 },
    .{ .id="random_negative", .seed=0x1A205, .kind=.random },
};

fn count(g: [Cells]u8, mask: u8) usize { var n: usize = 0; for (0..Cells) |i| for (0..Cells) |j| { const bi: u8 = @as(u8, 1) << @intCast(i); const bj: u8 = @as(u8, 1) << @intCast(j); if ((mask & bi) != 0 and (mask & bj) == 0 and g[i] > g[j]) n += 1; }; return n; }
fn pred(c: Candidate, x: Sample) bool { return count(x.g, c.mask) % c.modulus == c.residue; }
fn threshold(x: Sample, t: u8, m: u8, r: u8) bool { var n: usize = 0; for (x.g) |v| { if (v >= t) n += 1; } return n % m == r; }
fn make(alloc: std.mem.Allocator, s: Spec) ![]Sample { var prng = std.Random.DefaultPrng.init(s.seed); const r = prng.random(); const xs = try alloc.alloc(Sample, N); for (xs) |*x| { for (0..Cells) |i| x.g[i] = r.intRangeAtMost(u8, 0, 5); x.y = switch (s.kind) { .directed => count(x.g, s.mask) % s.modulus == s.residue, .threshold => threshold(x.*, s.threshold, s.modulus, s.residue), .random => r.boolean(), }; } return xs; }
fn acc(c: Candidate, xs: []const Sample, lo: usize, hi: usize) f64 { var ok: usize = 0; for (xs[lo..hi]) |x| { if (pred(c, x) == x.y) ok += 1; } return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo)); }
fn fixedBest(xs: []const Sample, lo: usize, hi: usize) f64 { var best: f64 = 0; for (1..6) |t| for (2..4) |m| for (0..m) |rr| { var ok: usize = 0; for (xs[lo..hi]) |x| { if (threshold(x, @intCast(t), @intCast(m), @intCast(rr)) == x.y) ok += 1; } best = @max(best, @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(hi - lo))); }; return best; }
// Every mask has an equal representative: canonicalisation removes only the
// complement duplicate, never privileging masks by cardinality.
fn canonical(mask: u8) bool { const comp: u8 = ~mask; return mask < comp; }
fn candidateAt(ix: usize) Candidate { const mask: u8 = @intCast(ix / 5 + 1); const q = ix % 5; return .{ .mask=mask, .modulus=if (q < 2) 2 else 3, .residue=@intCast(if (q < 2) q else q - 2) }; }
// A partition response is a predeclared validation-free train statistic.  It
// is symmetric over every mask; the selected candidate is chosen separately.
fn partitionResponse(xs: []const Sample) f64 { var best: f64 = 0; for (0..DirectedBudget) |i| { const c = candidateAt(i); best = @max(best, acc(c, xs, 0, TrainEnd)); } return best; }
fn selectOnValidation(xs: []const Sample) Candidate { var best = candidateAt(0); var best_a: f64 = -1; for (0..DirectedBudget) |i| { const c = candidateAt(i); const a = acc(c, xs, TrainEnd, ValEnd); if (a > best_a) { best_a = a; best = c; } } return best; }
fn uniform(r: std.Random) Candidate { return candidateAt(r.intRangeLessThan(usize, 0, DirectedBudget)); }
fn baseRate(xs: []const Sample) f64 { var n: usize = 0; for (xs) |x| { if (x.y) n += 1; } return @as(f64, @floatFromInt(n)) / N; }

fn run(out: anytype, alloc: std.mem.Allocator, s: Spec) !void {
    const xs = try make(alloc, s);
    const base = baseRate(xs);
    const fixed = fixedBest(xs, TrainEnd, ValEnd);
    const response = partitionResponse(xs);
    const admitted = base > 0.10 and base < 0.90 and response >= AdmissionMin;
    const chosen = selectOnValidation(xs);
    const chosen_val = acc(chosen, xs, TrainEnd, ValEnd);
    const chosen_test = acc(chosen, xs, ValEnd, N);
    // Full raw candidate ledger makes the admission score and selected member
    // independently checkable from the CSV.
    for (0..DirectedBudget) |i| { const c = candidateAt(i); try out.print("{s},candidate,{d},{d},{d:.4},{d:.4},,,,,mask=0x{X:0>2};m={d};r={d}\n", .{s.id, i, 1, acc(c,xs,0,TrainEnd),acc(c,xs,TrainEnd,ValEnd),c.mask,c.modulus,c.residue}); }
    var hits: usize = 0; var mean: f64 = 0;
    for (0..RandomTrials) |trial| { var prng = std.Random.DefaultPrng.init(s.seed ^ (0x9E3779B97F4A7C15 *% @as(u64,@intCast(trial + 1)))); const r = prng.random(); var b: f64 = 0; for (0..DirectedBudget) |_| b = @max(b, acc(uniform(r),xs,TrainEnd,ValEnd)); mean += b; if (b >= 0.999) hits += 1; try out.print("{s},random_trial,{d},{d},,{d:.4},,,,,max_validation={d:.4}\n", .{s.id,trial,DirectedBudget,fixed,b}); }
    mean /= RandomTrials; const hit_rate = @as(f64,@floatFromInt(hits)) / RandomTrials;
    const expected_admit = s.kind == .directed;
    const correct_admission = admitted == expected_admit;
    const gate = base > 0.10 and base < 0.90 and correct_admission and (if (admitted) chosen_test >= 0.99 and chosen_test > fixed else true);
    try out.print("{s},summary,0,{d},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},admitted={s};expected={s};chosen=0x{X:0>2}/{d}/{d};blind_mean={d:.4};heldout={s};{s}\n", .{s.id,DirectedBudget,response,fixed,chosen_val,chosen_test,hit_rate,base,if(admitted)"yes" else "no",if(expected_admit)"yes" else "no",chosen.mask,chosen.modulus,chosen.residue,mean,if(s.heldout)"yes" else "no",if(gate)"PASS" else "FAIL"});
}
pub fn main() !void { var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit(); const f = try std.fs.cwd().createFile("../results/multicell_admission_round_i.csv", .{.truncate=true}); defer f.close(); var out=f.writer(); try out.writeAll("condition,arm,trial,candidate_evaluations,train_accuracy,validation_accuracy,chosen_validation,chosen_test,blind_exact_rate,base_rate,detail\n"); for (specs) |s| try run(out,arena.allocator(),s); }
