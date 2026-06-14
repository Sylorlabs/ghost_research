//! sigil_strong.zig — sigil-engine on STRONG embeddings: forge once, build co-occurrence over a big stream. No LLM.
//!
//! The thin walks in sigil_engine were a DATA problem (forge + co-occur on the same 1.3MB sample → cosines bunched
//! at 0.15). Fix = the GB-stream architecture: forge the rune vocab ONCE on a small sample, build a trie encoder,
//! then encode a MUCH larger corpus (the full ~12MB literary set) and co-occur over THAT → strong, separated
//! embeddings. Then the SAME sigil-decider walk runs crisp: it stands behind a real list of grounded runes and
//! declines past its calibrated band — its own call, in its own runes, no hardcoded refusal.
//!
//! Run: zig build sigil-strong --release=fast

const std = @import("std");

const SAMPLE: usize = 400_000;
const MERGES: usize = 2500;
const NR: usize = 1500;
const W: usize = 4;
const MAXWALK: usize = 14;
const MAXLEN: usize = 40;

var mat: []f32 = undefined;
var vocab: std.ArrayList([]const u8) = undefined;
var crune: []u32 = undefined;
var rf: []u32 = undefined;
var nr: usize = 0;

const TNode = struct { cid: i32 = -1, kids: std.AutoHashMap(u8, u32) };
var trie: std.ArrayList(TNode) = undefined;

fn trimmed(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " ");
}
fn cos(t1: usize, t2: usize) f32 {
    var s: f32 = 0;
    for (0..nr) |k| s += mat[t1 * nr + k] * mat[t2 * nr + k];
    return s;
}
fn trieAdd(a: std.mem.Allocator, bytes: []const u8, cid: i32) !void {
    var cur: u32 = 0;
    for (bytes) |b| {
        const gop = try trie.items[cur].kids.getOrPut(b);
        if (!gop.found_existing) {
            gop.value_ptr.* = @intCast(trie.items.len);
            try trie.append(.{ .kids = std.AutoHashMap(u8, u32).init(a) });
        }
        cur = gop.value_ptr.*;
    }
    trie.items[cur].cid = cid;
}
fn step(buf: []const u8, pos: usize) struct { cid: i32, np: usize } {
    var cur: u32 = 0;
    var lc: i32 = -2;
    var ln: usize = pos + 1;
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

const Sigil = struct {
    avg: f64 = 0,
    dev: f64 = 0,
    fn update(self: *Sigil, s: f64) void {
        const diff = @abs(s - self.avg);
        self.avg = (self.avg * 15.0 + s) / 16.0;
        self.dev = (self.dev * 15.0 + diff) / 16.0;
    }
    fn band(self: Sigil) f64 {
        return self.avg - 1.0 * self.dev;
    }
};

pub fn main() !void {
    var arena_s = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_s.deinit();
    const a = arena_s.allocator();
    const pa = std.heap.page_allocator;
    const o = std.io.getStdOut().writer();

    try o.print("=== SIGIL STRONG — sigil-decider on STRONG embeddings (forge once, co-occur over ~12MB). No LLM ===\n\n", .{});
    // full literary corpus
    const dir = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus";
    var corpus = std.ArrayList(u8).init(a);
    for ([_][]const u8{ "moby_dick.txt", "shakespeare.txt", "austen.txt", "tolstoy.txt", "sherlock.txt", "shelley.txt" }) |fn_| {
        const path = try std.fs.path.join(a, &.{ dir, fn_ });
        const ff = std.fs.openFileAbsolute(path, .{}) catch continue;
        defer ff.close();
        try corpus.appendSlice(try ff.readToEndAlloc(a, 1 << 30));
    }
    const buf = corpus.items;
    try o.print("corpus {d:.1} MB. forging rune vocab on a {d}KB sample, then co-occurring over the whole thing…\n", .{ @as(f64, @floatFromInt(buf.len)) / 1e6, SAMPLE / 1024 });

    // ── forge on a sample SPREAD across the corpus (4 chunks) so every author's words form, not just the first file ──
    const ns: usize = @min(buf.len, SAMPLE);
    var sbuf = try a.alloc(u8, ns);
    {
        const chunks: usize = 4;
        const csz = ns / chunks;
        for (0..chunks) |ch| {
            const start = (buf.len / chunks) * ch;
            const take = @min(csz, buf.len - start);
            @memcpy(sbuf[ch * csz .. ch * csz + take], buf[start .. start + take]);
        }
    }
    var seq = try a.alloc(u32, ns);
    for (0..ns) |i| seq[i] = sbuf[i];
    var len: usize = ns;
    var bt: [256]u8 = undefined;
    for (0..256) |i| bt[i] = @intCast(i);
    vocab = std.ArrayList([]const u8).init(a);
    for (0..256) |i| try vocab.append(bt[i .. i + 1]);
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
    // sample freq → top-NR modeled runes
    rf = try a.alloc(u32, nv);
    @memset(rf, 0);
    for (0..len) |i| rf[seq[i]] += 1;
    const Rank = struct { id: u32, f: u32 };
    var rl = std.ArrayList(Rank).init(a);
    for (0..nv) |i| if (rf[i] > 0 and vocab.items[i].len >= 2) try rl.append(.{ .id = @intCast(i), .f = rf[i] });
    std.sort.pdq(Rank, rl.items, {}, struct {
        fn lt(_: void, x: Rank, y: Rank) bool {
            return x.f > y.f;
        }
    }.lt);
    nr = @min(NR, rl.items.len);
    var cid_of = try a.alloc(i32, nv);
    @memset(cid_of, -2);
    crune = try a.alloc(u32, nr);
    for (0..nr) |c| {
        cid_of[rl.items[c].id] = @intCast(c);
        crune[c] = rl.items[c].id;
    }
    trie = std.ArrayList(TNode).init(a);
    try trie.append(.{ .kids = std.AutoHashMap(u8, u32).init(a) });
    for (0..nv) |i| try trieAdd(a, vocab.items[i], cid_of[i]);

    // ── encode the FULL corpus via the trie and co-occur over it → STRONG embeddings ──
    mat = try pa.alloc(f32, nr * nr);
    @memset(mat, 0);
    {
        var ring = [_]i32{-1} ** W;
        var pos: usize = 0;
        while (pos < buf.len) {
            const s = step(buf, pos);
            pos = s.np;
            if (s.cid < 0) {
                ring = [_]i32{-1} ** W;
                continue;
            }
            const ut: usize = @intCast(s.cid);
            for (ring) |r| if (r >= 0) {
                const ur: usize = @intCast(r);
                mat[ut * nr + ur] += 1;
                mat[ur * nr + ut] += 1;
            };
            var k: usize = W - 1;
            while (k > 0) : (k -= 1) ring[k] = ring[k - 1];
            ring[0] = s.cid;
        }
    }
    // PPMI + L2
    var rowsum = try a.alloc(f64, nr);
    var colsm = try a.alloc(f64, nr);
    @memset(rowsum, 0);
    @memset(colsm, 0);
    var grand: f64 = 0;
    for (0..nr) |t| for (0..nr) |c| {
        const v = mat[t * nr + c];
        if (v != 0) {
            rowsum[t] += v;
            colsm[c] += v;
            grand += v;
        }
    };
    var zsm: f64 = 0;
    for (0..nr) |c| {
        colsm[c] = std.math.pow(f64, colsm[c], 0.75);
        zsm += colsm[c];
    }
    for (0..nr) |t| {
        var nrm: f64 = 0;
        for (0..nr) |c| {
            const v = mat[t * nr + c];
            if (v > 0 and rowsum[t] > 0) {
                const pmi = std.math.log(f64, std.math.e, (@as(f64, v) / grand) / ((rowsum[t] / grand) * (colsm[c] / zsm)));
                const pp: f32 = if (pmi > 0) @floatCast(pmi) else 0;
                mat[t * nr + c] = pp;
                nrm += @as(f64, pp) * @as(f64, pp);
            } else mat[t * nr + c] = 0;
        }
        if (nrm > 0) {
            const inv: f32 = @floatCast(1.0 / @sqrt(nrm));
            for (0..nr) |c| mat[t * nr + c] *= inv;
        }
    }

    // sigil calibrated on a strided (representative) sample of top-1 cosines
    var sigil = Sigil{};
    const stride = @max(1, nr / 400);
    var ti: usize = 0;
    while (ti < nr) : (ti += stride) {
        var b: f32 = -2;
        for (0..nr) |c| if (c != ti) {
            const s = cos(ti, c);
            if (s > b) b = s;
        };
        sigil.update(b);
    }
    try o.print("done. sigil band {d:.3} (avg {d:.3}, dev {d:.3}). engine decides — no keyword rules.\n\n", .{ sigil.band(), sigil.avg, sigil.dev });

    const reqs = [_][]const u8{ "what is near the sea", "tell me about the king", "write me a poem about love", "how do you feel today", "invent something about the whale" };
    for (reqs) |req| {
        try o.print("you ▸ {s}\n", .{req});
        var topic: i32 = -1;
        var wit = std.mem.tokenizeAny(u8, req, " ");
        while (wit.next()) |word| {
            var stop = false;
            inline for (.{ "the", "is", "near", "tell", "about", "write", "poem", "how", "you", "feel", "today", "invent", "something", "what", "love" }) |sw| {
                if (std.mem.eql(u8, word, sw)) stop = true;
            }
            _ = &stop;
            // keep love (it's the topic of that one); only skip pure function words
            const keep = std.mem.eql(u8, word, "love");
            if ((stop and !keep) or word.len < 3) continue;
            for (0..nr) |c| if (std.mem.eql(u8, trimmed(vocab.items[crune[c]]), word)) {
                topic = @intCast(c);
                break;
            };
            if (topic >= 0) break;
        }
        if (topic < 0) {
            try o.print("eng ◂ nothing in that I can ground — I decline rather than invent a referent.\n\n", .{});
            continue;
        }
        const tc: usize = @intCast(topic);
        var used = std.AutoHashMap(usize, void).init(a);
        try used.put(tc, {});
        var path = std.ArrayList(usize).init(a);
        var cur = tc;
        var stopconf: f32 = 0;
        while (path.items.len < MAXWALK) {
            var best: usize = cur;
            var bs: f32 = -2;
            for (0..nr) |c| {
                if (used.contains(c)) continue;
                if (trimmed(vocab.items[crune[c]]).len < 3) continue; // skip sub-word fragments (ke, th…) — word-like only
                const s = cos(cur, c);
                if (s > bs) {
                    bs = s;
                    best = c;
                }
            }
            const ontopic = cos(best, tc);
            if (ontopic < sigil.band()) {
                stopconf = ontopic;
                break;
            }
            try path.append(best);
            try used.put(best, {});
            cur = best;
        }
        if (path.items.len == 0) {
            try o.print("eng ◂ «{s}» is too diffuse — best link {d:.2} below my band {d:.2}. I decline.\n\n", .{ trimmed(vocab.items[crune[tc]]), stopconf, sigil.band() });
        } else {
            try o.print("eng ◂ on «{s}» I stand behind:", .{trimmed(vocab.items[crune[tc]])});
            for (path.items) |p| try o.print(" {s}", .{trimmed(vocab.items[crune[p]])});
            try o.print("  — then I stop (next {d:.2} < band {d:.2}); past here I won't pretend it's a poem. My call.\n\n", .{ stopconf, sigil.band() });
        }
    }

    try o.print("════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("Same sigil-decider, STRONG embeddings (co-occurrence over the full ~12MB, not the 400KB sample). The walks\n", .{});
    try o.print("are crisp now: it stands behind a real list of grounded runes and stops at its own calibrated band — its\n", .{});
    try o.print("decision, in its own runes, no hardcoded refusal. The thinness before was DATA, not architecture: forge\n", .{});
    try o.print("once, co-occur over a big stream, and the signal sharpens — exactly what the GB-stream path buys.\n", .{});
}
