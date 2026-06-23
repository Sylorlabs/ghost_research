//! oracle_grounded.zig — CLOSE THE LOOP. A knowing engine whose IS-A knowledge is the graph it LEARNED ITSELF
//! from raw streamed Wikipedia + Webster, grounded by cross-source agreement (corpus/grounded_isa.tsv). NO WordNet,
//! no handed ontology. It answers [KNOWN]/[REFUSED] with a provenance chain, abstains when it can't verify, and
//! composes TAUGHT facts over its learned graph (the memorization-proof test, now WordNet-free).
//! Build: zig build-exe oracle_grounded.zig -O ReleaseFast -femit-bin=/tmp/og && /tmp/og
const std = @import("std");
const KB = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/grounded_isa.tsv";
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
    const f = try std.fs.openFileAbsolute(KB, .{});
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
    const MAXD = 2; // shallow: deep composition over a ~30-40% base manufactures false certainty (oak→high→sea→animal)
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
    try o.print("you> is {s} {s} {s} {s}?\n", .{ art(x), x, art(y), y });
    if (chain(x, y)) |p| {
        var buf = std.ArrayList(u8).init(A);
        for (p.words, 0..) |w, i| {
            if (i > 0) buf.appendSlice(" → ") catch {};
            buf.appendSlice(w) catch {};
        }
        const src = if (p.taught_used) "taught + learned graph" else "learned graph (grounded: Wikipedia ∩ Webster/literature)";
        try o.print("[KNOWN]   yes\n          source: {s}\n          proof:  {s}\n", .{ src, buf.items });
    } else if (conjecture(x, y)) |c| {
        try o.print("[CONJECTURE] maybe — this is a GUESS by analogy, not verified.\n          basis:  {s} is also {s} {s} (shares '{s}' with {s}); promote only if a source confirms it.\n", .{ x, art(y), y, c.h, c.sib });
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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();
    isa = std.StringHashMap(std.ArrayList([]const u8)).init(A);
    taught = std.StringHashMap(std.ArrayList([]const u8)).init(A);
    known_word = std.StringHashMap(void).init(A);

    try o.print("=== THE GROUNDED ORACLE — knowledge LEARNED from raw text, not handed (no WordNet) ===\n", .{});
    const n = try loadKB();
    buildChildren();
    try o.print("loaded {d} grounded IS-A edges ({d} concepts) — self-learned from Wikipedia+Webster+Wiktionary, cross-source verified.\n", .{ n, isa.count() });
    try o.print("(three epistemic states: KNOWN = grounded/proven · CONJECTURE = labeled guess, NOT trusted · REFUSED.\n grounded graph ~30-44%% precise vs WordNet — the cross-source frontier; queries below hit its real core.)\n\n", .{});

    try o.print("──────── 1. it KNOWS what it learned (answers with a provenance chain) ────────\n", .{});
    try ask(o, "oak", "tree");
    try ask(o, "cathedral", "church");
    try ask(o, "lieutenant", "officer");
    try ask(o, "loch", "lake");
    try ask(o, "guild", "association");
    try ask(o, "breakfast", "meal");

    try o.print("\n──────── 2. it ABSTAINS when it can't verify (knower, not guesser) ────────\n", .{});
    try ask(o, "oak", "animal"); // no learned path
    try ask(o, "blarnac", "tree"); // never encountered
    try ask(o, "breakfast", "vehicle");

    try o.print("\n──────── 3. it GUESSES out loud — CONJECTURE by analogy, labeled, never passed off as fact ────────\n", .{});
    try o.print("(invention fuel: a hypothesis is a guess. It's marked [CONJECTURE] and only a source can promote it to KNOWN.)\n", .{});
    try ask(o, "raven", "bird");
    try ask(o, "robin", "animal");
    try ask(o, "trout", "fish");

    try o.print("\n──────── 4. memorization-proof COMPOSITION over the LEARNED graph (no WordNet) ────────\n", .{});
    try o.print("(teach a brand-new word, then ask a consequence it was never told — only real composition can answer)\n", .{});
    try teach(o, "blorch", "oak");
    try ask(o, "blorch", "tree"); // blorch→oak (taught) → tree (learned)  ⇒ KNOWN
    try ask(o, "blorch", "animal"); // no path ⇒ REFUSED

    // show a few multi-hop chains the learned graph already contains (composition without teaching)
    try o.print("\n──────── 5. multi-hop chains discovered in the learned graph ────────\n", .{});
    var shown: usize = 0;
    var it = isa.iterator();
    while (it.next()) |e| {
        if (shown >= 8) break;
        const x = e.key_ptr.*;
        // walk best-first to depth, print if ≥2 hops
        var cur = x;
        var buf = std.ArrayList(u8).init(A);
        buf.appendSlice(x) catch {};
        var d: usize = 0;
        var seen = std.StringHashMap(void).init(A);
        while (d < 5) : (d += 1) {
            if (seen.contains(cur)) break;
            seen.put(cur, {}) catch {};
            const ps = isa.get(cur) orelse break;
            if (ps.items.len == 0) break;
            cur = ps.items[0];
            buf.appendSlice(" → ") catch {};
            buf.appendSlice(cur) catch {};
        }
        if (d >= 2) {
            try o.print("    {s}\n", .{buf.items});
            shown += 1;
        }
    }

    // optional interactive: read "x|y" or "teach x|y" lines from stdin
    const stdin = std.io.getStdIn();
    var br = std.io.bufferedReader(stdin.reader());
    var line = std.ArrayList(u8).init(A);
    if (stdin.isTty() == false) {
        while (true) {
            line.clearRetainingCapacity();
            br.reader().streamUntilDelimiter(line.writer(), '\n', null) catch break;
            const t = std.mem.trim(u8, line.items, " \r");
            if (t.len == 0) continue;
            const teach_pref = std.mem.startsWith(u8, t, "teach ");
            const body = if (teach_pref) t[6..] else t;
            const bar = std.mem.indexOfScalar(u8, body, '|') orelse continue;
            const x = std.mem.trim(u8, body[0..bar], " ");
            const y = std.mem.trim(u8, body[bar + 1 ..], " ");
            if (teach_pref) try teach(o, x, y) else try ask(o, x, y);
        }
    }
}
