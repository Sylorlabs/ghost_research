const std = @import("std");
const gpu = @import("src/gpu.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    const g = try gpu.GPUAccelerator.init(alloc);
    defer g.deinit();
    try g.loadPipeline("src/shaders/compute_1bit.spv");
    const gws = try g.benchResidentGEMV(7168, 3072, 300);
    try stdout.print("GPU resident-VRAM 1-bit GEMV 3072x7168: {d:.1} Gw/s (1 plane)\n", .{gws});
    try stdout.print("  vs CPU-XNOR 10.7 Gw/s = {d:.1}x | vs naive-PCIe 20.4 = {d:.1}x\n", .{ gws / 10.7, gws / 20.4 });
    try stdout.print("  P3 (3 planes) effective: {d:.1} Gw/s-equiv; compute floor (full 37.8GMAC): {d:.1} tps\n", .{ gws / 3.0, gws * 1e9 / 37.8e9 });
}
