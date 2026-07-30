const std = @import("std");
const ss = @import("src/signal_survival.zig");
const safetensors = @import("src/safetensors.zig");

// User reframe (2026-06-14): we are DISK/FETCH-bound, compute is ~free (GPU 2-7x
// faster than disk read). So the format should be chosen by RATE-DISTORTION (fewest
// bits/weight at target quality), NOT by XNOR-kernel friendliness. "Beyond XOR" is
// allowed: a costlier-to-decode but smaller code is a net win (fewer bytes fetched
// = more speed AND less storage), as long as decode stays faster than the disk.
//
// This sweeps bitplanes (XNOR-native) vs Lloyd-Max scalar (beyond-XOR, adaptive
// k-means levels on the real weight distribution), on REAL experts, with honest
// overhead (per-256-block f32 scale = 0.125 b/w). Reports min bits/w at quality bars
// and the full-model GB + disk-bound aggregate tps each implies.

fn cosine(a: []const f32, b: []const f32) f64 {
    var dot: f64 = 0;
    var na: f64 = 0;
    var nb: f64 = 0;
    for (a, b) |x, y| {
        dot += @as(f64, x) * @as(f64, y);
        na += @as(f64, x) * @as(f64, x);
        nb += @as(f64, y) * @as(f64, y);
    }
    return dot / (@sqrt(na) * @sqrt(nb) + 1e-30);
}

// 1D Lloyd-Max (k-means) on values, N levels, ~25 iters. Returns reconstruction
// into `recon` (caller-owned, same len as vals) using per-256-block scale.
const BLK = 256;
fn lloydMaxCos(alloc: std.mem.Allocator, w: []const f32, levels_n: usize) !f64 {
    const recon = try alloc.alloc(f32, w.len);
    defer alloc.free(recon);
    // per-block scale (mean abs), normalize into tmp
    const norm = try alloc.alloc(f32, w.len);
    defer alloc.free(norm);
    const scale = try alloc.alloc(f32, (w.len + BLK - 1) / BLK);
    defer alloc.free(scale);
    var bi: usize = 0;
    var i: usize = 0;
    while (i < w.len) : (i += BLK) {
        const end = @min(i + BLK, w.len);
        var s: f64 = 0;
        for (w[i..end]) |v| s += @abs(v);
        const sc: f32 = @floatCast(s / @as(f64, @floatFromInt(end - i)) + 1e-12);
        scale[bi] = sc;
        for (i..end) |j| norm[j] = w[j] / sc;
        bi += 1;
    }
    // init levels at quantiles of |normal| spread, symmetric
    var lv = try alloc.alloc(f64, levels_n);
    defer alloc.free(lv);
    for (0..levels_n) |k| {
        const t = (@as(f64, @floatFromInt(k)) + 0.5) / @as(f64, @floatFromInt(levels_n));
        lv[k] = -2.5 + 5.0 * t; // spread across ~[-2.5,2.5]
    }
    // Lloyd iterations
    const sums = try alloc.alloc(f64, levels_n);
    defer alloc.free(sums);
    const cnts = try alloc.alloc(u64, levels_n);
    defer alloc.free(cnts);
    for (0..25) |_| {
        @memset(sums, 0);
        @memset(cnts, 0);
        for (norm) |x| {
            var best: usize = 0;
            var bd: f64 = std.math.inf(f64);
            for (lv, 0..) |c, k| {
                const d = (@as(f64, x) - c) * (@as(f64, x) - c);
                if (d < bd) {
                    bd = d;
                    best = k;
                }
            }
            sums[best] += x;
            cnts[best] += 1;
        }
        for (0..levels_n) |k| {
            if (cnts[k] > 0) lv[k] = sums[k] / @as(f64, @floatFromInt(cnts[k]));
        }
    }
    // quantize + reconstruct
    i = 0;
    bi = 0;
    while (i < w.len) : (i += BLK) {
        const end = @min(i + BLK, w.len);
        const sc = scale[bi];
        for (i..end) |j| {
            const x: f64 = norm[j];
            var best: usize = 0;
            var bd: f64 = std.math.inf(f64);
            for (lv, 0..) |c, k| {
                const d = (x - c) * (x - c);
                if (d < bd) {
                    bd = d;
                    best = k;
                }
            }
            recon[j] = @floatCast(lv[best] * @as(f64, sc));
        }
        bi += 1;
    }
    return cosine(recon, w);
}

fn fullGB(bits_per_w: f64) f64 {
    const total_w: f64 = 61.0 * 384.0 * 3.0 * 3072.0 * 7168.0;
    return total_w * bits_per_w / 8.0 / 1e9;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();
    const layer = 30;
    const st = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(layer + 2));
    defer st.deinit();

    try out.print("=== E24: rate-distortion frontier (real experts L{d}, disk-bound regime) ===\n", .{layer});
    try out.print("overhead: f32 scale per 256 weights = 0.125 b/w (both families). DISK 1.23 GB/s, B=512.\n\n", .{});

    const experts = [_]usize{ 0, 5, 100, 300 };
    const mats = [_]u8{ '1', '2', '3' };
    var nb: [128]u8 = undefined;

    // accumulators
    const Form = struct { name: []const u8, bpw: f64, cos: f64 };
    // bitplane P2/P3/P4 at block256 (XNOR-native): bpw = P*(1 + 32/256) = P*1.125
    // lloyd N=4/6/8/16: bpw = log2(N) + 0.125
    var bp = [_]f64{ 0, 0, 0 }; // P2,P3,P4 cos sums
    var lm = [_]f64{ 0, 0, 0, 0 }; // N=4,6,8,16 cos sums
    const lmN = [_]usize{ 4, 6, 8, 16 };
    var nm: usize = 0;

    for (experts) |e| {
        for (mats) |w| {
            const name = try std.fmt.bufPrint(&nb, "layers.{d}.ffn.experts.{d}.w{c}.weight", .{ layer, e, w });
            const m = (try ss.loadDequant(alloc, st, name)) orelse continue;
            defer alloc.free(m.data);
            ss.rotateRows(m, ss.hadamardChunkFor(m.cols));
            inline for (.{ 2, 3, 4 }, 0..) |P, idx| {
                const r = try ss.quantizeBitplanesRefit(alloc, m, BLK, P, 0);
                defer alloc.free(r.data);
                bp[idx] += cosine(r.data, m.data);
            }
            for (lmN, 0..) |N, idx| lm[idx] += try lloydMaxCos(alloc, m.data, N);
            nm += 1;
        }
    }
    const fnm: f64 = @floatFromInt(nm);
    try out.print("matrices: {d}\n\n{s:>16} | {s:>7} | {s:>9} | {s:>8} | {s:>10}\n", .{ nm, "format", "b/w", "cos", "fullGB", "B512 tps" });
    const forms = [_]Form{
        .{ .name = "bitplane P2", .bpw = 2.25, .cos = bp[0] / fnm },
        .{ .name = "bitplane P3", .bpw = 3.375, .cos = bp[1] / fnm },
        .{ .name = "bitplane P4", .bpw = 4.5, .cos = bp[2] / fnm },
        .{ .name = "lloyd N=4", .bpw = 2.125, .cos = lm[0] / fnm },
        .{ .name = "lloyd N=6", .bpw = 2.71, .cos = lm[1] / fnm },
        .{ .name = "lloyd N=8", .bpw = 3.125, .cos = lm[2] / fnm },
        .{ .name = "lloyd N=16", .bpw = 4.125, .cos = lm[3] / fnm },
    };
    for (forms) |f| {
        const gb = fullGB(f.bpw);
        // disk-bound aggregate tps at B=512, 1.23 GB/s, full model = gb + ~30GB core
        const tps = 512.0 * 1.23 / (gb + 30.0);
        try out.print("{s:>16} | {d:>7.3} | {d:>9.5} | {d:>8.1} | {d:>10.2}\n", .{ f.name, f.bpw, f.cos, gb, tps });
    }
    try out.print("\nfp4 source = 4.25 b/w = 806GB. quality bar (P3 block256) = ~0.9733.\n", .{});
    try out.print("min b/w that meets/beats the bar => smallest model => fastest (disk-bound).\n", .{});
}
