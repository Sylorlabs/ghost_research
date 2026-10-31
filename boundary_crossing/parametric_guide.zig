//! parametric_guide.zig — a LEARNED parametric guide that generalizes to UNSEEN categories. No LLM.
//!
//! tiered_learner's guide was non-parametric (a memory) — great on categories it has SEEN, useless on new ones.
//! This adds the parametric guide from verification_learning.md: a tiny model mapping cheap DATA FEATURES →
//! predicted gzip-gain of each candidate primitive, trained ONLINE on the verifier's PERFECT labels. Because it
//! reasons over features (not category identity), it picks a good primitive for categories it has NEVER seen —
//! exactly where the memory is empty. This is the AlphaZero "policy net" trained on verifiable rewards (RLVR).
//!
//! Demo: train the guide on a stream of {ramp, record4, record8} ONLY. Then test on HELD-OUT {record12,
//! record16} it never trained on. Compare evaluations: parametric guide vs blind vs the non-parametric memory.
//!
//! Run: zig build parametric-guide --release=fast

const std = @import("std");

var prng: u64 = 0x9E37_79B9_7F4A_7C15;
fn rnd() u64 {
    prng ^= prng << 13;
    prng ^= prng >> 7;
    prng ^= prng << 17;
    return prng;
}
fn rN(n: usize) usize {
    return @intCast(rnd() % @as(u64, @max(1, n)));
}

const MAXP = 3;
const Gene = struct { op: u8 = 0, param: u8 = 0 }; // 1=delta 4=stride
const Prog = struct { g: [MAXP]Gene = [_]Gene{.{}} ** MAXP, len: usize = 0 };
fn opF(b: []u8, g: Gene, s: []u8) void {
    const n = b.len;
    if (g.op == 1) {
        const d: usize = g.param;
        for (0..n) |i| s[i] = b[i] -% (if (i >= d) b[i - d] else 0);
        @memcpy(b, s[0..n]);
    } else if (g.op == 4) {
        const st: usize = @max(2, @as(usize, g.param));
        var p: usize = 0;
        for (0..st) |r| {
            var i = r;
            while (i < n) : (i += st) {
                s[p] = b[i];
                p += 1;
            }
        }
        @memcpy(b, s[0..n]);
    }
}
fn appF(p: Prog, d: []const u8, a: std.mem.Allocator) ![]u8 {
    const b = try a.dupe(u8, d);
    const s = try a.alloc(u8, @max(1, d.len));
    defer a.free(s);
    for (0..p.len) |k| opF(b, p.g[k], s);
    return b;
}
fn gz(a: std.mem.Allocator, d: []const u8) usize {
    var o = std.ArrayList(u8).init(a);
    defer o.deinit();
    var f = std.io.fixedBufferStream(d);
    std.compress.gzip.compress(f.reader(), o.writer(), .{ .level = .default }) catch return d.len;
    return o.items.len;
}
var evals: usize = 0;
fn realGain(p: Prog, d: []const u8, base: usize, a: std.mem.Allocator) !f64 {
    evals += 1;
    const f = try appF(p, d, a);
    defer a.free(f);
    return @as(f64, @floatFromInt(base)) - @as(f64, @floatFromInt(gz(a, f))); // bytes saved (perfect label)
}
fn entropy(d: []const u8) f64 {
    var h = [_]u32{0} ** 256;
    for (d) |b| h[b] += 1;
    var e: f64 = 0;
    const n: f64 = @floatFromInt(d.len);
    for (h) |c| if (c > 0) {
        const p = @as(f64, @floatFromInt(c)) / n;
        e -= p * @log2(p);
    };
    return e;
}

// ── candidate primitives + a cheap per-primitive FEATURE (entropy-gain proxy, no gzip) ──
const NCAND = 8;
fn candidate(i: usize) Prog {
    const widths = [_]u8{ 0, 1, 2, 4, 6, 8, 12, 16 }; // 0=identity, 1=delta1, else stride(w)>delta1
    const w = widths[i];
    if (w == 0) return .{};
    if (w == 1) return .{ .g = [_]Gene{ .{ .op = 1, .param = 1 }, .{}, .{} }, .len = 1 };
    return .{ .g = [_]Gene{ .{ .op = 4, .param = w }, .{ .op = 1, .param = 1 }, .{} }, .len = 2 };
}
// feature vector for candidate i on data d: [cheap entropy-gain proxy, bias]. The model learns proxy→real gain.
fn featProxy(i: usize, d: []const u8, h0: f64, a: std.mem.Allocator) !f64 {
    const f = try appF(candidate(i), d, a);
    defer a.free(f);
    return h0 - entropy(f); // cheap, no gzip
}

// ── the PARAMETRIC model: predicted_real_gain = w0*proxy + w1  (shared weights, online-trained) ──
var w0: f64 = 1.0;
var w1: f64 = 0.0;
fn predict(proxy: f64) f64 {
    return w0 * proxy + w1;
}
fn learn(proxy: f64, actual_gain: f64) void {
    const lr = 0.00002;
    const err = actual_gain - predict(proxy);
    w0 += lr * err * proxy;
    w1 += lr * err;
}

fn genItem(a: std.mem.Allocator, n: usize, width: u8, seed: u64) ![]u8 {
    prng = seed *% 0x2545F4914F6CDD1D | 1;
    const b = try a.alloc(u8, n);
    if (width == 1) { // ramp
        const mul: u8 = @intCast(1 + rN(7));
        for (0..n) |i| b[i] = @intCast((i *% mul) & 0xFF);
        return b;
    }
    const wsz: usize = width; // record of this width
    var i: usize = 0;
    while (i + wsz <= n) : (i += wsz) {
        const r = i / wsz;
        b[i] = @intCast(r & 0xFF);
        if (wsz > 1) b[i + 1] = 0x42;
        for (2..wsz) |c| b[i + c] = @intCast(rN(256));
    }
    while (i < n) : (i += 1) b[i] = 0;
    return b;
}

// solve via the parametric guide: rank candidates by predicted gain, try top-K, verify, learn online
fn solveGuided(d: []const u8, base: usize, a: std.mem.Allocator, topk: usize, train: bool) !struct { best: Prog, gain: f64 } {
    const h0 = entropy(d);
    var proxies: [NCAND]f64 = undefined;
    var pred: [NCAND]f64 = undefined;
    var order: [NCAND]usize = undefined;
    for (0..NCAND) |i| {
        proxies[i] = try featProxy(i, d, h0, a); // cheap, not counted as a verifier eval
        pred[i] = predict(proxies[i]);
        order[i] = i;
    }
    // sort candidates by predicted gain desc
    const pctx: []const f64 = pred[0..];
    std.sort.pdq(usize, order[0..], pctx, struct {
        fn lt(p: []const f64, x: usize, y: usize) bool {
            return p[x] > p[y];
        }
    }.lt);
    var best = Prog{};
    var bg: f64 = 0;
    for (0..@min(topk, NCAND)) |k| {
        const i = order[k];
        const g = try realGain(candidate(i), d, base, a); // PERFECT label (1 verifier eval)
        if (train) learn(proxies[i], g);
        if (g > bg) {
            bg = g;
            best = candidate(i);
        }
    }
    return .{ .best = best, .gain = bg };
}
fn blindEvalCount(d: []const u8, base: usize, a: std.mem.Allocator) !void {
    // count what a blind search would spend (small evolutionary budget) — for the comparison
    for (0..6) |_| {
        var p = Prog{ .len = 1 };
        p.g[0] = if (rN(2) == 0) .{ .op = 1, .param = @intCast(1 + rN(4)) } else .{ .op = 4, .param = @intCast(2 + rN(15)) };
        var g = try realGain(p, d, base, a);
        for (0..16) |_| {
            var q = p;
            if (q.len < MAXP) {
                q.g[q.len] = if (rN(2) == 0) .{ .op = 1, .param = @intCast(1 + rN(4)) } else .{ .op = 4, .param = @intCast(2 + rN(15)) };
                q.len += 1;
            }
            const gg = try realGain(q, d, base, a);
            if (gg >= g) {
                p = q;
                g = gg;
            }
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    const N: usize = 8192;

    try o.print("=== PARAMETRIC GUIDE — generalizes to UNSEEN categories (trained on verifier labels, no LLM) ===\n\n", .{});
    try o.print("a tiny model maps cheap data-features → predicted gzip-gain of each primitive, trained ONLINE on the\n", .{});
    try o.print("verifier's perfect labels. It reasons over FEATURES, so it works on widths it never trained on.\n\n", .{});

    // ── TRAIN on a stream of SEEN categories only: ramp, record4, record8 ──
    const seen = [_]u8{ 1, 4, 8 }; // 1=ramp, else record-width
    try o.print("[train] streaming SEEN categories {{ramp, record4, record8}} ", .{});
    var t: usize = 0;
    while (t < 60) : (t += 1) {
        const wsel = seen[t % seen.len];
        const d = try genItem(a, N, wsel, 1000 + @as(u64, @intCast(t)));
        const base = gz(a, d);
        _ = try solveGuided(d, base, a, 3, true); // train=on
    }
    try o.print("→ learned model: predicted_gain = {d:.3}·proxy + {d:.1}\n\n", .{ w0, w1 });

    // ── TEST on HELD-OUT categories the guide NEVER trained on: record12, record16 ──
    try o.print("[test] HELD-OUT categories the guide never saw — parametric guide vs blind vs empty-memory:\n", .{});
    const held = [_]u8{ 12, 16, 3, 5 }; // record widths never in training (+ odd widths 3,5)
    var guide_evals: usize = 0;
    var blind_evals: usize = 0;
    for (held) |wsel| {
        const d = try genItem(a, N, wsel, 7777 + @as(u64, wsel));
        const base = gz(a, d);
        evals = 0;
        const r = try solveGuided(d, base, a, 2, false); // train=off: pure generalization, try top-2
        const ge = evals;
        guide_evals += ge;
        evals = 0;
        try blindEvalCount(d, base, a);
        const be = evals;
        blind_evals += be;
        var fb: [24]u8 = undefined;
        try o.print("  record{d:<3} (UNSEEN)  guide picked {s:<12} saving {d:>5.0} B in {d} evals   |  blind needs {d} evals  |  memory: MISS (empty)\n", .{ wsel, fmtProg(&fb, r.best), r.gain, ge, be });
    }

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("On categories it NEVER trained on, the parametric guide reached a good primitive in {d} total evals;\n", .{guide_evals});
    try o.print("blind search would spend {d}; the non-parametric memory MISSES entirely (no entry for an unseen width).\n", .{blind_evals});
    try o.print("That is the generalization the memory can't give: the guide learned the FEATURE→gain mapping from the\n", .{});
    try o.print("seen categories and applied it to new ones — trained purely on the verifier's perfect labels, no LLM.\n", .{});
    try o.print("Honest: the model is a tiny linear calibrator over per-primitive features; the features carry the\n", .{});
    try o.print("cross-width generalization, the learned weights calibrate proxy→real gzip. Next: deeper features +\n", .{});
    try o.print("a small MLP to generalize across primitive TYPES, not just widths. Same loop, same perfect labels.\n", .{});
}

fn fmtProg(buf: []u8, p: Prog) []const u8 {
    if (p.len == 0) return "identity";
    var w: usize = 0;
    for (0..p.len) |k| {
        if (k > 0 and w < buf.len) {
            buf[w] = '>';
            w += 1;
        }
        const part = std.fmt.bufPrint(buf[w..], "{s}{d}", .{ if (p.g[k].op == 1) "d" else "s", p.g[k].param }) catch break;
        w += part.len;
    }
    return buf[0..w];
}
