const std = @import("std");
const ss = @import("src/signal_survival.zig");
const safetensors = @import("src/safetensors.zig");
// Forge one layer's 384 routed experts (w1,w2,w3) to P3-packed on the fast drive.
// Lets the batched engine READ packed P3 (no fp4->P3 convert at runtime, 7x faster).
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    var args = std.process.args(); _ = args.skip();
    const layer: usize = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 30;
    const planes: usize = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 3;
    const outdir: []const u8 = if (args.next()) |a| a else "engine_weights";

    const st = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(layer + 2));
    defer st.deinit();
    var pb: [256]u8 = undefined;
    const outp = try std.fmt.bufPrint(&pb, "{s}/L{d}_experts_P{d}.bin", .{ outdir, layer, planes });
    const f = try std.fs.cwd().createFile(outp, .{});
    defer f.close();
    var timer = try std.time.Timer.start();
    var nb: [128]u8 = undefined;
    var total: u64 = 0;
    for (0..384) |e| {
        inline for (.{ '1', '2', '3' }) |w| {
            const name = try std.fmt.bufPrint(&nb, "layers.{d}.ffn.experts.{d}.w{c}.weight", .{ layer, e, w });
            const m = (try ss.loadDequant(alloc, st, name)).?;
            defer alloc.free(m.data);
            ss.rotateRows(m, ss.hadamardChunkFor(m.cols));
            const p = try ss.packBitplanesRefit(alloc, m, planes, 0);
            defer p.deinit(alloc);
            try f.writeAll(std.mem.sliceAsBytes(p.bits));
            try f.writeAll(std.mem.sliceAsBytes(p.scales));
            total += p.bits.len * 8 + p.scales.len * 4;
        }
        if (e % 64 == 0) try stdout.print("  expert {d} t={d:.0}s\n", .{ e, @as(f64, @floatFromInt(timer.read())) / 1e9 });
    }
    try stdout.print("FORGED L{d} 384 experts P{d}: {d}MB in {d:.0}s -> {s}\n", .{ layer, planes, total / (1 << 20), @as(f64, @floatFromInt(timer.read())) / 1e9, outp });
}
