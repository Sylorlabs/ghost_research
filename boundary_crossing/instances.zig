//! instances.zig — INSTANCE-EXTENSION grounding for IS-A. The one text-derivable signal that is asymmetric BY
//! CONSTRUCTION: IS-A is extensional (set of dogs ⊆ set of animals), so mine instance→type assertions
//! ("Einstein is a physicist", "Einstein is a scientist") and verify T1 ⊆ T2 by SUBJECT-SET INCLUSION:
//! subjects(T1) ⊆ subjects(T2). No hardcoded structure — uniform measure over referents (the entities text
//! actually predicates types of), not over word co-occurrence (which was symmetric and failed).
//!
//! Reads definition corpora given as args (each line "Subject is/was/are ... Type ..."). Reports: corpus stats,
//! DECISIVE calibration on real pairs (is it asymmetric?), generator precision/recall vs WordNet with a threshold
//! sweep, and sample discovered edges WITH their instance evidence. WordNet grades only.
//! Build: zig build-exe instances.zig -O ReleaseFast -femit-bin=/tmp/inst && /tmp/inst <corpus.txt> [more...]
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
var A: std.mem.Allocator = undefined;
const PA = std.heap.page_allocator;

fn lc(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn isStop(w: []const u8) bool {
    inline for (.{ "a", "an", "the", "is", "are", "was", "were", "be", "been", "of", "to", "in", "on", "as", "by", "for", "with", "and", "or", "any", "one", "that", "which", "who", "whose", "used", "from", "at", "into", "it", "its", "this", "their", "such", "other", "also", "esp", "usually", "often", "typically", "generally", "first", "second", "now", "not", "his", "her", "its" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}
fn isBoundary(w: []const u8) bool {
    inline for (.{ "of", "that", "which", "who", "whose", "used", "with", "in", "on", "from", "for", "to", "by", "having", "consisting", "especially", "located", "found", "based", "known", "born", "made" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}

// subject and type id spaces
var sid: std.StringHashMap(u32) = undefined;
var ttab: std.ArrayList([]const u8) = undefined; // type id -> string
var tid: std.StringHashMap(u32) = undefined;
fn internS(w: []const u8) u32 {
    const g = sid.getOrPut(w) catch unreachable;
    if (!g.found_existing) {
        g.key_ptr.* = A.dupe(u8, w) catch unreachable;
        g.value_ptr.* = sid.count() - 1;
    }
    return g.value_ptr.*;
}
fn internT(w: []const u8) u32 {
    const g = tid.getOrPut(w) catch unreachable;
    if (!g.found_existing) {
        const d = A.dupe(u8, w) catch unreachable;
        g.key_ptr.* = d;
        g.value_ptr.* = @intCast(ttab.items.len);
        ttab.append(d) catch unreachable;
    }
    return g.value_ptr.*;
}

// subjectsOf[type] = set of subject ids ; typesOf[subject] = list of type ids
var subjectsOf: std.AutoHashMap(u32, *std.AutoHashMap(u32, void)) = undefined;
var typesOf: std.AutoHashMap(u32, *std.ArrayList(u32)) = undefined;
var n_assert: usize = 0;
fn addAssertion(s: u32, t: u32) void {
    const so = subjectsOf.getOrPut(t) catch return;
    if (!so.found_existing) {
        const m = A.create(std.AutoHashMap(u32, void)) catch return;
        m.* = std.AutoHashMap(u32, void).init(A);
        so.value_ptr.* = m;
    }
    const r = so.value_ptr.*.getOrPut(s) catch return;
    if (r.found_existing) return; // already have this (subject,type)
    n_assert += 1;
    const to = typesOf.getOrPut(s) catch return;
    if (!to.found_existing) {
        const l = A.create(std.ArrayList(u32)) catch return;
        l.* = std.ArrayList(u32).init(A);
        to.value_ptr.* = l;
    }
    to.value_ptr.*.append(t) catch {};
}

fn mineFile(path: []const u8) void {
    const f = std.fs.openFileAbsolute(path, .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(PA, 8 << 30) catch return;
    defer PA.free(buf);
    var lines = std.mem.splitScalar(u8, buf, '\n');
    var toks = std.ArrayList([]const u8).init(A); // slices into lbuf (reused per line — no per-token arena dupes)
    var lbuf = std.ArrayList(u8).init(A);
    while (lines.next()) |line| {
        toks.clearRetainingCapacity();
        lbuf.clearRetainingCapacity();
        for (line) |ch| lbuf.append(if (isAlpha(ch)) lc(ch) else ' ') catch {};
        var sp = std.mem.tokenizeScalar(u8, lbuf.items, ' ');
        while (sp.next()) |w| toks.append(w) catch {};
        if (toks.items.len < 3) continue;
        // copula position
        var k: usize = 1;
        while (k < toks.items.len and !(std.mem.eql(u8, toks.items[k], "is") or std.mem.eql(u8, toks.items[k], "are") or std.mem.eql(u8, toks.items[k], "was") or std.mem.eql(u8, toks.items[k], "were"))) : (k += 1) {}
        if (k == 0 or k >= toks.items.len - 1 or k > 6) continue; // copula must be early (definitional)
        // subject = everything before copula, joined (the entity)
        var sb = std.ArrayList(u8).init(A);
        for (toks.items[0..k], 0..) |w, i| {
            if (i > 0) sb.append(' ') catch {};
            sb.appendSlice(w) catch {};
        }
        if (sb.items.len < 2) continue;
        const s = internS(sb.items);
        // types = content words after copula until a boundary, cap 5 (keep across and/or = co-types)
        var taken: usize = 0;
        var j = k + 1;
        while (j < toks.items.len and taken < 5) : (j += 1) {
            const w = toks.items[j];
            if (isBoundary(w)) break;
            if (isStop(w) or w.len < 3) continue;
            addAssertion(s, internT(w));
            taken += 1;
        }
    }
}

fn subjCount(t: u32) usize {
    if (subjectsOf.get(t)) |m| return m.count();
    return 0;
}
// inclusion(T1→T2) = |subjects(T1) ∩ subjects(T2)| / |subjects(T1)|
fn inclusion(t1: u32, t2: u32) f64 {
    const m1 = subjectsOf.get(t1) orelse return 0;
    const m2 = subjectsOf.get(t2) orelse return 0;
    if (m1.count() == 0) return 0;
    var inter: usize = 0;
    var it = m1.keyIterator();
    while (it.next()) |s| if (m2.contains(s.*)) {
        inter += 1;
    };
    return @as(f64, @floatFromInt(inter)) / @as(f64, @floatFromInt(m1.count()));
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

// generate IS-A edges by instance inclusion, at given thresholds; return precision/recall vs WordNet
const Edge = struct { a: u32, b: u32, incl: f64, inter: usize };
fn generate(minsup: usize, incl_t: f64, asym: f64, out: ?*std.ArrayList(Edge)) [4]usize {
    var prec_c: usize = 0;
    var prec_h: usize = 0;
    // for each type with enough subjects, find supercategory candidates via co-typed subjects
    var cand = std.AutoHashMap(u32, u32).init(A);
    var it = subjectsOf.iterator();
    while (it.next()) |e| {
        const t1 = e.key_ptr.*;
        const subs = e.value_ptr.*;
        if (subs.count() < minsup) continue;
        cand.clearRetainingCapacity();
        var si = subs.keyIterator();
        var seen_s: usize = 0;
        while (si.next()) |s| {
            seen_s += 1;
            if (seen_s > 4000) break; // cap work for huge types
            if (typesOf.get(s.*)) |ts| for (ts.items) |t2| {
                if (t2 == t1) continue;
                const g = cand.getOrPut(t2) catch continue;
                if (!g.found_existing) g.value_ptr.* = 0;
                g.value_ptr.* += 1;
            };
        }
        const n1 = subs.count();
        var ci = cand.iterator();
        while (ci.next()) |ce| {
            const t2 = ce.key_ptr.*;
            const inter = ce.value_ptr.*;
            if (inter < 2) continue;
            const inc12 = @as(f64, @floatFromInt(inter)) / @as(f64, @floatFromInt(n1));
            if (inc12 < incl_t) continue;
            const n2 = subjCount(t2);
            if (n2 == 0) continue;
            const inc21 = @as(f64, @floatFromInt(inter)) / @as(f64, @floatFromInt(n2));
            if (inc12 < asym * inc21) continue; // asymmetric: t1 more specific (contained in t2)
            // graded edge t1 -> t2
            const x = ttab.items[t1];
            const y = ttab.items[t2];
            if (wnHas(x) and wnHas(y)) {
                prec_c += 1;
                if (wnReaches(x, y)) prec_h += 1;
            }
            if (out) |o| o.append(.{ .a = t1, .b = t2, .incl = inc12, .inter = inter }) catch {};
        }
    }
    return .{ prec_h, prec_c, 0, 0 };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();
    sid = std.StringHashMap(u32).init(A);
    tid = std.StringHashMap(u32).init(A);
    ttab = std.ArrayList([]const u8).init(A);
    subjectsOf = std.AutoHashMap(u32, *std.AutoHashMap(u32, void)).init(A);
    typesOf = std.AutoHashMap(u32, *std.ArrayList(u32)).init(A);

    const args = try std.process.argsAlloc(A);
    try o.print("=== INSTANCE-EXTENSION grounding for IS-A (asymmetric by construction; no hardcoded structure) ===\n", .{});
    if (args.len < 2) {
        try o.print("usage: instances <corpus.txt> [more...]\n", .{});
        return;
    }
    try o.print("[1] mining instance→type assertions from {d} corpus file(s)…\n", .{args.len - 1});
    for (args[1..]) |p| mineFile(p);
    loadWordNet();
    try o.print("    subjects(entities) {d} · types {d} · assertions {d}\n\n", .{ sid.count(), ttab.items.len, n_assert });

    // ── DECISIVE CALIBRATION: is instance-inclusion ASYMMETRIC on real IS-A pairs? ──
    try o.print("──────── DECISIVE CALIBRATION: incl(hyponym→hypernym) / incl(hypernym→hyponym) ────────\n", .{});
    try o.print("  (instance-extension predicts the FIRST clearly higher — every X that is T1 is also T2)\n", .{});
    inline for (.{ .{ "physicist", "scientist" }, .{ "dog", "animal" }, .{ "city", "place" }, .{ "poet", "writer" }, .{ "actor", "person" }, .{ "village", "settlement" }, .{ "island", "land" }, .{ "river", "stream" }, .{ "painter", "artist" }, .{ "novel", "book" }, .{ "dog", "mammal" }, .{ "town", "place" } }) |pr| {
        const a = tid.get(pr[0]);
        const b = tid.get(pr[1]);
        if (a != null and b != null) {
            try o.print("    {s:<11}→ {s:<11}:  {d:.3} / {d:.3}   (|subj| {d} / {d})\n", .{ pr[0], pr[1], inclusion(a.?, b.?), inclusion(b.?, a.?), subjCount(a.?), subjCount(b.?) });
        } else try o.print("    {s:<11}→ {s:<11}:  (missing: {s})\n", .{ pr[0], pr[1], if (a == null) pr[0] else pr[1] });
    }

    // ── DIRECTIONALITY ACCURACY: over WordNet IS-A pairs present in our data, does instance-inclusion orient
    //    them correctly (incl(hyponym→hypernym) > incl(hypernym→hyponym))? The clean aggregate asymmetry test. ──
    try o.print("\n──────── DIRECTIONALITY ACCURACY on WordNet IS-A pairs (minsup 5) ────────\n", .{});
    {
        const minsup: usize = 5;
        var correct: usize = 0;
        var backwards: usize = 0;
        var tie: usize = 0;
        var nojudge: usize = 0;
        var seen = std.AutoHashMap(u64, void).init(A);
        for (0..ttab.items.len) |t1| {
            if (subjCount(@intCast(t1)) < minsup) continue;
            const x = ttab.items[t1];
            const offs = wn_offs_of.get(x) orelse continue;
            for (offs) |off| {
                const ps = wn_parents.get(off) orelse continue;
                for (ps) |po| {
                    const ws = wn_words_at.get(po) orelse continue;
                    for (ws) |y| {
                        const t2 = tid.get(y) orelse continue;
                        if (t2 == t1 or subjCount(t2) < minsup) continue;
                        const key = @as(u64, @intCast(t1)) * 1000003 + @as(u64, t2);
                        if (seen.contains(key)) continue;
                        seen.put(key, {}) catch {};
                        const fwd = inclusion(@intCast(t1), t2); // hyponym → hypernym (should be higher)
                        const rev = inclusion(t2, @intCast(t1));
                        if (fwd == 0 and rev == 0) {
                            nojudge += 1;
                        } else if (fwd > rev * 1.05) {
                            correct += 1;
                        } else if (rev > fwd * 1.05) {
                            backwards += 1;
                        } else tie += 1;
                    }
                }
            }
        }
        const decisive = correct + backwards;
        try o.print("  decisive pairs {d}  ·  CORRECT {d} ({d:.1}%)  ·  backwards {d}  ·  tie {d}  ·  no-overlap {d}\n", .{ decisive, correct, pct(correct, decisive), backwards, tie, nojudge });
        try o.print("  (50%% = no usable direction; >50%% = instance-inclusion carries real IS-A direction)\n", .{});
    }

    // ── GENERATOR: discover IS-A edges by instance inclusion; threshold sweep (lots of data) ──
    try o.print("\n──────── GENERATOR precision vs WordNet — threshold sweep ────────\n", .{});
    try o.print("  {s:>7} {s:>7} {s:>6}  {s:>14}\n", .{ "minsup", "incl", "asym", "precision" });
    for ([_]usize{ 3, 5, 10 }) |ms| {
        for ([_]f64{ 0.4, 0.5, 0.6, 0.7 }) |it| {
            const r = generate(ms, it, 1.2, null);
            try o.print("  {d:>7} {d:>7.2} {d:>6.1}  {d:>6}/{d:<6} = {d:.1}%\n", .{ ms, it, @as(f64, 1.2), r[0], r[1], pct(r[0], r[1]) });
        }
    }

    // ── sample discovered edges WITH instance evidence, at a balanced setting ──
    try o.print("\n──────── sample DISCOVERED IS-A edges (minsup 5, incl 0.6) with instance evidence ────────\n", .{});
    var edges = std.ArrayList(Edge).init(A);
    _ = generate(5, 0.6, 1.2, &edges);
    std.mem.sort(Edge, edges.items, {}, struct {
        fn lt(_: void, x: Edge, y: Edge) bool {
            return x.inter > y.inter;
        }
    }.lt);
    var shown: usize = 0;
    for (edges.items) |e| {
        if (shown >= 25) break;
        const x = ttab.items[e.a];
        const y = ttab.items[e.b];
        const wn = if (wnHas(x) and wnHas(y) and wnReaches(x, y)) "✓" else " ";
        // pull up to 3 shared instances as evidence
        var ev = std.ArrayList(u8).init(A);
        const m1 = subjectsOf.get(e.a).?;
        const m2 = subjectsOf.get(e.b).?;
        var n: usize = 0;
        var mi = m1.keyIterator();
        while (mi.next()) |s| {
            if (n >= 3) break;
            if (m2.contains(s.*)) {
                // find subject name
                var nameit = sid.iterator();
                while (nameit.next()) |se| if (se.value_ptr.* == s.*) {
                    if (n > 0) ev.appendSlice(", ") catch {};
                    ev.appendSlice(se.key_ptr.*) catch {};
                    n += 1;
                    break;
                };
            }
        }
        try o.print("  [{s}] {s} → {s}  (incl {d:.2}, {d} shared: {s})\n", .{ wn, x, y, e.incl, e.inter, ev.items });
        shown += 1;
    }
    try o.print("\n  total edges proposed at (minsup5, incl0.6): {d}\n", .{edges.items.len});
}
