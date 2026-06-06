// Frontier 17 — Adaptive Retrain
//
// F16 confirmed: the dual-stop discovery finds the correct 4 features for k3-parity
// (b[0]*b[1]*b[2], b[0]*b[1], b[0]*b[2], b[1]*b[2]). But logistic regression
// plateaus at 0.877 regardless.
//
// Root cause: the exact polynomial representation of k3-parity requires coefficient
// ratios of 4:-2:-2:-2 (degree-3 vs degree-2 terms). Batch gradient descent with
// fixed LR drives these toward the right direction but converges slowly when the
// features are correlated binary values.
//
// Fix: adaptive retrain with LR halving. When loss stops decreasing for N steps,
// halve the learning rate. Repeat until LR drops below min or converged.
// Also test: very long fixed training at very low LR as a control.

const std = @import("std");

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 3200;
const NTRAIN: usize = NSAMP * 4 / 5;
const NTEST: usize = NSAMP - NTRAIN;

const MAX_FEAT: usize = 16;
const NDEG1: usize = 6;
const NDEG2: usize = 15;
const NDEG3: usize = 20;
const NCANDS: usize = NDEG1 + NDEG2 + NDEG3;

const GAP_STOP: f64 = 1.5;
const GRAD_MIN: f64 = 0.008;
const TARGET: f64 = 0.97;

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

fn packByList(idxs: []const usize) usize {
    for (idxs, 0..) |k, f| {
        for (0..NSAMP) |i| g_feat[i][f] = g_all[i][k];
    }
    return idxs.len;
}

// Compute cross-entropy loss + accuracy with current weights
fn evalModel(nfeat: usize, w: []const f64, b: f64) struct { loss: f64, acc: f64 } {
    var loss: f64 = 0;
    var ok: usize = 0;
    for (0..NTRAIN) |i| {
        var logit = b;
        for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
        const p = sigmoid(logit);
        const y: f64 = if (g_labels[i]) 1.0 else 0.0;
        loss += -(y*@log(p+1e-15) + (1.0-y)*@log(1.0-p+1e-15));
    }
    for (NTRAIN..NSAMP) |i| {
        var logit = b;
        for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
        if ((logit >= 0.0) == g_labels[i]) ok += 1;
    }
    const raw = @as(f64,@floatFromInt(ok))/@as(f64,@floatFromInt(NTEST));
    return .{
        .loss = loss / @as(f64, @floatFromInt(NTRAIN)),
        .acc = @max(raw, 1.0-raw),
    };
}

// Fixed LR training, returns final accuracy
fn trainFixed(nfeat: usize, niters: usize, lr: f64) f64 {
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
    return evalModel(nfeat, &w, b).acc;
}

// Adaptive LR training: halve LR when loss stops improving
fn trainAdaptive(nfeat: usize, max_steps: usize, lr_init: f64, lr_min: f64,
                 patience: usize) f64 {
    var w = [_]f64{0.0} ** MAX_FEAT;
    var b: f64 = 0.0;
    var lr = lr_init;
    var best_loss: f64 = 1e18;
    var no_improve: usize = 0;
    var total_steps: usize = 0;

    while (total_steps < max_steps and lr >= lr_min) {
        // One gradient step
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
        total_steps += 1;

        // Check loss every `patience` steps
        if (total_steps % patience == 0) {
            const ev = evalModel(nfeat, &w, b);
            if (ev.loss < best_loss - 1e-6) {
                best_loss = ev.loss;
                no_improve = 0;
            } else {
                no_improve += 1;
                if (no_improve >= 3) {
                    lr *= 0.5;
                    no_improve = 0;
                }
            }
        }
    }

    for (0..NTRAIN) |i| {
        var logit = b;
        for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
        g_err[i] = sigmoid(logit) - if (g_labels[i]) @as(f64,1.0) else 0.0;
    }
    return evalModel(nfeat, &w, b).acc;
}

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

// Full pipeline: dual-stop discovery + chosen retrain strategy
fn pipeline(comptime use_adaptive: bool, w: anytype, name: []const u8) !f64 {
    // Phase 1: dual-stop discovery
    var active = [_]bool{false} ** NCANDS;
    for (0..NDEG1) |k| active[k] = true;
    var disc_buf: [16]usize = undefined;
    var n_disc: usize = 0;
    var deg1: [NDEG1]usize = undefined;
    for (0..NDEG1) |k| deg1[k] = k;
    _ = trainFixed(packByList(&deg1), 2000, 0.05);

    var steps: usize = 0;
    while (steps < 16) {
        const best = bestCandidate(&active);
        if (best.gap < GAP_STOP and best.g < GRAD_MIN) break;
        active[best.k] = true;
        disc_buf[n_disc] = best.k; n_disc += 1;
        steps += 1;
        var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
        for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
        const acc = trainFixed(packByList(al[0..na]), 2000, 0.05);
        if (acc >= TARGET) break;
    }

    // Build phase 2 feature list
    const disc_sl = disc_buf[0..n_disc];
    const rel_mask = relevantBitMask(disc_sl);
    var p2: [MAX_FEAT]usize = undefined;
    var np2: usize = 0;
    for (0..NDEG1) |k| {
        if (rel_mask & (@as(u8,1)<<@as(u3,@intCast(k))) != 0) { p2[np2]=k; np2+=1; }
    }
    for (disc_sl) |k| { p2[np2]=k; np2+=1; }

    const nf = packByList(p2[0..np2]);

    // Phase 2: retrain with chosen strategy
    const acc_p2 = if (use_adaptive)
        trainAdaptive(nf, 50000, 0.05, 1e-5, 500)
    else
        trainFixed(nf, 40000, 0.003);

    const verdict: []const u8 = if (acc_p2 >= TARGET) "SOLVED" else "FAILED";
    try w.print("{s:<32} feats={d:2}  acc={d:.4}  {s}\n",
        .{name, np2, acc_p2, verdict});
    return acc_p2;
}

// ─── predicates ───────────────────────────────────────────────────────────────
fn predK2(c: [NCELL]u8) bool {
    return ((if(c[0]>=THRESH)@as(u1,1)else 0)^(if(c[1]>=THRESH)@as(u1,1)else 0))==1;
}
fn predK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..3])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}
fn predK3r(c: [NCELL]u8) bool {
    return ((if(c[1]>=THRESH)@as(u1,1)else 0)^(if(c[3]>=THRESH)@as(u1,1)else 0)^(if(c[5]>=THRESH)@as(u1,1)else 0))==1;
}
fn predK2AndK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[2..5])|v| p^=if(v>=THRESH)@as(u1,1)else 0;
    return predK2(c) and (p==1);
}
fn predK4(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..4])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}

fn evalPred(c: [NCELL]u8, kind: u8, p: [4]u8) bool {
    return switch (kind) {
        0 => ((if(c[p[0]]>=THRESH)@as(u1,1)else 0)^(if(c[p[1]]>=THRESH)@as(u1,1)else 0))==1,
        1 => blk: {
            var x: u1=0;
            x^=if(c[p[0]]>=THRESH)@as(u1,1)else 0;
            x^=if(c[p[1]]>=THRESH)@as(u1,1)else 0;
            x^=if(c[p[2]]>=THRESH)@as(u1,1)else 0;
            break :blk x==1;
        },
        2 => ((if(c[p[0]]>=THRESH)@as(u1,1)else 0)&(if(c[p[1]]>=THRESH)@as(u1,1)else 0))==1,
        3 => blk: {
            const b0: u1=if(c[p[0]]>=THRESH)1 else 0;
            const b1: u1=if(c[p[1]]>=THRESH)1 else 0;
            const b2: u1=if(c[p[2]]>=THRESH)1 else 0;
            break :blk (b0&b1&b2)==1;
        },
        else => false,
    };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    initMeta();
    var rng: u64 = 0xF17ADA_7EBEEF17;

    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        precomputeAll(g_cells[i], &g_all[i]);
    }

    try stdout.print("ADAPTIVE RETRAIN  (Frontier 17)\n", .{});
    try stdout.print("Discovery: dual-stop (gap<1.5 AND |g|<0.008)\n", .{});
    try stdout.print("Retrain A: fixed 40000 iters, LR=0.003\n", .{});
    try stdout.print("Retrain B: adaptive LR halving, max 50000 steps, lr_init=0.05→min=1e-5\n\n", .{});

    // ── Fixed LR control ──────────────────────────────────────────────────────
    try stdout.print("STRATEGY A — fixed low LR (40k iters, lr=0.003)\n", .{});
    try stdout.print("{s}\n", .{"─"**60});

    for (0..NSAMP) |i| g_labels[i] = predK2(g_cells[i]);
    _ = try pipeline(false, stdout, "k2-parity b[0]⊕b[1]");
    for (0..NSAMP) |i| g_labels[i] = predK3(g_cells[i]);
    _ = try pipeline(false, stdout, "k3-parity b[0]⊕b[1]⊕b[2]");
    for (0..NSAMP) |i| g_labels[i] = predK3r(g_cells[i]);
    _ = try pipeline(false, stdout, "k3-random b[1]⊕b[3]⊕b[5]");
    for (0..NSAMP) |i| g_labels[i] = predK2AndK3(g_cells[i]);
    _ = try pipeline(false, stdout, "k2∧k3");
    for (0..NSAMP) |i| g_labels[i] = predK4(g_cells[i]);
    _ = try pipeline(false, stdout, "k4-parity (out of pool)");

    // ── Adaptive LR ───────────────────────────────────────────────────────────
    try stdout.print("\nSTRATEGY B — adaptive LR halving\n", .{});
    try stdout.print("{s}\n", .{"─"**60});

    for (0..NSAMP) |i| g_labels[i] = predK2(g_cells[i]);
    _ = try pipeline(true, stdout, "k2-parity b[0]⊕b[1]");
    for (0..NSAMP) |i| g_labels[i] = predK3(g_cells[i]);
    _ = try pipeline(true, stdout, "k3-parity b[0]⊕b[1]⊕b[2]");
    for (0..NSAMP) |i| g_labels[i] = predK3r(g_cells[i]);
    _ = try pipeline(true, stdout, "k3-random b[1]⊕b[3]⊕b[5]");
    for (0..NSAMP) |i| g_labels[i] = predK2AndK3(g_cells[i]);
    _ = try pipeline(true, stdout, "k2∧k3");
    for (0..NSAMP) |i| g_labels[i] = predK4(g_cells[i]);
    _ = try pipeline(true, stdout, "k4-parity (out of pool)");

    // ── Part B: 20 random unknowns with adaptive strategy ────────────────────
    try stdout.print("\nPART B — 20 unknown predicates, strategy B (adaptive)\n", .{});
    try stdout.print("{s:<8} {s:<18} feats  acc_p2  verdict\n", .{"#", "type+positions"});
    try stdout.print("{s}\n", .{"─"**55});

    var solved: usize = 0;
    var total: usize = 0;
    const kindNames = [_][]const u8{"k2-XOR","k3-XOR","2-AND ","3-AND "};

    for (0..20) |trial| {
        const kind: u8 = @intCast(lcg(&rng) % 4);
        var pos: [4]u8 = .{0,0,0,0};
        var used: u8 = 0;
        for (0..4) |pi| {
            var p: u8 = @intCast(lcg(&rng) % NCELL);
            while (used & (@as(u8,1)<<@as(u3,@intCast(p))) != 0) p = @intCast(lcg(&rng) % NCELL);
            pos[pi] = p;
            used |= @as(u8,1) << @as(u3, @intCast(p));
        }
        for (0..NSAMP) |i| g_labels[i] = evalPred(g_cells[i], kind, pos);
        var npos: usize = 0;
        for (0..NSAMP) |i| { if (g_labels[i]) npos += 1; }
        const pf = @as(f64,@floatFromInt(npos))/@as(f64,@floatFromInt(NSAMP));
        if (pf < 0.05 or pf > 0.95) {
            try stdout.print("{d:2}     skipped (imbalanced)\n", .{trial+1});
            continue;
        }

        // Dual-stop discovery
        var active = [_]bool{false} ** NCANDS;
        for (0..NDEG1) |k| active[k] = true;
        var disc_buf: [16]usize = undefined;
        var n_disc: usize = 0;
        var deg1: [NDEG1]usize = undefined;
        for (0..NDEG1) |k| deg1[k] = k;
        _ = trainFixed(packByList(&deg1), 2000, 0.05);
        var steps: usize = 0;
        while (steps < 16) {
            const best = bestCandidate(&active);
            if (best.gap < GAP_STOP and best.g < GRAD_MIN) break;
            active[best.k] = true;
            disc_buf[n_disc] = best.k; n_disc += 1;
            steps += 1;
            var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
            for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
            const acc = trainFixed(packByList(al[0..na]), 2000, 0.05);
            if (acc >= TARGET) break;
        }
        const disc_sl = disc_buf[0..n_disc];
        const rel_mask = relevantBitMask(disc_sl);
        var p2: [MAX_FEAT]usize = undefined; var np2: usize = 0;
        for (0..NDEG1) |k| {
            if (rel_mask & (@as(u8,1)<<@as(u3,@intCast(k))) != 0) { p2[np2]=k; np2+=1; }
        }
        for (disc_sl) |k| { p2[np2]=k; np2+=1; }
        const nf = packByList(p2[0..np2]);
        const acc_p2 = trainAdaptive(nf, 50000, 0.05, 1e-5, 500);

        const verdict: []const u8 = if (acc_p2 >= TARGET) "SOLVED" else "FAILED";
        if (acc_p2 >= TARGET) solved += 1;
        total += 1;
        try stdout.print("{d:2}     {s} [{d},{d},{d},{d}]    {d:2}  {d:.4}  {s}\n",
            .{trial+1, kindNames[kind], pos[0],pos[1],pos[2],pos[3], np2, acc_p2, verdict});
    }

    try stdout.print("\n{s}\n", .{"─"**55});
    try stdout.print("Part B adaptive: {d}/{d} solved\n", .{solved, total});
}
