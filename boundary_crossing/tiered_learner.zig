//! tiered_learner.zig — the engine LEARNS AS IT GOES: a learned guide over a TIERED, CATEGORIZED memory,
//! trained on the verifier's perfect labels. No LLM, not frozen. Steals ghost_engine's memory+data tiers.
//!
//! Micah engineered, in ghost_engine: Category {structural/procedural/relational/boundary/state/invariant},
//! Tier {pattern/convention/logic/contract}, TrustClass {exploratory/project/promoted/core}, DecayState
//! {active/stale/prunable/protected}, Reinforcement {success/failure/...}→promote/demote, and the rune rank
//! ladder (NOISE→EMERGING→PATTERN→VALIDATED, promoted by occurrences + distinct contexts, TTL-pruned). This
//! file steals those mechanisms properly and wires them to the verification-learning thesis
//! (see verification_learning.md): a VERIFIER (real gzip + round-trip) hands out PERFECT labels, and the
//! tiered/categorized memory is the LEARNED GUIDE — AlphaZero-style, but the labels are certified, free, online.
//!
//! What it does, per streamed data item:
//!   1. CATEGORIZE the data (feature-based: ramp / record(width) / sparse / noisy) — "categorizes into categories".
//!   2. GUIDE: try the memory's primitives for THAT category, highest rank first (the learned policy).
//!   3. VERIFY with real gzip (perfect label). If a memory primitive wins → cheap. Else BLIND search (expensive),
//!      then file the discovery into memory.
//!   4. REINFORCE: success → occurrences++, promote up the rank ladder; misses decay; unused noise is pruned (TTL).
//! Over a stream, familiar categories get solved in a FEW evaluations (the promoted primitive) instead of a full
//! blind search — measured head-to-head. That drop IS "learns as it goes," and it beats re-searching every time.
//!
//! Run: zig build tiered-learner --release=fast

const std = @import("std");

var prng: u64 = 0x7E1E_4ED1_0000_0001;
fn rnd() u64 {
    prng ^= prng << 13;
    prng ^= prng >> 7;
    prng ^= prng << 17;
    return prng;
}
fn rN(n: usize) usize {
    return @intCast(rnd() % @as(u64, @max(1, n)));
}

// ── reversible filter DSL (the substrate) ──
const MAXP = 4;
const Gene = struct { op: u8 = 0, param: u8 = 0 }; // op 1=delta(param) 4=stride(param)
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
// the VERIFIER: returns compressed size if reversible, else huge. EVERY call is one "evaluation".
var evals: usize = 0;
fn verify(p: Prog, d: []const u8, a: std.mem.Allocator) !usize {
    evals += 1;
    if (!try okrt(p, d, a)) return std.math.maxInt(usize);
    const f = try appF(p, d, a);
    defer a.free(f);
    return gz(a, f);
}

// ── DATA CATEGORIZATION (steal: Category) — cheap feature-based, no gzip ──
const Kind = enum(u8) { ramp, record, sparse, noisy };
fn kindName(k: Kind) []const u8 {
    return switch (k) {
        .ramp => "ramp",
        .record => "record",
        .sparse => "sparse",
        .noisy => "noisy",
    };
}
const Cat = struct { kind: Kind, param: u8 = 0 }; // param = record width
fn entropy(d: []const u8) f64 {
    var h = [_]u32{0} ** 256;
    for (d) |b| h[b] += 1;
    var e: f64 = 0;
    const n: f64 = @floatFromInt(d.len);
    for (h) |c| if (c > 0) {
        const p = @as(f64, @floatFromInt(c)) / n;
        e -= p * @log2(p);
    };
    return e;
}
fn categorize(a: std.mem.Allocator, d: []const u8) !Cat {
    // modal fraction → sparse
    var h = [_]u32{0} ** 256;
    for (d) |b| h[b] += 1;
    var modal: u32 = 0;
    for (h) |c| if (c > modal) {
        modal = c;
    };
    if (@as(f64, @floatFromInt(modal)) / @as(f64, @floatFromInt(d.len)) > 0.6) return .{ .kind = .sparse };
    const h0 = entropy(d);
    // delta1 entropy
    const d1 = try appF(.{ .g = [_]Gene{.{ .op = 1, .param = 1 }} ++ [_]Gene{.{}} ** (MAXP - 1), .len = 1 }, d, a);
    defer a.free(d1);
    const hd = entropy(d1);
    // best stride+delta1 entropy over candidate widths
    var best_h = hd;
    var best_w: u8 = 0;
    for ([_]u8{ 2, 3, 4, 6, 8, 12, 16 }) |w| {
        var p2 = Prog{ .len = 2 };
        p2.g[0] = .{ .op = 4, .param = w };
        p2.g[1] = .{ .op = 1, .param = 1 };
        const t = try appF(p2, d, a);
        defer a.free(t);
        const ht = entropy(t);
        if (ht < best_h) {
            best_h = ht;
            best_w = w;
        }
    }
    if (best_w != 0 and best_h < hd - 0.3 and best_h < h0 - 0.5) return .{ .kind = .record, .param = best_w };
    if (hd < h0 - 0.5) return .{ .kind = .ramp };
    return .{ .kind = .noisy };
}

// ── TIERED, CATEGORIZED MEMORY (steal: rune rank ladder + reinforcement + decay) ──
const Rank = enum(u8) { noise = 0, emerging = 1, pattern = 2, validated = 3 };
fn rankName(r: Rank) []const u8 {
    return switch (r) {
        .noise => "NOISE",
        .emerging => "EMERGING",
        .pattern => "PATTERN",
        .validated => "VALIDATED",
    };
}
const Mem = struct {
    prog: Prog,
    kind: Kind,
    param: u8,
    rank: Rank = .noise,
    occ: u32 = 0, // observations (reinforcement)
    distinct: u32 = 0, // distinct contexts (items) it helped on
    last_turn: usize = 0,
};
// ghost_engine-style promotion thresholds (scaled): occ>=3→emerging; occ>=8 & distinct>=2→pattern; occ>=16→validated
fn maybePromote(m: *Mem) void {
    const target: ?Rank = switch (m.rank) {
        .noise => if (m.occ >= 3) Rank.emerging else null,
        .emerging => if (m.occ >= 8 and m.distinct >= 2) Rank.pattern else null,
        .pattern => if (m.occ >= 16) Rank.validated else null,
        .validated => null,
    };
    if (target) |t| m.rank = t;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();
    const N: usize = 8192;
    const TTL: usize = 6; // noise unused for TTL turns is pruned (DecayState: prunable)

    try o.print("=== TIERED LEARNER — learns as it goes: categorized data + ranked memory + verifier labels, no LLM ===\n\n", .{});
    try o.print("a stream of data items arrives. each is CATEGORIZED, then solved by a learned GUIDE over a TIERED\n", .{});
    try o.print("memory (ghost_engine rune ranks + reinforcement). the verifier (real gzip) gives perfect labels.\n", .{});
    try o.print("we compare evaluations used WITH the tiered memory vs a BLIND searcher that relearns every time.\n\n", .{});

    var mem = std.ArrayList(Mem).init(a);
    var tiered_evals: usize = 0;
    var blind_evals: usize = 0;
    var memhits: usize = 0;

    // a stream where categories RECUR (so memory pays off): cycle ramp / record8 / record4 / noisy / sparse
    const StreamItem = struct { kind: u8, seed: u64 };
    const plan = [_]StreamItem{
        .{ .kind = 0, .seed = 1 }, .{ .kind = 1, .seed = 2 }, .{ .kind = 2, .seed = 3 }, .{ .kind = 3, .seed = 4 }, .{ .kind = 4, .seed = 5 },
        .{ .kind = 0, .seed = 6 }, .{ .kind = 1, .seed = 7 }, .{ .kind = 2, .seed = 8 }, .{ .kind = 3, .seed = 9 }, .{ .kind = 4, .seed = 10 },
        .{ .kind = 0, .seed = 11 }, .{ .kind = 1, .seed = 12 }, .{ .kind = 2, .seed = 13 }, .{ .kind = 1, .seed = 14 }, .{ .kind = 0, .seed = 15 },
        .{ .kind = 1, .seed = 16 }, .{ .kind = 2, .seed = 17 }, .{ .kind = 0, .seed = 18 }, .{ .kind = 1, .seed = 19 }, .{ .kind = 2, .seed = 20 },
    };

    try o.print("turn  data-category    solved-by             filter           evals(tiered/blind)\n", .{});
    try o.print("────  ───────────────  ────────────────────  ───────────────  ───────────────────\n", .{});
    for (plan, 0..) |it, turn| {
        const data = try genItem(a, N, it.kind, it.seed);
        const cat = try categorize(a, data);
        const base = gz(a, data);

        // ── TIERED path: guide with memory (rank desc), else blind, then file + reinforce ──
        evals = 0;
        var solved = Prog{};
        var solved_cost = base;
        var via: []const u8 = "blind-search";
        // sort matching memory entries by rank desc (the learned policy)
        var cand_idx = std.ArrayList(usize).init(a);
        defer cand_idx.deinit();
        for (mem.items, 0..) |m, i| if (m.kind == cat.kind and (cat.kind != .record or m.param == cat.param)) try cand_idx.append(i);
        std.sort.pdq(usize, cand_idx.items, mem.items, cmpRankDesc);
        var hit_i: ?usize = null;
        for (cand_idx.items) |i| {
            const c = try verify(mem.items[i].prog, data, a);
            if (c * 100 < base * 95) {
                solved = mem.items[i].prog;
                solved_cost = c;
                hit_i = i;
                via = rankName(mem.items[i].rank);
                break;
            }
        }
        if (hit_i == null) {
            // BLIND fallback search (and file the discovery)
            solved = try blindSearch(data, a, base, &solved_cost);
            if (solved.len >= 1 and solved_cost * 100 < base * 95) {
                try mem.append(.{ .prog = solved, .kind = cat.kind, .param = cat.param, .occ = 1, .distinct = 1, .last_turn = turn });
            }
        } else {
            memhits += 1;
            var m = &mem.items[hit_i.?];
            m.occ += 1;
            m.distinct += 1;
            m.last_turn = turn;
            maybePromote(m);
        }
        tiered_evals += evals;
        const this_tiered = evals;

        // ── BLIND control: relearn from scratch every time (no memory) ──
        evals = 0;
        var bc = base;
        _ = try blindSearch(data, a, base, &bc);
        blind_evals += evals;
        const this_blind = evals;

        // decay: prune NOISE entries unused for TTL turns (DecayState prunable)
        var w: usize = 0;
        for (mem.items) |m| {
            const keep = !(m.rank == .noise and turn > m.last_turn + TTL);
            if (keep) {
                mem.items[w] = m;
                w += 1;
            }
        }
        mem.shrinkRetainingCapacity(w);

        var fb: [40]u8 = undefined;
        try o.print("{d:>3}   {s:<7} w={d:<5}  {s:<20}  {s:<15}  {d:>5} / {d:<5}\n", .{ turn, kindName(cat.kind), cat.param, via, fmtProg(&fb, solved), this_tiered, this_blind });
    }

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("total verifier evaluations:  TIERED memory {d}   vs   BLIND-every-time {d}\n", .{ tiered_evals, blind_evals });
    const save = 100.0 * (@as(f64, @floatFromInt(blind_evals)) - @as(f64, @floatFromInt(tiered_evals))) / @as(f64, @floatFromInt(blind_evals));
    try o.print("the learner used {d:.0}% FEWER evaluations by reusing what it had certified before — it LEARNED AS IT\n", .{save});
    try o.print("WENT. {d} of {d} items were solved straight from memory (no search). nothing frozen; perfect labels.\n\n", .{ memhits, plan.len });
    try o.print("final tiered/categorized memory (the stolen ghost_engine structure, populated by real outcomes):\n", .{});
    for (mem.items) |m| {
        var fb: [40]u8 = undefined;
        try o.print("   [{s:<9}] category={s:<7} w={d:<3} occ={d:<2} distinct={d:<2}  {s}\n", .{ rankName(m.rank), kindName(m.kind), m.param, m.occ, m.distinct, fmtProg(&fb, m.prog) });
    }
    try o.print("\nHONEST: the 'guide' is the tiered memory (verifier-certified primitives, ranked by reuse); the labels\n", .{});
    try o.print("are perfect (gzip + round-trip). It generalizes WITHIN a category and prunes what doesn't earn its\n", .{});
    try o.print("keep. This is the AlphaZero/DreamCoder loop with ghost_engine's tiers — learning, not a frozen table.\n", .{});
}

fn cmpRankDesc(mem: []const Mem, x: usize, y: usize) bool {
    if (@intFromEnum(mem[x].rank) != @intFromEnum(mem[y].rank)) return @intFromEnum(mem[x].rank) > @intFromEnum(mem[y].rank);
    return mem[x].occ > mem[y].occ;
}

fn randG() Gene {
    const op: u8 = if (rN(2) == 0) 1 else 4;
    return .{ .op = op, .param = if (op == 1) @intCast(1 + rN(4)) else @intCast(2 + rN(15)) };
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
fn blindSearch(data: []const u8, a: std.mem.Allocator, base: usize, out_cost: *usize) !Prog {
    var best = Prog{};
    var bc = base;
    for (0..8) |_| {
        var cur = mut(Prog{});
        var cc = verify(cur, data, a) catch std.math.maxInt(usize);
        for (0..18) |_| {
            const cand = mut(cur);
            const x = verify(cand, data, a) catch std.math.maxInt(usize);
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
    out_cost.* = bc;
    return best;
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

fn genItem(a: std.mem.Allocator, n: usize, kind: u8, seed: u64) ![]u8 {
    prng = seed *% 0x9E3779B97F4A7C15 | 1;
    const b = try a.alloc(u8, n);
    switch (kind) {
        0 => { // ramp
            const mul: u8 = @intCast(1 + rN(7));
            for (0..n) |i| b[i] = @intCast((i *% mul) & 0xFF);
        },
        1 => { // record width 8
            var i: usize = 0;
            while (i + 8 <= n) : (i += 8) {
                const r = i / 8;
                b[i] = @intCast(r & 0xFF);
                b[i + 1] = 0x42;
                b[i + 2] = @intCast((r *% 3) & 0xFF);
                for (3..8) |c| b[i + c] = @intCast(rN(256));
            }
            while (i < n) : (i += 1) b[i] = 0;
        },
        2 => { // record width 4
            var i: usize = 0;
            while (i + 4 <= n) : (i += 4) {
                const r = i / 4;
                b[i] = @intCast(r & 0xFF);
                b[i + 1] = @intCast((r *% 5) & 0xFF);
                b[i + 2] = 0x10;
                b[i + 3] = @intCast(rN(256));
            }
            while (i < n) : (i += 1) b[i] = 0;
        },
        3 => for (0..n) |i| {
            b[i] = @intCast(rN(256));
        }, // noisy
        else => for (0..n) |i| {
            b[i] = if (rN(20) == 0) @intCast(rN(256)) else 0;
        }, // sparse
    }
    return b;
}
