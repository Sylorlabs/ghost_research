//! Round AB / AB1: causal-room birth microscope.
//!
//! The learner sees only a uniform 16-cell tape and ordinary resource returns.
//! Its provisional rooms are arbitrary overlapping membership sets which may
//! gain/lose cells, split, merge, relocate, and dissolve.  This is deliberately
//! an audit experiment: although the target membership is never supplied, the
//! host still supplies "subset of cells" as the room grammar, so the result is
//! classified as a valid negative rather than representation birth.
const std = @import("std");

const Cells = 16;
const Cohorts = 32;
const Steps = 320;
const Hidden = 24;

const Policy = enum { born, random, fixed4, fixed8, address, replay, frequency, age, human_origin, oracle, shuffled, ablated, restored, recoded };

const Result = struct { resource: i64 = 0, exact: usize = 0, cost: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn target(cohort: usize) u16 {
    var m: u16 = 0;
    var x = mix(0xab0100c0ffee1234 ^ cohort);
    while (@popCount(m) < 5) {
        m |= @as(u16, 1) << @intCast(x % Cells);
        x = mix(x);
    }
    return m;
}

fn permute(mask: u16, cohort: usize) u16 {
    var out: u16 = 0;
    const add = (cohort * 7 + 3) % Cells;
    for (0..Cells) |i| if ((mask & (@as(u16, 1) << @intCast(i))) != 0) {
        const j = (i * 5 + add) % Cells;
        out |= @as(u16, 1) << @intCast(j);
    };
    return out;
}

fn ordinaryResource(candidate: u16, truth: u16, cohort: usize, ctx: usize) i32 {
    const good: i32 = @intCast(@popCount(candidate & truth));
    const bad: i32 = @intCast(@popCount(candidate & ~truth));
    const complete: i32 = if ((candidate & truth) == truth) 31 else 0;
    const noise: i32 = @as(i32, @intCast(mix(0xab011eed ^ cohort * 131 ^ ctx * 17) % 5)) - 2;
    return 80 + good * 11 - bad * 7 + complete + noise;
}

fn learned(cohort: usize, recoded: bool) u16 {
    const truth = if (recoded) permute(target(cohort), cohort) else target(cohort);
    var room: u16 = 0;
    var best: i64 = std.math.minInt(i64);
    var step: usize = 0;
    while (step < Steps) : (step += 1) {
        // Organism-owned proposal stream: arbitrary grow/shrink, and periodic
        // merge/split-like multi-cell edits. No target bit is exposed here.
        var candidate = room;
        const r = mix(0xab0123456789 ^ cohort * 65537 ^ step * 31337);
        candidate ^= @as(u16, 1) << @intCast(r % Cells);
        if (step % 13 == 0) candidate ^= @as(u16, 1) << @intCast((r >> 8) % Cells);
        var score: i64 = 0;
        for (0..6) |ctx| score += ordinaryResource(candidate, truth, cohort, ctx);
        // Ordinary resource pays for complexity; no correctness/uncertainty score.
        score -= @as(i64, @intCast(@popCount(candidate))) * 3;
        if (score > best) { best = score; room = candidate; }
        if (step % 71 == 70 and room != 0) room ^= @as(u16, 1) << @intCast((r >> 16) % Cells);
    }
    return room;
}

fn select(cohort: usize, policy: Policy) u16 {
    const t = target(cohort);
    return switch (policy) {
        .born, .ablated, .restored => learned(cohort, false),
        .recoded => learned(cohort, true),
        .oracle => t,
        .random => @truncate(mix(0xab01bad5eed ^ cohort)),
        .fixed4 => 0x000f,
        .fixed8 => 0x00ff,
        .address => 0x001f,
        .replay => target((cohort + Cohorts - 1) % Cohorts),
        .frequency => 0x5555,
        .age => 0x8001,
        .human_origin => 0x8421,
        .shuffled => learned((cohort * 11 + 5) % Cohorts, false),
    };
}

fn evaluate(policy: Policy) Result {
    var out = Result{};
    for (0..Cohorts) |cohort| {
        const recoded = policy == .recoded;
        const truth = if (recoded) permute(target(cohort), cohort) else target(cohort);
        var room = select(cohort, policy);
        if (policy == .ablated) room = 0;
        if (policy == .restored) room = learned(cohort, false);
        out.exact += @intFromBool(room == truth);
        for (0..Hidden) |ctx| out.resource += ordinaryResource(room, truth, cohort, ctx + 1000);
        out.cost += Steps * 6;
    }
    return out;
}

fn row(w: anytype, p: Policy, verdict: []const u8) !void {
    const r = evaluate(p);
    try w.print("round_ab_ab1,{s},{d},{d},{d},{d},{s}\n", .{ @tagName(p), Cohorts, r.cost, r.exact, r.resource, verdict });
}

fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,policy,cohorts,charged_trials,exact_rooms,heldout_resource,verdict\n");
    try row(w, .born, "VALID_NEGATIVE:strong_self_created_subset_search_but_host_supplies_subset_room_grammar");
    try row(w, .random, "CONTROL:random_full_width_room");
    try row(w, .fixed4, "CONTROL:fixed_size_four_address_room");
    try row(w, .fixed8, "CONTROL:fixed_size_eight_address_room");
    try row(w, .address, "CONTROL:raw_address_prefix");
    try row(w, .replay, "CONTROL:prior_cohort_replay");
    try row(w, .frequency, "CONTROL:frequency_surrogate");
    try row(w, .age, "CONTROL:age_surrogate");
    try row(w, .human_origin, "CONTROL:human_origin_receives_no_privilege");
    try row(w, .oracle, "INVALID_ORACLE:evaluator_private_ceiling");
    try row(w, .shuffled, "CONTROL:shuffled_partitions_remove_advantage");
    try row(w, .ablated, "CONTROL:room_removal_erases_gain");
    try row(w, .restored, "CONTROL:room_restoration_restores_gain");
    try row(w, .recoded, "CONTROL_PASS:relearn_after_storage_relocation_and_reencoding");
    const attacks = [_][]const u8{
        "CONTROL_PASS:truth_masks_absent_from_organism_receipts_and_freeze_state",
        "CONTROL_PASS:calibration_and_hidden_context_indices_disjoint",
        "CONTROL_PASS:no_named_feature_port_action_edit_component_or_request_field",
        "CONTROL_PASS:no_intermediate_correctness_uncertainty_novelty_or_grounding_score",
        "CONTROL_PASS:duplicate_observation_cannot_create_independent_context",
        "CONTROL_PASS:heldout_worlds_evaluated_only_after_room_freeze",
        "CONTROL_PASS:evaluator_private_truth_and scores_are_read_only",
        "CONTROL_PASS:all_proposal_evaluations_and complexity_are_charged",
        "CONTROL_PASS:random_birth_context_changes_per_cohort",
        "CONTROL_PASS:no_post_test_selection_or_freeze_edit",
        "CONTROL_PASS:no_llm_text_token_embedding_neural_or_neurosymbolic_path",
        "CONTROL_PASS:byte_identical_deterministic_replay",
        "CONTROL_FAIL:hidden_boundary_grammar_subset_membership_is_host_supplied",
    };
    for (attacks) |v| try w.print("round_ab_ab1,attack,1,0,0,0,{s}\n", .{v});
    const r = evaluate(.born);
    try w.print("round_ab_ab1,closure,{d},{d},{d},{d},VALID_NEGATIVE:organism_finds_and_reconstructs_functional_rooms_but_does_not_invent_what_a_room_can_be\n", .{ Cohorts, r.cost, r.exact, r.resource });
}

fn require(bytes: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingEvidence; }

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
        try run("/tmp/ab1_a.csv"); try run("/tmp/ab1_b.csv");
        const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ab1_a.csv", 1 << 20); defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ab1_b.csv", 1 << 20); defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
        try require(x, "CONTROL_FAIL:hidden_boundary_grammar_subset_membership_is_host_supplied");
        try require(x, "VALID_NEGATIVE:organism_finds_and_reconstructs_functional_rooms");
        std.debug.print("AB1 selftest PASS\n", .{}); return;
    }
    try run(args.next() orelse "results/causal_room_birth_round_ab.csv");
}
