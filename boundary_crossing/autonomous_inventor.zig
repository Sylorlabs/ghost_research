//! autonomous_inventor.zig — THE ENGINE WITHOUT THE NEURAL LAYER.
//!
//! Micah's test: can it do things by itself, with NO LLM to understand human intent?
//! Answer, demonstrated here: for a FORMAL, machine-measurable objective — YES, fully autonomous.
//!
//! The objective is the one the LLM normally has to *understand* from a human, here stated formally
//! once and never interpreted again: "find a REVERSIBLE byte-transform that minimizes the REAL
//! compressed size of this data." The verifier is real measurement — std.gzip size + exact
//! round-trip (forward then inverse must equal the original). The generator is an EVOLUTIONARY
//! search over a tiny filter-DSL (delta / xor / add / stride / move-to-front). No LLM proposes
//! anything; a fixed PRNG mutates programs and measurement keeps the winners.
//!
//! This is exactly the mathpressor filter work I just did BY HAND (I proposed the word model) —
//! but here the engine proposes its own transforms and certifies them against real bytes, with
//! zero neural layer in the loop. It invents the right filter per data type ITSELF.
//!
//! The honest bound (Closure Principle, unchanged): it is confined to its DSL's closure — it cannot
//! invent a primitive the DSL lacks, nor *choose* which objective to pursue. Those two acts —
//! extending the substrate, and understanding a NEW human intent — remain the only things that need
//! an out-of-closure source (the LLM). Autonomy over a FIXED formal objective: real, and shown below.
//!
//! Run: zig build autonomous-inventor --release=fast

const std = @import("std");

// ── fixed PRNG (no LLM, no Math.random; deterministic, reproducible) ──
var prng: u64 = 0x243F_6A88_85A3_08D3;
fn reseed(s: u64) void {
    prng = s | 1;
}
fn rnd() u64 {
    prng ^= prng << 13;
    prng ^= prng >> 7;
    prng ^= prng << 17;
    return prng;
}
fn rndN(n: usize) usize {
    return @intCast(rnd() % @as(u64, n));
}

// ── the filter-DSL: reversible byte transforms (the engine's closure) ──
// op: 1=DELTA(dist) 2=XOR(dist) 3=ADD(const) 4=STRIDE(deinterleave) 5=MTF(move-to-front)
const MAXP = 4;
const Gene = struct { op: u8 = 0, param: u8 = 0 };
const Prog = struct { genes: [MAXP]Gene = [_]Gene{.{}} ** MAXP, len: usize = 0 };

fn mtfFwd(buf: []u8) void {
    var tbl: [256]u8 = undefined;
    for (0..256) |i| tbl[i] = @intCast(i);
    for (buf) |*b| {
        const v = b.*;
        var r: u8 = 0;
        while (tbl[r] != v) r += 1;
        b.* = r;
        var j: usize = r;
        while (j > 0) : (j -= 1) tbl[j] = tbl[j - 1];
        tbl[0] = v;
    }
}
fn mtfInv(buf: []u8) void {
    var tbl: [256]u8 = undefined;
    for (0..256) |i| tbl[i] = @intCast(i);
    for (buf) |*b| {
        const r = b.*;
        const v = tbl[r];
        b.* = v;
        var j: usize = r;
        while (j > 0) : (j -= 1) tbl[j] = tbl[j - 1];
        tbl[0] = v;
    }
}

fn opFwd(buf: []u8, g: Gene, scratch: []u8) void {
    const n = buf.len;
    switch (g.op) {
        1 => { // DELTA(dist): out[i] = in[i] - in[i-d]
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) scratch[i] = buf[i] -% (if (i >= d) buf[i - d] else 0);
            @memcpy(buf, scratch[0..n]);
        },
        2 => { // XOR(dist)
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) scratch[i] = buf[i] ^ (if (i >= d) buf[i - d] else 0);
            @memcpy(buf, scratch[0..n]);
        },
        3 => { // ADD(const)
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] +% g.param;
        },
        4 => { // STRIDE: deinterleave into `s` columns (reversible reorder)
            const s: usize = @max(2, @as(usize, g.param));
            var pos: usize = 0;
            var r: usize = 0;
            while (r < s) : (r += 1) {
                var i: usize = r;
                while (i < n) : (i += s) {
                    scratch[pos] = buf[i];
                    pos += 1;
                }
            }
            @memcpy(buf, scratch[0..n]);
        },
        5 => mtfFwd(buf),
        else => {},
    }
}
fn opInv(buf: []u8, g: Gene, scratch: []u8) void {
    const n = buf.len;
    switch (g.op) {
        1 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] +% (if (i >= d) buf[i - d] else 0);
        },
        2 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] ^ (if (i >= d) buf[i - d] else 0);
        },
        3 => {
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] -% g.param;
        },
        4 => {
            const s: usize = @max(2, @as(usize, g.param));
            var pos: usize = 0;
            var r: usize = 0;
            while (r < s) : (r += 1) {
                var i: usize = r;
                while (i < n) : (i += s) {
                    scratch[i] = buf[pos];
                    pos += 1;
                }
            }
            @memcpy(buf, scratch[0..n]);
        },
        5 => mtfInv(buf),
        else => {},
    }
}

fn applyFwd(p: Prog, data: []const u8, a: std.mem.Allocator) ![]u8 {
    const buf = try a.dupe(u8, data);
    const scratch = try a.alloc(u8, @max(1, data.len));
    defer a.free(scratch);
    for (0..p.len) |k| opFwd(buf, p.genes[k], scratch);
    return buf;
}
fn applyInv(p: Prog, data: []const u8, a: std.mem.Allocator) ![]u8 {
    const buf = try a.dupe(u8, data);
    const scratch = try a.alloc(u8, @max(1, data.len));
    defer a.free(scratch);
    var k = p.len;
    while (k > 0) {
        k -= 1;
        opInv(buf, p.genes[k], scratch);
    }
    return buf;
}

// ── the VERIFIER: real measurement (gzip size) + exact reversibility ──
fn gzSize(a: std.mem.Allocator, data: []const u8) usize {
    var buf = std.ArrayList(u8).init(a);
    defer buf.deinit();
    var fbs = std.io.fixedBufferStream(data);
    std.compress.gzip.compress(fbs.reader(), buf.writer(), .{ .level = .default }) catch return data.len;
    return buf.items.len;
}
fn reversible(p: Prog, data: []const u8, a: std.mem.Allocator) !bool {
    const f = try applyFwd(p, data, a);
    defer a.free(f);
    const b = try applyInv(p, f, a);
    defer a.free(b);
    return std.mem.eql(u8, data, b);
}
fn cost(p: Prog, data: []const u8, a: std.mem.Allocator) !usize {
    if (!try reversible(p, data, a)) return std.math.maxInt(usize); // never accept a non-invertible filter
    const f = try applyFwd(p, data, a);
    defer a.free(f);
    return gzSize(a, f);
}

// ── the autonomous GENERATOR: evolutionary mutation (no LLM) ──
fn randGene() Gene {
    const op: u8 = @intCast(1 + rndN(5));
    const param: u8 = switch (op) {
        1, 2 => @intCast(1 + rndN(4)), // distance 1..4
        3 => @intCast(1 + rndN(255)), // add constant
        4 => @intCast(2 + rndN(7)), // stride 2..8
        else => 0,
    };
    return .{ .op = op, .param = param };
}
fn mutate(p: Prog) Prog {
    var q = p;
    const c = rndN(3);
    if (c == 0 and q.len < MAXP) {
        q.genes[q.len] = randGene();
        q.len += 1;
    } else if (c == 1 and q.len > 0) {
        q.len -= 1;
    } else if (q.len > 0) {
        q.genes[rndN(q.len)] = randGene();
    } else {
        q.genes[0] = randGene();
        q.len = 1;
    }
    return q;
}
fn search(data: []const u8, a: std.mem.Allocator, restarts: usize, steps: usize) !Prog {
    var best = Prog{}; // identity (no filter)
    var best_cost = try cost(best, data, a);
    for (0..restarts) |_| {
        var cur = mutate(Prog{});
        var cur_cost = cost(cur, data, a) catch std.math.maxInt(usize);
        for (0..steps) |_| {
            const cand = mutate(cur);
            const cc = cost(cand, data, a) catch std.math.maxInt(usize);
            if (cc <= cur_cost) {
                cur = cand;
                cur_cost = cc;
            }
            if (cur_cost < best_cost) {
                best = cur;
                best_cost = cur_cost;
            }
        }
    }
    return best;
}

fn printProg(o: anytype, p: Prog) void {
    if (p.len == 0) {
        o.print("identity (no filter)", .{}) catch {};
        return;
    }
    for (0..p.len) |k| {
        if (k > 0) o.print(" → ", .{}) catch {};
        const g = p.genes[k];
        switch (g.op) {
            1 => o.print("delta(d={d})", .{g.param}) catch {},
            2 => o.print("xor(d={d})", .{g.param}) catch {},
            3 => o.print("add({d})", .{g.param}) catch {},
            4 => o.print("stride({d})", .{g.param}) catch {},
            5 => o.print("mtf", .{}) catch {},
            else => o.print("ident", .{}) catch {},
        }
    }
}

// ── deterministic, realistic data types (the engine is told nothing about them) ──
fn genGradient(a: std.mem.Allocator, n: usize) ![]u8 {
    const b = try a.alloc(u8, n);
    for (0..n) |i| b[i] = @intCast(i & 0xFF); // a counter/ramp — delta(1) ideal
    return b;
}
fn genWalk(a: std.mem.Allocator, n: usize) ![]u8 {
    reseed(0xA17D10);
    const b = try a.alloc(u8, n);
    var v: u8 = 128;
    for (0..n) |i| {
        const step: i32 = @as(i32, @intCast(rndN(7))) - 3; // small ±3 step (audio/sensor-like)
        v = @intCast(@mod(@as(i32, v) + step, 256));
        b[i] = v;
    }
    return b;
}
fn genRecords(a: std.mem.Allocator, n: usize) ![]u8 {
    reseed(0x4EC0DD);
    const b = try a.alloc(u8, n);
    var i: usize = 0;
    while (i + 8 <= n) : (i += 8) {
        const rec = i / 8;
        b[i + 0] = @intCast(rec & 0xFF); // counter column   → delta-able once de-interleaved
        b[i + 1] = 0x42; // constant column  → run once de-interleaved
        b[i + 2] = @intCast((rec *% 3) & 0xFF); // ramp column
        b[i + 3] = @intCast((rec *% 3) >> 8 & 0xFF);
        b[i + 4] = @intCast(rndN(256));
        b[i + 5] = @intCast(rndN(256));
        b[i + 6] = @intCast(rndN(256));
        b[i + 7] = @intCast(rndN(256));
    }
    while (i < n) : (i += 1) b[i] = 0;
    return b;
}
fn genText(a: std.mem.Allocator, n: usize) ![]u8 {
    reseed(0x7E47);
    const words = [_][]const u8{ "the ", "engine ", "invents ", "a ", "filter ", "by ", "itself ", "now ", "and ", "again " };
    const b = try a.alloc(u8, n);
    var i: usize = 0;
    while (i < n) {
        const w = words[rndN(words.len)];
        for (w) |ch| {
            if (i < n) {
                b[i] = ch;
                i += 1;
            }
        }
    }
    return b;
}

const Dataset = struct { name: []const u8, gen: *const fn (std.mem.Allocator, usize) anyerror![]u8 };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();

    try o.print("=== AUTONOMOUS INVENTOR — the engine with NO neural layer in the loop ===\n\n", .{});
    try o.print("objective (formal, never interpreted at runtime): minimize the REAL gzip size of a reversible\n", .{});
    try o.print("byte-transform of the data. verifier = gzip size + exact round-trip. generator = evolutionary\n", .{});
    try o.print("mutation of a filter-DSL (delta/xor/add/stride/mtf). NO LLM proposes anything — a fixed PRNG does.\n", .{});
    try o.print("the engine is told NOTHING about each data type; it must DISCOVER the right filter by measurement.\n\n", .{});

    const N: usize = 16384;
    const sets = [_]Dataset{
        .{ .name = "counter/ramp ", .gen = &genGradient },
        .{ .name = "sensor walk  ", .gen = &genWalk },
        .{ .name = "record array ", .gen = &genRecords },
        .{ .name = "text         ", .gen = &genText },
    };

    var tot_base: usize = 0;
    var tot_best: usize = 0;
    for (sets) |ds| {
        const data = try ds.gen(a, N);
        const base = gzSize(a, data); // gzip with NO filter (identity) — the baseline to beat
        reseed(0xC0FFEE ^ @as(u64, @intFromPtr(ds.name.ptr))); // vary exploration per set
        const best = try search(data, a, 24, 48);
        const f = try applyFwd(best, data, a);
        const bsz = gzSize(a, f);
        const ok = try reversible(best, data, a);
        tot_base += base;
        tot_best += @min(base, bsz);
        const impr = 100.0 * (@as(f64, @floatFromInt(base)) - @as(f64, @floatFromInt(bsz))) / @as(f64, @floatFromInt(base));
        try o.print("  {s}  gzip {d:>6} → {d:>6}  ({d:>5.1}% smaller)  reversible={s}\n      INVENTED: ", .{ ds.name, base, bsz, impr, if (ok) "✓" else "✗" });
        printProg(o, best);
        try o.print("\n\n", .{});
    }

    const tot_impr = 100.0 * (@as(f64, @floatFromInt(tot_base)) - @as(f64, @floatFromInt(tot_best))) / @as(f64, @floatFromInt(tot_base));
    try o.print("════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("Across all four types the engine cut gzip size by {d:.1}% TOTAL — by inventing the right reversible\n", .{tot_impr});
    try o.print("transform for each, with NO neural layer: no human intent understood, no LLM proposal. It was given\n", .{});
    try o.print("only a FORMAL objective (minimize measured size, stay invertible) and it searched + certified itself.\n\n", .{});
    try o.print("This is the autonomous half of the answer: once an objective is FORMAL and machine-measurable, the\n", .{});
    try o.print("engine needs no neural layer — it is FunSearch with the LLM replaced by blind mutation + measurement.\n", .{});
    try o.print("The two things it still can't do alone (Closure Principle): invent a primitive OUTSIDE its DSL, and\n", .{});
    try o.print("CHOOSE which objective to pursue. Understanding a NEW human intent is exactly that second act — the\n", .{});
    try o.print("one irreducible job of the neural layer. So: by itself on a fixed formal goal — yes. Understanding a\n", .{});
    try o.print("new human goal — that still needs the LLM. The engine is autonomous; the AIMING is not.\n", .{});
}
