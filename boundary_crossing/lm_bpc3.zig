//! lm_bpc2.zig — Phase 1 of closing the capability gap to GPT-2: proper SMOOTHING. Replaces lm_bpc's crude linear
//! interpolation with INTERPOLATED ABSOLUTE DISCOUNTING (the gold-standard count-LM smoothing, ≈ interpolated
//! Kneser-Ney) over rune orders 0..K, plus phrase/concept experts that back off to the rune estimate. Same data, same
//! held-out, same BITS-PER-BYTE metric vs gpt2 (1.9105) / distilgpt2 (2.0241). CPU, no GPU, no LLM.
//!
//! Arg1 (optional) = warm-start size in MB (for the Phase-2 data-scaling sweep). Default uses the 3 books fully.
//! Run: zig build lm-bpc2 --release=fast            (or: zig build lm-bpc2 --release=fast -- 8)
const std = @import("std");

const RUNE_MERGES: usize = 1500;
const PHRASE_MERGES: usize = 1200;
const CONCEPT_MERGES: usize = 800;
const MAXLEN: usize = 48;
const ORD: usize = 6; // max rune n-gram order (condition on last ORD runes)
const DISC: f64 = 0.75; // absolute discount

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

// context node: cached total + per-rune counts (so lookups are O(1), no re-summing)
const Ctx = struct { tot: u32 = 0, m: std.AutoHashMap(u32, u32) };
const CT = std.AutoHashMap(u64, Ctx);
const Look = struct { c: u32, tot: u32, types: u32 };
fn look(map: *CT, key: u64, r: u32) Look {
    if (map.getPtr(key)) |ctx| {
        return .{ .c = ctx.m.get(r) orelse 0, .tot = ctx.tot, .types = @intCast(ctx.m.count()) };
    }
    return .{ .c = 0, .tot = 0, .types = 0 };
}
fn bump(a: std.mem.Allocator, map: *CT, key: u64, r: u32) !void {
    const e = try map.getOrPut(key);
    if (!e.found_existing) e.value_ptr.* = .{ .tot = 0, .m = std.AutoHashMap(u32, u32).init(a) };
    e.value_ptr.tot += 1;
    const ie = try e.value_ptr.m.getOrPut(r);
    if (!ie.found_existing) ie.value_ptr.* = 0;
    ie.value_ptr.* += 1;
}
// de-wrap: collapse single '\n' (hard line wrap) to ' ', keep '\n\n' (paragraph) — matches gpt2_bpb's de-wrap exactly
fn dewrapBytes(a: std.mem.Allocator, b0: []const u8) ![]u8 {
    // pass 1: normalize CRLF→LF (drop '\r'), matching gpt2_bpb's .replace('\r\n','\n')
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
fn ngKey(R: []const u32, p: usize, k: usize) u64 {
    if (k == 0) return 0xABCDEF; // global unigram context
    var h: u64 = 1469598103934665603 ^ (k *% 1000003);
    for (1..k + 1) |d| h = mix(h ^ @as(u64, R[p - d] + 1));
    return h;
}

var ng: [ORD + 1]CT = undefined;
var phr: CT = undefined;
var con: CT = undefined;
var invV: f64 = 0;

// ── kNN / embedding smoothing (Option 1): when the exact context is sparse, borrow next-rune evidence from
//    EMBEDDING-SIMILAR contexts via an LSH bucket of the decayed context embedding (O(1), no neural encoder). ──
const ED: usize = 48; // embedding dim (= top-ED runes as context features, cheap PPMI)
const LBITS: usize = 16; // LSH bits
const HW: usize = 6; // context window for the embedding key
const LAMBDA_E: f32 = 0.65;
var emb: []f32 = undefined; // [V * ED]
var proj: []f32 = undefined; // [LBITS * ED]
var lsh: CT = undefined;
var rngE: u64 = 0x51F3A2;
fn ctxBucket(R: []const u32, p: usize) u32 {
    var cv = [_]f32{0} ** ED;
    var w: f32 = 1.0;
    var d: usize = 1;
    while (d <= HW and p >= d) : (d += 1) {
        const u: usize = R[p - d];
        for (0..ED) |k| cv[k] += w * emb[u * ED + k];
        w *= LAMBDA_E;
    }
    var b: u32 = 0;
    for (0..LBITS) |j| {
        var s: f32 = 0;
        for (0..ED) |k| s += proj[j * ED + k] * cv[k];
        if (s > 0) b |= (@as(u32, 1) << @intCast(j));
    }
    return b;
}

// interpolated absolute discounting over rune orders 0..ORD; returns p(r | context)
fn pRune(R: []const u32, p: usize, r: u32) f64 {
    var prob: f64 = invV; // base: uniform
    for (0..ORD + 1) |k| {
        if (k > p) break;
        const L = look(&ng[k], ngKey(R, p, k), r);
        if (L.tot > 0) {
            const disc = @max(@as(f64, @floatFromInt(L.c)) - DISC, 0.0) / @as(f64, @floatFromInt(L.tot));
            const lam = DISC * @as(f64, @floatFromInt(L.types)) / @as(f64, @floatFromInt(L.tot));
            prob = disc + lam * prob; // higher order interpolates the running lower-order estimate
        }
    }
    return prob;
}
// final probability: rune n-gram blended with phrase- and concept-conditioned experts (each abs-disc, backoff to p_rune)
fn discBackoff(L: Look, base: f64) f64 {
    if (L.tot == 0) return base;
    const disc = @max(@as(f64, @floatFromInt(L.c)) - DISC, 0.0) / @as(f64, @floatFromInt(L.tot));
    const lam = DISC * @as(f64, @floatFromInt(L.types)) / @as(f64, @floatFromInt(L.tot));
    return disc + lam * base;
}
fn pFinal(R: []const u32, p: usize, r: u32, prevP: u32, prevC: u32, bucket: u32) f64 {
    const pr = pRune(R, p, r);
    const pp = discBackoff(look(&phr, mix((@as(u64, prevP) << 24) ^ @as(u64, R[p - 1])), r), pr);
    const pcp = discBackoff(look(&con, mix((@as(u64, prevC) << 24) ^ @as(u64, R[p - 1])), r), pr);
    const pl = discBackoff(look(&lsh, bucket, r), pr); // kNN/embedding-similar context smoothing
    return 0.72 * pr + 0.12 * pp + 0.06 * pcp + 0.10 * pl;
}
fn update(a: std.mem.Allocator, R: []const u32, p: usize, r: u32, prevP: u32, prevC: u32, bucket: u32) !void {
    for (0..ORD + 1) |k| {
        if (k > p) break;
        try bump(a, &ng[k], ngKey(R, p, k), r);
    }
    try bump(a, &phr, mix((@as(u64, prevP) << 24) ^ @as(u64, R[p - 1])), r);
    try bump(a, &con, mix((@as(u64, prevC) << 24) ^ @as(u64, R[p - 1])), r);
    try bump(a, &lsh, bucket, r);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    const dir = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus";

    var trainMB: usize = 0; // 0 = use the 3 books fully
    var dewrap = false; // arg2 == "dw" → collapse hard line-wraps (formatting control)
    {
        const args = try std.process.argsAlloc(a);
        if (args.len > 1) trainMB = try std.fmt.parseInt(usize, args[1], 10);
        if (args.len > 2 and std.mem.eql(u8, args[2], "dw")) dewrap = true;
    }

    try o.print("=== LM-BPC3 — Option 1: abs-disc + kNN/LSH EMBEDDING SMOOTHING (cheap generalization ceiling). dewrap={} ===\n\n", .{dewrap});

    var tr = std.ArrayList(u8).init(a);
    for ([_][]const u8{ "moby_dick.txt", "shakespeare.txt", "tolstoy.txt" }) |fnm| {
        const p = try std.fs.path.join(a, &.{ dir, fnm });
        const f = std.fs.openFileAbsolute(p, .{}) catch continue;
        defer f.close();
        try tr.appendSlice(try f.readToEndAlloc(a, 1 << 30));
    }
    const cap: usize = if (trainMB > 0) trainMB * 1_000_000 else tr.items.len;
    var TRB = tr.items[0..@min(cap, tr.items.len)];
    const hp = try std.fs.path.join(a, &.{ dir, "heldout_eval.txt" });
    const hf = try std.fs.openFileAbsolute(hp, .{});
    var HB = try hf.readToEndAlloc(a, 1 << 30);
    hf.close();
    if (dewrap) { // formatting control: collapse hard line-wraps in BOTH warm-start and held-out
        TRB = try dewrapBytes(a, TRB);
        HB = try dewrapBytes(a, HB);
    }

    var trU = try a.alloc(u32, TRB.len);
    for (0..TRB.len) |i| trU[i] = TRB[i];
    const rbpe = try bpe(a, trU[0..@min(TRB.len, 600_000)], 256, RUNE_MERGES, MAXLEN); // forge on a sample
    const V = rbpe.vocab.items.len;
    invV = 1.0 / @as(f64, @floatFromInt(V));
    var runeTrie = try Trie.init(a);
    for (0..V) |i| try runeTrie.add(rbpe.vocab.items[i], @intCast(i));

    var trUf = try a.alloc(u32, TRB.len);
    for (0..TRB.len) |i| trUf[i] = TRB[i];
    const TR = try segment(a, &runeTrie, trUf, null);
    var hUf = try a.alloc(u32, HB.len);
    for (0..HB.len) |i| hUf[i] = HB[i];
    const EV = try segment(a, &runeTrie, hUf, null);

    const pbpe = try bpe(a, TR, V, PHRASE_MERGES, MAXLEN);
    var phraseTrie = try Trie.init(a);
    for (0..pbpe.vocab.items.len) |i| try phraseTrie.add(pbpe.vocab.items[i], @intCast(i));
    const cbpe = try bpe(a, pbpe.seq, pbpe.vocab.items.len, CONCEPT_MERGES, MAXLEN);
    var conceptTrie = try Trie.init(a);
    for (0..cbpe.vocab.items.len) |i| try conceptTrie.add(cbpe.vocab.items[i], @intCast(i));

    const evPhOf = try a.alloc(u32, EV.len);
    const evPH = try segment(a, &phraseTrie, EV, evPhOf);
    const evCoOfPh = try a.alloc(u32, evPH.len);
    const evCO = try segment(a, &conceptTrie, evPH, evCoOfPh);
    const trPhOf = try a.alloc(u32, TR.len);
    const trPH = try segment(a, &phraseTrie, TR, trPhOf);
    const trCoOfPh = try a.alloc(u32, trPH.len);
    const trCO = try segment(a, &conceptTrie, trPH, trCoOfPh);

    for (0..ORD + 1) |k| ng[k] = CT.init(a);
    phr = CT.init(a);
    con = CT.init(a);
    lsh = CT.init(a);

    // build cheap PPMI embeddings (rune × top-ED-rune co-occurrence, L2-normalized) from the training rune stream
    emb = try std.heap.page_allocator.alloc(f32, V * ED);
    @memset(emb, 0);
    {
        var ring = [_]i32{-1} ** 4;
        for (0..TR.len) |i| {
            const cc: usize = TR[i];
            for (ring) |rr| if (rr >= 0 and @as(usize, @intCast(rr)) < ED) {
                const ur: usize = @intCast(rr);
                emb[cc * ED + ur] += 1;
                if (cc < ED) emb[@as(usize, @intCast(rr)) * ED + cc] += 1;
            };
            var k: usize = 3;
            while (k > 0) : (k -= 1) ring[k] = ring[k - 1];
            ring[0] = @intCast(cc);
        }
        for (0..V) |t| {
            var n2: f64 = 0;
            for (0..ED) |c| n2 += @as(f64, emb[t * ED + c]) * @as(f64, emb[t * ED + c]);
            if (n2 > 0) {
                const iv: f32 = @floatCast(1.0 / @sqrt(n2));
                for (0..ED) |c| emb[t * ED + c] *= iv;
            }
        }
    }
    proj = try a.alloc(f32, LBITS * ED);
    for (0..LBITS * ED) |i| {
        rngE ^= rngE << 13;
        rngE ^= rngE >> 7;
        rngE ^= rngE << 17;
        proj[i] = (@as(f32, @floatFromInt(rngE % 2000)) - 1000.0) / 1000.0;
    }

    // warm-start: train counts on TR
    {
        var p: usize = ORD;
        while (p < TR.len) : (p += 1) {
            const cph = trPhOf[p];
            const prevP: u32 = if (cph > 0) trPH[cph - 1] else 0;
            const cco = trCoOfPh[cph];
            const prevC: u32 = if (cco > 0) trCO[cco - 1] else 0;
            try update(a, TR, p, TR[p], prevP, prevC, ctxBucket(TR, p));
        }
    }

    // FROZEN pass (no updates on held-out) — raw transfer capability
    var frozenBits: f64 = 0;
    {
        var p: usize = ORD;
        while (p < EV.len) : (p += 1) {
            const cph = evPhOf[p];
            const prevP: u32 = if (cph > 0) evPH[cph - 1] else 0;
            const cco = evCoOfPh[cph];
            const prevC: u32 = if (cco > 0) evCO[cco - 1] else 0;
            const prob = pFinal(EV, p, EV[p], prevP, prevC, ctxBucket(EV, p));
            frozenBits += -std.math.log2(@max(prob, 1e-12));
        }
    }
    // PREQUENTIAL pass (predict-then-update) — continual learning
    var preqBits: f64 = 0;
    var scored: usize = 0;
    {
        var p: usize = ORD;
        while (p < EV.len) : (p += 1) {
            const cph = evPhOf[p];
            const prevP: u32 = if (cph > 0) evPH[cph - 1] else 0;
            const cco = evCoOfPh[cph];
            const prevC: u32 = if (cco > 0) evCO[cco - 1] else 0;
            const bk = ctxBucket(EV, p);
            const prob = pFinal(EV, p, EV[p], prevP, prevC, bk);
            preqBits += -std.math.log2(@max(prob, 1e-12));
            scored += 1;
            try update(a, EV, p, EV[p], prevP, prevC, bk);
        }
    }

    const nbytes = HB.len;
    try o.print("warm-start {d:.1} MB ({d} runes) → held-out {d} bytes / {d} runes ({d:.2} B/rune), rune vocab {d}.\n\n", .{ @as(f64, @floatFromInt(TRB.len)) / 1e6, TR.len, nbytes, EV.len, @as(f64, @floatFromInt(nbytes)) / @as(f64, @floatFromInt(EV.len)), V });
    const bf = frozenBits / @as(f64, @floatFromInt(nbytes));
    const bp = preqBits / @as(f64, @floatFromInt(nbytes));
    // FAIR gpt2 baseline depends on formatting: 1.0499 on de-wrapped (flowing) text, 1.9105 on wrapped (which fragments
    // gpt2's context — an unfair confound we caught with the de-wrap control). Compare against the matching setting.
    const gpt2 = if (dewrap) @as(f64, 1.0499) else @as(f64, 1.9105);
    try o.print("  OUR FROZEN (warm-start only)      BPB = {d:.4}\n", .{bf});
    try o.print("  OUR PREQUENTIAL (continual)       BPB = {d:.4}   (rune-ppl {d:.1})\n\n", .{ bp, std.math.exp(preqBits / @as(f64, @floatFromInt(scored)) * std.math.ln2) });
    try o.print("  gpt2-124M baseline ({s}) = {d:.4}\n", .{ if (dewrap) "de-wrapped / FAIR flowing text" else "WRAPPED — confounded, gpt2's context is fragmented", gpt2 });
    try o.print("  Δ vs gpt2: frozen {s}{d:.4}, prequential {s}{d:.4}  (negative = we beat gpt2; on FAIR text gpt2 wins big)\n", .{ if (bf - gpt2 >= 0) "+" else "", bf - gpt2, if (bp - gpt2 >= 0) "+" else "", bp - gpt2 });
}
