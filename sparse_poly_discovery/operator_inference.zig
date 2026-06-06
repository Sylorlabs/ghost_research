//! FRONTIER 6 — can structural probes identify a composed family without being told?
//!
//! composed_discovery.md left the key question open: the staged pipeline for
//! inversion-parity required KNOWING the decomposition (inversion count is the inner
//! quantity; parity is the outer structure). A genuine discoverer must infer this.
//!
//! This experiment tests a specific new structural probe: the POWER-ACCURACY MISMATCH.
//!
//!   Hypothesis: when spectral is applied to the WRONG domain (raw count for
//!   inversion-parity), it finds a "spectral peak" (high power), but the classifier
//!   from that peak FAILS (low accuracy). A simple periodic family (parity of raw count)
//!   shows high power AND high accuracy. The mismatch — high power, low accuracy — is
//!   the composition signal.
//!
//! Three families compared:
//!   F1 — parity-of-count:    y = (Σbᵢ) mod 2   [simple periodic]
//!   F2 — inversion-parity:   y = (inv_count) mod 2  [composed: periodic-in-relational]
//!   F3 — XOR(b0,b1):         y = b0 XOR b1     [pure relational, no periodicity]
//!
//! Five probes per family:
//!   P1  linear accuracy over [bᵢ] features
//!   P2a spectral power ratio on raw count (peak power / mean power)
//!   P2b spectral classifier accuracy at P2a's peak ω
//!   P3  swap-delta: |E[y|b0=1,b1=0] − E[y|b0=0,b1=1]| (orientation signal)
//!   P4  order lift: accuracy(deg-2) / accuracy(deg-1)
//!
//! Composition detector:
//!   P2a > POWER_THR AND P2b < ACC_THR → MISMATCH → try spectral on inversion count
//!   If inv-spectral acc >> raw-spectral acc → COMPOSED
//!
//! Run: zig build operator-inference

const std = @import("std");

const NCELL: usize = 8;
const VMAX: u8 = 5;
const THRESH: u8 = 2;
const NSAMP: usize = 8000;
const NTR:   usize = NSAMP * 2 / 3;
const POWER_THR: f64 = 5.0;
const ACC_THR:   f64 = 0.72;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn standardize(X: [][]f64, ntr: usize, dim: usize) void {
    for (0..dim) |j| {
        var mu: f64 = 0;
        for (0..ntr) |s| mu += X[s][j];
        mu /= @floatFromInt(ntr);
        var sd: f64 = 0;
        for (0..ntr) |s| sd += (X[s][j] - mu) * (X[s][j] - mu);
        sd = @max(1e-5, @sqrt(sd / @as(f64, @floatFromInt(ntr))));
        for (0..X.len) |s| X[s][j] = (X[s][j] - mu) / sd;
    }
}

fn linAcc(X: []const []f64, Y: []const f64, ntr: usize, dim: usize) f64 {
    const alloc = std.heap.page_allocator;
    const w = alloc.alloc(f64, dim) catch unreachable;
    defer alloc.free(w);
    @memset(w, 0);
    var bias: f64 = 0;
    const lr: f64 = 0.05;
    for (0..100) |_| for (0..ntr) |s| {
        var z = bias;
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        bias -= lr * e;
    };
    var correct: usize = 0;
    for (ntr..X.len) |s| {
        var z = bias;
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(X.len - ntr));
}

const SpectralOut = struct { power_ratio: f64, omega: f64, acc: f64 };

fn runSpectral(counts: []const f64, labels: []const f64,
               ntr: usize, cmax: usize) SpectralOut {
    const alloc = std.heap.page_allocator;
    const f_sum = alloc.alloc(f64, cmax + 1) catch unreachable;
    const f_cnt = alloc.alloc(usize, cmax + 1) catch unreachable;
    defer alloc.free(f_sum);
    defer alloc.free(f_cnt);
    @memset(f_sum, 0);
    @memset(f_cnt, 0);
    for (0..ntr) |s| {
        const c = @min(cmax, @as(usize, @intFromFloat(@max(0, @round(counts[s])))));
        f_sum[c] += labels[s];
        f_cnt[c] += 1;
    }
    const FREQS: usize = 400;
    var best_pow: f64 = -1;
    var best_w: f64 = 0;
    var total_power: f64 = 0;
    for (1..FREQS + 1) |fi| {
        const w = @as(f64, @floatFromInt(fi)) * std.math.pi / @as(f64, @floatFromInt(FREQS));
        var power: f64 = 0;
        for (0..cmax + 1) |c| {
            if (f_cnt[c] == 0) continue;
            const fc = f_sum[c] / @as(f64, @floatFromInt(f_cnt[c])) - 0.5;
            power += @as(f64, @floatFromInt(f_cnt[c])) * fc * @cos(w * @as(f64, @floatFromInt(c)));
        }
        total_power += @abs(power);
        if (@abs(power) > best_pow) { best_pow = @abs(power); best_w = w; }
    }
    const power_ratio = if (total_power > 0)
        best_pow / (total_power / @as(f64, @floatFromInt(FREQS)))
    else 1.0;

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
    return .{ .power_ratio = power_ratio, .omega = best_w, .acc = acc };
}

fn swapDelta(Y: []const f64, b: [][NCELL]f64) f64 {
    var s10: f64 = 0; var c10: f64 = 0;
    var s01: f64 = 0; var c01: f64 = 0;
    for (0..NTR) |s| {
        const b0 = b[s][0] > 0.5;
        const b1 = b[s][1] > 0.5;
        if (b0 and !b1) { s10 += Y[s]; c10 += 1; }
        if (!b0 and b1) { s01 += Y[s]; c01 += 1; }
    }
    if (c10 == 0 or c01 == 0) return 0;
    return @abs(s10 / c10 - s01 / c01);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    var prng = std.Random.DefaultPrng.init(0x0FEE1234);
    const rand = prng.random();

    const grid = try alloc.alloc([NCELL]u8, NSAMP);
    const bits  = try alloc.alloc([NCELL]f64, NSAMP);
    defer alloc.free(grid);
    defer alloc.free(bits);
    for (0..NSAMP) |s| for (0..NCELL) |i| {
        grid[s][i] = rand.intRangeAtMost(u8, 0, VMAX);
        bits[s][i] = if (grid[s][i] >= THRESH) @as(f64, 1.0) else @as(f64, 0.0);
    };

    const raw_count = try alloc.alloc(f64, NSAMP);
    const inv_count = try alloc.alloc(f64, NSAMP);
    defer alloc.free(raw_count);
    defer alloc.free(inv_count);
    var inv_max: f64 = 0;
    for (0..NSAMP) |s| {
        var rc: usize = 0;
        for (0..NCELL) |i| if (bits[s][i] > 0.5) { rc += 1; };
        raw_count[s] = @floatFromInt(rc);
        var inv: usize = 0;
        for (0..NCELL) |i| for (i + 1..NCELL) |j| {
            if (grid[s][i] > grid[s][j]) inv += 1;
        };
        inv_count[s] = @floatFromInt(inv);
        if (inv_count[s] > inv_max) inv_max = inv_count[s];
    }

    const Yf1 = try alloc.alloc(f64, NSAMP);
    const Yf2 = try alloc.alloc(f64, NSAMP);
    const Yf3 = try alloc.alloc(f64, NSAMP);
    defer alloc.free(Yf1); defer alloc.free(Yf2); defer alloc.free(Yf3);
    for (0..NSAMP) |s| {
        Yf1[s] = @floatFromInt(@as(usize, @intFromFloat(raw_count[s])) & 1);
        Yf2[s] = @floatFromInt(@as(usize, @intFromFloat(inv_count[s])) & 1);
        Yf3[s] = if ((bits[s][0] > 0.5) != (bits[s][1] > 0.5)) 1.0 else 0.0;
    }

    const npairs = NCELL * (NCELL - 1) / 2;

    // first-order features
    const Xlin = try alloc.alloc([]f64, NSAMP);
    defer { for (Xlin) |r| alloc.free(r); alloc.free(Xlin); }
    for (0..NSAMP) |s| {
        Xlin[s] = try alloc.alloc(f64, NCELL);
        @memcpy(Xlin[s], &bits[s]);
    }
    standardize(Xlin, NTR, NCELL);

    // second-order features [bits | pairwise products]
    const Xdeg2 = try alloc.alloc([]f64, NSAMP);
    defer { for (Xdeg2) |r| alloc.free(r); alloc.free(Xdeg2); }
    for (0..NSAMP) |s| {
        Xdeg2[s] = try alloc.alloc(f64, NCELL + npairs);
        @memcpy(Xdeg2[s][0..NCELL], &bits[s]);
        var pi: usize = NCELL;
        for (0..NCELL) |i| for (i + 1..NCELL) |j| {
            Xdeg2[s][pi] = bits[s][i] * bits[s][j];
            pi += 1;
        };
    }
    standardize(Xdeg2, NTR, NCELL + npairs);

    const family_names = [_][]const u8{ "parity-of-count", "inversion-parity", "XOR(b0,b1)" };
    const family_labels = [_][]const f64{ Yf1, Yf2, Yf3 };

    try out.print("=== FRONTIER 6: composition detection via power-accuracy mismatch ===\n\n", .{});
    try out.print("KEY HYPOTHESIS: spectral on the WRONG domain shows high power but low accuracy.\n", .{});
    try out.print("That mismatch — not the power alone — is the composition signal.\n\n", .{});

    const FamilyResult = struct {
        p1: f64, p2a: f64, p2b: f64, p3: f64, p4: f64,
        inv_acc: f64, detect: []const u8,
    };
    var results: [3]FamilyResult = undefined;

    for (0..3) |fi| {
        const Y = family_labels[fi];
        const p1 = linAcc(Xlin, Y, NTR, NCELL);
        const sp  = runSpectral(raw_count, Y, NTR, NCELL);
        const p2a = sp.power_ratio;
        const p2b = sp.acc;
        const p3  = swapDelta(Y, bits);
        const p4d1 = linAcc(Xlin,  Y, NTR, NCELL);
        const p4d2 = linAcc(Xdeg2, Y, NTR, NCELL + npairs);
        const p4   = if (p4d1 > 0.55) p4d2 / p4d1 else 9.9;

        const sp_inv = runSpectral(inv_count, Y, NTR, @intFromFloat(inv_max));
        const mismatch = p2a > POWER_THR and p2b < ACC_THR;

        const detect: []const u8 = blk: {
            if (p1 > 0.80) break :blk "LINEAR";
            if (p2a > POWER_THR and p2b >= ACC_THR) break :blk "SPECTRAL";
            if (p3 > 0.20) break :blk "ORIENTED";
            if (mismatch and sp_inv.acc > p2b + 0.20) break :blk "COMPOSED";
            if (p4 > 1.4 and p3 < 0.15) break :blk "RELATIONAL";
            break :blk "?";
        };

        results[fi] = .{ .p1=p1, .p2a=p2a, .p2b=p2b, .p3=p3, .p4=p4,
                          .inv_acc=sp_inv.acc, .detect=detect };
    }

    try out.print("  family              | P1 lin | P2a pwr | P2b acc | P3 swap | P4 ord | → detect\n", .{});
    try out.print("  --------------------+--------+---------+---------+---------+--------+---------\n", .{});
    for (0..3) |fi| {
        const r = results[fi];
        try out.print("  {s:<20}| {d:.3}  | {d:6.1}x | {d:.3}   | {d:.3}   | {d:.2}x | {s}\n",
            .{ family_names[fi], r.p1, r.p2a, r.p2b, r.p3, r.p4, r.detect });
    }

    try out.print("\n  --- COMPOSITION probe detail ---\n", .{});
    try out.print("  family              | raw-spectral acc | inv-spectral acc | mismatch?\n", .{});
    try out.print("  --------------------+------------------+------------------+----------\n", .{});
    for (0..3) |fi| {
        const r = results[fi];
        const mismatch = r.p2a > POWER_THR and r.p2b < ACC_THR;
        const inv_beats = r.inv_acc > r.p2b + 0.20;
        const signal: []const u8 = if (mismatch and inv_beats) "YES → COMPOSED"
                                   else if (mismatch)          "MISMATCH (inv weak)"
                                   else                        "no";
        try out.print("  {s:<20}|       {d:.3}        |       {d:.3}        | {s}\n",
            .{ family_names[fi], r.p2b, r.inv_acc, signal });
    }

    try out.print("\n--- VERDICT ---\n", .{});
    const f1_correct = std.mem.eql(u8, results[0].detect, "SPECTRAL");
    const f2_correct = std.mem.eql(u8, results[1].detect, "COMPOSED");
    const f3_correct = std.mem.eql(u8, results[2].detect, "RELATIONAL");

    if (f1_correct and f2_correct and f3_correct) {
        try out.print("FULL DETECTION: all three families correctly identified.\n", .{});
        try out.print("Power-accuracy mismatch IS a reliable composition signal.\n", .{});
        try out.print("  F1 parity-of-count:   high power ({d:.1}x) + high acc ({d:.3}) → SPECTRAL\n",
            .{ results[0].p2a, results[0].p2b });
        try out.print("  F2 inversion-parity:  power ({d:.1}x) + low acc ({d:.3}) → MISMATCH → COMPOSED\n",
            .{ results[1].p2a, results[1].p2b });
        try out.print("  F3 XOR:               no power, order lift → RELATIONAL\n", .{});
    } else {
        try out.print("PARTIAL detection: F1={s} F2={s} F3={s}\n",
            .{ results[0].detect, results[1].detect, results[2].detect });
        if (!f1_correct)
            try out.print("  F1 failed: power={d:.1}x acc={d:.3} — parity-of-count harder than expected.\n",
                .{ results[0].p2a, results[0].p2b });
        if (!f2_correct)
            try out.print("  F2 failed: raw acc={d:.3} inv acc={d:.3} — mismatch gap too small.\n",
                .{ results[1].p2b, results[1].inv_acc });
        if (!f3_correct)
            try out.print("  F3 failed: P4={d:.2}x P3={d:.3} — XOR order lift weaker than expected.\n",
                .{ results[2].p4, results[2].p3 });
    }
    try out.print("\nSee: composed_discovery.md, spectral_discovery.md.\n", .{});
}
