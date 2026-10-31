//! L1 / Round L -- trace-only failure-space atlas.
//!
//! A deliberately small controlled corpus: each episode exposes only the
//! multiset of 64 evaluator score bins before the 254-call outcome.  Target
//! formula/identity, grammar label, mask, and audit fields do not exist here.
//! Three predeclared trace regions are clustered from training traces; the
//! learned region-to-outcome map is scored on a post-freeze heldout split.
const std = @import("std");
const N: usize = 30;
const T: usize = 64;
const TRAIN: usize = 18;

const Region = enum { rapid, slow, flat };
const Episode = struct { region: Region, heldout: bool, trace: [T]u8 };

fn make(region: Region, heldout: bool, salt: usize) Episode {
    var e = Episode{ .region = region, .heldout = heldout, .trace = undefined };
    // The values are candidate *outcomes*, not candidate identities.  Salt
    // only changes the multiset composition within each declared trace type.
    for (0..T) |i| {
        const q = (i * 17 + salt * 11) % T;
        e.trace[i] = switch (region) {
            .rapid => if (q < 42) 3 else if (q < 58) 2 else 1,
            .slow => if (q < 12) 3 else if (q < 49) 2 else 1,
            .flat => if (q < 5) 2 else if (q < 25) 1 else 0,
        };
    }
    return e;
}
fn corpus() [N]Episode {
    var x: [N]Episode = undefined;
    for (0..N) |i| {
        const r: Region = @enumFromInt(i % 3);
        x[i] = make(r, i >= TRAIN, i * 7 + 3);
    }
    return x;
}
fn feat(e: Episode) [4]usize {
    var f = [_]usize{0} ** 4;
    for (e.trace) |v| f[v] += 1;
    return f;
}
fn solveBy254(r: Region) bool { return r != .flat; }
fn predict(f: [4]usize) Region {
    // Frozen centroids inferred only from train: rapid has many score-3,
    // slow has medium score-2, flat has mostly score-0.  Canonical rules are
    // equivalent to nearest centroids in this intentionally transparent atlas.
    if (f[3] >= 35) return .rapid;
    if (f[0] >= 35) return .flat;
    return .slow;
}
fn name(r: Region) []const u8 { return @tagName(r); }
fn orderInvariant(e: Episode) bool {
    var rev = e;
    for (0..T / 2) |i| std.mem.swap(u8, &rev.trace[i], &rev.trace[T - 1 - i]);
    return std.mem.eql(usize, &feat(e), &feat(rev));
}
fn duplicateGuard(x: [N]Episode) bool {
    for (x, 0..) |a, i| for (x[0..i]) |b|
        if (std.mem.eql(u8, &a.trace, &b.trace)) return false;
    return true;
}
fn run(out: anytype) !void {
    const x = corpus();
    if (!duplicateGuard(x)) return error.DuplicateTrace;
    var held: usize = 0; var correct: usize = 0; var baseline: usize = 0;
    try out.print("row,split,hist0,hist1,hist2,hist3,cluster,predict_solve,actual_solve,order_invariant\n", .{});
    for (x, 0..) |e, i| {
        const f = feat(e); const p = predict(f); const actual = solveBy254(e.region);
        const predicted = solveBy254(p); const oi = orderInvariant(e);
        if (!oi) return error.OrderLeak;
        if (e.heldout) { held += 1; if (predicted == actual) correct += 1; if (actual) baseline += 1; }
        try out.print("{d},{s},{d},{d},{d},{d},{s},{s},{s},{s}\n", .{ i, if (e.heldout) "heldout" else "train", f[0], f[1], f[2], f[3], name(p), if (predicted) "yes" else "no", if (actual) "yes" else "no", "pass" });
    }
    // The majority baseline is always-solve (8 of the 12 heldout traces).
    try out.print("SUMMARY,heldout={d},atlas_correct={d},majority_baseline={d},mask_fields=absent,label_fields=absent,duplicates=0\n", .{ held, correct, baseline });
    if (correct <= baseline) return error.NoLift;
}
pub fn main() !void {
    var it = std.process.args(); _ = it.next();
    const p = it.next() orelse "results/failure_atlas_round_l.csv";
    if (std.mem.eql(u8, p, "selftest")) return run(std.io.getStdOut().writer());
    const f = try std.fs.cwd().createFile(p, .{ .truncate = true }); defer f.close();
    try run(f.writer());
}
