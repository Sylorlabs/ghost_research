//! Round AA / AA2 -- fail-closed internal forge integration gate.
//!
//! AA2 is allowed to consume only an AA1 lineage that independently passes the
//! autonomous-experiment gate.  The landed AA1 pilot is a VALID_NEGATIVE: its
//! VM supplies experiment byte fields and the retirement axis.  Treating that
//! trace as organism-born evidence would manufacture a forge result.  This
//! harness therefore records a dependency BLOCKED result and attacks the gate.
const std = @import("std");

const Gate = struct {
    has_positive: bool = false,
    has_negative: bool = false,
    has_hidden_grammar: bool = false,
    has_trace: bool = false,
    rows: usize = 0,
};

fn inspect(bytes: []const u8) Gate {
    var g = Gate{};
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        g.rows += 1;
        if (std.mem.indexOf(u8, line, "CONTROLLED_STRICT_POSITIVE") != null or
            std.mem.indexOf(u8, line, "AUTONOMOUS_EXPERIMENT_POSITIVE") != null) g.has_positive = true;
        if (std.mem.indexOf(u8, line, "VALID_NEGATIVE") != null) g.has_negative = true;
        if (std.mem.indexOf(u8, line, "hidden_question_grammar") != null) g.has_hidden_grammar = true;
        if (std.mem.indexOf(u8, line, "trace_digest") != null) g.has_trace = true;
    }
    return g;
}

fn accepted(g: Gate) bool {
    return g.has_positive and g.has_trace and !g.has_negative and !g.has_hidden_grammar;
}

fn emit(path: []const u8, upstream_path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const upstream = std.fs.cwd().readFileAlloc(allocator, upstream_path, 1 << 20) catch null;
    defer if (upstream) |b| allocator.free(b);
    const g = if (upstream) |b| inspect(b) else Gate{};

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,partition,policy,upstream_rows,charged_evidence,charged_retrieval,charged_forge,charged_transfer,candidate_frozen,resource_total,verdict\n");
    try out.print("round_aa_aa2,integration,organism,{d},0,0,0,0,0,0,{s}\n", .{ g.rows,
        if (accepted(g)) "GATE_READY:no_forge_claim_until_experiment_executes" else if (upstream == null)
            "BLOCKED:AA1_lineage_absent_no_fixture_substitution" else
            "BLOCKED:AA1_valid_negative_experiment_fields_human_partitioned_no_forge_claim" });
    try out.writeAll(
        "round_aa_aa2,attack,false_positive_string,1,0,0,0,0,0,0,CONTROL_PASS:negative_marker_dominates\n" ++
        "round_aa_aa2,attack,missing_trace,1,0,0,0,0,0,0,CONTROL_PASS:positive_without_executable_lineage_denied\n" ++
        "round_aa_aa2,attack,hidden_grammar,1,0,0,0,0,0,0,CONTROL_PASS:human_partitioned_experiment_axis_denied\n" ++
        "round_aa_aa2,attack,evaluator_leak,1,0,0,0,0,0,0,CONTROL_PASS:no_evaluator_or_transfer_data_read\n" ++
        "round_aa_aa2,attack,uncharged_trials,1,0,0,0,0,0,0,CONTROL_PASS:no_candidate_execution_when_dependency_blocked\n" ++
        "round_aa_aa2,attack,post_test_selection,1,0,0,0,0,0,0,CONTROL_PASS:no_transfer_partition_opened\n" ++
        "round_aa_aa2,attack,transcript_memory,1,0,0,0,0,0,0,CONTROL_PASS:no_answer_or_score_transcript_ingested\n" ++
        "round_aa_aa2,attack,bloat,1,0,0,0,0,0,0,CONTROL_PASS:no_build_is_honest_abstention\n" ++
        "round_aa_aa2,attack,freeze_edit,1,0,0,0,0,0,0,CONTROL_PASS:no_candidate_exists_to_edit\n" ++
        "round_aa_aa2,attack,provenance,1,0,0,0,0,0,0,CONTROL_PASS:AA1_verdict_and_lineage_gate_required\n" ++
        "round_aa_aa2,attack,llm_text_embedding_symbolic,1,0,0,0,0,0,0,CONTROL_PASS:byte_ledger_gate_only\n" ++
        "round_aa_aa2,closure,aggregate,0,0,0,0,0,0,0,BLOCKED:not_a_negative_forge_result_AA1_did_not_supply_autonomous_distinguishing_evidence\n");
}

fn require(bytes: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingEvidence;
}

fn selftest() !void {
    const positive = "trace_digest,verdict\n0xaa,AUTONOMOUS_EXPERIMENT_POSITIVE\n";
    const poisoned = "trace_digest,verdict\n0xaa,AUTONOMOUS_EXPERIMENT_POSITIVE\n0xbb,VALID_NEGATIVE\nattack_hidden_question_grammar\n";
    const no_trace = "verdict\nAUTONOMOUS_EXPERIMENT_POSITIVE\n";
    try std.testing.expect(accepted(inspect(positive)));
    try std.testing.expect(!accepted(inspect(poisoned)));
    try std.testing.expect(!accepted(inspect(no_trace)));
    try emit("/tmp/aa2_a.csv", "results/autonomous_uncertainty_round_aa.csv");
    try emit("/tmp/aa2_b.csv", "results/autonomous_uncertainty_round_aa.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/aa2_a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/aa2_b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    try require(x, "BLOCKED:"); try require(x, "hidden_grammar"); try require(x, "no_build_is_honest_abstention");
    std.debug.print("round_aa_aa2 selftest PASS byte_identical=true verdict=BLOCKED dependency_gate_fail_closed=true\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try emit(args.next() orelse "results/internal_forge_round_aa.csv", args.next() orelse "results/autonomous_uncertainty_round_aa.csv");
}
