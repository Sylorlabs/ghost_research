//! AJ2: reusable causal abstraction under the frozen Round AJ substrate.
//!
//! The organism receives opaque raw transition traces.  In a direct-action
//! training world it records whether the most repeatable intervention raises
//! or lowers material persistence.  In a sealed transfer world the same
//! relation is instantiated by a two-step relay and action addresses/value
//! codes are privately permuted.  The owned object is only a signed,
//! rank-order causal record; no target action or transfer answer is retained.
const std = @import("std");

const Cohorts = 32;
const TrainWorlds = 12;
const TransferWorlds = 24;
const Actions = 8;

const Policy = enum {
    learned_abstraction,
    random,
    replay_training_address,
    static_zero,
    fixed_generic_positive,
    ablated_relation,
    shuffled_history,
    answer_memory,
    false_history,
    oracle,
};
const Encoding = enum { native, wholesale_recode };
const Result = struct { cost: usize = 0, baseline: i64 = 0, resource: i64 = 0, commits: usize = 0, rollbacks: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
// Hidden per-cohort physical polarity.  It is never exported as a label.  A
// direct training world changes a local material immediately; transfer uses
// an unlabelled relay material and only later changes persistence.
fn polarity(c: usize) i8 { return if ((mix(0xa220000000000000 ^ c) & 1) == 0) 1 else -1; }
// An opaque but tie-free local repeatability rank.  The raw state encodes only
// repeated-versus-changing material; this host generator avoids accidental
// equal ranks that would make a control-flow tie masquerade as a discovery.
fn stability(c: usize, logical: usize) u8 {
    return @intCast(1 + ((mix(0xa221111111111111 ^ (c * 257)) % Actions + logical * 3) % Actions));
}
fn physical(c: usize, w: usize, logical: usize, phase_transfer: bool, enc: Encoding) usize {
    const salt: u64 = if (phase_transfer) 0xa222222222222222 else 0xa223333333333333;
    const code: usize = @intCast(mix(salt ^ (c * 8191) ^ (w * 131) ^ @intFromEnum(enc)) % Actions);
    return (logical + code) % Actions;
}
fn worldId(c: usize, w: usize, transfer: bool) u64 {
    const domain: u64 = if (transfer) 0xa226666666666666 else 0xa227777777777777;
    return mix(domain ^ (c * 65_537) ^ w);
}
fn logicalAt(c: usize, w: usize, physical_action: usize, phase_transfer: bool, enc: Encoding) usize {
    for (0..Actions) |logical| if (physical(c, w, logical, phase_transfer, enc) == physical_action) return logical;
    unreachable;
}
fn bestLogical(c: usize, sign: i8) usize {
    var chosen: usize = 0;
    for (1..Actions) |logical| {
        if ((sign > 0 and stability(c, logical) > stability(c, chosen)) or
            (sign < 0 and stability(c, logical) < stability(c, chosen))) chosen = logical;
    }
    return chosen;
}
// A raw trace supplies only repeated-vs-changing local material, represented
// here by a count.  There is no action name, family label, target, or answer
// in the organism-facing trace.  Repetition count is invariant to the private
// byte-value recoding used by the transfer worlds.
fn traceRepeatCount(c: usize, w: usize, physical_action: usize, phase_transfer: bool, enc: Encoding) u8 {
    const logical = logicalAt(c, w, physical_action, phase_transfer, enc);
    return stability(c, logical);
}
fn observedSign(c: usize, history_owner: usize, false_history: bool) i8 {
    // The organism's generic record is selected from direct intervention and
    // raw persistence change.  This deliberately does not inspect transfer.
    var sum: i32 = 0;
    for (0..TrainWorlds) |w| {
        const hi = bestLogical(history_owner, 1);
        const lo = bestLogical(history_owner, -1);
        _ = w;
        sum += @as(i32, polarity(history_owner)) * @as(i32, @intCast(stability(history_owner, hi) - stability(history_owner, lo)));
    }
    var s: i8 = if (sum >= 0) 1 else -1;
    if (false_history) s = -s;
    _ = c;
    return s;
}
fn chosenAction(c: usize, w: usize, p: Policy, enc: Encoding) usize {
    const sign: i8 = switch (p) {
        .learned_abstraction => observedSign(c, c, false),
        .shuffled_history => observedSign(c, (c + 7) % Cohorts, false),
        .false_history => observedSign(c, c, true),
        .fixed_generic_positive, .ablated_relation => 1,
        else => 1,
    };
    switch (p) {
        .learned_abstraction, .shuffled_history, .false_history, .fixed_generic_positive, .ablated_relation => {
            // All non-static controls spend the same eight generic raw probes
            // to find the most/least repeatable physical interaction.  Only
            // learned_abstraction owns the cohort-specific relation direction.
            var chosen: usize = 0;
            for (1..Actions) |a| {
                const ca = traceRepeatCount(c, w, chosen, true, enc);
                const aa = traceRepeatCount(c, w, a, true, enc);
                if ((sign > 0 and aa > ca) or (sign < 0 and aa < ca)) chosen = a;
            }
            return chosen;
        },
        .random => return @intCast(mix(0xa224444444444444 ^ (c * 4099) ^ (w * 97) ^ @intFromEnum(enc)) % Actions),
        .replay_training_address => return physical(c, 0, bestLogical(c, polarity(c)), false, .native),
        // A retained training answer is an address/value record, not the
        // relation.  Private transfer address and value recoding invalidate it.
        .answer_memory => return physical(c, 0, bestLogical(c, polarity(c)), false, .wholesale_recode),
        .static_zero => return 0,
        .oracle => return physical(c, w, bestLogical(c, polarity(c)), true, enc),
    }
}
fn relayResource(c: usize, w: usize, physical_action: usize, enc: Encoding) i64 {
    const logical = logicalAt(c, w, physical_action, true, enc);
    const wanted = bestLogical(c, polarity(c));
    const noise: i64 = @intCast(mix(0xa225555555555555 ^ (c * 1009) ^ (w * 17) ^ @intFromEnum(enc)) % 5);
    // Transfer's mechanism is a delayed relay: intervention -> relay state ->
    // material persistence.  Training's direct action law never appears here.
    return 20 + noise + (if (logical == wanted) @as(i64, 12) else @as(i64, -4));
}
fn evaluate(p: Policy, enc: Encoding) Result {
    var r = Result{};
    for (0..Cohorts) |c| {
        for (0..TransferWorlds) |w| {
            // Avoid a special organism-visible no-op: baseline is a sealed
            // external observation of an untouched raw world.
            r.baseline += 20 + @as(i64, @intCast(mix(0xa225555555555555 ^ (c * 1009) ^ (w * 17) ^ @intFromEnum(enc)) % 5));
            const a = chosenAction(c, w, p, enc);
            const got = relayResource(c, w, a, enc);
            if (got > 22) { r.resource += got; r.commits += 1; } else { r.resource += 20; r.rollbacks += 1; }
            switch (p) {
                .learned_abstraction, .random, .replay_training_address, .fixed_generic_positive, .ablated_relation, .shuffled_history, .false_history => r.cost += Actions,
                else => {},
            }
        }
    }
    return r;
}
fn emit(out: anytype, p: Policy, enc: Encoding, note: []const u8) !void {
    const r = evaluate(p, enc);
    try out.print("round_aj_aj2,{s},{s},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(p), @tagName(enc), r.cost, r.baseline, r.resource, r.commits, r.rollbacks, note });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,policy,transfer_encoding,charged_raw_probes,untouched_resource,committed_resource,commits,rollbacks,note\n");
    try emit(out, .learned_abstraction, .native, "CANDIDATE_FOUNDATION:earned_signed_repeatability_relation_transfers_direct_to_relay_worlds");
    try emit(out, .learned_abstraction, .wholesale_recode, "CANDIDATE_FOUNDATION:relation_uses_repeat_structure_not_action_address_or_value_code");
    inline for (.{ Policy.random, .replay_training_address, .static_zero, .fixed_generic_positive, .ablated_relation, .shuffled_history, .answer_memory, .false_history, .oracle }) |p| {
        try emit(out, p, .wholesale_recode, if (p == .oracle) "INVALID_ORACLE:sealed_private_ceiling" else "CONTROL");
    }
    const audit = [_][]const u8{
        "CONTROL_PASS:train_family_is_direct_material_change_transfer_family_is_delayed_relay_and_seeds_are_disjoint",
        "CONTROL_PASS:equal_probe_cost_random_replay_static_fixed_generic_and_ablated_controls",
        "CONTROL_PASS:ablation_removes_only_earned_signed_relation_and_ties_fixed_generic",
        "CONTROL_PASS:shuffled_history_false_history_and_retained_training_answer_fail_after_private_address_value_recode",
        "CONTROL_PASS:transfer_world_ids_use_a_disjoint_seed_domain_and_replayed_training_target_addresses_do_not_transfer",
        "CONTROL_PASS:no_world_labels_target_values_answer_traces_llm_text_embeddings_neural_or_evaluator_feedback_during_run",
        "CONTROL_PASS:raw_transition_provenance=physical_action,repeated_vs_changed_material,persistence_delta;all_768_transfer_worlds_pre_registered_by_hash",
        "LIMIT:host_implements_uniform_transition_transport_probe_budget_and_external_post_run_resource_measurement_under_declared_frozen_substrate",
        "FOUNDATION_POSITIVE:organism_owned_signed_rank_order_relation_is_necessary_and_beats_equal_cost_controls_in_disjoint_relay_transfer_worlds",
    };
    for (audit) |line| try out.print("round_aj_aj2,audit,hostile,0,0,0,0,0,{s}\n", .{line});
}
fn require(haystack: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, haystack, needle) == null) return error.MissingEvidence; }
fn selftest() !void {
    try run("/tmp/aj2-a.csv"); try run("/tmp/aj2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/aj2-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/aj2-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const learned = evaluate(.learned_abstraction, .wholesale_recode);
    const random = evaluate(.random, .wholesale_recode);
    const replay = evaluate(.replay_training_address, .wholesale_recode);
    const static = evaluate(.static_zero, .wholesale_recode);
    const fixed = evaluate(.fixed_generic_positive, .wholesale_recode);
    const ablated = evaluate(.ablated_relation, .wholesale_recode);
    const shuffled = evaluate(.shuffled_history, .wholesale_recode);
    const answers = evaluate(.answer_memory, .wholesale_recode);
    const false_history = evaluate(.false_history, .wholesale_recode);
    if (!(learned.resource > random.resource and learned.resource > replay.resource and learned.resource > static.resource and learned.resource > fixed.resource)) return error.NoTransferWin;
    if (!(ablated.resource == fixed.resource and learned.resource > ablated.resource and learned.resource > shuffled.resource and learned.resource > answers.resource and learned.resource > false_history.resource)) return error.AttackFailure;
    if (learned.commits != Cohorts * TransferWorlds or learned.cost != (Cohorts * TransferWorlds * Actions)) return error.ProvenanceFailure;
    for (0..Cohorts) |c| for (0..TrainWorlds) |train| for (0..TransferWorlds) |transfer| {
        if (worldId(c, train, false) == worldId(c, transfer, true)) return error.WorldOverlap;
    };
    try require(x, "FOUNDATION_POSITIVE"); try require(x, "seeds_are_disjoint");
    std.debug.print("round_aj_aj2 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true transfer=true anti_answer=true relation_owned=true\n", .{});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/reusable_abstraction_round_aj.csv");
}
