// Frontier 19 — Guided Pool Extension
//
// F18 finding: a large pool (62 features) dilutes gradient signal — the algorithm
// dual-stops before collecting all support terms for k4/k5-parity.
//
// Fix: staged pool construction guided by what was already discovered.
//   Pass 1: run discovery on degree-3 pool (41 features)
//           → finds the leading monomial and identifies which BIT POSITIONS matter
//   Pass 2: extend pool by adding degree-4 and degree-5 monomials ONLY AT the
//           bit positions found in pass 1 (not all C(6,4)/C(6,5) combinations)
//   Pass 3: re-run discovery on the extended but position-filtered pool
//   Final:  adaptive retrain on all discovered features
//
// For k4-parity b[0]⊕b[1]⊕b[2]⊕b[3]:
//   Pass 1 finds positions {0,1,2,3} from the degree-4 monomial
//   Pass 2 adds only degree-2 through degree-4 features on {0,1,2,3}: 6+4+1 = 11 features
//   Much smaller pool → higher signal per feature

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
const NCANDS3: usize = NDEG1 + NDEG2 + NDEG3; // 41 — degree-3 pool

const GAP_STOP: f64 = 1.5;
const GRAD_MIN: f64 = 0.008;
const TARGET: f64 = 0.97;

// Full pool including degree-4 and degree-5
const NDEG4: usize = 15;
const NDEG5: usize = 6;
const NCANDS5: usize = NCANDS3 + NDEG4 + NDEG5; // 62

var g_cells: [NSAMP][NCELL]u8 = undefined;
var g_labels: [NSAMP]bool = undefined;
var g_all3: [NSAMP][NCANDS3]f64 = undefined;  // degree-3 pool
var g_all5: [NSAMP][NCANDS5]f64 = undefined;  // full pool
var g_feat: [NSAMP][MAX_FEAT]f64 = undefined;
var g_err: [NSAMP]f64 = undefined;

const FeatMeta = struct { deg: u8, i: u8, j: u8, l: u8, m: u8, n: u8 };
var g_meta3: [NCANDS3]FeatMeta = undefined;
var g_meta5: [NCANDS5]FeatMeta = undefined;

fn lcg(s: *u64) u64 {
    s.* ^= s.* >> 12;
    s.* ^= s.* << 25;
    s.* ^= s.* >> 27;
    return s.* *% 0x2545F4914F6CDD1D;
}
fn sigmoid(x: f64) f64 { return 1.0 / (1.0 + @exp(-x)); }
fn bit(c: [NCELL]u8, i: usize) f64 { return if (c[i] >= THRESH) 1.0 else 0.0; }

fn fillMeta(meta: []FeatMeta, max_deg: u8) void {
    var k: usize = 0;
    for (0..NCELL) |i| { meta[k] = .{.deg=1,.i=@intCast(i),.j=0,.l=0,.m=0,.n=0}; k+=1; }
    for (0..NCELL) |i| for (i+1..NCELL) |j| {
        meta[k] = .{.deg=2,.i=@intCast(i),.j=@intCast(j),.l=0,.m=0,.n=0}; k+=1;
    };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| {
        meta[k] = .{.deg=3,.i=@intCast(i),.j=@intCast(j),.l=@intCast(l),.m=0,.n=0}; k+=1;
    };
    if (max_deg >= 4) {
        for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| for (l+1..NCELL) |m| {
            meta[k] = .{.deg=4,.i=@intCast(i),.j=@intCast(j),.l=@intCast(l),.m=@intCast(m),.n=0}; k+=1;
        };
    }
    if (max_deg >= 5) {
        for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| for (l+1..NCELL) |m| for (m+1..NCELL) |n| {
            meta[k] = .{.deg=5,.i=@intCast(i),.j=@intCast(j),.l=@intCast(l),.m=@intCast(m),.n=@intCast(n)}; k+=1;
        };
    }
}

fn precompute3(c: [NCELL]u8, f: *[NCANDS3]f64) void {
    var k: usize = 0;
    for (0..NCELL) |i| { f[k]=bit(c,i); k+=1; }
    for (0..NCELL) |i| for (i+1..NCELL) |j| { f[k]=bit(c,i)*bit(c,j); k+=1; };
    for (0..NCELL) |i| for (i+1..NCELL) |j| for (j+1..NCELL) |l| {
        f[k]=bit(c,i)*bit(c,j)*bit(c,l); k+=1;
    };
}

fn precompute5(c: [NCELL]u8, f: *[NCANDS5]f64) void {
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

fn packFromAll5(idxs: []const usize) usize {
    for (idxs, 0..) |k, f| {
        for (0..NSAMP) |i| g_feat[i][f] = g_all5[i][k];
    }
    return idxs.len;
}

fn packFromAll3(idxs: []const usize) usize {
    for (idxs, 0..) |k, f| {
        for (0..NSAMP) |i| g_feat[i][f] = g_all3[i][k];
    }
    return idxs.len;
}

fn trainAdaptive(nfeat: usize, max_steps: usize, lr_init: f64) f64 {
    var w = [_]f64{0.0} ** MAX_FEAT;
    var b: f64 = 0.0;
    var lr = lr_init;
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

fn bestCand3(active: *const [NCANDS3]bool) struct { k: usize, g: f64, gap: f64 } {
    var best_k: usize = 0; var best_g: f64 = 0; var second_g: f64 = 0;
    for (0..NCANDS3) |k| if (!active[k]) {
        var g: f64 = 0;
        for (0..NTRAIN) |i| g += g_err[i]*g_all3[i][k];
        g = @abs(g)/@as(f64,@floatFromInt(NTRAIN));
        if (g > best_g) { second_g=best_g; best_g=g; best_k=k; }
        else if (g > second_g) second_g=g;
    };
    const gap = if (second_g > 1e-10) best_g/second_g else 0.0;
    return .{.k=best_k,.g=best_g,.gap=gap};
}

fn bestCand5(active: *const [NCANDS5]bool) struct { k: usize, g: f64, gap: f64 } {
    var best_k: usize = 0; var best_g: f64 = 0; var second_g: f64 = 0;
    for (0..NCANDS5) |k| if (!active[k]) {
        var g: f64 = 0;
        for (0..NTRAIN) |i| g += g_err[i]*g_all5[i][k];
        g = @abs(g)/@as(f64,@floatFromInt(NTRAIN));
        if (g > best_g) { second_g=best_g; best_g=g; best_k=k; }
        else if (g > second_g) second_g=g;
    };
    const gap = if (second_g > 1e-10) best_g/second_g else 0.0;
    return .{.k=best_k,.g=best_g,.gap=gap};
}

// Extract bit positions from discovered feature indices (into meta3 or meta5)
fn bitMaskFrom3(discovered: []const usize) u8 {
    var mask: u8 = 0;
    for (discovered) |k| {
        const m = g_meta3[k];
        mask |= @as(u8,1)<<@as(u3,@intCast(m.i));
        if (m.deg >= 2) mask |= @as(u8,1)<<@as(u3,@intCast(m.j));
        if (m.deg >= 3) mask |= @as(u8,1)<<@as(u3,@intCast(m.l));
    }
    return mask;
}

// Build a filtered pool5 that only includes features whose ALL bits are in `mask`
fn buildFilteredPool5(pos_mask: u8, pool: *[NCANDS5]usize) usize {
    var np: usize = 0;
    for (0..NCANDS5) |k| {
        const m = g_meta5[k];
        var feat_mask: u8 = @as(u8,1)<<@as(u3,@intCast(m.i));
        if (m.deg >= 2) feat_mask |= @as(u8,1)<<@as(u3,@intCast(m.j));
        if (m.deg >= 3) feat_mask |= @as(u8,1)<<@as(u3,@intCast(m.l));
        if (m.deg >= 4) feat_mask |= @as(u8,1)<<@as(u3,@intCast(m.m));
        if (m.deg >= 5) feat_mask |= @as(u8,1)<<@as(u3,@intCast(m.n));
        // Include if all feature bits are within the relevant positions
        if ((feat_mask & pos_mask) == feat_mask) {
            pool[np] = k; np += 1;
        }
    }
    return np;
}

fn featStr3(k: usize) [20]u8 {
    var buf = [_]u8{' '} ** 20;
    const m = g_meta3[k];
    _ = switch (m.deg) {
        1 => std.fmt.bufPrint(&buf, "b[{d}]", .{m.i}),
        2 => std.fmt.bufPrint(&buf, "b[{d}]*b[{d}]", .{m.i,m.j}),
        3 => std.fmt.bufPrint(&buf, "b[{d}]*b[{d}]*b[{d}]", .{m.i,m.j,m.l}),
        else => std.fmt.bufPrint(&buf, "?", .{}),
    } catch {};
    return buf;
}

fn featStr5(k: usize) [24]u8 {
    var buf = [_]u8{' '} ** 24;
    const m = g_meta5[k];
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

fn runGuided(w: anytype, name: []const u8) !void {
    try w.print("\n── {s} ──\n", .{name});

    // ── Pass 1: degree-3 pool, identify relevant bit positions ─────────────────
    var active3 = [_]bool{false} ** NCANDS3;
    for (0..NDEG1) |k| active3[k] = true;
    var disc3: [MAX_DISC]usize = undefined;
    var nd3: usize = 0;

    var deg1: [NDEG1]usize = undefined;
    for (0..NDEG1) |k| deg1[k] = k;
    _ = trainAdaptive(packFromAll3(&deg1), 3000, 0.05);

    var steps1: usize = 0;
    while (steps1 < 20) {
        const best = bestCand3(&active3);
        if (best.gap < GAP_STOP and best.g < GRAD_MIN) break;
        active3[best.k] = true;
        disc3[nd3] = best.k; nd3 += 1;
        steps1 += 1;
        var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
        for (0..NCANDS3) |k| if (active3[k]) { al[na]=k; na+=1; };
        const acc = trainAdaptive(packFromAll3(al[0..na]), 2000, 0.05);
        const nm = featStr3(best.k);
        try w.print("  P1 step {d:2}: +{s}  acc={d:.3}  |g|={d:.4}\n",
            .{steps1, nm[0..16], acc, best.g});
        if (acc >= TARGET) break;
    }

    // Bit mask from pass-1 discovered features
    const pos_mask = bitMaskFrom3(disc3[0..nd3]);
    var mask_bits: usize = 0;
    { var m = pos_mask; while (m != 0) { mask_bits += m&1; m >>= 1; } }
    try w.print("  Pass 1: {d} features, positions mask=0b{b:0>6} ({d} bits)\n",
        .{nd3, pos_mask, mask_bits});

    // ── Pass 2: build guided pool (only features on discovered positions) ───────
    var filtered5: [NCANDS5]usize = undefined;
    const nf5 = buildFilteredPool5(pos_mask, &filtered5);
    try w.print("  Guided pool: {d} features (all-positions subset of deg-5 pool)\n", .{nf5});

    // Activate all degree-1 features in the filtered pool
    var active5 = [_]bool{false} ** NCANDS5;
    for (0..NCANDS5) |k| {
        const m = g_meta5[k];
        if (m.deg == 1 and (pos_mask & (@as(u8,1)<<@as(u3,@intCast(m.i))) != 0)) active5[k] = true;
    }
    // Also activate previously discovered deg≥2 features from pass 1 (mapped to pool5 by content)
    // Simple: rebuild residuals from scratch on deg-1 init
    var deg1_active: [MAX_FEAT]usize = undefined;
    var ndeg1a: usize = 0;
    for (0..NCANDS5) |k| if (active5[k]) { deg1_active[ndeg1a]=k; ndeg1a+=1; };
    _ = trainAdaptive(packFromAll5(deg1_active[0..ndeg1a]), 3000, 0.05);

    var disc5: [MAX_DISC]usize = undefined;
    var nd5: usize = 0;
    var steps2: usize = 0;
    var acc5: f64 = 0;

    // Only consider features in the filtered pool
    while (steps2 < MAX_DISC) {
        // Compute gradients only for filtered candidates
        var best_k: usize = 0; var best_g: f64 = 0; var second_g: f64 = 0;
        for (0..nf5) |fi| {
            const k = filtered5[fi];
            if (active5[k]) continue;
            var g: f64 = 0;
            for (0..NTRAIN) |i| g += g_err[i]*g_all5[i][k];
            g = @abs(g)/@as(f64,@floatFromInt(NTRAIN));
            if (g > best_g) { second_g=best_g; best_g=g; best_k=k; }
            else if (g > second_g) second_g=g;
        }
        const gap = if (second_g > 1e-10) best_g/second_g else 0.0;

        if (gap < GAP_STOP and best_g < GRAD_MIN) {
            try w.print("  P2 dual-stop (gap={d:.2} |g|={d:.4}) after {d} steps\n", .{gap, best_g, steps2});
            break;
        }

        active5[best_k] = true;
        disc5[nd5] = best_k; nd5 += 1;
        steps2 += 1;

        var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
        for (0..NCANDS5) |k| if (active5[k]) { al[na]=k; na+=1; };
        acc5 = trainAdaptive(packFromAll5(al[0..na]), 2000, 0.05);
        const nm = featStr5(best_k);
        try w.print("  P2 step {d:2}: +{s}  acc={d:.3}  |g|={d:.4}  gap={d:.2}x\n",
            .{steps2, nm[0..20], acc5, best_g, gap});
        if (acc5 >= TARGET) break;
    }

    // Final adaptive retrain on all discovered features
    var all_disc: [MAX_FEAT]usize = undefined;
    var n_all: usize = 0;
    for (0..NCANDS5) |k| if (active5[k]) { all_disc[n_all]=k; n_all+=1; };
    const acc_final = trainAdaptive(packFromAll5(all_disc[0..n_all]), 60000, 0.05);
    const verdict: []const u8 = if (acc_final >= TARGET) "SOLVED" else "FAILED";
    try w.print("  Final retrain ({d} total feats): acc={d:.4}  {s}\n", .{n_all, acc_final, verdict});
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

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    fillMeta(&g_meta3, 3);
    fillMeta(&g_meta5, 5);

    var rng: u64 = 0xF196ADED_F00DDEF0;

    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        precompute3(g_cells[i], &g_all3[i]);
        precompute5(g_cells[i], &g_all5[i]);
    }

    try stdout.print("GUIDED POOL EXTENSION  (Frontier 19)\n", .{});
    try stdout.print("Strategy: pass-1 on deg-3 pool → identify positions → filtered deg-5 pool\n\n", .{});

    for (0..NSAMP) |i| g_labels[i] = predK3(g_cells[i]);
    try runGuided(stdout, "k3-parity (sanity)");

    for (0..NSAMP) |i| g_labels[i] = predK4(g_cells[i]);
    try runGuided(stdout, "k4-parity");

    for (0..NSAMP) |i| g_labels[i] = predK5(g_cells[i]);
    try runGuided(stdout, "k5-parity");

    for (0..NSAMP) |i| g_labels[i] = predK2AndK3(g_cells[i]);
    try runGuided(stdout, "k2∧k3 (AND-of-parities)");
}
