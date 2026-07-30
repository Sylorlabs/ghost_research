// E6: calibration-aware quantization on REAL activations captured by the
// E4 stack run (calib_acts.bin: layer u32, tok u32, 7168 f32 — post-ffn_norm
// inputs from the reference stream).
//
// Tests, per layer in {5, 30, 50}, on expert w1 of that layer:
//   - naive P3, acts f32          (baseline on real act distribution)
//   - H-rotated P3, rotated int8 acts (the recommended operating point)
//   - AWQ-style: scale cols by (E[x_c^2])^alpha before quantization,
//     compensate activations by 1/s — alpha in {0.25, 0.5}
// Real activations have the model's true outlier structure, so this also
// validates the synthetic heavy-tail results.

const std = @import("std");
const ss = @import("signal_survival.zig");
const safetensors = @import("safetensors.zig");

const DIM = 7168;

fn cosOnActs(alloc: std.mem.Allocator, wref: ss.Mat, wq: ss.Mat, acts: []const [DIM]f32, rotate_chunk: usize, int8_acts: bool, col_comp: ?[]const f32) !f64 {
    const y_ref = try alloc.alloc(f32, wref.rows);
    defer alloc.free(y_ref);
    const y_q = try alloc.alloc(f32, wref.rows);
    defer alloc.free(y_q);
    const xt = try alloc.alloc(f32, DIM);
    defer alloc.free(xt);
    const xa = try alloc.alloc(f32, DIM);
    defer alloc.free(xa);

    var cos_sum: f64 = 0;
    for (acts) |*x| {
        ss.gemv(wref, x, y_ref);
        @memcpy(xt, x);
        if (col_comp) |s| {
            for (0..DIM) |i| xt[i] /= s[i];
        }
        if (rotate_chunk > 0) ss.fwhtChunks(xt, rotate_chunk);
        if (int8_acts) {
            ss.quantizeActInt8(xt, xa, 64);
        } else {
            @memcpy(xa, xt);
        }
        ss.gemv(wq, xa, y_q);
        cos_sum += ss.cosine(y_ref, y_q);
    }
    return cos_sum / @as(f64, @floatFromInt(acts.len));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== E6: quantization fidelity on REAL captured activations ===\n\n", .{});

    // load all calib records
    const cf = try std.fs.cwd().openFile("calib_acts_p3.bin", .{});
    defer cf.close();
    const stat = try cf.stat();
    const rec_size = 8 + DIM * 4;
    const n_rec = stat.size / rec_size;
    var by_layer = std.AutoHashMap(u32, std.ArrayListUnmanaged([DIM]f32)).init(alloc);
    defer {
        var it = by_layer.valueIterator();
        while (it.next()) |l| l.deinit(alloc);
        by_layer.deinit();
    }
    {
        var buf: [8]u8 = undefined;
        var vec: [DIM]f32 = undefined;
        for (0..n_rec) |_| {
            _ = try cf.readAll(&buf);
            const layer = std.mem.readInt(u32, buf[0..4], .little);
            _ = try cf.readAll(std.mem.sliceAsBytes(&vec));
            const gop = try by_layer.getOrPut(layer);
            if (!gop.found_existing) gop.value_ptr.* = .{};
            try gop.value_ptr.append(alloc, vec);
        }
    }
    try stdout.print("loaded {d} activation records, {d} layers\n", .{ n_rec, by_layer.count() });

    // activation channel stats across all layers: outlier magnitude check
    {
        var it = by_layer.iterator();
        var worst_ratio: f32 = 0;
        while (it.next()) |e| {
            for (e.value_ptr.items) |*x| {
                var amax: f32 = 0;
                var asum: f32 = 0;
                for (x) |v| {
                    amax = @max(amax, @abs(v));
                    asum += @abs(v);
                }
                worst_ratio = @max(worst_ratio, amax / (asum / DIM));
            }
        }
        try stdout.print("real act outlier severity: worst max/mean|x| = {d:.0}x\n\n", .{worst_ratio});
    }

    for ([3]u32{ 5, 30, 50 }) |layer| {
        const acts = (by_layer.get(layer) orelse continue).items;
        const shard_path = ss.shardPath(layer + 2);
        const st = try safetensors.SafetensorsFile.load(alloc, shard_path);
        defer st.deinit();
        var nb: [128]u8 = undefined;
        const wname = try std.fmt.bufPrint(&nb, "layers.{d}.ffn.experts.0.w1.weight", .{layer});
        const wref = (try ss.loadDequant(alloc, st, wname)).?;
        defer alloc.free(wref.data);
        const chunk = ss.hadamardChunkFor(DIM);

        try stdout.print("layer {d} ({d} real act vectors), experts.0.w1:\n", .{ layer, acts.len });

        // baseline: naive P3, f32 acts
        {
            const wq = try ss.quantizeBitplanesRefit(alloc, wref, 64, 3, 2);
            defer alloc.free(wq.data);
            const c = try cosOnActs(alloc, wref, wq, acts, 0, false, null);
            try stdout.print("  naive P3 + act f32          : {d:.4}\n", .{c});
        }
        // recommended: H-rot P3 + rotated int8 acts
        {
            const wrot = ss.Mat{ .data = try alloc.dupe(f32, wref.data), .rows = wref.rows, .cols = wref.cols };
            defer alloc.free(wrot.data);
            ss.rotateRows(wrot, chunk);
            const wq = try ss.quantizeBitplanesRefit(alloc, wrot, 64, 3, 2);
            defer alloc.free(wq.data);
            const c = try cosOnActs(alloc, wref, wq, acts, chunk, true, null);
            try stdout.print("  H + P3 + act int8 (operating point): {d:.4}\n", .{c});
        }
        // no-rotation int8 acts (does real outlier structure break absmax int8?)
        {
            const wq = try ss.quantizeBitplanesRefit(alloc, wref, 64, 3, 2);
            defer alloc.free(wq.data);
            const c = try cosOnActs(alloc, wref, wq, acts, 0, true, null);
            try stdout.print("  P3 + act int8, NO rotation  : {d:.4}\n", .{c});
        }
        // AWQ-style column scaling from these acts
        for ([2]f32{ 0.25, 0.5 }) |alpha| {
            const s = try alloc.alloc(f32, DIM);
            defer alloc.free(s);
            for (0..DIM) |c_| {
                var e2: f64 = 0;
                for (acts) |*x| e2 += @as(f64, x[c_]) * x[c_];
                const rms = @sqrt(e2 / @as(f64, @floatFromInt(acts.len)));
                s[c_] = std.math.pow(f32, @as(f32, @floatCast(rms)) + 1e-6, alpha);
            }
            const wsc = ss.Mat{ .data = try alloc.dupe(f32, wref.data), .rows = wref.rows, .cols = wref.cols };
            defer alloc.free(wsc.data);
            for (0..wsc.rows) |r| {
                for (0..DIM) |c_| wsc.data[r * DIM + c_] *= s[c_];
            }
            const wq = try ss.quantizeBitplanesRefit(alloc, wsc, 64, 3, 2);
            defer alloc.free(wq.data);
            const c = try cosOnActs(alloc, wref, wq, acts, 0, false, s);
            try stdout.print("  AWQ a={d:.2} P3 + act f32     : {d:.4}\n", .{ alpha, c });
        }
    }
}
