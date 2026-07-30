//! Boundary crossing — source C: the certifier TAMES an unreliable generator (the LLM stand-in).
//!
//! The whole point of "an LLM subordinated to the certifier" is that the LLM is an UNRELIABLE rich source —
//! it proposes a flood of candidates, most of them garbage or dressed-up recombinations, a few genuine. What
//! makes it usable for INVENTION (not recombination) is that the certifier keeps ONLY the proposals that
//! provably escape the current closure. This probe demonstrates that property directly, with no live LLM: a
//! noisy proposer emits a stream that is mostly junk, and the certifier (ESCAPE + IRREDUCIBLE) extracts the
//! genuine out-of-substrate generators at high precision.
//!
//! Setting (the clean number-theory one): library starts = the bits of n; target = "divisible by 3, 5, or 7" (each genuine mod is decisive). The proposer
//! emits candidate generators tagged by construction:
//!   • GENUINE   : divisibility primitives mod_{3,5,7} — out-of-substrate, each decisive for the target.
//!   • REDUCIBLE : mod_2 and bit-copies — already in the substrate's closure (an LLM "rediscovering" what you
//!                 have). They look plausible but add nothing.
//!   • GARBAGE   : random features — an LLM hallucination; no structure.
//! The stream is ~89% non-genuine. ESCAPE must REPLICATE on two independent held-out folds (a single fold is
//! fooled by overfit noise; irreducibility alone never rejects garbage, since random features are irreducible).
//!
//! Run: zig build certifier-filter --release=fast

const std = @import("std");

const N: usize = 14;
const DOM: usize = 1 << N; // 16384 — bigger domain → lower noise floor for the held-out folds
const NTR: usize = DOM / 2; // fit
const NVA: usize = DOM * 3 / 4; // val end ([NTR,NVA) val, [NVA,DOM) test — two INDEPENDENT held-out folds)

fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}
fn isPrime(n: usize) bool {
    if (n < 2) return false;
    var d: usize = 2;
    while (d * d <= n) : (d += 1) if (n % d == 0) return false;
    return true;
}

const Tag = enum { genuine, reducible, garbage };
const Cand = struct { name: []const u8, tag: Tag, feat: []f64 };

var perm: [DOM]usize = undefined;

fn balAcc(lib: []const []const f64, target: []const f64, w: []const f64, lo: usize, hi: usize) f64 {
    const dim = lib.len;
    var tp: f64 = 0;
    var fn_: f64 = 0;
    var tn: f64 = 0;
    var fp: f64 = 0;
    for (lo..hi) |ii| {
        const n = perm[ii];
        var z = w[dim];
        for (0..dim) |j| z += w[j] * lib[j][n];
        const pred = z >= 0;
        const act = target[n] > 0.5;
        if (act and pred) tp += 1 else if (act and !pred) fn_ += 1 else if (!act and !pred) tn += 1 else fp += 1;
    }
    return 0.5 * (tp / @max(1, tp + fn_) + tn / @max(1, tn + fp));
}

// fit on TRAIN, return balanced accuracy on the two INDEPENDENT held-out folds (val, test)
const Acc = struct { val: f64, tst: f64 };
fn coverage(lib: []const []const f64, target: []const f64, w: []f64) Acc {
    const dim = lib.len;
    @memset(w[0 .. dim + 1], 0);
    for (0..90) |_| for (0..NTR) |ii| {
        const n = perm[ii];
        var z = w[dim];
        for (0..dim) |j| z += w[j] * lib[j][n];
        const e = sigmoid(z) - target[n];
        for (0..dim) |j| w[j] -= 0.1 * e * lib[j][n];
        w[dim] -= 0.1 * e;
    };
    return .{ .val = balAcc(lib, target, w, NTR, NVA), .tst = balAcc(lib, target, w, NVA, DOM) };
}

// held-out R² reconstructing a candidate from the current library
fn reconR2(lib: []const []const f64, cand: []const f64, w: []f64) f64 {
    const dim = lib.len;
    @memset(w[0 .. dim + 1], 0);
    for (0..300) |_| for (0..NTR) |ii| {
        const n = perm[ii];
        var z = w[dim];
        for (0..dim) |j| z += w[j] * lib[j][n];
        const e = z - cand[n];
        for (0..dim) |j| w[j] -= 0.02 * e * lib[j][n];
        w[dim] -= 0.02 * e;
    };
    var mu: f64 = 0;
    for (NTR..DOM) |ii| mu += cand[perm[ii]];
    mu /= @floatFromInt(DOM - NTR);
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (NTR..DOM) |ii| {
        const n = perm[ii];
        var z = w[dim];
        for (0..dim) |j| z += w[j] * lib[j][n];
        ssr += (cand[n] - z) * (cand[n] - z);
        sst += (cand[n] - mu) * (cand[n] - mu);
    }
    return 1.0 - ssr / @max(1e-9, sst);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    var prng = std.Random.DefaultPrng.init(0xCEF1F7E59A11);
    const rand = prng.random();

    for (0..DOM) |i| perm[i] = i;
    var i: usize = DOM;
    while (i > 1) {
        i -= 1;
        const j = rand.uintLessThan(usize, i + 1);
        const t = perm[i];
        perm[i] = perm[j];
        perm[j] = t;
    }

    // target: divisible by 3, 5, or 7 — each genuine generator (mod_3/5/7) is individually DECISIVE,
    // giving a large, replicable gain well above the random-feature noise floor (unlike primality).
    const target = try alloc.alloc(f64, DOM);
    for (0..DOM) |n| target[n] = if (n % 3 == 0 or n % 5 == 0 or n % 7 == 0) 1.0 else 0.0;

    // library starts = standardized bits of n
    var lib = std.ArrayList([]const f64).init(alloc);
    for (0..N) |b| {
        const col = try alloc.alloc(f64, DOM);
        for (0..DOM) |n| col[n] = @floatFromInt((n >> @intCast(b)) & 1);
        try lib.append(col);
    }

    // helper to make a feature column
    const mkdiv = struct {
        fn f(a: std.mem.Allocator, k: usize) []f64 {
            const col = a.alloc(f64, DOM) catch unreachable;
            for (0..DOM) |n| col[n] = if (n % k == 0) @as(f64, 1) else 0;
            return col;
        }
    }.f;

    // ── the unreliable proposer's stream (mixed, mostly junk) ──
    var stream = std.ArrayList(Cand).init(alloc);
    // genuine
    for ([_]usize{ 3, 5, 7 }) |p| {
        try stream.append(.{ .name = "mod_p(genuine)", .tag = .genuine, .feat = mkdiv(alloc, p) });
    }
    // reducible: mod_2 (= bit0) and bit copies
    try stream.append(.{ .name = "mod_2(reducible)", .tag = .reducible, .feat = mkdiv(alloc, 2) });
    for ([_]usize{ 4, 7, 9 }) |b| {
        const col = try alloc.alloc(f64, DOM);
        for (0..DOM) |n| col[n] = @floatFromInt((n >> @intCast(b)) & 1);
        try stream.append(.{ .name = "bit_copy(reducible)", .tag = .reducible, .feat = col });
    }
    // garbage: random features
    for (0..20) |_| {
        const col = try alloc.alloc(f64, DOM);
        for (0..DOM) |n| col[n] = if (rand.float(f64) < 0.5) @as(f64, 1) else 0;
        try stream.append(.{ .name = "random(garbage)", .tag = .garbage, .feat = col });
    }
    // shuffle the stream (realistic interleaving)
    var k: usize = stream.items.len;
    while (k > 1) {
        k -= 1;
        const j = rand.uintLessThan(usize, k + 1);
        const t = stream.items[k];
        stream.items[k] = stream.items[j];
        stream.items[j] = t;
    }

    var w: [N + 40]f64 = undefined;
    const ESCAPE: f64 = 0.04; // required on BOTH independent folds (replication kills spurious gains)
    const IRRED: f64 = 0.40;

    try out.print("=== Boundary crossing — source C: the certifier tames an unreliable generator (LLM stand-in) ===\n\n", .{});
    var ng: usize = 0;
    var nr: usize = 0;
    var nj: usize = 0;
    for (stream.items) |c| switch (c.tag) {
        .genuine => ng += 1,
        .reducible => nr += 1,
        .garbage => nj += 1,
    };
    try out.print("proposer stream: {d} candidates = {d} genuine, {d} reducible, {d} garbage ({d:.0}% non-genuine).\n", .{ stream.items.len, ng, nr, nj, 100.0 * @as(f64, @floatFromInt(nr + nj)) / @as(f64, @floatFromInt(stream.items.len)) });
    try out.print("certify: accept iff ESCAPE — balanced-acc gain > {d:.3} on BOTH independent held-out folds\n", .{ESCAPE});
    try out.print("(replication kills spurious overfit gains) — AND IRREDUCIBLE (R² from library < {d:.2}).\n\n", .{IRRED});

    var accepted: usize = 0;
    var acc_genuine: usize = 0;
    var rej_red: usize = 0;
    var rej_gar: usize = 0;
    var rej_gen: usize = 0;
    const base = coverage(lib.items, target, &w);
    var cur = base;
    try out.print("library starts at balanced acc val={d:.3}/test={d:.3} on div(3,5,7) (bits only).\n\n", .{ base.val, base.tst });

    for (stream.items, 0..) |c, idx| {
        try lib.append(c.feat);
        const with = coverage(lib.items, target, &w);
        _ = lib.pop();
        const gv = with.val - cur.val;
        const gt = with.tst - cur.tst;
        const r2 = reconR2(lib.items, c.feat, &w);
        const escapes = gv > ESCAPE and gt > ESCAPE; // REPLICATED on both folds
        const accept = escapes and r2 < IRRED;
        if (accept) {
            try lib.append(c.feat);
            cur = with;
            accepted += 1;
            if (c.tag == .genuine) acc_genuine += 1;
            try out.print("  [{d:>2}] {s:<22} gain {d:.3}/{d:.3}, R² {d:.3}  → ACCEPT\n", .{ idx, c.name, gv, gt, r2 });
        } else {
            switch (c.tag) {
                .reducible => rej_red += 1,
                .garbage => rej_gar += 1,
                .genuine => rej_gen += 1,
            }
            try out.print("  [{d:>2}] {s:<22} gain {d:.3}/{d:.3}, R² {d:.3}  → reject ({s})\n", .{ idx, c.name, gv, gt, r2, if (!escapes) "no replicated escape" else "reducible" });
        }
    }

    const precision = if (accepted > 0) @as(f64, @floatFromInt(acc_genuine)) / @as(f64, @floatFromInt(accepted)) else 0;
    const recall = @as(f64, @floatFromInt(acc_genuine)) / @as(f64, @floatFromInt(ng));

    try out.print("\n──────── result ────────\n", .{});
    try out.print("accepted {d} of {d}.  precision = {d:.3} (genuine among accepted),  recall = {d:.3} (genuine recovered).\n", .{ accepted, stream.items.len, precision, recall });
    try out.print("rejected: {d} garbage, {d} reducible, {d} genuine.   final library test acc on div(3,5,7): {d:.3} (from {d:.3}).\n", .{ rej_gar, rej_red, rej_gen, cur.tst, base.tst });

    // ── verdict ──
    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    if (precision >= 0.99) {
        try out.print("The certifier achieved PRECISION {d:.3} on a stream that was {d:.0}% non-genuine: every accepted\n", .{ precision, 100.0 * @as(f64, @floatFromInt(nr + nj)) / @as(f64, @floatFromInt(stream.items.len)) });
        try out.print("generator is a real out-of-substrate escape; every garbage and every dressed-up recombination was\n", .{});
        try out.print("rejected (garbage fails ESCAPE — it doesn't help; reducible fails IRREDUCIBILITY — the library already\n", .{});
        try out.print("contains it). That is EXACTLY the property that makes an unreliable rich source usable for invention:\n", .{});
        try out.print("the proposer can be an LLM hallucinating most of the time, and the certified library is still clean.\n", .{});
    } else {
        try out.print("Precision {d:.3} — inspect; some non-genuine candidate passed both gates (tighten ESCAPE/IRRED).\n", .{precision});
    }
    try out.print("\nThis closes the source survey. The inject→certify→promote loop is generator-AGNOSTIC: the source can be\n", .{});
    try out.print("number theory (world_injection / invention_engine), a verifiable external unknown (superopt), real data\n", .{});
    try out.print("(real_data), or an unreliable proposer like an LLM (here). The certifier is the invariant — it is what\n", .{});
    try out.print("turns ANY rich-but-unreliable source into certified invention, separating it from recombination with a\n", .{});
    try out.print("receipt. The LLM (if used) is the entropy source; the certifier is the inventor.\n", .{});
    try out.print("\nSee: invention_engine.md, world_injection.md, superopt.md, real_data.md, ../README.md, CLOSURE_PRINCIPLE.md.\n", .{});
    try out.print("Method/prior art: FunSearch (DeepMind 2023) — LLM proposer + evaluator; here the evaluator is the closure certifier.\n", .{});
}
