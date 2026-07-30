//! discover_isa.zig — DISCOVER the IS-A hierarchy from raw text with ZERO hand-given linguistic knowledge.
//! No Hearst patterns, no part-of-speech list, no stop-word list, no dictionary genus rules. The ONLY
//! mechanism is: split bytes into words (lowercase, letters), then let the STRUCTURE reveal itself from how
//! words distribute. The machine must recognize how concepts relate on its own.
//!
//! Signal (Distributional Inclusion Hypothesis, Weeds & Weir): a hyponym occurs in a SUBSET of the contexts
//! its hypernym occurs in. So "x is-a y" when y's context-meaning CONTAINS x's (asymmetric inclusion).
//!   • context = neighbor words in a ±W window (discovered co-occurrence, not parsed grammar)
//!   • weight  = PPMI (kills function-word glue automatically — they associate with nothing selectively)
//!   • IS-A    = Cincl(x→y) high AND Cincl(x→y) > Cincl(y→x)   (y is the broader, containing concept)
//! It COMMITS (knower) only above a certification threshold; otherwise it abstains. Nothing is handed to it.
//!
//! WordNet is loaded ONLY to grade precision/recall (full hypernym closure); never to answer.
//! Build: zig build-exe discover_isa.zig -O ReleaseFast -femit-bin=/tmp/disc && /tmp/disc
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

// ── tunables (reported, not linguistic knowledge) ──
const W = 3; // context window radius
const MINC = 25; // min word frequency to enter vocab (stable statistics)
const VMAX = 7000; // cap vocab to top-N by frequency (keeps inclusion O(V·cands·topF) tractable)
const TOPF = 60; // keep each word's top-PPMI features
const CERT_INCL = 0.22; // certify: x's meaning at least this covered by y
const CERT_ASYM = 1.15; // certify: and y is at least this much broader than x is of y
const MIN_SHARED = 4; // need at least this many shared context features

// ── corpus → word-id stream ──
var vocab: std.ArrayList([]const u8) = undefined; // id → word
var id_of: std.StringHashMap(u32) = undefined; // word → id
const FILES = .{ "webster1913.txt", "gutenberg_dense.txt", "moby_dick.txt", "shakespeare.txt", "tolstoy.txt", "austen.txt", "sherlock.txt" };

fn countFile(freq: *std.StringHashMap(u32), fnm: []const u8) void {
    const f = std.fs.openFileAbsolute(fmt("{s}{s}", .{ C, fnm }), .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    var tok = std.ArrayList(u8).init(A);
    for (buf) |ch| {
        if (isAlpha(ch)) {
            tok.append(lo(ch)) catch {};
        } else {
            if (tok.items.len >= 2) {
                const e = freq.getOrPut(tok.items) catch unreachable;
                if (!e.found_existing) {
                    e.key_ptr.* = A.dupe(u8, tok.items) catch unreachable;
                    e.value_ptr.* = 0;
                }
                e.value_ptr.* += 1;
            }
            tok = std.ArrayList(u8).init(A);
        }
    }
}
fn countPass() !void {
    var freq = std.StringHashMap(u32).init(A);
    inline for (FILES) |fnm| countFile(&freq, fnm);
    // keep words with freq ≥ MINC, take top VMAX by freq
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

// ── co-occurrence among vocab words (±W window) ──
var co: []std.AutoHashMap(u32, u32) = undefined; // id → (neighbor id → count)
var tot: []f64 = undefined; // id → total co-occurrence mass
var Ntot: f64 = 0;
fn coPass() !void {
    const V = vocab.items.len;
    co = try A.alloc(std.AutoHashMap(u32, u32), V);
    tot = try A.alloc(f64, V);
    for (0..V) |i| {
        co[i] = std.AutoHashMap(u32, u32).init(A);
        tot[i] = 0;
    }
    inline for (FILES) |fnm| coFile(fnm);
}
fn coFile(fnm: []const u8) void {
    const f = std.fs.openFileAbsolute(fmt("{s}{s}", .{ C, fnm }), .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    var ring: [2 * W]u32 = undefined;
    var rn: usize = 0; // how many valid ids seen (ring index)
    var tok = std.ArrayList(u8).init(A);
    var i: usize = 0;
    while (i <= buf.len) : (i += 1) {
        const ch: u8 = if (i < buf.len) buf[i] else ' ';
        if (isAlpha(ch)) {
            tok.append(lo(ch)) catch {};
            continue;
        }
        if (tok.items.len >= 2) {
            if (id_of.get(tok.items)) |a| {
                const back = @min(rn, 2 * W);
                var k: usize = 0;
                while (k < back) : (k += 1) {
                    const b = ring[(rn - 1 - k) % (2 * W)];
                    const ea = co[a].getOrPut(b) catch break;
                    if (!ea.found_existing) ea.value_ptr.* = 0;
                    ea.value_ptr.* += 1;
                    const eb = co[b].getOrPut(a) catch break;
                    if (!eb.found_existing) eb.value_ptr.* = 0;
                    eb.value_ptr.* += 1;
                    tot[a] += 1;
                    tot[b] += 1;
                    Ntot += 2;
                }
                ring[rn % (2 * W)] = a;
                rn += 1;
            }
        } else {
            if (ch == '.' or ch == '\n' or ch == '!' or ch == '?') rn = 0;
        }
        tok = std.ArrayList(u8).init(A);
    }
}

// ── PPMI top-feature profiles ──
var prof: []std.AutoHashMap(u32, f32) = undefined; // id → (feature id → ppmi), top-TOPF only
var pmass: []f64 = undefined; // id → sum of kept ppmi
fn ppmi(a: u32, f: u32, caf: u32) f32 {
    const v = (@as(f64, @floatFromInt(caf)) * Ntot) / (tot[a] * tot[f]);
    if (v <= 1.0) return 0;
    return @floatCast(@log(v));
}
fn buildProfiles() !void {
    const V = vocab.items.len;
    prof = try A.alloc(std.AutoHashMap(u32, f32), V);
    pmass = try A.alloc(f64, V);
    const FW = struct { f: u32, w: f32 };
    for (0..V) |a| {
        var list = std.ArrayList(FW).init(A);
        var it = co[a].iterator();
        while (it.next()) |e| {
            const p = ppmi(@intCast(a), e.key_ptr.*, e.value_ptr.*);
            if (p > 0) list.append(.{ .f = e.key_ptr.*, .w = p }) catch {};
        }
        std.mem.sort(FW, list.items, {}, struct {
            fn f(_: void, x: FW, y: FW) bool {
                return x.w > y.w;
            }
        }.f);
        prof[a] = std.AutoHashMap(u32, f32).init(A);
        pmass[a] = 0;
        const n = @min(list.items.len, TOPF);
        for (list.items[0..n]) |x| {
            prof[a].put(x.f, x.w) catch {};
            pmass[a] += x.w;
        }
    }
}

// ── inverted index: feature → [(word, ppmi)] from top profiles ──
const Posting = struct { w: u32, p: f32 };
var inv: std.AutoHashMap(u32, std.ArrayList(Posting)) = undefined;
fn buildInverted() !void {
    inv = std.AutoHashMap(u32, std.ArrayList(Posting)).init(A);
    for (0..vocab.items.len) |a| {
        var it = prof[a].iterator();
        while (it.next()) |e| {
            const g = inv.getOrPut(e.key_ptr.*) catch continue;
            if (!g.found_existing) g.value_ptr.* = std.ArrayList(Posting).init(A);
            g.value_ptr.*.append(.{ .w = @intCast(a), .p = e.value_ptr.* }) catch {};
        }
    }
}

// ── discover best hypernym(s) per word via asymmetric inclusion ──
var isa: [][]u32 = undefined; // id → certified hypernym ids (best first)
const Cand = struct { shared: u32, numx: f64, numy: f64 };
fn discover() !void {
    const V = vocab.items.len;
    isa = try A.alloc([]u32, V);
    var cand = std.AutoHashMap(u32, Cand).init(A);
    const Scored = struct { y: u32, incl: f32, score: f32 };
    for (0..V) |a| {
        cand.clearRetainingCapacity();
        var it = prof[a].iterator();
        while (it.next()) |e| {
            const wx = e.value_ptr.*;
            const post = inv.get(e.key_ptr.*) orelse continue;
            for (post.items) |pp| {
                if (pp.w == a) continue;
                const g = cand.getOrPut(pp.w) catch continue;
                if (!g.found_existing) g.value_ptr.* = .{ .shared = 0, .numx = 0, .numy = 0 };
                g.value_ptr.*.shared += 1;
                g.value_ptr.*.numx += wx;
                g.value_ptr.*.numy += pp.p;
            }
        }
        var best = std.ArrayList(Scored).init(A);
        var cit = cand.iterator();
        while (cit.next()) |e| {
            const c = e.value_ptr.*;
            if (c.shared < MIN_SHARED) continue;
            const inclXY: f32 = @floatCast(c.numx / (pmass[a] + 1e-9));
            const inclYX: f32 = @floatCast(c.numy / (pmass[e.key_ptr.*] + 1e-9));
            if (inclXY < CERT_INCL) continue;
            if (inclXY < CERT_ASYM * inclYX) continue; // y must be the broader/containing concept
            best.append(.{ .y = e.key_ptr.*, .incl = inclXY, .score = inclXY * (inclXY - inclYX) }) catch {};
        }
        std.mem.sort(Scored, best.items, {}, struct {
            fn f(_: void, x: Scored, y: Scored) bool {
                return x.score > y.score;
            }
        }.f);
        const keep = @min(best.items.len, 3);
        const arr = A.alloc(u32, keep) catch {
            isa[a] = &[_]u32{};
            continue;
        };
        for (0..keep) |k| arr[k] = best.items[k].y;
        isa[a] = arr;
    }
}
fn chainStr(x: []const u8) ?[]const u8 {
    var cur = id_of.get(x) orelse return null;
    var out = std.ArrayList(u8).init(A);
    out.appendSlice(x) catch {};
    var depth: usize = 0;
    var seen = std.AutoHashMap(u32, void).init(A);
    while (depth < 10) : (depth += 1) {
        if (seen.contains(cur)) break;
        seen.put(cur, {}) catch {};
        if (isa[cur].len == 0) break;
        cur = isa[cur][0];
        out.appendSlice(" → ") catch {};
        out.appendSlice(vocab.items[cur]) catch {};
    }
    return if (out.items.len > x.len) out.items else null;
}
fn reaches(xs: []const u8, ys: []const u8) bool {
    const x = id_of.get(xs) orelse return false;
    const y = id_of.get(ys) orelse return false;
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

// ─────────────────── WordNet — grade only ───────────────────
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
fn pct(a: usize, b: usize) f64 {
    return if (b == 0) 0 else 100.0 * @as(f64, @floatFromInt(a)) / @as(f64, @floatFromInt(b));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();
    vocab = std.ArrayList([]const u8).init(A);
    id_of = std.StringHashMap(u32).init(A);

    try o.print("=== DISCOVER IS-A — zero hand-given linguistic knowledge (no patterns, no POS, no stoplist) ===\n", .{});
    try o.print("config: window±{d}, min-freq {d}, vocab≤{d}, top-{d} features, certify incl≥{d:.2} asym≥{d:.2}\n\n", .{ W, MINC, VMAX, TOPF, CERT_INCL, CERT_ASYM });
    try o.print("[1] counting words…\n", .{});
    try countPass();
    try o.print("    vocab = {d} words (top by frequency)\n", .{vocab.items.len});
    try o.print("[2] co-occurrence (±{d})…\n", .{W});
    try coPass();
    try o.print("[3] PPMI top-{d} profiles…\n", .{TOPF});
    try buildProfiles();
    try buildInverted();
    try o.print("[4] discovering hypernyms by asymmetric inclusion…\n", .{});
    try discover();
    var edges: usize = 0;
    for (isa) |a| edges += a.len;
    try o.print("    discovered {d} certified IS-A edges over {d} concepts\n\n", .{ edges, vocab.items.len });

    try o.print("── sample DISCOVERED chains (nothing handed) ──\n", .{});
    inline for (.{ "dog", "king", "knife", "horse", "whale", "oak", "rose", "computer", "lion", "ship", "doctor", "iron", "sword", "wine", "house" }) |w| {
        if (chainStr(w)) |ch| try o.print("  {s}\n", .{ch}) else try o.print("  {s}  (no hypernym discovered)\n", .{w});
    }

    try o.print("\n[5] grading vs WordNet (grade only)…\n", .{});
    loadWordNet();
    if (!wn_loaded) {
        try o.print("  WordNet absent — cannot grade.\n", .{});
        return;
    }
    // precision: of our DIRECT edges with both endpoints in WordNet, fraction WordNet's closure confirms
    var pc: usize = 0;
    var ph: usize = 0;
    var fails: usize = 0;
    try o.print("  precision failures (discovered edges WordNet rejects):\n", .{});
    for (0..vocab.items.len) |a| {
        const x = vocab.items[a];
        for (isa[a]) |yid| {
            const y = vocab.items[yid];
            if (!wnHas(x) or !wnHas(y)) continue;
            pc += 1;
            if (wnReaches(x, y)) {
                ph += 1;
            } else if (fails < 20) {
                try o.print("      ✗ {s} → {s}\n", .{ x, y });
                fails += 1;
            }
        }
    }
    // recall: WordNet direct edges among our vocab, fraction we reach
    var rc: usize = 0;
    var rh: usize = 0;
    var seen = std.StringHashMap(void).init(A);
    outer: for (vocab.items) |x| {
        if (rc >= 4000) break;
        const offs = wn_offs_of.get(x) orelse continue;
        for (offs) |off| {
            if (wn_parents.get(off)) |ps| for (ps) |po| {
                if (wn_words_at.get(po)) |ws| for (ws) |y| {
                    if (std.mem.indexOfScalar(u8, y, ' ') != null) continue;
                    if (!id_of.contains(y) or std.mem.eql(u8, x, y)) continue;
                    const key = fmt("{s}|{s}", .{ x, y });
                    if (seen.contains(key)) continue;
                    seen.put(key, {}) catch {};
                    rc += 1;
                    if (reaches(x, y)) rh += 1;
                    if (rc >= 4000) break :outer;
                };
            };
        }
    }
    try o.print("\n════════════════ DISCOVERY SCORECARD ════════════════\n", .{});
    try o.print("  edges {d} · concepts {d}\n", .{ edges, vocab.items.len });
    try o.print("  PRECISION  {d}/{d} = {d:.1}%   (vs hardcoded-Hearst baseline 36.9%)\n", .{ ph, pc, pct(ph, pc) });
    try o.print("  RECALL     {d}/{d} = {d:.1}%   (vs hardcoded-Hearst baseline 4.3%, scoped to top-{d} vocab)\n", .{ rh, rc, pct(rh, rc), VMAX });
    try o.print("\n  NB: every edge here was DISCOVERED from distribution. No pattern, POS, or list was handed in.\n", .{});
}
