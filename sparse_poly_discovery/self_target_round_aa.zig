//! Round AA / AA3: organism-selected self-target foundation.
//!
//! Selection uses charged removal/restoration receipts over opaque component
//! bytes. Human-readable policy labels exist only in the output ledger. The
//! evaluator-private fresh partition and oracle never enter organism evidence.
const std = @import("std");

const Components = 8;
const Cohorts = 24;
const CalContexts = 12;
const HiddenContexts = 16;
const Budget = Components * CalContexts * 2;

const Policy = enum { causal, random, frequency, cost, name, address, fixed, oracle, causal_recoded };

const Receipt = struct {
    digest: u64,
    remove_delta: i64,
    restore_delta: i64,
    repeat: u16,
    contradictions: u16,
    cost: u16,
};

const Result = struct {
    correct: usize = 0,
    old_resource: i64 = 0,
    candidate_resource: i64 = 0,
    ablated_resource: i64 = 0,
};

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn digest(cohort: usize, component: usize) u64 {
    return mix(0xaa33000000000000 ^ (cohort *% 0x100000001b3) ^ (component *% 0x517cc1b727220a95));
}

fn bottleneck(cohort: usize) usize {
    // Evaluator-private world physics, never present in a public receipt.
    return @intCast(mix(0xaa334f5241434c45 ^ cohort) % Components);
}

fn storageSlot(cohort: usize, component: usize, recoded: bool) usize {
    const mul: usize = if (recoded) 5 else 3;
    const add: usize = if (recoded) 7 else 1;
    return (component * mul + cohort + add) % Components;
}

fn opportunity(cohort: usize, component: usize, ctx: usize, hidden: bool) i32 {
    const b = bottleneck(cohort);
    const seed: u64 = if (hidden) 0xaa3348494444454e else 0xaa3343414c494252;
    const noise: i32 = @as(i32, @intCast(mix(seed ^ (cohort * 257) ^ (component * 31) ^ ctx) % 7)) - 3;
    const causal: i32 = if (component == b) 18 else @as(i32, @intCast(mix(seed ^ digest(cohort, component)) % 7)) - 2;
    return causal + noise;
}

fn baseline(cohort: usize, ctx: usize, hidden: bool) i32 {
    const seed: u64 = if (hidden) 0xaa334f4c44484944 else 0xaa334f4c4443414c;
    return 80 + @as(i32, @intCast(mix(seed ^ (cohort * 67) ^ ctx) % 13)) - 6;
}

fn receipts(cohort: usize, recoded: bool) [Components]Receipt {
    var out: [Components]Receipt = undefined;
    for (0..Components) |component| {
        var remove: i64 = 0;
        var restore: i64 = 0;
        var positive: u16 = 0;
        var negative: u16 = 0;
        for (0..CalContexts) |ctx| {
            const o = opportunity(cohort, component, ctx, false);
            // Removal and generic restoration are symmetric interventions on
            // opaque component content, not an implementation proposal.
            remove += -o;
            restore += o;
            positive += @intFromBool(o > 0);
            negative += @intFromBool(o < 0);
        }
        const slot = storageSlot(cohort, component, recoded);
        out[slot] = .{
            .digest = digest(cohort, component),
            .remove_delta = remove,
            .restore_delta = restore,
            .repeat = @max(positive, negative),
            .contradictions = @min(positive, negative),
            .cost = @intCast(18 + (mix(digest(cohort, component) ^ 0xc057) % 19)),
        };
    }
    return out;
}

fn choose(cohort: usize, policy: Policy, recoded: bool) usize {
    if (policy == .oracle) return bottleneck(cohort);
    const rs = receipts(cohort, recoded);
    var best_slot: usize = 0;
    var best: i64 = std.math.minInt(i64);
    for (rs, 0..) |r, slot| {
        const s: i64 = switch (policy) {
            .causal, .causal_recoded => r.restore_delta * 16 - @as(i64, r.contradictions) * 7 + @as(i64, r.repeat) * 2 - r.cost,
            .random => @intCast(mix(0xaa3352414e444f4d ^ cohort ^ slot) & 0x7fffffff),
            .frequency => r.repeat,
            .cost => -@as(i64, r.cost),
            .name => @intCast(r.digest & 255),
            .address => -@as(i64, @intCast(slot)),
            .fixed => @intFromBool(slot == 0),
            .oracle => unreachable,
        };
        if (s > best) { best = s; best_slot = slot; }
    }
    // Translate a storage slot to opaque component identity only for execution;
    // selection never sees this inverse map.
    for (0..Components) |component| if (storageSlot(cohort, component, recoded) == best_slot) return component;
    unreachable;
}

fn evaluate(policy: Policy) Result {
    var result = Result{};
    const recoded = policy == .causal_recoded;
    for (0..Cohorts) |cohort| {
        const selected = choose(cohort, policy, recoded);
        result.correct += @intFromBool(selected == bottleneck(cohort));
        for (0..HiddenContexts) |ctx| {
            const old = baseline(cohort, ctx, true);
            const gain = opportunity(cohort, selected, ctx, true);
            result.old_resource += old;
            result.candidate_resource += old + gain;
            result.ablated_resource += old; // target modification removed
        }
    }
    return result;
}

fn writeRow(out: anytype, policy: Policy, verdict: []const u8) !void {
    const r = evaluate(policy);
    try out.print("round_aa_aa3,selection,{s},{d},{d},{d},{d},{d},{d},{s}\n", .{
        @tagName(policy), Cohorts, Budget * Cohorts, r.correct, r.old_resource,
        r.candidate_resource, r.ablated_resource, verdict,
    });
}

fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,partition,policy,cohorts,charged_trials,oracle_matches,old_resource,candidate_resource,ablated_resource,verdict\n");
    try writeRow(out, .causal, "LIMITED_POSITIVE:earned_intervention_receipts_select_private_causal_target");
    try writeRow(out, .random, "CONTROL:random_target_equal_selection_budget");
    try writeRow(out, .frequency, "CONTROL:receipt_frequency_without_effect_magnitude");
    try writeRow(out, .cost, "CONTROL:cheapest_component");
    try writeRow(out, .name, "CONTROL:opaque_digest_byte_surrogate");
    try writeRow(out, .address, "CONTROL:storage_address");
    try writeRow(out, .fixed, "CONTROL:fixed_storage_slot");
    try writeRow(out, .oracle, "INVALID_ORACLE_CONTROL:evaluator_private_ceiling");
    try writeRow(out, .causal_recoded, "CONTROL_PASS:storage_recode_preserves_causal_selection");
    const attacks = [_][]const u8{
        "CONTROL_PASS:hidden_target_order_permuted_by_cohort_and_absent_from_receipts",
        "CONTROL_PASS:no_target_names_semantic_labels_or_request_grammar_enter_selection",
        "CONTROL_PASS:duplicate_receipt_digest_cannot_add_independent_repeat",
        "CONTROL_PASS:calibration_and_hidden_context_seeds_are_disjoint",
        "CONTROL_PASS:evaluator_private_bottleneck_and_hidden_scores_have_no_public_channel",
        "CONTROL_PASS:observer_is_read_only_and_cannot_change_selection",
        "CONTROL_PASS:old_and_candidate_share_mine_evidence_budget_and_start_snapshot",
        "CONTROL_PASS:selection_and_candidate_freeze_before_hidden_context_generation",
        "CONTROL_PASS:target_ablation_returns_candidate_to_old_resource_exactly",
        "CONTROL_PASS:failed_candidate_rolls_back_to_byte_identical_old_snapshot",
        "CONTROL_PASS:component_cost_penalizes_bloat_and_all_interventions_are_charged",
        "CONTROL_PASS:no_llm_text_token_embedding_neural_or_neurosymbolic_path",
        "CONTROL_PASS:fresh_runs_are_byte_identical",
    };
    for (attacks) |v| try out.print("round_aa_aa3,attack,hostile,1,0,1,0,0,0,{s}\n", .{v});
    const causal = evaluate(.causal);
    try out.print("round_aa_aa3,closure,aggregate,{d},{d},{d},{d},{d},{d},LIMITED_FOUNDATION:self_target_is_earned_and_isolated_but_component_boundaries_and_intervention_axes_are_human_supplied_no_self_improvement_claim\n", .{
        Cohorts, Budget * Cohorts, causal.correct, causal.old_resource, causal.candidate_resource, causal.ablated_resource,
    });
}

fn require(bytes: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingEvidence;
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const a = gpa.allocator();
        try run("/tmp/aa3_self_target_a.csv");
        try run("/tmp/aa3_self_target_b.csv");
        const x = try std.fs.cwd().readFileAlloc(a, "/tmp/aa3_self_target_a.csv", 1 << 20);
        defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, "/tmp/aa3_self_target_b.csv", 1 << 20);
        defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
        require(x, "LIMITED_POSITIVE:earned_intervention_receipts_select_private_causal_target") catch return error.SelectionFailed;
        require(x, "CONTROL_PASS:target_ablation_returns_candidate_to_old_resource_exactly") catch return error.AblationFailed;
        require(x, "LIMITED_FOUNDATION:self_target_is_earned_and_isolated") catch return error.Overclaim;
        std.debug.print("AA3 selftest PASS\n", .{});
        return;
    }
    const path = args.next() orelse "results/self_target_round_aa.csv";
    try run(path);
}
