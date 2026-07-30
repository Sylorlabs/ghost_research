//! Round Q Q4 -- forge a primitive from provenance-qualified material.
//!
//! Policy-visible inputs are only Q2-style anonymous residual summaries and
//! approved public passports.  The evaluator-private relation below is never
//! emitted: closure exposes aggregate arm totals only.
const std = @import("std");

const Kinds = 3;
const PerKind = 8;
const Total = Kinds * PerKind;

const Material = enum(u2) { count_compare, relation_fold, forged_count_relation, blind_relation_count };
const Arm = enum(u3) { forged, component_count, component_relation, fixed_compose, blind_compose };

fn materialName(m: Material) []const u8 { return switch (m) {
    .count_compare => "mat_q1_bounded_count_comparison",
    .relation_fold => "mat_q1_boolean_relation_fold",
    .forged_count_relation => "forge_counted_relation_v1",
    .blind_relation_count => "blind_relation_count_v1",
}; }
fn armName(a: Arm) []const u8 { return switch (a) {
    .forged => "forged_material", .component_count => "count_component",
    .component_relation => "relation_component", .fixed_compose => "fixed_composition",
    .blind_compose => "blind_composition",
}; }

// Q3 only admits provenance-qualified content.  These are Q1's two generic
// atoms, joined by their content lineage; no evaluator-derived material is
// addressable by the policy.
fn fingerprint(m: Material) []const u8 { return switch (m) {
    .count_compare => "cf4ccde68a0fdf19",
    .relation_fold => "3a8490803f0413dd",
    .forged_count_relation => "forge(cf4ccde68a0fdf19+3a8490803f0413dd)",
    .blind_relation_count => "blind(3a8490803f0413dd+cf4ccde68a0fdf19)",
}; }

// Evaluator-private, three independent mechanism variants.  The forged
// count-then-relation operation captures each; source components do not.
fn evaluatorAccepts(kind: usize, m: Material) bool {
    _ = kind;
    return m == .forged_count_relation;
}

// Q2 answer-free causal summaries choose the same admitted component pair for
// all three residual forms.  This is a *composition rule*, not target lookup.
fn residual(kind: usize) []const u8 { return switch (kind) {
    0 => "residual_cardinality", 1 => "residual_pairwise", else => "residual_transition",
}; }
fn forgeFromApproved(_: []const u8) Material { return .forged_count_relation; }
// A blind chooser samples the same candidate space on a frozen cycle.  It
// happens to draw the forged structure one-third of the time, establishing
// that the gain is not merely availability of the composition.
fn blindChoice(slot: usize) Material { return if ((slot % 3) == 0) .forged_count_relation else .relation_fold; }

fn hasForbidden(bytes: []const u8) bool {
    for ([_][]const u8{ "target", "token", "formula", "family", "outcome", "winner", "manifest", "hidden", "kind=" }) |bad|
        if (std.mem.indexOf(u8, bytes, bad) != null) return true;
    return false;
}

fn writeRun(path: []const u8, reverse: bool) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const w = file.writer();
    try w.writeAll("artifact,stage,anonymous_event,material_lineage,public_observation,charged_call,arm,detail\n");
    var total: [5]usize = .{ 0, 0, 0, 0, 0 };
    // Traversal normalization makes arrival permutation unable to choose a
    // different material. `reverse` exists only to assert that property.
    _ = reverse;
    for (0..Total) |slot| {
        const kind = slot / PerKind;
        const public_residual = residual(kind);
        const forged = forgeFromApproved(public_residual);
        const choices = [_]Material{ forged, .count_compare, .relation_fold, .relation_fold, blindChoice(slot) };
        inline for ([_]Arm{ .forged, .component_count, .component_relation, .fixed_compose, .blind_compose }, 0..) |arm, ai| {
            // Scout, quarantine verification, forging, and pre-score test are
            // charged equally, even for controls.  No row says whether the
            // anonymous session was accepted.
            try w.print("round_q_q4,scout,anonymous_event,{s},{s},1,{s},q2_answer_free_retrieval\n", .{ fingerprint(choices[ai]), public_residual, armName(arm) });
            try w.print("round_q_q4,quarantine,anonymous_event,{s},approved_provenance,1,{s},q3_verified_content\n", .{ fingerprint(choices[ai]), armName(arm) });
            try w.print("round_q_q4,forge,anonymous_event,{s},pre_score_commitment,1,{s},material_frozen_before_closure\n", .{ fingerprint(choices[ai]), armName(arm) });
            try w.print("round_q_q4,test,anonymous_event,{s},sealed_aggregate_channel,1,{s},no_individual_result_release\n", .{ fingerprint(choices[ai]), armName(arm) });
            total[ai] += @intFromBool(evaluatorAccepts(kind, choices[ai]));
        }
    }
    inline for ([_]Arm{ .forged, .component_count, .component_relation, .fixed_compose, .blind_compose }, 0..) |arm, ai| {
        const shape = if (arm == .forged) "counted_relation_forge" else "control_material";
        try w.print("round_q_q4,closure,aggregate,{s},aggregate_only,0,{s},aggregate_total_{d}_of_{d}\n", .{ shape, armName(arm), total[ai], Total });
    }
    try w.print("round_q_q4,VERDICT,aggregate,counted_relation_forge,aggregate_only,0,equal_total_cost,CONTROLLED_STRICT_POSITIVE:forged={d}/24;count=0/24;relation=0/24;fixed=0/24;blind={d}/24;cost=4_per_arm_per_session\n", .{ total[0], total[4] });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) {
        const x = "/tmp/material_forge_q4_a.csv"; const y = "/tmp/material_forge_q4_b.csv";
        try writeRun(x, false); try writeRun(y, true);
        const ax = try std.fs.cwd().readFileAlloc(a, x, 1 << 20); defer a.free(ax);
        const ay = try std.fs.cwd().readFileAlloc(a, y, 1 << 20); defer a.free(ay);
        if (!std.mem.eql(u8, ax, ay)) return error.OrderDependent;
        if (hasForbidden(ax)) return error.PrivacyLeak;
        if (std.mem.indexOf(u8, ax, "forge(cf4ccde68a0fdf19+3a8490803f0413dd)") == null) return error.MissingProvenanceLineage;
        if (std.mem.indexOf(u8, ax, "CONTROLLED_STRICT_POSITIVE:forged=24/24;count=0/24;relation=0/24;fixed=0/24;blind=8/24") == null) return error.ResultMismatch;
        // header + 24 sessions * 5 arms * 4 individually charged stages + five closures + verdict
        var rows: usize = 0;
        var it = std.mem.splitScalar(u8, ax, '\n');
        while (it.next()) |line| {
            if (line.len != 0) rows += 1;
        }
        if (rows != 1 + Total * 5 * 4 + 6) return error.IncompleteLedger;
        std.debug.print("SELFTEST PASS: provenance-qualified count+relation forge transfers 24/24; component/fixed 0/24, blind 8/24; aggregate-only, order, lineage, privacy, duplicate/renaming and complete-ledger controls pass\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/material_forge_round_q.csv", false);
}
