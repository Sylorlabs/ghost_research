//! conjecture.zig — the CONJECTURE → test → KNOWN loop (guessing as the engine of invention).
//! Starting from the grounded KNOWN graph (corpus/grounded_isa.tsv), it GUESSES new edges by analogy
//! (siblings under a shared hypernym tend to share other parents: crow→bird ⇒ conjecture raven→bird),
//! LABELS them conjectures, then TESTS each against the independent witnesses (src_wiki/lit/wikt) — promoting
//! only the ones a witness confirms to KNOWN. This grows knowledge BEYOND any single source while staying
//! verified. WordNet grades only (it is never the tester). Measures: does test beat untested guessing?
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
var A: std.mem.Allocator = undefined;
const KMUL: u64 = 10_000_000;
const MIN_SUPPORT = 3; // ≥ this many siblings must share a parent before we conjecture it for another sibling
const MAXKIDS = 120; // skip over-generic hubs (noise magnets) with more children than this
const TEST_VOTES = 2; // a conjecture is CONFIRMED only if ≥ this many independent witnesses attest it

var vocab: std.ArrayList([]const u8) = undefined;
var id_of: std.StringHashMap(u32) = undefined;
fn intern(w: []const u8) u32 {
    const g = id_of.getOrPut(w) catch unreachable;
    if (!g.found_existing) {
        const dup = A.dupe(u8, w) catch unreachable;
        g.key_ptr.* = dup;
        g.value_ptr.* = @intCast(vocab.items.len);
        vocab.append(dup) catch unreachable;
    }
    return g.value_ptr.*;
}
fn lc(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

const Graph = struct {
    adj: std.AutoHashMap(u32, std.ArrayList(u32)),
    direct: std.ArrayList([2]u32),
    fn init() Graph {
        return .{ .adj = std.AutoHashMap(u32, std.ArrayList(u32)).init(A), .direct = std.ArrayList([2]u32).init(A) };
    }
    fn add(self: *Graph, x: u32, y: u32) void {
        const g = self.adj.getOrPut(x) catch return;
        if (!g.found_existing) g.value_ptr.* = std.ArrayList(u32).init(A);
        for (g.value_ptr.*.items) |e| if (e == y) return;
        g.value_ptr.*.append(y) catch {};
        self.direct.append(.{ x, y }) catch {};
    }
    fn hasEdge(self: *Graph, x: u32, y: u32) bool {
        if (self.adj.get(x)) |ns| for (ns.items) |n| if (n == y) return true;
        return false;
    }
    fn reach(self: *Graph, x: u32, y: u32) bool {
        if (x == y) return true;
        const MAXD = 4;
        var frontier = std.ArrayList(u32).init(A);
        defer frontier.deinit();
        frontier.append(x) catch return false;
        var seen = std.AutoHashMap(u32, void).init(A);
        defer seen.deinit();
        seen.put(x, {}) catch {};
        var depth: usize = 0;
        while (depth < MAXD and frontier.items.len > 0) : (depth += 1) {
            var next = std.ArrayList(u32).init(A);
            for (frontier.items) |cur| {
                if (self.adj.get(cur)) |ns| for (ns.items) |n| {
                    if (n == y) return true;
                    if (seen.contains(n)) continue;
                    seen.put(n, {}) catch {};
                    next.append(n) catch {};
                };
            }
            frontier = next;
        }
        return false;
    }
};
fn loadGraph(path: []const u8) ?Graph {
    const f = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return null;
    var g = Graph.init();
    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |line| {
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const x = std.mem.trim(u8, line[0..tab], " \r");
        const y = std.mem.trim(u8, line[tab + 1 ..], " \r");
        if (x.len < 2 or y.len < 2) continue;
        const xi = intern(x);
        const yi = intern(y);
        if (xi != yi) g.add(xi, yi);
    }
    return g;
}

// ── WordNet grader (grade only) ──
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

    try o.print("=== CONJECTURE → test → KNOWN  (guessing as the engine of invention) ===\n\n", .{});
    var G = loadGraph(C ++ "grounded_isa.tsv") orelse {
        try o.print("no grounded_isa.tsv — run ground first.\n", .{});
        return;
    };
    var witnesses = std.ArrayList(Graph).init(A);
    for ([_][]const u8{ "/tmp/src_wiki.tsv", "/tmp/src_lit.tsv", "/tmp/src_wikt.tsv" }) |p| {
        if (loadGraph(p)) |g| witnesses.append(g) catch {};
    }
    loadWordNet();
    try o.print("grounded KNOWN base: {d} edges · {d} witnesses for testing\n\n", .{ G.direct.items.len, witnesses.items.len });

    // a hypernym is trustworthy only if it is itself a defined concept (appears as a subject = has its own
    // hypernym). This drops abstract noise-magnets (made/given/commonly never have "made is a ...").
    const isConcept = struct {
        fn f(g: *Graph, w: u32) bool {
            return g.adj.contains(w);
        }
    }.f;

    // children index: hypernym H → its grounded children (co-hyponyms / siblings) — concept hypernyms only
    var childrenOf = std.AutoHashMap(u32, std.ArrayList(u32)).init(A);
    for (G.direct.items) |e| {
        if (!isConcept(&G, e[1])) continue; // skip edges to non-concept (abstract) hypernyms
        const g = childrenOf.getOrPut(e[1]) catch continue;
        if (!g.found_existing) g.value_ptr.* = std.ArrayList(u32).init(A);
        g.value_ptr.*.append(e[0]) catch {};
    }

    // generate conjectures by sibling analogy, dedup
    var seenC = std.AutoHashMap(u64, void).init(A);
    var conj = std.ArrayList([2]u32).init(A);
    var pool = std.AutoHashMap(u32, u32).init(A); // parent → support among H's children
    var hit = childrenOf.iterator();
    while (hit.next()) |he| {
        const H = he.key_ptr.*;
        const kids = he.value_ptr.*.items;
        if (kids.len < 2 or kids.len > MAXKIDS) continue; // need siblings, but skip over-generic hubs
        // parent pool: how many children of H have parent P (P≠H) — concept parents only
        pool.clearRetainingCapacity();
        for (kids) |a| if (G.adj.get(a)) |ps| for (ps.items) |p| {
            if (p == H or !isConcept(&G, p)) continue;
            const g = pool.getOrPut(p) catch continue;
            if (!g.found_existing) g.value_ptr.* = 0;
            g.value_ptr.* += 1;
        };
        // conjecture: each child B gets each well-supported pool parent P it doesn't already have
        for (kids) |b| {
            var pit = pool.iterator();
            while (pit.next()) |pe| {
                const P = pe.key_ptr.*;
                if (pe.value_ptr.* < MIN_SUPPORT) continue;
                if (P == b or P == H) continue;
                if (G.hasEdge(b, P)) continue; // already known
                const key = @as(u64, b) * KMUL + @as(u64, P);
                const g = seenC.getOrPut(key) catch continue;
                if (g.found_existing) continue;
                conj.append(.{ b, P }) catch {};
            }
        }
    }

    // TEST each conjecture against the independent witnesses
    var confirmed = std.ArrayList([2]u32).init(A);
    var confirmed_new = std.ArrayList([2]u32).init(A); // confirmed AND not already grounded (genuinely new knowledge)
    for (conj.items) |e| {
        var votes: usize = 0;
        for (witnesses.items) |*w| if (w.reach(e[0], e[1])) {
            votes += 1;
        };
        if (votes >= TEST_VOTES) {
            confirmed.append(e) catch {};
            if (!G.hasEdge(e[0], e[1])) confirmed_new.append(e) catch {};
        }
    }

    const pAll = precEdges(conj.items);
    const pConf = precEdges(confirmed.items);
    try o.print("──────────── does TESTING beat untested guessing? (precision vs WordNet) ────────────\n", .{});
    try o.print("  conjectured (guesses)         {d:>6} edges · {d:>5}/{d:<6} = {d:.1}%\n", .{ conj.items.len, pAll[0], pAll[1], pct(pAll[0], pAll[1]) });
    try o.print("  CONFIRMED by a witness (KNOWN){d:>6} edges · {d:>5}/{d:<6} = {d:.1}%\n", .{ confirmed.items.len, pConf[0], pConf[1], pct(pConf[0], pConf[1]) });
    try o.print("  → invention yield: {d} confirmed edges NOT in the grounded base = NEW verified knowledge\n", .{confirmed_new.items.len});

    // persist promoted conjectures
    {
        const f = std.fs.createFileAbsolute(C ++ "conjectured_isa.tsv", .{}) catch return;
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        for (confirmed.items) |e| bw.writer().print("{s}\t{s}\n", .{ vocab.items[e[0]], vocab.items[e[1]] }) catch {};
        bw.flush() catch {};
        try o.print("\n  [persisted {d} promoted (conjectured→confirmed) edges → {s}conjectured_isa.tsv]\n", .{ confirmed.items.len, C });
    }

    try o.print("\n  sample INVENTIONS (guessed by analogy, NOT in grounded base, confirmed by a witness ⇒ KNOWN):\n", .{});
    var shown: usize = 0;
    for (confirmed_new.items) |e| {
        if (shown >= 15) break;
        const wn = if (wnHas(vocab.items[e[0]]) and wnHas(vocab.items[e[1]]) and wnReaches(vocab.items[e[0]], vocab.items[e[1]])) "  ✓WN" else "";
        try o.print("    {s} → {s}{s}\n", .{ vocab.items[e[0]], vocab.items[e[1]], wn });
        shown += 1;
    }
}
