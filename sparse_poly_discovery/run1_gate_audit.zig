//! F3 (Round 2026-07-11b / Round F) -- RUN1 CERTIFIER-BOUNDARY AUDIT.
//!
//! Context: E1 (docs/research/repr_expansion.md) found that the `run` family's
//! exact member `run(maxRunGE3, ident)` scores val=1.000 / cov_after=1.000 for
//! target RUN1 ("longest run of >=3 consecutive cells >=3 reaches >=3"), yet
//! the standard pre-tax novelty gate (R^2 < 0.40 of the candidate's raw value
//! against the current growable library, `certifyLocal` in repr_expansion.zig)
//! REJECTS it at R^2 = 0.51-0.53. This is a new boundary type: representable
//! (exact solver exists) but certifier-blocked ("too reconstructible").
//!
//! THE QUESTION (instrument-trust, analogous to round c's matcher audits /
//! tier8_gate_v5.md's v3-vs-v5-ladder split): is the R^2 gate CORRECT here
//! (run(maxRunGE3) genuinely IS redundant with count-basis features) or is it
//! WRONG (a false rejection -- R^2 of a LINEAR fit is a poor proxy for
//! reconstructibility of a target whose true rule is a nonlinear threshold /
//! adjacency conjunction)?
//!
//! Design (four parts, matching the assignment):
//!  PART 1 -- Reproduce: rebuild RUN1's grid + exact member + gate rejection.
//!  PART 2 -- The core test: GREEDY MULTI-FEATURE reconstruction. Two attacks:
//!    (2a) "Incidental" library: greedy-select up to K_MAIN columns from the
//!         WHOLE existing (non-run) family menu to CLASSIFY RUN1's label
//!         directly (this is a strictly *stronger* reconstruction attempt than
//!         the original sequential single-best-per-stage ladder, since it
//!         picks the single best-classifying column from the ENTIRE menu at
//!         every round, not one per family in a fixed order). Then test the
//!         run candidate against THIS library exactly as certifyLocal would
//!         (cov_before/cov_after/R^2) -- the faithful reproduction number.
//!    (2b) "Dedicated" library: greedy-select up to K_MAIN columns to directly
//!         maximize R^2 of the RAW maxRunGE3 statistic (not the label) -- the
//!         most generous possible linear-reconstruction attempt, an upper
//!         bound on what ANY R^2-based novelty test could see.
//!  PART 3 -- Threshold ROC sweep: 4 run-family targets (RUN1 + 3 variants,
//!    all genuinely position/adjacency-dependent, "novel" by the same
//!    argument used for RUN1) + 3 already-certified novel targets (C09,
//!    RATIO1, MIXMOD1, recomputed independently) + 2 deliberately-constructed
//!    TRUE-REMIX candidates (countAtLeast(g,2) with `thresh` excluded from the
//!    pool; gridSum with `mono`+`world` excluded) with KNOWN ground truth
//!    (exact/near-exact linear functions of excluded-family features). Ground
//!    truth novelty = does a K_SECONDARY-round greedy library (excluding the
//!    candidate's own defining family) reach COVER on the label? Compare
//!    against the gate's R^2 verdict at threshold 0.40 and sweep other
//!    thresholds -- a confusion table / ROC, not just a claim.
//!  PART 4 -- Corrected measure: propose and test replacing single-column
//!    linear R^2 with "does a generous multi-feature composition of the
//!    excluded-family menu already classify the label to >= COVER?" and show
//!    which verdicts flip.
//!
//! Reuse (read-only, per the task): sparse_poly_discovery/repr_expansion.zig
//! for RUN1's definition (maxRunGE, labelRun1) and the novelty gate mechanism
//! (certifyLocal: escape = cov_before<COVER<=cov_after AND R^2<0.40, reconR2's
//! exact linear-regression-out-of-sample-R^2 definition). repr_expansion.zig
//! exposes no `pub` declarations (single-file convention, per its own header:
//! "duplicated numeric glue is the established convention here"), so the
//! needed pieces are TRANSCRIBED below, not imported, exactly like
//! repr_expansion.zig itself transcribed from tier8_reach_gap.zig. This file
//! does not modify or import repr_expansion.zig.
//!
//! Build (zig 0.14.1), from sparse_poly_discovery/:
//!   zig build-exe run1_gate_audit.zig -O ReleaseFast
//! Run:
//!   ./run1_gate_audit            (full: Part 1+2 at 3 seeds, Part 3+4 at 1 seed)
//!   ./run1_gate_audit --diag     (fast smoke: 1 seed, small K, reduced epochs)
//! Single-threaded (no std.Thread used) -- well under the <=2-thread bound.

const std = @import("std");

// ── Constants (identical splits/thresholds to repr_expansion.zig) ─────────
const NCELL: usize = 8;
const THRESH: u8 = 3;
const MID: f64 = 2.5;
const NSAMP: usize = 7000;
const NTR: usize = 3500;
const NVA: usize = 5250;
const COVER: f64 = 0.90;
const R2_GATE: f64 = 0.40;
const SEEDS = [_]u64{ 0xF0235A11CE0FF1CE, 0xC1B10D20260706, 0xC2B10D20260707 };

const MAXK: usize = 24; // committed columns cap (K_MAIN=12 + headroom for trial/extra col)

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

// ── Grid statistics (transcribed from repr_expansion.zig) ──────────────────
fn phi(g: [NCELL]u8, mask: u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) p *= (@as(f64, @floatFromInt(g[i])) - MID);
    }
    return p;
}
fn gridSum(g: [NCELL]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}
fn signPattern(g: [NCELL]u8) u8 {
    var p: u8 = 0;
    for (0..NCELL) |i| {
        if (g[i] >= THRESH) p |= @as(u8, 1) << @intCast(i);
    }
    return p;
}
fn chi(S: u8, p: u8) f64 {
    const neg = @popCount(S & ~p);
    return if (neg & 1 == 0) 1.0 else -1.0;
}
fn countGE(g: [NCELL]u8) f64 {
    var c: usize = 0;
    for (g) |v| if (v >= THRESH) {
        c += 1;
    };
    return @floatFromInt(c);
}
fn countAtLeast(g: [NCELL]u8, k: u8) usize {
    var c: usize = 0;
    for (g) |v| if (v >= k) {
        c += 1;
    };
    return c;
}
fn cliffordTheta(g: [NCELL]u8, theta: f64) f64 {
    const v0: f64 = @floatFromInt(g[0]);
    const v1: f64 = @floatFromInt(g[1]);
    return @sin(theta * (v1 - v0));
}
fn inversionCount(g: [NCELL]u8) usize {
    var inv: usize = 0;
    for (0..NCELL) |i| for (i + 1..NCELL) |j| {
        if (g[i] > g[j]) inv += 1;
    };
    return inv;
}
const CmpSet = enum(u8) { all, low, high, cross, adj };
fn cmpAggregate(g: [NCELL]u8, set: CmpSet) usize {
    var a: usize = 0;
    switch (set) {
        .all => {
            for (0..NCELL) |i| for (i + 1..NCELL) |j| {
                if (g[i] > g[j]) a += 1;
            };
        },
        .low => {
            for (0..4) |i| for (i + 1..4) |j| {
                if (g[i] > g[j]) a += 1;
            };
        },
        .high => {
            for (4..NCELL) |i| for (i + 1..NCELL) |j| {
                if (g[i] > g[j]) a += 1;
            };
        },
        .cross => {
            for (0..4) |i| for (4..NCELL) |j| {
                if (g[i] > g[j]) a += 1;
            };
        },
        .adj => {
            for (0..NCELL - 1) |i| {
                if (g[i] > g[i + 1]) a += 1;
            }
        },
    }
    return a;
}
const StdLens = enum(u8) { ident, mod2, mod3, mod4, mod5, mod6 };
fn applyLens(raw: f64, lens: StdLens) f64 {
    return switch (lens) {
        .ident => raw,
        else => blk: {
            const m: i64 = switch (lens) {
                .mod2 => 2,
                .mod3 => 3,
                .mod4 => 4,
                .mod5 => 5,
                .mod6 => 6,
                else => unreachable,
            };
            const iv: i64 = @intFromFloat(@round(raw));
            break :blk @floatFromInt(@mod(iv, m));
        },
    };
}
// RUN family
fn maxRunGE(g: [NCELL]u8, k: u8) usize {
    var best: usize = 0;
    var cur: usize = 0;
    for (g) |v| {
        if (v >= k) {
            cur += 1;
            if (cur > best) best = cur;
        } else cur = 0;
    }
    return best;
}
fn firstDescentPos(g: [NCELL]u8) usize {
    for (0..NCELL - 1) |i| {
        if (g[i] > g[i + 1]) return i;
    }
    return NCELL;
}
fn numLocalMax(g: [NCELL]u8) usize {
    var c: usize = 0;
    for (1..NCELL - 1) |i| {
        if (g[i - 1] < g[i] and g[i] > g[i + 1]) c += 1;
    }
    return c;
}
// MIXR / RATIO joint statistics (pair 0 = sum,count3 -- the certified MIXMOD1 member)
fn mixrBaseA(g: [NCELL]u8) usize {
    return gridSum(g);
}
fn mixrBaseB(g: [NCELL]u8) usize {
    return countAtLeast(g, THRESH);
}

// ── Labels (targets) ─────────────────────────────────────────────────────
fn labelRun1(g: [NCELL]u8) f64 {
    return if (maxRunGE(g, 3) >= 3) 1.0 else 0.0;
}
fn labelRunVar2(g: [NCELL]u8) f64 {
    return if (maxRunGE(g, 2) >= 4) 1.0 else 0.0;
}
fn labelRunVar3(g: [NCELL]u8) f64 {
    return if (firstDescentPos(g) >= 4) 1.0 else 0.0;
}
fn labelRunVar4(g: [NCELL]u8) f64 {
    return if (numLocalMax(g) >= 2) 1.0 else 0.0;
}
fn labelC09(g: [NCELL]u8) f64 {
    return @floatFromInt(inversionCount(g) & 1);
}
fn labelRatio1(g: [NCELL]u8) f64 {
    const p = countAtLeast(g, 4) * countAtLeast(g, 1);
    return if (p % 3 == 0) 1.0 else 0.0;
}
fn labelMixmod1(g: [NCELL]u8) f64 {
    return if ((gridSum(g) % 3) == (countAtLeast(g, THRESH) % 3)) 1.0 else 0.0;
}
fn labelRemixA(g: [NCELL]u8) f64 {
    return if (countAtLeast(g, 2) >= 5) 1.0 else 0.0;
}
fn labelRemixB(g: [NCELL]u8) f64 {
    return if (gridSum(g) >= 21) 1.0 else 0.0;
}

// ── ML core (transcribed verbatim in spirit from repr_expansion.zig; generic
//    in `dim` already, so reused as-is for both greedy trials and finals) ──
fn fitLogit(X: []const []f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = sigmoid(z) - Y[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
}
fn accLogit(X: []const []f64, Y: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var c: usize = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}
fn fitLin(X: []const []f64, t: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..NTR) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        const e = z - t[s];
        for (0..dim) |j| w[j] -= lr * e * X[s][j];
        w[dim] -= lr * e;
    };
}
fn r2OutOfSample(X: []const []f64, t: []const f64, w: []const f64, dim: usize, lo: usize, hi: usize) f64 {
    var mu: f64 = 0;
    for (lo..hi) |s| mu += t[s];
    mu /= @floatFromInt(hi - lo);
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (lo..hi) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        ssr += (t[s] - z) * (t[s] - z);
        sst += (t[s] - mu) * (t[s] - mu);
    }
    return 1.0 - ssr / @max(1e-9, sst);
}

/// Standardize `raw` (mean/std over TRAIN rows only) into column `col` of X.
fn standardizeInto(X: [][]f64, col: usize, raw: []const f64) void {
    var mu: f64 = 0;
    for (0..NTR) |s| mu += raw[s];
    mu /= @floatFromInt(NTR);
    var sd: f64 = 0;
    for (0..NTR) |s| sd += (raw[s] - mu) * (raw[s] - mu);
    sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(NTR))));
    for (0..NSAMP) |s| X[s][col] = (raw[s] - mu) / sd;
}

// ── Candidate pool (the "existing count/order/algebraic basis", RUN excluded
//    by construction -- run stats never appear here) ────────────────────────
const Family = enum(u8) { mono, walsh, spectral, clifford, world, cmp, thresh, mixr, ratio };
const family_name = [_][]const u8{ "mono", "walsh", "spectral", "clifford", "world", "cmp", "thresh", "mixr", "ratio" };

const Pool = struct {
    vals: [][]f64, // [ncol][NSAMP], raw (unstandardized)
    fam: []Family,
    desc: [][]const u8,
    n: usize,
};

fn buildPool(alloc: std.mem.Allocator, grid: []const [NCELL]u8) !Pool {
    var vals = std.ArrayList([]f64).init(alloc);
    var fam = std.ArrayList(Family).init(alloc);
    var desc = std.ArrayList([]const u8).init(alloc);

    // mono: 8 singleton + 28 pair(=degree2) + 6 adjacent-triple + 5 adjacent-quad = 47
    var mono_masks = std.ArrayList(u8).init(alloc);
    for (0..NCELL) |i| try mono_masks.append(@as(u8, 1) << @intCast(i));
    for (0..NCELL) |i| for (i + 1..NCELL) |j| try mono_masks.append((@as(u8, 1) << @intCast(i)) | (@as(u8, 1) << @intCast(j)));
    for (0..NCELL - 2) |i| try mono_masks.append((@as(u8, 1) << @intCast(i)) | (@as(u8, 1) << @intCast(i + 1)) | (@as(u8, 1) << @intCast(i + 2)));
    for (0..NCELL - 3) |i| {
        var m: u8 = 0;
        for (0..4) |d| m |= @as(u8, 1) << @intCast(i + d);
        try mono_masks.append(m);
    }
    for (mono_masks.items) |mask| {
        const col = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| col[s] = phi(grid[s], mask);
        try vals.append(col);
        try fam.append(.mono);
        try desc.append(try std.fmt.allocPrint(alloc, "phi(0x{X:0>2})", .{mask}));
    }
    // walsh: 42 spread chi(S) values (S=1,7,13,...)
    {
        var sVal: u16 = 1;
        while (sVal < 256) : (sVal += 6) {
            const S: u8 = @intCast(sVal);
            const col = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| col[s] = chi(S, signPattern(grid[s]));
            try vals.append(col);
            try fam.append(.walsh);
            try desc.append(try std.fmt.allocPrint(alloc, "chi(0x{X:0>2})", .{S}));
        }
    }
    // spectral: 20 freqs over [0,pi]
    {
        const NF = 20;
        var i: usize = 1;
        while (i <= NF) : (i += 1) {
            const om = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, NF);
            const col = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| col[s] = @cos(om * countGE(grid[s]));
            try vals.append(col);
            try fam.append(.spectral);
            try desc.append(try std.fmt.allocPrint(alloc, "cos(w={d:.3}*c3)", .{om}));
        }
    }
    // clifford: 4 thetas
    {
        const thetas = [_]f64{ 0.1, 0.3, 0.4, 0.6 };
        for (thetas) |th| {
            const col = try alloc.alloc(f64, NSAMP);
            for (0..NSAMP) |s| col[s] = cliffordTheta(grid[s], th);
            try vals.append(col);
            try fam.append(.clifford);
            try desc.append(try std.fmt.allocPrint(alloc, "clifford(th={d:.2})", .{th}));
        }
    }
    // world: sum_mod / sign_mod, k=2..9 (8 each = 16)
    {
        var k: usize = 2;
        while (k <= 9) : (k += 1) {
            {
                const col = try alloc.alloc(f64, NSAMP);
                for (0..NSAMP) |s| col[s] = if (gridSum(grid[s]) % k == 0) @as(f64, 1) else 0;
                try vals.append(col);
                try fam.append(.world);
                try desc.append(try std.fmt.allocPrint(alloc, "sum%{d}==0", .{k}));
            }
            {
                const col = try alloc.alloc(f64, NSAMP);
                for (0..NSAMP) |s| col[s] = if (@as(usize, signPattern(grid[s])) % k == 0) @as(f64, 1) else 0;
                try vals.append(col);
                try fam.append(.world);
                try desc.append(try std.fmt.allocPrint(alloc, "sign%{d}==0", .{k}));
            }
        }
    }
    // cmp: 5 sets x 6 lenses = 30
    {
        const sets = [_]CmpSet{ .all, .low, .high, .cross, .adj };
        const set_name = [_][]const u8{ "all28", "low6", "high6", "cross16", "adj7" };
        const lenses = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
        for (sets, 0..) |set, si| {
            for (lenses) |lens| {
                const col = try alloc.alloc(f64, NSAMP);
                for (0..NSAMP) |s| col[s] = applyLens(@floatFromInt(cmpAggregate(grid[s], set)), lens);
                try vals.append(col);
                try fam.append(.cmp);
                try desc.append(try std.fmt.allocPrint(alloc, "cmp({s},{s})", .{ set_name[si], @tagName(lens) }));
            }
        }
    }
    // thresh: k in {1,2,4,5} x 6 lenses = 24
    {
        const ks = [_]u8{ 1, 2, 4, 5 };
        const lenses = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
        for (ks) |k| {
            for (lenses) |lens| {
                const col = try alloc.alloc(f64, NSAMP);
                for (0..NSAMP) |s| col[s] = applyLens(@floatFromInt(countAtLeast(grid[s], k)), lens);
                try vals.append(col);
                try fam.append(.thresh);
                try desc.append(try std.fmt.allocPrint(alloc, "thresh(k={d},{s})", .{ k, @tagName(lens) }));
            }
        }
    }
    // mixr: pair(sum,count3) x radii{2x2,3x3} x 6 lenses = 12; plus pair(sum,inv)/(count3,inv) x same = 24 -> 36
    {
        const lenses = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
        const radii = [_][2]u8{ .{ 2, 2 }, .{ 3, 3 } };
        const PairKind = enum { sum_count3, sum_inv, count3_inv };
        const kinds = [_]PairKind{ .sum_count3, .sum_inv, .count3_inv };
        for (kinds) |kind| {
            for (radii) |rad| {
                const ra = rad[0];
                const rb = rad[1];
                for (lenses) |lens| {
                    const col = try alloc.alloc(f64, NSAMP);
                    for (0..NSAMP) |s| {
                        const g = grid[s];
                        const a_raw: usize = switch (kind) {
                            .sum_count3 => gridSum(g),
                            .sum_inv => gridSum(g),
                            .count3_inv => countAtLeast(g, THRESH),
                        };
                        const b_raw: usize = switch (kind) {
                            .sum_count3 => countAtLeast(g, THRESH),
                            .sum_inv => inversionCount(g),
                            .count3_inv => inversionCount(g),
                        };
                        const idx: f64 = @floatFromInt((a_raw % ra) * @as(usize, rb) + (b_raw % rb));
                        col[s] = applyLens(idx, lens);
                    }
                    try vals.append(col);
                    try fam.append(.mixr);
                    try desc.append(try std.fmt.allocPrint(alloc, "mixr({s},{d}x{d},{s})", .{ @tagName(kind), ra, rb, @tagName(lens) }));
                }
            }
        }
    }
    // ratio: 3 pairs x (diff:ident + prod:6 lenses) = 3*7 = 21
    {
        const RPair = struct { hi: u8, lo: u8 };
        const pairs = [_]RPair{ .{ .hi = 4, .lo = 1 }, .{ .hi = 5, .lo = 0 }, .{ .hi = 3, .lo = 2 } };
        const lenses = [_]StdLens{ .ident, .mod2, .mod3, .mod4, .mod5, .mod6 };
        for (pairs) |p| {
            {
                const col = try alloc.alloc(f64, NSAMP);
                for (0..NSAMP) |s| {
                    const hi: f64 = @floatFromInt(countAtLeast(grid[s], p.hi));
                    const lo: f64 = @floatFromInt(countAtLeast(grid[s], p.lo));
                    col[s] = (hi - lo) / (hi + lo + 1.0);
                }
                try vals.append(col);
                try fam.append(.ratio);
                try desc.append(try std.fmt.allocPrint(alloc, "ratio(diff,hi{d}lo{d})", .{ p.hi, p.lo }));
            }
            for (lenses) |lens| {
                const col = try alloc.alloc(f64, NSAMP);
                for (0..NSAMP) |s| {
                    const raw: f64 = @floatFromInt(countAtLeast(grid[s], p.hi) * countAtLeast(grid[s], p.lo));
                    col[s] = applyLens(raw, lens);
                }
                try vals.append(col);
                try fam.append(.ratio);
                try desc.append(try std.fmt.allocPrint(alloc, "ratio(prod,hi{d}lo{d},{s})", .{ p.hi, p.lo, @tagName(lens) }));
            }
        }
    }

    const n = vals.items.len;
    return .{ .vals = try vals.toOwnedSlice(), .fam = try fam.toOwnedSlice(), .desc = try desc.toOwnedSlice(), .n = n };
}

// ── Greedy forward selection ────────────────────────────────────────────
const RoundRec = struct { col: usize, fam: Family, val_metric: f64, tst_metric: f64 };

/// Greedy classify: at each round, pick (from pool, excluding `excl` family and
/// already-chosen) the column that maximizes held-out VALIDATION accuracy
/// (NTR..NVA) of a logistic fit using [chosen so far + this column]; commit it;
/// record TEST accuracy (NVA..NSAMP) for that round. Screen with reduced
/// epochs for speed; the caller may do a heavier final refit on the result.
fn famBit(f: Family) u16 {
    return @as(u16, 1) << @as(u4, @intCast(@intFromEnum(f)));
}

fn greedyClassify(
    pool: Pool,
    excl_mask: u16,
    Y: []const f64,
    K: usize,
    X: [][]f64,
    w: []f64,
    screen_epochs: usize,
    screen_lr: f64,
    chosen: []usize,
    rounds: []RoundRec,
) usize {
    var used = std.StaticBitSet(4096).initEmpty();
    var dim: usize = 0;
    while (dim < K) : (dim += 1) {
        var best_val: f64 = -1;
        var best_idx: ?usize = null;
        for (0..pool.n) |idx| {
            if (used.isSet(idx)) continue;
            if (excl_mask & famBit(pool.fam[idx]) != 0) continue;
            standardizeInto(X, dim, pool.vals[idx]);
            fitLogit(X, Y, dim + 1, screen_epochs, screen_lr, w);
            const va = accLogit(X, Y, w, dim + 1, NTR, NVA);
            if (va > best_val) {
                best_val = va;
                best_idx = idx;
            }
        }
        const bi = best_idx orelse break;
        standardizeInto(X, dim, pool.vals[bi]);
        fitLogit(X, Y, dim + 1, screen_epochs, screen_lr, w);
        const tst = accLogit(X, Y, w, dim + 1, NVA, NSAMP);
        chosen[dim] = bi;
        rounds[dim] = .{ .col = bi, .fam = pool.fam[bi], .val_metric = best_val, .tst_metric = tst };
        used.set(bi);
        // early stop: 2 consecutive rounds with < 0.001 val improvement (checked from round 3 on)
        if (dim >= 3) {
            const imp = rounds[dim].val_metric - rounds[dim - 1].val_metric;
            const imp_prev = rounds[dim - 1].val_metric - rounds[dim - 2].val_metric;
            if (imp < 0.001 and imp_prev < 0.001) {
                dim += 1;
                break;
            }
        }
    }
    return dim;
}

/// Same as greedyClassify but the objective is R^2 of a continuous target
/// (used for the "dedicated" reconstruction attack on the raw run statistic).
fn greedyRegress(
    pool: Pool,
    excl_mask: u16,
    t: []const f64,
    K: usize,
    X: [][]f64,
    w: []f64,
    screen_epochs: usize,
    screen_lr: f64,
    chosen: []usize,
    rounds: []RoundRec,
) usize {
    var used = std.StaticBitSet(4096).initEmpty();
    var dim: usize = 0;
    while (dim < K) : (dim += 1) {
        var best_val: f64 = -1e18;
        var best_idx: ?usize = null;
        for (0..pool.n) |idx| {
            if (used.isSet(idx)) continue;
            if (excl_mask & famBit(pool.fam[idx]) != 0) continue;
            standardizeInto(X, dim, pool.vals[idx]);
            fitLin(X, t, dim + 1, screen_epochs, screen_lr, w);
            const va = r2OutOfSample(X, t, w, dim + 1, NTR, NVA);
            if (va > best_val) {
                best_val = va;
                best_idx = idx;
            }
        }
        const bi = best_idx orelse break;
        standardizeInto(X, dim, pool.vals[bi]);
        fitLin(X, t, dim + 1, screen_epochs, screen_lr, w);
        const tst = r2OutOfSample(X, t, w, dim + 1, NVA, NSAMP);
        chosen[dim] = bi;
        rounds[dim] = .{ .col = bi, .fam = pool.fam[bi], .val_metric = best_val, .tst_metric = tst };
        used.set(bi);
        if (dim >= 3) {
            const imp = rounds[dim].val_metric - rounds[dim - 1].val_metric;
            const imp_prev = rounds[dim - 1].val_metric - rounds[dim - 2].val_metric;
            if (imp < 0.002 and imp_prev < 0.002) {
                dim += 1;
                break;
            }
        }
    }
    return dim;
}

// ── main ─────────────────────────────────────────────────────────────────
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    var diag = false;
    {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();
        _ = args.skip();
        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "--diag")) diag = true;
        }
    }

    const K_MAIN: usize = if (diag) 6 else 12;
    const K_SEC: usize = if (diag) 5 else 8;
    const SCREEN_EPOCHS: usize = if (diag) 25 else 40;
    const SCREEN_LR: f64 = 0.08;
    const FINAL_EPOCHS: usize = 150;
    const FINAL_LR: f64 = 0.05;
    const REG_SCREEN_EPOCHS: usize = if (diag) 60 else 100;
    const REG_SCREEN_LR: f64 = 0.02;
    const REG_FINAL_EPOCHS: usize = 400;
    const REG_FINAL_LR: f64 = 0.01;
    const seeds_used: []const u64 = if (diag) SEEDS[0..1] else SEEDS[0..];

    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/run1_gate_audit_2026_07_11.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("section,seed,target,round_or_gt,family_or_verdict,detail,metric_val,metric_tst,extra1,extra2\n", .{});

    const t_start = std.time.milliTimestamp();
    const X = try alloc.alloc([]f64, NSAMP);
    for (0..NSAMP) |s| X[s] = try alloc.alloc(f64, MAXK);
    var w: [MAXK + 1]f64 = undefined;
    var chosen: [MAXK]usize = undefined;
    var rounds: [MAXK]RoundRec = undefined;

    try out.print("════ PART 1+2: RUN1 reproduce + greedy multi-feature reconstruction ({d} seed(s)) ════\n", .{seeds_used.len});

    for (seeds_used) |seed| {
        var prng = std.Random.DefaultPrng.init(seed);
        const rand = prng.random();
        const grid = try alloc.alloc([NCELL]u8, NSAMP);
        for (0..NSAMP) |s| {
            for (0..NCELL) |i| grid[s][i] = rand.intRangeAtMost(u8, 0, 5);
        }
        const pool = try buildPool(alloc, grid);
        try out.print("\n[seed 0x{X:0>16}] pool built: {d} columns, {d}ms\n", .{ seed, pool.n, std.time.milliTimestamp() - t_start });

        const Yrun1 = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Yrun1[s] = labelRun1(grid[s]);
        const raw_run1 = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| raw_run1[s] = @floatFromInt(maxRunGE(grid[s], 3));
        var pos: usize = 0;
        for (Yrun1) |y| {
            if (y > 0.5) pos += 1;
        }
        try out.print("  RUN1 base_rate={d:.3}\n", .{@as(f64, @floatFromInt(pos)) / NSAMP});
        try cw.print("base_rate,0x{X:0>16},RUN1,-,-,base_rate,{d:.4},,,\n", .{ seed, @as(f64, @floatFromInt(pos)) / NSAMP });

        // (2a) incidental library: greedy-classify RUN1 label directly, no run family present.
        const dimA = greedyClassify(pool, 0, Yrun1, K_MAIN, X, w[0..], SCREEN_EPOCHS, SCREEN_LR, chosen[0..], rounds[0..]);
        try out.print("  (2a) incidental-library greedy classify (K<= {d}, stopped at {d}):\n", .{ K_MAIN, dimA });
        for (0..dimA) |k| {
            const r = rounds[k];
            try out.print("    round {d:>2}: +{s:<9} {s:<24} val={d:.4} tst={d:.4}\n", .{ k + 1, family_name[@intFromEnum(r.fam)], pool.desc[r.col], r.val_metric, r.tst_metric });
            try cw.print("greedy_trace,0x{X:0>16},RUN1,{d},{s},\"{s}\",{d:.4},{d:.4},class,incidental\n", .{ seed, k + 1, family_name[@intFromEnum(r.fam)], pool.desc[r.col], r.val_metric, r.tst_metric });
        }
        // final heavy refit on the chosen incidental library -> cov_before
        for (0..dimA) |k| standardizeInto(X, k, pool.vals[chosen[k]]);
        fitLogit(X, Yrun1, dimA, FINAL_EPOCHS, FINAL_LR, w[0..]);
        const cov_before = accLogit(X, Yrun1, w[0..], dimA, NVA, NSAMP);
        // add the exact run candidate as one more column -> cov_after
        standardizeInto(X, dimA, raw_run1);
        fitLogit(X, Yrun1, dimA + 1, FINAL_EPOCHS, FINAL_LR, w[0..]);
        const cov_after = accLogit(X, Yrun1, w[0..], dimA + 1, NVA, NSAMP);
        // R^2 of raw_run1 vs the SAME incidental library (faithful reproduction of certifyLocal's r2)
        for (0..dimA) |k| standardizeInto(X, k, pool.vals[chosen[k]]);
        fitLin(X, raw_run1, dimA, REG_FINAL_EPOCHS, REG_FINAL_LR, w[0..]);
        const r2_incidental = r2OutOfSample(X, raw_run1, w[0..], dimA, NVA, NSAMP);
        try out.print("  REPRODUCE: cov_before={d:.4} cov_after={d:.4} R2(incidental)={d:.4} (gate: reject if R2>={d:.2})\n", .{ cov_before, cov_after, r2_incidental, R2_GATE });
        try cw.print("gate_repro,0x{X:0>16},RUN1,-,-,cov_before,{d:.4},,,\n", .{ seed, cov_before });
        try cw.print("gate_repro,0x{X:0>16},RUN1,-,-,cov_after,{d:.4},,,\n", .{ seed, cov_after });
        try cw.print("gate_repro,0x{X:0>16},RUN1,-,-,r2_incidental,{d:.4},,gate_verdict,{s}\n", .{ seed, r2_incidental, if (r2_incidental >= R2_GATE) "reject" else "admit" });

        // (2b) dedicated library: greedy-regress directly on raw_run1 (the most
        // generous possible linear-reconstruction attempt -- upper bound on R^2).
        const dimB = greedyRegress(pool, 0, raw_run1, K_MAIN, X, w[0..], REG_SCREEN_EPOCHS, REG_SCREEN_LR, chosen[0..], rounds[0..]);
        try out.print("  (2b) dedicated-library greedy regress (K<= {d}, stopped at {d}):\n", .{ K_MAIN, dimB });
        for (0..dimB) |k| {
            const r = rounds[k];
            try out.print("    round {d:>2}: +{s:<9} {s:<24} val_R2={d:.4} tst_R2={d:.4}\n", .{ k + 1, family_name[@intFromEnum(r.fam)], pool.desc[r.col], r.val_metric, r.tst_metric });
            try cw.print("greedy_trace,0x{X:0>16},RUN1,{d},{s},\"{s}\",{d:.4},{d:.4},regress,dedicated\n", .{ seed, k + 1, family_name[@intFromEnum(r.fam)], pool.desc[r.col], r.val_metric, r.tst_metric });
        }
        for (0..dimB) |k| standardizeInto(X, k, pool.vals[chosen[k]]);
        fitLin(X, raw_run1, dimB, REG_FINAL_EPOCHS, REG_FINAL_LR, w[0..]);
        const r2_dedicated = r2OutOfSample(X, raw_run1, w[0..], dimB, NVA, NSAMP);
        // does the dedicated (R2-optimized) library also classify the LABEL well?
        fitLogit(X, Yrun1, dimB, FINAL_EPOCHS, FINAL_LR, w[0..]);
        const cov_dedicated = accLogit(X, Yrun1, w[0..], dimB, NVA, NSAMP);
        try out.print("  DEDICATED CEILING: R2(dedicated)={d:.4}  cov_using_dedicated_lib={d:.4}\n", .{ r2_dedicated, cov_dedicated });
        try cw.print("gate_repro,0x{X:0>16},RUN1,-,-,r2_dedicated,{d:.4},,cov_dedicated,{d:.4}\n", .{ seed, r2_dedicated, cov_dedicated });

        try out.print("[seed 0x{X:0>16} done at {d}ms]\n", .{ seed, std.time.milliTimestamp() - t_start });
    }

    try out.print("\n════ PART 3: ROC / threshold sweep (1 seed, production seed) ════\n", .{});
    const seed0 = SEEDS[0];
    var prng0 = std.Random.DefaultPrng.init(seed0);
    const rand0 = prng0.random();
    const grid0 = try alloc.alloc([NCELL]u8, NSAMP);
    for (0..NSAMP) |s| {
        for (0..NCELL) |i| grid0[s][i] = rand0.intRangeAtMost(u8, 0, 5);
    }
    const pool0 = try buildPool(alloc, grid0);

    const RocTarget = struct {
        name: []const u8,
        label_fn: *const fn ([NCELL]u8) f64,
        raw_fn: *const fn ([NCELL]u8) f64,
        excl: u16, // bitmask of Family (famBit) -- must cover every family that has
        // DIRECT access to the raw ingredient statistic(s) the target's own
        // defining formula operates on, or the "reconstruction" test cheats.
        gt_category: []const u8, // "novel" or "remix" (design-time ground truth, verified below)
    };
    const cmpAllRaw = struct {
        fn f(g: [NCELL]u8) f64 {
            return @floatFromInt(cmpAggregate(g, .all) % 2);
        }
    }.f;
    const ratioProdRaw = struct {
        fn f(g: [NCELL]u8) f64 {
            const p = countAtLeast(g, 4) * countAtLeast(g, 1);
            return @floatFromInt(p % 3);
        }
    }.f;
    const mixmodRaw = struct {
        fn f(g: [NCELL]u8) f64 {
            const idx = (mixrBaseA(g) % 3) * 3 + (mixrBaseB(g) % 3);
            return @floatFromInt(idx % 4);
        }
    }.f;
    const runVar2Raw = struct {
        fn f(g: [NCELL]u8) f64 {
            return @floatFromInt(maxRunGE(g, 2));
        }
    }.f;
    const runVar3Raw = struct {
        fn f(g: [NCELL]u8) f64 {
            return @floatFromInt(firstDescentPos(g));
        }
    }.f;
    const runVar4Raw = struct {
        fn f(g: [NCELL]u8) f64 {
            return @floatFromInt(numLocalMax(g));
        }
    }.f;
    const runVar1Raw = struct {
        fn f(g: [NCELL]u8) f64 {
            return @floatFromInt(maxRunGE(g, 3));
        }
    }.f;
    const threshK2Raw = struct {
        fn f(g: [NCELL]u8) f64 {
            return @floatFromInt(countAtLeast(g, 2));
        }
    }.f;
    const gridSumRaw = struct {
        fn f(g: [NCELL]u8) f64 {
            return @floatFromInt(gridSum(g));
        }
    }.f;

    // NOTE on exclusion masks: `mixr`'s (sum,inv)/(count3,inv) pairs give it
    // DIRECT raw access to inversionCount, so it must be excluded alongside
    // `cmp` for C09 (verified empirically: cmp-only exclusion left C09 at
    // cov_before=1.000 via mixr's back-door -- exactly the "mixr re-derives
    // C09 independently of cmp" overlap repr_expansion.md itself documents).
    // `thresh` (k in {1,2,4,5}) directly exposes countAtLeast(g,4) and
    // countAtLeast(g,1) with a mod3 lens, i.e. RATIO1's own two raw
    // ingredients, so it must be excluded alongside `ratio` for the same
    // reason (verified: ratio-only exclusion left RATIO1 at cov_before=0.997).
    const targets = [_]RocTarget{
        .{ .name = "RUN1(again,1seed)", .label_fn = labelRun1, .raw_fn = runVar1Raw, .excl = 0, .gt_category = "novel" },
        .{ .name = "RUN-var2(maxRunGE2>=4)", .label_fn = labelRunVar2, .raw_fn = runVar2Raw, .excl = 0, .gt_category = "novel" },
        .{ .name = "RUN-var3(firstDescent>=4)", .label_fn = labelRunVar3, .raw_fn = runVar3Raw, .excl = 0, .gt_category = "novel" },
        .{ .name = "RUN-var4(numLocalMax>=2)", .label_fn = labelRunVar4, .raw_fn = runVar4Raw, .excl = 0, .gt_category = "novel" },
        .{ .name = "C09(inv parity)", .label_fn = labelC09, .raw_fn = cmpAllRaw, .excl = famBit(.cmp) | famBit(.mixr), .gt_category = "novel" },
        .{ .name = "RATIO1", .label_fn = labelRatio1, .raw_fn = ratioProdRaw, .excl = famBit(.ratio) | famBit(.thresh), .gt_category = "novel" },
        .{ .name = "MIXMOD1", .label_fn = labelMixmod1, .raw_fn = mixmodRaw, .excl = famBit(.mixr), .gt_category = "novel" },
        .{ .name = "REMIX-A(thresh k=2 dup)", .label_fn = labelRemixA, .raw_fn = threshK2Raw, .excl = famBit(.thresh), .gt_category = "remix" },
        .{ .name = "REMIX-B(gridSum dup)", .label_fn = labelRemixB, .raw_fn = gridSumRaw, .excl = famBit(.mono), .gt_category = "remix" },
    };

    const RocRow = struct {
        name: []const u8,
        gt_category: []const u8,
        cov_before: f64,
        cov_after: f64,
        r2: f64,
        gt_reconstructible: bool, // cov_before (generous, K_SEC rounds) >= COVER
    };
    var roc_rows = std.ArrayList(RocRow).init(alloc);

    for (targets) |tgt| {
        const Y = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| Y[s] = tgt.label_fn(grid0[s]);
        const raw = try alloc.alloc(f64, NSAMP);
        for (0..NSAMP) |s| raw[s] = tgt.raw_fn(grid0[s]);

        var excl_desc: [64]u8 = undefined;
        var excl_len: usize = 0;
        if (tgt.excl == 0) {
            @memcpy(excl_desc[0..4], "none");
            excl_len = 4;
        } else {
            for (family_name, 0..) |fname, fi| {
                if (tgt.excl & famBit(@enumFromInt(fi)) != 0) {
                    if (excl_len > 0) {
                        excl_desc[excl_len] = '+';
                        excl_len += 1;
                    }
                    @memcpy(excl_desc[excl_len .. excl_len + fname.len], fname);
                    excl_len += fname.len;
                }
            }
        }
        const excl_str = excl_desc[0..excl_len];

        const dim = greedyClassify(pool0, tgt.excl, Y, K_SEC, X, w[0..], SCREEN_EPOCHS, SCREEN_LR, chosen[0..], rounds[0..]);
        for (0..dim) |k| standardizeInto(X, k, pool0.vals[chosen[k]]);
        fitLogit(X, Y, dim, FINAL_EPOCHS, FINAL_LR, w[0..]);
        const cov_before = accLogit(X, Y, w[0..], dim, NVA, NSAMP);
        standardizeInto(X, dim, raw);
        fitLogit(X, Y, dim + 1, FINAL_EPOCHS, FINAL_LR, w[0..]);
        const cov_after = accLogit(X, Y, w[0..], dim + 1, NVA, NSAMP);
        for (0..dim) |k| standardizeInto(X, k, pool0.vals[chosen[k]]);
        fitLin(X, raw, dim, REG_FINAL_EPOCHS, REG_FINAL_LR, w[0..]);
        const r2 = r2OutOfSample(X, raw, w[0..], dim, NVA, NSAMP);

        const gt_recon = cov_before >= COVER;
        try out.print("  {s:<26} excl={s:<15} K={d:>2} cov_before={d:.4} cov_after={d:.4} R2={d:.4} gt={s}\n", .{ tgt.name, excl_str, dim, cov_before, cov_after, r2, if (gt_recon) "RECONSTRUCTIBLE" else "not-reconstructible" });
        try cw.print("roc,0x{X:0>16},\"{s}\",{s},{s},excl={s};K={d},{d:.4},{d:.4},{s},{s}\n", .{ seed0, tgt.name, tgt.gt_category, if (gt_recon) "gt_remix" else "gt_novel", excl_str, dim, cov_before, cov_after, if (r2 >= R2_GATE) "gate_reject" else "gate_admit", "-" });
        try cw.print("roc_r2,0x{X:0>16},\"{s}\",-,-,r2,{d:.4},,,\n", .{ seed0, tgt.name, r2 });

        try roc_rows.append(.{ .name = tgt.name, .gt_category = tgt.gt_category, .cov_before = cov_before, .cov_after = cov_after, .r2 = r2, .gt_reconstructible = gt_recon });
    }

    // ── PART 4: threshold sweep / confusion table over the ROC rows ────────
    try out.print("\n════ PART 4: R^2 threshold sweep (confusion vs greedy ground truth) ════\n", .{});
    const thresholds = [_]f64{ 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90 };
    for (thresholds) |thr| {
        var tp: usize = 0; // predicted remix (r2>=thr) AND gt remix (cov_before>=COVER)
        var fp: usize = 0; // predicted remix but gt novel (FALSE REJECTION if this were a real candidate)
        var tn: usize = 0; // predicted novel AND gt novel
        var fn_: usize = 0; // predicted novel but gt remix (missed redundancy)
        for (roc_rows.items) |r| {
            const pred_remix = r.r2 >= thr;
            if (pred_remix and r.gt_reconstructible) tp += 1;
            if (pred_remix and !r.gt_reconstructible) fp += 1;
            if (!pred_remix and !r.gt_reconstructible) tn += 1;
            if (!pred_remix and r.gt_reconstructible) fn_ += 1;
        }
        try out.print("  thr={d:.2}: TP={d} FP(false-reject)={d} TN={d} FN(missed-remix)={d}\n", .{ thr, tp, fp, tn, fn_ });
        try cw.print("threshold_scan,-,-,-,-,thr={d:.2},{d},{d},{d},{d}\n", .{ thr, tp, fp, tn, fn_ });
    }
    // Also report RUN1's own position explicitly.
    try out.print("\nRUN1 in the sweep: see roc row 'RUN1(again,1seed)' above for its R2/cov_before/gt.\n", .{});

    try out.print("\nDone at {d}ms. CSV: {s}\n", .{ std.time.milliTimestamp() - t_start, csv_path });
}
