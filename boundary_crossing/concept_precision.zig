//! concept_precision.zig — measure what concept_learn.zig never did: PRECISION of the learned IS-A graph,
//! not just recall. For a KNOWER, a wrong edge (king→instrument) is fatal; a missing edge is just an honest
//! abstention. So precision is the metric to drive first.
//!
//! Two experiments in one run, before/after:
//!   (A) BASELINE  — concept_learn's exact extraction (genus + Hearst + possessive, ev≥3).
//!   (B) POS-FILTER — same, but IS-A nodes are restricted to NOUNS using Webster's OWN part-of-speech tags
//!                    ("King, n." vs "King, v. i."). This kills adjective/verb chain garbage and, because we
//!                    only read the noun entry's genus, the homograph pollution too. Still no WordNet, no LLM.
//!
//! WordNet is loaded ONLY to GRADE (precision + recall via full hypernym closure), never to answer.
//! Build: zig build concept-precision   (or: zig build-exe concept_precision.zig -O ReleaseFast && ./concept_precision)
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
var A: std.mem.Allocator = undefined;

fn lo(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn fmt(comptime f: []const u8, a: anytype) []const u8 {
    return std.fmt.allocPrint(A, f, a) catch "?";
}
fn isStop(w: []const u8) bool {
    inline for (.{ "the", "a", "an", "of", "to", "in", "on", "as", "by", "for", "with", "and", "or", "is", "are", "was", "were", "be", "been", "it", "its", "this", "that", "these", "those", "which", "who", "such", "other", "some", "any", "all", "one", "two", "his", "her", "their", "they", "he", "she", "you", "we", "i", "not", "no", "but", "from", "at", "into", "out", "up", "so", "if", "then", "than", "them", "him", "me", "my", "your" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}

const Inner = std.StringHashMap(u32);
var isa_ev: std.StringHashMap(*Inner) = undefined;
var part_ev: std.StringHashMap(*Inner) = undefined;
fn bump(m: *std.StringHashMap(*Inner), a: []const u8, b: []const u8, w: u32) void {
    if (a.len < 3 or b.len < 3 or std.mem.eql(u8, a, b)) return;
    const e = m.getOrPut(a) catch return;
    if (!e.found_existing) {
        const inner = A.create(Inner) catch return;
        inner.* = Inner.init(A);
        e.key_ptr.* = A.dupe(u8, a) catch return;
        e.value_ptr.* = inner;
    }
    const ie = e.value_ptr.*.getOrPut(b) catch return;
    if (!ie.found_existing) {
        ie.key_ptr.* = A.dupe(u8, b) catch return;
        ie.value_ptr.* = 0;
    }
    ie.value_ptr.* += w;
}

// ── Webster ──
var dict_words: std.StringHashMap(void) = undefined;
var noun_words: std.StringHashMap(void) = undefined; // headwords whose entry POS is a noun ("n.")
var g_pos_filter: bool = false;

fn isHeadword(line: []const u8) bool {
    if (line.len < 2 or line.len > 40) return false;
    var letters: usize = 0;
    for (line) |c| {
        if (c >= 'a' and c <= 'z') return false;
        if (c >= 'A' and c <= 'Z') letters += 1 else if (c == ' ' or c == '-' or c == '\'' or c == ';' or c == ',' or c == '.' or (c >= '0' and c <= '9')) {} else return false;
    }
    return letters >= 2;
}
fn isArticle(w: []const u8) bool {
    inline for (.{ "a", "an", "the", "one", "any", "some" }) |t| if (std.mem.eql(u8, w, t)) return true;
    return false;
}
fn isTrigger(w: []const u8) bool {
    inline for (.{ "of", "which", "that", "consisting", "having", "used", "for", "with", "to", "in", "on", "as", "by", "from", "or", "and", "esp", "usually", "made", "formed" }) |t| if (std.mem.eql(u8, w, t)) return true;
    return false;
}
fn headOf(clause: []const u8) []const u8 {
    var arr = std.ArrayList([]const u8).init(A);
    var it = std.mem.tokenizeAny(u8, clause, " ,;:()./");
    while (it.next()) |raw| {
        var b = std.ArrayList(u8).init(A);
        for (raw) |c| if (isAlpha(c)) b.append(lo(c)) catch {};
        if (b.items.len >= 1) arr.append(b.items) catch {};
    }
    const ws = arr.items;
    var idx: usize = 0;
    while (idx < ws.len and isArticle(ws[idx])) idx += 1;
    var head: []const u8 = "";
    var j = idx;
    while (j < ws.len and !isTrigger(ws[j])) : (j += 1) head = ws[j];
    return head;
}
fn extractGloss(body: []const u8) []const u8 {
    var marker: ?usize = null;
    var start: usize = 0;
    if (std.mem.indexOf(u8, body, "Defn:")) |d| {
        marker = d;
        start = d + 5;
    }
    var i: usize = 0;
    while (i + 2 < body.len) : (i += 1) if ((i == 0 or body[i - 1] == '\n') and body[i] == '1' and body[i + 1] == '.' and body[i + 2] == ' ') {
        if (marker == null or i < marker.?) start = i + 2;
        break;
    };
    if (marker == null and start == 0) return "";
    var s = start;
    while (s < body.len and (body[s] == ' ' or body[s] == '\n')) s += 1;
    var out = std.ArrayList(u8).init(A);
    var j = s;
    var nl: usize = 0;
    while (j < body.len) : (j += 1) {
        const c = body[j];
        if (c == '\n') {
            nl += 1;
            if (nl >= 2) break;
            out.append(' ') catch {};
        } else {
            nl = 0;
            out.append(c) catch {};
        }
        if (out.items.len > 300) break;
    }
    var g = std.mem.trim(u8, out.items, " ");
    if (g.len > 0 and g[0] == '(') {
        if (std.mem.indexOfScalar(u8, g, ')')) |p| g = std.mem.trim(u8, g[p + 1 ..], " ");
    }
    if (std.mem.startsWith(u8, g, "1. ")) g = std.mem.trim(u8, g[3..], " ");
    inline for (.{ "\"", " -- ", "Etym", "Syn.", " [" }) |cut| {
        if (std.mem.indexOf(u8, g, cut)) |at| g = std.mem.trim(u8, g[0..at], " ");
    }
    return g;
}
fn extractGenus(gloss: []const u8) []const u8 {
    var clauses = std.mem.tokenizeScalar(u8, gloss, ';');
    const first = clauses.next() orelse return "";
    return headOf(std.mem.trim(u8, first, " ,."));
}
// Part-of-speech of an entry block: the block begins with the inflection line, e.g. "King, n.Etym:..." or
// "Knife, n.; pl. Knives." or "King, v. i. [imp...". We read the token right after the FIRST comma on the
// first line; noun iff it begins "n" (n. / n.;). This is Webster's own tagging — not a hand-built list.
fn entryIsNoun(block: []const u8) bool {
    var line_end: usize = 0;
    while (line_end < block.len and block[line_end] != '\n') line_end += 1;
    const line = block[0..line_end];
    const comma = std.mem.indexOfScalar(u8, line, ',') orelse return false;
    var k = comma + 1;
    while (k < line.len and line[k] == ' ') k += 1;
    // POS token: letters/dots until space or ';'
    var p = k;
    while (p < line.len and line[p] != ' ' and line[p] != ';') p += 1;
    const pos = line[k..p];
    return pos.len >= 1 and (pos[0] == 'n' or pos[0] == 'N') and (pos.len == 1 or pos[1] == '.');
}
fn loadWebster() void {
    const f = std.fs.openFileAbsolute(C ++ "webster1913.txt", .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    var lines = std.mem.splitScalar(u8, buf, '\n');
    var cur: ?[]const u8 = null;
    var bstart: usize = 0;
    var pos: usize = 0;
    var heads = std.ArrayList(struct { w: []const u8, s: usize }).init(A);
    while (lines.next()) |line| {
        pos += line.len + 1;
        const t = std.mem.trim(u8, line, " \r");
        if (isHeadword(t)) {
            if (cur) |h| heads.append(.{ .w = h, .s = bstart }) catch {};
            var hw = t;
            for (hw, 0..) |c, k| if (c == ' ' or c == ';' or c == ',') {
                hw = hw[0..k];
                break;
            };
            const key = A.alloc(u8, hw.len) catch return;
            for (0..hw.len) |k| key[k] = lo(hw[k]);
            cur = key;
            bstart = pos;
            dict_words.put(key, {}) catch {};
        }
    }
    if (cur) |h| heads.append(.{ .w = h, .s = buf.len }) catch {};

    // Pass 1: mark which headwords have a NOUN entry (Webster POS). A homograph counts as a noun if ANY of its
    // entries is tagged "n." — but for genus we only read noun entries (pass 2), so the instrument-sense of
    // "king" (also "n.") still pollutes unless we pick the PRIMARY noun sense. We mitigate in pass 2.
    for (heads.items, 0..) |h, i| {
        const end = if (i + 1 < heads.items.len) heads.items[i + 1].s else buf.len;
        if (entryIsNoun(buf[h.s..@min(end, buf.len)])) noun_words.put(h.w, {}) catch {};
    }

    // Pass 2: genus per NOUN entry. To curb homograph pollution we only take the genus from the FIRST noun
    // entry of each headword (Webster orders the principal sense first for the main entry; the obscure
    // instrument-"king" is a separate earlier stub, so we additionally prefer the LONGEST gloss as principal).
    var best_gloss_len = std.StringHashMap(usize).init(A);
    for (heads.items, 0..) |h, i| {
        const end = if (i + 1 < heads.items.len) heads.items[i + 1].s else buf.len;
        const block = buf[h.s..@min(end, buf.len)];
        const noun_entry = entryIsNoun(block);
        if (g_pos_filter and !noun_entry) continue; // POS filter: skip non-noun entries entirely
        const gloss = extractGloss(block);
        const genus = extractGenus(gloss);
        if (genus.len < 3 or std.mem.eql(u8, genus, h.w)) continue;
        if (std.mem.endsWith(u8, genus, "ed") or std.mem.endsWith(u8, genus, "ing")) continue;
        if (!dict_words.contains(genus)) continue;
        if (g_pos_filter) {
            if (!noun_words.contains(genus)) continue; // genus must be a noun too
            // homograph mitigation: keep only the genus from the LONGEST gloss (principal sense)
            const gl = gloss.len;
            const prev = best_gloss_len.get(h.w) orelse 0;
            if (gl < prev) continue;
            best_gloss_len.put(h.w, gl) catch {};
        }
        bump(&isa_ev, h.w, genus, 5);
    }
}

// ── Hearst + possessive ──
fn mineText(buf: []const u8) void {
    var p1: []const u8 = "";
    var p2: []const u8 = "";
    var lcn: []const u8 = "";
    var pend_hyper: []const u8 = "";
    var pend_n: u32 = 0;
    var and_other = false;
    var i: usize = 0;
    var tok = std.ArrayList(u8).init(A);
    while (i <= buf.len) : (i += 1) {
        const c: u8 = if (i < buf.len) buf[i] else ' ';
        if (isAlpha(c)) {
            tok.append(lo(c)) catch {};
            continue;
        }
        const is_poss = (c == '\'' and i + 1 < buf.len and lo(buf[i + 1]) == 's') or
            (c == 0xE2 and i + 3 < buf.len and buf[i + 1] == 0x80 and buf[i + 2] == 0x99 and lo(buf[i + 3]) == 's');
        const w = tok.items;
        if (w.len > 0) {
            if (and_other and !isStop(w)) {
                bump(&isa_ev, lcn, w, 1);
                and_other = false;
            } else and_other = false;
            if (pend_n > 0 and !isStop(w)) {
                bump(&isa_ev, w, pend_hyper, 1);
                pend_n -= 1;
            }
            if (std.mem.eql(u8, w, "as") and std.mem.eql(u8, p1, "such") and !isStop(p2) and p2.len >= 3) {
                pend_hyper = p2;
                pend_n = 3;
            }
            if (std.mem.eql(u8, w, "other") and (std.mem.eql(u8, p1, "and") or std.mem.eql(u8, p1, "or")) and lcn.len >= 3) {
                and_other = true;
            }
            if ((std.mem.eql(u8, w, "including") or std.mem.eql(u8, w, "especially")) and lcn.len >= 3 and !isStop(lcn)) {
                pend_hyper = lcn;
                pend_n = 3;
            }
            if (is_poss) {
                var j = i + (if (c == '\'') @as(usize, 2) else 4);
                while (j < buf.len and !isAlpha(buf[j])) j += 1;
                var nb = std.ArrayList(u8).init(A);
                while (j < buf.len and isAlpha(buf[j])) : (j += 1) nb.append(lo(buf[j])) catch {};
                if (!isStop(w) and nb.items.len >= 3 and !isStop(nb.items)) bump(&part_ev, w, nb.items, 1);
            }
            p2 = p1;
            p1 = w;
            if (!isStop(w)) lcn = w;
        }
        if (c == '.' or c == ';' or c == ':' or c == '\n' or c == '!' or c == '?') {
            pend_n = 0;
            and_other = false;
            lcn = "";
        }
        tok = std.ArrayList(u8).init(A);
    }
}
fn mineFile(name: []const u8) void {
    const f = std.fs.openFileAbsolute(fmt("{s}{s}", .{ C, name }), .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    mineText(buf);
}

// ── certify + freeze (with optional noun gate on both endpoints) ──
var isa: std.StringHashMap([][]const u8) = undefined;
var parts: std.StringHashMap([][]const u8) = undefined;
const WEv = struct { w: []const u8, ev: u32 };
fn cmpEv(_: void, a: WEv, b: WEv) bool {
    return a.ev > b.ev;
}
fn freeze(ev: *std.StringHashMap(*Inner), out: *std.StringHashMap([][]const u8), min_ev: u32, noun_gate: bool) usize {
    var edges: usize = 0;
    var it = ev.iterator();
    while (it.next()) |e| {
        if (noun_gate and !noun_words.contains(e.key_ptr.*)) continue;
        var list = std.ArrayList(WEv).init(A);
        var iit = e.value_ptr.*.iterator();
        while (iit.next()) |ie| {
            if (ie.value_ptr.* < min_ev) continue;
            if (noun_gate and !noun_words.contains(ie.key_ptr.*)) continue;
            list.append(.{ .w = ie.key_ptr.*, .ev = ie.value_ptr.* }) catch {};
        }
        if (list.items.len == 0) continue;
        std.mem.sort(WEv, list.items, {}, cmpEv);
        var arr = A.alloc([]const u8, list.items.len) catch continue;
        for (list.items, 0..) |x, k| arr[k] = x.w;
        out.put(e.key_ptr.*, arr) catch {};
        edges += arr.len;
    }
    return edges;
}
fn chainStr(x: []const u8) ?[]const u8 {
    var cur = x;
    var out = std.ArrayList(u8).init(A);
    out.appendSlice(x) catch {};
    var depth: usize = 0;
    var seen = std.StringHashMap(void).init(A);
    while (depth < 12) : (depth += 1) {
        if (seen.contains(cur)) break;
        seen.put(cur, {}) catch {};
        const ps = isa.get(cur) orelse break;
        if (ps.len == 0) break;
        cur = ps[0];
        out.appendSlice(" → ") catch {};
        out.appendSlice(cur) catch {};
    }
    return if (out.items.len > x.len) out.items else null;
}
fn reaches(x: []const u8, y: []const u8) bool {
    var stack = std.ArrayList([]const u8).init(A);
    stack.append(x) catch return false;
    var seen = std.StringHashMap(void).init(A);
    var steps: usize = 0;
    while (stack.items.len > 0) {
        const cur = stack.pop() orelse break;
        steps += 1;
        if (steps > 8000) break;
        if (std.mem.eql(u8, cur, y)) return true;
        if (seen.contains(cur)) continue;
        seen.put(cur, {}) catch {};
        if (isa.get(cur)) |ps| for (ps) |p| stack.append(p) catch {};
    }
    return false;
}

// ─────────────────── WordNet — loaded ONLY to grade ───────────────────
var wn_parents: std.AutoHashMap(u32, []u32) = undefined; // synset → all hypernym synsets (@)
var wn_words_at: std.AutoHashMap(u32, [][]const u8) = undefined; // synset → its words
var wn_offs_of: std.StringHashMap([]u32) = undefined; // word → synsets containing it
var wn_loaded = false;
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
        _ = t.next(); // lex filenum
        if (!std.mem.eql(u8, t.next() orelse "", "n")) continue;
        const wc = std.fmt.parseInt(usize, t.next() orelse continue, 16) catch continue;
        var wl = std.ArrayList([]const u8).init(A);
        var wi: usize = 0;
        while (wi < wc) : (wi += 1) {
            const wname = t.next() orelse break;
            _ = t.next(); // lex id
            const wclean = A.alloc(u8, wname.len) catch continue;
            for (0..wname.len) |k| wclean[k] = if (wname[k] == '_') ' ' else lo(wname[k]);
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
            _ = t.next(); // pos
            _ = t.next(); // source/target
            if (std.mem.eql(u8, sym, "@") or std.mem.eql(u8, sym, "@i"))
                pl.append(std.fmt.parseInt(u32, to, 10) catch continue) catch {};
        }
        wn_parents.put(off, pl.items) catch {};
    }
    var owi = off_words.iterator();
    while (owi.next()) |e| wn_words_at.put(e.key_ptr.*, e.value_ptr.*.items) catch {};
    var woi = word_offs.iterator();
    while (woi.next()) |e| wn_offs_of.put(e.key_ptr.*, e.value_ptr.*.items) catch {};
    wn_loaded = true;
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

// ─────────────────── build the graph for a given config ───────────────────
const Stats = struct {
    concepts: usize,
    edges: usize,
    // precision: of our DIRECT edges with both endpoints in WordNet, fraction WordNet's closure confirms
    prec_checked: usize,
    prec_hit: usize,
    // recall: of WordNet direct edges whose child we learned, fraction our graph reaches
    rec_checked: usize,
    rec_hit: usize,
};
fn resetMaps() void {
    isa_ev = std.StringHashMap(*Inner).init(A);
    part_ev = std.StringHashMap(*Inner).init(A);
    dict_words = std.StringHashMap(void).init(A);
    noun_words = std.StringHashMap(void).init(A);
    isa = std.StringHashMap([][]const u8).init(A);
    parts = std.StringHashMap([][]const u8).init(A);
}
fn buildGraph(pos_filter: bool) void {
    g_pos_filter = pos_filter;
    resetMaps();
    loadWebster();
    inline for (.{ "webster1913.txt", "gutenberg_dense.txt", "moby_dick.txt", "shakespeare.txt", "tolstoy.txt", "austen.txt", "sherlock.txt" }) |fnm| mineFile(fnm);
    _ = freeze(&isa_ev, &isa, 3, pos_filter);
    _ = freeze(&part_ev, &parts, 2, false);
}
fn measure(o: anytype, label: []const u8, dump_fail: bool) !Stats {
    var s = Stats{ .concepts = isa.count(), .edges = 0, .prec_checked = 0, .prec_hit = 0, .rec_checked = 0, .rec_hit = 0 };
    // PRECISION: iterate our direct edges
    var fails: usize = 0;
    var it = isa.iterator();
    while (it.next()) |e| {
        const x = e.key_ptr.*;
        for (e.value_ptr.*) |y| {
            s.edges += 1;
            if (!wnHas(x) or !wnHas(y)) continue; // can only grade words WordNet knows
            s.prec_checked += 1;
            if (wnReaches(x, y)) {
                s.prec_hit += 1;
            } else if (dump_fail and fails < 25) {
                try o.print("      ✗ WE SAY: {s} → {s}  (WordNet disagrees)\n", .{ x, y });
                fails += 1;
            }
        }
    }
    // RECALL: sample WordNet direct edges whose child we learned
    var wit = wn_offs_of.iterator();
    var seen_pairs = std.StringHashMap(void).init(A);
    outer: while (wit.next()) |e| {
        if (s.rec_checked >= 4000) break;
        const x = e.key_ptr.*;
        if (std.mem.indexOfScalar(u8, x, ' ') != null) continue;
        if (!isa.contains(x)) continue;
        // each direct WordNet parent word of x
        for (e.value_ptr.*) |off| {
            if (wn_parents.get(off)) |ps| for (ps) |po| {
                if (wn_words_at.get(po)) |ws| for (ws) |y| {
                    if (std.mem.indexOfScalar(u8, y, ' ') != null) continue;
                    if (std.mem.eql(u8, x, y)) continue;
                    const key = fmt("{s}|{s}", .{ x, y });
                    if (seen_pairs.contains(key)) continue;
                    seen_pairs.put(key, {}) catch {};
                    s.rec_checked += 1;
                    if (reaches(x, y)) s.rec_hit += 1;
                    if (s.rec_checked >= 4000) break :outer;
                };
            };
        }
    }
    _ = label;
    return s;
}
fn pct(a: usize, b: usize) f64 {
    return if (b == 0) 0 else 100.0 * @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();

    try o.print("=== CONCEPT PRECISION — does the LEARNED graph actually know, or just guess? ===\n", .{});
    try o.print("(WordNet loaded ONLY to grade precision+recall via full hypernym closure; never to answer.)\n\n", .{});
    loadWordNet();
    if (!wn_loaded) {
        try o.print("WordNet not present — cannot grade. Abort.\n", .{});
        return;
    }
    try o.print("graded against {d} WordNet noun-words.\n\n", .{wn_offs_of.count()});

    const probe = [_][]const u8{ "dog", "king", "knife", "horse", "whale", "oak", "rose", "computer", "lion", "ship", "doctor", "iron" };

    try o.print("──────────── (A) BASELINE: concept_learn.zig extraction ────────────\n", .{});
    buildGraph(false);
    try o.print("  sample chains:\n", .{});
    for (probe) |w| {
        if (chainStr(w)) |ch| try o.print("    {s}\n", .{ch}) else try o.print("    {s}  (not learned)\n", .{w});
    }
    try o.print("  precision failures (our asserted edges WordNet rejects):\n", .{});
    const sa = try measure(o, "baseline", true);

    try o.print("\n──────────── (B) POS-FILTER: noun-only nodes (Webster's own tags) ────────────\n", .{});
    buildGraph(true);
    try o.print("  sample chains:\n", .{});
    for (probe) |w| {
        if (chainStr(w)) |ch| try o.print("    {s}\n", .{ch}) else try o.print("    {s}  (not learned)\n", .{w});
    }
    try o.print("  precision failures (our asserted edges WordNet rejects):\n", .{});
    const sb = try measure(o, "pos", true);

    try o.print("\n════════════════════════ SCORECARD ════════════════════════\n", .{});
    try o.print("  {s:<14} {s:>10} {s:>10} {s:>22} {s:>20}\n", .{ "config", "concepts", "edges", "PRECISION (right/graded)", "recall (got/gold)" });
    try o.print("  {s:<14} {d:>10} {d:>10} {d:>10}/{d:<7} {d:>5.1}% {d:>8}/{d:<6} {d:>4.1}%\n", .{ "baseline", sa.concepts, sa.edges, sa.prec_hit, sa.prec_checked, pct(sa.prec_hit, sa.prec_checked), sa.rec_hit, sa.rec_checked, pct(sa.rec_hit, sa.rec_checked) });
    try o.print("  {s:<14} {d:>10} {d:>10} {d:>10}/{d:<7} {d:>5.1}% {d:>8}/{d:<6} {d:>4.1}%\n", .{ "pos-filter", sb.concepts, sb.edges, sb.prec_hit, sb.prec_checked, pct(sb.prec_hit, sb.prec_checked), sb.rec_hit, sb.rec_checked, pct(sb.rec_hit, sb.rec_checked) });
    try o.print("\n  precision Δ: {d:.1}%% → {d:.1}%%   recall Δ: {d:.1}%% → {d:.1}%%\n", .{ pct(sa.prec_hit, sa.prec_checked), pct(sb.prec_hit, sb.prec_checked), pct(sa.rec_hit, sa.rec_checked), pct(sb.rec_hit, sb.rec_checked) });
}
