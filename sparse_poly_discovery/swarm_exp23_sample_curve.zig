//! EXP-23 (F43): hidden non-salient feature — minimum failure-labels for supervised recovery.
//!
//! Task from feature_discovery.md Level 3: cell 0 is the true safety direction e_0;
//! cells 8-15 are a loud correlated decoy block. PCA (unsupervised) is misled (cosine≈0);
//! supervised one-sided credit-assignment recovers e_0 with enough failure labels.
//!
//! Sweep labeled failure counts: {0, 10, 50, 200, 1000}.
//! At each point: PCA cosine (0 labels) vs supervised mean(fail)-mean(safe) cosine.
//!
//! Run: zig build swarm-exp23

const std = @import("std");

const POOL: usize = 50_000;
const LABEL_COUNTS = [_]usize{ 0, 10, 50, 200, 1000 };
const N_SEEDS: usize = 12;
const RECOVERY_THRESH: f64 = 0.90;
const CHANCE_COS: f64 = 0.25; // ~1/sqrt(16) for random unit vector vs e_0

fn cosToE0(v: [16]f64) f64 {
    var n: f64 = 0;
    for (v) |x| n += x * x;
    if (n < 1e-12) return 0;
    return @abs(v[0]) / @sqrt(n);
}

fn topPCA(X: [][16]f64) f64 {
    const samples = X.len;
    var mean: [16]f64 = [_]f64{0} ** 16;
    for (X) |g| {
        for (0..16) |i| mean[i] += g[i];
    }
    for (0..16) |i| mean[i] /= @floatFromInt(samples);

    var cov: [16][16]f64 = undefined;
    for (&cov) |*row| row.* = [_]f64{0} ** 16;
    for (X) |g| {
        for (0..16) |i| {
            for (0..16) |j| {
                cov[i][j] += (g[i] - mean[i]) * (g[j] - mean[j]);
            }
        }
    }

    var v: [16]f64 = [_]f64{1.0} ** 16;
    for (0..60) |_| {
        var nv: [16]f64 = [_]f64{0} ** 16;
        for (0..16) |i| {
            for (0..16) |j| nv[i] += cov[i][j] * v[j];
        }
        var nn: f64 = 0;
        for (nv) |x| nn += x * x;
        nn = @sqrt(nn);
        if (nn < 1e-12) break;
        for (0..16) |i| v[i] = nv[i] / nn;
    }
    return cosToE0(v);
}

fn supervisedDir(X: [][16]f64, fail_idx: []const usize) [16]f64 {
    var mf: [16]f64 = [_]f64{0} ** 16;
    var ms: [16]f64 = [_]f64{0} ** 16;
    var nf: f64 = 0;
    var nsf: f64 = 0;

    var is_fail = [_]bool{false} ** POOL;
    for (fail_idx) |i| is_fail[i] = true;

    for (X, 0..) |g, s| {
        if (is_fail[s]) {
            for (0..16) |i| mf[i] += g[i];
            nf += 1;
        } else {
            for (0..16) |i| ms[i] += g[i];
            nsf += 1;
        }
    }
    var d: [16]f64 = undefined;
    for (0..16) |i| d[i] = (if (nf > 0) mf[i] / nf else 0) - (if (nsf > 0) ms[i] / nsf else 0);
    return d;
}

fn generatePool(r: std.Random, X: [][16]f64, lab1: []bool, fail_list: *std.ArrayList(usize)) void {
    fail_list.clearRetainingCapacity();
    for (X, 0..) |*g, s| {
        const decoy: f64 = @floatFromInt(r.intRangeAtMost(i32, 0, 40));
        g.*[0] = @floatFromInt(r.intRangeAtMost(i32, 0, 6));
        for (1..8) |i| g[i] = @floatFromInt(r.intRangeAtMost(i32, 0, 2));
        for (8..16) |i| g[i] = decoy + @as(f64, @floatFromInt(r.intRangeAtMost(i32, 0, 2)));
        lab1[s] = g[0] > 4.0;
        if (lab1[s]) fail_list.append(s) catch {};
    }
}

fn subsampleFailures(r: std.Random, fail_list: []const usize, n_labels: usize, buf: []usize) void {
    const n = @min(n_labels, fail_list.len);
    // Fisher-Yates partial shuffle on indices into fail_list
    for (0..n) |i| buf[i] = fail_list[i];
    var i: usize = n;
    while (i < fail_list.len) : (i += 1) {
        const j = r.intRangeLessThan(usize, 0, i + 1);
        if (j < n) buf[j] = fail_list[i];
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const X = try alloc.alloc([16]f64, POOL);
    defer alloc.free(X);
    const lab1 = try alloc.alloc(bool, POOL);
    defer alloc.free(lab1);
    var fail_list = try std.ArrayList(usize).initCapacity(alloc, POOL / 3);
    defer fail_list.deinit();

    var pick_buf = try alloc.alloc(usize, 1000);
    defer alloc.free(pick_buf);

    // Accumulators: [label_count][seed] not needed — mean over seeds per count
    var pca_acc = [_]f64{0} ** LABEL_COUNTS.len;
    var sup_acc = [_]f64{0} ** LABEL_COUNTS.len;

    try out.print("=== EXP-23 (F43): failure-label sample-complexity curve ===\n\n", .{});
    try out.print("Task: hidden e_0 amid loud decoy block (feature_discovery.md Level 3)\n", .{});
    try out.print("Pool: {d} samples; one-sided label (cell0 > 4); {d} seeds\n", .{ POOL, N_SEEDS });
    try out.print("Recovery threshold: cosine >= {d:.2} (full recovery reference: 0.999)\n\n", .{RECOVERY_THRESH});

    var total_fails: usize = 0;
    for (0..N_SEEDS) |s| {
        var prng = std.Random.DefaultPrng.init(0xF4300000 +% @as(u64, s) *% 0x9E37);
        const r = prng.random();
        generatePool(r, X, lab1, &fail_list);
        if (s == 0) total_fails = fail_list.items.len;

        const pca_cos = topPCA(X);
        pca_acc[0] += pca_cos;
        // PCA is label-free; same for all label-count rows — record once
        for (LABEL_COUNTS, 0..) |n_lab, li| {
            if (n_lab == 0) {
                sup_acc[li] += 0; // no supervised at 0 labels
                continue;
            }
            subsampleFailures(r, fail_list.items, n_lab, pick_buf);
            const sup_cos = cosToE0(supervisedDir(X, pick_buf[0..@min(n_lab, fail_list.items.len)]));
            sup_acc[li] += sup_cos;
        }
    }

    try out.print("Failures in pool (seed 0): {d} / {d} ({d:.1}%)\n\n", .{
        total_fails, POOL, @as(f64, @floatFromInt(total_fails)) / @as(f64, @floatFromInt(POOL)) * 100.0,
    });
    try out.print("  n_fail_labels | PCA cosine | supervised cosine | recovered?\n", .{});
    try out.print("  --------------+------------+-------------------+-----------\n", .{});

    const pca_mean = pca_acc[0] / @as(f64, @floatFromInt(N_SEEDS));
    var phase_n: ?usize = null;
    var crossover_n: ?usize = null;

    for (LABEL_COUNTS, 0..) |n_lab, li| {
        if (n_lab == 0) {
            try out.print("  {d:>13} | {d:10.3} | {s:>17} | {s}\n", .{
                n_lab, pca_mean, "—", if (pca_mean >= RECOVERY_THRESH) "PCA only" else "PCA blind",
            });
        } else {
            const sup_mean = sup_acc[li] / @as(f64, @floatFromInt(N_SEEDS));
            const recovered = sup_mean >= RECOVERY_THRESH;
            try out.print("  {d:>13} | {d:10.3} | {d:17.3} | {s}\n", .{
                n_lab, pca_mean, sup_mean, if (recovered) "YES" else "no",
            });
            if (phase_n == null and recovered) phase_n = n_lab;
            if (crossover_n == null and sup_mean > pca_mean) crossover_n = n_lab;
        }
    }

    try out.print("\n=== VERDICT ===\n", .{});
    try out.print("  PCA (0 labels):           {d:.3}  (reference from feature_discovery.md: 0.000)\n", .{pca_mean});
    try out.print("  Chance baseline:          ~{d:.2}\n", .{CHANCE_COS});
    if (phase_n) |n| {
        try out.print("  Phase transition:         {d} failure labels (first n with cosine >= {d:.2})\n", .{ n, RECOVERY_THRESH });
    } else {
        try out.print("  Phase transition:         NOT reached by {d} labels\n", .{LABEL_COUNTS[LABEL_COUNTS.len - 1]});
    }
    if (crossover_n) |n| {
        try out.print("  PCA vs supervised cross:  {d} failure labels (supervised > PCA)\n", .{n});
    } else {
        try out.print("  PCA vs supervised cross:  never (PCA always >= supervised)\n", .{});
    }
    try out.print("\nDoc: docs/research/swarm_exp23_sample_curve.md\n", .{});
}