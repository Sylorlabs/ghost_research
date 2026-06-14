const std = @import("std");
const ss = @import("src/signal_survival.zig");
const safetensors = @import("src/safetensors.zig");
// Dump real L30 expert weights (f32) so Python can research activation-aware
// quantization against the real L30 activations (acts_T128.bin).
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const out = std.io.getStdOut().writer();
    const layer = 30;
    const st = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(layer + 2));
    defer st.deinit();
    const experts = [_]usize{ 0, 5, 100 };
    var nb: [128]u8 = undefined;
    var fb: [128]u8 = undefined;
    for (experts) |e| {
        inline for (.{ '1', '2', '3' }) |w| {
            const name = try std.fmt.bufPrint(&nb, "layers.{d}.ffn.experts.{d}.w{c}.weight", .{ layer, e, w });
            const m = (try ss.loadDequant(alloc, st, name)).?;
            defer alloc.free(m.data);
            const fp = try std.fmt.bufPrint(&fb, "expert_L30_e{d}_w{c}.bin", .{ e, w });
            const f = try std.fs.cwd().createFile(fp, .{});
            defer f.close();
            const hdr = [2]u32{ @intCast(m.rows), @intCast(m.cols) };
            try f.writeAll(std.mem.asBytes(&hdr));
            try f.writeAll(std.mem.sliceAsBytes(m.data));
            try out.print("dumped {s}: {d}x{d}\n", .{ fp, m.rows, m.cols });
        }
    }
}
