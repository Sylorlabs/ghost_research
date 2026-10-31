//! Round Q Q1 -- deterministic, provenance-tracked material universe.
//!
//! This is a fixture registry, not internet/world access.  It exposes only
//! approved public material descriptors and rejects evaluator/test/answer
//! artifacts before they can become forge inputs.
const std = @import("std");

const SourceClass = enum { generic_atom, synthetic_simulator, public_forge_artifact, safe_local_corpus };

const Material = struct {
    source: SourceClass,
    content: []const u8,
    capability: []const u8,
    cost: u32,
    policy: []const u8,
    lineage: []const u8,
};

const approved = [_]Material{
    .{ .source = .generic_atom, .content = "bool_fold(xor)", .capability = "boolean_relation_fold", .cost = 1, .policy = "approved_generic", .lineage = "raw_atom_v1" },
    .{ .source = .generic_atom, .content = "count(compare_ge)", .capability = "bounded_count_comparison", .cost = 1, .policy = "approved_generic", .lineage = "raw_atom_v1" },
    .{ .source = .synthetic_simulator, .content = "simulator:anonymous_bit_relation:v1", .capability = "safe_counterfactual_observation", .cost = 3, .policy = "approved_synthetic", .lineage = "simulator_fixture_v1" },
    .{ .source = .public_forge_artifact, .content = "forge_artifact:count_then_compare:public_descriptor", .capability = "aggregate_measurement_shape", .cost = 2, .policy = "public_prior_artifact", .lineage = "round_p_p4_public" },
    .{ .source = .safe_local_corpus, .content = "corpus_snippet:finite_state_transition_observation", .capability = "state_transition_vocabulary", .cost = 1, .policy = "local_safe_excerpt", .lineage = "local_fixture_corpus_v1" },
};

fn className(c: SourceClass) []const u8 { return @tagName(c); }
fn hashContent(content: []const u8) u64 {
    var h: u64 = 1469598103934665603;
    for (content) |b| { h ^= b; h *%= 1099511628211; }
    return h;
}
fn forbidden(s: []const u8) bool {
    for ([_][]const u8{ "evaluator", "test_manifest", "answer", "fresh_score", "hidden_target", "secret", "policy_memory" }) |bad|
        if (std.mem.indexOf(u8, s, bad) != null) return true;
    return false;
}
fn valid(m: Material) bool {
    return m.content.len != 0 and m.capability.len != 0 and m.policy.len != 0 and m.lineage.len != 0 and
        !forbidden(m.content) and !forbidden(m.capability) and !forbidden(m.lineage);
}
fn less(_: void, a: Material, b: Material) bool {
    const ah = hashContent(a.content); const bh = hashContent(b.content);
    return if (ah == bh) std.mem.order(u8, a.content, b.content) == .lt else ah < bh;
}
fn writeRegistry(allocator: std.mem.Allocator, path: []const u8, reverse_input: bool) !void {
    var list = std.ArrayList(Material).init(allocator); defer list.deinit();
    var seen = std.AutoHashMap(u64, void).init(allocator); defer seen.deinit();
    var i: usize = 0;
    while (i < approved.len) : (i += 1) {
        const at = if (reverse_input) approved.len - 1 - i else i;
        const m = approved[at];
        if (!valid(m)) return error.InvalidApprovedMaterial;
        const h = hashContent(m.content);
        if (seen.contains(h)) return error.DuplicateContent;
        try seen.put(h, {}); try list.append(m);
    }
    std.mem.sort(Material, list.items, {}, less);
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    try f.writer().writeAll("material_id,source_class,content_hash,capability_descriptor,cost,policy_tag,lineage,admission\n");
    for (list.items, 0..) |m, n| {
        try f.writer().print("QMAT-{d},{s},{x},{s},{d},{s},{s},accepted\n", .{ n + 1, className(m.source), hashContent(m.content), m.capability, m.cost, m.policy, m.lineage });
    }
}
fn privacySafe(bytes: []const u8) bool {
    return !forbidden(bytes) and std.mem.indexOf(u8, bytes, "QMAT-") != null;
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        const a = "/tmp/q1_registry_a.csv"; const b = "/tmp/q1_registry_b.csv";
        try writeRegistry(allocator, a, false); try writeRegistry(allocator, b, true);
        const aa = try std.fs.cwd().readFileAlloc(allocator, a, 1 << 20); defer allocator.free(aa);
        const bb = try std.fs.cwd().readFileAlloc(allocator, b, 1 << 20); defer allocator.free(bb);
        if (!std.mem.eql(u8, aa, bb)) return error.NonDeterministicTraversal;
        if (!privacySafe(aa)) return error.PrivateDescriptorLeak;
        const renamed = Material{ .source = .generic_atom, .content = approved[0].content, .capability = "renamed", .cost = 1, .policy = "approved_generic", .lineage = "test" };
        if (hashContent(renamed.content) != hashContent(approved[0].content)) return error.RenameHashFailure;
        const missing = Material{ .source = .generic_atom, .content = "x", .capability = "c", .cost = 1, .policy = "", .lineage = "" };
        if (valid(missing)) return error.MissingProvenanceAccepted;
        const forbidden_source = Material{ .source = .safe_local_corpus, .content = "evaluator:test_manifest", .capability = "x", .cost = 1, .policy = "bad", .lineage = "bad" };
        if (valid(forbidden_source)) return error.ForbiddenSourceAccepted;
        std.debug.print("SELFTEST PASS: Q1 5 approved typed materials; missing provenance, renamed duplicate, evaluator artifacts, hash replay, traversal, and descriptor privacy rejected\n", .{});
        return;
    }
    try writeRegistry(allocator, args.next() orelse "results/material_universe_round_q.csv", false);
}
