//! refine.zig — attack the SYSTEMATIC noise that cross-source voting can't (abstract-hub attachments shared by
//! all dictionary sources: →act, →quality, →state, →part, →form). Discovered signal, no hardcoded list:
//! abstract RELATIONAL nouns are overwhelmingly followed by "of" ("the act OF", "the quality OF"), while concrete
//! taxonomic hubs (animal, tree, bird) are not. So measure each hypernym's P(next == "of") from the corpus and
//! DEMOTE edges whose hypernym is predominantly an "of"-noun. Grade the grounded graph before/after vs WordNet.
//! Build: zig build-exe refine.zig -O ReleaseFast -femit-bin=/tmp/ref && /tmp/ref
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
var A: std.mem.Allocator = undefined;
const PA = std.heap.page_allocator;
const OF_MAX = 0.80; // demote only egregious connectives ("X is a KIND/TYPE/PART of Y" — real hypernym is Y, not the connective)
const MINOCC = 20; // need at least this many occurrences to judge the of-ratio (else keep)

fn lc(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn fmt(comptime f: []const u8, a: anytype) []const u8 {
    return std.fmt.allocPrint(A, f, a) catch "?";
}

// ── of-ratio from corpus: freq[w] and ofcount[w] (= times w is immediately followed by "of") ──
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
fn countFile(name: []const u8) void {
    const f = std.fs.openFileAbsolute(fmt("{s}{s}", .{ C, name }), .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(PA, 1 << 30) catch return;
    defer PA.free(buf);
    var prev: []const u8 = "";
    var tok = std.ArrayList(u8).init(A);
    defer tok.deinit();
    var i: usize = 0;
    while (i <= buf.len) : (i += 1) {
        const ch: u8 = if (i < buf.len) buf[i] else ' ';
        if (isAlpha(ch)) {
            tok.append(lc(ch)) catch {};
            continue;
        }
        if (tok.items.len >= 1) {
            const w = tok.items;
            bump(&freq, w);
            if (std.mem.eql(u8, w, "of") and prev.len > 0) bump(&ofc, prev);
            prev = A.dupe(u8, w) catch "";
        }
        tok.clearRetainingCapacity();
    }
}
fn ofRatio(w: []const u8) ?f64 {
    const fc = freq.get(w) orelse return null;
    if (fc < MINOCC) return null; // not enough evidence
    const oc = ofc.get(w) orelse 0;
    return @as(f64, @floatFromInt(oc)) / @as(f64, @floatFromInt(fc));
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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();
    freq = std.StringHashMap(u32).init(A);
    ofc = std.StringHashMap(u32).init(A);

    try o.print("=== REFINE — demote abstract 'of'-hubs (systematic noise voting can't remove) ===\n", .{});
    try o.print("[1] counting word + 'word of' frequencies from definition corpora…\n", .{});
    countFile("wiki_simple_defs.txt");
    countFile("wikt_defs.txt");
    loadWordNet();

    // load grounded edges; split into kept / demoted by hypernym of-ratio
    const f = std.fs.openFileAbsolute(C ++ "grounded_isa.tsv", .{}) catch {
        try o.print("no grounded_isa.tsv\n", .{});
        return;
    };
    const buf = try f.readToEndAlloc(A, 1 << 30);
    f.close();
    const Edge = struct { x: []const u8, y: []const u8 };
    var all = std.ArrayList(Edge).init(A);
    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |line| {
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const x = std.mem.trim(u8, line[0..tab], " \r");
        const y = std.mem.trim(u8, line[tab + 1 ..], " \r");
        if (x.len < 2 or y.len < 2) continue;
        all.append(.{ .x = A.dupe(u8, x) catch x, .y = A.dupe(u8, y) catch y }) catch {};
    }

    var kept = std.ArrayList(Edge).init(A);
    var demoted_hubs = std.StringHashMap(u32).init(A);
    for (all.items) |e| {
        const r = ofRatio(e.y);
        if (r != null and r.? > OF_MAX) {
            const g = demoted_hubs.getOrPut(e.y) catch continue;
            if (!g.found_existing) {
                g.key_ptr.* = e.y;
                g.value_ptr.* = 0;
            }
            g.value_ptr.* += 1;
            continue; // demote this edge
        }
        kept.append(e) catch {};
    }

    // grade before/after
    var bc: usize = 0;
    var bh: usize = 0;
    for (all.items) |e| {
        if (!wnHas(e.x) or !wnHas(e.y)) continue;
        bc += 1;
        if (wnReaches(e.x, e.y)) bh += 1;
    }
    var kc: usize = 0;
    var kh: usize = 0;
    for (kept.items) |e| {
        if (!wnHas(e.x) or !wnHas(e.y)) continue;
        kc += 1;
        if (wnReaches(e.x, e.y)) kh += 1;
    }
    try o.print("\n──────────── precision before/after demoting 'of'-hubs (vs WordNet) ────────────\n", .{});
    try o.print("  before:  {d} edges · {d}/{d} = {d:.1}%\n", .{ all.items.len, bh, bc, pct(bh, bc) });
    try o.print("  after:   {d} edges · {d}/{d} = {d:.1}%   ({d} edges demoted as 'of'-hub attachments)\n", .{ kept.items.len, kh, kc, pct(kh, kc), all.items.len - kept.items.len });

    // show the abstract hubs it discovered + demoted
    const HC = struct { w: []const u8, c: u32, r: f64 };
    var hubs = std.ArrayList(HC).init(A);
    var hit = demoted_hubs.iterator();
    while (hit.next()) |e| hubs.append(.{ .w = e.key_ptr.*, .c = e.value_ptr.*, .r = ofRatio(e.key_ptr.*) orelse 0 }) catch {};
    std.mem.sort(HC, hubs.items, {}, struct {
        fn lt(_: void, a: HC, b: HC) bool {
            return a.c > b.c;
        }
    }.lt);
    try o.print("\n  discovered abstract 'of'-hubs demoted (by edges removed):\n", .{});
    for (hubs.items, 0..) |h, i| {
        if (i >= 18) break;
        try o.print("    {s:<14} of-rate={d:.0}%  removed {d} edges\n", .{ h.w, h.r * 100, h.c });
    }

    // persist cleaned graph
    {
        const cf = std.fs.createFileAbsolute(C ++ "grounded_clean.tsv", .{}) catch return;
        defer cf.close();
        var bw = std.io.bufferedWriter(cf.writer());
        for (kept.items) |e| bw.writer().print("{s}\t{s}\n", .{ e.x, e.y }) catch {};
        bw.flush() catch {};
        try o.print("\n  [persisted {d} cleaned edges → {s}grounded_clean.tsv]\n", .{ kept.items.len, C });
    }
}
