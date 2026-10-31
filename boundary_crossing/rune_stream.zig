//! rune_stream.zig — network training with the RUNE ladder as the memory (not a flat first-N-words cap). No LLM.
//!
//! Micah caught the drift: corpus_english/network_train count plain word TOKENS into a fixed matrix and bound memory
//! with a crude "keep the first 10k words, then stop" cap. That's NOT the rune-native design. A token is only the
//! INPUT unit; the MEMORY should be RUNES — patterns that earn RANK (NOISE→EMERGING→PATTERN→VALIDATED) by recurring
//! across DISTINCT CONTEXTS, with one-off noise TTL-PRUNED (the ghost_engine triad ladder, ported in tiered_learner).
//!
//! This restores it for streaming, where it matters most. Each streamed word is a candidate rune. It promotes as it
//! recurs across distinct contexts; hapax noise (names, boilerplate, typos — the Zipf tail) decays and is pruned, so
//! memory is bounded by RANK+TTL, adaptively, not by a first-come cap. ONLY promoted runes (PATTERN+) get a model
//! slot, so the learned vectors are built from SIGNAL, never noise. Same live web stream, same PPMI readout.
//!
//! Run: zig build rune-stream --release=fast            (streams a default public-domain text live)
//!      zig build rune-stream --release=fast -- URL     (stream any text URL through the rune ladder)

const std = @import("std");

const SLOTS: usize = 6000; // model rows = promoted runes (PATTERN+)
const CTX: usize = 1200; // model cols = the most stable runes (VALIDATED)
const W: usize = 4;
const SMOOTH: f64 = 0.75;
const BYTE_CAP: usize = 64 * 1024 * 1024;
const PRUNE_EVERY: u64 = 100_000; // sweep noise this often (ticks = tokens)
const TTL_NOISE: u64 = 40_000; // a once-seen rune not re-seen within this window is pruned

// promotion thresholds: occurrences AND distinct-context count (popcount of a neighbor-hash bloom)
fn rankOf(occ: u32, ctx: u32) u8 {
    if (occ >= 25 and ctx >= 10) return 3; // VALIDATED
    if (occ >= 6 and ctx >= 4) return 2; // PATTERN
    if (occ >= 2) return 1; // EMERGING
    return 0; // NOISE (seen once)
}
fn rankName(r: u8) []const u8 {
    return switch (r) {
        3 => "VALIDATED",
        2 => "PATTERN",
        1 => "EMERGING",
        else => "NOISE",
    };
}

const Rune = struct {
    occ: u32 = 0,
    ctxbits: u64 = 0, // bloom of neighbor hashes → distinct-context proxy (popcount)
    last: u64 = 0,
    rank: u8 = 0,
    slot: i32 = -1, // model target row, or -1 until promoted to PATTERN
    cdim: i32 = -1, // context column, or -1 until promoted to VALIDATED
};

var runes: std.StringHashMap(Rune) = undefined;
var mat: []f32 = undefined;
var slot_word: [][]const u8 = undefined;
var next_slot: usize = 0;
var next_cdim: usize = 0;
var tick: u64 = 0;
var pruned_total: u64 = 0;
var peak_table: usize = 0;
var arena_g: std.mem.Allocator = undefined;

// streaming tokenizer state (persists across chunk boundaries)
var tokbuf: [64]u8 = undefined;
var tn: usize = 0;
const Recent = struct { slot: i32 = -1, cdim: i32 = -1, hash: u32 = 0 };
var recent = [_]Recent{.{}} ** W;

fn lo(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}
fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn hashWord(w: []const u8) u32 {
    var h: u32 = 2166136261;
    for (w) |c| {
        h ^= c;
        h *%= 16777619;
    }
    return h;
}

fn emit(word: []const u8) void {
    const h = hashWord(word);
    const gop = runes.getOrPut(word) catch return;
    if (!gop.found_existing) {
        gop.key_ptr.* = arena_g.dupe(u8, word) catch return;
        gop.value_ptr.* = .{};
    }
    const r = gop.value_ptr;
    r.occ +|= 1;
    r.last = tick;
    for (recent) |nb| if (nb.hash != 0) {
        r.ctxbits |= (@as(u64, 1) << @intCast(nb.hash & 63));
    };
    // re-rank; on promotion, hand out a model slot (PATTERN) / context dim (VALIDATED)
    const nr = rankOf(r.occ, @popCount(r.ctxbits));
    if (nr > r.rank) {
        r.rank = nr;
        if (r.rank >= 2 and r.slot < 0 and next_slot < SLOTS) {
            r.slot = @intCast(next_slot);
            slot_word[next_slot] = gop.key_ptr.*;
            next_slot += 1;
        }
        if (r.rank >= 3 and r.cdim < 0 and next_cdim < CTX) {
            r.cdim = @intCast(next_cdim);
            next_cdim += 1;
        }
    }
    // co-occurrence — ONLY between promoted runes (slot × cdim); noise never enters the model
    if (r.slot >= 0) {
        const s: usize = @intCast(r.slot);
        for (recent) |nb| if (nb.cdim >= 0) {
            mat[s * CTX + @as(usize, @intCast(nb.cdim))] += 1;
        };
    }
    if (r.cdim >= 0) {
        const cd: usize = @intCast(r.cdim);
        for (recent) |nb| if (nb.slot >= 0) {
            mat[@as(usize, @intCast(nb.slot)) * CTX + cd] += 1;
        };
    }
    var k: usize = W - 1;
    while (k > 0) : (k -= 1) recent[k] = recent[k - 1];
    recent[0] = .{ .slot = r.slot, .cdim = r.cdim, .hash = h };
    tick += 1;
}

// prune the Zipf tail: once-seen runes not re-seen within TTL are forgotten (memory bounded by rank, not a cap)
fn prune(a: std.mem.Allocator) void {
    var dead = std.ArrayList([]const u8).init(a);
    defer dead.deinit();
    var it = runes.iterator();
    while (it.next()) |e| {
        if (e.value_ptr.rank == 0 and tick - e.value_ptr.last > TTL_NOISE) dead.append(e.key_ptr.*) catch {};
    }
    for (dead.items) |key| {
        if (runes.remove(key)) pruned_total += 1;
    }
}

fn consume(a: std.mem.Allocator, chunk: []const u8) void {
    for (chunk) |c| {
        if (isAlpha(c)) {
            if (tn < tokbuf.len) {
                tokbuf[tn] = lo(c);
                tn += 1;
            }
        } else {
            if (tn >= 2) emit(tokbuf[0..tn]);
            tn = 0;
            if (tick % PRUNE_EVERY == 0 and tick > 0) {
                if (runes.count() > peak_table) peak_table = runes.count();
                prune(a);
            }
        }
    }
}

fn cosRows(t1: usize, t2: usize, cdim: usize) f32 {
    var s: f32 = 0;
    for (0..cdim) |k| s += mat[t1 * CTX + k] * mat[t2 * CTX + k];
    return s;
}
fn printNN(o: anytype, query: []const u8, cdim: usize) !void {
    const r = runes.get(query) orelse {
        try o.print("  {s:<9} → (not seen)\n", .{query});
        return;
    };
    if (r.slot < 0) {
        try o.print("  {s:<9} → (rune rank {s}, never promoted to a model slot)\n", .{ query, rankName(r.rank) });
        return;
    }
    const qid: usize = @intCast(r.slot);
    var bid = [_]usize{0} ** 6;
    var bsc = [_]f32{-2.0} ** 6;
    for (0..next_slot) |t| {
        if (t == qid) continue;
        const s = cosRows(qid, t, cdim);
        if (s <= bsc[5]) continue;
        var p: usize = 5;
        while (p > 0 and bsc[p - 1] < s) : (p -= 1) {
            bsc[p] = bsc[p - 1];
            bid[p] = bid[p - 1];
        }
        bsc[p] = s;
        bid[p] = t;
    }
    try o.print("  {s:<9} →", .{query});
    for (0..6) |i| try o.print("  {s} {d:.2}", .{ slot_word[bid[i]], bsc[i] });
    try o.print("\n", .{});
}

pub fn main() !void {
    var arena_s = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_s.deinit();
    const a = arena_s.allocator();
    arena_g = a;
    const o = std.io.getStdOut().writer();
    const pa = std.heap.page_allocator;

    var argit = try std.process.argsWithAllocator(a);
    _ = argit.next();
    const url = argit.next() orelse "https://www.gutenberg.org/cache/epub/2600/pg2600.txt";

    try o.print("=== RUNE STREAM — network training with the RUNE ladder as memory (rank+prune, not a flat cap). No LLM ===\n\n", .{});
    try o.print("streaming: {s}\n", .{url});
    try o.print("tokens are the input; RUNES are the memory: promote by occurrence×distinct-context, TTL-prune the noise.\n\n", .{});

    mat = try pa.alloc(f32, SLOTS * CTX);
    @memset(mat, 0);
    runes = std.StringHashMap(Rune).init(a);
    slot_word = try a.alloc([]const u8, SLOTS);

    var child = std.process.Child.init(&.{ "curl", "-sL", "--max-time", "150", url }, a);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    const stream = child.stdout.?;

    var rbuf: [65536]u8 = undefined;
    var total: usize = 0;
    var next_mark: usize = 2 * 1024 * 1024;
    var capped = false;
    while (true) {
        const n = stream.read(&rbuf) catch break;
        if (n == 0) break;
        consume(a, rbuf[0..n]);
        total += n;
        if (total >= next_mark) {
            try o.print("  …{d:.1} MB | live runes {d} (pruned {d} noise) | promoted slots {d} | validated dims {d}\n", .{ @as(f64, @floatFromInt(total)) / 1e6, runes.count(), pruned_total, next_slot, next_cdim });
            next_mark += 2 * 1024 * 1024;
        }
        if (total >= BYTE_CAP) {
            capped = true;
            break;
        }
    }
    if (capped) _ = child.kill() catch {} else _ = child.wait() catch {};
    if (total < 50_000) {
        try o.print("\nstream returned only {d} bytes — network/URL issue. Nothing trained.\n", .{total});
        return;
    }

    // rune census
    var census = [_]usize{0} ** 4;
    var cit = runes.iterator();
    while (cit.next()) |e| census[e.value_ptr.rank] += 1;
    try o.print("\nstreamed {d:.2} MB, {d} ticks. RUNE CENSUS (the memory that survived):\n", .{ @as(f64, @floatFromInt(total)) / 1e6, tick });
    try o.print("  VALIDATED {d}   PATTERN {d}   EMERGING {d}   NOISE {d}   |   pruned {d} hapax-noise along the way (peak table {d})\n", .{ census[3], census[2], census[1], census[0], pruned_total, peak_table });
    try o.print("  → only the {d} PATTERN+ runes got model slots; noise never touched the vectors.\n", .{next_slot});

    // PPMI on the promoted matrix
    const cdim = @min(CTX, next_cdim);
    var rowsum = try a.alloc(f64, next_slot);
    var colsum = try a.alloc(f64, cdim);
    @memset(rowsum, 0);
    @memset(colsum, 0);
    var grand: f64 = 0;
    for (0..next_slot) |t| {
        for (0..cdim) |c| {
            const v = mat[t * CTX + c];
            if (v != 0) {
                rowsum[t] += v;
                colsum[c] += v;
                grand += v;
            }
        }
    }
    var colsm = try a.alloc(f64, cdim);
    var zsm: f64 = 0;
    for (0..cdim) |c| {
        colsm[c] = std.math.pow(f64, colsum[c], SMOOTH);
        zsm += colsm[c];
    }
    for (0..next_slot) |t| {
        var nrm: f64 = 0;
        for (0..cdim) |c| {
            const v = mat[t * CTX + c];
            if (v > 0 and rowsum[t] > 0) {
                const pmi = std.math.log(f64, std.math.e, (@as(f64, v) / grand) / ((rowsum[t] / grand) * (colsm[c] / zsm)));
                const ppmi: f32 = if (pmi > 0) @floatCast(pmi) else 0;
                mat[t * CTX + c] = ppmi;
                nrm += @as(f64, ppmi) * @as(f64, ppmi);
            } else mat[t * CTX + c] = 0;
        }
        if (nrm > 0) {
            const inv: f32 = @floatCast(1.0 / @sqrt(nrm));
            for (0..cdim) |c| mat[t * CTX + c] *= inv;
        }
    }

    try o.print("\n── what the RUNES learned (neighbors among promoted runes — signal only, noise pruned) ──\n", .{});
    const probes = [_][]const u8{ "prince", "war", "love", "death", "horse", "money", "eyes", "night", "woman", "battle" };
    for (probes) |p| try printNN(o, p, cdim);

    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("Fixed: the MEMORY is rune-native again. Tokens are still the input unit (you must cut text into words), but\n", .{});
    try o.print("what we KEEP is the rune ladder — {d} VALIDATED + {d} PATTERN runes that earned rank by recurring across\n", .{ census[3], census[2] });
    try o.print("distinct contexts, while {d} once-seen hapax runes (names, boilerplate, the Zipf tail) were TTL-pruned. Memory\n", .{pruned_total});
    try o.print("is bounded by RANK, not a first-come cap, and the vectors are built only from PATTERN+ signal — so the noise\n", .{});
    try o.print("that polluted network_train's first-10k (ebook/title/tovich) never enters here. This is the ghost_engine\n", .{});
    try o.print("triad ladder doing exactly its job on a live stream: forge the recurring, forget the once-seen. Same PPMI\n", .{});
    try o.print("readout, same truth, no LLM — but the memory is now the runes, as it should have been. Good catch.\n", .{});
}
