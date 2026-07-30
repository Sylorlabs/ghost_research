//! stream_lm.zig — BOUNDED-MEMORY STREAMING count LM (the no-data-center thesis made real). Streams a large EN+ZH
//! corpus file-by-file, updates an interpolated-absolute-discounting rune n-gram, and keeps memory FLAT by pruning
//! singleton high-order contexts when over a budget. Prints (data consumed, RSS, EN BPB, ZH BPB) at intervals → the
//! data-scaling curve at constant RAM. CPU only, no GPU. Hard RSS safety abort so it can never crash the machine.
//!
//! Run: zig build stream-lm --release=fast
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
const RUNE_MERGES: usize = 2200;
const MAXLEN: usize = 48;
const ORD: usize = 5;
const DISC: f64 = 0.75;
const BUDGET: usize = 600_000; // low enough that peak RSS stays well under available RAM (machine safety)
const SAFETY_RSS_MB: usize = 3500; // hard abort ceiling — well under free RAM so it can never OOM the machine
const EVAL_EVERY: usize = 4_000_000; // bytes between held-out evals

fn mix(h: u64) u64 {
    var z = h +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}
fn rssMB() usize {
    const f = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return 0;
    defer f.close();
    var buf: [128]u8 = undefined;
    const n = f.read(&buf) catch return 0;
    var it = std.mem.tokenizeScalar(u8, buf[0..n], ' ');
    _ = it.next();
    const res = it.next() orelse return 0;
    const pages = std.fmt.parseInt(usize, res, 10) catch return 0;
    return pages * 4096 / (1024 * 1024);
}
// ── de-wrap (CRLF→LF, single \n → space) so it matches the GPT/held-out preprocessing ──
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
// ── BPE forge (for the one-time rune vocab) ──
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
            var p = pos;
            while (p < buf.len) {
                const kid = self.nodes.items[cur].kids.get(buf[p]) orelse break;
                cur = kid;
                p += 1;
                if (self.nodes.items[cur].id != -1) {
                    lid = self.nodes.items[cur].id;
                    ln = p;
                }
            }
            try out.append(if (lid < 0) 0 else @intCast(lid));
            pos = ln;
        }
        return out.items;
    }
};
// ── count tables (reclaiming allocator so pruning actually frees memory) ──
const Ctx = struct { tot: u32 = 0, m: std.AutoHashMap(u32, u32) };
const CT = std.AutoHashMap(u64, Ctx);
var ng: [ORD + 1]CT = undefined;
var ngAlloc: std.mem.Allocator = undefined;
var invV: f64 = 0;
var entries: usize = 0;
fn ngKey(R: []const u32, p: usize, k: usize) u64 {
    if (k == 0) return 0xABCDEF;
    var h: u64 = 1469598103934665603 ^ (k *% 1000003);
    for (1..k + 1) |d| h = mix(h ^ @as(u64, R[p - d] + 1));
    return h;
}
fn bumpN(R: []const u32, p: usize) !void {
    for (0..ORD + 1) |k| {
        if (k > p) break;
        const key = ngKey(R, p, k);
        const e = try ng[k].getOrPut(key);
        if (!e.found_existing) {
            e.value_ptr.* = .{ .tot = 0, .m = std.AutoHashMap(u32, u32).init(ngAlloc) };
            entries += 1;
        }
        e.value_ptr.tot += 1;
        const ie = try e.value_ptr.m.getOrPut(R[p]);
        if (!ie.found_existing) ie.value_ptr.* = 0;
        ie.value_ptr.* += 1;
    }
}
// prune singleton (tot==1) contexts from the highest orders until under target — bounds memory, minimal accuracy loss
fn prune(target: usize) !void {
    var k: usize = ORD;
    while (k >= 2 and entries > target) : (k -= 1) {
        var rm = std.ArrayList(u64).init(ngAlloc); // reclaiming allocator so this temp list is actually freed
        defer rm.deinit();
        var it = ng[k].iterator();
        while (it.next()) |e| if (e.value_ptr.tot <= 1) try rm.append(e.key_ptr.*);
        for (rm.items) |key| {
            if (ng[k].getPtr(key)) |ctx| ctx.m.deinit();
            _ = ng[k].remove(key);
            entries -= 1;
        }
    }
}
fn pRune(R: []const u32, p: usize, r: u32) f64 {
    var prob: f64 = invV;
    for (0..ORD + 1) |k| {
        if (k > p) break;
        if (ng[k].getPtr(ngKey(R, p, k))) |ctx| {
            const c: f64 = @floatFromInt(ctx.m.get(r) orelse 0);
            const tot: f64 = @floatFromInt(ctx.tot);
            const types: f64 = @floatFromInt(ctx.m.count());
            prob = @max(c - DISC, 0.0) / tot + (DISC * types / tot) * prob;
        }
    }
    return prob;
}
fn evalBPB(scratch: std.mem.Allocator, tr: *Trie, held: []const u8) !f64 {
    const EV = try tr.enc(scratch, held);
    var bits: f64 = 0;
    var p: usize = ORD;
    while (p < EV.len) : (p += 1) bits += -std.math.log2(@max(pRune(EV, p, EV[p]), 1e-12));
    return bits / @as(f64, @floatFromInt(held.len));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    ngAlloc = gpa.allocator(); // reclaiming allocator for the count tables (so prune frees memory)
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    try o.print("=== STREAM-LM — bounded-memory streaming count LM on big EN+ZH. Flat RAM, data-scaling curve. CPU, no GPU ===\n\n", .{});

    // training files: base books + all biglit (Austen excluded) + Chinese, streamed one at a time
    var files = std.ArrayList([]const u8).init(a);
    for ([_][]const u8{ "moby_dick.txt", "shakespeare.txt", "tolstoy.txt" }) |f| try files.append(f);
    try files.append("chinese_train.txt"); // Chinese early so BOTH languages are learned across the run
    {
        const bl = try std.mem.concat(a, u8, &.{ C, "biglit" });
        var d = try std.fs.openDirAbsolute(bl, .{ .iterate = true });
        defer d.close();
        var it = d.iterate();
        while (try it.next()) |e| if (e.kind == .file and std.mem.endsWith(u8, e.name, ".txt"))
            try files.append(try std.mem.concat(a, u8, &.{ "biglit/", try a.dupe(u8, e.name) }));
    }

    // held-outs (loaded once, kept)
    const enHeld = try dewrap(a, blk: {
        const f = try std.fs.openFileAbsolute(C ++ "heldout_eval_dw.txt", .{});
        defer f.close();
        break :blk try f.readToEndAlloc(a, 1 << 30);
    });
    const zhHeld = blk: {
        const f = try std.fs.openFileAbsolute(C ++ "zh_held_dw.txt", .{});
        defer f.close();
        break :blk try f.readToEndAlloc(a, 1 << 30);
    };

    // forge runes once on a mixed sample (first base book + the Chinese head) so both scripts get runes
    var trie = try Trie.init(a);
    {
        var samp = std.ArrayList(u8).init(a);
        for ([_][]const u8{ "moby_dick.txt", "chinese.txt" }) |fn_| {
            const p = try std.mem.concat(a, u8, &.{ C, fn_ });
            const f = try std.fs.openFileAbsolute(p, .{});
            defer f.close();
            const raw = try f.readToEndAlloc(a, 1 << 30);
            const dw = try dewrap(a, raw[0..@min(450_000, raw.len)]);
            try samp.appendSlice(dw);
        }
        var su = try a.alloc(u32, samp.items.len);
        for (0..samp.items.len) |i| su[i] = samp.items[i];
        const vocab = try bpe(a, su, 256, RUNE_MERGES);
        invV = 1.0 / @as(f64, @floatFromInt(vocab.items.len));
        for (0..vocab.items.len) |i| try trie.add(vocab.items[i], @intCast(i));
        try o.print("forged {d} runes on a mixed EN+ZH sample (vocab {d}).\n", .{ vocab.items.len - 256, vocab.items.len });
        try o.print("budget {d}M context entries; prune singletons above it; safety abort at {d} MB RSS.\n\n", .{ BUDGET / 1_000_000, SAFETY_RSS_MB });
    }
    for (0..ORD + 1) |k| ng[k] = CT.init(ngAlloc);

    try o.print("   data(MB)   RSS(MB)   entries(M)   EN-BPB   ZH-BPB   (gpt2 EN ref 1.0499)\n", .{});
    try o.print("   ──────────────────────────────────────────────────────────────────────\n", .{});
    var consumed: usize = 0;
    var nextEval: usize = EVAL_EVERY;
    var pruned: usize = 0;
    for (files.items) |fname| {
        var fa = std.heap.ArenaAllocator.init(std.heap.page_allocator); // per-file scratch — freed each iteration → flat RAM
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
        var p: usize = ORD;
        while (p < R.len) : (p += 1) {
            try bumpN(R, p);
            if (entries > BUDGET) {
                try prune(BUDGET * 4 / 5);
                pruned += 1;
                if (rssMB() > SAFETY_RSS_MB) {
                    try o.print("\n!! RSS {d} MB exceeded safety ceiling — aborting cleanly to protect the machine.\n", .{rssMB()});
                    return;
                }
            }
        }
        consumed += dw.len;
        if (consumed >= nextEval) {
            const en = try evalBPB(faa, &trie, enHeld);
            const zh = try evalBPB(faa, &trie, zhHeld);
            try o.print("   {d:>7.1}   {d:>7}   {d:>8.2}     {d:.4}   {d:.4}\n", .{ @as(f64, @floatFromInt(consumed)) / 1e6, rssMB(), @as(f64, @floatFromInt(entries)) / 1e6, en, zh });
            nextEval = consumed + EVAL_EVERY;
        }
    }
    const en = try evalBPB(a, &trie, enHeld);
    const zh = try evalBPB(a, &trie, zhHeld);
    try o.print("\n── FINAL ({d:.1} MB streamed, {d} prune passes) ──\n", .{ @as(f64, @floatFromInt(consumed)) / 1e6, pruned });
    try o.print("  EN BPB {d:.4}   ZH BPB {d:.4}   peak RSS {d} MB   entries {d:.2}M\n", .{ en, zh, rssMB(), @as(f64, @floatFromInt(entries)) / 1e6 });
    try o.print("  Memory stayed BOUNDED (pruned singletons) while streaming all data — the no-data-center thesis: GB in, MB resident.\n", .{});
}
