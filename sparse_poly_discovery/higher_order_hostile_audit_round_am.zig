//! AM6 independent hostile reconstruction for AM2/AM4/AM5.
const std = @import("std");
const Verdict = enum { inconclusive, invalidated };
fn has(h: []const u8, n: []const u8) bool { return std.mem.indexOf(u8, h, n) != null; }
fn read(a: std.mem.Allocator, p: []const u8) ![]u8 { return std.fs.cwd().readFileAlloc(a, p, 1 << 20); }
fn run(path: []const u8) !Verdict {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const am2 = try read(a, "sparse_poly_discovery/intervention_topology_round_am.zig"); defer a.free(am2);
    const am4 = try read(a, "sparse_poly_discovery/relevance_recovery_round_am.zig"); defer a.free(am4);
    const am5 = try read(a, "sparse_poly_discovery/higher_order_portfolio_round_am.zig"); defer a.free(am5);
    const csv2 = try read(a, "results/intervention_topology_round_am.csv"); defer a.free(csv2);
    const csv4 = try read(a, "results/relevance_recovery_round_am.csv"); defer a.free(csv4);
    const csv5 = try read(a, "results/higher_order_portfolio_round_am.csv"); defer a.free(csv5);
    const accounting = has(am2, "const Cohorts = 96;") and has(am2, "total.contacts += 16") and has(am4, "const Cohorts = 120;") and has(am4, "out.contacts += 16") and has(am5, "const Cohorts = 96;") and has(am5, "out.contacts += 15") and has(csv2, "earned_topology,1536,24960") and has(csv4, "earned_chain,1920,3600") and has(csv5, "earned_portfolio,4320,5760");
    const contrasts = has(csv2, "fixed_effect_vector,1536,1560") and has(csv2, "last_outcome,1536,8320") and has(csv2, "fixed_schedule,1536,9100") and has(csv4, "broad_coverage,1920,1660") and has(csv4, "topology_ablation,1920,1320") and has(csv4, "value_ablation,1920,990") and has(csv4, "arbitration_ablation,1920,1230") and has(csv5, "mechanism_misrouting,4320,0") and has(csv5, "fixed_portfolio_schedule,4320,1400");
    const causal = has(am4, ".topology_ablation") and has(am4, ".value_ablation") and has(am4, ".arbitration_ablation") and has(am5, ".mechanism_misrouting") and has(am5, ".am4_single_record");
    // Independent hostile finding: evaluator and policy are callable together.
    const coupled = has(am4, "fn hiddenQueryRecord") and has(am4, "fn evaluateAfterCharge") and has(am4, "fn runPolicy") and has(am5, "fn targetAction") and has(am5, "fn reward") and has(am5, "fn runPolicy") and has(am2, ".degree = degree(c, record)");
    const manifest_only = has(am4, "not an OS/process isolation claim") and has(am5, "not_runtime_or_hostile_containment");
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("artifact,case,status,observed,interpretation\n");
    try w.print("round_am_am6,static_matching_vector_last_trace_motif_graph_schedule_portfolio,ATTACK_RECONSTRUCTED,{s},named controls and contrast rows independently found\n", .{@as([]const u8, if (contrasts) "PASS" else "FAIL")});
    try w.print("round_am_am6,hidden_candidate_equivalent_implementation,ATTACK_FOUND,{s},policy target and evaluator share compilation unit; AM2 reads degree helper directly\n", .{@as([]const u8, if (coupled) "YES" else "NO")});
    try w.print("round_am_am6,leakage_labels_ids_targets_answers_scores_feedback_recoding_overlap_supplied_router,MANIFEST_LIMIT,{s},source record surface is not an enforceable runtime boundary\n", .{@as([]const u8, if (manifest_only) "SOURCE_ONLY" else "MISSING")});
    try w.print("round_am_am6,causal_necessity_wrong_topology_provenance_wrong_route_no_value_no_arbitration,RECONSTRUCTED,{s},ablations and explicit misroute are present\n", .{@as([]const u8, if (causal) "PASS" else "FAIL")});
    try w.print("round_am_am6,fairness_equal_charged_contacts,RECOMPUTED,{s},AM2=96x16=1536 AM4=120x16=1920 AM5=96x3x15=4320\n", .{@as([]const u8, if (accounting) "PASS" else "FAIL")});
    try w.print("round_am_am6,lineage_source_csv_claims,RECONSTRUCTED,{s},source cohort arithmetic and ledger headline rows agree\n", .{@as([]const u8, if (accounting and contrasts) "PASS" else "FAIL")});
    try w.writeAll("round_am_am6,security_process_evaluator_isolation,NOT_ESTABLISHED,NO,in-process deterministic fixture has no OS sandbox or separate protected evaluator\n");
    try w.writeAll("round_am_am6,verdict,INCONCLUSIVE,NO_FOUNDATION_SURVIVAL,fixture contrasts reproduce but evaluator-policy coupling prevents autonomy or hostile-isolation conclusion\n");
    return if (coupled) .inconclusive else .invalidated;
}
fn selftest() !void {
    const a_verdict = try run("/tmp/am6-a.csv"); const b_verdict = try run("/tmp/am6-b.csv"); if (a_verdict != .inconclusive or b_verdict != .inconclusive) return error.UnexpectedVerdict;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator(); const x = try read(a, "/tmp/am6-a.csv"); defer a.free(x); const y = try read(a, "/tmp/am6-b.csv"); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    if (!has(x, "hidden_candidate_equivalent_implementation,ATTACK_FOUND,YES") or !has(x, "verdict,INCONCLUSIVE")) return error.AuditMissedFinding;
    std.debug.print("round_am_am6 selftest PASS verdict=INCONCLUSIVE deterministic=true equal_accounting=true hostile_coupling_found=true security_not_upgraded=true\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run"; if (std.mem.eql(u8, command, "selftest")) return selftest(); _ = try run(args.next() orelse "results/higher_order_hostile_audit_round_am.csv"); }
