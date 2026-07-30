//! engine_live.zig — CHAT with it, and it LEARNS FROM TERMINAL OUTPUTS. No LLM.
//!
//! Micah: by the end I should be able to chat with it; and it should learn from terminal outputs — "it noticed
//! this happened when it ran A and B happened instead of the expected A." That is an EXPECTATION VIOLATION, and
//! the web research backs it: RLVR (RL from Verifiable Rewards) + the cognitive finding that expectancy-violating
//! outcomes are learned BEST. The terminal IS a verifier — the engine is native to it.
//!
//! This is a runnable chat. It does three real things, all grounded, no faked language:
//!   • INVENTS (shrinks the working data by searching + certifying with real gzip).
//!   • LEARNS FROM TERMINAL RUNS: tell it  "learn: ran <cmd> expected <X> got <Y>"  and it records the real
//!     outcome, FLAGS the surprise when Y≠X, and remembers the correction (reinforced by repeats).
//!   • RECALLS:  "predict <cmd>"  /  "what happens when i run <cmd>"  → answers from what it actually observed.
//!
//! Interactive:  zig build engine-live --release=fast    (then type; blank line / Ctrl-D quits)
//! Scripted demo: printf 'hey\nlearn: ran zig build expected ok got 3 errors\npredict zig build\nlearn: ran zig build expected ok got 3 errors\nmake it smaller\nwhat have you learned\n' | zig build engine-live --release=fast

const std = @import("std");

// ── minimal reversible inventor (for "make it smaller") ──
var prng: u64 = 0x11FE_0000_0001;
fn rnd() u64 {
    prng ^= prng << 13;
    prng ^= prng >> 7;
    prng ^= prng << 17;
    return prng;
}
fn rN(n: usize) usize {
    return @intCast(rnd() % @as(u64, @max(1, n)));
}
const MAXP = 3;
const Gene = struct { op: u8 = 0, param: u8 = 0 };
const Prog = struct { g: [MAXP]Gene = [_]Gene{.{}} ** MAXP, len: usize = 0 };
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
fn appF(p: Prog, d: []const u8, a: std.mem.Allocator) ![]u8 {
    const b = try a.dupe(u8, d);
    const s = try a.alloc(u8, @max(1, d.len));
    defer a.free(s);
    for (0..p.len) |k| opF(b, p.g[k], s);
    return b;
}
fn gz(a: std.mem.Allocator, d: []const u8) usize {
    var o = std.ArrayList(u8).init(a);
    defer o.deinit();
    var f = std.io.fixedBufferStream(d);
    std.compress.gzip.compress(f.reader(), o.writer(), .{ .level = .default }) catch return d.len;
    return o.items.len;
}
fn invent(d: []const u8, a: std.mem.Allocator, base: usize, outp: *Prog) !usize {
    var best = Prog{};
    var bc = base;
    for (0..8) |_| {
        var cur = Prog{ .len = 1 };
        cur.g[0] = if (rN(2) == 0) .{ .op = 1, .param = @intCast(1 + rN(4)) } else .{ .op = 4, .param = @intCast(2 + rN(15)) };
        for (0..14) |_| {
            var q = cur;
            if (q.len < MAXP and rN(2) == 0) {
                q.g[q.len] = if (rN(2) == 0) .{ .op = 1, .param = @intCast(1 + rN(4)) } else .{ .op = 4, .param = @intCast(2 + rN(15)) };
                q.len += 1;
            } else q.g[rN(q.len)] = if (rN(2) == 0) .{ .op = 1, .param = @intCast(1 + rN(4)) } else .{ .op = 4, .param = @intCast(2 + rN(15)) };
            const f = try appF(q, d, a);
            defer a.free(f);
            const c = gz(a, f);
            if (c < bc) {
                bc = c;
                best = q;
                cur = q;
            }
        }
    }
    outp.* = best;
    return bc;
}
fn fmtProg(buf: []u8, p: Prog) []const u8 {
    if (p.len == 0) return "identity";
    var w: usize = 0;
    for (0..p.len) |k| {
        if (k > 0 and w < buf.len) {
            buf[w] = '>';
            w += 1;
        }
        const part = std.fmt.bufPrint(buf[w..], "{s}{d}", .{ if (p.g[k].op == 1) "d" else "s", p.g[k].param }) catch break;
        w += part.len;
    }
    return buf[0..w];
}

// ── terminal-outcome memory (verification learning: command → observed outcome, surprise-flagged) ──
const Obs = struct { cmd: []const u8, outcome: []const u8, occ: u32, surprised: bool };

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}
fn after(s: []const u8, marker: []const u8) ?[]const u8 {
    const i = std.mem.indexOf(u8, s, marker) orelse return null;
    return s[i + marker.len ..];
}
fn before(s: []const u8, marker: []const u8) []const u8 {
    const i = std.mem.indexOf(u8, s, marker) orelse return s;
    return s[0..i];
}
fn has(s: []const u8, sub: []const u8) bool {
    return std.mem.indexOf(u8, s, sub) != null;
}

fn genData(a: std.mem.Allocator) ![]u8 {
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
    const data = try genData(a);
    const raw = gz(a, data);
    var term = std.ArrayList(Obs).init(a);

    try o.print("hey. I can SHRINK data (\"make it smaller\"), and I LEARN from terminal runs:\n", .{});
    try o.print("  teach me:  learn: ran <cmd> expected <X> got <Y>\n  ask me:    predict <cmd>\n", .{});
    try o.print("(working data: {d}-byte record array, gzip {d}). blank line / Ctrl-D to quit.\n\n", .{ data.len, raw });

    const in = std.io.getStdIn().reader();
    var line = std.ArrayList(u8).init(a);
    while (true) {
        try o.print("you ▸ ", .{});
        line.clearRetainingCapacity();
        in.streamUntilDelimiter(line.writer(), '\n', null) catch break;
        const w = trim(line.items);
        if (w.len == 0) break;
        var lw = try a.alloc(u8, w.len);
        for (0..w.len) |i| lw[i] = if (w[i] >= 'A' and w[i] <= 'Z') w[i] + 32 else w[i];

        // ── LEARN FROM TERMINAL: "learn: ran <cmd> expected <X> got <Y>" ──
        if (std.mem.startsWith(u8, lw, "learn:") and after(lw, "ran ") != null) {
            const rest = after(lw, "ran ").?;
            const cmd = trim(before(rest, " expected "));
            const exp = if (after(rest, " expected ")) |e| trim(before(e, " got ")) else "";
            const got = if (after(rest, " got ")) |g| trim(g) else "";
            if (cmd.len == 0 or got.len == 0) {
                try o.print("eng ◂ tell me like: learn: ran <cmd> expected <X> got <Y>\n\n", .{});
                continue;
            }
            const surprise = exp.len > 0 and !std.mem.eql(u8, exp, got);
            var found = false;
            for (term.items) |*ob| if (std.mem.eql(u8, ob.cmd, cmd)) {
                found = true;
                ob.occ += 1;
                ob.surprised = ob.surprised or surprise;
                ob.outcome = try a.dupe(u8, got); // learn the REAL outcome (the correction)
            };
            if (!found) try term.append(.{ .cmd = try a.dupe(u8, cmd), .outcome = try a.dupe(u8, got), .occ = 1, .surprised = surprise });
            if (surprise) {
                try o.print("eng ◂ surprise noted: I'd have expected \"{s}\" too, but \"{s}\" actually produces \"{s}\".\n      I'll remember the real outcome and trust it over the expectation.\n\n", .{ exp, cmd, got });
            } else {
                var oc: u32 = 1;
                for (term.items) |ob| if (std.mem.eql(u8, ob.cmd, cmd)) {
                    oc = ob.occ;
                };
                try o.print("eng ◂ logged: \"{s}\" → \"{s}\" (confirmed, seen {d}×).\n\n", .{ cmd, got, oc });
            }
            continue;
        }
        // ── RECALL: "predict <cmd>" / "what happens when i run <cmd>" ──
        if (std.mem.startsWith(u8, lw, "predict ") or has(lw, "what happens") or has(lw, "will happen")) {
            const cmd = if (std.mem.startsWith(u8, lw, "predict ")) trim(lw["predict ".len..]) else if (after(lw, "run ")) |c| trim(c) else "";
            var found = false;
            for (term.items) |ob| if (cmd.len > 0 and std.mem.eql(u8, ob.cmd, cmd)) {
                try o.print("eng ◂ from what I've seen, \"{s}\" → \"{s}\" (seen {d}×{s}).\n\n", .{ ob.cmd, ob.outcome, ob.occ, if (ob.surprised) ", learned the hard way" else "" });
                found = true;
                break;
            };
            if (!found) try o.print("eng ◂ I haven't watched \"{s}\" run yet — teach me: learn: ran {s} expected <X> got <Y>\n\n", .{ cmd, cmd });
            continue;
        }
        // ── what have you learned ──
        if (has(lw, "what have you learned") or has(lw, "what do you know")) {
            if (term.items.len == 0) try o.print("eng ◂ nothing from the terminal yet.\n\n", .{}) else {
                try o.print("eng ◂ terminal outcomes I've learned:\n", .{});
                for (term.items) |ob| try o.print("        {s} → {s}  (seen {d}×{s})\n", .{ ob.cmd, ob.outcome, ob.occ, if (ob.surprised) ", was a surprise" else "" });
                try o.print("\n", .{});
            }
            continue;
        }
        // ── INVENT: shrink ──
        if (has(lw, "smaller") or has(lw, "shrink") or has(lw, "compress")) {
            var p = Prog{};
            const sz = try invent(data, a, raw, &p);
            var fb: [24]u8 = undefined;
            try o.print("eng ◂ invented [{s}] → gzip {d}→{d} ({d:.0}% smaller), reversible.\n\n", .{ fmtProg(&fb, p), raw, sz, 100.0 * (@as(f64, @floatFromInt(raw)) - @as(f64, @floatFromInt(sz))) / @as(f64, @floatFromInt(raw)) });
            continue;
        }
        if (std.mem.eql(u8, lw, "hi") or std.mem.eql(u8, lw, "hey") or has(lw, "hello") or has(lw, "help")) {
            try o.print("eng ◂ hey — try \"make it smaller\", or teach me a terminal fact: learn: ran <cmd> expected <X> got <Y>\n\n", .{});
            continue;
        }
        try o.print("eng ◂ I can shrink data or learn from terminal runs. say \"make it smaller\" or \"learn: ran ...\".\n\n", .{});
    }
    try o.print("\n[bye — I learned {d} terminal outcome(s) this session]\n", .{term.items.len});
}
