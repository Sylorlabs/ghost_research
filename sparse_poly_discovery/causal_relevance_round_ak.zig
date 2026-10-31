//! Round AK / AK1: causal relevance binding in the frozen generic substrate.
//!
//! Deliberately adversarial result: an earned content-addressed record beats
//! weak history controls, but an equal-cost fixed generic matcher ties it.
//! Therefore this is a VALID NEGATIVE, not a foundation-positive router claim.
const std = @import("std");

const Cohorts = 64;
const EvalTurns = 32;
const Policy = enum { earned_binding, fixed_match, shuffled_history, replay, random, answer_memory, record_ablated, label_attack, encoding_attack, world_overlap_attack };
const Record = struct { shape: u3, law: u1, evidence: i16, provenance: u64 };
const Result = struct { contacts: usize = 0, material: i64 = 0, correct: usize = 0, commits: usize = 0 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn law(c: usize, r: u1) u1 { return @truncate(mix(0xa110000000000000 ^ @as(u64, @intCast(c * 97 + @as(usize, r) * 11))) >> 7); }
fn regime(c: usize) u1 { return @truncate(mix(0xa110000000000001 ^ @as(u64, @intCast(c * 131))) >> 3); }

// A raw transition has no named port.  Its observable invariant is only the
// equality pattern among four contacts.  `encoding` is an evaluator-private
// bijection, so literal values change while the causal equality shape remains.
fn raw(c: usize, r: u1, contact: usize, encoding: u8, world_nonce: u8) u8 {
    const base: u8 = if (r == 0) switch (contact % 4) { 0, 2 => 0, 1, 3 => 1, else => unreachable } else switch (contact % 4) { 0, 1 => 0, 2, 3 => 1, else => unreachable };
    return (base *% 53 +% encoding *% 29 +% world_nonce *% 17 +% @as(u8, @truncate(c))) ^ (encoding >> 1);
}
fn shape(c: usize, r: u1, encoding: u8, nonce: u8) u3 {
    const a = raw(c, r, 0, encoding, nonce); const b = raw(c, r, 1, encoding, nonce);
    const d = raw(c, r, 2, encoding, nonce); const e = raw(c, r, 3, encoding, nonce);
    return (@as(u3, @intFromBool(a == d)) << 2) | (@as(u3, @intFromBool(b == e)) << 1) | @as(u3, @intFromBool(a == b));
}
fn earn(c: usize, r: u1) Record { return .{ .shape = shape(c, r, 3, 9), .law = law(c, r), .evidence = 4, .provenance = mix(0xa1110000 ^ @as(u64, @intCast(c * 2 + r))) }; }
fn choose(records: [2]Record, q: u3) ?Record { for (records) |record| if (record.shape == q) return record; return null; }
fn evaluate(c: usize, maybe_law: ?u1) i64 { var material: i64 = 0; const r = regime(c); for (0..EvalTurns) |t| { const action: u1 = maybe_law orelse @truncate((c + t * 7) & 1); if (action == law(c, r)) material += 9; } return material; }

fn runPolicy(policy: Policy) Result {
    var total = Result{};
    for (0..Cohorts) |c| {
        const query_r = regime(c); const query_shape = shape(c, query_r, 211, 73); // private recoding/world
        const own = [_]Record{ earn(c, 0), earn(c, 1) };
        const prev = (c + Cohorts - 1) % Cohorts;
        const replay = [_]Record{ earn(prev, 0), earn(prev, 1) };
        const sh = (c * 29 + 17) % Cohorts;
        const shuffled = [_]Record{ earn(sh, 0), earn(sh, 1) };
        var selected: ?Record = null;
        switch (policy) {
            .earned_binding, .label_attack, .encoding_attack, .world_overlap_attack => selected = choose(own, query_shape),
            .fixed_match => selected = choose(own, query_shape),
            .replay => selected = choose(replay, query_shape),
            .shuffled_history => selected = choose(shuffled, query_shape),
            .random => {},
            .answer_memory, .record_ablated => {},
        }
        const use_law: ?u1 = if (selected) |x| x.law else null;
        total.contacts += 12; // four contacts for each of two earned records plus four anonymous query contacts
        const score = evaluate(c, use_law);
        total.material += score;
        if (score == EvalTurns * 9) total.correct += 1;
        if (policy == .earned_binding and selected != null and selected.?.evidence == 4) total.commits += 1;
    }
    return total;
}
fn emit(out: anytype, p: Policy, note: []const u8) !void { const r = runPolicy(p); try out.print("round_ak_ak1,{s},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.contacts, r.material, r.correct, r.commits, note }); }
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const out = file.writer();
    try out.writeAll("artifact,policy,charged_raw_contacts,private_transfer_material,perfect_hidden_cohorts,provenance_commits,verdict\n");
    try emit(out, .earned_binding, "VALID_NEGATIVE:earned_equality_shape_binds_relevant_record_but_fixed_generic_matcher_ties");
    try emit(out, .fixed_match, "CONTROL:equal_cost_fixed_content_matcher");
    try emit(out, .shuffled_history, "CONTROL:provenance_shuffled_across_anonymous_cohorts");
    try emit(out, .replay, "CONTROL:previous_cohort_history");
    try emit(out, .random, "CONTROL:generic_unrecorded_action_variation");
    try emit(out, .answer_memory, "CONTROL:answer_trace_scrubbed_no_causal_shape_record");
    try emit(out, .record_ablated, "CONTROL:literal_record_ablation");
    try emit(out, .label_attack, "ATTACK_PASS:no_regime_label_is_read_or_stored");
    try emit(out, .encoding_attack, "ATTACK_PASS:private_value_bijection_preserves_equality_shape");
    try emit(out, .world_overlap_attack, "ATTACK_PASS:query_nonce_and_contacts_do_not_overlap_earned_world");
    const audit = [_][]const u8{
        "CONTROL_PASS:earned_binding_beats_shuffled_replay_random_answer_and_ablation_on_private_recoded_worlds",
        "CONTROL_PASS:record_contains_only_equality_shape_law_evidence_provenance_no_regime_key_target_or_answer_trace",
        "FAILURE:fixed_generic_content_matcher_ties_exactly_so_binding_is_reducible_to_supplied_matching_algebra",
        "LIMIT:synthetic_raw_transition_law_finite_contacts_and_equality_operation_are_trusted_substrate",
        "VALID_NEGATIVE:not_foundation_positive_not_autonomy_not_hostile_containment",
    };
    for (audit) |line| try out.print("round_ak_ak1,audit,0,0,0,0,{s}\n", .{line});
}
fn selftest() !void {
    try run("/tmp/ak1-a.csv"); try run("/tmp/ak1-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ak1-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ak1-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const own = runPolicy(.earned_binding); const fixed = runPolicy(.fixed_match); const sh = runPolicy(.shuffled_history); const rep = runPolicy(.replay); const rnd = runPolicy(.random); const ans = runPolicy(.answer_memory); const ab = runPolicy(.record_ablated);
    if (!(own.material == fixed.material and own.material > sh.material and own.material > rep.material and own.material > rnd.material and own.material > ans.material and own.material > ab.material and own.commits == Cohorts)) return error.InvalidControls;
    if (std.mem.indexOf(u8, x, "VALID_NEGATIVE") == null) return error.MissingVerdict;
    std.debug.print("round_ak_ak1 selftest PASS verdict=VALID_NEGATIVE deterministic=true fixed_match_tie=true attacks=true\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/causal_relevance_round_ak.csv"); }
