const std = @import("std");
const gpu = @import("src/gpu.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const in_dim: u32 = 7168;
    const out_dim: u32 = 3072;

    // naive shader: 1 thread/row, (out_dim+63)/64 groups
    {
        const g = try gpu.GPUAccelerator.init(alloc);
        defer g.deinit();
        try g.loadPipeline("src/shaders/compute_1bit.spv");
        const gws = try g.benchResidentGEMV(in_dim, out_dim, 300, (out_dim + 63) / 64);
        try stdout.print("naive   (resident VRAM): {d:.1} Gw/s 1-plane | P3-equiv {d:.1} | vs CPU-P3 107: {d:.2}x\n", .{ gws, gws / 3.0, (gws / 3.0) / 107.0 });
    }
    // optimized shader: 1 workgroup(64 lanes)/row, out_dim groups
    {
        const g = try gpu.GPUAccelerator.init(alloc);
        defer g.deinit();
        try g.loadPipeline("src/shaders/compute_1bit_opt.spv");
        const gws = try g.benchResidentGEMV(in_dim, out_dim, 300, out_dim);
        const p3 = gws / 3.0;
        try stdout.print("opt-wgroup (resident): {d:.1} Gw/s 1-plane | P3-equiv {d:.1} | vs CPU-P3 107: {d:.2}x\n", .{ gws, p3, p3 / 107.0 });
        try stdout.print("  -> full-model compute floor (P3, GPU-resident): {d:.1} tps\n", .{ p3 * 1e9 / 37.8e9 });
    }
}
