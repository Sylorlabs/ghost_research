const std = @import("std");
const gpu = @import("src/gpu.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    
    var g = try gpu.GPUAccelerator.init(alloc);
    defer g.deinit();
    
    // We must call dispatch first to initialize buffers
    var w_blocks_1bit = [_]u8{0};
    var dummy_in = [_]f32{0};
    var dummy_out = [_]f32{0};
    try g.dispatch(1, 1, &dummy_in, &dummy_out, &w_blocks_1bit);
    
    const in_dim = 4;
    const out_dim = 2;
    var in_vec = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    var out_vec = [_]f32{ 0.0, 0.0 };
    var w_blocks = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0 };
    
    try g.dispatchFp32(in_dim, out_dim, &in_vec, &out_vec, &w_blocks);
    
    std.debug.print("Out: {any}\n", .{out_vec});
}
