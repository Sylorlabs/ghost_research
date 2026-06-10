// E4/E9: multi-layer DeepSeek V4 Pro residual-stream compounding study.
//
// Runs real token embeddings through the model's actual FFN path — RMSNorm,
// sqrtsoftplus gate (hash routing layers 0-2 / score routing 3+), top-6
// routed experts + shared expert with swiglu clamps, and the full
// Hyper-Connections residual machinery (Sinkhorn comb mixing, hc_mult=4) —
// for ALL layers, with two streams side by side:
//   ref:   f32 dequantized weights, f32 activations
//   quant: H-rotated 3-bitplane (refit) weights, rotated int8 activations
// Attention sublayer is ablated to zero in BOTH streams (its HC mixing still
// runs). Per layer: hidden-state cosine, routing overlap. At the end: final
// HC head + norm + lm_head logits, top-k agreement.
//
// Also dumps: calibration activations (E6) and per-layer routing (E7).

const std = @import("std");
const ss = @import("signal_survival.zig");
const safetensors = @import("safetensors.zig");

const HC = 4;
const DIM = 7168;
const HCDIM = HC * DIM;
const MIX = (2 + HC) * HC; // 24
const N_EXPERTS = 384;
const TOPK = 6;
const INTER = 3072;
const N_LAYERS = 61;
const N_HASH = 3;
const ROUTE_SCALE = 2.5;
const SWIGLU_LIMIT = 10.0;
const EPS = 1e-6;
const SINKHORN_ITERS = 20;
const VOCAB = 129280;
const ACT_BLOCK = 64;

// runtime-configurable (CLI): plane count and routing control
var w_planes: usize = 3;
var force_route: bool = false; // quant stream reuses ref routing (control exp)

// ---------- small math ----------

fn rmsNormApply(x: []f32, w: []const f32) void {
    var ss_: f64 = 0;
    for (x) |v| ss_ += @as(f64, v) * v;
    const inv: f32 = @floatCast(1.0 / @sqrt(ss_ / @as(f64, @floatFromInt(x.len)) + EPS));
    for (x, 0..) |*v, i| v.* = v.* * inv * w[i];
}

fn sigmoid(x: f32) f32 {
    return 1.0 / (1.0 + @exp(-x));
}

fn sqrtSoftplus(x: f32) f32 {
    const sp = if (x > 20.0) x else std.math.log1p(@exp(x));
    return @sqrt(sp);
}

fn dotF64(a: []const f32, b: []const f32) f64 {
    var acc: f64 = 0;
    for (a, b) |x, y| acc += @as(f64, x) * y;
    return acc;
}

// ---------- hyper-connections ----------

const HcParams = struct {
    fn_: []f32, // [MIX, HCDIM]
    base: []f32, // [MIX]
    scale: []f32, // [3]
};

const HcSplit = struct {
    pre: [HC]f32,
    post: [HC]f32,
    comb: [HC][HC]f32,
};

fn hcSplitSinkhorn(mixes: [MIX]f32, scale: []const f32, base: []const f32) HcSplit {
    var out: HcSplit = undefined;
    for (0..HC) |j| out.pre[j] = sigmoid(mixes[j] * scale[0] + base[j]) + EPS;
    for (0..HC) |j| out.post[j] = 2.0 * sigmoid(mixes[HC + j] * scale[1] + base[HC + j]);
    var comb: [HC][HC]f32 = undefined;
    for (0..HC) |j| {
        for (0..HC) |k| comb[j][k] = mixes[j * HC + k + HC * 2] * scale[2] + base[j * HC + k + HC * 2];
    }
    // softmax rows + eps
    for (0..HC) |j| {
        var mx: f32 = -std.math.inf(f32);
        for (comb[j]) |v| mx = @max(mx, v);
        var sum: f32 = 0;
        for (&comb[j]) |*v| {
            v.* = @exp(v.* - mx);
            sum += v.*;
        }
        for (&comb[j]) |*v| v.* = v.* / sum + EPS;
    }
    // col normalize, then (iters-1) x (row, col)
    var it: usize = 0;
    while (it < SINKHORN_ITERS) : (it += 1) {
        if (it > 0) {
            for (0..HC) |j| {
                var rs: f32 = 0;
                for (comb[j]) |v| rs += v;
                for (&comb[j]) |*v| v.* /= (rs + EPS);
            }
        }
        for (0..HC) |k| {
            var cs: f32 = 0;
            for (0..HC) |j| cs += comb[j][k];
            for (0..HC) |j| comb[j][k] /= (cs + EPS);
        }
    }
    out.comb = comb;
    return out;
}

// x: [HC*DIM]; returns reduced y[DIM] and the split coefficients
fn hcPre(x: []const f32, p: HcParams, y: []f32) HcSplit {
    var ssum: f64 = 0;
    for (x) |v| ssum += @as(f64, v) * v;
    const rsqrt: f32 = @floatCast(1.0 / @sqrt(ssum / HCDIM + EPS));
    var mixes: [MIX]f32 = undefined;
    for (0..MIX) |m| {
        mixes[m] = @as(f32, @floatCast(dotF64(p.fn_[m * HCDIM .. (m + 1) * HCDIM], x))) * rsqrt;
    }
    const split = hcSplitSinkhorn(mixes, p.scale, p.base);
    @memset(y, 0);
    for (0..HC) |j| {
        const xj = x[j * DIM .. (j + 1) * DIM];
        for (0..DIM) |i| y[i] += split.pre[j] * xj[i];
    }
    return split;
}

// h_new[k] = post[k]*out + sum_j comb[j][k]*residual[j]
fn hcPost(out: []const f32, residual: []const f32, split: HcSplit, h_new: []f32) void {
    for (0..HC) |k| {
        const dst = h_new[k * DIM .. (k + 1) * DIM];
        for (0..DIM) |i| dst[i] = split.post[k] * out[i];
        for (0..HC) |j| {
            const c = split.comb[j][k];
            const rj = residual[j * DIM .. (j + 1) * DIM];
            for (0..DIM) |i| dst[i] += c * rj[i];
        }
    }
}

// ---------- tensor loading helpers ----------

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

fn bf16Row(t: safetensors.Tensor, row: usize, out: []f32) void {
    const cols = t.shape[1];
    const u16s = std.mem.bytesAsSlice(u16, @as([]align(2) const u8, @alignCast(t.data)));
    for (0..cols) |i| out[i] = @bitCast(@as(u32, u16s[row * cols + i]) << 16);
}

// ---------- quantized matmul path (the H+P3+int8 operating point) ----------

// rotate x by block-Hadamard (chunk per dims), int8-quantize per ACT_BLOCK,
// then gemv against a pre-rotated quantized matrix
fn quantGemv(wq: ss.Mat, x: []const f32, y: []f32, scratch: []f32) void {
    const chunk = ss.hadamardChunkFor(wq.cols);
    const xr = scratch[0..wq.cols];
    @memcpy(xr, x);
    ss.fwhtChunks(xr, chunk);
    const xa = scratch[wq.cols .. 2 * wq.cols];
    ss.quantizeActInt8(xr, xa, ACT_BLOCK);
    ss.gemv(wq, xa, y);
}

// dequantize + rotate + 3-plane refit quantize an expert matrix
fn prepQuant(alloc: std.mem.Allocator, w: ss.Mat) !ss.Mat {
    const wrot = ss.Mat{ .data = try alloc.dupe(f32, w.data), .rows = w.rows, .cols = w.cols };
    defer alloc.free(wrot.data);
    ss.rotateRows(wrot, ss.hadamardChunkFor(w.cols));
    return try ss.quantizeBitplanesRefit(alloc, wrot, 64, w_planes, 2);
}

// ---------- expert evaluation ----------

const ExpertUse = struct {
    tok: usize,
    stream: usize, // 0 ref, 1 quant
    weight: f32,
    out: [DIM]f32 = undefined,
};

const ExpertWork = struct {
    eid: usize, // expert id, or SHARED
    uses: std.ArrayListUnmanaged(ExpertUse) = .{},
};

const SHARED: usize = std.math.maxInt(usize);

fn expertName(buf: []u8, layer: usize, eid: usize, which: u8) []const u8 {
    if (eid == SHARED) {
        return std.fmt.bufPrint(buf, "layers.{d}.ffn.shared_experts.w{c}.weight", .{ layer, which }) catch unreachable;
    }
    return std.fmt.bufPrint(buf, "layers.{d}.ffn.experts.{d}.w{c}.weight", .{ layer, eid, which }) catch unreachable;
}

const ExpertCtx = struct {
    alloc: std.mem.Allocator,
    st: *safetensors.SafetensorsFile,
    layer: usize,
    xs: []const [2][DIM]f32, // normed ffn inputs per token per stream
    work: *ExpertWork,
    err: ?anyerror = null,
};

fn runExpert(ctx: *ExpertCtx) void {
    runExpertInner(ctx) catch |e| {
        ctx.err = e;
    };
}

fn runExpertInner(ctx: *ExpertCtx) !void {
    const alloc = ctx.alloc;
    var need_ref = false;
    var need_q = false;
    for (ctx.work.uses.items) |u| {
        if (u.stream == 0) need_ref = true else need_q = true;
    }
    var nb: [128]u8 = undefined;
    const w1 = (try ss.loadDequant(alloc, ctx.st, expertName(&nb, ctx.layer, ctx.work.eid, '1'))).?;
    defer alloc.free(w1.data);
    const w2 = (try ss.loadDequant(alloc, ctx.st, expertName(&nb, ctx.layer, ctx.work.eid, '2'))).?;
    defer alloc.free(w2.data);
    const w3 = (try ss.loadDequant(alloc, ctx.st, expertName(&nb, ctx.layer, ctx.work.eid, '3'))).?;
    defer alloc.free(w3.data);

    var wq1: ?ss.Mat = null;
    var wq2: ?ss.Mat = null;
    var wq3: ?ss.Mat = null;
    if (need_q) {
        wq1 = try prepQuant(alloc, w1);
        wq2 = try prepQuant(alloc, w2);
        wq3 = try prepQuant(alloc, w3);
    }
    defer if (wq1) |m| alloc.free(m.data);
    defer if (wq2) |m| alloc.free(m.data);
    defer if (wq3) |m| alloc.free(m.data);

    const gate = try alloc.alloc(f32, INTER);
    defer alloc.free(gate);
    const up = try alloc.alloc(f32, INTER);
    defer alloc.free(up);
    const hidden = try alloc.alloc(f32, INTER);
    defer alloc.free(hidden);
    const scratch = try alloc.alloc(f32, 2 * DIM);
    defer alloc.free(scratch);

    for (ctx.work.uses.items) |*u| {
        const x = &ctx.xs[u.tok][u.stream];
        if (u.stream == 0) {
            ss.gemv(w1, x, gate);
            ss.gemv(w3, x, up);
        } else {
            quantGemv(wq1.?, x, gate, scratch);
            quantGemv(wq3.?, x, up, scratch);
        }
        for (0..INTER) |i| {
            const g = @min(gate[i], SWIGLU_LIMIT);
            const v = std.math.clamp(up[i], -SWIGLU_LIMIT, SWIGLU_LIMIT);
            hidden[i] = g * sigmoid(g) * v;
        }
        if (u.stream == 0) {
            ss.gemv(w2, hidden, &u.out);
        } else {
            quantGemv(wq2.?, hidden, &u.out, scratch);
        }
        for (&u.out) |*v| v.* *= u.weight;
    }
}

// ---------- main ----------

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    var args = std.process.args();
    _ = args.skip();
    var ntok: usize = 8;
    var max_layers: usize = N_LAYERS;
    if (args.next()) |a| ntok = try std.fmt.parseInt(usize, a, 10);
    if (args.next()) |a| max_layers = try std.fmt.parseInt(usize, a, 10);
    if (args.next()) |a| w_planes = try std.fmt.parseInt(usize, a, 10);
    if (args.next()) |a| force_route = std.mem.eql(u8, a, "force");

    // probe tokens
    const ptf = try std.fs.cwd().openFile("probe_tokens.bin", .{});
    defer ptf.close();
    var tok_buf: [64]u32 = undefined;
    const nread = try ptf.readAll(std.mem.sliceAsBytes(&tok_buf));
    ntok = @min(ntok, nread / 4);
    const tokens = tok_buf[0..ntok];

    try stdout.print("=== E4/E9 MoE residual-stream compounding ===\n", .{});
    try stdout.print("tokens: {any}\n", .{tokens});
    try stdout.print("streams: ref(f32) vs quant(H+P{d}refit weights, rotated int8 acts){s}\n", .{ w_planes, if (force_route) " [ROUTING FORCED TO REF]" else "" });
    try stdout.print("attention ablated to zero in both streams; HC machinery exact\n\n", .{});

    const calib_f = try std.fs.cwd().createFile("calib_acts.bin", .{});
    defer calib_f.close();
    const route_f = try std.fs.cwd().createFile("e4_routing.csv", .{});
    defer route_f.close();
    const metrics_f = try std.fs.cwd().createFile("e4_metrics.csv", .{});
    defer metrics_f.close();
    try route_f.writer().print("layer,token,stream,e0,e1,e2,e3,e4,e5\n", .{});
    try metrics_f.writer().print("layer,mean_cos,route_overlap,uniq_experts\n", .{});

    // hidden states: [tok][stream][HCDIM]
    const h = try alloc.alloc([2][HCDIM]f32, ntok);
    defer alloc.free(h);

    { // embed
        const st1 = try safetensors.SafetensorsFile.load(alloc, ss.WEIGHTS_DIR ++ "/model-00001-of-00064.safetensors");
        defer st1.deinit();
        const emb = st1.tensors.get("embed.weight").?;
        var row: [DIM]f32 = undefined;
        for (tokens, 0..) |t, i| {
            bf16Row(emb, t, &row);
            for (0..HC) |c| {
                @memcpy(h[i][0][c * DIM .. (c + 1) * DIM], &row);
                @memcpy(h[i][1][c * DIM .. (c + 1) * DIM], &row);
            }
        }
    }

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = alloc, .n_jobs = 6 });
    defer pool.deinit();

    var timer = try std.time.Timer.start();

    const xs = try alloc.alloc([2][DIM]f32, ntok);
    defer alloc.free(xs);
    const y_ffn = try alloc.alloc([2][DIM]f32, ntok);
    defer alloc.free(y_ffn);
    const splits_attn = try alloc.alloc([2]HcSplit, ntok);
    defer alloc.free(splits_attn);
    const splits_ffn = try alloc.alloc([2]HcSplit, ntok);
    defer alloc.free(splits_ffn);
    const resid = try alloc.alloc([2][HCDIM]f32, ntok);
    defer alloc.free(resid);

    var name_buf: [128]u8 = undefined;

    for (0..max_layers) |layer| {
        var shard_path_buf: [256]u8 = undefined;
        const shard_path = try std.fmt.bufPrint(&shard_path_buf, "{s}/model-{d:0>5}-of-00064.safetensors", .{ ss.WEIGHTS_DIR, layer + 2 });
        const st = try safetensors.SafetensorsFile.load(alloc, shard_path);
        defer st.deinit();

        // layer params
        const hc_attn = HcParams{
            .fn_ = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.hc_attn_fn", .{layer})),
            .base = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.hc_attn_base", .{layer})),
            .scale = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.hc_attn_scale", .{layer})),
        };
        defer {
            alloc.free(hc_attn.fn_);
            alloc.free(hc_attn.base);
            alloc.free(hc_attn.scale);
        }
        const hc_ffn = HcParams{
            .fn_ = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.hc_ffn_fn", .{layer})),
            .base = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.hc_ffn_base", .{layer})),
            .scale = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.hc_ffn_scale", .{layer})),
        };
        defer {
            alloc.free(hc_ffn.fn_);
            alloc.free(hc_ffn.base);
            alloc.free(hc_ffn.scale);
        }
        const ffn_norm = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.ffn_norm.weight", .{layer}));
        defer alloc.free(ffn_norm);
        const gate_w = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.gate.weight", .{layer}))).?;
        defer alloc.free(gate_w.data);
        const is_hash = layer < N_HASH;
        var gate_bias: []f32 = &[_]f32{};
        var tid2eid: []const i64 = &[_]i64{};
        if (is_hash) {
            const t = st.tensors.get(try std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.gate.tid2eid", .{layer})).?;
            tid2eid = std.mem.bytesAsSlice(i64, @as([]align(8) const u8, @alignCast(t.data)));
        } else {
            gate_bias = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.gate.bias", .{layer}));
        }
        defer if (gate_bias.len > 0) alloc.free(gate_bias);

        // 1. attention sublayer (ablated): hc_pre for coefficients, out = 0
        var x_red: [DIM]f32 = undefined;
        const zero_out = [_]f32{0} ** DIM;
        for (0..ntok) |t| {
            for (0..2) |s| {
                @memcpy(&resid[t][s], &h[t][s]);
                splits_attn[t][s] = hcPre(&h[t][s], hc_attn, &x_red);
                hcPost(&zero_out, &resid[t][s], splits_attn[t][s], &h[t][s]);
            }
        }

        // 2. ffn sublayer: hc_pre -> norm -> route
        var scores: [N_EXPERTS]f32 = undefined;
        var routing: [16][2][TOPK]usize = undefined; // [tok][stream][k]
        var route_weights: [16][2][TOPK]f32 = undefined;
        for (0..ntok) |t| {
            for (0..2) |s| {
                @memcpy(&resid[t][s], &h[t][s]);
                splits_ffn[t][s] = hcPre(&h[t][s], hc_ffn, &xs[t][s]);
                rmsNormApply(&xs[t][s], ffn_norm);
                if (s == 1 and force_route) {
                    routing[t][1] = routing[t][0];
                    route_weights[t][1] = route_weights[t][0];
                    continue;
                }
                // gate (f32 both streams)
                for (0..N_EXPERTS) |e| {
                    scores[e] = sqrtSoftplus(@floatCast(dotF64(gate_w.data[e * DIM .. (e + 1) * DIM], &xs[t][s])));
                }
                if (is_hash) {
                    for (0..TOPK) |k| routing[t][s][k] = @intCast(tid2eid[tokens[t] * TOPK + k]);
                } else {
                    var biased: [N_EXPERTS]f32 = undefined;
                    for (0..N_EXPERTS) |e| biased[e] = scores[e] + gate_bias[e];
                    for (0..TOPK) |k| {
                        var best: usize = 0;
                        var bv: f32 = -std.math.inf(f32);
                        for (0..N_EXPERTS) |e| {
                            var taken = false;
                            for (0..k) |kk| {
                                if (routing[t][s][kk] == e) taken = true;
                            }
                            if (!taken and biased[e] > bv) {
                                bv = biased[e];
                                best = e;
                            }
                        }
                        routing[t][s][k] = best;
                    }
                }
                var wsum: f32 = 0;
                for (0..TOPK) |k| {
                    route_weights[t][s][k] = scores[routing[t][s][k]];
                    wsum += route_weights[t][s][k];
                }
                for (0..TOPK) |k| route_weights[t][s][k] = route_weights[t][s][k] / wsum * ROUTE_SCALE;
            }
            // calib dump (ref stream)
            try calib_f.writer().writeInt(u32, @intCast(layer), .little);
            try calib_f.writer().writeInt(u32, @intCast(t), .little);
            try calib_f.writer().writeAll(std.mem.sliceAsBytes(&xs[t][0]));
            for (0..2) |s| {
                try route_f.writer().print("{d},{d},{d},{d},{d},{d},{d},{d},{d}\n", .{ layer, t, s, routing[t][s][0], routing[t][s][1], routing[t][s][2], routing[t][s][3], routing[t][s][4], routing[t][s][5] });
            }
        }

        // 3. build expert work list (union over tokens/streams + shared)
        var works = std.AutoHashMap(usize, *ExpertWork).init(alloc);
        defer {
            var it = works.valueIterator();
            while (it.next()) |wp| {
                wp.*.uses.deinit(alloc);
                alloc.destroy(wp.*);
            }
            works.deinit();
        }
        for (0..ntok) |t| {
            for (0..2) |s| {
                for (0..TOPK) |k| {
                    const eid = routing[t][s][k];
                    const gop = try works.getOrPut(eid);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = try alloc.create(ExpertWork);
                        gop.value_ptr.*.* = .{ .eid = eid };
                    }
                    try gop.value_ptr.*.uses.append(alloc, .{ .tok = t, .stream = s, .weight = route_weights[t][s][k] });
                }
                const gop = try works.getOrPut(SHARED);
                if (!gop.found_existing) {
                    gop.value_ptr.* = try alloc.create(ExpertWork);
                    gop.value_ptr.*.* = .{ .eid = SHARED };
                }
                try gop.value_ptr.*.uses.append(alloc, .{ .tok = t, .stream = s, .weight = 1.0 });
            }
        }

        // 4. evaluate experts in parallel
        const ctxs = try alloc.alloc(ExpertCtx, works.count());
        defer alloc.free(ctxs);
        {
            var wg: std.Thread.WaitGroup = .{};
            var it = works.valueIterator();
            var ci: usize = 0;
            while (it.next()) |wp| : (ci += 1) {
                ctxs[ci] = .{ .alloc = alloc, .st = st, .layer = layer, .xs = xs, .work = wp.* };
                pool.spawnWg(&wg, runExpert, .{&ctxs[ci]});
            }
            pool.waitAndWork(&wg);
        }
        for (ctxs) |*c| {
            if (c.err) |e| return e;
        }

        // 5. accumulate and hc_post
        for (0..ntok) |t| {
            for (0..2) |s| @memset(&y_ffn[t][s], 0);
        }
        var it2 = works.valueIterator();
        while (it2.next()) |wp| {
            for (wp.*.uses.items) |*u| {
                for (0..DIM) |i| y_ffn[u.tok][u.stream][i] += u.out[i];
            }
        }
        for (0..ntok) |t| {
            for (0..2) |s| {
                hcPost(&y_ffn[t][s], &resid[t][s], splits_ffn[t][s], &h[t][s]);
            }
        }

        // 6. metrics
        var cos_sum: f64 = 0;
        var overlap_sum: f64 = 0;
        for (0..ntok) |t| {
            cos_sum += ss.cosine(&h[t][0], &h[t][1]);
            var ov: usize = 0;
            for (0..TOPK) |a| {
                for (0..TOPK) |b| {
                    if (routing[t][0][a] == routing[t][1][b]) ov += 1;
                }
            }
            overlap_sum += @as(f64, @floatFromInt(ov)) / TOPK;
        }
        const mean_cos = cos_sum / @as(f64, @floatFromInt(ntok));
        const mean_ov = overlap_sum / @as(f64, @floatFromInt(ntok));
        const elapsed = @as(f64, @floatFromInt(timer.read())) / 1e9;
        try stdout.print("L{d:0>2} {s} cos={d:.5} route_overlap={d:.2} experts={d} t={d:.0}s\n", .{ layer, if (is_hash) "hash " else "score", mean_cos, mean_ov, works.count(), elapsed });
        try metrics_f.writer().print("{d},{d:.6},{d:.4},{d}\n", .{ layer, mean_cos, mean_ov, works.count() });
    }

    // ---------- final head (E9) ----------
    try stdout.print("\n--- final head ---\n", .{});
    const st63 = try safetensors.SafetensorsFile.load(alloc, ss.WEIGHTS_DIR ++ "/model-00063-of-00064.safetensors");
    defer st63.deinit();
    const head_fn = try tensor1dF32(alloc, st63, "hc_head_fn"); // [HC, HCDIM]
    defer alloc.free(head_fn);
    const head_base = try tensor1dF32(alloc, st63, "hc_head_base");
    defer alloc.free(head_base);
    const head_scale = try tensor1dF32(alloc, st63, "hc_head_scale");
    defer alloc.free(head_scale);
    const final_norm = try tensor1dF32(alloc, st63, "norm.weight");
    defer alloc.free(final_norm);
    const head_w = st63.tensors.get("head.weight").?;

    // hc_head reduce: pre[j] = sigmoid(mix_j*scale+base_j)+eps over hc_mult rows
    const xfin = try alloc.alloc([2][DIM]f32, ntok);
    defer alloc.free(xfin);
    for (0..ntok) |t| {
        for (0..2) |s| {
            var ssum: f64 = 0;
            for (h[t][s]) |v| ssum += @as(f64, v) * v;
            const rsqrt: f32 = @floatCast(1.0 / @sqrt(ssum / HCDIM + EPS));
            var pre: [HC]f32 = undefined;
            for (0..HC) |j| {
                const mix = @as(f32, @floatCast(dotF64(head_fn[j * HCDIM .. (j + 1) * HCDIM], &h[t][s]))) * rsqrt;
                pre[j] = sigmoid(mix * head_scale[0] + head_base[j]) + EPS;
            }
            @memset(&xfin[t][s], 0);
            for (0..HC) |j| {
                for (0..DIM) |i| xfin[t][s][i] += pre[j] * h[t][s][j * DIM + i];
            }
            rmsNormApply(&xfin[t][s], final_norm);
        }
    }

    // logits: stream over bf16 head rows
    const logits = try alloc.alloc([2][]f32, ntok);
    for (0..ntok) |t| {
        logits[t][0] = try alloc.alloc(f32, VOCAB);
        logits[t][1] = try alloc.alloc(f32, VOCAB);
    }
    defer {
        for (0..ntok) |t| {
            alloc.free(logits[t][0]);
            alloc.free(logits[t][1]);
        }
        alloc.free(logits);
    }
    {
        var row: [DIM]f32 = undefined;
        for (0..VOCAB) |r| {
            bf16Row(head_w, r, &row);
            for (0..ntok) |t| {
                logits[t][0][r] = @floatCast(dotF64(&row, &xfin[t][0]));
                logits[t][1][r] = @floatCast(dotF64(&row, &xfin[t][1]));
            }
        }
    }

    var top1_match: usize = 0;
    var top10_overlap_sum: f64 = 0;
    for (0..ntok) |t| {
        const lc = ss.cosine(logits[t][0], logits[t][1]);
        var top_ref: [10]usize = undefined;
        var top_q: [10]usize = undefined;
        for ([2]usize{ 0, 1 }) |s| {
            var taken = [_]bool{false} ** 10;
            _ = &taken;
            const l = logits[t][s];
            var tops: *[10]usize = if (s == 0) &top_ref else &top_q;
            var used = std.StaticBitSet(VOCAB).initEmpty();
            for (0..10) |k| {
                var best: usize = 0;
                var bv: f32 = -std.math.inf(f32);
                for (0..VOCAB) |v| {
                    if (!used.isSet(v) and l[v] > bv) {
                        bv = l[v];
                        best = v;
                    }
                }
                used.set(best);
                tops[k] = best;
            }
        }
        if (top_ref[0] == top_q[0]) top1_match += 1;
        var ov: usize = 0;
        for (top_ref) |a| {
            for (top_q) |b| {
                if (a == b) ov += 1;
            }
        }
        top10_overlap_sum += @as(f64, @floatFromInt(ov)) / 10.0;
        try stdout.print("tok {d:>6}: logit_cos={d:.5} top1 ref={d} q={d} {s} top10_overlap={d:.1}\n", .{ tokens[t], lc, top_ref[0], top_q[0], if (top_ref[0] == top_q[0]) "MATCH" else "DIFF ", @as(f64, @floatFromInt(ov)) / 10.0 });
    }
    try stdout.print("\ntop1 agreement: {d}/{d}   mean top10 overlap: {d:.3}\n", .{ top1_match, ntok, top10_overlap_sum / @as(f64, @floatFromInt(ntok)) });
    try stdout.print("total time: {d:.0}s\n", .{@as(f64, @floatFromInt(timer.read())) / 1e9});
}
