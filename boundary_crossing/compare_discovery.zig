//! compare_discovery.zig — two ways to DISCOVER IS-A from raw text with no handed linguistic knowledge,
//! measured head-to-head. The machine must recognize the structure itself; nothing is labeled for it.
//!
//!  APPROACH 1 — self-discovered FRAMES. Connector words are found by frequency alone (the top-FUNCN most
//!    frequent tokens — never a handed stoplist). A "frame" is whatever connector-sequence sits between two
//!    content words ("_ is a _", "_ such as _", "_ of the _", …). The machine COUNTS every frame, then
//!    CERTIFIES a frame as IS-A iff its pairs consistently run specific→general (generality = context breadth,
//!    discovered from co-occurrence). It is never told "is a" means IS-A — it induces it. Then it reads edges
//!    only through certified frames.
//!
//!  APPROACH 2 — NO frames. Pure structure: distributional similarity (PPMI cosine) says two words are
//!    related; direction by generality-via-entropy (SLQS-style: the hypernym's contexts are higher-entropy /
//!    more general). x is-a y iff sim(x,y) high AND gen(y) > gen(x). No reliance on any function-word frame.
//!
//! WordNet loaded ONLY to grade (full hypernym closure). Baselines printed for reference:
//!   hand-patterns (Hearst+genus, HARDCODED) 36.9% / 4.3% ; pure-inclusion (naive) 2.9% / 0.0%.
//! Build: zig build-exe compare_discovery.zig -O ReleaseFast -femit-bin=/tmp/cmp && /tmp/cmp
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

const W = 3;
const MINC = 25;
const VMAX = 7000;
const TOPF = 60;
const FUNCN = 100; // top-100 most frequent words are "connectors" (discovered by frequency, not a handed list)
// approach 1
const FRAME_MIN = 150; // a frame must connect at least this many pairs to be judged (productive)
const DIR_MIN = 0.60; // certify frame as IS-A iff this fraction of its pairs run specific→general
const EDGE_MIN = 2; // an edge must be read through a certified frame at least this many times
// approach 2
const SIM_MIN = 0.10; // min PPMI-cosine to be "related"
const ENT_MARGIN = 0.20; // hypernym entropy must exceed hyponym by this (nats)

const FILES = .{ "webster1913.txt", "gutenberg_dense.txt", "moby_dick.txt", "shakespeare.txt", "tolstoy.txt", "austen.txt", "sherlock.txt" };

var vocab: std.ArrayList([]const u8) = undefined;
var id_of: std.StringHashMap(u32) = undefined;

fn countFile(freq: *std.StringHashMap(u32), fnm: []const u8) void {
    const f = std.fs.openFileAbsolute(fmt("{s}{s}", .{ C, fnm }), .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    var tok = std.ArrayList(u8).init(A);
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
            tok = std.ArrayList(u8).init(A);
        }
    }
}
fn countPass() !void {
    var freq = std.StringHashMap(u32).init(A);
    inline for (FILES) |fnm| countFile(&freq, fnm);
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

var co: []std.AutoHashMap(u32, u32) = undefined;
var tot: []f64 = undefined;
var Ntot: f64 = 0;
fn coFile(fnm: []const u8) void {
    const f = std.fs.openFileAbsolute(fmt("{s}{s}", .{ C, fnm }), .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    var ring: [2 * W]u32 = undefined;
    var rn: usize = 0;
    var tok = std.ArrayList(u8).init(A);
    var i: usize = 0;
    while (i <= buf.len) : (i += 1) {
        const ch: u8 = if (i < buf.len) buf[i] else ' ';
        if (isAlpha(ch)) {
            tok.append(lo(ch)) catch {};
            continue;
        }
        if (tok.items.len >= 1) {
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
        } else if (ch == '.' or ch == '\n' or ch == '!' or ch == '?') rn = 0;
        tok = std.ArrayList(u8).init(A);
    }
}
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

// generality signals (both discovered from co-occurrence)
var gen_breadth: []u32 = undefined; // distinct context types
var gen_entropy: []f64 = undefined; // entropy of context distribution (SLQS-style generality)
fn buildGenerality() !void {
    const V = vocab.items.len;
    gen_breadth = try A.alloc(u32, V);
    gen_entropy = try A.alloc(f64, V);
    for (0..V) |a| {
        gen_breadth[a] = co[a].count();
        var h: f64 = 0;
        const t = tot[a];
        if (t > 0) {
            var it = co[a].iterator();
            while (it.next()) |e| {
                const p = @as(f64, @floatFromInt(e.value_ptr.*)) / t;
                if (p > 0) h -= p * @log(p);
            }
        }
        gen_entropy[a] = h;
    }
}

// PPMI top-feature profiles + norms (approach 2)
var prof: []std.AutoHashMap(u32, f32) = undefined;
var pmass: []f64 = undefined;
var pnorm: []f64 = undefined;
fn ppmi(a: u32, f: u32, caf: u32) f32 {
    const v = (@as(f64, @floatFromInt(caf)) * Ntot) / (tot[a] * tot[f]);
    if (v <= 1.0) return 0;
    return @floatCast(@log(v));
}
fn buildProfiles() !void {
    const V = vocab.items.len;
    prof = try A.alloc(std.AutoHashMap(u32, f32), V);
    pmass = try A.alloc(f64, V);
    pnorm = try A.alloc(f64, V);
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
        var nrm: f64 = 0;
        const n = @min(list.items.len, TOPF);
        for (list.items[0..n]) |x| {
            prof[a].put(x.f, x.w) catch {};
            pmass[a] += x.w;
            nrm += @as(f64, x.w) * x.w;
        }
        pnorm[a] = @sqrt(nrm);
    }
}
var inv: std.AutoHashMap(u32, std.ArrayList(u32)) = undefined; // feature → words (top profiles)
fn buildInverted() !void {
    inv = std.AutoHashMap(u32, std.ArrayList(u32)).init(A);
    for (0..vocab.items.len) |a| {
        var it = prof[a].iterator();
        while (it.next()) |e| {
            const g = inv.getOrPut(e.key_ptr.*) catch continue;
            if (!g.found_existing) g.value_ptr.* = std.ArrayList(u32).init(A);
            g.value_ptr.*.append(@intCast(a)) catch {};
        }
    }
}

// ───────────────── APPROACH 1: self-discovered frames ─────────────────
const FrameStat = struct { name: []const u8, freq: u32, dirsum: u32, dirn: u32 };
var frames: std.AutoHashMap(u32, FrameStat) = undefined; // framecode → stats
var certified: std.AutoHashMap(u32, void) = undefined; // certified IS-A framecodes
var ec1: []std.AutoHashMap(u32, u32) = undefined; // x → (y → count via certified frames)

fn frameCode(pending: []const u32) u32 {
    var code: u32 = @intCast(pending.len);
    for (pending) |r| code = code * 101 + (r + 1); // r = connector id (<FUNCN<100)
    return code;
}
fn frameName(pending: []const u32) []const u8 {
    var s = std.ArrayList(u8).init(A);
    for (pending, 0..) |r, k| {
        if (k > 0) s.append(' ') catch {};
        s.appendSlice(vocab.items[r]) catch {};
    }
    return s.items;
}
fn frameScanFile(fnm: []const u8, certified_only: bool) void {
    const f = std.fs.openFileAbsolute(fmt("{s}{s}", .{ C, fnm }), .{}) catch return;
    defer f.close();
    const buf = f.readToEndAlloc(A, 1 << 30) catch return;
    const NONE = std.math.maxInt(u32);
    var last: u32 = NONE;
    var pend: [3]u32 = undefined;
    var pn: usize = 0;
    var tok = std.ArrayList(u8).init(A);
    var i: usize = 0;
    while (i <= buf.len) : (i += 1) {
        const ch: u8 = if (i < buf.len) buf[i] else ' ';
        if (isAlpha(ch)) {
            tok.append(lo(ch)) catch {};
            continue;
        }
        const sent_break = (ch == '.' or ch == '\n' or ch == '!' or ch == '?');
        if (tok.items.len >= 1) {
            if (id_of.get(tok.items)) |t| {
                if (t < FUNCN) { // connector
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
                        if (!certified_only) {
                            const g = frames.getOrPut(code) catch return;
                            if (!g.found_existing) g.value_ptr.* = .{ .name = frameName(pend[0..pn]), .freq = 0, .dirsum = 0, .dirn = 0 };
                            g.value_ptr.*.freq += 1;
                            g.value_ptr.*.dirn += 1;
                            if (gen_breadth[t] > gen_breadth[last]) g.value_ptr.*.dirsum += 1; // y broader than x
                        } else if (certified.contains(code)) {
                            const e = ec1[last].getOrPut(t) catch return;
                            if (!e.found_existing) e.value_ptr.* = 0;
                            e.value_ptr.* += 1;
                        }
                    }
                    last = t;
                    pn = 0;
                }
            } else { // unknown word breaks the frame
                last = NONE;
                pn = 0;
            }
        }
        if (sent_break) {
            last = NONE;
            pn = 0;
        }
        tok = std.ArrayList(u8).init(A);
    }
}
var isa1: [][]u32 = undefined;
fn runApproach1(o: anytype) !void {
    frames = std.AutoHashMap(u32, FrameStat).init(A);
    certified = std.AutoHashMap(u32, void).init(A);
    inline for (FILES) |fnm| frameScanFile(fnm, false);
    // DIAGNOSTIC: do the canonical taxonomy frames even exist / can the mechanism see them?
    try o.print("  [diag] canonical taxonomy frames (freq=0 means the mechanism can't see it):\n", .{});
    inline for (.{ "is a", "is an", "is the", "was a", "of the", "such as", "kind of", "a", "are" }) |nm| {
        var ids: [3]u32 = undefined;
        var n: usize = 0;
        var allconn = true;
        var parts = std.mem.tokenizeScalar(u8, nm, ' ');
        while (parts.next()) |p| {
            if (id_of.get(p)) |pid| {
                if (pid >= FUNCN) allconn = false;
                if (n < 3) {
                    ids[n] = pid;
                    n += 1;
                }
            } else allconn = false;
        }
        if (n > 0 and allconn) {
            const code = frameCode(ids[0..n]);
            if (frames.get(code)) |s| {
                const dir = @as(f64, @floatFromInt(s.dirsum)) / @as(f64, @floatFromInt(@max(s.dirn, 1)));
                try o.print("    \"_ {s} _\"  freq={d}  specific→general={d:.0}%\n", .{ nm, s.freq, dir * 100 });
            } else try o.print("    \"_ {s} _\"  freq=0 (not seen connecting two content words)\n", .{nm});
        } else try o.print("    \"_ {s} _\"  UNSEEABLE — a token isn't a top-{d} connector (breaks the frame)\n", .{ nm, FUNCN });
    }
    // certify frames: productive AND consistently specific→general
    const FR = struct { code: u32, name: []const u8, freq: u32, dir: f64 };
    var cl = std.ArrayList(FR).init(A);
    var it = frames.iterator();
    while (it.next()) |e| {
        const s = e.value_ptr.*;
        if (s.freq < FRAME_MIN) continue;
        const dir = @as(f64, @floatFromInt(s.dirsum)) / @as(f64, @floatFromInt(s.dirn));
        if (dir >= DIR_MIN) {
            certified.put(e.key_ptr.*, {}) catch {};
            cl.append(.{ .code = e.key_ptr.*, .name = s.name, .freq = s.freq, .dir = dir }) catch {};
        }
    }
    std.mem.sort(FR, cl.items, {}, struct {
        fn f(_: void, a: FR, b: FR) bool {
            return a.freq > b.freq;
        }
    }.f);
    try o.print("  DISCOVERED IS-A frames (machine certified these on its own, top 15 by frequency):\n", .{});
    for (cl.items, 0..) |fr, k| {
        if (k >= 15) break;
        try o.print("    \"_ {s} _\"   freq={d}  specific→general={d:.0}%\n", .{ fr.name, fr.freq, fr.dir * 100 });
    }
    try o.print("    ({d} frames certified as IS-A out of {d} productive frames seen)\n", .{ certified.count(), cl.items.len });
    // read edges through certified frames
    const V = vocab.items.len;
    ec1 = try A.alloc(std.AutoHashMap(u32, u32), V);
    for (0..V) |i| ec1[i] = std.AutoHashMap(u32, u32).init(A);
    inline for (FILES) |fnm| frameScanFile(fnm, true);
    isa1 = try A.alloc([]u32, V);
    const YC = struct { y: u32, c: u32 };
    for (0..V) |a| {
        var ys = std.ArrayList(YC).init(A);
        var eit = ec1[a].iterator();
        while (eit.next()) |e| if (e.value_ptr.* >= EDGE_MIN) ys.append(.{ .y = e.key_ptr.*, .c = e.value_ptr.* }) catch {};
        std.mem.sort(YC, ys.items, {}, struct {
            fn f(_: void, x: YC, y: YC) bool {
                return x.c > y.c;
            }
        }.f);
        const keep = @min(ys.items.len, 3);
        const arr = A.alloc(u32, keep) catch {
            isa1[a] = &[_]u32{};
            continue;
        };
        for (0..keep) |k| arr[k] = ys.items[k].y;
        isa1[a] = arr;
    }
}

// ───────────────── APPROACH 2: pure structure (similarity + entropy direction) ─────────────────
var isa2: [][]u32 = undefined;
fn runApproach2() !void {
    const V = vocab.items.len;
    isa2 = try A.alloc([]u32, V);
    var cand = std.AutoHashMap(u32, f64).init(A); // y → dot product accumulator
    const Sc = struct { y: u32, sim: f64, score: f64 };
    for (FUNCN..V) |a| { // only content words as hyponyms
        cand.clearRetainingCapacity();
        var it = prof[a].iterator();
        while (it.next()) |e| {
            const wx = e.value_ptr.*;
            const post = inv.get(e.key_ptr.*) orelse continue;
            for (post.items) |y| {
                if (y == a or y < FUNCN) continue;
                const wy = prof[y].get(e.key_ptr.*) orelse continue;
                const g = cand.getOrPut(y) catch continue;
                if (!g.found_existing) g.value_ptr.* = 0;
                g.value_ptr.* += @as(f64, wx) * wy;
            }
        }
        var best = std.ArrayList(Sc).init(A);
        var cit = cand.iterator();
        while (cit.next()) |e| {
            const y = e.key_ptr.*;
            const denom = pnorm[a] * pnorm[y];
            if (denom <= 0) continue;
            const sim = e.value_ptr.* / denom;
            if (sim < SIM_MIN) continue;
            if (gen_entropy[y] < gen_entropy[a] + ENT_MARGIN) continue; // y must be more general
            best.append(.{ .y = y, .sim = sim, .score = sim * (gen_entropy[y] - gen_entropy[a]) }) catch {};
        }
        std.mem.sort(Sc, best.items, {}, struct {
            fn f(_: void, x: Sc, y: Sc) bool {
                return x.score > y.score;
            }
        }.f);
        const keep = @min(best.items.len, 3);
        const arr = A.alloc(u32, keep) catch {
            isa2[a] = &[_]u32{};
            continue;
        };
        for (0..keep) |k| arr[k] = best.items[k].y;
        isa2[a] = arr;
    }
    for (0..FUNCN) |a| isa2[a] = &[_]u32{};
}

// ───────────────── grading ─────────────────
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
fn reachesG(isa: [][]u32, x: u32, y: u32) bool {
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
const Grade = struct { edges: usize, pc: usize, ph: usize, rc: usize, rh: usize };
fn grade(isa: [][]u32) Grade {
    var g = Grade{ .edges = 0, .pc = 0, .ph = 0, .rc = 0, .rh = 0 };
    for (0..vocab.items.len) |a| {
        const x = vocab.items[a];
        for (isa[a]) |yid| {
            g.edges += 1;
            const y = vocab.items[yid];
            if (!wnHas(x) or !wnHas(y)) continue;
            g.pc += 1;
            if (wnReaches(x, y)) g.ph += 1;
        }
    }
    var seen = std.StringHashMap(void).init(A);
    outer: for (vocab.items, 0..) |x, xi| {
        if (g.rc >= 4000) break;
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
                    g.rc += 1;
                    if (reachesG(isa, @intCast(xi), yid)) g.rh += 1;
                    if (g.rc >= 4000) break :outer;
                };
            };
        }
    }
    return g;
}
fn sampleChains(o: anytype, isa: [][]u32) !void {
    inline for (.{ "dog", "king", "knife", "horse", "whale", "oak", "rose", "lion", "sword", "wine" }) |w| {
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
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    A = arena.allocator();
    const o = std.io.getStdOut().writer();
    vocab = std.ArrayList([]const u8).init(A);
    id_of = std.StringHashMap(u32).init(A);

    try o.print("=== COMPARE DISCOVERY — self-discovered frames vs pure structure (no handed knowledge) ===\n\n", .{});
    try o.print("[setup] count → vocab, co-occurrence, generality, profiles…\n", .{});
    try countPass();
    try coPass();
    try buildGenerality();
    try buildProfiles();
    try buildInverted();
    try o.print("    vocab {d} · connectors = top {d} by frequency\n\n", .{ vocab.items.len, FUNCN });

    try o.print("──────── APPROACH 1: self-discovered FRAMES ────────\n", .{});
    try runApproach1(o);
    try o.print("  sample chains:\n", .{});
    try sampleChains(o, isa1);

    try o.print("\n──────── APPROACH 2: pure STRUCTURE (similarity + entropy) ────────\n", .{});
    try runApproach2();
    try o.print("  sample chains:\n", .{});
    try sampleChains(o, isa2);

    try o.print("\n[grade] loading WordNet (grade only)…\n", .{});
    loadWordNet();
    if (!wn_loaded) {
        try o.print("WordNet absent — cannot grade.\n", .{});
        return;
    }
    const g1 = grade(isa1);
    const g2 = grade(isa2);
    try o.print("\n════════════════════════ SCORECARD ════════════════════════\n", .{});
    try o.print("  {s:<26} {s:>8} {s:>16} {s:>14}\n", .{ "approach", "edges", "PRECISION", "recall" });
    try o.print("  {s:<26} {s:>8} {d:>7}/{d:<5}{d:>5.1}% {d:>5}/{d:<5}{d:>4.1}%\n", .{ "1: self-discovered frames", fmtu(g1.edges), g1.ph, g1.pc, pct(g1.ph, g1.pc), g1.rh, g1.rc, pct(g1.rh, g1.rc) });
    try o.print("  {s:<26} {s:>8} {d:>7}/{d:<5}{d:>5.1}% {d:>5}/{d:<5}{d:>4.1}%\n", .{ "2: pure structure", fmtu(g2.edges), g2.ph, g2.pc, pct(g2.ph, g2.pc), g2.rh, g2.rc, pct(g2.rh, g2.rc) });
    try o.print("  {s:<26} {s:>8} {s:>16} {s:>14}\n", .{ "—hand-patterns (HARDCODED)", "63836", "36.9%", "4.3%" });
    try o.print("  {s:<26} {s:>8} {s:>16} {s:>14}\n", .{ "—naive inclusion", "457", "2.9%", "0.0%" });
    try o.print("\n  Approach 1 induced its IS-A frames from data — it was never told what \"is a\" means.\n", .{});
}
var ubuf: [32]u8 = undefined;
fn fmtu(x: usize) []const u8 {
    return std.fmt.bufPrint(&ubuf, "{d}", .{x}) catch "?";
}
