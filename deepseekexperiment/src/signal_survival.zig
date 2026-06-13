// Signal-survival experiment: how much of each DeepSeek V4 matmul survives
// 1-bit / ternary weight quantization (the "XOR transition")?
//
// For each tensor: dequantize the real fp8/fp4 weights to f32 (reference),
// quantize to sign+block-scale, then compare GEMV outputs on random
// activations. Cosine similarity = direction survival.
//
// Variants:
//   A  w:1bit/b64   act:f32     (distiller format, weight-only binarization)
//   B  w:1bit/b64   act:1bit    (full XNOR path, what engine.zig computes)
//   C  w:ternary/b64 act:f32    (BitNet-b1.58-style, 0.7*mean|w| threshold)
//   D  w:ternary/b64 act:1bit
// Activation distributions: gaussian, and gaussian with 1% outlier channels
// x20 (transformer activations have outlier channels; they decide act-1bit).

const std = @import("std");
const safetensors = @import("safetensors.zig");

// The weights drive has two fstab entries (same UUID) that race at boot,
// so the checkpoint shows up at a different mount point per boot.
// Resolve at runtime instead of baking one path in at comptime.
pub const WEIGHTS_DIR_CANDIDATES = [_][]const u8{
    "/mnt/steamgames/DeepSeek-V4-Pro",
    "/mnt/corpus/DeepSeek-V4-Pro",
};

pub fn weightsDir() []const u8 {
    for (WEIGHTS_DIR_CANDIDATES) |d| {
        std.fs.accessAbsolute(d, .{}) catch continue;
        return d;
    }
    std.debug.panic("DeepSeek-V4-Pro checkpoint not found at any known mount point (is the NTFS drive mounted?)", .{});
}

var shard_path_buf: [128]u8 = undefined;

/// Path to shard `idx` of the checkpoint. Returns a slice of a shared
/// module buffer — call from the (single) weight-loading thread only.
pub fn shardPath(idx: usize) []const u8 {
    return std.fmt.bufPrint(&shard_path_buf, "{s}/model-{d:0>5}-of-00064.safetensors", .{ weightsDir(), idx }) catch unreachable;
}

// ---------- dtype decode ----------

fn buildFp8Lut() [256]f32 {
    @setEvalBranchQuota(100000);
    var lut: [256]f32 = undefined;
    for (0..256) |i| {
        const b: u8 = @intCast(i);
        const sign: f32 = if (b & 0x80 != 0) -1.0 else 1.0;
        const e: u8 = (b >> 3) & 0xF;
        const m: f32 = @floatFromInt(b & 7);
        if (e == 0) {
            lut[i] = sign * (m / 8.0) * 0.015625; // 2^-6 subnormal
        } else if (e == 15 and (b & 7) == 7) {
            lut[i] = 0.0; // e4m3fn NaN; should not appear in weights
        } else {
            const ef: i32 = @as(i32, e) - 7;
            lut[i] = sign * (1.0 + m / 8.0) * std.math.scalbn(@as(f32, 1.0), ef);
        }
    }
    return lut;
}

fn buildFp4Lut() [16]f32 {
    const mags = [8]f32{ 0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0 };
    var lut: [16]f32 = undefined;
    for (0..16) |i| {
        const mag = mags[i & 7];
        lut[i] = if (i & 8 != 0) -mag else mag;
    }
    return lut;
}

fn buildE8m0Lut() [256]f32 {
    @setEvalBranchQuota(100000);
    var lut: [256]f32 = undefined;
    for (0..256) |i| {
        lut[i] = std.math.scalbn(@as(f32, 1.0), @as(i32, @intCast(i)) - 127);
    }
    return lut;
}

pub const fp8_lut = buildFp8Lut();
pub const fp4_lut = buildFp4Lut();
pub const e8m0_lut = buildE8m0Lut();

pub const Mat = struct {
    data: []f32,
    rows: usize,
    cols: usize,

    fn deinit(self: Mat, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
    }
};

// fp8 e4m3 weight [R, C] with e8m0 scale [ceil(R/128), ceil(C/128)]
pub fn dequantFp8(alloc: std.mem.Allocator, w: safetensors.Tensor, s: safetensors.Tensor) !Mat {
    const rows = w.shape[0];
    const cols = w.shape[1];
    const s_cols = s.shape[1];
    std.debug.assert(s.shape[0] == (rows + 127) / 128);
    std.debug.assert(s_cols == (cols + 127) / 128);
    const out = try alloc.alloc(f32, rows * cols);
    for (0..rows) |r| {
        const s_row = (r / 128) * s_cols;
        for (0..cols) |c| {
            const scale = e8m0_lut[s.data[s_row + c / 128]];
            out[r * cols + c] = fp8_lut[w.data[r * cols + c]] * scale;
        }
    }
    return .{ .data = out, .rows = rows, .cols = cols };
}

// fp4 e2m1 packed 2/byte along K (low nibble = even col), stored [R, C/2],
// e8m0 scale [R, C/32]
pub fn dequantFp4(alloc: std.mem.Allocator, w: safetensors.Tensor, s: safetensors.Tensor) !Mat {
    const rows = w.shape[0];
    const byte_cols = w.shape[1];
    const cols = byte_cols * 2;
    const s_cols = s.shape[1];
    std.debug.assert(s.shape[0] == rows);
    std.debug.assert(s_cols == cols / 32);
    const out = try alloc.alloc(f32, rows * cols);
    for (0..rows) |r| {
        const s_row = r * s_cols;
        for (0..byte_cols) |bc| {
            const byte = w.data[r * byte_cols + bc];
            const c0 = bc * 2;
            const scale = e8m0_lut[s.data[s_row + c0 / 32]];
            out[r * cols + c0] = fp4_lut[byte & 15] * scale;
            out[r * cols + c0 + 1] = fp4_lut[byte >> 4] * scale;
        }
    }
    return .{ .data = out, .rows = rows, .cols = cols };
}

// bf16 weight (no scale)
pub fn dequantBf16(alloc: std.mem.Allocator, w: safetensors.Tensor) !Mat {
    const rows = w.shape[0];
    const cols = w.shape[1];
    const out = try alloc.alloc(f32, rows * cols);
    const u16s = std.mem.bytesAsSlice(u16, @as([]align(2) const u8, @alignCast(w.data)));
    for (0..rows * cols) |i| {
        out[i] = @bitCast(@as(u32, u16s[i]) << 16);
    }
    return .{ .data = out, .rows = rows, .cols = cols };
}

// ---------- quantizers (produce a dequantized-equivalent f32 matrix) ----------

// 1-bit: per block of `block` cols, w -> sign(w) * mean|w|  (distiller format)
pub fn quantize1bit(alloc: std.mem.Allocator, w: Mat, block: usize) !Mat {
    const out = try alloc.alloc(f32, w.rows * w.cols);
    var i: usize = 0;
    while (i < w.data.len) : (i += block) {
        var sum_abs: f32 = 0;
        for (w.data[i .. i + block]) |v| sum_abs += @abs(v);
        const scale = sum_abs / @as(f32, @floatFromInt(block));
        for (0..block) |j| {
            // matches smart_distiller: bit = (w > 0), so w==0 -> -1
            out[i + j] = if (w.data[i + j] > 0) scale else -scale;
        }
    }
    return .{ .data = out, .rows = w.rows, .cols = w.cols };
}

// ternary: threshold 0.7*mean|w| per block, scale = mean|w| over kept elems
pub fn quantizeTernary(alloc: std.mem.Allocator, w: Mat, block: usize) !Mat {
    const out = try alloc.alloc(f32, w.rows * w.cols);
    var i: usize = 0;
    while (i < w.data.len) : (i += block) {
        var sum_abs: f32 = 0;
        for (w.data[i .. i + block]) |v| sum_abs += @abs(v);
        const thresh = 0.7 * sum_abs / @as(f32, @floatFromInt(block));
        var kept_sum: f32 = 0;
        var kept_n: usize = 0;
        for (w.data[i .. i + block]) |v| {
            if (@abs(v) > thresh) {
                kept_sum += @abs(v);
                kept_n += 1;
            }
        }
        const scale = if (kept_n > 0) kept_sum / @as(f32, @floatFromInt(kept_n)) else 0;
        for (0..block) |j| {
            const v = w.data[i + j];
            out[i + j] = if (@abs(v) > thresh) (if (v > 0) scale else -scale) else 0;
        }
    }
    return .{ .data = out, .rows = w.rows, .cols = w.cols };
}

// k-plane residual binarization: W ~ sum_p s_p * sign(r_p), r_{p+1} = r_p - s_p*sign(r_p).
// Every plane is still XNOR+popcount at runtime. Returns dequantized-equivalent matrix.
pub fn quantizeBitplanes(alloc: std.mem.Allocator, w: Mat, block: usize, planes: usize) !Mat {
    const out = try alloc.alloc(f32, w.rows * w.cols);
    @memset(out, 0);
    const resid = try alloc.alloc(f32, w.rows * w.cols);
    defer alloc.free(resid);
    @memcpy(resid, w.data);
    for (0..planes) |_| {
        var i: usize = 0;
        while (i < resid.len) : (i += block) {
            var sum_abs: f32 = 0;
            for (resid[i .. i + block]) |v| sum_abs += @abs(v);
            const scale = sum_abs / @as(f32, @floatFromInt(block));
            for (0..block) |j| {
                const s: f32 = if (resid[i + j] > 0) scale else -scale;
                out[i + j] += s;
                resid[i + j] -= s;
            }
        }
    }
    return .{ .data = out, .rows = w.rows, .cols = w.cols };
}

// in-place fast Walsh-Hadamard transform on chunks of `chunk` (power of 2),
// normalized so the transform is orthonormal
pub fn fwhtChunks(x: []f32, chunk: usize) void {
    const inv = 1.0 / @sqrt(@as(f32, @floatFromInt(chunk)));
    var base: usize = 0;
    while (base < x.len) : (base += chunk) {
        var h: usize = 1;
        while (h < chunk) : (h *= 2) {
            var i: usize = 0;
            while (i < chunk) : (i += h * 2) {
                for (0..h) |j| {
                    const a = x[base + i + j];
                    const b = x[base + i + j + h];
                    x[base + i + j] = a + b;
                    x[base + i + j + h] = a - b;
                }
            }
        }
        for (x[base .. base + chunk]) |*v| v.* *= inv;
    }
}

pub fn hadamardChunkFor(cols: usize) usize {
    // largest power of 2 that divides cols (7168 -> 1024, 1536 -> 512, 3072 -> 1024)
    var c: usize = 1;
    while (cols % (c * 2) == 0 and c * 2 <= 4096) c *= 2;
    return c;
}

// rotate every row of W by the block-diagonal Hadamard (W' = W * H^T);
// pairing with x' = H x preserves the product since H is orthonormal
pub fn rotateRows(w: Mat, chunk: usize) void {
    for (0..w.rows) |r| {
        fwhtChunks(w.data[r * w.cols .. (r + 1) * w.cols], chunk);
    }
}

// 1-bit activation with per-`block` scale: sign(x) * mean|x|_block
pub fn binarizeActScaled(x: []const f32, out: []f32, block: usize) void {
    var i: usize = 0;
    while (i < x.len) : (i += block) {
        var sum_abs: f32 = 0;
        for (x[i .. i + block]) |v| sum_abs += @abs(v);
        const scale = sum_abs / @as(f32, @floatFromInt(block));
        for (0..block) |j| out[i + j] = if (x[i + j] > 0) scale else -scale;
    }
}

// k-plane residual binarization of the activation vector (same trick as weights;
// every weight-plane x act-plane dot is still XNOR+popcount at runtime)
pub fn binarizeActPlanes(x: []const f32, out: []f32, block: usize, planes: usize) void {
    var resid_buf: [32768]f32 = undefined;
    const resid = resid_buf[0..x.len];
    @memcpy(resid, x);
    @memset(out, 0);
    for (0..planes) |_| {
        var i: usize = 0;
        while (i < x.len) : (i += block) {
            var sum_abs: f32 = 0;
            for (resid[i .. i + block]) |v| sum_abs += @abs(v);
            const scale = sum_abs / @as(f32, @floatFromInt(block));
            for (0..block) |j| {
                const s: f32 = if (resid[i + j] > 0) scale else -scale;
                out[i + j] += s;
                resid[i + j] -= s;
            }
        }
    }
}

// E1: greedy bitplanes + least-squares scale refit (+ optional sign re-greedy).
// Given fixed signs s_p per block, scales solve the kxk system G a = b,
// G_pq = <s_p,s_q>, b_p = <s_p,w>. Storage identical to greedy planes.
pub fn quantizeBitplanesRefit(alloc: std.mem.Allocator, w: Mat, block: usize, planes: usize, alternations: usize) !Mat {
    const out = try alloc.alloc(f32, w.rows * w.cols);
    const signs = try alloc.alloc(i8, planes * block);
    defer alloc.free(signs);
    const resid = try alloc.alloc(f32, block);
    defer alloc.free(resid);
    var scales: [8]f64 = undefined;

    var i: usize = 0;
    while (i < w.data.len) : (i += block) {
        const wblk = w.data[i .. i + block];
        // greedy init
        @memcpy(resid, wblk);
        for (0..planes) |p| {
            var sum_abs: f32 = 0;
            for (resid) |v| sum_abs += @abs(v);
            const scale = sum_abs / @as(f32, @floatFromInt(block));
            scales[p] = scale;
            for (0..block) |j| {
                const s: i8 = if (resid[j] > 0) 1 else -1;
                signs[p * block + j] = s;
                resid[j] -= @as(f32, @floatFromInt(s)) * scale;
            }
        }
        for (0..alternations + 1) |it| {
            // refit scales: solve G a = b (planes x planes, tiny -> gauss elim)
            var g: [8][9]f64 = undefined;
            for (0..planes) |p| {
                for (0..planes) |q| {
                    var dot: i32 = 0;
                    for (0..block) |j| dot += @as(i32, signs[p * block + j]) * signs[q * block + j];
                    g[p][q] = @floatFromInt(dot);
                }
                var bp: f64 = 0;
                for (0..block) |j| bp += @as(f64, wblk[j]) * @as(f64, @floatFromInt(signs[p * block + j]));
                g[p][planes] = bp;
            }
            for (0..planes) |col| { // gaussian elimination, partial pivot
                var piv = col;
                for (col + 1..planes) |r| {
                    if (@abs(g[r][col]) > @abs(g[piv][col])) piv = r;
                }
                std.mem.swap([9]f64, &g[col], &g[piv]);
                if (@abs(g[col][col]) < 1e-12) continue;
                for (col + 1..planes) |r| {
                    const f = g[r][col] / g[col][col];
                    for (col..planes + 1) |c| g[r][c] -= f * g[col][c];
                }
            }
            var p_rev: usize = planes;
            while (p_rev > 0) {
                p_rev -= 1;
                var acc = g[p_rev][planes];
                for (p_rev + 1..planes) |c| acc -= g[p_rev][c] * scales[c];
                scales[p_rev] = if (@abs(g[p_rev][p_rev]) < 1e-12) 0 else acc / g[p_rev][p_rev];
            }
            if (it == alternations) break;
            // re-greedy signs with refit scales
            @memcpy(resid, wblk);
            for (0..planes) |p| {
                for (0..block) |j| {
                    const s: i8 = if (resid[j] > 0) 1 else -1;
                    signs[p * block + j] = s;
                    resid[j] -= @as(f32, @floatFromInt(s)) * @as(f32, @floatCast(scales[p]));
                }
            }
        }
        for (0..block) |j| {
            var acc: f64 = 0;
            for (0..planes) |p| acc += scales[p] * @as(f64, @floatFromInt(signs[p * block + j]));
            out[i + j] = @floatCast(acc);
        }
    }
    return .{ .data = out, .rows = w.rows, .cols = w.cols };
}

// Packed export of quantizeBitplanesRefit: identical math, but emits the
// sign bits + refit scales (the engine's on-disk/runtime format) instead of
// the dequantized-equivalent matrix. Layout matches xnor_bench.PackedPlanes:
// bits[plane][row][col/64] u64 (bit j = sign of element j positive),
// scales[plane][row][col/64] f32. block must be 64.
pub const Packed3 = struct {
    bits: []u64,
    scales: []f32,
    rows: usize,
    cols: usize,
    planes: usize,

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.bits);
        alloc.free(self.scales);
    }
};

pub fn packBitplanesRefit(alloc: std.mem.Allocator, w: Mat, planes: usize, alternations: usize) !Packed3 {
    const block = 64;
    std.debug.assert(w.cols % block == 0);
    const words = w.cols / block;
    const n = planes * w.rows * words;
    var out = Packed3{
        .bits = try alloc.alloc(u64, n),
        .scales = try alloc.alloc(f32, n),
        .rows = w.rows,
        .cols = w.cols,
        .planes = planes,
    };
    const signs = try alloc.alloc(i8, planes * block);
    defer alloc.free(signs);
    const resid = try alloc.alloc(f32, block);
    defer alloc.free(resid);
    var scales: [8]f64 = undefined;

    var i: usize = 0;
    while (i < w.data.len) : (i += block) {
        const wblk = w.data[i .. i + block];
        @memcpy(resid, wblk);
        for (0..planes) |p| {
            var sum_abs: f32 = 0;
            for (resid) |v| sum_abs += @abs(v);
            const scale = sum_abs / @as(f32, @floatFromInt(block));
            scales[p] = scale;
            for (0..block) |j| {
                const s: i8 = if (resid[j] > 0) 1 else -1;
                signs[p * block + j] = s;
                resid[j] -= @as(f32, @floatFromInt(s)) * scale;
            }
        }
        for (0..alternations + 1) |it| {
            var g: [8][9]f64 = undefined;
            for (0..planes) |p| {
                for (0..planes) |q| {
                    var dot: i32 = 0;
                    for (0..block) |j| dot += @as(i32, signs[p * block + j]) * signs[q * block + j];
                    g[p][q] = @floatFromInt(dot);
                }
                var bp: f64 = 0;
                for (0..block) |j| bp += @as(f64, wblk[j]) * @as(f64, @floatFromInt(signs[p * block + j]));
                g[p][planes] = bp;
            }
            for (0..planes) |col| {
                var piv = col;
                for (col + 1..planes) |r| {
                    if (@abs(g[r][col]) > @abs(g[piv][col])) piv = r;
                }
                std.mem.swap([9]f64, &g[col], &g[piv]);
                if (@abs(g[col][col]) < 1e-12) continue;
                for (col + 1..planes) |r| {
                    const f = g[r][col] / g[col][col];
                    for (col..planes + 1) |c| g[r][c] -= f * g[col][c];
                }
            }
            var p_rev: usize = planes;
            while (p_rev > 0) {
                p_rev -= 1;
                var acc = g[p_rev][planes];
                for (p_rev + 1..planes) |c| acc -= g[p_rev][c] * scales[c];
                scales[p_rev] = if (@abs(g[p_rev][p_rev]) < 1e-12) 0 else acc / g[p_rev][p_rev];
            }
            if (it == alternations) break;
            @memcpy(resid, wblk);
            for (0..planes) |p| {
                for (0..block) |j| {
                    const s: i8 = if (resid[j] > 0) 1 else -1;
                    signs[p * block + j] = s;
                    resid[j] -= @as(f32, @floatFromInt(s)) * @as(f32, @floatCast(scales[p]));
                }
            }
        }
        const row = (i / w.cols);
        const word0 = (i % w.cols) / block;
        for (0..planes) |p| {
            var bits: u64 = 0;
            for (0..block) |j| {
                if (signs[p * block + j] > 0) bits |= @as(u64, 1) << @intCast(j);
            }
            const idx = p * w.rows * words + row * words + word0;
            out.bits[idx] = bits;
            out.scales[idx] = @floatCast(scales[p]);
        }
    }
    return out;
}

// E2: int8 activations with per-block absmax scale (hybrid alternative to act planes)
pub fn quantizeActInt8(x: []const f32, out: []f32, block: usize) void {
    var i: usize = 0;
    while (i < x.len) : (i += block) {
        var amax: f32 = 0;
        for (x[i .. i + block]) |v| amax = @max(amax, @abs(v));
        const scale = amax / 127.0;
        if (scale == 0) {
            @memset(out[i .. i + block], 0);
            continue;
        }
        for (0..block) |j| {
            out[i + j] = @round(x[i + j] / scale) * scale;
        }
    }
}

// E5: random sign diagonal (QuaRot-style incoherence), deterministic per index
fn randSign(idx: usize) f32 {
    var h = idx *% 0x9E3779B97F4A7C15;
    h ^= h >> 33;
    h *%= 0xFF51AFD7ED558CCD;
    return if (h & 1 == 0) 1.0 else -1.0;
}

fn applySignDiagCols(w: Mat) void {
    for (0..w.rows) |r| {
        for (0..w.cols) |c| w.data[r * w.cols + c] *= randSign(c);
    }
}

fn applySignDiagVec(x: []f32) void {
    for (x, 0..) |*v, c| v.* *= randSign(c);
}

// ---------- gemv + metrics ----------

pub fn gemv(w: Mat, x: []const f32, y: []f32) void {
    for (0..w.rows) |r| {
        const row = w.data[r * w.cols .. (r + 1) * w.cols];
        var acc: f32 = 0;
        for (row, x) |wv, xv| acc += wv * xv;
        y[r] = acc;
    }
}

pub fn cosine(a: []const f32, b: []const f32) f32 {
    var dot: f64 = 0;
    var na: f64 = 0;
    var nb: f64 = 0;
    for (a, b) |av, bv| {
        dot += @as(f64, av) * bv;
        na += @as(f64, av) * av;
        nb += @as(f64, bv) * bv;
    }
    if (na == 0 or nb == 0) return 0;
    return @floatCast(dot / (@sqrt(na) * @sqrt(nb)));
}

const NVEC = 8;

const VariantResult = struct {
    cos_gauss: f32,
    cos_heavy: f32,
};

// avg cosine of gemv(wq, x-or-sign(x)) vs gemv(wref, x) over NVEC vectors
fn runVariant(
    alloc: std.mem.Allocator,
    wref: Mat,
    wq: Mat,
    xs_gauss: []const []f32,
    xs_heavy: []const []f32,
    binarize_act: bool,
) !VariantResult {
    const y_ref = try alloc.alloc(f32, wref.rows);
    defer alloc.free(y_ref);
    const y_q = try alloc.alloc(f32, wref.rows);
    defer alloc.free(y_q);
    const x_act = try alloc.alloc(f32, wref.cols);
    defer alloc.free(x_act);

    var result: VariantResult = .{ .cos_gauss = 0, .cos_heavy = 0 };
    for ([2][]const []f32{ xs_gauss, xs_heavy }, 0..) |xs, dist| {
        var cos_sum: f32 = 0;
        for (xs) |x| {
            gemv(wref, x, y_ref);
            if (binarize_act) {
                // engine.zig: bit = (x > 0) -> ±1 in the XNOR dot
                for (x, 0..) |v, i| x_act[i] = if (v > 0) 1.0 else -1.0;
                gemv(wq, x_act, y_q);
            } else {
                gemv(wq, x, y_q);
            }
            cos_sum += cosine(y_ref, y_q);
        }
        const avg = cos_sum / NVEC;
        if (dist == 0) result.cos_gauss = avg else result.cos_heavy = avg;
    }
    return result;
}

fn makeActivations(alloc: std.mem.Allocator, rng: *std.Random.DefaultPrng, dim: usize, heavy: bool) ![][]f32 {
    const xs = try alloc.alloc([]f32, NVEC);
    const r = rng.random();
    for (0..NVEC) |v| {
        xs[v] = try alloc.alloc(f32, dim);
        for (xs[v]) |*e| e.* = r.floatNorm(f32);
        if (heavy) {
            // ~1% outlier channels x20, transformer-style
            const n_out = @max(dim / 100, 1);
            for (0..n_out) |_| {
                xs[v][r.uintLessThan(usize, dim)] *= 20.0;
            }
        }
    }
    return xs;
}

fn freeActivations(alloc: std.mem.Allocator, xs: [][]f32) void {
    for (xs) |x| alloc.free(x);
    alloc.free(xs);
}

// ---------- per-tensor experiment ----------

const Job = struct {
    shard: usize,
    name: []const u8, // weight tensor name; ".scale" sibling derived for fp8/fp4
};

fn weightStats(w: Mat) struct { mean_abs: f32, frac_zero: f32 } {
    var sum_abs: f64 = 0;
    var n_zero: usize = 0;
    for (w.data) |v| {
        sum_abs += @abs(v);
        if (v == 0) n_zero += 1;
    }
    const n: f64 = @floatFromInt(w.data.len);
    return .{
        .mean_abs = @floatCast(sum_abs / n),
        .frac_zero = @floatCast(@as(f64, @floatFromInt(n_zero)) / n),
    };
}

pub fn loadDequant(alloc: std.mem.Allocator, st: *safetensors.SafetensorsFile, name: []const u8) !?Mat {
    const w_t = st.tensors.get(name) orelse return null;
    var name_buf: [256]u8 = undefined;
    if (std.mem.eql(u8, w_t.dtype, "F8_E4M3")) {
        const scale_name = try std.fmt.bufPrint(&name_buf, "{s}.scale", .{name[0 .. name.len - ".weight".len]});
        const s_t = st.tensors.get(scale_name) orelse return error.ScaleNotFound;
        return try dequantFp8(alloc, w_t, s_t);
    } else if (std.mem.eql(u8, w_t.dtype, "I8")) {
        const scale_name = try std.fmt.bufPrint(&name_buf, "{s}.scale", .{name[0 .. name.len - ".weight".len]});
        const s_t = st.tensors.get(scale_name) orelse return error.ScaleNotFound;
        return try dequantFp4(alloc, w_t, s_t);
    } else if (std.mem.eql(u8, w_t.dtype, "BF16")) {
        return try dequantBf16(alloc, w_t);
    }
    return null;
}

fn runJob(alloc: std.mem.Allocator, st: *safetensors.SafetensorsFile, name: []const u8, stdout: anytype, rng: *std.Random.DefaultPrng, block_sweep: bool) !void {
    const w_t = st.tensors.get(name) orelse {
        try stdout.print("{s}: NOT FOUND\n", .{name});
        return;
    };
    const wref = (try loadDequant(alloc, st, name)) orelse {
        try stdout.print("{s}: unsupported dtype {s}\n", .{ name, w_t.dtype });
        return;
    };
    defer wref.deinit(alloc);

    const stats = weightStats(wref);

    const xs_gauss = try makeActivations(alloc, rng, wref.cols, false);
    defer freeActivations(alloc, xs_gauss);
    const xs_heavy = try makeActivations(alloc, rng, wref.cols, true);
    defer freeActivations(alloc, xs_heavy);

    const w1 = try quantize1bit(alloc, wref, 64);
    const a = try runVariant(alloc, wref, w1, xs_gauss, xs_heavy, false);
    const b = try runVariant(alloc, wref, w1, xs_gauss, xs_heavy, true);
    w1.deinit(alloc);

    const wt = try quantizeTernary(alloc, wref, 64);
    const c = try runVariant(alloc, wref, wt, xs_gauss, xs_heavy, false);
    const d = try runVariant(alloc, wref, wt, xs_gauss, xs_heavy, true);
    wt.deinit(alloc);

    try stdout.print(
        "{s:<42} {s:<7} [{d:>5}x{d:<5}] z={d:.3} | A {d:.4}/{d:.4} | B {d:.4}/{d:.4} | C {d:.4}/{d:.4} | D {d:.4}/{d:.4}\n",
        .{ name, w_t.dtype, wref.rows, wref.cols, stats.frac_zero, a.cos_gauss, a.cos_heavy, b.cos_gauss, b.cos_heavy, c.cos_gauss, c.cos_heavy, d.cos_gauss, d.cos_heavy },
    );

    if (block_sweep) {
        try stdout.print("  block sweep (variant A, gauss/heavy):", .{});
        for ([4]usize{ 16, 32, 128, 256 }) |blk| {
            const wq = try quantize1bit(alloc, wref, blk);
            const r = try runVariant(alloc, wref, wq, xs_gauss, xs_heavy, false);
            wq.deinit(alloc);
            try stdout.print("  b{d}={d:.4}/{d:.4}", .{ blk, r.cos_gauss, r.cos_heavy });
        }
        try stdout.print("\n", .{});
    }
}

// round 2: residual bitplanes + Hadamard activation rotation.
// goal: break the sqrt(2/pi)=0.798 single-plane wall while staying XOR-native.
fn runRound2Job(alloc: std.mem.Allocator, st: *safetensors.SafetensorsFile, name: []const u8, stdout: anytype, rng: *std.Random.DefaultPrng) !void {
    const wref = (try loadDequant(alloc, st, name)) orelse {
        try stdout.print("{s}: NOT FOUND / unsupported\n", .{name});
        return;
    };
    defer wref.deinit(alloc);

    const xs_gauss = try makeActivations(alloc, rng, wref.cols, false);
    defer freeActivations(alloc, xs_gauss);
    const xs_heavy = try makeActivations(alloc, rng, wref.cols, true);
    defer freeActivations(alloc, xs_heavy);

    try stdout.print("{s} [{d}x{d}]\n", .{ name, wref.rows, wref.cols });

    // bitplanes, real activations
    try stdout.print("  planes act:f32   ", .{});
    for (1..5) |k| {
        const wq = try quantizeBitplanes(alloc, wref, 64, k);
        defer wq.deinit(alloc);
        const r = try runVariant(alloc, wref, wq, xs_gauss, xs_heavy, false);
        try stdout.print("P{d}={d:.4}/{d:.4}  ", .{ k, r.cos_gauss, r.cos_heavy });
    }
    try stdout.print("\n", .{});

    // bitplanes, 1-bit activations with per-64 scale (XOR-native runtime)
    const y_ref = try alloc.alloc(f32, wref.rows);
    defer alloc.free(y_ref);
    const y_q = try alloc.alloc(f32, wref.rows);
    defer alloc.free(y_q);
    const x_act = try alloc.alloc(f32, wref.cols);
    defer alloc.free(x_act);

    try stdout.print("  planes act:1b64  ", .{});
    for (2..4) |k| {
        const wq = try quantizeBitplanes(alloc, wref, 64, k);
        defer wq.deinit(alloc);
        for ([2][]const []f32{ xs_gauss, xs_heavy }, 0..) |xs, dist| {
            var cos_sum: f32 = 0;
            for (xs) |x| {
                gemv(wref, x, y_ref);
                binarizeActScaled(x, x_act, 64);
                gemv(wq, x_act, y_q);
                cos_sum += cosine(y_ref, y_q);
            }
            const tag: []const u8 = if (dist == 0) "g" else "h";
            try stdout.print("P{d}{s}={d:.4}  ", .{ k, tag, cos_sum / NVEC });
        }
    }
    try stdout.print("\n", .{});

    // both sides multi-plane: Pk weights x Pk acts, all XNOR at runtime
    try stdout.print("  planes act:Pk64  ", .{});
    for (2..4) |k| {
        const wq = try quantizeBitplanes(alloc, wref, 64, k);
        defer wq.deinit(alloc);
        for ([2][]const []f32{ xs_gauss, xs_heavy }, 0..) |xs, dist| {
            var cos_sum: f32 = 0;
            for (xs) |x| {
                gemv(wref, x, y_ref);
                binarizeActPlanes(x, x_act, 64, k);
                gemv(wq, x_act, y_q);
                cos_sum += cosine(y_ref, y_q);
            }
            const tag: []const u8 = if (dist == 0) "g" else "h";
            try stdout.print("P{d}wP{d}a{s}={d:.4}  ", .{ k, k, tag, cos_sum / NVEC });
        }
    }
    try stdout.print("\n", .{});

    // Hadamard + both sides multi-plane (outlier-proof + XOR-native)
    {
        const chunk2 = hadamardChunkFor(wref.cols);
        const wrot2 = Mat{ .data = try alloc.dupe(f32, wref.data), .rows = wref.rows, .cols = wref.cols };
        defer wrot2.deinit(alloc);
        rotateRows(wrot2, chunk2);
        const x_rot2 = try alloc.alloc(f32, wref.cols);
        defer alloc.free(x_rot2);
        try stdout.print("  H+PkwPka 1b64    ", .{});
        for (2..4) |k| {
            const wq = try quantizeBitplanes(alloc, wrot2, 64, k);
            defer wq.deinit(alloc);
            for ([2][]const []f32{ xs_gauss, xs_heavy }, 0..) |xs, dist| {
                var cos_sum: f32 = 0;
                for (xs) |x| {
                    gemv(wref, x, y_ref);
                    @memcpy(x_rot2, x);
                    fwhtChunks(x_rot2, chunk2);
                    binarizeActPlanes(x_rot2, x_act, 64, k);
                    gemv(wq, x_act, y_q);
                    cos_sum += cosine(y_ref, y_q);
                }
                const tag: []const u8 = if (dist == 0) "g" else "h";
                try stdout.print("HP{d}{s}={d:.4}  ", .{ k, tag, cos_sum / NVEC });
            }
        }
        try stdout.print("\n", .{});
    }

    // Hadamard-rotated: W' = W*H^T binarized, x' = H x binarized (per-64 scale)
    const chunk = hadamardChunkFor(wref.cols);
    const wrot = Mat{ .data = try alloc.dupe(f32, wref.data), .rows = wref.rows, .cols = wref.cols };
    defer wrot.deinit(alloc);
    rotateRows(wrot, chunk);

    const x_rot = try alloc.alloc(f32, wref.cols);
    defer alloc.free(x_rot);

    try stdout.print("  H(c{d}) act:1b64 ", .{chunk});
    for (2..4) |k| {
        const wq = try quantizeBitplanes(alloc, wrot, 64, k);
        defer wq.deinit(alloc);
        for ([2][]const []f32{ xs_gauss, xs_heavy }, 0..) |xs, dist| {
            var cos_sum: f32 = 0;
            for (xs) |x| {
                gemv(wref, x, y_ref);
                @memcpy(x_rot, x);
                fwhtChunks(x_rot, chunk);
                binarizeActScaled(x_rot, x_act, 64);
                gemv(wq, x_act, y_q);
                cos_sum += cosine(y_ref, y_q);
            }
            const tag: []const u8 = if (dist == 0) "g" else "h";
            try stdout.print("HP{d}{s}={d:.4}  ", .{ k, tag, cos_sum / NVEC });
        }
    }
    try stdout.print("\n", .{});
}

const ActMode = union(enum) {
    full: void, // f32 activations
    planes: struct { k: usize, blk: usize },
    int8: usize, // block size
};

const WMode = union(enum) {
    greedy: usize, // planes
    refit: struct { k: usize, alternations: usize },
};

// one full pipeline evaluation: optional sign-diag + Hadamard on both sides,
// weight quantization, activation quantization, cosine vs untouched reference
fn evalConfig(
    alloc: std.mem.Allocator,
    wref: Mat,
    xs_gauss: []const []f32,
    xs_heavy: []const []f32,
    chunk: usize, // 0 = no rotation
    signdiag: bool,
    wmode: WMode,
    act: ActMode,
) !VariantResult {
    var wwork = Mat{ .data = try alloc.dupe(f32, wref.data), .rows = wref.rows, .cols = wref.cols };
    defer wwork.deinit(alloc);
    if (signdiag) applySignDiagCols(wwork);
    if (chunk > 0) rotateRows(wwork, chunk);
    const wq = switch (wmode) {
        .greedy => |k| try quantizeBitplanes(alloc, wwork, 64, k),
        .refit => |r| try quantizeBitplanesRefit(alloc, wwork, 64, r.k, r.alternations),
    };
    defer wq.deinit(alloc);

    const y_ref = try alloc.alloc(f32, wref.rows);
    defer alloc.free(y_ref);
    const y_q = try alloc.alloc(f32, wref.rows);
    defer alloc.free(y_q);
    const x_t = try alloc.alloc(f32, wref.cols);
    defer alloc.free(x_t);
    const x_act = try alloc.alloc(f32, wref.cols);
    defer alloc.free(x_act);

    var result: VariantResult = .{ .cos_gauss = 0, .cos_heavy = 0 };
    for ([2][]const []f32{ xs_gauss, xs_heavy }, 0..) |xs, dist| {
        var cos_sum: f32 = 0;
        for (xs) |x| {
            gemv(wref, x, y_ref);
            @memcpy(x_t, x);
            if (signdiag) applySignDiagVec(x_t);
            if (chunk > 0) fwhtChunks(x_t, chunk);
            switch (act) {
                .full => @memcpy(x_act, x_t),
                .planes => |p| binarizeActPlanes(x_t, x_act, p.blk, p.k),
                .int8 => |blk| quantizeActInt8(x_t, x_act, blk),
            }
            gemv(wq, x_act, y_q);
            cos_sum += cosine(y_ref, y_q);
        }
        const avg = cos_sum / NVEC;
        if (dist == 0) result.cos_gauss = avg else result.cos_heavy = avg;
    }
    return result;
}

// E1+E2+E5
fn runRound3Job(alloc: std.mem.Allocator, st: *safetensors.SafetensorsFile, name: []const u8, stdout: anytype, rng: *std.Random.DefaultPrng) !void {
    const wref = (try loadDequant(alloc, st, name)) orelse {
        try stdout.print("{s}: NOT FOUND\n", .{name});
        return;
    };
    defer wref.deinit(alloc);
    const xs_gauss = try makeActivations(alloc, rng, wref.cols, false);
    defer freeActivations(alloc, xs_gauss);
    const xs_heavy = try makeActivations(alloc, rng, wref.cols, true);
    defer freeActivations(alloc, xs_heavy);
    const chunk = hadamardChunkFor(wref.cols);
    try stdout.print("{s} [{d}x{d}] chunk={d}\n", .{ name, wref.rows, wref.cols, chunk });

    // E1: greedy vs refit vs refit+regreedy (act f32, no rotation needed)
    try stdout.print("  E1 w-only      ", .{});
    for ([2]usize{ 2, 3 }) |k| {
        const g_ = try evalConfig(alloc, wref, xs_gauss, xs_heavy, 0, false, .{ .greedy = k }, .full);
        const r0 = try evalConfig(alloc, wref, xs_gauss, xs_heavy, 0, false, .{ .refit = .{ .k = k, .alternations = 0 } }, .full);
        const r2 = try evalConfig(alloc, wref, xs_gauss, xs_heavy, 0, false, .{ .refit = .{ .k = k, .alternations = 2 } }, .full);
        try stdout.print("P{d}: greedy={d:.4} refit={d:.4} alt2={d:.4}  ", .{ k, g_.cos_gauss, r0.cos_gauss, r2.cos_gauss });
    }
    try stdout.print("\n", .{});

    // E2: act budget under H rotation, P3 refit weights
    const wm = WMode{ .refit = .{ .k = 3, .alternations = 2 } };
    try stdout.print("  E2 acts (H+P3w)", .{});
    inline for (.{ 1, 2, 3, 4 }) |ak| {
        const r = try evalConfig(alloc, wref, xs_gauss, xs_heavy, chunk, false, wm, .{ .planes = .{ .k = ak, .blk = 64 } });
        try stdout.print(" aP{d}={d:.4}/{d:.4}", .{ ak, r.cos_gauss, r.cos_heavy });
    }
    {
        const r32 = try evalConfig(alloc, wref, xs_gauss, xs_heavy, chunk, false, wm, .{ .planes = .{ .k = 3, .blk = 32 } });
        const r128 = try evalConfig(alloc, wref, xs_gauss, xs_heavy, chunk, false, wm, .{ .planes = .{ .k = 3, .blk = 128 } });
        const ri8 = try evalConfig(alloc, wref, xs_gauss, xs_heavy, chunk, false, wm, .{ .int8 = 64 });
        const rfull = try evalConfig(alloc, wref, xs_gauss, xs_heavy, chunk, false, wm, .full);
        try stdout.print("\n  E2 cont.        aP3b32={d:.4}/{d:.4} aP3b128={d:.4}/{d:.4} aInt8={d:.4}/{d:.4} aF32={d:.4}/{d:.4}\n", .{ r32.cos_gauss, r32.cos_heavy, r128.cos_gauss, r128.cos_heavy, ri8.cos_gauss, ri8.cos_heavy, rfull.cos_gauss, rfull.cos_heavy });
    }

    // E5: rotation design at P3w/P3a-b64
    const am = ActMode{ .planes = .{ .k = 3, .blk = 64 } };
    try stdout.print("  E5 rotation    ", .{});
    {
        const none = try evalConfig(alloc, wref, xs_gauss, xs_heavy, 0, false, wm, am);
        try stdout.print(" none={d:.4}/{d:.4}", .{ none.cos_gauss, none.cos_heavy });
        for ([3]usize{ 256, 1024, 4096 }) |c| {
            if (wref.cols % c != 0) continue;
            const r = try evalConfig(alloc, wref, xs_gauss, xs_heavy, c, false, wm, am);
            try stdout.print(" H{d}={d:.4}/{d:.4}", .{ c, r.cos_gauss, r.cos_heavy });
        }
        const sd = try evalConfig(alloc, wref, xs_gauss, xs_heavy, chunk, true, wm, am);
        try stdout.print(" sdH{d}={d:.4}/{d:.4}\n", .{ chunk, sd.cos_gauss, sd.cos_heavy });
    }
}

// E3: sensitivity of every tensor class at P1..P4 (act f32)
fn runRound4Job(alloc: std.mem.Allocator, st: *safetensors.SafetensorsFile, name: []const u8, stdout: anytype, rng: *std.Random.DefaultPrng) !void {
    const wref = (try loadDequant(alloc, st, name)) orelse {
        try stdout.print("{s:<48} NOT FOUND / unsupported\n", .{name});
        return;
    };
    defer wref.deinit(alloc);
    const xs_gauss = try makeActivations(alloc, rng, wref.cols, false);
    defer freeActivations(alloc, xs_gauss);
    const xs_heavy = try makeActivations(alloc, rng, wref.cols, true);
    defer freeActivations(alloc, xs_heavy);
    try stdout.print("{s:<48} [{d:>5}x{d:<5}]", .{ name, wref.rows, wref.cols });
    for (1..5) |k| {
        const r = try evalConfig(alloc, wref, xs_gauss, xs_heavy, 0, false, .{ .refit = .{ .k = k, .alternations = 2 } }, .full);
        try stdout.print(" P{d}={d:.4}", .{ k, r.cos_gauss });
    }
    try stdout.print("\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    var rng = std.Random.DefaultPrng.init(42);

    var args = std.process.args();
    _ = args.skip();
    const mode: []const u8 = args.next() orelse "round1";
    const round2 = std.mem.eql(u8, mode, "round2");

    if (std.mem.eql(u8, mode, "round3")) {
        try stdout.print("=== ROUND 3 (E1 refit / E2 act budget / E5 rotation design) ===\n", .{});
        try stdout.print("cells: gaussian/heavy-tail cosine\n\n", .{});
        var timer = try std.time.Timer.start();
        const st = try safetensors.SafetensorsFile.load(alloc, shardPath(2));
        defer st.deinit();
        const jobs = [_][]const u8{
            "layers.0.attn.wkv.weight",
            "layers.0.ffn.shared_experts.w1.weight",
            "layers.0.ffn.experts.0.w1.weight",
        };
        for (jobs) |name| try runRound3Job(alloc, st, name, stdout, &rng);
        try stdout.print("\ntotal time: {d:.1}s\n", .{@as(f64, @floatFromInt(timer.read())) / 1e9});
        return;
    }

    if (std.mem.eql(u8, mode, "round4")) {
        try stdout.print("=== ROUND 4 (E3 per-tensor-class sensitivity, refit planes, act f32) ===\n\n", .{});
        var timer = try std.time.Timer.start();
        const st = try safetensors.SafetensorsFile.load(alloc, shardPath(5));
        defer st.deinit();
        const jobs = [_][]const u8{
            "layers.3.attn.wq_a.weight",
            "layers.3.attn.wq_b.weight",
            "layers.3.attn.wkv.weight",
            "layers.3.attn.wo_a.weight",
            "layers.3.attn.wo_b.weight",
            "layers.3.attn.compressor.wkv.weight",
            "layers.3.attn.compressor.wgate.weight",
            "layers.3.ffn.gate.weight",
            "layers.3.ffn.shared_experts.w1.weight",
            "layers.3.ffn.shared_experts.w2.weight",
            "layers.3.ffn.shared_experts.w3.weight",
            "layers.3.ffn.experts.0.w1.weight",
            "layers.3.ffn.experts.0.w2.weight",
            "layers.3.ffn.experts.0.w3.weight",
            "layers.3.ffn.experts.100.w1.weight",
        };
        for (jobs) |name| try runRound4Job(alloc, st, name, stdout, &rng);
        try stdout.print("\ntotal time: {d:.1}s\n", .{@as(f64, @floatFromInt(timer.read())) / 1e9});
        return;
    }

    if (round2) {
        try stdout.print("=== ROUND 2: residual XOR bitplanes + Hadamard rotation ===\n", .{});
        try stdout.print("Pk = k bitplanes (each plane is XNOR+popcount). H = block-Hadamard rotation.\n", .{});
        try stdout.print("act:f32 = real activations; act:1b64 = sign(x)*mean|x| per 64 (XOR-native)\n", .{});
        try stdout.print("g = gaussian acts, h = heavy-tail acts\n\n", .{});
        var timer = try std.time.Timer.start();
        const st = try safetensors.SafetensorsFile.load(alloc, shardPath(2));
        defer st.deinit();
        const jobs = [_][]const u8{
            "layers.0.attn.wkv.weight",
            "layers.0.attn.wq_b.weight",
            "layers.0.ffn.shared_experts.w1.weight",
            "layers.0.ffn.experts.0.w1.weight",
        };
        for (jobs) |name| try runRound2Job(alloc, st, name, stdout, &rng);
        const elapsed = @as(f64, @floatFromInt(timer.read())) / 1e9;
        try stdout.print("\ntotal time: {d:.1}s\n", .{elapsed});
        return;
    }

    try stdout.print("=== SIGNAL SURVIVAL: DeepSeek V4 Pro 1-bit/ternary quantization ===\n", .{});
    try stdout.print("cosine(reference fp32 GEMV, quantized GEMV), avg over {d} vectors\n", .{NVEC});
    try stdout.print("A: w1bit+act_f32  B: w1bit+act_1bit(XNOR)  C: ternary+act_f32  D: ternary+act_1bit\n", .{});
    try stdout.print("each cell: gaussian / heavy-tail(1% channels x20)   z = fraction of exact-zero weights\n\n", .{});

    const layer0_jobs = [_][]const u8{
        "layers.0.attn.wq_a.weight",
        "layers.0.attn.wq_b.weight",
        "layers.0.attn.wkv.weight",
        "layers.0.attn.wo_a.weight",
        "layers.0.attn.wo_b.weight",
        "layers.0.attn.compressor.wkv.weight",
        "layers.0.ffn.shared_experts.w1.weight",
        "layers.0.ffn.shared_experts.w2.weight",
        "layers.0.ffn.experts.0.w1.weight",
        "layers.0.ffn.experts.0.w2.weight",
        "layers.0.ffn.experts.0.w3.weight",
        "layers.0.ffn.experts.7.w1.weight",
    };
    const layer30_jobs = [_][]const u8{
        "layers.30.attn.wq_b.weight",
        "layers.30.attn.wkv.weight",
        "layers.30.ffn.shared_experts.w1.weight",
        "layers.30.ffn.experts.0.w1.weight",
        "layers.30.ffn.experts.0.w2.weight",
    };

    var timer = try std.time.Timer.start();

    {
        try stdout.print("--- layer 0 (shard 2) ---\n", .{});
        const st = try safetensors.SafetensorsFile.load(alloc, shardPath(2));
        defer st.deinit();
        for (layer0_jobs, 0..) |name, i| {
            // sweep block sizes on one fp8 and one fp4 tensor
            const sweep = (i == 2) or (i == 8);
            try runJob(alloc, st, name, stdout, &rng, sweep);
        }
    }
    {
        try stdout.print("--- layer 30 (shard 32) ---\n", .{});
        const st = try safetensors.SafetensorsFile.load(alloc, shardPath(32));
        defer st.deinit();
        for (layer30_jobs) |name| {
            try runJob(alloc, st, name, stdout, &rng, false);
        }
    }

    const elapsed = @as(f64, @floatFromInt(timer.read())) / 1e9;
    try stdout.print("\ntotal time: {d:.1}s\n", .{elapsed});
}
