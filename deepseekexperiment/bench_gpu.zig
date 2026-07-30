const std = @import("std");
const gpu = @import("src/gpu.zig");

// Block matches compute_1bit.glsl std430: {uint bits_low; uint bits_high; float scale;}
const Block = extern struct { bits_low: u32, bits_high: u32, scale: f32 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    const in_dim: u32 = 7168;
    const out_dim: u32 = 3072; // expert-shaped matmul (one of w1/w3)
    const bpr: u32 = in_dim / 64; // 112 blocks/row
    const nblocks = out_dim * bpr;

    const blocks = try alloc.alloc(Block, nblocks);
    defer alloc.free(blocks);
    var seed: u64 = 0x1234;
    for (blocks) |*b| {
        seed = seed *% 0x9E3779B97F4A7C15 +% 1;
        b.bits_low = @truncate(seed);
        b.bits_high = @truncate(seed >> 32);
        b.scale = 0.05;
    }
    const w_bytes = std.mem.sliceAsBytes(blocks);

    const in_vec = try alloc.alloc(f32, in_dim);
    defer alloc.free(in_vec);
    for (in_vec, 0..) |*v, i| v.* = @floatFromInt(@as(u8, @truncate(i)) % 7);
    const out_vec = try alloc.alloc(f32, out_dim);
    defer alloc.free(out_vec);

    const g = try gpu.GPUAccelerator.init(alloc);
    defer g.deinit();
    try g.loadPipeline("src/shaders/compute_1bit.spv");

    // warmup
    for (0..5) |_| try g.dispatch(in_dim, out_dim, in_vec, out_vec, w_bytes);

    const N: usize = 200;
    var timer = try std.time.Timer.start();
    for (0..N) |_| try g.dispatch(in_dim, out_dim, in_vec, out_vec, w_bytes);
    const ns = timer.read();
    const sec = @as(f64, @floatFromInt(ns)) / 1e9;
    const weights: f64 = @floatFromInt(@as(u64, out_dim) * in_dim * N);
    const gws = weights / sec / 1e9;
    const ms = sec / @as(f64, @floatFromInt(N)) * 1000.0;
    try stdout.print("GPU 1-bit GEMV {d}x{d}: {d:.3} ms/call, {d:.1} Gw/s (end-to-end incl upload)\n", .{ out_dim, in_dim, ms, gws });
    try stdout.print("CPU reference: f32 6.9 Gw/s, XNOR 10.7 Gw/s (E8). GPU vs CPU-XNOR: {d:.1}x\n", .{ gws / 10.7 });
    try stdout.print("sample out[0..3] = {d:.2} {d:.2} {d:.2}\n", .{ out_vec[0], out_vec[1], out_vec[2] });
}
