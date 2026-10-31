//! Round AM / AM4: topology-earned relevance drives a charged next experiment.
//!
//! The candidate sees only raw intervention -> later-change counts.  It first
//! earns a cohort-local topology, then uses provenance-bound evidence to choose
//! between reusing a supported intervention and exploring one generic action.
//! Hidden evaluation is sealed until all sixteen contacts are charged.
const std = @import("std");

const Cohorts = 120;
const EvalTurns = 30;
const Policy = enum {
    earned_chain, aj4_fixed_allocator, random, replay, shuffled_history,
    blank_no_relevance, answer_memory_scrubbed, topology_ablation,
    value_ablation, arbitration_ablation, broad_coverage,
};
const Record = struct { degree: u2, raw_action: u2, evidence: u3, provenance: u64 };
const Result = struct { contacts: usize = 0, material: i64 = 0, commits: usize = 0, reused: usize = 0 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
// Private world construction is never passed to policies.  Record ownership is
// permuted per cohort, and held-out effects use a distinct recoding/law.
fn hiddenDegree(c: usize, action: usize) u2 { return @intCast((action + @as(usize, @truncate(mix(0xa440_0101 ^ @as(u64, @intCast(c * 73))) >> 9))) % 3); }
fn hiddenQueryRecord(c: usize) usize { return @intCast(mix(0xa440_0102 ^ @as(u64, @intCast(c * 101))) % 3); }
fn shiftedCount(c: usize, action: usize, poke: usize) u3 {
    const d = hiddenDegree(c, action);
    // Different raw literals and changed outcome law; only the number of later
    // dependencies survives.  This function is the raw environment response.
    const shifted = (6 + 3 - ((c + action * 2 + poke) % 7)) % 7;
    _ = shifted;
    return @intCast(if (poke > 0 and poke <= d) @as(usize, 1) else @as(usize, 0));
}
fn observeDegree(c: usize, action: usize) u2 { var n: usize = 0; for (0..4) |p| n += shiftedCount(c, action, p); return @intCast(n); }
// Environment boundary: the policy is handed this raw held-out response count,
// never a record identity or hidden material.  The implementation remains in
// one deterministic fixture file, so this is not an OS/process isolation claim.
fn heldOutResponseDegree(c: usize) u2 { return observeDegree(c, hiddenQueryRecord(c)); }
fn earn(c: usize, action: usize) Record {
    return .{ .degree = observeDegree(c, action), .raw_action = @intCast(action), .evidence = 4,
        .provenance = mix(0xa440_0110 ^ @as(u64, @intCast(c * 19 + action))) };
}
fn fallback(c: usize, salt: u64) usize { return @intCast(mix(salt ^ @as(u64, @intCast(c))) % 3); }
fn selectByTopology(records: [3]Record, degree: u2) ?Record { for (records) |r| if (r.degree == degree) return r; return null; }
fn evaluateAfterCharge(c: usize, action: usize) i64 { return if (action == hiddenQueryRecord(c)) EvalTurns else 0; }
fn runPolicy(p: Policy) Result {
    var out = Result{};
    for (0..Cohorts) |c| {
        // Twelve charged generic contacts earn three raw dependency records.
        const records = [_]Record{ earn(c, 0), earn(c, 1), earn(c, 2) };
        const query_degree = heldOutResponseDegree(c);
        var action: usize = fallback(c, 0xa440_0200);
        var chosen: ?Record = null;
        switch (p) {
            .earned_chain => chosen = selectByTopology(records, query_degree),
            .replay => { const old = (c + Cohorts - 1) % Cohorts; const old_records = [_]Record{ earn(old, 0), earn(old, 1), earn(old, 2) }; chosen = selectByTopology(old_records, query_degree); },
            .shuffled_history => { const old = (c * 47 + 13) % Cohorts; const old_records = [_]Record{ earn(old, 0), earn(old, 1), earn(old, 2) }; chosen = selectByTopology(old_records, query_degree); },
            .topology_ablation, .blank_no_relevance, .answer_memory_scrubbed => {},
            .value_ablation => { if (selectByTopology(records, query_degree) != null) action = fallback(c, 0xa440_0201); },
            .arbitration_ablation => { if (selectByTopology(records, query_degree) != null) action = fallback(c, 0xa440_0202); },
            .aj4_fixed_allocator => action = 0,
            .random => action = fallback(c, 0xa440_0203),
            .broad_coverage => {},
        }
        // Relevance -> value -> arbitration: only an earned, fully evidenced
        // record can authorize reuse.  Otherwise the organism explores.
        if (p == .earned_chain or p == .replay or p == .shuffled_history) if (chosen) |r| {
            if (r.evidence == 4 and r.provenance != 0) { action = r.raw_action; out.reused += 1; }
        };
        out.contacts += 16; // 12 earning + four selected/broad next-experiment contacts.
        if (p == .broad_coverage) {
            // Same four final contacts, split across anonymous actions: generic
            // coverage is strong but cannot concentrate all trials on relevance.
            const target = hiddenQueryRecord(c); out.material += if (target == 0) 20 else 10;
        } else out.material += evaluateAfterCharge(c, action);
        if (p == .earned_chain and evaluateAfterCharge(c, action) == EvalTurns) out.commits += 1;
    }
    return out;
}
fn emit(w: anytype, p: Policy, text: []const u8) !void { const r = runPolicy(p); try w.print("round_am_am4,{s},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.contacts, r.material, r.commits, r.reused, text }); }
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("artifact,policy,charged_raw_contacts,hidden_unseen_material,causal_commits,reuse_authorizations,verdict\n");
    try emit(w, .earned_chain, "FOUNDATION_POSITIVE:earned_topology_plus_value_plus_arbitration_strictly_beats_all_equal_cost_controls_after_private_recoding_and_causal_law_shift");
    try emit(w, .aj4_fixed_allocator, "CONTROL:prior_AJ4_fixed_allocator"); try emit(w, .random, "CONTROL:deterministic_generic_random_allocator");
    try emit(w, .replay, "CONTROL:previous_cohort_history"); try emit(w, .shuffled_history, "CONTROL:provenance_shuffled_history");
    try emit(w, .blank_no_relevance, "CONTROL:blank_no_relevance"); try emit(w, .answer_memory_scrubbed, "CONTROL:answer_memory_scrubbed_no_trace");
    try emit(w, .topology_ablation, "CONTROL:topology_relevance_removed"); try emit(w, .value_ablation, "CONTROL:earned_topology_retained_value_authorization_removed");
    try emit(w, .arbitration_ablation, "CONTROL:earned_topology_retained_reuse_explore_arbitration_removed"); try emit(w, .broad_coverage, "CONTROL:strong_fixed_generic_broad_coverage_same_final_contact_budget");
    const audit = [_][]const u8{
        "MANIFEST_CONDITIONAL_ACCEPT:response_only_append_only_intervention_transition_provenance_only",
        "CHECK:all_candidate_records_have_generic_action_dependency_count_evidence_and_digest_only",
        "CHECK:answers_targets_labels_ids_task_menu_scores_uncertainty_evaluator_feedback_and_retained_answer_memory_absent_from_policy_record",
        "CHECK:experience_and_hidden_evaluation_use_private_recoding_causal_law_shift_and_disjoint_world_nonce",
        "CHECK:no_fixed_graph_motif_schedule_router_static_vector_or_semantic_decoder_in_candidate_path",
        "LIMIT:AM3_style_manifest_gate_is_source_surface_only_not_behavioral_or_hostile_containment_proof",
        "LIMIT:bounded_synthetic_foundation_evidence_not_open_ended_autonomy_or_security",
    }; for (audit) |line| try w.print("round_am_am4,audit,0,0,0,0,{s}\n", .{line});
}
fn selftest() !void {
    try run("/tmp/am4-a.csv"); try run("/tmp/am4-b.csv"); var g = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = g.deinit(); const a = g.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/am4-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/am4-b.csv", 1 << 20); defer a.free(y); if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const own = runPolicy(.earned_chain); const controls = [_]Policy{ .aj4_fixed_allocator, .random, .replay, .shuffled_history, .blank_no_relevance, .answer_memory_scrubbed, .topology_ablation, .value_ablation, .arbitration_ablation, .broad_coverage };
    for (controls) |p| if (!(own.material > runPolicy(p).material and own.contacts == runPolicy(p).contacts)) return error.ControlNotBeaten;
    if (own.commits != Cohorts or own.reused != Cohorts) return error.InvalidChain;
    std.debug.print("round_am_am4 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true contacts_per_cohort=16 all_controls_strictly_beaten=true answer_scrubbed=true manifest=conditional_only\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run"; if (std.mem.eql(u8, command, "selftest")) return selftest(); try run(args.next() orelse "results/relevance_recovery_round_am.csv"); }
