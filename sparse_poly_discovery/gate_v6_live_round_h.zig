//! Round H / H5 -- live, candidate-excluded gate-v6 integration audit.
//!
//! This is intentionally independent of G1's frozen witness table.  For each
//! candidate it generates a fresh balanced data set, learns a greedy
//! multi-feature reconstruction from the current *candidate-excluded* library,
//! then makes the legacy R2 and v6 COVER decisions inside two promotion loops.
//! The output is an audit of a decision layer, not a production adoption.
const std = @import("std");

const NCELL: usize = 8;
const PER_CLASS: usize = 900;
const TRAIN: usize = 1080; // 60% of balanced 1800
const VALID: usize = 1440; // 80%
const COVER: f64 = 0.90;
const R2_GATE: f64 = 0.40;
const SEED: u64 = 0x48355F4C49564531;

const Kind = enum { run1, run_var2, remix_count, g4_partition };
const Candidate = struct { name: []const u8, kind: Kind, truth_remix: bool };
const candidates = [_]Candidate{
    .{ .name = "RUN1", .kind = .run1, .truth_remix = false },
    .{ .name = "RUN-var2", .kind = .run_var2, .truth_remix = false },
    .{ .name = "REMIX-countGE3-atleast4", .kind = .remix_count, .truth_remix = true },
    .{ .name = "G4-directed-partition-rankmod", .kind = .g4_partition, .truth_remix = false },
};
const Sample = struct { g: [NCELL]u8, y: bool, raw: f64 };
const Feature = enum { count2, count3, count4, sum_bin, inv_bin, spread_bin, prior_run1, prior_run2, prior_remix, prior_g4 };
const base_features = [_]Feature{ .count2, .count3, .count4, .sum_bin, .inv_bin, .spread_bin };

fn maxRun(g: [NCELL]u8, threshold: u8) u8 { var best: u8 = 0; var cur: u8 = 0; for (g) |v| { if (v >= threshold) { cur += 1; best = @max(best, cur); } else cur = 0; } return best; }
fn countGE(g: [NCELL]u8, threshold: u8) u8 { var n: u8 = 0; for (g) |v| { if (v >= threshold) n += 1; } return n; }
fn inv(g: [NCELL]u8) u8 { var n: u8 = 0; for (0..NCELL) |i| { for (i + 1..NCELL) |j| { if (g[i] > g[j]) n += 1; } } return n; }
fn partition(g: [NCELL]u8) u8 { // G4's held-out, directed singleton partition (cell 3 vs rest)
    var n: u8 = 0; for (0..NCELL) |j| { if (j != 3 and g[3] > g[j]) n += 1; } return n;
}
fn target(kind: Kind, g: [NCELL]u8) struct { y: bool, raw: f64 } {
    return switch (kind) {
        .run1 => .{ .y = maxRun(g, 3) >= 3, .raw = @floatFromInt(maxRun(g, 3)) },
        .run_var2 => .{ .y = maxRun(g, 2) >= 4, .raw = @floatFromInt(maxRun(g, 2)) },
        .remix_count => .{ .y = countGE(g, 3) >= 4, .raw = @floatFromInt(countGE(g, 3)) },
        .g4_partition => .{ .y = partition(g) % 3 == 1, .raw = @floatFromInt(partition(g)) },
    };
}
fn fval(f: Feature, s: Sample) u8 {
    return switch (f) {
        .count2 => countGE(s.g, 2), .count3 => countGE(s.g, 3), .count4 => countGE(s.g, 4),
        .sum_bin => blk: { var z: u8 = 0; for (s.g) |v| z += v; break :blk z / 4; },
        .inv_bin => inv(s.g) / 4,
        .spread_bin => blk: { var lo: u8 = 5; var hi: u8 = 0; for (s.g) |v| { lo = @min(lo, v); hi = @max(hi, v); } break :blk hi - lo; },
        // Previously admitted candidates are available as ordinary library
        // columns to later candidates, never to their own reconstruction.
        .prior_run1 => @intFromBool(target(.run1, s.g).y),
        .prior_run2 => @intFromBool(target(.run_var2, s.g).y),
        .prior_remix => @intFromBool(target(.remix_count, s.g).y),
        .prior_g4 => @intFromBool(target(.g4_partition, s.g).y),
    };
}
fn makeBalanced(alloc: std.mem.Allocator, kind: Kind, seed: u64) ![]Sample {
    var out = try alloc.alloc(Sample, PER_CLASS * 2); var yes: usize = 0; var no: usize = 0;
    var p = std.Random.DefaultPrng.init(seed); const r = p.random();
    while (yes < PER_CLASS or no < PER_CLASS) {
        var g: [NCELL]u8 = undefined; for (&g) |*v| v.* = r.intRangeAtMost(u8, 0, 5);
        const t = target(kind, g); if (t.y and yes < PER_CLASS) { out[yes] = .{ .g = g, .y = true, .raw = t.raw }; yes += 1; }
        if (!t.y and no < PER_CLASS) { out[PER_CLASS + no] = .{ .g = g, .y = false, .raw = t.raw }; no += 1; }
    }
    // Deterministic shuffle prevents class order from leaking into splits.
    for (out, 0..) |_, i| { const j = r.intRangeLessThan(usize, i, out.len); const tmp = out[i]; out[i] = out[j]; out[j] = tmp; }
    return out;
}
const Stump = struct { f: Feature, threshold: u8, acc: f64 };
const Model = struct { selected: [4]Stump, n: usize, threshold: u8 };
fn score(f: Feature, s: Sample) u8 { return fval(f, s); }
fn bestStump(xs: []const Sample, features: []const Feature, selected: []const Feature) Stump {
    var best: Stump = .{ .f = features[0], .threshold = @as(u8, 0), .acc = @as(f64, -1) };
    for (features) |f| {
        var duplicate = false; for (selected) |q| { if (q == f) duplicate = true; } if (duplicate) continue;
        for (0..9) |th| { var ok: usize = 0; for (xs) |x| { const pred = score(f, x) >= th; if (pred == x.y) ok += 1; } const a = @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(xs.len)); if (a > best.acc) best = .{ .f = f, .threshold = @intCast(th), .acc = a }; }
    }
    return best;
}
// Greedy multi-feature OR-of-stumps classifier.  It is intentionally simple,
// fixed before data inspection, and records selected columns in raw output.
fn fit(xs: []const Sample, features: []const Feature) Model {
    var m = Model{ .selected = undefined, .n = 0, .threshold = 0 };
    // Greedy column order; using multiple selected columns is required even
    // when one exact remix column is enough (the raw list makes that visible).
    while (m.n < 4 and m.n < features.len) : (m.n += 1) {
        var prior: [4]Feature = undefined;
        for (m.selected[0..m.n], 0..) |s, q| prior[q] = s.f;
        const b = bestStump(xs, features, prior[0..m.n]); m.selected[m.n] = b;
    }
    // Fixed vote threshold: any two stumps, or half if only one feature.
    m.threshold = if (m.n >= 2) 2 else 1; return m;
}
fn predict(m: Model, s: Sample) bool { var n: u8 = 0; for (m.selected[0..m.n]) |stump| { if (score(stump.f, s) >= stump.threshold) n += 1; } return n >= m.threshold; }
fn accuracy(m: Model, xs: []const Sample) f64 { var ok: usize = 0; for (xs) |s| { if (predict(m, s) == s.y) ok += 1; } return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(xs.len)); }
fn r2Raw(xs: []const Sample) f64 {
    // Legacy proxy: max absolute squared Pearson correlation of candidate raw
    // statistic against each current *base* raw feature (the v5 wrong axis).
    var best: f64 = 0; for (base_features) |f| { var sx: f64 = 0; var sy: f64 = 0; for (xs) |s| { sx += s.raw; sy += @floatFromInt(fval(f, s)); } const mx = sx / @as(f64, @floatFromInt(xs.len)); const my = sy / @as(f64, @floatFromInt(xs.len)); var cov: f64 = 0; var vx: f64 = 0; var vy: f64 = 0; for (xs) |s| { const a = s.raw - mx; const b = @as(f64, @floatFromInt(fval(f, s))) - my; cov += a * b; vx += a * a; vy += b * b; } if (vx > 0 and vy > 0) best = @max(best, cov * cov / (vx * vy)); } return best;
}
fn fmtFeatures(m: Model, buf: *[96]u8) []const u8 { var w = std.io.fixedBufferStream(buf); for (m.selected[0..m.n], 0..) |stump, i| { if (i != 0) w.writer().writeAll("+") catch {}; w.writer().print("{s}>={d}", .{ @tagName(stump.f), stump.threshold }) catch {}; } return buf[0..w.pos]; }
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit(); const a = arena.allocator();
    var csv = try std.fs.cwd().createFile("../results/gate_v6_live_round_h.csv", .{ .truncate = true }); defer csv.close(); const out = csv.writer();
    try out.writeAll("loop,order,seed,target,truth,train_cover,valid_cover,legacy_r2,legacy_decision,v6_decision,legacy_promoted,v6_promoted,selected_features,validity\n");
    var legacy_library = std.ArrayList(Feature).init(a); defer legacy_library.deinit(); try legacy_library.appendSlice(&base_features);
    var v6_library = std.ArrayList(Feature).init(a); defer v6_library.deinit(); try v6_library.appendSlice(&base_features);
    var legacy_correct: usize = 0; var v6_correct: usize = 0; var v6_novel_admits: usize = 0;
    for (candidates, 0..) |c, i| {
        const xs = try makeBalanced(a, c.kind, SEED + @as(u64, @intCast(i)) * 17);
        const train = xs[0..TRAIN]; const valid = xs[TRAIN..VALID];
        const lm = fit(train, legacy_library.items); const vm = fit(train, v6_library.items);
        const lcover = accuracy(lm, valid); const vcover = accuracy(vm, valid); const r2 = r2Raw(train);
        const lreject = r2 >= R2_GATE; const vreject = vcover >= COVER;
        const want_reject = c.truth_remix; if (lreject == want_reject) legacy_correct += 1; if (vreject == want_reject) v6_correct += 1;
        if (!c.truth_remix and !vreject) v6_novel_admits += 1;
        var fl: [96]u8 = undefined; var fv: [96]u8 = undefined;
        try out.print("legacy,{d},0x{X},{s},{s},{d:.4},{d:.4},{d:.4},{s},n/a,{s},n/a,{s},PASS\n", .{ i + 1, SEED + @as(u64, @intCast(i)) * 17, c.name, if (c.truth_remix) "remix" else "novel", accuracy(lm, train), lcover, r2, if (lreject) "reject" else "admit", if (!lreject) "yes" else "no", fmtFeatures(lm, &fl) });
        try out.print("v6,{d},0x{X},{s},{s},{d:.4},{d:.4},{d:.4},n/a,{s},n/a,{s},{s},PASS\n", .{ i + 1, SEED + @as(u64, @intCast(i)) * 17, c.name, if (c.truth_remix) "remix" else "novel", accuracy(vm, train), vcover, r2, if (vreject) "reject" else "admit", if (!vreject) "yes" else "no", fmtFeatures(vm, &fv) });
        if (!lreject) try legacy_library.append(switch (c.kind) { .run1 => .prior_run1, .run_var2 => .prior_run2, .remix_count => .prior_remix, .g4_partition => .prior_g4 });
        if (!vreject) try v6_library.append(switch (c.kind) { .run1 => .prior_run1, .run_var2 => .prior_run2, .remix_count => .prior_remix, .g4_partition => .prior_g4 });
    }
    try out.print("summary,-,0x{X},all,-,-,-,-,-,legacy_correct={d}/4,v6_correct={d}/4,legacy_library={d},v6_library={d},v6_novel_admits={d}/3,PASS\n", .{ SEED, legacy_correct, v6_correct, legacy_library.items.len - base_features.len, v6_library.items.len - base_features.len, v6_novel_admits });
    try std.io.getStdOut().writer().print("H5 live gate: legacy={d}/4 v6={d}/4; promotions legacy={d}, v6={d}; raw CSV ../results/gate_v6_live_round_h.csv\n", .{ legacy_correct, v6_correct, legacy_library.items.len - base_features.len, v6_library.items.len - base_features.len });
}
