//! verify_world.zig — the EXTERNAL verifier for IS-A: world grounding by EXTENSIONAL USAGE INCLUSION.
//!
//! IS-A is extensional: every dog is an animal. We verify a conjecture B→P not by what any source *states*
//! (definitions — that failed, correlated noise) but by how B and P actually *behave* in observed running text
//! (a trace of the world's usage). Signal: distributional inclusion — B's usage contexts are asymmetrically
//! CONTAINED in P's (B more specific, P more general). It is ONE uniform measure applied to every pair; NO handed
//! patterns, NO POS, NO stop-lists, NO ontology — the structure of IS-A is discovered, not hardcoded. The usage
//! model is built from RUNNING PROSE (literary corpora), decorrelated from the DEFINITIONAL grounding witnesses.
//!
//! Generates sibling-analogy conjectures over the grounded graph, verifies each by usage-inclusion, grades vs
//! WordNet, and compares to the prior (failed) verifiers. Build: zig build-exe verify_world.zig -O ReleaseFast
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
var A: std.mem.Allocator = undefined;
const PA = std.heap.page_allocator;

const W = 3; // usage context window radius
const MINC = 10; // min usage frequency to model a word
const VMAX = 16000; // cap usage vocab
const TOPF = 150; // top-PPMI usage features per word
const INCL_MIN = 0.28; // B is-a P requires ≥ this much of B's usage contained in P's
const ASYM = 1.25; // and B→P inclusion must exceed P→B by this factor (B is the more specific one)
const MIN_SUPPORT = 3;
const MAXKIDS = 120;

// running-prose usage corpus (NOT the definitional witnesses → decorrelated)
const FILES = .{ "gutenberg_dense.txt", "big_corpus.txt", "train_mix.txt", "moby_dick.txt", "shakespeare.txt", "tolstoy.txt", "austen.txt", "sherlock.txt", "ulysses.txt", "shelley.txt" };
const DIRS = .{ "bigcorpus", "biglit" };

var vocab: std.ArrayList([]const u8) = undefined;
var id_of: std.StringHashMap(u32) = undefined;
fn lc(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn fmt(comptime f: []const u8, a: anytype) []const u8 {
    return std.fmt.allocPrint(A, f, a) catch "?";
}

fn countFile(freq: *std.StringHashMap(u32), path: []const u8) void {
    const f = std.fs.openFileAbsolute(path, .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(PA, 1 << 30) catch return;
    defer PA.free(buf);
    var tok = std.ArrayList(u8).init(A);
    defer tok.deinit();
    for (buf) |ch| {
        if (isAlpha(ch)) {
            tok.append(lc(ch)) catch {};
        } else {
            if (tok.items.len >= 2) {
                const e = freq.getOrPut(tok.items) catch unreachable;
                if (!e.found_existing) {
                    e.key_ptr.* = A.dupe(u8, tok.items) catch unreachable;
                    e.value_ptr.* = 0;
                }
                e.value_ptr.* += 1;
            }
            tok.clearRetainingCapacity();
        }
    }
}
var corpus_paths: std.ArrayList([]const u8) = undefined;
fn addDir(sub: []const u8) void {
    var d = std.fs.openDirAbsolute(fmt("{s}{s}", .{ C, sub }), .{ .iterate = true }) catch return;
    defer d.close();
    var it = d.iterate();
    while (it.next() catch null) |ent| {
        if (ent.kind == .file and std.mem.endsWith(u8, ent.name, ".txt"))
            corpus_paths.append(fmt("{s}{s}/{s}", .{ C, sub, ent.name })) catch {};
    }
}
fn gather() void {
    inline for (FILES) |nm| corpus_paths.append(C ++ nm) catch {};
    inline for (DIRS) |sub| addDir(sub);
}
fn countPass() void {
    var freq = std.StringHashMap(u32).init(A);
    for (corpus_paths.items) |p| countFile(&freq, p);
    const WF = struct { w: []const u8, f: u32 };
    var all = std.ArrayList(WF).init(A);
    var it = freq.iterator();
    while (it.next()) |e| if (e.value_ptr.* >= MINC) all.append(.{ .w = e.key_ptr.*, .f = e.value_ptr.* }) catch {};
    std.mem.sort(WF, all.items, {}, struct {
        fn lt(_: void, a: WF, b: WF) bool {
            return a.f > b.f;
        }
    }.lt);
    const n = @min(all.items.len, VMAX);
    for (all.items[0..n]) |x| {
        id_of.put(x.w, @intCast(vocab.items.len)) catch {};
        vocab.append(x.w) catch {};
    }
}

var co: []std.AutoHashMap(u32, u32) = undefined;
var tot: []f64 = undefined;
var Ntot: f64 = 0;
fn coFile(path: []const u8) void {
    const f = std.fs.openFileAbsolute(path, .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(PA, 1 << 30) catch return;
    defer PA.free(buf);
    var ring: [2 * W]u32 = undefined;
    var rn: usize = 0;
    var tok = std.ArrayList(u8).init(A);
    defer tok.deinit();
    var i: usize = 0;
    while (i <= buf.len) : (i += 1) {
        const ch: u8 = if (i < buf.len) buf[i] else ' ';
        if (isAlpha(ch)) {
            tok.append(lc(ch)) catch {};
            continue;
        }
        if (tok.items.len >= 2) {
            if (id_of.get(tok.items)) |a| {
                const back = @min(rn, 2 * W);
                var k: usize = 0;
                while (k < back) : (k += 1) {
                    const b = ring[(rn - 1 - k) % (2 * W)];
                    const ea = co[a].getOrPut(b) catch break;
                    if (!ea.found_existing) ea.value_ptr.* = 0;
                    ea.value_ptr.* += 1;
                    const eb = co[b].getOrPut(a) catch break;
                    if (!eb.found_existing) eb.value_ptr.* = 0;
                    eb.value_ptr.* += 1;
                    tot[a] += 1;
                    tot[b] += 1;
                    Ntot += 2;
                }
                ring[rn % (2 * W)] = a;
                rn += 1;
            }
        } else if (ch == '.' or ch == '\n' or ch == '!' or ch == '?') rn = 0;
        tok.clearRetainingCapacity();
    }
}
fn coPass() void {
    const V = vocab.items.len;
    co = A.alloc(std.AutoHashMap(u32, u32), V) catch unreachable;
    tot = A.alloc(f64, V) catch unreachable;
    for (0..V) |i| {
        co[i] = std.AutoHashMap(u32, u32).init(A);
        tot[i] = 0;
    }
    for (corpus_paths.items) |p| coFile(p);
}

var prof: []std.AutoHashMap(u32, f32) = undefined;
var pmass: []f64 = undefined;
fn buildProfiles() void {
    const V = vocab.items.len;
    prof = A.alloc(std.AutoHashMap(u32, f32), V) catch unreachable;
    pmass = A.alloc(f64, V) catch unreachable;
    const FW = struct { f: u32, w: f32 };
    for (0..V) |a| {
        var list = std.ArrayList(FW).init(A);
        var it = co[a].iterator();
        while (it.next()) |e| {
            const caf = e.value_ptr.*;
            const v = (@as(f64, @floatFromInt(caf)) * Ntot) / (tot[a] * tot[e.key_ptr.*]);
            if (v > 1.0) list.append(.{ .f = e.key_ptr.*, .w = @floatCast(@log(v)) }) catch {};
        }
        std.mem.sort(FW, list.items, {}, struct {
            fn lt(_: void, x: FW, y: FW) bool {
                return x.w > y.w;
            }
        }.lt);
        prof[a] = std.AutoHashMap(u32, f32).init(A);
        pmass[a] = 0;
        const n = @min(list.items.len, TOPF);
        for (list.items[0..n]) |x| {
            prof[a].put(x.f, x.w) catch {};
            pmass[a] += x.w;
        }
    }
}
// directional usage inclusion: how much of B's usage profile is contained in P's
fn incl(b: u32, p: u32) f64 {
    if (pmass[b] <= 0) return 0;
    var num: f64 = 0;
    var it = prof[b].iterator();
    while (it.next()) |e| if (prof[p].contains(e.key_ptr.*)) {
        num += e.value_ptr.*;
    };
    return num / pmass[b];
}
// the world verifier: B is-a P iff B's usage is well-contained in P's AND asymmetric (B more specific)
fn worldVerify(b: u32, p: u32) bool {
    const ibp = incl(b, p);
    if (ibp < INCL_MIN) return false;
    const ipb = incl(p, b);
    return ibp >= ASYM * ipb;
}

// ── grounded graph (conjecture base) — only edges whose endpoints we have OBSERVED in usage ──
var adj: std.AutoHashMap(u32, std.ArrayList(u32)) = undefined;
var direct: std.ArrayList([2]u32) = undefined;
fn hasEdge(x: u32, y: u32) bool {
    if (adj.get(x)) |ns| for (ns.items) |n| if (n == y) return true;
    return false;
}
fn loadGrounded() void {
    adj = std.AutoHashMap(u32, std.ArrayList(u32)).init(A);
    direct = std.ArrayList([2]u32).init(A);
    const f = std.fs.openFileAbsolute(C ++ "grounded_clean.tsv", .{}) catch
        (std.fs.openFileAbsolute(C ++ "grounded_isa.tsv", .{}) catch return);
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |line| {
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const xs = std.mem.trim(u8, line[0..tab], " \r");
        const ys = std.mem.trim(u8, line[tab + 1 ..], " \r");
        const x = id_of.get(xs) orelse continue; // only words observed in usage prose
        const y = id_of.get(ys) orelse continue;
        if (x == y) continue;
        const g = adj.getOrPut(x) catch continue;
        if (!g.found_existing) g.value_ptr.* = std.ArrayList(u32).init(A);
        for (g.value_ptr.*.items) |e| if (e == y) break;
        g.value_ptr.*.append(y) catch {};
        direct.append(.{ x, y }) catch {};
    }
}

// ── WordNet grader ──
var wn_parents: std.AutoHashMap(u32, []u32) = undefined;
var wn_words_at: std.AutoHashMap(u32, [][]const u8) = undefined;
var wn_offs_of: std.StringHashMap([]u32) = undefined;
fn loadWordNet() void {
    const df = std.fs.openFileAbsolute(C ++ "dict/data.noun", .{}) catch return;
    defer df.close();
    const buf = df.readToEndAlloc(A, 1 << 30) catch return;
    wn_parents = std.AutoHashMap(u32, []u32).init(A);
    wn_words_at = std.AutoHashMap(u32, [][]const u8).init(A);
    wn_offs_of = std.StringHashMap([]u32).init(A);
    var off_words = std.AutoHashMap(u32, std.ArrayList([]const u8)).init(A);
    var word_offs = std.StringHashMap(std.ArrayList(u32)).init(A);
    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |line| {
        if (line.len < 10) continue;
        var t = std.mem.tokenizeScalar(u8, line, ' ');
        const off = std.fmt.parseInt(u32, t.next() orelse continue, 10) catch continue;
        _ = t.next();
        if (!std.mem.eql(u8, t.next() orelse "", "n")) continue;
        const wc = std.fmt.parseInt(usize, t.next() orelse continue, 16) catch continue;
        var wl = std.ArrayList([]const u8).init(A);
        var wi: usize = 0;
        while (wi < wc) : (wi += 1) {
            const wname = t.next() orelse break;
            _ = t.next();
            const wclean = A.alloc(u8, wname.len) catch continue;
            for (0..wname.len) |k| wclean[k] = if (wname[k] == '_') ' ' else lc(wname[k]);
            wl.append(wclean) catch {};
            const goe = word_offs.getOrPut(wclean) catch continue;
            if (!goe.found_existing) goe.value_ptr.* = std.ArrayList(u32).init(A);
            goe.value_ptr.*.append(off) catch {};
        }
        off_words.put(off, wl) catch {};
        const pc = std.fmt.parseInt(usize, t.next() orelse "0", 10) catch 0;
        var pl = std.ArrayList(u32).init(A);
        var p: usize = 0;
        while (p < pc) : (p += 1) {
            const sym = t.next() orelse break;
            const to = t.next() orelse break;
            _ = t.next();
            _ = t.next();
            if (std.mem.eql(u8, sym, "@") or std.mem.eql(u8, sym, "@i"))
                pl.append(std.fmt.parseInt(u32, to, 10) catch continue) catch {};
        }
        wn_parents.put(off, pl.items) catch {};
    }
    var owi = off_words.iterator();
    while (owi.next()) |e| wn_words_at.put(e.key_ptr.*, e.value_ptr.*.items) catch {};
    var woi = word_offs.iterator();
    while (woi.next()) |e| wn_offs_of.put(e.key_ptr.*, e.value_ptr.*.items) catch {};
}
fn wnHas(w: []const u8) bool {
    return wn_offs_of.contains(w);
}
fn wnReaches(x: []const u8, y: []const u8) bool {
    const starts = wn_offs_of.get(x) orelse return false;
    var stack = std.ArrayList(u32).init(A);
    for (starts) |s| stack.append(s) catch {};
    var seen = std.AutoHashMap(u32, void).init(A);
    var steps: usize = 0;
    while (stack.items.len > 0) {
        const cur = stack.pop() orelse break;
        steps += 1;
        if (steps > 20000) break;
        if (seen.contains(cur)) continue;
        seen.put(cur, {}) catch {};
        if (wn_words_at.get(cur)) |ws| for (ws) |w| if (std.mem.eql(u8, w, y)) return true;
        if (wn_parents.get(cur)) |ps| for (ps) |p| stack.append(p) catch {};
    }
    return false;
}
fn pct(a: usize, b: usize) f64 {
    return if (b == 0) 0 else 100.0 * @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b));
}
fn precEdges(edges: []const [2]u32) [2]usize {
    var c: usize = 0;
    var h: usize = 0;
    for (edges) |e| {
        if (!wnHas(vocab.items[e[0]]) or !wnHas(vocab.items[e[1]])) continue;
        c += 1;
        if (wnReaches(vocab.items[e[0]], vocab.items[e[1]])) h += 1;
    }
    return .{ h, c };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();
    vocab = std.ArrayList([]const u8).init(A);
    id_of = std.StringHashMap(u32).init(A);
    corpus_paths = std.ArrayList([]const u8).init(A);

    try o.print("=== VERIFY_WORLD — external IS-A verifier by extensional USAGE inclusion (no hardcoded structure) ===\n", .{});
    gather();
    try o.print("[1] building usage model from {d} running-prose files (decorrelated from the definitional witnesses)…\n", .{corpus_paths.items.len});
    countPass();
    coPass();
    buildProfiles();
    try o.print("    usage vocab {d}\n[2] loading grounded base (only words OBSERVED in usage)…\n", .{vocab.items.len});
    loadGrounded();
    loadWordNet();
    try o.print("    grounded edges over observed words: {d}\n[3] conjecture by analogy, verify by world usage…\n", .{direct.items.len});

    // children index
    var childrenOf = std.AutoHashMap(u32, std.ArrayList(u32)).init(A);
    for (direct.items) |e| {
        const g = childrenOf.getOrPut(e[1]) catch continue;
        if (!g.found_existing) g.value_ptr.* = std.ArrayList(u32).init(A);
        g.value_ptr.*.append(e[0]) catch {};
    }
    // sibling-analogy conjectures (same as conjecture.zig), dedup
    var seenC = std.AutoHashMap(u64, void).init(A);
    var conj = std.ArrayList([2]u32).init(A);
    var pool = std.AutoHashMap(u32, u32).init(A);
    var hit = childrenOf.iterator();
    while (hit.next()) |he| {
        const H = he.key_ptr.*;
        const kids = he.value_ptr.*.items;
        if (kids.len < 2 or kids.len > MAXKIDS) continue;
        pool.clearRetainingCapacity();
        for (kids) |a| if (adj.get(a)) |ps| for (ps.items) |p| {
            if (p == H) continue;
            const g = pool.getOrPut(p) catch continue;
            if (!g.found_existing) g.value_ptr.* = 0;
            g.value_ptr.* += 1;
        };
        for (kids) |b| {
            var pit = pool.iterator();
            while (pit.next()) |pe| {
                if (pe.value_ptr.* < MIN_SUPPORT) continue;
                const P = pe.key_ptr.*;
                if (P == b or P == H or hasEdge(b, P)) continue;
                const key = @as(u64, b) * 100000 + @as(u64, P);
                const g = seenC.getOrPut(key) catch continue;
                if (g.found_existing) continue;
                conj.append(.{ b, P }) catch {};
            }
        }
    }

    // RANK by usage-inclusion asymmetry (does the world signal discriminate at all?), don't hard-threshold
    const Scored = struct { e: [2]u32, s: f64 };
    var scored = std.ArrayList(Scored).init(A);
    for (conj.items) |e| scored.append(.{ .e = e, .s = incl(e[0], e[1]) - incl(e[1], e[0]) }) catch {};
    std.mem.sort(Scored, scored.items, {}, struct {
        fn lt(_: void, a: Scored, b: Scored) bool {
            return a.s > b.s;
        }
    }.lt);
    const pAll = precEdges(conj.items);
    try o.print("\n════════════════ WORLD-USAGE VERIFIER (does it discriminate?) ════════════════\n", .{});
    try o.print("  conjectured (raw)                {d:>6} edges · {d:.1}%\n", .{ conj.items.len, pct(pAll[0], pAll[1]) });
    for ([_]usize{ 500, 1000, 2000, 5000 }) |K| {
        const k = @min(K, scored.items.len);
        if (k == 0) continue;
        var es = A.alloc([2]u32, k) catch continue;
        for (0..k) |i| es[i] = scored.items[i].e;
        const p = precEdges(es);
        try o.print("  top-{d:<5} by world score      · {d:>4}/{d:<6} = {d:.1}%\n", .{ k, p[0], p[1], pct(p[0], p[1]) });
    }
    // bottom for contrast
    if (scored.items.len >= 1000) {
        const es = A.alloc([2]u32, 1000) catch unreachable;
        for (0..1000) |i| es[i] = scored.items[scored.items.len - 1 - i].e;
        const p = precEdges(es);
        try o.print("  bottom-1000 by world score   · {d:>4}/{d:<6} = {d:.1}%\n", .{ p[0], p[1], pct(p[0], p[1]) });
    }
    try o.print("\n  reference (prior verifiers): correlated text 5.1% · graph-coherence 4.4% · raw ~4%\n", .{});
    try o.print("\n  [decisive calib] usage incl(hyponym→hypernym) / incl(hypernym→hyponym) on REAL IS-A pairs:\n", .{});
    try o.print("  (if usage grounds IS-A, the FIRST number should be clearly higher — hyponym contained in hypernym)\n", .{});
    inline for (.{ .{ "dog", "animal" }, .{ "cat", "animal" }, .{ "oak", "tree" }, .{ "rose", "flower" }, .{ "knife", "tool" }, .{ "ship", "vessel" }, .{ "king", "ruler" }, .{ "gold", "metal" }, .{ "wine", "drink" }, .{ "doctor", "person" } }) |pr| {
        const a = id_of.get(pr[0]);
        const b = id_of.get(pr[1]);
        if (a != null and b != null and pmass[a.?] > 0 and pmass[b.?] > 0) {
            try o.print("    {s:<8} → {s:<8}:  {d:.3} / {d:.3}\n", .{ pr[0], pr[1], incl(a.?, b.?), incl(b.?, a.?) });
        } else try o.print("    {s:<8} → {s:<8}:  (one not in usage vocab)\n", .{ pr[0], pr[1] });
    }
}
