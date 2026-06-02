const std = @import("std");
const hv = @import("hypervector.zig");
const connectome = @import("connectome.zig");
const agent_mod = @import("agent.zig");
const env_mod = @import("environment.zig");

// =============================================================================
// asi_attempt — expressiveness-ceiling probe
//
// The forward model is XOR-affine: it predicts S_next = bind(S_t, rule_a), i.e.
// the current state XORed with a learned per-action offset. bind/permute are
// GF(2)-LINEAR. The project's mixer work already proved an analogous point —
// mul-free champions were all affine maps, so their failure was a theorem, not
// bad luck. The question here: is the agent's WORLD MODEL stuck in the same
// linear basin?
//
// Test (decisive): measure the model's steady-state 1-step prediction error on
//   (1) synthetic XOR-affine dynamics  S_next = bind(S_t, true_offset_a)
//       -> inside the model's representable class; error should collapse to ~0.
//   (2) the battery's real dynamics (grid shifts) -- linear regime.
//   (3) the battery with an added nonlinear (bitwise-AND neighbour) coupling.
// If (1)~0 but (2),(3) stay high, the floors are REPRESENTATIONAL: the model
// can only fit XOR-affine transitions, and real/nonlinear dynamics fall outside
// what bind/permute can express. (3) > (2) shows added nonlinearity costs more.
// =============================================================================

const D_F: f32 = 8192.0;

fn popcountHV(v: hv.Hypervector) u32 {
    const vec: @Vector(hv.Blocks, u64) = v;
    return @reduce(.Add, @as(@Vector(hv.Blocks, u32), @popCount(vec)));
}

// Steady-state prediction error of the agent's forward model under random
// actions on a battery regime (mean over the last fifth of the run).
fn batteryFloor(allocator: std.mem.Allocator, params: env_mod.TaskParams, n: usize, seed: u64) !f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var env = env_mod.Environment.initWith(params);
    var agent = try agent_mod.Agent.init(allocator, rand, .{
        .action_mode = .random, .enable_learning = true, .enable_macros = false, .enable_meta = false,
    }, &env);
    defer agent.deinit();

    const tail = @max(n / 5, 1);
    var sum: f64 = 0;
    var cnt: usize = 0;
    for (0..n) |i| {
        const r = agent.step(&env, rand);
        if (i >= n - tail) {
            sum += r.prediction_error;
            cnt += 1;
        }
    }
    return sum / @as(f64, @floatFromInt(cnt));
}

// Same learning rule, but on synthetic dynamics that ARE XOR-affine:
// S_next = bind(S_t, true_offset_a). The rule should converge to true_offset_a
// (target = bind(S_t, S_next) = bind(S_t, bind(S_t, offset)) = offset, constant),
// driving prediction error to ~0.
fn xorAffineFloor(n: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var offsets: [3]hv.Hypervector = undefined;
    var rules: [3]hv.Hypervector = undefined;
    for (0..3) |a| {
        offsets[a] = hv.initRandom(rand);
        rules[a] = hv.initRandom(rand);
    }
    var s_t = hv.initRandom(rand);

    const alpha: f32 = 0.20;
    const thr: f32 = 0.05;
    const tail = @max(n / 5, 1);
    var sum: f64 = 0;
    var cnt: usize = 0;

    for (0..n) |i| {
        const a = rand.intRangeLessThan(usize, 0, 3);
        const pred = hv.bind(s_t, rules[a]);
        const s_next = hv.bind(s_t, offsets[a]); // true XOR-affine transition
        const err = @as(f32, @floatFromInt(popcountHV(hv.bind(pred, s_next)))) / D_F;

        const target = hv.bind(s_t, s_next);
        if (err > thr) connectome.attractVectorsPtr(rand, &rules[a], &target, alpha);

        if (i >= n - tail) {
            sum += err;
            cnt += 1;
        }
        s_t = s_next;
    }
    return sum / @as(f64, @floatFromInt(cnt));
}

// Pure attraction: connectome.attractVectorsPtr's attraction branch WITHOUT the
// "repulsion if dist < 0.25" forcefield. Used to test whether that forcefield is
// what floors prediction error.
fn attractPure(rand: std.Random, a: *hv.Hypervector, b: *const hv.Hypervector, alpha: f32) void {
    for (0..hv.Blocks) |i| {
        var diff = a[i] ^ b[i];
        var flip: u64 = 0;
        while (diff != 0) {
            const tz = @ctz(diff);
            if (rand.float(f32) < alpha) flip |= (@as(u64, 1) << @as(u6, @intCast(tz)));
            diff &= diff - 1;
        }
        a[i] ^= flip;
    }
}

// XOR-affine dynamics learned with PURE attraction (no repulsion floor).
fn xorAffinePureFloor(n: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var offsets: [3]hv.Hypervector = undefined;
    var rules: [3]hv.Hypervector = undefined;
    for (0..3) |a| {
        offsets[a] = hv.initRandom(rand);
        rules[a] = hv.initRandom(rand);
    }
    var s_t = hv.initRandom(rand);
    const alpha: f32 = 0.20;
    const thr: f32 = 0.05;
    const tail = @max(n / 5, 1);
    var sum: f64 = 0;
    var cnt: usize = 0;
    for (0..n) |i| {
        const a = rand.intRangeLessThan(usize, 0, 3);
        const pred = hv.bind(s_t, rules[a]);
        const s_next = hv.bind(s_t, offsets[a]);
        const err = @as(f32, @floatFromInt(popcountHV(hv.bind(pred, s_next)))) / D_F;
        const target = hv.bind(s_t, s_next);
        if (err > thr) attractPure(rand, &rules[a], &target, alpha);
        if (i >= n - tail) {
            sum += err;
            cnt += 1;
        }
        s_t = s_next;
    }
    return sum / @as(f64, @floatFromInt(cnt));
}

fn meanXorAffinePure(n: usize, seeds: usize) f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| acc += xorAffinePureFloor(n, @as(u64, s) + 1);
    return acc / @as(f64, @floatFromInt(seeds));
}

fn meanBattery(allocator: std.mem.Allocator, params: env_mod.TaskParams, n: usize, seeds: usize) !f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| acc += try batteryFloor(allocator, params, n, @as(u64, s) + 1);
    return acc / @as(f64, @floatFromInt(seeds));
}

fn meanXorAffine(n: usize, seeds: usize) f64 {
    var acc: f64 = 0;
    for (0..seeds) |s| acc += xorAffineFloor(n, @as(u64, s) + 1);
    return acc / @as(f64, @floatFromInt(seeds));
}

// =============================================================================
// Band-readout ceiling (theorem-grade, control-domain analogue of affine_closure).
// Question: can ANY linear/XOR readout of the encoding classify "total mass in
// band"? The encoder XOR-binds all cells into ONE vector, so the grid collapses to
// a PARITY — value structure (random OR ordinal fillers) is destroyed and the SUM
// is unrecoverable. We test the agent's actual readout (nearest-prototype, a
// centroid classifier) and the BEST linear readout (a trained perceptron over the
// 8192 encoding bits), on random vs ordinal encoding, against the out-of-closure
// SUM (perfect by construction).
// =============================================================================
const BandLo: u32 = 16;
const BandHi: u32 = 48;

fn gridMassP(g: [16]u8) u32 {
    var m: u32 = 0;
    for (g) |c| m += c;
    return m;
}

fn randGrid(rand: std.Random) [16]u8 {
    var g: [16]u8 = undefined;
    for (0..16) |i| g[i] = rand.intRangeAtMost(u8, 0, 6); // mass ~ N(48,8): ~balanced about the band
    return g;
}

inline fn bitAt(e: hv.Hypervector, j: usize) u1 {
    return @intCast((e[j / 64] >> @intCast(j % 64)) & 1);
}

// The agent's actual readout: majority-bundle prototypes + nearest (Hamming) class.
fn protoReadoutAcc(allocator: std.mem.Allocator, rand: std.Random, ordinal: bool, n_train: usize, n_test: usize) !f32 {
    const enc = agent_mod.EnvEncoder.init(rand, ordinal);
    var env = env_mod.Environment.initWith(.{});
    const in_counts = try allocator.alloc(u32, hv.D);
    defer allocator.free(in_counts);
    const out_counts = try allocator.alloc(u32, hv.D);
    defer allocator.free(out_counts);
    @memset(in_counts, 0);
    @memset(out_counts, 0);
    var in_n: u32 = 0;
    var out_n: u32 = 0;
    for (0..n_train) |_| {
        const g = randGrid(rand);
        env.grid = g;
        env.failed = false;
        const e = enc.encode(&env);
        const is_in = gridMassP(g) >= BandLo and gridMassP(g) <= BandHi;
        const counts = if (is_in) in_counts else out_counts;
        for (0..hv.D) |j| counts[j] += bitAt(e, j);
        if (is_in) in_n += 1 else out_n += 1;
    }
    var in_proto: hv.Hypervector = [_]u64{0} ** hv.Blocks;
    var out_proto: hv.Hypervector = [_]u64{0} ** hv.Blocks;
    for (0..hv.D) |j| {
        if (in_n > 0 and in_counts[j] * 2 > in_n) in_proto[j / 64] |= (@as(u64, 1) << @intCast(j % 64));
        if (out_n > 0 and out_counts[j] * 2 > out_n) out_proto[j / 64] |= (@as(u64, 1) << @intCast(j % 64));
    }
    var correct: usize = 0;
    for (0..n_test) |_| {
        const g = randGrid(rand);
        env.grid = g;
        env.failed = false;
        const e = enc.encode(&env);
        const is_in = gridMassP(g) >= BandLo and gridMassP(g) <= BandHi;
        const pred_in = hv.hammingDistance(e, in_proto) < hv.hammingDistance(e, out_proto);
        if (pred_in == is_in) correct += 1;
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(n_test));
}

// The BEST linear readout: an online perceptron over the 8192 encoding bits.
fn perceptronAcc(allocator: std.mem.Allocator, rand: std.Random, ordinal: bool, n_train: usize, n_test: usize, epochs: usize) !f32 {
    const enc = agent_mod.EnvEncoder.init(rand, ordinal);
    var env = env_mod.Environment.initWith(.{});
    const w = try allocator.alloc(f32, hv.D);
    defer allocator.free(w);
    @memset(w, 0);
    var b: f32 = 0;
    const lr: f32 = 0.01;
    const X = try allocator.alloc(hv.Hypervector, n_train);
    defer allocator.free(X);
    const Y = try allocator.alloc(f32, n_train);
    defer allocator.free(Y);
    for (0..n_train) |i| {
        const g = randGrid(rand);
        env.grid = g;
        env.failed = false;
        X[i] = enc.encode(&env);
        Y[i] = if (gridMassP(g) >= BandLo and gridMassP(g) <= BandHi) 1.0 else -1.0;
    }
    for (0..epochs) |_| {
        for (0..n_train) |i| {
            var score: f32 = b;
            for (0..hv.D) |j| score += if (bitAt(X[i], j) == 1) w[j] else -w[j];
            const pred: f32 = if (score >= 0) 1.0 else -1.0;
            if (pred != Y[i]) {
                for (0..hv.D) |j| {
                    const x: f32 = if (bitAt(X[i], j) == 1) 1.0 else -1.0;
                    w[j] += lr * Y[i] * x;
                }
                b += lr * Y[i];
            }
        }
    }
    var correct: usize = 0;
    for (0..n_test) |_| {
        const g = randGrid(rand);
        env.grid = g;
        env.failed = false;
        const e = enc.encode(&env);
        var score: f32 = b;
        for (0..hv.D) |j| score += if (bitAt(e, j) == 1) w[j] else -w[j];
        const is_in = gridMassP(g) >= BandLo and gridMassP(g) <= BandHi;
        if ((score >= 0) == is_in) correct += 1;
    }
    return @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(n_test));
}

// =============================================================================
// Construction-level discovery: is the out-of-closure feature (the SUM) recoverable
// from RAW cells with no candidate library and no labels? We collect grids under a
// random policy on the band, form the 16x16 cell covariance, and power-iterate its
// top principal component. If the dynamics move mass coherently (charge/rest shift
// all cells together), the dominant variance direction is ~uniform = the sum. We
// report cosine(top-PC, uniform): ~1 means the sum direction is CONSTRUCTED
// unsupervised, not selected. (Control via the sum then scores 11.02 -- mb_mass.)
// =============================================================================
fn topPCcosineToUniform(samples: usize, seed: u64) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    var env = env_mod.Environment.initWith(.{ .min_mass = 16, .max_mass = 48, .shock_period = 0, .volatility_after = 1_000_000 });
    var sum: [16]f64 = [_]f64{0} ** 16;
    var outer: [16][16]f64 = undefined;
    for (&outer) |*row| row.* = [_]f64{0} ** 16;
    var n: f64 = 0;
    for (0..samples) |_| {
        const a: env_mod.Action = @enumFromInt(rand.intRangeLessThan(usize, 0, 3));
        env.step(a, rand);
        var g: [16]f64 = undefined;
        for (0..16) |i| g[i] = @floatFromInt(env.grid[i]);
        for (0..16) |i| {
            sum[i] += g[i];
            for (0..16) |j| outer[i][j] += g[i] * g[j];
        }
        n += 1;
    }
    var mean: [16]f64 = undefined;
    for (0..16) |i| mean[i] = sum[i] / n;
    var cov: [16][16]f64 = undefined;
    for (0..16) |i| for (0..16) |j| {
        cov[i][j] = outer[i][j] / n - mean[i] * mean[j];
    };
    // Power iteration for the top eigenvector.
    var v: [16]f64 = [_]f64{1.0} ** 16;
    for (0..50) |_| {
        var nv: [16]f64 = [_]f64{0} ** 16;
        for (0..16) |i| for (0..16) |j| {
            nv[i] += cov[i][j] * v[j];
        };
        var norm: f64 = 0;
        for (0..16) |i| norm += nv[i] * nv[i];
        norm = @sqrt(norm);
        if (norm < 1e-12) break;
        for (0..16) |i| v[i] = nv[i] / norm;
    }
    // Cosine to the uniform (all-ones) direction = the sum.
    var dot: f64 = 0;
    var vn: f64 = 0;
    for (0..16) |i| {
        dot += v[i];
        vn += v[i] * v[i];
    }
    const u_norm = @sqrt(@as(f64, 16.0));
    return @abs(dot) / (@sqrt(vn) * u_norm);
}

// =============================================================================
// Hidden-feature discovery (the NON-circular test). The PCA result discovers the
// sum only because the dynamics make the sum the dominant variance axis. Here we
// rig the opposite: the safety feature is a single cell (cell 0), while cells 8-15
// are a high-variance CORRELATED decoy block independent of failure. Now the
// useful feature is NOT salient. We compare three recoverers against the true
// direction e_0 (cosine; 1.0 = recovered, ~0 = missed):
//   PCA (unsupervised variance), supervised one-sided, supervised two-sided band.
// =============================================================================
fn cosToE0(v: [16]f64) f64 {
    var n: f64 = 0;
    for (v) |x| n += x * x;
    if (n < 1e-12) return 0;
    return @abs(v[0]) / @sqrt(n);
}

fn hiddenFeatureRecovery(out: anytype, samples: usize, seed: u64) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const X = try std.heap.page_allocator.alloc([16]f64, samples);
    defer std.heap.page_allocator.free(X);
    const lab1 = try std.heap.page_allocator.alloc(bool, samples); // one-sided
    defer std.heap.page_allocator.free(lab1);
    const lab2 = try std.heap.page_allocator.alloc(bool, samples); // two-sided band
    defer std.heap.page_allocator.free(lab2);
    for (0..samples) |s| {
        var g: [16]f64 = undefined;
        const decoy: f64 = @floatFromInt(r.intRangeAtMost(i32, 0, 40)); // big shared decoy
        g[0] = @floatFromInt(r.intRangeAtMost(i32, 0, 6)); // the signal cell
        for (1..8) |i| g[i] = @floatFromInt(r.intRangeAtMost(i32, 0, 2)); // quiet
        for (8..16) |i| g[i] = decoy + @as(f64, @floatFromInt(r.intRangeAtMost(i32, 0, 2))); // loud decoy block
        X[s] = g;
        lab1[s] = g[0] > 4.0; // one-sided: cell0 too high
        lab2[s] = g[0] < 2.0 or g[0] > 4.0; // two-sided band on cell0
    }
    // PCA: top eigenvector of the 16x16 covariance.
    var mean: [16]f64 = [_]f64{0} ** 16;
    for (X) |g| for (0..16) |i| {
        mean[i] += g[i];
    };
    for (0..16) |i| mean[i] /= @floatFromInt(samples);
    var cov: [16][16]f64 = undefined;
    for (&cov) |*row| row.* = [_]f64{0} ** 16;
    for (X) |g| for (0..16) |i| for (0..16) |j| {
        cov[i][j] += (g[i] - mean[i]) * (g[j] - mean[j]);
    };
    var v: [16]f64 = [_]f64{1.0} ** 16;
    for (0..60) |_| {
        var nv: [16]f64 = [_]f64{0} ** 16;
        for (0..16) |i| for (0..16) |j| {
            nv[i] += cov[i][j] * v[j];
        };
        var nn: f64 = 0;
        for (nv) |x| nn += x * x;
        nn = @sqrt(nn);
        if (nn < 1e-12) break;
        for (0..16) |i| v[i] = nv[i] / nn;
    }
    const pca_cos = cosToE0(v);
    // Supervised direction = mean(fail) - mean(safe), for each labelling.
    const sup = struct {
        fn dir(Xs: [][16]f64, lab: []bool) [16]f64 {
            var mf: [16]f64 = [_]f64{0} ** 16;
            var ms: [16]f64 = [_]f64{0} ** 16;
            var nf: f64 = 0;
            var nsf: f64 = 0;
            for (Xs, lab) |g, f| {
                if (f) {
                    for (0..16) |i| mf[i] += g[i];
                    nf += 1;
                } else {
                    for (0..16) |i| ms[i] += g[i];
                    nsf += 1;
                }
            }
            var d: [16]f64 = undefined;
            for (0..16) |i| d[i] = (if (nf > 0) mf[i] / nf else 0) - (if (nsf > 0) ms[i] / nsf else 0);
            return d;
        }
    };
    const sup1_cos = cosToE0(sup.dir(X, lab1));
    const sup2_cos = cosToE0(sup.dir(X, lab2));
    try out.print("\n=== hidden-feature discovery (non-circular): recover e_0 amid a loud decoy ===\n", .{});
    try out.print("(cosine to the true safety direction; 1.0 = recovered, ~0.25 = chance among 16)\n\n", .{});
    try out.print("  method                       | cosine to true feature\n", .{});
    try out.print("  -----------------------------+-----------------------\n", .{});
    try out.print("  PCA (unsupervised variance)  | {d:.3}\n", .{pca_cos});
    try out.print("  supervised, one-sided        | {d:.3}\n", .{sup1_cos});
    try out.print("  supervised, two-sided band   | {d:.3}\n", .{sup2_cos});
    try out.print("\nReading: PCA is MISLED by the decoy (the earlier sum=top-PC win was circular --\n", .{});
    try out.print("it only worked because the useful feature WAS the dominant variance). Supervised\n", .{});
    try out.print("credit-assignment recovers a non-salient ONE-SIDED feature. But a two-sided BAND\n", .{});
    try out.print("defeats linear supervision too (failures sit on both sides, so mean(fail)~mean(safe)\n", .{});
    try out.print("along e_0): the band predicate is itself out-of-linear-closure. Discovery of a\n", .{});
    try out.print("non-salient, non-monotone feature needs supervised direction-finding COMPOSED with\n", .{});
    try out.print("a nonlinear readout -- neither variance nor linear supervision alone suffices.\n", .{});
}

// =============================================================================
// Item 1 — complete the discovery ladder: supervised + NONLINEAR cracks the band.
// The hidden non-salient TWO-SIDED band defeated PCA (0.000), selection, and linear
// supervision (cosine 0.139). The last rung: does a tiny MLP (supervised + a
// nonlinearity) recover and classify it? It can represent |w.x - c| with two ReLUs.
// =============================================================================
fn sigmoid(z: f64) f64 {
    const zc = @max(@as(f64, -30), @min(@as(f64, 30), z));
    return 1.0 / (1.0 + @exp(-zc));
}

fn mlpVsLinearOnBand(samples: usize, seed: u64) void {
    const NIN = 16;
    const H = 8;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const ntr = samples * 4 / 5;
    // Generate standardized data: cell 0 is the (non-salient) signal; cells 8-15 a
    // loud correlated decoy; label = two-sided band on cell 0.
    var X = std.heap.page_allocator.alloc([NIN]f64, samples) catch return;
    defer std.heap.page_allocator.free(X);
    var Y = std.heap.page_allocator.alloc(f64, samples) catch return;
    defer std.heap.page_allocator.free(Y);
    for (0..samples) |s| {
        var g: [NIN]f64 = undefined;
        const decoy: f64 = @floatFromInt(r.intRangeAtMost(i32, 0, 40));
        g[0] = @floatFromInt(r.intRangeAtMost(i32, 0, 6));
        for (1..8) |i| g[i] = @floatFromInt(r.intRangeAtMost(i32, 0, 2));
        for (8..16) |i| g[i] = decoy + @as(f64, @floatFromInt(r.intRangeAtMost(i32, 0, 2)));
        X[s] = g;
        Y[s] = if (g[0] < 2.0 or g[0] > 4.0) 1.0 else 0.0; // two-sided band on cell 0
    }
    // Standardize features using TRAIN stats.
    var mean: [NIN]f64 = [_]f64{0} ** NIN;
    var sd: [NIN]f64 = [_]f64{0} ** NIN;
    for (0..ntr) |s| for (0..NIN) |i| {
        mean[i] += X[s][i];
    };
    for (0..NIN) |i| mean[i] /= @floatFromInt(ntr);
    for (0..ntr) |s| for (0..NIN) |i| {
        const d = X[s][i] - mean[i];
        sd[i] += d * d;
    };
    for (0..NIN) |i| sd[i] = @max(1e-6, @sqrt(sd[i] / @as(f64, @floatFromInt(ntr))));
    for (0..samples) |s| for (0..NIN) |i| {
        X[s][i] = (X[s][i] - mean[i]) / sd[i];
    };
    // Majority-class baseline on test.
    var pos: f64 = 0;
    for (ntr..samples) |s| pos += Y[s];
    const nte: f64 = @floatFromInt(samples - ntr);
    const majority = @max(pos, nte - pos) / nte;

    // --- Linear logistic regression ---
    var wl: [NIN]f64 = [_]f64{0} ** NIN;
    var bl: f64 = 0;
    const lr: f64 = 0.05;
    for (0..40) |_| for (0..ntr) |s| {
        var z: f64 = bl;
        for (0..NIN) |i| z += wl[i] * X[s][i];
        const e = sigmoid(z) - Y[s];
        for (0..NIN) |i| wl[i] -= lr * e * X[s][i];
        bl -= lr * e;
    };
    var lin_correct: f64 = 0;
    for (ntr..samples) |s| {
        var z: f64 = bl;
        for (0..NIN) |i| z += wl[i] * X[s][i];
        if ((sigmoid(z) > 0.5) == (Y[s] > 0.5)) lin_correct += 1;
    }

    // --- Tiny MLP: 16 -> 8 ReLU -> 1 sigmoid ---
    var W1: [H][NIN]f64 = undefined;
    var b1: [H]f64 = [_]f64{0} ** H;
    var W2: [H]f64 = undefined;
    var b2: f64 = 0;
    for (0..H) |h| {
        W2[h] = (r.float(f64) - 0.5) * 0.5;
        for (0..NIN) |i| W1[h][i] = (r.float(f64) - 0.5) * 0.5;
    }
    for (0..120) |_| for (0..ntr) |s| {
        var a1: [H]f64 = undefined;
        var z1: [H]f64 = undefined;
        var z2: f64 = b2;
        for (0..H) |h| {
            var z: f64 = b1[h];
            for (0..NIN) |i| z += W1[h][i] * X[s][i];
            z1[h] = z;
            a1[h] = if (z > 0) z else 0;
            z2 += W2[h] * a1[h];
        }
        const e = sigmoid(z2) - Y[s];
        for (0..H) |h| {
            const d1 = e * W2[h] * (if (z1[h] > 0) @as(f64, 1) else 0);
            W2[h] -= lr * e * a1[h];
            for (0..NIN) |i| W1[h][i] -= lr * d1 * X[s][i];
            b1[h] -= lr * d1;
        }
        b2 -= lr * e;
    };
    var mlp_correct: f64 = 0;
    for (ntr..samples) |s| {
        var z2: f64 = b2;
        for (0..H) |h| {
            var z: f64 = b1[h];
            for (0..NIN) |i| z += W1[h][i] * X[s][i];
            z2 += W2[h] * (if (z > 0) z else 0);
        }
        if ((sigmoid(z2) > 0.5) == (Y[s] > 0.5)) mlp_correct += 1;
    }
    // How much of the MLP's input weight mass lands on cell 0 (the true feature)?
    var w0: f64 = 0;
    var wtot: f64 = 0;
    for (0..H) |h| for (0..NIN) |i| {
        const a = @abs(W1[h][i]);
        wtot += a;
        if (i == 0) w0 += a;
    };
    std.debug.print("\n=== Item 1: supervised + NONLINEAR cracks the hidden two-sided band ===\n", .{});
    std.debug.print("(same non-salient task that gave PCA 0.000, linear-supervised cosine 0.139)\n\n", .{});
    std.debug.print("  classifier                    | test accuracy\n", .{});
    std.debug.print("  ------------------------------+--------------\n", .{});
    std.debug.print("  majority-class baseline       |    {d:.3}\n", .{majority});
    std.debug.print("  linear logistic regression    |    {d:.3}\n", .{lin_correct / nte});
    std.debug.print("  tiny MLP (16->8 ReLU->1)      |    {d:.3}\n", .{mlp_correct / nte});
    std.debug.print("  -> MLP input-weight mass on the true cell 0: {d:.1}% (random would be {d:.1}%)\n", .{ w0 / wtot * 100.0, 100.0 / @as(f64, NIN) });
    std.debug.print("\nReading: the linear classifier is stuck near the majority baseline (the band is a\n", .{});
    std.debug.print("slab -- out of linear closure). The MLP, supervision COMPOSED with a nonlinearity,\n", .{});
    std.debug.print("cracks it and concentrates its weight on the hidden cell. This is the last rung of\n", .{});
    std.debug.print("the discovery ladder -- and the honest bound: it is a small net doing small-net\n", .{});
    std.debug.print("things, the textbook escape, not a new mechanism. See docs/research/feature_discovery.md.\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var n: usize = 8000;
    var seeds: usize = 8;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    if (args.next()) |a| n = std.fmt.parseInt(usize, a, 10) catch n;
    if (args.next()) |a| seeds = std.fmt.parseInt(usize, a, 10) catch seeds;

    std.debug.print("=== expressiveness ceiling: forward-model prediction error ===\n", .{});
    std.debug.print("({d} steps x {d} seeds, mean over final 1/5; lower = model fits the dynamics)\n\n", .{ n, seeds });

    const xor_affine = meanXorAffine(n, seeds);
    const xor_affine_pure = meanXorAffinePure(n, seeds);
    const battery_linear = try meanBattery(allocator, .{}, n, seeds);
    const battery_nonlinear = try meanBattery(allocator, .{ .nonlinear = true }, n, seeds);

    std.debug.print("  dynamics                    | steady-state pred error\n", .{});
    std.debug.print("  ----------------------------+------------------------\n", .{});
    std.debug.print("  xor_affine (stock rule)     | {d:.4}\n", .{xor_affine});
    std.debug.print("  xor_affine (pure attraction)| {d:.4}\n", .{xor_affine_pure});
    std.debug.print("  battery_linear (stock rule) | {d:.4}\n", .{battery_linear});
    std.debug.print("  battery_nonlinear           | {d:.4}\n", .{battery_nonlinear});
    std.debug.print("\nReading: the stock learning rule (attractVectorsPtr) repels any two vectors\n", .{});
    std.debug.print("within 0.25, so it CANNOT drive prediction error below ~0.25 even on perfectly\n", .{});
    std.debug.print("representable XOR-affine dynamics. Removing that repulsion (pure attraction)\n", .{});
    std.debug.print("collapses the affine error toward 0 -> the dominant ceiling is the LEARNING\n", .{});
    std.debug.print("RULE, not GF(2) expressiveness. The battery floor sits above the affine one,\n", .{});
    std.debug.print("a smaller, secondary representational gap (nonlinear >= linear).\n", .{});

    // --- Band-readout ceiling (the control-domain closure witness) ---
    var prng2 = std.Random.DefaultPrng.init(99);
    const r2 = prng2.random();
    const proto_rand = try protoReadoutAcc(allocator, r2, false, 4000, 4000);
    const proto_ord = try protoReadoutAcc(allocator, r2, true, 4000, 4000);
    const perc_rand = try perceptronAcc(allocator, r2, false, 2000, 2000, 5);
    const perc_ord = try perceptronAcc(allocator, r2, true, 2000, 2000, 5);
    std.debug.print("\n=== band-readout ceiling: can a linear/XOR readout see total mass? ===\n", .{});
    std.debug.print("(classify 'mass in [16,48]' from the encoding; chance ~ 0.50, balanced)\n\n", .{});
    std.debug.print("  readout                          | random enc | ordinal enc\n", .{});
    std.debug.print("  ---------------------------------+------------+------------\n", .{});
    std.debug.print("  nearest-prototype (agent readout)|   {d:.3}    |   {d:.3}\n", .{ proto_rand, proto_ord });
    std.debug.print("  best linear (perceptron, 8192b)  |   {d:.3}    |   {d:.3}\n", .{ perc_rand, perc_ord });
    std.debug.print("  sum-threshold (out-of-closure)   |   1.000    |   1.000   (perfect by construction)\n", .{});
    std.debug.print("\nReading: the encoder XOR-binds all cells into one vector, so the grid collapses\n", .{});
    std.debug.print("to a PARITY and total mass (a SUM) is unrecoverable by any linear/XOR readout --\n", .{});
    std.debug.print("random AND ordinal fillers both ~chance. The band predicate is OUTSIDE the closure\n", .{});
    std.debug.print("of the substrate; only the explicit SUM feature (mb_mass) reads it. This is the\n", .{});
    std.debug.print("control-domain analogue of affine_closure -- a representational impossibility,\n", .{});
    std.debug.print("not a tuning failure. See docs/research/closure_escape_control.md.\n", .{});

    // --- Construction-level discovery: PCA recovers the sum direction ---
    var cos_acc: f64 = 0;
    const pca_seeds: usize = 6;
    for (0..pca_seeds) |s| cos_acc += topPCcosineToUniform(8000, @as(u64, s) + 1);
    const cos_mean = cos_acc / @as(f64, @floatFromInt(pca_seeds));
    std.debug.print("\n=== construction-level discovery: top principal component vs the SUM ===\n", .{});
    std.debug.print("cosine(top-PC of raw-cell covariance, uniform/sum direction) = {d:.4}\n", .{cos_mean});
    std.debug.print("(mean over {d} seeds x 8000 random-policy band steps; 1.0 = the sum direction)\n", .{pca_seeds});
    std.debug.print("\nReading: with NO candidate library and NO labels, the dominant variance direction\n", .{});
    std.debug.print("of the raw cells is ~uniform -- the SUM -- because charge/rest move all cells\n", .{});
    std.debug.print("together. The out-of-closure feature is CONSTRUCTED unsupervised, not just\n", .{});
    std.debug.print("selected. Control via it scores 11.02 (mb_mass). See docs/research/feature_discovery.md.\n", .{});

    try hiddenFeatureRecovery(std.io.getStdErr().writer(), 20000, 7);
    mlpVsLinearOnBand(20000, 7);
}
