//! Round AN / AN3: answer-key-free open discovery-record admission gate.
//!
//! This is deliberately an evaluation protocol, not an inventor.  It admits a
//! record only after the record was frozen before an intervention, predicts raw
//! observable outcomes, carries append-only provenance, replicates in a held-out
//! recoding/condition, and confronts both attacker and simpler alternatives.
//! There is no target-answer comparison and no candidate ranking channel.
const std = @import("std");

const Decision = enum { admit, reject };

const Record = struct {
    name: []const u8,
    // Required, pre-intervention record components.
    precommitted: bool = false,
    claim_present: bool = false,
    raw_prediction_present: bool = false,
    generic_intervention_protocol_present: bool = false,
    append_only_provenance_present: bool = false,
    heldout_recoding_replication: bool = false,
    heldout_condition_replication: bool = false,
    attacker_alternative_tested: bool = false,
    simplicity_alternative_tested: bool = false,
    intervention_changed_predicted_raw_observation: bool = false,

    // Disqualifying channels or process failures.
    answer_key_or_target: bool = false,
    label_or_semantic_decoder: bool = false,
    training_data_or_answer_trace: bool = false,
    posthoc_claim_rewrite: bool = false,
    evaluator_feedback_during_discovery: bool = false,
    correlation_only: bool = false,
    private_world_or_test_overlap: bool = false,
};

// Stable, deny-by-default priority: a report has one primary rejection reason.
fn rejectReason(r: Record) ?[]const u8 {
    if (r.answer_key_or_target) return "REJECT:answer_key_or_human_target_channel";
    if (r.label_or_semantic_decoder) return "REJECT:label_or_semantic_decoder_channel";
    if (r.training_data_or_answer_trace) return "REJECT:training_data_or_answer_trace";
    if (r.posthoc_claim_rewrite) return "REJECT:posthoc_claim_rewrite";
    if (r.evaluator_feedback_during_discovery) return "REJECT:evaluator_feedback_during_discovery";
    if (r.private_world_or_test_overlap) return "REJECT:private_world_or_test_overlap";
    if (!r.precommitted) return "REJECT:not_precommitted_before_intervention";
    if (!r.claim_present) return "REJECT:missing_falsifiable_claim";
    if (!r.raw_prediction_present) return "REJECT:missing_raw_outcome_prediction";
    if (!r.generic_intervention_protocol_present) return "REJECT:missing_intervention_protocol";
    if (!r.append_only_provenance_present) return "REJECT:missing_append_only_provenance";
    if (r.correlation_only) return "REJECT:correlation_only_no_intervention";
    if (!r.intervention_changed_predicted_raw_observation) return "REJECT:prediction_not_realized_after_intervention";
    if (!r.heldout_recoding_replication) return "REJECT:failed_heldout_recoding_replication";
    if (!r.heldout_condition_replication) return "REJECT:failed_heldout_condition_replication";
    if (!r.attacker_alternative_tested) return "REJECT:attacker_alternative_not_tested";
    if (!r.simplicity_alternative_tested) return "REJECT:simplicity_alternative_not_tested";
    return null;
}

fn decide(r: Record) Decision {
    return if (rejectReason(r) == null) .admit else .reject;
}

const causal = Record{
    .name = "precommitted_intervention_changes_delayed_raw_signal",
    .precommitted = true,
    .claim_present = true,
    .raw_prediction_present = true,
    .generic_intervention_protocol_present = true,
    .append_only_provenance_present = true,
    .heldout_recoding_replication = true,
    .heldout_condition_replication = true,
    .attacker_alternative_tested = true,
    .simplicity_alternative_tested = true,
    .intervention_changed_predicted_raw_observation = true,
};

const fixtures = [_]Record{
    causal,
    .{ .name = "answer_key_match", .precommitted = true, .claim_present = true, .raw_prediction_present = true, .generic_intervention_protocol_present = true, .append_only_provenance_present = true, .heldout_recoding_replication = true, .heldout_condition_replication = true, .attacker_alternative_tested = true, .simplicity_alternative_tested = true, .intervention_changed_predicted_raw_observation = true, .answer_key_or_target = true },
    .{ .name = "memorized_training_trace", .precommitted = true, .claim_present = true, .raw_prediction_present = true, .generic_intervention_protocol_present = true, .append_only_provenance_present = true, .heldout_recoding_replication = true, .heldout_condition_replication = true, .attacker_alternative_tested = true, .simplicity_alternative_tested = true, .intervention_changed_predicted_raw_observation = true, .training_data_or_answer_trace = true },
    .{ .name = "posthoc_rewritten_claim", .claim_present = true, .raw_prediction_present = true, .generic_intervention_protocol_present = true, .append_only_provenance_present = true, .heldout_recoding_replication = true, .heldout_condition_replication = true, .attacker_alternative_tested = true, .simplicity_alternative_tested = true, .intervention_changed_predicted_raw_observation = true, .posthoc_claim_rewrite = true },
    .{ .name = "correlation_without_intervention", .precommitted = true, .claim_present = true, .raw_prediction_present = true, .generic_intervention_protocol_present = true, .append_only_provenance_present = true, .heldout_recoding_replication = true, .heldout_condition_replication = true, .attacker_alternative_tested = true, .simplicity_alternative_tested = true, .correlation_only = true },
    .{ .name = "failed_heldout_replication", .precommitted = true, .claim_present = true, .raw_prediction_present = true, .generic_intervention_protocol_present = true, .append_only_provenance_present = true, .heldout_recoding_replication = false, .heldout_condition_replication = true, .attacker_alternative_tested = true, .simplicity_alternative_tested = true, .intervention_changed_predicted_raw_observation = true },
    .{ .name = "semantic_decoder_channel", .precommitted = true, .claim_present = true, .raw_prediction_present = true, .generic_intervention_protocol_present = true, .append_only_provenance_present = true, .heldout_recoding_replication = true, .heldout_condition_replication = true, .attacker_alternative_tested = true, .simplicity_alternative_tested = true, .intervention_changed_predicted_raw_observation = true, .label_or_semantic_decoder = true },
    .{ .name = "evaluator_feedback_loop", .precommitted = true, .claim_present = true, .raw_prediction_present = true, .generic_intervention_protocol_present = true, .append_only_provenance_present = true, .heldout_recoding_replication = true, .heldout_condition_replication = true, .attacker_alternative_tested = true, .simplicity_alternative_tested = true, .intervention_changed_predicted_raw_observation = true, .evaluator_feedback_during_discovery = true },
    .{ .name = "no_attacker_alternative", .precommitted = true, .claim_present = true, .raw_prediction_present = true, .generic_intervention_protocol_present = true, .append_only_provenance_present = true, .heldout_recoding_replication = true, .heldout_condition_replication = true, .simplicity_alternative_tested = true, .intervention_changed_predicted_raw_observation = true },
    .{ .name = "no_simplicity_alternative", .precommitted = true, .claim_present = true, .raw_prediction_present = true, .generic_intervention_protocol_present = true, .append_only_provenance_present = true, .heldout_recoding_replication = true, .heldout_condition_replication = true, .attacker_alternative_tested = true, .intervention_changed_predicted_raw_observation = true },
};

fn emit(out: anytype, r: Record) !void {
    const verdict = rejectReason(r) orelse "ADMIT:precommitted_causal_claim_replicated_without_answer_key_or_human_invention_match";
    try out.print("round_an_an3,{s},{s},{s}\n", .{ r.name, @tagName(decide(r)), verdict });
}

fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,fixture,decision,verdict\n");
    for (fixtures) |r| try emit(out, r);
    const rules = [_][]const u8{
        "SOURCE_RULE:no_answer_key_target_candidate_ranking_or_human_preferred_invention_comparison",
        "SOURCE_RULE:require_precommitted_claim_raw_prediction_intervention_provenance_and_heldout_replication",
        "SOURCE_RULE:require_attacker_and_simplicity_alternatives",
        "SOURCE_RULE:reject_labels_semantic_decoders_training_traces_posthoc_rewrites_feedback_and_world_overlap",
        "COVERAGE:one_causal_admission_nine_required_rejections",
        "GATE_READY:evaluation_protocol_only_not_proof_of_autonomous_invention_or_novelty",
    };
    for (rules) |rule| try out.print("round_an_an3,audit,admit,{s}\n", .{rule});
}

fn selftest() !void {
    try run("/tmp/an3-open-discovery-a.csv");
    try run("/tmp/an3-open-discovery-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const a = try std.fs.cwd().readFileAlloc(allocator, "/tmp/an3-open-discovery-a.csv", 1 << 20);
    defer allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(allocator, "/tmp/an3-open-discovery-b.csv", 1 << 20);
    defer allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    var admitted: usize = 0;
    var rejected: usize = 0;
    for (fixtures) |r| switch (decide(r)) { .admit => admitted += 1, .reject => rejected += 1 };
    if (admitted != 1 or rejected != 9) return error.InvalidFixtureCoverage;
    if (std.mem.indexOf(u8, a, "answer_key_or_human_target") == null) return error.MissingNoAnswerRule;
    std.debug.print("round_an_an3 selftest PASS deterministic=true causal_admits=1 required_rejects=9 verdict=GATE_READY residual=evaluation_protocol_not_autonomous_invention\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/open_discovery_protocol_round_an.csv");
}
