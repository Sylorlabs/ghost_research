//! E26-style equivalence tax — promotion gate for Tier 5.
//! Greedy forward selection over expanded basis; if test ≥ COVER without the
//! candidate being necessary, the escape is basis-remix (block promote).

const std = @import("std");
const ui = @import("unified_invention.zig");

pub const COVER = ui.COVER_THRESHOLD;
pub const TaxStats = struct {
    checked: usize = 0,
    remix_blocked: usize = 0,
    novel_allowed: usize = 0,

    pub fn novelRate(self: TaxStats) f64 {
        if (self.checked == 0) return 0;
        return @as(f64, @floatFromInt(self.novel_allowed)) / @as(f64, @floatFromInt(self.checked));
    }
};

pub var strict_enabled: bool = false;
pub var stats: TaxStats = .{};

const MAX_BUDGET: usize = 6;
const PREFILTER_TOP: usize = 64;
const MAX_CANDS: usize = 512;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn fitLogit(X: []const []f64, Y: []const f64, dim: usize, epochs: usize, lr: f64, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..epochs) |_| for (0..ui.NTR) |s| {
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

fn corrTrain(a: []const f64, b: []const f64) f64 {
    var ma: f64 = 0;
    var mb: f64 = 0;
    for (0..ui.NTR) |s| {
        ma += a[s];
        mb += b[s];
    }
    ma /= @floatFromInt(ui.NTR);
    mb /= @floatFromInt(ui.NTR);
    var num: f64 = 0;
    var da: f64 = 0;
    var db: f64 = 0;
    for (0..ui.NTR) |s| {
        const xa = a[s] - ma;
        const xb = b[s] - mb;
        num += xa * xb;
        da += xa * xa;
        db += xb * xb;
    }
    return num / @max(1e-9, @sqrt(da * db));
}

fn containsFeature(list: []const ui.Feature, f: ui.Feature) bool {
    for (list) |x| if (ui.featuresEqual(x, f)) return true;
    return false;
}

fn buildStaticCandidates(grid: []const [8]u8, Y: []const f64, lib: []const ui.Feature, scratch: []f64, out: []ui.Feature, n: *usize) void {
    n.* = 0;
    var mm: u16 = 1;
    while (mm < 256 and n.* < MAX_CANDS) : (mm += 1) {
        const mask: u8 = @intCast(mm);
        const pc = @popCount(mask);
        if (pc < 1 or pc > 4) continue;
        const f: ui.Feature = .{ .monomial = mask };
        if (containsFeature(lib, f)) continue;
        out[n.*] = f;
        n.* += 1;
    }
    for (0..8) |i| for (i + 1..8) |j| {
        if (n.* >= MAX_CANDS) return;
        const f: ui.Feature = .{ .pair_relation = .{ .i = i, .j = j } };
        if (containsFeature(lib, f)) continue;
        out[n.*] = f;
        n.* += 1;
    };
    const wal_scores = struct {
        S: u8,
        c: f64,
    };
    var wtop: [32]wal_scores = undefined;
    for (&wtop) |*w| w.* = .{ .S = 0, .c = -2 };
    var S: u16 = 1;
    while (S < 256) : (S += 1) {
        const mask: u8 = @intCast(S);
        const f: ui.Feature = .{ .walsh = mask };
        if (containsFeature(lib, f)) continue;
        for (0..grid.len) |s| scratch[s] = ui.evalFeaturePublic(f, grid[s]);
        const c = @abs(corrTrain(scratch, Y));
        if (c <= wtop[31].c) continue;
        wtop[31] = .{ .S = mask, .c = c };
        std.sort.pdq(wal_scores, &wtop, {}, struct {
            fn lt(_: void, a: wal_scores, b: wal_scores) bool {
                return a.c > b.c;
            }
        }.lt);
    }
    for (wtop) |w| {
        if (w.c < 0 or n.* >= MAX_CANDS) break;
        out[n.*] = .{ .walsh = w.S };
        n.* += 1;
    }
    const primes = [_]usize{ 2, 3, 5, 7, 11, 13 };
    for (primes) |p| {
        if (n.* >= MAX_CANDS) return;
        const fs: ui.Feature = .{ .world_sum_mod = p };
        if (!containsFeature(lib, fs)) {
            out[n.*] = fs;
            n.* += 1;
        }
        if (n.* >= MAX_CANDS) return;
        const fg: ui.Feature = .{ .world_sign_mod = p };
        if (!containsFeature(lib, fg)) {
            out[n.*] = fg;
            n.* += 1;
        }
    }
}

fn greedyTestAcc(
    grid: []const [8]u8,
    Y: []const f64,
    lib: []const ui.Feature,
    static: []const ui.Feature,
    _: []f64,
) f64 {
    const n_lib = lib.len;
    const n_static = static.len;
    const n_total = n_lib + n_static;
    if (n_total == 0) return 0;

    var cols: [MAX_CANDS + 32][]f64 = undefined;
    var col_store: [MAX_CANDS + 32][ui.NSAMP]f64 = undefined;
    for (0..n_lib) |i| {
        for (0..grid.len) |s| col_store[i][s] = ui.evalFeaturePublic(lib[i], grid[s]);
        cols[i] = col_store[i][0..];
    }
    for (0..n_static) |i| {
        const j = n_lib + i;
        for (0..grid.len) |s| col_store[j][s] = ui.evalFeaturePublic(static[i], grid[s]);
        cols[j] = col_store[j][0..];
    }

    var selected: [MAX_BUDGET]usize = undefined;
    var n_sel: usize = 0;
    var w: [MAX_BUDGET + 1]f64 = undefined;
    var Xtr: [ui.NSAMP][MAX_BUDGET]f64 = undefined;
    var Xte: [ui.NSAMP][MAX_BUDGET]f64 = undefined;
    var Xtr_rows: [ui.NSAMP][]f64 = undefined;
    var Xte_rows: [ui.NSAMP][]f64 = undefined;

    var best_test: f64 = 0;

    for (0..MAX_BUDGET) |_| {
        var round_best_val: f64 = -1;
        var round_best_idx: ?usize = null;

        const CandScore = struct { idx: usize, corr: f64 };
        var top: [PREFILTER_TOP]CandScore = undefined;
        for (&top) |*t| t.* = .{ .idx = 0, .corr = -2 };
        for (0..n_total) |gi| {
            var used = false;
            for (selected[0..n_sel]) |sel| {
                if (sel == gi) used = true;
            }
            if (used) continue;
            const c = @abs(corrTrain(cols[gi], Y));
            if (c <= top[top.len - 1].corr) continue;
            top[top.len - 1] = .{ .idx = gi, .corr = c };
            std.sort.pdq(CandScore, &top, {}, struct {
                fn lt(_: void, a: CandScore, b: CandScore) bool {
                    return a.corr > b.corr;
                }
            }.lt);
        }

        for (top) |cs| {
            if (cs.corr < 0) break;
            const dim = n_sel + 1;
            for (0..ui.NSAMP) |s| {
                for (0..n_sel) |j| Xtr[s][j] = cols[selected[j]][s];
                Xtr[s][n_sel] = cols[cs.idx][s];
                Xtr_rows[s] = Xtr[s][0..dim];
            }
            fitLogit(&Xtr_rows, Y, dim, 60, 0.06, &w);
            const v = accLogit(&Xtr_rows, Y, &w, dim, ui.NTR, ui.NVA);
            if (v > round_best_val) {
                round_best_val = v;
                round_best_idx = cs.idx;
            }
        }

        const pick = round_best_idx orelse break;
        selected[n_sel] = pick;
        n_sel += 1;

        const dim = n_sel;
        for (0..ui.NSAMP) |s| {
            for (0..dim) |j| Xtr[s][j] = cols[selected[j]][s];
            Xtr_rows[s] = Xtr[s][0..dim];
        }
        for (0..ui.NSAMP) |s| {
            for (0..dim) |j| Xte[s][j] = cols[selected[j]][s];
        }

        fitLogit(&Xtr_rows, Y, dim, 120, 0.05, &w);
        for (0..dim) |j| {
            var mu: f64 = 0;
            for (0..ui.NTR) |s| mu += Xtr[s][j];
            mu /= @floatFromInt(ui.NTR);
            var sd: f64 = 0;
            for (0..ui.NTR) |s| sd += (Xtr[s][j] - mu) * (Xtr[s][j] - mu);
            sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(ui.NTR))));
            for (0..ui.NSAMP) |s| Xte[s][j] = (Xte[s][j] - mu) / sd;
        }
        for (0..ui.NSAMP) |s| Xte_rows[s] = Xte[s][0..dim];
        best_test = accLogit(&Xte_rows, Y, &w, dim, 0, ui.NSAMP);
        if (best_test >= COVER) break;
    }
    return best_test;
}

/// Returns true if greedy expanded basis already reaches COVER (candidate is remix).
pub fn isBasisRemix(
    grid: []const [8]u8,
    lib: []const ui.Feature,
    cand: ui.Feature,
    Y: []const f64,
) bool {
    _ = cand;
    var scratch: [ui.NSAMP]f64 = undefined;
    var static: [MAX_CANDS]ui.Feature = undefined;
    var n_static: usize = 0;
    buildStaticCandidates(grid, Y, lib, &scratch, &static, &n_static);
    const test_acc = greedyTestAcc(grid, Y, lib, static[0..n_static], &scratch);
    return test_acc >= COVER;
}

pub fn gatePromote(
    grid: []const [8]u8,
    lib: []const ui.Feature,
    cand: ui.Feature,
    Y: []const f64,
    cert_ok: bool,
) bool {
    if (!cert_ok) return false;
    if (!strict_enabled) return true;
    stats.checked += 1;
    if (isBasisRemix(grid, lib, cand, Y)) {
        stats.remix_blocked += 1;
        return false;
    }
    stats.novel_allowed += 1;
    return true;
}

pub fn resetStats() void {
    stats = .{};
}