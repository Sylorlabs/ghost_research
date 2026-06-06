// Frontier 22 — Newton's Method for Logistic Regression
//
// F21 leaves k5-parity at 0.9125 with all 31 needed features present.
// Root cause: gradient descent needs exponentially more iterations as the
// required coefficient ratio grows (k5: 16:-8:4:-2:1 ≈ 32x range).
//
// Newton's method (second-order optimization) converges quadratically.
// Each step solves: w ← w - H^{-1} g  where H = X^T diag(p(1-p)) X
// For logistic regression this is the exact IRLS (Iteratively Reweighted
// Least Squares) update and converges in O(log log ε) steps.
//
// With 32 features and 2560 training samples, H is 32×32 — small enough
// to invert directly via Gaussian elimination.

const std = @import("std");
const math = std.math;

const NCELL: usize = 6;
const VMAX: usize = 8;
const THRESH: usize = 4;
const NSAMP: usize = 3200;
const NTRAIN: usize = NSAMP * 4 / 5;
const NTEST: usize = NSAMP - NTRAIN;

const MAX_FEAT: usize = 80;
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

// Gaussian elimination on a square matrix (in-place, returns false if singular)
// Solves A x = b, stores result in b
fn gaussSolve(comptime N: usize, A: *[N][N]f64, b: *[N]f64) bool {
    for (0..N) |col| {
        // Find pivot
        var pivot_row = col;
        var max_val = @abs(A[col][col]);
        for (col+1..N) |row| {
            const v = @abs(A[row][col]);
            if (v > max_val) { max_val = v; pivot_row = row; }
        }
        if (max_val < 1e-14) return false;
        // Swap rows
        if (pivot_row != col) {
            const tmp_row = A[col];
            A[col] = A[pivot_row];
            A[pivot_row] = tmp_row;
            const tmp_b = b[col];
            b[col] = b[pivot_row];
            b[pivot_row] = tmp_b;
        }
        // Eliminate below
        const inv_pivot = 1.0 / A[col][col];
        for (col+1..N) |row| {
            const factor = A[row][col] * inv_pivot;
            for (col..N) |c| A[row][c] -= factor * A[col][c];
            b[row] -= factor * b[col];
        }
    }
    // Back-substitute
    var r: usize = N;
    while (r > 0) {
        r -= 1;
        var s = b[r];
        for (r+1..N) |c| s -= A[r][c] * b[c];
        b[r] = s / A[r][r];
    }
    return true;
}

// Newton's method (IRLS) for logistic regression.
// nfeat features packed in g_feat[i][0..nfeat].
// Returns accuracy. Also fills g_err for shadow gradient computation.
fn trainNewton(nfeat: usize, max_iter: usize) f64 {
    // We include a bias term by treating it as feature index nfeat
    // (constant 1.0). Total params = nfeat + 1.
    const NP: usize = MAX_FEAT + 1;
    var w = [_]f64{0.0} ** NP;
    const np = nfeat + 1; // actual number of params

    for (0..max_iter) |_| {
        // Gradient: g[j] = Σ_i (p_i - y_i) * x_ij  (j=0..nfeat, x_i[nfeat]=1 for bias)
        var grad = [_]f64{0.0} ** NP;
        // Hessian: H[j][k] = Σ_i p_i(1-p_i) * x_ij * x_ik
        var H: [NP][NP]f64 = [_][NP]f64{[_]f64{0.0}**NP}**NP;

        var max_grad: f64 = 0;
        for (0..NTRAIN) |i| {
            var logit = w[nfeat]; // bias
            for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
            const p = sigmoid(logit);
            const e = p - if (g_labels[i]) @as(f64,1.0) else 0.0;
            const hess_w = p * (1.0 - p); // IRLS weight

            for (0..nfeat) |j| {
                grad[j] += e * g_feat[i][j];
                for (0..nfeat) |k| H[j][k] += hess_w * g_feat[i][j] * g_feat[i][k];
                H[j][nfeat] += hess_w * g_feat[i][j];
                H[nfeat][j] += hess_w * g_feat[i][j];
            }
            grad[nfeat] += e;
            H[nfeat][nfeat] += hess_w;
        }

        // Normalize by N
        const n: f64 = @floatFromInt(NTRAIN);
        for (0..np) |j| {
            grad[j] /= n;
            for (0..np) |k| H[j][k] /= n;
        }

        // Check convergence on gradient magnitude
        for (0..np) |j| max_grad = @max(max_grad, @abs(grad[j]));
        if (max_grad < 1e-8) break;

        // Solve H Δw = grad, then w ← w - Δw
        // Need fixed-size arrays for gaussSolve — use dynamic approach with np
        // Since np ≤ MAX_FEAT+1 = 81, handle up to 81 params
        // Simple: extract np×np submatrix, solve, update
        var H_sub: [NP][NP]f64 = H;
        var delta = grad;
        // Zero out irrelevant rows/cols
        for (np..NP) |j| {
            for (0..NP) |k| { H_sub[j][k]=0; H_sub[k][j]=0; }
            H_sub[j][j] = 1;
            delta[j] = 0;
        }
        _ = gaussSolve(NP, &H_sub, &delta);
        for (0..np) |j| w[j] -= delta[j];
    }

    // Fill g_err for shadow gradient computation (on training set)
    for (0..NTRAIN) |i| {
        var logit = w[nfeat];
        for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
        g_err[i] = sigmoid(logit) - if (g_labels[i]) @as(f64,1.0) else 0.0;
    }

    var ok: usize = 0;
    for (NTRAIN..NSAMP) |i| {
        var logit = w[nfeat];
        for (0..nfeat) |j| logit += w[j]*g_feat[i][j];
        if ((logit >= 0.0) == g_labels[i]) ok += 1;
    }
    const raw = @as(f64,@floatFromInt(ok))/@as(f64,@floatFromInt(NTEST));
    return @max(raw, 1.0-raw);
}

fn trainAdaptive(nfeat: usize, max_steps: usize) f64 {
    var w = [_]f64{0.0} ** MAX_FEAT;
    var b: f64 = 0.0;
    var lr: f64 = 0.05;
    var best_loss: f64 = 1e18;
    var no_improve: usize = 0;
    var total: usize = 0;
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
        if (total % 500 == 0) {
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

fn featMask(k: usize) u8 {
    const m = g_meta[k];
    var mask: u8 = @as(u8,1)<<@as(u3,@intCast(m.i));
    if (m.deg >= 2) mask |= @as(u8,1)<<@as(u3,@intCast(m.j));
    if (m.deg >= 3) mask |= @as(u8,1)<<@as(u3,@intCast(m.l));
    if (m.deg >= 4) mask |= @as(u8,1)<<@as(u3,@intCast(m.m));
    if (m.deg >= 5) mask |= @as(u8,1)<<@as(u3,@intCast(m.n));
    return mask;
}

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

fn forceSubMonomials(active: *[NCANDS]bool, positions: []const u8) usize {
    const k = positions.len;
    if (k < 3) return 0;
    var added: usize = 0;
    const total_subsets: usize = @as(usize, 1) << @as(u6, @intCast(k));
    for (0..total_subsets) |mask| {
        const pop = @popCount(mask);
        if (pop < 2 or pop >= k) continue;
        var sub: [5]u8 = .{0,0,0,0,0};
        var ns: usize = 0;
        for (0..k) |bit_i| {
            if (mask & (@as(usize, 1) << @as(u6, @intCast(bit_i))) != 0) {
                sub[ns] = positions[bit_i]; ns += 1;
            }
        }
        if (findFeature(sub[0..ns])) |idx| {
            if (!active[idx]) { active[idx] = true; added += 1; }
        }
    }
    return added;
}

// Run full pipeline with specified solver for phase 2
fn runPipeline(w: anytype, name: []const u8, use_newton: bool) !void {
    try w.print("\n── {s} ──\n", .{name});

    var active = [_]bool{false} ** NCANDS;
    for (0..NDEG1) |k| active[k] = true;
    var disc_buf: [40]usize = undefined;
    var n_disc: usize = 0;

    var deg1: [NDEG1]usize = undefined;
    for (0..NDEG1) |k| deg1[k] = k;
    _ = trainAdaptive(packByList(&deg1), 3000);

    var steps: usize = 0;
    while (steps < 30) {
        const best = bestCand(&active);
        if (best.gap < GAP_STOP and best.g < GRAD_MIN) break;
        active[best.k] = true;
        disc_buf[n_disc] = best.k; n_disc += 1;
        steps += 1;

        const m = g_meta[best.k];
        if (m.deg >= 3) {
            var positions: [5]u8 = .{m.i, m.j, m.l, m.m, m.n};
            _ = forceSubMonomials(&active, positions[0..m.deg]);
        }

        var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
        for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
        _ = trainAdaptive(packByList(al[0..na]), 2000);
    }

    var al: [MAX_FEAT]usize = undefined; var na: usize = 0;
    for (0..NCANDS) |k| if (active[k]) { al[na]=k; na+=1; };
    const nf = packByList(al[0..na]);

    const acc_final = if (use_newton)
        trainNewton(nf, 30)  // Newton converges in ≪ 30 steps
    else
        trainAdaptive(nf, 100000);

    const verdict: []const u8 = if (acc_final >= TARGET) "SOLVED" else "FAILED";
    const solver_str: []const u8 = if (use_newton) "Newton" else "AdaptGD";
    try w.print("  {s}: {d} feats → acc={d:.4}  {s}\n", .{solver_str, na, acc_final, verdict});
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
    initMeta();
    var rng: u64 = 0xF22BEEFDEAD1234;

    for (0..NSAMP) |i| {
        for (&g_cells[i]) |*v| v.* = @intCast(lcg(&rng) % VMAX);
        precomputeAll(g_cells[i], &g_all[i]);
    }

    try stdout.print("NEWTON SOLVER  (Frontier 22)\n", .{});
    try stdout.print("Sub-monomial force-add discovery + Newton IRLS vs adaptive GD\n\n", .{});

    try stdout.print("NEWTON (IRLS, ≤30 iterations):\n", .{});
    for (0..NSAMP) |i| g_labels[i] = predK3(g_cells[i]);
    try runPipeline(stdout, "k3-parity", true);
    for (0..NSAMP) |i| g_labels[i] = predK4(g_cells[i]);
    try runPipeline(stdout, "k4-parity", true);
    for (0..NSAMP) |i| g_labels[i] = predK5(g_cells[i]);
    try runPipeline(stdout, "k5-parity", true);
    for (0..NSAMP) |i| g_labels[i] = predK2AndK3(g_cells[i]);
    try runPipeline(stdout, "k2∧k3", true);

    try stdout.print("\nADAPTIVE GD (100k steps) for comparison:\n", .{});
    for (0..NSAMP) |i| g_labels[i] = predK3(g_cells[i]);
    try runPipeline(stdout, "k3-parity", false);
    for (0..NSAMP) |i| g_labels[i] = predK4(g_cells[i]);
    try runPipeline(stdout, "k4-parity", false);
    for (0..NSAMP) |i| g_labels[i] = predK5(g_cells[i]);
    try runPipeline(stdout, "k5-parity", false);
    for (0..NSAMP) |i| g_labels[i] = predK2AndK3(g_cells[i]);
    try runPipeline(stdout, "k2∧k3", false);
}
