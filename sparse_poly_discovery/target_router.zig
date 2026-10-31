//! E2 (Round 2026-07-11) — Learned aim / target router.
//!
//! Context: round b (tier8_aimed_proposer.md) moved the battery-C XOR wall
//! 3/33 -> 8/33 with a FIXED lens (mod2/GF2 over the near-miss mask). Round c
//! (tier8_evidence_lenses.md) proved the wall was an estimator artifact and
//! introduced several exact lenses (L0..LG), always HANDED to the target by
//! the experimenter, never chosen by the machine. This experiment asks: can
//! a router PREDICT, from a target's own cheap failure signal (which weak
//! evidence probes fire, spectral power-vs-accuracy gap, base-rate skew,
//! etc. -- all computable WITHOUT knowing which family solves the target),
//! which of three qualitatively distinct "aim" mechanisms to commit to,
//! single-shot, on a held-out target it has never seen labeled?
//!
//! Three mechanisms (families), each a standalone certifier over the grid:
//!   BASE         -- the ladder's own cheap value/threshold basis (monomial
//!                   sign up to degree 4, Walsh tb-parity up to weight 8,
//!                   single pairwise comparisons, world sum/count mod-k,
//!                   power-argmax spectral pick on count3, and simple
//!                   AND/OR composition of the above). No special aim.
//!   GF2_JOINT    -- the round-c LG lens: a single 45-column GF(2) dictionary
//!                   (28 pairwise comparison bits c_ij=[g_i>g_j], 8 mod-2
//!                   bits, 8 threshold-@3 bits, intercept) solved by exact
//!                   Gaussian elimination. This is ONE atomic move that
//!                   subsumes both the battery-C XOR wall (lives entirely in
//!                   the 8 mod-2 bits) and the order-statistic wall (C09/B11,
//!                   lives entirely in the 28 comparison bits) -- round c's
//!                   own finding that these were "secretly one family".
//!   SPECTRAL_ACC -- the round-c MENUACC fix: accuracy-argmax (not
//!                   power-argmax) selection over a 200-point frequency grid,
//!                   generalized across 6 candidate scalar statistics
//!                   (sum(g), count(cells>=t) for t=1..5), needed whenever
//!                   the ladder's own power-pick lands on the wrong harmonic
//!                   (D08-class) or the true statistic differs from count3.
//!
//! Reused read-only (no existing file modified): open_invention_tier8_battery_c.zig
//! (BATTERY_C + labelTarget, imports open_invention_e2.zig internally),
//! tier8_battery_d.zig (BATTERY_D + labelTarget), open_invention_rq1.zig
//! (generateBatteryB + labelBattery + NSAMP/NTR/NVA/COVER/GRID_SEED). Extra
//! parameterized targets in the SAME three families are synthesized fresh in
//! this file (varying XOR mask weight, comparison-subset size, statistic x
//! modulus) to get enough labeled targets for a train/val/test split and a
//! sample-complexity curve -- the algorithms (GF2 elimination, mod2/tb
//! parity, power-vs-accuracy spectral gap) were read from
//! tier8_aimed_proposer.zig / tier8_lenses.zig for reference and
//! reimplemented fresh here (those files expose no public API besides
//! `main`).
//!
//! Discipline: rows [0,NTR) are the search/fit split, [NTR,NVA) is the
//! selection/validation split, [NVA,NSAMP) is the certify/test split --
//! identical convention to tier8_lenses.zig. TARGETS (not rows) are split
//! train/val/test; the router is fit on TRAIN target descriptors+labels
//! only, model choice (k) is picked on VAL, and the headline 3-arm
//! comparison is scored ONCE on TEST.
//!
//! Reproduce:
//!   zig build-exe target_router.zig -O ReleaseFast   # zig 0.14.1
//!   ./target_router                                   # single-threaded, ~seconds
//!   # CSV -> results/target_router_2026_07_11.csv

const std = @import("std");
const bc = @import("open_invention_tier8_battery_c.zig");
const bd = @import("tier8_battery_d.zig");
const rq1 = @import("open_invention_rq1.zig");

// ---------------------------------------------------------------------------
// Shared constants (reused from rq1)
// ---------------------------------------------------------------------------
const NCELL: usize = 8;
const NSAMP: usize = rq1.NSAMP; // 7000
const NTR: usize = rq1.NTR; // 3500  (fit/search split start..NTR)
const NVA: usize = rq1.NVA; // 5250  (val split NTR..NVA)
const COVER: f64 = rq1.COVER; // 0.90
const NPAIR: usize = 28;

var PAIR_I: [NPAIR]u8 = undefined;
var PAIR_J: [NPAIR]u8 = undefined;

fn initPairs() void {
    var idx: usize = 0;
    for (0..NCELL) |i| {
        for (i + 1..NCELL) |j| {
            PAIR_I[idx] = @intCast(i);
            PAIR_J[idx] = @intCast(j);
            idx += 1;
        }
    }
    std.debug.assert(idx == NPAIR);
}

fn gridSum(g: [NCELL]u8) usize {
    var s: usize = 0;
    for (g) |v| s += v;
    return s;
}

fn countGE(g: [NCELL]u8, t: u8) usize {
    var c: usize = 0;
    for (g) |v| {
        if (v >= t) c += 1;
    }
    return c;
}

fn cmpBit(g: [NCELL]u8, p: usize) u1 {
    return if (g[PAIR_I[p]] > g[PAIR_J[p]]) 1 else 0;
}

fn lbBit(v: u8) u1 {
    return @intCast(v & 1);
}
fn tbBit(v: u8) u1 {
    return if (v >= 3) 1 else 0;
}

// ---------------------------------------------------------------------------
// Candidate mask tables for the BASE family (monomial deg<=4, walsh weight<=8)
// ---------------------------------------------------------------------------
var MONO_MASKS: [162]u8 = undefined;
var N_MONO: usize = 0;
var WALSH_MASKS: [255]u8 = undefined;
var N_WALSH: usize = 0;

fn popcount8(x: u8) usize {
    return @popCount(x);
}

fn buildMaskTables() void {
    N_MONO = 0;
    N_WALSH = 0;
    var m: u16 = 1;
    while (m <= 255) : (m += 1) {
        const mask: u8 = @intCast(m);
        const w = popcount8(mask);
        if (w >= 1 and w <= 4) {
            MONO_MASKS[N_MONO] = mask;
            N_MONO += 1;
        }
        WALSH_MASKS[N_WALSH] = mask;
        N_WALSH += 1;
    }
    std.debug.assert(N_MONO == 162);
    std.debug.assert(N_WALSH == 255);
}

fn monomialSign(mask: u8, g: [NCELL]u8) f64 {
    var p: f64 = 1.0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0) {
            p *= (@as(f64, @floatFromInt(g[i])) - 2.5);
        }
    }
    return if (p > 0) 1.0 else 0.0;
}

fn walshParity(mask: u8, g: [NCELL]u8) f64 {
    var acc: u1 = 0;
    for (0..NCELL) |i| {
        if (mask & (@as(u8, 1) << @intCast(i)) != 0 and g[i] >= 3) acc ^= 1;
    }
    return @floatFromInt(acc);
}

// ---------------------------------------------------------------------------
// Rows-range binary-feature scoring: signed agreement (round-c formalism)
// and best-of-two-polarities accuracy on a row range.
// ---------------------------------------------------------------------------
fn signedAgreement(featVal01: f64, y: f64) f64 {
    // feature and y both in {0,1}; agreement in {-1,+1}
    const fb: f64 = if (featVal01 > 0.5) 1.0 else -1.0;
    const yb: f64 = if (y > 0.5) 1.0 else -1.0;
    return fb * yb;
}

fn binAccuracy(matchCount: usize, n: usize) f64 {
    const mc: f64 = @floatFromInt(matchCount);
    const nf: f64 = @floatFromInt(n);
    const a = mc / nf;
    return @max(a, 1.0 - a);
}

// ---------------------------------------------------------------------------
// Discrete-domain bucket threshold search (used for spectral + scalar-thresh
// families: domain is small (<=41 distinct values), so we bucketize once in
// O(NSAMP) and then sweep O(domain) thresholds per candidate frequency
// instead of sorting O(NSAMP) rows per candidate.
// ---------------------------------------------------------------------------
const MAXDOM = 64;

const BestSplit = struct {
    acc: f64,
    predict1: [MAXDOM]bool,
    ndom: usize,
};

fn bestSplitOneDir(pos: []const usize, tot: []const usize, score: []const f64, ndom: usize) BestSplit {
    var idx: [MAXDOM]usize = undefined;
    for (0..ndom) |i| idx[i] = i;
    const Ctx = struct {
        s: []const f64,
        fn lt(self: @This(), a: usize, b: usize) bool {
            return self.s[a] < self.s[b];
        }
    };
    std.sort.pdq(usize, idx[0..ndom], Ctx{ .s = score }, Ctx.lt);

    var total_pos: usize = 0;
    var total: usize = 0;
    for (0..ndom) |i| {
        total_pos += pos[i];
        total += tot[i];
    }
    var best = BestSplit{ .acc = 0, .predict1 = [_]bool{false} ** MAXDOM, .ndom = ndom };
    if (total == 0) return best;
    best.acc = @as(f64, @floatFromInt(total - total_pos)) / @as(f64, @floatFromInt(total));

    var cum_pos: usize = 0;
    var cum_tot: usize = 0;
    var i: usize = ndom;
    while (i > 0) {
        i -= 1;
        const d = idx[i];
        cum_pos += pos[d];
        cum_tot += tot[d];
        const tp = cum_pos;
        const tn = (total - cum_tot) - (total_pos - cum_pos);
        const acc = @as(f64, @floatFromInt(tp + tn)) / @as(f64, @floatFromInt(total));
        if (acc > best.acc) {
            best.acc = acc;
            var pr = [_]bool{false} ** MAXDOM;
            var k: usize = i;
            while (k < ndom) : (k += 1) pr[idx[k]] = true;
            best.predict1 = pr;
        }
    }
    return best;
}

/// Best single-threshold classifier on `score`, covering both polarities
/// (predict-1-above and predict-1-below), chosen on the given bucket stats.
fn bestSplitFromBuckets(pos: []const usize, tot: []const usize, score: []const f64, ndom: usize) BestSplit {
    const a = bestSplitOneDir(pos, tot, score, ndom);
    var neg: [MAXDOM]f64 = undefined;
    for (0..ndom) |i| neg[i] = -score[i];
    const b = bestSplitOneDir(pos, tot, neg[0..ndom], ndom);
    return if (a.acc >= b.acc) a else b;
}

fn applySplit(pos: []const usize, tot: []const usize, sp: BestSplit) f64 {
    var tp: usize = 0;
    var tot_all: usize = 0;
    var pos_all: usize = 0;
    var predicted_pos_total: usize = 0;
    for (0..sp.ndom) |d| {
        tot_all += tot[d];
        pos_all += pos[d];
        if (sp.predict1[d]) {
            tp += pos[d];
            predicted_pos_total += tot[d];
        }
    }
    if (tot_all == 0) return 0.5;
    const tn = (tot_all - predicted_pos_total) - (pos_all - tp);
    return @as(f64, @floatFromInt(tp + tn)) / @as(f64, @floatFromInt(tot_all));
}

fn bucketize(vals: []const usize, Y: []const f64, lo: usize, hi: usize, ndom: usize, pos: []usize, tot: []usize) void {
    for (0..ndom) |i| {
        pos[i] = 0;
        tot[i] = 0;
    }
    for (lo..hi) |s| {
        const v = vals[s];
        tot[v] += 1;
        if (Y[s] > 0.5) pos[v] += 1;
    }
}

// ---------------------------------------------------------------------------
// Target construction
// ---------------------------------------------------------------------------
const TKind = enum { batC, batD, batB, xor_extra, cmp_subset, spectral_extra, base_extra };

const Target = struct {
    name: []const u8,
    kind: TKind,
    bc_idx: usize = 0,
    bd_idx: usize = 0,
    bb: rq1.BatteryTarget = undefined,
    mask: u8 = 0,
    pairs_mask: u32 = 0,
    stat_kind: u8 = 0, // 0=sum(g), 1..5=count(cells>=t)
    mod_k: u8 = 0,
    be_kind: u8 = 0, // 0 = sum>=c, 1 = countGE(t)>=c
    be_t: u8 = 0,
    be_c: i32 = 0,
};

fn statValue(g: [NCELL]u8, stat_kind: u8) usize {
    if (stat_kind == 0) return gridSum(g);
    return countGE(g, stat_kind);
}
fn statDomain(stat_kind: u8) usize {
    if (stat_kind == 0) return 41; // sum(g) in 0..40
    return 9; // count(cells>=t) in 0..8
}

fn labelOf(t: Target, g: [NCELL]u8) f64 {
    return switch (t.kind) {
        .batC => bc.labelTarget(g, bc.BATTERY_C[t.bc_idx]),
        .batD => bd.labelTarget(g, bd.BATTERY_D[t.bd_idx]),
        .batB => rq1.labelBattery(g, t.bb),
        .xor_extra => blk: {
            var acc: u1 = 0;
            for (0..NCELL) |i| {
                if (t.mask & (@as(u8, 1) << @intCast(i)) != 0) acc ^= lbBit(g[i]);
            }
            break :blk @floatFromInt(acc);
        },
        .cmp_subset => blk: {
            var acc: u1 = 0;
            for (0..NPAIR) |p| {
                if (t.pairs_mask & (@as(u32, 1) << @intCast(p)) != 0) acc ^= cmpBit(g, p);
            }
            break :blk @floatFromInt(acc);
        },
        .spectral_extra => blk: {
            const s = statValue(g, t.stat_kind);
            break :blk if (s % t.mod_k == 0) 1.0 else 0.0;
        },
        .base_extra => blk: {
            const s: i64 = @intCast(if (t.be_kind == 0) gridSum(g) else countGE(g, t.be_t));
            break :blk if (s >= t.be_c) 1.0 else 0.0;
        },
    };
}

fn rol8(x: u8, r: u3) u8 {
    if (r == 0) return x;
    const left = x << r;
    const right = x >> @intCast(8 - @as(u4, r));
    return left | right;
}

fn buildTargets(alloc: std.mem.Allocator) ![]Target {
    var list = std.ArrayList(Target).init(alloc);

    // --- Battery C (11, minus C10 which is an exact duplicate of C01: both
    //     e2 kinds `xor_cells`/`parity_xor` reduce to the identical formula
    //     xorMasked(g,mask)&1, and both specify mask=0x0F -- dropped here to
    //     avoid an exact-duplicate leak across train/test splits, caught by
    //     the leakage guard below) ---
    for (0..bc.BATTERY_C.len) |i| {
        const spec = bc.BATTERY_C[i].e2_spec;
        if (spec) |sp| {
            if (sp.kind == .parity_xor and sp.mask == 0x0F) continue; // dup of C01
        }
        try list.append(.{ .name = bc.BATTERY_C[i].name, .kind = .batC, .bc_idx = i });
    }
    // --- Battery D (11) ---
    for (0..bd.BATTERY_D.len) |i| {
        try list.append(.{ .name = bd.BATTERY_D[i].name, .kind = .batD, .bd_idx = i });
    }
    // --- Battery B (11, minus inversion_parity which duplicates C09 exactly
    //     -- same function of g, dropped to avoid an exact-duplicate leak
    //     between train/test splits) ---
    var bprng = std.Random.DefaultPrng.init(0xB477E120260711);
    const brand = bprng.random();
    const bb_targets = try rq1.generateBatteryB(brand, alloc);
    for (bb_targets) |bt| {
        if (bt.kind == .inversion_parity) continue; // dedupe vs C09
        try list.append(.{ .name = bt.name, .kind = .batB, .bb = bt });
    }

    // --- xor_extra: weight 2,3,6,7 masks (battery C only covers weight 4-5) ---
    const weights = [_]usize{ 2, 3, 6, 7 };
    const shifts = [_]u3{ 0, 3, 5 };
    var namebuf: [64][32]u8 = undefined;
    var nb: usize = 0;
    for (weights) |w| {
        const base: u8 = @intCast((@as(u16, 1) << @intCast(w)) - 1);
        for (shifts) |sh| {
            const mask = rol8(base, sh);
            std.debug.assert(popcount8(mask) == w);
            const s = try std.fmt.bufPrint(&namebuf[nb], "XR w{d} mask=0x{X:0>2}", .{ w, mask });
            nb += 1;
            try list.append(.{ .name = s, .kind = .xor_extra, .mask = mask });
        }
    }

    // --- cmp_subset: prefix subsets of the 28 canonical comparison pairs,
    //     sizes 3,6,10,14,18,22 (parity-over-comparisons family, generalizing
    //     C09/B11's all-28 case to smaller order-statistic aggregates) ---
    const csizes = [_]usize{ 3, 6, 10, 14, 18, 22 };
    for (csizes) |sz| {
        const pm: u32 = if (sz >= 32) 0xFFFFFFFF else (@as(u32, 1) << @intCast(sz)) - 1;
        const s = try std.fmt.bufPrint(&namebuf[nb], "CMP sz{d}", .{sz});
        nb += 1;
        try list.append(.{ .name = s, .kind = .cmp_subset, .pairs_mask = pm });
    }

    // --- spectral_extra: count(cells>=t) mod k, t in {1,2,4,5} (t=3 is
    //     battery D's own count3), k in {3,4,6,8} ---
    const stats = [_]u8{ 1, 2, 4, 5 };
    const mods = [_]u8{ 3, 4, 6, 8 };
    for (stats) |st| {
        for (mods) |k| {
            const s = try std.fmt.bufPrint(&namebuf[nb], "SPEC t{d}k{d}", .{ st, k });
            nb += 1;
            try list.append(.{ .name = s, .kind = .spectral_extra, .stat_kind = st, .mod_k = k });
        }
    }

    // --- base_extra: plain scalar-threshold predicates, easy for the base
    //     ladder's own scalar_thresh family ---
    const sum_cs = [_]i32{ 15, 20, 25 };
    for (sum_cs) |c| {
        const s = try std.fmt.bufPrint(&namebuf[nb], "BASE sum>={d}", .{c});
        nb += 1;
        try list.append(.{ .name = s, .kind = .base_extra, .be_kind = 0, .be_c = c });
    }
    const cnt_cs = [_]i32{ 3, 4, 5 };
    for (cnt_cs) |c| {
        const s = try std.fmt.bufPrint(&namebuf[nb], "BASE cnt2>={d}", .{c});
        nb += 1;
        try list.append(.{ .name = s, .kind = .base_extra, .be_kind = 1, .be_t = 2, .be_c = c });
    }

    return try list.toOwnedSlice();
}

// ---------------------------------------------------------------------------
// GF2 joint dictionary: 28 cmp bits + 8 lb bits + 8 tb bits + intercept = 45
// ---------------------------------------------------------------------------
const NDICT = 45;

fn featBits45(g: [NCELL]u8) u64 {
    var bits: u64 = 0;
    for (0..NPAIR) |p| {
        if (cmpBit(g, p) == 1) bits |= (@as(u64, 1) << @intCast(p));
    }
    for (0..NCELL) |i| {
        if (lbBit(g[i]) == 1) bits |= (@as(u64, 1) << @intCast(28 + i));
    }
    for (0..NCELL) |i| {
        if (tbBit(g[i]) == 1) bits |= (@as(u64, 1) << @intCast(36 + i));
    }
    bits |= (@as(u64, 1) << 44); // intercept
    return bits;
}

const Gf2Result = struct {
    consistent: bool,
    rank: usize,
    sol_bits: u64, // bit c = coefficient c (only meaningful for pivoted cols)
};

/// Gaussian elimination over GF(2) using up to `maxrows` training rows.
/// Row format: bits 0..44 = features, bit 45 = label (RHS).
fn gf2Fit(grid: []const [NCELL]u8, Y: []const f64, maxrows: usize) Gf2Result {
    var pivots: [NDICT]u64 = undefined;
    var used: [NDICT]bool = [_]bool{false} ** NDICT;
    var rank: usize = 0;
    var consistent = true;

    var s: usize = 0;
    while (s < maxrows and s < NTR) : (s += 1) {
        var r: u64 = featBits45(grid[s]);
        const yb: u64 = if (Y[s] > 0.5) 1 else 0;
        r |= (yb << 45);
        // reduce by existing pivots
        var c: usize = 0;
        while (c < NDICT) : (c += 1) {
            if (used[c] and (r & (@as(u64, 1) << @intCast(c))) != 0) {
                r ^= pivots[c];
            }
        }
        // find lowest set bit among 0..44
        var lead: ?usize = null;
        var cc: usize = 0;
        while (cc < NDICT) : (cc += 1) {
            if ((r & (@as(u64, 1) << @intCast(cc))) != 0) {
                lead = cc;
                break;
            }
        }
        if (lead) |lc| {
            pivots[lc] = r;
            used[lc] = true;
            rank += 1;
        } else {
            // all feature bits zero; must have RHS bit zero too
            if ((r & (@as(u64, 1) << 45)) != 0) {
                consistent = false;
                break;
            }
        }
    }

    if (!consistent) return .{ .consistent = false, .rank = rank, .sol_bits = 0 };

    // back-substitute to RREF among pivoted columns
    var c: usize = NDICT;
    while (c > 0) {
        c -= 1;
        if (!used[c]) continue;
        var c2: usize = 0;
        while (c2 < c) : (c2 += 1) {
            if (used[c2] and (pivots[c2] & (@as(u64, 1) << @intCast(c))) != 0) {
                pivots[c2] ^= pivots[c];
            }
        }
    }
    var sol: u64 = 0;
    var ci: usize = 0;
    while (ci < NDICT) : (ci += 1) {
        if (used[ci]) {
            const rhs = (pivots[ci] >> 45) & 1;
            if (rhs != 0) sol |= (@as(u64, 1) << @intCast(ci));
        }
    }
    return .{ .consistent = true, .rank = rank, .sol_bits = sol };
}

fn gf2Predict(sol_bits: u64, g: [NCELL]u8) f64 {
    const fb = featBits45(g) & ((@as(u64, 1) << NDICT) - 1);
    const overlap = fb & sol_bits;
    return @floatFromInt(@popCount(overlap) & 1);
}

fn gf2Accuracy(sol_bits: u64, grid: []const [NCELL]u8, Y: []const f64, lo: usize, hi: usize) f64 {
    var match: usize = 0;
    for (lo..hi) |s| {
        if (gf2Predict(sol_bits, grid[s]) == Y[s]) match += 1;
    }
    return @as(f64, @floatFromInt(match)) / @as(f64, @floatFromInt(hi - lo));
}

// ---------------------------------------------------------------------------
// Per-target analysis: descriptor + 3 arms
// ---------------------------------------------------------------------------
const Family = enum { base, gf2_joint, spectral_acc };

const NFEAT = 10;

const Analysis = struct {
    desc: [NFEAT]f64,
    base_acc: f64,
    gf2_acc: f64,
    spec_acc: f64,
    base_via: [40]u8 = undefined,
    base_via_len: usize = 0,
    spec_via_stat: u8 = 0,
    spec_via_k_est: u8 = 0,
    gf2_sol: u64 = 0,
};

fn setNote(buf: *[40]u8, comptime fmt: []const u8, args: anytype) usize {
    const s = std.fmt.bufPrint(buf, fmt, args) catch return 0;
    return s.len;
}

fn evalKindParam(kd: u8, pm: u8, g: [NCELL]u8) f64 {
    return switch (kd) {
        0 => monomialSign(pm, g),
        1 => walshParity(pm, g),
        2 => @floatFromInt(cmpBit(g, pm)),
        else => 0,
    };
}

/// Evaluate the BASE family exhaustively: monomial(162) + walsh(255) +
/// pair_relation(28) + world_sum_mod(6) + scalar_thresh(6) +
/// spectral_power_argmax(1, count3) + AND/OR top-5 combos(20).
/// Selection on VAL split [NTR,NVA), certify on TEST split [NVA,NSAMP).
fn evalBase(grid: []const [NCELL]u8, Y: []const f64) struct { acc: f64, via_len: usize, via: [40]u8 } {
    var via: [40]u8 = undefined;
    // --- monomial + walsh + pair: track best val accuracy, and top-5 for AND/OR combos ---
    const NCAND = 162 + 255 + 28;
    var val_acc: [NCAND]f64 = undefined;
    var kind: [NCAND]u8 = undefined; // 0=mono,1=walsh,2=pair
    var param: [NCAND]u8 = undefined;
    var nc: usize = 0;

    for (0..N_MONO) |i| {
        var match: usize = 0;
        for (NTR..NVA) |s| {
            if (monomialSign(MONO_MASKS[i], grid[s]) == Y[s]) match += 1;
        }
        val_acc[nc] = binAccuracy(match, NVA - NTR);
        kind[nc] = 0;
        param[nc] = MONO_MASKS[i];
        nc += 1;
    }
    for (0..N_WALSH) |i| {
        var match: usize = 0;
        for (NTR..NVA) |s| {
            if (walshParity(WALSH_MASKS[i], grid[s]) == Y[s]) match += 1;
        }
        val_acc[nc] = binAccuracy(match, NVA - NTR);
        kind[nc] = 1;
        param[nc] = WALSH_MASKS[i];
        nc += 1;
    }
    for (0..NPAIR) |p| {
        var match: usize = 0;
        for (NTR..NVA) |s| {
            const fv: f64 = @floatFromInt(cmpBit(grid[s], p));
            if (fv == Y[s]) match += 1;
        }
        val_acc[nc] = binAccuracy(match, NVA - NTR);
        kind[nc] = 2;
        param[nc] = @intCast(p);
        nc += 1;
    }

    // best single candidate among mono/walsh/pair
    var best_idx: usize = 0;
    var best_val: f64 = -1;
    for (0..nc) |i| {
        if (val_acc[i] > best_val) {
            best_val = val_acc[i];
            best_idx = i;
        }
    }
    // top-5 indices for AND/OR composition
    var top5: [5]usize = .{ 0, 0, 0, 0, 0 };
    var top5v: [5]f64 = .{ -1, -1, -1, -1, -1 };
    for (0..nc) |i| {
        var j: usize = 0;
        while (j < 5) : (j += 1) {
            if (val_acc[i] > top5v[j]) {
                var k: usize = 4;
                while (k > j) : (k -= 1) {
                    top5v[k] = top5v[k - 1];
                    top5[k] = top5[k - 1];
                }
                top5v[j] = val_acc[i];
                top5[j] = i;
                break;
            }
        }
    }

    // best threshold polarity per top5 (0/1 bit, using its own val-optimal orientation)
    var top5_bit_val: [5][NVA]f64 = undefined; // cached feature values on val split, reused for AND/OR
    for (0..5) |t| {
        for (NTR..NVA) |s| {
            top5_bit_val[t][s - NTR] = evalKindParam(kind[top5[t]], param[top5[t]], grid[s]);
        }
    }

    var best_and_val: f64 = -1;
    var best_and_pair: [2]usize = .{ 0, 1 };
    var best_and_op: u8 = 0; // 0=AND,1=OR
    for (0..5) |a| {
        for (a + 1..5) |b| {
            var match_and: usize = 0;
            var match_or: usize = 0;
            for (0..(NVA - NTR)) |k| {
                const fa = top5_bit_val[a][k] > 0.5;
                const fb = top5_bit_val[b][k] > 0.5;
                const cand_and: f64 = if (fa and fb) 1.0 else 0.0;
                const cand_or: f64 = if (fa or fb) 1.0 else 0.0;
                if (cand_and == Y[NTR + k]) match_and += 1;
                if (cand_or == Y[NTR + k]) match_or += 1;
            }
            const acc_and = binAccuracy(match_and, NVA - NTR);
            const acc_or = binAccuracy(match_or, NVA - NTR);
            if (acc_and > best_and_val) {
                best_and_val = acc_and;
                best_and_pair = .{ a, b };
                best_and_op = 0;
            }
            if (acc_or > best_and_val) {
                best_and_val = acc_or;
                best_and_pair = .{ a, b };
                best_and_op = 1;
            }
        }
    }

    // --- world_sum_mod (6) ---
    const primes = [_]u8{ 2, 3, 5, 7, 11, 13 };
    var wsm_val: [6]f64 = undefined;
    for (primes, 0..) |k, i| {
        var match: usize = 0;
        for (NTR..NVA) |s| {
            const fv: f64 = if (gridSum(grid[s]) % k == 0) 1.0 else 0.0;
            if (fv == Y[s]) match += 1;
        }
        wsm_val[i] = binAccuracy(match, NVA - NTR);
    }
    var wsm_best: f64 = -1;
    var wsm_best_k: u8 = 0;
    for (primes, 0..) |k, i| {
        if (wsm_val[i] > wsm_best) {
            wsm_best = wsm_val[i];
            wsm_best_k = k;
        }
    }

    // --- scalar_thresh (6: sum(g), count>=1..5), bucketized threshold search ---
    var sc_best_val: f64 = -1;
    var sc_best_stat: u8 = 0;
    var sc_best_split: BestSplit = undefined;
    var stat_vals_cache: [NSAMP]usize = undefined;
    for (0..6) |si| {
        const stat_kind: u8 = @intCast(si); // 0=sum,1..5=count>=t
        const ndom = statDomain(stat_kind);
        for (0..NSAMP) |s| stat_vals_cache[s] = statValue(grid[s], stat_kind);
        var pos: [MAXDOM]usize = undefined;
        var tot: [MAXDOM]usize = undefined;
        bucketize(&stat_vals_cache, Y, NTR, NVA, ndom, &pos, &tot);
        var score: [MAXDOM]f64 = undefined;
        for (0..ndom) |v| score[v] = @floatFromInt(v);
        const sp = bestSplitFromBuckets(&pos, &tot, &score, ndom);
        if (sp.acc > sc_best_val) {
            sc_best_val = sp.acc;
            sc_best_stat = stat_kind;
            sc_best_split = sp;
        }
    }

    // --- spectral power-argmax pick on count3 (the ladder's own menu stage) ---
    var count3_vals: [NSAMP]usize = undefined;
    for (0..NSAMP) |s| count3_vals[s] = countGE(grid[s], 3);
    const NFREQ = 200;
    var freqs: [NFREQ]f64 = undefined;
    for (0..NFREQ) |i| freqs[i] = std.math.pi * (@as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(NFREQ)));
    var pos9: [MAXDOM]usize = undefined;
    var tot9: [MAXDOM]usize = undefined;
    bucketize(&count3_vals, Y, 0, NTR, 9, &pos9, &tot9); // power selection uses TRAIN split
    var best_power: f64 = -1;
    var best_power_freq_idx: usize = 0;
    for (0..NFREQ) |fi| {
        var power: f64 = 0;
        for (0..9) |v| {
            const cosv = @cos(freqs[fi] * @as(f64, @floatFromInt(v)));
            const bip: f64 = if (tot9[v] > 0) (2.0 * @as(f64, @floatFromInt(pos9[v])) / @as(f64, @floatFromInt(tot9[v])) - 1.0) else 0.0;
            power += cosv * bip * @as(f64, @floatFromInt(tot9[v]));
        }
        power = power * power;
        if (power > best_power) {
            best_power = power;
            best_power_freq_idx = fi;
        }
    }
    var pos9v: [MAXDOM]usize = undefined;
    var tot9v: [MAXDOM]usize = undefined;
    bucketize(&count3_vals, Y, NTR, NVA, 9, &pos9v, &tot9v); // threshold selection on VAL
    var score9: [MAXDOM]f64 = undefined;
    for (0..9) |v| score9[v] = @cos(freqs[best_power_freq_idx] * @as(f64, @floatFromInt(v)));
    const power_split = bestSplitFromBuckets(&pos9v, &tot9v, &score9, 9);

    // --- pick overall winner among: best mono/walsh/pair, AND/OR combo,
    //     world_sum_mod, scalar_thresh, spectral-power-pick ---
    const Candidate = struct { tag: u8, val: f64 };
    const cands = [_]Candidate{
        .{ .tag = 0, .val = best_val }, // mono/walsh/pair single
        .{ .tag = 1, .val = best_and_val }, // AND/OR combo
        .{ .tag = 2, .val = wsm_best }, // world_sum_mod
        .{ .tag = 3, .val = sc_best_val }, // scalar_thresh
        .{ .tag = 4, .val = power_split.acc }, // spectral power pick
    };
    var win: usize = 0;
    for (1..cands.len) |i| {
        if (cands[i].val > cands[win].val) win = i;
    }

    var test_acc: f64 = 0.5;
    var via_len: usize = 0;
    switch (cands[win].tag) {
        0 => {
            // accuracy on test with best-of-two polarities fixed by val
            var match_pos: usize = 0;
            var match_neg: usize = 0;
            for (NVA..NSAMP) |s| {
                const fv = evalKindParam(kind[best_idx], param[best_idx], grid[s]);
                if (fv == Y[s]) match_pos += 1;
                if ((1.0 - fv) == Y[s]) match_neg += 1;
            }
            test_acc = @max(@as(f64, @floatFromInt(match_pos)), @as(f64, @floatFromInt(match_neg))) / @as(f64, @floatFromInt(NSAMP - NVA));
            via_len = setNote(&via, "mono/walsh/pair kind={d} mask=0x{X:0>2}", .{ kind[best_idx], param[best_idx] });
        },
        1 => {
            var match: usize = 0;
            for (NVA..NSAMP) |s| {
                const fa = evalKindParam(kind[top5[best_and_pair[0]]], param[top5[best_and_pair[0]]], grid[s]) > 0.5;
                const fb = evalKindParam(kind[top5[best_and_pair[1]]], param[top5[best_and_pair[1]]], grid[s]) > 0.5;
                const cand: f64 = if (best_and_op == 0) (if (fa and fb) 1.0 else 0.0) else (if (fa or fb) 1.0 else 0.0);
                if (cand == Y[s]) match += 1;
            }
            test_acc = binAccuracy(match, NSAMP - NVA);
            via_len = setNote(&via, "AND/OR combo op={d}", .{best_and_op});
        },
        2 => {
            var match: usize = 0;
            for (NVA..NSAMP) |s| {
                const fv: f64 = if (gridSum(grid[s]) % wsm_best_k == 0) 1.0 else 0.0;
                if (fv == Y[s]) match += 1;
            }
            test_acc = binAccuracy(match, NSAMP - NVA);
            via_len = setNote(&via, "world_sum_mod k={d}", .{wsm_best_k});
        },
        3 => {
            var pos_t: [MAXDOM]usize = undefined;
            var tot_t: [MAXDOM]usize = undefined;
            const ndom = statDomain(sc_best_stat);
            for (0..NSAMP) |s| stat_vals_cache[s] = statValue(grid[s], sc_best_stat);
            bucketize(&stat_vals_cache, Y, NVA, NSAMP, ndom, &pos_t, &tot_t);
            test_acc = applySplit(&pos_t, &tot_t, sc_best_split);
            via_len = setNote(&via, "scalar_thresh stat={d}", .{sc_best_stat});
        },
        4 => {
            var pos_t: [MAXDOM]usize = undefined;
            var tot_t: [MAXDOM]usize = undefined;
            bucketize(&count3_vals, Y, NVA, NSAMP, 9, &pos_t, &tot_t);
            test_acc = applySplit(&pos_t, &tot_t, power_split);
            via_len = setNote(&via, "spectral power-pick freq_idx={d}", .{best_power_freq_idx});
        },
        else => unreachable,
    }
    return .{ .acc = test_acc, .via_len = via_len, .via = via };
}

fn evalGf2(grid: []const [NCELL]u8, Y: []const f64) struct { acc: f64, sol: u64 } {
    const fit = gf2Fit(grid, Y, 300);
    if (!fit.consistent) return .{ .acc = 0.5, .sol = 0 };
    const acc = gf2Accuracy(fit.sol_bits, grid, Y, NVA, NSAMP);
    return .{ .acc = acc, .sol = fit.sol_bits };
}

fn evalSpectralAcc(grid: []const [NCELL]u8, Y: []const f64) struct { acc: f64, stat: u8, freq_idx: usize } {
    const NFREQ = 200;
    var freqs: [NFREQ]f64 = undefined;
    for (0..NFREQ) |i| freqs[i] = std.math.pi * (@as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(NFREQ)));

    var best_val: f64 = -1;
    var best_stat: u8 = 0;
    var best_freq_idx: usize = 0;
    var best_split: BestSplit = undefined;
    var vals_cache: [NSAMP]usize = undefined;

    for (0..6) |si| {
        const stat_kind: u8 = @intCast(si);
        const ndom = statDomain(stat_kind);
        for (0..NSAMP) |s| vals_cache[s] = statValue(grid[s], stat_kind);
        var pos: [MAXDOM]usize = undefined;
        var tot: [MAXDOM]usize = undefined;
        bucketize(&vals_cache, Y, NTR, NVA, ndom, &pos, &tot); // accuracy-argmax selection on VAL
        for (0..NFREQ) |fi| {
            var score: [MAXDOM]f64 = undefined;
            for (0..ndom) |v| score[v] = @cos(freqs[fi] * @as(f64, @floatFromInt(v)));
            const sp = bestSplitFromBuckets(&pos, &tot, &score, ndom);
            if (sp.acc > best_val) {
                best_val = sp.acc;
                best_stat = stat_kind;
                best_freq_idx = fi;
                best_split = sp;
            }
        }
    }

    // certify on TEST split using the winning (stat, freq)
    const ndom = statDomain(best_stat);
    for (0..NSAMP) |s| vals_cache[s] = statValue(grid[s], best_stat);
    var pos_t: [MAXDOM]usize = undefined;
    var tot_t: [MAXDOM]usize = undefined;
    bucketize(&vals_cache, Y, NVA, NSAMP, ndom, &pos_t, &tot_t);
    const test_acc = applySplit(&pos_t, &tot_t, best_split);
    return .{ .acc = test_acc, .stat = best_stat, .freq_idx = best_freq_idx };
}

/// Cheap failure-signal descriptor -- computable without knowing which
/// family wins. Uses weak/near-miss proxies (correlational argmaxes,
/// power-vs-accuracy gap), not full certification.
fn computeDescriptor(grid: []const [NCELL]u8, Y: []const f64) [NFEAT]f64 {
    var d: [NFEAT]f64 = undefined;

    // d1: max |signed agreement| over monomial162 on VAL split
    var d1: f64 = 0;
    for (0..N_MONO) |i| {
        var acc: f64 = 0;
        for (NTR..NVA) |s| acc += signedAgreement(monomialSign(MONO_MASKS[i], grid[s]), Y[s]);
        acc /= @floatFromInt(NVA - NTR);
        d1 = @max(d1, @abs(acc));
    }
    d[0] = d1;

    // d2: max |signed agreement| over walsh255 on VAL split
    var d2: f64 = 0;
    var mono_agree_std_acc: f64 = 0;
    var mono_agree_sq: f64 = 0;
    for (0..N_WALSH) |i| {
        var acc: f64 = 0;
        for (NTR..NVA) |s| acc += signedAgreement(walshParity(WALSH_MASKS[i], grid[s]), Y[s]);
        acc /= @floatFromInt(NVA - NTR);
        d2 = @max(d2, @abs(acc));
        if (i < N_MONO) {} // no-op, keep loop shape stable
    }
    // d9 flatness: use monomial162 agreement spread instead (recompute cheaply)
    for (0..N_MONO) |i| {
        var acc: f64 = 0;
        for (NTR..NVA) |s| acc += signedAgreement(monomialSign(MONO_MASKS[i], grid[s]), Y[s]);
        acc /= @floatFromInt(NVA - NTR);
        mono_agree_std_acc += acc;
        mono_agree_sq += acc * acc;
    }
    const nmono_f: f64 = @floatFromInt(N_MONO);
    const mean_a = mono_agree_std_acc / nmono_f;
    const var_a = mono_agree_sq / nmono_f - mean_a * mean_a;
    d[1] = d2;
    d[8] = @sqrt(@max(0.0, var_a));

    // d3: max |signed agreement| over single cmp bits (28)
    var d3: f64 = 0;
    for (0..NPAIR) |p| {
        var acc: f64 = 0;
        for (NTR..NVA) |s| acc += signedAgreement(@floatFromInt(cmpBit(grid[s], p)), Y[s]);
        acc /= @floatFromInt(NVA - NTR);
        d3 = @max(d3, @abs(acc));
    }
    d[2] = d3;

    // d4: max |signed agreement| over sampled cmp-subset parities (fixed,
    // deterministic set of 24 subset masks of varying size -- weak proxy for
    // order-statistic structure beyond a single comparison bit)
    var d4: f64 = 0;
    var rng = std.Random.DefaultPrng.init(0xD4C0DE);
    const rr = rng.random();
    for (0..24) |_| {
        const sz = 2 + (rr.int(u5) % 7); // size 2..8
        var pm: u32 = 0;
        var placed: usize = 0;
        while (placed < sz) {
            const p = rr.int(u5) % NPAIR;
            const bit = @as(u32, 1) << @intCast(p);
            if (pm & bit == 0) {
                pm |= bit;
                placed += 1;
            }
        }
        var acc: f64 = 0;
        for (NTR..NVA) |s| {
            var par: u1 = 0;
            for (0..NPAIR) |p| {
                if (pm & (@as(u32, 1) << @intCast(p)) != 0) par ^= cmpBit(grid[s], p);
            }
            acc += signedAgreement(@floatFromInt(par), Y[s]);
        }
        acc /= @floatFromInt(NVA - NTR);
        d4 = @max(d4, @abs(acc));
    }
    d[3] = d4;

    // d5: world_sum_mod best VAL accuracy (6 primes) -- cheap "is base
    // already nearly sufficient" signal
    const primes = [_]u8{ 2, 3, 5, 7, 11, 13 };
    var d5: f64 = 0;
    for (primes) |k| {
        var match: usize = 0;
        for (NTR..NVA) |s| {
            const fv: f64 = if (gridSum(grid[s]) % k == 0) 1.0 else 0.0;
            if (fv == Y[s]) match += 1;
        }
        d5 = @max(d5, binAccuracy(match, NVA - NTR));
    }
    d[4] = d5;

    // d6/d7: spectral power-pick vs accuracy-pick accuracy on count3, VAL split
    var count3_vals: [NSAMP]usize = undefined;
    for (0..NSAMP) |s| count3_vals[s] = countGE(grid[s], 3);
    const NFREQ = 200;
    var freqs: [NFREQ]f64 = undefined;
    for (0..NFREQ) |i| freqs[i] = std.math.pi * (@as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(NFREQ)));
    var pos_tr: [MAXDOM]usize = undefined;
    var tot_tr: [MAXDOM]usize = undefined;
    bucketize(&count3_vals, Y, 0, NTR, 9, &pos_tr, &tot_tr);
    var best_power: f64 = -1;
    var best_power_fi: usize = 0;
    for (0..NFREQ) |fi| {
        var power: f64 = 0;
        for (0..9) |v| {
            const cosv = @cos(freqs[fi] * @as(f64, @floatFromInt(v)));
            const bip: f64 = if (tot_tr[v] > 0) (2.0 * @as(f64, @floatFromInt(pos_tr[v])) / @as(f64, @floatFromInt(tot_tr[v])) - 1.0) else 0.0;
            power += cosv * bip * @as(f64, @floatFromInt(tot_tr[v]));
        }
        power = power * power;
        if (power > best_power) {
            best_power = power;
            best_power_fi = fi;
        }
    }
    var pos_va: [MAXDOM]usize = undefined;
    var tot_va: [MAXDOM]usize = undefined;
    bucketize(&count3_vals, Y, NTR, NVA, 9, &pos_va, &tot_va);
    var score_pw: [MAXDOM]f64 = undefined;
    for (0..9) |v| score_pw[v] = @cos(freqs[best_power_fi] * @as(f64, @floatFromInt(v)));
    const d6 = bestSplitFromBuckets(&pos_va, &tot_va, &score_pw, 9).acc;
    var best_acc_pick: f64 = 0;
    for (0..NFREQ) |fi| {
        var score: [MAXDOM]f64 = undefined;
        for (0..9) |v| score[v] = @cos(freqs[fi] * @as(f64, @floatFromInt(v)));
        const sp = bestSplitFromBuckets(&pos_va, &tot_va, &score, 9);
        best_acc_pick = @max(best_acc_pick, sp.acc);
    }
    d[5] = d6;
    d[6] = best_acc_pick;
    d[7] = best_acc_pick - d6;

    // d9 base-rate skew
    var mean_y: f64 = 0;
    for (0..NTR) |s| mean_y += Y[s];
    mean_y /= @floatFromInt(NTR);
    d[9] = @abs(mean_y - 0.5);

    return d;
}

fn analyzeTarget(grid: []const [NCELL]u8, Y: []const f64) Analysis {
    const desc = computeDescriptor(grid, Y);
    const base_r = evalBase(grid, Y);
    const gf2_r = evalGf2(grid, Y);
    const spec_r = evalSpectralAcc(grid, Y);
    return .{
        .desc = desc,
        .base_acc = base_r.acc,
        .gf2_acc = gf2_r.acc,
        .spec_acc = spec_r.acc,
        .base_via = base_r.via,
        .base_via_len = base_r.via_len,
        .spec_via_stat = spec_r.stat,
        .spec_via_k_est = 0,
        .gf2_sol = gf2_r.sol,
    };
}

// ---------------------------------------------------------------------------
// Router: standardized-descriptor kNN
// ---------------------------------------------------------------------------
const TargetRecord = struct {
    name: []const u8,
    construct_tag: []const u8,
    desc: [NFEAT]f64,
    label: Family,
    base_acc: f64,
    gf2_acc: f64,
    spec_acc: f64,
    overlap: bool,
    gf2_sol: u64,
    kindtag: TKind,
    mask: u8,
    pairs_mask: u32,
    stat_kind: u8,
    mod_k: u8,
    bc_idx: usize,
    bd_idx: usize,
    spec_via_stat: u8,
};

const Stand = struct {
    mean: [NFEAT]f64,
    sd: [NFEAT]f64,
};

fn fitStand(recs: []const TargetRecord, idxs: []const usize) Stand {
    var mean: [NFEAT]f64 = [_]f64{0} ** NFEAT;
    for (idxs) |ix| {
        for (0..NFEAT) |f| mean[f] += recs[ix].desc[f];
    }
    const n: f64 = @floatFromInt(idxs.len);
    for (0..NFEAT) |f| mean[f] /= n;
    var sd: [NFEAT]f64 = [_]f64{0} ** NFEAT;
    for (idxs) |ix| {
        for (0..NFEAT) |f| {
            const d = recs[ix].desc[f] - mean[f];
            sd[f] += d * d;
        }
    }
    for (0..NFEAT) |f| sd[f] = @max(1e-6, @sqrt(sd[f] / n));
    return .{ .mean = mean, .sd = sd };
}

fn standardize(d: [NFEAT]f64, st: Stand) [NFEAT]f64 {
    var out: [NFEAT]f64 = undefined;
    for (0..NFEAT) |f| out[f] = (d[f] - st.mean[f]) / st.sd[f];
    return out;
}

fn dist2(a: [NFEAT]f64, b: [NFEAT]f64) f64 {
    var s: f64 = 0;
    for (0..NFEAT) |f| {
        const d = a[f] - b[f];
        s += d * d;
    }
    return s;
}

/// kNN predicts the family via majority vote among the k nearest TRAIN
/// points (Euclidean, standardized). Ties broken by nearest single neighbor.
fn knnPredict(recs: []const TargetRecord, train_idxs: []const usize, st: Stand, q: [NFEAT]f64, k: usize) Family {
    const qs = standardize(q, st);
    var order: [512]usize = undefined;
    var dists: [512]f64 = undefined;
    const n = train_idxs.len;
    for (0..n) |i| {
        const ts = standardize(recs[train_idxs[i]].desc, st);
        dists[i] = dist2(qs, ts);
        order[i] = i;
    }
    const Ctx = struct {
        d: []const f64,
        fn lt(self: @This(), a: usize, b: usize) bool {
            return self.d[a] < self.d[b];
        }
    };
    std.sort.pdq(usize, order[0..n], Ctx{ .d = &dists }, Ctx.lt);
    const kk = @min(k, n);
    var votes = [_]usize{ 0, 0, 0 };
    for (0..kk) |i| {
        const fam = recs[train_idxs[order[i]]].label;
        votes[@intFromEnum(fam)] += 1;
    }
    var best: usize = 0;
    for (1..3) |i| {
        if (votes[i] > votes[best]) best = i;
    }
    if (votes[best] == votes[0] and votes[0] == votes[1] and votes[1] == votes[2]) {
        // full tie: fall back to single nearest neighbor
        return recs[train_idxs[order[0]]].label;
    }
    return @enumFromInt(best);
}

fn majorityFamily(recs: []const TargetRecord, idxs: []const usize) Family {
    var counts = [_]usize{ 0, 0, 0 };
    for (idxs) |ix| counts[@intFromEnum(recs[ix].label)] += 1;
    var best: usize = 0;
    for (1..3) |i| {
        if (counts[i] > counts[best]) best = i;
    }
    return @enumFromInt(best);
}

fn familyName(f: Family) []const u8 {
    return switch (f) {
        .base => "base",
        .gf2_joint => "gf2_joint",
        .spectral_acc => "spectral_acc",
    };
}

fn evalCostOf(f: Family, eval_base: usize, eval_gf2: usize, eval_spec: usize) usize {
    return switch (f) {
        .base => eval_base,
        .gf2_joint => eval_gf2,
        .spectral_acc => eval_spec,
    };
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
pub fn main() !void {
    var timer = try std.time.Timer.start();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    initPairs();
    buildMaskTables();

    const EVAL_BASE: usize = 162 + 255 + 28 + 10 + 6 + 6 + 1; // mono+walsh+pair+AND/OR-pair-scan(top5 choose2)+world+scalar+spectralpower
    const EVAL_GF2: usize = NDICT;
    const EVAL_SPEC: usize = 6 * 200;

    try out.print("=== E2 Target Router (Round 2026-07-11) ===\n", .{});
    try out.print("EVAL_BASE={d} EVAL_GF2={d} EVAL_SPEC={d}\n\n", .{ EVAL_BASE, EVAL_GF2, EVAL_SPEC });

    // --- shared grid ---
    const GRID_SEED: u64 = 0xE2A0011E2026071;
    var gprng = std.Random.DefaultPrng.init(GRID_SEED);
    const grand = gprng.random();
    var grid: [NSAMP][NCELL]u8 = undefined;
    for (0..NSAMP) |s| {
        for (0..NCELL) |i| grid[s][i] = grand.intRangeAtMost(u8, 0, 5);
    }

    const targets = try buildTargets(alloc);
    try out.print("Built {d} candidate targets.\n", .{targets.len});

    var recs = std.ArrayList(TargetRecord).init(alloc);
    var n_excluded: usize = 0;
    var n_overlap: usize = 0;

    // three separate buffers so the CSV can be assembled in clean block
    // order even though the curve is computed before the final test loop
    var csv_block1 = std.ArrayList(u8).init(alloc); // per-target rows
    var csv_block2 = std.ArrayList(u8).init(alloc); // sample-complexity curve
    var csv_block3 = std.ArrayList(u8).init(alloc); // summary
    const cw = csv_block1.writer();
    const cw2 = csv_block2.writer();
    const cw3 = csv_block3.writer();
    try cw.print("split,name,construct_tag,true_family,base_acc,gf2_acc,spec_acc,d1,d2,d3,d4,d5,d6,d7,d8,d9,d10,router_pred,fixedbest_pred,random_pred,router_hit,fixedbest_hit,random_hit,notes\n", .{});

    for (targets) |t| {
        var Y: [NSAMP]f64 = undefined;
        for (0..NSAMP) |s| Y[s] = labelOf(t, grid[s]);

        const an = analyzeTarget(&grid, &Y);
        const solved_base = an.base_acc >= COVER;
        const solved_gf2 = an.gf2_acc >= COVER;
        const solved_spec = an.spec_acc >= COVER;
        const nsolved = @as(usize, if (solved_base) 1 else 0) + @as(usize, if (solved_gf2) 1 else 0) + @as(usize, if (solved_spec) 1 else 0);

        if (nsolved == 0) {
            n_excluded += 1;
            try out.print("  EXCLUDED (unsolved by all arms): {s} base={d:.3} gf2={d:.3} spec={d:.3}\n", .{ t.name, an.base_acc, an.gf2_acc, an.spec_acc });
            continue;
        }
        var label: Family = .base;
        // precedence on overlap: base (cheapest) > spectral_acc > gf2_joint
        if (solved_base) {
            label = .base;
        } else if (solved_spec) {
            label = .spectral_acc;
        } else {
            label = .gf2_joint;
        }
        if (nsolved > 1) n_overlap += 1;

        const tag = switch (t.kind) {
            .batC => "batteryC",
            .batD => "batteryD",
            .batB => "batteryB",
            .xor_extra => "xor_extra",
            .cmp_subset => "cmp_subset",
            .spectral_extra => "spectral_extra",
            .base_extra => "base_extra",
        };

        try recs.append(.{
            .name = t.name,
            .construct_tag = tag,
            .desc = an.desc,
            .label = label,
            .base_acc = an.base_acc,
            .gf2_acc = an.gf2_acc,
            .spec_acc = an.spec_acc,
            .overlap = nsolved > 1,
            .gf2_sol = an.gf2_sol,
            .kindtag = t.kind,
            .mask = t.mask,
            .pairs_mask = t.pairs_mask,
            .stat_kind = t.stat_kind,
            .mod_k = t.mod_k,
            .bc_idx = t.bc_idx,
            .bd_idx = t.bd_idx,
            .spec_via_stat = an.spec_via_stat,
        });
    }

    try out.print("\nSolved targets: {d} / {d} ({d} excluded, {d} multi-arm overlaps)\n", .{ recs.items.len, targets.len, n_excluded, n_overlap });

    var cbase: usize = 0;
    var cgf2: usize = 0;
    var cspec: usize = 0;
    for (recs.items) |r| {
        switch (r.label) {
            .base => cbase += 1,
            .gf2_joint => cgf2 += 1,
            .spectral_acc => cspec += 1,
        }
    }
    try out.print("Class counts: base={d} gf2_joint={d} spectral_acc={d}\n\n", .{ cbase, cgf2, cspec });

    // --- stratified split by class: ~60/20/20 ---
    var rngsplit = std.Random.DefaultPrng.init(0x5171700020260711);
    const rsplit = rngsplit.random();

    var by_class: [3]std.ArrayList(usize) = .{ std.ArrayList(usize).init(alloc), std.ArrayList(usize).init(alloc), std.ArrayList(usize).init(alloc) };
    for (recs.items, 0..) |r, i| try by_class[@intFromEnum(r.label)].append(i);
    for (0..3) |c| {
        const sl = by_class[c].items;
        rsplit.shuffle(usize, sl);
    }

    var train_idx = std.ArrayList(usize).init(alloc);
    var val_idx = std.ArrayList(usize).init(alloc);
    var test_idx = std.ArrayList(usize).init(alloc);
    for (0..3) |c| {
        const sl = by_class[c].items;
        const n = sl.len;
        if (n == 0) continue;
        var n_test: usize = @max(1, n / 5);
        var n_val: usize = @max(1, n / 5);
        if (n_test + n_val >= n) {
            n_test = if (n >= 3) 1 else 0;
            n_val = if (n >= 3) 1 else 0;
        }
        const n_tr = n - n_test - n_val;
        var i: usize = 0;
        while (i < n_tr) : (i += 1) try train_idx.append(sl[i]);
        while (i < n_tr + n_val) : (i += 1) try val_idx.append(sl[i]);
        while (i < n) : (i += 1) try test_idx.append(sl[i]);
    }

    try out.print("Split: train={d} val={d} test={d}\n\n", .{ train_idx.items.len, val_idx.items.len, test_idx.items.len });

    // --- leakage guard: nearest train-neighbor distance for every test target ---
    const st_full = fitStand(recs.items, train_idx.items);
    try out.print("Leakage guard (min standardized descriptor distance test->train):\n", .{});
    var min_dist_overall: f64 = std.math.inf(f64);
    for (test_idx.items) |tix| {
        const qs = standardize(recs.items[tix].desc, st_full);
        var mind: f64 = std.math.inf(f64);
        for (train_idx.items) |trix| {
            const ts = standardize(recs.items[trix].desc, st_full);
            mind = @min(mind, dist2(qs, ts));
        }
        min_dist_overall = @min(min_dist_overall, mind);
        if (mind < 0.01) {
            try out.print("  WARNING near-duplicate: {s} (dist2={d:.5})\n", .{ recs.items[tix].name, mind });
        }
    }
    try out.print("  min dist2 across all test targets: {d:.4} ({s})\n\n", .{ min_dist_overall, if (min_dist_overall < 0.01) "FLAGGED" else "clear" });

    // --- pick k on VAL using TRAIN-fit standardization ---
    var best_k: usize = 3;
    var best_k_acc: f64 = -1;
    for ([_]usize{ 1, 3, 5 }) |k| {
        var hit: usize = 0;
        for (val_idx.items) |vix| {
            const pred = knnPredict(recs.items, train_idx.items, st_full, recs.items[vix].desc, k);
            if (pred == recs.items[vix].label) hit += 1;
        }
        const acc = @as(f64, @floatFromInt(hit)) / @as(f64, @floatFromInt(@max(1, val_idx.items.len)));
        try out.print("  k={d} VAL acc={d:.3}\n", .{ k, acc });
        if (acc > best_k_acc) {
            best_k_acc = acc;
            best_k = k;
        }
    }
    try out.print("  chosen k={d} (selected on VAL only)\n\n", .{best_k});

    // --- sample-complexity curve: subsample TRAIN, refit stand+kNN each
    //     time, evaluate on VAL only ---
    try out.print("=== Sample-complexity curve (VAL accuracy vs #labeled train targets) ===\n", .{});
    try out.print("{s:>8} {s:>14} {s:>14} {s:>14}\n", .{ "n_train", "router_acc", "fixedbest_acc", "random_acc" });
    try cw2.print("n_train,router_val_acc,fixedbest_val_acc,random_val_acc\n", .{});
    const curve_sizes = [_]usize{ 4, 8, 12, 16, 24, 32, 999999 };
    for (curve_sizes) |raw_n| {
        const n = @min(raw_n, train_idx.items.len);
        if (n == 0) continue;
        const sub = train_idx.items[0..n];
        const st_sub = fitStand(recs.items, sub);
        var hit_router: usize = 0;
        for (val_idx.items) |vix| {
            const pred = knnPredict(recs.items, sub, st_sub, recs.items[vix].desc, best_k);
            if (pred == recs.items[vix].label) hit_router += 1;
        }
        const fb = majorityFamily(recs.items, sub);
        var hit_fb: usize = 0;
        for (val_idx.items) |vix| {
            if (recs.items[vix].label == fb) hit_fb += 1;
        }
        const nval: f64 = @floatFromInt(@max(1, val_idx.items.len));
        const acc_router = @as(f64, @floatFromInt(hit_router)) / nval;
        const acc_fb = @as(f64, @floatFromInt(hit_fb)) / nval;
        const acc_rand = 1.0 / 3.0;
        try out.print("{d:>8} {d:>14.3} {d:>14.3} {d:>14.3}\n", .{ n, acc_router, acc_fb, acc_rand });
        try cw2.print("{d},{d:.4},{d:.4},{d:.4}\n", .{ n, acc_router, acc_fb, acc_rand });
    }
    try out.print("\n", .{});

    // --- final headline: router (trained on TRAIN+VAL) vs fixed-best vs
    //     random, scored ONCE on TEST ---
    var trainval = std.ArrayList(usize).init(alloc);
    try trainval.appendSlice(train_idx.items);
    try trainval.appendSlice(val_idx.items);
    const st_tv = fitStand(recs.items, trainval.items);
    const fixedbest_family = majorityFamily(recs.items, trainval.items);

    var rngrand = std.Random.DefaultPrng.init(0x2A2A2A2A20260711);
    const rrand = rngrand.random();

    var router_solves: usize = 0;
    var fb_solves: usize = 0;
    var rand_solves: usize = 0;
    var router_evals: usize = 0;
    var fb_evals: usize = 0;
    var rand_evals: usize = 0;
    var router_derivation_ok: usize = 0;
    var router_derivation_checked: usize = 0;

    // secondary metric: ranked multi-shot evals-to-solve
    var router_shots_evals: usize = 0;
    var fb_shots_evals: usize = 0;
    var rand_shots_evals: usize = 0;

    try out.print("=== Headline: 3 arms on TEST (n={d}) ===\n", .{test_idx.items.len});
    try out.print("{s:<24} {s:>10} {s:>8} {s:>10} {s:>8} {s:>10}\n", .{ "target", "true", "router", "fixed", "random", "notes" });

    for (test_idx.items) |tix| {
        const r = recs.items[tix];
        const pred_router = knnPredict(recs.items, trainval.items, st_tv, r.desc, best_k);
        const pred_fb = fixedbest_family;
        const pred_rand: Family = @enumFromInt(rrand.int(u2) % 3);

        const router_hit = pred_router == r.label;
        const fb_hit = pred_fb == r.label;
        const rand_hit = pred_rand == r.label;
        if (router_hit) router_solves += 1;
        if (fb_hit) fb_solves += 1;
        if (rand_hit) rand_solves += 1;
        router_evals += evalCostOf(pred_router, EVAL_BASE, EVAL_GF2, EVAL_SPEC);
        fb_evals += evalCostOf(pred_fb, EVAL_BASE, EVAL_GF2, EVAL_SPEC);
        rand_evals += evalCostOf(pred_rand, EVAL_BASE, EVAL_GF2, EVAL_SPEC);

        // multi-shot: try predicted family first; if wrong, try the other two
        // in a fixed fallback order (base, gf2_joint, spectral_acc minus the
        // one already tried), summing costs until hitting the true label.
        router_shots_evals += multiShotCost(pred_router, r.label, EVAL_BASE, EVAL_GF2, EVAL_SPEC);
        fb_shots_evals += multiShotCost(pred_fb, r.label, EVAL_BASE, EVAL_GF2, EVAL_SPEC);
        rand_shots_evals += multiShotCost(pred_rand, r.label, EVAL_BASE, EVAL_GF2, EVAL_SPEC);

        var note_buf: [64]u8 = undefined;
        var note: []const u8 = "";
        if (router_hit) {
            router_derivation_checked += 1;
            const ok = derivationCheckOk(recs.items[tix]);
            if (ok) router_derivation_ok += 1;
            note = std.fmt.bufPrint(&note_buf, "deriv={s}", .{if (ok) "OK" else "FAIL"}) catch "";
        }
        try out.print("{s:<24} {s:>10} {s:>8} {s:>10} {s:>8} {s:>10}\n", .{ r.name, familyName(r.label), if (router_hit) "HIT" else "miss", familyName(pred_fb), if (rand_hit) "HIT" else "miss", note });

        try cw.print("test,{s},{s},{s}," ++ "{d:.4}," ** 12 ++ "{d:.4},{s},{s},{s},{d},{d},{d},{s}\n", .{
            r.name, r.construct_tag, familyName(r.label),
            r.base_acc, r.gf2_acc, r.spec_acc,
            r.desc[0], r.desc[1], r.desc[2], r.desc[3], r.desc[4], r.desc[5], r.desc[6], r.desc[7], r.desc[8], r.desc[9],
            familyName(pred_router), familyName(pred_fb), familyName(pred_rand),
            @as(u8, if (router_hit) 1 else 0), @as(u8, if (fb_hit) 1 else 0), @as(u8, if (rand_hit) 1 else 0),
            note,
        });
    }

    // also dump train/val rows for the record (router_pred..notes left blank:
    // 7 trailing empty fields)
    for ([_]struct { sp: []const usize, tag: []const u8 }{ .{ .sp = train_idx.items, .tag = "train" }, .{ .sp = val_idx.items, .tag = "val" } }) |grp| {
        for (grp.sp) |ix| {
            const r = recs.items[ix];
            try cw.print("{s},{s},{s},{s}," ++ "{d:.4}," ** 12 ++ "{d:.4}" ++ ",,,,,,,\n", .{
                grp.tag, r.name, r.construct_tag, familyName(r.label),
                r.base_acc, r.gf2_acc, r.spec_acc,
                r.desc[0], r.desc[1], r.desc[2], r.desc[3], r.desc[4], r.desc[5], r.desc[6], r.desc[7], r.desc[8], r.desc[9],
            });
        }
    }

    const ntest: f64 = @floatFromInt(@max(1, test_idx.items.len));
    try out.print("\n{s:<16} {s:>8} {s:>10} {s:>16}\n", .{ "arm", "solves", "solve_rate", "evals(single-shot)" });
    try out.print("{s:<16} {d:>8} {d:>10.3} {d:>16}\n", .{ "router", router_solves, @as(f64, @floatFromInt(router_solves)) / ntest, router_evals });
    try out.print("{s:<16} {d:>8} {d:>10.3} {d:>16}\n", .{ "fixed-best", fb_solves, @as(f64, @floatFromInt(fb_solves)) / ntest, fb_evals });
    try out.print("{s:<16} {d:>8} {d:>10.3} {d:>16}\n", .{ "random", rand_solves, @as(f64, @floatFromInt(rand_solves)) / ntest, rand_evals });
    try out.print("\nSecondary (multi-shot, ranked-order evals-to-solve, sums to full battery since union of 3 arms solves all TEST targets by construction):\n", .{});
    try out.print("{s:<16} {d:>16}\n", .{ "router", router_shots_evals });
    try out.print("{s:<16} {d:>16}\n", .{ "fixed-best-order", fb_shots_evals });
    try out.print("{s:<16} {d:>16}\n", .{ "random-order", rand_shots_evals });

    try out.print("\nFixed-best family (majority in TRAIN+VAL): {s}\n", .{familyName(fixedbest_family)});
    try out.print("Router derivation-chain honesty check: {d}/{d} correct-and-solving router predictions independently verified.\n", .{ router_derivation_ok, router_derivation_checked });

    const elapsed_s = @as(f64, @floatFromInt(timer.read())) / 1e9;
    try out.print("\nWall clock: {d:.1}s\n", .{elapsed_s});

    try cw3.print("key,value\n", .{});
    try cw3.print("router_solves,{d}\n", .{router_solves});
    try cw3.print("fixedbest_solves,{d}\n", .{fb_solves});
    try cw3.print("random_solves,{d}\n", .{rand_solves});
    try cw3.print("n_test,{d}\n", .{test_idx.items.len});
    try cw3.print("n_train,{d}\n", .{train_idx.items.len});
    try cw3.print("n_val,{d}\n", .{val_idx.items.len});
    try cw3.print("router_evals_singleshot,{d}\n", .{router_evals});
    try cw3.print("fixedbest_evals_singleshot,{d}\n", .{fb_evals});
    try cw3.print("random_evals_singleshot,{d}\n", .{rand_evals});
    try cw3.print("router_evals_multishot,{d}\n", .{router_shots_evals});
    try cw3.print("fixedbest_evals_multishot,{d}\n", .{fb_shots_evals});
    try cw3.print("random_evals_multishot,{d}\n", .{rand_shots_evals});
    try cw3.print("fixedbest_family,{s}\n", .{familyName(fixedbest_family)});
    try cw3.print("chosen_k,{d}\n", .{best_k});
    try cw3.print("router_derivation_ok,{d}\n", .{router_derivation_ok});
    try cw3.print("router_derivation_checked,{d}\n", .{router_derivation_checked});
    try cw3.print("n_excluded_unsolved,{d}\n", .{n_excluded});
    try cw3.print("n_overlap_multi_arm,{d}\n", .{n_overlap});
    try cw3.print("min_leakage_dist2,{d:.4}\n", .{min_dist_overall});
    try cw3.print("elapsed_s,{d:.1}\n", .{elapsed_s});

    var csv_final = std.ArrayList(u8).init(alloc);
    try csv_final.appendSlice("# BLOCK 1: per-target rows (train/val/test)\n");
    try csv_final.appendSlice(csv_block1.items);
    try csv_final.appendSlice("\n# BLOCK 2: sample-complexity curve (VAL accuracy)\n");
    try csv_final.appendSlice(csv_block2.items);
    try csv_final.appendSlice("\n# BLOCK 3: summary\n");
    try csv_final.appendSlice(csv_block3.items);

    const csv_path = "results/target_router_2026_07_11.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    try cf.writeAll(csv_final.items);
    try out.print("CSV -> {s}\n", .{csv_path});
}

fn multiShotCost(first: Family, true_label: Family, eb: usize, eg: usize, es: usize) usize {
    if (first == true_label) return evalCostOf(first, eb, eg, es);
    // try the remaining two in a fixed fallback order
    const order = [_]Family{ .base, .gf2_joint, .spectral_acc };
    var cost = evalCostOf(first, eb, eg, es);
    for (order) |f| {
        if (f == first) continue;
        cost += evalCostOf(f, eb, eg, es);
        if (f == true_label) return cost;
    }
    return cost;
}

fn recoveredLb(sol: u64) u8 {
    var lb: u8 = 0;
    for (0..NCELL) |i| {
        if ((sol & (@as(u64, 1) << @intCast(28 + i))) != 0) lb |= (@as(u8, 1) << @intCast(i));
    }
    return lb;
}

fn recoveredCmp(sol: u64) u32 {
    var cmp: u32 = 0;
    for (0..NPAIR) |p| {
        if ((sol & (@as(u64, 1) << @intCast(p))) != 0) cmp |= (@as(u32, 1) << @intCast(p));
    }
    return cmp;
}

const ALL28: u32 = (1 << NPAIR) - 1;

/// Independent recompute: for every family the router got right, verify the
/// recovered coefficients/statistic byte-exactly match the target's own
/// construction parameters (not just "the arm's accuracy cleared 0.90").
fn derivationCheckOk(r: TargetRecord) bool {
    return switch (r.label) {
        .gf2_joint => blk: {
            if (r.kindtag == .xor_extra) break :blk recoveredLb(r.gf2_sol) == r.mask;
            if (r.kindtag == .cmp_subset) break :blk recoveredCmp(r.gf2_sol) == r.pairs_mask;
            if (r.kindtag == .batC) {
                const spec = bc.BATTERY_C[r.bc_idx];
                if (spec.e2_spec) |sp| {
                    if (sp.kind == .xor_cells or sp.kind == .parity_xor) break :blk recoveredLb(r.gf2_sol) == sp.mask;
                }
                if (spec.composed) |ck| {
                    if (ck == .inversion_parity) break :blk recoveredCmp(r.gf2_sol) == ALL28;
                }
                break :blk r.gf2_acc >= COVER;
            }
            break :blk r.gf2_acc >= COVER;
        },
        .spectral_acc => blk: {
            if (r.kindtag == .spectral_extra) break :blk r.spec_via_stat == r.stat_kind;
            if (r.kindtag == .batD) break :blk r.spec_via_stat == 3; // battery D's own statistic is count(cells>=3)
            break :blk r.spec_acc >= COVER;
        },
        .base => r.base_acc >= COVER,
    };
}
