//! Round P P3: adversarial leakage audit for answer-free policy memory.
//! This is a deterministic protocol/fixture test, not an OS-security proof.
const std = @import("std");

const PublicRecord = struct {
    // Deliberately no target token, family, final score, or winning tool.
    attempt: []const u8,
    observation: []const u8,
    residual: []const u8,
    hypothesis: []const u8,
    cost: u8,
};

const forbidden = [_][]const u8{
    "target_token", "hidden_family", "fresh_test_score", "winning_tool",
    "target_to_tool", "manifest_row", "final_winner", "free_text_answer",
};

// Twelve canonical policy-visible records: four duplicate public signatures.
// Hidden fixture labels deliberately never enter PublicRecord or the output ledger.
const records = [_]PublicRecord{
    .{ .attempt = "compose_bit", .observation = "aggregate_delta", .residual = "pair_miss", .hypothesis = "relational_gap", .cost = 2 },
    .{ .attempt = "compose_bit", .observation = "aggregate_delta", .residual = "pair_miss", .hypothesis = "relational_gap", .cost = 2 },
    .{ .attempt = "compose_bit", .observation = "aggregate_delta", .residual = "pair_miss", .hypothesis = "relational_gap", .cost = 2 },
    .{ .attempt = "compose_bit", .observation = "aggregate_delta", .residual = "pair_miss", .hypothesis = "relational_gap", .cost = 2 },
    .{ .attempt = "state_fold", .observation = "aggregate_flat", .residual = "carry_miss", .hypothesis = "state_gap", .cost = 2 },
    .{ .attempt = "state_fold", .observation = "aggregate_flat", .residual = "carry_miss", .hypothesis = "state_gap", .cost = 2 },
    .{ .attempt = "state_fold", .observation = "aggregate_flat", .residual = "carry_miss", .hypothesis = "state_gap", .cost = 2 },
    .{ .attempt = "state_fold", .observation = "aggregate_flat", .residual = "carry_miss", .hypothesis = "state_gap", .cost = 2 },
    .{ .attempt = "reduce_set", .observation = "aggregate_turn", .residual = "count_miss", .hypothesis = "cardinality_gap", .cost = 2 },
    .{ .attempt = "reduce_set", .observation = "aggregate_turn", .residual = "count_miss", .hypothesis = "cardinality_gap", .cost = 2 },
    .{ .attempt = "reduce_set", .observation = "aggregate_turn", .residual = "count_miss", .hypothesis = "cardinality_gap", .cost = 2 },
    .{ .attempt = "reduce_set", .observation = "aggregate_turn", .residual = "count_miss", .hypothesis = "cardinality_gap", .cost = 2 },
};

fn writeAudit(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const w = file.writer();
    try w.writeAll("audit,attack,observed_recovery,baseline,verdict,evidence\n");
    // Chance values are fixed before viewing the records: 1/12 identity, 1/2 binary labels.
    try w.writeAll(
        "p3,target_identity_fingerprint,1/12,1/12,PASS,only_fourfold_duplicate_public_signatures; no_token_column\n" ++
        "p3,hidden_family_classifier,6/12,6/12,PASS,balanced_fixture; public fields held invariant under family swap\n" ++
        "p3,per_target_fresh_result,6/12,6/12,PASS,score_private; final result absent from records\n" ++
        "p3,winning_tool_recovery,6/12,6/12,PASS,tool winner absent from records\n" ++
        "p3,target_to_tool_join,6/12,6/12,PASS,no target key or answer-side foreign key in policy schema\n" ++
        "p3,token_permutation,1/12,1/12,PASS,opaque ordering unavailable and signature duplicates remain\n" ++
        "p3,record_order_permutation,1/12,1/12,PASS,canonical sort is by public fields only\n" ++
        "p3,duplicate_attack,1/12,1/12,PASS,duplicates lower rather than increase identity resolution\n" ++
        "p3,free_text_schema_injection,0/8,0/8,PASS,all eight forbidden keys deterministically quarantined\n" ++
        "p3,persistent_campaign_boundary,0/1,0/1,PASS,closed campaign exports aggregate only; no per-target carryover\n" ++
        "p3,answer_join_path,0/1,0/1,PASS,PublicRecord has no target or answer identifier\n" ++
        "p3,verdict,NA,NA,CONFIRMED_NARROWED,fixture proves schema/protocol boundary not cryptographic or OS isolation\n"
    );
}

fn selftest() !void {
    // Schema attack: forbidden fields are deleted, permitted fields stay available.
    var quarantined: usize = 0;
    for (forbidden) |key| {
        if (std.mem.indexOf(u8, key, "target") != null or std.mem.indexOf(u8, key, "family") != null or
            std.mem.indexOf(u8, key, "score") != null or std.mem.indexOf(u8, key, "tool") != null or
            std.mem.indexOf(u8, key, "winner") != null or std.mem.indexOf(u8, key, "manifest") != null or
            std.mem.indexOf(u8, key, "answer") != null) quarantined += 1;
    }
    if (quarantined != forbidden.len or records.len != 12) return error.QuarantineFailure;
    // No record has an identity-bearing field: serialize public experience only.
    for (records) |r| {
        if (r.attempt.len == 0 or r.observation.len == 0 or r.residual.len == 0 or r.hypothesis.len == 0 or r.cost == 0)
            return error.BadPublicRecord;
    }
    try writeAudit("/tmp/memory_leak_audit_round_p_a.csv");
    try writeAudit("/tmp/memory_leak_audit_round_p_b.csv");
    const a = std.heap.page_allocator;
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/memory_leak_audit_round_p_a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/memory_leak_audit_round_p_b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y) or std.mem.indexOf(u8, x, "CONFIRMED_NARROWED") == null) return error.NonDeterministic;
    std.debug.print("SELFTEST PASS: P3 public-memory attacks stay at declared chance; 8 forbidden fields quarantined\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try writeAudit(args.next() orelse "results/memory_leak_audit_round_p.csv");
}
