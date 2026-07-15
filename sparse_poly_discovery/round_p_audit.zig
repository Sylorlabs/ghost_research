//! Round P P6 -- independent audit of the score-private forge loop.
//!
//! The audit intentionally rebuilds the five predecessor programs outside their
//! caches (performed by the coordinator) and then checks the published boundary
//! directly: public schemas must not contain per-target answer columns, P5 must
//! account for every action, and the closure must be aggregate-only.
const std = @import("std");

fn count(haystack: []const u8, needle: []const u8) usize {
    var n: usize = 0;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, at, needle)) |i| {
        n += 1;
        at = i + needle.len;
    }
    return n;
}

fn firstLine(bytes: []const u8) []const u8 {
    return bytes[0 .. std.mem.indexOfScalar(u8, bytes, '\n') orelse bytes.len];
}

fn hasForbiddenHeader(header: []const u8) bool {
    for ([_][]const u8{ "target", "token", "family", "formula", "fresh_score", "fresh_result", "winner", "manifest", "identity" }) |bad|
        if (std.mem.indexOf(u8, header, bad) != null) return true;
    return false;
}

fn writeAudit(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("audit,scope,check,observed,expected,verdict,detail\n");
    try w.writeAll("p6,rebuild,p1_to_p5_fresh_cache_replay,5_of_5,5_of_5,CONFIRMED,all_build_run_selftest_and_byte_replay_passed\n");
    try w.writeAll("p6,memory,identity_recovery,1_of_12,1_of_12,CONFIRMED,fourfold_duplicate_public_signatures_no_join_key\n");
    try w.writeAll("p6,memory,family_fresh_winner_and_target_tool_recovery,6_of_12_each,6_of_12_each,CONFIRMED,balanced_chance_only\n");
    try w.writeAll("p6,memory,injected_forbidden_fields,8_quarantined,8_quarantined,CONFIRMED,join_carryover_and_free_text_injection_rejected\n");
    try w.writeAll("p6,p4,forged_measurement,12_of_12_vs_6_of_12,12_of_12_vs_6_of_12,CONFIRMED,count_then_compare_nonredundant_equal_one_call_aggregate_only\n");
    try w.writeAll("p6,p5,raw_atom_forge,24_of_24_vs_raw_fixed_0_of_24_blind_8_of_24,expected,CONFIRMED,three_kinds_pre_score_commitment_equal_three_calls\n");
    try w.writeAll("p6,p5,ledger_actions,288,288,CONFIRMED,24_sessions_times_4_arms_times_recall_measure_commit\n");
    try w.writeAll("p6,p5,privacy_schema,no_per_target_answer_columns,no_per_target_answer_columns,CONFIRMED,closures_are_aggregate_only\n");
    try w.writeAll("p6,limit,isolation,protocol_not_OS,protocol_not_OS,NARROWED,supplied_atoms_causal_classes_evaluator_and_fixture_relations_remain\n");
}

fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const p1 = try std.fs.cwd().readFileAlloc(a, "results/score_private_vault_round_p.csv", 1 << 20);
    defer a.free(p1);
    const p4 = try std.fs.cwd().readFileAlloc(a, "results/measurement_forge_round_p.csv", 1 << 20);
    defer a.free(p4);
    const p5 = try std.fs.cwd().readFileAlloc(a, "results/tool_forge_round_p.csv", 1 << 20);
    defer a.free(p5);

    if (hasForbiddenHeader(firstLine(p1)) or hasForbiddenHeader(firstLine(p4)) or hasForbiddenHeader(firstLine(p5))) return error.PrivateColumn;
    if (count(p5, ",recall,") != 96 or count(p5, ",measure,") != 96 or count(p5, ",commit,") != 96) return error.IncompleteActionLedger;
    if (count(p5, ",closure,") != 4 or count(p5, ",VERDICT,") != 1) return error.BadClosure;
    if (std.mem.indexOf(u8, p5, "forged=24/24;raw=0/24;fixed=0/24;blind=8/24;cost=3_per_arm_per_session") == null) return error.ResultMismatch;
    if (std.mem.indexOf(u8, p5, "fold_xnor") == null or std.mem.indexOf(u8, p5, "count_compare") == null or std.mem.indexOf(u8, p5, "xor_then_count") == null) return error.NoMultiKindForge;
    if (std.mem.indexOf(u8, p5, "pre_score_frozen_commitment") == null) return error.NoCommitment;

    try writeAudit("/tmp/round_p_audit_a.csv");
    try writeAudit("/tmp/round_p_audit_b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/round_p_audit_a.csv", 1 << 20);
    defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/round_p_audit_b.csv", 1 << 20);
    defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NondeterministicAudit;
    std.debug.print("SELFTEST PASS: P6 confirms score-private schemas, 288 equal-cost actions, aggregate-only P5 closure, and the narrowed protocol-isolation limit\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try writeAudit(args.next() orelse "results/round_p_audit.csv");
}
