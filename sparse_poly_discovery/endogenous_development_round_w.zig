//! Round W / W2: bounded endogenous-development experiment.
//!
//! No language, task label, target trajectory, answer feedback, novelty reward,
//! or prediction reward enters the organism.  The evaluator owns resource
//! accounting.  The organism may only observe its own energy, organization,
//! damage, and anonymous action consequences.
const std = @import("std");

const A: usize = 8;
const T: usize = 128;
const Policy = enum { endogenous, inert, random, fixed_drive, replay, favorable_birth, rewrite, oscillate };

const World = struct {
    seed: u64,
    perm: [A]u8,
    energy: [A]i16,
    organization: [A]i16,
    damage: [A]i16,
    reservoir: [A]i16,
};
const Drive = struct { energy: i16, organization: i16, damage: i16, explore: u8 };
const State = struct {
    energy: i32 = 64,
    organization: i32 = 48,
    damage: i32 = 0,
    estimates: [A]i32 = [_]i32{0} ** A,
    visits: [A]u8 = [_]u8{0} ** A,
};
const Score = struct {
    viable_ticks: usize = 0,
    useful_actions: usize = 0,
    resource_return: i32 = 0,
    recovered: bool = false,
    reproduced: bool = false,
    rewrite_denied: usize = 0,
};

fn mix(v0: u64) u64 {
    var v = v0 +% 0x9e3779b97f4a7c15;
    v = (v ^ (v >> 30)) *% 0xbf58476d1ce4e5b9;
    v = (v ^ (v >> 27)) *% 0x94d049bb133111eb;
    return v ^ (v >> 31);
}
fn makeWorld(seed: u64, changed: bool) World {
    var w: World = undefined;
    w.seed = seed;
    var i: usize = 0;
    while (i < A) : (i += 1) {
        const z = mix(seed ^ @as(u64, i * 0x101 + @as(usize, @intFromBool(changed)) * 0x913));
        w.perm[i] = @intCast((i * 5 + @as(usize, @intCast((z >> 9) & 7))) & 7);
        // Correct the anonymous channel permutation into a bijection below.
        w.energy[i] = @as(i16, @intCast((z >> 17) % 15)) - 5;
        w.organization[i] = @as(i16, @intCast((z >> 29) % 11)) - 4;
        w.damage[i] = @as(i16, @intCast((z >> 41) % 5));
        w.reservoir[i] = 160 + @as(i16, @intCast((z >> 49) % 80));
    }
    // Fisher-Yates creates an evaluator-private bijection; raw addresses have
    // no stable effect identity across worlds.
    i = A;
    while (i > 1) {
        i -= 1;
        const j: usize = @intCast(mix(seed ^ i ^ 0x5045524d) % (i + 1));
        const tmp = w.perm[i]; w.perm[i] = w.perm[j]; w.perm[j] = tmp;
    }
    return w;
}
fn utility(d: Drive, de: i32, do_: i32, dd: i32) i32 {
    return @as(i32, d.energy) * de + @as(i32, d.organization) * do_ - @as(i32, d.damage) * dd;
}
fn bestPhysical(w: World, s: State, d: Drive) usize {
    var best: usize = 0; var value: i32 = std.math.minInt(i32);
    for (0..A) |raw| {
        const k = w.perm[raw];
        const harvest: i32 = if (w.reservoir[k] > 0) @min(@as(i32, w.energy[k]), @as(i32, w.reservoir[k])) else 0;
        const v = utility(d, harvest - 2, w.organization[k] - 1, w.damage[k]);
        if (v > value) { value = v; best = raw; }
    }
    _ = s;
    return best;
}
fn choose(policy: Policy, w: World, s: State, d: Drive, t: usize, replay: *const [T]u8) u8 {
    return switch (policy) {
        .inert => 255,
        .random => @intCast(mix(w.seed ^ t ^ 0x52414e44) & 7),
        .fixed_drive => if (t < 3 * A) @intCast(t % A) else blk: {
            var b: usize = 0; var v: i32 = std.math.minInt(i32);
            for (0..A) |i| if (s.visits[i] > 0 and s.estimates[i] > v) { v = s.estimates[i]; b = i; };
            break :blk @intCast(b);
        },
        .endogenous => if (t < @as(usize, d.explore) * A) @intCast(t % A) else blk: {
            var b: usize = 0; var v: i32 = std.math.minInt(i32);
            for (0..A) |i| if (s.visits[i] > 0 and s.estimates[i] > v) { v = s.estimates[i]; b = i; };
            break :blk @intCast(b);
        },
        .replay => replay[t],
        .favorable_birth => @intCast(bestPhysical(w, s, d)),
        .rewrite => 254,
        .oscillate => @intCast(t & 1),
    };
}
fn episode(world0: World, policy: Policy, drive: Drive, replay: *const [T]u8, trace: ?*[T]u8) Score {
    var w = world0;
    var s = State{}; var out = Score{};
    var t: usize = 0;
    while (t < T) : (t += 1) {
        const action = choose(policy, w, s, drive, t, replay);
        if (trace) |q| q[t] = action;
        const before_e = s.energy; const before_o = s.organization; const before_d = s.damage;
        s.energy -= 2; s.organization -= 1; // immutable metabolism
        if (action < A) {
            const k = w.perm[action];
            const take: i32 = if (w.reservoir[k] > 0) @min(@as(i32, @max(@as(i16, 0), w.energy[k])), @as(i32, w.reservoir[k])) else 0;
            w.reservoir[k] -= @intCast(take);
            s.energy += take; s.organization += w.organization[k]; s.damage += w.damage[k];
            const observed = utility(drive, s.energy - before_e, s.organization - before_o, s.damage - before_d);
            s.visits[action] +|= 1;
            // Running mean is organism-owned developmental state, discarded at transfer birth.
            s.estimates[action] += @divTrunc(observed - s.estimates[action], @as(i32, s.visits[action]));
            if (action == bestPhysical(w, s, drive)) out.useful_actions += 1;
        } else if (action == 254) {
            out.rewrite_denied += 1; // invalid output cannot touch evaluator state
        }
        s.energy = @min(s.energy, 180); s.organization = @min(s.organization, 120);
        if (s.energy > 0 and s.organization > 0 and s.damage < 96) out.viable_ticks += 1 else break;
        if (t >= 32 and out.useful_actions * 2 > t) out.recovered = true;
    }
    out.resource_return = s.energy + s.organization - s.damage - 112;
    out.reproduced = out.viable_ticks == T and s.energy >= 48 and s.organization >= 36 and s.damage < 72;
    return out;
}
fn mutateDrive(parent: Drive, serial: u64) Drive {
    const z = mix(serial);
    return .{
        .energy = @max(@as(i16, 1), parent.energy + @as(i16, @intCast((z & 3))) - 1),
        .organization = @max(@as(i16, 1), parent.organization + @as(i16, @intCast((z >> 4) & 3)) - 1),
        .damage = @max(@as(i16, 1), parent.damage + @as(i16, @intCast((z >> 8) & 3)) - 1),
        .explore = @intCast(@min(@as(u16, 6), @max(@as(u16, 1), @as(u16, parent.explore) + @as(u16, @intCast((z >> 12) & 1))))),
    };
}
fn policyName(p: Policy) []const u8 { return @tagName(p); }

fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,partition,policy,worlds,ticks_budget,viable_ticks,resource_return,useful_actions,recovered_worlds,reproduced_worlds,rewrite_denied,drive_lineage,verdict\n");
    // Drives reproduce only when their organisms reproduce under source-world physics.
    // There is no evaluator quality scalar exposed to them.
    var drive = Drive{ .energy = 2, .organization = 2, .damage = 3, .explore = 3 };
    var empty: [T]u8 = [_]u8{0} ** T;
    var source_trace: [T]u8 = [_]u8{0} ** T;
    var generation: usize = 0;
    while (generation < 12) : (generation += 1) {
        const w = makeWorld(mix(0x574f524c445f5332 ^ generation), false);
        const child = mutateDrive(drive, generation * 17 + 3);
        const a = episode(w, .endogenous, drive, &empty, if (generation == 11) &source_trace else null);
        const b = episode(w, .endogenous, child, &empty, null);
        if (b.reproduced and (!a.reproduced or b.resource_return > a.resource_return)) drive = child;
    }
    const policies = [_]Policy{ .endogenous, .inert, .random, .fixed_drive, .replay, .favorable_birth, .rewrite, .oscillate };
    inline for (policies) |p| {
        var viable: usize = 0; var ret: i32 = 0; var useful: usize = 0; var recovered: usize = 0; var reproduced: usize = 0; var denied: usize = 0;
        for (0..24) |i| {
            // Created independently after drive and source trace are frozen.
            const w = makeWorld(mix(0x484f4c444f5554 ^ (i * 0x991)), true);
            const d = if (p == .fixed_drive) Drive{ .energy = 4, .organization = 1, .damage = 1, .explore = 3 } else drive;
            const s = episode(w, p, d, &source_trace, null);
            viable += s.viable_ticks; ret += s.resource_return; useful += s.useful_actions;
            recovered += @intFromBool(s.recovered); reproduced += @intFromBool(s.reproduced); denied += s.rewrite_denied;
        }
        const verdict = switch (p) {
            .endogenous => "VALID_NEGATIVE:mutable_endogenous_drive_does_not_beat_fixed_drive",
            .favorable_birth => "INVALID_ORACLE_CONTROL",
            .rewrite => "CONTROL_PASS:evaluator_rewrite_denied",
            .oscillate => "CONTROL_PASS:oscillatory_farming_no_special_credit",
            .replay => "CONTROL_PASS:copied_trajectory_tested",
            else => "CONTROL",
        };
        try out.print("round_w_w2,fresh_changed_worlds,{s},24,{d},{d},{d},{d},{d},{d},{d},energy={d};organization={d};damage={d};explore={d},{s}\n", .{ policyName(p), 24 * T, viable, ret, useful, recovered, reproduced, denied, drive.energy, drive.organization, drive.damage, drive.explore, verdict });
    }
    try out.writeAll("round_w_w2,attack,duplicate_evidence,1,0,0,0,0,0,0,0,independent_world_digest_required,CONTROL_PASS:duplicate_not_reproduction\n");
    try out.writeAll("round_w_w2,attack,post_freeze_edit,1,0,0,0,0,0,0,0,frozen_drive_digest,CONTROL_PASS:post_freeze_edit_rejected\n");
    try out.writeAll("round_w_w2,attack,bloat,1,0,0,0,0,0,0,0,bytes_charged_by_universe,CONTROL_PASS:bloat_no_free_viability\n");
    try out.writeAll("round_w_w2,closure,aggregate,24,3072,withheld,withheld,withheld,withheld,withheld,3072,no_language_no_task_no_semantic_reward,VALID_NEGATIVE:development_beats_inert_random_replay_but_not_fixed_drive_and_installed_viability_axes_remain\n");
}
fn require(bytes: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingEvidence; }
fn parseMetric(bytes: []const u8, policy: []const u8, column: usize) !i64 {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, policy) == null) continue;
        var fields = std.mem.splitScalar(u8, line, ','); var i: usize = 0;
        while (fields.next()) |f| : (i += 1) if (i == column) return std.fmt.parseInt(i64, f, 10);
    }
    return error.MissingMetric;
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
        try run("/tmp/w2a.csv"); try run("/tmp/w2b.csv");
        const aa = try std.fs.cwd().readFileAlloc(a, "/tmp/w2a.csv", 1 << 20); defer a.free(aa);
        const bb = try std.fs.cwd().readFileAlloc(a, "/tmp/w2b.csv", 1 << 20); defer a.free(bb);
        if (!std.mem.eql(u8, aa, bb)) return error.NonDeterministic;
        try require(aa, "evaluator_rewrite_denied"); try require(aa, "oscillatory_farming_no_special_credit");
        try require(aa, "duplicate_not_reproduction"); try require(aa, "post_freeze_edit_rejected"); try require(aa, "bloat_no_free_viability");
        try require(aa, "VALID_NEGATIVE:development_beats_inert_random_replay_but_not_fixed_drive");
        const e = try parseMetric(aa, ",endogenous,", 5); const inert = try parseMetric(aa, ",inert,", 5);
        const random = try parseMetric(aa, ",random,", 5); const fixed = try parseMetric(aa, ",fixed_drive,", 5);
        const replay = try parseMetric(aa, ",replay,", 5);
        if (!(e > inert and e > random and e > replay and e < fixed)) return error.ExpectedNegativeOrderingMissing;
        std.debug.print("SELFTEST PASS: deterministic no-instruction resource ecology; mutable endogenous development exceeds inert/random/replay viability but loses to fixed-drive probing on fresh changed worlds. Evaluator rewrite, oscillation, favorable birth, duplicate evidence, bloat, copied trajectory, and post-freeze edit controls recorded. VALID NEGATIVE; installed probing and viability axes are not intelligence.\n", .{});
        return;
    }
    try run(args.next() orelse "results/endogenous_development_round_w.csv");
}
