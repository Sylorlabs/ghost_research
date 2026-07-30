//! lm_bpc.zig — our no-LLM rune stack vs a stolen GPT-2, on the FAIR metric: BITS-PER-BYTE on the same held-out text.
//! A probabilistic hierarchical model: interpolated rune n-gram backoff (orders 1..5) + phrase-conditioned +
//! concept-conditioned, warm-started on Melville/Shakespeare/Tolstoy, then PREQUENTIAL on an Austen held-out slice
//! (disjoint — no overlap with training). BPB = (Σ −log2 p(rune)) / held-out-bytes, directly comparable to GPT-2's
//! bits/byte regardless of tokenization. CPU, seconds, tens of MB, no GPU, no LLM.
//!
//! Run: zig build lm-bpc --release=fast
const std = @import("std");

const RUNE_MERGES: usize = 1500;
const PHRASE_MERGES: usize = 1200;
const CONCEPT_MERGES: usize = 800;
const TRAIN_BYTES: usize = 2_400_000; // warm-start corpus (Melville+Shakespeare+Tolstoy)
const MAXLEN: usize = 48;
const ORD: usize = 5; // max rune n-gram order

fn mix(h: u64) u64 {
    var z = h +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}
const Bpe = struct { vocab: std.ArrayList([]u32), seq: []u32 };
fn bpe(a: std.mem.Allocator, input: []const u32, nbase: usize, merges: usize, maxlen: usize) !Bpe {
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
        if (exp.len > maxlen) continue;
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
    fn step(self: *Trie, buf: []const u32, pos: usize) struct { id: i32, np: usize } {
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
        return .{ .id = lid, .np = ln };
    }
};
fn segment(a: std.mem.Allocator, t: *Trie, buf: []const u32, unitOf: ?[]u32) ![]u32 {
    var units = std.ArrayList(u32).init(a);
    var pos: usize = 0;
    while (pos < buf.len) {
        const s = t.step(buf, pos);
        const id: u32 = if (s.id < 0) 0 else @intCast(s.id);
        try units.append(id);
        if (unitOf) |uo| for (pos..s.np) |q| {
            uo[q] = @intCast(units.items.len - 1);
        };
        pos = s.np;
    }
    return units.items;
}

// a context→next-rune count table
const CT = std.AutoHashMap(u64, std.AutoHashMap(u32, u32));
fn cnt(map: *CT, key: u64, r: u32) struct { c: u32, tot: u32 } {
    if (map.get(key)) |inner| {
        const c = inner.get(r) orelse 0;
        var tot: u32 = 0;
        var it = inner.iterator();
        while (it.next()) |e| tot += e.value_ptr.*;
        return .{ .c = c, .tot = tot };
    }
    return .{ .c = 0, .tot = 0 };
}
fn bump(a: std.mem.Allocator, map: *CT, key: u64, r: u32) !void {
    const e = try map.getOrPut(key);
    if (!e.found_existing) e.value_ptr.* = std.AutoHashMap(u32, u32).init(a);
    const ie = try e.value_ptr.getOrPut(r);
    if (!ie.found_existing) ie.value_ptr.* = 0;
    ie.value_ptr.* += 1;
}

var runeOf: []u32 = undefined;
fn ngKey(R: []const u32, p: usize, k: usize) u64 {
    var h: u64 = 1469598103934665603 ^ (k * 1000003);
    for (1..k + 1) |d| h = mix(h ^ @as(u64, R[p - d] + 1));
    return h;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    const dir = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus";

    try o.print("=== LM-BPC — our no-LLM rune stack vs a stolen GPT-2, fair metric: BITS-PER-BYTE on the same held-out text ===\n\n", .{});

    // training corpus = Melville + Shakespeare + Tolstoy (DISJOINT from the Austen held-out)
    var tr = std.ArrayList(u8).init(a);
    for ([_][]const u8{ "moby_dick.txt", "shakespeare.txt", "tolstoy.txt" }) |fnm| {
        const p = try std.fs.path.join(a, &.{ dir, fnm });
        const f = std.fs.openFileAbsolute(p, .{}) catch continue;
        defer f.close();
        try tr.appendSlice((try f.readToEndAlloc(a, 1 << 30))[0..@min(900_000, (try f.stat()).size)]);
    }
    const TRB = tr.items[0..@min(TRAIN_BYTES, tr.items.len)];
    // held-out
    const hp = try std.fs.path.join(a, &.{ dir, "heldout_eval.txt" });
    const hf = try std.fs.openFileAbsolute(hp, .{});
    const HB = try hf.readToEndAlloc(a, 1 << 30);
    hf.close();

    // forge runes on the training bytes
    var trU = try a.alloc(u32, TRB.len);
    for (0..TRB.len) |i| trU[i] = TRB[i];
    const rbpe = try bpe(a, trU, 256, RUNE_MERGES, MAXLEN);
    const V = rbpe.vocab.items.len; // full rune vocab (for the uniform floor)
    var runeTrie = try Trie.init(a);
    for (0..V) |i| try runeTrie.add(rbpe.vocab.items[i], @intCast(i));

    // encode train + held-out into runes
    var trUf = try a.alloc(u32, TRB.len);
    for (0..TRB.len) |i| trUf[i] = TRB[i];
    const TR = try segment(a, &runeTrie, trUf, null);
    var hUf = try a.alloc(u32, HB.len);
    for (0..HB.len) |i| hUf[i] = HB[i];
    const evPhraseOf = try a.alloc(u32, HB.len); // rune-pos in held-out → phrase index (filled after we have EV)
    _ = evPhraseOf;
    const EV = try segment(a, &runeTrie, hUf, null);

    // forge phrases (on TR), concepts (on TR phrases)
    const pbpe = try bpe(a, TR, V, PHRASE_MERGES, MAXLEN);
    var phraseTrie = try Trie.init(a);
    for (0..pbpe.vocab.items.len) |i| try phraseTrie.add(pbpe.vocab.items[i], @intCast(i));
    const cbpe = try bpe(a, pbpe.seq, pbpe.vocab.items.len, CONCEPT_MERGES, MAXLEN);
    var conceptTrie = try Trie.init(a);
    for (0..cbpe.vocab.items.len) |i| try conceptTrie.add(cbpe.vocab.items[i], @intCast(i));

    // segment held-out runes into phrases/concepts (using TRAIN-forged hierarchy) → prevPhrase/prevConcept per rune pos
    const evPhOf = try a.alloc(u32, EV.len);
    const evPH = try segment(a, &phraseTrie, EV, evPhOf);
    const evCoOfPh = try a.alloc(u32, evPH.len);
    const evCO = try segment(a, &conceptTrie, evPH, evCoOfPh);
    // same for train (for warm-start phrase/concept contexts)
    const trPhOf = try a.alloc(u32, TR.len);
    const trPH = try segment(a, &phraseTrie, TR, trPhOf);
    const trCoOfPh = try a.alloc(u32, trPH.len);
    const trCO = try segment(a, &conceptTrie, trPH, trCoOfPh);

    // count tables: rune orders 1..ORD + phrase(prevP,r1) + concept(prevC,r1)
    var ng: [ORD + 1]CT = undefined;
    for (1..ORD + 1) |k| ng[k] = CT.init(a);
    var phr = CT.init(a);
    var con = CT.init(a);

    // train one pass over a rune stream (used for warm-start, and again prequentially on held-out)
    const trainOn = struct {
        fn f(al: std.mem.Allocator, R: []const u32, phOf: []const u32, PH: []const u32, coOfPh: []const u32, CO: []const u32, ngp: []CT, phrp: *CT, conp: *CT) !void {
            var p: usize = ORD;
            while (p < R.len) : (p += 1) {
                const r = R[p];
                for (1..ORD + 1) |k| try bump(al, &ngp[k], ngKey(R, p, k), r);
                const cph = phOf[p];
                const prevP: u32 = if (cph > 0) PH[cph - 1] else 0;
                const cco = coOfPh[cph];
                const prevC: u32 = if (cco > 0) CO[cco - 1] else 0;
                try bump(al, phrp, mix((@as(u64, prevP) << 24) ^ @as(u64, R[p - 1])), r);
                try bump(al, conp, mix((@as(u64, prevC) << 24) ^ @as(u64, R[p - 1])), r);
            }
        }
    }.f;
    try trainOn(a, TR, trPhOf, trPH, trCoOfPh, trCO, &ng, &phr, &con);

    // PREQUENTIAL bits-per-byte on the held-out (predict-then-update)
    // mixture weights over the firing experts + a uniform floor (guarantees p>0)
    const wOrd = [_]f64{ 0, 0.04, 0.18, 0.26, 0.20, 0.12 }; // index = order
    const wPhr: f64 = 0.10;
    const wCon: f64 = 0.06;
    const wUnif: f64 = 0.02;
    const invV: f64 = 1.0 / @as(f64, @floatFromInt(V));
    // probability of the true rune r at position p under the current tables
    const probOf = struct {
        fn f(EVs: []const u32, ph: []const u32, evPHs: []const u32, evPhOfs: []const u32, evCOs: []const u32, evCoOfPhs: []const u32, ngp: []CT, phrp: *CT, conp: *CT, wO: []const f64, wP: f64, wC: f64, wU: f64, iv: f64, pp: usize) f64 {
            const r = EVs[pp];
            const cph = evPhOfs[pp];
            const prevP: u32 = if (cph > 0) evPHs[cph - 1] else 0;
            const cco = evCoOfPhs[cph];
            const prevC: u32 = if (cco > 0) evCOs[cco - 1] else 0;
            var num: f64 = wU * iv;
            var den: f64 = wU;
            for (1..ORD + 1) |k| {
                const q = cnt(&ngp[k], ngKey(EVs, pp, k), r);
                if (q.tot > 0) {
                    num += wO[k] * (@as(f64, @floatFromInt(q.c)) / @as(f64, @floatFromInt(q.tot)));
                    den += wO[k];
                }
            }
            const qp = cnt(phrp, mix((@as(u64, prevP) << 24) ^ @as(u64, EVs[pp - 1])), r);
            if (qp.tot > 0) {
                num += wP * (@as(f64, @floatFromInt(qp.c)) / @as(f64, @floatFromInt(qp.tot)));
                den += wP;
            }
            const qc = cnt(conp, mix((@as(u64, prevC) << 24) ^ @as(u64, EVs[pp - 1])), r);
            if (qc.tot > 0) {
                num += wC * (@as(f64, @floatFromInt(qc.c)) / @as(f64, @floatFromInt(qc.tot)));
                den += wC;
            }
            _ = ph;
            return num / den;
        }
    }.f;
    // FROZEN pass: warm-start model only, NO updates on the held-out (raw transfer capability)
    var frozenBits: f64 = 0;
    {
        var pp: usize = ORD;
        while (pp < EV.len) : (pp += 1) {
            const prob = probOf(EV, evPH, evPH, evPhOf, evCO, evCoOfPh, &ng, &phr, &con, &wOrd, wPhr, wCon, wUnif, invV, pp);
            frozenBits += -std.math.log2(@max(prob, 1e-12));
        }
    }
    var totBits: f64 = 0;
    var scored: usize = 0;
    var p: usize = ORD;
    while (p < EV.len) : (p += 1) {
        const r = EV[p];
        const cph = evPhOf[p];
        const prevP: u32 = if (cph > 0) evPH[cph - 1] else 0;
        const cco = evCoOfPh[cph];
        const prevC: u32 = if (cco > 0) evCO[cco - 1] else 0;

        var num: f64 = wUnif * invV; // probability of the TRUE rune r
        var den: f64 = wUnif;
        for (1..ORD + 1) |k| {
            const q = cnt(&ng[k], ngKey(EV, p, k), r);
            if (q.tot > 0) {
                num += wOrd[k] * (@as(f64, @floatFromInt(q.c)) / @as(f64, @floatFromInt(q.tot)));
                den += wOrd[k];
            }
        }
        {
            const q = cnt(&phr, mix((@as(u64, prevP) << 24) ^ @as(u64, EV[p - 1])), r);
            if (q.tot > 0) {
                num += wPhr * (@as(f64, @floatFromInt(q.c)) / @as(f64, @floatFromInt(q.tot)));
                den += wPhr;
            }
        }
        {
            const q = cnt(&con, mix((@as(u64, prevC) << 24) ^ @as(u64, EV[p - 1])), r);
            if (q.tot > 0) {
                num += wCon * (@as(f64, @floatFromInt(q.c)) / @as(f64, @floatFromInt(q.tot)));
                den += wCon;
            }
        }
        const prob = num / den;
        totBits += -std.math.log2(@max(prob, 1e-12));
        scored += 1;
        // update (prequential, continual learning)
        for (1..ORD + 1) |k| try bump(a, &ng[k], ngKey(EV, p, k), r);
        try bump(a, &phr, mix((@as(u64, prevP) << 24) ^ @as(u64, EV[p - 1])), r);
        try bump(a, &con, mix((@as(u64, prevC) << 24) ^ @as(u64, EV[p - 1])), r);
    }

    const nbytes = HB.len;
    const bpb = totBits / @as(f64, @floatFromInt(nbytes));
    try o.print("held-out: {d} bytes → {d} runes ({d:.2} bytes/rune). rune vocab {d}.\n", .{ nbytes, EV.len, @as(f64, @floatFromInt(nbytes)) / @as(f64, @floatFromInt(EV.len)), V });
    try o.print("warm-started on {d} bytes of Melville+Shakespeare+Tolstoy (DISJOINT from Austen held-out), then prequential.\n\n", .{TRB.len});
    const bpbFrozen = frozenBits / @as(f64, @floatFromInt(nbytes));
    try o.print("  OUR STACK (FROZEN, warm-start only, no held-out adaptation)  BPB = {d:.4}\n", .{bpbFrozen});
    try o.print("  ►► OUR STACK (PREQUENTIAL, continual learning on the stream) BPB = {d:.4}   (bits/rune {d:.3}, rune-ppl {d:.1})\n", .{ bpb, totBits / @as(f64, @floatFromInt(scored)), std.math.exp(totBits / @as(f64, @floatFromInt(scored)) * std.math.ln2) });
    try o.print("  CPU, seconds, tens of MB of count tables, no GPU, no LLM.\n\n", .{});
    try o.print("Compare to GPT-2 on the SAME held-out file (run: python3 gpt2_bpb.py distilgpt2): lower BPB wins.\n", .{});
    try o.print("Honest framing: GPT-2 is pretrained on billions of tokens (frozen); ours warm-starts on ~2MB and then ADAPTS on\n", .{});
    try o.print("the held-out stream (continual). BPB is the fair cross-tokenization metric — whoever encodes these bytes in fewer bits.\n", .{});
}
