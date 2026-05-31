//! Frontier harness + novelty certifier for the alien-architecture search.
//!
//! The research question (see CLAUDE.md / TESTING.md §20):
//!   Can execution-only search over a NON-HUMAN primitive space discover a
//!   sequence operator that pushes the recall ↔ length-gen frontier PAST where
//!   every known primitive sits — and if not, why not?
//!
//! Before any search we need two pieces of honest machinery, and they live here:
//!
//!   PHASE 0 — THE MAP.  Two tasks that pull in opposite directions:
//!     * length-gen (prefix-parity): a SCAN (running product, persistent state)
//!       is correct at any length; a fixed-depth/all-pairs operator (attention)
//!       cannot represent the unbounded recurrence → stuck at chance.
//!     * associative recall: K (key→value) bindings then a query key; ATTENTION
//!       does content-addressed lookup and nails it at any K; a bounded-state
//!       SCAN must compress K bindings into S slots → collapses to chance as
//!       K ≫ S.
//!   Placing the known mechanisms on this (recall, length-gen) plane gives the
//!   map. KILL-TEST: attention and scan must sit at OPPOSITE corners. If they
//!   don't, the tasks don't separate the mechanisms and no later claim is real.
//!
//!   PHASE 1 — THE NOVELTY CERTIFIER.  When the engine emits a bit-mixing
//!   monster we must know whether it is genuinely new or a known primitive in
//!   disguise (the ratio-gate/product-gate underdetermination already bit us).
//!   A BEHAVIOURAL FINGERPRINT — the operator's response to a battery of
//!   mechanism-revealing probes — clusters the known primitives. A candidate is
//!   "novel" only if its fingerprint is far from EVERY known anchor. KILL-TEST:
//!   a re-implemented scan (same behaviour, different formula) must certify as
//!   NOT novel (close to the scan anchor); attention must be far from scan.
//!
//! Operators here are HAND-WRITTEN references — concrete instances of each known
//! mechanism — used only to draw the map and anchor the clusters. The alien VM
//! that SEARCHES for a trade-off-breaker is Phase 2+ (inv_seq successor); its
//! programs will be scored and fingerprinted by exactly these functions.

const std = @import("std");

// ===========================================================================
// Tasks
// ===========================================================================

pub const VAL_VOCAB: usize = 4; // recall values 0..3  → chance = 0.25
pub const MAX_K: usize = 64; // max key→value pairs in a recall instance
pub const MEM_SLOTS: usize = 4; // bounded-scan associative memory capacity (S)
const L_MAX: usize = 512;

/// One associative-recall instance: K distinct keys each bound to a value, then
/// a query asking for the value of `keys[qpos]`. Truth = vals[qpos].
pub const RecallInst = struct {
    k: usize,
    keys: [MAX_K]u32 = undefined,
    vals: [MAX_K]f64 = undefined, // each in 0..VAL_VOCAB-1
    qpos: usize = 0,

    pub fn gen(rng: std.Random, k: usize) RecallInst {
        var inst = RecallInst{ .k = k };
        // distinct keys = a shuffled run of 1..k (so key%S is ~uniform over slots)
        for (0..k) |i| inst.keys[i] = @intCast(i + 1);
        rng.shuffle(u32, inst.keys[0..k]);
        for (0..k) |i| inst.vals[i] = @floatFromInt(rng.uintLessThan(usize, VAL_VOCAB));
        inst.qpos = rng.uintLessThan(usize, k);
        return inst;
    }
    fn answer(self: *const RecallInst) f64 {
        return self.vals[self.qpos];
    }
};

// ===========================================================================
// Operator interface
// ===========================================================================

/// A sequence-mixing mechanism, applied to BOTH tasks (the whole point: one
/// mechanism, opposite strengths). `parity` fills out[0..L] with sign(y[i]);
/// `recall` returns the predicted value for the query.
pub const Operator = struct {
    name: []const u8,
    parity: *const fn (x: []const f64, out: []f64) void,
    recall: *const fn (inst: *const RecallInst) f64,
};

// ---- reference: ATTENTION (content-addressed, fixed-depth, no carried state) --

/// Parity under a single attention-style layer: output is a sign of a convex
/// combination of the prefix tokens (here uniform attention = prefix mean).
/// No weighted average + sign can realise parity → this is ≈ chance, BY DESIGN
/// of what attention is. (Content-based weights don't help: parity is not a
/// function of a convex combination of ±1 inputs.)
fn attnParity(x: []const f64, out: []f64) void {
    var sum: f64 = 0;
    for (x, 0..) |xi, i| {
        sum += xi;
        out[i] = if (sum >= 0) 1 else -1; // sign(prefix mean)
    }
}
/// Recall under attention: match the query key against all key positions and
/// read the bound value directly. Content-addressed → exact at any K.
fn attnRecall(inst: *const RecallInst) f64 {
    const q = inst.keys[inst.qpos];
    for (0..inst.k) |i| if (inst.keys[i] == q) return inst.vals[i];
    return 0;
}
pub const attention = Operator{ .name = "attention", .parity = attnParity, .recall = attnRecall };

// ---- reference: SCAN (persistent state, O(1) memory, sequential) -------------

/// Parity under a scan: a single persistent accumulator running the product.
/// Correct at ANY length — the length-generalising primitive.
fn scanParity(x: []const f64, out: []f64) void {
    var acc: f64 = 1;
    for (x, 0..) |xi, i| {
        acc *= xi;
        out[i] = if (acc >= 0) 1 else -1;
    }
}
/// Recall under a bounded scan: a fixed S-slot associative memory, slot = key%S,
/// later writes overwrite. At query, read slot qkey%S; correct only if that slot
/// still holds the queried key's binding. As K ≫ S, collisions destroy bindings
/// → accuracy decays toward chance. A faithful bounded-state model.
fn scanRecall(inst: *const RecallInst) f64 {
    var slot_key = [_]u32{0} ** MEM_SLOTS;
    var slot_val = [_]f64{0} ** MEM_SLOTS;
    for (0..inst.k) |i| {
        const s = inst.keys[i] % MEM_SLOTS;
        slot_key[s] = inst.keys[i];
        slot_val[s] = inst.vals[i];
    }
    const q = inst.keys[inst.qpos];
    return slot_val[q % MEM_SLOTS]; // whatever currently occupies the slot
}
pub const scan = Operator{ .name = "scan", .parity = scanParity, .recall = scanRecall };

// ---- reference: LOCAL/CONV (fixed window, no long-range, no content addr) -----

/// Parity over a width-2 window only: sign(x[i]·x[i-1]). Captures local sign
/// structure, cannot accumulate the full prefix → poor parity, no length-gen.
fn convParity(x: []const f64, out: []f64) void {
    var prev: f64 = 1;
    for (x, 0..) |xi, i| {
        out[i] = if (xi * prev >= 0) 1 else -1;
        prev = xi;
    }
}
/// Recall with no content addressing: just return the most-recently-written
/// value (the last pair's value). Independent of the query → chance.
fn convRecall(inst: *const RecallInst) f64 {
    return inst.vals[inst.k - 1];
}
pub const local = Operator{ .name = "local", .parity = convParity, .recall = convRecall };

// ---- DISGUISED SCAN: same behaviour, different formula (for the kill-test) ----

/// Prefix-parity via the count of −1 tokens (even → +1, odd → −1). Mathematically
/// identical to the running product, computed by a totally different route. The
/// certifier MUST recognise this as the scan mechanism, not as something novel.
fn scanDisguisedParity(x: []const f64, out: []f64) void {
    var neg: usize = 0;
    for (x, 0..) |xi, i| {
        if (xi < 0) neg += 1;
        out[i] = if (neg % 2 == 0) 1 else -1;
    }
}
/// Same bounded memory, addressed by (key+S) % S (an equivalent re-indexing).
fn scanDisguisedRecall(inst: *const RecallInst) f64 {
    var slot_key = [_]u32{0} ** MEM_SLOTS;
    var slot_val = [_]f64{0} ** MEM_SLOTS;
    for (0..inst.k) |i| {
        const s = (inst.keys[i] + MEM_SLOTS) % MEM_SLOTS;
        slot_key[s] = inst.keys[i];
        slot_val[s] = inst.vals[i];
    }
    const q = inst.keys[inst.qpos];
    return slot_val[(q + MEM_SLOTS) % MEM_SLOTS];
}
pub const scan_disguised = Operator{ .name = "scan(disguised)", .parity = scanDisguisedParity, .recall = scanDisguisedRecall };

// ===========================================================================
// Scoring (the map axes) — produced ONLY by execution
// ===========================================================================

/// Per-position sign-accuracy on prefix-parity over random ±1 sequences.
pub fn parityAcc(op: Operator, L: usize, n_seq: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var x: [L_MAX]f64 = undefined;
    var out: [L_MAX]f64 = undefined;
    var correct: usize = 0;
    var total: usize = 0;
    for (0..n_seq) |_| {
        for (0..L) |i| x[i] = if (rng.boolean()) 1 else -1;
        op.parity(x[0..L], out[0..L]);
        var prod: f64 = 1;
        for (0..L) |i| {
            prod *= x[i];
            const truth: f64 = if (prod >= 0) 1 else -1;
            total += 1;
            if (out[i] == truth) correct += 1;
        }
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(total));
}

/// Exact-match accuracy on associative recall with K bindings.
pub fn recallAcc(op: Operator, k: usize, n_inst: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var correct: usize = 0;
    for (0..n_inst) |_| {
        const inst = RecallInst.gen(rng, k);
        const pred = @round(op.recall(&inst));
        if (pred == inst.answer()) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(n_inst));
}

// ===========================================================================
// Behavioural fingerprint + novelty certifier
// ===========================================================================

pub const FP_N: usize = 6;
pub const Fingerprint = [FP_N]f64;

/// A mechanism-revealing signature, all components in ~[0,1]:
///   [0] parity_short   — can it do parity at all (L=16)?
///   [1] parity_long    — does it length-generalise (L=256)?
///   [2] recall_small   — recall at K=4 (≤ memory capacity)
///   [3] recall_large   — recall at K=48 (≫ memory capacity = content addressing)
///   [4] x0_sensitivity — fraction of LATE outputs that flip when x[0] flips
///                        (unbounded accumulation/state ⇒ ~1; averaging ⇒ ~0)
///   [5] recent_only    — fraction of outputs equal to a width-2 local rule
///                        (locality signature; separates conv from scan/attn)
pub fn fingerprint(op: Operator, seed: u64) Fingerprint {
    var fp: Fingerprint = undefined;
    fp[0] = parityAcc(op, 16, 64, seed);
    fp[1] = parityAcc(op, 256, 16, seed +% 1);
    fp[2] = recallAcc(op, 4, 256, seed +% 2);
    fp[3] = recallAcc(op, 48, 256, seed +% 3);
    fp[4] = x0Sensitivity(op, seed +% 4);
    fp[5] = localAgreement(op, seed +% 5);
    return fp;
}

/// Flip x[0] on random parity sequences; measure the fraction of outputs in the
/// SECOND HALF that change. A running accumulator propagates the flip to every
/// later position (~1.0); a convex-average smears it out (~0).
fn x0Sensitivity(op: Operator, seed: u64) f64 {
    const L: usize = 64;
    const n: usize = 64;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var x: [L_MAX]f64 = undefined;
    var a: [L_MAX]f64 = undefined;
    var b: [L_MAX]f64 = undefined;
    var flips: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| x[i] = if (rng.boolean()) 1 else -1;
        op.parity(x[0..L], a[0..L]);
        x[0] = -x[0];
        op.parity(x[0..L], b[0..L]);
        for (L / 2..L) |i| {
            total += 1;
            if (a[i] != b[i]) flips += 1;
        }
    }
    return @as(f64, @floatFromInt(flips)) / @as(f64, @floatFromInt(total));
}

/// Fraction of outputs that match the width-2 local rule sign(x[i]·x[i-1]).
/// High for a conv/local mechanism, lower for full-prefix accumulation.
fn localAgreement(op: Operator, seed: u64) f64 {
    const L: usize = 32;
    const n: usize = 64;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var x: [L_MAX]f64 = undefined;
    var out: [L_MAX]f64 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| x[i] = if (rng.boolean()) 1 else -1;
        op.parity(x[0..L], out[0..L]);
        var prev: f64 = 1;
        for (0..L) |i| {
            const loc: f64 = if (x[i] * prev >= 0) 1 else -1;
            total += 1;
            if (out[i] == loc) agree += 1;
            prev = x[i];
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

pub fn fpDist(a: Fingerprint, b: Fingerprint) f64 {
    var s: f64 = 0;
    for (0..FP_N) |i| {
        const d = a[i] - b[i];
        s += d * d;
    }
    return std.math.sqrt(s);
}

pub const Anchor = struct { name: []const u8, fp: Fingerprint };

pub const Verdict = struct {
    nearest: []const u8,
    dist: f64,
    novel: bool,
};

/// Classify an operator against known anchors. `novel` iff it is far from EVERY
/// known mechanism's fingerprint (distance > threshold).
pub fn classify(fp: Fingerprint, anchors: []const Anchor, threshold: f64) Verdict {
    var best: usize = 0;
    var best_d: f64 = std.math.inf(f64);
    for (anchors, 0..) |an, i| {
        const d = fpDist(fp, an.fp);
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return .{ .nearest = anchors[best].name, .dist = best_d, .novel = best_d > threshold };
}

/// The standard anchor set: the three known mechanism families.
pub fn knownAnchors(seed: u64) [3]Anchor {
    return .{
        .{ .name = "attention", .fp = fingerprint(attention, seed) },
        .{ .name = "scan", .fp = fingerprint(scan, seed) },
        .{ .name = "local", .fp = fingerprint(local, seed) },
    };
}

/// Distance at which we call something genuinely outside the known clusters.
/// Calibrated below: known mechanisms sit ≥ ~0.8 apart; a disguised scan is
/// < ~0.1 from the scan anchor. 0.35 cleanly separates "same mechanism" from
/// "different mechanism".
pub const NOVELTY_THRESHOLD: f64 = 0.35;

// ===========================================================================
// Tests — the kill-tests for Phase 0 and Phase 1
// ===========================================================================

test "PHASE 0 kill-test: the two tasks place attention and scan at OPPOSITE corners" {
    const seed: u64 = 0xF00D;
    // scan: nails length-gen parity, fails large-K recall
    const scan_par = parityAcc(scan, 256, 32, seed);
    const scan_rec = recallAcc(scan, 32, 512, seed);
    try std.testing.expect(scan_par > 0.99); // length-generalises
    try std.testing.expect(scan_rec < 0.65); // can't content-address at K≫S

    // attention: nails recall, fails parity (≈ chance)
    const attn_par = parityAcc(attention, 256, 32, seed);
    const attn_rec = recallAcc(attention, 32, 512, seed);
    try std.testing.expect(attn_par < 0.65); // fixed-depth avg can't do parity
    try std.testing.expect(attn_rec > 0.99); // content-addressed lookup

    // opposite corners ⇒ the diagonal gap is large on BOTH axes
    try std.testing.expect(scan_par - attn_par > 0.3);
    try std.testing.expect(attn_rec - scan_rec > 0.3);
}

test "PHASE 0: recall degrades for the bounded scan as K grows past capacity" {
    const seed: u64 = 0x1234;
    const small = recallAcc(scan, MEM_SLOTS, 1024, seed); // K = S
    const large = recallAcc(scan, 48, 1024, seed); // K ≫ S
    try std.testing.expect(small > large); // collisions destroy bindings
    try std.testing.expect(large < 0.5); // collapses toward chance
}

test "PHASE 1 kill-test: a disguised scan certifies as NOT novel (close to the scan anchor)" {
    const seed: u64 = 0xBEEF;
    const anchors = knownAnchors(seed);

    // a re-implemented scan (different formula, identical behaviour)
    const fp_disg = fingerprint(scan_disguised, seed);
    const v = classify(fp_disg, &anchors, NOVELTY_THRESHOLD);
    try std.testing.expect(!v.novel); // must NOT be flagged as new
    try std.testing.expectEqualStrings("scan", v.nearest); // recognised as the scan mechanism

    // and the disguised scan is genuinely near the scan anchor, far from attention
    const d_scan = fpDist(fp_disg, fingerprint(scan, seed));
    const d_attn = fpDist(fp_disg, fingerprint(attention, seed));
    try std.testing.expect(d_scan < 0.1);
    try std.testing.expect(d_attn > 0.8);
}

test "PHASE 1: known mechanisms are mutually far apart (clusters are well separated)" {
    const seed: u64 = 0xABCD;
    const fa = fingerprint(attention, seed);
    const fs = fingerprint(scan, seed);
    const fl = fingerprint(local, seed);
    try std.testing.expect(fpDist(fa, fs) > NOVELTY_THRESHOLD);
    try std.testing.expect(fpDist(fa, fl) > NOVELTY_THRESHOLD);
    try std.testing.expect(fpDist(fs, fl) > NOVELTY_THRESHOLD);
}
