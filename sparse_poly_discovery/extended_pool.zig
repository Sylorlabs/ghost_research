// Frontier 18 — Extended Pool
//
// F17 left two unsolved predicates with known reasons:
//   k4-parity: needs degree-4 monomial — NOT in the degree-3 pool
//   k2∧k3:     AND of two parities → cross-terms up to degree 5
//
// This experiment extends the pool to degree-4 (15 more monomials) and degree-5
// (6 more monomials), then re-runs the full pipeline on both predicates.
//
// Prediction:
//   k4-parity:  degree-4 monomial b[0]*b[1]*b[2]*b[3] found at step 1 with large gap
//               + degree-3 and degree-2 support terms added in subsequent steps → SOLVED
//   k2∧k3:      cross-terms like b[0]*b[2]*b[3]*b[4] found; needs degree 4 or 5 → ?
//
// The pool: deg-1(6) + deg-2(15) + deg-3(20) + deg-4(15) + deg-5(6) = 62 features

const std = @import("std");

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 3200;
const NTRAIN: usize = NSAMP * 4 / 5;
const NTEST: usize = NSAMP - NTRAIN;

const MAX_FEAT: usize = 70;
const MAX_DISC: usize = 30;
const NDEG1: usize = 6;
const NDEG2: usize = 15;
const NDEG3: usize = 20;
const NDEG4: usize = 15;  // C(6,4)
const NDEG5: usize = 6;   // C(6,5)
const NCANDS: usize = NDEG1 + NDEG2 + NDEG3 + NDEG4 + NDEG5; // 62

const GAP_STOP: f64 = 1.5;
const GRAD_MIN: f64 = 0.008;
const TARGET: f64 = 0.97;

var g_cells: [NSAMP][NCELL]u8 = undefined;
var g_labels: [NSAMP]bool = undefined;
var g_all: [NSAMP][NCANDS]f64 = undefined;
var g_feat: [NSAMP][MAX_FEAT]f64 = undefined;
var g_err: [NSAMP]f64 = undefined;

const FeatMeta = struct { deg: u8, i: u8, j: u8, l: u8, m: u8, n: u8 };
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
    // deg-1
    for (0..NCELL) |i| { g_meta[k] = .{.deg=1,.i=@intCast(i),.j=0,.l=0,.m=0,.n=0}; k+=1; }
    // deg-2
    for (0..NCELL) |i| for (i+1..NCELL) |j| {
        g_meta[k] = .{.deg=2,.i=@intCast(i),.j=@intCast(j),.l=0,.m=0,.n=0}; k+=1;
    };
    // deg-3
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| {
        g_meta[k] = .{.deg=3,.i=@intCast(i),.j=@intCast(j),.l=@intCast(l),.m=0,.n=0}; k+=1;
    };
    // deg-4
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| for (l+1..NCELL) |m| {
        g_meta[k] = .{.deg=4,.i=@intCast(i),.j=@intCast(j),.l=@intCast(l),.m=@intCast(m),.n=0}; k+=1;
    };
    // deg-5
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| for (l+1..NCELL) |m| for (m+1..NCELL) |n| {
        g_meta[k] = .{.deg=5,.i=@intCast(i),.j=@intCast(j),.l=@intCast(l),.m=@intCast(m),.n=@intCast(n)}; k+=1;
    };
}

fn precomputeAll(c: [NCELL]u8, f: *[NCANDS]f64) void {
    var k: usize = 0;
    for (0..NCELL) |i| { f[k]=bit(c,i); k+=1; }
    for (0..NCELL) |i| for (i+1..NCELL) |j| { f[k]=bit(c,i)*bit(c,j); k+=1; };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| {
        f[k]=bit(c,i)*bit(c,j)*bit(c,l); k+=1;
    };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| for (l+1..NCELL) |m| {
        f[k]=bit(c,i)*bit(c,j)*bit(c,l)*bit(c,m); k+=1;
    };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| for (l+1..NCELL) |m| for (m+1..NCELL) |n| {
        f[k]=bit(c,i)*bit(c,j)*bit(c,l)*bit(c,m)*bit(c,n); k+=1;
    };
}

fn packByList(idxs: []const usize) usize {
    for (idxs, 0..) |k, f| {
        for (0..NSAMP) |i| g_feat[i][f] = g_all[i][k];
    }
    return idxs.len;
}

fn trainAdaptive(nfeat: usize, max_steps: usize, lr_init: f64, lr_min: f64, patience: usize) f64 {
    var w = [_]f64{0.0} ** MAX_FEAT;
    var b: f64 = 0.0;
    var lr = lr_init;
    var best_loss: f64 = 1e18;
    var no_improve: usize = 0;
    var total: usize = 0;
    while (total < max_steps and lr >= lr_min) {
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
        total += 1;
        if (total % patience == 0) {
            var loss: f64 = 0;
            for (0..NTRAIN) |i| {
                var logit = b;
                for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
                const p = sigmoid(logit);
                const y: f64 = if (g_labels[i]) 1.0 else 0.0;
                loss += -(y*@log(p+1e-15)+(1.0-y)*@log(1.0-p+1e-15));
            }
            loss /= @as(f64,@floatFromInt(NTRAIN));
            if (loss < best_loss - 1e-6) { best_loss=loss; no_improve=0; }
            else { no_improve+=1; if (no_improve>=3) { lr*=0.5; no_improve=0; } }
        }
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

fn bestCandidate(active: *const [NCANDS]bool) struct { k: usize, g: f64, gap: f64 } {
    var best_k: usize = 0; var best_g: f64 = 0; var second_g: f64 = 0;
    for (0..NCANDS) |k| if (!active[k]) {
        var g: f64 = 0;
        for (0..NTRAIN) |i| g += g_err[i]*g_all[i][k];
        g = @abs(g)/@as(f64,@floatFromInt(NTRAIN));
        if (g > best_g) { second_g=best_g; best_g=g; best_k=k; }
        else if (g > second_g) second_g=g;
    };
    const gap = if (second_g > 1e-10) best_g/second_g else 0.0;
    return .{.k=best_k,.g=best_g,.gap=gap};
}

fn relevantBitMask(discovered: []const usize) u8 {
    var mask: u8 = 0;
    for (discovered) |k| {
        const m = g_meta[k];
        mask |= @as(u8,1)<<@as(u3,@intCast(m.i));
        if (m.deg >= 2) mask |= @as(u8,1)<<@as(u3,@intCast(m.j));
        if (m.deg >= 3) mask |= @as(u8,1)<<@as(u3,@intCast(m.l));
        if (m.deg >= 4) mask |= @as(u8,1)<<@as(u3,@intCast(m.m));
        if (m.deg >= 5) mask |= @as(u8,1)<<@as(u3,@intCast(m.n));
    }
    return mask;
}

fn featName(k: usize) [24]u8 {
    var buf = [_]u8{' '} ** 24;
    const m = g_meta[k];
    _ = switch (m.deg) {
        1 => std.fmt.bufPrint(&buf, "b[{d}]", .{m.i}),
        2 => std.fmt.bufPrint(&buf, "b[{d}]*b[{d}]", .{m.i,m.j}),
        3 => std.fmt.bufPrint(&buf, "b[{d}]*b[{d}]*b[{d}]", .{m.i,m.j,m.l}),
        4 => std.fmt.bufPrint(&buf, "b[{d}]*b[{d}]*b[{d}]*b[{d}]", .{m.i,m.j,m.l,m.m}),
        5 => std.fmt.bufPrint(&buf, "b[0]*b[1]*b[2]*b[3]*b[4]", .{}),
        else => std.fmt.bufPrint(&buf, "?", .{}),
    } catch {};
    return buf;
}

fn runVerbose(w: anytype, name: []const u8) !void {
    try w.print("\n── {s} ──\n", .{name});

    var active = [_]bool{false} ** NCANDS;
    for (0..NDEG1) |k| active[k] = true;
    var disc_buf: [MAX_DISC]usize = undefined;
    var n_disc: usize = 0;

    var deg1: [NDEG1]usize = undefined;
    for (0..NDEG1) |k| deg1[k] = k;
    _ = trainAdaptive(packByList(&deg1), 3000, 0.05, 1e-5, 300);

    var acc: f64 = 0;
    var steps: usize = 0;
    while (steps < MAX_DISC) {
        const best = bestCandidate(&active);
        if (best.gap < GAP_STOP and best.g < GRAD_MIN) {
            try w.print("  dual-stop (gap={d:.2} |g|={d:.4}) after {d} steps\n", .{best.gap, best.g, steps});
            break;
        }
        active[best.k] = true;
        disc_buf[n_disc] = best.k; n_disc += 1;
        steps += 1;
        var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
        for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
        acc = trainAdaptive(packByList(al[0..na]), 3000, 0.05, 1e-5, 300);
        const nm = featName(best.k);
        try w.print("  step {d:2}: +{s}  acc={d:.3}  |g|={d:.4}  gap={d:.2}x\n",
            .{steps, nm[0..20], acc, best.g, best.gap});
        if (acc >= TARGET) break;
    }

    // Phase 2
    const disc_sl = disc_buf[0..n_disc];
    const rel_mask = relevantBitMask(disc_sl);
    var p2: [MAX_FEAT]usize = undefined; var np2: usize = 0;
    for (0..NDEG1) |k| if (rel_mask & (@as(u8,1)<<@as(u3,@intCast(k))) != 0) { p2[np2]=k; np2+=1; };
    for (disc_sl) |k| { p2[np2]=k; np2+=1; }
    const acc_p2 = trainAdaptive(packByList(p2[0..np2]), 60000, 0.05, 1e-5, 500);
    const verdict: []const u8 = if (acc_p2 >= TARGET) "SOLVED" else "FAILED";
    try w.print("  phase2 ({d} feats, {d} deg-1): acc={d:.4}  {s}\n",
        .{n_disc, np2-n_disc, acc_p2, verdict});
}

// ─── predicates ───────────────────────────────────────────────────────────────
fn predK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..3])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}
fn predK4(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..4])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}
fn predK5(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..5])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}
fn predK6(c: [NCELL]u8) bool {
    var p: u1=0; for(c)|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}
fn predK2(c: [NCELL]u8) bool {
    return ((if(c[0]>=THRESH)@as(u1,1)else 0)^(if(c[1]>=THRESH)@as(u1,1)else 0))==1;
}
fn predK2AndK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[2..5])|v| p^=if(v>=THRESH)@as(u1,1)else 0;
    return predK2(c) and (p==1);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    initMeta();
    var rng: u64 = 0xF18E7000BEEF0DEF;

    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        precomputeAll(g_cells[i], &g_all[i]);
    }

    try stdout.print("EXTENDED POOL  (Frontier 18)\n", .{});
    try stdout.print("Pool: deg1({d}) + deg2({d}) + deg3({d}) + deg4({d}) + deg5({d}) = {d} features\n\n",
        .{NDEG1, NDEG2, NDEG3, NDEG4, NDEG5, NCANDS});

    // k3-parity: already solved in F17, run as sanity check
    for (0..NSAMP) |i| g_labels[i] = predK3(g_cells[i]);
    try runVerbose(stdout, "k3-parity (sanity: should solve in ~4 steps)");

    // k4-parity: previously rejected, now should be solvable
    for (0..NSAMP) |i| g_labels[i] = predK4(g_cells[i]);
    try runVerbose(stdout, "k4-parity (needs degree-4 monomial — now in pool)");

    // k5-parity: needs degree-5 monomial — now in pool
    for (0..NSAMP) |i| g_labels[i] = predK5(g_cells[i]);
    try runVerbose(stdout, "k5-parity (needs degree-5 monomial — now in pool)");

    // k6-parity: needs degree-6 monomial — still NOT in pool
    for (0..NSAMP) |i| g_labels[i] = predK6(g_cells[i]);
    try runVerbose(stdout, "k6-parity (needs degree-6 — still out of pool)");

    // k2∧k3: AND of two parities, needs degree-5 cross-terms
    for (0..NSAMP) |i| g_labels[i] = predK2AndK3(g_cells[i]);
    try runVerbose(stdout, "k2∧k3  AND-of-parities (degree-5 cross-terms now in pool)");
}
