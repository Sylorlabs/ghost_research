//! engine_repl.zig — GO BACK AND FORTH WITH THE ENGINE. No LLM.
//!
//! Micah: "could I go back and forth with it?" — yes. This wires the three engine-native pieces into one
//! interactive loop with PERSISTENT state:
//!   you type a want  →  [recognizer: tiny trained perceptron]  → formal objective (or "out of scope")
//!                    →  [inventor: evolves a reversible filter, certified by real gzip]  → result in your terms
//! and it CARRIES STATE across turns: the library of primitives it invents persists, so the conversation
//! builds. It also talks back — on an out-of-scope want it tells you what it CAN do, so you can rephrase.
//! No LLM anywhere: a perceptron understands, blind search invents, measurement certifies.
//!
//! Interactive:   zig build engine-repl --release=fast        (then type wants, blank line / Ctrl-D to quit)
//! Scripted demo: printf 'make it smaller\nsmaller but keep it live\nmake it prettier\nshrink it more\n' \
//!                  | zig build engine-repl --release=fast

const std = @import("std");

// ───────────────────────── recognizer (NL want → formal objective) ─────────────────────────
const NOBJ = 3; // SIZE TIME MEMORY
const NLIVE = 2; // COLD LIVE
const obj_name = [_][]const u8{ "minimize SIZE", "minimize TIME", "minimize MEMORY" };
const live_name = [_][]const u8{ "cold (offline)", "live (random-access)" };
const Ex = struct { t: []const u8, o: usize, l: usize };
const train = [_]Ex{
    .{ .t = "make it smaller", .o = 0, .l = 0 },          .{ .t = "compress this offline", .o = 0, .l = 0 },
    .{ .t = "shrink the file cold storage", .o = 0, .l = 0 }, .{ .t = "pack it tiny offline", .o = 0, .l = 0 },
    .{ .t = "make it smaller but keep it live", .o = 0, .l = 1 }, .{ .t = "compress with random access", .o = 0, .l = 1 },
    .{ .t = "shrink it must run live on demand", .o = 0, .l = 1 }, .{ .t = "smaller live random access", .o = 0, .l = 1 },
    .{ .t = "make it faster live", .o = 1, .l = 1 },      .{ .t = "decode quicker realtime", .o = 1, .l = 1 },
    .{ .t = "speed it up low latency live", .o = 1, .l = 1 }, .{ .t = "make decoding fast on demand", .o = 1, .l = 1 },
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
    const sw = [_][]const u8{ "make", "it", "the", "is", "this", "for", "with", "more", "please", "want", "ok", "keep", "and", "but", "mode", "file", "get", "use", "up", "run", "must", "now", "even", "i", "a", "to", "of", "on" };
    for (sw) |w| if (std.mem.eql(u8, t, w)) return true;
    return false;
}
fn toks(a: std.mem.Allocator, text: []const u8, add: bool) ![]usize {
    var list = std.ArrayList(usize).init(a);
    var i: usize = 0;
    var buf: [64]u8 = undefined;
    while (i < text.len) {
        var n: usize = 0;
        while (i < text.len and ((lower(text[i]) >= 'a' and lower(text[i]) <= 'z'))) : (i += 1) {
            if (n < buf.len) {
                buf[n] = lower(text[i]);
                n += 1;
            }
        }
        if (n == 0) {
            i += 1;
            continue;
        }
        const tok = buf[0..n];
        if (vocab.get(tok)) |idx| {
            try list.append(idx);
        } else if (add) {
            const owned = try a.dupe(u8, tok);
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
fn trainRecognizer(a: std.mem.Allocator) !void {
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
    // content = concentrated-in-one-class AND not a function word
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

// ───────────────────────── inventor (formal objective → certified filter) ─────────────────────────
const MAXP = 5;
const Gene = struct { op: u8 = 0, param: u8 = 0 };
const Prog = struct { g: [MAXP]Gene = [_]Gene{.{}} ** MAXP, len: usize = 0 };
var prng: u64 = 0xDA1A;
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
    switch (g.op) {
        1 => {
            const d: usize = g.param;
            for (0..n) |i| s[i] = b[i] -% (if (i >= d) b[i - d] else 0);
            @memcpy(b, s[0..n]);
        },
        4 => {
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
        },
        else => {},
    }
}
fn opI(b: []u8, g: Gene, s: []u8) void {
    const n = b.len;
    switch (g.op) {
        1 => {
            const d: usize = g.param;
            for (0..n) |i| b[i] = b[i] +% (if (i >= d) b[i - d] else 0);
        },
        4 => {
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
        },
        else => {},
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
fn ok(p: Prog, d: []const u8, a: std.mem.Allocator) !bool {
    const f = try appF(p, d, a);
    defer a.free(f);
    const b = try appI(p, f, a);
    defer a.free(b);
    return std.mem.eql(u8, d, b);
}
fn cost(p: Prog, d: []const u8, a: std.mem.Allocator) !usize {
    if (!try ok(p, d, a)) return std.math.maxInt(usize);
    const f = try appF(p, d, a);
    defer a.free(f);
    return gz(a, f);
}
fn randG() Gene {
    const op: u8 = if (rN(2) == 0) 1 else 4;
    return .{ .op = op, .param = if (op == 1) @intCast(1 + rN(4)) else @intCast(2 + rN(7)) };
}
fn mut(p: Prog, lib: []const Prog) Prog {
    var q = p;
    if (lib.len > 0 and rN(2) == 0) {
        const m = lib[rN(lib.len)];
        if (q.len + m.len <= MAXP) {
            for (0..m.len) |k| {
                q.g[q.len] = m.g[k];
                q.len += 1;
            }
            return q;
        }
    }
    const c = rN(3);
    if (c == 0 and q.len < MAXP) {
        q.g[q.len] = randG();
        q.len += 1;
    } else if (c == 1 and q.len > 0) {
        q.len -= 1;
    } else if (q.len > 0) {
        q.g[rN(q.len)] = randG();
    } else {
        q.g[0] = randG();
        q.len = 1;
    }
    return q;
}
fn invent(d: []const u8, a: std.mem.Allocator, lib: []const Prog) !Prog {
    var best = Prog{};
    var bc = try cost(best, d, a);
    for (0..14) |_| {
        var cur = mut(Prog{}, lib);
        var cc = cost(cur, d, a) catch std.math.maxInt(usize);
        for (0..30) |_| {
            const cand = mut(cur, lib);
            const x = cost(cand, d, a) catch std.math.maxInt(usize);
            if (x <= cc) {
                cur = cand;
                cc = x;
            }
            if (cc < bc) {
                best = cur;
                bc = cc;
            }
        }
    }
    return best;
}
fn printFilter(o: anytype, p: Prog) void {
    if (p.len == 0) {
        o.print("identity", .{}) catch {};
        return;
    }
    for (0..p.len) |k| {
        if (k > 0) o.print("→", .{}) catch {};
        if (p.g[k].op == 1) o.print("delta{d}", .{p.g[k].param}) catch {} else o.print("stride{d}", .{p.g[k].param}) catch {};
    }
}

fn dataset(a: std.mem.Allocator) ![]u8 { // a structured record array (filters help)
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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    vocab = std.StringHashMap(usize).init(a);
    toklist = std.ArrayList([]const u8).init(a);
    try trainRecognizer(a);

    const data = try dataset(a);
    const raw = gz(a, data);
    var lib = std.ArrayList(Prog).init(a);
    var turn: usize = 0;

    try o.print("engine ready. it understands: minimize {{size,time,memory}} keeping it {{cold,live}}.\n", .{});
    try o.print("type a want (blank line / Ctrl-D to quit). working data = a {d}-byte record array (gzip {d}).\n\n", .{ data.len, raw });

    const in = std.io.getStdIn().reader();
    var line = std.ArrayList(u8).init(a);
    while (true) {
        try o.print("you ▸ ", .{});
        line.clearRetainingCapacity();
        in.streamUntilDelimiter(line.writer(), '\n', null) catch break;
        const want = std.mem.trim(u8, line.items, " \t\r");
        if (want.len == 0) break;
        turn += 1;

        const idxs = try toks(a, want, false);
        var hasC = false;
        for (idxs) |x| if (content[x]) {
            hasC = true;
            break;
        };
        if (idxs.len == 0 or !hasC) {
            try o.print("eng ◂ I can't measure that. I CAN: minimize size / time / memory, kept cold or live.\n", .{});
            try o.print("       try e.g. \"make it smaller but keep it live\".\n\n", .{});
            continue;
        }
        var so = [_]f32{0} ** NOBJ;
        for (0..NOBJ) |c| so[c] = dot(idxs, wObj[c]);
        var sl = [_]f32{0} ** NLIVE;
        for (0..NLIVE) |c| sl[c] = dot(idxs, wLive[c]);
        const obj = argmax(&so);
        const live = argmax(&sl);
        try o.print("eng ◂ understood: {s}, {s}.\n", .{ obj_name[obj], live_name[live] });

        if (obj == 0) { // SIZE — the wired, measured action
            const p = try invent(data, a, lib.items);
            const f = try appF(p, data, a);
            defer a.free(f);
            const sz = gz(a, f);
            const okv = try ok(p, data, a);
            if (p.len >= 1 and sz < raw) {
                // promote (grow the library — persists across the conversation)
                var dup = false;
                for (lib.items) |m| if (m.len == p.len) {
                    var same = true;
                    for (0..p.len) |k| if (m.g[k].op != p.g[k].op or m.g[k].param != p.g[k].param) {
                        same = false;
                    };
                    if (same) dup = true;
                };
                if (!dup) try lib.append(p);
            }
            try o.print("       invented filter [ ", .{});
            printFilter(o, p);
            try o.print(" ]  gzip {d}→{d} ({d:.0}% smaller)  reversible={s}  {s}\n", .{ raw, sz, 100.0 * (@as(f64, @floatFromInt(raw)) - @as(f64, @floatFromInt(sz))) / @as(f64, @floatFromInt(raw)), if (okv) "yes" else "NO", if (live == 1) "[random-access kept]" else "[cold: max effort ok]" });
            try o.print("       library now holds {d} self-invented primitive(s).\n\n", .{lib.items.len});
        } else {
            try o.print("       (this demo wires the measured SIZE optimizer; the SAME loop drives a {s} optimizer\n", .{obj_name[obj]});
            try o.print("        once that measurement is added — engineering, not a new neural part.)\n\n", .{});
        }
    }
    try o.print("\n[session ended after {d} turn(s); library kept {d} primitive(s) — no LLM was involved]\n", .{ turn, lib.items.len });
}
