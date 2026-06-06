// Frontier 15 — Two-Phase Discovery
//
// F14 showed: gradient correctly finds the right features BUT accuracy plateaus
// because irrelevant degree-1 features (noise) slow down convergence.
//
// Fix — two-phase algorithm:
//   Phase 1 (DISCOVER): run gradient loop, stop when gap < GAP_STOP
//     → collects the set of needed features
//   Phase 2 (SOLVE):    retrain from scratch on discovered features ONLY
//     → no irrelevant degree-1 noise, more iterations, lower LR
//
// Part A: test on known predicates (k2, k3, k3-random, k2∧k3, k4-parity)
// Part B: benchmark on 20 randomly generated unknown predicates
//         — the real test: is gradient discovery a general algorithm?

const std = @import("std");
const math = std.math;

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 3200;
const NTRAIN: usize = NSAMP * 4 / 5;
const NTEST: usize = NSAMP - NTRAIN;

const LR_P1: f64 = 0.05;
const LR_P2: f64 = 0.015;
const NITERS_P1: usize = 2000;
const NITERS_P2: usize = 6000;
const MAX_FEAT: usize = 60;
const MAX_DISC: usize = 20; // max features discovered in phase 1
const GAP_STOP: f64 = 1.5;
const TARGET: f64 = 0.97;

// Candidate pool: deg-1 (6) + deg-2 (15) + deg-3 (20) = 41
const NDEG1: usize = 6;
const NDEG2: usize = 15;
const NDEG3: usize = 20;
const NCANDS: usize = NDEG1 + NDEG2 + NDEG3;

var g_cells: [NSAMP][NCELL]u8 = undefined;
var g_labels: [NSAMP]bool = undefined;
var g_all: [NSAMP][NCANDS]f64 = undefined;
var g_feat: [NSAMP][MAX_FEAT]f64 = undefined;
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
    for (0..NCELL) |i| { g_meta[k] = .{ .deg=1,.i=@intCast(i),.j=0,.l=0 }; k+=1; }
    for (0..NCELL) |i| for (i+1..NCELL) |j| {
        g_meta[k] = .{ .deg=2,.i=@intCast(i),.j=@intCast(j),.l=0 }; k+=1;
    };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| {
        g_meta[k] = .{ .deg=3,.i=@intCast(i),.j=@intCast(j),.l=@intCast(l) }; k+=1;
    };
}

fn precomputeAll(c: [NCELL]u8, f: *[NCANDS]f64) void {
    var k: usize = 0;
    for (0..NCELL) |i| { f[k]=bit(c,i); k+=1; }
    for (0..NCELL) |i| for (i+1..NCELL) |j| { f[k]=bit(c,i)*bit(c,j); k+=1; };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| {
        f[k]=bit(c,i)*bit(c,j)*bit(c,l); k+=1;
    };
}

// Pack features into g_feat by index list, return count
fn packByList(idxs: []const usize) usize {
    for (idxs, 0..) |k, f| {
        for (0..NSAMP) |i| g_feat[i][f] = g_all[i][k];
    }
    return idxs.len;
}

fn trainTestLR(nfeat: usize, niters: usize, lr: f64) f64 {
    var w = [_]f64{0.0} ** MAX_FEAT;
    var b: f64 = 0.0;
    for (0..niters) |_| {
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
        for (0..nfeat) |j| w[j] -= lr*dw[j]/n;
        b -= lr*db/n;
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
    const raw = @as(f64,@floatFromInt(ok))/@as(f64,@floatFromInt(NTEST));
    return @max(raw, 1.0-raw);
}

// Find best inactive candidate: returns (index, |gradient|, gap_ratio)
fn bestCandidate(active: *const [NCANDS]bool) struct { k: usize, g: f64, gap: f64 } {
    var best_k: usize = 0;
    var best_g: f64 = 0;
    var second_g: f64 = 0;
    for (0..NCANDS) |k| if (!active[k]) {
        var g: f64 = 0;
        for (0..NTRAIN) |i| g += g_err[i]*g_all[i][k];
        g = @abs(g)/@as(f64,@floatFromInt(NTRAIN));
        if (g > best_g) { second_g=best_g; best_g=g; best_k=k; }
        else if (g > second_g) second_g=g;
    };
    const gap = if (second_g > 1e-10) best_g/second_g else 0.0;
    return .{ .k=best_k, .g=best_g, .gap=gap };
}

// Extract which bit positions appear in discovered features (for phase 2)
fn relevantBitMask(discovered: []const usize) u8 {
    var mask: u8 = 0;
    for (discovered) |k| {
        const m = g_meta[k];
        mask |= @as(u8, 1) << @as(u3, @intCast(m.i));
        if (m.deg >= 2) mask |= @as(u8, 1) << @as(u3, @intCast(m.j));
        if (m.deg >= 3) mask |= @as(u8, 1) << @as(u3, @intCast(m.l));
    }
    return mask;
}

const DiscoveryResult = struct {
    acc_p1_final: f64,   // accuracy at end of phase 1
    acc_p2: f64,         // accuracy after phase 2 clean retrain
    steps_p1: usize,     // features added in phase 1
    stopped_by_gap: bool,// true = gap criterion triggered; false = hit max steps
    final_gap: f64,
};

fn twoPhaseDiscovery(rng: *u64, pred: *const fn([NCELL]u8) bool) DiscoveryResult {
    // Regenerate labels
    for (0..NSAMP) |i| g_labels[i] = pred(g_cells[i]);

    // Phase 1: gradient discovery with gap stopping
    var active = [_]bool{false} ** NCANDS;
    for (0..NDEG1) |k| active[k] = true;

    var discovered_buf: [MAX_DISC]usize = undefined;
    var n_disc: usize = 0;

    // Initial train
    var deg1_list: [NDEG1]usize = undefined;
    for (0..NDEG1) |k| deg1_list[k] = k;
    var acc = trainTestLR(packByList(&deg1_list), NITERS_P1, LR_P1);

    var last_gap: f64 = 99.0;
    var steps: usize = 0;
    while (steps < MAX_DISC) {
        const best = bestCandidate(&active);
        last_gap = best.gap;

        if (best.gap < GAP_STOP or best.g < 0.005) break; // signal gone dark

        active[best.k] = true;
        if (n_disc < MAX_DISC) {
            discovered_buf[n_disc] = best.k;
            n_disc += 1;
        }
        steps += 1;

        // Rebuild active list and retrain from scratch
        var active_list: [MAX_FEAT]usize = undefined;
        var nactive: usize = 0;
        for (0..NCANDS) |k| if (active[k]) { active_list[nactive]=k; nactive+=1; };
        acc = trainTestLR(packByList(active_list[0..nactive]), NITERS_P1, LR_P1);
    }

    const acc_p1 = acc;
    const stopped_by_gap = last_gap < GAP_STOP or steps == 0;

    // Phase 2: clean retrain on discovered features + only RELEVANT degree-1 bits
    const disc_slice = discovered_buf[0..n_disc];
    const rel_mask = relevantBitMask(disc_slice);

    var phase2_list: [MAX_FEAT]usize = undefined;
    var np2: usize = 0;
    // Add relevant degree-1 features only
    for (0..NDEG1) |k| {
        const bit_pos: u8 = @as(u8, 1) << @as(u3, @intCast(k));
        if (rel_mask & bit_pos != 0) { phase2_list[np2]=k; np2+=1; }
    }
    // Add all discovered features
    for (disc_slice) |k| { phase2_list[np2]=k; np2+=1; }

    const acc_p2 = if (np2 > 0)
        trainTestLR(packByList(phase2_list[0..np2]), NITERS_P2, LR_P2)
    else acc_p1;

    _ = rng;
    return .{
        .acc_p1_final = acc_p1,
        .acc_p2 = acc_p2,
        .steps_p1 = steps,
        .stopped_by_gap = stopped_by_gap,
        .final_gap = last_gap,
    };
}

// ─── predicates ───────────────────────────────────────────────────────────────
fn predK2(c: [NCELL]u8) bool {
    return ((if(c[0]>=THRESH)@as(u1,1)else 0)^(if(c[1]>=THRESH)@as(u1,1)else 0))==1;
}
fn predK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..3])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}
fn predK3r(c: [NCELL]u8) bool {
    const b1: u1=if(c[1]>=THRESH)1 else 0;
    const b3: u1=if(c[3]>=THRESH)1 else 0;
    const b5: u1=if(c[5]>=THRESH)1 else 0;
    return (b1^b3^b5)==1;
}
fn predK2AndK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[2..5])|v| p^=if(v>=THRESH)@as(u1,1)else 0;
    return predK2(c) and (p==1);
}
fn predK4(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..4])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}

// Random predicate generator — produces a degree-2 or degree-3 threshold-bit predicate
// at random positions, unknown to the algorithm
fn makeRandomPred(rng: *u64, pred_type: u8,
                  pos: *[4]u8) *const fn([NCELL]u8) bool {
    _ = rng;
    _ = pred_type;
    _ = pos;
    // This is handled inline in the benchmark; function pointer approach is complex.
    // See benchmarkUnknown below.
    unreachable;
}

// Evaluate a threshold-bit predicate defined by type+positions
fn evalPred(c: [NCELL]u8, kind: u8, p: [4]u8) bool {
    return switch (kind) {
        0 => ((if(c[p[0]]>=THRESH)@as(u1,1)else 0)^(if(c[p[1]]>=THRESH)@as(u1,1)else 0))==1, // k2-parity
        1 => blk: { // k3-parity at random positions
            var x: u1=0;
            x^=if(c[p[0]]>=THRESH)@as(u1,1)else 0;
            x^=if(c[p[1]]>=THRESH)@as(u1,1)else 0;
            x^=if(c[p[2]]>=THRESH)@as(u1,1)else 0;
            break :blk x==1;
        },
        2 => ((if(c[p[0]]>=THRESH)@as(u1,1)else 0)&(if(c[p[1]]>=THRESH)@as(u1,1)else 0))==1, // 2-AND
        3 => blk: { // 3-AND
            const b0: u1=if(c[p[0]]>=THRESH)1 else 0;
            const b1: u1=if(c[p[1]]>=THRESH)1 else 0;
            const b2: u1=if(c[p[2]]>=THRESH)1 else 0;
            break :blk (b0&b1&b2)==1;
        },
        else => false,
    };
}

fn kindName(kind: u8) []const u8 {
    return switch (kind) {
        0 => "k2-XOR",
        1 => "k3-XOR",
        2 => "2-AND ",
        3 => "3-AND ",
        else => "?????",
    };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    initMeta();
    var rng: u64 = 0xF15F00DC0FFEE_BEE;

    // Generate shared cell arrays
    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        precomputeAll(g_cells[i], &g_all[i]);
    }

    try stdout.print("TWO-PHASE GRADIENT DISCOVERY  NCELL={d}  NSAMP={d}\n", .{NCELL, NSAMP});
    try stdout.print("Phase 1: discover features (stop when gap < {d:.1})\n", .{GAP_STOP});
    try stdout.print("Phase 2: retrain from scratch on discovered + relevant deg-1 ONLY\n\n", .{});

    // ── Part A: known predicates ───────────────────────────────────────────────
    try stdout.print("PART A — known predicates\n", .{});
    try stdout.print("{s:<24} p1_acc  p2_acc  steps  gap    verdict\n", .{"predicate"});
    try stdout.print("{s}\n", .{"─"**72});

    const KnownPred = struct {
        name: []const u8,
        fn_: *const fn([NCELL]u8) bool,
        expected: []const u8,
    };
    const known = [_]KnownPred{
        .{ .name="k2-parity b[0]⊕h[1]",    .fn_=predK2,       .expected="1 step → 1.000" },
        .{ .name="k3-parity h[0]⊕h[1]⊕h[2]",.fn_=predK3,      .expected="plateau fix"   },
        .{ .name="k3-random h[1]⊕h[3]⊕h[5]",.fn_=predK3r,     .expected="plateau fix"   },
        .{ .name="k2∧k3",                    .fn_=predK2AndK3,  .expected="2-step fix"    },
        .{ .name="k4-parity (out of pool)",  .fn_=predK4,       .expected="FAIL"          },
    };

    for (known) |kp| {
        const r = twoPhaseDiscovery(&rng, kp.fn_);
        const verdict: []const u8 = if (r.acc_p2 >= TARGET) "SOLVED"
                                    else if (r.acc_p1_final >= TARGET) "P1-ok "
                                    else "FAILED";
        try stdout.print("{s:<24} {d:.3}   {d:.3}   {d:2}     {d:.2}   {s}  [{s}]\n",
            .{ kp.name, r.acc_p1_final, r.acc_p2, r.steps_p1,
               r.final_gap, verdict, kp.expected });
    }

    // ── Part B: unknown random predicates ─────────────────────────────────────
    try stdout.print("\nPART B — 20 unknown random predicates\n", .{});
    try stdout.print("(positions chosen randomly; algorithm has no knowledge of predicate type)\n\n", .{});
    try stdout.print("{s:<8} {s:<18} p1_acc  p2_acc  steps  verdict\n", .{"#", "type+positions"});
    try stdout.print("{s}\n", .{"─"**60});

    var solved: usize = 0;
    var total: usize = 0;
    var total_steps: usize = 0;

    for (0..20) |trial| {
        // Random predicate
        const kind: u8 = @intCast(lcg(&rng) % 4);
        var pos: [4]u8 = .{0,0,0,0};

        // Choose distinct random positions
        var used: u8 = 0;
        for (0..4) |pi| {
            var p: u8 = @intCast(lcg(&rng) % NCELL);
            while (used & (@as(u8,1)<<@as(u3,@intCast(p))) != 0) {
                p = @intCast(lcg(&rng) % NCELL);
            }
            pos[pi] = p;
            used |= @as(u8,1) << @as(u3, @intCast(p));
        }

        // Generate labels
        for (0..NSAMP) |i| g_labels[i] = evalPred(g_cells[i], kind, pos);

        // Check class balance — skip if too imbalanced
        var npos: usize = 0;
        for (0..NSAMP) |i| if (g_labels[i]) { npos += 1; };
        const pos_frac = @as(f64, @floatFromInt(npos)) / @as(f64, @floatFromInt(NSAMP));
        if (pos_frac < 0.05 or pos_frac > 0.95) {
            try stdout.print("{d:2}     {s} p[{d},{d}({d},{d})]  skipped (imbalanced {d:.0}%)\n",
                .{trial+1, kindName(kind), pos[0],pos[1],pos[2],pos[3], pos_frac*100.0});
            continue;
        }

        // Run two-phase discovery (labels already set, don't regenerate)
        // We need a pred function — inline approach using a closure-like trick
        // Since Zig doesn't have closures, pack the predicate inline:
        var active = [_]bool{false} ** NCANDS;
        for (0..NDEG1) |k| active[k] = true;

        var discovered_buf: [MAX_DISC]usize = undefined;
        var n_disc: usize = 0;

        var deg1_list: [NDEG1]usize = undefined;
        for (0..NDEG1) |k| deg1_list[k] = k;
        var acc = trainTestLR(packByList(&deg1_list), NITERS_P1, LR_P1);

        var last_gap: f64 = 99.0;
        var steps: usize = 0;
        while (steps < MAX_DISC) {
            const best = bestCandidate(&active);
            last_gap = best.gap;
            if (best.gap < GAP_STOP or best.g < 0.005) break;
            active[best.k] = true;
            if (n_disc < MAX_DISC) { discovered_buf[n_disc]=best.k; n_disc+=1; }
            steps += 1;
            var al: [MAX_FEAT]usize = undefined;
            var na: usize = 0;
            for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
            acc = trainTestLR(packByList(al[0..na]), NITERS_P1, LR_P1);
        }
        const acc_p1 = acc;

        // Phase 2
        const disc_sl = discovered_buf[0..n_disc];
        const rel_mask = relevantBitMask(disc_sl);
        var p2_list: [MAX_FEAT]usize = undefined;
        var np2: usize = 0;
        for (0..NDEG1) |k| {
            if (rel_mask & (@as(u8,1)<<@as(u3,@intCast(k))) != 0) { p2_list[np2]=k; np2+=1; }
        }
        for (disc_sl) |k| { p2_list[np2]=k; np2+=1; }
        const acc_p2 = if (np2>0) trainTestLR(packByList(p2_list[0..np2]), NITERS_P2, LR_P2) else acc_p1;

        const verdict: []const u8 = if (acc_p2 >= TARGET) "SOLVED" else if (acc_p1 >= TARGET) "P1-ok" else "FAILED";
        if (acc_p2 >= TARGET) solved += 1;
        total += 1;
        total_steps += steps;

        try stdout.print("{d:2}     {s} [{d},{d},{d},{d}]  {d:.3}   {d:.3}   {d:2}     {s}\n",
            .{ trial+1, kindName(kind), pos[0],pos[1],pos[2],pos[3],
               acc_p1, acc_p2, steps, verdict });
    }

    try stdout.print("\n{s}\n", .{"─"**60});
    try stdout.print("Part B summary: {d}/{d} solved  avg_steps={d:.1}\n",
        .{ solved, total, @as(f64,@floatFromInt(total_steps))/@as(f64,@floatFromInt(@max(total,1))) });
    try stdout.print("\nKey: p1_acc=end-of-phase-1 accuracy  p2_acc=after-clean-retrain\n", .{});
    try stdout.print("     Gap stopping: < {d:.1} = signal gone, stop discovery\n", .{GAP_STOP});
    try stdout.print("     Phase 2 uses only relevant degree-1 bits + discovered features\n", .{});
}
