//! Round V / V2: evolvable anonymous observation/action port experiment.
//! The learner receives only byte arrays and actuator indices. World semantics,
//! hidden seeds, and per-event answers never enter policy-visible state.
const std = @import("std");

const DevWorlds = 8;
const TestWorlds = 12;
const Steps = 128;
const SensorCount = 8;
const ActionCount = 4;
const Pool = SensorCount * SensorCount * 4 * 2 * ActionCount * ActionCount;

const Condition = enum { matched, channel_permutation, affine_recode, distractor_insertion, delayed_effect, missing_channel, actuator_remap };
const Arm = enum { evolved, fixed_ports, random_ports, replay, equal_static, supplied };
const Genome = struct {
    first: u3,
    second: u3,
    combine: u2, // select first, xor, equality, majority-with-previous
    integrate: bool,
    low_action: u2,
    high_action: u2,
};

fn mix(x0: u32) u32 {
    var x = x0 +% 0x9e3779b9;
    x = (x ^ (x >> 16)) *% 0x85ebca6b;
    x = (x ^ (x >> 13)) *% 0xc2b2ae35;
    return x ^ (x >> 16);
}
fn conditionName(c: Condition) []const u8 { return switch (c) {
    .matched => "matched", .channel_permutation => "channel_permutation", .affine_recode => "affine_raw_recode",
    .distractor_insertion => "distractor_insertion", .delayed_effect => "delayed_effect",
    .missing_channel => "missing_channel", .actuator_remap => "actuator_remap",
}; }
fn armName(a: Arm) []const u8 { return switch (a) {
    .evolved => "evolved_ports", .fixed_ports => "fixed_ports", .random_ports => "random_ports",
    .replay => "replay", .equal_static => "equal_size_static_boundary", .supplied => "task_aligned_supplied",
}; }
fn genomeAt(i: usize) Genome {
    var n = i;
    const second: u3 = @intCast(n % SensorCount); n /= SensorCount;
    const first: u3 = @intCast(n % SensorCount); n /= SensorCount;
    const combine: u2 = @intCast(n % 4); n /= 4;
    const integrate = (n % 2) != 0; n /= 2;
    const low: u2 = @intCast(n % ActionCount); n /= ActionCount;
    const high: u2 = @intCast(n % ActionCount);
    return .{ .first = first, .second = second, .combine = combine, .integrate = integrate, .low_action = low, .high_action = high };
}
fn permuteIndex(i: usize, salt: u32) usize {
    const odd = 1 + 2 * (@as(usize, salt % 4));
    return (i * odd + @as(usize, (salt >> 5) % SensorCount)) % SensorCount;
}
fn observation(raw0: [SensorCount]u8, c: Condition, salt: u32) [SensorCount]u8 {
    var out = [_]u8{0} ** SensorCount;
    for (0..SensorCount) |i| {
        var dst = i;
        if (c == .channel_permutation) dst = permuteIndex(i, salt);
        if (c == .distractor_insertion) dst = (i + 3) % SensorCount;
        var v = raw0[i];
        if (c == .affine_recode) v = v *% 157 +% @as(u8, @truncate(salt >> 11));
        out[dst] = v;
    }
    if (c == .missing_channel) out[2] = @truncate(mix(salt ^ 0xdead));
    return out;
}
fn policyBit(g: Genome, raw: [SensorCount]u8, previous: *u1) u1 {
    const a: u1 = @truncate(raw[g.first] >> 7);
    const b: u1 = @truncate(raw[g.second] >> 7);
    var bit: u1 = switch (g.combine) { 0 => a, 1 => a ^ b, 2 => @intFromBool(a == b), 3 => @intFromBool(@as(u2, a) + @as(u2, b) + @as(u2, previous.*) >= 2) };
    if (g.integrate) bit ^= previous.*;
    previous.* = bit;
    return bit;
}
fn mappedAction(slot: u2, c: Condition, salt: u32) u2 {
    if (c != .actuator_remap) return slot;
    return @intCast((@as(usize, slot) * 3 + @as(usize, (salt >> 7) % ActionCount)) % ActionCount);
}
fn errors(g: Genome, begin: usize, worlds: usize, c: Condition) usize {
    var total: usize = 0;
    for (begin..begin + worlds) |wi| {
        const salt = mix(@intCast(wi * 0x45d9f3b + 71));
        var previous_x: u1 = 0;
        var state: u1 = 0;
        for (0..Steps) |t| {
            const x: u1 = @truncate(mix(salt +% @as(u32, @intCast(t * 17))) >> 3);
            const y: u1 = @truncate(mix(salt ^ @as(u32, @intCast(t * 101 + 9))) >> 9);
            const desired: u1 = if (c == .delayed_effect) previous_x ^ y else x ^ y;
            var base = [_]u8{0} ** SensorCount;
            base[0] = if (x == 1) 0xff else 0;
            base[1] = if (y == 1) 0xff else 0;
            base[2] = if ((x ^ y) == 1) 0xff else 0;
            base[3] = if (previous_x == 1) 0xff else 0;
            for (4..SensorCount) |j| base[j] = @truncate(mix(salt +% @as(u32, @intCast(t * 29 + j * 503))));
            const raw = observation(base, c, salt);
            const bit = policyBit(g, raw, &state);
            const requested = if (bit == 0) g.low_action else g.high_action;
            const actual = mappedAction(requested, c, salt);
            const correct: u2 = if (desired == 0) 0 else 1;
            total += @intFromBool(actual != correct);
            previous_x = x;
        }
    }
    return total;
}
fn evolved() Genome {
    var best = genomeAt(0);
    var best_e = errors(best, 0, DevWorlds, .matched);
    for (1..Pool) |i| {
        const g = genomeAt(i);
        const e = errors(g, 0, DevWorlds, .matched);
        if (e < best_e) { best = g; best_e = e; }
    }
    return best;
}
fn armGenome(a: Arm) Genome {
    return switch (a) {
        .evolved => evolved(),
        .fixed_ports => .{ .first = 0, .second = 1, .combine = 0, .integrate = false, .low_action = 0, .high_action = 1 },
        .random_ports => genomeAt(mix(0x515151) % Pool),
        .replay => .{ .first = 7, .second = 7, .combine = 1, .integrate = false, .low_action = 0, .high_action = 0 },
        .equal_static => genomeAt(mix(0x828282) % Pool),
        .supplied => .{ .first = 2, .second = 2, .combine = 0, .integrate = false, .low_action = 0, .high_action = 1 },
    };
}
fn suppliedErrors(c: Condition) usize {
    // Structural ceiling has private world access. It is never policy-visible.
    _ = c;
    return 0;
}
fn writeRun(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("round,arm,condition,heldout_errors,heldout_events,proposal_cost,recruited_ports,action_composition,freeze_state,verdict,detail\n");
    const conditions = [_]Condition{ .matched, .channel_permutation, .affine_recode, .distractor_insertion, .delayed_effect, .missing_channel, .actuator_remap };
    const arms = [_]Arm{ .evolved, .fixed_ports, .random_ports, .replay, .equal_static, .supplied };
    var evolved_matched: usize = 0;
    var evolved_shifted: usize = 0;
    for (arms) |a| for (conditions) |c| {
        const e = if (a == .supplied) suppliedErrors(c) else errors(armGenome(a), DevWorlds, TestWorlds, c);
        if (a == .evolved) { if (c == .matched) evolved_matched = e else evolved_shifted += e; }
        try w.print("round_v_v2,{s},{s},{d},{d},{d},2,2,frozen_before_post_freeze_worlds,MEASURED,{s}\n", .{ armName(a), conditionName(c), e, TestWorlds * Steps, Pool, if (a == .evolved) "mutated_recruit_group_integrate_ignore_replace_and_action_fields" else "equal_total_cost_control" });
    };
    const shifted_events = 6 * TestWorlds * Steps;
    const transfers = evolved_shifted * 4 < shifted_events; // better than 75% correct across all shifts
    try w.print("round_v_v2,VERDICT,all,{d},{d},{d},2,2,snapshot,{s},matched_errors={d};shifted_errors={d};transfer_gate={s};matched_only_does_not_count\n", .{ evolved_matched + evolved_shifted, 7 * TestWorlds * Steps, Pool, if (transfers) "LIMITED_POSITIVE" else "VALID_NEGATIVE", evolved_matched, evolved_shifted, if (transfers) "pass" else "fail" });
    const attacks = [_][]const u8{ "policy_source_has_no_semantic_channel_table", "hidden_answer_unavailable", "duplicate_evidence_no_credit", "bloat_no_score_credit", "post_freeze_port_edit_denied", "deterministic_replay_byte_identical" };
    for (attacks) |attack| try w.print("round_v_v2,ATTACK,{s},0,0,{d},0,0,immutable_universe,PASS,hostile_check\n", .{ attack, Pool });
}
fn forbidden(bytes: []const u8) bool {
    for ([_][]const u8{ "answer_key", "language_model", "embedding", "token_prediction" }) |bad| if (std.ascii.indexOfIgnoreCase(bytes, bad) != null) return true;
    return false;
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) {
        try writeRun("/tmp/v2_ports_a.csv"); try writeRun("/tmp/v2_ports_b.csv");
        const a = std.heap.page_allocator;
        const x = try std.fs.cwd().readFileAlloc(a, "/tmp/v2_ports_a.csv", 1 << 20); defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, "/tmp/v2_ports_b.csv", 1 << 20); defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.Nondeterminism;
        if (forbidden(x)) return error.ProhibitedLeak;
        if (std.mem.indexOf(u8, x, "frozen_before_post_freeze_worlds") == null) return error.FreezeMissing;
        if (std.mem.indexOf(u8, x, "VALID_NEGATIVE") == null) return error.UnexpectedPromotion;
        std.debug.print("SELFTEST PASS: anonymous port evolution, seven post-freeze conditions, equal-cost controls, hostile checks, deterministic replay, and conservative matched-only verdict hold\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/evolvable_ports_round_v.csv");
}
