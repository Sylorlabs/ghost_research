//! stream_fast.zig — the SCALABLE streaming count LM: FIXED pre-allocated open-addressing hash tables (flat RAM from
//! the first byte, no allocator churn, no pruning) → fast + bounded, scales to GBs. Interpolated absolute discounting
//! over rune orders 0..ORD with incrementally-maintained context totals + distinct-continuation counts. Streams a big
//! EN corpus file-by-file, prints (data, RSS, BPB) — the data-scaling curve toward gpt2's fair de-wrapped 1.0499.
//! Collisions merge counts gracefully (count-min-like) when a table saturates. CPU only, no GPU, single binary.
//!
//! Build+run: zig build-exe stream_fast.zig -O ReleaseFast -femit-bin=/tmp/sf && /tmp/sf
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
const RUNE_MERGES: usize = 2000;
const MAXLEN: usize = 48;
const ORD: usize = 5;
const DISC: f64 = 0.75;
const CK_BITS: u6 = 24; // (ctx,rune) table slots = 2^24 = 16.7M per order (bigger → saturation later; RAM-bounded)
const CC_BITS: u6 = 21; // ctx table slots = 2^21 = 2.1M per order
const MAXPROBE: usize = 24;
const EVAL_EVERY: usize = 8_000_000;

fn mix(h: u64) u64 {
    var z = h +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return (z ^ (z >> 31)) | (1 << 63); // nonzero (0 = empty sentinel)
}
fn rssMB() usize {
    const f = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return 0;
    defer f.close();
    var buf: [128]u8 = undefined;
    const n = f.read(&buf) catch return 0;
    var it = std.mem.tokenizeScalar(u8, buf[0..n], ' ');
    _ = it.next();
    const pages = std.fmt.parseInt(usize, it.next() orelse "0", 10) catch 0;
    return pages * 4096 / (1024 * 1024);
}
// (ctx,rune) → count, fixed open-addressing. bump returns true if this key was NEW (0→1).
const Cnt = struct {
    keys: []u64,
    vals: []u32,
    mask: usize,
    fn init(a: std.mem.Allocator, bits: u6) !Cnt {
        const n = @as(usize, 1) << bits;
        const k = try a.alloc(u64, n);
        @memset(k, 0);
        const v = try a.alloc(u32, n);
        @memset(v, 0);
        return .{ .keys = k, .vals = v, .mask = n - 1 };
    }
    fn bump(self: *Cnt, key: u64) bool {
        var s = key & self.mask;
        var p: usize = 0;
        while (p < MAXPROBE) : (p += 1) {
            if (self.keys[s] == key) {
                self.vals[s] +|= 1;
                return false;
            }
            if (self.keys[s] == 0) {
                self.keys[s] = key;
                self.vals[s] = 1;
                return true;
            }
            s = (s + 1) & self.mask;
        }
        self.keys[s] = key; // saturated → overwrite (graceful collision)
        self.vals[s] = 1;
        return true;
    }
    fn get(self: *const Cnt, key: u64) u32 {
        var s = key & self.mask;
        var p: usize = 0;
        while (p < MAXPROBE) : (p += 1) {
            if (self.keys[s] == key) return self.vals[s];
            if (self.keys[s] == 0) return 0;
            s = (s + 1) & self.mask;
        }
        return 0;
    }
};
// ctx → {total, distinct-continuations}, fixed open-addressing
const Cc = struct {
    keys: []u64,
    tot: []u32,
    typ: []u32,
    mask: usize,
    fn init(a: std.mem.Allocator, bits: u6) !Cc {
        const n = @as(usize, 1) << bits;
        const k = try a.alloc(u64, n);
        @memset(k, 0);
        const t = try a.alloc(u32, n);
        @memset(t, 0);
        const y = try a.alloc(u32, n);
        @memset(y, 0);
        return .{ .keys = k, .tot = t, .typ = y, .mask = n - 1 };
    }
    fn add(self: *Cc, key: u64, dtyp: u32) void {
        var s = key & self.mask;
        var p: usize = 0;
        while (p < MAXPROBE) : (p += 1) {
            if (self.keys[s] == key) {
                self.tot[s] +|= 1;
                self.typ[s] +|= dtyp;
                return;
            }
            if (self.keys[s] == 0) {
                self.keys[s] = key;
                self.tot[s] = 1;
                self.typ[s] = dtyp;
                return;
            }
            s = (s + 1) & self.mask;
        }
        self.keys[s] = key;
        self.tot[s] = 1;
        self.typ[s] = dtyp;
    }
    fn get(self: *const Cc, key: u64) struct { tot: u32, typ: u32 } {
        var s = key & self.mask;
        var p: usize = 0;
        while (p < MAXPROBE) : (p += 1) {
            if (self.keys[s] == key) return .{ .tot = self.tot[s], .typ = self.typ[s] };
            if (self.keys[s] == 0) return .{ .tot = 0, .typ = 0 };
            s = (s + 1) & self.mask;
        }
        return .{ .tot = 0, .typ = 0 };
    }
};

var cnt: [ORD + 1]Cnt = undefined;
var ctx: [ORD + 1]Cc = undefined;
var invV: f64 = 0;
var Vrunes: usize = 0;
fn ctxHash(R: []const u32, p: usize, k: usize) u64 {
    var h: u64 = 1469598103934665603 ^ (@as(u64, k) *% 1000003);
    for (1..k + 1) |d| h = (h ^ @as(u64, R[p - d] + 1)) *% 1099511628211;
    return mix(h);
}
fn bumpAll(R: []const u32, p: usize) void {
    const r = R[p];
    for (1..ORD + 1) |k| {
        if (k > p) break;
        const ch = ctxHash(R, p, k);
        const ck = mix(ch ^ (@as(u64, r) *% 2654435761));
        const isNew = cnt[k].bump(ck);
        ctx[k].add(ch, if (isNew) 1 else 0);
    }
}
var uni: []u32 = undefined;
var uniTot: u64 = 0;
fn pRune(R: []const u32, p: usize, r: u32) f64 {
    // unigram base with discounting
    var prob: f64 = invV;
    if (uniTot > 0) {
        const c: f64 = @floatFromInt(uni[r]);
        const t: f64 = @floatFromInt(uniTot);
        prob = @max(c - DISC, 0.0) / t + (DISC * @as(f64, @floatFromInt(Vrunes)) / t) * invV;
    }
    for (1..ORD + 1) |k| {
        if (k > p) break;
        const ch = ctxHash(R, p, k);
        const g = ctx[k].get(ch);
        if (g.tot > 0) {
            const ck = mix(ch ^ (@as(u64, r) *% 2654435761));
            const c: f64 = @floatFromInt(cnt[k].get(ck));
            const t: f64 = @floatFromInt(g.tot);
            const ty: f64 = @floatFromInt(g.typ);
            prob = @max(c - DISC, 0.0) / t + (DISC * ty / t) * prob;
        }
    }
    return prob;
}

fn dewrap(a: std.mem.Allocator, b0: []const u8) ![]u8 {
    var tmp = try a.alloc(u8, b0.len);
    var n: usize = 0;
    for (b0) |c| if (c != '\r') {
        tmp[n] = c;
        n += 1;
    };
    const b = tmp[0..n];
    var out = try a.alloc(u8, b.len);
    var w: usize = 0;
    var i: usize = 0;
    while (i < b.len) {
        if (b[i] == '\n' and i + 1 < b.len and b[i + 1] == '\n') {
            out[w] = '\n';
            out[w + 1] = '\n';
            w += 2;
            i += 2;
        } else if (b[i] == '\n') {
            out[w] = ' ';
            w += 1;
            i += 1;
        } else {
            out[w] = b[i];
            w += 1;
            i += 1;
        }
    }
    return out[0..w];
}
fn bpe(a: std.mem.Allocator, input: []const u32, nbase: usize, merges: usize) !std.ArrayList([]u32) {
    var vocab = std.ArrayList([]u32).init(a);
    for (0..nbase) |i| {
        const e = try a.alloc(u32, 1);
        e[0] = @intCast(i);
        try vocab.append(e);
    }
    var seq = try a.alloc(u32, input.len);
    @memcpy(seq, input);
    var len = input.len;
    var pairs = std.AutoHashMap(u64, u32).init(a);
    defer pairs.deinit();
    var m: usize = 0;
    while (m < merges) : (m += 1) {
        pairs.clearRetainingCapacity();
        var i: usize = 0;
        while (i + 1 < len) : (i += 1) {
            const key = (@as(u64, seq[i]) << 32) | @as(u64, seq[i + 1]);
            const e = try pairs.getOrPut(key);
            if (!e.found_existing) e.value_ptr.* = 0;
            e.value_ptr.* += 1;
        }
        var bk: u64 = 0;
        var bc: u32 = 1;
        var it = pairs.iterator();
        while (it.next()) |e| if (e.value_ptr.* > bc) {
            bc = e.value_ptr.*;
            bk = e.key_ptr.*;
        };
        if (bc < 3) break;
        const av: u32 = @intCast(bk >> 32);
        const bv: u32 = @intCast(bk & 0xffffffff);
        const exp = try std.mem.concat(a, u32, &.{ vocab.items[av], vocab.items[bv] });
        if (exp.len > MAXLEN) continue;
        try vocab.append(exp);
        const nid: u32 = @intCast(vocab.items.len - 1);
        var w: usize = 0;
        var r: usize = 0;
        while (r < len) {
            if (r + 1 < len and seq[r] == av and seq[r + 1] == bv) {
                seq[w] = nid;
                w += 1;
                r += 2;
            } else {
                seq[w] = seq[r];
                w += 1;
                r += 1;
            }
        }
        len = w;
    }
    return vocab;
}
const Trie = struct {
    const Node = struct { id: i32 = -1, kids: std.AutoHashMap(u32, u32) };
    nodes: std.ArrayList(Node),
    a: std.mem.Allocator,
    fn init(a: std.mem.Allocator) !Trie {
        var t = Trie{ .nodes = std.ArrayList(Node).init(a), .a = a };
        try t.nodes.append(.{ .kids = std.AutoHashMap(u32, u32).init(a) });
        return t;
    }
    fn add(self: *Trie, syms: []const u32, id: i32) !void {
        var cur: u32 = 0;
        for (syms) |s| {
            const g = try self.nodes.items[cur].kids.getOrPut(s);
            if (!g.found_existing) {
                g.value_ptr.* = @intCast(self.nodes.items.len);
                try self.nodes.append(.{ .kids = std.AutoHashMap(u32, u32).init(self.a) });
            }
            cur = g.value_ptr.*;
        }
        self.nodes.items[cur].id = id;
    }
    fn enc(self: *Trie, a: std.mem.Allocator, buf: []const u8) ![]u32 {
        var out = std.ArrayList(u32).init(a);
        var pos: usize = 0;
        while (pos < buf.len) {
            var cur: u32 = 0;
            var lid: i32 = -1;
            var ln = pos + 1;
            var pp = pos;
            while (pp < buf.len) {
                const kid = self.nodes.items[cur].kids.get(buf[pp]) orelse break;
                cur = kid;
                pp += 1;
                if (self.nodes.items[cur].id != -1) {
                    lid = self.nodes.items[cur].id;
                    ln = pp;
                }
            }
            try out.append(if (lid < 0) 0 else @intCast(lid));
            pos = ln;
        }
        return out.items;
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pa = std.heap.page_allocator;
    const o = std.io.getStdOut().writer();
    try o.print("=== STREAM-FAST — fixed-memory streaming count LM (flat RAM, scales to GB). Data-scaling toward gpt2 1.0499 ===\n\n", .{});

    // file list: base books + biglit + bigcorpus (all English; Austen excluded). Chinese left out (English-only scaling run).
    var files = std.ArrayList([]const u8).init(a);
    for ([_][]const u8{ "moby_dick.txt", "shakespeare.txt", "tolstoy.txt" }) |f| try files.append(f);
    for ([_][]const u8{ "biglit" }) |sub| { // clean literary English only (bigcorpus had Italian Dante / poetry — dilutes)
        const dp = try std.mem.concat(a, u8, &.{ C, sub });
        var d = std.fs.openDirAbsolute(dp, .{ .iterate = true }) catch continue;
        defer d.close();
        var it = d.iterate();
        while (try it.next()) |e| if (e.kind == .file and std.mem.endsWith(u8, e.name, ".txt"))
            try files.append(try std.mem.concat(a, u8, &.{ sub, "/", try a.dupe(u8, e.name) }));
    }

    const enHeld = blk: {
        const f = try std.fs.openFileAbsolute(C ++ "heldout_eval_dw.txt", .{});
        defer f.close();
        break :blk try f.readToEndAlloc(a, 1 << 30);
    };

    // forge runes once on a sample, then pre-allocate the fixed tables (flat RAM from here on)
    var trie = try Trie.init(a);
    {
        const f = try std.fs.openFileAbsolute(C ++ "moby_dick.txt", .{});
        defer f.close();
        const raw = try f.readToEndAlloc(a, 1 << 30);
        const dw = try dewrap(a, raw[0..@min(700_000, raw.len)]);
        var su = try a.alloc(u32, dw.len);
        for (0..dw.len) |i| su[i] = dw[i];
        const vocab = try bpe(a, su, 256, RUNE_MERGES);
        Vrunes = vocab.items.len;
        invV = 1.0 / @as(f64, @floatFromInt(Vrunes));
        for (0..Vrunes) |i| try trie.add(vocab.items[i], @intCast(i));
    }
    for (1..ORD + 1) |k| {
        cnt[k] = try Cnt.init(pa, CK_BITS);
        ctx[k] = try Cc.init(pa, CC_BITS);
    }
    uni = try pa.alloc(u32, Vrunes);
    @memset(uni, 0);
    const tableMB = ((@as(usize, 1) << CK_BITS) * 12 + (@as(usize, 1) << CC_BITS) * 16) * ORD / (1024 * 1024);
    try o.print("forged {d} runes; fixed tables pre-allocated (~{d} MB, flat). streaming {d} files...\n\n", .{ Vrunes - 256, tableMB, files.items.len });
    try o.print("   data(MB)   RSS(MB)   EN-BPB   (gpt2 fair ref 1.0499)\n", .{});
    try o.print("   ────────────────────────────────────────────────────\n", .{});

    var consumed: usize = 0;
    var nextEval: usize = EVAL_EVERY;
    for (files.items) |fname| {
        var fa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer fa.deinit();
        const faa = fa.allocator();
        const path = try std.mem.concat(faa, u8, &.{ C, fname });
        const f = std.fs.openFileAbsolute(path, .{}) catch continue;
        const raw = f.readToEndAlloc(faa, 1 << 30) catch {
            f.close();
            continue;
        };
        f.close();
        const dw = try dewrap(faa, raw);
        const R = try trie.enc(faa, dw);
        for (R) |rr| {
            uniTot += 1;
            uni[rr] +|= 1;
        }
        var p: usize = ORD;
        while (p < R.len) : (p += 1) bumpAll(R, p);
        consumed += dw.len;
        if (consumed >= nextEval) {
            const EV = try trie.enc(faa, enHeld);
            var bits: f64 = 0;
            var q: usize = ORD;
            while (q < EV.len) : (q += 1) bits += -std.math.log2(@max(pRune(EV, q, EV[q]), 1e-12));
            try o.print("   {d:>7.1}   {d:>7}   {d:.4}\n", .{ @as(f64, @floatFromInt(consumed)) / 1e6, rssMB(), bits / @as(f64, @floatFromInt(enHeld.len)) });
            nextEval = consumed + EVAL_EVERY;
        }
    }
    const EV = try trie.enc(a, enHeld);
    var bits: f64 = 0;
    var q: usize = ORD;
    while (q < EV.len) : (q += 1) bits += -std.math.log2(@max(pRune(EV, q, EV[q]), 1e-12));
    const bpb = bits / @as(f64, @floatFromInt(enHeld.len));
    try o.print("\n── FINAL: {d:.1} MB streamed, EN BPB {d:.4}, RSS {d} MB (flat) ──\n", .{ @as(f64, @floatFromInt(consumed)) / 1e6, bpb, rssMB() });
    try o.print("  vs gpt2 fair de-wrapped 1.0499. {s}\n", .{if (bpb < 1.0499) "WE WIN ON PROBABILITY." else "still above gpt2 — needs more data (curve still dropping)."});
}
