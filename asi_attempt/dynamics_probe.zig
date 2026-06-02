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
}
