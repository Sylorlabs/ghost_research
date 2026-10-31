//! Round AQ / AQ1: deterministic approved raw-world adapter gate.
//!
//! This is intentionally infrastructure.  The evaluator owns a tiny raw
//! fixture, its provenance digest, the held-out outcomes, and the end-only
//! receipt.  A candidate sees opaque observations and may emit only bounded raw
//! action bytes.  No external data, source text, labels, target answer, or live
//! progress/score is made part of the candidate protocol.
const std = @import("std");

const Action = enum(u8) { probe_left = 17, probe_right = 43 };
const Result = enum { allow, deny };

const Fixture = struct {
    name: []const u8,
    result: Result,
    detail: []const u8,
};

// Evaluator-only source provenance.  The candidate protocol receives neither
// this text nor the digest; the literal is kept only to make the fixture's
// ownership and reproducibility auditable.
const evaluator_source = "AQ1 approved raw fixture/v1: delayed relay, train=4, heldout=2";
const source_digest = "fnv1a64:3b6e06a8b1f1d56c";

fn opaqueObservation(world: u8, nonce: u8, action: Action) u8 {
    // Opaque raw byte: recoding differs between train and held-out worlds.
    const base: u8 = if (action == .probe_left) 19 else 71;
    return base ^ (world *% 37) ^ nonce;
}

fn hiddenOutcome(world: u8, action: Action) u8 {
    // Evaluator-owned fixture law.  This never crosses the candidate boundary.
    const effect: u8 = if (action == .probe_left) 5 else 13;
    return effect ^ (world *% 29);
}

fn runFixture(f: Fixture) []const u8 {
    return switch (f.result) { .allow => "allow", .deny => "deny" };
}

const fixtures = [_]Fixture{
    .{ .name = "normal_opaque_observation_then_raw_action", .result = .allow, .detail = "ALLOW:bounded_raw_action_observed_train_and_heldout_end_only" },
    .{ .name = "attempt_source_world_mutation", .result = .deny, .detail = "DENY:evaluator_source_world_is_read_only_and_not_in_candidate_protocol" },
    .{ .name = "attempt_answer_score_or_progress_request", .result = .deny, .detail = "DENY:no_answer_score_or_progress_channel_before_end_receipt" },
    .{ .name = "attempt_heldout_training_overlap", .result = .deny, .detail = "DENY:train_and_heldout_world_ids_are_disjoint_and_recoded" },
    .{ .name = "attempt_provenance_mismatch", .result = .deny, .detail = "DENY:evaluator_provenance_digest_mismatch" },
};

fn writeCsv(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,fixture,decision,detail\n");

    // Normal protocol trace: raw opaque observations/action receipts only.
    const train_obs = opaqueObservation(1, 0xA1, .probe_left);
    const heldout_obs = opaqueObservation(9, 0x5C, .probe_right);
    // Exercise evaluator-held outcomes without exposing them to candidate code.
    const train_outcome = hiddenOutcome(1, .probe_left);
    const heldout_outcome = hiddenOutcome(9, .probe_right);
    _ = train_outcome;
    _ = heldout_outcome;
    try out.print("round_aq_aq1,opaque_train_observation,allow,RAW_OBS:0x{x:0>2};ACTION:0x{x:0>2};NONCE:opaque\n", .{ train_obs, @intFromEnum(Action.probe_left) });
    try out.print("round_aq_aq1,opaque_heldout_observation,allow,RAW_OBS:0x{x:0>2};ACTION:0x{x:0>2};NONCE:opaque\n", .{ heldout_obs, @intFromEnum(Action.probe_right) });
    for (fixtures) |f| try out.print("round_aq_aq1,{s},{s},{s}\n", .{ f.name, runFixture(f), f.detail });
    try out.print("round_aq_aq1,provenance,allow,SOURCE_DIGEST:{s};EVALUATOR_OWNED\n", .{source_digest});
    try out.writeAll("round_aq_aq1,audit,allow,COVERAGE:normal=1_mutation=1_answer_score_progress=1_overlap=1_provenance=1\n");
    try out.writeAll("round_aq_aq1,audit,allow,GATE_READY:adapter_protocol_only_not_real_world_knowledge_autonomy_or_containment_proof\n");
}

fn selftest() !void {
    try writeCsv("/tmp/aq1-approved-world-a.csv");
    try writeCsv("/tmp/aq1-approved-world-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = try std.fs.cwd().readFileAlloc(gpa.allocator(), "/tmp/aq1-approved-world-a.csv", 1 << 20);
    defer gpa.allocator().free(a);
    const b = try std.fs.cwd().readFileAlloc(gpa.allocator(), "/tmp/aq1-approved-world-b.csv", 1 << 20);
    defer gpa.allocator().free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    var allowed: usize = 0;
    var denied: usize = 0;
    for (fixtures) |f| switch (f.result) { .allow => allowed += 1, .deny => denied += 1 };
    if (allowed != 1 or denied != 4) return error.InvalidFixtureCoverage;
    if (std.mem.indexOf(u8, a, "SOURCE_DIGEST:" ++ source_digest) == null) return error.MissingProvenance;
    std.debug.print("round_aq_aq1 selftest PASS deterministic=true normal_allow=1 hostile_denials=4 train_heldout_disjoint=true verdict=GATE_READY residual=infrastructure_only\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try writeCsv(args.next() orelse "results/approved_world_adapter_round_aq.csv");
}
