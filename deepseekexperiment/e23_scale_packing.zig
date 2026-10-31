const std = @import("std");
const ss = @import("src/signal_survival.zig");
const safetensors = @import("src/safetensors.zig");

// WHY is forged P3 (4.5 bits/w) bigger than fp4 source (4.25 bits/w)?
// scales: one f32 per (plane x 64-block) = 3*32/64 = 1.5 bits/w.
// FIX: coarsen the scale block (one scale per 128/256/512 weights). prior work
// says block 16-256 is fidelity-free. MEASURE it on real experts before claiming.
// bits/w(block B, planes P, fp bits S) = P + P*S/B.

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

fn bitsPerW(planes: usize, block: usize, scale_bits: usize) f64 {
    return @as(f64, @floatFromInt(planes)) + @as(f64, @floatFromInt(planes * scale_bits)) / @as(f64, @floatFromInt(block));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const layer = 30;
    const st = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(layer + 2));
    defer st.deinit();

    const SRC_BITS_PER_W: f64 = 4.25; // fp4-e2m1 (4) + e8m0 scale/32 (0.25)
    try out.print("=== E23: P3 scale-packing efficiency (real experts, layer {d}) ===\n", .{layer});
    try out.print("fp4 source = {d:.3} bits/w. current P3 (block64,f32) wastes 1.5 b/w on scales.\n\n", .{SRC_BITS_PER_W});

    const experts = [_]usize{ 0, 5, 100, 300 };
    const mats = [_]u8{ '1', '2', '3' };
    const blocks = [_]usize{ 64, 128, 256, 512 };

    var sum_cos = [_]f64{0} ** blocks.len;
    var nmeas: usize = 0;
    var nb: [128]u8 = undefined;

    for (experts) |e| {
        for (mats) |w| {
            const name = try std.fmt.bufPrint(&nb, "layers.{d}.ffn.experts.{d}.w{c}.weight", .{ layer, e, w });
            const m = (try ss.loadDequant(alloc, st, name)) orelse continue;
            defer alloc.free(m.data);
            ss.rotateRows(m, ss.hadamardChunkFor(m.cols));
            for (blocks, 0..) |blk, bi| {
                const recon = try ss.quantizeBitplanesRefit(alloc, m, blk, 3, 0);
                defer alloc.free(recon.data);
                sum_cos[bi] += cosine(recon.data, m.data);
            }
            nmeas += 1;
        }
    }

    try out.print("matrices measured: {d}  (3072x7168 each)\n\n", .{nmeas});
    try out.print("{s:>8} | {s:>9} {s:>9} | {s:>9} {s:>9} | {s:>10}\n", .{ "block", "cos", "b/w f32", "b/w fp16", "b/w fp8", "fullGB f32" });
    for (blocks, 0..) |blk, bi| {
        const cos = sum_cos[bi] / @as(f64, @floatFromInt(nmeas));
        const bw32 = bitsPerW(3, blk, 32);
        const bw16 = bitsPerW(3, blk, 16);
        const bw8 = bitsPerW(3, blk, 8);
        // full model: 61 layers * 384 experts * 3 mats * 3072*7168 weights
        const total_w: f64 = 61.0 * 384.0 * 3.0 * 3072.0 * 7168.0;
        const gb32 = total_w * bw32 / 8.0 / 1e9;
        try out.print("{d:>8} | {d:>9.5} {d:>9.3} | {d:>9.3} {d:>9.3} | {d:>9.1}  {s}\n", .{ blk, cos, bw32, bw16, bw8, gb32, if (gb32 < 806) "< source ✓ FITS" else "> source ✗" });
    }
    try out.print("\nbaseline block64/f32 cos is the quality bar; if block256 matches it, the\n4x scale-block coarsening is fidelity-free -> P3 shrinks below source -> fits.\n", .{});
}
