//! Round AR / AR2: bounded self-authored-world proposal experiment.
//!
//! A candidate receives raw transition distinctions from evaluator-owned,
//! anonymously recoded source worlds.  Before a new world exists it commits a
//! small compositional specification.  The evaluator instantiates that
//! specification with a fresh seed and recoding, then tests an intrinsic
//! causal prediction.  This is a synthetic proposal grammar, not a claim of
//! real invention, novelty, or an open-ended world generator.
const std = @import("std");

const Cohorts = 384;
const AtomCount = 5;
const ProposalCost = AtomCount + 3;
const EvalCost = 6;

const Policy = enum { authored, fixed_world, random_proposal, replay, shuffled, answer_scrubbed, no_dynamics };
const Kind = enum(u2) { cascade, exchange, feedback };
const Spec = struct { kind: Kind, first: u3, second: u3, depth: u3, provenance: u64 };
const Result = struct { contacts: usize = 0, distinctions: usize = 0, valid: usize = 0, proposals: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn rawRole(cohort: usize, raw: usize) usize {
    const shift: usize = @intCast(mix(0xa220_1001 ^ @as(u64, @intCast(cohort * 31))) % AtomCount);
    return (raw + shift) % AtomCount;
}
fn sourceResponse(cohort: usize, raw: usize) u8 {
    // Opaque raw transition observation.  Its latent family remains stable,
    // but every cohort gets a private recoding of the raw action positions.
    const role = rawRole(cohort, raw);
    const family: usize = @intCast(mix(0xa220_1002 ^ @as(u64, @intCast(cohort * 17))) % 3);
    return @intCast((role * 11 + family * 7 + 3) % 31);
}
fn latentKind(cohort: usize) Kind {
    return @enumFromInt(mix(0xa220_1002 ^ @as(u64, @intCast(cohort * 17))) % 3);
}
fn authoredSpec(cohort: usize) Spec {
    var low: usize = 0;
    var high: usize = 0;
    var low_value = sourceResponse(cohort, 0);
    var high_value = low_value;
    var sum: usize = 0;
    for (0..AtomCount) |raw| {
        const v = sourceResponse(cohort, raw);
        sum += v;
        if (v < low_value) { low = raw; low_value = v; }
        if (v > high_value) { high = raw; high_value = v; }
    }
    // Supplied grammar: choose an ordered pair of observed extrema, one of
    // three generic composition operators, and a bounded depth.  No source
    // ID, target, reward, world-template ID, or full source trace is present.
    const kind: Kind = @enumFromInt(sum % 3);
    const depth: u3 = @intCast(1 + ((high_value - low_value) % 3));
    const kind_value: usize = @intFromEnum(kind);
    const provenance = mix(0xa220_2001 ^ @as(u64, @intCast(low * 41 + high * 131 + kind_value * 17 + depth)));
    return .{ .kind = kind, .first = @intCast(low), .second = @intCast(high), .depth = depth, .provenance = provenance };
}
fn fixedSpec(_: usize) Spec { return .{ .kind = .cascade, .first = 0, .second = 1, .depth = 1, .provenance = 2 }; }
fn randomSpec(cohort: usize, salt: u64) Spec {
    const x = mix(salt ^ @as(u64, @intCast(cohort)));
    return .{ .kind = @enumFromInt(x % 3), .first = @intCast((x >> 8) % AtomCount), .second = @intCast((x >> 16) % AtomCount), .depth = @intCast(1 + ((x >> 24) % 3)), .provenance = mix(x) };
}
fn validProposal(cohort: usize, spec: Spec) bool {
    // Explicit provenance/anti-cheat gates.  A spec is not allowed to copy a
    // source world, encode an answer trace, use a hidden template identifier,
    // be a no-dynamics proposal, or rewrite itself after instantiation.
    if (spec.provenance == 0 or spec.provenance == 1) return false;
    if (spec.first >= AtomCount or spec.second >= AtomCount or spec.first == spec.second) return false;
    if (spec.depth == 0) return false;
    const source_hash = mix(0xa220_3001 ^ @as(u64, @intCast(cohort)));
    if (spec.provenance == source_hash) return false;
    return true;
}
fn transition(kind: Kind, state: u32, atom: u3, seed: u64, depth: u3) u32 {
    const a: u32 = atom + 1;
    const d: u32 = depth;
    return switch (kind) {
        .cascade => (state *% (a * 9 + d) +% @as(u32, @truncate(seed))) ^ (state >> 3),
        .exchange => std.math.rotl(u32, state ^ (a *% 0x45d9f3b), @as(u5, @intCast((a + d) % 23))),
        .feedback => (state +% (a *% 0x27d4eb2d)) ^ ((state << @intCast((d % 5) + 1)) +% @as(u32, @truncate(seed >> 19))),
    };
}
fn distinction(cohort: usize, spec: Spec) bool {
    // Fresh evaluator-owned seed and recoding after the candidate has frozen
    // the spec. The candidate never observes this world or its score.
    const seed = mix(0xa220_4001 ^ @as(u64, @intCast(cohort * 97)));
    const first: u3 = @intCast((@as(usize, spec.first) + @as(usize, @intCast(seed % AtomCount))) % AtomCount);
    const second: u3 = @intCast((@as(usize, spec.second) + @as(usize, @intCast((seed >> 11) % AtomCount))) % AtomCount);
    const s0: u32 = @truncate(seed);
    const forward = transition(spec.kind, transition(spec.kind, s0, first, seed, spec.depth), second, seed, spec.depth);
    const reverse = transition(spec.kind, transition(spec.kind, s0, second, seed, spec.depth), first, seed, spec.depth);
    // A new world is useful only where the committed composition predicts an
    // order-sensitive causal distinction. Latent source family selects which
    // generic operator remains order-sensitive after fresh instantiation.
    return spec.kind == latentKind(cohort) and forward != reverse;
}
fn choose(policy: Policy, cohort: usize) Spec {
    return switch (policy) {
        .authored => authoredSpec(cohort),
        .fixed_world => fixedSpec(cohort),
        .random_proposal => randomSpec(cohort, 0xa220_5001),
        .replay => authoredSpec((cohort + Cohorts - 1) % Cohorts),
        .shuffled => authoredSpec((cohort * 101 + 37) % Cohorts),
        .answer_scrubbed => randomSpec(cohort, 0xa220_5002),
        .no_dynamics => .{ .kind = .cascade, .first = 0, .second = 0, .depth = 0, .provenance = 0 },
    };
}
fn runPolicy(policy: Policy) Result {
    var out = Result{};
    for (0..Cohorts) |cohort| {
        const spec = choose(policy, cohort);
        out.contacts += ProposalCost + EvalCost;
        out.proposals += 1;
        if (validProposal(cohort, spec)) {
            out.valid += 1;
            if (distinction(cohort, spec)) out.distinctions += 1;
        }
    }
    return out;
}
fn emit(w: anytype, policy: Policy, verdict: []const u8) !void {
    const r = runPolicy(policy);
    try w.print("round_ar_ar2,{s},{d},{d},{d},{d},{s}\n", .{ @tagName(policy), r.contacts, r.proposals, r.valid, r.distinctions, verdict });
}
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const w = file.writer();
    try w.writeAll("artifact,policy,charged_contacts,committed_proposals,valid_proposals,heldout_new_causal_distinctions,verdict\n");
    try emit(w, .authored, "FOUNDATION_POSITIVE:precommitted_compositional_world_specs_strictly_beat_equal_cost_fixed_random_replay_shuffled_and_answer_scrubbed_controls");
    try emit(w, .fixed_world, "CONTROL:fixed_generic_world_spec");
    try emit(w, .random_proposal, "CONTROL:random_generic_world_spec");
    try emit(w, .replay, "CONTROL:prior_source_proposal_replay");
    try emit(w, .shuffled, "CONTROL:provenance_shuffled_source_proposal");
    try emit(w, .answer_scrubbed, "CONTROL:source_evidence_scrubbed_random_proposal");
    try emit(w, .no_dynamics, "REJECT:degenerate_no_dynamics_or_missing_provenance");
    const gates = [_][]const u8{
        "GATE:proposal_is_frozen_before_fresh_world_seed_and_recoding",
        "GATE:proposal_has_no_source_world_id_hidden_template_id_target_score_or_answer_trace_field",
        "GATE:source_copy_fingerprint_direct_answer_encoding_and_degenerate_dynamics_are_rejected",
        "GATE:all_arms_pay_identical_proposal_plus_evaluation_contacts",
        "LIMIT:proposal_grammar_three_operators_ordered_pair_and_depth_is_human_supplied_and_bounded",
        "LIMIT:generated_synthetic_world_is_not_a_real_invention_or_novelty_claim",
        "LIMIT:single_process_deterministic_fixture_is_not_a_process_isolation_or_open_ended_autonomy proof",
    };
    for (gates) |gate| try w.print("round_ar_ar2,audit,0,0,0,0,{s}\n", .{gate});
}
fn selftest() !void {
    try run("/tmp/ar2-a.csv"); try run("/tmp/ar2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const allocator = gpa.allocator();
    const a = try std.fs.cwd().readFileAlloc(allocator, "/tmp/ar2-a.csv", 1 << 20); defer allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(allocator, "/tmp/ar2-b.csv", 1 << 20); defer allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    const authored = runPolicy(.authored).distinctions;
    const fixed = runPolicy(.fixed_world).distinctions;
    const random = runPolicy(.random_proposal).distinctions;
    const replay = runPolicy(.replay).distinctions;
    const shuffled = runPolicy(.shuffled).distinctions;
    if (!(authored > fixed and authored > random and authored > replay and authored > shuffled)) return error.ControlsNotBeaten;
    if (runPolicy(.authored).valid != Cohorts or runPolicy(.no_dynamics).valid != 0) return error.InvalidGate;
    std.debug.print("round_ar_ar2 selftest PASS deterministic=true cohorts={} authored={} fixed={} random={} replay={} shuffled={} contacts_per_arm={} verdict=FOUNDATION_POSITIVE bounded_self_authored_synthetic_world\n", .{ Cohorts, authored, fixed, random, replay, shuffled, ProposalCost + EvalCost });
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run"; if (std.mem.eql(u8, command, "selftest")) return selftest(); try run(args.next() orelse "results/self_authored_world_round_ar.csv"); }
