//! Shared operator-menu primitives — spectral (count-Fourier) and Walsh (Boolean Fourier).
//! Used by operator_menu.zig (standalone benchmark) and inner_forge.zig (escape on saturation).

const std = @import("std");

pub const NCELL: usize = 8;
pub const THRESH: u8 = 3;
pub const DOM: usize = 1 << NCELL;

pub const Operator = enum { spectral, walsh };
pub const op_name = [_][]const u8{ "spectral", "walsh" };

pub fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

pub fn accLogit(feat: []const f64, Y: []const f64, ntr: usize, lo: usize, hi: usize) f64 {
    var w: [2]f64 = .{ 0.0, 0.0 };
    for (0..80) |_| for (0..ntr) |s| {
        const e = sigmoid(w[0] * feat[s] + w[1]) - Y[s];
        w[0] -= 0.1 * e * feat[s];
        w[1] -= 0.1 * e;
    };
    var c: usize = 0;
    for (lo..hi) |s| {
        if ((w[0] * feat[s] + w[1] >= 0) == (Y[s] > 0.5)) c += 1;
    }
    return @as(f64, @floatFromInt(c)) / @as(f64, @floatFromInt(hi - lo));
}

pub fn signPattern(g: [NCELL]u8) u8 {
    var p: u8 = 0;
    for (0..NCELL) |i| {
        if (g[i] >= THRESH) p |= @as(u8, 1) << @intCast(i);
    }
    return p;
}

pub fn chi(S: u8, p: u8) f64 {
    const neg = @popCount(S & ~p);
    return if (neg & 1 == 0) 1.0 else -1.0;
}

pub fn countGE(g: [NCELL]u8) f64 {
    var c: usize = 0;
    for (g) |v| if (v >= THRESH) {
        c += 1;
    };
    return @floatFromInt(c);
}

/// Spectral peak on count signal — returns feature vector, validation/test acc, discovered ω.
pub fn discoverSpectral(
    grid: []const [NCELL]u8,
    Y: []const f64,
    feat_out: []f64,
    ntr: usize,
    nva: usize,
    nsamp: usize,
) struct { val: f64, tst: f64, omega: f64 } {
    const CMAX = NCELL + 1;
    var fsum = [_]f64{0} ** CMAX;
    var ncnt = [_]f64{0} ** CMAX;
    for (0..ntr) |s| {
        const c: usize = @intFromFloat(countGE(grid[s]));
        fsum[c] += Y[s];
        ncnt[c] += 1;
    }
    var f = [_]f64{0} ** CMAX;
    var fbar: f64 = 0;
    var ntot: f64 = 0;
    for (0..CMAX) |c| {
        if (ncnt[c] > 0) f[c] = fsum[c] / ncnt[c];
        fbar += fsum[c];
        ntot += ncnt[c];
    }
    fbar /= ntot;

    const NF = 200;
    var peak_pw: f64 = -1;
    var peak_w: f64 = 0;
    var i: usize = 1;
    while (i <= NF) : (i += 1) {
        const w = std.math.pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(NF));
        var re: f64 = 0;
        var im: f64 = 0;
        for (0..CMAX) |c| {
            if (ncnt[c] == 0) continue;
            const amp = ncnt[c] * (f[c] - fbar);
            const cc: f64 = @floatFromInt(c);
            re += amp * @cos(w * cc);
            im += amp * @sin(w * cc);
        }
        const pw = re * re + im * im;
        if (pw > peak_pw) {
            peak_pw = pw;
            peak_w = w;
        }
    }
    for (0..nsamp) |s| feat_out[s] = @cos(peak_w * countGE(grid[s]));
    return .{
        .val = accLogit(feat_out, Y, ntr, ntr, nva),
        .tst = accLogit(feat_out, Y, ntr, nva, nsamp),
        .omega = peak_w,
    };
}

/// Walsh argmax |f̂(S)| — returns feature vector, validation/test acc, best subset S.
pub fn discoverWalsh(
    grid: []const [NCELL]u8,
    Y: []const f64,
    feat_out: []f64,
    ntr: usize,
    nva: usize,
    nsamp: usize,
) struct { val: f64, tst: f64, bestS: u8 } {
    var est = [_]f64{0} ** DOM;
    for (0..ntr) |s| {
        const p = signPattern(grid[s]);
        const g: f64 = if (Y[s] > 0.5) @as(f64, -1.0) else @as(f64, 1.0);
        for (0..DOM) |S| est[S] += g * chi(@intCast(S), p);
    }
    var best_abs: f64 = -1;
    var bestS: u8 = 0;
    for (0..DOM) |S| {
        const v = @abs(est[S]) / @as(f64, @floatFromInt(ntr));
        if (v > best_abs) {
            best_abs = v;
            bestS = @intCast(S);
        }
    }
    for (0..nsamp) |s| {
        const p = signPattern(grid[s]);
        feat_out[s] = chi(bestS, p);
    }
    return .{
        .val = accLogit(feat_out, Y, ntr, ntr, nva),
        .tst = accLogit(feat_out, Y, ntr, nva, nsamp),
        .bestS = bestS,
    };
}

pub const PromotedOp = struct {
    kind: Operator,
    omega: f64 = 0,
    walsh_s: u8 = 0,

    pub fn eval(self: PromotedOp, g: [NCELL]u8) f64 {
        return switch (self.kind) {
            .spectral => @cos(self.omega * countGE(g)),
            .walsh => chi(self.walsh_s, signPattern(g)),
        };
    }
};

/// Run spectral + Walsh menu for one target; pick argmax validation accuracy.
pub fn runMenu(
    grid: []const [NCELL]u8,
    Y: []const f64,
    feat_scratch: []f64,
    ntr: usize,
    nva: usize,
    nsamp: usize,
) struct {
    winner: Operator,
    val: f64,
    tst: f64,
    promoted: PromotedOp,
} {
    const spec = discoverSpectral(grid, Y, feat_scratch, ntr, nva, nsamp);
    const wal = discoverWalsh(grid, Y, feat_scratch, ntr, nva, nsamp);
    const accs = [_]f64{ spec.val, wal.val };
    const tests = [_]f64{ spec.tst, wal.tst };
    var best: usize = 0;
    for (1..2) |k| {
        if (accs[k] > accs[best]) best = k;
    }
    const winner: Operator = @enumFromInt(best);
    const promoted: PromotedOp = switch (winner) {
        .spectral => .{ .kind = .spectral, .omega = spec.omega },
        .walsh => .{ .kind = .walsh, .walsh_s = wal.bestS },
    };
    return .{
        .winner = winner,
        .val = accs[best],
        .tst = tests[best],
        .promoted = promoted,
    };
}

pub fn fmtWalshSet(buf: []u8, S: u8) []const u8 {
    var w: usize = 0;
    buf[w] = '{';
    w += 1;
    var first = true;
    for (0..NCELL) |i| {
        if (S & (@as(u8, 1) << @intCast(i)) != 0) {
            if (!first) {
                buf[w] = ',';
                w += 1;
            }
            buf[w] = '0' + @as(u8, @intCast(i));
            w += 1;
            first = false;
        }
    }
    buf[w] = '}';
    w += 1;
    return buf[0..w];
}