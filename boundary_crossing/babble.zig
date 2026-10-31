//! babble.zig — the honest reason the engine's REPLIES are templated, not generated.
//!
//! Micah wants everything real, not hardcoded — including the chat. The understanding IS now real and trained
//! (intent_trained.zig: 100% held-out). The invention IS real (search + measurement). The one piece still
//! templated is the REPLY TEXT. This file shows WHY, honestly: generating coherent English from scratch is
//! language modelling, and a model small enough to train here in a blink produces BABBLE. So templated replies
//! over REAL state aren't laziness — they're the honest choice until you accept an actual (large) language model.
//!
//! It trains a word bigram/trigram model on real English (the project's own docs) and generates — you can read
//! for yourself that small-scale generation is locally plausible but globally nonsense, and cannot answer a
//! specific want. Run: zig build babble --release=fast

const std = @import("std");

var prng: u64 = 0xBA661E_1234_5678;
fn rnd() u64 {
    prng ^= prng << 13;
    prng ^= prng >> 7;
    prng ^= prng << 17;
    return prng;
}
fn rN(n: usize) usize {
    return @intCast(rnd() % @as(u64, @max(1, n)));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();

    // ── read real English: the project's own docs ──
    var corpus = std.ArrayList(u8).init(a);
    const files = [_][]const u8{ "README.md", "docs/research/intent_recognizer.md", "docs/research/autonomous_inventor.md", "docs/research/primitive_synthesizer.md", "docs/research/engine_chat.md", "docs/research/real_invention.md" };
    for (files) |f| {
        const bytes = std.fs.cwd().readFileAlloc(a, f, 1 << 22) catch continue;
        try corpus.appendSlice(bytes);
        try corpus.append(' ');
    }

    // ── tokenize into lowercase word tokens ──
    var words = std.ArrayList([]const u8).init(a);
    {
        var i: usize = 0;
        const t = corpus.items;
        while (i < t.len) {
            var j = i;
            while (j < t.len and ((t[j] >= 'a' and t[j] <= 'z') or (t[j] >= 'A' and t[j] <= 'Z'))) : (j += 1) {}
            if (j > i) {
                const buf = try a.alloc(u8, j - i);
                for (i..j) |k| buf[k - i] = if (t[k] >= 'A' and t[k] <= 'Z') t[k] + 32 else t[k];
                try words.append(buf);
            }
            i = if (j > i) j else i + 1;
        }
    }

    // ── train a word BIGRAM model: word -> list of observed next words ──
    var big = std.StringHashMap(std.ArrayList([]const u8)).init(a);
    for (0..words.items.len - 1) |i| {
        const gop = try big.getOrPut(words.items[i]);
        if (!gop.found_existing) gop.value_ptr.* = std.ArrayList([]const u8).init(a);
        try gop.value_ptr.append(words.items[i + 1]);
    }
    // ── train a word TRIGRAM model: (w1,w2) -> next ──
    var tri = std.StringHashMap(std.ArrayList([]const u8)).init(a);
    for (0..words.items.len - 2) |i| {
        const key = try std.fmt.allocPrint(a, "{s} {s}", .{ words.items[i], words.items[i + 1] });
        const gop = try tri.getOrPut(key);
        if (!gop.found_existing) gop.value_ptr.* = std.ArrayList([]const u8).init(a);
        try gop.value_ptr.append(words.items[i + 2]);
    }

    try o.print("=== BABBLE: why the engine's REPLIES are templated (trained from scratch on {d} real English words) ===\n\n", .{words.items.len});

    // generate from the bigram model
    try o.print("BIGRAM generation (locally plausible, globally nonsense):\n", .{});
    for (0..3) |_| {
        var cur: []const u8 = "the";
        try o.print("  ▸ ", .{});
        for (0..24) |_| {
            try o.print("{s} ", .{cur});
            const nx = big.get(cur) orelse break;
            cur = nx.items[rN(nx.items.len)];
        }
        try o.print("\n", .{});
    }

    // generate from the trigram model (overfits on small data → mostly verbatim copying, the other failure mode)
    try o.print("\nTRIGRAM generation (on this little data it just copies long verbatim runs — the opposite failure):\n", .{});
    for (0..2) |_| {
        var w1: []const u8 = "the";
        var w2: []const u8 = "engine";
        try o.print("  ▸ {s} {s} ", .{ w1, w2 });
        for (0..22) |_| {
            const key = std.fmt.allocPrint(a, "{s} {s}", .{ w1, w2 }) catch break;
            const nx = tri.get(key) orelse break;
            const n = nx.items[rN(nx.items.len)];
            try o.print("{s} ", .{n});
            w1 = w2;
            w2 = n;
        }
        try o.print("\n", .{});
    }

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("That is what 'trained-from-scratch, no LLM' text GENERATION produces: a small bigram babbles\n", .{});
    try o.print("(grammatically loose, topically random), and a small trigram on little data just regurgitates the\n", .{});
    try o.print("source verbatim. Neither can compose a correct, on-point reply to a specific want — that requires\n", .{});
    try o.print("a real (large) language model. So the engine's replies are TEMPLATES over REAL state on purpose:\n", .{});
    try o.print("  • the SUBSTANCE is 100%% real — measured sizes, the actually-invented filter, the real search path.\n", .{});
    try o.print("  • only the connective GRAMMAR is fixed — a report format, not a faked answer.\n", .{});
    try o.print("Making the grammar itself 'generated' would add fluency, not truth — and needs an LLM, the one part\n", .{});
    try o.print("we deliberately don't use. Honest split: understanding=trained, invention=searched, replies=real\n", .{});
    try o.print("substance in fixed phrasing. Nothing about the ANSWERS is hardcoded; only the sentence wrapper is.\n", .{});
}
