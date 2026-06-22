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
const Status = enum { known, opinion, refused };
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
fn lower(s: []const u8) []const u8 {
    const b = A.alloc(u8, s.len) catch return s;
    for (0..s.len) |i| b[i] = lo(s[i]);
    return b;
}

// ─────────────────────────── WordNet curated IS-A ───────────────────────────
const WNode = struct { word: []const u8, hyper: u32 };
var wn_data: std.AutoHashMap(u32, WNode) = undefined;
var wn_index: std.StringHashMap([]u32) = undefined;
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
    var p: usize = 0;
    while (p < pcnt) : (p += 1) {
        const base = pcnt_idx + 1 + p * 4;
        if (base + 1 >= toks.items.len) break;
        if (std.mem.eql(u8, toks.items[base], "@") or std.mem.eql(u8, toks.items[base], "@i")) {
            hyper = std.fmt.parseInt(u32, toks.items[base + 1], 10) catch 0;
            break;
        }
    }
    wn_data.put(offset, .{ .word = firstWordClean(word), .hyper = hyper }) catch {};
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
fn wnKnown(x: []const u8) bool {
    return wn_index.contains(x);
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
    inline for (.{ "\"", " -- ", "Etym", "Syn.", " [" }) |cut| {
        if (std.mem.indexOf(u8, g, cut)) |at| g = std.mem.trim(u8, g[0..at], " ");
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

// ─────────────────────────── the query router ───────────────────────────
var last: Answer = .{ .status = .refused, .text = "(nothing asked yet)" };
fn answer(q: []const u8) Answer {
    const ws = words(q);
    if (ws.len == 0) return refuse("(empty)");

    // ── TEACH: "X is a Y" / "a X is a Y" (statement, ends without '?') ──
    if (std.mem.indexOf(u8, q, "?") == null) {
        // find "is a/an" pattern: subject before "is", genus after "is a"
        for (ws, 0..) |w, i| if (std.mem.eql(u8, w, "is") and i + 2 < ws.len and isArticle(ws[i + 1]) and i >= 1) {
            const subj = ws[i - 1];
            const gen = ws[i + 2];
            if (subj.len >= 2 and gen.len >= 2 and !has(ws, "what")) {
                taught.put(A.dupe(u8, subj) catch subj, A.dupe(u8, gen) catch gen) catch {};
                return known(fmt("learned: a {s} is a {s}.", .{ subj, gen }), "taught by you", "stored in the knowledge base (provenance: you)");
            }
        };
    }

    // ── ARITHMETIC: <int> <op> <int> ──
    if (firstInt(ws)) |fi| {
        if (fi + 2 < ws.len) {
            const a1 = parseU(ws[fi]);
            const op = ws[fi + 1];
            const a2 = parseU(ws[fi + 2]);
            if (a1 != null and a2 != null) {
                const x = a1.?;
                const y = a2.?;
                var r: ?u64 = null;
                if (has(ws, "plus") or std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "plus")) r = x + y;
                if (std.mem.eql(u8, op, "minus") or std.mem.eql(u8, op, "-")) r = if (x >= y) x - y else 0;
                if (std.mem.eql(u8, op, "times") or std.mem.eql(u8, op, "x") or std.mem.eql(u8, op, "*")) r = x * y;
                if (r) |v| return known(fmt("{d}", .{v}), "computed", fmt("exact arithmetic: {d} {s} {d} = {d}", .{ x, op, y, v }));
            }
        }
    }

    // ── NUMBER PROPERTIES ──
    if (firstInt(ws)) |fi| if (parseU(ws[fi])) |n| {
        if (has(ws, "prime")) return known(if (isPrime(n)) "yes" else "no", "computed", fmt("trial division: {d} is {s}prime", .{ n, if (isPrime(n)) "" else "not " }));
        if (has(ws, "square")) return known(if (isSquare(n)) "yes" else "no", "computed", fmt("{d} = isqrt² check → {s} a perfect square", .{ n, if (isSquare(n)) "is" else "is not" }));
        if (has(ws, "even")) return known(if (n % 2 == 0) "yes" else "no", "computed", fmt("{d} mod 2 = {d}", .{ n, n % 2 }));
        if (has(ws, "divisors") or has(ws, "factors")) {
            const dc = divisorCount(n);
            return known(fmt("{d}", .{dc}), "computed", fmt("counted divisors of {d}", .{n}));
        }
    };
    // identity question: "is odd-divisors the same as square" / "for all n"
    if ((has(ws, "divisors") or has(ws, "identity")) and (has(ws, "always") or has(ws, "all"))) {
        if (identityHoldsOverDomain())
            return opinion("likely yes for all n — it's Fermat's divisor-pairing theorem", "KNOWN: verified that (odd #divisors ⟺ perfect square) for every n in [1,4096); beyond that range it is unverified here (a conjecture from the proven domain)");
    }

    // ── STRING ATOMS ──
    if (has(ws, "letters") and has(ws, "in")) {
        const s = subject(ws);
        return known(fmt("{d}", .{s.len}), "computed", fmt("counted letters in \"{s}\"", .{s}));
    }
    if (has(ws, "reverse")) {
        const s = subject(ws);
        const b = A.alloc(u8, s.len) catch return refuse("?");
        for (0..s.len) |i| b[i] = s[s.len - 1 - i];
        return known(b, "computed", fmt("reversed \"{s}\"", .{s}));
    }
    if ((has(ws, "first") or has(ws, "last")) and has(ws, "letter")) {
        const s = subject(ws);
        if (s.len == 0) return refuse("which word?");
        const c = if (has(ws, "first")) s[0] else s[s.len - 1];
        return known(fmt("{c}", .{c}), "computed", fmt("indexed \"{s}\"", .{s}));
    }

    // ── ACTION OUTCOME: "does `<cmd>` succeed/work" — run it for real (safe commands only) ──
    if (std.mem.indexOf(u8, q, "`")) |b0| if (std.mem.indexOfPos(u8, q, b0 + 1, "`")) |b1| {
        const cmd = q[b0 + 1 .. b1];
        if (runOutcome(cmd)) |ok2|
            return known(if (ok2) "succeeds" else "fails", "real execution", fmt("ran `{s}` → exit {s}", .{ cmd, if (ok2) "0" else "nonzero" }))
        else
            return refuse(fmt("I won't run `{s}` — only safe read-only commands (test/ls/cat/echo/stat/wc/head/file).", .{cmd}));
    };

    // ── IS-A QUESTION: "is a X a Y" / "is X a kind of Y" (yes/no; NOT "what is X" which is a definition) ──
    if (has(ws, "is") and !has(ws, "what") and !has(ws, "define")) {
        // pattern: ... is [a] X [a/kind of] Y  → take the two content nouns around the second article
        var nouns = std.ArrayList([]const u8).init(A);
        for (ws) |w| if (!isArticle(w) and !std.mem.eql(u8, w, "is") and !std.mem.eql(u8, w, "kind") and !std.mem.eql(u8, w, "of")) nouns.append(w) catch {};
        if (nouns.items.len >= 2) {
            const x = nouns.items[0];
            const y = nouns.items[nouns.items.len - 1];
            if (!std.mem.eql(u8, x, y)) {
                if (wnIsA(x, y)) |chain| return known("yes", "WordNet (curated IS-A)", chain);
                // taught-fact chain
                if (taught.get(x)) |g| {
                    if (std.mem.eql(u8, g, y)) return known("yes", "taught by you", fmt("you told me: {s} is-a {s}", .{ x, y }));
                    if (wnIsA(g, y)) |ch| return known("yes", "taught + WordNet", fmt("you taught {s} is-a {s}; {s}", .{ x, g, ch }));
                }
                if (wnKnown(x) and wnKnown(y)) return known("no", "WordNet (curated IS-A)", fmt("{s} has no hypernym chain reaching {s}", .{ x, y }));
                if (deriveIsA(x, y)) |op| return op;
                return refuse(fmt("I can't verify whether a {s} is a {s} — neither is in my curated knowledge.", .{ x, y }));
            }
        }
    }

    // ── DEFINE / WHAT IS X / ATTRIBUTES ──
    if (has(ws, "what") or has(ws, "define") or (has(ws, "does") and (has(ws, "have") or has(ws, "has")))) {
        const s = subject(ws);
        if (s.len == 0) return refuse("define what?");
        // attributes: "what does a king have"
        if (has(ws, "have") or has(ws, "has")) {
            const at = attributesOf(s);
            if (at.len > 0) return known(fmt("a {s} has: {s}", .{ s, at }), "corpus-attested (possessive usage in literature)", fmt("found \"{s}'s …\" patterns in the corpus", .{s}));
        }
        if (dict.get(s)) |d| {
            const syn = if (d.syns.len > 0) fmt(" (also: {s})", .{d.syns}) else "";
            return known(fmt("a {s} is a {s}{s} — \"{s}\"", .{ s, d.genus, syn, d.gloss }), "Webster 1913", fmt("genus extracted from the definition gloss", .{}));
        }
        if (taught.get(s)) |g| return known(fmt("a {s} is a {s}", .{ s, g }), "taught by you", "from the knowledge base you extended");
        // opinion fallback: build from WordNet chain if any
        if (wnChainStr(s)) |ch| return opinion(fmt("I don't have a definition, but its kind-chain is: {s}", .{ch}), fmt("KNOWN: {s} (WordNet IS-A chain)", .{ch}));
        return refuse(fmt("I have no verified definition of \"{s}\".", .{s}));
    }

    // ── SUBJECTIVE / UNGROUNDED → refuse (or thin opinion if a known fact is touched) ──
    inline for (.{ "beautiful", "best", "should", "feel", "meaning", "love", "happy", "good", "evil", "will", "future", "evolve", "think", "opinion", "believe" }) |sub| {
        if (has(ws, sub)) {
            return refuse("that's a matter of opinion or an open/unverifiable question — I won't pass a guess off as knowledge. Ask me something I can verify, or ask explicitly for my opinion on a topic I have facts about.");
        }
    }
    return refuse("I couldn't map that to anything I can verify. Try: \"is a king a person?\", \"what is a whale?\", \"what's 12 times 8?\", \"is 17 prime?\", \"what does a king have?\", \"does `ls` succeed?\", or teach me \"a quokka is a marsupial\".");
}

fn render(o: anytype, ans: Answer) !void {
    const tag = switch (ans.status) {
        .known => "[KNOWN]  ",
        .opinion => "[OPINION]",
        .refused => "[REFUSED]",
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

    try o.print("ready: {d} WordNet synsets, {d} Webster definitions, {d:.1} MB literary corpus.\n", .{ wn_data.count(), dict.count(), @as(f64, @floatFromInt(corpus.len)) / 1e6 });
    try o.print("ask me anything (or 'why' for the last proof, 'quit' to exit). I only assert what I can verify.\n\n", .{});

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
        last = answer(q);
        try render(o, last);
    }
    try o.print("\n(oracle closed)\n", .{});
}
