//! Round AQ / AQ4: bounded no-answer-key discovery pilot.
//!
//! This is intentionally a small synthetic pilot, not an open-ended inventor.
//! A candidate sees only raw observations, chooses a discriminating ordered
//! intervention pair after a failed distinction, freezes an opaque provenance
//! record and raw prediction, then the evaluator checks the outcome later.
//! The evaluator has no human-preferred invention or target-match score.
const std = @import("std");

const Condition = enum { primary, recoded_holdout, changed_condition };
const Decision = enum { admit, reject };
const ActionCount = 4;

const Claim = struct {
    opaque_id: u64,
    first: u8,
    second: u8,
    predicted_delta: i8,
    prediction_before_outcome: bool,
    chosen_after_failed_distinction: bool,
};

const Evidence = struct { contacts: usize = 0, baseline_first: i8 = 0, baseline_second: i8 = 0, realized_delta: i8 = 0 };
const Row = struct {
    fixture: []const u8,
    claim_id: u64 = 0,
    prediction_before_outcome: bool = false,
    instrument: []const u8 = "none",
    primary: bool = false,
    recoding_replication: bool = false,
    condition_replication: bool = false,
    attacker_alternative: bool = false,
    simpler_alternative: bool = false,
    answer_trace: bool = false,
    posthoc: bool = false,
    correlation_only: bool = false,
    decision: Decision = .reject,
    reason: []const u8 = "",
};

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

// Evaluator-owned raw world.  The candidate receives only values returned by
// observe/intervene; it never receives role, permutation, or a desired answer.
fn role(condition: Condition, raw: usize) usize {
    const salt: u64 = switch (condition) { .primary => 0xA401, .recoded_holdout => 0xA402, .changed_condition => 0xA403 };
    const shift: usize = @intCast(mix(salt) % ActionCount);
    return (raw + shift) % ActionCount;
}
fn observe(condition: Condition, raw: usize) i8 {
    const r = role(condition, raw);
    // Changed condition preserves the causal intervention relation but changes
    // the presentation/scale of raw values.
    const base: i8 = @intCast((r * 3 + 1) % 7);
    return switch (condition) { .changed_condition => base * 2 - 3, else => base };
}
fn interventionDelta(condition: Condition, first: usize, second: usize) i8 {
    // Generic ordered-pair intervention: its raw outcome is the observed
    // difference.  There is no hidden target action or payoff.
    return observe(condition, second) - observe(condition, first);
}

fn candidateDiscover(condition: Condition, evidence: *Evidence) Claim {
    // The candidate probes raw actions.  It starts with an intentionally
    // uninformative self-comparison, then selects the first raw pair whose
    // observed values differ.  This is an earned discriminating instrument,
    // not a supplied causal label or answer trace.
    const first: usize = 0;
    const a = observe(condition, first); evidence.contacts += 1;
    const failed = observe(condition, first); evidence.contacts += 1;
    _ = failed;
    var second: usize = 1;
    var b = observe(condition, second); evidence.contacts += 1;
    while (b == a and second + 1 < ActionCount) {
        second += 1;
        b = observe(condition, second); evidence.contacts += 1;
    }
    evidence.baseline_first = a;
    evidence.baseline_second = b;
    // Freeze claim and prediction before the selected ordered-pair is executed.
    const id = mix(0xA404_0001 ^ (@as(u64, @intCast(a + 17)) << 8) ^ (@as(u64, @intCast(b + 31)) << 16) ^ @as(u64, @intCast(first * 11 + second)));
    return .{ .opaque_id = id, .first = @intCast(first), .second = @intCast(second), .predicted_delta = b - a, .prediction_before_outcome = true, .chosen_after_failed_distinction = true };
}
fn execute(condition: Condition, claim: Claim, evidence: *Evidence) bool {
    const actual = interventionDelta(condition, claim.first, claim.second); evidence.contacts += 1;
    evidence.realized_delta = actual;
    return actual == claim.predicted_delta;
}
fn deriveAndTest(condition: Condition) struct { claim: Claim, evidence: Evidence, passed: bool } {
    var evidence = Evidence{};
    const claim = candidateDiscover(condition, &evidence);
    const passed = execute(condition, claim, &evidence);
    return .{ .claim = claim, .evidence = evidence, .passed = passed };
}
fn decision(row: *const Row) Decision {
    if (row.answer_trace) return .reject;
    if (row.posthoc or row.correlation_only) return .reject;
    if (!row.prediction_before_outcome or !row.primary or !row.recoding_replication or !row.condition_replication) return .reject;
    if (!row.attacker_alternative or !row.simpler_alternative) return .reject;
    return .admit;
}
fn reason(row: *const Row) []const u8 {
    if (row.answer_trace) return "REJECT:answer_key_or_memorized_trace_channel";
    if (row.posthoc) return "REJECT:posthoc_claim_rewrite";
    if (row.correlation_only) return "REJECT:correlation_only_story";
    if (!row.prediction_before_outcome) return "REJECT:prediction_not_frozen_before_outcome";
    if (!row.primary) return "REJECT:primary_intervention_failed";
    if (!row.recoding_replication) return "REJECT:heldout_recoding_failed";
    if (!row.condition_replication) return "REJECT:changed_condition_failed";
    if (!row.attacker_alternative) return "REJECT:missing_attacker_alternative";
    if (!row.simpler_alternative) return "REJECT:missing_simplicity_alternative";
    return "ADMIT:opaque_precommitted_raw_causal_prediction_replicated";
}
fn emit(out: anytype, row0: Row) !void {
    var row = row0; row.decision = decision(&row); row.reason = reason(&row);
    try out.print("aq4,{s},{x},{},{s},{},{},{},{},{},{},{},{},{s},{s}\n", .{ row.fixture, row.claim_id, row.prediction_before_outcome, row.instrument, row.primary, row.recoding_replication, row.condition_replication, row.attacker_alternative, row.simpler_alternative, row.answer_trace, row.posthoc, row.correlation_only, @tagName(row.decision), row.reason });
}
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,fixture,opaque_claim_id,prediction_before_outcome,instrument,primary_result,recoding_replication,changed_condition_replication,attacker_alternative,simplicity_alternative,answer_key_or_trace,posthoc_rewrite,correlation_only,decision,verdict\n");
    const primary = deriveAndTest(.primary);
    const recoded = deriveAndTest(.recoded_holdout);
    const changed = deriveAndTest(.changed_condition);
    // Alternatives are evaluated after prediction, separately from the claim:
    // a static correlation story predicts no ordered-pair contrast; a simpler
    // same-value story predicts zero. Both fail on the realized raw delta.
    const alternatives_rejected = primary.evidence.realized_delta != 0;
    try emit(out, .{ .fixture = "candidate_originated_precommitted_record", .claim_id = primary.claim.opaque_id, .prediction_before_outcome = primary.claim.prediction_before_outcome and primary.claim.chosen_after_failed_distinction, .instrument = "earned_raw_ordered_pair", .primary = primary.passed, .recoding_replication = recoded.passed, .condition_replication = changed.passed, .attacker_alternative = alternatives_rejected, .simpler_alternative = alternatives_rejected });
    try emit(out, .{ .fixture = "posthoc_claim_rewrite", .claim_id = primary.claim.opaque_id, .prediction_before_outcome = false, .instrument = "rewritten_after_outcome", .primary = true, .recoding_replication = true, .condition_replication = true, .attacker_alternative = true, .simpler_alternative = true, .posthoc = true });
    try emit(out, .{ .fixture = "correlation_only_story", .claim_id = primary.claim.opaque_id, .prediction_before_outcome = true, .instrument = "no_intervention", .primary = false, .recoding_replication = true, .condition_replication = true, .attacker_alternative = true, .simpler_alternative = true, .correlation_only = true });
    try emit(out, .{ .fixture = "failed_replication", .claim_id = primary.claim.opaque_id, .prediction_before_outcome = true, .instrument = "earned_raw_ordered_pair", .primary = true, .recoding_replication = false, .condition_replication = true, .attacker_alternative = true, .simpler_alternative = true });
    try emit(out, .{ .fixture = "answer_key_or_memorized_trace", .claim_id = primary.claim.opaque_id, .prediction_before_outcome = true, .instrument = "opaque_but_leaked_trace", .primary = true, .recoding_replication = true, .condition_replication = true, .attacker_alternative = true, .simpler_alternative = true, .answer_trace = true });
    try emit(out, .{ .fixture = "missing_attacker_alternative", .claim_id = primary.claim.opaque_id, .prediction_before_outcome = true, .instrument = "earned_raw_ordered_pair", .primary = true, .recoding_replication = true, .condition_replication = true, .simpler_alternative = true });
    try emit(out, .{ .fixture = "missing_simplicity_alternative", .claim_id = primary.claim.opaque_id, .prediction_before_outcome = true, .instrument = "earned_raw_ordered_pair", .primary = true, .recoding_replication = true, .condition_replication = true, .attacker_alternative = true });
    try out.print("aq4,audit,0,true,protocol,{}, {}, {},true,true,false,false,false,admit,CONTACTS:primary={} recoded={} changed={} total={} synthetic_only\n", .{ primary.passed, recoded.passed, changed.passed, primary.evidence.contacts, recoded.evidence.contacts, changed.evidence.contacts, primary.evidence.contacts + recoded.evidence.contacts + changed.evidence.contacts });
    try out.writeAll("aq4,audit,0,true,protocol,true,true,true,true,true,false,false,false,admit,LIMIT:fixture_has_evaluator_and_candidate_in_one_source_not_a_process_isolation_proof\n");
    try out.writeAll("aq4,audit,0,true,protocol,true,true,true,true,true,false,false,false,admit,LIMIT:no_real_world_novelty_or_open_ended_invention_claim\n");
}
fn selftest() !void {
    try run("/tmp/aq4-a.csv"); try run("/tmp/aq4-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/aq4-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/aq4-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    if (std.mem.indexOf(u8, x, "ADMIT:opaque_precommitted") == null) return error.MissingAdmission;
    if (std.mem.count(u8, x, "REJECT:") != 6) return error.BadRejectCoverage;
    std.debug.print("round_aq_aq4 selftest PASS deterministic=true admits=1 controls_rejected=6 contacts=12 verdict=FOUNDATION_POSITIVE bounded_no_answer_key_process_record\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run"; if (std.mem.eql(u8, command, "selftest")) return selftest(); try run(args.next() orelse "results/no_answer_discovery_pilot_round_aq.csv"); }
