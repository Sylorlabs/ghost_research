//! FRONTIER 23 — Bit-state mechanism: the third corner of the recall↔parity plane
//!
//! The recall↔length-gen map has two known corners:
//!   scan:      perfect parity (O(1) float state), poor recall (4 slots → collides K>4)
//!   attention: perfect recall (content-addressed),  poor parity (≈ chance)
//!
//! Hypothesis: a bit-addressed state machine occupies a THIRD region.
//!
//! The argument:
//!   - Parity over ±1 tokens = running XOR of threshold bits (x[i]<0 → 1, else 0).
//!     A single bit tracks this exactly — O(1) state, correct at any length.
//!   - Recall of K key→value pairs (values 0..3, 2-bit) needs K×2 bits.
//!     With 256 bits of state: 128 key-slots with no collision when K < 128.
//!   - The float scan uses 4×f64 = 256 bits for 4 key-slots.
//!     At EQUAL total bits, the bit machine holds 32× more key-value pairs.
//!
//! Kill-tests:
//!   1. bit_parity: 100% at L=16, 100% at L=256 (exact, no float drift)
//!   2. bit_recall at K=4:  high (within 128-slot capacity)
//!   3. bit_recall at K=48: float scan collapses (<0.65); bit stays near 1.0
//!   4. behavioral fingerprint: bit-machine certifies as NOVEL vs {scan, attention, local}
//!
//! Run: zig build bit-state

const std = @import("std");

// ===========================================================================
// Recall task (from inv_frontier.zig pattern)
// ===========================================================================

pub const VAL_VOCAB: usize = 4;   // recall values 0..3
pub const MAX_K: usize = 128;     // max key→value pairs
pub const FLOAT_SLOTS: usize = 4; // bounded-scan capacity for the float reference

pub const RecallInst = struct {
    k: usize,
    keys: [MAX_K]u32 = undefined,
    vals: [MAX_K]f64 = undefined,
    qpos: usize = 0,

    pub fn gen(rng: std.Random, k: usize) RecallInst {
        var inst = RecallInst{ .k = k };
        for (0..k) |i| inst.keys[i] = @intCast(i + 1);
        rng.shuffle(u32, inst.keys[0..k]);
        for (0..k) |i| inst.vals[i] = @floatFromInt(rng.uintLessThan(usize, VAL_VOCAB));
        inst.qpos = rng.uintLessThan(usize, k);
        return inst;
    }
    pub fn answer(self: *const RecallInst) f64 { return self.vals[self.qpos]; }
};

// ===========================================================================
// Operator interface
// ===========================================================================

pub const Operator = struct {
    name: []const u8,
    parity: *const fn (x: []const f64, out: []f64) void,
    recall: *const fn (inst: *const RecallInst) f64,
};

// ===========================================================================
// Reference operators
// ===========================================================================

// ---- FLOAT SCAN (running product, 4-slot bounded recall) -------------------

fn scanParity(x: []const f64, out: []f64) void {
    var acc: f64 = 1;
    for (x, 0..) |xi, i| {
        acc *= xi;
        out[i] = if (acc >= 0) 1 else -1;
    }
}

fn scanRecall(inst: *const RecallInst) f64 {
    var slot_key = [_]u32{0} ** FLOAT_SLOTS;
    var slot_val = [_]f64{0} ** FLOAT_SLOTS;
    for (0..inst.k) |i| {
        const s = inst.keys[i] % FLOAT_SLOTS;
        slot_key[s] = inst.keys[i];
        slot_val[s] = inst.vals[i];
    }
    return slot_val[inst.keys[inst.qpos] % FLOAT_SLOTS];
}

pub const scan = Operator{ .name = "scan", .parity = scanParity, .recall = scanRecall };

// ---- ATTENTION (content-addressed, stateless) ------------------------------

fn attnParity(x: []const f64, out: []f64) void {
    var sum: f64 = 0;
    for (x, 0..) |xi, i| {
        sum += xi;
        out[i] = if (sum >= 0) 1 else -1;
    }
}

fn attnRecall(inst: *const RecallInst) f64 {
    const q = inst.keys[inst.qpos];
    for (0..inst.k) |i| if (inst.keys[i] == q) return inst.vals[i];
    return 0;
}

pub const attention = Operator{ .name = "attention", .parity = attnParity, .recall = attnRecall };

// ---- LOCAL (width-2 window) ------------------------------------------------

fn localParity(x: []const f64, out: []f64) void {
    var prev: f64 = 1;
    for (x, 0..) |xi, i| {
        out[i] = if (xi * prev >= 0) 1 else -1;
        prev = xi;
    }
}

fn localRecall(inst: *const RecallInst) f64 { return inst.vals[inst.k - 1]; }

pub const local = Operator{ .name = "local", .parity = localParity, .recall = localRecall };

// ===========================================================================
// Bit-state machine (256 bits = 4 × u64)
// ===========================================================================
//
// Layout: 128 key-slots, each 2 bits (stores values 0..3).
//   Key k occupies bits [(k%128)*2 .. (k%128)*2+1].
//   Word index = ((k%128)*2) / 64, bit offset = ((k%128)*2) % 64.
//
// Parity: running XOR of threshold bits lives in a separate single bit (no
//   collision with the recall state — conceptually distinct storage).

const BIT_SLOTS: usize = 128; // key capacity = 256 bits / 2 bits per slot

const BitState = struct {
    words: [4]u64 = [_]u64{0} ** 4,

    fn write(self: *BitState, key: u32, val: usize) void {
        const slot = key % BIT_SLOTS;
        const word_idx: u6 = @intCast((slot * 2) / 64);
        const bit_off:  u6 = @intCast((slot * 2) % 64);
        const mask: u64 = ~(@as(u64, 3) << bit_off);
        self.words[word_idx] = (self.words[word_idx] & mask) | (@as(u64, val & 3) << bit_off);
    }

    fn read(self: *const BitState, key: u32) usize {
        const slot = key % BIT_SLOTS;
        const word_idx: u6 = @intCast((slot * 2) / 64);
        const bit_off:  u6 = @intCast((slot * 2) % 64);
        return @intCast((self.words[word_idx] >> bit_off) & 3);
    }
};

fn bitMachineParity(x: []const f64, out: []f64) void {
    var acc: u1 = 0;
    for (x, 0..) |xi, i| {
        if (xi < 0) acc ^= 1;
        out[i] = if (acc == 0) 1.0 else -1.0;
    }
}

fn bitMachineRecall(inst: *const RecallInst) f64 {
    var s = BitState{};
    for (0..inst.k) |i| s.write(inst.keys[i], @intFromFloat(inst.vals[i]));
    return @floatFromInt(s.read(inst.keys[inst.qpos]));
}

pub const bit_machine = Operator{
    .name = "bit-machine",
    .parity = bitMachineParity,
    .recall = bitMachineRecall,
};

// ===========================================================================
// Scoring functions
// ===========================================================================

const L_MAX: usize = 512;

pub fn parityAcc(op: Operator, L: usize, n_seq: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var x:   [L_MAX]f64 = undefined;
    var out: [L_MAX]f64 = undefined;
    var correct: usize = 0;
    var total:   usize = 0;
    for (0..n_seq) |_| {
        for (0..L) |i| x[i] = if (rng.boolean()) 1 else -1;
        op.parity(x[0..L], out[0..L]);
        var prod: f64 = 1;
        for (0..L) |i| {
            prod *= x[i];
            if (out[i] == (if (prod >= 0) @as(f64, 1) else @as(f64, -1))) correct += 1;
            total += 1;
        }
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(total));
}

pub fn recallAcc(op: Operator, k: usize, n_inst: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var correct: usize = 0;
    for (0..n_inst) |_| {
        const inst = RecallInst.gen(rng, k);
        if (@round(op.recall(&inst)) == inst.answer()) correct += 1;
    }
    return @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(n_inst));
}

// ===========================================================================
// Behavioral fingerprint + novelty certifier
// ===========================================================================

pub const FP_N: usize = 6;
pub const Fingerprint = [FP_N]f64;
pub const NOVELTY_THRESHOLD: f64 = 0.35;

/// [parity_short, parity_long, recall_small, recall_large, x0_sensitivity, local_agree]
pub fn fingerprint(op: Operator, seed: u64) Fingerprint {
    var fp: Fingerprint = undefined;
    fp[0] = parityAcc(op, 16,  64,  seed);
    fp[1] = parityAcc(op, 256, 16,  seed +% 1);
    fp[2] = recallAcc(op, 4,   256, seed +% 2);
    fp[3] = recallAcc(op, 48,  256, seed +% 3);
    fp[4] = x0Sensitivity(op, seed +% 4);
    fp[5] = localAgreement(op, seed +% 5);
    return fp;
}

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

fn localAgreement(op: Operator, seed: u64) f64 {
    const L: usize = 32;
    const n: usize = 64;
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var x:   [L_MAX]f64 = undefined;
    var out: [L_MAX]f64 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| x[i] = if (rng.boolean()) 1 else -1;
        op.parity(x[0..L], out[0..L]);
        var prev: f64 = 1;
        for (0..L) |i| {
            const loc: f64 = if (x[i] * prev >= 0) 1 else -1;
            if (out[i] == loc) agree += 1;
            total += 1;
            prev = x[i];
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

pub fn fpDist(a: Fingerprint, b: Fingerprint) f64 {
    var s: f64 = 0;
    for (0..FP_N) |i| { const d = a[i] - b[i]; s += d * d; }
    return std.math.sqrt(s);
}

pub const Anchor = struct { name: []const u8, fp: Fingerprint };

pub const Verdict = struct { nearest: []const u8, dist: f64, novel: bool };

pub fn classify(fp: Fingerprint, anchors: []const Anchor, threshold: f64) Verdict {
    var best: usize = 0;
    var best_d: f64 = std.math.inf(f64);
    for (anchors, 0..) |an, i| {
        const d = fpDist(fp, an.fp);
        if (d < best_d) { best_d = d; best = i; }
    }
    return .{ .nearest = anchors[best].name, .dist = best_d, .novel = best_d > threshold };
}

pub fn knownAnchors(seed: u64) [3]Anchor {
    return .{
        .{ .name = "attention",  .fp = fingerprint(attention, seed) },
        .{ .name = "scan",       .fp = fingerprint(scan,      seed) },
        .{ .name = "local",      .fp = fingerprint(local,     seed) },
    };
}

// ===========================================================================
// Main report
// ===========================================================================

pub fn main() !void {
    const seed: u64 = 0xF23_F00D;
    const out = std.io.getStdOut().writer();

    try out.print("=== FRONTIER 23: Bit-state mechanism — the third corner ===\n\n", .{});
    try out.print("Equal-memory comparison (both use 256 bits of state):\n", .{});
    try out.print("  float-scan  : 4 × f64 = 256 bits →  4 key-slots (2-bit value capacity)\n", .{});
    try out.print("  bit-machine : 4 × u64 = 256 bits → 128 key-slots (2-bit value per slot)\n\n", .{});

    const mechs = [_]Operator{ scan, attention, local, bit_machine };

    // --- Parity accuracy table -----------------------------------------------
    try out.print("--- PARITY (prefix-parity accuracy) ---\n", .{});
    try out.print("  mechanism    | L=16   | L=64   | L=256\n", .{});
    try out.print("  -------------|--------|--------|------\n", .{});
    for (mechs) |m| {
        const p16  = parityAcc(m, 16,  128, seed);
        const p64  = parityAcc(m, 64,  64,  seed +% 1);
        const p256 = parityAcc(m, 256, 32,  seed +% 2);
        try out.print("  {s:<13}| {d:.4} | {d:.4} | {d:.4}\n", .{ m.name, p16, p64, p256 });
    }

    // --- Recall accuracy table -----------------------------------------------
    try out.print("\n--- RECALL accuracy vs K (# key-value pairs) ---\n", .{});
    try out.print("  mechanism    | K=4    | K=8    | K=16   | K=48   | K=100\n", .{});
    try out.print("  -------------|--------|--------|--------|--------|------\n", .{});
    for (mechs) |m| {
        const r4   = recallAcc(m, 4,   512, seed);
        const r8   = recallAcc(m, 8,   512, seed +% 1);
        const r16  = recallAcc(m, 16,  512, seed +% 2);
        const r48  = recallAcc(m, 48,  512, seed +% 3);
        const r100 = recallAcc(m, 100, 256, seed +% 4);
        try out.print("  {s:<13}| {d:.4} | {d:.4} | {d:.4} | {d:.4} | {d:.4}\n",
            .{ m.name, r4, r8, r16, r48, r100 });
    }

    // --- Behavioral fingerprints ---------------------------------------------
    try out.print("\n--- BEHAVIORAL FINGERPRINTS ---\n", .{});
    try out.print("  [par16, par256, rec4, rec48, x0_sens, local_agree]\n\n", .{});
    const anchors = knownAnchors(seed);
    for (mechs) |m| {
        const fp = fingerprint(m, seed);
        const v  = classify(fp, &anchors, NOVELTY_THRESHOLD);
        try out.print("  {s:<13}: [{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3}]\n",
            .{ m.name, fp[0], fp[1], fp[2], fp[3], fp[4], fp[5] });
        try out.print("    nearest={s}  dist={d:.3}  novel={}\n\n",
            .{ v.nearest, v.dist, v.novel });
    }

    // --- Parity-plane summary ------------------------------------------------
    try out.print("--- RECALL↔PARITY PLANE ---\n", .{});
    try out.print("  mechanism    | parity_long | recall_K48 | region\n", .{});
    try out.print("  -------------|-------------|------------|-------\n", .{});
    for (mechs) |m| {
        const pl = parityAcc(m, 256, 32, seed);
        const rl = recallAcc(m, 48,  256, seed);
        const region: []const u8 =
            if (pl > 0.95 and rl > 0.95) "TOP-RIGHT  ← third corner"
            else if (pl > 0.95)           "left  (parity-only)"
            else if (rl > 0.95)           "right (recall-only)"
            else                          "bottom";
        try out.print("  {s:<13}| {d:.4}       | {d:.4}     | {s}\n",
            .{ m.name, pl, rl, region });
    }

    // --- Verdict -------------------------------------------------------------
    const bm_pl = parityAcc(bit_machine, 256, 32, seed);
    const bm_rl = recallAcc(bit_machine, 48, 256, seed);
    const bm_fp = fingerprint(bit_machine, seed);
    const bm_v  = classify(bm_fp, &anchors, NOVELTY_THRESHOLD);
    try out.print("\n=== VERDICT ===\n", .{});
    if (bm_pl > 0.99 and bm_rl > 0.95 and bm_v.novel) {
        try out.print("CONFIRMED: bit-machine is the third corner.\n", .{});
        try out.print("  parity_long = {d:.4}  (need > 0.99)\n", .{bm_pl});
        try out.print("  recall_K48  = {d:.4}  (need > 0.95)\n", .{bm_rl});
        try out.print("  fingerprint novel = true (dist={d:.3} from nearest '{s}')\n\n",
            .{ bm_v.dist, bm_v.nearest });
        try out.print("  Mechanism: XOR bit accumulator (parity) + 128-slot bit-indexed\n", .{});
        try out.print("  key-value map (recall). Equal 256-bit state budget as float-scan;\n", .{});
        try out.print("  32x more key capacity because bit addressing beats float addressing.\n", .{});
    } else {
        try out.print("REFUTED or PARTIAL:\n", .{});
        try out.print("  parity_long={d:.4}  recall_K48={d:.4}  novel={}\n",
            .{ bm_pl, bm_rl, bm_v.novel });
    }
}

// ===========================================================================
// Kill-tests
// ===========================================================================

test "F23-1: bit-machine parity is exact at any length (no float drift)" {
    try std.testing.expect(parityAcc(bit_machine, 16,  64, 0xF23_0001) > 0.999);
    try std.testing.expect(parityAcc(bit_machine, 256, 16, 0xF23_0002) > 0.999);
}

test "F23-2: bit-machine recall is near-perfect within 128-slot capacity" {
    try std.testing.expect(recallAcc(bit_machine, 4,  1024, 0xF23_0010) > 0.99);
    try std.testing.expect(recallAcc(bit_machine, 48, 1024, 0xF23_0011) > 0.95);
}

test "F23-3: float-scan collapses at K=48; bit-machine does not" {
    const scan_r48 = recallAcc(scan,        48, 1024, 0xF23_0020);
    const bit_r48  = recallAcc(bit_machine, 48, 1024, 0xF23_0020);
    try std.testing.expect(scan_r48 < 0.65);
    try std.testing.expect(bit_r48  > 0.95);
    try std.testing.expect(bit_r48 - scan_r48 > 0.30);
}

test "F23-4: bit-machine certifies as NOVEL vs known anchors" {
    const anchors = knownAnchors(0xF23_0030);
    const fp = fingerprint(bit_machine, 0xF23_0030);
    const v  = classify(fp, &anchors, NOVELTY_THRESHOLD);
    try std.testing.expect(v.novel);
}

test "F23-5: third-corner — bit-machine has parity_long AND recall_K48 both > 0.95" {
    const pl = parityAcc(bit_machine, 256, 32, 0xF23_0040);
    const rl = recallAcc(bit_machine, 48,  256, 0xF23_0041);
    try std.testing.expect(pl > 0.99);
    try std.testing.expect(rl > 0.95);
    // verify scan and attention do NOT both exceed 0.95 simultaneously
    try std.testing.expect(!(parityAcc(scan,      256, 32, 0xF23_0040) > 0.95 and recallAcc(scan,      48, 256, 0xF23_0041) > 0.95));
    try std.testing.expect(!(parityAcc(attention, 256, 32, 0xF23_0040) > 0.95 and recallAcc(attention, 48, 256, 0xF23_0041) > 0.95));
}

test "F23-kill: PHASE 0 from inv_frontier — scan and attention at opposite corners" {
    const seed: u64 = 0xF00D;
    try std.testing.expect(parityAcc(scan,      256, 32, seed) > 0.99);
    try std.testing.expect(recallAcc(scan,      32,  512, seed) < 0.65);
    try std.testing.expect(parityAcc(attention, 256, 32, seed) < 0.65);
    try std.testing.expect(recallAcc(attention, 32,  512, seed) > 0.99);
}
