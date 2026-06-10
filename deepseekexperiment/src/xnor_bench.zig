// E8: real packed-kernel throughput on this CPU.
//
// Kernels, all on a [3072x7168] expert-shaped matrix:
//   A: f32 GEMV (SIMD)                                  — dequantized baseline
//   B: 3-bitplane weights (packed u64) x int8 acts       — recommended format
//   C: 3-bitplane weights x 3-bitplane acts (pure XNOR)  — popcount only
//   D: fp4 -> f32 dequant GEMV (decode-on-read baseline)
// Plus: FWHT throughput, fp4->packed-bitplane conversion throughput.
//
// Output: ms per expert visit (w1+w3+w2 = 66M weights) per kernel, and a
// per-token compute estimate for 7 experts x 61 layers.

const std = @import("std");
const ss = @import("signal_survival.zig");

const ROWS = 3072;
const COLS = 7168;
const BLOCK = 64;
const PLANES = 3;

const PackedPlanes = struct {
    bits: []u64, // [plane][row][col/64]
    scales: []f32, // [plane][row][col/64]
    rows: usize,
    cols: usize,

    fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        alloc.free(self.bits);
        alloc.free(self.scales);
    }
};

fn packPlanes(alloc: std.mem.Allocator, w: ss.Mat) !PackedPlanes {
    const words_per_row = w.cols / 64;
    const n = PLANES * w.rows * words_per_row;
    var p = PackedPlanes{
        .bits = try alloc.alloc(u64, n),
        .scales = try alloc.alloc(f32, n),
        .rows = w.rows,
        .cols = w.cols,
    };
    const resid = try alloc.alloc(f32, w.cols);
    defer alloc.free(resid);
    for (0..w.rows) |r| {
        @memcpy(resid, w.data[r * w.cols .. (r + 1) * w.cols]);
        for (0..PLANES) |pl| {
            const base = pl * w.rows * words_per_row + r * words_per_row;
            var c: usize = 0;
            while (c < w.cols) : (c += BLOCK) {
                var sum_abs: f32 = 0;
                for (resid[c .. c + BLOCK]) |v| sum_abs += @abs(v);
                const scale = sum_abs / BLOCK;
                var bits: u64 = 0;
                for (0..BLOCK) |j| {
                    if (resid[c + j] > 0) {
                        bits |= @as(u64, 1) << @intCast(j);
                        resid[c + j] -= scale;
                    } else {
                        resid[c + j] += scale;
                    }
                }
                p.bits[base + c / 64] = bits;
                p.scales[base + c / 64] = scale;
            }
        }
    }
    return p;
}

// int8 acts with per-block scale
fn quantActInt8(x: []const f32, q: []i8, scales: []f32) void {
    var c: usize = 0;
    while (c < x.len) : (c += BLOCK) {
        var amax: f32 = 0;
        for (x[c .. c + BLOCK]) |v| amax = @max(amax, @abs(v));
        const s = if (amax > 0) amax / 127.0 else 1.0;
        scales[c / BLOCK] = s;
        for (0..BLOCK) |j| q[c + j] = @intFromFloat(@round(std.math.clamp(x[c + j] / s, -127, 127)));
    }
}

// kernel B: per plane, per 64-block: sum(+-x_int8) * wscale * ascale
fn gemvPlanesInt8(p: PackedPlanes, xq: []const i8, xs: []const f32, y: []f32) void {
    const words = p.cols / 64;
    for (0..p.rows) |r| {
        var acc: f32 = 0;
        for (0..PLANES) |pl| {
            const base = pl * p.rows * words + r * words;
            for (0..words) |w| {
                const bits = p.bits[base + w];
                const xv: @Vector(64, i8) = xq[w * 64 ..][0..64].*;
                const mask: @Vector(64, bool) = @bitCast(bits);
                const signed = @select(i8, mask, xv, -% xv);
                const wide: @Vector(64, i16) = signed;
                const blocksum: i32 = @reduce(.Add, @as(@Vector(64, i32), wide));
                acc += @as(f32, @floatFromInt(blocksum)) * p.scales[base + w] * xs[w];
            }
        }
        y[r] = acc;
    }
}

// activation bitplanes (3) packed
const ActPlanes = struct {
    bits: [PLANES][]u64,
    scales: [PLANES][]f32,
};

fn quantActPlanes(alloc: std.mem.Allocator, x: []const f32) !ActPlanes {
    const words = x.len / 64;
    var a: ActPlanes = undefined;
    const resid = try alloc.alloc(f32, x.len);
    defer alloc.free(resid);
    @memcpy(resid, x);
    for (0..PLANES) |pl| {
        a.bits[pl] = try alloc.alloc(u64, words);
        a.scales[pl] = try alloc.alloc(f32, words);
        var c: usize = 0;
        while (c < x.len) : (c += BLOCK) {
            var sum_abs: f32 = 0;
            for (resid[c .. c + BLOCK]) |v| sum_abs += @abs(v);
            const scale = sum_abs / BLOCK;
            var bits: u64 = 0;
            for (0..BLOCK) |j| {
                if (resid[c + j] > 0) {
                    bits |= @as(u64, 1) << @intCast(j);
                    resid[c + j] -= scale;
                } else {
                    resid[c + j] += scale;
                }
            }
            a.bits[pl][c / 64] = bits;
            a.scales[pl][c / 64] = scale;
        }
    }
    return a;
}

// kernel C: pure XNOR popcount, 9 plane combos
fn gemvXnor(p: PackedPlanes, a: ActPlanes, y: []f32) void {
    const words = p.cols / 64;
    for (0..p.rows) |r| {
        var acc: f32 = 0;
        for (0..PLANES) |wp| {
            const base = wp * p.rows * words + r * words;
            for (0..PLANES) |ap| {
                const abits = a.bits[ap];
                const ascales = a.scales[ap];
                for (0..words) |w| {
                    const xnor = ~(p.bits[base + w] ^ abits[w]);
                    const pop: i32 = @popCount(xnor);
                    acc += @as(f32, @floatFromInt(2 * pop - 64)) * p.scales[base + w] * ascales[w];
                }
            }
        }
        y[r] = acc;
    }
}

// kernel A: straightforward SIMD f32 GEMV
fn gemvF32(w: ss.Mat, x: []const f32, y: []f32) void {
    const V = 8;
    for (0..w.rows) |r| {
        const row = w.data[r * w.cols .. (r + 1) * w.cols];
        var acc: @Vector(V, f32) = @splat(0);
        var c: usize = 0;
        while (c + V <= w.cols) : (c += V) {
            const wv: @Vector(V, f32) = row[c..][0..V].*;
            const xv: @Vector(V, f32) = x[c..][0..V].*;
            acc += wv * xv;
        }
        y[r] = @reduce(.Add, acc);
    }
}

// kernel D: decode fp4 bytes + scale on the fly (simulated: random bytes)
fn gemvFp4Direct(wbytes: []const u8, scales: []const u8, x: []const f32, rows: usize, cols: usize, y: []f32) void {
    const byte_cols = cols / 2;
    const s_cols = cols / 32;
    for (0..rows) |r| {
        var acc: f32 = 0;
        for (0..byte_cols) |bc| {
            const b = wbytes[r * byte_cols + bc];
            const c0 = bc * 2;
            const sc = ss.e8m0_lut[scales[r * s_cols + c0 / 32]];
            acc += ss.fp4_lut[b & 15] * sc * x[c0];
            acc += ss.fp4_lut[b >> 4] * sc * x[c0 + 1];
        }
        y[r] = acc;
    }
}

fn bench(comptime f: anytype, args: anytype, reps: usize) f64 {
    var timer = std.time.Timer.start() catch unreachable;
    for (0..reps) |_| @call(.auto, f, args);
    return @as(f64, @floatFromInt(timer.read())) / 1e9 / @as(f64, @floatFromInt(reps));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== E8: packed kernel throughput ({d}x{d} expert-shaped matrix) ===\n\n", .{ ROWS, COLS });

    var rng = std.Random.DefaultPrng.init(7);
    const r = rng.random();

    // synthetic gaussian weights (kernel timing doesn't depend on values)
    const w = ss.Mat{ .data = try alloc.alloc(f32, ROWS * COLS), .rows = ROWS, .cols = COLS };
    defer alloc.free(w.data);
    for (w.data) |*v| v.* = r.floatNorm(f32) * 0.02;
    const x = try alloc.alloc(f32, COLS);
    defer alloc.free(x);
    for (x) |*v| v.* = r.floatNorm(f32);
    const y = try alloc.alloc(f32, ROWS);
    defer alloc.free(y);

    const n_weights: f64 = ROWS * COLS;

    // A: f32
    const tA = bench(gemvF32, .{ w, x, y }, 20);
    try stdout.print("A f32 GEMV            : {d:6.2} ms  ({d:.1} Gw/s, {d:.1} GB/s f32)\n", .{ tA * 1e3, n_weights / tA / 1e9, n_weights * 4 / tA / 1e9 });

    // B: planes x int8
    var pk = try packPlanes(alloc, w);
    defer pk.deinit(alloc);
    const xq = try alloc.alloc(i8, COLS);
    defer alloc.free(xq);
    const xsc = try alloc.alloc(f32, COLS / BLOCK);
    defer alloc.free(xsc);
    quantActInt8(x, xq, xsc);
    const tB = bench(gemvPlanesInt8, .{ pk, xq, xsc, y }, 20);
    try stdout.print("B P3w x int8a         : {d:6.2} ms  ({d:.1} Gw/s, {d:.2} GB/s of packed planes)\n", .{ tB * 1e3, n_weights / tB / 1e9, n_weights * PLANES / 8 / tB / 1e9 });

    // C: pure XNOR
    const ap = try quantActPlanes(alloc, x);
    defer for (0..PLANES) |pl| {
        alloc.free(ap.bits[pl]);
        alloc.free(ap.scales[pl]);
    };
    const tC = bench(gemvXnor, .{ pk, ap, y }, 20);
    try stdout.print("C P3w x P3a XNOR      : {d:6.2} ms  ({d:.1} Gw/s)\n", .{ tC * 1e3, n_weights / tC / 1e9 });

    // D: fp4 decode-on-read
    const wbytes = try alloc.alloc(u8, ROWS * COLS / 2);
    defer alloc.free(wbytes);
    r.bytes(wbytes);
    const wscales = try alloc.alloc(u8, ROWS * COLS / 32);
    defer alloc.free(wscales);
    @memset(wscales, 127);
    const tD = bench(gemvFp4Direct, .{ wbytes, wscales, x, ROWS, COLS, y }, 20);
    try stdout.print("D fp4 decode GEMV     : {d:6.2} ms  ({d:.1} Gw/s, {d:.2} GB/s of fp4)\n", .{ tD * 1e3, n_weights / tD / 1e9, n_weights / 2 / tD / 1e9 });

    // FWHT
    const tF = bench(ss.fwhtChunks, .{ x, 1024 }, 1000);
    try stdout.print("FWHT 7168 (c1024)     : {d:6.3} ms\n", .{tF * 1e3});

    // fp4 -> packed conversion (decode + 3-plane pack)
    var conv_timer = try std.time.Timer.start();
    {
        const wd = ss.Mat{ .data = try alloc.alloc(f32, ROWS * COLS), .rows = ROWS, .cols = COLS };
        defer alloc.free(wd.data);
        const byte_cols = COLS / 2;
        for (0..ROWS) |rr| {
            for (0..byte_cols) |bc| {
                const b = wbytes[rr * byte_cols + bc];
                wd.data[rr * COLS + bc * 2] = ss.fp4_lut[b & 15];
                wd.data[rr * COLS + bc * 2 + 1] = ss.fp4_lut[b >> 4];
            }
        }
        var pk2 = try packPlanes(alloc, wd);
        pk2.deinit(alloc);
    }
    const tConv = @as(f64, @floatFromInt(conv_timer.read())) / 1e9;
    try stdout.print("fp4->P3 conversion    : {d:6.1} ms per expert matrix ({d:.1} Mw/s)\n\n", .{ tConv * 1e3, n_weights / tConv / 1e6 });

    // per-token compute model: 7 experts x 3 matrices x 61 layers (this matrix
    // is w1-shaped; w2 same element count) + attention (~3.3B weights total)
    const expert_weights: f64 = 3.0 * n_weights; // one expert visit
    const per_token_weights = expert_weights * 7.0 * 61.0;
    inline for (.{ .{ "A f32", tA }, .{ "B P3xint8", tB }, .{ "C XNOR", tC }, .{ "D fp4", tD } }) |k| {
        const tok_ms = per_token_weights / (n_weights / k[1]) * 1e3;
        try stdout.print("per-token MoE compute, kernel {s}: {d:7.0} ms ({d:.2} tps compute-bound, 1 thread)\n", .{ k[0], tok_ms, 1000.0 / tok_ms });
    }
    try stdout.print("\n(multiply tps by ~10 for 12-core parallel GEMV)\n", .{});
}
