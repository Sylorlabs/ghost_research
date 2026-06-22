//! concept_learn.zig — LEARN the concept graph (IS-A + HAS-PART) from a raw text corpus, instead of being handed
//! WordNet's pre-built ontology. The machine derives the structure itself by general patterns, then CERTIFIES it.
//! No handed graph, no LLM. This is the measurement probe: mine, then report quality (and WordNet recall as a
//! throwaway yardstick we then discard).
//!
//! IS-A is learned from two general patterns over text:
//!   • definition-genus: a dictionary entry's gloss head IS the kind ("Knife: an instrument …" → knife is-a instrument)
//!   • Hearst patterns: "Y such as X", "X and/or other Y", "Y including/especially X"  (Hearst 1992)
//! HAS-PART is learned from possessives ("the king's crown" → king has-part crown) and "made/consists of".
//! A relation is CERTIFIED only with enough independent evidence; the rest is dropped (we'd rather refuse than guess).
//!
//! Build: zig build-exe concept_learn.zig -O ReleaseFast -femit-bin=/tmp/cl && /tmp/cl
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
fn isStop(w: []const u8) bool {
    inline for (.{ "the", "a", "an", "of", "to", "in", "on", "as", "by", "for", "with", "and", "or", "is", "are", "was", "were", "be", "been", "it", "its", "this", "that", "these", "those", "which", "who", "such", "other", "some", "any", "all", "one", "two", "his", "her", "their", "they", "he", "she", "you", "we", "i", "not", "no", "but", "from", "at", "into", "out", "up", "so", "if", "then", "than", "them", "him", "me", "my", "your" }) |s|
        if (std.mem.eql(u8, w, s)) return true;
    return false;
}

// ── evidence maps: hyponym → (hypernym → count), owner → (part → count) ──
const Inner = std.StringHashMap(u32);
var isa_ev: std.StringHashMap(*Inner) = undefined;
var part_ev: std.StringHashMap(*Inner) = undefined;
fn bump(m: *std.StringHashMap(*Inner), a: []const u8, b: []const u8, w: u32) void {
    if (a.len < 3 or b.len < 3 or std.mem.eql(u8, a, b)) return;
    const e = m.getOrPut(a) catch return;
    if (!e.found_existing) {
        const inner = A.create(Inner) catch return;
        inner.* = Inner.init(A);
        e.key_ptr.* = A.dupe(u8, a) catch return;
        e.value_ptr.* = inner;
    }
    const ie = e.value_ptr.*.getOrPut(b) catch return;
    if (!ie.found_existing) {
        ie.key_ptr.* = A.dupe(u8, b) catch return;
        ie.value_ptr.* = 0;
    }
    ie.value_ptr.* += w;
}

// ─────────────────────────── Webster: definition-genus IS-A ───────────────────────────
var dict_words: std.StringHashMap(void) = undefined; // headword set, used as a "is this a real noun" filter
fn isHeadword(line: []const u8) bool {
    if (line.len < 2 or line.len > 40) return false;
    var letters: usize = 0;
    for (line) |c| {
        if (c >= 'a' and c <= 'z') return false;
        if (c >= 'A' and c <= 'Z') letters += 1 else if (c == ' ' or c == '-' or c == '\'' or c == ';' or c == ',' or c == '.' or (c >= '0' and c <= '9')) {} else return false;
    }
    return letters >= 2;
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
    return head;
}
fn extractGloss(body: []const u8) []const u8 {
    var marker: ?usize = null;
    var start: usize = 0;
    if (std.mem.indexOf(u8, body, "Defn:")) |d| {
        marker = d;
        start = d + 5;
    }
    var i: usize = 0;
    while (i + 2 < body.len) : (i += 1) if ((i == 0 or body[i - 1] == '\n') and body[i] == '1' and body[i + 1] == '.' and body[i + 2] == ' ') {
        if (marker == null or i < marker.?) start = i + 2;
        break;
    };
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
        if (out.items.len > 300) break;
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
// genus = head of the FIRST ';'-clause (the primary kind)
fn extractGenus(gloss: []const u8) []const u8 {
    var clauses = std.mem.tokenizeScalar(u8, gloss, ';');
    const first = clauses.next() orelse return "";
    return headOf(std.mem.trim(u8, first, " ,."));
}
fn loadWebster() void {
    const f = std.fs.openFileAbsolute(C ++ "webster1913.txt", .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    var lines = std.mem.splitScalar(u8, buf, '\n');
    var cur: ?[]const u8 = null;
    var bstart: usize = 0;
    var pos: usize = 0;
    var heads = std.ArrayList(struct { w: []const u8, s: usize }).init(A);
    while (lines.next()) |line| {
        const off = pos;
        pos += line.len + 1;
        const t = std.mem.trim(u8, line, " \r");
        if (isHeadword(t)) {
            if (cur) |h| heads.append(.{ .w = h, .s = bstart }) catch {};
            var hw = t;
            for (hw, 0..) |c, k| if (c == ' ' or c == ';' or c == ',') {
                hw = hw[0..k];
                break;
            };
            const key = A.alloc(u8, hw.len) catch return;
            for (0..hw.len) |k| key[k] = lo(hw[k]);
            cur = key;
            bstart = pos;
            dict_words.put(key, {}) catch {};
        }
        _ = off;
    }
    // second pass: genus per headword (definition-genus is the strongest IS-A signal → weight 5)
    for (heads.items, 0..) |h, i| {
        const end = if (i + 1 < heads.items.len) heads.items[i + 1].s else buf.len;
        const genus = extractGenus(extractGloss(buf[h.s..@min(end, buf.len)]));
        if (genus.len >= 3 and !std.mem.eql(u8, genus, h.w) and !std.mem.endsWith(u8, genus, "ed") and !std.mem.endsWith(u8, genus, "ing") and dict_words.contains(genus))
            bump(&isa_ev, h.w, genus, 5);
    }
}

// ─────────────────────────── Hearst patterns + possessives over a corpus ───────────────────────────
fn mineText(buf: []const u8) void {
    // sliding window of recent content tokens; pending hypernym for forward patterns
    var p1: []const u8 = ""; // previous raw token (may be stopword)
    var p2: []const u8 = "";
    var lcn: []const u8 = ""; // last content (non-stop) token
    var pend_hyper: []const u8 = ""; // for "Y such as X…" / "Y including X…"
    var pend_n: u32 = 0;
    var and_other = false; // saw "and/or other" → next content token is the hypernym for lcn-before-and
    var i: usize = 0;
    var tok = std.ArrayList(u8).init(A);
    while (i <= buf.len) : (i += 1) {
        const c: u8 = if (i < buf.len) buf[i] else ' ';
        if (isAlpha(c)) {
            tok.append(lo(c)) catch {};
            continue;
        }
        // possessive: a token immediately followed by 's or ’s, then a content word → owner has-part word
        const is_poss = (c == '\'' and i + 1 < buf.len and lo(buf[i + 1]) == 's') or
            (c == 0xE2 and i + 3 < buf.len and buf[i + 1] == 0x80 and buf[i + 2] == 0x99 and lo(buf[i + 3]) == 's');
        const w = tok.items;
        if (w.len > 0) {
            // pattern resolution at this token boundary
            if (and_other and !isStop(w)) { // "lcn and other W" → lcn is-a W
                bump(&isa_ev, lcn, w, 1);
                and_other = false;
            } else and_other = false;
            if (pend_n > 0 and !isStop(w)) { // collecting hyponyms for pend_hyper
                bump(&isa_ev, w, pend_hyper, 1);
                pend_n -= 1;
            }
            // triggers
            if (std.mem.eql(u8, w, "as") and std.mem.eql(u8, p1, "such") and !isStop(p2) and p2.len >= 3) {
                pend_hyper = p2;
                pend_n = 3; // "Y such as X1 X2 X3"
            }
            if (std.mem.eql(u8, w, "other") and (std.mem.eql(u8, p1, "and") or std.mem.eql(u8, p1, "or")) and lcn.len >= 3) {
                and_other = true; // next content token is the hypernym
            }
            if ((std.mem.eql(u8, w, "including") or std.mem.eql(u8, w, "especially")) and lcn.len >= 3 and !isStop(lcn)) {
                pend_hyper = lcn;
                pend_n = 3;
            }
            // possessive HAS-PART: previous content token owned the upcoming word
            if (is_poss) {
                // skip the 's tail and the separating space, then take the next content word = the possessed thing
                var j = i + (if (c == '\'') @as(usize, 2) else 4);
                while (j < buf.len and !isAlpha(buf[j])) j += 1;
                var nb = std.ArrayList(u8).init(A);
                while (j < buf.len and isAlpha(buf[j])) : (j += 1) nb.append(lo(buf[j])) catch {};
                if (!isStop(w) and nb.items.len >= 3 and !isStop(nb.items)) bump(&part_ev, w, nb.items, 1);
            }
            p2 = p1;
            p1 = w;
            if (!isStop(w)) lcn = w;
        }
        // sentence break resets pending collection
        if (c == '.' or c == ';' or c == ':' or c == '\n' or c == '!' or c == '?') {
            pend_n = 0;
            and_other = false;
            lcn = "";
        }
        tok = std.ArrayList(u8).init(A);
    }
}
fn mineFile(name: []const u8) void {
    const f = std.fs.openFileAbsolute(fmt("{s}{s}", .{ C, name }), .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    mineText(buf);
}

// ─────────────────────────── certify + freeze ───────────────────────────
var isa: std.StringHashMap([][]const u8) = undefined; // hyponym → certified hypernyms (best first)
var parts: std.StringHashMap([][]const u8) = undefined;
const WEv = struct { w: []const u8, ev: u32 };
fn cmpEv(_: void, a: WEv, b: WEv) bool {
    return a.ev > b.ev;
}
fn freeze(ev: *std.StringHashMap(*Inner), out: *std.StringHashMap([][]const u8), min_ev: u32) usize {
    var edges: usize = 0;
    var it = ev.iterator();
    while (it.next()) |e| {
        var list = std.ArrayList(WEv).init(A);
        var iit = e.value_ptr.*.iterator();
        while (iit.next()) |ie| if (ie.value_ptr.* >= min_ev) list.append(.{ .w = ie.key_ptr.*, .ev = ie.value_ptr.* }) catch {};
        if (list.items.len == 0) continue;
        std.mem.sort(WEv, list.items, {}, cmpEv);
        var arr = A.alloc([]const u8, list.items.len) catch continue;
        for (list.items, 0..) |x, k| arr[k] = x.w;
        out.put(e.key_ptr.*, arr) catch {};
        edges += arr.len;
    }
    return edges;
}

// ── chain walk (best-parent, multi-parent search to a target) ──
fn chainStr(x: []const u8) ?[]const u8 {
    var cur = x;
    var out = std.ArrayList(u8).init(A);
    out.appendSlice(x) catch {};
    var depth: usize = 0;
    var seen = std.StringHashMap(void).init(A);
    while (depth < 12) : (depth += 1) {
        if (seen.contains(cur)) break;
        seen.put(cur, {}) catch {};
        const ps = isa.get(cur) orelse break;
        if (ps.len == 0) break;
        cur = ps[0]; // best hypernym
        out.appendSlice(" → ") catch {};
        out.appendSlice(cur) catch {};
    }
    return if (out.items.len > x.len) out.items else null;
}
fn reaches(x: []const u8, y: []const u8) bool {
    // DFS up to depth, any parent
    var stack = std.ArrayList([]const u8).init(A);
    stack.append(x) catch return false;
    var seen = std.StringHashMap(void).init(A);
    var steps: usize = 0;
    while (stack.items.len > 0) {
        const cur = stack.pop() orelse break;
        steps += 1;
        if (steps > 4000) break;
        if (std.mem.eql(u8, cur, y)) return true;
        if (seen.contains(cur)) continue;
        seen.put(cur, {}) catch {};
        if (isa.get(cur)) |ps| for (ps) |p| stack.append(p) catch {};
    }
    return false;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();
    isa_ev = std.StringHashMap(*Inner).init(A);
    part_ev = std.StringHashMap(*Inner).init(A);
    dict_words = std.StringHashMap(void).init(A);
    isa = std.StringHashMap([][]const u8).init(A);
    parts = std.StringHashMap([][]const u8).init(A);

    try o.print("=== CONCEPT LEARNER — mining IS-A & HAS-PART from raw text (no handed WordNet). ===\n\n", .{});
    try o.print("[mine] Webster definition-genus…\n", .{});
    loadWebster();
    try o.print("[mine] Hearst patterns + possessives over corpus…\n", .{});
    inline for (.{ "webster1913.txt", "gutenberg_dense.txt", "moby_dick.txt", "shakespeare.txt", "tolstoy.txt", "austen.txt", "sherlock.txt" }) |fnm| mineFile(fnm);

    const ie = freeze(&isa_ev, &isa, 3); // certify IS-A: evidence ≥ 3 (definitional genus=5, or ≥3 Hearst hits) — drop weak noise so we don't infer "dog is a plant"
    const pe = freeze(&part_ev, &parts, 2); // certify HAS-PART: seen ≥ 2 times
    try o.print("\n[learned] {d} concepts with IS-A ({d} certified edges), {d} with HAS-PART ({d} edges). No WordNet.\n\n", .{ isa.count(), ie, parts.count(), pe });

    try o.print("── learned IS-A chains (mined, not handed) ──\n", .{});
    inline for (.{ "dog", "king", "knife", "horse", "whale", "oak", "rose", "computer", "lion", "ship", "doctor", "iron" }) |w| {
        if (chainStr(w)) |ch| try o.print("  {s}\n", .{ch}) else try o.print("  {s}  (not learned)\n", .{w});
    }

    try o.print("\n── IS-A Q&A on the LEARNED graph ──\n", .{});
    const Q = struct { x: []const u8, y: []const u8, exp: bool };
    const battery = [_]Q{
        .{ .x = "dog", .y = "animal", .exp = true },  .{ .x = "knife", .y = "instrument", .exp = true },
        .{ .x = "king", .y = "ruler", .exp = true },  .{ .x = "horse", .y = "animal", .exp = true },
        .{ .x = "whale", .y = "animal", .exp = true }, .{ .x = "lion", .y = "animal", .exp = true },
        .{ .x = "dog", .y = "plant", .exp = false },  .{ .x = "knife", .y = "animal", .exp = false },
    };
    var ok: usize = 0;
    for (battery) |q| {
        const got = reaches(q.x, q.y);
        if (got == q.exp) ok += 1;
        try o.print("  is a {s:<8} a {s:<10}? {s:<3} {s}\n", .{ q.x, q.y, if (got) "yes" else "no", if (got == q.exp) "✓" else "✗" });
    }
    try o.print("  → {d}/{d}\n", .{ ok, battery.len });

    try o.print("\n── learned HAS-PART (corpus possessives) ──\n", .{});
    inline for (.{ "king", "horse", "ship", "man" }) |w| {
        if (parts.get(w)) |ps| {
            try o.print("  {s} has:", .{w});
            for (ps, 0..) |p, k| {
                if (k >= 6) break;
                try o.print(" {s}", .{p});
            }
            try o.print("\n", .{});
        } else try o.print("  {s}  (no parts learned)\n", .{w});
    }

    // ── throwaway yardstick: how much of WordNet's IS-A did we recover? (WordNet loaded ONLY here, then discarded) ──
    try o.print("\n── WordNet recall (throwaway benchmark — not used by the engine) ──\n", .{});
    try wordnetRecall(o);
}

// Loads WordNet purely to score recall, then it is never used again (the engine will not depend on it).
fn wordnetRecall(o: anytype) !void {
    const di = std.fs.openFileAbsolute(C ++ "dict/index.noun", .{}) catch {
        try o.print("  (WordNet not present — skipping benchmark)\n", .{});
        return;
    };
    di.close();
    const df = std.fs.openFileAbsolute(C ++ "dict/data.noun", .{}) catch return;
    defer df.close();
    const buf = df.readToEndAlloc(A, 1 << 30) catch return;
    // build offset→first-word and offset→hypernym
    var word = std.AutoHashMap(u32, []const u8).init(A);
    var hyp = std.AutoHashMap(u32, u32).init(A);
    var lines = std.mem.splitScalar(u8, buf, '\n');
    while (lines.next()) |line| {
        if (line.len < 10) continue;
        var t = std.mem.tokenizeScalar(u8, line, ' ');
        const off = std.fmt.parseInt(u32, t.next() orelse continue, 10) catch continue;
        _ = t.next();
        if (!std.mem.eql(u8, t.next() orelse "", "n")) continue;
        const wc = std.fmt.parseInt(usize, t.next() orelse continue, 16) catch continue;
        const wname = t.next() orelse continue;
        const wclean = A.alloc(u8, wname.len) catch continue;
        for (0..wname.len) |k| wclean[k] = if (wname[k] == '_') ' ' else lo(wname[k]);
        word.put(off, wclean) catch {};
        var skip: usize = 1 + 2 * (wc - 1);
        while (skip > 0) : (skip -= 1) _ = t.next();
        const pc = std.fmt.parseInt(usize, t.next() orelse "0", 10) catch 0;
        var p: usize = 0;
        while (p < pc) : (p += 1) {
            const sym = t.next() orelse break;
            const to = t.next() orelse break;
            _ = t.next();
            _ = t.next();
            if (std.mem.eql(u8, sym, "@")) {
                hyp.put(off, std.fmt.parseInt(u32, to, 10) catch 0) catch {};
                break;
            }
        }
    }
    // sample direct WordNet is-a pairs (word → its hypernym word) and check our graph reaches them
    var checked: usize = 0;
    var hit: usize = 0;
    var it = hyp.iterator();
    while (it.next()) |e| {
        if (checked >= 4000) break;
        const x = word.get(e.key_ptr.*) orelse continue;
        const y = word.get(e.value_ptr.*) orelse continue;
        if (std.mem.indexOfScalar(u8, x, ' ') != null or std.mem.indexOfScalar(u8, y, ' ') != null) continue; // single words only
        if (!isa.contains(x)) continue; // only score words we even have
        checked += 1;
        if (reaches(x, y)) hit += 1;
    }
    if (checked > 0)
        try o.print("  recovered {d}/{d} = {d:.0}% of WordNet's direct IS-A links (on words we learned). Coverage is lower\n  than WordNet, but it is OURS — mined from text and root-fixable. WordNet now discarded.\n", .{ hit, checked, 100.0 * @as(f64, @floatFromInt(hit)) / @as(f64, @floatFromInt(checked)) })
    else
        try o.print("  (no overlap to score)\n", .{});
}
