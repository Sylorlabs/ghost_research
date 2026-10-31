// forge.zig — builds the engine-format model core on the fast (ext4) drive.
//
// Converts the always-active tensors of DeepSeek V4 Pro from the source
// checkpoint (fp8/fp4/bf16, NTFS reference drive) into the format every
// experiment validated: block-Hadamard rotation + 3 refit XOR bitplanes with
// per-64 f32 scales (identical math to ppl_stack's quantized stream), packed
// for the XNOR kernels (bits[plane][row][col/64] u64, then scales f32).
//
// What gets converted to P3 (exactly the set ppl_stack quantizes):
//   wq_a, wq_b, wkv, wo_a, wo_b, compressor.wkv, compressor.wgate,
//   shared expert w1/w2/w3 per layer.
// What stays exact (matching the instrument): all norms/hc params/sink/ape
// (f32), gate weight+bias (f32 — routing precision is load-bearing),
// tid2eid (raw i64), embed + head (raw bf16).
//
// Usage:  forge [out_dir] [max_layers]      — convert
//         forge verify [out_dir]            — reload layer-0 wq_a, compare
//                                             vs direct quantization path
const std = @import("std");
const ss = @import("signal_survival.zig");
const safetensors = @import("safetensors.zig");

const W_PLANES = 3;
const REFIT_ALT = 0;

const P3_MATS = [_][]const u8{
    "attn.wq_a.weight",
    "attn.wq_b.weight",
    "attn.wkv.weight",
    "attn.wo_a.weight",
    "attn.wo_b.weight",
    "attn.compressor.wkv.weight",
    "attn.compressor.wgate.weight",
    "ffn.shared_experts.w1.weight",
    "ffn.shared_experts.w2.weight",
    "ffn.shared_experts.w3.weight",
};

const F32_1D = [_][]const u8{
    "hc_attn_fn",
    "hc_attn_base",
    "hc_attn_scale",
    "hc_ffn_fn",
    "hc_ffn_base",
    "hc_ffn_scale",
    "attn_norm.weight",
    "ffn_norm.weight",
    "attn.q_norm.weight",
    "attn.kv_norm.weight",
    "attn.attn_sink",
    "attn.compressor.ape",
    "attn.compressor.norm.weight",
};

const Out = struct {
    bin: std.fs.File,
    man: std.fs.File,
    off: u64 = 0,

    fn writeBlob(self: *Out, name: []const u8, kind: []const u8, rows: usize, cols: usize, had: usize, bytes: []const u8) !void {
        try self.bin.writeAll(bytes);
        var buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{{\"name\":\"{s}\",\"kind\":\"{s}\",\"rows\":{d},\"cols\":{d},\"had\":{d},\"off\":{d},\"bytes\":{d}}}\n", .{ name, kind, rows, cols, had, self.off, bytes.len });
        try self.man.writeAll(line);
        self.off += bytes.len;
    }
};

fn tensor1dF32(alloc: std.mem.Allocator, st: *safetensors.SafetensorsFile, name: []const u8) ![]f32 {
    const t = st.tensors.get(name) orelse return error.TensorNotFound;
    var n: usize = 1;
    for (t.shape) |s| n *= s;
    const out = try alloc.alloc(f32, n);
    if (std.mem.eql(u8, t.dtype, "F32")) {
        const f32s = std.mem.bytesAsSlice(f32, @as([]align(4) const u8, @alignCast(t.data)));
        @memcpy(out, f32s);
    } else if (std.mem.eql(u8, t.dtype, "BF16")) {
        const u16s = std.mem.bytesAsSlice(u16, @as([]align(2) const u8, @alignCast(t.data)));
        for (0..n) |i| out[i] = @bitCast(@as(u32, u16s[i]) << 16);
    } else return error.BadDtype;
    return out;
}

/// dequant -> rotate -> pack with refit; writes bits blob then scales blob
/// as one manifest entry of kind "p3".
fn forgeP3(alloc: std.mem.Allocator, out: *Out, st: *safetensors.SafetensorsFile, name: []const u8) !void {
    const w = (try ss.loadDequant(alloc, st, name)) orelse return error.TensorNotFound;
    defer alloc.free(w.data);
    const chunk = ss.hadamardChunkFor(w.cols);
    ss.rotateRows(w, chunk);
    const p = try ss.packBitplanesRefit(alloc, w, W_PLANES, REFIT_ALT);
    defer p.deinit(alloc);
    // single entry: bits then scales, engine derives the split from counts
    const bits_bytes = std.mem.sliceAsBytes(p.bits);
    const scale_bytes = std.mem.sliceAsBytes(p.scales);
    const both = try alloc.alloc(u8, bits_bytes.len + scale_bytes.len);
    defer alloc.free(both);
    @memcpy(both[0..bits_bytes.len], bits_bytes);
    @memcpy(both[bits_bytes.len..], scale_bytes);
    try out.writeBlob(name, "p3", p.rows, p.cols, chunk, both);
}

fn forgeRaw(out: *Out, st: *safetensors.SafetensorsFile, name: []const u8, kind: []const u8) !void {
    const t = st.tensors.get(name) orelse return error.TensorNotFound;
    const rows = if (t.shape.len > 0) t.shape[0] else 1;
    const cols = if (t.shape.len > 1) t.shape[1] else 1;
    try out.writeBlob(name, kind, rows, cols, 0, t.data);
}

fn forgeF32(alloc: std.mem.Allocator, out: *Out, st: *safetensors.SafetensorsFile, name: []const u8) !void {
    const v = try tensor1dF32(alloc, st, name);
    defer alloc.free(v);
    try out.writeBlob(name, "f32", v.len, 1, 0, std.mem.sliceAsBytes(v));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    var args = std.process.args();
    _ = args.skip();
    var out_dir: []const u8 = "engine_weights";
    var max_layers: usize = 61;
    var verify_mode = false;
    if (args.next()) |a| {
        if (std.mem.eql(u8, a, "verify")) {
            verify_mode = true;
            if (args.next()) |d| out_dir = d;
        } else {
            out_dir = a;
            if (args.next()) |l| max_layers = try std.fmt.parseInt(usize, l, 10);
        }
    }

    if (verify_mode) return verify(alloc, out_dir, stdout);

    try std.fs.cwd().makePath(out_dir);
    var pb: [256]u8 = undefined;
    var out = Out{
        .bin = try std.fs.cwd().createFile(try std.fmt.bufPrint(&pb, "{s}/core.bin", .{out_dir}), .{}),
        .man = try std.fs.cwd().createFile(try std.fmt.bufPrint(&pb, "{s}/manifest.jsonl", .{out_dir}), .{}),
    };
    defer out.bin.close();
    defer out.man.close();

    var timer = try std.time.Timer.start();
    var nb: [128]u8 = undefined;

    { // globals: embed (shard 1), head block (shard 63)
        const st1 = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(1));
        defer st1.deinit();
        try forgeRaw(&out, st1, "embed.weight", "bf16");
        try stdout.print("embed done t={d:.0}s\n", .{@as(f64, @floatFromInt(timer.read())) / 1e9});
    }
    {
        const st63 = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(63));
        defer st63.deinit();
        try forgeRaw(&out, st63, "head.weight", "bf16");
        try forgeF32(alloc, &out, st63, "hc_head_fn");
        try forgeF32(alloc, &out, st63, "hc_head_base");
        try forgeF32(alloc, &out, st63, "hc_head_scale");
        try forgeF32(alloc, &out, st63, "norm.weight");
        try stdout.print("head block done t={d:.0}s\n", .{@as(f64, @floatFromInt(timer.read())) / 1e9});
    }

    for (0..max_layers) |layer| {
        const st = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(layer + 2));
        defer st.deinit();
        for (F32_1D) |suffix| {
            try forgeF32(alloc, &out, st, try std.fmt.bufPrint(&nb, "layers.{d}.{s}", .{ layer, suffix }));
        }
        if (layer < 3) {
            try forgeRaw(&out, st, try std.fmt.bufPrint(&nb, "layers.{d}.ffn.gate.tid2eid", .{layer}), "i64");
        } else {
            const gname = try std.fmt.bufPrint(&nb, "layers.{d}.ffn.gate.weight", .{layer});
            const g = (try ss.loadDequant(alloc, st, gname)) orelse return error.TensorNotFound;
            defer alloc.free(g.data);
            try out.writeBlob(gname, "f32mat", g.rows, g.cols, 0, std.mem.sliceAsBytes(g.data));
            try forgeF32(alloc, &out, st, try std.fmt.bufPrint(&nb, "layers.{d}.ffn.gate.bias", .{layer}));
        }
        for (P3_MATS) |suffix| {
            try forgeP3(alloc, &out, st, try std.fmt.bufPrint(&nb, "layers.{d}.{s}", .{ layer, suffix }));
        }
        try stdout.print("L{d:0>2} done off={d}MB t={d:.0}s\n", .{ layer, out.off / (1 << 20), @as(f64, @floatFromInt(timer.read())) / 1e9 });
    }
    try stdout.print("FORGE COMPLETE: {d}MB in {d:.0}s\n", .{ out.off / (1 << 20), @as(f64, @floatFromInt(timer.read())) / 1e9 });
}

/// Reload layer-0 wq_a from the forged core, reconstruct the dequantized
/// equivalent, and compare against the instrument's direct quantization
/// path (rotate + quantizeBitplanesRefit). Must match to float roundoff.
fn verify(alloc: std.mem.Allocator, out_dir: []const u8, stdout: anytype) !void {
    var pb: [256]u8 = undefined;
    const man = try std.fs.cwd().openFile(try std.fmt.bufPrint(&pb, "{s}/manifest.jsonl", .{out_dir}), .{});
    defer man.close();
    const mtext = try man.readToEndAlloc(alloc, 1 << 22);
    defer alloc.free(mtext);

    const target = "layers.0.attn.wq_a.weight";
    var off: u64 = 0;
    var bytes: u64 = 0;
    var rows: usize = 0;
    var cols: usize = 0;
    var lines = std.mem.splitScalar(u8, mtext, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, target) == null) continue;
        var it = std.mem.tokenizeAny(u8, line, "{},\":");
        while (it.next()) |tok| {
            if (std.mem.eql(u8, tok, "rows")) rows = try std.fmt.parseInt(usize, it.next().?, 10);
            if (std.mem.eql(u8, tok, "cols")) cols = try std.fmt.parseInt(usize, it.next().?, 10);
            if (std.mem.eql(u8, tok, "off")) off = try std.fmt.parseInt(u64, it.next().?, 10);
            if (std.mem.eql(u8, tok, "bytes")) bytes = try std.fmt.parseInt(u64, it.next().?, 10);
        }
        break;
    }
    if (rows == 0) return error.TensorNotInManifest;

    const bin = try std.fs.cwd().openFile(try std.fmt.bufPrint(&pb, "{s}/core.bin", .{out_dir}), .{});
    defer bin.close();
    try bin.seekTo(off);
    const blob = try alloc.alloc(u8, bytes);
    defer alloc.free(blob);
    _ = try bin.readAll(blob);
    const words = cols / 64;
    const n = W_PLANES * rows * words;
    const bits = std.mem.bytesAsSlice(u64, @as([]align(8) u8, @alignCast(blob[0 .. n * 8])));
    const scales = std.mem.bytesAsSlice(f32, @as([]align(4) u8, @alignCast(blob[n * 8 ..])));

    // reconstruct
    const recon = try alloc.alloc(f32, rows * cols);
    defer alloc.free(recon);
    @memset(recon, 0);
    for (0..W_PLANES) |p| {
        for (0..rows) |r| {
            for (0..words) |w| {
                const idx = p * rows * words + r * words + w;
                const b = bits[idx];
                const s = scales[idx];
                for (0..64) |j| {
                    const sign: f32 = if (b & (@as(u64, 1) << @intCast(j)) != 0) 1 else -1;
                    recon[r * cols + w * 64 + j] += sign * s;
                }
            }
        }
    }

    // direct path
    const st = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(2));
    defer st.deinit();
    const w = (try ss.loadDequant(alloc, st, target)).?;
    defer alloc.free(w.data);
    ss.rotateRows(w, ss.hadamardChunkFor(w.cols));
    const direct = try ss.quantizeBitplanesRefit(alloc, w, 64, W_PLANES, REFIT_ALT);
    defer alloc.free(direct.data);

    var max_diff: f32 = 0;
    var dot: f64 = 0;
    var na: f64 = 0;
    var nb2: f64 = 0;
    for (0..rows * cols) |i| {
        max_diff = @max(max_diff, @abs(recon[i] - direct.data[i]));
        dot += @as(f64, recon[i]) * direct.data[i];
        na += @as(f64, recon[i]) * recon[i];
        nb2 += @as(f64, direct.data[i]) * direct.data[i];
    }
    try stdout.print("verify {s}: max|diff|={e:.3} cosine={d:.9}\n", .{ target, max_diff, dot / (@sqrt(na) * @sqrt(nb2)) });
}
