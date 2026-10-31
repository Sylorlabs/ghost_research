//! Round AL / AL3: independent hostile gate for matcher-free relevance claims.
//!
//! This does not measure intelligence. It tests a claim manifest against a
//! pre-registered deny list. A claim is eligible only when its relevance is
//! backed by intervention-response provenance and has no surface matcher,
//! identifier, supplied routing scalar, answer/history leak, or fixed segment.
const std = @import("std");

const Fixture = struct {
    name: []const u8,
    direct_matcher: bool = false, alias_matcher: bool = false, encoded_matcher: bool = false,
    address_compare: bool = false, regime_id: bool = false, label: bool = false,
    routing_scalar: bool = false, uncertainty_scalar: bool = false,
    target_or_answer: bool = false, history_answer: bool = false, world_overlap: bool = false,
    fixed_fingerprint: bool = false, fixed_segment: bool = false,
    representation_sensitive: bool = false, law_shift_sensitive: bool = false,
    causal_response_provenance: bool = false,
};
const Decision = enum { reject, conditional_accept };

fn rejectReason(f: Fixture) ?[]const u8 {
    if (f.direct_matcher) return "REJECT:direct_equality_or_similarity_matcher";
    if (f.alias_matcher) return "REJECT:aliased_matcher_algebra";
    if (f.encoded_matcher) return "REJECT:encoded_similarity_or_key";
    if (f.address_compare) return "REJECT:address_identity_comparison";
    if (f.regime_id) return "REJECT:regime_identifier";
    if (f.label) return "REJECT:supplied_label_or_router";
    if (f.routing_scalar) return "REJECT:supplied_change_point_or_routing_scalar";
    if (f.uncertainty_scalar) return "REJECT:supplied_uncertainty_scalar";
    if (f.target_or_answer) return "REJECT:target_or_answer_memory";
    if (f.history_answer) return "REJECT:history_answer_leak";
    if (f.world_overlap) return "REJECT:earned_and_private_world_overlap";
    if (f.fixed_fingerprint) return "REJECT:fixed_fingerprint_template";
    if (f.fixed_segment) return "REJECT:fixed_segment_or_boundary";
    if (f.representation_sensitive) return "REJECT:fails_private_representation_recoding";
    if (f.law_shift_sensitive) return "REJECT:fails_private_causal_law_shift";
    if (!f.causal_response_provenance) return "REJECT:no_intervention_response_provenance";
    return null;
}
fn decide(f: Fixture) Decision { return if (rejectReason(f) == null) .conditional_accept else .reject; }

const fixtures = [_]Fixture{
    .{ .name = "qualified_response_only", .causal_response_provenance = true },
    .{ .name = "direct_equality", .direct_matcher = true, .causal_response_provenance = true },
    .{ .name = "alias_compare_fn", .alias_matcher = true, .causal_response_provenance = true },
    .{ .name = "xor_encoded_key", .encoded_matcher = true, .causal_response_provenance = true },
    .{ .name = "address_router", .address_compare = true, .causal_response_provenance = true },
    .{ .name = "private_regime_id", .regime_id = true, .causal_response_provenance = true },
    .{ .name = "label_port", .label = true, .causal_response_provenance = true },
    .{ .name = "change_point_score", .routing_scalar = true, .causal_response_provenance = true },
    .{ .name = "uncertainty_port", .uncertainty_scalar = true, .causal_response_provenance = true },
    .{ .name = "answer_cache", .target_or_answer = true, .causal_response_provenance = true },
    .{ .name = "history_answer_alias", .history_answer = true, .causal_response_provenance = true },
    .{ .name = "shared_world_trace", .world_overlap = true, .causal_response_provenance = true },
    .{ .name = "fixed_fingerprint", .fixed_fingerprint = true, .causal_response_provenance = true },
    .{ .name = "fixed_segmentation", .fixed_segment = true, .causal_response_provenance = true },
    .{ .name = "value_recode_failure", .representation_sensitive = true, .causal_response_provenance = true },
    .{ .name = "causal_law_shift_failure", .law_shift_sensitive = true, .causal_response_provenance = true },
    .{ .name = "no_provenance", .causal_response_provenance = false },
};

fn emit(out: anytype, f: Fixture) !void {
    const reason = rejectReason(f) orelse "CONDITIONAL_ACCEPT:response_provenance_only; runtime benefit still needs independent controls";
    try out.print("round_al_al3,{s},{s},{s},{s}\n", .{ f.name, @tagName(decide(f)), if (f.causal_response_provenance) "present" else "absent", reason });
}
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,fixture,decision,response_provenance,verdict\n");
    for (fixtures) |f| try emit(out, f);
    const manifest = [_][]const u8{
        "COVERAGE:16_hostile_fixtures_plus_one_qualified_minimal_manifest",
        "DENY:direct_alias_encoded_matchers_addresses_ids_labels_routing_uncertainty_answers_history_overlap_fixed_shapes_segments",
        "ROBUSTNESS:representation_recoding_and_private_causal_law_shift_required",
        "PERMITTED:generic_byte_transport_append_only_provenance_observed_intervention_response_only",
        "RESIDUAL:source_manifest_audit_cannot_prove_a_separate_binary_has_no_hidden_behavior",
        "GATE_READY:not_a_foundation_positive_not_an_intelligence_claim_not_hostile_containment",
    };
    for (manifest) |line| try out.print("round_al_al3,audit,conditional_accept,na,{s}\n", .{line});
}
fn selftest() !void {
    try run("/tmp/al3-a.csv"); try run("/tmp/al3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const allocator = gpa.allocator();
    const a = try std.fs.cwd().readFileAlloc(allocator, "/tmp/al3-a.csv", 1 << 20); defer allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(allocator, "/tmp/al3-b.csv", 1 << 20); defer allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    var rejects: usize = 0;
    for (fixtures) |f| {
        if (decide(f) == .reject) rejects += 1;
    }
    if (rejects != 16 or decide(fixtures[0]) != .conditional_accept) return error.InvalidFixtureCoverage;
    if (std.mem.indexOf(u8, a, "GATE_READY") == null) return error.MissingManifest;
    std.debug.print("round_al_al3 selftest PASS deterministic=true hostile_rejects=16 qualified_manifests=1 verdict=GATE_READY residual=source_manifest_only\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/matcher_free_audit_round_al.csv"); }
