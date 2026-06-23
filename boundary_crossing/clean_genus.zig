//! clean_genus.zig — the HARD fix for "what is a dog → common". Extract the real HEAD NOUN of each definition's
//! genus, with no hardcoded part-of-speech and no hardcoded connective list:
//!   • HEAD = last content word of the noun phrase (English heads are NP-final): "domesticated carnivorous MAMMAL".
//!   • CONNECTIVE handling is DISCOVERED via the "followed-by-of" rate: "kind/type/member" are almost always
//!     followed by "of" (high of-rate) so they are partitive connectives — "a kind OF animal" → head = animal;
//!     a real noun like "mammal" has a low of-rate, so "mammal OF the family" keeps mammal as the head.
//!   • SENSE-DOMINANCE: aggregate every definition of a concept across sources and take the MAJORITY head, so the
//!     "Dog (2022 film)" sense can't outvote the animal sense.
//! Sources: Wiktionary (dominant-sense glosses) + Simple/English Wikipedia. WordNet grades only.
//! Build: zig build-exe clean_genus.zig -O ReleaseFast -femit-bin=/tmp/cg && /tmp/cg
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
var A: std.mem.Allocator = undefined;
const PA = std.heap.page_allocator;
const OF_HI = 0.45; // a word with this "followed-by-of" rate is treated as a partitive connective (kind/type/member)

fn lc(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn isArticle(w: []const u8) bool {
    inline for (.{ "a", "an", "the", "any", "one", "some", "this", "that" }) |s| if (std.mem.eql(u8, w, s)) return true;
    return false;
}
// hard NP boundary = function words that end the noun phrase (NOT "of", which continues partitives). Mechanism.
fn isBoundary(w: []const u8) bool {
    inline for (.{ "that", "which", "who", "whom", "whose", "used", "with", "in", "on", "at", "from", "for", "to", "by", "having", "consisting", "especially", "also", "while", "when", "where", "usually", "often", "typically", "commonly", "generally", "and", "or", "but", "found", "located", "made", "known", "born", "based", "designed", "characterized", "belonging", "native", "intended" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}
fn isStopHead(w: []const u8) bool { // never a genus by itself
    inline for (.{ "is", "are", "was", "were", "be", "it", "its", "他们", "they", "he", "she", "you", "we", "i", "his", "her", "their", "name", "term", "word" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}
fn singular(w: []const u8) []const u8 {
    if (w.len > 4 and std.mem.endsWith(u8, w, "ies")) return std.mem.concat(A, u8, &.{ w[0 .. w.len - 3], "y" }) catch w;
    if (w.len > 3 and w[w.len - 1] == 's' and w[w.len - 2] != 's' and w[w.len - 2] != 'u' and w[w.len - 2] != 'i') return w[0 .. w.len - 1];
    return w;
}

// ── of-rate (followed-by-"of") per word ──
var freq: std.StringHashMap(u32) = undefined;
var ofc: std.StringHashMap(u32) = undefined;
fn bump(m: *std.StringHashMap(u32), w: []const u8) void {
    const g = m.getOrPut(w) catch return;
    if (!g.found_existing) {
        g.key_ptr.* = A.dupe(u8, w) catch return;
        g.value_ptr.* = 0;
    }
    g.value_ptr.* += 1;
}
fn ofRateHi(w: []const u8) bool {
    const fc = freq.get(w) orelse return false;
    if (fc < 20) return false;
    const oc = ofc.get(w) orelse 0;
    return @as(f64, @floatFromInt(oc)) / @as(f64, @floatFromInt(fc)) > OF_HI;
}

// ── head-noun genus extraction from a tokenized definition ──
// returns the head noun of "S is/was/are a/an <NP>", or "" if none
fn extractHead(toks: [][]const u8) struct { subj: []const u8, head: []const u8 } {
    // copula
    var k: usize = 0;
    while (k < toks.len and !(std.mem.eql(u8, toks[k], "is") or std.mem.eql(u8, toks[k], "are") or std.mem.eql(u8, toks[k], "was") or std.mem.eql(u8, toks[k], "were"))) : (k += 1) {}
    if (k == 0 or k >= toks.len - 1 or k > 6) return .{ .subj = "", .head = "" };
    // subject = the FULL concept/title (all non-article words before the copula), so "reservoir dogs" stays
    // distinct from "dog" — taking only the last word merged every multi-word title ending in that word.
    var sbuf = std.ArrayList(u8).init(A);
    var nwords: usize = 0;
    var si: usize = 0;
    while (si < k) : (si += 1) if (!isArticle(toks[si]) and toks[si].len >= 1) {
        if (nwords > 0) sbuf.append(' ') catch {};
        sbuf.appendSlice(toks[si]) catch {};
        nwords += 1;
    };
    if (sbuf.items.len < 2) return .{ .subj = "", .head = "" };
    const subj = sbuf.items; // do NOT singularize the subject — the "dogs" (slang=feet) entry must not merge into "dog"
    // walk the predicate NP for the head
    var i = k + 1;
    var head: []const u8 = "";
    while (i < toks.len) : (i += 1) {
        const w = toks[i];
        if (isArticle(w)) continue;
        if (isBoundary(w)) break;
        if (std.mem.eql(u8, w, "of")) continue; // shouldn't normally hit (handled below)
        if (w.len < 3 or isStopHead(w)) continue;
        const next_of = (i + 1 < toks.len and std.mem.eql(u8, toks[i + 1], "of"));
        if (ofRateHi(w) and next_of) {
            i += 1; // partitive connective ("kind of") → skip it and the "of"; head is further
            continue;
        }
        head = w; // real noun candidate (NP-final wins as we advance)
        if (next_of) break; // a low-of-rate noun followed by "of" → the of-phrase modifies it; it's the head
    }
    return .{ .subj = subj, .head = if (head.len > 0) singular(head) else "" };
}

// ── aggregation: concept → primacy-weighted head scores (WSD via sense ORDER: Wiktionary lists the basic
//    sense first, so earlier glosses get more weight — "dog"'s 1st gloss "A mammal" beats its later senses) ──
var heads: std.StringHashMap(*std.StringHashMap(u32)) = undefined;
var glossRank: std.StringHashMap(u32) = undefined; // per-subject: how many glosses seen so far (for primacy)
fn addHead(s: []const u8, h: []const u8) void {
    if (std.mem.eql(u8, s, h)) return;
    const rk = glossRank.getOrPut(s) catch return;
    if (!rk.found_existing) {
        rk.key_ptr.* = A.dupe(u8, s) catch return;
        rk.value_ptr.* = 0;
    }
    const rank = rk.value_ptr.*;
    rk.value_ptr.* += 1;
    const weight: u32 = if (rank < 7) 8 - rank else 1; // 1st gloss=8, 2nd=7, … floor 1
    const g = heads.getOrPut(s) catch return;
    if (!g.found_existing) {
        g.key_ptr.* = rk.key_ptr.*;
        const m = A.create(std.StringHashMap(u32)) catch return;
        m.* = std.StringHashMap(u32).init(A);
        g.value_ptr.* = m;
    }
    const e = g.value_ptr.*.getOrPut(h) catch return;
    if (!e.found_existing) {
        e.key_ptr.* = A.dupe(u8, h) catch return;
        e.value_ptr.* = 0;
    }
    e.value_ptr.* += weight;
}

fn processFile(path: []const u8, count_of: bool) void {
    const f = std.fs.openFileAbsolute(path, .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(PA, 8 << 30) catch return;
    defer PA.free(buf);
    var lines = std.mem.splitScalar(u8, buf, '\n');
    var toks = std.ArrayList([]const u8).init(A);
    var lbuf = std.ArrayList(u8).init(A);
    while (lines.next()) |line| {
        toks.clearRetainingCapacity();
        lbuf.clearRetainingCapacity();
        for (line) |ch| lbuf.append(if (isAlpha(ch)) lc(ch) else ' ') catch {};
        var sp = std.mem.tokenizeScalar(u8, lbuf.items, ' ');
        while (sp.next()) |w| toks.append(w) catch {};
        if (toks.items.len < 3) continue;
        if (count_of) {
            var pi: usize = 0;
            while (pi + 1 < toks.items.len) : (pi += 1) {
                bump(&freq, toks.items[pi]);
                if (std.mem.eql(u8, toks.items[pi + 1], "of")) bump(&ofc, toks.items[pi]);
            }
            bump(&freq, toks.items[toks.items.len - 1]);
        } else {
            const r = extractHead(toks.items);
            if (r.subj.len >= 2 and r.head.len >= 2) addHead(r.subj, r.head);
        }
    }
}

// dominant head per concept → the IS-A graph
var isa: std.StringHashMap([]const u8) = undefined; // concept → dominant genus
var isa2: std.StringHashMap([][]const u8) = undefined; // concept → top genera (for reaches)
var indeg: std.StringHashMap(u32) = undefined; // how many concepts list a word as a candidate genus (category-likeness)
fn freezeGraph() usize {
    isa = std.StringHashMap([]const u8).init(A);
    isa2 = std.StringHashMap([][]const u8).init(A);
    indeg = std.StringHashMap(u32).init(A);
    // pass 1: genus in-degree
    var idg_it = heads.iterator();
    while (idg_it.next()) |e| {
        var hi = e.value_ptr.*.keyIterator();
        while (hi.next()) |h| {
            const g = indeg.getOrPut(h.*) catch continue;
            if (!g.found_existing) g.value_ptr.* = 0;
            g.value_ptr.* += 1;
        }
    }
    // pass 2: per concept, dominant genus = category-like (in-degree) weighted by assertion count.
    // WSD via the graph's own structure: the sense whose genus is a real category wins (mammal ≫ feet).
    var edges: usize = 0;
    var it = heads.iterator();
    while (it.next()) |e| {
        const WC = struct { w: []const u8, score: f64 };
        var list = std.ArrayList(WC).init(A);
        var hi = e.value_ptr.*.iterator();
        while (hi.next()) |he| {
            const idg: f64 = @floatFromInt(@min(indeg.get(he.key_ptr.*) orelse 1, 1000));
            const cnt: f64 = @floatFromInt(he.value_ptr.*);
            list.append(.{ .w = he.key_ptr.*, .score = cnt * 2000.0 + idg }) catch {}; // primacy dominates; in-degree (category-likeness) tiebreaks
        }
        if (list.items.len == 0) continue;
        std.mem.sort(WC, list.items, {}, struct {
            fn lt(_: void, a: WC, b: WC) bool {
                return a.score > b.score;
            }
        }.lt);
        isa.put(e.key_ptr.*, list.items[0].w) catch {};
        const keep = @min(list.items.len, 3);
        const arr = A.alloc([]const u8, keep) catch continue;
        for (0..keep) |j| arr[j] = list.items[j].w;
        isa2.put(e.key_ptr.*, arr) catch {};
        edges += keep;
    }
    return edges;
}
fn reaches(x: []const u8, y: []const u8) bool {
    var stack = std.ArrayList([]const u8).init(A);
    stack.append(x) catch return false;
    var seen = std.StringHashMap(void).init(A);
    var steps: usize = 0;
    while (stack.items.len > 0) {
        const cur = stack.pop() orelse break;
        steps += 1;
        if (steps > 5000) break;
        if (std.mem.eql(u8, cur, y)) return true;
        if (seen.contains(cur)) continue;
        seen.put(cur, {}) catch {};
        if (isa2.get(cur)) |ps| for (ps) |p| stack.append(p) catch {};
    }
    return false;
}
fn chainStr(x: []const u8) []const u8 {
    var out = std.ArrayList(u8).init(A);
    out.appendSlice(x) catch {};
    var cur = x;
    var d: usize = 0;
    var seen = std.StringHashMap(void).init(A);
    while (d < 8) : (d += 1) {
        if (seen.contains(cur)) break;
        seen.put(cur, {}) catch {};
        const h = isa.get(cur) orelse break;
        out.appendSlice(" → ") catch {};
        out.appendSlice(h) catch {};
        cur = h;
    }
    return out.items;
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
            for (0..wname.len) |kk| wclean[kk] = if (wname[kk] == '_') ' ' else lc(wname[kk]);
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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();
    freq = std.StringHashMap(u32).init(A);
    ofc = std.StringHashMap(u32).init(A);
    heads = std.StringHashMap(*std.StringHashMap(u32)).init(A);
    glossRank = std.StringHashMap(u32).init(A);

    const args = try std.process.argsAlloc(A);
    var files = std.ArrayList([]const u8).init(A);
    if (args.len > 1) {
        for (args[1..]) |a| files.append(a) catch {};
    } else {
        files.append(C ++ "wikt_defs.txt") catch {};
        files.append(C ++ "wiki_simple_defs.txt") catch {};
        files.append(C ++ "wiki_en_defs.txt") catch {};
    }
    try o.print("=== CLEAN GENUS — head-noun + discovered connectives + sense-dominance ===\n", .{});
    try o.print("[1] of-rate pass…\n", .{});
    for (files.items) |p| processFile(p, true);
    try o.print("[2] head-noun extraction + aggregation…\n", .{});
    for (files.items) |p| processFile(p, false);
    const e = freezeGraph();
    loadWordNet();
    try o.print("    concepts {d} · edges {d}\n\n", .{ isa.count(), e });

    try o.print("──────── the test that failed before: what is X? ────────\n", .{});
    inline for (.{ "dog", "cat", "church", "english", "knife", "city", "wine", "oak", "rose", "physicist", "computer", "guitar" }) |w| {
        if (isa.get(w)) |h| try o.print("    {s:<10} → {s:<14}  [{s}]\n", .{ w, h, chainStr(w) }) else try o.print("    {s:<10} → (not learned)\n", .{w});
    }

    try o.print("\n──────── IS-A reaches (transitive) ────────\n", .{});
    inline for (.{ .{ "dog", "animal" }, .{ "cat", "animal" }, .{ "oak", "plant" }, .{ "wine", "drink" }, .{ "city", "place" }, .{ "knife", "tool" }, .{ "rose", "plant" } }) |pr| {
        try o.print("    is a {s} a {s}? {s}\n", .{ pr[0], pr[1], if (reaches(pr[0], pr[1])) "YES" else "no" });
    }

    // precision/recall vs WordNet
    var pc: usize = 0;
    var ph: usize = 0;
    var it = isa.iterator();
    while (it.next()) |en| {
        const x = en.key_ptr.*;
        const y = en.value_ptr.*;
        if (!wnHas(x) or !wnHas(y)) continue;
        pc += 1;
        if (wnReaches(x, y)) ph += 1;
    }
    var rc: usize = 0;
    var rh: usize = 0;
    var wit = wn_offs_of.iterator();
    var seenp = std.StringHashMap(void).init(A);
    outer: while (wit.next()) |we| {
        if (rc >= 4000) break;
        const x = we.key_ptr.*;
        if (std.mem.indexOfScalar(u8, x, ' ') != null or !isa.contains(x)) continue;
        for (we.value_ptr.*) |off| if (wn_parents.get(off)) |ps| for (ps) |po| if (wn_words_at.get(po)) |ws| for (ws) |y| {
            if (std.mem.indexOfScalar(u8, y, ' ') != null or std.mem.eql(u8, x, y)) continue;
            const key = std.fmt.allocPrint(A, "{s}|{s}", .{ x, y }) catch continue;
            if (seenp.contains(key)) continue;
            seenp.put(key, {}) catch {};
            rc += 1;
            if (reaches(x, y)) rh += 1;
            if (rc >= 4000) break :outer;
        };
    }
    try o.print("\n──────── precision/recall vs WordNet ────────\n", .{});
    try o.print("  PRECISION (dominant edge) {d}/{d} = {d:.1}%   (prior grounded graph: ~32%)\n", .{ ph, pc, pct(ph, pc) });
    try o.print("  RECALL (reaches)          {d}/{d} = {d:.1}%   (prior: ~4-9%)\n", .{ rh, rc, pct(rh, rc) });
    // dump the clean graph for the oracle
    {
        const cf = std.fs.createFileAbsolute(C ++ "clean_isa.tsv", .{}) catch return;
        defer cf.close();
        var bw = std.io.bufferedWriter(cf.writer());
        var git = isa2.iterator();
        var n: usize = 0;
        while (git.next()) |en| for (en.value_ptr.*) |h| {
            bw.writer().print("{s}\t{s}\n", .{ en.key_ptr.*, h }) catch {};
            n += 1;
        };
        bw.flush() catch {};
        try o.print("\n  [wrote {d} edges → {s}clean_isa.tsv]\n", .{ n, C });
    }
}
