const std = @import("std");
const ss = @import("src/signal_survival.zig");
const safetensors = @import("src/safetensors.zig");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const layer = 30;
    const st = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(layer + 2));
    defer st.deinit();
    var nb: [128]u8 = undefined;
    const gw = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&nb, "layers.{d}.ffn.gate.weight", .{layer}))).?;
    const f = try std.fs.cwd().createFile("gate_L30_w.bin", .{});
    defer f.close();
    const hdr = [2]u32{ @intCast(gw.rows), @intCast(gw.cols) };
    try f.writeAll(std.mem.asBytes(&hdr));
    try f.writeAll(std.mem.sliceAsBytes(gw.data));
    // bias
    const bt = st.tensors.get(try std.fmt.bufPrint(&nb, "layers.{d}.ffn.gate.bias", .{layer})) orelse unreachable;
    _ = bt;
    const bias = try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&nb, "layers.{d}.ffn.gate.bias", .{layer}));
    if (bias) |b| {
        const bf = try std.fs.cwd().createFile("gate_L30_bias.bin", .{});
        defer bf.close();
        try bf.writeAll(std.mem.sliceAsBytes(b.data));
        std.debug.print("gate {d}x{d}, bias {d}\n", .{ gw.rows, gw.cols, b.data.len });
    }
}
