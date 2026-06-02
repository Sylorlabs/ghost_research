const std = @import("std");
const testing = std.testing;
const hv = @import("hypervector.zig");
const connectome = @import("connectome.zig");
const agent_mod = @import("agent.zig");
const env_mod = @import("environment.zig");

fn majorityBundle(vs: []const hv.Hypervector) hv.Hypervector {
    var proto: hv.Hypervector = [_]u64{0} ** hv.Blocks;
    const n: u32 = @intCast(vs.len);
    for (0..hv.Blocks) |b| {
        for (0..64) |bit| {
            var count: u32 = 0;
            const one = @as(u64, 1) << @intCast(bit);
            for (vs) |v| {
                if (v[b] & one != 0) count += 1;
            }
            if (count * 2 > n) proto[b] |= one;
        }
    }
    return proto;
}

test "bind is its own inverse (XOR algebra)" {
    var prng = std.Random.DefaultPrng.init(1);
    const a = hv.initRandom(prng.random());
    const b = hv.initRandom(prng.random());
    const round_trip = hv.bind(hv.bind(a, b), b);
    try testing.expect(hv.hammingDistance(a, round_trip) == 0.0);
}

test "random hypervectors are ~orthogonal (~0.5 normalized Hamming)" {
    var prng = std.Random.DefaultPrng.init(7);
    const a = hv.initRandom(prng.random());
    const b = hv.initRandom(prng.random());
    const d = hv.hammingDistance(a, b);
    try testing.expect(d > 0.45 and d < 0.55);
}

test "bind destroys similarity: a bound vector is far from its inputs" {
    // This is WHY the failure bit cannot be read from the XOR-encoded state.
    var prng = std.Random.DefaultPrng.init(11);
    const a = hv.initRandom(prng.random());
    const b = hv.initRandom(prng.random());
    const bound = hv.bind(a, b);
    try testing.expect(hv.hammingDistance(bound, a) > 0.45);
    try testing.expect(hv.hammingDistance(bound, b) > 0.45);
}

test "the readable channel is RECURRING GRID STRUCTURE, not the failure bit" {
    // A first version of this test modelled each state as bind(independent_noise,
    // fail_filler) and asserted the failure filler was recoverable. It FAILED —
    // correctly. Because state = G XOR fail_val and majority commutes with a
    // constant XOR, the fail_val term cancels in the distance and contributes
    // nothing; with independent G, majority(G) washes out and readout is a coin
    // flip. The instrument refuted the "read the failure bit" story.
    //
    // The mechanism that actually works: under control the cell sits at ONE
    // dominant recurring grid (all-zeros), so G repeats and the majority prototype
    // locks onto it. A second subtlety the first attempt missed: bitwise majority
    // over a near-50/50 mix of two states snaps entirely to the more frequent one,
    // so the safe attractor must be the DOMINANT mode (here ~70% pure all-zeros,
    // with occasional small perturbations) for it to be captured. This uses the
    // real encoder; fail = high-mass short-circuited grids.
    var prng = std.Random.DefaultPrng.init(23);
    const rand = prng.random();
    const enc = agent_mod.EnvEncoder.init(rand);

    const N = 64;
    var safe: [N]hv.Hypervector = undefined;
    var fail: [N]hv.Hypervector = undefined;
    for (0..N) |i| {
        var se = env_mod.Environment.init(); // the all-zeros safe attractor...
        if (rand.float(f32) < 0.3) se.grid[rand.intRangeLessThan(usize, 0, 16)] = 1; // ...with rare drift
        se.failed = false;
        safe[i] = enc.encode(&se);

        var fe = env_mod.Environment.init(); // high mass, a short-circuited cell
        fe.grid[rand.intRangeLessThan(usize, 0, 16)] = rand.intRangeLessThan(u8, 5, 9);
        fe.grid[rand.intRangeLessThan(usize, 0, 16)] = rand.intRangeLessThan(u8, 5, 9);
        fe.failed = true;
        fail[i] = enc.encode(&fe);
    }
    const safe_proto = majorityBundle(&safe);
    const fail_proto = majorityBundle(&fail);

    var fresh = env_mod.Environment.init();
    fresh.failed = false; // a fresh low-mass safe state
    const fresh_enc = enc.encode(&fresh);
    const d_safe = hv.hammingDistance(fresh_enc, safe_proto);
    const d_fail = hv.hammingDistance(fresh_enc, fail_proto);
    try testing.expect(d_safe < d_fail);
}

test "VSA role-binding recovers the object above chance" {
    // bindRule packs (subject, action, object) into one vector; traceInference
    // reads the object back out. The recovery is noisy (lossy majority bundle)
    // but must land closer to the true object than to an unrelated distractor.
    var prng = std.Random.DefaultPrng.init(41);
    const rand = prng.random();
    var matrix = connectome.MemoryMatrix.init(testing.allocator);
    defer matrix.deinit();

    const subject = hv.initRandom(rand);
    const action = hv.initRandom(rand);
    const object = hv.initRandom(rand);
    const distractor = hv.initRandom(rand);

    const rule = connectome.bindRule(&matrix, subject, action, object);
    const recovered = connectome.traceInference(&matrix, subject, rule);

    const d_obj = hv.hammingDistance(recovered, object);
    const d_rand = hv.hammingDistance(recovered, distractor);
    try testing.expect(d_obj < d_rand);
}

test "attractVectorsPtr moves a vector toward its target" {
    var prng = std.Random.DefaultPrng.init(31);
    const rand = prng.random();
    var a = hv.initRandom(rand);
    const b = hv.initRandom(rand);
    const before = hv.hammingDistance(a, b);
    // Several attraction passes should reduce distance (until the repulsion floor).
    for (0..20) |_| connectome.attractVectorsPtr(rand, &a, &b, 0.30);
    const after = hv.hammingDistance(a, b);
    try testing.expect(after < before);
}
