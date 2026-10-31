//! lm_mixed.zig — does the byte-native count model handle ENGLISH + CHINESE mixed? Forge runes on an interleaved EN+ZH
//! corpus, train the interpolated-absolute-discounting rune n-gram, measure BITS-PER-BYTE on an English held-out AND a
//! Chinese held-out separately (and combined). Byte-native = no language config; UTF-8 Chinese is just bytes → runes.
//! CPU, no GPU, no LLM. (Reference: gpt2 on de-wrapped English = 1.0499; Chinese is a different, harder script.)
//!
//! Run: zig build lm-mixed --release=fast
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
const RUNE_MERGES: usize = 2200;
const MAXLEN: usize = 48;
const ORD: usize = 6;
const DISC: f64 = 0.75;

fn mix(h: u64) u64 {
    var z = h +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}
const Bpe = struct { vocab: std.ArrayList([]u32), seq: []u32 };
fn bpe(a: std.mem.Allocator, input: []const u32, nbase: usize, merges: usize) !Bpe {
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
    return .{ .vocab = vocab, .seq = seq[0..len] };
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
    fn enc(self: *Trie, a: std.mem.Allocator, buf: []const u32) ![]u32 {
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
const Ctx = struct { tot: u32 = 0, m: std.AutoHashMap(u32, u32) };
const CT = std.AutoHashMap(u64, Ctx);
var ng: [ORD + 1]CT = undefined;
var invV: f64 = 0;
fn ngKey(R: []const u32, p: usize, k: usize) u64 {
    if (k == 0) return 0xABCDEF;
    var h: u64 = 1469598103934665603 ^ (k *% 1000003);
    for (1..k + 1) |d| h = mix(h ^ @as(u64, R[p - d] + 1));
    return h;
}
fn bumpN(a: std.mem.Allocator, R: []const u32, p: usize) !void {
    for (0..ORD + 1) |k| {
        if (k > p) break;
        const key = ngKey(R, p, k);
        const e = try ng[k].getOrPut(key);
        if (!e.found_existing) e.value_ptr.* = .{ .tot = 0, .m = std.AutoHashMap(u32, u32).init(a) };
        e.value_ptr.tot += 1;
        const ie = try e.value_ptr.m.getOrPut(R[p]);
        if (!ie.found_existing) ie.value_ptr.* = 0;
        ie.value_ptr.* += 1;
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
fn readFile(a: std.mem.Allocator, name: []const u8) ![]u8 {
    const p = try std.mem.concat(a, u8, &.{ C, name });
    const f = try std.fs.openFileAbsolute(p, .{});
    defer f.close();
    return try f.readToEndAlloc(a, 1 << 30);
}
fn toU32(a: std.mem.Allocator, b: []const u8) ![]u32 {
    var u = try a.alloc(u32, b.len);
    for (0..b.len) |i| u[i] = b[i];
    return u;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    try o.print("=== LM-MIXED — byte-native count model on ENGLISH + CHINESE mixed. BITS-PER-BYTE per language. CPU, no LLM ===\n\n", .{});

    const train = try readFile(a, "train_mix.txt");
    const enHeld = try readFile(a, "heldout_eval_dw.txt");
    const zhHeld = try readFile(a, "zh_held_dw.txt");

    // forge runes on a sample that spans BOTH scripts (train_mix is interleaved EN/ZH 200KB blocks)
    const sample = train[0..@min(900_000, train.len)];
    const rbpe = try bpe(a, try toU32(a, sample), 256, RUNE_MERGES);
    const V = rbpe.vocab.items.len;
    invV = 1.0 / @as(f64, @floatFromInt(V));
    var trie = try Trie.init(a);
    for (0..V) |i| try trie.add(rbpe.vocab.items[i], @intCast(i));

    const TR = try trie.enc(a, try toU32(a, train));
    for (0..ORD + 1) |k| ng[k] = CT.init(a);
    {
        var p: usize = ORD;
        while (p < TR.len) : (p += 1) try bumpN(a, TR, p);
    }

    const evalBPB = struct {
        fn f(al: std.mem.Allocator, tr: *Trie, held: []const u8) !struct { bpb: f64, runes: usize } {
            const EV = try tr.enc(al, try toU32(al, held));
            var bits: f64 = 0;
            var p: usize = ORD;
            while (p < EV.len) : (p += 1) bits += -std.math.log2(@max(pRune(EV, p, EV[p]), 1e-12));
            return .{ .bpb = bits / @as(f64, @floatFromInt(held.len)), .runes = EV.len };
        }
    }.f;

    const en = try evalBPB(a, &trie, enHeld);
    const zh = try evalBPB(a, &trie, zhHeld);
    const combinedBytes = enHeld.len + zhHeld.len;
    const combinedBits = en.bpb * @as(f64, @floatFromInt(enHeld.len)) + zh.bpb * @as(f64, @floatFromInt(zhHeld.len));

    try o.print("forged {d} runes on a mixed EN+ZH sample. trained on {d} mixed runes ({d:.1} MB).\n\n", .{ V - 256, TR.len, @as(f64, @floatFromInt(train.len)) / 1e6 });
    try o.print("  ENGLISH held-out ({d} bytes → {d} runes, {d:.2} B/rune):  BPB = {d:.4}\n", .{ enHeld.len, en.runes, @as(f64, @floatFromInt(enHeld.len)) / @as(f64, @floatFromInt(en.runes)), en.bpb });
    try o.print("  CHINESE held-out ({d} bytes → {d} runes, {d:.2} B/rune):  BPB = {d:.4}  (= {d:.3} bits/Han-char ≈ {d:.2} B/char)\n", .{ zhHeld.len, zh.runes, @as(f64, @floatFromInt(zhHeld.len)) / @as(f64, @floatFromInt(zh.runes)), zh.bpb, zh.bpb * 3.0, 3.0 });
    try o.print("  COMBINED BPB = {d:.4}\n\n", .{combinedBits / @as(f64, @floatFromInt(combinedBytes))});
    try o.print("════ VERDICT ════\n", .{});
    try o.print("Byte-native: ONE model, no language config, forges runes for BOTH scripts and predicts each. English BPB\n", .{});
    try o.print("{d:.2} (ref: gpt2 1.05 on much more data); Chinese BPB {d:.2} — Chinese is 3 bytes/char so {d:.2} bits/char, a\n", .{ en.bpb, zh.bpb, zh.bpb * 3.0 });
    try o.print("harder script with less data here (2.3MB ZH). Both handled by the SAME byte→rune→count pipeline, CPU, no GPU.\n", .{});
}
