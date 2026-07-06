//! Independent coverage/certify implementation for T8-AG-16 cross-audit.
//! Duplicates unified_invention math with separate code path.

const std = @import("std");
const ui = @import("unified_invention.zig");

const COVER: f64 = ui.COVER_THRESHOLD;
const R2_MAX: f64 = 0.40;

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

fn fillMatrix(X: [][]f64, grid: []const [8]u8, lib: []const ui.Feature) void {
    const k = lib.len;
    for (0..ui.NSAMP) |s| {
        for (0..k) |c| X[s][c] = ui.evalFeaturePublic(lib[c], grid[s]);
    }
    for (0..k) |c| {
        var mu: f64 = 0;
        for (0..ui.NTR) |s| mu += X[s][c];
        mu /= @floatFromInt(ui.NTR);
        var sd: f64 = 0;
        for (0..ui.NTR) |s| sd += (X[s][c] - mu) * (X[s][c] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(ui.NTR))));
        for (0..ui.NSAMP) |s| X[s][c] = (X[s][c] - mu) / sd;
    }
}

fn trainLogistic(X: []const []f64, Y: []const f64, dim: usize, w: []f64) void {
    @memset(w[0 .. dim + 1], 0);
    for (0..150) |_| {
        for (0..ui.NTR) |s| {
            var z = w[dim];
            for (0..dim) |j| z += w[j] * X[s][j];
            const err = sigmoid(z) - Y[s];
            for (0..dim) |j| w[j] -= 0.05 * err * X[s][j];
            w[dim] -= 0.05 * err;
        }
    }
}

fn heldOutAcc(X: []const []f64, Y: []const f64, w: []const f64, dim: usize) f64 {
    var ok: usize = 0;
    for (ui.NVA..ui.NSAMP) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        if ((z >= 0) == (Y[s] > 0.5)) ok += 1;
    }
    return @as(f64, @floatFromInt(ok)) / @as(f64, @floatFromInt(ui.NSAMP - ui.NVA));
}

pub fn measureCoverageAudit(X: [][]f64, grid: []const [8]u8, lib: []const ui.Feature, Y: []const f64, w: []f64) f64 {
    fillMatrix(X, grid, lib);
    trainLogistic(X, Y, lib.len, w);
    return heldOutAcc(X, Y, w, lib.len);
}

fn reconR2Audit(X: []const []f64, t: []const f64, dim: usize, w: []f64) f64 {
    @memset(w[0 .. dim + 1], 0);
    for (0..400) |_| {
        for (0..ui.NTR) |s| {
            var z = w[dim];
            for (0..dim) |j| z += w[j] * X[s][j];
            const err = z - t[s];
            for (0..dim) |j| w[j] -= 0.01 * err * X[s][j];
            w[dim] -= 0.01 * err;
        }
    }
    var mu: f64 = 0;
    for (ui.NVA..ui.NSAMP) |s| mu += t[s];
    mu /= @floatFromInt(ui.NSAMP - ui.NVA);
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (ui.NVA..ui.NSAMP) |s| {
        var z = w[dim];
        for (0..dim) |j| z += w[j] * X[s][j];
        ssr += (t[s] - z) * (t[s] - z);
        sst += (t[s] - mu) * (t[s] - mu);
    }
    return 1.0 - ssr / @max(1e-9, sst);
}

pub fn certifyAudit(
    X: [][]f64,
    grid: []const [8]u8,
    lib: []const ui.Feature,
    cand: ui.Feature,
    Y: []const f64,
    scratch: []f64,
    w: []f64,
) ui.CertResult {
    const cov_before = measureCoverageAudit(X, grid, lib, Y, w);
    var aug: [32]ui.Feature = undefined;
    @memcpy(aug[0..lib.len], lib);
    aug[lib.len] = cand;
    const cov_after = measureCoverageAudit(X, grid, aug[0 .. lib.len + 1], Y, w);
    for (0..ui.NSAMP) |s| scratch[s] = ui.evalFeaturePublic(cand, grid[s]);
    fillMatrix(X, grid, lib);
    const r2 = reconR2Audit(X, scratch, lib.len, w);
    const escape = cov_after >= COVER and cov_before < COVER;
    const certified = escape and r2 < R2_MAX;
    return .{
        .ok = certified,
        .cov_before = cov_before,
        .cov_after = cov_after,
        .r2 = r2,
    };
}

pub fn coverageAgrees(a: f64, b: f64) bool {
    return @abs(a - b) < 1e-9;
}

pub fn certifyAgrees(a: ui.CertResult, b: ui.CertResult) bool {
    return a.ok == b.ok and coverageAgrees(a.cov_before, b.cov_before) and coverageAgrees(a.cov_after, b.cov_after) and @abs(a.r2 - b.r2) < 1e-6;
}