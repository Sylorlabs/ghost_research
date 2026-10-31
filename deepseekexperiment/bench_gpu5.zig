const std = @import("std");
const gpu = @import("src/gpu.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const in_dim: u32 = 7168; const out_dim: u32 = 3072;
    inline for (.{ 32, 64, 128 }) |B| {
        const g = try gpu.GPUAccelerator.init(alloc);
        defer g.deinit();
        try g.loadPipeline("src/shaders/compute_1bit_elem.spv");
        const groups: u32 = (out_dim * B + 63) / 64;
        const gws = try g.benchResidentGEMM(in_dim, out_dim, B, 80, groups);
        const p3 = gws / 3.0;
        try stdout.print("per-elem B={d:3}: {d:.0} Gw/s | P3 {d:.0} | {d:.2}x CPU | floor {d:.1} tps agg\n", .{ B, gws, p3, p3 / 107.0, p3 * 1e9 / 37.8e9 });
    }
}
