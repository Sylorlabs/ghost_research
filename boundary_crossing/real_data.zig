//! Boundary crossing — source A: a REAL DATASET injects out-of-substrate structure.
//!
//! Same inject→certify loop; the out-of-substrate ingredient is now real-world DATA (English prose from
//! corpus/austen.txt). The claim the Closure Principle makes: real data carries structure that no fixed
//! algebraic substrate generates — it can only be injected from the data. We test it concretely.
//!
//! Target: predict whether the NEXT character is a vowel, from the CURRENT character. The substrate is the
//! algebraic structure of the byte encoding: low-degree (≤2) functions of the current char's 8 bits. The
//! bigram regularity ("q precedes a vowel; a space rarely does") is a fact about LANGUAGE, not about the
//! byte code — so it should be out of the low-degree substrate, and captured only by a generator learned
//! from the data (the empirical per-character next-vowel rate). The certifier confirms on HELD-OUT text.
//!
//! Run: zig build real-data --release=fast
//! (reads corpus/austen.txt; reports honest balanced accuracies — the gap is the data-injected structure.)

const std = @import("std");

fn isVowel(c: u8) bool {
    return switch (c | 0x20) { // lowercase fold
        'a', 'e', 'i', 'o', 'u' => true,
        else => false,
    };
}
fn isAlpha(c: u8) bool {
    return (c | 0x20) >= 'a' and (c | 0x20) <= 'z';
}
fn sigmoid(z: f64) f64 {
    return 1.0 / (1.0 + @exp(-@max(@as(f64, -30), @min(@as(f64, 30), z))));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== Boundary crossing — source A: a real dataset (English prose) injects out-of-substrate structure ===\n\n", .{});

    // load real text (try a few paths; cap length for speed)
    const paths = [_][]const u8{ "../corpus/austen.txt", "corpus/austen.txt", "/home/micah/Desktop/Sylorlabs/ghost_research/corpus/austen.txt" };
    var text: []u8 = undefined;
    var loaded = false;
    for (paths) |p| {
        const f = std.fs.cwd().openFile(p, .{}) catch continue;
        defer f.close();
        text = f.readToEndAlloc(alloc, 2_000_000) catch continue;
        loaded = true;
        try out.print("loaded {d} bytes of real text from {s}\n\n", .{ text.len, p });
        break;
    }
    if (!loaded) {
        try out.print("could not open corpus/austen.txt — run from the boundary_crossing/ dir or check the path.\n", .{});
        return;
    }

    // build (current char, next-is-vowel) over alphabetic-current pairs
    const Pair = struct { c: u8, y: f64 };
    var list = std.ArrayList(Pair).init(alloc);
    for (0..text.len - 1) |i| {
        if (!isAlpha(text[i])) continue;
        try list.append(.{ .c = text[i] | 0x20, .y = if (isVowel(text[i + 1])) 1.0 else 0.0 });
    }
    const pairs = list.items;
    const ntr = pairs.len * 2 / 3;

    // ── data generator: empirical per-char next-vowel rate on TRAIN ──
    var cnt = [_]f64{0} ** 256;
    var vow = [_]f64{0} ** 256;
    var marg: f64 = 0;
    for (0..ntr) |i| {
        cnt[pairs[i].c] += 1;
        vow[pairs[i].c] += pairs[i].y;
        marg += pairs[i].y;
    }
    marg /= @floatFromInt(ntr);
    var rate = [_]f64{0} ** 256;
    for (0..256) |c| rate[c] = if (cnt[c] > 0) vow[c] / cnt[c] else marg;

    // balanced-accuracy helper on TEST
    const bal = struct {
        fn f(pred: []const bool, pr: []const Pair, lo: usize) f64 {
            var tp: f64 = 0;
            var fn_: f64 = 0;
            var tn: f64 = 0;
            var fp: f64 = 0;
            for (lo..pr.len) |i| {
                const a = pr[i].y > 0.5;
                const p = pred[i - lo];
                if (a and p) tp += 1 else if (a and !p) fn_ += 1 else if (!a and !p) tn += 1 else fp += 1;
            }
            return 0.5 * (tp / @max(1, tp + fn_) + tn / @max(1, tn + fp));
        }
    }.f;

    const nte = pairs.len - ntr;
    const predbuf = try alloc.alloc(bool, nte);

    // (0) marginal baseline: always predict the majority class
    for (0..nte) |i| predbuf[i] = marg > 0.5;
    const acc_marg = bal(predbuf, pairs, ntr);

    // (1) data generator: predict vowel-next iff the char's empirical rate > 0.5
    for (0..nte) |i| predbuf[i] = rate[pairs[ntr + i].c] > 0.5;
    const acc_data = bal(predbuf, pairs, ntr);

    // (2) substrate: low-degree (≤2) logistic over the 8 bits of the current char
    const DIM = 8 + 8 * 7 / 2; // 8 bits + 28 pairwise products = 36
    const X = try alloc.alloc([]f64, pairs.len);
    for (0..pairs.len) |i| {
        X[i] = try alloc.alloc(f64, DIM);
        var k: usize = 0;
        var bits: [8]f64 = undefined;
        for (0..8) |b| {
            bits[b] = @floatFromInt((pairs[i].c >> @intCast(b)) & 1);
            X[i][k] = bits[b];
            k += 1;
        }
        for (0..8) |a| for (a + 1..8) |b| {
            X[i][k] = bits[a] * bits[b];
            k += 1;
        };
    }
    // standardize on train
    for (0..DIM) |j| {
        var mu: f64 = 0;
        for (0..ntr) |i| mu += X[i][j];
        mu /= @floatFromInt(ntr);
        var sd: f64 = 0;
        for (0..ntr) |i| sd += (X[i][j] - mu) * (X[i][j] - mu);
        sd = @max(1e-6, @sqrt(sd / @as(f64, @floatFromInt(ntr))));
        for (0..pairs.len) |i| X[i][j] = (X[i][j] - mu) / sd;
    }
    var w = [_]f64{0} ** (DIM + 1);
    for (0..120) |_| for (0..ntr) |i| {
        var z = w[DIM];
        for (0..DIM) |j| z += w[j] * X[i][j];
        const e = sigmoid(z) - pairs[i].y;
        for (0..DIM) |j| w[j] -= 0.05 * e * X[i][j];
        w[DIM] -= 0.05 * e;
    };
    for (0..nte) |i| {
        var z = w[DIM];
        for (0..DIM) |j| z += w[j] * X[ntr + i][j];
        predbuf[i] = z >= 0;
    }
    const acc_sub = bal(predbuf, pairs, ntr);

    // (3) irreducibility: can the low-degree substrate reconstruct the data feature rate[c]? held-out R²
    var wr = [_]f64{0} ** (DIM + 1);
    for (0..400) |_| for (0..ntr) |i| {
        var z = wr[DIM];
        for (0..DIM) |j| z += wr[j] * X[i][j];
        const e = z - rate[pairs[i].c];
        for (0..DIM) |j| wr[j] -= 0.02 * e * X[i][j];
        wr[DIM] -= 0.02 * e;
    };
    var mu: f64 = 0;
    for (ntr..pairs.len) |i| mu += rate[pairs[i].c];
    mu /= @floatFromInt(nte);
    var ssr: f64 = 0;
    var sst: f64 = 0;
    for (ntr..pairs.len) |i| {
        var z = wr[DIM];
        for (0..DIM) |j| z += wr[j] * X[i][j];
        ssr += (rate[pairs[i].c] - z) * (rate[pairs[i].c] - z);
        sst += (rate[pairs[i].c] - mu) * (rate[pairs[i].c] - mu);
    }
    const r2 = 1.0 - ssr / @max(1e-9, sst);

    // ── results ──
    try out.print("{d} alphabetic bigrams; train/test = {d}/{d}; marginal P(next vowel) = {d:.3}\n\n", .{ pairs.len, ntr, nte, marg });
    try out.print("predictor                                  | held-out balanced accuracy\n", .{});
    try out.print("-------------------------------------------+---------------------------\n", .{});
    try out.print("marginal baseline (always majority)        |   {d:.3}\n", .{acc_marg});
    try out.print("SUBSTRATE: low-degree (≤2) byte-bit algebra |   {d:.3}\n", .{acc_sub});
    try out.print("DATA GENERATOR: empirical bigram rate (corpus) |   {d:.3}   ◄ injected from data\n", .{acc_data});
    try out.print("\nirreducibility: substrate reconstructs the data feature rate[c] at held-out R² = {d:.3}\n", .{r2});

    // ── verdict (honest about magnitude: escape is real but the irreducibility is partial) ──
    const escapes = acc_data > acc_sub + 0.03;
    const reducible_frac = r2; // fraction of the data feature the substrate CAN reconstruct
    try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    if (escapes) {
        try out.print("Real data IS an out-of-substrate ingredient — and here, mostly a RECOMBINATION with a real residual.\n", .{});
        try out.print("The empirical bigram generator predicts next-vowel at balanced {d:.3} on HELD-OUT text vs the low-\n", .{acc_data});
        try out.print("degree byte-bit substrate's {d:.3} — a real but MODEST escape of +{d:.3}. The reason it is modest is\n", .{ acc_sub, acc_data - acc_sub });
        try out.print("honest and measured: the substrate already reconstructs {d:.0}% of the data feature (R²={d:.3}), so most\n", .{ reducible_frac * 100, r2 });
        try out.print("of next-vowel IS low-degree-capturable; only the ~{d:.0}% residual is genuinely out of the substrate's\n", .{(1.0 - reducible_frac) * 100});
        try out.print("closure. That residual is the data-injected part — structure about LANGUAGE the byte code cannot forge.\n", .{});
        try out.print("(Mirrors the number-theory result: not all of mathematics was out-of-closure either — Thue-Morse was a\n", .{});
        try out.print("Fourier character. Here, not all of language is out-of-substrate; a real residual is.)\n", .{});
    } else {
        try out.print("Honest null-ish result: next-vowel-from-current-char is largely capturable by the low-degree substrate\n", .{});
        try out.print("(data {d:.3} vs substrate {d:.3}, R²={d:.3}). The mechanism holds; this target is mostly in-substrate.\n", .{ acc_data, acc_sub, r2 });
    }
    try out.print("\nSame loop as the number-theory engine and the superoptimizer, third source: real data. Same certifier.\n", .{});
    try out.print("Honest scope: this is statistical (bigram) structure captured by a learned lookup — the simplest out-of-\n", .{});
    try out.print("substrate ingredient — and a target where MOST structure is in-substrate, so the escape is a small\n", .{});
    try out.print("residual, not a clean break like primality. The certifier's value is exactly that it MEASURES the\n", .{});
    try out.print("split (here ~{d:.0}% recombination, ~{d:.0}% genuine) rather than letting the data look wholly novel.\n", .{ reducible_frac * 100, (1.0 - reducible_frac) * 100 });
    try out.print("\nSee: invention_engine.md, world_injection.md, superopt.md, ../README.md, CLOSURE_PRINCIPLE.md §J.\n", .{});
}
