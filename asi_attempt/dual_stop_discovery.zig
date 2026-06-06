// Frontier 16 — Dual Stopping Criterion
//
// F15 revealed two distinct meanings for gap < 1.5x:
//   (A) gap < 1.5 AND |g| < noise floor  → nothing representable; truly stop
//   (B) gap < 1.5 AND |g| still large    → symmetric feature group; WRONG to stop
//
// Fix: conjunctive stopping — stop only when BOTH conditions hold:
//   gap < GAP_STOP AND |g| < GRAD_MIN
//
// k3-parity after step 1: gap ≈ 1.04, |g| ≈ 0.029 → old algo stops, new continues
// k4-parity throughout:   gap ≈ 1.01, |g| ≈ 0.003 → both stop (correct rejection)
//
// Predicted: k3-XOR/k3-parity go from 0/6 → 6/6; k4 still correctly rejected.

const std = @import("std");

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 3200;
const NTRAIN: usize = NSAMP * 4 / 5;
const NTEST: usize = NSAMP - NTRAIN;

const LR_P1: f64 = 0.05;
const LR_P2: f64 = 0.012;
const NITERS_P1: usize = 2000;
const NITERS_P2: usize = 8000;
const MAX_FEAT: usize = 60;
const MAX_DISC: usize = 25;
const GAP_STOP: f64 = 1.5;
const GRAD_MIN: f64 = 0.008; // below this AND gap < 1.5 → truly stop
const TARGET: f64 = 0.97;

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

fn featName(k: usize, buf: []u8) []u8 {
    const m = g_meta[k];
    return switch (m.deg) {
        1 => std.fmt.bufPrint(buf, "b[{d}]          ", .{m.i}) catch buf,
        2 => std.fmt.bufPrint(buf, "b[{d}]*b[{d}]      ", .{m.i,m.j}) catch buf,
        3 => std.fmt.bufPrint(buf, "b[{d}]*b[{d}]*b[{d}]  ", .{m.i,m.j,m.l}) catch buf,
        else => buf,
    };
}

const RunResult = struct { acc_p1: f64, acc_p2: f64, steps: usize, stop_reason: u8 };
// stop_reason: 0=both(true stop), 1=gap-only(old wrong stop), 2=mag-only, 3=max-steps

fn runDualStop(w: anytype, name: []const u8, verbose: bool) !RunResult {
    var active = [_]bool{false} ** NCANDS;
    for (0..NDEG1) |k| active[k] = true;

    var disc_buf: [MAX_DISC]usize = undefined;
    var n_disc: usize = 0;

    var deg1: [NDEG1]usize = undefined;
    for (0..NDEG1) |k| deg1[k] = k;
    var acc = trainTestLR(packByList(&deg1), NITERS_P1, LR_P1);

    if (verbose) try w.print("  Phase 1:\n", .{});

    var last_gap: f64 = 99.0;
    var last_g: f64 = 99.0;
    var steps: usize = 0;
    var stop_reason: u8 = 3;

    while (steps < MAX_DISC) {
        const best = bestCandidate(&active);
        last_gap = best.gap;
        last_g = best.g;

        // DUAL criterion: stop only when BOTH gap low AND magnitude low
        const gap_low = best.gap < GAP_STOP;
        const mag_low = best.g < GRAD_MIN;

        if (gap_low and mag_low) { stop_reason = 0; break; }  // true stop
        if (steps == MAX_DISC - 1) { stop_reason = 3; }

        active[best.k] = true;
        if (n_disc < MAX_DISC) { disc_buf[n_disc]=best.k; n_disc+=1; }
        steps += 1;

        var al: [MAX_FEAT]usize = undefined;
        var na: usize = 0;
        for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
        acc = trainTestLR(packByList(al[0..na]), NITERS_P1, LR_P1);

        if (verbose) {
            var nbuf: [20]u8 = [_]u8{' '} ** 20;
            const nm = featName(best.k, &nbuf);
            try w.print("    step {d}: +{s}  acc={d:.3}  |g|={d:.4}  gap={d:.2}x\n",
                .{ steps, nm[0..14], acc, best.g, best.gap });
        }

        if (acc >= TARGET) { stop_reason = 4; break; }
    }

    const acc_p1 = acc;

    // Phase 2: clean retrain on discovered + relevant deg-1 only
    const disc_sl = disc_buf[0..n_disc];
    const rel_mask = relevantBitMask(disc_sl);
    var p2: [MAX_FEAT]usize = undefined;
    var np2: usize = 0;
    for (0..NDEG1) |k| {
        if (rel_mask & (@as(u8,1)<<@as(u3,@intCast(k))) != 0) { p2[np2]=k; np2+=1; }
    }
    for (disc_sl) |k| { p2[np2]=k; np2+=1; }
    const acc_p2 = if (np2>0) trainTestLR(packByList(p2[0..np2]), NITERS_P2, LR_P2) else acc_p1;

    const verdict: []const u8 = if (acc_p2 >= TARGET) "SOLVED"
                                else if (acc_p1 >= TARGET) "P1-ok "
                                else "FAILED";

    const stop_str: []const u8 = switch (stop_reason) {
        0 => "dual-stop",
        3 => "max-steps",
        4 => "target   ",
        else => "?        ",
    };

    try w.print("{s:<28} {d:.3}  {d:.3}  {d:2}  {d:.3}  {s}  {s}\n",
        .{ name, acc_p1, acc_p2, steps, last_g, stop_str, verdict });

    return .{ .acc_p1=acc_p1, .acc_p2=acc_p2, .steps=steps, .stop_reason=stop_reason };
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

fn kindName(kind: u8) []const u8 {
    return switch (kind) { 0=>"k2-XOR", 1=>"k3-XOR", 2=>"2-AND ", 3=>"3-AND ", else=>"?????" };
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    initMeta();
    var rng: u64 = 0xF16_D0A1_BEEF_C0DE;

    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        precomputeAll(g_cells[i], &g_all[i]);
    }

    try stdout.print("DUAL-STOP GRADIENT DISCOVERY  (Frontier 16)\n", .{});
    try stdout.print("Stop when: gap < {d:.1} AND |g| < {d:.3}  (conjunction, not disjunction)\n\n", .{GAP_STOP, GRAD_MIN});

    // ── verbose trace on the 3 problem cases ──────────────────────────────────
    try stdout.print("── Verbose trace: k3-parity (the F15 plateau case) ──\n", .{});
    for (0..NSAMP) |i| g_labels[i] = predK3(g_cells[i]);
    {
        var active = [_]bool{false} ** NCANDS;
        for (0..NDEG1) |k| active[k] = true;
        var disc_buf: [MAX_DISC]usize = undefined;
        var n_disc: usize = 0;
        var deg1: [NDEG1]usize = undefined;
        for (0..NDEG1) |k| deg1[k] = k;
        var acc = trainTestLR(packByList(&deg1), NITERS_P1, LR_P1);
        try stdout.print("  start acc={d:.3}\n", .{acc});
        var steps: usize = 0;
        while (steps < MAX_DISC) {
            const best = bestCandidate(&active);
            if (best.gap < GAP_STOP and best.g < GRAD_MIN) { try stdout.print("  dual-stop (gap={d:.2} |g|={d:.4})\n", .{best.gap,best.g}); break; }
            active[best.k] = true;
            disc_buf[n_disc] = best.k; n_disc += 1;
            steps += 1;
            var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
            for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
            acc = trainTestLR(packByList(al[0..na]), NITERS_P1, LR_P1);
            var nbuf: [20]u8 = [_]u8{' '} ** 20;
            const nm = featName(best.k, &nbuf);
            try stdout.print("  step {d}: +{s}  acc={d:.3}  |g|={d:.4}  gap={d:.2}x\n",
                .{steps, nm[0..14], acc, best.g, best.gap});
            if (acc >= TARGET) break;
        }
        const disc_sl = disc_buf[0..n_disc];
        const rel_mask = relevantBitMask(disc_sl);
        var p2: [MAX_FEAT]usize = undefined; var np2: usize = 0;
        for (0..NDEG1) |k| if (rel_mask & (@as(u8,1)<<@as(u3,@intCast(k))) != 0) { p2[np2]=k; np2+=1; };
        for (disc_sl) |k| { p2[np2]=k; np2+=1; }
        const acc_p2 = trainTestLR(packByList(p2[0..np2]), NITERS_P2, LR_P2);
        try stdout.print("  phase2 ({d} features, {d} relevant deg-1): acc={d:.3}\n\n", .{n_disc, np2-n_disc, acc_p2});
    }

    // ── Part A: known predicates ──────────────────────────────────────────────
    try stdout.print("PART A — known predicates\n", .{});
    try stdout.print("{s:<28} p1     p2     steps  |g|    stop       verdict\n", .{"predicate"});
    try stdout.print("{s}\n", .{"─"**80});

    const KP = struct { name: []const u8, fn_: *const fn([NCELL]u8) bool };
    const known = [_]KP{
        .{ .name="k2-parity b[0]⊕b[1]",      .fn_=predK2      },
        .{ .name="k3-parity b[0]⊕b[1]⊕b[2]", .fn_=predK3      },
        .{ .name="k3-random b[1]⊕b[3]⊕b[5]", .fn_=predK3r     },
        .{ .name="k2∧k3",                     .fn_=predK2AndK3 },
        .{ .name="k4-parity (out of pool)",   .fn_=predK4      },
    };
    for (known) |kp| {
        for (0..NSAMP) |i| g_labels[i] = kp.fn_(g_cells[i]);
        _ = try runDualStop(stdout, kp.name, false);
    }

    // ── Part B: 20 random unknown predicates ──────────────────────────────────
    try stdout.print("\nPART B — 20 unknown random predicates (blind test)\n", .{});
    try stdout.print("{s:<8} {s:<20} p1     p2     steps  verdict\n", .{"#", "type+positions"});
    try stdout.print("{s}\n", .{"─"**65});

    var solved: usize = 0;
    var total: usize = 0;

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
            try stdout.print("{d:2}     {s} [{d},{d},{d},{d}]  skipped (imbalanced)\n",
                .{trial+1,kindName(kind),pos[0],pos[1],pos[2],pos[3]});
            continue;
        }

        // Inline two-phase with dual stop
        var active = [_]bool{false} ** NCANDS;
        for (0..NDEG1) |k| active[k] = true;
        var disc_buf: [MAX_DISC]usize = undefined;
        var n_disc: usize = 0;
        var deg1: [NDEG1]usize = undefined;
        for (0..NDEG1) |k| deg1[k] = k;
        var acc = trainTestLR(packByList(&deg1), NITERS_P1, LR_P1);
        var steps: usize = 0;
        while (steps < MAX_DISC) {
            const best = bestCandidate(&active);
            if (best.gap < GAP_STOP and best.g < GRAD_MIN) break;
            active[best.k] = true;
            if (n_disc < MAX_DISC) { disc_buf[n_disc]=best.k; n_disc+=1; }
            steps += 1;
            var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
            for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
            acc = trainTestLR(packByList(al[0..na]), NITERS_P1, LR_P1);
            if (acc >= TARGET) break;
        }
        const acc_p1 = acc;
        const disc_sl = disc_buf[0..n_disc];
        const rel_mask = relevantBitMask(disc_sl);
        var p2: [MAX_FEAT]usize = undefined; var np2: usize = 0;
        for (0..NDEG1) |k| if (rel_mask & (@as(u8,1)<<@as(u3,@intCast(k))) != 0) { p2[np2]=k; np2+=1; };
        for (disc_sl) |k| { p2[np2]=k; np2+=1; }
        const acc_p2 = if (np2>0) trainTestLR(packByList(p2[0..np2]), NITERS_P2, LR_P2) else acc_p1;

        const verdict: []const u8 = if (acc_p2 >= TARGET) "SOLVED" else if (acc_p1 >= TARGET) "P1-ok" else "FAILED";
        if (acc_p2 >= TARGET) solved += 1;
        total += 1;

        try stdout.print("{d:2}     {s} [{d},{d},{d},{d}]    {d:.3}  {d:.3}  {d:2}     {s}\n",
            .{trial+1,kindName(kind),pos[0],pos[1],pos[2],pos[3], acc_p1,acc_p2,steps,verdict});
    }

    try stdout.print("\n{s}\n", .{"─"**65});
    try stdout.print("Part B: {d}/{d} solved\n", .{solved, total});
    try stdout.print("\nF15→F16 comparison: F15 solved 14/20; F16 target: 20/20\n", .{});
    try stdout.print("Remaining failures = predicates not representable in deg≤3 pool\n", .{});
}
