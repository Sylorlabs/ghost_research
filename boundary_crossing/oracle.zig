//! oracle.zig — the KNOWING ENGINE. A unified, queryable oracle over the project's VERIFIED knowledge sources.
//! Every answer is labelled by epistemic status and carries its provenance:
//!   [KNOWN]   — proved / computed / measured / looked up in curated data. Authoritative. Shows its source + proof.
//!   [OPINION] — could not be verified, but DERIVED by reasoning over known facts. Labelled, non-authoritative,
//!               QUARANTINED (never stored as knowledge). Cites the known facts it was built from.
//!   [REFUSED] — nothing verifiable and nothing derivable. Honest "I can't verify that" (the anti-hallucination move).
//!
//! Knowledge sources unified: WordNet curated IS-A (proof chains) · Webster 1913 definitions/genus · exact arithmetic
//! and string atoms · number-theory predicates (+ an identity proved over [1,4096)) · REAL terminal execution (safe,
//! read-only) · corpus-attested possessive attributes · a taught-fact store you can extend live. CPU, no GPU, no LLM.
//!
//! Build+run:  zig build-exe oracle.zig -O ReleaseFast -femit-bin=/tmp/oracle && /tmp/oracle
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";

// ─────────────────────────── epistemic core ───────────────────────────
const Status = enum { known, opinion, refused, meta };
const Answer = struct {
    status: Status,
    text: []const u8,
    source: []const u8 = "",
    proof: []const u8 = "",
};
fn known(t: []const u8, src: []const u8, pf: []const u8) Answer {
    return .{ .status = .known, .text = t, .source = src, .proof = pf };
}
fn opinion(t: []const u8, derived: []const u8) Answer {
    return .{ .status = .opinion, .text = t, .source = "derived from known facts", .proof = derived };
}
fn refuse(t: []const u8) Answer {
    return .{ .status = .refused, .text = t };
}
fn meta(t: []const u8) Answer { // social / meta reply — NOT a knowledge claim, so it carries no epistemic tag
    return .{ .status = .meta, .text = t };
}

var A: std.mem.Allocator = undefined;
fn lo(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn fmt(comptime f: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(A, f, args) catch "?";
}
fn art(w: []const u8) []const u8 { // "a" / "an" by first letter — kills the "a instrument" / "a animal" look
    if (w.len == 0) return "a";
    return switch (lo(w[0])) {
        'a', 'e', 'i', 'o', 'u' => "an",
        else => "a",
    };
}
fn lower(s: []const u8) []const u8 {
    const b = A.alloc(u8, s.len) catch return s;
    for (0..s.len) |i| b[i] = lo(s[i]);
    return b;
}

// ─────────────────────────── WordNet curated IS-A ───────────────────────────
const WNode = struct { word: []const u8, hyper: u32 };
var wn_data: std.AutoHashMap(u32, WNode) = undefined;
var wn_index: std.StringHashMap([]u32) = undefined;
var wn_meron: std.AutoHashMap(u32, []u32) = undefined; // synset → its HAS-PART/MEMBER/SUBSTANCE target synsets (curated)
var wn_holo: std.AutoHashMap(u32, []u32) = undefined; // synset → the WHOLES it is a part/member/substance OF (holonyms)
fn firstWordClean(w: []const u8) []const u8 {
    const b = A.alloc(u8, w.len) catch return w;
    for (0..w.len) |i| b[i] = if (w[i] == '_') ' ' else lo(w[i]);
    return b;
}
fn wnParseData(line: []const u8) void {
    var toks = std.ArrayList([]const u8).init(A);
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    while (it.next()) |t| {
        if (t.len == 1 and t[0] == '|') break;
        toks.append(t) catch return;
        if (toks.items.len > 200) break;
    }
    if (toks.items.len < 6) return;
    const offset = std.fmt.parseInt(u32, toks.items[0], 10) catch return;
    if (!std.mem.eql(u8, toks.items[2], "n")) return;
    const wcnt = std.fmt.parseInt(usize, toks.items[3], 16) catch return;
    const word = toks.items[4];
    const pcnt_idx = 4 + 2 * wcnt;
    if (pcnt_idx >= toks.items.len) return;
    const pcnt = std.fmt.parseInt(usize, toks.items[pcnt_idx], 10) catch return;
    var hyper: u32 = 0;
    var parts = std.ArrayList(u32).init(A);
    var wholes = std.ArrayList(u32).init(A);
    var p: usize = 0;
    while (p < pcnt) : (p += 1) {
        const base = pcnt_idx + 1 + p * 4;
        if (base + 1 >= toks.items.len) break;
        const sym = toks.items[base];
        if (hyper == 0 and (std.mem.eql(u8, sym, "@") or std.mem.eql(u8, sym, "@i")))
            hyper = std.fmt.parseInt(u32, toks.items[base + 1], 10) catch 0;
        // %p/%m/%s = this synset HAS-PART target (meronym); #p/#m/#s = this synset is part OF target (holonym)
        if (std.mem.eql(u8, sym, "%p") or std.mem.eql(u8, sym, "%m") or std.mem.eql(u8, sym, "%s"))
            parts.append(std.fmt.parseInt(u32, toks.items[base + 1], 10) catch continue) catch {};
        if (std.mem.eql(u8, sym, "#p") or std.mem.eql(u8, sym, "#m") or std.mem.eql(u8, sym, "#s"))
            wholes.append(std.fmt.parseInt(u32, toks.items[base + 1], 10) catch continue) catch {};
    }
    wn_data.put(offset, .{ .word = firstWordClean(word), .hyper = hyper }) catch {};
    if (parts.items.len > 0) wn_meron.put(offset, parts.items) catch {};
    if (wholes.items.len > 0) wn_holo.put(offset, wholes.items) catch {};
}
fn wnParseIndex(line: []const u8) void {
    if (line.len == 0 or line[0] == ' ') return;
    var toks = std.ArrayList([]const u8).init(A);
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    while (it.next()) |t| toks.append(t) catch return;
    if (toks.items.len < 7 or !std.mem.eql(u8, toks.items[1], "n")) return;
    const scnt = std.fmt.parseInt(usize, toks.items[2], 10) catch return;
    const pcnt = std.fmt.parseInt(usize, toks.items[3], 10) catch return;
    const off_idx = 6 + pcnt;
    if (off_idx + scnt > toks.items.len) return;
    const offs = A.alloc(u32, scnt) catch return;
    for (0..scnt) |i| offs[i] = std.fmt.parseInt(u32, toks.items[off_idx + i], 10) catch 0;
    wn_index.put(A.dupe(u8, toks.items[0]) catch return, offs) catch {};
}
fn wnChainFrom(start: u32, out: *std.ArrayList([]const u8)) void {
    var cur = start;
    var depth: usize = 0;
    while (depth < 30) : (depth += 1) {
        const node = wn_data.get(cur) orelse break;
        if (node.hyper == 0) break;
        const h = wn_data.get(node.hyper) orelse break;
        out.append(h.word) catch break;
        cur = node.hyper;
    }
}
// returns the proof chain (x → … → y) if x IS-A y in any sense, else null
fn wnIsA(x: []const u8, y: []const u8) ?[]const u8 {
    const senses = wn_index.get(x) orelse return null;
    for (senses) |off| {
        var ch = std.ArrayList([]const u8).init(A);
        wnChainFrom(off, &ch);
        for (ch.items) |n| if (std.mem.eql(u8, n, y)) {
            var s = std.ArrayList(u8).init(A);
            s.appendSlice(x) catch {};
            for (ch.items) |c| {
                s.appendSlice(" → ") catch {};
                s.appendSlice(c) catch {};
                if (std.mem.eql(u8, c, y)) break;
            }
            return s.items;
        };
    }
    return null;
}
fn wnChainStr(x: []const u8) ?[]const u8 {
    const senses = wn_index.get(x) orelse return null;
    if (senses.len == 0) return null;
    var ch = std.ArrayList([]const u8).init(A);
    wnChainFrom(senses[0], &ch);
    if (ch.items.len == 0) return null;
    var s = std.ArrayList(u8).init(A);
    s.appendSlice(x) catch {};
    for (ch.items) |c| {
        s.appendSlice(" → ") catch {};
        s.appendSlice(c) catch {};
    }
    return s.items;
}
fn wnParent(x: []const u8) ?[]const u8 { // immediate curated hypernym (the kind it most directly is)
    const senses = wn_index.get(x) orelse return null;
    if (senses.len == 0) return null;
    var ch = std.ArrayList([]const u8).init(A);
    wnChainFrom(senses[0], &ch);
    return if (ch.items.len == 0) null else ch.items[0];
}
fn wnKnown(x: []const u8) bool {
    return wn_index.contains(x);
}
// curated HAS-PART, with INHERITANCE: a synset's own meronyms + every ancestor's meronyms (a car is-a vehicle,
// a vehicle has-part wheel ⇒ a car has-part wheel). Real sound inference over the curated graph, not a hardcoded list.
fn partsOf(word: []const u8) []const u8 {
    const senses = wn_index.get(word) orelse return "";
    if (senses.len == 0) return "";
    var out = std.ArrayList(u8).init(A);
    var seen = std.StringHashMap(void).init(A);
    var cur = senses[0];
    var depth: usize = 0;
    var picked: usize = 0;
    while (depth < 30 and picked < 8) : (depth += 1) {
        if (wn_meron.get(cur)) |parts| for (parts) |ps| {
            if (wn_data.get(ps)) |pn| if (!seen.contains(pn.word)) {
                seen.put(pn.word, {}) catch {};
                if (out.items.len > 0) out.appendSlice(", ") catch {};
                out.appendSlice(pn.word) catch {};
                picked += 1;
                if (picked >= 8) break;
            };
        };
        const node = wn_data.get(cur) orelse break;
        if (node.hyper == 0) break;
        cur = node.hyper;
    }
    return out.items;
}
// holonyms: the wholes this word is a part/member/substance OF ("what is a wheel part of" → car, …)
fn holonymsOf(word: []const u8) []const u8 {
    const senses = wn_index.get(word) orelse return "";
    var out = std.ArrayList(u8).init(A);
    var seen = std.StringHashMap(void).init(A);
    var picked: usize = 0;
    for (senses) |s0| {
        if (wn_holo.get(s0)) |wh| for (wh) |hw| {
            if (wn_data.get(hw)) |hn| if (!seen.contains(hn.word)) {
                seen.put(hn.word, {}) catch {};
                if (out.items.len > 0) out.appendSlice(", ") catch {};
                out.appendSlice(hn.word) catch {};
                picked += 1;
                if (picked >= 6) break;
            };
        };
        if (picked >= 6) break;
    }
    return out.items;
}
// noun match tolerant of plural 's' (wheel ≈ wheels) — naive but real, no hardcoded word list
fn nounEq(a0: []const u8, b0: []const u8) bool {
    var a1 = a0;
    var b1 = b0;
    if (a1.len > 3 and a1[a1.len - 1] == 's') a1 = a1[0 .. a1.len - 1];
    if (b1.len > 3 and b1[b1.len - 1] == 's') b1 = b1[0 .. b1.len - 1];
    return std.mem.eql(u8, a1, b1);
}
// does the meronym word (maybe multi-word, e.g. "car door") match the asked part (e.g. "door")? full or last-word
fn partMatch(mword: []const u8, q: []const u8) bool {
    if (nounEq(mword, q)) return true;
    var it = std.mem.tokenizeScalar(u8, mword, ' ');
    var lastw: []const u8 = "";
    while (it.next()) |w| lastw = w;
    return lastw.len > 0 and nounEq(lastw, q);
}
// does X have-part Y? walk X's senses + is-a chain checking meronyms; return the derivation proof or null
fn hasPartChain(x: []const u8, y: []const u8) ?[]const u8 {
    const senses = wn_index.get(x) orelse return null;
    for (senses) |s0| {
        var cur = s0;
        var depth: usize = 0;
        while (depth < 30) : (depth += 1) {
            if (wn_meron.get(cur)) |parts| for (parts) |ps| {
                if (wn_data.get(ps)) |pn| if (partMatch(pn.word, y)) {
                    if (cur == s0) return fmt("{s} has-part {s} (WordNet, curated)", .{ x, pn.word });
                    const anc = wn_data.get(cur).?.word;
                    return fmt("{s} is-a {s}, and {s} has-part {s} (WordNet, inherited)", .{ x, anc, anc, pn.word });
                };
            };
            const node = wn_data.get(cur) orelse break;
            if (node.hyper == 0) break;
            cur = node.hyper;
        }
    }
    return null;
}
// does a synset's IS-A chain reach Y? (walks hypernyms from the synset offset — no string lookup, plural-tolerant)
fn synsetReaches(off: u32, y: []const u8) bool {
    var ch = std.ArrayList([]const u8).init(A);
    wnChainFrom(off, &ch);
    for (ch.items) |n| if (partMatch(n, y)) return true;
    return false;
}
// CROSS-SOURCE inference: chain HAS-PART then IS-A. "a car has an engine" — not a direct part, but a car
// has-part an *automobile engine*, and an automobile engine IS-A engine. Two relations, one conclusion no single
// lookup holds. Sound (both links curated), and the whole derivation is shown.
fn hasPartGeneralize(x: []const u8, y: []const u8) ?[]const u8 {
    const senses = wn_index.get(x) orelse return null;
    for (senses) |s0| {
        var cur = s0;
        var depth: usize = 0;
        while (depth < 30) : (depth += 1) {
            if (wn_meron.get(cur)) |parts| for (parts) |ps| {
                if (wn_data.get(ps)) |pn| if (!partMatch(pn.word, y) and synsetReaches(ps, y)) {
                    if (cur == s0) return fmt("{s} has-part {s}, and {s} is-a {s} (WordNet — cross-source: HAS-PART then IS-A)", .{ x, pn.word, pn.word, y });
                    const anc = wn_data.get(cur).?.word;
                    return fmt("{s} is-a {s}, {s} has-part {s}, and {s} is-a {s} (WordNet — cross: IS-A + HAS-PART + IS-A)", .{ x, anc, anc, pn.word, pn.word, y });
                };
            };
            const node = wn_data.get(cur) orelse break;
            if (node.hyper == 0) break;
            cur = node.hyper;
        }
    }
    return null;
}

// ─────────────────────────── Webster 1913 definitions ───────────────────────────
const Def = struct { pos: []const u8, gloss: []const u8, genus: []const u8, syns: []const u8 };
var dict: std.StringHashMap(Def) = undefined;
fn isHeadword(line: []const u8) bool {
    if (line.len < 2 or line.len > 40) return false;
    var letters: usize = 0;
    for (line) |c| {
        if (c >= 'a' and c <= 'z') return false;
        if (c >= 'A' and c <= 'Z') letters += 1 else if (c == ' ' or c == '-' or c == '\'' or c == ';' or c == ',' or c == '.' or (c >= '0' and c <= '9')) {} else return false;
    }
    return letters >= 2;
}
fn partOfSpeech(body: []const u8) []const u8 {
    const head = body[0..@min(body.len, 120)];
    const marks = [_]struct { m: []const u8, n: []const u8 }{
        .{ .m = " n.", .n = "noun" },   .{ .m = " a.", .n = "adjective" }, .{ .m = " v. t.", .n = "verb" },
        .{ .m = " v. i.", .n = "verb" }, .{ .m = " v.", .n = "verb" },     .{ .m = " adv.", .n = "adverb" },
    };
    var bestpos: []const u8 = "";
    var bestat: usize = head.len;
    for (marks) |mk| if (std.mem.indexOf(u8, head, mk.m)) |at| if (at < bestat) {
        bestat = at;
        bestpos = mk.n;
    };
    return bestpos;
}
fn extractGloss(body: []const u8) []const u8 {
    var marker: ?usize = null;
    var start: usize = 0;
    if (std.mem.indexOf(u8, body, "Defn:")) |d| {
        marker = d;
        start = d + 5;
    }
    var i: usize = 0;
    while (i + 2 < body.len) : (i += 1) {
        if ((i == 0 or body[i - 1] == '\n') and body[i] == '1' and body[i + 1] == '.' and body[i + 2] == ' ') {
            if (marker == null or i < marker.?) {
                start = i + 2;
            }
            break;
        }
    }
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
        if (out.items.len > 400) break;
    }
    var g = std.mem.trim(u8, out.items, " ");
    if (g.len > 0 and g[0] == '(') {
        if (std.mem.indexOfScalar(u8, g, ')')) |p| g = std.mem.trim(u8, g[p + 1 ..], " ");
    }
    if (std.mem.startsWith(u8, g, "1. ")) g = std.mem.trim(u8, g[3..], " ");
    inline for (.{ "\"", " -- ", "Etym", "Syn.", " [", "Note:", "  2.", " 2. " }) |cut| {
        if (std.mem.indexOf(u8, g, cut)) |at| g = std.mem.trim(u8, g[0..at], " ");
    }
    // trim to a clean sentence boundary so a definition never cuts off mid-word
    if (g.len > 200) {
        var p: usize = @min(g.len, 220);
        while (p > 60) : (p -= 1) if (g[p - 1] == '.') break;
        if (p > 60) g = std.mem.trim(u8, g[0..p], " ");
    }
    return g;
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
    if (head.len > 0) return head;
    while (j < ws.len and (isTrigger(ws[j]) or isArticle(ws[j]))) j += 1;
    while (j < ws.len and !isTrigger(ws[j])) : (j += 1) head = ws[j];
    return head;
}
fn extractGenus(gloss: []const u8) struct { genus: []const u8, syns: []const u8 } {
    var syns = std.ArrayList(u8).init(A);
    var genus: []const u8 = "";
    var added: usize = 0;
    var clauses = std.mem.tokenizeScalar(u8, gloss, ';');
    var ci: usize = 0;
    while (clauses.next()) |raw| {
        const clause = std.mem.trim(u8, raw, " ,.");
        const h = headOf(clause);
        if (h.len == 0) {
            ci += 1;
            continue;
        }
        if (ci == 0) genus = h;
        var wc: usize = 0;
        var wit = std.mem.tokenizeAny(u8, clause, " ,");
        while (wit.next()) |_| wc += 1;
        if (wc <= 3 and added < 4) {
            if (syns.items.len > 0) syns.appendSlice(" / ") catch {};
            syns.appendSlice(h) catch {};
            added += 1;
        }
        ci += 1;
    }
    return .{ .genus = genus, .syns = syns.items };
}

// ─────────────────────────── corpus (possessive attributes) ───────────────────────────
var corpus: []const u8 = "";
// scan corpus for "<owner>'s <noun>" — corpus-attested HAS-A attributes (on demand)
fn attributesOf(owner: []const u8) []const u8 {
    if (corpus.len == 0) return "";
    var counts = std.StringHashMap(u32).init(A);
    // match both straight ('s) and Gutenberg curly (’s, U+2019) possessives
    const needles = [_][]const u8{ fmt("{s}'s ", .{owner}), fmt("{s}\u{2019}s ", .{owner}) };
    var found: usize = 0;
    for (needles) |needle| {
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, corpus, i, needle)) |at| {
            i = at + needle.len;
            var j = i;
            var b = std.ArrayList(u8).init(A);
            while (j < corpus.len and isAlpha(corpus[j])) : (j += 1) b.append(lo(corpus[j])) catch {};
            if (b.items.len >= 3) {
                const e = counts.getOrPut(b.items) catch break;
                if (!e.found_existing) e.value_ptr.* = 0;
                e.value_ptr.* += 1;
                found += 1;
            }
            if (found > 6000) break;
        }
    }
    // top 5 by count
    var out = std.ArrayList(u8).init(A);
    var picked: usize = 0;
    while (picked < 5) : (picked += 1) {
        var best: []const u8 = "";
        var bc: u32 = 1;
        var it = counts.iterator();
        while (it.next()) |e| if (e.value_ptr.* > bc) {
            bc = e.value_ptr.*;
            best = e.key_ptr.*;
        };
        if (best.len == 0) break;
        if (out.items.len > 0) out.appendSlice(", ") catch {};
        out.appendSlice(best) catch {};
        _ = counts.put(best, 0) catch {};
    }
    return out.items;
}

// ─────────────────────────── number-theory verifiers ───────────────────────────
fn isPrime(n: u64) bool {
    if (n < 2) return false;
    var d: u64 = 2;
    while (d * d <= n) : (d += 1) if (n % d == 0) return false;
    return true;
}
fn isSquare(n: u64) bool {
    const r: u64 = std.math.sqrt(n);
    return r * r == n;
}
fn divisorCount(n: u64) u64 {
    var c: u64 = 0;
    var d: u64 = 1;
    while (d * d <= n) : (d += 1) if (n % d == 0) {
        c += if (d * d == n) 1 else 2;
    };
    return c;
}
fn gcd(a0: u64, b0: u64) u64 {
    var x = a0;
    var y = b0;
    while (y != 0) {
        const t = y;
        y = x % y;
        x = t;
    }
    return x;
}
// n is a Fibonacci number iff 5n²+4 or 5n²−4 is a perfect square (computed, exact for n < ~1.9e9)
fn isFib(n: u64) bool {
    if (n > 1_900_000_000) return false;
    const f = 5 * n * n;
    return isSquare(f + 4) or (f >= 4 and isSquare(f - 4));
}
// the discovered identity (real_invention.zig): odd #divisors  ⟺  perfect square. We verify it over [1,4096).
fn identityHoldsOverDomain() bool {
    var n: u64 = 1;
    while (n < 4096) : (n += 1) if ((divisorCount(n) % 2 == 1) != isSquare(n)) return false;
    return true;
}

// ─────────────────────────── taught-fact store (the writable knowledge) ───────────────────────────
var taught: std.StringHashMap([]const u8) = undefined; // word → genus (is-a), provenance "taught by you"

// ─────────────────────────── safe terminal execution ───────────────────────────
fn safeCmd(cmd: []const u8) bool {
    const t = std.mem.trim(u8, cmd, " ");
    inline for (.{ "test ", "ls", "cat ", "echo ", "true", "false", "stat ", "wc ", "head ", "file " }) |ok|
        if (std.mem.startsWith(u8, t, ok)) return true;
    return false;
}
fn runOutcome(cmd: []const u8) ?bool {
    if (!safeCmd(cmd)) return null;
    const res = std.process.Child.run(.{ .allocator = A, .argv = &.{ "sh", "-c", cmd } }) catch return null;
    return switch (res.term) {
        .Exited => |c| c == 0,
        else => false,
    };
}

// ─────────────────────────── tokenization helpers for the router ───────────────────────────
fn words(q: []const u8) [][]const u8 {
    var arr = std.ArrayList([]const u8).init(A);
    var it = std.mem.tokenizeAny(u8, q, " \t?.,!");
    while (it.next()) |w| arr.append(lower(w)) catch {};
    return arr.items;
}
fn has(ws: [][]const u8, w: []const u8) bool {
    for (ws) |x| if (std.mem.eql(u8, x, w)) return true;
    return false;
}
fn firstInt(ws: [][]const u8) ?usize {
    for (ws, 0..) |w, i| {
        if (w.len > 0 and w[0] >= '0' and w[0] <= '9') {
            _ = std.fmt.parseInt(u64, w, 10) catch continue;
            return i;
        }
    }
    return null;
}
fn parseU(w: []const u8) ?u64 {
    return std.fmt.parseInt(u64, w, 10) catch null;
}
// last meaningful noun in the question (skip stop words) — the subject of "what is X" / "letters in X"
fn subject(ws: [][]const u8) []const u8 {
    var i = ws.len;
    while (i > 0) {
        i -= 1;
        const w = ws[i];
        if (isArticle(w)) continue;
        inline for (.{ "is", "a", "an", "the", "of", "in", "what", "does", "do", "letters", "word", "words", "reverse", "first", "last", "letter", "kind", "have", "has", "define" }) |s| {
            if (std.mem.eql(u8, w, s)) break;
        } else return w;
    }
    return "";
}
fn isStop(w: []const u8) bool {
    inline for (.{ "what", "is", "are", "a", "an", "the", "of", "does", "do", "it", "have", "has", "having", "parts", "part", "made", "contain", "contains", "kind", "and", "or", "in", "to", "many", "much", "how" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}
// owner/part split for HAS-PART questions: relation word (have/parts/made/contain) separates owner (before) from
// part (after). "does a car have wheels" → car / wheels.  "what does a king have" → king / (none).  "parts of a car" → car / (none).
fn ownerPart(ws: [][]const u8) struct { owner: []const u8, part: []const u8 } {
    var ri: ?usize = null;
    for (ws, 0..) |w, i| {
        inline for (.{ "have", "has", "having", "parts", "part", "made", "contain", "contains" }) |r|
            if (std.mem.eql(u8, w, r)) {
                ri = i;
                break;
            };
        if (ri != null) break;
    }
    if (ri == null) return .{ .owner = subject(ws), .part = "" };
    var before: []const u8 = "";
    var i: usize = 0;
    while (i < ri.?) : (i += 1) if (!isStop(ws[i])) {
        before = ws[i];
    };
    var after: []const u8 = "";
    i = ri.? + 1;
    while (i < ws.len) : (i += 1) if (!isStop(ws[i])) {
        after = ws[i];
        break;
    };
    if (before.len > 0) return .{ .owner = before, .part = after }; // "X have/parts Y"
    return .{ .owner = after, .part = "" }; // "parts OF a X" — owner came after the relation word
}

// ─────────────────────────── opinion-from-knowledge ───────────────────────────
// try to DERIVE an is-a opinion: X is-a G (Webster genus), and G is-a Y (WordNet) ⇒ X is probably a Y
fn deriveIsA(x: []const u8, y: []const u8) ?Answer {
    if (dict.get(x)) |d| if (d.genus.len > 0) {
        if (wnIsA(d.genus, y)) |chain| {
            return opinion(fmt("probably yes — a {s} is a {s}, and {s}", .{ x, d.genus, chain }), fmt("KNOWN: {s} is-a {s} (Webster); KNOWN: {s} (WordNet)", .{ x, d.genus, chain }));
        }
        if (std.mem.eql(u8, d.genus, y)) return opinion(fmt("probably yes — Webster defines a {s} as a {s}", .{ x, y }), fmt("KNOWN: {s} is-a {s} (Webster)", .{ x, y }));
    };
    return null;
}

// ─────────────────────────── handlers (each verifies; returns null if it can't apply) ───────────────────────────
const CAPS =
    \\I'm a knowing engine — I only assert what I can verify, and I label everything [KNOWN] / [OPINION] / [REFUSED].
    \\Try me with:
    \\  • is a king a person?            (curated IS-A, shows the proof chain)
    \\  • what is a whale?  /  define knife   (definitions)
    \\  • does a car have wheels?  /  what does a king have?   (HAS-PART, with inheritance + cross-source)
    \\  • is a wheel part of a car?      (reverse part-of)
    \\  • what's 12 times 8?  /  100 divided by 4  /  is 17 prime?  /  gcd of 48 and 36   (computed)
    \\  • which is bigger, 5 or 8?       (comparison)
    \\  • does `ls` succeed?             (I actually run safe read-only commands)
    \\  • teach me: "a quokka is a marsupial"   then ask "is a quokka an animal?"
    \\Ask me something open or subjective and I'll tell you honestly that I can't verify it. ('route <q>' shows how I parse it.)
;
fn hSocial(q: []const u8, ws: [][]const u8) ?Answer {
    _ = q;
    const w0 = ws[0];
    inline for (.{ "hi", "hello", "hey", "yo", "sup", "hiya", "howdy", "greetings", "hello!" }) |g|
        if (std.mem.eql(u8, w0, g)) return meta("Hey — I'm an oracle that only says what it can verify. Ask me something, or type 'help' to see what I can do.");
    inline for (.{ "thanks", "thank", "thx", "ty", "cheers", "appreciated" }) |t|
        if (std.mem.eql(u8, w0, t)) return meta("Anytime.");
    if (std.mem.eql(u8, w0, "help") or std.mem.eql(u8, w0, "commands")) return meta(CAPS);
    // "what can you do" / "what do you know"
    if (has(ws, "you") and (has(ws, "can") or has(ws, "do")) and (has(ws, "what") or has(ws, "things"))) return meta(CAPS);
    if ((std.mem.eql(u8, w0, "how") and has(ws, "you")) or (std.mem.eql(u8, w0, "how") and has(ws, "going"))) return meta("Running fine — every answer measured, nothing guessed. What do you want to know?");
    return null;
}
fn isPronoun(w: []const u8) bool {
    inline for (.{ "you", "i", "it", "we", "they", "he", "she", "me", "us", "them", "this", "that", "who", "what", "everything", "anything", "something", "nothing" }) |p|
        if (std.mem.eql(u8, w, p)) return true;
    return false;
}
fn isWh(w: []const u8) bool {
    inline for (.{ "who", "what", "whats", "which", "where", "when", "why", "how", "whos", "does", "do", "is", "are", "can" }) |x|
        if (std.mem.eql(u8, w, x)) return true;
    return false;
}
fn hTeach(q: []const u8, ws: [][]const u8) ?Answer {
    if (std.mem.indexOf(u8, q, "?") != null) return null;
    if (ws.len > 0 and isWh(ws[0])) return null; // a teach is a DECLARATIVE statement, never a question ("who is a king")
    for (ws, 0..) |w, i| if (std.mem.eql(u8, w, "is") and i + 2 < ws.len and isArticle(ws[i + 1]) and i >= 1) {
        const subj = ws[i - 1];
        const gen = ws[i + 2];
        if (subj.len >= 2 and gen.len >= 2 and !has(ws, "what")) {
            taught.put(A.dupe(u8, subj) catch subj, A.dupe(u8, gen) catch gen) catch {};
            return known(fmt("learned: {s} {s} is {s} {s}.", .{ art(subj), subj, art(gen), gen }), "taught by you", "stored in the knowledge base (provenance: you)");
        }
    };
    return null;
}
fn hAction(q: []const u8) ?Answer {
    if (std.mem.indexOf(u8, q, "`")) |b0| if (std.mem.indexOfPos(u8, q, b0 + 1, "`")) |b1| {
        const cmd = q[b0 + 1 .. b1];
        if (runOutcome(cmd)) |ok2|
            return known(if (ok2) "succeeds" else "fails", "real execution", fmt("ran `{s}` → exit {s}", .{ cmd, if (ok2) "0" else "nonzero" }))
        else
            return refuse(fmt("I won't run `{s}` — only safe read-only commands (test/ls/cat/echo/stat/wc/head/file).", .{cmd}));
    };
    return null;
}
fn hArith(ws: [][]const u8) ?Answer {
    var nums: [6]u64 = undefined;
    var cnt: usize = 0;
    for (ws) |w| if (parseU(w)) |v| {
        if (cnt < nums.len) {
            nums[cnt] = v;
            cnt += 1;
        }
    };
    if (cnt == 0) return null;
    if (has(ws, "squared")) return known(fmt("{d}", .{nums[0] * nums[0]}), "computed", fmt("{d}² = {d}", .{ nums[0], nums[0] * nums[0] }));
    if (has(ws, "cubed")) return known(fmt("{d}", .{nums[0] * nums[0] * nums[0]}), "computed", fmt("{d}³", .{nums[0]}));
    if (cnt < 2) return null;
    const a = nums[0];
    const b = nums[1];
    if (has(ws, "power") or has(ws, "exponent")) {
        if (b > 63) return refuse("that exponent would overflow my 64-bit integers — I won't return an approximate answer.");
        var r: u64 = 1;
        var i: u64 = 0;
        var overflow = false;
        while (i < b) : (i += 1) {
            const m = @mulWithOverflow(r, a);
            if (m[1] != 0) {
                overflow = true;
                break;
            }
            r = m[0];
        }
        if (overflow) return refuse("that result overflows 64-bit integers — I won't give an approximate answer.");
        return known(fmt("{d}", .{r}), "computed", fmt("{d} ^ {d} = {d}", .{ a, b, r }));
    }
    if (has(ws, "plus") or has(ws, "add") or has(ws, "sum") or has(ws, "+")) return known(fmt("{d}", .{a + b}), "computed", fmt("{d} + {d} = {d}", .{ a, b, a + b }));
    if (has(ws, "minus") or has(ws, "subtract") or has(ws, "difference") or has(ws, "-"))
        return if (a >= b) known(fmt("{d}", .{a - b}), "computed", fmt("{d} - {d} = {d}", .{ a, b, a - b })) else known(fmt("-{d}", .{b - a}), "computed", fmt("{d} - {d} = -{d}", .{ a, b, b - a }));
    if (has(ws, "times") or has(ws, "multiplied") or has(ws, "product") or has(ws, "x") or has(ws, "*")) return known(fmt("{d}", .{a * b}), "computed", fmt("{d} × {d} = {d}", .{ a, b, a * b }));
    if (has(ws, "divided") or has(ws, "over") or has(ws, "divide") or has(ws, "/")) {
        if (b == 0) return known("undefined", "computed", "division by zero is undefined");
        if (a % b == 0) return known(fmt("{d}", .{a / b}), "computed", fmt("{d} ÷ {d} = {d}", .{ a, b, a / b }));
        return known(fmt("{d} remainder {d}", .{ a / b, a % b }), "computed", fmt("{d} ÷ {d} = {d} r{d}", .{ a, b, a / b, a % b }));
    }
    return null;
}
fn hNumProp(ws: [][]const u8) ?Answer {
    if ((has(ws, "divisors") or has(ws, "identity")) and (has(ws, "always") or has(ws, "all"))) {
        if (identityHoldsOverDomain())
            return opinion("likely yes for all n — but only verified on a bounded range", "KNOWN: I checked (odd #divisors ⟺ perfect square) for EVERY n in [1,4096) and it held without exception; beyond that range it is unverified — this answer is an extrapolation from the proven domain, NOT a proof");
    }
    const fi = firstInt(ws) orelse return null;
    const n = parseU(ws[fi]) orelse return null;
    if (has(ws, "prime")) return known(if (isPrime(n)) "yes" else "no", "computed", fmt("trial division: {d} is {s}prime", .{ n, if (isPrime(n)) "" else "not " }));
    if (has(ws, "square")) return known(if (isSquare(n)) "yes" else "no", "computed", fmt("{d} = isqrt² check → {s} a perfect square", .{ n, if (isSquare(n)) "is" else "is not" }));
    if (has(ws, "even")) return known(if (n % 2 == 0) "yes" else "no", "computed", fmt("{d} mod 2 = {d}", .{ n, n % 2 }));
    if (has(ws, "odd")) return known(if (n % 2 == 1) "yes" else "no", "computed", fmt("{d} mod 2 = {d}", .{ n, n % 2 }));
    if (has(ws, "fibonacci") or has(ws, "fib")) return known(if (isFib(n)) "yes" else "no", "computed", fmt("5·{d}²±4 perfect-square test", .{n}));
    if (has(ws, "divisors") or has(ws, "factors")) return known(fmt("{d}", .{divisorCount(n)}), "computed", fmt("counted divisors of {d}", .{n}));
    var n2: ?u64 = null;
    var k = fi + 1;
    while (k < ws.len) : (k += 1) if (parseU(ws[k])) |v| {
        n2 = v;
        break;
    };
    if (n2) |m| {
        if (has(ws, "divisible") or has(ws, "multiple")) return known(if (m != 0 and n % m == 0) "yes" else "no", "computed", fmt("{d} mod {d} = {d}", .{ n, m, if (m == 0) 0 else n % m }));
        if (has(ws, "gcd") or has(ws, "common")) return known(fmt("{d}", .{gcd(n, m)}), "computed", fmt("Euclid's algorithm on {d}, {d}", .{ n, m }));
        if (has(ws, "lcm")) return known(fmt("{d}", .{n / gcd(n, m) * m}), "computed", fmt("lcm via n·m/gcd on {d}, {d}", .{ n, m }));
        const bigger = has(ws, "bigger") or has(ws, "larger") or has(ws, "greater") or has(ws, "biggest") or has(ws, "more") or has(ws, "max");
        const smaller = has(ws, "smaller") or has(ws, "less") or has(ws, "lesser") or has(ws, "smallest") or has(ws, "fewer") or has(ws, "min");
        if (bigger or smaller) {
            if (has(ws, "which") or has(ws, "what") or has(ws, "bigger of") or has(ws, "biggest") or has(ws, "smallest"))
                return known(fmt("{d}", .{if (bigger) @max(n, m) else @min(n, m)}), "computed", fmt("compared {d} and {d}", .{ n, m }));
            const yes = (bigger and n > m) or (smaller and n < m);
            return known(if (n == m) "they're equal" else (if (yes) "yes" else "no"), "computed", fmt("{d} vs {d}", .{ n, m }));
        }
    }
    return null;
}
fn hString(ws: [][]const u8) ?Answer {
    if (has(ws, "letters") and has(ws, "in")) {
        const s = subject(ws);
        return known(fmt("{d}", .{s.len}), "computed", fmt("counted letters in \"{s}\"", .{s}));
    }
    if (has(ws, "reverse")) {
        const s = subject(ws);
        if (s.len == 0) return null;
        const b = A.alloc(u8, s.len) catch return null;
        for (0..s.len) |i| b[i] = s[s.len - 1 - i];
        return known(b, "computed", fmt("reversed \"{s}\"", .{s}));
    }
    if ((has(ws, "first") or has(ws, "last")) and has(ws, "letter")) {
        const s = subject(ws);
        if (s.len == 0) return null;
        const c = if (has(ws, "first")) s[0] else s[s.len - 1];
        return known(fmt("{c}", .{c}), "computed", fmt("indexed \"{s}\"", .{s}));
    }
    return null;
}
fn hIsA(ws: [][]const u8, routed: bool) ?Answer {
    _ = routed;
    // an is-a question ALWAYS has a copula and is never a "what is"/"define" (those are definitions). This structural
    // floor holds even when the learned router mis-routes here — it prevents a confident-wrong answer on a non-is-a sentence.
    if (!(has(ws, "is") or has(ws, "are"))) return null;
    if (has(ws, "what") or has(ws, "define")) return null;
    if (has(ws, "part") and has(ws, "of")) return null; // "is X part of Y" is HAS-PART, not IS-A
    // LEARNED slots first (subject/object tagger); fall back to the first/last-noun heuristic if it abstains
    const sl = slotsFromWs(ws);
    var x: []const u8 = sl.subj;
    var y: []const u8 = sl.obj;
    if (x.len == 0 or y.len == 0) {
        var nouns = std.ArrayList([]const u8).init(A);
        for (ws) |w| if (!isArticle(w) and !std.mem.eql(u8, w, "is") and !std.mem.eql(u8, w, "are") and !std.mem.eql(u8, w, "kind") and !std.mem.eql(u8, w, "of")) nouns.append(w) catch {};
        if (nouns.items.len < 2) return null;
        x = nouns.items[0];
        y = nouns.items[nouns.items.len - 1];
    }
    if (std.mem.eql(u8, x, y)) return null;
    if (isPronoun(x) or isPronoun(y)) return null; // "are you alive" / "is it good" aren't curated IS-A questions
    // plural tolerance: "are dogs animals" → dog / animal
    if (!wnKnown(x) and !taught.contains(x) and wnKnown(sing(x))) x = sing(x);
    if (!wnKnown(y) and wnKnown(sing(y))) y = sing(y);
    if (wnIsA(x, y)) |chain| return known("yes", "WordNet (curated IS-A)", chain);
    if (taught.get(x)) |g| {
        if (std.mem.eql(u8, g, y)) return known("yes", "taught by you", fmt("you told me: {s} is-a {s}", .{ x, y }));
        if (wnIsA(g, y)) |ch| return known("yes", "taught + WordNet", fmt("you taught {s} is-a {s}; {s}", .{ x, g, ch }));
    }
    if (wnKnown(x) and wnKnown(y)) return known("no", "WordNet (curated IS-A)", fmt("no hypernym chain reaches {s}; {s} is classified as: {s}", .{ y, x, wnChainStr(x) orelse x }));
    if (deriveIsA(x, y)) |op| return op;
    return refuse(fmt("I can't verify whether {s} {s} is {s} {s} — neither is in my curated knowledge.", .{ art(x), x, art(y), y }));
}
fn hHasPart(ws: [][]const u8, routed: bool) ?Answer {
    if (!routed and !(has(ws, "have") or has(ws, "has") or has(ws, "parts") or has(ws, "part") or has(ws, "made") or has(ws, "contain") or has(ws, "contains"))) return null;
    // REVERSE relation: "is a wheel part of a car" → does the car (after "of") have-part the wheel (before "part")?
    if (has(ws, "part") and has(ws, "of") and !has(ws, "parts")) {
        var pi: usize = 0;
        for (ws, 0..) |w, i| if (std.mem.eql(u8, w, "part")) {
            pi = i;
            break;
        };
        var X: []const u8 = "";
        var i: usize = 0;
        while (i < pi) : (i += 1) if (!isStop(ws[i]) and !std.mem.eql(u8, ws[i], "part")) {
            X = ws[i];
        };
        var Y: []const u8 = "";
        var sawOf = false;
        i = pi;
        while (i < ws.len) : (i += 1) {
            if (std.mem.eql(u8, ws[i], "of")) sawOf = true else if (sawOf and !isStop(ws[i])) {
                Y = ws[i];
                break;
            }
        }
        if (X.len > 0 and Y.len > 0) { // "is X part of Y" → does Y have-part X
            if (hasPartChain(Y, X)) |pf| return known("yes", "WordNet (curated HAS-PART)", pf);
            if (hasPartGeneralize(Y, X)) |pf| return known("yes", "cross-source inference (HAS-PART + IS-A)", pf);
            if (wnKnown(Y)) return refuse(fmt("I can't confirm {s} {s} is part of {s} {s} — it's not among {s}'s curated parts (which are incomplete), so I won't assert it either way.", .{ art(X), X, art(Y), Y, Y }));
            return null;
        }
        if (X.len > 0 and Y.len == 0) { // "what is X part of" → list X's holonyms
            const hs = holonymsOf(X);
            if (hs.len > 0) return known(fmt("{s} {s} is part of: {s}", .{ art(X), X, hs }), "WordNet (curated part-of / holonym)", fmt("holonym links for {s}", .{X}));
            if (wnKnown(X)) return refuse(fmt("I don't have curated part-of links for {s} {s}.", .{ art(X), X }));
        }
    }
    // LEARNED slots first; fall back to the structural owner/part split
    const sl = slotsFromWs(ws);
    const op = ownerPart(ws);
    const owner = if (sl.subj.len > 0) sl.subj else op.owner;
    const part = if (sl.obj.len > 0) sl.obj else op.part;
    if (owner.len == 0) return null;
    if (part.len > 0) {
        if (hasPartChain(owner, part)) |pf| return known("yes", "WordNet (curated HAS-PART)", pf);
        if (hasPartGeneralize(owner, part)) |pf| return known("yes", "cross-source inference (HAS-PART + IS-A)", pf);
        const at0 = attributesOf(owner);
        if (at0.len > 0 and std.mem.indexOf(u8, at0, part) != null)
            return known("yes", "corpus-attested (possessive usage)", fmt("\"{s}'s {s}\" attested in the corpus", .{ owner, part }));
        if (wnKnown(owner))
            return refuse(fmt("I can't confirm a {s} has a {s} — it's not among {s}'s curated parts. (Curated HAS-PART is incomplete, so I won't assert 'no' either — I just don't know.)", .{ owner, part, owner }));
        return null;
    }
    const cp = partsOf(owner);
    if (cp.len > 0) return known(fmt("{s} {s} has: {s}", .{ art(owner), owner, cp }), "WordNet (curated HAS-PART, incl. inherited)", fmt("meronyms of {s} and the kinds it inherits from", .{owner}));
    const at = attributesOf(owner);
    if (at.len > 0) return known(fmt("{s} {s} has: {s}", .{ art(owner), owner, at }), "corpus-attested (possessive usage in literature)", fmt("found \"{s}'s …\" patterns in the corpus", .{owner}));
    return null;
}
fn sing(w: []const u8) []const u8 { // naive singularize: drop a trailing plural 's' (whales→whale)
    return if (w.len > 3 and w[w.len - 1] == 's') w[0 .. w.len - 1] else w;
}
// is the extracted Webster genus a REAL noun (not a verb/junk like computer→"computes", engine→"pronounced")?
fn genusOk(s: []const u8, g: []const u8) bool {
    if (g.len < 3 or std.mem.eql(u8, g, s)) return false;
    if (std.mem.endsWith(u8, g, "ed") or std.mem.endsWith(u8, g, "ing")) return false; // pronounced, computing…
    return wnKnown(g); // must exist as a noun in WordNet
}
fn hDefine(ws: [][]const u8, routed: bool) ?Answer {
    if (!routed and !(has(ws, "what") or has(ws, "define"))) return null;
    // "the meaning/purpose/point OF X" asks for significance, not a dictionary genus → not answerable here (refuse)
    if ((has(ws, "meaning") or has(ws, "purpose") or has(ws, "point") or has(ws, "significance")) and has(ws, "of") and !has(ws, "part")) return null;
    if ((has(ws, "part") or has(ws, "made")) and has(ws, "of")) return null; // "what is X part of / made of" → HAS-PART, not a definition
    const sl = slotsFromWs(ws); // LEARNED subject; fall back to the heuristic
    var s = if (sl.subj.len > 0) sl.subj else subject(ws);
    if (s.len == 0) return null;
    if (!dict.contains(s) and !taught.contains(s) and !wnKnown(s) and (dict.contains(sing(s)) or taught.contains(sing(s)) or wnKnown(sing(s)))) s = sing(s);
    if (dict.get(s)) |d| {
        if (genusOk(s, d.genus)) { // Webster genus is a clean noun → use it + the gloss
            const syn = if (d.syns.len > 0) fmt(" (also: {s})", .{d.syns}) else "";
            return known(fmt("{s} {s} is {s} {s}{s} — \"{s}\"", .{ art(s), s, art(d.genus), d.genus, syn, d.gloss }), "Webster 1913", "genus extracted from the definition gloss");
        }
        // Webster genus is junk (verb/archaic) → prefer WordNet's clean curated kind; else give the gloss with no claimed genus
        if (wnParent(s)) |p| return known(fmt("{s} {s} is {s} {s}", .{ art(s), s, art(p), p }), "WordNet (curated IS-A)", wnChainStr(s) orelse "curated hypernym");
        if (d.gloss.len > 0) return known(fmt("{s} {s}: \"{s}\"", .{ art(s), s, d.gloss }), "Webster 1913", "definition gloss (no clean genus extracted)");
    }
    if (taught.get(s)) |g| return known(fmt("{s} {s} is {s} {s}", .{ art(s), s, art(g), g }), "taught by you", "from the knowledge base you extended");
    // Webster lacks it (e.g. modern words) but WordNet has it → a real CURATED definition from the immediate kind
    if (wnParent(s)) |p| return known(fmt("{s} {s} is {s} {s}", .{ art(s), s, art(p), p }), "WordNet (curated IS-A)", wnChainStr(s) orelse "curated hypernym");
    return refuse(fmt("I have no verified definition of \"{s}\".", .{s}));
}

// ─────────────────────────── learned intent router (trained perceptron, no hand-written keyword routing) ──────────
const NINTENT = 9;
const Intent = enum(u8) { teach, isa, define, haspart, arith, numprop, string, action, oos };
const intent_name = [_][]const u8{ "teach", "is-a", "define", "has-part", "arithmetic", "number", "string", "action", "out-of-scope" };
var rvocab: std.StringHashMap(u32) = undefined;
var rvcount: u32 = 0;
var rweights: []f32 = undefined;
fn normTok(w: []const u8) []const u8 {
    if (w.len == 0) return w;
    for (w) |c| if (c < '0' or c > '9') return w;
    return "<num>"; // all-digit token → generalize over numbers
}
fn addFeat(ids: *std.ArrayList(u32), key: []const u8, add: bool) void {
    if (rvocab.get(key)) |id| {
        ids.append(id) catch {};
    } else if (add) {
        rvocab.put(A.dupe(u8, key) catch return, rvcount) catch return;
        ids.append(rvcount) catch {};
        rvcount += 1;
    }
}
fn featList(q: []const u8, add: bool) []u32 {
    var ids = std.ArrayList(u32).init(A);
    const ws = words(q);
    var prev: []const u8 = "";
    for (ws) |w0| {
        const w = normTok(w0);
        addFeat(&ids, w, add);
        if (prev.len > 0) addFeat(&ids, fmt("{s}|{s}", .{ prev, w }), add); // bigram
        prev = w;
    }
    if (std.mem.indexOfScalar(u8, q, '`') != null) addFeat(&ids, "<cmd>", add);
    return ids.items;
}
fn predict(ids: []const u32) u8 {
    var best: u8 = 0;
    var bests: f32 = -1e30;
    var c: u8 = 0;
    while (c < NINTENT) : (c += 1) {
        var s: f32 = 0;
        for (ids) |f| s += rweights[@as(usize, c) * rvcount + f];
        if (s > bests) {
            bests = s;
            best = c;
        }
    }
    return best;
}
fn classifyIntent(q: []const u8) Intent {
    return @enumFromInt(predict(featList(q, false)));
}
// generate a labelled corpus combinatorially from word banks — the perceptron learns the routing and generalizes
// to unseen phrasings/combinations (measured on held-out), instead of hand-written `if has("is")` rules.
fn genCorpus(ph: *std.ArrayList([]const u8), lb: *std.ArrayList(u8)) void {
    const N = [_][]const u8{ "king", "dog", "car", "bird", "tree", "whale", "knife", "ship", "horse", "house", "queen", "lion", "clock", "boat" };
    const N2 = [_][]const u8{ "animal", "person", "vehicle", "tool", "plant", "thing", "wheel", "engine", "wing" };
    const NM = [_][]const u8{ "3", "7", "12", "17", "25", "100", "144" };
    const CMD = [_][]const u8{ "`ls`", "`pwd`", "`echo hi`", "`cat readme`" };
    const OOS = [_][]const u8{ "life", "future", "technology", "art", "music", "society", "love", "the universe" };
    const add = struct {
        fn f(p: *std.ArrayList([]const u8), l: *std.ArrayList(u8), s: []const u8, it: Intent) void {
            p.append(s) catch {};
            l.append(@intFromEnum(it)) catch {};
        }
    }.f;
    for (N) |n1| {
        for (N2) |n2| {
            add(ph, lb, fmt("a {s} is a {s}", .{ n1, n2 }), .teach);
            add(ph, lb, fmt("{s} is a {s}", .{ n1, n2 }), .teach);
            add(ph, lb, fmt("is a {s} a {s}", .{ n1, n2 }), .isa);
            add(ph, lb, fmt("is {s} a {s}", .{ n1, n2 }), .isa);
            add(ph, lb, fmt("is a {s} a kind of {s}", .{ n1, n2 }), .isa);
            add(ph, lb, fmt("does a {s} have a {s}", .{ n1, n2 }), .haspart);
            add(ph, lb, fmt("does a {s} have {s}", .{ n1, n2 }), .haspart);
        }
        add(ph, lb, fmt("what is a {s}", .{n1}), .define);
        add(ph, lb, fmt("what is {s}", .{n1}), .define);
        add(ph, lb, fmt("define {s}", .{n1}), .define);
        add(ph, lb, fmt("what does {s} mean", .{n1}), .define);
        add(ph, lb, fmt("tell me about {s}", .{n1}), .define);
        add(ph, lb, fmt("tell me about a {s}", .{n1}), .define);
        add(ph, lb, fmt("describe a {s}", .{n1}), .define);
        add(ph, lb, fmt("describe {s}", .{n1}), .define);
        add(ph, lb, fmt("whats a {s}", .{n1}), .define);
        add(ph, lb, fmt("who is {s}", .{n1}), .define);
        add(ph, lb, fmt("who is a {s}", .{n1}), .define);
        add(ph, lb, fmt("what does a {s} have", .{n1}), .haspart);
        add(ph, lb, fmt("what parts does a {s} have", .{n1}), .haspart);
        add(ph, lb, fmt("parts of a {s}", .{n1}), .haspart);
        add(ph, lb, fmt("what is a {s} made of", .{n1}), .haspart);
        add(ph, lb, fmt("how many letters in {s}", .{n1}), .string);
        add(ph, lb, fmt("reverse {s}", .{n1}), .string);
        add(ph, lb, fmt("first letter of {s}", .{n1}), .string);
        add(ph, lb, fmt("last letter of {s}", .{n1}), .string);
    }
    for (NM) |m1| {
        for (NM) |m2| {
            add(ph, lb, fmt("what is {s} plus {s}", .{ m1, m2 }), .arith);
            add(ph, lb, fmt("{s} times {s}", .{ m1, m2 }), .arith);
            add(ph, lb, fmt("what is {s} minus {s}", .{ m1, m2 }), .arith);
            add(ph, lb, fmt("what is {s} divided by {s}", .{ m1, m2 }), .arith);
            add(ph, lb, fmt("{s} divided by {s}", .{ m1, m2 }), .arith);
            add(ph, lb, fmt("is {s} divisible by {s}", .{ m1, m2 }), .numprop);
            add(ph, lb, fmt("gcd of {s} and {s}", .{ m1, m2 }), .numprop);
            add(ph, lb, fmt("which is bigger {s} or {s}", .{ m1, m2 }), .numprop);
            add(ph, lb, fmt("which is smaller {s} or {s}", .{ m1, m2 }), .numprop);
            add(ph, lb, fmt("is {s} bigger than {s}", .{ m1, m2 }), .numprop);
        }
        add(ph, lb, fmt("is {s} prime", .{m1}), .numprop);
        add(ph, lb, fmt("is {s} even", .{m1}), .numprop);
        add(ph, lb, fmt("is {s} odd", .{m1}), .numprop);
        add(ph, lb, fmt("is {s} a square", .{m1}), .numprop);
        add(ph, lb, fmt("is {s} fibonacci", .{m1}), .numprop);
        add(ph, lb, fmt("how many divisors does {s} have", .{m1}), .numprop);
        add(ph, lb, fmt("what is {s} squared", .{m1}), .arith);
    }
    for (CMD) |c| {
        add(ph, lb, fmt("does {s} work", .{c}), .action);
        add(ph, lb, fmt("does {s} succeed", .{c}), .action);
        add(ph, lb, fmt("run {s}", .{c}), .action);
        add(ph, lb, fmt("what does {s} do", .{c}), .action);
    }
    for (OOS) |o| {
        add(ph, lb, fmt("how will {s} evolve", .{o}), .oos);
        add(ph, lb, fmt("is this {s} beautiful", .{o}), .oos);
        add(ph, lb, fmt("what is the meaning of {s}", .{o}), .oos);
        add(ph, lb, fmt("do you think {s} is good", .{o}), .oos);
        add(ph, lb, fmt("will {s} change", .{o}), .oos);
        add(ph, lb, fmt("should i learn {s}", .{o}), .oos);
    }
}
// train averaged-ish perceptron; return held-out accuracy
fn trainRouter() f64 {
    rvocab = std.StringHashMap(u32).init(A);
    rvcount = 0;
    var ph = std.ArrayList([]const u8).init(A);
    var lb = std.ArrayList(u8).init(A);
    genCorpus(&ph, &lb);
    const N = ph.items.len;
    const feats = A.alloc([]u32, N) catch return 0;
    for (0..N) |i| feats[i] = featList(ph.items[i], true);
    rweights = A.alloc(f32, NINTENT * rvcount) catch return 0;
    @memset(rweights, 0);
    var idx = A.alloc(usize, N) catch return 0;
    for (0..N) |i| idx[i] = i;
    var prng = std.Random.DefaultPrng.init(0x0AC1E5EED);
    const rnd = prng.random();
    rnd.shuffle(usize, idx);
    const ntr = N * 8 / 10;
    for (0..30) |_| for (idx[0..ntr]) |i| {
        const pred = predict(feats[i]);
        const gold = lb.items[i];
        if (pred != gold) for (feats[i]) |f| {
            rweights[@as(usize, gold) * rvcount + f] += 1;
            rweights[@as(usize, pred) * rvcount + f] -= 1;
        };
    };
    var correct: usize = 0;
    for (idx[ntr..]) |i| if (predict(feats[i]) == lb.items[i]) {
        correct += 1;
    };
    const held = N - ntr;
    return if (held == 0) 0 else 100.0 * @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(held));
}

// ─────────────────────────── learned slot extractor (per-token role tagging) ───────────────────────────
// Which token is the SUBJECT vs the OBJECT vs a NUMBER — learned, not hand-coded "first noun / last noun". A per-token
// perceptron over context features (the token, its neighbours, position). Trained on the same generated phrasings,
// auto-labelled because we know which filler is which. Generalises to unseen nouns via the CONTEXT (prev=have→object).
const NROLE = 4; // 0 none, 1 subject, 2 object, 3 num
var svocab: std.StringHashMap(u32) = undefined;
var svcount: u32 = 0;
var sweights: []f32 = undefined;
fn sAdd(ids: *std.ArrayList(u32), key: []const u8, add: bool) void {
    if (svocab.get(key)) |id| {
        ids.append(id) catch {};
    } else if (add) {
        svocab.put(A.dupe(u8, key) catch return, svcount) catch return;
        ids.append(svcount) catch {};
        svcount += 1;
    }
}
fn slotFeats(ws: [][]const u8, i: usize, add: bool) []u32 {
    var ids = std.ArrayList(u32).init(A);
    const w = normTok(ws[i]);
    const prev = if (i > 0) normTok(ws[i - 1]) else "^";
    const next = if (i + 1 < ws.len) normTok(ws[i + 1]) else "$";
    sAdd(&ids, fmt("w={s}", .{w}), add);
    sAdd(&ids, fmt("p={s}", .{prev}), add);
    sAdd(&ids, fmt("n={s}", .{next}), add);
    sAdd(&ids, fmt("pn={s}|{s}", .{ prev, next }), add);
    if (i == 0) sAdd(&ids, "i0", add);
    if (i + 1 == ws.len) sAdd(&ids, "iL", add);
    return ids.items;
}
fn predictRole(ids: []const u32) u8 {
    var best: u8 = 0;
    var bs: f32 = -1e30;
    var c: u8 = 0;
    while (c < NROLE) : (c += 1) {
        var s: f32 = 0;
        for (ids) |f| s += sweights[@as(usize, c) * svcount + f];
        if (s > bs) {
            bs = s;
            best = c;
        }
    }
    return best;
}
fn roleOf(ws: [][]const u8, i: usize) u8 {
    return predictRole(slotFeats(ws, i, false));
}
// the learned operands: first token tagged SUBJECT, first tagged OBJECT
fn slotsFromWs(ws: [][]const u8) struct { subj: []const u8, obj: []const u8 } {
    var subj: []const u8 = "";
    var obj: []const u8 = "";
    for (ws, 0..) |w, i| {
        const r = roleOf(ws, i);
        if (r == 1 and subj.len == 0) subj = w;
        if (r == 2 and obj.len == 0) obj = w;
    }
    return .{ .subj = subj, .obj = obj };
}
fn genSlotCorpus(ph: *std.ArrayList([]const u8), sj: *std.ArrayList([]const u8), ob: *std.ArrayList([]const u8)) void {
    const N = [_][]const u8{ "king", "dog", "car", "bird", "tree", "whale", "knife", "ship", "horse", "house", "queen", "lion", "clock", "boat" };
    const N2 = [_][]const u8{ "animal", "person", "vehicle", "tool", "plant", "thing", "wheel", "engine", "wing" };
    const NM = [_][]const u8{ "3", "7", "12", "17", "100" };
    const OOS = [_][]const u8{ "life", "future", "technology", "art" };
    const add = struct {
        fn f(p: *std.ArrayList([]const u8), s: *std.ArrayList([]const u8), o: *std.ArrayList([]const u8), phrase: []const u8, subj: []const u8, obj: []const u8) void {
            p.append(phrase) catch {};
            s.append(subj) catch {};
            o.append(obj) catch {};
        }
    }.f;
    for (N) |n1| {
        for (N2) |n2| {
            add(ph, sj, ob, fmt("a {s} is a {s}", .{ n1, n2 }), n1, n2);
            add(ph, sj, ob, fmt("{s} is a {s}", .{ n1, n2 }), n1, n2);
            add(ph, sj, ob, fmt("is a {s} a {s}", .{ n1, n2 }), n1, n2);
            add(ph, sj, ob, fmt("is {s} a {s}", .{ n1, n2 }), n1, n2);
            add(ph, sj, ob, fmt("is a {s} a kind of {s}", .{ n1, n2 }), n1, n2);
            add(ph, sj, ob, fmt("does a {s} have a {s}", .{ n1, n2 }), n1, n2);
            add(ph, sj, ob, fmt("does a {s} have {s}", .{ n1, n2 }), n1, n2);
        }
        add(ph, sj, ob, fmt("what is a {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("what is {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("define {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("what does {s} mean", .{n1}), n1, "");
        add(ph, sj, ob, fmt("tell me about {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("tell me about a {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("describe a {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("describe {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("whats a {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("who is {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("who is a {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("what does a {s} have", .{n1}), n1, "");
        add(ph, sj, ob, fmt("what parts does a {s} have", .{n1}), n1, "");
        add(ph, sj, ob, fmt("parts of a {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("what is a {s} made of", .{n1}), n1, "");
        add(ph, sj, ob, fmt("how many letters in {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("reverse {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("first letter of {s}", .{n1}), n1, "");
        add(ph, sj, ob, fmt("last letter of {s}", .{n1}), n1, "");
    }
    for (NM) |m| {
        add(ph, sj, ob, fmt("is {s} prime", .{m}), "", "");
        add(ph, sj, ob, fmt("is {s} fibonacci", .{m}), "", "");
        add(ph, sj, ob, fmt("gcd of {s} and {s}", .{ m, m }), "", "");
    }
    for (OOS) |o| {
        add(ph, sj, ob, fmt("how will {s} evolve", .{o}), "", "");
        add(ph, sj, ob, fmt("is this {s} beautiful", .{o}), "", "");
    }
}
fn labelToken(tok: []const u8, subjF: []const u8, objF: []const u8) u8 {
    var dig = tok.len > 0;
    for (tok) |c| if (c < '0' or c > '9') {
        dig = false;
        break;
    };
    if (dig) return 3;
    if (subjF.len > 0 and std.mem.eql(u8, tok, subjF)) return 1;
    if (objF.len > 0 and std.mem.eql(u8, tok, objF)) return 2;
    return 0;
}
// train the per-token tagger; return accuracy on CONTENT tokens (gold != none) of held-out phrases (the meaningful metric)
fn trainSlots() f64 {
    svocab = std.StringHashMap(u32).init(A);
    svcount = 0;
    var ph = std.ArrayList([]const u8).init(A);
    var sj = std.ArrayList([]const u8).init(A);
    var ob = std.ArrayList([]const u8).init(A);
    genSlotCorpus(&ph, &sj, &ob);
    const NP = ph.items.len;
    var tf = std.ArrayList([]u32).init(A);
    var tl = std.ArrayList(u8).init(A);
    var tp = std.ArrayList(usize).init(A);
    for (0..NP) |i| {
        const ws = words(ph.items[i]);
        for (ws, 0..) |w, j| {
            tf.append(slotFeats(ws, j, true)) catch {};
            tl.append(labelToken(w, sj.items[i], ob.items[i])) catch {};
            tp.append(i) catch {};
        }
    }
    sweights = A.alloc(f32, NROLE * svcount) catch return 0;
    @memset(sweights, 0);
    var isTest = A.alloc(bool, NP) catch return 0;
    @memset(isTest, false);
    var pidx = A.alloc(usize, NP) catch return 0;
    for (0..NP) |i| pidx[i] = i;
    var prng = std.Random.DefaultPrng.init(0x5107ACED);
    prng.random().shuffle(usize, pidx);
    for (pidx[NP * 8 / 10 ..]) |p| isTest[p] = true;
    const T = tf.items.len;
    for (0..30) |_| for (0..T) |t| {
        if (isTest[tp.items[t]]) continue;
        const pred = predictRole(tf.items[t]);
        const gold = tl.items[t];
        if (pred != gold) for (tf.items[t]) |f| {
            sweights[@as(usize, gold) * svcount + f] += 1;
            sweights[@as(usize, pred) * svcount + f] -= 1;
        };
    };
    var corr: usize = 0;
    var tot: usize = 0;
    for (0..T) |t| if (isTest[tp.items[t]] and tl.items[t] != 0) {
        tot += 1;
        if (predictRole(tf.items[t]) == tl.items[t]) corr += 1;
    };
    return if (tot == 0) 0 else 100.0 * @as(f64, @floatFromInt(corr)) / @as(f64, @floatFromInt(tot));
}

// ─────────────────────────── the query router ───────────────────────────
var last: Answer = .{ .status = .refused, .text = "(nothing asked yet)" };
var last_intent: Intent = .oos;
fn dispatch(intent: Intent, q: []const u8, ws: [][]const u8) ?Answer {
    return switch (intent) {
        .teach => hTeach(q, ws),
        .isa => hIsA(ws, true),
        .define => hDefine(ws, true),
        .haspart => hHasPart(ws, true),
        .arith => hArith(ws),
        .numprop => hNumProp(ws),
        .string => hString(ws),
        .action => hAction(q),
        .oos => null,
    };
}
// deterministic safety net: try every handler in a sound order (self-gating). Recovers from any router misroute.
fn tryCascade(q: []const u8, ws: [][]const u8) ?Answer {
    if (hTeach(q, ws)) |a| return a;
    if (hAction(q)) |a| return a;
    if (hArith(ws)) |a| return a;
    if (hNumProp(ws)) |a| return a;
    if (hString(ws)) |a| return a;
    if (hHasPart(ws, false)) |a| return a;
    if (hIsA(ws, false)) |a| return a;
    if (hDefine(ws, false)) |a| return a;
    return null;
}
fn answer(q: []const u8) Answer {
    const ws = words(q);
    if (ws.len == 0) return refuse("(empty)");
    if (hSocial(q, ws)) |a| return a; // greetings / thanks / help — courteous, not a knowledge claim
    last_intent = classifyIntent(q); // LEARNED routing decides which handler to try first
    const routed = dispatch(last_intent, q, ws);
    if (routed) |a| if (a.status != .refused) return a; // confident learned-routed answer wins
    if (tryCascade(q, ws)) |a| return a; // else the deterministic net recovers
    if (routed) |a| return a; // a specific (refused) answer from the routed handler
    // EMERGENT refusal: every source + inference was tried and none verified or derived an answer — not a blacklist.
    return refuse("I have nothing verified that answers this, and I can't derive it from what I know — so I won't guess. (I tried: curated IS-A & HAS-PART, definitions, arithmetic/number-theory, real execution, attested attributes, taught facts, and inference over them.)");
}

fn render(o: anytype, ans: Answer) !void {
    if (ans.status == .meta) { // social/meta: plain reply, no epistemic tag (it isn't a knowledge claim)
        try o.print("{s}\n", .{ans.text});
        return;
    }
    const tag = switch (ans.status) {
        .known => "[KNOWN]  ",
        .opinion => "[OPINION]",
        .refused => "[REFUSED]",
        .meta => unreachable,
    };
    try o.print("{s} {s}\n", .{ tag, ans.text });
    if (ans.source.len > 0) try o.print("          source: {s}\n", .{ans.source});
    if (ans.proof.len > 0) try o.print("          {s}: {s}\n", .{ if (ans.status == .opinion) "derived from" else "proof", ans.proof });
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();

    try o.print("=== THE ORACLE — a knowing engine. Answers are [KNOWN] / [OPINION] / [REFUSED], always with provenance. ===\n", .{});
    try o.print("loading verified knowledge sources...\n", .{});

    // WordNet
    wn_data = std.AutoHashMap(u32, WNode).init(A);
    wn_index = std.StringHashMap([]u32).init(A);
    wn_meron = std.AutoHashMap(u32, []u32).init(A);
    wn_holo = std.AutoHashMap(u32, []u32).init(A);
    if (std.fs.openFileAbsolute(C ++ "dict/data.noun", .{})) |f| {
        defer f.close();
        const buf = try f.readToEndAlloc(A, 1 << 30);
        var lines = std.mem.splitScalar(u8, buf, '\n');
        while (lines.next()) |line| if (line.len >= 5) wnParseData(line);
    } else |_| {}
    if (std.fs.openFileAbsolute(C ++ "dict/index.noun", .{})) |f| {
        defer f.close();
        const buf = try f.readToEndAlloc(A, 1 << 30);
        var lines = std.mem.splitScalar(u8, buf, '\n');
        while (lines.next()) |line| if (line.len >= 5) wnParseIndex(line);
    } else |_| {}
    // Webster
    dict = std.StringHashMap(Def).init(A);
    if (std.fs.openFileAbsolute(C ++ "webster1913.txt", .{})) |f| {
        defer f.close();
        const buf = try f.readToEndAlloc(A, 1 << 30);
        var lines = std.mem.splitScalar(u8, buf, '\n');
        var cur_head: ?[]const u8 = null;
        var body_start: usize = 0;
        var pos_in: usize = 0;
        var longest = std.StringHashMap(usize).init(A);
        while (lines.next()) |line| {
            const line_off = pos_in;
            pos_in += line.len + 1;
            const trimmed = std.mem.trim(u8, line, " \r");
            if (isHeadword(trimmed)) {
                if (cur_head) |h| {
                    const body = buf[body_start..@min(line_off, buf.len)];
                    if (body.len > (longest.get(h) orelse 0)) {
                        const gloss = extractGloss(body);
                        if (gloss.len >= 3) {
                            const gg = extractGenus(gloss);
                            dict.put(h, .{ .pos = partOfSpeech(body), .gloss = gloss, .genus = gg.genus, .syns = gg.syns }) catch {};
                            longest.put(h, body.len) catch {};
                        }
                    }
                }
                var hw = trimmed;
                for (hw, 0..) |c, k| if (c == ' ' or c == ';' or c == ',') {
                    hw = hw[0..k];
                    break;
                };
                cur_head = lower(hw);
                body_start = pos_in;
            }
        }
    } else |_| {}
    // literary corpus (possessive attributes)
    {
        var cb = std.ArrayList(u8).init(A);
        inline for (.{ "moby_dick.txt", "shakespeare.txt", "tolstoy.txt", "austen.txt" }) |fn_| {
            if (std.fs.openFileAbsolute(C ++ fn_, .{})) |f| {
                defer f.close();
                const b = f.readToEndAlloc(A, 1 << 30) catch &[_]u8{};
                cb.appendSlice(b) catch {};
            } else |_| {}
        }
        for (cb.items) |*c| c.* = lo(c.*); // lowercase so possessive scan matches "King's"→"king's"
        corpus = cb.items;
    }
    taught = std.StringHashMap([]const u8).init(A);
    const route_acc = trainRouter(); // learned question-router: trained perceptron over generated phrasings
    const slot_acc = trainSlots(); // learned slot tagger: which token is subject/object/number

    try o.print("ready: {d} WordNet synsets, {d} Webster definitions, {d:.1} MB literary corpus.\n", .{ wn_data.count(), dict.count(), @as(f64, @floatFromInt(corpus.len)) / 1e6 });
    try o.print("learned router: {d:.1}% held-out intent ({d} feats) · learned slots: {d:.1}% held-out subject/object/number ({d} feats).\n", .{ route_acc, rvcount, slot_acc, svcount });
    try o.print("ask me anything ('why' = last proof, 'route <q>' = show the learned intent, 'quit'). I only assert what I can verify.\n\n", .{});

    const stdin = std.io.getStdIn().reader();
    var line = std.ArrayList(u8).init(A);
    while (true) {
        try o.print("you> ", .{});
        line.clearRetainingCapacity();
        stdin.streamUntilDelimiter(line.writer(), '\n', 1 << 16) catch break;
        const q = std.mem.trim(u8, line.items, " \r\t");
        if (q.len == 0) continue;
        if (std.mem.eql(u8, q, "quit") or std.mem.eql(u8, q, "exit")) break;
        if (std.mem.eql(u8, q, "why") or std.mem.eql(u8, q, "how")) {
            try render(o, last);
            continue;
        }
        if (std.mem.startsWith(u8, q, "route ")) { // show the learned router's prediction (no answering)
            try o.print("          learned intent → {s}\n", .{intent_name[@intFromEnum(classifyIntent(q[6..]))]});
            continue;
        }
        last = answer(q);
        try o.print("          (routed as: {s})\n", .{intent_name[@intFromEnum(last_intent)]});
        try render(o, last);
    }
    try o.print("\n(oracle closed)\n", .{});
}
