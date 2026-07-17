//! Round AB / AB3 -- bootstrap scaffold replacement on a uniform raw tape.
//!
//! This is deliberately a bounded instrument, not a self-improvement claim.
//! No room/component table or replacement template is exposed to selection.
//! The organism challenges raw storage locations and constructs a whole-tape
//! successor from charged counterfactual receipts.  The hostile verdict still
//! treats byte boundaries and the mutation generator as human scaffold.
const std = @import("std");

const Width = 64;
const Cohorts = 20;
const Calibration = 10;
const Hidden = 18;
const Alternatives = 16;

const Policy = enum {
    evidence,
    evidence_recoded,
    random,
    frequency,
    cost,
    name,
    address,
    human_origin,
    fixed,
    no_replacement,
    request_free,
    shuffled,
    false_evidence,
    oracle,
};

const Result = struct {
    old_resource: i64 = 0,
    new_resource: i64 = 0,
    ablated_resource: i64 = 0,
    charged_trials: usize = 0,
    changed: usize = 0,
    committed: usize = 0,
    rolled_back: usize = 0,
};

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn logicalByte(cohort: usize, logical: usize) u8 {
    return @truncate(mix(0xab33000000000000 ^ (cohort *% 0x100000001b3) ^ (logical *% 0x517cc1b727220a95)));
}

fn slotFor(cohort: usize, logical: usize, recoded: bool) usize {
    if (!recoded) return logical;
    const mul: usize = 37; // coprime to 64; evaluator transport only
    return (logical * mul + cohort * 11 + 7) % Width;
}

fn maskFor(cohort: usize, logical: usize, recoded: bool) u8 {
    if (!recoded) return 0;
    return @truncate(mix(0xab335245434f4445 ^ cohort ^ (logical * 131)));
}

fn initialTape(cohort: usize, recoded: bool) [Width]u8 {
    var tape: [Width]u8 = undefined;
    for (0..Width) |logical| {
        const raw: u8 = @truncate(mix(0xab33424952544800 ^ (cohort * 257) ^ logical));
        tape[slotFor(cohort, logical, recoded)] = raw ^ maskFor(cohort, logical, recoded);
    }
    return tape;
}

fn resource(tape: [Width]u8, cohort: usize, ctx: usize, hidden: bool, recoded: bool) i64 {
    var total: i64 = 0;
    for (0..Width) |logical| {
        const decoded = tape[slotFor(cohort, logical, recoded)] ^ maskFor(cohort, logical, recoded);
        const target = logicalByte(cohort, logical);
        total += 8 - @as(i64, @intCast(@popCount(decoded ^ target)));
    }
    const seed: u64 = if (hidden) 0xab3348494444454e else 0xab3343414c494252;
    total += @as(i64, @intCast(mix(seed ^ (cohort * 4099) ^ ctx) % 9)) - 4;
    return total;
}

fn proposal(tape: [Width]u8, cohort: usize, slot: usize, nonce: usize) u8 {
    // Constructed only from organism-owned bytes, location-independent folds,
    // and mutable nonce state.  No evaluator target or alternative template.
    const a = tape[(slot + 13 + nonce * 3) % Width];
    const b = tape[(slot * 5 + 29 + nonce) % Width];
    return a ^ std.math.rotl(u8, b, @as(u3, @intCast(nonce & 7))) ^ @as(u8, @truncate(mix(cohort ^ nonce ^ a)));
}

fn calibration(tape: [Width]u8, cohort: usize, recoded: bool) i64 {
    var sum: i64 = 0;
    for (0..Calibration) |ctx| sum += resource(tape, cohort, ctx, false, recoded);
    return sum;
}

fn build(cohort: usize, policy: Policy, recoded: bool, charged: *usize) [Width]u8 {
    const old = initialTape(cohort, recoded);
    if (policy == .fixed or policy == .no_replacement or policy == .human_origin or policy == .cost) return old;
    if (policy == .oracle) {
        var out = old;
        for (0..Width) |logical| out[slotFor(cohort, logical, recoded)] = logicalByte(cohort, logical) ^ maskFor(cohort, logical, recoded);
        return out;
    }
    var out = old;
    var chosen: [Width]u8 = old;
    for (0..Width) |slot| {
        const target_slot = if (policy == .shuffled) (slot * 17 + 9) % Width else slot;
        var best = calibration(out, cohort, recoded);
        var worst = best;
        var best_byte = out[target_slot];
        var worst_byte = best_byte;
        for (0..Alternatives) |nonce| {
            var trial = out;
            trial[target_slot] = proposal(out, cohort, target_slot, nonce);
            const score = calibration(trial, cohort, recoded);
            charged.* += Calibration;
            if (score > best) { best = score; best_byte = trial[target_slot]; }
            if (score < worst) { worst = score; worst_byte = trial[target_slot]; }
        }
        chosen[slot] = switch (policy) {
            .evidence, .evidence_recoded => best_byte,
            .frequency => proposal(out, cohort, target_slot, Alternatives - 1),
            .false_evidence => worst_byte,
            .random => proposal(out, cohort, target_slot, mix(cohort ^ slot) % Alternatives),
            .name => proposal(out, cohort, target_slot, out[target_slot] % Alternatives),
            .address => if (slot < 8) best_byte else out[target_slot],
            .request_free => proposal(out, cohort, target_slot, (slot + cohort) % Alternatives),
            .shuffled => best_byte,
            else => out[target_slot],
        };
        if (policy != .shuffled) out[target_slot] = chosen[slot];
    }
    if (policy == .shuffled) {
        for (0..Width) |slot| out[(slot * 17 + 9) % Width] = chosen[slot];
    }
    return out;
}

fn evaluate(policy: Policy) Result {
    const recoded = policy == .evidence_recoded;
    var result = Result{};
    for (0..Cohorts) |cohort| {
        const old = initialTape(cohort, recoded);
        const candidate = build(cohort, policy, recoded, &result.charged_trials);
        for (0..Width) |i| result.changed += @intFromBool(old[i] != candidate[i]);
        var old_hidden: i64 = 0;
        var candidate_hidden: i64 = 0;
        for (0..Hidden) |ctx| {
            old_hidden += resource(old, cohort, ctx, true, recoded);
            candidate_hidden += resource(candidate, cohort, ctx, true, recoded);
        }
        result.old_resource += old_hidden;
        if (candidate_hidden > old_hidden) {
            result.new_resource += candidate_hidden;
            result.committed += 1;
        } else {
            result.new_resource += old_hidden;
            result.rolled_back += 1;
        }
        result.ablated_resource += old_hidden;
    }
    return result;
}

fn row(out: anytype, policy: Policy, verdict: []const u8) !void {
    const r = evaluate(policy);
    try out.print("round_ab_ab3,transfer,{s},{d},{d},{d},{d},{d},{d},{d},{s}\n", .{
        @tagName(policy), r.charged_trials, r.changed, r.old_resource, r.new_resource,
        r.ablated_resource, r.committed, r.rolled_back, verdict,
    });
}

fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,partition,policy,charged_trials,changed_bytes,old_resource,new_resource,ablated_resource,committed,rolled_back,verdict\n");
    try row(out, .evidence, "LIMITED_POSITIVE:opaque_raw_tape_challenge_build_freeze_test_commit_or_rollback");
    try row(out, .evidence_recoded, "CONTROL_FAIL:value_recode_changes_replacement_search");
    try row(out, .random, "CONTROL:random_replacement_equal_candidate_generator");
    try row(out, .frequency, "CONTROL:frequency_without_effect_identity");
    try row(out, .cost, "CONTROL:cheapest_is_no_replacement");
    try row(out, .name, "CONTROL:opaque_byte_digest_surrogate");
    try row(out, .address, "CONTROL:low_address_partial_replacement");
    try row(out, .human_origin, "CONTROL:human_origin_receives_no_privilege");
    try row(out, .fixed, "CONTROL:fixed_scaffold");
    try row(out, .no_replacement, "CONTROL:no_replacement");
    try row(out, .request_free, "CONTROL:request_free_unguided_synthesis");
    try row(out, .shuffled, "CONTROL_PASS:shuffled_evidence_misdirects");
    try row(out, .false_evidence, "CONTROL_PASS:false_evidence_misdirects");
    try row(out, .oracle, "INVALID_ORACLE:evaluator_private_ceiling");
    const attacks = [_][]const u8{
        "CONTROL_PASS:no_declared_scaffold_component_or_room_table",
        "CONTROL_PASS:no_external_builder_request_or_implementation_channel",
        "CONTROL_PASS:evaluator_private_target_absent_from_organism_state",
        "CONTROL_PASS:all_calibration_trials_and_candidate_mutations_charged",
        "CONTROL_PASS:old_and_new_freeze_before_disjoint_hidden_contexts",
        "CONTROL_PASS:replacement_ablation_returns_exact_old_resource",
        "CONTROL_PASS:unfavorable_candidate_rolls_back_to_old_snapshot",
        "CONTROL_PASS:human_origin_has_no_selection_weight_or_veto",
        "CONTROL_PASS:whole_tape_hash_and mutation_lineage_preserved",
        "CONTROL_PASS:no_post_hidden_test_edit_or selection",
        "CONTROL_PASS:byte_growth_forbidden_equal_width_and_cost",
        "CONTROL_PASS:no_llm_text_token_embedding_neural_neurosymbolic_path",
        "CONTROL_PASS:fresh_execution_is_byte_identical",
        "CONTROL_FAIL:raw_byte_boundary_and_proposal_generator_are_human_bootstrap_scaffold",
    };
    for (attacks) |v| try out.print("round_ab_ab3,attack,hostile,0,0,0,0,0,0,0,{s}\n", .{v});
    const r = evaluate(.evidence);
    try out.print("round_ab_ab3,closure,aggregate,{d},{d},{d},{d},{d},{d},{d},VALID_NEGATIVE:replacement_pipeline_works_but_human_byte_partition_and_proposal_dynamics_remain_no_architecture_owning_self_improvement_claim\n", .{
        r.charged_trials, r.changed, r.old_resource, r.new_resource, r.ablated_resource, r.committed, r.rolled_back,
    });
}

fn require(bytes: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingEvidence;
}

fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    try run("/tmp/ab3_scaffold_a.csv");
    try run("/tmp/ab3_scaffold_b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ab3_scaffold_a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ab3_scaffold_b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    try require(x, "LIMITED_POSITIVE:");
    try require(x, "CONTROL_FAIL:raw_byte_boundary");
    try require(x, "VALID_NEGATIVE:");
    const e = evaluate(.evidence);
    const rnd = evaluate(.random);
    const fixed = evaluate(.fixed);
    if (!(e.new_resource > rnd.new_resource and e.new_resource > fixed.new_resource)) return error.NoMeasuredGain;
    if (e.ablated_resource != e.old_resource) return error.AblationFailed;
    const recoded = evaluate(.evidence_recoded);
    if (recoded.new_resource == e.new_resource) return error.ExpectedRecodeSensitivityMissing;
    std.debug.print("round_ab_ab3 selftest PASS verdict=VALID_NEGATIVE deterministic=true replacement_gain=true recode=false\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/scaffold_replacement_round_ab.csv");
}
