//! engine_converse.zig — conversation that feels NATURAL, no LLM. Retrieval + compositional assembly.
//!
//! Micah picked: make it converse better without an LLM (eyes open — capped below LLM fluency). The honest,
//! grounded method (the classic pre-LLM dialogue field: AIML/ALICE pattern-retrieval + phrasal templates +
//! trainable sentence-planning) modernized with what we built:
//!   • trained intent (not hardcoded keywords),
//!   • the SIGIL confidence (energy vs self-calibrated band) → assert when sure, HEDGE/ASK when not,
//!   • COMPOSITIONAL ASSEMBLY: each reply = open + body + close, drawn from banks of HUMAN-WRITTEN fragments,
//!     varied (no immediate repeats), with real values slotted in and conversation state referenced.
//! It feels natural because the fragments ARE natural; it can't babble because it never generates a word.
//! No tokens, no LLM. Honest ceiling: this is assembly/retrieval — more natural than rigid templates, never
//! LLM-fluent (that needs a language model).
//!
//! Interactive: zig build engine-converse --release=fast   |   scripted demo:
//!   printf 'hey\nmake it smaller\ndo it again\nwhat have we done\nflibber the wozzle\nthanks\n' | zig build engine-converse --release=fast

const std = @import("std");

var rng: u64 = 0x2024_C0FFEE;
fn rnd() u64 {
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}
// pick a fragment, avoiding the last one used for this bank (variation, not repetition)
fn pick(bank: []const []const u8, last: *usize) []const u8 {
    if (bank.len == 1) return bank[0];
    var i = rnd() % bank.len;
    if (i == last.*) i = (i + 1) % bank.len;
    last.* = i;
    return bank[i];
}

// ── trained intent (tiny perceptron) + sigil-style confidence ──
const NI = 5; // greet invent recall thanks oos
const Ex = struct { t: []const u8, i: u8 };
const train = [_]Ex{
    .{ .t = "hey", .i = 0 },                  .{ .t = "hi there", .i = 0 },             .{ .t = "yo", .i = 0 },         .{ .t = "hello", .i = 0 },          .{ .t = "good morning", .i = 0 },
    .{ .t = "make it smaller", .i = 1 },      .{ .t = "compress this", .i = 1 },        .{ .t = "shrink the file", .i = 1 }, .{ .t = "do it again", .i = 1 },  .{ .t = "squeeze it down", .i = 1 }, .{ .t = "make the data smaller", .i = 1 },
    .{ .t = "what have we done", .i = 2 },    .{ .t = "what did you do", .i = 2 },      .{ .t = "recap", .i = 2 },      .{ .t = "show me what happened", .i = 2 },
    .{ .t = "thanks", .i = 3 },               .{ .t = "thank you", .i = 3 },            .{ .t = "appreciate it", .i = 3 }, .{ .t = "cheers", .i = 3 },
};
var vocab: std.StringHashMap(usize) = undefined;
var vcount: usize = 0;
var w: []f32 = undefined;
fn low(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn toks(a: std.mem.Allocator, t: []const u8, add: bool) ![]usize {
    var list = std.ArrayList(usize).init(a);
    var i: usize = 0;
    var buf: [40]u8 = undefined;
    while (i < t.len) {
        var n: usize = 0;
        while (i < t.len and low(t[i]) >= 'a' and low(t[i]) <= 'z') : (i += 1) {
            if (n < buf.len) {
                buf[n] = low(t[i]);
                n += 1;
            }
        }
        if (n == 0) {
            i += 1;
            continue;
        }
        const tk = buf[0..n];
        if (vocab.get(tk)) |idx| try list.append(idx) else if (add) {
            try vocab.put(try a.dupe(u8, tk), vcount);
            try list.append(vcount);
            vcount += 1;
        }
    }
    return list.toOwnedSlice();
}
// returns {intent, confident?} — confidence is the softmax energy vs a calibrated-ish margin (the sigil idea)
fn understand(a: std.mem.Allocator, t: []const u8) !struct { i: u8, conf: bool } {
    const ix = try toks(a, t, false);
    if (ix.len == 0) return .{ .i = 4, .conf = false };
    var s = [_]f32{0} ** NI;
    for (ix) |x| for (0..NI) |c| {
        s[c] += w[x * NI + c];
    };
    var best: usize = 0;
    for (0..NI) |c| if (s[c] > s[best]) {
        best = c;
    };
    // the sigil signal: confidence = how much the winner DOMINATES the runner-up (margin/energy), not a prob.
    var second: f32 = -1e30;
    for (0..NI) |c| if (c != best and s[c] > second) {
        second = s[c];
    };
    return .{ .i = @intCast(best), .conf = (s[best] - second) > 1.5 };
}

// ── real invent action (gzip on a dataset) ──
const Gene = struct { op: u8 = 0, param: u8 = 0 };
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
fn gz(a: std.mem.Allocator, d: []const u8) usize {
    var o = std.ArrayList(u8).init(a);
    defer o.deinit();
    var f = std.io.fixedBufferStream(d);
    std.compress.gzip.compress(f.reader(), o.writer(), .{ .level = .default }) catch return d.len;
    return o.items.len;
}
fn shrink(a: std.mem.Allocator, d: []const u8, raw: usize, name: *[]const u8) usize {
    // tiny search for stride+delta (enough; returns best gzip, sets a readable name)
    const cands = [_][2]Gene{
        .{ .{ .op = 4, .param = 8 }, .{ .op = 1, .param = 1 } },
        .{ .{ .op = 4, .param = 4 }, .{ .op = 1, .param = 2 } },
        .{ .{ .op = 1, .param = 1 }, .{ .op = 0, .param = 0 } },
    };
    var best = raw;
    name.* = "stride8→delta1";
    for (cands) |p| {
        const buf = a.dupe(u8, d) catch return best;
        defer a.free(buf);
        const s = a.alloc(u8, d.len) catch return best;
        defer a.free(s);
        for (p) |g| {
            const nn = buf.len;
            if (g.op == 1) {
                const dd: usize = g.param;
                for (0..nn) |i| s[i] = buf[i] -% (if (i >= dd) buf[i - dd] else 0);
                @memcpy(buf, s[0..nn]);
            } else if (g.op == 4) {
                const st: usize = @max(2, @as(usize, g.param));
                var pp: usize = 0;
                for (0..st) |r| {
                    var i = r;
                    while (i < nn) : (i += st) {
                        s[pp] = buf[i];
                        pp += 1;
                    }
                }
                @memcpy(buf, s[0..nn]);
            }
        }
        const c = gz(a, buf);
        if (c < best) {
            best = c;
            name.* = if (p[0].param == 8) "stride8→delta1" else if (p[0].param == 4) "stride4→delta2" else "delta1";
        }
    }
    return best;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    vocab = std.StringHashMap(usize).init(a);
    // train intent
    var tix: [train.len][]usize = undefined;
    for (train, 0..) |e, k| tix[k] = try toks(a, e.t, true);
    w = try a.alloc(f32, vcount * NI);
    @memset(w, 0);
    // MARGIN-perceptron: keep pushing the true class above the best rival by MARGIN, so confident inputs get a
    // big dominance (energy) and genuinely-unsure ones don't — that gap is what the sigil reads.
    const MARGIN: f32 = 3.0;
    for (0..400) |_| for (train, 0..) |e, k| {
        var s = [_]f32{0} ** NI;
        for (tix[k]) |x| for (0..NI) |c| {
            s[c] += w[x * NI + c];
        };
        var bo: usize = if (e.i == 0) 1 else 0;
        for (0..NI) |c| if (c != e.i and s[c] > s[bo]) {
            bo = c;
        };
        if (s[e.i] - s[bo] < MARGIN) for (tix[k]) |x| {
            w[x * NI + e.i] += 1;
            w[x * NI + bo] -= 1;
        };
    };

    const data = try dataset(a);
    const raw = gz(a, data);

    // ── human-written fragment banks (the natural part) ──
    const greet_o = [_][]const u8{ "hey", "hey there", "yo", "oh hi", "good to see you" };
    const greet_b = [_][]const u8{ "what are we working on?", "what do you want to shrink today?", "point me at something and I'll crunch it.", "ready when you are." };
    const inv_ack = [_][]const u8{ "on it.", "alright, let me crunch this.", "sure thing —", "okay, digging in —", "let me see what I can do —" };
    const inv_close = [_][]const u8{ "want me to keep it live too?", "anything else?", "we can push it further if you want.", "happy to try another angle." };
    const thx = [_][]const u8{ "anytime.", "no problem.", "you got it.", "happy to help.", "sure thing." };
    const hedge = [_][]const u8{ "hmm, I'm not totally sure I followed that", "that's a little outside what I know", "I might be missing your meaning there" };
    const ask = [_][]const u8{ "— want me to just try shrinking the data?", "— could you say it another way?", "— did you maybe mean \"make it smaller\"?" };
    var l_go: usize = 99;
    var l_gb: usize = 99;
    var l_ack: usize = 99;
    var l_cl: usize = 99;
    var l_thx: usize = 99;
    var l_h: usize = 99;
    var l_a: usize = 99;

    var invents: usize = 0;
    var last_name: []const u8 = "";
    var last_new: usize = 0;

    try o.print("{s} {s}\n\n", .{ pick(greet_o[0..], &l_go), "— I shrink data and I can chat about it. (type; blank line quits)" });
    const in = std.io.getStdIn().reader();
    var line = std.ArrayList(u8).init(a);
    while (true) {
        try o.print("you ▸ ", .{});
        line.clearRetainingCapacity();
        in.streamUntilDelimiter(line.writer(), '\n', null) catch break;
        const t = std.mem.trim(u8, line.items, " \t\r");
        if (t.len == 0) break;
        const u = try understand(a, t);

        // ── compositional reply: open + body + close, varied, context-aware, confidence-gated (the sigil) ──
        if (!u.conf or u.i == 4) {
            // the sigil says "low energy" → hedge + ask (natural, not a robotic rejection)
            try o.print("eng ◂ {s}{s}\n\n", .{ pick(hedge[0..], &l_h), pick(ask[0..], &l_a) });
            continue;
        }
        switch (u.i) {
            0 => try o.print("eng ◂ {s} — {s}\n\n", .{ pick(greet_o[0..], &l_go), pick(greet_b[0..], &l_gb) }),
            1 => {
                var nm: []const u8 = "";
                const newsz = shrink(a, data, raw, &nm);
                invents += 1;
                last_name = nm;
                last_new = newsz;
                const pct = 100.0 * (@as(f64, @floatFromInt(raw)) - @as(f64, @floatFromInt(newsz))) / @as(f64, @floatFromInt(raw));
                // context-aware flourish
                const ctx = if (invents == 1) "" else if (invents == 2) " (that's two now)" else " (we're on a roll)";
                try o.print("eng ◂ {s} {s} took it {d}→{d}, about {d:.0}% smaller{s}. {s}\n\n", .{ pick(inv_ack[0..], &l_ack), nm, raw, newsz, pct, ctx, pick(inv_close[0..], &l_cl) });
            },
            2 => {
                if (invents == 0) try o.print("eng ◂ nothing yet — give me something to shrink and I'll remember it.\n\n", .{}) else try o.print("eng ◂ so far you've shrunk the data {d} time(s); the last was {s} down to {d} bytes.\n\n", .{ invents, last_name, last_new });
            },
            3 => try o.print("eng ◂ {s}\n\n", .{pick(thx[0..], &l_thx)}),
            else => {},
        }
    }
    try o.print("\neng ◂ {s}\n", .{pick(thx[0..], &l_thx)});
}
