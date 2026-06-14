//! hier_runes.zig — GIANT SWING at DEPTH without attention: HIERARCHICAL RUNES. Compose discovered units bottom-up
//! (bytes → runes → phrases → concepts), each level a FEATURE-OF-FEATURES, and predict the next rune from MULTI-SCALE
//! context (recent runes + current phrase + current concept). That is depth via COMPOSITION — the thing a transformer's
//! layers buy — native to the discrete-rune substrate, O(1)/step, no softmax, no n², no GPU, no LLM.
//!
//! Level 1 = runes (BPE over bytes). Level 2 = phrases (BPE over the RUNE stream). Level 3 = concepts (BPE over phrases).
//! For each rune position we know the last completed phrase id and concept id (abstract long-range context). Experts:
//!   rune n-gram (local) · phrase-conditioned · concept-conditioned — combined by a SIGIL-reliability committee.
//! HYPOTHESIS: abstract higher-level context improves next-rune over rune-only. Measured, prequential, honest either way.
//!
//! Run: zig build hier-runes --release=fast
const std = @import("std");

const SAMPLE: usize = 400_000;
const RUNE_MERGES: usize = 1200;
const PHRASE_MERGES: usize = 1200;
const CONCEPT_MERGES: usize = 800;
const NRC: usize = 400;
const STREAM: usize = 500_000;
const WARM: usize = 40_000;
const MAXLEN: usize = 48;

var rng: u64 = 0xCBF29CE484222325;
fn mix(h: u64) u64 {
    var z = h +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

// generic BPE over a u32 symbol sequence. Returns vocab where vocab[i] = the BASE-symbol expansion of symbol i
// (vocab[i] for i<nbase is [i]); merged entries are concat of their pair's expansions. Also returns the merged sequence.
const Bpe = struct {
    vocab: std.ArrayList([]u32),
    seq: []u32,
    nbase: usize,
};
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
    return .{ .vocab = vocab, .seq = seq[0..len], .nbase = nbase };
}

// u32-keyed trie for greedy longest-match segmentation over base symbols
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
    // greedy longest match starting at pos; returns {id, next_pos}
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

// segment `buf` (base symbols) into units via the trie; fill unitOf[pos] = unit-index, and return the unit-id sequence
fn segment(a: std.mem.Allocator, t: *Trie, buf: []const u32, unitOf: []u32) ![]u32 {
    var units = std.ArrayList(u32).init(a);
    var pos: usize = 0;
    while (pos < buf.len) {
        const s = t.step(buf, pos);
        const uidx: u32 = @intCast(units.items.len);
        const id: u32 = if (s.id < 0) 0 else @intCast(s.id);
        try units.append(id);
        for (pos..s.np) |q| unitOf[q] = uidx; // every base pos in this unit maps to the unit index
        pos = s.np;
    }
    return units.items;
}

const Sigil = struct {
    avg: f64 = 0,
    fn upd(self: *Sigil, s: f64, keep: f64) void {
        self.avg = self.avg * keep + s * (1.0 - keep);
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    const dir = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus";

    try o.print("=== HIERARCHICAL RUNES — depth via composition (bytes→runes→phrases→concepts), multi-scale next-rune. No attention ===\n\n", .{});

    var ca = std.ArrayList(u8).init(a);
    for ([_][]const u8{ "moby_dick.txt", "shakespeare.txt", "austen.txt", "tolstoy.txt" }) |fnm| {
        const p = try std.fs.path.join(a, &.{ dir, fnm });
        const f = std.fs.openFileAbsolute(p, .{}) catch continue;
        defer f.close();
        try ca.appendSlice((try f.readToEndAlloc(a, 1 << 30))[0..@min(1_200_000, (try f.stat()).size)]);
    }
    const A = ca.items;
    const ns: usize = @min(A.len, SAMPLE);
    // sample 4 spread chunks for forging
    var sbuf = try a.alloc(u8, ns);
    {
        const ch: usize = 4;
        const csz = ns / ch;
        for (0..ch) |c| {
            const st = (A.len / ch) * c;
            @memcpy(sbuf[c * csz .. c * csz + @min(csz, A.len - st)], A[st .. st + @min(csz, A.len - st)]);
        }
    }
    // LEVEL 1: bytes → runes (BPE over bytes)
    var byteSeq = try a.alloc(u32, ns);
    for (0..ns) |i| byteSeq[i] = sbuf[i];
    const rb = try bpe(a, byteSeq, 256, RUNE_MERGES, MAXLEN);
    // rune trie over bytes, to encode the FULL corpus into runes
    var runeTrie = try Trie.init(a);
    for (0..rb.vocab.items.len) |i| try runeTrie.add(rb.vocab.items[i], @intCast(i));
    var fullBytes = try a.alloc(u32, @min(A.len, STREAM * 6));
    const fbn = @min(A.len, fullBytes.len);
    for (0..fbn) |i| fullBytes[i] = A[i];
    const dummy1 = try a.alloc(u32, fbn);
    const R = try segment(a, &runeTrie, fullBytes[0..fbn], dummy1); // rune-id sequence (level 1)
    const LR = @min(R.len, STREAM);

    // LEVEL 2: runes → phrases (BPE over the rune stream)
    const pb = try bpe(a, R[0..LR], rb.vocab.items.len, PHRASE_MERGES, MAXLEN);
    var phraseTrie = try Trie.init(a);
    for (0..pb.vocab.items.len) |i| try phraseTrie.add(pb.vocab.items[i], @intCast(i));
    const phraseOf = try a.alloc(u32, LR); // rune position → phrase-unit index
    const PH = try segment(a, &phraseTrie, R[0..LR], phraseOf); // phrase-id sequence (level 2)

    // LEVEL 3: phrases → concepts (BPE over the phrase stream)
    const cb = try bpe(a, PH, pb.vocab.items.len, CONCEPT_MERGES, MAXLEN);
    var conceptTrie = try Trie.init(a);
    for (0..cb.vocab.items.len) |i| try conceptTrie.add(cb.vocab.items[i], @intCast(i));
    const conceptOfPhrase = try a.alloc(u32, PH.len); // phrase-unit index → concept-unit index
    const CO = try segment(a, &conceptTrie, PH, conceptOfPhrase); // concept-id sequence (level 3)

    try o.print("forged: runes {d}, phrases {d}, concepts {d}. stream {d} runes ({d} phrases, {d} concepts).\n\n", .{ rb.vocab.items.len - 256, pb.vocab.items.len - rb.vocab.items.len, cb.vocab.items.len - pb.vocab.items.len, LR, PH.len, CO.len });

    // ── online prequential next-rune ──
    // E_rune: order-2 + order-3 rune n-gram (committee handles backoff). key by rune ids.
    var cnt2 = std.AutoHashMap(u64, std.AutoHashMap(u32, u32)).init(a);
    var cnt3 = std.AutoHashMap(u64, std.AutoHashMap(u32, u32)).init(a);
    // E_phrase: key = (prev completed phrase id, last rune) → next rune
    var cphr = std.AutoHashMap(u64, std.AutoHashMap(u32, u32)).init(a);
    // E_concept: key = (prev completed concept id, last rune) → next rune
    var ccon = std.AutoHashMap(u64, std.AutoHashMap(u32, u32)).init(a);

    const NEXP = 4;
    var reliab: [NEXP]Sigil = .{Sigil{}} ** NEXP;
    const epred = try a.alloc(i32, NEXP);
    var votes = std.AutoHashMap(u32, f64).init(a);

    var nE: [NEXP]usize = .{0} ** NEXP;
    var nRuneOnly: usize = 0; // committee using only rune experts (E0,E1)
    var nFull: usize = 0; // committee using all experts
    var tot: usize = 0;

    const getMaj = struct {
        fn f(map: *std.AutoHashMap(u64, std.AutoHashMap(u32, u32)), key: u64) i32 {
            if (map.get(key)) |inner| {
                var bc2: u32 = 0;
                var pr: i32 = -1;
                var it = inner.iterator();
                while (it.next()) |e| if (e.value_ptr.* > bc2) {
                    bc2 = e.value_ptr.*;
                    pr = @intCast(e.key_ptr.*);
                };
                return pr;
            }
            return -1;
        }
    }.f;
    const bump = struct {
        fn f(al: std.mem.Allocator, map: *std.AutoHashMap(u64, std.AutoHashMap(u32, u32)), key: u64, val: u32) !void {
            const e = try map.getOrPut(key);
            if (!e.found_existing) e.value_ptr.* = std.AutoHashMap(u32, u32).init(al);
            const ie = try e.value_ptr.getOrPut(val);
            if (!ie.found_existing) ie.value_ptr.* = 0;
            ie.value_ptr.* += 1;
        }
    }.f;

    var p: usize = 2;
    while (p < LR) : (p += 1) {
        const truth = R[p];
        const scoring = p >= WARM and truth < NRC;
        const r1 = R[p - 1];
        const r2 = R[p - 2];
        // abstract context: previous completed phrase id, previous completed concept id
        const curPhrase = phraseOf[p];
        const prevPhrase: u32 = if (curPhrase > 0) PH[curPhrase - 1] else 0;
        const curConcept = conceptOfPhrase[curPhrase];
        const prevConcept: u32 = if (curConcept > 0) CO[curConcept - 1] else 0;

        const k2 = (@as(u64, r1) << 24) | @as(u64, r2);
        const k3b = mix((@as(u64, r1) << 40) ^ (@as(u64, r2) << 20) ^ @as(u64, if (p >= 3) R[p - 3] else 0));
        const kp = mix((@as(u64, prevPhrase) << 24) ^ @as(u64, r1));
        const kc = mix((@as(u64, prevConcept) << 24) ^ @as(u64, r1));

        epred[0] = getMaj(&cnt2, k2);
        epred[1] = getMaj(&cnt3, k3b);
        epred[2] = getMaj(&cphr, kp);
        epred[3] = getMaj(&ccon, kc);

        // committee votes (sigil reliability weighted). Two variants: rune-only (0,1) and full (0..3).
        var runePred: i32 = -1;
        var fullPred: i32 = -1;
        {
            votes.clearRetainingCapacity();
            var best: f64 = -1;
            for (0..2) |i| if (epred[i] >= 0) {
                const w = reliab[i].avg + 0.02;
                const e = try votes.getOrPut(@intCast(epred[i]));
                if (!e.found_existing) e.value_ptr.* = 0;
                e.value_ptr.* += w;
                if (e.value_ptr.* > best) {
                    best = e.value_ptr.*;
                    runePred = epred[i];
                }
            };
        }
        {
            votes.clearRetainingCapacity();
            var best: f64 = -1;
            for (0..NEXP) |i| if (epred[i] >= 0) {
                const w = reliab[i].avg + 0.02;
                const e = try votes.getOrPut(@intCast(epred[i]));
                if (!e.found_existing) e.value_ptr.* = 0;
                e.value_ptr.* += w;
                if (e.value_ptr.* > best) {
                    best = e.value_ptr.*;
                    fullPred = epred[i];
                }
            };
        }

        if (scoring) {
            tot += 1;
            for (0..NEXP) |i| if (epred[i] == @as(i32, @intCast(truth))) {
                nE[i] += 1;
            };
            if (runePred == @as(i32, @intCast(truth))) nRuneOnly += 1;
            if (fullPred == @as(i32, @intCast(truth))) nFull += 1;
        }
        // update reliabilities + tables
        for (0..NEXP) |i| if (epred[i] >= 0) reliab[i].upd(if (epred[i] == @as(i32, @intCast(truth))) 1.0 else 0.0, 0.997);
        try bump(a, &cnt2, k2, truth);
        try bump(a, &cnt3, k3b, truth);
        try bump(a, &cphr, kp, truth);
        try bump(a, &ccon, kc, truth);
    }

    const pc = struct {
        fn f(x: usize, n: usize) f64 {
            return 100.0 * @as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(@max(1, n)));
        }
    };
    try o.print("── individual experts (online next-rune top-1, {d} scored) ──\n", .{tot});
    try o.print("  E0 rune order-2     {d:.1}%   (reliab {d:.2})\n", .{ pc.f(nE[0], tot), reliab[0].avg });
    try o.print("  E1 rune order-3     {d:.1}%   (reliab {d:.2})\n", .{ pc.f(nE[1], tot), reliab[1].avg });
    try o.print("  E2 PHRASE-cond      {d:.1}%   (reliab {d:.2})  ← level-2 abstract context\n", .{ pc.f(nE[2], tot), reliab[2].avg });
    try o.print("  E3 CONCEPT-cond     {d:.1}%   (reliab {d:.2})  ← level-3 abstract context\n\n", .{ pc.f(nE[3], tot), reliab[3].avg });
    try o.print("── DEPTH TEST: does hierarchical (phrase+concept) context help next-rune? ──\n", .{});
    try o.print("  rune-only committee (E0+E1)        {d:.1}%\n", .{pc.f(nRuneOnly, tot)});
    try o.print("  ►► FULL hierarchical committee     {d:.1}%   ({s})\n", .{ pc.f(nFull, tot), if (nFull > nRuneOnly) "DEPTH HELPS" else "no gain" });

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    const helps = nFull > nRuneOnly;
    try o.print("HIERARCHICAL RUNES = depth via COMPOSITION: bytes→runes→phrases→concepts, each level a feature-of-features,\n", .{});
    try o.print("next-rune predicted from multi-scale context. Measured: full hierarchical committee {d:.1}%% vs rune-only {d:.1}%% — {s}.\n", .{ pc.f(nFull, tot), pc.f(nRuneOnly, tot), if (helps) "abstract phrase/concept context ADDS signal the local n-gram lacks" else "no gain here" });
    try o.print("The phrase/concept experts condition next-rune on WHICH abstract unit we're inside — a learned-by-counting\n", .{});
    try o.print("hierarchy, O(1)/step, no attention, no softmax, no n². This is the depth lever probe-4's naive stacking lacked:\n", .{});
    try o.print("higher levels are GENUINELY different features (composed units), not a re-conditioning on the same context.\n", .{});
    try o.print("Honest: still next-rune top-1 on a tiny substrate; the result is whether the DEPTH SHAPE adds signal ({s}).\n", .{if (helps) "it does" else "it didn't here — needs richer level-coupling"});
}
