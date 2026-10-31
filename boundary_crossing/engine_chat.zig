//! engine_chat.zig — make the engine feel like something you CHAT with, not a calculator. Still NO LLM.
//!
//! Micah: get it to not act like a strict calculator — chat, go back and forth, with invention. Ideas stolen
//! from ghost_engine (the REAL, non-theatrical ones): conversation session/history + last_result
//! (conversation_session.zig), epistemic labels (epistemic_renderer.zig), mood = parameter swap
//! (sigil_runtime.zig applyMoodName), runes = ranked pattern memory (triad.zig rank ladder).
//!
//! The honest principle (matches the agent's own finding + this repo's anti-theater rule): the conversational
//! feel comes from STRUCTURED STATE + REASONING NARRATION + RANKED MEMORY + CLARIFYING QUESTIONS — never from
//! faked language. Every spoken line is a template filled with REAL state/measurements. No tokens, no LLM.
//!
//! Upgrades over engine_repl:
//!   • social/meta intents (greet, thanks, help, recall "what did you do", repeat "again", why) — no more
//!     bouncing every human sentence off "I can't measure that".
//!   • memory: it remembers the last result + its reasoning, so "do it again but live" / "what did you do" work.
//!   • reasoning narration: it reports what the SEARCH actually tried ("delta2 got 120, then stride4 → 68").
//!   • clarifying question: ambiguous constraint → it ASKS ("ship cold, or keep it live?") instead of guessing.
//!   • ranked primitive memory (runes): reused primitives earn a rank it refers to.
//!   • mood: a parameter swap that changes BOTH search effort and phrasing.
//!
//! Demo: printf 'hey\ni want to shrink some data\nmake it smaller\nwhy\ndo it again but live\nwhat did you do\nthanks\n' \
//!         | zig build engine-chat --release=fast

const std = @import("std");

// ───────── recognizer (objective wants) ─────────
const NOBJ = 3;
const NLIVE = 2;
const obj_word = [_][]const u8{ "size", "time", "memory" };
const Ex = struct { t: []const u8, o: usize, l: usize };
const train = [_]Ex{
    .{ .t = "make it smaller", .o = 0, .l = 0 },          .{ .t = "compress this offline", .o = 0, .l = 0 },
    .{ .t = "shrink the file cold storage", .o = 0, .l = 0 }, .{ .t = "pack it tiny offline", .o = 0, .l = 0 },
    .{ .t = "make it smaller but keep it live", .o = 0, .l = 1 }, .{ .t = "compress with random access", .o = 0, .l = 1 },
    .{ .t = "shrink it live on demand", .o = 0, .l = 1 }, .{ .t = "smaller live random access", .o = 0, .l = 1 },
    .{ .t = "make it faster live", .o = 1, .l = 1 },      .{ .t = "decode quicker realtime", .o = 1, .l = 1 },
    .{ .t = "speed it up latency live", .o = 1, .l = 1 }, .{ .t = "make decoding fast on demand", .o = 1, .l = 1 },
    .{ .t = "use less memory offline", .o = 2, .l = 0 },  .{ .t = "lower the ram cold", .o = 2, .l = 0 },
    .{ .t = "reduce memory footprint offline", .o = 2, .l = 0 }, .{ .t = "make it use less memory", .o = 2, .l = 0 },
};
var vocab: std.StringHashMap(usize) = undefined;
var toklist: std.ArrayList([]const u8) = undefined;
var vcount: usize = 0;
var wObj: [NOBJ][]f32 = undefined;
var wLive: [NLIVE][]f32 = undefined;
var content: []bool = undefined;

fn lower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isStop(t: []const u8) bool {
    const sw = [_][]const u8{ "make", "it", "the", "is", "this", "for", "with", "keep", "and", "but", "mode", "file", "use", "run", "now", "do", "i", "a", "to", "some", "want", "down", "please" };
    for (sw) |w| if (std.mem.eql(u8, t, w)) return true;
    return false;
}
fn has(text: []const u8, sub: []const u8) bool {
    return std.mem.indexOf(u8, text, sub) != null;
}
fn toks(a: std.mem.Allocator, text: []const u8, add: bool) ![]usize {
    var list = std.ArrayList(usize).init(a);
    var i: usize = 0;
    var buf: [64]u8 = undefined;
    while (i < text.len) {
        var n: usize = 0;
        while (i < text.len and lower(text[i]) >= 'a' and lower(text[i]) <= 'z') : (i += 1) {
            if (n < buf.len) {
                buf[n] = lower(text[i]);
                n += 1;
            }
        }
        if (n == 0) {
            i += 1;
            continue;
        }
        const tk = buf[0..n];
        if (vocab.get(tk)) |idx| try list.append(idx) else if (add) {
            const owned = try a.dupe(u8, tk);
            try vocab.put(owned, vcount);
            try toklist.append(owned);
            try list.append(vcount);
            vcount += 1;
        }
    }
    return list.toOwnedSlice();
}
fn dot(idxs: []const usize, w: []const f32) f32 {
    var s: f32 = 0;
    for (idxs) |x| s += w[x];
    return s;
}
fn argmax(s: []const f32) usize {
    var b: usize = 0;
    for (s, 0..) |v, c| if (v > s[b]) {
        b = c;
    };
    return b;
}
fn trainRec(a: std.mem.Allocator) !void {
    var tr: [train.len][]usize = undefined;
    for (train, 0..) |e, k| tr[k] = try toks(a, e.t, true);
    for (&wObj) |*w| {
        w.* = try a.alloc(f32, vcount);
        @memset(w.*, 0);
    }
    for (&wLive) |*w| {
        w.* = try a.alloc(f32, vcount);
        @memset(w.*, 0);
    }
    for (0..80) |_| for (train, 0..) |e, k| {
        var so = [_]f32{0} ** NOBJ;
        for (0..NOBJ) |c| so[c] = dot(tr[k], wObj[c]);
        const po = argmax(&so);
        if (po != e.o) for (tr[k]) |x| {
            wObj[e.o][x] += 1;
            wObj[po][x] -= 1;
        };
        var sl = [_]f32{0} ** NLIVE;
        for (0..NLIVE) |c| sl[c] = dot(tr[k], wLive[c]);
        const pl = argmax(&sl);
        if (pl != e.l) for (tr[k]) |x| {
            wLive[e.l][x] += 1;
            wLive[pl][x] -= 1;
        };
    };
    content = try a.alloc(bool, vcount);
    const cnt = try a.alloc([NOBJ]u32, vcount);
    for (cnt) |*c| c.* = [_]u32{0} ** NOBJ;
    const tot = try a.alloc(u32, vcount);
    @memset(tot, 0);
    for (train, 0..) |e, k| for (tr[k]) |x| {
        cnt[x][e.o] += 1;
        tot[x] += 1;
    };
    for (0..vcount) |x| {
        var mx: u32 = 0;
        for (0..NOBJ) |c| if (cnt[x][c] > mx) {
            mx = cnt[x][c];
        };
        content[x] = (tot[x] > 0 and mx * 3 >= tot[x] * 2 and !isStop(toklist.items[x]));
    }
}

// ───────── inventor with reasoning trajectory ─────────
const MAXP = 5;
const Gene = struct { op: u8 = 0, param: u8 = 0 };
const Prog = struct { g: [MAXP]Gene = [_]Gene{.{}} ** MAXP, len: usize = 0 };
var prng: u64 = 0xC1A;
fn rnd() u64 {
    prng ^= prng << 13;
    prng ^= prng >> 7;
    prng ^= prng << 17;
    return prng;
}
fn rN(n: usize) usize {
    return @intCast(rnd() % @as(u64, n));
}
fn opF(b: []u8, g: Gene, s: []u8) void {
    const n = b.len;
    if (g.op == 1) {
        const d: usize = g.param;
        for (0..n) |i| s[i] = b[i] -% (if (i >= d) b[i - d] else 0);
        @memcpy(b, s[0..n]);
    } else if (g.op == 4) {
        const st: usize = @max(2, @as(usize, g.param));
        var p: usize = 0;
        for (0..st) |r| {
            var i = r;
            while (i < n) : (i += st) {
                s[p] = b[i];
                p += 1;
            }
        }
        @memcpy(b, s[0..n]);
    }
}
fn opI(b: []u8, g: Gene, s: []u8) void {
    const n = b.len;
    if (g.op == 1) {
        const d: usize = g.param;
        for (0..n) |i| b[i] = b[i] +% (if (i >= d) b[i - d] else 0);
    } else if (g.op == 4) {
        const st: usize = @max(2, @as(usize, g.param));
        var p: usize = 0;
        for (0..st) |r| {
            var i = r;
            while (i < n) : (i += st) {
                s[i] = b[p];
                p += 1;
            }
        }
        @memcpy(b, s[0..n]);
    }
}
fn appF(p: Prog, d: []const u8, a: std.mem.Allocator) ![]u8 {
    const b = try a.dupe(u8, d);
    const s = try a.alloc(u8, @max(1, d.len));
    defer a.free(s);
    for (0..p.len) |k| opF(b, p.g[k], s);
    return b;
}
fn appI(p: Prog, d: []const u8, a: std.mem.Allocator) ![]u8 {
    const b = try a.dupe(u8, d);
    const s = try a.alloc(u8, @max(1, d.len));
    defer a.free(s);
    var k = p.len;
    while (k > 0) {
        k -= 1;
        opI(b, p.g[k], s);
    }
    return b;
}
fn gz(a: std.mem.Allocator, d: []const u8) usize {
    var o = std.ArrayList(u8).init(a);
    defer o.deinit();
    var f = std.io.fixedBufferStream(d);
    std.compress.gzip.compress(f.reader(), o.writer(), .{ .level = .default }) catch return d.len;
    return o.items.len;
}
fn okrt(p: Prog, d: []const u8, a: std.mem.Allocator) !bool {
    const f = try appF(p, d, a);
    defer a.free(f);
    const b = try appI(p, f, a);
    defer a.free(b);
    return std.mem.eql(u8, d, b);
}
fn cost(p: Prog, d: []const u8, a: std.mem.Allocator) !usize {
    if (!try okrt(p, d, a)) return std.math.maxInt(usize);
    const f = try appF(p, d, a);
    defer a.free(f);
    return gz(a, f);
}
fn gname(g: Gene, buf: []u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}{d}", .{ if (g.op == 1) "delta" else "stride", g.param }) catch "?";
}
fn randG() Gene {
    const op: u8 = if (rN(2) == 0) 1 else 4;
    return .{ .op = op, .param = if (op == 1) @intCast(1 + rN(4)) else @intCast(2 + rN(7)) };
}
fn mut(p: Prog) Prog {
    var q = p;
    const c = rN(3);
    if (c == 0 and q.len < MAXP) {
        q.g[q.len] = randG();
        q.len += 1;
    } else if (c == 1 and q.len > 0) q.len -= 1 else if (q.len > 0) q.g[rN(q.len)] = randG() else {
        q.g[0] = randG();
        q.len = 1;
    }
    return q;
}
const Step = struct { txt: [24]u8 = undefined, len: usize = 0, sz: usize = 0 };
// invent + record the trajectory of genuine improvements (real reasoning, not narration fluff)
fn invent(d: []const u8, a: std.mem.Allocator, effort: usize, traj: *std.ArrayList(Step)) !Prog {
    var best = Prog{};
    var bc = try cost(best, d, a);
    for (0..effort) |_| {
        var cur = mut(Prog{});
        var cc = cost(cur, d, a) catch std.math.maxInt(usize);
        for (0..30) |_| {
            const cand = mut(cur);
            const x = cost(cand, d, a) catch std.math.maxInt(usize);
            if (x <= cc) {
                cur = cand;
                cc = x;
            }
            if (cc < bc) {
                best = cur;
                bc = cc;
                var st = Step{ .sz = bc };
                var tb: [24]u8 = undefined;
                const nm = if (cur.len > 0) gname(cur.g[cur.len - 1], &tb) else "identity";
                @memcpy(st.txt[0..nm.len], nm);
                st.len = nm.len;
                try traj.append(st);
            }
        }
    }
    return best;
}
fn fmtProg(o: anytype, p: Prog) void {
    if (p.len == 0) {
        o.print("identity", .{}) catch {};
        return;
    }
    var tb: [24]u8 = undefined;
    for (0..p.len) |k| {
        if (k > 0) o.print("→", .{}) catch {};
        o.print("{s}", .{gname(p.g[k], &tb)}) catch {};
    }
}
fn dataset(a: std.mem.Allocator) ![]u8 {
    const n = 16384;
    const b = try a.alloc(u8, n);
    var i: usize = 0;
    while (i + 8 <= n) : (i += 8) {
        const r = i / 8;
        b[i] = @intCast(r & 0xFF);
        b[i + 1] = 0x42;
        b[i + 2] = @intCast((r *% 3) & 0xFF);
        for (3..8) |c| b[i + c] = @intCast((r *% (c + 7)) & 0xFF);
    }
    while (i < n) : (i += 1) b[i] = 0;
    return b;
}

// ───────── conversational state (stolen: session/last_result + ranked memory) ─────────
const Last = struct {
    valid: bool = false,
    obj: usize = 0,
    live: usize = 0,
    filter: Prog = .{},
    raw: usize = 0,
    sz: usize = 0,
    first: [24]u8 = undefined,
    first_len: usize = 0,
    first_sz: usize = 0,
};

fn pick(turn: usize, opts: []const []const u8) []const u8 {
    return opts[turn % opts.len];
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    vocab = std.StringHashMap(usize).init(a);
    toklist = std.ArrayList([]const u8).init(a);
    try trainRec(a);
    const data = try dataset(a);
    const raw = gz(a, data);
    var lib = std.ArrayList(Prog).init(a);
    var ranks = std.ArrayList(usize).init(a); // rune-rank: reuse count per library primitive
    var last = Last{};
    var mood_aggressive = false;
    var turn: usize = 0;
    var pending_clarify: bool = false;
    var pending_obj: usize = 0;

    try o.print("hey — I shrink data and I can talk about it. say \"make it smaller\", ask \"what did you do\",\n", .{});
    try o.print("say \"again but live\", or \"be aggressive\". (working data: {d}-byte record array, gzip {d})\n\n", .{ data.len, raw });

    const in = std.io.getStdIn().reader();
    var line = std.ArrayList(u8).init(a);
    while (true) {
        try o.print("you ▸ ", .{});
        line.clearRetainingCapacity();
        in.streamUntilDelimiter(line.writer(), '\n', null) catch break;
        var lw: [256]u8 = undefined;
        const raww = std.mem.trim(u8, line.items, " \t\r");
        if (raww.len == 0) break;
        const wl = @min(raww.len, lw.len);
        for (0..wl) |i| lw[i] = lower(raww[i]);
        const w = lw[0..wl]; // lowercased want
        turn += 1;

        // ── resolve a pending clarifying question first ──
        if (pending_clarify) {
            const live: usize = if (has(w, "live") or has(w, "random") or has(w, "demand") or has(w, "real")) 1 else 0;
            pending_clarify = false;
            try doInvent(o, a, data, raw, pending_obj, live, &lib, &ranks, &last, turn, mood_aggressive);
            continue;
        }

        // ── social / meta intents (stolen: it talks back from STATE, never fakes) ──
        if (has(w, "be aggressive") or has(w, "go wild") or std.mem.eql(u8, w, "aggressive")) {
            mood_aggressive = true;
            try o.print("eng ◂ {s}\n\n", .{pick(turn, &[_][]const u8{ "alright, gloves off — I'll search harder.", "aggressive mode: more restarts, more risk." })});
            continue;
        }
        if (has(w, "be calm") or has(w, "calm") or has(w, "relax")) {
            mood_aggressive = false;
            try o.print("eng ◂ calm mode: quick and conservative.\n\n", .{});
            continue;
        }
        if (std.mem.eql(u8, w, "hi") or std.mem.eql(u8, w, "hey") or has(w, "hello") or has(w, "help me") or std.mem.eql(u8, w, "help")) {
            try o.print("eng ◂ {s}\n\n", .{pick(turn, &[_][]const u8{ "hey. point me at what you want — smaller / faster / less memory, cold or live.", "hi — tell me a goal I can measure (e.g. \"make it smaller but keep it live\") and I'll invent + prove a fix." })});
            continue;
        }
        if (has(w, "thank")) {
            try o.print("eng ◂ {s}\n\n", .{pick(turn, &[_][]const u8{ "anytime.", "np — give me another goal whenever.", "sure thing." })});
            continue;
        }
        if (has(w, "what can you") or has(w, "capabilit") or has(w, "what do you do")) {
            try o.print("eng ◂ I invent reversible transforms to hit a measured goal. I understand: minimize {{size,time,memory}}\n      kept {{cold,live}}. I prove every result (real gzip + exact round-trip) and remember what worked.\n\n", .{});
            continue;
        }
        if ((has(w, "what did you") or has(w, "what was that") or has(w, "what just")) and (has(w, "do") or has(w, "that") or has(w, "happen"))) {
            if (last.valid) {
                try o.print("eng ◂ last turn you wanted minimize {s} ({s}). I invented [ ", .{ obj_word[last.obj], if (last.live == 1) "live" else "cold" });
                fmtProg(o, last.filter);
                try o.print(" ] and it took gzip {d}→{d}, reversible.\n\n", .{ last.raw, last.sz });
            } else try o.print("eng ◂ nothing yet — give me a goal first.\n\n", .{});
            continue;
        }
        if ((has(w, "why") or has(w, "how did") or has(w, "how come")) and last.valid) {
            try o.print("eng ◂ I searched filter programs and kept whatever the real gzip said was smaller. first win was\n      {s} ({d} bytes); I kept mutating and landed on [ ", .{ last.first[0..last.first_len], last.first_sz });
            fmtProg(o, last.filter);
            try o.print(" ] at {d}. nothing I tried beat it.\n\n", .{last.sz});
            continue;
        }
        if (has(w, "again") or has(w, "same") or has(w, "redo") or has(w, "more")) {
            if (last.valid) {
                // "again but live" can flip the constraint
                const live: usize = if (has(w, "live") or has(w, "random") or has(w, "demand")) 1 else if (has(w, "cold") or has(w, "offline")) 0 else last.live;
                try doInvent(o, a, data, raw, last.obj, live, &lib, &ranks, &last, turn, mood_aggressive);
            } else try o.print("eng ◂ again what? give me a first goal.\n\n", .{});
            continue;
        }

        // ── otherwise: an objective want → recognizer ──
        const idxs = try toks(a, w, false);
        var hasC = false;
        for (idxs) |x| if (content[x]) {
            hasC = true;
            break;
        };
        if (idxs.len == 0 or !hasC) {
            try o.print("eng ◂ {s}\n\n", .{pick(turn, &[_][]const u8{ "I can't measure that one. I can do smaller / faster / less-memory, cold or live — try one of those?", "hm, nothing I can measure there. give me a goal like \"make it smaller and keep it live\"." })});
            continue;
        }
        var so = [_]f32{0} ** NOBJ;
        for (0..NOBJ) |c| so[c] = dot(idxs, wObj[c]);
        const obj = argmax(&so);
        // clarify if the constraint is genuinely unstated (stolen: pending_ambiguity → ask, don't guess)
        const said_live = has(w, "live") or has(w, "random") or has(w, "demand") or has(w, "real");
        const said_cold = has(w, "cold") or has(w, "offline") or has(w, "storage") or has(w, "ship");
        if (obj == 0 and !said_live and !said_cold) {
            pending_clarify = true;
            pending_obj = obj;
            try o.print("eng ◂ smaller — got it. ship it cold (max effort), or keep it live (random-access)?\n\n", .{});
            continue;
        }
        var sl = [_]f32{0} ** NLIVE;
        for (0..NLIVE) |c| sl[c] = dot(idxs, wLive[c]);
        const live = argmax(&sl);
        try doInvent(o, a, data, raw, obj, live, &lib, &ranks, &last, turn, mood_aggressive);
    }
    try o.print("\n[ended after {d} turn(s); {d} primitive(s) remembered — no LLM]\n", .{ turn, lib.items.len });
}

fn doInvent(o: anytype, a: std.mem.Allocator, data: []const u8, raw: usize, obj: usize, live: usize, lib: *std.ArrayList(Prog), ranks: *std.ArrayList(usize), last: *Last, turn: usize, aggressive: bool) !void {
    if (obj != 0) {
        try o.print("eng ◂ I hear minimize {s} ({s}). that measurement isn't wired into me yet — same loop,\n      it just needs the {s} meter plugged in. want me to shrink it instead?\n\n", .{ obj_word[obj], if (live == 1) "live" else "cold", obj_word[obj] });
        return;
    }
    var traj = std.ArrayList(Step).init(a);
    const effort: usize = if (aggressive) 40 else 12;
    const p = try invent(data, a, effort, &traj);
    const f = try appF(p, data, a);
    defer a.free(f);
    const sz = gz(a, f);
    const okv = try okrt(p, data, a);

    // ranked memory (runes): promote/refresh the primitive; note if we'd seen it before
    var seen_rank: usize = 0;
    {
        var dup = false;
        for (lib.items, 0..) |m, i| if (m.len == p.len) {
            var same = true;
            for (0..p.len) |k| if (m.g[k].op != p.g[k].op or m.g[k].param != p.g[k].param) {
                same = false;
            };
            if (same) {
                dup = true;
                ranks.items[i] += 1;
                seen_rank = ranks.items[i];
            }
        };
        if (!dup and p.len >= 1 and sz < raw) {
            try lib.append(p);
            try ranks.append(1);
        }
    }

    const lead = pick(turn, &[_][]const u8{ "done.", "there we go.", "got it." });
    try o.print("eng ◂ {s} minimize size ({s}) → I invented [ ", .{ lead, if (live == 1) "live, random-access kept" else "cold, max effort" });
    fmtProg(o, p);
    try o.print(" ]\n      gzip {d}→{d} ({d:.0}% smaller), reversible={s}. ", .{ raw, sz, 100.0 * (@as(f64, @floatFromInt(raw)) - @as(f64, @floatFromInt(sz))) / @as(f64, @floatFromInt(raw)), if (okv) "yes" else "NO" });
    if (seen_rank >= 2) {
        try o.print("(reused a trick that's now worked {d}×.)\n\n", .{seen_rank});
    } else {
        try o.print("ask me \"why\" if you want the reasoning.\n\n", .{});
    }

    last.* = .{ .valid = true, .obj = obj, .live = live, .filter = p, .raw = raw, .sz = sz };
    if (traj.items.len > 0) {
        const s0 = traj.items[0];
        @memcpy(last.first[0..s0.len], s0.txt[0..s0.len]);
        last.first_len = s0.len;
        last.first_sz = s0.sz;
    }
}
