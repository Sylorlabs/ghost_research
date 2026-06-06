// Frontier 20 — Online Position Refinement
//
// F19 finding: guided approach can't bootstrap k4-parity because the degree-4 leading
// monomial has zero Fourier coefficients at degree ≤ 3 — pass-1 finds nothing.
//
// New strategy: online refinement during a SINGLE discovery pass over the full pool.
// After each discovered feature, update a position mask. All subsequent candidates
// are restricted to only use positions in the current mask.
//
// At step 1: full pool (62 candidates)
//            → finds b[0]*b[1]*b[2]*b[3] (k4 leading monomial, |g| large)
//            → position mask updated to {0,1,2,3}
// At step 2: pool filtered to features on positions {0,1,2,3} only (11 candidates)
//            → high signal-to-noise; finds degree-3 support terms cleanly
// ...
//
// This solves the pool-pollution problem: the contaminating degree-4/5 noise features
// are pruned away as soon as the relevant positions are identified.

const std = @import("std");

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 3200;
const NTRAIN: usize = NSAMP * 4 / 5;
const NTEST: usize = NSAMP - NTRAIN;

const MAX_FEAT: usize = 80;
const MAX_DISC: usize = 40;
const NDEG1: usize = 6;
const NDEG2: usize = 15;
const NDEG3: usize = 20;
const NDEG4: usize = 15;
const NDEG5: usize = 6;
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
    for (0..NCELL) |i| { g_meta[k] = .{.deg=1,.i=@intCast(i),.j=0,.l=0,.m=0,.n=0}; k+=1; }
    for (0..NCELL) |i| for (i+1..NCELL) |j| {
        g_meta[k] = .{.deg=2,.i=@intCast(i),.j=@intCast(j),.l=0,.m=0,.n=0}; k+=1;
    };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| {
        g_meta[k] = .{.deg=3,.i=@intCast(i),.j=@intCast(j),.l=@intCast(l),.m=0,.n=0}; k+=1;
    };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| for (l+1..NCELL) |m| {
        g_meta[k] = .{.deg=4,.i=@intCast(i),.j=@intCast(j),.l=@intCast(l),.m=@intCast(m),.n=0}; k+=1;
    };
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

fn trainAdaptive(nfeat: usize, max_steps: usize) f64 {
    var w = [_]f64{0.0} ** MAX_FEAT;
    var b: f64 = 0.0;
    var lr: f64 = 0.05;
    var best_loss: f64 = 1e18;
    var no_improve: usize = 0;
    var total: usize = 0;
    const patience: usize = 500;
    while (total < max_steps and lr >= 1e-5) {
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
            loss /= @as(f64, @floatFromInt(NTRAIN));
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

// Compute bit mask for a feature
fn featMask(k: usize) u8 {
    const m = g_meta[k];
    var mask: u8 = @as(u8,1)<<@as(u3,@intCast(m.i));
    if (m.deg >= 2) mask |= @as(u8,1)<<@as(u3,@intCast(m.j));
    if (m.deg >= 3) mask |= @as(u8,1)<<@as(u3,@intCast(m.l));
    if (m.deg >= 4) mask |= @as(u8,1)<<@as(u3,@intCast(m.m));
    if (m.deg >= 5) mask |= @as(u8,1)<<@as(u3,@intCast(m.n));
    return mask;
}

// Best candidate from the filtered candidate set (within pos_mask)
// pos_mask=0xFF means no filter (full pool)
fn bestCandFiltered(active: *const [NCANDS]bool, pos_mask: u8) struct { k: usize, g: f64, gap: f64 } {
    var best_k: usize = 0; var best_g: f64 = 0; var second_g: f64 = 0;
    for (0..NCANDS) |k| {
        if (active[k]) continue;
        // Filter: feature must only use positions within pos_mask
        const fm = featMask(k);
        if ((fm & pos_mask) != fm) continue;
        var g: f64 = 0;
        for (0..NTRAIN) |i| g += g_err[i]*g_all[i][k];
        g = @abs(g)/@as(f64,@floatFromInt(NTRAIN));
        if (g > best_g) { second_g=best_g; best_g=g; best_k=k; }
        else if (g > second_g) second_g=g;
    }
    const gap = if (second_g > 1e-10) best_g/second_g else 0.0;
    return .{.k=best_k,.g=best_g,.gap=gap};
}

fn featStr(k: usize) [24]u8 {
    var buf = [_]u8{' '} ** 24;
    const m = g_meta[k];
    _ = switch (m.deg) {
        1 => std.fmt.bufPrint(&buf, "b[{d}]", .{m.i}),
        2 => std.fmt.bufPrint(&buf, "b[{d}]*b[{d}]", .{m.i,m.j}),
        3 => std.fmt.bufPrint(&buf, "b[{d}]*b[{d}]*b[{d}]", .{m.i,m.j,m.l}),
        4 => std.fmt.bufPrint(&buf, "b[{d}]*b[{d}]*b[{d}]*b[{d}]", .{m.i,m.j,m.l,m.m}),
        5 => std.fmt.bufPrint(&buf, "b[{d}]*b[{d}]*b[{d}]*b[{d}]*b[{d}]", .{m.i,m.j,m.l,m.m,m.n}),
        else => std.fmt.bufPrint(&buf, "?", .{}),
    } catch {};
    return buf;
}

fn runOnlineGuided(w: anytype, name: []const u8) !void {
    try w.print("\n── {s} ──\n", .{name});

    var active = [_]bool{false} ** NCANDS;
    // Start with degree-1 features only
    for (0..NCELL) |k| active[k] = true;

    var disc_buf: [MAX_DISC]usize = undefined;
    var n_disc: usize = 0;

    var deg1: [NDEG1]usize = undefined;
    for (0..NDEG1) |k| deg1[k] = k;
    _ = trainAdaptive(packByList(&deg1), 3000);

    var pos_mask: u8 = 0xFF; // start unfiltered
    var steps: usize = 0;
    var acc: f64 = 0;

    while (steps < MAX_DISC) {
        const best = bestCandFiltered(&active, pos_mask);
        if (best.gap < GAP_STOP and best.g < GRAD_MIN) {
            try w.print("  dual-stop (gap={d:.2} |g|={d:.4}) after {d} steps\n", .{best.gap, best.g, steps});
            break;
        }

        active[best.k] = true;
        disc_buf[n_disc] = best.k; n_disc += 1;
        steps += 1;

        // Update position mask: narrow to only positions seen so far
        var new_mask: u8 = 0;
        for (disc_buf[0..n_disc]) |k| new_mask |= featMask(k);
        const was_unfiltered = (pos_mask == 0xFF);
        pos_mask = new_mask;

        var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
        for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
        acc = trainAdaptive(packByList(al[0..na]), 2000);

        const nm = featStr(best.k);
        const filter_info: []const u8 = if (was_unfiltered) " [pool narrowed]" else "";
        try w.print("  step {d:2}: +{s}  acc={d:.3}  |g|={d:.4}  gap={d:.2}x{s}\n",
            .{steps, nm[0..20], acc, best.g, best.gap, filter_info});
        if (acc >= TARGET) break;
    }

    // Final retrain
    var all: [MAX_FEAT]usize = undefined; var na: usize = 0;
    for (0..NCANDS) |k| if (active[k]) { all[na]=k; na+=1; };
    const acc_final = trainAdaptive(packByList(all[0..na]), 60000);
    const verdict: []const u8 = if (acc_final >= TARGET) "SOLVED" else "FAILED";
    try w.print("  final retrain ({d} feats): acc={d:.4}  {s}\n", .{na, acc_final, verdict});
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
fn predK2(c: [NCELL]u8) bool {
    return ((if(c[0]>=THRESH)@as(u1,1)else 0)^(if(c[1]>=THRESH)@as(u1,1)else 0))==1;
}
fn predK2AndK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[2..5])|v| p^=if(v>=THRESH)@as(u1,1)else 0;
    return predK2(c) and (p==1);
}
fn predK4rand(c: [NCELL]u8) bool {
    // k4-parity at positions 1,2,3,4 (not the default 0,1,2,3)
    const b1: u1 = if (c[1]>=THRESH) 1 else 0;
    const b2: u1 = if (c[2]>=THRESH) 1 else 0;
    const b3: u1 = if (c[3]>=THRESH) 1 else 0;
    const b4: u1 = if (c[4]>=THRESH) 1 else 0;
    return (b1 ^ b2 ^ b3 ^ b4) == 1;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    initMeta();
    var rng: u64 = 0xF200BEEF_0DEF1234;

    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        precomputeAll(g_cells[i], &g_all[i]);
    }

    try stdout.print("ONLINE GUIDED DISCOVERY  (Frontier 20)\n", .{});
    try stdout.print("Pool: {d} features (deg 1-5). After first discovery, narrow pool to found positions.\n\n", .{NCANDS});

    for (0..NSAMP) |i| g_labels[i] = predK3(g_cells[i]);
    try runOnlineGuided(stdout, "k3-parity (sanity)");

    for (0..NSAMP) |i| g_labels[i] = predK4(g_cells[i]);
    try runOnlineGuided(stdout, "k4-parity b[0]⊕b[1]⊕b[2]⊕b[3]");

    for (0..NSAMP) |i| g_labels[i] = predK4rand(g_cells[i]);
    try runOnlineGuided(stdout, "k4-parity b[1]⊕b[2]⊕b[3]⊕b[4] (random positions)");

    for (0..NSAMP) |i| g_labels[i] = predK5(g_cells[i]);
    try runOnlineGuided(stdout, "k5-parity b[0]⊕...⊕b[4]");

    for (0..NSAMP) |i| g_labels[i] = predK2AndK3(g_cells[i]);
    try runOnlineGuided(stdout, "k2∧k3");
}
