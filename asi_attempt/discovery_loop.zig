// Frontier 14 — Discovery Loop
//
// Does gradient discovery converge? Run the algorithm as a full loop:
//   1. Start with degree-1 threshold-bit features only
//   2. Train to convergence
//   3. If accuracy < target: compute shadow gradients for all candidate extensions
//   4. Add highest-|gradient| feature
//   5. RETRAIN FROM SCRATCH (not warm-start)
//   6. Repeat until solved or MAX_STEPS exhausted
//
// Tested on 8 predicates spanning: solvable, unsolvable (not in candidate pool),
// multi-step, and predicates that defeat the threshold-bit substrate entirely.
//
// Key open question: does the gradient stay informative at each step, or degrade?

const std = @import("std");
const math = std.math;

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 3200;
const NTRAIN: usize = NSAMP * 4 / 5; // 2560
const NTEST: usize = NSAMP - NTRAIN;  //  640
const LR: f64 = 0.05;
const NITERS: usize = 2500;
const MAX_FEAT: usize = 50;
const MAX_STEPS: usize = 8;
const TARGET_ACC: f64 = 0.97;

// Candidate pool: degree-1 (6) + degree-2 (15) + degree-3 (20) = 41
const NDEG1: usize = 6;
const NDEG2: usize = 15;
const NDEG3: usize = 20;
const NCANDS: usize = NDEG1 + NDEG2 + NDEG3; // 41

var g_cells: [NSAMP][NCELL]u8 = undefined;
var g_labels: [NSAMP]bool = undefined;
var g_all: [NSAMP][NCANDS]f64 = undefined; // all 41 candidates precomputed
var g_feat: [NSAMP][MAX_FEAT]f64 = undefined; // packed active features
var g_err: [NSAMP]f64 = undefined;

const FeatMeta = struct { deg: u8, i: u8, j: u8, l: u8 };
var g_meta: [NCANDS]FeatMeta = undefined;

fn lcg(s: *u64) u64 {
    s.* ^= s.* >> 12;
    s.* ^= s.* << 25;
    s.* ^= s.* >> 27;
    return s.* *% 0x2545F4914F6CDD1D;
}

fn sigmoid(x: f64) f64 { return 1.0 / (1.0 + @exp(-x)); }
fn bit(c: [NCELL]u8, i: usize) f64 { return if (c[i] >= THRESH) 1.0 else 0.0; }

fn initMeta() void {
    var k: usize = 0;
    for (0..NCELL) |i| { g_meta[k] = .{ .deg=1, .i=@intCast(i), .j=0, .l=0 }; k+=1; }
    for (0..NCELL) |i| for (i+1..NCELL) |j| {
        g_meta[k] = .{ .deg=2, .i=@intCast(i), .j=@intCast(j), .l=0 }; k+=1;
    };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| {
        g_meta[k] = .{ .deg=3, .i=@intCast(i), .j=@intCast(j), .l=@intCast(l) }; k+=1;
    };
}

fn precomputeAll(c: [NCELL]u8, f: *[NCANDS]f64) void {
    var k: usize = 0;
    for (0..NCELL) |i| { f[k] = bit(c,i); k+=1; }
    for (0..NCELL) |i| for (i+1..NCELL) |j| { f[k]=bit(c,i)*bit(c,j); k+=1; };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| {
        f[k]=bit(c,i)*bit(c,j)*bit(c,l); k+=1;
    };
}

fn pack(active: *const [NCANDS]bool) usize {
    var nf: usize = 0;
    for (0..NCANDS) |k| if (active[k]) {
        for (0..NSAMP) |i| g_feat[i][nf] = g_all[i][k];
        nf += 1;
    };
    return nf;
}

fn trainTest(nfeat: usize) f64 {
    var w = [_]f64{0.0} ** MAX_FEAT;
    var b: f64 = 0.0;
    for (0..NITERS) |_| {
        var dw = [_]f64{0.0} ** MAX_FEAT;
        var db: f64 = 0.0;
        for (0..NTRAIN) |i| {
            var logit = b;
            for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
            const e = sigmoid(logit) - if (g_labels[i]) @as(f64,1.0) else 0.0;
            for (0..nfeat) |j| dw[j] += e*g_feat[i][j];
            db += e;
        }
        const n: f64 = @floatFromInt(NTRAIN);
        for (0..nfeat) |j| w[j] -= LR*dw[j]/n;
        b -= LR*db/n;
    }
    for (0..NTRAIN) |i| {
        var logit = b;
        for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
        g_err[i] = sigmoid(logit) - if (g_labels[i]) @as(f64,1.0) else 0.0;
    }
    var ok: usize = 0;
    for (NTRAIN..NSAMP) |i| {
        var logit = b;
        for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
        if ((logit >= 0.0) == g_labels[i]) ok += 1;
    }
    const raw = @as(f64,@floatFromInt(ok)) / @as(f64,@floatFromInt(NTEST));
    return @max(raw, 1.0-raw);
}

fn featName(k: usize, buf: []u8) []u8 {
    const m = g_meta[k];
    return switch (m.deg) {
        1 => std.fmt.bufPrint(buf, "b[{d}]            ", .{m.i}) catch buf,
        2 => std.fmt.bufPrint(buf, "b[{d}]*b[{d}]        ", .{m.i,m.j}) catch buf,
        3 => std.fmt.bufPrint(buf, "b[{d}]*b[{d}]*b[{d}]    ", .{m.i,m.j,m.l}) catch buf,
        else => buf,
    };
}

fn runLoop(
    pred: *const fn([NCELL]u8) bool,
    name: []const u8,
    note: []const u8,
    w: anytype,
) !void {
    // regenerate fresh labels (same cells, different predicate)
    for (0..NSAMP) |i| g_labels[i] = pred(g_cells[i]);

    var active = [_]bool{false} ** NCANDS;
    for (0..NDEG1) |k| active[k] = true;

    try w.print("\n── {s}\n", .{name});
    try w.print("   {s}\n", .{note});

    var acc = trainTest(pack(&active));
    try w.print("   start  (6 feats) acc={d:.3}\n", .{acc});

    if (acc >= TARGET_ACC) { try w.print("   → SOLVED at start (predicate trivial for degree-1)\n", .{}); return; }

    var step: usize = 0;
    while (step < MAX_STEPS) : (step += 1) {
        // find best inactive candidate by shadow gradient
        var best_k: usize = 0;
        var best_g: f64 = 0;
        var second_g: f64 = 0;
        for (0..NCANDS) |k| if (!active[k]) {
            var g: f64 = 0;
            for (0..NTRAIN) |i| g += g_err[i]*g_all[i][k];
            g = @abs(g) / @as(f64,@floatFromInt(NTRAIN));
            if (g > best_g) { second_g=best_g; best_g=g; best_k=k; }
            else if (g > second_g) { second_g=g; }
        };

        active[best_k] = true;
        const new_nfeat = pack(&active);
        acc = trainTest(new_nfeat);

        var nbuf: [24]u8 = [_]u8{' '} ** 24;
        const nm = featName(best_k, &nbuf);
        const gap = if (second_g > 0) best_g/second_g else 0.0;
        try w.print("   step {d}: +{s}  acc={d:.3}  |g|={d:.4}  gap={d:.1}x\n",
            .{ step+1, nm[0..16], acc, best_g, gap });

        if (acc >= TARGET_ACC) {
            try w.print("   → SOLVED in {d} step(s)\n", .{step+1});
            return;
        }
    }
    try w.print("   → FAILED: acc={d:.3} after {d} steps\n", .{acc, MAX_STEPS});
}

// ─── predicates ───────────────────────────────────────────────────────────────
fn predK2(c: [NCELL]u8) bool {
    return ((if(c[0]>=THRESH) @as(u1,1) else 0)^(if(c[1]>=THRESH) @as(u1,1) else 0))==1;
}
fn predK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..3])|v| p^=if(v>=THRESH) @as(u1,1) else 0; return p==1;
}
fn predK4(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..4])|v| p^=if(v>=THRESH) @as(u1,1) else 0; return p==1;
}
fn predK3_rand(c: [NCELL]u8) bool {
    // XOR of bits at positions 1, 3, 5 — not the default 0,1,2
    const b1: u1 = if(c[1]>=THRESH) 1 else 0;
    const b3: u1 = if(c[3]>=THRESH) 1 else 0;
    const b5: u1 = if(c[5]>=THRESH) 1 else 0;
    return (b1^b3^b5)==1;
}
fn predK2_AND_K3(c: [NCELL]u8) bool {
    // (b[0] XOR b[1]) AND (b[2] XOR b[3] XOR b[4])
    const k2: bool = predK2(c);
    var p: u1=0; for(c[2..5])|v| p^=if(v>=THRESH) @as(u1,1) else 0;
    return k2 and (p==1);
}
fn predCountParity(c: [NCELL]u8) bool {
    var n: usize=0; for(c)|v| if(v>=THRESH){n+=1;}; return (n&1)==1;
}
fn predInvParity(c: [NCELL]u8) bool {
    var inv: usize=0;
    for(0..NCELL)|i| for(i+1..NCELL)|j| { if(c[i]>c[j]) inv+=1; };
    return (inv&1)==1;
}
fn predK2_XOR_K3(c: [NCELL]u8) bool {
    // (b[0] XOR b[1]) XOR (b[2] XOR b[3] XOR b[4])
    return predK2(c) != blk: {
        var p: u1=0; for(c[2..5])|v| p^=if(v>=THRESH) @as(u1,1) else 0; break :blk (p==1);
    };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    initMeta();

    // Generate shared cell arrays (same input distribution for all predicates)
    var rng: u64 = 0xD15C0BEE_FF00DCAF;
    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        precomputeAll(g_cells[i], &g_all[i]);
    }

    try stdout.print("DISCOVERY LOOP  NCELL={d}  VMAX={d}  NSAMP={d}  TARGET={d:.2}\n", .{NCELL, VMAX, NSAMP, TARGET_ACC});
    try stdout.print("Candidate pool: {d} threshold-bit features (deg-1:{d}  deg-2:{d}  deg-3:{d})\n", .{NCANDS, NDEG1, NDEG2, NDEG3});
    try stdout.print("Algorithm: train → shadow gradients → add best → retrain from scratch → repeat\n", .{});
    try stdout.print("Output: each step shows feature added, test accuracy, gradient magnitude, gap to next-best\n", .{});

    // ── solvable predicates ────────────────────────────────────────────────────
    try runLoop(predK2, "k2-parity  b[0]⊕b[1]",
        "needs degree-2: b[0]*b[1]. Pool has it. Expected: 1 step.", stdout);

    try runLoop(predK3, "k3-parity  b[0]⊕b[1]⊕b[2]",
        "needs degree-3: b[0]*b[1]*b[2]. Pool has it. Expected: 1 step.", stdout);

    try runLoop(predK3_rand, "k3-random  b[1]⊕b[3]⊕b[5]",
        "needs b[1]*b[3]*b[5]. Tests if gradient finds non-default positions.", stdout);

    try runLoop(predK2_AND_K3, "k2∧k3  (b[0]⊕b[1]) ∧ (b[2]⊕b[3]⊕b[4])",
        "needs b[0]*b[1] AND b[2]*b[3]*b[4]. Expected: 2 steps.", stdout);

    try runLoop(predK2_XOR_K3, "k2⊕k3  (b[0]⊕b[1]) ⊕ (b[2]⊕b[3]⊕b[4])",
        "XOR of two parity conditions. How many steps?", stdout);

    // ── predicates outside the candidate pool ─────────────────────────────────
    try runLoop(predK4, "k4-parity  b[0]⊕b[1]⊕b[2]⊕b[3]",
        "needs degree-4 monomial — NOT in pool. Expected: FAILED.", stdout);

    try runLoop(predCountParity, "count-parity  (Σb[i]) mod 2",
        "= 6-way XOR — needs degree-6. NOT in pool. Will gradient thrash?", stdout);

    try runLoop(predInvParity, "inv-parity  inv_count mod 2",
        "relational, not threshold-bit. No representation in pool. Expected: FAILED.", stdout);

    // ── summary ────────────────────────────────────────────────────────────────
    try stdout.print("\n{s}\n", .{"─"**70});
    try stdout.print("SUMMARY OF OPEN QUESTIONS:\n", .{});
    try stdout.print("  1. Does gradient converge in exactly ceil(k/3) steps for k-parity?\n", .{});
    try stdout.print("  2. For multi-condition predicates (k2∧k3), does it find both features\n", .{});
    try stdout.print("     in the right order, or does one condition dominate?\n", .{});
    try stdout.print("  3. For predicates outside the pool (k4, inv-parity), does the gradient\n", .{});
    try stdout.print("     degrade gracefully (add best approximation) or thrash (oscillate)?\n", .{});
    try stdout.print("  4. The 'gap' column (|grad_1st|/|grad_2nd|) measures signal clarity.\n", .{});
    try stdout.print("     Does gap decay as steps increase? If yes, the algorithm becomes\n", .{});
    try stdout.print("     unreliable for deep predicates.\n", .{});
}
