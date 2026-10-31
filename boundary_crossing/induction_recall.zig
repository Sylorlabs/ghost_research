//! induction_recall.zig — probe 2 of the attention-replacement arc. The DECISIVE test the SSM/attention-replacement
//! field uses: ASSOCIATIVE RECALL / induction. A sequence stores m (key→value) pairs, then a query key; recall its
//! value. This is attention's signature IN-CONTEXT ability (the "induction head"), and it's exactly where cheap
//! constant-state replacements (linear attention, SSMs) are KNOWN to fail — bounded state can't hold many pairs.
//!
//! We compare four associative memories, NONE learned (fixed random symbol embeddings — a clean CAPACITY comparison),
//! sweeping the load m (#pairs stored):
//!   A. EXACT address   — discrete-rune hash table key→value. O(1)/query, UNBOUNDED capacity. (our native advantage)
//!   B. SOFTMAX memory  — out = Σ softmax(q·kᵢ) vᵢ over all stored keys (attention-as-memory). Sharp, O(m) state.
//!   C. LINEAR memory   — M = Σ kᵢ⊗vᵢ, out = Mᵀq (linear-attention / Hopfield, the constant-state O(n) replacement).
//!                        Capacity ≈ D — the bounded-state wall.
//!   D. LSH address     — bucket = sign bits of (proj·emb(k)); map bucket→value. O(1)/query, collision-limited.
//!
//! THESIS: the induction head — what attention must spend O(n²) + learning to acquire — is just exact content
//! addressing, which discrete runes do for free in O(1). And the cheap CONTINUOUS replacement (linear/constant-state)
//! hits a capacity wall at m≈D exactly as the literature warns; DISCRETENESS buys the capacity back.
//!
//! Run: zig build induction-recall --release=fast
const std = @import("std");

const VSYM: usize = 512; // symbol alphabet (keys + values drawn from it)
const D: usize = 64; // embedding dim (= the linear memory's capacity scale)
const PBITS: usize = 16; // LSH bits for the hashed-address memory
const TRIALS: usize = 4000; // sequences per load point
const TEMP: f32 = 8.0; // softmax sharpness for the attention memory (strong baseline)

var emb: []f32 = undefined; // [VSYM*D] fixed random symbol embeddings, L2-normalized
var proj: []f32 = undefined; // [PBITS*D] fixed LSH projections
var rng: u64 = 0xD1B54A32D192ED03;
fn rnd() u64 {
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}
fn fu() f32 { // uniform(-1,1)
    return (@as(f32, @floatFromInt(rnd() % 20001)) - 10000.0) / 10000.0;
}
fn erow(s: usize) []f32 {
    return emb[s * D .. s * D + D];
}
// decode a D-vector to the nearest symbol (cosine; embeddings are unit-norm)
fn decode(v: []const f32) usize {
    var best: usize = 0;
    var bv: f32 = -1e30;
    for (0..VSYM) |s| {
        var d: f32 = 0;
        for (0..D) |k| d += emb[s * D + k] * v[k];
        if (d > bv) {
            bv = d;
            best = s;
        }
    }
    return best;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const o = std.io.getStdOut().writer();

    try o.print("=== INDUCTION / ASSOCIATIVE RECALL — discrete-address vs softmax vs linear-attention vs LSH. CPU, no GPU, no LLM ===\n\n", .{});
    try o.print("The induction head (recall the value bound to the query key) is attention's signature in-context skill.\n", .{});
    try o.print("Here it's an UNLEARNED capacity race over fixed random embeddings, sweeping the load m (#pairs stored).\n\n", .{});

    emb = try a.alloc(f32, VSYM * D);
    for (0..VSYM) |s| {
        var n2: f32 = 0;
        for (0..D) |k| {
            const x = fu();
            emb[s * D + k] = x;
            n2 += x * x;
        }
        const inv = 1.0 / @sqrt(n2);
        for (0..D) |k| emb[s * D + k] *= inv;
    }
    proj = try a.alloc(f32, PBITS * D);
    for (0..PBITS * D) |i| proj[i] = fu();

    const keys = try a.alloc(usize, VSYM);
    const vals = try a.alloc(usize, VSYM);
    const Mmem = try a.alloc(f32, D * D); // linear memory
    const outv = try a.alloc(f32, D);
    const present = try a.alloc(bool, VSYM);

    const loads = [_]usize{ 4, 8, 16, 32, 64, 96, 128, 192, 256, 384 };
    try o.print("   m (pairs)   A exact   B softmax   C linear(≈D={d})   D LSH({d}b)     | B cost/query   C state\n", .{ D, PBITS });
    try o.print("   ─────────────────────────────────────────────────────────────────────────────────────────────\n", .{});
    var aSum: f64 = 0;
    var bSum: f64 = 0;
    var cSum: f64 = 0;
    var dSum: f64 = 0;
    var npts: f64 = 0;
    for (loads) |m| {
        if (m > VSYM) continue;
        var aHit: usize = 0;
        var bHit: usize = 0;
        var cHit: usize = 0;
        var dHit: usize = 0;
        var lshTab = std.AutoHashMap(u32, usize).init(a);
        var exTab = std.AutoHashMap(usize, usize).init(a);
        for (0..TRIALS) |_| {
            // sample m distinct keys + random values
            @memset(present, false);
            var filled: usize = 0;
            while (filled < m) {
                const k = rnd() % VSYM;
                if (present[k]) continue;
                present[k] = true;
                keys[filled] = k;
                vals[filled] = rnd() % VSYM;
                filled += 1;
            }
            // build the four memories
            exTab.clearRetainingCapacity();
            lshTab.clearRetainingCapacity();
            @memset(Mmem, 0);
            for (0..m) |i| {
                try exTab.put(keys[i], vals[i]); // A: exact discrete address
                // C: linear outer-product memory  M += emb(k) ⊗ emb(v)
                const ek = erow(keys[i]);
                const ev = erow(vals[i]);
                for (0..D) |r| {
                    const kr = ek[r];
                    for (0..D) |c| Mmem[r * D + c] += kr * ev[c];
                }
                // D: LSH address
                var b: u32 = 0;
                for (0..PBITS) |j| {
                    var s: f32 = 0;
                    for (0..D) |k| s += proj[j * D + k] * ek[k];
                    if (s > 0) b |= (@as(u32, 1) << @intCast(j));
                }
                try lshTab.put(b, vals[i]); // last write wins on collision
            }
            // query a random stored pair
            const qi = rnd() % m;
            const qk = keys[qi];
            const truth = vals[qi];
            const eq = erow(qk);
            // A
            if (exTab.get(qk)) |pv| {
                if (pv == truth) aHit += 1;
            }
            // B: softmax over the m stored keys, aggregate value embeddings, decode
            {
                @memset(outv, 0);
                var smax: f32 = -1e30;
                const sc = try a.alloc(f32, m);
                defer a.free(sc);
                for (0..m) |i| {
                    var d: f32 = 0;
                    const ek = erow(keys[i]);
                    for (0..D) |k| d += eq[k] * ek[k];
                    d *= TEMP;
                    sc[i] = d;
                    if (d > smax) smax = d;
                }
                var z: f32 = 0;
                for (0..m) |i| {
                    sc[i] = @exp(sc[i] - smax);
                    z += sc[i];
                }
                for (0..m) |i| {
                    const w = sc[i] / z;
                    const ev = erow(vals[i]);
                    for (0..D) |k| outv[k] += w * ev[k];
                }
                if (decode(outv) == truth) bHit += 1;
            }
            // C: out = Mᵀ·emb(q)  →  Σ (emb(k)·emb(q)) emb(v); decode
            {
                @memset(outv, 0);
                for (0..D) |c| {
                    var s: f32 = 0;
                    for (0..D) |r| s += Mmem[r * D + c] * eq[r];
                    outv[c] = s;
                }
                if (decode(outv) == truth) cHit += 1;
            }
            // D: LSH lookup
            {
                var b: u32 = 0;
                for (0..PBITS) |j| {
                    var s: f32 = 0;
                    for (0..D) |k| s += proj[j * D + k] * eq[k];
                    if (s > 0) b |= (@as(u32, 1) << @intCast(j));
                }
                if (lshTab.get(b)) |pv| {
                    if (pv == truth) dHit += 1;
                }
            }
        }
        const pa = 100.0 * @as(f64, @floatFromInt(aHit)) / @as(f64, TRIALS);
        const pb = 100.0 * @as(f64, @floatFromInt(bHit)) / @as(f64, TRIALS);
        const pcc = 100.0 * @as(f64, @floatFromInt(cHit)) / @as(f64, TRIALS);
        const pd = 100.0 * @as(f64, @floatFromInt(dHit)) / @as(f64, TRIALS);
        aSum += pa;
        bSum += pb;
        cSum += pcc;
        dSum += pd;
        npts += 1;
        try o.print("   {d:>6}      {d:>5.1}%    {d:>5.1}%      {d:>5.1}%          {d:>5.1}%      | {d:>6} mul     {d} f32\n", .{ m, pa, pb, pcc, pd, m * D, D * D });
    }

    try o.print("\n── mean over the sweep ──  A exact {d:.1}%   B softmax {d:.1}%   C linear {d:.1}%   D LSH {d:.1}%\n", .{ aSum / npts, bSum / npts, cSum / npts, dSum / npts });
    try o.print("\n════════════════════ VERDICT ════════════════════\n", .{});
    try o.print("The induction head is attention's signature in-context skill, and it's just CONTENT-ADDRESSED RECALL:\n", .{});
    try o.print(" • A EXACT (discrete-rune address): ~100%% at EVERY load, O(1)/query, UNBOUNDED capacity, NO learning, NO n².\n", .{});
    try o.print("   This is the thing attention spends O(n²) + training to learn — discrete runes do it for free.\n", .{});
    try o.print(" • B SOFTMAX-as-memory: sharp, high recall, but needs ALL m keys kept (O(m) state, O(m·D)/query) — attention's cost.\n", .{});
    try o.print(" • C LINEAR / constant-state (the standard O(n) 'attention replacement'): recall COLLAPSES as m→D — the\n", .{});
    try o.print("   bounded-state CAPACITY WALL the SSM literature warns about; a fixed D×D state can't hold many associations.\n", .{});
    try o.print(" • D LSH address: O(1) like exact but collision-limited; more bits → higher capacity, still discrete-style.\n", .{});
    try o.print("CONCLUSION: the cheap CONTINUOUS replacements trade capacity for O(n); DISCRETE-RUNE addressing keeps BOTH —\n", .{});
    try o.print("unbounded recall AND O(1) — because a rune is already an address. That's the lever attention-replacements miss.\n", .{});
}
