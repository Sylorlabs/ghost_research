//! ground.zig — GROUND discovered IS-A by cross-source convergence over N independent witnesses (the project's
//! certifier principle: a fact replicated by independent witnesses is real). Witnesses (different corpora, same
//! discovery method — all bytes-up, no hardcoding, no LLM):
//!   • src_wiki.tsv — Wikipedia definitions (funnel+self-closure)      [encyclopedia]
//!   • src_lit.tsv  — Webster genus + literary Hearst (concept_learn)  [dictionary/prose]
//!   • src_wikt.tsv — Wiktionary glosses (funnel+self-closure)         [crowd dictionary]
//! An edge X→Y is GROUNDED at level K iff ≥K witnesses confirm it (X reaches Y, bounded depth, within that
//! witness's own graph — transitive matching converges divergent vocab at shared ancestors). Uncorrelated
//! per-source noise fails to reach quorum. WordNet grades only. Persists the ≥2 set → corpus/grounded_isa.tsv.
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
var A: std.mem.Allocator = undefined;
const KMUL: u64 = 10_000_000;

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

const Graph = struct {
    adj: std.AutoHashMap(u32, std.ArrayList(u32)),
    direct: std.ArrayList([2]u32),
    name: []const u8,
    fn init(name: []const u8) Graph {
        return .{ .adj = std.AutoHashMap(u32, std.ArrayList(u32)).init(A), .direct = std.ArrayList([2]u32).init(A), .name = name };
    }
    fn add(self: *Graph, x: u32, y: u32) void {
        const g = self.adj.getOrPut(x) catch return;
        if (!g.found_existing) g.value_ptr.* = std.ArrayList(u32).init(A);
        g.value_ptr.*.append(y) catch {};
        self.direct.append(.{ x, y }) catch {};
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
fn loadWitness(path: []const u8, name: []const u8) ?Graph {
    const f = std.fs.openFileAbsolute(path, .{}) catch {
        return null;
    };
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return null;
    var g = Graph.init(name);
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
fn lc(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
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

    try o.print("=== GROUND — cross-source convergence over N witnesses ===\n\n", .{});
    var witnesses = std.ArrayList(Graph).init(A);
    const specs = [_][2][]const u8{
        .{ "/tmp/src_wiki.tsv", "wiki" },
        .{ "/tmp/src_lit.tsv", "lit" },
        .{ "/tmp/src_wikt.tsv", "wikt" },
    };
    for (specs) |s| {
        if (loadWitness(s[0], s[1])) |g| witnesses.append(g) catch {};
    }
    loadWordNet();
    for (witnesses.items) |*w| {
        const p = precEdges(w.direct.items);
        try o.print("  witness {s:<5}: {d:>6} edges · alone precision {d:>5}/{d:<6} = {d:.1}%\n", .{ w.name, w.direct.items.len, p[0], p[1], pct(p[0], p[1]) });
    }
    try o.print("\n", .{});

    // candidate edges = dedup union of all witnesses' direct edges
    var cand = std.AutoHashMap(u64, void).init(A);
    var candList = std.ArrayList([2]u32).init(A);
    for (witnesses.items) |*w| {
        for (w.direct.items) |e| {
            const k = @as(u64, e[0]) * KMUL + @as(u64, e[1]);
            const g = cand.getOrPut(k) catch continue;
            if (!g.found_existing) candList.append(e) catch {};
        }
    }

    // vote: how many witnesses confirm each candidate (transitive reach within each)
    var g2 = std.ArrayList([2]u32).init(A);
    var g3 = std.ArrayList([2]u32).init(A);
    for (candList.items) |e| {
        var votes: usize = 0;
        for (witnesses.items) |*w| {
            if (w.reach(e[0], e[1])) votes += 1;
        }
        if (votes >= 2) g2.append(e) catch {};
        if (votes >= 3) g3.append(e) catch {};
    }
    const p2 = precEdges(g2.items);
    const p3 = precEdges(g3.items);

    try o.print("──────────── GROUNDED (precision vs WordNet; coverage = grounded edge count) ────────────\n", .{});
    try o.print("  ≥2 witnesses agree:  {d:>6} edges · {d:>5}/{d:<6} = {d:.1}%\n", .{ g2.items.len, p2[0], p2[1], pct(p2[0], p2[1]) });
    try o.print("  ≥3 witnesses agree:  {d:>6} edges · {d:>5}/{d:<6} = {d:.1}%\n", .{ g3.items.len, p3[0], p3[1], pct(p3[0], p3[1]) });
    try o.print("\n  reference: hand-patterns(HARDCODED) 36.9% · best single-source discovery ~12-15%\n", .{});

    // persist the ≥2 grounded set as the knowledge base
    {
        const f = std.fs.createFileAbsolute(C ++ "grounded_isa.tsv", .{}) catch return;
        defer f.close();
        var bw = std.io.bufferedWriter(f.writer());
        for (g2.items) |e| bw.writer().print("{s}\t{s}\n", .{ vocab.items[e[0]], vocab.items[e[1]] }) catch {};
        bw.flush() catch {};
        try o.print("\n  [persisted {d} grounded (≥2) edges → {s}grounded_isa.tsv]\n", .{ g2.items.len, C });
    }

    try o.print("\n  sample ≥3-witness edges (strongest grounding):\n", .{});
    var shown: usize = 0;
    for (g3.items) |e| {
        if (shown >= 15) break;
        try o.print("    {s} → {s}{s}\n", .{ vocab.items[e[0]], vocab.items[e[1]], if (wnHas(vocab.items[e[0]]) and wnHas(vocab.items[e[1]]) and wnReaches(vocab.items[e[0]], vocab.items[e[1]])) "  ✓WN" else "" });
        shown += 1;
    }
}
