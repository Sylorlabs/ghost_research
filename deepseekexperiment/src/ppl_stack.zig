// E11: full V4 layer stack with REAL MLA attention, prefill-only, and a
// standalone perplexity A/B between the reference (f32) and XOR-quantized
// streams.
//
// Attention port (faithful to inference/model.py for start_pos=0, T <= 4096):
//   q = rope(rms(wq_b @ rmsnorm(wq_a @ x)))            [128 heads x 512]
//   kv = fp8sim(rope(rmsnorm(wkv @ x)))                [1 shared kv, MQA]
//   compressor: gated softmax pooling over ratio-blocks (overlap at ratio 4)
//   selection: sliding window 128 + ALL causal compressed slots — exact,
//     because the indexer's top-1024 over <=T/4 slots selects everything.
//   softmax with per-head sink logit; inverse-rope on output;
//   grouped O: 16 x [1024,4096] wo_a, then wo_b.
// YaRN rope (theta 160000, factor 16, orig 65536) on every layer (all main
// layers have compress_ratio != 0 in V4 Pro).
//
// Perplexity: mean NLL of next-token at eval positions in the second half
// of the sequence, computed independently for each stream. This — not
// cosine-to-reference — answers whether the XOR model still models language.

const std = @import("std");
const ss = @import("signal_survival.zig");
const safetensors = @import("safetensors.zig");

const HC = 4;
const DIM = 7168;
const HCDIM = HC * DIM;
const MIX = (2 + HC) * HC;
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
const W_PLANES = 3;
var REFIT_ALT: usize = 0; // refit alternations (arg13): error-feedback re-greedy passes, XNOR-native quality

const QR_RANK = 1536;
const HD = 512; // head_dim, also MQA kv dim
const RD = 64; // rope dims
const NOPE = HD - RD;
const NHEADS = 128;
const OGROUPS = 16;
const OLR = 1024;
const GROUP_DIM = NHEADS * HD / OGROUPS; // 4096
const WIN = 128;

var n_threads: u32 = 10;

// ---------- layer checkpointing (resume an interrupted run) ----------
// The only cross-layer state is `h` (hidden states) plus the U3 counters,
// so a byte-identical restore continues deterministically.

const CKPT_MAGIC: u64 = 0xC4EC9D11;

const CkptHeader = extern struct {
    magic: u64,
    ntok: u64,
    tok_offset: u64,
    cache_cap: u64,
    eps_bits: u64,
    next_layer: u64,
    u3_subs: u64,
    u3_miss_pol: u64,
    u3_miss_base: u64,
};

fn ckptSave(name: []const u8, hdr: CkptHeader, h: []const f32) !void {
    var tmp_buf: [128]u8 = undefined;
    const tmp = try std.fmt.bufPrint(&tmp_buf, "{s}.tmp", .{name});
    {
        const f = try std.fs.cwd().createFile(tmp, .{});
        defer f.close();
        try f.writeAll(std.mem.asBytes(&hdr));
        try f.writeAll(std.mem.sliceAsBytes(h));
    }
    try std.fs.cwd().rename(tmp, name);
}

/// Returns the header if a checkpoint matching the run config exists
/// (and fills `h`), else null.
fn ckptLoad(name: []const u8, want: CkptHeader, h: []f32) ?CkptHeader {
    const f = std.fs.cwd().openFile(name, .{}) catch return null;
    defer f.close();
    var hdr: CkptHeader = undefined;
    const n = f.readAll(std.mem.asBytes(&hdr)) catch return null;
    if (n != @sizeOf(CkptHeader)) return null;
    if (hdr.magic != CKPT_MAGIC or hdr.ntok != want.ntok or
        hdr.tok_offset != want.tok_offset or hdr.cache_cap != want.cache_cap or
        hdr.eps_bits != want.eps_bits) return null;
    const hn = f.readAll(std.mem.sliceAsBytes(h)) catch return null;
    if (hn != h.len * 4) return null;
    return hdr;
}

// ---------- U3: cache-aware routing (quant stream, score layers) ----------
// Simulates a per-layer LRU expert cache evolving over tokens (= decode time).
// Policy: if a routed expert is not resident and some resident expert keeps
// >= (1-eps) of its gate score, route to the resident one instead. The gate's
// razor-thin top-6 margins (P8 chaos finding) suggest this is nearly free.

fn lruFind(cache: []const usize, n: usize, eid: usize) ?usize {
    for (cache[0..n], 0..) |e, i| {
        if (e == eid) return i;
    }
    return null;
}

/// Touch eid (insert/refresh, LRU-evict if full). Returns true on miss.
fn lruTouch(cache: []usize, ts: []u64, n: *usize, cap: usize, eid: usize, clock: u64) bool {
    if (lruFind(cache, n.*, eid)) |i| {
        ts[i] = clock;
        return false;
    }
    if (n.* < cap) {
        cache[n.*] = eid;
        ts[n.*] = clock;
        n.* += 1;
    } else {
        var victim: usize = 0;
        var i: usize = 1;
        while (i < n.*) : (i += 1) {
            if (ts[i] < ts[victim]) victim = i;
        }
        cache[victim] = eid;
        ts[victim] = clock;
    }
    return true;
}

fn ratioFor(layer: usize) usize {
    if (layer < 2) return 128;
    return if (layer % 2 == 0) 4 else 128;
}

// ---------- small math (shared with moe_stack) ----------

fn rmsNormApply(x: []f32, w: []const f32) void {
    var s: f64 = 0;
    for (x) |v| s += @as(f64, v) * v;
    const inv: f32 = @floatCast(1.0 / @sqrt(s / @as(f64, @floatFromInt(x.len)) + EPS));
    for (x, 0..) |*v, i| v.* = v.* * inv * w[i];
}

fn rmsPlain(x: []f32) void {
    var s: f64 = 0;
    for (x) |v| s += @as(f64, v) * v;
    const inv: f32 = @floatCast(1.0 / @sqrt(s / @as(f64, @floatFromInt(x.len)) + EPS));
    for (x) |*v| v.* *= inv;
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

// ---------- rope (YaRN) ----------

var yarn_freqs: [RD / 2]f32 = undefined;

fn initYarnFreqs() void {
    const theta: f64 = 160000.0;
    const factor: f64 = 16.0;
    const orig: f64 = 65536.0;
    const beta_fast: f64 = 32.0;
    const beta_slow: f64 = 1.0;
    const dim: f64 = RD;
    const cd_fast = dim * @log(orig / (beta_fast * 2.0 * std.math.pi)) / (2.0 * @log(theta));
    const cd_slow = dim * @log(orig / (beta_slow * 2.0 * std.math.pi)) / (2.0 * @log(theta));
    const low = @max(@floor(cd_fast), 0.0);
    var high = @ceil(cd_slow);
    if (high > dim / 2.0 - 1.0) high = dim / 2.0 - 1.0;
    for (0..RD / 2) |i| {
        const f = 1.0 / std.math.pow(f64, theta, 2.0 * @as(f64, @floatFromInt(i)) / dim);
        var ramp = (@as(f64, @floatFromInt(i)) - low) / (high - low + 1e-9);
        ramp = std.math.clamp(ramp, 0.0, 1.0);
        const smooth = 1.0 - ramp;
        yarn_freqs[i] = @floatCast(f / factor * (1.0 - smooth) + f * smooth);
    }
}

fn ropeApply(v: []f32, pos: usize, inverse: bool) void {
    for (0..RD / 2) |p| {
        const angle = @as(f32, @floatFromInt(pos)) * yarn_freqs[p];
        const c = @cos(angle);
        var s = @sin(angle);
        if (inverse) s = -s;
        const x0 = v[2 * p];
        const x1 = v[2 * p + 1];
        v[2 * p] = x0 * c - x1 * s;
        v[2 * p + 1] = x0 * s + x1 * c;
    }
}

// ---------- fp8 e4m3 simulation (act_quant inplace equivalent) ----------

var fp8_pos_vals: [127]f32 = undefined; // positive e4m3fn values, ascending

fn initFp8Table() void {
    for (0..127) |b| fp8_pos_vals[b] = ss.fp8_lut[b];
}

fn fp8Nearest(a: f32) f32 {
    // binary search ascending table for |a| clamped to 448
    const x = @min(a, 448.0);
    var lo: usize = 0;
    var hi: usize = 126;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (fp8_pos_vals[mid] < x) lo = mid + 1 else hi = mid;
    }
    if (lo == 0) return fp8_pos_vals[0];
    const a1 = fp8_pos_vals[lo - 1];
    const a2 = fp8_pos_vals[lo];
    return if (x - a1 <= a2 - x) a1 else a2;
}

// fused quant-dequant with per-64 power-of-2 (ue8m0) scales, on dims [0..n)
// KV-dissection: quantize the KV latent to kv_bits. >=8 -> existing fp8 path
// (baseline, unchanged). <8 -> int-N per-block absmax (does halving KV below
// fp8 cost quality? if not -> smaller KV -> bigger batch -> more amortization).
var kv_bits: usize = 8;
fn kvQuant(v: []f32) void {
    if (kv_bits >= 8) return fp8Sim(v);
    const levels: f32 = @floatFromInt((@as(usize, 1) << @intCast(kv_bits - 1)) - 1);
    var i: usize = 0;
    while (i < v.len) : (i += ACT_BLOCK) {
        const end = @min(i + ACT_BLOCK, v.len);
        var amax: f32 = 0;
        for (v[i..end]) |x| amax = @max(amax, @abs(x));
        if (amax == 0) continue;
        const scale = amax / levels;
        for (v[i..end]) |*x| x.* = @round(x.* / scale) * scale;
    }
}

fn fp8Sim(v: []f32) void {
    var i: usize = 0;
    while (i < v.len) : (i += ACT_BLOCK) {
        const end = @min(i + ACT_BLOCK, v.len);
        var amax: f32 = 0;
        for (v[i..end]) |x| amax = @max(amax, @abs(x));
        if (amax == 0) continue;
        const scale = std.math.exp2(@ceil(std.math.log2(amax / 448.0)));
        for (v[i..end]) |*x| {
            const sgn: f32 = if (x.* < 0) -1.0 else 1.0;
            x.* = sgn * fp8Nearest(@abs(x.*) / scale) * scale;
        }
    }
}

// ---------- hyper-connections ----------

const HcParams = struct { fn_: []f32, base: []f32, scale: []f32 };
const HcSplit = struct { pre: [HC]f32, post: [HC]f32, comb: [HC][HC]f32 };

fn hcSplitSinkhorn(mixes: [MIX]f32, scale: []const f32, base: []const f32) HcSplit {
    var out: HcSplit = undefined;
    for (0..HC) |j| out.pre[j] = sigmoid(mixes[j] * scale[0] + base[j]) + EPS;
    for (0..HC) |j| out.post[j] = 2.0 * sigmoid(mixes[HC + j] * scale[1] + base[HC + j]);
    var comb: [HC][HC]f32 = undefined;
    for (0..HC) |j| {
        for (0..HC) |k| comb[j][k] = mixes[j * HC + k + HC * 2] * scale[2] + base[j * HC + k + HC * 2];
    }
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

// ---------- tensor loading ----------

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

// ---------- quantized path ----------

fn quantGemvInto(wq: ss.Mat, x: []const f32, y: []f32, scratch: []f32) void {
    const chunk = ss.hadamardChunkFor(wq.cols);
    const xr = scratch[0..wq.cols];
    @memcpy(xr, x);
    ss.fwhtChunks(xr, chunk);
    const xa = scratch[wq.cols .. 2 * wq.cols];
    ss.quantizeActInt8(xr, xa, ACT_BLOCK);
    ss.gemv(wq, xa, y);
}

fn prepQuant(alloc: std.mem.Allocator, w: ss.Mat) !ss.Mat {
    return prepQuantN(alloc, w, W_PLANES);
}
fn prepQuantN(alloc: std.mem.Allocator, w: ss.Mat, planes: usize) !ss.Mat {
    const wrot = ss.Mat{ .data = try alloc.dupe(f32, w.data), .rows = w.rows, .cols = w.cols };
    defer alloc.free(wrot.data);
    ss.rotateRows(wrot, ss.hadamardChunkFor(w.cols));
    return try ss.quantizeBitplanesRefit(alloc, wrot, 64, planes, REFIT_ALT);
}

// ---------- threaded GEMM over positions ----------

const GemmJob = struct {
    w: ss.Mat,
    xs: []const f32, // [T x in_dim] flattened
    ys: []f32, // [T x out_dim] flattened
    in_dim: usize,
    out_dim: usize,
    t0: usize,
    t1: usize,
    quant: bool,
    alloc: std.mem.Allocator,
};

fn gemmTask(j: *GemmJob) void {
    if (j.quant) {
        const scratch = j.alloc.alloc(f32, 2 * j.in_dim) catch unreachable;
        defer j.alloc.free(scratch);
        for (j.t0..j.t1) |t| {
            quantGemvInto(j.w, j.xs[t * j.in_dim .. (t + 1) * j.in_dim], j.ys[t * j.out_dim .. (t + 1) * j.out_dim], scratch);
        }
    } else {
        for (j.t0..j.t1) |t| {
            ss.gemv(j.w, j.xs[t * j.in_dim .. (t + 1) * j.in_dim], j.ys[t * j.out_dim .. (t + 1) * j.out_dim]);
        }
    }
}

fn gemmAll(alloc: std.mem.Allocator, pool: *std.Thread.Pool, w: ss.Mat, xs: []const f32, ys: []f32, ntok: usize, quant: bool) !void {
    const in_dim = w.cols;
    const out_dim = w.rows;
    const nchunk: usize = n_threads;
    const jobs = try alloc.alloc(GemmJob, nchunk);
    defer alloc.free(jobs);
    var wg: std.Thread.WaitGroup = .{};
    const per = (ntok + nchunk - 1) / nchunk;
    var ji: usize = 0;
    var t0: usize = 0;
    while (t0 < ntok) : (t0 += per) {
        jobs[ji] = .{ .w = w, .xs = xs, .ys = ys, .in_dim = in_dim, .out_dim = out_dim, .t0 = t0, .t1 = @min(t0 + per, ntok), .quant = quant, .alloc = alloc };
        pool.spawnWg(&wg, gemmTask, .{&jobs[ji]});
        ji += 1;
    }
    pool.waitAndWork(&wg);
}

// ---------- compressor (prefill) ----------

const CompWeights = struct {
    wkv: ss.Mat, // [coff*512, 7168] (or quantized equivalent)
    wgate: ss.Mat,
    ape: []f32, // [ratio, coff*512]
    norm: []f32, // [512]
};

// returns comp slots [T/ratio][512] (caller owns)
fn compressorPrefill(alloc: std.mem.Allocator, pool: *std.Thread.Pool, cw: CompWeights, xs: []const f32, ntok: usize, ratio: usize, quant: bool) ![]f32 {
    const coff: usize = if (ratio == 4) 2 else 1;
    const cdim = coff * HD;
    const nblocks = ntok / ratio;
    const kv = try alloc.alloc(f32, ntok * cdim);
    defer alloc.free(kv);
    const sc = try alloc.alloc(f32, ntok * cdim);
    defer alloc.free(sc);
    try gemmAll(alloc, pool, cw.wkv, xs, kv, ntok, quant);
    try gemmAll(alloc, pool, cw.wgate, xs, sc, ntok, quant);

    const comp = try alloc.alloc(f32, nblocks * HD);
    for (0..nblocks) |b| {
        const dst = comp[b * HD .. (b + 1) * HD];
        if (coff == 1) {
            for (0..HD) |ch| {
                var mx: f32 = -std.math.inf(f32);
                var logits: [128]f32 = undefined;
                for (0..ratio) |j| {
                    logits[j] = sc[(b * ratio + j) * cdim + ch] + cw.ape[j * cdim + ch];
                    mx = @max(mx, logits[j]);
                }
                var den: f32 = 0;
                var num: f32 = 0;
                for (0..ratio) |j| {
                    const e = @exp(logits[j] - mx);
                    den += e;
                    num += e * kv[(b * ratio + j) * cdim + ch];
                }
                dst[ch] = num / den;
            }
        } else {
            // overlap (ratio 4): 8 slots; 0-3 = prev block first-half, 4-7 = this block second-half
            for (0..HD) |ch| {
                var logits: [8]f32 = undefined;
                var vals: [8]f32 = undefined;
                for (0..4) |j| {
                    if (b > 0) {
                        const tpos = (b - 1) * 4 + j;
                        logits[j] = sc[tpos * cdim + ch] + cw.ape[j * cdim + ch];
                        vals[j] = kv[tpos * cdim + ch];
                    } else {
                        logits[j] = -std.math.inf(f32);
                        vals[j] = 0;
                    }
                }
                for (0..4) |j| {
                    const tpos = b * 4 + j;
                    logits[4 + j] = sc[tpos * cdim + HD + ch] + cw.ape[j * cdim + HD + ch];
                    vals[4 + j] = kv[tpos * cdim + HD + ch];
                }
                var mx: f32 = -std.math.inf(f32);
                for (logits) |l| mx = @max(mx, l);
                var den: f32 = 0;
                var num: f32 = 0;
                for (0..8) |j| {
                    const e = @exp(logits[j] - mx);
                    den += e;
                    num += e * vals[j];
                }
                dst[ch] = num / den;
            }
        }
        rmsNormApply(dst, cw.norm);
        ropeApply(dst[NOPE..HD], b * ratio, false);
        kvQuant(dst[0..NOPE]);
    }
    return comp;
}

// ---------- sparse attention (prefill) ----------

const AttnJob = struct {
    q: []const f32, // [T x NHEADS x HD]
    kvr: []const f32, // [T x HD]
    comp: []const f32, // [nblocks x HD]
    sink: []const f32, // [NHEADS]
    o: []f32, // [T x NHEADS x HD]
    ratio: usize,
    ntok: usize,
    t0: usize,
    t1: usize,
};

fn attnTask(j: *AttnJob) void {
    const scale: f32 = 1.0 / @sqrt(@as(f32, HD));
    var logits: [WIN + 1024]f32 = undefined;
    var slot_ptr: [WIN + 1024][]const f32 = undefined;
    for (j.t0..j.t1) |t| {
        // gather slots: window then compressed
        var n: usize = 0;
        const wstart = if (t >= WIN) t - WIN + 1 else 0;
        for (wstart..t + 1) |p| {
            slot_ptr[n] = j.kvr[p * HD .. (p + 1) * HD];
            n += 1;
        }
        const ncomp = (t + 1) / j.ratio;
        for (0..ncomp) |b| {
            slot_ptr[n] = j.comp[b * HD .. (b + 1) * HD];
            n += 1;
        }
        for (0..NHEADS) |h| {
            const qh = j.q[(t * NHEADS + h) * HD .. (t * NHEADS + h + 1) * HD];
            var mx: f32 = -std.math.inf(f32);
            for (0..n) |i| {
                var acc: f32 = 0;
                for (0..HD) |d| acc += qh[d] * slot_ptr[i][d];
                logits[i] = acc * scale;
                mx = @max(mx, logits[i]);
            }
            var den: f32 = @exp(j.sink[h] - mx);
            for (0..n) |i| {
                logits[i] = @exp(logits[i] - mx);
                den += logits[i];
            }
            const oh = j.o[(t * NHEADS + h) * HD .. (t * NHEADS + h + 1) * HD];
            @memset(oh, 0);
            for (0..n) |i| {
                const p = logits[i] / den;
                for (0..HD) |d| oh[d] += p * slot_ptr[i][d];
            }
            ropeApply(oh[NOPE..HD], t, true);
        }
    }
}

// ---------- expert machinery (per (pos, stream)) ----------

const ExpertUse = struct {
    tok: usize,
    stream: usize,
    weight: f32,
    out: [DIM]f32 = undefined,
};

const ExpertWork = struct {
    eid: usize,
    uses: std.ArrayListUnmanaged(ExpertUse) = .{},
    planes: usize = W_PLANES, // frequency-precision: hot=P3, cold=P1
};

const SHARED: usize = std.math.maxInt(usize);
const DROP: usize = std.math.maxInt(usize) - 1; // top-k-reduced (skipped) expert slot

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
    xs: []const f32, // [T x 2 x DIM] flattened: (t*2+s)*DIM
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
        wq1 = try prepQuantN(alloc, w1, ctx.work.planes);
        wq2 = try prepQuantN(alloc, w2, ctx.work.planes);
        wq3 = try prepQuantN(alloc, w3, ctx.work.planes);
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
        const x = ctx.xs[(u.tok * 2 + u.stream) * DIM .. (u.tok * 2 + u.stream + 1) * DIM];
        if (u.stream == 0) {
            ss.gemv(w1, x, gate);
            ss.gemv(w3, x, up);
        } else {
            quantGemvInto(wq1.?, x, gate, scratch);
            quantGemvInto(wq3.?, x, up, scratch);
        }
        for (0..INTER) |i| {
            const g = @min(gate[i], SWIGLU_LIMIT);
            const v = std.math.clamp(up[i], -SWIGLU_LIMIT, SWIGLU_LIMIT);
            hidden[i] = g * sigmoid(g) * v;
        }
        if (u.stream == 0) {
            ss.gemv(w2, hidden, &u.out);
        } else {
            quantGemvInto(wq2.?, hidden, &u.out, scratch);
        }
        for (&u.out) |*v| v.* *= u.weight;
    }
}

// quantize-attention-tensor task
const PrepJob = struct {
    alloc: std.mem.Allocator,
    src: ss.Mat,
    dst: *?ss.Mat,
    err: ?anyerror = null,
};

fn prepTask(j: *PrepJob) void {
    j.dst.* = prepQuant(j.alloc, j.src) catch |e| {
        j.err = e;
        return;
    };
}

// ---------- main ----------

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    initYarnFreqs();
    initFp8Table();

    var args = std.process.args();
    _ = args.skip();
    var ntok: usize = 256;
    var max_layers: usize = N_LAYERS;
    var tok_offset: usize = 0; // skip this many stream tokens (pick eval text region)
    var cache_cap: usize = 0; // U3: per-layer LRU expert cache capacity (0 = policy off)
    var sub_eps: f32 = 0.10; // U3: max relative gate-score sacrifice for a resident substitute
    if (args.next()) |a| ntok = try std.fmt.parseInt(usize, a, 10);
    if (args.next()) |a| max_layers = try std.fmt.parseInt(usize, a, 10);
    if (args.next()) |a| tok_offset = try std.fmt.parseInt(usize, a, 10);
    if (args.next()) |a| cache_cap = try std.fmt.parseInt(usize, a, 10);
    if (args.next()) |a| sub_eps = try std.fmt.parseFloat(f32, a);
    if (args.next()) |a| n_threads = try std.fmt.parseInt(u32, a, 10);
    var topk_use: usize = TOPK; // arg8: route to only top-N of the top-6 (cuts active params)
    if (args.next()) |a| topk_use = try std.fmt.parseInt(usize, a, 10);
    var freq_topn: usize = 0; // arg9: frequency-precision — top-N experts/layer at P3, rest at P1 (0=off)
    if (args.next()) |a| freq_topn = try std.fmt.parseInt(usize, a, 10);
    var gplanes: usize = W_PLANES; // arg10: global bit-planes for experts (lean-er: 2=P2, 1=P1)
    if (args.next()) |a| gplanes = try std.fmt.parseInt(usize, a, 10);
    var lean_from: usize = N_LAYERS; // arg11: layers >= this run at 1 plane (per-layer lean test); default off
    if (args.next()) |a| lean_from = try std.fmt.parseInt(usize, a, 10);
    if (args.next()) |a| kv_bits = try std.fmt.parseInt(usize, a, 10); // arg12: KV latent bits (8=fp8 baseline, <8=int-N)
    if (args.next()) |a| REFIT_ALT = try std.fmt.parseInt(usize, a, 10); // arg13: refit alternations (tax payoff)
    std.debug.assert(ntok % 128 == 0);

    // ACT_DUMP=<path>: dump ref-stream post-ffn_norm activations (the exact
    // gate/expert inputs) as [layer u32, tok u32, 7168 f32] records — same
    // format as calib_acts.bin, for manifold analysis (B5).
    var act_dump: ?std.fs.File = null;
    if (std.process.getEnvVarOwned(alloc, "ACT_DUMP")) |p| {
        act_dump = try std.fs.cwd().createFile(p, .{});
        alloc.free(p);
    } else |_| {}
    defer if (act_dump) |f| f.close();

    var route_dump: ?std.fs.File = null;
    if (std.process.getEnvVarOwned(alloc, "ROUTE_DUMP")) |p| {
        route_dump = try std.fs.cwd().createFile(p, .{});
        alloc.free(p);
    } else |_| {}
    defer if (route_dump) |f| f.close();

    var ckpt_name_buf: [128]u8 = undefined;
    const ckpt_name = try std.fmt.bufPrint(&ckpt_name_buf, "ppl_ckpt_T{d}_off{d}_cap{d}.bin", .{ ntok, tok_offset, cache_cap });
    const ckpt_want = CkptHeader{
        .magic = CKPT_MAGIC,
        .ntok = ntok,
        .tok_offset = tok_offset,
        .cache_cap = cache_cap,
        .eps_bits = @as(u32, @bitCast(sub_eps)),
        .next_layer = 0,
        .u3_subs = 0,
        .u3_miss_pol = 0,
        .u3_miss_base = 0,
    };

    // real text tokens
    const tf = try std.fs.cwd().openFile("stream_tokens.bin", .{});
    defer tf.close();
    try tf.seekTo(tok_offset * 4);
    const tokens = try alloc.alloc(u32, ntok + 1);
    defer alloc.free(tokens);
    _ = try tf.readAll(std.mem.sliceAsBytes(tokens));

    try stdout.print("=== E11: full V4 stack with MLA attention — standalone perplexity A/B ===\n", .{});
    try stdout.print("T={d} real text tokens (stream offset {d}) | ref(f32) vs quant(H+P{d}refit weights, int8 acts)\n", .{ ntok, tok_offset, W_PLANES });
    if (cache_cap > 0) try stdout.print("U3 cache-aware routing ON (quant stream, score layers): LRU cap={d}/layer, eps={d:.2}\n", .{ cache_cap, sub_eps });
    if (topk_use < TOPK) try stdout.print("TOPK-REDUCED: routing to top-{d} of {d} experts (active params x{d:.2})\n", .{ topk_use, TOPK, @as(f32, @floatFromInt(topk_use)) / TOPK });
    if (freq_topn > 0) try stdout.print("FREQ-PRECISION: top-{d} experts/layer at P{d}, rest at P1\n", .{ freq_topn, gplanes });
    if (gplanes != W_PLANES) try stdout.print("LEAN: global expert planes = P{d} ({d:.2} bits/w)\n", .{ gplanes, @as(f32, @floatFromInt(gplanes)) + 0.25 });
    if (lean_from < N_LAYERS) try stdout.print("LEAN-FROM: layers >= {d} forced to P1\n", .{lean_from});
    try stdout.print("attention: MLA + window-{d} + gated compressor (exact at this T)\n\n", .{WIN});

    // hidden states: [t][stream][HCDIM] flattened
    const h = try alloc.alloc(f32, ntok * 2 * HCDIM);
    defer alloc.free(h);

    var start_layer: usize = 0;
    var u3_subs_total: usize = 0;
    var u3_miss_pol_total: usize = 0;
    var u3_miss_base_total: usize = 0;
    if (ckptLoad(ckpt_name, ckpt_want, h)) |hdr| {
        start_layer = hdr.next_layer;
        u3_subs_total = hdr.u3_subs;
        u3_miss_pol_total = hdr.u3_miss_pol;
        u3_miss_base_total = hdr.u3_miss_base;
        try stdout.print("RESUMING from checkpoint {s} at layer {d}\n", .{ ckpt_name, start_layer });
    } else {
        const st1 = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(1));
        defer st1.deinit();
        const emb = st1.tensors.get("embed.weight").?;
        var row: [DIM]f32 = undefined;
        for (0..ntok) |t| {
            bf16Row(emb, tokens[t], &row);
            for (0..2) |s| {
                for (0..HC) |c| {
                    @memcpy(h[((t * 2 + s) * HC + c) * DIM .. ((t * 2 + s) * HC + c + 1) * DIM], &row);
                }
            }
        }
    }

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = alloc, .n_jobs = n_threads });
    defer pool.deinit();

    var timer = try std.time.Timer.start();
    var name_buf: [128]u8 = undefined;

    // reusable big buffers
    const xs = try alloc.alloc(f32, ntok * 2 * DIM); // normed sublayer inputs
    defer alloc.free(xs);
    const sub_out = try alloc.alloc(f32, ntok * 2 * DIM);
    defer alloc.free(sub_out);
    const resid = try alloc.alloc(f32, ntok * 2 * HCDIM);
    defer alloc.free(resid);
    const splits = try alloc.alloc(HcSplit, ntok * 2);
    defer alloc.free(splits);
    const qr = try alloc.alloc(f32, ntok * QR_RANK);
    defer alloc.free(qr);
    const qfull = try alloc.alloc(f32, ntok * NHEADS * HD);
    defer alloc.free(qfull);
    const kvr = try alloc.alloc(f32, ntok * HD);
    defer alloc.free(kvr);
    const ovec = try alloc.alloc(f32, ntok * NHEADS * HD);
    defer alloc.free(ovec);
    const r16 = try alloc.alloc(f32, ntok * OGROUPS * OLR);
    defer alloc.free(r16);
    const routing = try alloc.alloc([2][TOPK]usize, ntok);
    defer alloc.free(routing);
    const route_w = try alloc.alloc([2][TOPK]f32, ntok);
    defer alloc.free(route_w);

    for (start_layer..max_layers) |layer| {
        const shard_path = ss.shardPath(layer + 2);
        const st = try safetensors.SafetensorsFile.load(alloc, shard_path);
        defer st.deinit();
        const ratio = ratioFor(layer);

        // --- load layer params ---
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
        const attn_norm = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn_norm.weight", .{layer}));
        defer alloc.free(attn_norm);
        const ffn_norm = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.ffn_norm.weight", .{layer}));
        defer alloc.free(ffn_norm);
        const q_norm = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.q_norm.weight", .{layer}));
        defer alloc.free(q_norm);
        const kv_norm = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.kv_norm.weight", .{layer}));
        defer alloc.free(kv_norm);
        const sink = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.attn_sink", .{layer}));
        defer alloc.free(sink);

        const wq_a = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.wq_a.weight", .{layer}))).?;
        const wq_b = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.wq_b.weight", .{layer}))).?;
        const wkv = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.wkv.weight", .{layer}))).?;
        const wo_a = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.wo_a.weight", .{layer}))).?;
        const wo_b = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.wo_b.weight", .{layer}))).?;
        const c_wkv = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.compressor.wkv.weight", .{layer}))).?;
        const c_wgate = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.compressor.wgate.weight", .{layer}))).?;
        const c_ape = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.compressor.ape", .{layer}));
        const c_norm = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.attn.compressor.norm.weight", .{layer}));
        defer alloc.free(c_ape);
        defer alloc.free(c_norm);

        // quantized versions (parallel)
        var q_wq_a: ?ss.Mat = null;
        var q_wq_b: ?ss.Mat = null;
        var q_wkv: ?ss.Mat = null;
        var q_wo_a: ?ss.Mat = null;
        var q_wo_b: ?ss.Mat = null;
        var q_c_wkv: ?ss.Mat = null;
        var q_c_wgate: ?ss.Mat = null;
        {
            var jobs = [_]PrepJob{
                .{ .alloc = alloc, .src = wq_a, .dst = &q_wq_a },
                .{ .alloc = alloc, .src = wq_b, .dst = &q_wq_b },
                .{ .alloc = alloc, .src = wkv, .dst = &q_wkv },
                .{ .alloc = alloc, .src = wo_a, .dst = &q_wo_a },
                .{ .alloc = alloc, .src = wo_b, .dst = &q_wo_b },
                .{ .alloc = alloc, .src = c_wkv, .dst = &q_c_wkv },
                .{ .alloc = alloc, .src = c_wgate, .dst = &q_c_wgate },
            };
            var wg: std.Thread.WaitGroup = .{};
            for (&jobs) |*j| pool.spawnWg(&wg, prepTask, .{j});
            pool.waitAndWork(&wg);
            for (&jobs) |*j| {
                if (j.err) |e| return e;
            }
        }

        // ===== attention sublayer, per stream =====
        for (0..2) |s| {
            const quant = (s == 1);
            // hc_pre + attn_norm
            for (0..ntok) |t| {
                const hi = h[(t * 2 + s) * HCDIM .. (t * 2 + s + 1) * HCDIM];
                @memcpy(resid[(t * 2 + s) * HCDIM .. (t * 2 + s + 1) * HCDIM], hi);
                splits[t * 2 + s] = hcPre(hi, hc_attn, xs[(t * 2 + s) * DIM .. (t * 2 + s + 1) * DIM]);
                rmsNormApply(xs[(t * 2 + s) * DIM .. (t * 2 + s + 1) * DIM], attn_norm);
            }
            // gather contiguous x for this stream
            const xstream = try alloc.alloc(f32, ntok * DIM);
            defer alloc.free(xstream);
            for (0..ntok) |t| @memcpy(xstream[t * DIM .. (t + 1) * DIM], xs[(t * 2 + s) * DIM .. (t * 2 + s + 1) * DIM]);

            // q path
            try gemmAll(alloc, &pool, if (quant) q_wq_a.? else wq_a, xstream, qr, ntok, quant);
            for (0..ntok) |t| rmsNormApply(qr[t * QR_RANK .. (t + 1) * QR_RANK], q_norm);
            try gemmAll(alloc, &pool, if (quant) q_wq_b.? else wq_b, qr, qfull, ntok, quant);
            for (0..ntok) |t| {
                for (0..NHEADS) |hh| {
                    const qh = qfull[(t * NHEADS + hh) * HD .. (t * NHEADS + hh + 1) * HD];
                    rmsPlain(qh);
                    ropeApply(qh[NOPE..HD], t, false);
                }
            }
            // kv path
            try gemmAll(alloc, &pool, if (quant) q_wkv.? else wkv, xstream, kvr, ntok, quant);
            for (0..ntok) |t| {
                const kvh = kvr[t * HD .. (t + 1) * HD];
                rmsNormApply(kvh, kv_norm);
                ropeApply(kvh[NOPE..HD], t, false);
                kvQuant(kvh[0..NOPE]);
            }
            // compressor
            const comp = try compressorPrefill(alloc, &pool, .{
                .wkv = if (quant) q_c_wkv.? else c_wkv,
                .wgate = if (quant) q_c_wgate.? else c_wgate,
                .ape = c_ape,
                .norm = c_norm,
            }, xstream, ntok, ratio, quant);
            defer alloc.free(comp);

            // sparse attention (parallel over positions)
            {
                const nchunk: usize = n_threads;
                const jobs = try alloc.alloc(AttnJob, nchunk);
                defer alloc.free(jobs);
                var wg: std.Thread.WaitGroup = .{};
                const per = (ntok + nchunk - 1) / nchunk;
                var ji: usize = 0;
                var t0: usize = 0;
                while (t0 < ntok) : (t0 += per) {
                    jobs[ji] = .{ .q = qfull, .kvr = kvr, .comp = comp, .sink = sink, .o = ovec, .ratio = ratio, .ntok = ntok, .t0 = t0, .t1 = @min(t0 + per, ntok) };
                    pool.spawnWg(&wg, attnTask, .{&jobs[ji]});
                    ji += 1;
                }
                pool.waitAndWork(&wg);
            }

            // grouped O projection: per group g, wo_a rows [g*OLR..(g+1)*OLR] x o_g
            for (0..OGROUPS) |g| {
                const wo_a_src = if (quant) q_wo_a.? else wo_a;
                const wga = ss.Mat{ .data = wo_a_src.data[g * OLR * GROUP_DIM .. (g + 1) * OLR * GROUP_DIM], .rows = OLR, .cols = GROUP_DIM };
                // input for position t = ovec[t][g*GROUP_DIM .. ]
                const gx = try alloc.alloc(f32, ntok * GROUP_DIM);
                defer alloc.free(gx);
                for (0..ntok) |t| @memcpy(gx[t * GROUP_DIM .. (t + 1) * GROUP_DIM], ovec[t * NHEADS * HD + g * GROUP_DIM .. t * NHEADS * HD + (g + 1) * GROUP_DIM]);
                const gy = try alloc.alloc(f32, ntok * OLR);
                defer alloc.free(gy);
                try gemmAll(alloc, &pool, wga, gx, gy, ntok, quant);
                for (0..ntok) |t| @memcpy(r16[t * OGROUPS * OLR + g * OLR .. t * OGROUPS * OLR + (g + 1) * OLR], gy[t * OLR .. (t + 1) * OLR]);
            }
            const attn_final = try alloc.alloc(f32, ntok * DIM);
            defer alloc.free(attn_final);
            try gemmAll(alloc, &pool, if (quant) q_wo_b.? else wo_b, r16, attn_final, ntok, quant);

            // hc_post
            for (0..ntok) |t| {
                hcPost(attn_final[t * DIM .. (t + 1) * DIM], resid[(t * 2 + s) * HCDIM .. (t * 2 + s + 1) * HCDIM], splits[t * 2 + s], h[(t * 2 + s) * HCDIM .. (t * 2 + s + 1) * HCDIM]);
            }
        }

        // free attention weights before expert phase
        alloc.free(wq_a.data);
        alloc.free(wq_b.data);
        alloc.free(wkv.data);
        alloc.free(wo_a.data);
        alloc.free(wo_b.data);
        alloc.free(c_wkv.data);
        alloc.free(c_wgate.data);
        if (q_wq_a) |m| alloc.free(m.data);
        if (q_wq_b) |m| alloc.free(m.data);
        if (q_wkv) |m| alloc.free(m.data);
        if (q_wo_a) |m| alloc.free(m.data);
        if (q_wo_b) |m| alloc.free(m.data);
        if (q_c_wkv) |m| alloc.free(m.data);
        if (q_c_wgate) |m| alloc.free(m.data);

        // ===== FFN sublayer =====
        const gate_w = (try ss.loadDequant(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.gate.weight", .{layer}))).?;
        defer alloc.free(gate_w.data);
        const is_hash = layer < N_HASH;
        var gate_bias: []f32 = &[_]f32{};
        var tid2eid: []const i64 = &[_]i64{};
        if (is_hash) {
            const t_ = st.tensors.get(try std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.gate.tid2eid", .{layer})).?;
            tid2eid = std.mem.bytesAsSlice(i64, @as([]align(8) const u8, @alignCast(t_.data)));
        } else {
            gate_bias = try tensor1dF32(alloc, st, try std.fmt.bufPrint(&name_buf, "layers.{d}.ffn.gate.bias", .{layer}));
        }
        defer if (gate_bias.len > 0) alloc.free(gate_bias);

        var scores: [N_EXPERTS]f32 = undefined;
        var route_overlap_sum: f64 = 0;
        // U3 per-layer state: policy LRU + identical baseline LRU fed by
        // unmodified picks (so one run yields both miss counts)
        var lru_pol: [N_EXPERTS]usize = undefined;
        var lru_pol_ts: [N_EXPERTS]u64 = undefined;
        var lru_pol_n: usize = 0;
        var lru_base: [N_EXPERTS]usize = undefined;
        var lru_base_ts: [N_EXPERTS]u64 = undefined;
        var lru_base_n: usize = 0;
        var u3_subs: usize = 0;
        var u3_miss_pol: usize = 0;
        var u3_miss_base: usize = 0;
        for (0..ntok) |t| {
            for (0..2) |s| {
                const hi = h[(t * 2 + s) * HCDIM .. (t * 2 + s + 1) * HCDIM];
                @memcpy(resid[(t * 2 + s) * HCDIM .. (t * 2 + s + 1) * HCDIM], hi);
                splits[t * 2 + s] = hcPre(hi, hc_ffn, xs[(t * 2 + s) * DIM .. (t * 2 + s + 1) * DIM]);
                const xn = xs[(t * 2 + s) * DIM .. (t * 2 + s + 1) * DIM];
                rmsNormApply(xn, ffn_norm);
                if (s == 0) if (act_dump) |f| {
                    const lt = [2]u32{ @intCast(layer), @intCast(t) };
                    try f.writeAll(std.mem.asBytes(&lt));
                    try f.writeAll(std.mem.sliceAsBytes(xn));
                };
                for (0..N_EXPERTS) |e| {
                    scores[e] = sqrtSoftplus(@floatCast(dotF64(gate_w.data[e * DIM .. (e + 1) * DIM], xn)));
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
                if (s == 1 and !is_hash and cache_cap > 0) {
                    // baseline miss accounting (unmodified picks)
                    for (0..TOPK) |k| {
                        if (lruTouch(&lru_base, &lru_base_ts, &lru_base_n, cache_cap, routing[t][s][k], t)) u3_miss_base += 1;
                    }
                    // policy: substitute cold picks with near-equal residents
                    for (0..TOPK) |k| {
                        const pick = routing[t][s][k];
                        if (lruFind(&lru_pol, lru_pol_n, pick) != null) continue;
                        var best_c: usize = N_EXPERTS;
                        var best_s: f32 = -1;
                        for (lru_pol[0..lru_pol_n]) |c| {
                            var taken = false;
                            for (0..TOPK) |kk| {
                                if (routing[t][s][kk] == c) taken = true;
                            }
                            if (!taken and scores[c] > best_s) {
                                best_s = scores[c];
                                best_c = c;
                            }
                        }
                        if (best_c < N_EXPERTS and best_s >= (1 - sub_eps) * scores[pick]) {
                            routing[t][s][k] = best_c;
                            u3_subs += 1;
                        }
                    }
                    // final picks update the policy cache; misses = fetches
                    for (0..TOPK) |k| {
                        if (lruTouch(&lru_pol, &lru_pol_ts, &lru_pol_n, cache_cap, routing[t][s][k], t)) u3_miss_pol += 1;
                    }
                }
                // TOPK_USE: keep only the top-N routed experts by score, zero
                // the rest (simulates top-N routing -> cuts active params/token
                // = the fundamental fetch driver). Hash layers exempt.
                if (topk_use < TOPK and !is_hash) {
                    var sc: [TOPK]f32 = undefined;
                    for (0..TOPK) |k| sc[k] = scores[routing[t][s][k]];
                    // find threshold = the topk_use-th largest score
                    var kept: usize = 0;
                    while (kept < TOPK - topk_use) : (kept += 1) {
                        var mink: usize = 0;
                        var minv: f32 = std.math.inf(f32);
                        for (0..TOPK) |k| {
                            if (sc[k] < minv) {
                                minv = sc[k];
                                mink = k;
                            }
                        }
                        sc[mink] = std.math.inf(f32); // mark dropped (sentinel)
                    }
                    for (0..TOPK) |k| {
                        if (sc[k] == std.math.inf(f32)) routing[t][s][k] = DROP; // dropped marker
                    }
                }
                var wsum: f32 = 0;
                for (0..TOPK) |k| {
                    route_w[t][s][k] = if (routing[t][s][k] == DROP) 0 else scores[routing[t][s][k]];
                    wsum += route_w[t][s][k];
                }
                for (0..TOPK) |k| route_w[t][s][k] = if (wsum > 0) route_w[t][s][k] / wsum * ROUTE_SCALE else 0;
            }
            var ov: usize = 0;
            for (0..TOPK) |a| {
                for (0..TOPK) |b| {
                    if (routing[t][0][a] == routing[t][1][b]) ov += 1;
                }
            }
            route_overlap_sum += @as(f64, @floatFromInt(ov)) / TOPK;
        }

        // ROUTE_DUMP: per-layer, per-token ref-stream routed expert ids
        // (records: layer u32, tok u32, TOPK u32 expert ids) for
        // context-locality / cold-token-fraction analysis.
        if (route_dump) |f| {
            if (!is_hash) {
                var rec: [2 + TOPK]u32 = undefined;
                rec[0] = @intCast(layer);
                for (0..ntok) |t| {
                    rec[1] = @intCast(t);
                    for (0..TOPK) |k| rec[2 + k] = @intCast(routing[t][0][k]);
                    try f.writeAll(std.mem.sliceAsBytes(rec[0..]));
                }
            }
        }

        // expert work list
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
                    if (eid == DROP) continue; // top-k-reduced: not fetched/computed
                    const gop = try works.getOrPut(eid);
                    if (!gop.found_existing) {
                        gop.value_ptr.* = try alloc.create(ExpertWork);
                        gop.value_ptr.*.* = .{ .eid = eid };
                    }
                    try gop.value_ptr.*.uses.append(alloc, .{ .tok = t, .stream = s, .weight = route_w[t][s][k] });
                }
                const gop = try works.getOrPut(SHARED);
                if (!gop.found_existing) {
                    gop.value_ptr.* = try alloc.create(ExpertWork);
                    gop.value_ptr.*.* = .{ .eid = SHARED };
                }
                try gop.value_ptr.*.uses.append(alloc, .{ .tok = t, .stream = s, .weight = 1.0 });
            }
        }

        // Per-expert bit allocation:
        //  - gplanes: global default plane count (lean test: 2=P2, 1=P1)
        //  - lean_from: layers >= this index forced to 1 plane (per-layer lean test)
        //  - freq_topn: top-N experts/layer at gplanes, rest at 1 plane
        const layer_planes: usize = if (!is_hash and layer >= lean_from) 1 else gplanes;
        if (!is_hash) {
            if (freq_topn > 0) {
                var counts = std.ArrayListUnmanaged(usize){};
                defer counts.deinit(alloc);
                var it_c = works.valueIterator();
                while (it_c.next()) |wp| {
                    if (wp.*.eid == SHARED) continue;
                    try counts.append(alloc, wp.*.uses.items.len);
                }
                std.mem.sort(usize, counts.items, {}, comptime std.sort.desc(usize));
                const thresh: usize = if (counts.items.len > freq_topn) counts.items[freq_topn] else 0;
                var it_p = works.valueIterator();
                while (it_p.next()) |wp| {
                    if (wp.*.eid == SHARED) continue;
                    wp.*.planes = if (wp.*.uses.items.len > thresh) layer_planes else 1;
                }
            } else if (layer_planes != W_PLANES) {
                var it_p = works.valueIterator();
                while (it_p.next()) |wp| {
                    if (wp.*.eid == SHARED) continue;
                    wp.*.planes = layer_planes;
                }
            }
        }

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

        @memset(sub_out, 0);
        var it2 = works.valueIterator();
        while (it2.next()) |wp| {
            for (wp.*.uses.items) |*u| {
                const dst = sub_out[(u.tok * 2 + u.stream) * DIM .. (u.tok * 2 + u.stream + 1) * DIM];
                for (0..DIM) |i| dst[i] += u.out[i];
            }
        }
        for (0..ntok) |t| {
            for (0..2) |s| {
                hcPost(sub_out[(t * 2 + s) * DIM .. (t * 2 + s + 1) * DIM], resid[(t * 2 + s) * HCDIM .. (t * 2 + s + 1) * HCDIM], splits[t * 2 + s], h[(t * 2 + s) * HCDIM .. (t * 2 + s + 1) * HCDIM]);
            }
        }

        // layer metric
        var cos_sum: f64 = 0;
        for (0..ntok) |t| {
            cos_sum += ss.cosine(h[(t * 2) * HCDIM .. (t * 2 + 1) * HCDIM], h[(t * 2 + 1) * HCDIM .. (t * 2 + 2) * HCDIM]);
        }
        const elapsed = @as(f64, @floatFromInt(timer.read())) / 1e9;
        try stdout.print("L{d:0>2} r{d:<3} {s} cos={d:.5} route_ov={d:.2} experts={d} t={d:.0}s\n", .{ layer, ratio, if (is_hash) "hash " else "score", cos_sum / @as(f64, @floatFromInt(ntok)), route_overlap_sum / @as(f64, @floatFromInt(ntok)), works.count(), elapsed });
        if (cache_cap > 0 and !is_hash) {
            try stdout.print("     U3: subs={d} miss_pol={d} miss_base={d}\n", .{ u3_subs, u3_miss_pol, u3_miss_base });
            u3_subs_total += u3_subs;
            u3_miss_pol_total += u3_miss_pol;
            u3_miss_base_total += u3_miss_base;
        }
        var ckpt_hdr = ckpt_want;
        ckpt_hdr.next_layer = layer + 1;
        ckpt_hdr.u3_subs = u3_subs_total;
        ckpt_hdr.u3_miss_pol = u3_miss_pol_total;
        ckpt_hdr.u3_miss_base = u3_miss_base_total;
        try ckptSave(ckpt_name, ckpt_hdr, h);
    }

    // ===== head + perplexity =====
    try stdout.print("\n--- perplexity (eval positions: second half, step 1) ---\n", .{});
    const st63 = try safetensors.SafetensorsFile.load(alloc, ss.shardPath(63));
    defer st63.deinit();
    const head_fn = try tensor1dF32(alloc, st63, "hc_head_fn");
    defer alloc.free(head_fn);
    const head_base = try tensor1dF32(alloc, st63, "hc_head_base");
    defer alloc.free(head_base);
    const head_scale = try tensor1dF32(alloc, st63, "hc_head_scale");
    defer alloc.free(head_scale);
    const final_norm = try tensor1dF32(alloc, st63, "norm.weight");
    defer alloc.free(final_norm);
    const head_w = st63.tensors.get("head.weight").?;

    var eval_pos = std.ArrayListUnmanaged(usize){};
    defer eval_pos.deinit(alloc);
    var ep: usize = ntok / 2;
    while (ep < ntok - 1) : (ep += 1) try eval_pos.append(alloc, ep);

    var nll = [2]f64{ 0, 0 };
    var top1_agree: usize = 0;
    const logits = try alloc.alloc(f32, 2 * VOCAB);
    defer alloc.free(logits);

    // per-position diagnostics: is quant damage diffuse or concentrated?
    var csv_name_buf: [64]u8 = undefined;
    const csv_name = if (cache_cap > 0)
        try std.fmt.bufPrint(&csv_name_buf, "e11_positions_T{d}_off{d}_cap{d}.csv", .{ ntok, tok_offset, cache_cap })
    else
        try std.fmt.bufPrint(&csv_name_buf, "e11_positions_T{d}_off{d}.csv", .{ ntok, tok_offset });
    const csv = try std.fs.cwd().createFile(csv_name, .{});
    defer csv.close();
    try csv.writeAll("pos,target,ref_nll,quant_nll,ref_top1,quant_top1\n");

    for (eval_pos.items) |t| {
        var xf: [2][DIM]f32 = undefined;
        for (0..2) |s| {
            const hi = h[(t * 2 + s) * HCDIM .. (t * 2 + s + 1) * HCDIM];
            var ssum: f64 = 0;
            for (hi) |v| ssum += @as(f64, v) * v;
            const rsqrt: f32 = @floatCast(1.0 / @sqrt(ssum / HCDIM + EPS));
            var pre: [HC]f32 = undefined;
            for (0..HC) |j| {
                const mix = @as(f32, @floatCast(dotF64(head_fn[j * HCDIM .. (j + 1) * HCDIM], hi))) * rsqrt;
                pre[j] = sigmoid(mix * head_scale[0] + head_base[j]) + EPS;
            }
            @memset(&xf[s], 0);
            for (0..HC) |j| {
                for (0..DIM) |i| xf[s][i] += pre[j] * hi[j * DIM + i];
            }
            rmsNormApply(&xf[s], final_norm);
        }
        {
            var row: [DIM]f32 = undefined;
            for (0..VOCAB) |r| {
                bf16Row(head_w, r, &row);
                logits[r] = @floatCast(dotF64(&row, &xf[0]));
                logits[VOCAB + r] = @floatCast(dotF64(&row, &xf[1]));
            }
        }
        const target = tokens[t + 1];
        var top1: [2]usize = undefined;
        var p_nll: [2]f64 = undefined;
        for (0..2) |s| {
            const l = logits[s * VOCAB .. (s + 1) * VOCAB];
            var mx: f32 = -std.math.inf(f32);
            var arg: usize = 0;
            for (l, 0..) |v, i| {
                if (v > mx) {
                    mx = v;
                    arg = i;
                }
            }
            top1[s] = arg;
            var den: f64 = 0;
            for (l) |v| den += @exp(@as(f64, v - mx));
            p_nll[s] = -(@as(f64, l[target]) - mx - @log(den));
            nll[s] += p_nll[s];
        }
        if (top1[0] == top1[1]) top1_agree += 1;
        var line_buf: [160]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "{d},{d},{d:.4},{d:.4},{d},{d}\n", .{ t, target, p_nll[0], p_nll[1], top1[0], top1[1] });
        try csv.writeAll(line);
    }
    const n_eval: f64 = @floatFromInt(eval_pos.items.len);
    try stdout.print("\nREF   mean NLL = {d:.4} nats  ppl = {d:.2}\n", .{ nll[0] / n_eval, @exp(nll[0] / n_eval) });
    try stdout.print("QUANT mean NLL = {d:.4} nats  ppl = {d:.2}\n", .{ nll[1] / n_eval, @exp(nll[1] / n_eval) });
    try stdout.print("top1 agreement at eval positions: {d}/{d}\n", .{ top1_agree, eval_pos.items.len });
    if (cache_cap > 0) {
        const red = 100.0 * (1.0 - @as(f64, @floatFromInt(u3_miss_pol_total)) / @as(f64, @floatFromInt(@max(u3_miss_base_total, 1))));
        try stdout.print("U3 totals (score layers, quant stream): subs={d}  fetches {d} vs baseline {d}  ({d:.1}% fetch reduction)\n", .{ u3_subs_total, u3_miss_pol_total, u3_miss_base_total, red });
    }
    try stdout.print("total time: {d:.0}s\n", .{@as(f64, @floatFromInt(timer.read())) / 1e9});
    std.fs.cwd().deleteFile(ckpt_name) catch {};
}
