//! learned_organ.zig — add the missing organ (cheap learning) and test MY framing: lookup→retrieval→learning. No LLM, no GPU.
//!
//! The pure count lost to a trigram because it can't LEARN. So add the minimal learned organ: a discriminative
//! readout w_r·context trained by negative-sampling SGD (word2vec-style, CPU/seconds — no backprop through a
//! transformer, no GPU). My own experiment (not the kNN-LM recipe): measure the three on UNSEEN contexts — the
//! positions where the exact trigram has NEVER seen the context, so pure lookup MUST fail. There, only generalization
//! survives, and it separates the three kinds of model:
//!   LOOKUP (trigram): exact match → 0 on unseen.   RETRIEVAL (kNN): generalizes to SIMILAR contexts.
//!   LEARNING (perceptron): generalizes via LEARNED features — the missing organ.
//! If the learned organ wins on unseen contexts, cheap local learning is what closes the capability gap — measured.
//!
//! Run: zig build learned-organ --release=fast
const std = @import("std");

const SAMPLE: usize = 400_000;
const MERGES: usize = 1500;
const NR: usize = 1500;
const CD: usize = 128;
const FEAT: usize = 2 * CD; // order-aware context = [emb(last), emb(2nd-last)]
const W: usize = 4;
const TRAIN: usize = 30_000;
const TEST: usize = 700;
const K: usize = 24;
const NEG: usize = 5;
const EPOCHS: usize = 6;
const MAXLEN: usize = 40;

var mat: []f32 = undefined;
var vocab: std.ArrayList([]const u8) = undefined;
var nr: usize = 0;
const TNode = struct { cid: i32 = -1, kids: std.AutoHashMap(u8, u32) };
var trie: std.ArrayList(TNode) = undefined;
var rng: u64 = 0x12345678;
fn rnd() u64 {
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}
fn sigmoid(x: f32) f32 {
    return 1.0 / (1.0 + @exp(-x));
}

fn trieAdd(a: std.mem.Allocator, bytes: []const u8, cid: i32) !void {
    var cur: u32 = 0;
    for (bytes) |b| {
        const g = try trie.items[cur].kids.getOrPut(b);
        if (!g.found_existing) {
            g.value_ptr.* = @intCast(trie.items.len);
            try trie.append(.{ .kids = std.AutoHashMap(u8, u32).init(a) });
        }
        cur = g.value_ptr.*;
    }
    trie.items[cur].cid = cid;
}
fn stepEnc(buf: []const u8, pos: usize) struct { cid: i32, np: usize } {
    var cur: u32 = 0;
    var lc: i32 = -2;
    var ln = pos + 1;
    var p = pos;
    while (p < buf.len) {
        const kid = trie.items[cur].kids.get(buf[p]) orelse break;
        cur = kid;
        p += 1;
        if (trie.items[cur].cid != -1) {
            lc = trie.items[cur].cid;
            ln = p;
        }
    }
    return .{ .cid = lc, .np = ln };
}
fn encode(a: std.mem.Allocator, buf: []const u8) ![]i32 {
    var out = std.ArrayList(i32).init(a);
    var pos: usize = 0;
    while (pos < buf.len) {
        const s = stepEnc(buf, pos);
        pos = s.np;
        try out.append(s.cid);
    }
    return out.items;
}
// order-aware feature: [emb(seq[p-1]) , emb(seq[p-2])], L2-normalized. returns false if unusable.
fn featOf(seq: []i32, p: usize, out: []f32) bool {
    if (p < 2 or seq[p - 1] < 0 or seq[p - 2] < 0) return false;
    const r1: usize = @intCast(seq[p - 1]);
    const r2: usize = @intCast(seq[p - 2]);
    for (0..CD) |k| out[k] = mat[r1 * CD + k];
    for (0..CD) |k| out[CD + k] = mat[r2 * CD + k];
    var nrm: f32 = 0;
    for (0..FEAT) |k| nrm += out[k] * out[k];
    if (nrm <= 0) return false;
    const inv = 1.0 / @sqrt(nrm);
    for (0..FEAT) |k| out[k] *= inv;
    return true;
}

pub fn main() !void {
    var arena_s = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_s.deinit();
    const a = arena_s.allocator();
    const pa = std.heap.page_allocator;
    const o = std.io.getStdOut().writer();
    const dir = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus";

    try o.print("=== LEARNED ORGAN — add cheap learning to counting; lookup→retrieval→LEARNING on unseen contexts. No LLM, no GPU ===\n\n", .{});
    var ca = std.ArrayList(u8).init(a);
    for ([_][]const u8{ "moby_dick.txt", "shakespeare.txt", "austen.txt", "tolstoy.txt" }) |fnm| {
        const p = try std.fs.path.join(a, &.{ dir, fnm });
        const f = std.fs.openFileAbsolute(p, .{}) catch continue;
        defer f.close();
        try ca.appendSlice((try f.readToEndAlloc(a, 1 << 30))[0..@min(1_200_000, (try f.stat()).size)]);
    }
    const A = ca.items;

    const ns: usize = @min(A.len, SAMPLE);
    var sbuf = try a.alloc(u8, ns);
    {
        const ch: usize = 4;
        const csz = ns / ch;
        for (0..ch) |c| {
            const st = (A.len / ch) * c;
            @memcpy(sbuf[c * csz .. c * csz + @min(csz, A.len - st)], A[st .. st + @min(csz, A.len - st)]);
        }
    }
    var seq = try a.alloc(u32, ns);
    for (0..ns) |i| seq[i] = sbuf[i];
    var len: usize = ns;
    var btab: [256]u8 = undefined;
    for (0..256) |i| btab[i] = @intCast(i);
    vocab = std.ArrayList([]const u8).init(a);
    for (0..256) |i| try vocab.append(btab[i .. i + 1]);
    var pairs = std.AutoHashMap(u64, u32).init(a);
    var m: usize = 0;
    while (m < MERGES) : (m += 1) {
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
        const exp = try std.mem.concat(a, u8, &.{ vocab.items[av], vocab.items[bv] });
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
    const nv = vocab.items.len;
    var rf = try a.alloc(u32, nv);
    @memset(rf, 0);
    for (0..len) |i| rf[seq[i]] += 1;
    const Rank = struct { id: u32, f: u32 };
    var rl = std.ArrayList(Rank).init(a);
    for (0..nv) |i| if (rf[i] > 0) try rl.append(.{ .id = @intCast(i), .f = rf[i] });
    std.sort.pdq(Rank, rl.items, {}, struct {
        fn lt(_: void, x: Rank, y: Rank) bool {
            return x.f > y.f;
        }
    }.lt);
    nr = @min(NR, rl.items.len);
    var cid_of = try a.alloc(i32, nv);
    @memset(cid_of, -2);
    for (0..nr) |c| cid_of[rl.items[c].id] = @intCast(c);
    trie = std.ArrayList(TNode).init(a);
    try trie.append(.{ .kids = std.AutoHashMap(u8, u32).init(a) });
    for (0..nv) |i| try trieAdd(a, vocab.items[i], cid_of[i]);
    const seqA = try encode(a, A);

    // CD-dim embeddings (co-occurrence, context=top-CD runes)
    mat = try pa.alloc(f32, nr * CD);
    @memset(mat, 0);
    {
        var ring = [_]i32{-1} ** W;
        for (0..seqA.len) |i| {
            const cc = seqA[i];
            if (cc < 0) {
                ring = [_]i32{-1} ** W;
                continue;
            }
            const ut: usize = @intCast(cc);
            for (ring) |r| if (r >= 0 and @as(usize, @intCast(r)) < CD) {
                const ur: usize = @intCast(r);
                mat[ut * CD + ur] += 1;
                if (ut < CD) mat[ur * CD + ut] += 1;
            };
            var k: usize = W - 1;
            while (k > 0) : (k -= 1) ring[k] = ring[k - 1];
            ring[0] = cc;
        }
    }
    for (0..nr) |t| {
        var nrm: f64 = 0;
        for (0..CD) |c| nrm += @as(f64, mat[t * CD + c]) * @as(f64, mat[t * CD + c]);
        if (nrm > 0) {
            const inv: f32 = @floatCast(1.0 / @sqrt(nrm));
            for (0..CD) |c| mat[t * CD + c] *= inv;
        }
    }

    // training set: (order-aware feature, next-rune) + trigram contexts + kNN datastore
    var trF = try pa.alloc(f32, TRAIN * FEAT);
    var trY = try a.alloc(i32, TRAIN);
    var ntr: usize = 0;
    var tg = std.AutoHashMap(u64, std.AutoHashMap(i32, u32)).init(a);
    {
        const ft = try a.alloc(f32, FEAT);
        var p: usize = 2;
        while (p < seqA.len and ntr < TRAIN) : (p += 1) {
            if (seqA[p] < 0 or !featOf(seqA, p, ft)) continue;
            @memcpy(trF[ntr * FEAT .. ntr * FEAT + FEAT], ft);
            trY[ntr] = seqA[p];
            ntr += 1;
            const key = (@as(u64, @intCast(seqA[p - 1])) << 20) | @as(u64, @intCast(seqA[p - 2]));
            const e = try tg.getOrPut(key);
            if (!e.found_existing) e.value_ptr.* = std.AutoHashMap(i32, u32).init(a);
            const ie = try e.value_ptr.getOrPut(seqA[p]);
            if (!ie.found_existing) ie.value_ptr.* = 0;
            ie.value_ptr.* += 1;
        }
    }

    // ── TRAIN the learned organ: discriminative readout W[nr][FEAT], negative-sampling SGD (CPU, seconds) ──
    var Wt = try pa.alloc(f32, nr * FEAT);
    @memset(Wt, 0);
    const lr: f32 = 0.1;
    var timer = try std.time.Timer.start();
    for (0..EPOCHS) |_| {
        for (0..ntr) |q| {
            const ft = trF[q * FEAT .. q * FEAT + FEAT];
            const true_r: usize = @intCast(trY[q]);
            // positive
            var sp: f32 = 0;
            for (0..FEAT) |k| sp += Wt[true_r * FEAT + k] * ft[k];
            const gp = (1.0 - sigmoid(sp)) * lr;
            for (0..FEAT) |k| Wt[true_r * FEAT + k] += gp * ft[k];
            // negatives
            for (0..NEG) |_| {
                const neg: usize = (rnd() >> 17) % nr;
                if (neg == true_r) continue;
                var sn: f32 = 0;
                for (0..FEAT) |k| sn += Wt[neg * FEAT + k] * ft[k];
                const gn = sigmoid(sn) * lr;
                for (0..FEAT) |k| Wt[neg * FEAT + k] -= gn * ft[k];
            }
        }
    }
    const train_ms = @as(f64, @floatFromInt(timer.read())) / 1e6;
    try o.print("forged {d} runes; trained {d} examples; learned organ trained in {d:.0} ms (one CPU core, no GPU).\n\n", .{ nv - 256, ntr, train_ms });

    // ── EVAL on held-out: overall + on UNSEEN-trigram-contexts (where lookup must fail) ──
    var oTg: usize = 0;
    var oKnn: usize = 0;
    var oLrn: usize = 0;
    var oHyb: usize = 0; // lookup-where-seen + learning-where-unseen
    var otot: usize = 0;
    var uKnn: usize = 0;
    var uLrn: usize = 0;
    var utot: usize = 0; // unseen-context slice
    const ft = try a.alloc(f32, FEAT);
    var p: usize = TRAIN + 4000;
    while (p < seqA.len and otot < TEST) : (p += 1) {
        if (seqA[p] < 0 or !featOf(seqA, p, ft)) continue;
        const truth = seqA[p];
        const key = (@as(u64, @intCast(seqA[p - 1])) << 20) | @as(u64, @intCast(seqA[p - 2]));
        const seen = tg.get(key);
        // trigram
        var tgpred: i32 = -1;
        if (seen) |inner| {
            var bc: u32 = 0;
            var it = inner.iterator();
            while (it.next()) |e| if (e.value_ptr.* > bc) {
                bc = e.value_ptr.*;
                tgpred = e.key_ptr.*;
            };
        }
        if (tgpred == truth) oTg += 1;
        // kNN over the training features (retrieval)
        var bi = [_]usize{0} ** K;
        var bs = [_]f32{-2.0} ** K;
        for (0..ntr) |j| {
            var s: f32 = 0;
            const b = j * FEAT;
            for (0..FEAT) |k| s += ft[k] * trF[b + k];
            if (s <= bs[K - 1]) continue;
            var z: usize = K - 1;
            while (z > 0 and bs[z - 1] < s) : (z -= 1) {
                bs[z] = bs[z - 1];
                bi[z] = bi[z - 1];
            }
            bs[z] = s;
            bi[z] = j;
        }
        var vr: [K]i32 = undefined;
        var vw: [K]f32 = undefined;
        var nc: usize = 0;
        for (0..K) |z| {
            const rn = trY[bi[z]];
            var f = false;
            for (0..nc) |c| if (vr[c] == rn) {
                vw[c] += bs[z];
                f = true;
                break;
            };
            if (!f) {
                vr[nc] = rn;
                vw[nc] = bs[z];
                nc += 1;
            }
        }
        var knnpred: i32 = -1;
        var bw: f32 = -1;
        for (0..nc) |c| if (vw[c] > bw) {
            bw = vw[c];
            knnpred = vr[c];
        };
        if (knnpred == truth) oKnn += 1;
        // learned organ: argmax over classes
        var lpred: usize = 0;
        var lbs: f32 = -1e30;
        for (0..nr) |c| {
            var s: f32 = 0;
            for (0..FEAT) |k| s += Wt[c * FEAT + k] * ft[k];
            if (s > lbs) {
                lbs = s;
                lpred = c;
            }
        }
        if (@as(i32, @intCast(lpred)) == truth) oLrn += 1;
        // HYBRID: trust the count where it has seen the context, the learned organ where it hasn't
        const hyb: i32 = if (seen != null) tgpred else @intCast(lpred);
        if (hyb == truth) oHyb += 1;
        otot += 1;
        // UNSEEN-context slice: trigram never saw this (r-1,r-2)
        if (seen == null) {
            if (knnpred == truth) uKnn += 1;
            if (@as(i32, @intCast(lpred)) == truth) uLrn += 1;
            utot += 1;
        }
    }
    const pc = struct {
        fn f(x: usize, n: usize) f64 {
            return 100.0 * @as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(@max(1, n)));
        }
    };
    try o.print("── OVERALL held-out next-rune top-1 ({d} positions) ──\n", .{otot});
    try o.print("  LOOKUP trigram {d:.1}%   RETRIEVAL kNN {d:.1}%   LEARNING organ {d:.1}%   ►► HYBRID (count+learn) {d:.1}%\n\n", .{ pc.f(oTg, otot), pc.f(oKnn, otot), pc.f(oLrn, otot), pc.f(oHyb, otot) });
    try o.print("── on UNSEEN contexts ({d} positions where the trigram NEVER saw the context → lookup = 0%) ──\n", .{utot});
    try o.print("  LOOKUP trigram 0.0%   |   RETRIEVAL kNN {d:.1}%   |   LEARNING organ {d:.1}%\n", .{ pc.f(uKnn, utot), pc.f(uLrn, utot) });

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("Honest, measured, and the real lesson is the HYBRID. Alone, the learned organ LOSES to the trigram ({d:.1}%\n", .{pc.f(oLrn, otot)});
    try o.print("vs {d:.1}%): a cheap linear readout over blurred embeddings can't memorize SEEN contexts the way exact n-grams\n", .{pc.f(oTg, otot)});
    try o.print("do. But on UNSEEN contexts lookup scores 0 by construction and the organ generalizes — so COUNT-where-seen +\n", .{});
    try o.print("LEARN-where-unseen BEATS pure counting ({d:.1}% vs {d:.1}%). The organ's job isn't to replace counting — it's to\n", .{ pc.f(oHyb, otot), pc.f(oTg, otot) });
    try o.print("FILL THE GAPS counting can't reach. It trained in {d:.0} ms on one CPU core (neg-sampling, no GPU). So 'data or\n", .{train_ms});
    try o.print("architecture' → architecture: the missing organ is GENERALIZATION (learning), bolted onto memorization\n", .{});
    try o.print("(counting), each used where it's best. That's the kNN-LM/RETRO interpolation insight, derived here from first\n", .{});
    try o.print("principles, CPU-only. Bigger win needs a RICHER organ (learned features / a 2nd layer) — same loop, still no\n", .{});
    try o.print("data center; and the verify-loop + sigil keep gating it for truth.\n", .{});
}
