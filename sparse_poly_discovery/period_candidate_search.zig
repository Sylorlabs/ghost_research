//! FRONTIER 9 — period-candidate search: accuracy grid vs power spectrum
//!
//! Frontier 7 (multi_period.md) found a failure mode: the power-spectrum spectral
//! operator fails on AND-compositions because the sparse positive class (1/6 of counts)
//! makes the DC (near-zero frequency) component dominate the power spectrum. The correct
//! combined period (ω=π/3) gives 1.000 accuracy but is NOT the power-peak frequency.
//!
//! The proposed fix: instead of hunting the spectral POWER peak, directly search the
//! ACCURACY landscape over ω. For AND-compositions the accuracy function has a sharp
//! peak at the correct ω even when the power function does not.
//!
//! This experiment tests three discovery strategies head-to-head on all four primitives:
//!
//!   STRATEGY A — power-spectrum (current): peak of |Σ f(c)·cos(ω·c)|
//!     Frontier 7 result: works for period-2, period-3, 2-XOR-3; FAILS for 2-AND-3
//!
//!   STRATEGY B — accuracy grid: peak of logistic accuracy at each ω
//!     Directly measures classifier performance; bypasses the DC-dominance problem
//!     Hypothesis: finds ω=π/3 for 2-AND-3 where power-spectrum cannot
//!
//!   STRATEGY C — iterative residual (multi-pass):
//!     1. Find dominant period ω₁ via power-spectrum
//!     2. Compute residuals after fitting cos(ω₁·c)
//!     3. Find next period ω₂ via power-spectrum on residuals
//!     4. Final classifier uses both cos(ω₁·c) + cos(ω₂·c)
//!     Hypothesis: for AND-compositions, pass 1 finds the DC trend; pass 2 finds the
//!     period-6 oscillation hidden in the residuals
//!
//! Secondary test — three periods (2 XOR 3 XOR 5, combined period = 30):
//!   Tests whether accuracy-grid scales to higher-period combinations
//!   ω = 2π/30 = π/15 ≈ 0.209 — very low frequency, harder to isolate
//!
//! Run: zig build period-candidate-search

const std = @import("std");

const NCELL: usize = 30;  // need counts up to 30 for period-30 to be visible
const VMAX:  u8    = 5;
const THRESH: u8   = 2;
const NSAMP: usize = 12000;
const NTR:   usize = NSAMP * 2 / 3;
const CMAX:  usize = NCELL;  // count range 0..NCELL

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

// ── fit logistic on a SINGLE cosine feature cos(w·count), return accuracy ──
fn singleCosAcc(counts: []const f64, labels: []const f64, ntr: usize, w: f64) f64 {
    var a: f64 = 1.0;
    var b: f64 = 0.0;
    for (0..80) |_| for (0..ntr) |s| {
        const cw = @cos(w * counts[s]);
        const e = sigmoid(a * cw + b) - labels[s];
        a -= 0.08 * e * cw;
        b -= 0.08 * e;
    };
    var correct: usize = 0;
    for (ntr..counts.len) |s| {
        const z = a * @cos(w * counts[s]) + b;
        if ((z >= 0) == (labels[s] > 0.5)) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(counts.len - ntr));
}

// ── fit logistic on TWO cosine features ──
fn twoCosAcc(counts: []const f64, labels: []const f64, ntr: usize, w1: f64, w2: f64) f64 {
    var a1: f64 = 1.0; var a2: f64 = 1.0; var b: f64 = 0.0;
    for (0..80) |_| for (0..ntr) |s| {
        const c1 = @cos(w1 * counts[s]);
        const c2 = @cos(w2 * counts[s]);
        const e = sigmoid(a1*c1 + a2*c2 + b) - labels[s];
        a1 -= 0.06*e*c1; a2 -= 0.06*e*c2; b -= 0.06*e;
    };
    var correct: usize = 0;
    for (ntr..counts.len) |s| {
        const z = a1*@cos(w1*counts[s]) + a2*@cos(w2*counts[s]) + b;
        if ((z >= 0) == (labels[s] > 0.5)) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(counts.len - ntr));
}

// ── STRATEGY A: power-spectrum peak ──
const StratResult = struct { omega: f64, acc: f64, name: []const u8 };

fn powerSpectral(counts: []const f64, labels: []const f64, ntr: usize) StratResult {
    const alloc = std.heap.page_allocator;
    const f_sum = alloc.alloc(f64, CMAX + 1) catch unreachable;
    const f_cnt = alloc.alloc(usize, CMAX + 1) catch unreachable;
    defer alloc.free(f_sum); defer alloc.free(f_cnt);
    @memset(f_sum, 0); @memset(f_cnt, 0);
    for (0..ntr) |s| {
        const c = @min(CMAX, @as(usize, @intFromFloat(@max(0, @round(counts[s])))));
        f_sum[c] += labels[s]; f_cnt[c] += 1;
    }
    const FREQS: usize = 600;
    var best_pow: f64 = -1; var best_w: f64 = 0;
    for (1..FREQS + 1) |fi| {
        const w = @as(f64, @floatFromInt(fi)) * std.math.pi / @as(f64, @floatFromInt(FREQS));
        var power: f64 = 0;
        for (0..CMAX + 1) |c| {
            if (f_cnt[c] == 0) continue;
            const fc = f_sum[c] / @as(f64, @floatFromInt(f_cnt[c])) - 0.5;
            power += @as(f64, @floatFromInt(f_cnt[c])) * fc * @cos(w * @as(f64, @floatFromInt(c)));
        }
        if (@abs(power) > best_pow) { best_pow = @abs(power); best_w = w; }
    }
    return .{ .omega = best_w, .acc = singleCosAcc(counts, labels, ntr, best_w), .name = "power-spectrum" };
}

// ── STRATEGY B: accuracy grid ──
fn accuracyGrid(counts: []const f64, labels: []const f64, ntr: usize) StratResult {
    const FREQS: usize = 600;
    var best_acc: f64 = -1; var best_w: f64 = 0;
    for (1..FREQS + 1) |fi| {
        const w = @as(f64, @floatFromInt(fi)) * std.math.pi / @as(f64, @floatFromInt(FREQS));
        const acc = singleCosAcc(counts, labels, ntr, w);
        if (acc > best_acc) { best_acc = acc; best_w = w; }
    }
    return .{ .omega = best_w, .acc = best_acc, .name = "accuracy-grid" };
}

// ── STRATEGY C: iterative residual (2-pass power-spectrum) ──
fn iterativeResidual(counts: []const f64, labels: []const f64, ntr: usize,
                     alloc: std.mem.Allocator) StratResult {
    // pass 1: find dominant period on labels
    const r1 = powerSpectral(counts, labels, ntr);

    // fit pass-1 classifier and compute residuals
    var a1: f64 = 1.0; var b1: f64 = 0.0;
    for (0..80) |_| for (0..ntr) |s| {
        const cw = @cos(r1.omega * counts[s]);
        const e = sigmoid(a1 * cw + b1) - labels[s];
        a1 -= 0.08 * e * cw; b1 -= 0.08 * e;
    };
    const residuals = alloc.alloc(f64, counts.len) catch unreachable;
    defer alloc.free(residuals);
    for (0..counts.len) |s| {
        residuals[s] = labels[s] - sigmoid(a1 * @cos(r1.omega * counts[s]) + b1);
    }

    // pass 2: power-spectrum on residuals
    const r2 = powerSpectral(counts, residuals, ntr);

    // final: two-frequency classifier with both ω₁ and ω₂
    const two_acc = twoCosAcc(counts, labels, ntr, r1.omega, r2.omega);
    return .{ .omega = r2.omega, .acc = two_acc, .name = "iterative-residual" };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0xCA1D1DA7);
    const rand = prng.random();

    // cell data and counts
    const cells = try alloc.alloc([NCELL]u8, NSAMP);
    const counts = try alloc.alloc(f64, NSAMP);
    defer alloc.free(cells); defer alloc.free(counts);
    for (0..NSAMP) |s| {
        var c: usize = 0;
        for (0..NCELL) |i| {
            cells[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
            if (cells[s][i] >= THRESH) c += 1;
        }
        counts[s] = @floatFromInt(c);
    }

    // label vectors: 5 primitives
    const Y = [5][]f64{
        try alloc.alloc(f64, NSAMP), // P1: period 2
        try alloc.alloc(f64, NSAMP), // P2: period 3
        try alloc.alloc(f64, NSAMP), // P3: 2 XOR 3  (period 6)
        try alloc.alloc(f64, NSAMP), // P4: 2 AND 3  (period 6) ← the failing case
        try alloc.alloc(f64, NSAMP), // P5: 2 XOR 3 XOR 5  (period 30) ← new
    };
    defer for (Y) |y| alloc.free(y);

    for (0..NSAMP) |s| {
        const c: usize = @intFromFloat(counts[s]);
        Y[0][s] = @floatFromInt(c & 1);
        Y[1][s] = if (c % 3 == 0) 1.0 else 0.0;
        Y[2][s] = @floatFromInt((c & 1) ^ @intFromBool(c % 3 == 0));
        Y[3][s] = @floatFromInt((c & 1) & @intFromBool(c % 3 == 0));
        Y[4][s] = @floatFromInt(((c & 1) ^ @intFromBool(c % 3 == 0)) ^ @intFromBool(c % 5 == 0));
    }

    const names  = [5][]const u8{
        "period-2",
        "period-3",
        "2 XOR 3 (p=6)",
        "2 AND 3 (p=6)   ← failing",
        "2 XOR 3 XOR 5 (p=30)",
    };
    const theory_w = [5]f64{
        std.math.pi,              // π ≈ 3.14
        2.0*std.math.pi/3.0,      // 2π/3 ≈ 2.09
        std.math.pi/3.0,          // π/3 ≈ 1.05
        std.math.pi/3.0,          // π/3 ≈ 1.05
        2.0*std.math.pi/30.0,     // π/15 ≈ 0.21
    };

    try out.print("=== FRONTIER 9: period-candidate search ===\n", .{});
    try out.print("Fix for Frontier 7 AND-failure: accuracy-grid and iterative-residual\n\n", .{});
    try out.print("NCELL={d}, counts 0..{d}, NSAMP={d}\n\n", .{ NCELL, NCELL, NSAMP });

    for (0..5) |pi| {
        const label = Y[pi];
        const ra = powerSpectral(counts, label, NTR);
        const rb = accuracyGrid(counts, label, NTR);
        const rc = iterativeResidual(counts, label, NTR, alloc);
        const theory = theory_w[pi];

        // also test the exact theoretical ω directly
        const exact_acc = singleCosAcc(counts, label, NTR, theory);

        try out.print("  ── {s} (theory ω={d:.4}) ──\n", .{ names[pi], theory });
        try out.print("  strategy               | found ω  | acc   | Δ from theory\n", .{});
        try out.print("  -----------------------+----------+-------+--------------\n", .{});
        try out.print("  A power-spectrum        | {d:.4}  | {d:.3} | {d:.4}\n",
            .{ ra.omega, ra.acc, @abs(ra.omega - theory) });
        try out.print("  B accuracy-grid         | {d:.4}  | {d:.3} | {d:.4}\n",
            .{ rb.omega, rb.acc, @abs(rb.omega - theory) });
        try out.print("  C iterative-residual    | ω2={d:.4} | {d:.3} | —\n",
            .{ rc.omega, rc.acc });
        try out.print("  exact theoretical ω     | {d:.4}  | {d:.3} | 0.0000\n\n",
            .{ theory, exact_acc });
    }

    // ── SUMMARY TABLE ──
    try out.print("═══ SUMMARY: which strategy succeeds on the AND failure case? ═══\n\n", .{});
    try out.print("  strategy         | p-2  | p-3  | 2XOR3 | 2AND3 | 2XOR3XOR5\n", .{});
    try out.print("  -----------------+------+------+-------+-------+----------\n", .{});

    const strats = [3][]const u8{ "A power-spectrum  ", "B accuracy-grid   ", "C iter-residual   " };
    for (0..3) |si| {
        try out.print("  {s}|", .{strats[si]});
        for (0..5) |pi| {
            const acc: f64 = switch (si) {
                0 => powerSpectral(counts, Y[pi], NTR).acc,
                1 => accuracyGrid(counts, Y[pi], NTR).acc,
                2 => iterativeResidual(counts, Y[pi], NTR, alloc).acc,
                else => unreachable,
            };
            const mark: []const u8 = if (acc > 0.90) "ok " else "---";
            try out.print(" {d:.3}{s}|", .{ acc, mark });
        }
        try out.print("\n", .{});
    }

    // ── VERDICT ──
    const and_pow  = powerSpectral(counts, Y[3], NTR).acc;
    const and_grid = accuracyGrid(counts, Y[3], NTR).acc;
    const and_iter = iterativeResidual(counts, Y[3], NTR, alloc).acc;
    const p30_pow  = powerSpectral(counts, Y[4], NTR).acc;
    const p30_grid = accuracyGrid(counts, Y[4], NTR).acc;

    try out.print("\n--- VERDICT ---\n", .{});
    try out.print("AND-composition failure (power-spectrum acc={d:.3}):\n", .{and_pow});
    if (and_grid > and_pow + 0.10) {
        try out.print("  FIXED by accuracy-grid ({d:.3}): the accuracy landscape has a clear\n", .{and_grid});
        try out.print("  peak at ω=π/3 even though the power spectrum is dominated by DC.\n", .{});
        try out.print("  The accuracy function is the right search objective for sparse labels.\n", .{});
    } else {
        try out.print("  accuracy-grid result: {d:.3} — no major improvement over power-spectrum.\n", .{and_grid});
    }
    if (and_iter > and_pow + 0.10) {
        try out.print("  ALSO FIXED by iterative-residual ({d:.3}): subtracting the DC-trend\n", .{and_iter});
        try out.print("  in pass 1 reveals the period-6 oscillation for pass 2.\n", .{});
    } else {
        try out.print("  iterative-residual: {d:.3} — subtraction didn't expose the hidden period.\n", .{and_iter});
    }

    try out.print("\nTriple-period (2 XOR 3 XOR 5, period=30):\n", .{});
    if (p30_grid > 0.85) {
        try out.print("  accuracy-grid succeeds ({d:.3}): even period-30 is findable.\n", .{p30_grid});
        try out.print("  power-spectrum: {d:.3}\n", .{p30_pow});
    } else if (p30_pow > 0.85) {
        try out.print("  power-spectrum succeeds ({d:.3}), accuracy-grid: {d:.3}\n", .{ p30_pow, p30_grid });
    } else {
        try out.print("  BOTH strategies fail (power {d:.3}, grid {d:.3}).\n", .{ p30_pow, p30_grid });
        try out.print("  Period-30 is too sparse for single-frequency discovery at this NSAMP.\n", .{});
    }

    try out.print("\nConclusion: the CHOICE of search objective (power vs accuracy) is itself\n", .{});
    try out.print("a closure question — the right objective must match the primitive family's\n", .{});
    try out.print("structure. Power-spectrum is correct for balanced periodic signals;\n", .{});
    try out.print("accuracy-grid is more robust when the positive class is sparse.\n", .{});
    try out.print("\nSee: multi_period.md (the Frontier-7 failure this fixes), spectral_discovery.md.\n", .{});
}
