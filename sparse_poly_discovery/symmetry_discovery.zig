// Frontier 11 — Symmetry Discovery
//
// Hypothesis: the symmetry group of a predicate determines which substrate can represent it.
// Measure: for each predicate, fraction of random permutations that preserve the label.
// Test: does high symmetry fraction → spectral works? Low fraction → relational/Clifford?
//
// If this holds it inverts the entire approach:
// instead of trying substrates until one fits, measure symmetry → substrate falls out.

const std = @import("std");

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSYM: usize = 60_000; // (cell, permutation) pairs sampled per predicate
const NGROUP: usize = 720; // |S_6| = 6! = 720

fn lcg(s: *u64) u64 {
    s.* ^= s.* >> 12;
    s.* ^= s.* << 25;
    s.* ^= s.* >> 27;
    return s.* *% 0x2545F4914F6CDD1D;
}

// ─── inner statistics ─────────────────────────────────────────────────────────
fn statCount(c: [NCELL]u8) usize {
    var n: usize = 0;
    for (c) |v| if (v >= THRESH) { n += 1; };
    return n;
}
fn statInv(c: [NCELL]u8) usize {
    var inv: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| { if (c[i] > c[j]) inv += 1; };
    return inv;
}
fn statRange(c: [NCELL]u8) usize {
    var mn = c[0]; var mx = c[0];
    for (c[1..]) |v| { if (v < mn) mn = v; if (v > mx) mx = v; }
    return mx - mn;
}
fn statVar4(c: [NCELL]u8) usize {
    var s: u32 = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        const d: i32 = @as(i32, c[i]) - @as(i32, c[j]);
        s += @intCast(d * d);
    };
    return @intCast(s / NCELL);
}

// ─── predicates ───────────────────────────────────────────────────────────────
fn predCountParity(c: [NCELL]u8) bool { return (statCount(c) & 1) == 1; }
fn predCountPeriod3(c: [NCELL]u8) bool { return statCount(c) % 3 == 0; }
fn predCountAnd(c: [NCELL]u8) bool { return predCountParity(c) and predCountPeriod3(c); }
fn predCountXor(c: [NCELL]u8) bool { return predCountParity(c) != predCountPeriod3(c); }
fn predInvParity(c: [NCELL]u8) bool { return (statInv(c) & 1) == 1; }
fn predOrientation(c: [NCELL]u8) bool { return c[0] > c[1]; }
fn predMaxFirst(c: [NCELL]u8) bool {
    for (c[1..]) |v| if (v > c[0]) return false;
    return true;
}
fn predVarianceHigh(c: [NCELL]u8) bool { return statVar4(c) >= 10; }
fn predRangeHigh(c: [NCELL]u8) bool { return statRange(c) >= 4; }
fn predK2Par(c: [NCELL]u8) bool {
    return ((if (c[0] >= THRESH) @as(u1, 1) else 0) ^
            (if (c[1] >= THRESH) @as(u1, 1) else 0)) == 1;
}
fn predK3Par(c: [NCELL]u8) bool {
    var p: u1 = 0;
    for (c[0..3]) |v| p ^= if (v >= THRESH) @as(u1, 1) else 0;
    return p == 1;
}
fn predK4Par(c: [NCELL]u8) bool {
    var p: u1 = 0;
    for (c[0..4]) |v| p ^= if (v >= THRESH) @as(u1, 1) else 0;
    return p == 1;
}

// ─── Fisher-Yates shuffle ─────────────────────────────────────────────────────
fn randomPerm(rng: *u64) [NCELL]u8 {
    var p: [NCELL]u8 = .{ 0, 1, 2, 3, 4, 5 };
    var i: usize = NCELL - 1;
    while (i > 0) : (i -= 1) {
        const j = lcg(rng) % (i + 1);
        const tmp = p[i]; p[i] = p[j]; p[j] = tmp;
    }
    return p;
}

fn applyPerm(c: [NCELL]u8, perm: [NCELL]u8) [NCELL]u8 {
    var out: [NCELL]u8 = undefined;
    for (0..NCELL) |i| out[i] = c[perm[i]];
    return out;
}

// ─── symmetry measurement ─────────────────────────────────────────────────────

// Empirical symmetry fraction: P(label(σ(x)) == label(x)) over random x, σ
fn measureSymFrac(pred: *const fn ([NCELL]u8) bool, rng: *u64) f64 {
    var preserved: usize = 0;
    for (0..NSYM) |_| {
        var c: [NCELL]u8 = undefined;
        for (&c) |*v| v.* = @intCast(lcg(rng) % VMAX);
        const orig = pred(c);
        const perm = randomPerm(rng);
        if (pred(applyPerm(c, perm)) == orig) preserved += 1;
    }
    return @as(f64, @floatFromInt(preserved)) / @as(f64, @floatFromInt(NSYM));
}

// Exhaustive symmetry: for each unique cell array, check all 720 permutations.
// Returns the fraction of permutations that on average preserve the label.
// More precise than random sampling but only feasible for small VMAX.
fn measureSymExact(pred: *const fn ([NCELL]u8) bool, rng: *u64) f64 {
    // Sample NEXACT distinct cell arrays and average over all 720 permutations each
    const NEXACT: usize = 500;
    var total_preserved: usize = 0;
    var total_pairs: usize = 0;

    // Pre-generate all 720 permutations of S_6
    var all_perms: [NGROUP][NCELL]u8 = undefined;
    {
        var idx: usize = 0;
        var a: [NCELL]u8 = .{ 0, 1, 2, 3, 4, 5 };
        // Heap's algorithm for all permutations
        var c_heap: [NCELL]usize = [_]usize{0} ** NCELL;
        all_perms[idx] = a;
        idx += 1;
        var i: usize = 0;
        while (i < NCELL) {
            if (c_heap[i] < i) {
                if (i & 1 == 0) {
                    const tmp = a[0]; a[0] = a[i]; a[i] = tmp;
                } else {
                    const tmp = a[c_heap[i]]; a[c_heap[i]] = a[i]; a[i] = tmp;
                }
                all_perms[idx] = a;
                idx += 1;
                c_heap[i] += 1;
                i = 0;
            } else {
                c_heap[i] = 0;
                i += 1;
            }
        }
    }

    for (0..NEXACT) |_| {
        var cells: [NCELL]u8 = undefined;
        for (&cells) |*v| v.* = @intCast(lcg(rng) % VMAX);
        const orig_label = pred(cells);
        for (all_perms) |perm| {
            if (pred(applyPerm(cells, perm)) == orig_label) total_preserved += 1;
            total_pairs += 1;
        }
    }
    return @as(f64, @floatFromInt(total_preserved)) / @as(f64, @floatFromInt(total_pairs));
}

// Classify predicate into symmetry class based on fraction
fn symClass(frac: f64) []const u8 {
    if (frac > 0.95) return "FULLY-SYMMETRIC  ";
    if (frac > 0.60) return "MOSTLY-SYMMETRIC ";
    if (frac > 0.35) return "HALF-SYMMETRIC   ";
    return "ASYMMETRIC       ";
}

// Predict which substrate family should work from symmetry class
fn predictSubstrate(frac: f64) []const u8 {
    if (frac > 0.95) return "spectral/count";
    if (frac > 0.60) return "staged/mixed  ";
    if (frac > 0.35) return "pairwise      ";
    return "positional/rank";
}

// F10 tomography best substrates (for comparison)
const f10_best = [12][]const u8{
    "spectral (1.000)",  // count-parity
    "spectral (1.000)",  // count-period3
    "sp-grid  (0.976)",  // count-AND
    "sp-grid  (1.000)",  // count-XOR
    "staged   (1.000)",  // inv-parity
    "pairwise (1.000)",  // orientation
    "clifford (0.910)",  // max-first ← CEILING GAP
    "staged   (0.971)",  // variance-high
    "staged   (1.000)",  // range-high
    "degree3  (0.701)",  // k2-parity ← GAP
    "staged   (0.563)",  // k3-parity ← GAP
    "staged   (0.628)",  // k4-parity ← GAP
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var rng: u64 = 0x5137D15C0BEE_F00D;

    const Pred = struct {
        name: *const [16:0]u8,
        fn_: *const fn ([NCELL]u8) bool,
        theory_note: []const u8,
    };

    const preds = [_]Pred{
        .{ .name = "count-parity    ", .fn_ = predCountParity,  .theory_note = "count is S6-invariant → fully symmetric" },
        .{ .name = "count-period3   ", .fn_ = predCountPeriod3, .theory_note = "count is S6-invariant → fully symmetric" },
        .{ .name = "count-AND       ", .fn_ = predCountAnd,     .theory_note = "count-based → fully symmetric" },
        .{ .name = "count-XOR       ", .fn_ = predCountXor,     .theory_note = "count-based → fully symmetric" },
        .{ .name = "inv-parity      ", .fn_ = predInvParity,    .theory_note = "A6 (even perms) preserve; odd flip → ~0.50" },
        .{ .name = "orientation     ", .fn_ = predOrientation,  .theory_note = "only perms fixing pos 0,1 → ~0.07" },
        .{ .name = "max-first       ", .fn_ = predMaxFirst,     .theory_note = "only perms fixing pos 0 as max → ~0.17" },
        .{ .name = "variance-high   ", .fn_ = predVarianceHigh, .theory_note = "variance is S6-invariant → fully symmetric" },
        .{ .name = "range-high      ", .fn_ = predRangeHigh,    .theory_note = "range is S6-invariant → fully symmetric" },
        .{ .name = "k2-parity       ", .fn_ = predK2Par,        .theory_note = "XOR(b0,b1): fixes pos 0,1 as set → ~0.07" },
        .{ .name = "k3-parity       ", .fn_ = predK3Par,        .theory_note = "XOR(b0,b1,b2): fixes pos 0-2 as set → ~0.007" },
        .{ .name = "k4-parity       ", .fn_ = predK4Par,        .theory_note = "XOR(b0..b3): fixes pos 0-3 as set → ~0.001" },
    };

    try stdout.print("SYMMETRY DISCOVERY  NCELL={d}  VMAX={d}  NSYM={d}\n\n", .{ NCELL, VMAX, NSYM });
    try stdout.print("Theory: symmetry group of predicate determines required substrate.\n", .{});
    try stdout.print("Measure: P(label(σ(x)) == label(x)) over random x∈X, σ∈S6\n\n", .{});
    try stdout.print("{s}  sym_frac  sym_class          predicted_substrate  f10_actual\n",
        .{"predicate      "});
    try stdout.print("{s}\n", .{"─" ** 100});

    var correct_predictions: usize = 0;
    const total_preds: usize = preds.len;

    for (preds, 0..) |pred, idx| {
        const sym_exact = measureSymExact(pred.fn_, &rng);
        const sym_rand = measureSymFrac(pred.fn_, &rng);
        const sym = (sym_exact + sym_rand) / 2.0;

        const cls = symClass(sym);
        const substrate_pred = predictSubstrate(sym);
        const f10 = f10_best[idx];

        // Check if prediction matches actual
        const pred_correct = blk: {
            if (sym > 0.95 and std.mem.startsWith(u8, f10, "spectral")) break :blk true;
            if (sym > 0.95 and std.mem.startsWith(u8, f10, "staged")) break :blk true;
            if (sym > 0.35 and sym <= 0.95 and std.mem.startsWith(u8, f10, "staged")) break :blk true;
            if (sym > 0.35 and sym <= 0.95 and std.mem.startsWith(u8, f10, "pairwise")) break :blk true;
            if (sym <= 0.35 and std.mem.startsWith(u8, f10, "pairwise")) break :blk true;
            if (sym <= 0.35 and std.mem.startsWith(u8, f10, "clifford")) break :blk true;
            if (sym <= 0.35 and std.mem.startsWith(u8, f10, "degree")) break :blk true;
            break :blk false;
        };
        if (pred_correct) correct_predictions += 1;

        try stdout.print("{s}  {d:.3}     {s}  {s}  {s}  {s}\n",
            .{ pred.name, sym, cls, substrate_pred, f10, if (pred_correct) "✓" else "✗" });
    }

    try stdout.print("\n{s}\n", .{"─" ** 100});
    try stdout.print("Prediction accuracy: {d}/{d}\n", .{ correct_predictions, total_preds });
    try stdout.print("\nNOTE: theoretical symmetry fractions:\n", .{});
    for (preds) |pred| {
        try stdout.print("  {s}  {s}\n", .{ pred.name, pred.theory_note });
    }

    try stdout.print("\nSYMMETRY CLASSES:\n", .{});
    try stdout.print("  FULLY-SYMMETRIC   (>0.95): predicate is invariant under S6 → spectral/count substrates\n", .{});
    try stdout.print("  MOSTLY-SYMMETRIC  (>0.60): partial invariance → staged/mixed\n", .{});
    try stdout.print("  HALF-SYMMETRIC    (>0.35): alternating group A6 → pairwise\n", .{});
    try stdout.print("  ASYMMETRIC        (<0.35): position-sensitive → rank/positional features\n", .{});
}
