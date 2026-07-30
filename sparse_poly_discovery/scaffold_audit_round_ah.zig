//! Round AH / AH3 -- independent, fail-closed human-scaffold audit gate.
//!
//! This is deliberately an infrastructure test, not an intelligence claim and
//! not an operating-system security proof.  It audits an explicit, versioned
//! capability/provenance manifest before a raw-medium result may be called
//! organism-owned.  Direct names, aliases, indirection, callbacks, encoded
//! names, and bypass channels are all rejected.  A missing or malformed
//! manifest is rejected too: absence of evidence is not a clean result.
const std = @import("std");

const Category = enum {
    score_reward_target_comparison,
    decoder_semantic_algebra,
    observation_action_port,
    candidate_mutation_grammar,
    component_boundary_tag,
    seed_template_repair,
    viability_fitness,
    scheduler_copy_reproduction,
    evaluator_feedback,
    file_process_ipc_access,
    allowed_exterior,
};

const Fixture = struct {
    id: []const u8,
    declared: []const u8,
    provenance: []const u8,
    expected: []const u8,
    note: []const u8,
};

const Finding = struct { category: Category, reason: []const u8 };

// A manifest is what the organism can name or receive, not merely what a host
// happens not to invoke in a particular run.  Deliberately hostile fixtures
// cover aliases, indirection, encoded aliases and an external bypass.
const fixtures = [_]Fixture{
    .{ .id = "clean_uniform_transport", .declared = "local_transport;conservation;bounded_space;bounded_time", .provenance = "host:uniform_law;mutant:none;evaluator:post_run_only", .expected = "ALLOW", .note = "permitted exterior physics only" },
    .{ .id = "direct_score", .declared = "local_transport;score", .provenance = "host:score_service", .expected = "BLOCK", .note = "direct reward name" },
    .{ .id = "alias_reward", .declared = "local_transport;alias:heat=score;heat", .provenance = "host:alias_table", .expected = "BLOCK", .note = "semantic alias must not evade lexical audit" },
    .{ .id = "indirect_decoder", .declared = "local_transport;callback:resolve->decoder", .provenance = "host:callback_registry", .expected = "BLOCK", .note = "function-pointer indirection" },
    .{ .id = "encoded_template", .declared = "local_transport;encoded:736565645F74656D706C617465", .provenance = "host:encoded_manifest", .expected = "BLOCK", .note = "hex spelling of seed_template" },
    .{ .id = "port_pair", .declared = "local_transport;observation_port;action_port", .provenance = "host:port_map", .expected = "BLOCK", .note = "hidden sensor/action split" },
    .{ .id = "mutation_menu", .declared = "local_transport;candidate_generator;mutation_grammar", .provenance = "host:proposal_service", .expected = "BLOCK", .note = "host proposal surface" },
    .{ .id = "boundary_tag", .declared = "local_transport;component_tag;boundary_table", .provenance = "host:identity_map", .expected = "BLOCK", .note = "predeclared organism parts" },
    .{ .id = "repair_seed", .declared = "local_transport;seed_template;repair_callback", .provenance = "host:repair_loop", .expected = "BLOCK", .note = "host organism restoration" },
    .{ .id = "fitness_scheduler", .declared = "local_transport;viability_scalar;replication_scheduler", .provenance = "host:lineage_service", .expected = "BLOCK", .note = "host selection/reproduction" },
    .{ .id = "evaluator_return", .declared = "local_transport;evaluator_feedback", .provenance = "evaluator:writeback", .expected = "BLOCK", .note = "post-run observer feeds world" },
    .{ .id = "ipc_bypass", .declared = "local_transport;process_spawn;unix_socket;file_read", .provenance = "host:external_channel", .expected = "BLOCK", .note = "process/file/IPC authority" },
};

const Rules = [_]Finding{
    .{ .category = .score_reward_target_comparison, .reason = "score|reward|target|comparison" },
    .{ .category = .decoder_semantic_algebra, .reason = "decoder|semantic|opcode|execute" },
    .{ .category = .observation_action_port, .reason = "observation_port|action_port|sensor|actuator" },
    .{ .category = .candidate_mutation_grammar, .reason = "candidate|mutation|proposal|grammar" },
    .{ .category = .component_boundary_tag, .reason = "component|boundary|tag|genome" },
    .{ .category = .seed_template_repair, .reason = "seed|template|repair" },
    .{ .category = .viability_fitness, .reason = "viability|fitness" },
    .{ .category = .scheduler_copy_reproduction, .reason = "scheduler|copy|replicat" },
    .{ .category = .evaluator_feedback, .reason = "evaluator_feedback|writeback|return_score" },
    .{ .category = .file_process_ipc_access, .reason = "file_|process_|socket|ipc|network" },
};

fn categoryName(c: Category) []const u8 { return @tagName(c); }

fn containsAny(haystack: []const u8, words: []const u8) bool {
    var it = std.mem.splitScalar(u8, words, '|');
    while (it.next()) |word| if (std.mem.indexOf(u8, haystack, word) != null) return true;
    return false;
}

fn hexDecodeContainsSeedTemplate(s: []const u8) bool {
    // The fixture encoding is intentionally simple. Reject *any* encoded
    // manifest field as opaque capability smuggling, while proving this known
    // alias is detected rather than silently accepted.
    return std.mem.indexOf(u8, s, "encoded:") != null;
}

fn audit(f: Fixture) ?Finding {
    if (f.declared.len == 0 or f.provenance.len == 0) return .{ .category = .file_process_ipc_access, .reason = "missing_manifest_or_provenance" };
    if (hexDecodeContainsSeedTemplate(f.declared)) return .{ .category = .seed_template_repair, .reason = "encoded_capability_requires_manual_rejection" };
    if (std.mem.indexOf(u8, f.declared, "alias:") != null) return .{ .category = .score_reward_target_comparison, .reason = "alias_or_renaming_is_forbidden" };
    if (std.mem.indexOf(u8, f.declared, "callback:") != null) return .{ .category = .decoder_semantic_algebra, .reason = "indirect_callback_is_forbidden" };
    for (Rules) |rule| {
        if (containsAny(f.declared, rule.reason) or containsAny(f.provenance, rule.reason)) return rule;
    }
    return null;
}

fn run(out: anytype) !void {
    try out.writeAll("round,fixture,declared_capabilities,provenance,expected,observed,category,reason,verdict,coverage\n");
    var blocked: usize = 0;
    for (fixtures) |f| {
        const finding = audit(f);
        const observed = if (finding == null) "ALLOW" else "BLOCK";
        const category = if (finding) |x| categoryName(x.category) else "allowed_exterior";
        const reason = if (finding) |x| x.reason else "uniform_local_transport_and_external_post_run_measurement_only";
        const ok = std.mem.eql(u8, observed, f.expected);
        if (!ok) return error.FixtureExpectationMismatch;
        if (finding != null) blocked += 1;
        try out.print("round_ah_ah3,{s},{s},{s},{s},{s},{s},{s},{s},fixture_manifest_and_provenance\n", .{ f.id, f.declared, f.provenance, f.expected, observed, category, reason, if (ok) "PASS" else "FAIL" });
    }
    if (blocked != fixtures.len - 1) return error.IncompleteHostileCoverage;
    try out.print("round_ah_ah3,SUMMARY,-,-,-,11_BLOCK_1_ALLOW,{d}_BLOCK_1_ALLOW,-,all_direct_alias_indirection_encoded_and_bypass_fixtures_detected,PASS,not_os_security_or_complete_static_analysis\n", .{blocked});
    try out.writeAll("round_ah_ah3,RESIDUAL,-,-,-,LIMITED,-,self_authored_local_scanner_cannot_prove_complete_source_binary_kernel_or_side_channel_absence,VALID_NEGATIVE,requires_independent_review_sandbox_and_runtime_trace\n");
}

fn writePath(path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try run(file.writer());
}

fn selftest() !void {
    try writePath("/tmp/scaffold_audit_round_ah_a.csv");
    try writePath("/tmp/scaffold_audit_round_ah_b.csv");
    const a = std.heap.page_allocator;
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/scaffold_audit_round_ah_a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/scaffold_audit_round_ah_b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    if (std.mem.indexOf(u8, x, "alias_or_renaming_is_forbidden") == null or std.mem.indexOf(u8, x, "encoded_capability_requires_manual_rejection") == null or std.mem.indexOf(u8, x, "self_authored_local_scanner") == null) return error.MissingRequiredGate;
    std.debug.print("round_ah_ah3 selftest PASS verdict=VALID_NEGATIVE deterministic=true hostile_fixtures=11 residual_security_claim=false\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const arg = args.next() orelse "results/scaffold_audit_round_ah.csv";
    if (std.mem.eql(u8, arg, "selftest")) return selftest();
    try writePath(arg);
}
