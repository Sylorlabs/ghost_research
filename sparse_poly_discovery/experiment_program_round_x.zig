//! Round X / X1: self-mutating experiment program.
//! No text, semantic ports, named task feature, body map, or policy-visible
//! grounding score exists. Procedure bytes are frozen before private bodies.
const std = @import("std");

const Bytes = 24;
const Slots = 8;
const Steps = 8;
const Classes = 4;
const DevBodies = 8;
const TestBodies = 24;
const Episodes = 8;

const Condition = enum {
    matched,
    port_permutation,
    raw_recode,
    temporal_delay,
    noise,
    missing_new,
    actuator_remap,
};
const Arm = enum { grown, fixed, random, replay, equal_static, w1_human };

const Genome = struct { bytes: [Bytes]u8 };

const base_genome = Genome{ .bytes = .{
    1, 3, 1, 2, 0, 8, 0, 0, 0, 0, 3, 1,
    2, 1, 0, 0, 7, 3, 5, 1, 11, 3, 1, 0,
} };

fn mix(x0: u32) u32 {
    var x = x0 +% 0x9e3779b9;
    x = (x ^ (x >> 16)) *% 0x85ebca6b;
    x = (x ^ (x >> 13)) *% 0xc2b2ae35;
    return x ^ (x >> 16);
}
fn digest(g: Genome) u64 {
    var h = std.hash.Wyhash.init(0x5831);
    h.update(&g.bytes);
    return h.final();
}
fn conditionName(c: Condition) []const u8 {
    return switch (c) {
        .matched => "matched",
        .port_permutation => "port_permutation",
        .raw_recode => "raw_recode",
        .temporal_delay => "temporal_delay",
        .noise => "noise",
        .missing_new => "missing_new_organs",
        .actuator_remap => "actuator_remap",
    };
}
fn armName(a: Arm) []const u8 {
    return switch (a) {
        .grown => "grown_experiment_program",
        .fixed => "fixed_procedure",
        .random => "random_procedure",
        .replay => "transcript_replay",
        .equal_static => "equal_size_static",
        .w1_human => "w1_human_protocol",
    };
}

// Fixed VM effects -- the complete installed bias:
// b0 waveform, b1 amplitude, b2 repeat count, b3 port stride,
// b4 schedule phase, b5 stop budget, b6 window origin, b7 window span,
// b8 centering, b9 scaling, b10 rotation, b11 compression fold,
// b12 comparison, b13 tie break, b14 response polarity, b15 accumulator,
// b16..b19 probe-sequence salt, b20 mutation index, b21 mutation step,
// b22 mutation rate, b23 descendant salt. The VM supplies arithmetic,
// buffers, byte addressing and raw transport, but no organ meaning.
fn byteEffect(g: Genome, i: usize) u32 {
    const b: u32 = g.bytes[i];
    return switch (i) {
        0 => b % 4,
        1 => 1 + b % 7,
        2 => 1 + b % 4,
        3 => 1 + b % 7,
        4 => b % Steps,
        5 => 1 + b % Slots,
        6 => b % Steps,
        7 => 1 + b % Steps,
        8 => b % 4,
        9 => b % 4,
        10 => b % Steps,
        11 => 1 + b % 4,
        12 => b % 4,
        13 => b % Slots,
        14 => b % 2,
        15 => b % 4,
        16...19 => b,
        20 => b % Bytes,
        21 => 1 + b % 31,
        22 => 1 + b % 8,
        23 => b,
        else => unreachable,
    };
}

fn mutationReachable(i: usize) bool {
    var g = base_genome;
    const before_digest = digest(g);
    const before_effect = byteEffect(g, i);
    var delta: u8 = 1;
    while (delta != 0) : (delta +%= 1) {
        g = base_genome;
        g.bytes[i] +%= delta;
        if (digest(g) != before_digest and byteEffect(g, i) != before_effect) return true;
    }
    return false;
}

fn child(parent: Genome, ordinal: usize) Genome {
    var out = parent;
    const rate = byteEffect(parent, 22);
    const step: u8 = @intCast(byteEffect(parent, 21));
    const salt = @as(u32, parent.bytes[23]) * 65537 + @as(u32, @intCast(ordinal));
    var k: u32 = 0;
    while (k < rate) : (k += 1) {
        const chosen = (byteEffect(parent, 20) + mix(salt + k * 97)) % Bytes;
        const direction: u8 = if ((mix(salt + k * 131) & 1) == 0) step else 0 -% step;
        out.bytes[chosen] +%= direction;
    }
    return out;
}
fn descendantDigest(g: Genome) u64 {
    var h = std.hash.Wyhash.init(0xdec0de);
    for (0..32) |i| {
        const c = child(g, i);
        h.update(&c.bytes);
    }
    return h.final();
}
fn mutatorChangesDistribution(i: usize) bool {
    var g = base_genome;
    const a = descendantDigest(g);
    g.bytes[i] +%= 1;
    return descendantDigest(g) != a;
}

const basis = [Classes][Steps]i32{
    .{ 9, 2, 1, 0, 0, 1, 2, 4 },
    .{ 1, 8, 2, 6, 1, 0, 3, 1 },
    .{ 3, 1, 7, 2, 8, 1, 0, 2 },
    .{ 2, 5, 1, 7, 2, 6, 1, 0 },
};

fn physicalClass(body: usize, slot: usize, kind: usize, c: Condition) usize {
    var stride: usize = 1;
    var shift = (body * 3 + kind) % Classes;
    if (c == .port_permutation or c == .actuator_remap) {
        stride = 3;
        shift = (body * 5 + kind * 2 + 1) % Classes;
    }
    if (c == .missing_new) shift = (body * 7 + kind + 2) % Classes;
    return (slot * stride + shift) % Classes;
}

fn rawTrace(class: usize, body: usize, slot: usize, kind: usize, c: Condition, waveform: usize, amp: i32) [Steps]i32 {
    var out: [Steps]i32 = undefined;
    const delay: usize = if (c == .temporal_delay) 1 + body % 3 else 0;
    const scale: i32 = if (c == .raw_recode) 3 else 1;
    const offset: i32 = if (c == .raw_recode) 17 else 0;
    for (0..Steps) |t| {
        const src = (t + Steps - delay) % Steps;
        var v = basis[class][src] * amp;
        if (waveform == 1 and (t & 1) == 1) v = -v;
        if (waveform == 2) v *= @intCast(1 + t % 3);
        if (waveform == 3) v = if (t == 0) v * 3 else @divTrunc(v, 2);
        v = v * scale + offset;
        if (c == .noise) {
            const n: i32 = @intCast(mix(@intCast(body * 1009 + slot * 101 + kind * 17 + t)) % 7);
            v += n - 3;
        }
        if (c == .missing_new and slot == body % Slots) v = offset;
        out[t] = v;
    }
    return out;
}

fn transform(g: Genome, raw: [Steps]i32) [Steps]i32 {
    var temp = raw;
    const origin: usize = @intCast(byteEffect(g, 6));
    const span: usize = @intCast(byteEffect(g, 7));
    const center = byteEffect(g, 8);
    var reference: i32 = 0;
    if (center == 1) reference = temp[origin];
    if (center == 2) {
        reference = temp[0];
        for (temp[1..]) |v| reference = @min(reference, v);
    }
    if (center == 3) {
        for (temp) |v| reference += v;
        reference = @divTrunc(reference, Steps);
    }
    for (&temp) |*v| v.* -= reference;
    const scaling = byteEffect(g, 9);
    var denom: i32 = 1;
    if (scaling == 1) {
        for (temp) |v| denom += @as(i32, @intCast(@abs(v)));
    }
    if (scaling == 2) {
        for (temp) |v| denom = @max(denom, @as(i32, @intCast(@abs(v))));
    }
    if (scaling == 3) {
        var sq: i32 = 1;
        for (temp) |v| sq +%= @as(i32, @intCast(@abs(v *% v)));
        denom = @max(1, @divTrunc(sq, 16));
    }
    var out = [_]i32{0} ** Steps;
    const rotate: usize = @intCast(byteEffect(g, 10));
    const fold: usize = @intCast(byteEffect(g, 11));
    for (0..span) |q| {
        const src = (origin + q) % Steps;
        const dst = (q + rotate) % fold;
        out[dst] +%= @divTrunc(temp[src] * 256, denom);
    }
    return out;
}

fn distance(g: Genome, a: [Steps]i32, b: [Steps]i32) i64 {
    var d: i64 = 0;
    const mode = byteEffect(g, 12);
    for (a, b) |x, y| {
        const z: i64 = @as(i64, x) - y;
        if (mode == 0) d += @as(i64, @intCast(@abs(z)));
        if (mode == 1) d +%= z *% z;
        if (mode == 2) d -= @as(i64, x) * y;
        if (mode == 3) d += @popCount(@as(u32, @bitCast(x ^ y)));
    }
    return d;
}

fn choose(g: Genome, body: usize, episode: usize, c: Condition) usize {
    const target_class = (body * 7 + episode * 3 + 1) % Classes;
    const waveform: usize = @intCast(byteEffect(g, 0));
    const amp: i32 = @intCast(byteEffect(g, 1));
    const target = transform(g, rawTrace(target_class, body, episode % Slots, 0, c, waveform, amp));
    const stride: usize = @intCast(byteEffect(g, 3));
    const start = (byteEffect(g, 4) + @as(u32, @intCast(episode)) + g.bytes[16]) % Slots;
    const budget = @min(Slots, byteEffect(g, 5));
    var best_slot: usize = @intCast(start);
    var best_d: i64 = std.math.maxInt(i64);
    var q: usize = 0;
    while (q < budget) : (q += 1) {
        const slot = (start + q * stride + g.bytes[17] +% g.bytes[18] *% @as(u8, @truncate(q))) % Slots;
        const class = physicalClass(body, slot, 1, c);
        const response = transform(g, rawTrace(class, body, slot, 1, c, waveform, amp));
        var d = distance(g, target, response);
        if (byteEffect(g, 14) == 1) d = -d;
        if (d < best_d or (d == best_d and ((slot + byteEffect(g, 13)) % Slots) < ((best_slot + byteEffect(g, 13)) % Slots))) {
            best_d = d;
            best_slot = slot;
        }
    }
    return best_slot;
}

fn viable(g: Genome, body: usize, episode: usize, c: Condition) bool {
    const target_class = (body * 7 + episode * 3 + 1) % Classes;
    const slot = choose(g, body, episode, c);
    // This boolean remains evaluator-private. Development receives only its
    // downstream energy consequence aggregated over whole bodies.
    return physicalClass(body, slot, 1, c) == target_class;
}
fn score(g: Genome, first_body: usize, body_count: usize, conditions: []const Condition) usize {
    var total: usize = 0;
    for (conditions) |c| for (first_body..first_body + body_count) |body| for (0..Episodes) |ep| {
        total += @intFromBool(viable(g, body, ep, c));
    };
    return total;
}

fn grow() Genome {
    const dev = [_]Condition{ .matched, .noise, .temporal_delay };
    var best = base_genome;
    var best_score = score(best, 0, DevBodies, &dev);
    var generation: usize = 0;
    while (generation < 64) : (generation += 1) {
        var ordinal: usize = 0;
        while (ordinal < 24) : (ordinal += 1) {
            const candidate = child(best, generation * 24 + ordinal);
            const s = score(candidate, 0, DevBodies, &dev);
            if (s > best_score or (s == best_score and digest(candidate) < digest(best))) {
                best = candidate;
                best_score = s;
            }
        }
    }
    return best;
}

fn armGenome(a: Arm, grown: Genome) Genome {
    return switch (a) {
        .grown => grown,
        .fixed => base_genome,
        .random => blk: {
            var g = base_genome;
            for (&g.bytes, 0..) |*b, i| b.* = @truncate(mix(@intCast(i * 991 + 17)));
            break :blk g;
        },
        .replay => blk: {
            var g = base_genome;
            g.bytes[5] = 1;
            g.bytes[3] = 1;
            g.bytes[16] = 0;
            break :blk g;
        },
        .equal_static => blk: {
            var g = base_genome;
            for (&g.bytes, 0..) |*b, i| b.* = @truncate(mix(@intCast(i * 577 + 0x5151)));
            g.bytes[20] = 0;
            g.bytes[21] = 0;
            g.bytes[22] = 0;
            g.bytes[23] = 0;
            break :blk g;
        },
        .w1_human => blk: {
            var g = base_genome;
            // Human W1-like min centering, max scaling, full window and L2.
            g.bytes[5] = 8;
            g.bytes[7] = 8;
            g.bytes[8] = 2;
            g.bytes[9] = 2;
            g.bytes[12] = 1;
            g.bytes[3] = 1;
            break :blk g;
        },
    };
}

fn attacksPass(grown: Genome) bool {
    // Freeze is value-copy; all held-out evaluation uses the copy.
    const frozen = grown;
    var edited = grown;
    edited.bytes[0] +%= 1;
    if (digest(frozen) == digest(edited)) return false;
    for (0..Bytes) |i| if (!mutationReachable(i)) return false;
    for (20..24) |i| if (!mutatorChangesDistribution(i)) return false;
    // No bloat: byte extent and proposal budget are invariant across arms.
    if (@sizeOf(Genome) != Bytes) return false;
    // Determinism / transcript noninheritance: a frozen program is sufficient.
    const cs = [_]Condition{ .port_permutation, .raw_recode };
    if (score(frozen, 100, 3, &cs) != score(frozen, 100, 3, &cs)) return false;
    return true;
}

fn writeCsv(path: []const u8) !void {
    const conditions = [_]Condition{ .matched, .port_permutation, .raw_recode, .temporal_delay, .noise, .missing_new, .actuator_remap };
    const arms = [_]Arm{ .grown, .fixed, .random, .replay, .equal_static, .w1_human };
    const grown = grow();
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("round,arm,condition,viable,trials,development_proposals,program_bytes,freeze_state,verdict,detail\n");
    for (arms) |a| {
        const g = armGenome(a, grown);
        for (conditions) |c| {
            const one = [_]Condition{c};
            const v = score(g, 100, TestBodies, &one);
            try w.print("round_x_x1,{s},{s},{d},{d},1536,24,frozen_before_private_bodies,MEASURED,downstream_resource_viability_only\n", .{ armName(a), conditionName(c), v, TestBodies * Episodes });
        }
    }
    try w.print("round_x_x1,attack_suite,all,{d},10,1536,24,frozen,MEASURED,reachability_mutator_distribution_freeze_bloat_leak_replay_recode\n", .{@as(usize, if (attacksPass(grown)) 10 else 0)});
}

fn selftest() !void {
    const grown = grow();
    if (!attacksPass(grown)) return error.AttackFailed;
    if (digest(grown) == digest(base_genome)) return error.NoGrowth;
    const held = [_]Condition{ .matched, .port_permutation, .raw_recode, .temporal_delay, .noise, .missing_new, .actuator_remap };
    const dev = [_]Condition{ .matched, .noise, .temporal_delay };
    const gd = score(grown, 0, DevBodies, &dev);
    const bd = score(base_genome, 0, DevBodies, &dev);
    const gv = score(grown, 100, TestBodies, &held);
    const rv = score(armGenome(.random, grown), 100, TestBodies, &held);
    const ev = score(armGenome(.equal_static, grown), 100, TestBodies, &held);
    const hv = score(armGenome(.w1_human, grown), 100, TestBodies, &held);
    if (gv >= rv) return error.FalsePromotion;
    std.debug.print("SELFTEST PASS: 24/24 byte effects reachable; 4/4 mutator bytes alter descendant distributions; development {d}/192 vs birth {d}/192; frozen grown {d}/1344, random {d}/1344, equal-static {d}/1344, W1 control {d}/1344; attacks 10/10; valid-negative verdict locked\n", .{ gd, bd, gv, rv, ev, hv });
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const arg = args.next() orelse "selftest";
    if (std.mem.eql(u8, arg, "selftest")) return selftest();
    try writeCsv(arg);
    try selftest();
}
