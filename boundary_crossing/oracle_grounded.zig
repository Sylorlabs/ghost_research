//! oracle_grounded.zig — CLOSE THE LOOP. A knowing engine whose IS-A knowledge is the graph it LEARNED ITSELF
//! from raw streamed Wikipedia + Webster, grounded by cross-source agreement (corpus/grounded_isa.tsv). NO WordNet,
//! no handed ontology. It answers [KNOWN]/[REFUSED] with a provenance chain, abstains when it can't verify, and
//! composes TAUGHT facts over its learned graph (the memorization-proof test, now WordNet-free).
//! Build: zig build-exe oracle_grounded.zig -O ReleaseFast -femit-bin=/tmp/og && /tmp/og
const std = @import("std");
const KB = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/grounded_isa.tsv";
const KB_CLEAN = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/grounded_clean.tsv";
const KB_GENUS = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/clean_isa.tsv"; // Wiktionary head-noun + primacy WSD
var A: std.mem.Allocator = undefined;

var isa: std.StringHashMap(std.ArrayList([]const u8)) = undefined; // learned (grounded) hypernyms
var taught: std.StringHashMap(std.ArrayList([]const u8)) = undefined; // taught-by-user hypernyms
var known_word: std.StringHashMap(void) = undefined; // any word the graph has heard of (subject or object)
var childrenOf: std.StringHashMap(std.ArrayList([]const u8)) = undefined; // hypernym → grounded children (for analogy)

fn addEdge(map: *std.StringHashMap(std.ArrayList([]const u8)), x: []const u8, y: []const u8) void {
    const g = map.getOrPut(x) catch return;
    if (!g.found_existing) {
        g.key_ptr.* = A.dupe(u8, x) catch return;
        g.value_ptr.* = std.ArrayList([]const u8).init(A);
    }
    for (g.value_ptr.*.items) |e| if (std.mem.eql(u8, e, y)) return;
    g.value_ptr.*.append(A.dupe(u8, y) catch return) catch {};
    known_word.put(g.key_ptr.*, {}) catch {};
    known_word.put(A.dupe(u8, y) catch return, {}) catch {};
}
fn loadKB() !usize {
    // prefer the clean Wiktionary-genus graph (head-noun + primacy WSD), else refined grounded, else raw
    const f = std.fs.openFileAbsolute(KB_GENUS, .{}) catch (std.fs.openFileAbsolute(KB_CLEAN, .{}) catch try std.fs.openFileAbsolute(KB, .{}));
    defer f.close();
    const buf = try f.readToEndAlloc(A, 1 << 30);
    var n: usize = 0;
    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |line| {
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const x = std.mem.trim(u8, line[0..tab], " \r");
        const y = std.mem.trim(u8, line[tab + 1 ..], " \r");
        if (x.len < 2 or y.len < 2) continue;
        addEdge(&isa, x, y);
        n += 1;
    }
    return n;
}

// BFS over learned ∪ taught; returns the path of words and whether a taught edge was used.
const Path = struct { words: [][]const u8, taught_used: bool };
fn chain(x: []const u8, y: []const u8) ?Path {
    const MAXD = 5; // the genus graph is cleaner (44% + dominant-sense) so deeper composition reaches roots safely
    var parent = std.StringHashMap([]const u8).init(A);
    var via_taught = std.StringHashMap(void).init(A);
    var frontier = std.ArrayList([]const u8).init(A);
    frontier.append(x) catch return null;
    var seen = std.StringHashMap(void).init(A);
    seen.put(x, {}) catch {};
    var depth: usize = 0;
    var found = false;
    outer: while (depth < MAXD and frontier.items.len > 0) : (depth += 1) {
        var next = std.ArrayList([]const u8).init(A);
        for (frontier.items) |cur| {
            for ([_]struct { m: *std.StringHashMap(std.ArrayList([]const u8)), t: bool }{ .{ .m = &taught, .t = true }, .{ .m = &isa, .t = false } }) |src| {
                if (src.m.get(cur)) |ps| for (ps.items) |p| {
                    if (seen.contains(p)) continue;
                    seen.put(p, {}) catch {};
                    parent.put(p, cur) catch {};
                    if (src.t) via_taught.put(p, {}) catch {};
                    if (std.mem.eql(u8, p, y)) {
                        found = true;
                        break :outer;
                    }
                    next.append(p) catch {};
                };
            }
        }
        frontier = next;
    }
    if (!found) return null;
    // reconstruct
    var rev = std.ArrayList([]const u8).init(A);
    var cur = y;
    var tused = false;
    while (true) {
        rev.append(cur) catch {};
        if (via_taught.contains(cur)) tused = true;
        if (std.mem.eql(u8, cur, x)) break;
        cur = parent.get(cur) orelse break;
    }
    var path = A.alloc([]const u8, rev.items.len) catch return null;
    for (rev.items, 0..) |w, i| path[rev.items.len - 1 - i] = w;
    return .{ .words = path, .taught_used = tused };
}

fn buildChildren() void {
    childrenOf = std.StringHashMap(std.ArrayList([]const u8)).init(A);
    var it = isa.iterator();
    while (it.next()) |e| for (e.value_ptr.*.items) |h| {
        const g = childrenOf.getOrPut(h) catch continue;
        if (!g.found_existing) {
            g.key_ptr.* = h;
            g.value_ptr.* = std.ArrayList([]const u8).init(A);
        }
        g.value_ptr.*.append(e.key_ptr.*) catch {};
    };
}
// CONJECTURE by sibling analogy: x shares a hypernym H with sibling S, and S is-a y ⇒ guess x is-a y.
const Conj = struct { sib: []const u8, h: []const u8 };
fn conjecture(x: []const u8, y: []const u8) ?Conj {
    for ([_]?std.ArrayList([]const u8){ isa.get(x), taught.get(x) }) |maybe| {
        const hs = maybe orelse continue;
        for (hs.items) |h| {
            const kids = childrenOf.get(h) orelse continue;
            var n: usize = 0;
            for (kids.items) |s| {
                if (n >= 400) break;
                n += 1;
                if (std.mem.eql(u8, s, x)) continue;
                if (chain(s, y) != null) return .{ .sib = s, .h = h };
            }
        }
    }
    return null;
}
fn art(w: []const u8) []const u8 {
    if (w.len == 0) return "a";
    return switch (w[0]) {
        'a', 'e', 'i', 'o', 'u' => "an",
        else => "a",
    };
}
fn ask(o: anytype, x: []const u8, y: []const u8) !void {
    if (chain(x, y)) |p| {
        var buf = std.ArrayList(u8).init(A);
        for (p.words, 0..) |w, i| {
            if (i > 0) buf.appendSlice(" → ") catch {};
            buf.appendSlice(w) catch {};
        }
        last_why = buf.items;
        const src = if (p.taught_used) "taught + learned graph" else "learned graph (grounded: Wikipedia ∩ Webster ∩ Wiktionary)";
        try o.print("[KNOWN]   yes — {s} {s} is {s} {s}\n          source: {s}\n          proof:  {s}\n", .{ art(x), x, art(y), y, src, buf.items });
    } else if (conjecture(x, y)) |c| {
        last_why = std.fmt.allocPrint(A, "guess by analogy: {s} shares '{s}' with {s} (which is {s} {s})", .{ x, c.h, c.sib, art(y), y }) catch "guess by analogy";
        try o.print("[CONJECTURE] maybe ({s} {s} → {s} {s}) — a GUESS by analogy, not verified.\n          basis:  shares '{s}' with {s}; only a source can promote it to KNOWN.\n", .{ art(x), x, art(y), y, c.h, c.sib });
    } else if (!known_word.contains(x) and !taught.contains(x)) {
        try o.print("[REFUSED] I've never encountered '{s}' in anything I learned — I won't guess.\n", .{x});
    } else {
        try o.print("[REFUSED] I can't verify {s} {s} is {s} {s} from what I learned — so I won't assert it.\n", .{ art(x), x, art(y), y });
    }
}
fn teach(o: anytype, x: []const u8, y: []const u8) !void {
    addEdge(&taught, x, y);
    try o.print("you> (teach) {s} {s} is {s} {s}\n[KNOWN]   learned: stored (provenance: you)\n", .{ art(x), x, art(y), y });
}

var last_why: []const u8 = "(nothing asked yet)";
// function/relational words skipped when pulling the two concepts out of a sentence (mechanism, not knowledge)
fn isFnWord(w: []const u8) bool {
    inline for (.{ "a", "an", "the", "is", "are", "was", "were", "be", "been", "does", "do", "did", "can", "could", "has", "have", "had", "kind", "kinds", "sort", "type", "types", "of", "any", "some", "it", "this", "that", "what", "whats", "which", "who", "define", "why", "to", "as", "or", "and", "really", "actually", "maybe", "you", "i", "me", "really", "just", "even", "also", "still" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}
fn lcdup(s: []const u8) []const u8 {
    const b = A.alloc(u8, s.len) catch return s;
    for (s, 0..) |c, i| b[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    return b;
}
// "what is X" — walk X's hypernym chain and report what it is
fn defineQ(o: anytype, x: []const u8) !void {
    var cur = x;
    var buf = std.ArrayList(u8).init(A);
    var depth: usize = 0;
    var seen = std.StringHashMap(void).init(A);
    while (depth < 2) : (depth += 1) { // "what is X" — the immediate kind(s), kept short to avoid wandering into noise
        if (seen.contains(cur)) break;
        seen.put(cur, {}) catch {};
        const ps = taught.get(cur) orelse isa.get(cur) orelse break;
        if (ps.items.len == 0) break;
        if (depth > 0) buf.appendSlice(" → ") catch {};
        buf.appendSlice(ps.items[0]) catch {};
        cur = ps.items[0];
    }
    if (buf.items.len > 0) {
        last_why = buf.items;
        try o.print("[KNOWN]   {s} {s} is {s} {s}\n          source: learned graph (grounded: Wikipedia ∩ Webster ∩ Wiktionary)\n          proof:  {s} → {s}\n", .{ art(x), x, art(buf.items), firstWord(buf.items), x, buf.items });
    } else if (known_word.contains(x) or taught.contains(x)) {
        try o.print("[REFUSED] I've seen '{s}' but haven't learned what kind of thing it is.\n", .{x});
    } else try o.print("[REFUSED] I've never encountered '{s}'.\n", .{x});
}
fn firstWord(s: []const u8) []const u8 {
    const sp = std.mem.indexOfScalar(u8, s, ' ') orelse return s;
    return s[0..sp];
}
// parse a free-text line and dispatch; returns false to quit
fn handle(o: anytype, raw: []const u8) !bool {
    const has_q = std.mem.indexOfScalar(u8, raw, '?') != null;
    var words = std.ArrayList([]const u8).init(A);
    var copula_at: ?usize = null;
    var tok = std.ArrayList(u8).init(A);
    var i: usize = 0;
    while (i <= raw.len) : (i += 1) {
        const c: u8 = if (i < raw.len) raw[i] else ' ';
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '\'') {
            tok.append(if (c >= 'A' and c <= 'Z') c + 32 else c) catch {};
        } else if (tok.items.len > 0) {
            const w = A.dupe(u8, tok.items) catch tok.items;
            if (copula_at == null and (std.mem.eql(u8, w, "is") or std.mem.eql(u8, w, "are") or std.mem.eql(u8, w, "was") or std.mem.eql(u8, w, "were"))) copula_at = words.items.len;
            words.append(w) catch {};
            tok.clearRetainingCapacity();
        }
    }
    if (words.items.len == 0) return true;
    const w0 = words.items[0];
    if (std.mem.eql(u8, w0, "quit") or std.mem.eql(u8, w0, "exit") or std.mem.eql(u8, w0, "bye")) {
        try o.print("bye.\n", .{});
        return false;
    }
    if (std.mem.eql(u8, w0, "why")) {
        try o.print("          {s}\n", .{last_why});
        return true;
    }
    // content nouns = non-function words
    var nouns = std.ArrayList([]const u8).init(A);
    for (words.items) |w| if (!isFnWord(w) and w.len >= 2) nouns.append(w) catch {};

    // "what is X" / "define X"
    if (std.mem.eql(u8, w0, "what") or std.mem.eql(u8, w0, "whats") or std.mem.eql(u8, w0, "define")) {
        if (nouns.items.len >= 1) try defineQ(o, nouns.items[nouns.items.len - 1]) else try o.print("define what?\n", .{});
        return true;
    }
    const is_question = has_q or std.mem.eql(u8, w0, "is") or std.mem.eql(u8, w0, "are") or std.mem.eql(u8, w0, "was") or std.mem.eql(u8, w0, "does") or std.mem.eql(u8, w0, "do") or std.mem.eql(u8, w0, "can") or std.mem.eql(u8, w0, "could");
    if (is_question) {
        if (nouns.items.len >= 2) {
            try ask(o, nouns.items[0], nouns.items[nouns.items.len - 1]);
        } else try o.print("ask me like: \"is a dog an animal?\"\n", .{});
        return true;
    }
    // declarative with a copula → teach (X is a Y)
    if (copula_at != null and nouns.items.len >= 2) {
        try teach(o, nouns.items[0], nouns.items[nouns.items.len - 1]);
        return true;
    }
    try o.print("try: \"is a dog an animal?\"  ·  \"a poodle is a dog\" (teach)  ·  \"what is a cathedral?\"  ·  why  ·  quit\n", .{});
    return true;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();
    isa = std.StringHashMap(std.ArrayList([]const u8)).init(A);
    taught = std.StringHashMap(std.ArrayList([]const u8)).init(A);
    known_word = std.StringHashMap(void).init(A);

    try o.print("════════════════════════════════════════════════════════════════════════\n", .{});
    try o.print("  THE GROUNDED KNOWER — everything it knows it LEARNED from raw text itself\n", .{});
    try o.print("  (streamed Wikipedia + Wiktionary + Webster; no WordNet, no patterns, no LLM)\n", .{});
    try o.print("════════════════════════════════════════════════════════════════════════\n", .{});
    const n = try loadKB();
    buildChildren();
    try o.print("  knowledge: {d} cross-source-verified IS-A edges over {d} concepts.\n", .{ n, isa.count() });
    try o.print("  I answer in three states and always show my reasoning:\n", .{});
    try o.print("    [KNOWN]      verified — with a proof chain\n", .{});
    try o.print("    [CONJECTURE] a labelled guess by analogy — never passed off as fact\n", .{});
    try o.print("    [REFUSED]    I won't guess when I have no basis\n", .{});
    try o.print("  talk to me:  \"is a dog an animal?\"  ·  \"what is a cathedral?\"  ·  teach me: \"a poodle is a dog\"\n", .{});
    try o.print("               \"why\" = last proof  ·  \"quit\" to leave\n\n", .{});

    const stdin = std.io.getStdIn();
    const interactive = stdin.isTty();
    var br = std.io.bufferedReader(stdin.reader());
    var line = std.ArrayList(u8).init(A);
    if (interactive) try o.print("you> ", .{});
    while (true) {
        line.clearRetainingCapacity();
        br.reader().streamUntilDelimiter(line.writer(), '\n', null) catch break;
        const t = std.mem.trim(u8, line.items, " \r\t");
        if (t.len > 0) {
            const keep = try handle(o, t);
            if (!keep) break;
        }
        if (interactive) try o.print("\nyou> ", .{});
    }
}
