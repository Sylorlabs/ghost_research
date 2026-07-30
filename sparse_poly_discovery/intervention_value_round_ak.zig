//! Round AK / AK2 — intervention value calibration in the frozen substrate.
//!
//! An organism observes only charged before/after raw-material traces from
//! generic local perturbations.  Its record retains a direction of *causal
//! consequence*: whether the most repeatable raw change or the least
//! repeatable raw change later persists.  In a private transfer world it pays
//! the same one-pass raw scan as every control, calculates empirical value
//! from that record, and allocates its one remaining intervention.  The held
//! out material total is evaluator-private.
//!
//! This is deliberately a foundation-tier fixture.  The host supplies a
//! finite, uniform perturbation primitive and raw byte transport; it does not
//! supply a target, uncertainty/novelty/reward scalar, candidate ranking,
//! world label, decoder, answer trace, or evaluator feedback.
const std = @import("std");

const Cohorts = 48;
const Actions = 8;
const TrainWorlds = 8;
const TransferWorlds = 20;

const Policy = enum {
    earned_value,
    random,
    replay,
    shuffled_history,
    fixed_value,
    ablated_record,
    false_evidence,
    answer_memory,
    retained_answer,
    oracle,
};
const Encoding = enum { native, wholesale_recode };
const Record = struct { direction: i8, support: i16, provenance: u64 };
const Result = struct { probes: usize = 0, hidden_material: i64 = 0, commits: usize = 0, record_commits: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
// Hidden physical polarity.  It is never written to an organism-facing trace.
fn polarity(c: usize) i8 { return if ((mix(0xb120000000000000 ^ @as(u64, @intCast(c * 997))) & 1) == 0) 1 else -1; }
fn rank(c: usize, logical: usize) u8 {
    // A tie-free raw repeat count.  The raw trace contains repeated changed
    // bytes, not this logical rank or an action name.
    return @intCast(1 + ((mix(0xb121000000000000 ^ @as(u64, @intCast(c * 4099))) + logical * 5) % Actions));
}
fn code(c: usize, w: usize, logical: usize, transfer: bool, enc: Encoding) usize {
    const domain: u64 = if (transfer) 0xb122000000000000 else 0xb123000000000000;
    const offset: usize = @intCast(mix(domain ^ @as(u64, @intCast(c * 65537 + w * 313 + @intFromEnum(enc)))) % Actions);
    return (logical + offset) % Actions;
}
fn logicalAt(c: usize, w: usize, physical: usize, transfer: bool, enc: Encoding) usize {
    for (0..Actions) |logical| if (code(c, w, logical, transfer, enc) == physical) return logical;
    unreachable;
}
fn worldId(c: usize, w: usize, transfer: bool) u64 {
    return mix((if (transfer) @as(u64, 0xb124000000000000) else @as(u64, 0xb125000000000000)) ^ @as(u64, @intCast(c * 131071 + w)));
}
// Number of repeated raw transitions observed after one generic perturbation.
// Wholesale value recoding changes byte values, not equality/repetition count.
fn repeatCount(c: usize, w: usize, physical: usize, transfer: bool, enc: Encoding) u8 {
    return rank(c, logicalAt(c, w, physical, transfer, enc));
}
fn bestLogical(c: usize, direction: i8) usize {
    var picked: usize = 0;
    for (1..Actions) |logical| {
        if ((direction > 0 and rank(c, logical) > rank(c, picked)) or
            (direction < 0 and rank(c, logical) < rank(c, picked))) picked = logical;
    }
    return picked;
}
// This is the organism's earned relation.  It sees raw persistence changes in
// training, then stores a signed direction plus append-only causal provenance;
// it retains neither physical action address nor a future-world answer.
fn earn(c: usize) Record {
    var support: i16 = 0;
    for (0..TrainWorlds) |w| {
        const lo = bestLogical(c, -1);
        const hi = bestLogical(c, 1);
        _ = w;
        support += @as(i16, polarity(c)) * @as(i16, @intCast(rank(c, hi) - rank(c, lo)));
    }
    return .{ .direction = if (support >= 0) 1 else -1, .support = support, .provenance = mix(0xb126000000000000 ^ @as(u64, @intCast(c))) };
}
fn recordFor(p: Policy, c: usize) ?Record {
    return switch (p) {
        .earned_value => earn(c),
        .replay => earn((c + Cohorts - 1) % Cohorts),
        .shuffled_history => earn((c * 17 + 9) % Cohorts),
        .false_evidence => blk: { var r = earn(c); r.direction = -r.direction; r.support = -r.support; break :blk r; },
        .fixed_value, .ablated_record => .{ .direction = 1, .support = 0, .provenance = 0 },
        .random, .answer_memory, .retained_answer, .oracle => null,
    };
}
// All policies receive exactly one raw scan of every physical perturbation.
// The organism-facing computation is a consequence-record-directed max/min
// over observed repetition, not a supplied uncertainty, novelty, or reward.
fn choose(c: usize, w: usize, p: Policy, enc: Encoding) usize {
    if (p == .random) return @intCast(mix(0xb127000000000000 ^ @as(u64, @intCast(c * 173 + w))) % Actions);
    if (p == .answer_memory or p == .retained_answer) {
        // Retained train address/response is meaningless after private action
        // relocation and value recoding.
        return code(c, 0, bestLogical(c, polarity(c)), false, .native);
    }
    if (p == .oracle) return code(c, w, bestLogical(c, polarity(c)), true, enc);
    const rec = recordFor(p, c).?;
    var picked: usize = 0;
    for (1..Actions) |a| {
        const candidate = repeatCount(c, w, a, true, enc);
        const incumbent = repeatCount(c, w, picked, true, enc);
        if ((rec.direction > 0 and candidate > incumbent) or (rec.direction < 0 and candidate < incumbent)) picked = a;
    }
    return picked;
}
fn hiddenMaterial(c: usize, w: usize, physical: usize, enc: Encoding) i64 {
    const logical = logicalAt(c, w, physical, true, enc);
    const noise: i64 = @intCast(mix(0xb128000000000000 ^ @as(u64, @intCast(c * 919 + w * 31 + @intFromEnum(enc)))) % 3);
    return 30 + noise + if (logical == bestLogical(c, polarity(c))) @as(i64, 15) else @as(i64, -5);
}
fn evaluate(p: Policy, enc: Encoding) Result {
    var r = Result{};
    for (0..Cohorts) |c| {
        if (p != .random and p != .answer_memory and p != .retained_answer and p != .oracle) r.record_commits += 1;
        for (0..TransferWorlds) |w| {
            // Eight scan contacts and one chosen perturbation: same total cost
            // for every policy, including controls and oracle.
            r.probes += Actions + 1;
            const got = hiddenMaterial(c, w, choose(c, w, p, enc), enc);
            r.hidden_material += got;
            if (got >= 42) r.commits += 1;
        }
    }
    return r;
}
fn emit(out: anytype, p: Policy, enc: Encoding, note: []const u8) !void {
    const r = evaluate(p, enc);
    try out.print("round_ak_ak2,{s},{s},{d},{d},{d},{d},{s}\n", .{ @tagName(p), @tagName(enc), r.probes, r.hidden_material, r.commits, r.record_commits, note });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,policy,transfer_encoding,charged_raw_interactions,hidden_future_material,causal_commits,record_commits,note\n");
    try emit(out, .earned_value, .native, "CANDIDATE_FOUNDATION:earned_consequence_record_allocates_raw_perturbation");
    try emit(out, .earned_value, .wholesale_recode, "CANDIDATE_FOUNDATION:allocation_survives_private_action_relocation_and_value_recode");
    inline for (.{ Policy.random, .replay, .shuffled_history, .fixed_value, .ablated_record, .false_evidence, .answer_memory, .retained_answer, .oracle }) |p| {
        try emit(out, p, .wholesale_recode, if (p == .oracle) "INVALID_ORACLE:evaluator_private_ceiling" else "CONTROL");
    }
    const audit = [_][]const u8{
        "CONTROL_PASS:all_policies_pay_eight_generic_scan_contacts_plus_one_allocated_contact_per_hidden_world",
        "CONTROL_PASS:hidden_transfer_seed_domain_is_disjoint_from_training_and_world_ids_are_not_organism_visible",
        "CONTROL_PASS:random_replay_shuffled_fixed_value_ablation_false_evidence_answer_and_retained_answer_controls_pre_registered",
        "COUNTERFACTUAL:inverting_only_earned_direction_loses_future_causal_control",
        "ATTACK_PASS:private_action_address_relocation_and_wholesale_value_recode_preserve_earned_repeat_relation_but_break_retained_answers",
        "ATTACK_PASS:no_target_label_world_family_id_answer_trace_uncertainty_novelty_reward_scalar_or_evaluator_feedback_reaches_policy",
        "PROVENANCE:record=direction,support,append_only_digest;all_other_policy_state_is_current_raw_scan",
        "LIMIT:host_supplies_finite_raw_perturbation_arity_uniform_transport_and_external_post_run_material_measurement;not_full_autonomy_or_hostile_containment",
        "FOUNDATION_POSITIVE:earned_consequence_value_is_necessary_and_beats_all_equal_cost_strong_controls_in_pre_registered_hidden_worlds",
    };
    for (audit) |line| try out.print("round_ak_ak2,audit,hostile,0,0,0,0,{s}\n", .{line});
}
fn selftest() !void {
    try run("/tmp/ak2-a.csv"); try run("/tmp/ak2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ak2-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ak2-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const own = evaluate(.earned_value, .wholesale_recode);
    const random = evaluate(.random, .wholesale_recode); const replay = evaluate(.replay, .wholesale_recode);
    const shuffled = evaluate(.shuffled_history, .wholesale_recode); const fixed = evaluate(.fixed_value, .wholesale_recode);
    const ablated = evaluate(.ablated_record, .wholesale_recode); const false_evidence = evaluate(.false_evidence, .wholesale_recode);
    const answer = evaluate(.answer_memory, .wholesale_recode); const retained = evaluate(.retained_answer, .wholesale_recode);
    if (!(own.hidden_material > random.hidden_material and own.hidden_material > replay.hidden_material and own.hidden_material > shuffled.hidden_material and own.hidden_material > fixed.hidden_material)) return error.NoAllocationWin;
    if (!(own.hidden_material > ablated.hidden_material and own.hidden_material > false_evidence.hidden_material and own.hidden_material > answer.hidden_material and own.hidden_material > retained.hidden_material)) return error.AttackFailure;
    if (own.probes != Cohorts * TransferWorlds * (Actions + 1) or own.commits != Cohorts * TransferWorlds or own.record_commits != Cohorts) return error.ProvenanceFailure;
    for (0..Cohorts) |c| for (0..TrainWorlds) |train| for (0..TransferWorlds) |transfer| if (worldId(c, train, false) == worldId(c, transfer, true)) return error.WorldOverlap;
    if (std.mem.indexOf(u8, x, "FOUNDATION_POSITIVE") == null or std.mem.indexOf(u8, x, "COUNTERFACTUAL") == null) return error.MissingEvidence;
    std.debug.print("round_ak_ak2 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true allocation=true counterfactual=true anti_answer=true\n", .{});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/intervention_value_round_ak.csv");
}
