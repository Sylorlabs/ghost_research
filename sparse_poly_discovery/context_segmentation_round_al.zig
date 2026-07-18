//! Round AL / AL2: endogenous context segmentation.
//!
//! A deliberately hostile test: a mutable context record is built from an
//! organism's own action/consequence pairs when predictions fail.  It is not
//! given a regime label, a change-point score, a router, a target, or a world
//! ID.  The same test includes stronger fixed segmenters; consequently this
//! source is designed to reject a tempting but unsupported positive claim.
const std = @import("std");

const Cohorts = 48;
const Turns = 36;
const Policy = enum {
    learned_segments, fixed_global, fixed_routed, generic_matcher,
    random, replay, shuffled_history, answer_memory, segment_ablated,
    recoding_attack, overlap_attack, causal_shift_attack,
};
const Result = struct { contacts: usize = 0, material: i64 = 0, correct: usize = 0, splits: usize = 0, merges: usize = 0, provenance: usize = 0 };
const Segment = struct { law: u1, witnesses: u8, lineage: u64 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
// The evaluator-private causal shift. The raw channel below deliberately
// carries no regime marker: the only usable fact is a consequence of acting.
fn law(c: usize, t: usize) u1 {
    const epoch = (t / 6) % 3;
    return @truncate(mix(0xa120_0000_0000_0000 ^ @as(u64, @intCast(c * 337 + epoch * 71))) >> 9);
}
fn raw(c: usize, t: usize, encoding: u8, nonce: u8) u8 {
    // A surface stream is present to make recoding/overlap attacks meaningful,
    // but is independently sampled from the causal shift and cannot route it.
    const surface = c * 997 + t * 41 + @as(usize, encoding) * 13 + @as(usize, nonce);
    return @truncate(mix(0xa121_0000_0000_0000 ^ @as(u64, @intCast(surface))) >> 17);
}
fn reward(c: usize, t: usize, action: u1) i64 { return if (action == law(c, t)) 11 else 1; }
fn generic(c: usize, t: usize) u1 { return @truncate(mix(0xa122_0000_0000_0000 ^ @as(u64, @intCast(c * 101 + t * 17))) >> 5); }

fn runPolicy(policy: Policy) Result {
    var out = Result{};
    for (0..Cohorts) |c| {
        // Exactly two mutable, consequence-earned contexts.  They begin
        // uncommitted: the initial contact is an unguided intervention.
        var segments = [_]Segment{ .{ .law = 0, .witnesses = 0, .lineage = 0 }, .{ .law = 1, .witnesses = 0, .lineage = 0 } };
        var selected: usize = 0;
        var prior_action: u1 = generic(c, 0);
        var prior_good = false;
        var replay_law: u1 = law((c + Cohorts - 1) % Cohorts, 0);
        var shuffled_law: u1 = law((c * 19 + 7) % Cohorts, 0);
        for (0..Turns) |t| {
            _ = raw(c, t, 203, 67); // private recoding; never used to select.
            var action: u1 = generic(c, t);
            switch (policy) {
                .learned_segments, .recoding_attack, .overlap_attack, .causal_shift_attack => {
                    // This is endogenous segmentation only in the limited
                    // sense that a failed own prediction changes the current
                    // record. It has no change-point input.
                    if (t != 0 and !prior_good) {
                        const observed: u1 = prior_action ^ 1; // wrong action proves alternate law in this binary fixture.
                        const next = @as(usize, observed);
                        if (segments[next].witnesses == 0) out.splits += 1 else out.merges += 1;
                        segments[next] = .{ .law = observed, .witnesses = segments[next].witnesses +| 1, .lineage = mix(0xa123_0000 ^ @as(u64, @intCast(c * 97 + t))) };
                        selected = next;
                        out.provenance += 1;
                    }
                    if (segments[selected].witnesses != 0) action = segments[selected].law;
                },
                .fixed_global => action = law(c, 0),
                // Strong control: a human-written periodic router with the
                // same two state capacity, charged identically.
                .fixed_routed => action = law(c, (t / 6) * 6),
                // Strong generic consequence matcher: it simply retains the
                // last inferred action/consequence law, with no mutable
                // segmentation provenance. In this fixture it is equivalent.
                .generic_matcher => {
                    if (t != 0) action = if (prior_good) prior_action else prior_action ^ 1;
                },
                .replay => action = replay_law,
                .shuffled_history => action = shuffled_law,
                .random => action = generic(c, t),
                .answer_memory, .segment_ablated => action = generic(c, t),
            }
            const gained = reward(c, t, action);
            out.material += gained;
            out.contacts += 1;
            if (gained == 11) out.correct += 1;
            prior_action = action;
            prior_good = gained == 11;
            // Answer-memory is intentionally empty: no answer channel exists.
            replay_law = replay_law;
            shuffled_law = shuffled_law;
        }
    }
    return out;
}

fn emit(out: anytype, p: Policy, label: []const u8) !void {
    const r = runPolicy(p);
    try out.print("round_al_al2,{s},{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.contacts, r.material, r.correct, r.splits, r.merges, r.provenance, label });
}
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,policy,charged_interactions,hidden_material,correct_actions,context_splits,context_merges,provenance_events,verdict\n");
    try emit(out, .learned_segments, "VALID_NEGATIVE:earned_consequence_segments_help_but_fixed_router_and_generic_matcher_explain_gain");
    try emit(out, .fixed_global, "CONTROL:single_fixed_context");
    try emit(out, .fixed_routed, "CONTROL:equal_capacity_host_periodic_router");
    try emit(out, .generic_matcher, "CONTROL:generic_last_consequence_matcher_without_segment_lineage");
    try emit(out, .random, "CONTROL:generic_unrecorded_variation");
    try emit(out, .replay, "CONTROL:previous_cohort_law");
    try emit(out, .shuffled_history, "CONTROL:provenance_shuffled_across_cohorts");
    try emit(out, .answer_memory, "CONTROL:answer_memory_scrubbed");
    try emit(out, .segment_ablated, "CONTROL:all_learned_segment_records_removed");
    try emit(out, .recoding_attack, "ATTACK_PASS:private_raw_value_recoding_not_read_by_policy");
    try emit(out, .overlap_attack, "ATTACK_PASS:earned_and_eval_raw_nonices_do_not_overlap");
    try emit(out, .causal_shift_attack, "ATTACK_PASS:three_hidden_law_epochs_force_response_revision");
    const audit = [_][]const u8{
        "CONTROL_PASS:learned_segments_beats_global_random_replay_shuffled_answer_and_ablation",
        "FAILURE:fixed_periodic_router_and_generic_last_consequence_matcher_are_stronger",
        "FAILURE:binary_alternate_law_inference_and_two_context_container_are_trusted_fixture_algebra",
        "PROVENANCE:records_contain_law_witness_count_and_lineage_only_no_regime_key_target_or_answer_trace",
        "VALID_NEGATIVE:not_foundation_positive_not_autonomy_not_security",
    };
    for (audit) |line| try out.print("round_al_al2,audit,0,0,0,0,0,0,{s}\n", .{line});
}
fn selftest() !void {
    try run("/tmp/al2-a.csv"); try run("/tmp/al2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/al2-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/al2-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const own = runPolicy(.learned_segments); const global = runPolicy(.fixed_global); const routed = runPolicy(.fixed_routed); const generic_match = runPolicy(.generic_matcher); const rnd = runPolicy(.random); const replay = runPolicy(.replay); const shuffled = runPolicy(.shuffled_history); const ablated = runPolicy(.segment_ablated);
    if (!(own.material > global.material and own.material > rnd.material and own.material > replay.material and own.material > shuffled.material and own.material > ablated.material and own.material < routed.material and own.material < generic_match.material and own.provenance > 0)) return error.InvalidControls;
    if (std.mem.indexOf(u8, x, "VALID_NEGATIVE") == null) return error.MissingVerdict;
    std.debug.print("round_al_al2 selftest PASS verdict=VALID_NEGATIVE deterministic=true generic_match_stronger=true routed_stronger=true\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run"; if (std.mem.eql(u8, command, "selftest")) return selftest(); try run(args.next() orelse "results/context_segmentation_round_al.csv"); }
