//! self_extending_inventor.zig — the autonomous engine that GROWS ITS OWN VOCABULARY.
//!
//! Micah's directive: keep automating the steps I do by hand until the engine does everything on its own —
//! the only human input being the prompt of what's wanted. `autonomous_inventor` already searches + certifies
//! alone on a fixed objective, but with a FIXED DSL. This rung removes the next hand-step: the engine now
//! PROMOTES its own winning compositions into reusable macro-primitives and COMPOUNDS them across a stream of
//! data — getting more budget-efficient over time, with NO LLM and no human help between datasets.
//!
//! The "want" (the only thing a human supplies): "losslessly shrink this data." Formal frame = minimize real
//! gzip size of a reversible byte-transform; verifier = gzip size + exact round-trip. Everything downstream —
//! search, certify, AND now self-extension of the primitive library — is autonomous, blind-mutation driven.
//!
//! Proof it's a real gain: run the SAME stream at the SAME tight budget twice — once with library growth
//! (self-extending), once base-ops-only (control), identical PRNG per dataset. The self-extending run reaches
//! deeper transforms within budget on later, structure-sharing datasets, because a macro discovered on an
//! earlier file is now reachable in ONE mutation. That is DreamCoder-style abstraction learning, autonomous.
//!
//! Honest bound (Closure Principle, unchanged): promotion is ABSTRACTION (faster/deeper reach), not closure
//! escape — a macro of delta+stride is still inside the delta+stride closure. The ceiling is still the base
//! ops + the formal frame. Escaping THOSE (a new primitive form; a different objective) remains the only acts
//! needing an out-of-closure source. This rung automates one more hand-step; it does not remove the last one.
//!
//! Run: zig build self-extending-inventor --release=fast

const std = @import("std");

var prng: u64 = 0x9E3779B97F4A7C15;
fn reseed(s: u64) void {
    prng = s | 1;
}
fn rnd() u64 {
    prng ^= prng << 13;
    prng ^= prng >> 7;
    prng ^= prng << 17;
    return prng;
}
fn rndN(n: usize) usize {
    return @intCast(rnd() % @as(u64, n));
}

// ── reversible filter-DSL (base ops) ──
const MAXLEN = 8;
const Gene = struct { op: u8 = 0, param: u8 = 0 };
const Prog = struct { genes: [MAXLEN]Gene = [_]Gene{.{}} ** MAXLEN, len: usize = 0 };
const Macro = struct { genes: [MAXLEN]Gene = [_]Gene{.{}} ** MAXLEN, len: usize = 0, born: usize = 0, uses: usize = 0 };

fn mtfFwd(buf: []u8) void {
    var tbl: [256]u8 = undefined;
    for (0..256) |i| tbl[i] = @intCast(i);
    for (buf) |*b| {
        const v = b.*;
        var r: u8 = 0;
        while (tbl[r] != v) r += 1;
        b.* = r;
        var j: usize = r;
        while (j > 0) : (j -= 1) tbl[j] = tbl[j - 1];
        tbl[0] = v;
    }
}
fn mtfInv(buf: []u8) void {
    var tbl: [256]u8 = undefined;
    for (0..256) |i| tbl[i] = @intCast(i);
    for (buf) |*b| {
        const r = b.*;
        const v = tbl[r];
        b.* = v;
        var j: usize = r;
        while (j > 0) : (j -= 1) tbl[j] = tbl[j - 1];
        tbl[0] = v;
    }
}
fn opFwd(buf: []u8, g: Gene, sc: []u8) void {
    const n = buf.len;
    switch (g.op) {
        1 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) sc[i] = buf[i] -% (if (i >= d) buf[i - d] else 0);
            @memcpy(buf, sc[0..n]);
        },
        2 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) sc[i] = buf[i] ^ (if (i >= d) buf[i - d] else 0);
            @memcpy(buf, sc[0..n]);
        },
        3 => {
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] +% g.param;
        },
        4 => {
            const s: usize = @max(2, @as(usize, g.param));
            var pos: usize = 0;
            var r: usize = 0;
            while (r < s) : (r += 1) {
                var i: usize = r;
                while (i < n) : (i += s) {
                    sc[pos] = buf[i];
                    pos += 1;
                }
            }
            @memcpy(buf, sc[0..n]);
        },
        5 => mtfFwd(buf),
        else => {},
    }
}
fn opInv(buf: []u8, g: Gene, sc: []u8) void {
    const n = buf.len;
    switch (g.op) {
        1 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] +% (if (i >= d) buf[i - d] else 0);
        },
        2 => {
            const d: usize = g.param;
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] ^ (if (i >= d) buf[i - d] else 0);
        },
        3 => {
            var i: usize = 0;
            while (i < n) : (i += 1) buf[i] = buf[i] -% g.param;
        },
        4 => {
            const s: usize = @max(2, @as(usize, g.param));
            var pos: usize = 0;
            var r: usize = 0;
            while (r < s) : (r += 1) {
                var i: usize = r;
                while (i < n) : (i += s) {
                    sc[i] = buf[pos];
                    pos += 1;
                }
            }
            @memcpy(buf, sc[0..n]);
        },
        5 => mtfInv(buf),
        else => {},
    }
}
fn applyFwd(p: Prog, data: []const u8, a: std.mem.Allocator) ![]u8 {
    const buf = try a.dupe(u8, data);
    const sc = try a.alloc(u8, @max(1, data.len));
    defer a.free(sc);
    for (0..p.len) |k| opFwd(buf, p.genes[k], sc);
    return buf;
}
fn applyInv(p: Prog, data: []const u8, a: std.mem.Allocator) ![]u8 {
    const buf = try a.dupe(u8, data);
    const sc = try a.alloc(u8, @max(1, data.len));
    defer a.free(sc);
    var k = p.len;
    while (k > 0) {
        k -= 1;
        opInv(buf, p.genes[k], sc);
    }
    return buf;
}
fn gzSize(a: std.mem.Allocator, data: []const u8) usize {
    var buf = std.ArrayList(u8).init(a);
    defer buf.deinit();
    var fbs = std.io.fixedBufferStream(data);
    std.compress.gzip.compress(fbs.reader(), buf.writer(), .{ .level = .default }) catch return data.len;
    return buf.items.len;
}
fn reversible(p: Prog, data: []const u8, a: std.mem.Allocator) !bool {
    const f = try applyFwd(p, data, a);
    defer a.free(f);
    const b = try applyInv(p, f, a);
    defer a.free(b);
    return std.mem.eql(u8, data, b);
}
fn cost(p: Prog, data: []const u8, a: std.mem.Allocator) !usize {
    if (!try reversible(p, data, a)) return std.math.maxInt(usize);
    const f = try applyFwd(p, data, a);
    defer a.free(f);
    return gzSize(a, f);
}

// ── autonomous generator: mutation can insert a base op OR a whole library macro ──
fn randGene() Gene {
    const op: u8 = @intCast(1 + rndN(5));
    const param: u8 = switch (op) {
        1, 2 => @intCast(1 + rndN(4)),
        3 => @intCast(1 + rndN(255)),
        4 => @intCast(2 + rndN(7)),
        else => 0,
    };
    return .{ .op = op, .param = param };
}
fn mutate(p: Prog, lib: []const Macro) Prog {
    var q = p;
    // with a library, sometimes splice a whole macro in one move (deeper reach per mutation)
    const use_macro = lib.len > 0 and rndN(2) == 0;
    if (use_macro) {
        const m = lib[rndN(lib.len)];
        if (q.len + m.len <= MAXLEN) {
            for (0..m.len) |k| {
                q.genes[q.len] = m.genes[k];
                q.len += 1;
            }
            return q;
        }
    }
    const c = rndN(3);
    if (c == 0 and q.len < MAXLEN) {
        q.genes[q.len] = randGene();
        q.len += 1;
    } else if (c == 1 and q.len > 0) {
        q.len -= 1;
    } else if (q.len > 0) {
        q.genes[rndN(q.len)] = randGene();
    } else {
        q.genes[0] = randGene();
        q.len = 1;
    }
    return q;
}
fn search(data: []const u8, a: std.mem.Allocator, lib: []const Macro, restarts: usize, steps: usize) !Prog {
    var best = Prog{};
    var best_cost = try cost(best, data, a);
    for (0..restarts) |_| {
        var cur = mutate(Prog{}, lib);
        var cur_cost = cost(cur, data, a) catch std.math.maxInt(usize);
        for (0..steps) |_| {
            const cand = mutate(cur, lib);
            const cc = cost(cand, data, a) catch std.math.maxInt(usize);
            if (cc <= cur_cost) {
                cur = cand;
                cur_cost = cc;
            }
            if (cur_cost < best_cost) {
                best = cur;
                best_cost = cur_cost;
            }
        }
    }
    return best;
}
fn macroEq(m: Macro, p: Prog) bool {
    if (m.len != p.len) return false;
    for (0..p.len) |k| if (m.genes[k].op != p.genes[k].op or m.genes[k].param != p.genes[k].param) return false;
    return true;
}

fn printProg(o: anytype, p: Prog) void {
    if (p.len == 0) {
        o.print("identity", .{}) catch {};
        return;
    }
    for (0..p.len) |k| {
        if (k > 0) o.print("→", .{}) catch {};
        const g = p.genes[k];
        switch (g.op) {
            1 => o.print("delta{d}", .{g.param}) catch {},
            2 => o.print("xor{d}", .{g.param}) catch {},
            3 => o.print("add{d}", .{g.param}) catch {},
            4 => o.print("stride{d}", .{g.param}) catch {},
            5 => o.print("mtf", .{}) catch {},
            else => {},
        }
    }
}

// ── data stream: pairs that SHARE structure, so a macro from file N helps file N+1 ──
fn genRec(a: std.mem.Allocator, n: usize, width: usize, seed: u64) ![]u8 {
    reseed(seed);
    const b = try a.alloc(u8, n);
    var i: usize = 0;
    while (i + width <= n) : (i += width) {
        const rec = i / width;
        b[i] = @intCast(rec & 0xFF); // counter column → delta-able once de-interleaved by `width`
        for (1..width) |c| {
            b[i + c] = if (c == 1) 0x42 else @intCast(rndN(256));
        }
    }
    while (i < n) : (i += 1) b[i] = 0;
    return b;
}
fn genRamp(a: std.mem.Allocator, n: usize, mul: u8) ![]u8 {
    const b = try a.alloc(u8, n);
    for (0..n) |i| b[i] = @intCast((i *% mul) & 0xFF);
    return b;
}

const DS = struct { name: []const u8, data: []u8, seed: u64 };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    const N: usize = 16384;

    try o.print("=== SELF-EXTENDING INVENTOR — the engine grows its own vocabulary, no LLM ===\n\n", .{});
    try o.print("the only human input is the WANT: \"losslessly shrink this data.\" everything else — search,\n", .{});
    try o.print("certify, AND promoting winning compositions into reusable primitives — is autonomous. proof:\n", .{});
    try o.print("the SAME stream at the SAME tight budget, with vs without self-extension (identical PRNG).\n\n", .{});

    // a stream where structure recurs: two 4-wide, two 8-wide, two ramps — later files can reuse earlier macros
    const sets = [_]DS{
        .{ .name = "rec4-A ", .data = try genRec(a, N, 4, 0x4A), .seed = 0x100 },
        .{ .name = "rec4-B ", .data = try genRec(a, N, 4, 0x4B), .seed = 0x101 },
        .{ .name = "rec8-A ", .data = try genRec(a, N, 8, 0x8A), .seed = 0x102 },
        .{ .name = "rec8-B ", .data = try genRec(a, N, 8, 0x8B), .seed = 0x103 },
        .{ .name = "ramp-A ", .data = try genRamp(a, N, 7), .seed = 0x104 },
        .{ .name = "ramp-B ", .data = try genRamp(a, N, 13), .seed = 0x105 },
    };
    const R: usize = 5;
    const S: usize = 14; // deliberately TIGHT budget so abstraction matters

    // ── RUN A: self-extending (library grows by promotion) ──
    var lib = std.ArrayList(Macro).init(a);
    var totalA: usize = 0;
    var baseTotal: usize = 0;
    try o.print("[self-extending run] (library carries across files; winners are promoted)\n", .{});
    for (sets) |ds| {
        const base = gzSize(a, ds.data);
        baseTotal += base;
        reseed(ds.seed);
        const libslice = lib.items;
        const best = try search(ds.data, a, libslice, R, S);
        const f = try applyFwd(best, ds.data, a);
        const bsz = gzSize(a, f);
        totalA += bsz;
        // promote winning multi-op compositions (self-extension)
        var promoted = false;
        if (best.len >= 2 and bsz * 100 < base * 95) { // only a real win
            var dup = false;
            for (lib.items) |m| if (macroEq(m, best)) {
                dup = true;
            };
            if (!dup) {
                var mac = Macro{ .len = best.len, .born = 0 };
                for (0..best.len) |k| mac.genes[k] = best.genes[k];
                try lib.append(mac);
                promoted = true;
            }
        }
        try o.print("  {s} gzip {d:>6}→{d:>6} ({d:>4.1}%)  ", .{ ds.name, base, bsz, 100.0 * (@as(f64, @floatFromInt(base)) - @as(f64, @floatFromInt(bsz))) / @as(f64, @floatFromInt(base)) });
        printProg(o, best);
        try o.print("{s}\n", .{if (promoted) "   [+promoted to library]" else ""});
    }
    try o.print("  library grew to {d} self-invented primitives.\n\n", .{lib.items.len});

    // ── RUN B: control, base-ops only (no library, no promotion), same budget + PRNG ──
    var totalB: usize = 0;
    try o.print("[control run] (base ops only — no self-extension; identical budget & seeds)\n", .{});
    const empty = [_]Macro{};
    for (sets) |ds| {
        const base = gzSize(a, ds.data);
        reseed(ds.seed);
        const best = try search(ds.data, a, empty[0..], R, S);
        const f = try applyFwd(best, ds.data, a);
        const bsz = gzSize(a, f);
        totalB += bsz;
        try o.print("  {s} gzip {d:>6}→{d:>6} ({d:>4.1}%)  ", .{ ds.name, base, bsz, 100.0 * (@as(f64, @floatFromInt(base)) - @as(f64, @floatFromInt(bsz))) / @as(f64, @floatFromInt(base)) });
        printProg(o, best);
        try o.print("\n", .{});
    }

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("raw {d}  |  self-extending {d}  |  base-only control {d}\n", .{ baseTotal, totalA, totalB });
    if (totalA < totalB) {
        try o.print("Self-extension WON at equal budget: {d} fewer bytes ({d:.1}% better than base-only) — by reusing\n", .{ totalB - totalA, 100.0 * (@as(f64, @floatFromInt(totalB)) - @as(f64, @floatFromInt(totalA))) / @as(f64, @floatFromInt(totalB)) });
        try o.print("primitives it invented earlier in the SAME run. The engine got more budget-efficient over time,\n", .{});
        try o.print("by itself, with no LLM and no human help between files — it grew its own vocabulary.\n", .{});
    } else {
        try o.print("Self-extension did not beat base-only this budget (honest: the tight-budget abstraction edge is\n", .{});
        try o.print("stochastic; on this seed the base search already reached the same transforms).\n", .{});
    }
    try o.print("\nThis automates one more hand-step toward 'all on its own': the engine now extends its OWN primitive\n", .{});
    try o.print("library autonomously (DreamCoder-style abstraction). HONEST BOUND: promotion is faster/deeper reach\n", .{});
    try o.print("WITHIN the base closure, not escape from it — the ceiling is still the base ops + the formal frame.\n", .{});
    try o.print("Remaining hand-steps: a genuinely-new primitive FORM (out-of-closure), and CHOOSING the objective —\n", .{});
    try o.print("the latter is exactly 'the prompt of what you want,' which you said the engine should never do alone.\n", .{});
}
