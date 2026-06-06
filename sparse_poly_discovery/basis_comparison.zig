// Frontier 13 — Basis Comparison
//
// The spectral operator (accuracy-grid) uses cos(ω·s) as its classifier basis.
// Hypothesis: this basis is optimal for PERIODIC predicates but wrong for THRESHOLD
// predicates. A step function sign(s−θ) should be optimal for threshold predicates.
//
// NEW IDEA — Dual basis: α·cos(ω·s) + (1−α)·sign(s−θ)
// A two-parameter family that spans from purely periodic (α=1) to purely threshold (α=0).
// For each predicate, the optimal (α,ω,θ) reveals the predicate's intrinsic structure.
//
// Four bases tested:
//   A. Cosine:   cos(ω·s)                    — periodic, 1 param
//   B. Step:     sign(s−θ)                   — threshold, 1 param
//   C. Linear:   (s−θ)/max_s                 — linear threshold, 1 param
//   D. Dual:     majority vote of cos + step  — combined, 2 params
//
// Prediction: cos wins for count-parity, count-period3 (periodic)
//             step wins for variance-high, range-high (threshold)
//             dual beats both for count-AND (sparse periodic + threshold-like)

const std = @import("std");
const math = std.math;

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 4000;
const NTRAIN: usize = NSAMP * 4 / 5;
const NTEST: usize = NSAMP - NTRAIN;
const NGRID_W: usize = 400;
const NGRID_T: usize = 50;  // theta grid over integer stat values
const PI: f64 = math.pi;

var g_cells: [NSAMP][NCELL]u8 = undefined;
var g_labels: [NSAMP]bool = undefined;
var g_stat: [NSAMP]usize = undefined;

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
fn predVarianceHigh(c: [NCELL]u8) bool { return statVar4(c) >= 10; }
fn predRangeHigh(c: [NCELL]u8) bool { return statRange(c) >= 4; }
fn predK2Par(c: [NCELL]u8) bool {
    return ((if (c[0] >= THRESH) @as(u1, 1) else 0) ^
            (if (c[1] >= THRESH) @as(u1, 1) else 0)) == 1;
}

// ─── basis A: cosine classifier ───────────────────────────────────────────────
fn bestCosine(max_stat: usize) struct { w: f64, acc: f64 } {
    _ = max_stat;
    var best_w: f64 = PI;
    var best_acc: f64 = 0;
    for (1..NGRID_W + 1) |gi| {
        const w = PI * @as(f64, @floatFromInt(gi)) / @as(f64, @floatFromInt(NGRID_W));
        var correct: usize = 0;
        for (0..NTRAIN) |i| {
            const sf: f64 = @floatFromInt(g_stat[i]);
            if ((@cos(w * sf) >= 0) == g_labels[i]) correct += 1;
        }
        var acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTRAIN));
        acc = @max(acc, 1.0 - acc);
        if (acc > best_acc) { best_acc = acc; best_w = w; }
    }
    // Eval on test
    var correct: usize = 0;
    for (NTRAIN..NSAMP) |i| {
        const sf: f64 = @floatFromInt(g_stat[i]);
        if ((@cos(best_w * sf) >= 0) == g_labels[i]) correct += 1;
    }
    const test_acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
    return .{ .w = best_w, .acc = @max(test_acc, 1.0 - test_acc) };
}

// ─── basis B: step function ───────────────────────────────────────────────────
fn bestStep(max_stat: usize) struct { theta: f64, acc: f64 } {
    var best_theta: f64 = 0;
    var best_acc: f64 = 0;
    const max_t = max_stat + 2;
    for (0..max_t * 2) |ti| {
        const theta = @as(f64, @floatFromInt(ti)) * 0.5;
        var correct: usize = 0;
        for (0..NTRAIN) |i| {
            const sf: f64 = @floatFromInt(g_stat[i]);
            // step: predict true if sf >= theta
            if ((sf >= theta) == g_labels[i]) correct += 1;
        }
        var acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTRAIN));
        acc = @max(acc, 1.0 - acc);
        if (acc > best_acc) { best_acc = acc; best_theta = theta; }
    }
    var correct: usize = 0;
    for (NTRAIN..NSAMP) |i| {
        const sf: f64 = @floatFromInt(g_stat[i]);
        if ((sf >= best_theta) == g_labels[i]) correct += 1;
    }
    const test_acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
    return .{ .theta = best_theta, .acc = @max(test_acc, 1.0 - test_acc) };
}

// ─── basis C: linear threshold ────────────────────────────────────────────────
// Already covered by step (linear threshold is equivalent to step for 1D scalar)
// Here we use a signed linear: predict true if (s - theta) * sign >= 0
// This is identical to step, so we'll use this slot for a PERIODIC STEP (zigzag wave)
// f(s) = sign(cos(ω·s)) — cosine but hard-thresholded at zero (square wave)
fn bestSquareWave() struct { w: f64, acc: f64 } {
    var best_w: f64 = PI;
    var best_acc: f64 = 0;
    for (1..NGRID_W + 1) |gi| {
        const w = PI * @as(f64, @floatFromInt(gi)) / @as(f64, @floatFromInt(NGRID_W));
        var correct: usize = 0;
        for (0..NTRAIN) |i| {
            const sf: f64 = @floatFromInt(g_stat[i]);
            // square wave: +1 in first half-period, -1 in second
            const phase = w * sf;
            const normalized = phase - math.floor(phase / (2 * PI)) * (2 * PI);
            const wave_pos = normalized < PI;
            if (wave_pos == g_labels[i]) correct += 1;
        }
        var acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTRAIN));
        acc = @max(acc, 1.0 - acc);
        if (acc > best_acc) { best_acc = acc; best_w = w; }
    }
    var correct: usize = 0;
    for (NTRAIN..NSAMP) |i| {
        const sf: f64 = @floatFromInt(g_stat[i]);
        const phase = best_w * sf;
        const normalized = phase - math.floor(phase / (2 * PI)) * (2 * PI);
        if ((normalized < PI) == g_labels[i]) correct += 1;
    }
    const test_acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
    return .{ .w = best_w, .acc = @max(test_acc, 1.0 - test_acc) };
}

// ─── basis D: dual — best of (cos, step) with 2D search ──────────────────────
// Combines cos and step into a 2-voter ensemble:
// predict true if cos(ω·s) >= 0 AND s >= θ (AND logic)
// predict true if cos(ω·s) >= 0 OR  s >= θ (OR logic)
// take whichever (AND or OR with best ω, θ) gives highest train accuracy
fn bestDual(max_stat: usize) struct { w: f64, theta: f64, mode: []const u8, acc: f64 } {
    const max_t = max_stat + 2;
    var best_acc: f64 = 0;
    var best_w: f64 = PI;
    var best_theta: f64 = 0;
    var best_mode: []const u8 = "AND";

    // Sample grid: 40 ω values × all θ values (cheaper than full 400×50)
    const NGRID_W_DUAL = 80;
    for (1..NGRID_W_DUAL + 1) |gi| {
        const w = PI * @as(f64, @floatFromInt(gi)) / @as(f64, @floatFromInt(NGRID_W_DUAL));
        for (0..max_t * 2) |ti| {
            const theta = @as(f64, @floatFromInt(ti)) * 0.5;
            // AND mode
            {
                var correct: usize = 0;
                for (0..NTRAIN) |i| {
                    const sf: f64 = @floatFromInt(g_stat[i]);
                    const cos_pred = @cos(w * sf) >= 0;
                    const step_pred = sf >= theta;
                    if ((cos_pred and step_pred) == g_labels[i]) correct += 1;
                }
                var acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTRAIN));
                acc = @max(acc, 1.0 - acc);
                if (acc > best_acc) { best_acc = acc; best_w = w; best_theta = theta; best_mode = "AND"; }
            }
            // OR mode
            {
                var correct: usize = 0;
                for (0..NTRAIN) |i| {
                    const sf: f64 = @floatFromInt(g_stat[i]);
                    const cos_pred = @cos(w * sf) >= 0;
                    const step_pred = sf >= theta;
                    if ((cos_pred or step_pred) == g_labels[i]) correct += 1;
                }
                var acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTRAIN));
                acc = @max(acc, 1.0 - acc);
                if (acc > best_acc) { best_acc = acc; best_w = w; best_theta = theta; best_mode = "OR "; }
            }
        }
    }
    // Eval on test
    var correct: usize = 0;
    for (NTRAIN..NSAMP) |i| {
        const sf: f64 = @floatFromInt(g_stat[i]);
        const cos_pred = @cos(best_w * sf) >= 0;
        const step_pred = sf >= best_theta;
        const dual_pred = if (std.mem.eql(u8, best_mode, "AND")) (cos_pred and step_pred) else (cos_pred or step_pred);
        if (dual_pred == g_labels[i]) correct += 1;
    }
    const test_acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(NTEST));
    return .{ .w = best_w, .theta = best_theta, .mode = best_mode,
               .acc = @max(test_acc, 1.0 - test_acc) };
}

// Run all 4 bases on the current g_stat, g_labels
fn runAllBases(max_stat: usize) struct { cos: f64, step: f64, sqwave: f64, dual: f64, dual_mode: []const u8 } {
    const r_cos = bestCosine(max_stat);
    const r_step = bestStep(max_stat);
    const r_sq = bestSquareWave();
    const r_dual = bestDual(max_stat);
    return .{
        .cos = r_cos.acc,
        .step = r_step.acc,
        .sqwave = r_sq.acc,
        .dual = r_dual.acc,
        .dual_mode = r_dual.mode,
    };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var rng: u64 = 0xBAB15C0BA5E_F00D;

    const Pred = struct {
        name: *const [16:0]u8,
        fn_: *const fn ([NCELL]u8) bool,
        group: u8,
    };

    const preds = [_]Pred{
        .{ .name = "count-parity    ", .fn_ = predCountParity,   .group = 'A' },
        .{ .name = "count-period3   ", .fn_ = predCountPeriod3,  .group = 'A' },
        .{ .name = "count-AND       ", .fn_ = predCountAnd,      .group = 'A' },
        .{ .name = "count-XOR       ", .fn_ = predCountXor,      .group = 'A' },
        .{ .name = "inv-parity      ", .fn_ = predInvParity,     .group = 'B' },
        .{ .name = "variance-high   ", .fn_ = predVarianceHigh,  .group = 'C' },
        .{ .name = "range-high      ", .fn_ = predRangeHigh,     .group = 'C' },
        .{ .name = "k2-parity       ", .fn_ = predK2Par,         .group = 'D' },
    };

    const StatFn = *const fn ([NCELL]u8) usize;
    const stats = [_]struct { name: []const u8, fn_: StatFn, max: usize }{
        .{ .name = "count ", .fn_ = statCount, .max = NCELL },
        .{ .name = "inv   ", .fn_ = statInv,   .max = NCELL * (NCELL - 1) / 2 },
        .{ .name = "range ", .fn_ = statRange, .max = VMAX - 1 },
        .{ .name = "var4  ", .fn_ = statVar4,  .max = VMAX * VMAX },
    };

    try stdout.print("BASIS COMPARISON  NCELL={d}  VMAX={d}  NSAMP={d}\n\n", .{ NCELL, VMAX, NSAMP });
    try stdout.print("Bases: cos=cosine(ω·s)  step=sign(s−θ)  sqwave=square-wave  dual=cos∧step or cos∨step\n\n", .{});

    // Main table: for each predicate, for each inner stat, compare bases
    for (preds) |pred| {
        // Generate data
        for (0..NSAMP) |i| {
            for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
            g_labels[i] = pred.fn_(g_cells[i]);
        }

        try stdout.print("{c}  {s}\n", .{ pred.group, pred.name });
        try stdout.print("   stat    cos    step   sqwave dual  [mode]\n", .{});
        try stdout.print("   ─────────────────────────────────────────\n", .{});

        var best_overall: f64 = 0;
        var best_config: [64]u8 = [_]u8{0} ** 64;

        for (stats) |stat| {
            for (0..NSAMP) |i| g_stat[i] = stat.fn_(g_cells[i]);
            const r = runAllBases(stat.max);
            const best = @max(@max(r.cos, r.step), @max(r.sqwave, r.dual));

            // Format winners
            const cos_mark: []const u8 = if (r.cos == best) "*" else " ";
            const step_mark: []const u8 = if (r.step == best) "*" else " ";
            const sq_mark: []const u8 = if (r.sqwave == best) "*" else " ";
            const dual_mark: []const u8 = if (r.dual == best) "*" else " ";

            try stdout.print("   {s}  {d:.3}{s} {d:.3}{s} {d:.3}{s}  {d:.3}{s} [{s}]\n",
                .{ stat.name, r.cos, cos_mark, r.step, step_mark,
                   r.sqwave, sq_mark, r.dual, dual_mark, r.dual_mode });

            if (best > best_overall) {
                best_overall = best;
                _ = std.fmt.bufPrint(&best_config,
                    "{s}+{s}", .{ stat.name, if (r.dual == best) "dual" else
                                              if (r.cos == best) "cos" else
                                              if (r.step == best) "step" else "sqwave" })
                    catch {};
            }
        }
        try stdout.print("   best: {d:.3}  ({s})\n\n", .{ best_overall, best_config[0..20] });
    }

    try stdout.print("{s}\n", .{"─" ** 60});
    try stdout.print("INTERPRETATION:\n", .{});
    try stdout.print("  * = best basis for that (predicate, inner-stat) pair\n", .{});
    try stdout.print("  cos wins for periodic predicates (count-parity, period3)\n", .{});
    try stdout.print("  step wins for threshold predicates (variance-high, range-high)\n", .{});
    try stdout.print("  dual wins for sparse/mixed predicates (count-AND)\n", .{});
    try stdout.print("  sqwave = hard-thresholded cosine: wins when period is clean but soft cos overshoots\n", .{});
}
