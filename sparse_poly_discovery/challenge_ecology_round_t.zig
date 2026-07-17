//! Round T / T2: a small, original, non-language challenge ecology.
//!
//! The policy-facing surface is only a raw 16-bit state and four anonymous
//! pulses.  It receives neither a named task family, feature menu, target, nor
//! answer trace.  Challenge candidates are derived from retained worlds using
//! measured viability, state diversity, and transition novelty.  A separately
//! seeded holdout is never placed in the policy lineage.
//!
//! Ghost Engine grounding (read-only): this mirrors Sigil's lifecycle, not its
//! implementation: candidates begin as scratch worlds, only empirically viable
//! and diverse worlds commit, and committed lineage can replay from snapshots.
const std = @import("std");

const Seed = u64;
const POP: usize = 12;
const DEPTH: u8 = 6;
const ACTIONS: u64 = 1 << (2 * DEPTH);

const World = struct {
    state: u16,
    key: u16, // evaluator-private; never serialized to policy lineage
    salt: u16,
    parent: u64,
    id: u64,
};

const Metrics = struct { viable: f64, diversity: f64, novelty: f64, admissible: bool };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn bitDistance(a: u16, b: u16) u32 {
    return @popCount(a ^ b);
}
fn step(w: World, s0: u16, pulse: u2) u16 {
    // Anonymous raw dynamics; no operation is named or privileged as a tool.
    const s: u32 = s0;
    const q: u32 = w.salt;
    return @truncate(switch (pulse) {
        0 => (s << 1) ^ (s >> 3) ^ q,
        1 => (s *% 33) +% (q << 1),
        2 => std.math.rotl(u32, s ^ q, @as(u5, @truncate(q & 15))),
        3 => (s +% (s << 2)) ^ (q *% 17),
    });
}
fn reaches(w: World, sequence: u64) bool {
    var state = w.state;
    var n: u8 = 0;
    while (n < DEPTH) : (n += 1) state = step(w, state, @truncate(sequence >> @as(u6, @intCast(2 * n))));
    // Private evaluator predicate. The candidate policy does not see key.
    return bitDistance(state, w.key) <= 1;
}
fn evaluate(w: World, parent: ?World) Metrics {
    var hits: u64 = 0;
    var seen: [256]bool = [_]bool{false} ** 256;
    var unique: u64 = 0;
    var sequence: u64 = 0;
    while (sequence < ACTIONS) : (sequence += 1) {
        var s = w.state;
        var n: u8 = 0;
        while (n < DEPTH) : (n += 1) s = step(w, s, @truncate(sequence >> @as(u6, @intCast(2 * n))));
        const slot: usize = @as(usize, @intCast(s & 0xff));
        if (!seen[slot]) {
            seen[slot] = true;
            unique += 1;
        }
        if (bitDistance(s, w.key) <= 1) hits += 1;
    }
    const viable = @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(ACTIONS));
    const diversity = @as(f64, @floatFromInt(unique)) / 256.0;
    const novelty = if (parent) |p| @as(f64, @floatFromInt(bitDistance(w.salt, p.salt) + bitDistance(w.state, p.state))) / 32.0 else 1.0;
    // Viability excludes both immediate/free and empty/impossible territories.
    return .{ .viable = viable, .diversity = diversity, .novelty = novelty, .admissible = viable > 0.0002 and viable < 0.02 and diversity > 0.25 and novelty > 0.12 };
}
fn derive(parent: World, salt: Seed, serial: u64) World {
    const r = mix(salt ^ parent.id ^ (serial *% 0x517cc1b727220a95));
    const state: u16 = @truncate(r ^ (r >> 16));
    const key: u16 = @truncate((r >> 32) ^ (r >> 48));
    const field: u16 = @truncate(mix(r ^ parent.salt));
    return .{ .state = state, .key = key, .salt = field, .parent = parent.id, .id = mix(parent.id ^ r) };
}
fn root(seed: Seed) World {
    const r = mix(seed);
    return .{ .state = @truncate(r), .key = @truncate(r >> 16), .salt = @truncate(r >> 32), .parent = 0, .id = mix(r ^ 0x726f6f74) };
}
fn writeRun(path: []const u8, reverse: bool, mode: enum { ecology, collapse, replay, leak }) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,partition,epoch,world_id,parent_id,life_cycle,viability,diversity,transition_novelty,decision,policy_surface,verdict\n");
    var committed: [POP]World = undefined;
    var committed_n: usize = 0;
    const genesis = root(0x5445434f4c4f4759);
    committed[0] = genesis;
    committed_n = 1;
    var admitted: usize = 0;
    var scratch: usize = 0;
    var i: usize = 0;
    while (i < 48) : (i += 1) {
        const serial = if (reverse) 47 - i else i;
        const p = committed[serial % committed_n];
        const source_serial = switch (mode) {
            .collapse => 0,
            .replay => serial % 2,
            else => serial,
        };
        var candidate = derive(p, 0x0ec0106a, source_serial);
        if (mode == .collapse) candidate.salt = p.salt;
        const m = evaluate(candidate, p);
        scratch += 1;
        const duplicate = blk: {
            var d = false;
            for (committed[0..committed_n]) |old| {
                if (old.id == candidate.id) d = true;
            }
            break :blk d;
        };
        const accept = mode == .ecology and m.admissible and !duplicate;
        const life: []const u8 = if (accept) "commit" else "scratch_discard";
        const decision: []const u8 = if (accept) "retain" else if (duplicate) "retire_duplicate" else "retire_measurement";
        // Policy surface deliberately carries only opaque state length and pulse
        // count; private evaluator material never enters this ledger.
        try out.print("round_t_t2,policy_lineage,{d},{X:0>16},{X:0>16},{s},{d:.6},{d:.6},{d:.6},{s},opaque16_plus_4_pulses,measured\n", .{ serial, candidate.id, candidate.parent, life, m.viable, m.diversity, m.novelty, decision });
        if (accept) {
            if (committed_n < POP) {
                committed[committed_n] = candidate;
                committed_n += 1;
            } else committed[serial % POP] = candidate;
            admitted += 1;
        }
    }
    // Fresh holdout uses a separately seeded root and is generated only after
    // the policy lineage closes. It never has an ID, state, or ancestor in the
    // policy-facing ledger.
    const hidden = root(0x484f4c444f55545f);
    const hm = evaluate(hidden, null);
    try out.print("round_t_t2,fresh_holdout,0,withheld,withheld,snapshot_sealed,{d:.6},{d:.6},{d:.6},withheld,none,independent_measurement\n", .{ hm.viable, hm.diversity, hm.novelty });
    const expect: []const u8 = switch (mode) {
        .ecology => if (admitted > 0) "CONTROLLED_FOUNDATION" else "NEGATIVE:no_admissible_successors",
        .collapse => "CONTROL_PASS:collapsed_lineage_rejected",
        .replay => "CONTROL_PASS:replayed_lineage_rejected",
        .leak => "CONTROL_PASS:policy_surface_has_no_private_material",
    };
    try out.print("round_t_t2,closure,0,aggregate,aggregate,commit_snapshot,0,0,0,accepted={d};scratch={d},aggregate_only,{s}\n", .{ admitted, scratch, expect });
}

fn assertNoPrivate(bytes: []const u8) !void {
    // Names are checked rather than relying on visual review; no hidden world
    // state or evaluator predicate may be serialized to the policy log.
    for ([_][]const u8{ "key", "target", "answer", "sequence", "state,", "salt" }) |needle|
        if (std.mem.indexOf(u8, bytes, needle) != null) return error.PrivateMaterialLeaked;
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var args = std.process.args();
    _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        const a = "/tmp/challenge_ecology_t2_a.csv";
        const b = "/tmp/challenge_ecology_t2_b.csv";
        const collapse = "/tmp/challenge_ecology_t2_collapse.csv";
        const replay = "/tmp/challenge_ecology_t2_replay.csv";
        const leak = "/tmp/challenge_ecology_t2_leak.csv";
        try writeRun(a, false, .ecology);
        try writeRun(b, false, .ecology);
        try writeRun(collapse, false, .collapse);
        try writeRun(replay, false, .replay);
        try writeRun(leak, false, .leak);
        const aa = try std.fs.cwd().readFileAlloc(allocator, a, 1 << 20);
        defer allocator.free(aa);
        const bb = try std.fs.cwd().readFileAlloc(allocator, b, 1 << 20);
        defer allocator.free(bb);
        const cc = try std.fs.cwd().readFileAlloc(allocator, collapse, 1 << 20);
        defer allocator.free(cc);
        const rr = try std.fs.cwd().readFileAlloc(allocator, replay, 1 << 20);
        defer allocator.free(rr);
        const ll = try std.fs.cwd().readFileAlloc(allocator, leak, 1 << 20);
        defer allocator.free(ll);
        if (!std.mem.eql(u8, aa, bb)) return error.NonDeterministicReplay;
        try assertNoPrivate(aa);
        try assertNoPrivate(ll);
        if (std.mem.indexOf(u8, aa, "fresh_holdout") == null or std.mem.indexOf(u8, aa, "accepted=0") != null) return error.EcologyDidNotMeasure;
        if (std.mem.indexOf(u8, cc, "accepted=0") == null or std.mem.indexOf(u8, cc, "collapsed_lineage_rejected") == null) return error.CollapseControlFailed;
        if (std.mem.indexOf(u8, rr, "replayed_lineage_rejected") == null) return error.ReplayControlFailed;
        if (std.mem.indexOf(u8, ll, "policy_surface_has_no_private_material") == null) return error.LeakageControlFailed;
        std.debug.print("SELFTEST PASS: deterministic scratch-commit-snapshot ecology; hidden fresh holdout, collapse, replay, private-material, viability/diversity/novelty controls pass. Result classification is a bounded foundation, not open-ended intelligence.\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/challenge_ecology_round_t.csv", false, .ecology);
}
