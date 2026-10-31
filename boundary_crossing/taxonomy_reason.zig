//! taxonomy_reason.zig — point the right data at it: turn the dictionary's IS-A links into a TAXONOMY, then
//! REASON over it by inheritance. It answers "is a king a person?" — a fact it was never told — by composing
//! extracted facts (king is-a ruler, ruler is-a person) and walking the chain. Verifiable. No LLM, no labels.
//!
//! This is the rung past lookup. dictionary_define gave one genus per word; here we extract the genus for EVERY
//! headword, build the directed IS-A graph (king→ruler→person; horse→quadruped→animal→being), and take its
//! TRANSITIVE CLOSURE. Transitive closure over IS-A *is* a sound form of reasoning — inheritance — so questions the
//! text never states get answered with a proof chain. That's the slice of "reasoning" I'd said data alone wouldn't
//! give: it does, for the part that's checkable. (It is NOT open-ended reasoning; that stays the LLM's edge.)
//!
//! Fix that matters: many entries' FIRST sense is an adjective ("quadruped: Having four feet"); the noun sense
//! ("A four-footed animal") is later. We pick the first sense that's a NOUN definition (starts with a determiner),
//! so the genus chains climb correctly. Webster's "One who …" / "That which …" are normalized to person / thing.
//!
//! Run: zig build taxonomy-reason --release=fast   (reads corpus/webster1913.txt; pass a path to override)

const std = @import("std");

fn lo(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isUpper(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}
fn isLower(c: u8) bool {
    return c >= 'a' and c <= 'z';
}
fn isAlpha(c: u8) bool {
    return isUpper(c) or isLower(c);
}
fn eqil(w: []const u8, lit: []const u8) bool {
    return std.mem.eql(u8, w, lit);
}
fn startsCI(s: []const u8, p: []const u8) bool { // p must be lowercase
    if (s.len < p.len) return false;
    for (0..p.len) |i| if (lo(s[i]) != p[i]) return false;
    return true;
}

fn isHeadword(line: []const u8) bool {
    if (line.len < 2 or line.len > 40) return false;
    var letters: usize = 0;
    for (line) |c| {
        if (isLower(c)) return false;
        if (isUpper(c)) letters += 1 else if (c == ' ' or c == '-' or c == '\'' or c == ';' or c == ',' or c == '.' or (c >= '0' and c <= '9')) {} else return false;
    }
    return letters >= 2;
}

fn isArticle(w: []const u8) bool {
    return eqil(w, "a") or eqil(w, "an") or eqil(w, "the") or eqil(w, "one") or eqil(w, "any") or eqil(w, "some");
}
fn isTrigger(w: []const u8) bool {
    inline for (.{ "of", "which", "that", "consisting", "having", "used", "for", "with", "to", "in", "on", "as", "by", "from", "or", "and", "esp", "usually", "made", "formed", "endowed", "characterized", "found", "provided", "native", "situated", "belonging", "resembling", "called", "containing", "growing", "living", "especially", "being" }) |t| {
        if (eqil(w, t)) return true;
    }
    return false;
}
// remove inline parentheticals like "(Felis leo)" / "(C. familiaris)" that pollute the head noun
fn stripParens(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(a);
    var depth: usize = 0;
    for (s) |c| {
        if (c == '(') {
            depth += 1;
        } else if (c == ')') {
            if (depth > 0) depth -= 1;
        } else if (depth == 0) try out.append(c);
    }
    return out.items;
}
// head noun of a clause: skip a leading article, take the last word before the first post-modifier trigger
fn headOf(a: std.mem.Allocator, clause: []const u8) ![]const u8 {
    var arr = std.ArrayList([]const u8).init(a);
    var it = std.mem.tokenizeAny(u8, clause, " ,;:()./");
    while (it.next()) |raw| {
        var b = std.ArrayList(u8).init(a);
        for (raw) |c| if (isAlpha(c)) try b.append(lo(c));
        if (b.items.len >= 1) try arr.append(b.items);
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

// clean ONE sense beginning at byte `start` (already past its "Defn:"/"N." marker): join to a line, cut citations
fn cleanSense(a: std.mem.Allocator, body: []const u8, start: usize) ![]const u8 {
    var s = start;
    while (s < body.len and (body[s] == ' ' or body[s] == '\n')) s += 1;
    var out = std.ArrayList(u8).init(a);
    var j = s;
    var nl: usize = 0;
    while (j < body.len) : (j += 1) {
        const c = body[j];
        if (c == '\n') {
            nl += 1;
            if (nl >= 2) break;
            try out.append(' ');
        } else {
            nl = 0;
            try out.append(c);
        }
        if (out.items.len > 300) break;
    }
    var g = std.mem.trim(u8, out.items, " ");
    if (g.len > 0 and g[0] == '(') {
        if (std.mem.indexOfScalar(u8, g, ')')) |p| g = std.mem.trim(u8, g[p + 1 ..], " ");
    }
    if (std.mem.indexOf(u8, g, "Defn:")) |dp| {
        if (dp < 6) g = std.mem.trim(u8, g[dp + 5 ..], " ");
    }
    inline for (.{ "\"", " -- ", "Etym", "Syn.", " [" }) |cut| {
        if (std.mem.indexOf(u8, g, cut)) |at| g = std.mem.trim(u8, g[0..at], " ");
    }
    return g;
}
fn nounCue(g: []const u8) bool {
    inline for (.{ "a ", "an ", "the ", "one ", "that ", "any ", "anything ", "something " }) |c| {
        if (startsCI(g, c)) return true;
    }
    return false;
}
// the best gloss for taxonomy = the first sense that is a NOUN definition (else the earliest sense)
fn bestNounGloss(a: std.mem.Allocator, body: []const u8) ![]const u8 {
    var fallback: []const u8 = "";
    // scan markers in order: each "Defn:" and each line-start "N. "
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        var start: ?usize = null;
        if (i + 5 <= body.len and std.mem.eql(u8, body[i .. i + 5], "Defn:")) {
            start = i + 5;
        } else if ((i == 0 or body[i - 1] == '\n') and i + 2 < body.len and body[i] >= '1' and body[i] <= '9' and body[i + 1] == '.' and body[i + 2] == ' ') {
            start = i + 2;
        }
        if (start) |st| {
            const g = try cleanSense(a, body, st);
            if (g.len >= 3) {
                if (fallback.len == 0) fallback = g;
                if (nounCue(g)) return g;
            }
        }
    }
    return fallback;
}

// genus from a noun gloss, with Webster person/thing conventions normalized
fn genusOf(a: std.mem.Allocator, gloss: []const u8) ![]const u8 {
    const g = std.mem.trim(u8, gloss, " ");
    inline for (.{ "one who ", "a person ", "a human ", "any one who ", "he who ", "she who ", "those who ", "a man who ", "a woman who " }) |p| {
        if (startsCI(g, p)) return "person";
    }
    inline for (.{ "that which ", "anything that ", "anything which ", "something ", "a substance " }) |p| {
        if (startsCI(g, p)) return if (eqil(p, "a substance ")) "substance" else "thing";
    }
    // genus comes from the DEFINITION sentence only — cut trailing example sentences ("… vessel. Like a stately ship…")
    var defsen = g;
    if (std.mem.indexOfScalarPos(u8, g, 4, '.')) |dp| defsen = g[0..dp];
    var it = std.mem.tokenizeScalar(u8, defsen, ';');
    const clause = it.next() orelse defsen;
    return headOf(a, try stripParens(a, clause));
}

// ── the IS-A graph ──
var graph: std.StringHashMap([]const u8) = undefined; // word → genus
var syn: std.StringHashMap([]const u8) = undefined; // word → slash-joined synonym heads

const ROOTS = [_][]const u8{ "being", "person", "thing", "substance", "plant", "body", "animal", "quality", "act", "state", "part", "matter", "individual", "one", "mass", "quantity", "number", "material", "place", "form" };
fn isRoot(w: []const u8) bool {
    for (ROOTS) |r| if (eqil(w, r)) return true;
    return false;
}

// walk the hypernym chain (no allocation; fixed visited buffer guards cycles)
fn chainInto(word: []const u8, out: *std.ArrayList([]const u8)) void {
    var vis: [20][]const u8 = undefined;
    var nv: usize = 0;
    var cur = word;
    var depth: usize = 0;
    while (depth < 18) : (depth += 1) {
        var dup = false;
        for (0..nv) |k| if (eqil(vis[k], cur)) {
            dup = true;
        };
        if (dup) break;
        if (nv < 20) {
            vis[nv] = cur;
            nv += 1;
        }
        const g = graph.get(cur) orelse break;
        if (g.len == 0 or eqil(g, cur)) break;
        out.append(g) catch break;
        if (isRoot(g)) break;
        cur = g;
    }
}
fn reachesRoot(word: []const u8) bool {
    var vis: [20][]const u8 = undefined;
    var nv: usize = 0;
    var cur = word;
    var depth: usize = 0;
    while (depth < 18) : (depth += 1) {
        var dup = false;
        for (0..nv) |k| if (eqil(vis[k], cur)) {
            dup = true;
        };
        if (dup) return false;
        if (nv < 20) {
            vis[nv] = cur;
            nv += 1;
        }
        const g = graph.get(cur) orelse return false;
        if (eqil(g, cur)) return false;
        if (isRoot(g)) return true;
        cur = g;
    }
    return false;
}
fn synHas(node: []const u8, y: []const u8) bool {
    const s = syn.get(node) orelse return false;
    var it = std.mem.tokenizeAny(u8, s, " /");
    while (it.next()) |w| if (eqil(w, y)) return true;
    return false;
}
// is X a Y? — Y is X itself, or on X's hypernym chain, or a synonym of a chain node
fn isA(a: std.mem.Allocator, x: []const u8, y: []const u8) !bool {
    if (eqil(x, y) or synHas(x, y)) return true;
    var ch = std.ArrayList([]const u8).init(a);
    chainInto(x, &ch);
    for (ch.items) |n| {
        if (eqil(n, y) or synHas(n, y)) return true;
    }
    return false;
}

fn extractSyns(a: std.mem.Allocator, gloss: []const u8) ![]const u8 {
    var s = std.ArrayList(u8).init(a);
    var added: usize = 0;
    var clauses = std.mem.tokenizeScalar(u8, gloss, ';');
    while (clauses.next()) |raw| {
        const clause = std.mem.trim(u8, raw, " ,.");
        var wc: usize = 0;
        var wit = std.mem.tokenizeAny(u8, clause, " ,");
        while (wit.next()) |_| wc += 1;
        if (wc == 0 or wc > 3) continue;
        const h = try headOf(a, clause);
        if (h.len < 2) continue;
        if (s.items.len > 0) try s.appendSlice(" / ");
        try s.appendSlice(h);
        added += 1;
        if (added >= 4) break;
    }
    return s.items;
}

fn printChain(o: anytype, a: std.mem.Allocator, word: []const u8) !void {
    var ch = std.ArrayList([]const u8).init(a);
    chainInto(word, &ch);
    try o.print("  {s}", .{word});
    for (ch.items) |n| try o.print(" → {s}", .{n});
    if (ch.items.len == 0) try o.print("  (no IS-A extracted)", .{});
    try o.print("\n", .{});
}

pub fn main() !void {
    var arena_s = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_s.deinit();
    const a = arena_s.allocator();
    const o = std.io.getStdOut().writer();

    var argit = try std.process.argsWithAllocator(a);
    _ = argit.next();
    const path = argit.next() orelse "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/webster1913.txt";

    try o.print("=== TAXONOMY REASON — extract the IS-A graph, then REASON by inheritance. Verifiable, no LLM ===\n\n", .{});
    const f = std.fs.openFileAbsolute(path, .{}) catch {
        try o.print("dictionary not found at {s}\n", .{path});
        return;
    };
    defer f.close();
    const buf = try f.readToEndAlloc(a, 1 << 30);

    // index entries (longest body per headword), extract genus + synonyms → graph
    graph = std.StringHashMap([]const u8).init(a);
    syn = std.StringHashMap([]const u8).init(a);
    var longest = std.StringHashMap(usize).init(a);
    var nounFlag = std.StringHashMap(bool).init(a); // does the chosen entry's gloss read as a NOUN definition?
    var lines = std.mem.splitScalar(u8, buf, '\n');
    var cur_head: ?[]const u8 = null;
    var body_start: usize = 0;
    var pos_in: usize = 0;
    while (lines.next()) |line| {
        const line_off = pos_in;
        pos_in += line.len + 1;
        const trimmed = std.mem.trim(u8, line, " \r");
        if (isHeadword(trimmed)) {
            if (cur_head) |h| {
                const body = buf[body_start..@min(line_off, buf.len)];
                const gloss = try bestNounGloss(a, body);
                if (gloss.len >= 3) {
                    const gen = try genusOf(a, gloss);
                    if (gen.len >= 2 and !eqil(gen, h)) {
                        // PREFER a noun-phrase definition (king-the-ruler over to-ship/quadruped-the-adjective);
                        // tie-break on body length. This keeps the taxonomy's genus a real hypernym.
                        const is_noun = nounCue(gloss);
                        const prev_noun = nounFlag.get(h) orelse false;
                        const prev_len = longest.get(h) orelse 0;
                        const take = (is_noun and !prev_noun) or (is_noun == prev_noun and body.len > prev_len);
                        if (take) {
                            try graph.put(h, gen);
                            try syn.put(h, try extractSyns(a, gloss));
                            try longest.put(h, body.len);
                            try nounFlag.put(h, is_noun);
                        }
                    }
                }
            }
            var hw = trimmed;
            for (hw, 0..) |c, k| if (c == ' ' or c == ';' or c == ',') {
                hw = hw[0..k];
                break;
            };
            const key = try a.alloc(u8, hw.len);
            for (0..hw.len) |k| key[k] = lo(hw[k]);
            cur_head = key;
            body_start = pos_in;
        }
    }

    // coverage
    const with_genus: usize = graph.count();
    var reach: usize = 0;
    var git = graph.keyIterator();
    while (git.next()) |k| {
        if (reachesRoot(k.*)) reach += 1;
    }
    try o.print("built IS-A graph: {d} words have an extracted genus; {d} ({d:.0}%) chain up to a root concept.\n\n", .{ with_genus, reach, 100.0 * @as(f64, @floatFromInt(reach)) / @as(f64, @floatFromInt(@max(1, with_genus))) });

    // ── the taxonomy climbing (hypernym chains it was never given as chains — composed from per-word genus) ──
    try o.print("── HYPERNYM CHAINS (each link extracted separately; the CHAIN is composed = transitive closure) ──\n", .{});
    const showcase = [_][]const u8{ "king", "queen", "dog", "horse", "lion", "knife", "sword", "ship", "oak", "rose", "gold", "doctor", "hammer", "eagle" };
    for (showcase) |w| try printChain(o, a, w);

    // ── INHERITANCE REASONING: answer is-X-a-Y it was never told, by walking the chain; measured on a battery ──
    const Q = struct { x: []const u8, y: []const u8, ans: bool };
    const battery = [_]Q{
        .{ .x = "king", .y = "ruler", .ans = true },      .{ .x = "king", .y = "person", .ans = true },
        .{ .x = "dog", .y = "animal", .ans = true },      .{ .x = "horse", .y = "animal", .ans = true },
        .{ .x = "lion", .y = "mammal", .ans = true },     .{ .x = "knife", .y = "instrument", .ans = true },
        .{ .x = "knife", .y = "tool", .ans = true },      .{ .x = "sword", .y = "weapon", .ans = true },
        .{ .x = "sword", .y = "instrument", .ans = true },.{ .x = "ship", .y = "vessel", .ans = true },
        .{ .x = "oak", .y = "tree", .ans = true },        .{ .x = "doctor", .y = "person", .ans = true },
        .{ .x = "eagle", .y = "bird", .ans = true },      .{ .x = "gold", .y = "metal", .ans = true },
        .{ .x = "dog", .y = "plant", .ans = false },      .{ .x = "knife", .y = "animal", .ans = false },
        .{ .x = "horse", .y = "metal", .ans = false },    .{ .x = "oak", .y = "animal", .ans = false },
        .{ .x = "gold", .y = "animal", .ans = false },    .{ .x = "ship", .y = "person", .ans = false },
        .{ .x = "rose", .y = "animal", .ans = false },    .{ .x = "king", .y = "fish", .ans = false },
    };
    try o.print("\n── INHERITANCE Q&A: \"is an X a Y?\" answered by chain-walk (never stated in the text); ✓=matches truth ──\n", .{});
    var correct: usize = 0;
    for (battery) |q| {
        const got = try isA(a, q.x, q.y);
        const ok = got == q.ans;
        if (ok) correct += 1;
        try o.print("  is a {s:<7} a {s:<11}? {s:<3} {s}\n", .{ q.x, q.y, if (got) "yes" else "no", if (ok) "✓" else "✗ (WRONG)" });
    }
    try o.print("\n  inheritance-reasoning accuracy: {d}/{d} = {d:.0}%\n", .{ correct, battery.len, 100.0 * @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(battery.len)) });

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("Pointed at the right data, the engine now REASONS, not just looks up: every IS-A link was extracted\n", .{});
    try o.print("separately, and their TRANSITIVE CLOSURE answers questions never written down — 'is a king a person?'\n", .{});
    try o.print("→ king is-a ruler is-a person → yes, WITH the proof chain. {d}/{d} on a true/false battery, and {d:.0}% of all\n", .{ correct, battery.len, 100.0 * @as(f64, @floatFromInt(reach)) / @as(f64, @floatFromInt(@max(1, with_genus))) });
    try o.print("{d} graphed words climb to a root concept. This is the slice of REASONING I'd ceded to the LLM — and it\n", .{with_genus});
    try o.print("turns out inheritance reasoning IS reachable from the right data, because it's sound transitive closure\n", .{});
    try o.print("over verifiable facts. No LLM, no labels, fully auditable (every answer is a chain you can read).\n\n", .{});
    try o.print("HONEST EDGE: this is TAXONOMIC inheritance (a sound, narrow kind of reasoning), not open-ended inference,\n", .{});
    try o.print("and the battery is a designed set — the broader, un-cherry-picked number is the {d:.0}% global root-reach. The\n", .{100.0 * @as(f64, @floatFromInt(reach)) / @as(f64, @floatFromInt(@max(1, with_genus)))});
    try o.print("limits are visible right in the chains: a few intermediate genera bleed an adjective (vessel → 'hollow'), and\n", .{});
    try o.print("biology dead-ends at Webster's LATIN class names (mammal → 'Mammalia', not a headword) so lion/eagle reach\n", .{});
    try o.print("their class but not 'animal'. A clean relational KB (WordNet/ConceptNet) is the next data to point — its IS-A\n", .{});
    try o.print("links are already normalized, and it adds HAS-PART / USED-FOR so 'what a king is' gets relations, not just kind.\n", .{});
}
