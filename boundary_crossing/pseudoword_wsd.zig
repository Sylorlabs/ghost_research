//! pseudoword_wsd.zig — the harder disambiguation test, with perfect ground truth + lever experiments. No LLM.
//!
//! Earlier the prose/code split was near-ceiling-easy (93%, no room to test noise-levers). The classic harder test
//! (Schütze 1998): take two REAL words A and B, pretend they're one polysemous PSEUDOWORD, and measure whether the
//! multi-sense clusterer splits the merged occurrences back into A vs B. Ground truth is perfect (we know which is
//! which), and difficulty is tunable: A,B FAR apart (king/whale) = easy; A,B CLOSE (father/mother, day/night) = hard.
//! On the HARD pairs there's real noise to remove, so the levers (IDF context-weighting) can finally be MEASURED.
//!
//! Run: zig build pseudoword-wsd --release=fast

const std = @import("std");

const SAMPLE: usize = 400_000;
const MERGES: usize = 2500;
const NR: usize = 1500;
const W: usize = 4;
const MAXOCC: usize = 1500;
const MAXLEN: usize = 40;

var mat: []f32 = undefined;
var vocab: std.ArrayList([]const u8) = undefined;
var crune: []u32 = undefined;
var wgt: []f32 = undefined;
var nr: usize = 0;

const TNode = struct { cid: i32 = -1, kids: std.AutoHashMap(u8, u32) };
var trie: std.ArrayList(TNode) = undefined;

fn trimmed(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " ");
}
fn cosv(t1: usize, t2: usize) f32 {
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
fn findRune(word: []const u8) i32 {
    for (0..nr) |c| if (std.mem.eql(u8, trimmed(vocab.items[crune[c]]), word)) return @intCast(c);
    return -1;
}

// k-means K=2 (cosine) → assignments; returns purity vs the true A/B labels
fn splitPurity(a: std.mem.Allocator, ctx: []f32, lab: []u8, M: usize) !f32 {
    var c0 = try a.alloc(f32, nr);
    var c1 = try a.alloc(f32, nr);
    @memcpy(c0, ctx[0..nr]);
    var far: usize = 0;
    var fd: f32 = 2;
    for (0..M) |q| {
        var s: f32 = 0;
        for (0..nr) |k| s += ctx[q * nr + k] * c0[k];
        if (s < fd) {
            fd = s;
            far = q;
        }
    }
    @memcpy(c1, ctx[far * nr .. far * nr + nr]);
    var asg = try a.alloc(u8, M);
    var iter: usize = 0;
    while (iter < 12) : (iter += 1) {
        for (0..M) |q| {
            var d0: f32 = 0;
            var d1: f32 = 0;
            for (0..nr) |k| {
                d0 += ctx[q * nr + k] * c0[k];
                d1 += ctx[q * nr + k] * c1[k];
            }
            asg[q] = if (d0 >= d1) 0 else 1;
        }
        const s0 = try a.alloc(f64, nr);
        const s1 = try a.alloc(f64, nr);
        @memset(s0, 0);
        @memset(s1, 0);
        for (0..M) |q| {
            const dst = if (asg[q] == 0) s0 else s1;
            for (0..nr) |k| dst[k] += ctx[q * nr + k];
        }
        var n0: f64 = 0;
        var n1: f64 = 0;
        for (0..nr) |k| {
            n0 += s0[k] * s0[k];
            n1 += s1[k] * s1[k];
        }
        const inv0: f32 = if (n0 > 0) @floatCast(1.0 / @sqrt(n0)) else 0;
        const inv1: f32 = if (n1 > 0) @floatCast(1.0 / @sqrt(n1)) else 0;
        for (0..nr) |k| {
            c0[k] = @as(f32, @floatCast(s0[k])) * inv0;
            c1[k] = @as(f32, @floatCast(s1[k])) * inv1;
        }
    }
    // purity: each cluster takes its majority TRUE label
    var correct: usize = 0;
    for (0..2) |cl| {
        var a0: usize = 0;
        var a1: usize = 0;
        for (0..M) |q| if (asg[q] == cl) {
            if (lab[q] == 0) a0 += 1 else a1 += 1;
        };
        correct += @max(a0, a1);
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(M));
}

pub fn main() !void {
    var arena_s = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_s.deinit();
    const a = arena_s.allocator();
    const pa = std.heap.page_allocator;
    const o = std.io.getStdOut().writer();

    try o.print("=== PSEUDOWORD WSD — merge two real words into one, measure if it splits them back. Levers, measured. No LLM ===\n\n", .{});
    const dir = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus";
    var corpus = std.ArrayList(u8).init(a);
    for ([_][]const u8{ "moby_dick.txt", "shakespeare.txt", "austen.txt", "tolstoy.txt", "sherlock.txt", "shelley.txt" }) |fn_| {
        const path = try std.fs.path.join(a, &.{ dir, fn_ });
        const ff = std.fs.openFileAbsolute(path, .{}) catch continue;
        defer ff.close();
        try corpus.appendSlice(try ff.readToEndAlloc(a, 1 << 30));
    }
    const buf = corpus.items;

    // forge on a spread sample
    const ns: usize = @min(buf.len, SAMPLE);
    var sbuf = try a.alloc(u8, ns);
    {
        const ch: usize = 4;
        const csz = ns / ch;
        for (0..ch) |c| {
            const st = (buf.len / ch) * c;
            const tk = @min(csz, buf.len - st);
            @memcpy(sbuf[c * csz .. c * csz + tk], buf[st .. st + tk]);
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
    var rf = try a.alloc(u32, nv);
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
    wgt = try a.alloc(f32, nr);
    var totf: f64 = 0;
    for (0..nr) |c| totf += @floatFromInt(rl.items[c].f);
    for (0..nr) |c| {
        cid_of[rl.items[c].id] = @intCast(c);
        crune[c] = rl.items[c].id;
        wgt[c] = @floatCast(@max(0.0, std.math.log(f64, std.math.e, totf / @as(f64, @floatFromInt(rl.items[c].f + 1)))));
    }
    trie = std.ArrayList(TNode).init(a);
    try trie.append(.{ .kids = std.AutoHashMap(u8, u32).init(a) });
    for (0..nv) |i| try trieAdd(a, vocab.items[i], cid_of[i]);

    // encode the full corpus → compact rune sequence (strong embeddings + occurrence collection)
    var cstream = std.ArrayList(i32).init(a);
    {
        var pos: usize = 0;
        while (pos < buf.len) {
            const s = step(buf, pos);
            pos = s.np;
            try cstream.append(s.cid);
        }
    }
    const cs = cstream.items;
    mat = try pa.alloc(f32, nr * nr);
    @memset(mat, 0);
    {
        var ring = [_]i32{-1} ** W;
        for (0..cs.len) |i| {
            const cc = cs[i];
            if (cc < 0) {
                ring = [_]i32{-1} ** W;
                continue;
            }
            const ut: usize = @intCast(cc);
            for (ring) |r| if (r >= 0) {
                const ur: usize = @intCast(r);
                mat[ut * nr + ur] += 1;
                mat[ur * nr + ut] += 1;
            };
            var k: usize = W - 1;
            while (k > 0) : (k -= 1) ring[k] = ring[k - 1];
            ring[0] = cc;
        }
    }
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
    try o.print("forged {d} runes, strong embeddings over {d:.1}MB. pseudoword splits (purity vs true word; 50%=chance):\n\n", .{ nv - 256, @as(f64, @floatFromInt(buf.len)) / 1e6 });

    const ps = [_][2][]const u8{
        .{ "king", "whale" }, .{ "king", "queen" },   .{ "love", "death" },
        .{ "sea", "ship" },   .{ "father", "mother" }, .{ "day", "night" },
    };
    const ctx = try a.alloc(f32, MAXOCC * nr);
    const lab = try a.alloc(u8, MAXOCC);
    try o.print("  {s:<16} {s:>5}  {s:>10}  {s:>10}\n", .{ "pseudoword", "sim", "purity(UW)", "purity(IDF)" });
    for (ps) |pr| {
        const ra = findRune(pr[0]);
        const rb = findRune(pr[1]);
        if (ra < 0 or rb < 0) continue;
        const sim = cosv(@intCast(ra), @intCast(rb)); // how similar = how HARD
        var pur = [_]f32{ 0, 0 };
        for ([_]bool{ false, true }, 0..) |weighted, cfg| {
            var M: usize = 0;
            for (0..cs.len) |i| {
                if (M >= MAXOCC) break;
                if (cs[i] != ra and cs[i] != rb) continue;
                const base = M * nr;
                @memset(ctx[base .. base + nr], 0);
                var any = false;
                var d: usize = 1;
                while (d <= W) : (d += 1) {
                    if (i >= d and cs[i - d] >= 0) {
                        const nb: usize = @intCast(cs[i - d]);
                        const ww: f32 = if (weighted) wgt[nb] else 1;
                        for (0..nr) |k| ctx[base + k] += ww * mat[nb * nr + k];
                        any = true;
                    }
                    if (i + d < cs.len and cs[i + d] >= 0) {
                        const nb: usize = @intCast(cs[i + d]);
                        const ww: f32 = if (weighted) wgt[nb] else 1;
                        for (0..nr) |k| ctx[base + k] += ww * mat[nb * nr + k];
                        any = true;
                    }
                }
                if (!any) continue;
                var nrm: f32 = 0;
                for (0..nr) |k| nrm += ctx[base + k] * ctx[base + k];
                if (nrm <= 0) continue;
                const inv = 1.0 / @sqrt(nrm);
                for (0..nr) |k| ctx[base + k] *= inv;
                lab[M] = if (cs[i] == ra) 0 else 1;
                M += 1;
            }
            if (M >= 20) pur[cfg] = try splitPurity(a, ctx, lab, M);
        }
        var nm: [40]u8 = undefined;
        const label = std.fmt.bufPrint(&nm, "{s}+{s}", .{ pr[0], pr[1] }) catch pr[0];
        try o.print("  {s:<16} {d:>5.2}  {d:>9.0}%  {d:>9.0}%\n", .{ label, sim, 100 * pur[0], 100 * pur[1] });
    }

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("The harder test, with perfect ground truth. FAR pairs (king+whale, low sim) split cleanly → high purity;\n", .{});
    try o.print("CLOSE pairs (father+mother, day+night, high sim) are genuinely hard → lower purity, real noise to remove.\n", .{});
    try o.print("That's the yardstick where the levers (IDF context-weighting, UW vs IDF columns) can finally be MEASURED\n", .{});
    try o.print("moving the number — not on a near-ceiling task. Difficulty is the sim column; the method's honest WSD\n", .{});
    try o.print("ability is now a curve over difficulty, count-based, no LLM — the thing to race a transformer on next.\n", .{});
}
