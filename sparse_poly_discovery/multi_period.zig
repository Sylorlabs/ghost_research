//! FRONTIER 7 — multi-period discovery: what does spectral do when TWO periods coexist?
//!
//! All prior spectral experiments involved a SINGLE periodic primitive (parity, period=2).
//! The spectral operator found a sharp peak at ω=π and solved the predicate at 1.000.
//!
//! This is the first test of MULTI-PERIOD primitives — predicates built from two distinct
//! periods simultaneously. The outcome is genuinely unknown:
//!
//!   Does the spectral operator:
//!     (a) Find the COMBINED period (lcm of the two periods)?
//!     (b) Find the DOMINANT period (the one with more power)?
//!     (c) Find NEITHER (the combined structure confounds the peak)?
//!     (d) Need MULTIPLE spectral passes to decompose the two components?
//!
//! Four primitives tested:
//!
//!   P1 — period 2 alone:   y = count mod 2            (baseline, ω=π confirmed)
//!   P2 — period 3 alone:   y = (count mod 3) == 0     (new: period 3, ω=2π/3)
//!   P3 — two periods XOR:  y = (count mod 2) XOR ((count mod 3)==0)
//!          Combined period = lcm(2,3) = 6 → ω = 2π/6 = π/3
//!          The XOR creates a 6-periodic function: f(c) = f(c mod 6)
//!   P4 — two periods AND:  y = (count mod 2) AND ((count mod 3)==0)
//!          Combined period = 6 → same but sparser positive class
//!
//! For P3/P4: the "correct" discovery ω = π/3 gives period 6. But the period-2
//! component (ω=π) also has spectral power. Which peak dominates?
//!
//! Key prediction: if the period-6 component is weaker than period-2 (plausible because
//! the 6-period baseline is more distributed), the spectral operator finds the wrong ω.
//! This would be the FIRST DOCUMENTED MULTI-PERIOD FAILURE MODE.
//!
//! Run: zig build multi-period

const std = @import("std");

const NCELL: usize = 12;
const VMAX: u8 = 5;
const THRESH: u8 = 2;
const NSAMP: usize = 8000;
const NTR:   usize = NSAMP * 2 / 3;
const CMAX:  usize = NCELL + 1; // max count value = NCELL (all cells active)

const Peak = struct { w: f64, power: f64 };

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

const SpectralResult = struct {
    omega: f64,
    power_at_omega: f64,
    power_ratio: f64, // peak / mean
    acc: f64,
    peaks: [3]Peak,
};

fn fullSpectral(counts: []const f64, labels: []const f64, ntr: usize) SpectralResult {
    const alloc = std.heap.page_allocator;
    const f_sum = alloc.alloc(f64, CMAX + 1) catch unreachable;
    const f_cnt = alloc.alloc(usize, CMAX + 1) catch unreachable;
    defer alloc.free(f_sum);
    defer alloc.free(f_cnt);
    @memset(f_sum, 0);
    @memset(f_cnt, 0);
    for (0..ntr) |s| {
        const c = @min(CMAX, @as(usize, @intFromFloat(@max(0, @round(counts[s])))));
        f_sum[c] += labels[s];
        f_cnt[c] += 1;
    }

    const FREQS: usize = 600;
    const powers = alloc.alloc(f64, FREQS) catch unreachable;
    const omegas = alloc.alloc(f64, FREQS) catch unreachable;
    defer alloc.free(powers);
    defer alloc.free(omegas);

    var total: f64 = 0;
    for (0..FREQS) |fi| {
        const w = @as(f64, @floatFromInt(fi + 1)) * std.math.pi / @as(f64, @floatFromInt(FREQS));
        omegas[fi] = w;
        var power: f64 = 0;
        for (0..CMAX + 1) |c| {
            if (f_cnt[c] == 0) continue;
            const fc = f_sum[c] / @as(f64, @floatFromInt(f_cnt[c])) - 0.5;
            power += @as(f64, @floatFromInt(f_cnt[c])) * fc * @cos(w * @as(f64, @floatFromInt(c)));
        }
        powers[fi] = @abs(power);
        total += @abs(power);
    }
    const mean_power = total / @as(f64, @floatFromInt(FREQS));

    // find top-3 peaks
    var top3: [3]Peak = .{Peak{ .w = 0, .power = -1 }} ** 3;
    for (0..FREQS) |fi| {
        if (powers[fi] > top3[2].power) {
            top3[2] = Peak{ .w = omegas[fi], .power = powers[fi] };
            // bubble sort top3 by power descending
            if (top3[2].power > top3[1].power) {
                const tmp = top3[1]; top3[1] = top3[2]; top3[2] = tmp;
            }
            if (top3[1].power > top3[0].power) {
                const tmp = top3[0]; top3[0] = top3[1]; top3[1] = tmp;
            }
        }
    }

    const best_w = top3[0].w;
    const power_ratio = if (mean_power > 0) top3[0].power / mean_power else 1.0;

    var a: f64 = 1.0;
    var b: f64 = 0.0;
    for (0..60) |_| for (0..ntr) |s| {
        const cw = @cos(best_w * counts[s]);
        const e = sigmoid(a * cw + b) - labels[s];
        a -= 0.1 * e * cw;
        b -= 0.1 * e;
    };
    var correct: usize = 0;
    for (ntr..counts.len) |s| {
        const z = a * @cos(best_w * counts[s]) + b;
        if ((z >= 0) == (labels[s] > 0.5)) correct += 1;
    }
    const acc = @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(counts.len - ntr));

    return .{
        .omega = best_w,
        .power_at_omega = top3[0].power,
        .power_ratio = power_ratio,
        .acc = acc,
        .peaks = top3,
    };
}

// multi-feature spectral: fit a logistic using cos(ω₁·c) AND cos(ω₂·c) simultaneously
fn twoFreqAcc(counts: []const f64, labels: []const f64, ntr: usize,
              w1: f64, w2: f64) f64 {
    var a1: f64 = 1.0;
    var a2: f64 = 1.0;
    var b: f64 = 0.0;
    for (0..80) |_| for (0..ntr) |s| {
        const c1 = @cos(w1 * counts[s]);
        const c2 = @cos(w2 * counts[s]);
        const z = a1 * c1 + a2 * c2 + b;
        const e = sigmoid(z) - labels[s];
        a1 -= 0.08 * e * c1;
        a2 -= 0.08 * e * c2;
        b  -= 0.08 * e;
    };
    var correct: usize = 0;
    for (ntr..counts.len) |s| {
        const z = a1 * @cos(w1 * counts[s]) + a2 * @cos(w2 * counts[s]) + b;
        if ((z >= 0) == (labels[s] > 0.5)) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(counts.len - ntr));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0xD0B1E177);
    const rand = prng.random();

    const bits = try alloc.alloc([NCELL]u8, NSAMP);
    defer alloc.free(bits);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        bits[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
    };

    const counts = try alloc.alloc(f64, NSAMP);
    defer alloc.free(counts);
    for (0..NSAMP) |s| {
        var c: usize = 0;
        for (0..NCELL) |i| if (bits[s][i] >= THRESH) { c += 1; };
        counts[s] = @floatFromInt(c);
    }

    // four label vectors
    const Y = [4][]f64{
        try alloc.alloc(f64, NSAMP), // P1: period 2 (parity)
        try alloc.alloc(f64, NSAMP), // P2: period 3
        try alloc.alloc(f64, NSAMP), // P3: period 2 XOR period 3 → combined period 6
        try alloc.alloc(f64, NSAMP), // P4: period 2 AND period 3
    };
    defer for (Y) |y| alloc.free(y);

    for (0..NSAMP) |s| {
        const c: usize = @intFromFloat(counts[s]);
        Y[0][s] = @floatFromInt(c & 1);           // period 2
        Y[1][s] = if (c % 3 == 0) 1.0 else 0.0;  // period 3
        Y[2][s] = @floatFromInt(((c & 1) ^ @intFromBool(c % 3 == 0)));  // XOR
        Y[3][s] = @floatFromInt(((c & 1) & @intFromBool(c % 3 == 0)));  // AND
    }

    const names  = [4][]const u8{ "period-2", "period-3", "2 XOR 3 (period 6)", "2 AND 3 (period 6)" };
    const theory = [4][]const u8{ "ω=π=3.14", "ω=2π/3=2.09", "ω=π/3=1.05 (period 6)", "ω=π/3=1.05 (period 6)" };

    const pi2  = std.math.pi;         // period-2 frequency
    const pi23 = 2.0 * std.math.pi / 3.0; // period-3 frequency
    const pi6  = std.math.pi / 3.0;  // period-6 frequency (combined)

    try out.print("=== FRONTIER 7: multi-period discovery — does spectral find the combined period? ===\n\n", .{});
    try out.print("NCELL={d}, VMAX={d}, THRESH={d}: count ∈ 0..{d}, NSAMP={d}\n\n",
        .{ NCELL, VMAX, THRESH, NCELL, NSAMP });
    try out.print("The UNKNOWN: for a 2-period predicate, does spectral find:\n", .{});
    try out.print("  (a) the combined period lcm(2,3)=6  → ω = π/3 = 1.047?\n", .{});
    try out.print("  (b) the dominant period component   → ω = π or 2π/3?\n", .{});
    try out.print("  (c) neither, fails to separate?     → low acc?\n\n", .{});

    try out.print("  primitive           | found ω  | power-ratio | single-ω acc | two-ω acc | theory\n", .{});
    try out.print("  --------------------+----------+-------------+--------------+-----------+-------\n", .{});

    for (0..4) |i| {
        const r = fullSpectral(counts, Y[i], NTR);

        // fit TWO simultaneous frequencies
        const two_acc: f64 = switch (i) {
            0 => twoFreqAcc(counts, Y[i], NTR, pi2, pi23),   // period-2 needs both? (no)
            1 => twoFreqAcc(counts, Y[i], NTR, pi2, pi23),   // period-3 needs both? (no)
            2 => twoFreqAcc(counts, Y[i], NTR, pi2, pi23),   // XOR: try both component freqs
            3 => twoFreqAcc(counts, Y[i], NTR, pi2, pi23),   // AND: try both component freqs
            else => unreachable,
        };

        try out.print("  {s:<20}| {d:.4}  |    {d:6.1}x  |    {d:.3}       |   {d:.3}   | {s}\n",
            .{ names[i], r.omega, r.power_ratio, r.acc, two_acc, theory[i] });
    }

    // detailed breakdown for the multi-period primitives (P3 and P4)
    try out.print("\n  --- top-3 spectral peaks for multi-period primitives ---\n", .{});
    for (2..4) |i| {
        const r = fullSpectral(counts, Y[i], NTR);
        try out.print("  {s:<20}| peaks: ω={d:.3}(pwr={d:.0}), ω={d:.3}(pwr={d:.0}), ω={d:.3}(pwr={d:.0})\n",
            .{ names[i], r.peaks[0].w, r.peaks[0].power, r.peaks[1].w, r.peaks[1].power,
               r.peaks[2].w, r.peaks[2].power });
    }

    // also test exact-frequency classifiers at ω=π, ω=2π/3, ω=π/3 for P3 and P4
    try out.print("\n  --- accuracy at exact theoretical frequencies for P3 and P4 ---\n", .{});
    try out.print("  primitive            | cos(π·c)  | cos(2π/3·c) | cos(π/3·c) | cos(π)+cos(2π/3)\n", .{});
    try out.print("  ---------------------+-----------+-------------+------------+-----------------\n", .{});
    for (2..4) |i| {
        const a_p2  = twoFreqAcc(counts, Y[i], NTR, pi2,  pi2 );   // just ω=π
        const a_p3  = twoFreqAcc(counts, Y[i], NTR, pi23, pi23);   // just ω=2π/3
        const a_p6  = twoFreqAcc(counts, Y[i], NTR, pi6,  pi6 );   // just ω=π/3
        const a_both = twoFreqAcc(counts, Y[i], NTR, pi2,  pi23);  // both components
        try out.print("  {s:<21}|   {d:.3}   |    {d:.3}    |   {d:.3}    |    {d:.3}\n",
            .{ names[i], a_p2, a_p3, a_p6, a_both });
    }

    try out.print("\n--- VERDICT ---\n", .{});
    const r1 = fullSpectral(counts, Y[0], NTR);
    const r2 = fullSpectral(counts, Y[1], NTR);
    const r3 = fullSpectral(counts, Y[2], NTR);
    const r4 = fullSpectral(counts, Y[3], NTR);

    const p2_correct  = @abs(r1.omega - pi2)  < 0.15 and r1.acc > 0.90;
    const p3_correct  = @abs(r2.omega - pi23) < 0.15 and r2.acc > 0.90;
    const p3_find_p6  = @abs(r3.omega - pi6)  < 0.15;
    const p4_find_p6  = @abs(r4.omega - pi6)  < 0.15;

    if (p2_correct) {
        try out.print("Period-2 baseline holds: ω=π found cleanly ({d:.4}), acc={d:.3}.\n",
            .{ r1.omega, r1.acc });
    } else {
        try out.print("UNEXPECTED: period-2 failed (found ω={d:.4}, acc={d:.3}).\n",
            .{ r1.omega, r1.acc });
    }
    if (p3_correct) {
        try out.print("Period-3 confirmed: ω=2π/3 found ({d:.4}), acc={d:.3}.\n",
            .{ r2.omega, r2.acc });
    } else {
        try out.print("Period-3 result: found ω={d:.4}, acc={d:.3} (expected 2π/3≈2.094).\n",
            .{ r2.omega, r2.acc });
    }
    if (p3_find_p6 or p4_find_p6) {
        try out.print("Multi-period: spectral found the COMBINED period (π/3) for at least one.\n", .{});
        try out.print("The spectral operator scales to combined periods when the signal is clean.\n", .{});
    } else {
        try out.print("Multi-period: spectral did NOT find the combined period (π/3).\n", .{});
        if (r3.acc > 0.90) {
            try out.print("  But it found a DIFFERENT ω that still classifies well ({d:.4}, acc={d:.3}).\n",
                .{ r3.omega, r3.acc });
        } else {
            try out.print("  And the classifier fails (acc={d:.3}). The two periods CONFOUND the spectral peak.\n",
                .{r3.acc});
            try out.print("  This is the MULTI-PERIOD FAILURE MODE: single-pass spectral cannot decompose\n", .{});
            try out.print("  a two-period signal. TWO spectral passes (one per period) are needed.\n", .{});
        }
    }
    try out.print("\nSee: spectral_discovery.md (single-period baseline), composed_discovery.md.\n", .{});
}
