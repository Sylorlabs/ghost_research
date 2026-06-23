//! funnel_discover.zig — discover IS-A *direction* with no handed knowledge, via the FUNNEL.
//!
//! The wall (measured in compare_discovery): the "is a" frame appears but scores 50% on every
//! generality-based direction test. The machine can find the relation, not which word is the category.
//!
//! New signal — the FUNNEL: in a real IS-A frame, MANY specific words point to FEW general ones
//! (dog, cat, horse, lion → animal). So within a frame's own pair-graph, the hypernym side is the
//! CONCENTRATED side (few words, each reused as a hub) and the hyponym side is the DIVERSE side.
//! Per frame:  typeRatio(side) = distinct_words / total_pairs   (low = concentrated = hub = hypernym).
//! A frame is certified IS-A iff its two sides are asymmetrically concentrated; the DIRECTION is read
//! off the concentration (diverse → concentrated = hyponym → hypernym). Nothing is handed in: connectors
//! are found by frequency, frames by counting, IS-A-ness and direction by the funnel. WordNet grades only.
//!
//! Build: zig build-exe funnel_discover.zig -O ReleaseFast -femit-bin=/tmp/fun && /tmp/fun
const std = @import("std");
const C = "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/";
var A: std.mem.Allocator = undefined;
const PA = std.heap.page_allocator;

fn lo(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn fmt(comptime f: []const u8, a: anytype) []const u8 {
    return std.fmt.allocPrint(A, f, a) catch "?";
}

const MINC = 8;
const VMAX = 20000;
const FUNCN = 100; // connectors = top-100 most frequent words (discovered by frequency)
const FRAME_MIN = 120; // a frame must connect ≥ this many pairs to be judged
const FUNNEL_MIN = 0.18; // funnel pre-filter: |typeRatio(L) − typeRatio(R)| ≥ this (gives direction)
const EDGE_MIN = 2;
const SELF_MIN = 0.10; // balance coverage vs precision for the grounded knowledge base
const SELF_EDGES = 20; // a frame needs ≥ this many edges to judge self-closure

var corpus_paths: std.ArrayList([]const u8) = undefined;
var vocab: std.ArrayList([]const u8) = undefined;
var id_of: std.StringHashMap(u32) = undefined;

fn addDir(sub: []const u8) void {
    var d = std.fs.openDirAbsolute(fmt("{s}{s}", .{ C, sub }), .{ .iterate = true }) catch return;
    defer d.close();
    var it = d.iterate();
    while (it.next() catch null) |ent| {
        if (ent.kind != .file) continue;
        if (!std.mem.endsWith(u8, ent.name, ".txt")) continue;
        corpus_paths.append(fmt("{s}{s}/{s}", .{ C, sub, ent.name })) catch {};
    }
}
fn gatherCorpus() void {
    inline for (.{ "webster1913.txt", "gutenberg_dense.txt", "big_corpus.txt", "train_mix.txt", "moby_dick.txt", "shakespeare.txt", "tolstoy.txt", "austen.txt", "sherlock.txt", "ulysses.txt", "shelley.txt" }) |nm|
        corpus_paths.append(C ++ nm) catch {};
    addDir("bigcorpus");
    addDir("biglit");
}

fn countPath(freq: *std.StringHashMap(u32), path: []const u8) void {
    const f = std.fs.openFileAbsolute(path, .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(PA, 1 << 30) catch return;
    defer PA.free(buf);
    var tok = std.ArrayList(u8).init(A);
    defer tok.deinit();
    for (buf) |ch| {
        if (isAlpha(ch)) {
            tok.append(lo(ch)) catch {};
        } else {
            if (tok.items.len >= 1) {
                const e = freq.getOrPut(tok.items) catch unreachable;
                if (!e.found_existing) {
                    e.key_ptr.* = A.dupe(u8, tok.items) catch unreachable;
                    e.value_ptr.* = 0;
                }
                e.value_ptr.* += 1;
            }
            tok.clearRetainingCapacity();
        }
    }
}
fn countPass() !void {
    var freq = std.StringHashMap(u32).init(A);
    for (corpus_paths.items) |p| countPath(&freq, p);
    const WF = struct { w: []const u8, f: u32 };
    var all = std.ArrayList(WF).init(A);
    var it = freq.iterator();
    while (it.next()) |e| if (e.value_ptr.* >= MINC) all.append(.{ .w = e.key_ptr.*, .f = e.value_ptr.* }) catch {};
    std.mem.sort(WF, all.items, {}, struct {
        fn f(_: void, a: WF, b: WF) bool {
            return a.f > b.f;
        }
    }.f);
    const n = @min(all.items.len, VMAX);
    for (all.items[0..n]) |x| {
        const id: u32 = @intCast(vocab.items.len);
        vocab.append(x.w) catch {};
        id_of.put(x.w, id) catch {};
    }
}

// ── frame scanning (3 modes) ──
const Mode = enum { freq, sides, edges };
var frames: std.AutoHashMap(u32, u32) = undefined; // framecode → freq
var fnames: std.AutoHashMap(u32, []const u8) = undefined; // framecode → display name
var productive: std.AutoHashMap(u32, void) = undefined;
var sideL: std.AutoHashMap(u32, *std.AutoHashMap(u32, u32)) = undefined; // frame → left-word counts
var sideR: std.AutoHashMap(u32, *std.AutoHashMap(u32, u32)) = undefined;
var pairN: std.AutoHashMap(u32, u32) = undefined;
var certDir: std.AutoHashMap(u32, u8) = undefined; // 1 = L→R (R hub), 2 = R→L (L hub)
var ec: []std.AutoHashMap(u32, u32) = undefined; // hyponym → (hypernym → count)
var fedges: std.AutoHashMap(u32, *std.AutoHashMap(u64, u32)) = undefined; // frame → ((hypo*KMUL+hyper) → count)
var isaFrames: std.AutoHashMap(u32, void) = undefined; // frames that pass self-closure (true IS-A)
const KMUL: u64 = 1_000_000;

fn frameCode(p: []const u32) u32 {
    var code: u32 = @intCast(p.len);
    for (p) |r| code = code * 101 + (r + 1);
    return code;
}
fn frameName(p: []const u32) []const u8 {
    var s = std.ArrayList(u8).init(A);
    for (p, 0..) |r, k| {
        if (k > 0) s.append(' ') catch {};
        s.appendSlice(vocab.items[r]) catch {};
    }
    return s.items;
}
fn bumpInner(m: *std.AutoHashMap(u32, *std.AutoHashMap(u32, u32)), frame: u32, key: u32) void {
    const g = m.getOrPut(frame) catch return;
    if (!g.found_existing) {
        const inner = A.create(std.AutoHashMap(u32, u32)) catch return;
        inner.* = std.AutoHashMap(u32, u32).init(A);
        g.value_ptr.* = inner;
    }
    const e = g.value_ptr.*.getOrPut(key) catch return;
    if (!e.found_existing) e.value_ptr.* = 0;
    e.value_ptr.* += 1;
}
fn emitFrameEdge(code: u32, hypo: u32, hyper: u32) void {
    if (hypo == hyper) return;
    const g = fedges.getOrPut(code) catch return;
    if (!g.found_existing) {
        const inner = A.create(std.AutoHashMap(u64, u32)) catch return;
        inner.* = std.AutoHashMap(u64, u32).init(A);
        g.value_ptr.* = inner;
    }
    const key = @as(u64, hypo) * KMUL + @as(u64, hyper);
    const e = g.value_ptr.*.getOrPut(key) catch return;
    if (!e.found_existing) e.value_ptr.* = 0;
    e.value_ptr.* += 1;
}
fn scanPath(path: []const u8, mode: Mode) void {
    const f = std.fs.openFileAbsolute(path, .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(PA, 1 << 30) catch return;
    defer PA.free(buf);
    const NONE = std.math.maxInt(u32);
    var last: u32 = NONE;
    var pend: [3]u32 = undefined;
    var pn: usize = 0;
    // EDGES mode: after a certified copula frame, collect the noun-phrase HEAD = last content word of the
    // run before the next connector/boundary ("a american romantic comedy film" → film, not romantic).
    var coll = false;
    var c_subj: u32 = 0;
    var c_head: u32 = 0;
    var c_dir: u8 = 1;
    var c_code: u32 = 0;
    var line_emitted = false; // EDGES: only the FIRST copula per definition line yields an edge (the IS-A one)
    var tok = std.ArrayList(u8).init(A);
    defer tok.deinit();
    var i: usize = 0;
    while (i <= buf.len) : (i += 1) {
        const ch: u8 = if (i < buf.len) buf[i] else ' ';
        if (isAlpha(ch)) {
            tok.append(lo(ch)) catch {};
            continue;
        }
        const sent_break = (ch == '.' or ch == '\n' or ch == '!' or ch == '?' or ch == ';' or ch == ':');
        if (tok.items.len >= 1) {
            if (id_of.get(tok.items)) |t| {
                if (t < FUNCN) { // connector
                    if (coll) {
                        emitFrameEdge(c_code, c_subj, c_head);
                        coll = false;
                    } // NP head ended
                    if (last != NONE and pn < 3) {
                        pend[pn] = t;
                        pn += 1;
                    } else if (pn >= 3) {
                        last = NONE;
                        pn = 0;
                    }
                } else { // content word
                    if (last != NONE and pn >= 1) {
                        const code = frameCode(pend[0..pn]);
                        switch (mode) {
                            .freq => {
                                const g = frames.getOrPut(code) catch return;
                                if (!g.found_existing) {
                                    g.value_ptr.* = 0;
                                    fnames.put(code, frameName(pend[0..pn])) catch {};
                                }
                                g.value_ptr.* += 1;
                            },
                            .sides => if (productive.contains(code)) {
                                bumpInner(&sideL, code, last);
                                bumpInner(&sideR, code, t);
                                const e = pairN.getOrPut(code) catch return;
                                if (!e.found_existing) e.value_ptr.* = 0;
                                e.value_ptr.* += 1;
                            },
                            .edges => {
                                if (coll) {
                                    emitFrameEdge(c_code, c_subj, c_head);
                                    coll = false;
                                }
                                if (!line_emitted) if (certDir.get(code)) |dir| {
                                    c_dir = dir;
                                    c_code = code;
                                    c_subj = if (dir == 1) last else t;
                                    c_head = if (dir == 1) t else last;
                                    coll = true;
                                    line_emitted = true;
                                };
                            },
                        }
                    } else if (mode == .edges and coll and pn == 0 and last != NONE and c_dir == 1) {
                        c_head = t; // adjacent content word extends the NP head rightward
                    }
                    last = t;
                    pn = 0;
                }
            } else { // unknown word
                if (coll) {
                    emitFrameEdge(c_code, c_subj, c_head);
                    coll = false;
                }
                last = NONE;
                pn = 0;
            }
        }
        if (sent_break) {
            if (coll) {
                emitFrameEdge(c_code, c_subj, c_head);
                coll = false;
            }
            last = NONE;
            pn = 0;
        }
        if (ch == '\n') line_emitted = false; // new definition line → allow its first copula to fire
        tok.clearRetainingCapacity();
    }
    if (coll) emitFrameEdge(c_code, c_subj, c_head);
}

var isa: [][]u32 = undefined;
const FRow = struct { code: u32, name: []const u8, p: u32, trL: f64, trR: f64, asym: f64, dir: u8 };
fn topHub(side: u8, code: u32) []const u8 {
    const m = (if (side == 2) sideL else sideR).get(code) orelse return "";
    const WC = struct { w: u32, c: u32 };
    var l = std.ArrayList(WC).init(A);
    var it = m.iterator();
    while (it.next()) |e| l.append(.{ .w = e.key_ptr.*, .c = e.value_ptr.* }) catch {};
    std.mem.sort(WC, l.items, {}, struct {
        fn f(_: void, a: WC, b: WC) bool {
            return a.c > b.c;
        }
    }.f);
    var s = std.ArrayList(u8).init(A);
    for (l.items, 0..) |x, k| {
        if (k >= 6) break;
        if (k > 0) s.appendSlice(", ") catch {};
        s.appendSlice(vocab.items[x.w]) catch {};
    }
    return s.items;
}
fn runFunnel(o: anytype) !void {
    frames = std.AutoHashMap(u32, u32).init(A);
    fnames = std.AutoHashMap(u32, []const u8).init(A);
    productive = std.AutoHashMap(u32, void).init(A);
    sideL = std.AutoHashMap(u32, *std.AutoHashMap(u32, u32)).init(A);
    sideR = std.AutoHashMap(u32, *std.AutoHashMap(u32, u32)).init(A);
    pairN = std.AutoHashMap(u32, u32).init(A);
    certDir = std.AutoHashMap(u32, u8).init(A);

    for (corpus_paths.items) |p| scanPath(p, .freq);
    var it = frames.iterator();
    while (it.next()) |e| if (e.value_ptr.* >= FRAME_MIN) productive.put(e.key_ptr.*, {}) catch {};
    try o.print("  productive frames (≥{d} pairs): {d}\n", .{ FRAME_MIN, productive.count() });
    for (corpus_paths.items) |p| scanPath(p, .sides);

    // certify by funnel asymmetry
    var rows = std.ArrayList(FRow).init(A);
    var pit = productive.keyIterator();
    while (pit.next()) |code| {
        const P = pairN.get(code.*) orelse continue;
        if (P == 0) continue;
        const dL: f64 = @floatFromInt((sideL.get(code.*) orelse continue).count());
        const dR: f64 = @floatFromInt((sideR.get(code.*) orelse continue).count());
        const Pf: f64 = @floatFromInt(P);
        const trL = dL / Pf;
        const trR = dR / Pf;
        const asym = trL - trR;
        if (@abs(asym) < FUNNEL_MIN) continue;
        const dir: u8 = if (asym > 0) 1 else 2; // asym>0: L diverse→R concentrated (R hub) → L is-a R
        certDir.put(code.*, dir) catch {};
        rows.append(.{ .code = code.*, .name = fnames.get(code.*) orelse "?", .p = P, .trL = trL, .trR = trR, .asym = asym, .dir = dir }) catch {};
    }
    std.mem.sort(FRow, rows.items, {}, struct {
        fn f(_: void, a: FRow, b: FRow) bool {
            return @abs(a.asym) > @abs(b.asym);
        }
    }.f);
    try o.print("  CERTIFIED IS-A frames by funnel (top 18 by asymmetry; hubs = discovered hypernyms):\n", .{});
    for (rows.items, 0..) |r, k| {
        if (k >= 18) break;
        const arrow = if (r.dir == 1) "_ → [_]" else "[_] → _";
        try o.print("    \"_ {s} _\"  pairs={d}  funnel={d:.2}  {s}  hubs: {s}\n", .{ r.name, r.p, @abs(r.asym), arrow, topHub(r.dir, r.code) });
    }
    try o.print("    ({d} frames certified IS-A by funnel)\n", .{certDir.count()});

    // read edges per-frame (with NP-head extension) so we can test each frame's SELF-CLOSURE
    const V = vocab.items.len;
    fedges = std.AutoHashMap(u32, *std.AutoHashMap(u64, u32)).init(A);
    isaFrames = std.AutoHashMap(u32, void).init(A);
    for (corpus_paths.items) |p| scanPath(p, .edges);

    // SELF-CLOSURE: a frame is genuinely IS-A iff its objects (hypernyms) re-appear as its own subjects
    // (categories have their own definitions: "mammal" is object of dog→mammal AND subject of mammal→animal).
    // Relational frames (born-on, located-in, referred-to-as) do NOT self-close. This isolates IS-A — no hardcoding.
    const SC = struct { code: u32, name: []const u8, sc: f64, edges: u32 };
    var scrows = std.ArrayList(SC).init(A);
    var fit = fedges.iterator();
    while (fit.next()) |fe| {
        var subjects = std.AutoHashMap(u32, void).init(A);
        var objects = std.AutoHashMap(u32, void).init(A);
        var nedges: u32 = 0;
        var kit = fe.value_ptr.*.iterator();
        while (kit.next()) |e| {
            const hypo: u32 = @intCast(e.key_ptr.* / KMUL);
            const hyper: u32 = @intCast(e.key_ptr.* % KMUL);
            subjects.put(hypo, {}) catch {};
            objects.put(hyper, {}) catch {};
            nedges += e.value_ptr.*;
        }
        if (objects.count() == 0 or nedges < SELF_EDGES) continue;
        var inter: usize = 0;
        var oit = objects.keyIterator();
        while (oit.next()) |ob| if (subjects.contains(ob.*)) {
            inter += 1;
        };
        const sc = @as(f64, @floatFromInt(inter)) / @as(f64, @floatFromInt(objects.count()));
        if (sc >= SELF_MIN) {
            isaFrames.put(fe.key_ptr.*, {}) catch {};
            scrows.append(.{ .code = fe.key_ptr.*, .name = fnames.get(fe.key_ptr.*) orelse "?", .sc = sc, .edges = nedges }) catch {};
        }
    }
    std.mem.sort(SC, scrows.items, {}, struct {
        fn f(_: void, a: SC, b: SC) bool {
            return a.sc > b.sc;
        }
    }.f);
    try o.print("\n  SELF-CLOSURE certified IS-A frames (objects re-appear as subjects — the true copulas):\n", .{});
    for (scrows.items, 0..) |r, k| {
        if (k >= 18) break;
        try o.print("    \"_ {s} _\"  self-closure={d:.0}%  edges={d}\n", .{ r.name, r.sc * 100, r.edges });
    }
    try o.print("    ({d} of {d} funnel frames survive self-closure)\n", .{ isaFrames.count(), fedges.count() });

    // final graph = edges only from self-closure-certified IS-A frames
    ec = try A.alloc(std.AutoHashMap(u32, u32), V);
    for (0..V) |i| ec[i] = std.AutoHashMap(u32, u32).init(A);
    var iit = isaFrames.keyIterator();
    while (iit.next()) |code| {
        const inner = fedges.get(code.*) orelse continue;
        var kit = inner.iterator();
        while (kit.next()) |e| {
            const hypo: u32 = @intCast(e.key_ptr.* / KMUL);
            const hyper: u32 = @intCast(e.key_ptr.* % KMUL);
            const g = ec[hypo].getOrPut(hyper) catch continue;
            if (!g.found_existing) g.value_ptr.* = 0;
            g.value_ptr.* += e.value_ptr.*;
        }
    }
    isa = try A.alloc([]u32, V);
    const YC = struct { y: u32, c: u32 };
    for (0..V) |a| {
        var ys = std.ArrayList(YC).init(A);
        var eit = ec[a].iterator();
        while (eit.next()) |e| if (e.value_ptr.* >= EDGE_MIN) ys.append(.{ .y = e.key_ptr.*, .c = e.value_ptr.* }) catch {};
        std.mem.sort(YC, ys.items, {}, struct {
            fn f(_: void, x: YC, y: YC) bool {
                return x.c > y.c;
            }
        }.f);
        const keep = @min(ys.items.len, 3);
        const arr = A.alloc(u32, keep) catch {
            isa[a] = &[_]u32{};
            continue;
        };
        for (0..keep) |k| arr[k] = ys.items[k].y;
        isa[a] = arr;
    }
}

// ── WordNet grader ──
var wn_parents: std.AutoHashMap(u32, []u32) = undefined;
var wn_words_at: std.AutoHashMap(u32, [][]const u8) = undefined;
var wn_offs_of: std.StringHashMap([]u32) = undefined;
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
        _ = t.next();
        if (!std.mem.eql(u8, t.next() orelse "", "n")) continue;
        const wc = std.fmt.parseInt(usize, t.next() orelse continue, 16) catch continue;
        var wl = std.ArrayList([]const u8).init(A);
        var wi: usize = 0;
        while (wi < wc) : (wi += 1) {
            const wname = t.next() orelse break;
            _ = t.next();
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
fn reachesG(x: u32, y: u32) bool {
    var stack = std.ArrayList(u32).init(A);
    stack.append(x) catch return false;
    var seen = std.AutoHashMap(u32, void).init(A);
    var steps: usize = 0;
    while (stack.items.len > 0) {
        const cur = stack.pop() orelse break;
        steps += 1;
        if (steps > 8000) break;
        if (cur == y) return true;
        if (seen.contains(cur)) continue;
        seen.put(cur, {}) catch {};
        for (isa[cur]) |p| stack.append(p) catch {};
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
    corpus_paths = std.ArrayList([]const u8).init(A);
    vocab = std.ArrayList([]const u8).init(A);
    id_of = std.StringHashMap(u32).init(A);

    try o.print("=== FUNNEL DISCOVERY — discover IS-A direction from the hub structure (no handed knowledge) ===\n", .{});
    const args = try std.process.argsAlloc(A);
    if (args.len > 1) {
        for (args[1..]) |a| corpus_paths.append(a) catch {};
        try o.print("(corpus override: {d} path(s) from args)\n", .{args.len - 1});
    } else gatherCorpus();
    try o.print("corpus: {d} files · vocab≤{d} · connectors=top {d} · funnel≥{d:.2}\n\n", .{ corpus_paths.items.len, VMAX, FUNCN, FUNNEL_MIN });
    try o.print("[1] counting…\n", .{});
    try countPass();
    try o.print("    vocab {d}\n[2] funnel discovery…\n", .{vocab.items.len});
    try runFunnel(o);

    var edges: usize = 0;
    for (isa) |a| edges += a.len;
    try o.print("\n  sample chains:\n", .{});
    inline for (.{ "dog", "king", "knife", "horse", "whale", "oak", "rose", "lion", "sword", "wine", "gold", "doctor" }) |w| {
        if (id_of.get(w)) |x0| {
            var cur = x0;
            var out = std.ArrayList(u8).init(A);
            out.appendSlice(w) catch {};
            var depth: usize = 0;
            var seen = std.AutoHashMap(u32, void).init(A);
            while (depth < 8) : (depth += 1) {
                if (seen.contains(cur)) break;
                seen.put(cur, {}) catch {};
                if (isa[cur].len == 0) break;
                cur = isa[cur][0];
                out.appendSlice(" → ") catch {};
                out.appendSlice(vocab.items[cur]) catch {};
            }
            if (out.items.len > w.len) try o.print("    {s}\n", .{out.items}) else try o.print("    {s}  (none)\n", .{w});
        } else try o.print("    {s}  (not in vocab)\n", .{w});
    }

    try o.print("\n[3] grading vs WordNet…\n", .{});
    loadWordNet();
    if (!wn_loaded) {
        try o.print("WordNet absent.\n", .{});
        return;
    }
    var pcc: usize = 0;
    var ph: usize = 0;
    for (0..vocab.items.len) |a| {
        const x = vocab.items[a];
        for (isa[a]) |yid| {
            const y = vocab.items[yid];
            if (!wnHas(x) or !wnHas(y)) continue;
            pcc += 1;
            if (wnReaches(x, y)) ph += 1;
        }
    }
    var rc: usize = 0;
    var rh: usize = 0;
    var seen = std.StringHashMap(void).init(A);
    outer: for (vocab.items, 0..) |x, xi| {
        if (rc >= 4000) break;
        const offs = wn_offs_of.get(x) orelse continue;
        for (offs) |off| {
            if (wn_parents.get(off)) |ps| for (ps) |po| {
                if (wn_words_at.get(po)) |ws| for (ws) |y| {
                    if (std.mem.indexOfScalar(u8, y, ' ') != null) continue;
                    const yid = id_of.get(y) orelse continue;
                    if (yid == xi) continue;
                    const key = fmt("{s}|{s}", .{ x, y });
                    if (seen.contains(key)) continue;
                    seen.put(key, {}) catch {};
                    rc += 1;
                    if (reachesG(@intCast(xi), yid)) rh += 1;
                    if (rc >= 4000) break :outer;
                };
            };
        }
    }
    try o.print("\n════════════════════════ FUNNEL SCORECARD ════════════════════════\n", .{});
    try o.print("  edges {d} · concepts {d}\n", .{ edges, vocab.items.len });
    try o.print("  PRECISION  {d}/{d} = {d:.1}%\n", .{ ph, pcc, pct(ph, pcc) });
    try o.print("  RECALL     {d}/{d} = {d:.1}%\n", .{ rh, rc, pct(rh, rc) });
    try o.print("\n  reference: hand-patterns(HARDCODED) 36.9%/4.3% · frames-by-breadth 2%/8% · pure-structure 11%/0.7%\n", .{});

    // dump edges (subject<TAB>hypernym) for cross-source GROUNDING
    if (args.len > 2) {
        const df = std.fs.createFileAbsolute(args[2], .{}) catch null;
        if (df) |f| {
            defer f.close();
            var bw = std.io.bufferedWriter(f.writer());
            var n: usize = 0;
            for (0..vocab.items.len) |a| {
                var it = ec[a].iterator();
                while (it.next()) |e| if (e.value_ptr.* >= EDGE_MIN) {
                    bw.writer().print("{s}\t{s}\n", .{ vocab.items[a], vocab.items[e.key_ptr.*] }) catch {};
                    n += 1;
                };
            }
            bw.flush() catch {};
            try o.print("  [dumped {d} edges → {s}]\n", .{ n, args[2] });
        }
    }
}
