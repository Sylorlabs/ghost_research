//! Round AM / AM3: independent fail-closed higher-order causal-relevance gate.
//!
//! Source-level rule: a claim manifest is conditionally admitted only when it
//! contains response-only, append-only intervention-transition provenance and
//! names no matcher, identity, route, schedule, topology, hidden-world, result,
//! or representation-dependent surface.  This audits the declared manifest;
//! it does not certify a separate program, intelligence, or ownership.
const std = @import("std");

const Fixture = struct {
    name: []const u8,
    direct_matcher: bool = false,
    alias_matcher: bool = false,
    encoded_matcher: bool = false,
    address_or_id: bool = false,
    label: bool = false,
    target_or_answer_or_trace: bool = false,
    score_or_uncertainty: bool = false,
    static_vector_or_fingerprint: bool = false,
    supplied_temporal_motif: bool = false,
    supplied_schedule: bool = false,
    supplied_router: bool = false,
    supplied_graph_or_topology: bool = false,
    representation_or_recoding_leak: bool = false,
    world_overlap: bool = false,
    transition_provenance: bool = false,
};
const Decision = enum { reject, conditional_accept };

// First-match order is intentional, deterministic, and deny-by-default.
fn rejectReason(f: Fixture) ?[]const u8 {
    if (f.direct_matcher) return "REJECT:direct_static_matcher";
    if (f.alias_matcher) return "REJECT:aliased_matcher";
    if (f.encoded_matcher) return "REJECT:encoded_matcher_or_key";
    if (f.address_or_id) return "REJECT:address_or_identifier";
    if (f.label) return "REJECT:supplied_label";
    if (f.target_or_answer_or_trace) return "REJECT:target_answer_or_trace_leak";
    if (f.score_or_uncertainty) return "REJECT:score_or_uncertainty_leak";
    if (f.static_vector_or_fingerprint) return "REJECT:fixed_static_matcher_or_vector";
    if (f.supplied_temporal_motif) return "REJECT:supplied_temporal_motif";
    if (f.supplied_schedule) return "REJECT:supplied_fixed_schedule";
    if (f.supplied_router) return "REJECT:supplied_router";
    if (f.supplied_graph_or_topology) return "REJECT:supplied_graph_or_topology";
    if (f.representation_or_recoding_leak) return "REJECT:representation_or_recoding_leak";
    if (f.world_overlap) return "REJECT:private_or_earned_world_overlap";
    if (!f.transition_provenance) return "REJECT:no_response_only_intervention_transition_provenance";
    return null;
}
fn decide(f: Fixture) Decision {
    return if (rejectReason(f) == null) .conditional_accept else .reject;
}

const fixtures = [_]Fixture{
    .{ .name = "qualified_single_transition_provenance", .transition_provenance = true },
    .{ .name = "qualified_append_only_transition_provenance", .transition_provenance = true },
    .{ .name = "direct_similarity_matcher", .direct_matcher = true, .transition_provenance = true },
    .{ .name = "alias_compare_helper", .alias_matcher = true, .transition_provenance = true },
    .{ .name = "encoded_xor_match_key", .encoded_matcher = true, .transition_provenance = true },
    .{ .name = "address_identity_route", .address_or_id = true, .transition_provenance = true },
    .{ .name = "opaque_regime_id", .address_or_id = true, .transition_provenance = true },
    .{ .name = "supplied_regime_label", .label = true, .transition_provenance = true },
    .{ .name = "target_cache", .target_or_answer_or_trace = true, .transition_provenance = true },
    .{ .name = "answer_history_trace", .target_or_answer_or_trace = true, .transition_provenance = true },
    .{ .name = "fresh_score_port", .score_or_uncertainty = true, .transition_provenance = true },
    .{ .name = "uncertainty_router", .score_or_uncertainty = true, .transition_provenance = true },
    .{ .name = "fixed_embedding_vector", .static_vector_or_fingerprint = true, .transition_provenance = true },
    .{ .name = "fixed_fingerprint_table", .static_vector_or_fingerprint = true, .transition_provenance = true },
    .{ .name = "supplied_temporal_motif", .supplied_temporal_motif = true, .transition_provenance = true },
    .{ .name = "fixed_tick_schedule", .supplied_schedule = true, .transition_provenance = true },
    .{ .name = "supplied_router_callback", .supplied_router = true, .transition_provenance = true },
    .{ .name = "provided_causal_graph", .supplied_graph_or_topology = true, .transition_provenance = true },
    .{ .name = "provided_neighborhood_topology", .supplied_graph_or_topology = true, .transition_provenance = true },
    .{ .name = "representation_decode_table", .representation_or_recoding_leak = true, .transition_provenance = true },
    .{ .name = "recode_sensitive_transition", .representation_or_recoding_leak = true, .transition_provenance = true },
    .{ .name = "shared_private_world_trace", .world_overlap = true, .transition_provenance = true },
    .{ .name = "no_transition_provenance", .transition_provenance = false },
};

fn emit(out: anytype, f: Fixture) !void {
    const verdict = rejectReason(f) orelse "CONDITIONAL_ACCEPT:response_only_append_only_intervention_transition_provenance; benefit and ownership unproven";
    try out.print("round_am_am3,{s},{s},{s},{s}\n", .{ f.name, @tagName(decide(f)), if (f.transition_provenance) "present" else "absent", verdict });
}
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,fixture,decision,response_only_intervention_transition_provenance,verdict\n");
    for (fixtures) |f| try emit(out, f);
    const rules = [_][]const u8{
        "SOURCE_RULE:deny_by_default_first_rejection_wins",
        "SOURCE_RULE:permit_only_response_only_append_only_observed_intervention_transition_provenance",
        "SOURCE_RULE:reject_direct_alias_encoded_matchers_address_ids_labels_target_answer_trace_score_uncertainty_static_vectors",
        "SOURCE_RULE:reject_supplied_temporal_motif_schedule_router_graph_topology_representation_recoding_and_world_overlap",
        "COVERAGE:21_hostile_negative_fixtures_plus_two_positive_provenance_only_fixtures",
        "RESIDUAL:source_manifest_audit_cannot_prove_unexposed_binary_runtime_or_environment_behavior",
        "GATE_READY:infrastructure_only_not_an_intelligence_foundation_or_ownership_positive",
    };
    for (rules) |rule| try out.print("round_am_am3,audit,conditional_accept,na,{s}\n", .{rule});
}
fn selftest() !void {
    try run("/tmp/am3-a.csv");
    try run("/tmp/am3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const a = try std.fs.cwd().readFileAlloc(allocator, "/tmp/am3-a.csv", 1 << 20);
    defer allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(allocator, "/tmp/am3-b.csv", 1 << 20);
    defer allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    var rejects: usize = 0;
    var accepts: usize = 0;
    for (fixtures) |f| switch (decide(f)) {
        .reject => rejects += 1,
        .conditional_accept => accepts += 1,
    };
    if (rejects != 21 or accepts != 2) return error.InvalidFixtureCoverage;
    if (std.mem.indexOf(u8, a, "GATE_READY") == null) return error.MissingManifestRule;
    std.debug.print("round_am_am3 selftest PASS deterministic=true hostile_rejects=21 qualified_manifests=2 verdict=GATE_READY residual=source_manifest_only\n", .{});
}
pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/higher_order_audit_round_am.csv");
}
