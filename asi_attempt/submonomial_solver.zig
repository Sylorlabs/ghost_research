// Frontier 21 — Sub-Monomial Force-Add
//
// F20 finding: once the degree-k leading monomial is discovered, shadow gradients
// for the degree-(k-1) through degree-2 sub-monomials are suppressed by multicollinearity
// — higher-degree terms partially absorb lower-degree structure, so the gradient criterion
// misses them.
//
// New insight: for k-parity predicates, the full polynomial representation is KNOWN by
// construction from the leading monomial's positions {i1,...,ik}:
//   XOR(b_i1,...,b_ik) = Σ_{S⊆{i1..ik}, |S| odd} c_S * Π_{j∈S} b_j
//
// Once the algorithm finds b[i1]*...*b[ik], it can ENUMERATE all C(k,2) degree-2,
// C(k,3) degree-3, ..., C(k,k-1) degree-(k-1) sub-monomials and force-add them all.
//
// This converts the discovery problem from gradient-based to combinatorial for k-parity.
//
// For compound predicates (k2∧k3): NOT k-parity structure. Use degree-3 gradient
// discovery for the lower-degree components, then extend pool at those positions for
// higher-degree cross-terms (this was F18's successful approach).
//
// Algorithm:
//   1. Run dual-stop gradient discovery on degree-5 pool (full)
//   2. Detect if a discovered feature is a high-degree monomial (degree ≥ 2)
//   3. If a degree-k monomial is found with k ≥ 3: force-add ALL C(k,j) sub-monomials
//      for j = 2,...,k-1 at those positions
//   4. Adaptive retrain on the force-augmented feature set

const std = @import("std");

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 3200;
const NTRAIN: usize = NSAMP * 4 / 5;
const NTEST: usize = NSAMP - NTRAIN;

const MAX_FEAT: usize = 80;
const MAX_DISC: usize = 30;
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

fn bestCand(active: *const [NCANDS]bool) struct { k: usize, g: f64, gap: f64 } {
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

// Find the pool index of a feature specified by its bit positions (sorted, up to degree 5)
fn findFeature(positions: []const u8) ?usize {
    for (0..NCANDS) |k| {
        const m = g_meta[k];
        if (m.deg != positions.len) continue;
        const match = switch (m.deg) {
            1 => m.i == positions[0],
            2 => m.i == positions[0] and m.j == positions[1],
            3 => m.i == positions[0] and m.j == positions[1] and m.l == positions[2],
            4 => m.i == positions[0] and m.j == positions[1] and m.l == positions[2] and m.m == positions[3],
            5 => m.i == positions[0] and m.j == positions[1] and m.l == positions[2] and m.m == positions[3] and m.n == positions[4],
            else => false,
        };
        if (match) return k;
    }
    return null;
}

// For a discovered degree-k monomial at positions p[0..k], force-activate all
// degree-2 through degree-(k-1) sub-monomials in the pool.
fn forceSubMonomials(active: *[NCANDS]bool, positions: []const u8, w: anytype) !usize {
    const k = positions.len;
    if (k < 3) return 0; // degree-2 has no sub-monomials to add
    var added: usize = 0;

    // Enumerate all subsets of positions of size 2..k-1
    // Use bitmask over positions[0..k]
    const total_subsets: usize = @as(usize, 1) << @as(u6, @intCast(k));
    for (0..total_subsets) |mask| {
        const pop = @popCount(mask);
        if (pop < 2 or pop >= k) continue; // only degree 2 to k-1

        // Extract the positions in this subset (sorted)
        var sub: [5]u8 = .{0,0,0,0,0};
        var ns: usize = 0;
        for (0..k) |bit_i| {
            if (mask & (@as(usize, 1) << @as(u6, @intCast(bit_i))) != 0) {
                sub[ns] = positions[bit_i]; ns += 1;
            }
        }

        // Sort sub[0..ns] (positions are already in sorted order within `positions`,
        // and we extract in order, so sub is already sorted)
        if (findFeature(sub[0..ns])) |idx| {
            if (!active[idx]) {
                active[idx] = true;
                try w.print("    force-add: sub-monomial of degree {d}\n", .{ns});
                added += 1;
            }
        }
    }
    return added;
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

fn runSubmonomial(w: anytype, name: []const u8) !void {
    try w.print("\n── {s} ──\n", .{name});

    var active = [_]bool{false} ** NCANDS;
    for (0..NDEG1) |k| active[k] = true;

    var disc_buf: [MAX_DISC]usize = undefined;
    var n_disc: usize = 0;

    var deg1: [NDEG1]usize = undefined;
    for (0..NDEG1) |k| deg1[k] = k;
    _ = trainAdaptive(packByList(&deg1), 3000);

    var steps: usize = 0;
    while (steps < MAX_DISC) {
        const best = bestCand(&active);
        if (best.gap < GAP_STOP and best.g < GRAD_MIN) {
            try w.print("  dual-stop (gap={d:.2} |g|={d:.4}) after {d} gradient steps\n",
                .{best.gap, best.g, steps});
            break;
        }
        active[best.k] = true;
        disc_buf[n_disc] = best.k; n_disc += 1;
        steps += 1;

        const m = g_meta[best.k];
        const nm = featStr(best.k);
        try w.print("  step {d:2}: +{s}  |g|={d:.4}  gap={d:.2}x\n",
            .{steps, nm[0..22], best.g, best.gap});

        // Force-add sub-monomials for degree-3+ discoveries
        if (m.deg >= 3) {
            var positions: [5]u8 = .{m.i, m.j, m.l, m.m, m.n};
            const added = try forceSubMonomials(&active, positions[0..m.deg], w);
            if (added > 0) {
                try w.print("    → force-added {d} sub-monomials\n", .{added});
            }
        }

        var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
        for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
        const acc = trainAdaptive(packByList(al[0..na]), 2000);
        try w.print("    retrain ({d} feats): acc={d:.3}\n", .{na, acc});
        if (acc >= TARGET) break;
    }

    var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
    for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
    const acc_final = trainAdaptive(packByList(al[0..na]), 60000);
    const verdict: []const u8 = if (acc_final >= TARGET) "SOLVED" else "FAILED";
    try w.print("  final retrain ({d} feats): acc={d:.4}  {s}\n", .{na, acc_final, verdict});
}

// ─── predicates ───────────────────────────────────────────────────────────────
fn predK2(c: [NCELL]u8) bool {
    return ((if(c[0]>=THRESH)@as(u1,1)else 0)^(if(c[1]>=THRESH)@as(u1,1)else 0))==1;
}
fn predK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..3])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}
fn predK4(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..4])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}
fn predK5(c: [NCELL]u8) bool {
    var p: u1=0; for(c[0..5])|v| p^=if(v>=THRESH)@as(u1,1)else 0; return p==1;
}
fn predK2AndK3(c: [NCELL]u8) bool {
    var p: u1=0; for(c[2..5])|v| p^=if(v>=THRESH)@as(u1,1)else 0;
    return predK2(c) and (p==1);
}
fn predK4rand(c: [NCELL]u8) bool {
    const b1: u1 = if (c[1]>=THRESH) 1 else 0;
    const b3: u1 = if (c[3]>=THRESH) 1 else 0;
    const b4: u1 = if (c[4]>=THRESH) 1 else 0;
    const b5: u1 = if (c[5]>=THRESH) 1 else 0;
    return (b1 ^ b3 ^ b4 ^ b5) == 1;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    initMeta();
    var rng: u64 = 0xF215_BEEF_C0DE_1234;

    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        precomputeAll(g_cells[i], &g_all[i]);
    }

    try stdout.print("SUB-MONOMIAL FORCE-ADD  (Frontier 21)\n", .{});
    try stdout.print("On discovering degree-k monomial: force-add all C(k,2)..C(k,k-1) sub-monomials\n\n", .{});

    for (0..NSAMP) |i| g_labels[i] = predK3(g_cells[i]);
    try runSubmonomial(stdout, "k3-parity (sanity)");

    for (0..NSAMP) |i| g_labels[i] = predK4(g_cells[i]);
    try runSubmonomial(stdout, "k4-parity b[0]⊕b[1]⊕b[2]⊕b[3]");

    for (0..NSAMP) |i| g_labels[i] = predK4rand(g_cells[i]);
    try runSubmonomial(stdout, "k4-parity random b[1]⊕b[3]⊕b[4]⊕b[5]");

    for (0..NSAMP) |i| g_labels[i] = predK5(g_cells[i]);
    try runSubmonomial(stdout, "k5-parity b[0]⊕...⊕b[4]");

    for (0..NSAMP) |i| g_labels[i] = predK2AndK3(g_cells[i]);
    try runSubmonomial(stdout, "k2∧k3 (compound, different positions)");
}
