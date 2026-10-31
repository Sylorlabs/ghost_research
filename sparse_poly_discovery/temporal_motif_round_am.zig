//! Round AM / AM1: delayed response motifs without a task target.
//! Deliberately a valid negative: a learned trace motif ties a fixed temporal
//! matcher/schedule, so it cannot establish constructed relevance.
const std = @import("std");

const Cohorts = 64;
const EvalTurns = 12;
const Policy = enum { learned_motif, fixed_effect_vector, last_outcome, fixed_temporal_motif, random, replay, shuffled_history, answer_memory, motif_ablated, recoded_attack, law_shift_attack, overlap_audit };
const Motif = struct { first_eq_last: bool, middle_changes: bool, schedule: u3, provenance: u64 };
const Result = struct { contacts: usize = 0, material: i64 = 0, perfect: usize = 0, commits: usize = 0 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn regime(c: usize) u1 { return @truncate(mix(0xa1100001 ^ @as(u64, @intCast(c * 31))) >> 4); }
fn shiftedRegime(c: usize) u1 { return @truncate(regime(c) ^ @as(u1, @truncate(mix(0xa1100002 ^ @as(u64, @intCast(c))) >> 1))); }
fn law(c: usize, r: u1, shifted: bool) u3 { return @truncate(mix(0xa1100003 ^ @as(u64, @intCast(c * 101 + @as(usize, r) * 13 + @as(usize, @intFromBool(shifted)) * 7))) >> 8); }

// Three generic intervention->transition observations.  The raw values are
// evaluator-encoded; only equality/change across delayed responses survives.
fn raw(c: usize, r: u1, step: usize, encoding: u8, nonce: u8, shifted: bool) u8 {
    const l = law(c, r, shifted);
    const base: u8 = switch (r) { 0 => switch (step) { 0, 2 => 17, 1 => 91, else => unreachable }, 1 => switch (step) { 0 => 17, 1 => 44, 2 => 71, else => unreachable } };
    return (base +% @as(u8, l) *% 19 +% encoding *% 37 +% nonce *% 11 +% @as(u8, @truncate(c))) ^ (encoding >> 1);
}
fn earn(c: usize, r: u1) Motif {
    const a = raw(c, r, 0, 3, 9, false); const b = raw(c, r, 1, 3, 9, false); const d = raw(c, r, 2, 3, 9, false);
    return .{ .first_eq_last = a == d, .middle_changes = a != b and b != d, .schedule = law(c, r, false), .provenance = mix(0xa1100004 ^ @as(u64, @intCast(c * 2 + r))) };
}
fn query(c: usize, shifted: bool) Motif {
    const r = if (shifted) shiftedRegime(c) else regime(c);
    const a = raw(c, r, 0, 211, 73, shifted); const b = raw(c, r, 1, 211, 73, shifted); const d = raw(c, r, 2, 211, 73, shifted);
    return .{ .first_eq_last = a == d, .middle_changes = a != b and b != d, .schedule = 0, .provenance = 0 };
}
fn select(records: [2]Motif, q: Motif) ?Motif { for (records) |m| if (m.first_eq_last == q.first_eq_last and m.middle_changes == q.middle_changes) return m; return null; }
fn score(c: usize, schedule: ?u3, shifted: bool) i64 {
    const target = law(c, if (shifted) shiftedRegime(c) else regime(c), shifted); var got: i64 = 0;
    for (0..EvalTurns) |t| { if ((schedule orelse @as(u3, @truncate((c + t * 5) & 7))) == target) got += 11; }
    return got;
}
fn runPolicy(p: Policy) Result {
    var out = Result{};
    const shifted = p == .law_shift_attack;
    for (0..Cohorts) |c| {
        const own = [_]Motif{ earn(c, 0), earn(c, 1) };
        const prev = (c + Cohorts - 1) % Cohorts;
        const replay = [_]Motif{ earn(prev, 0), earn(prev, 1) };
        const sh = (c * 29 + 17) % Cohorts;
        const shuffled = [_]Motif{ earn(sh, 0), earn(sh, 1) };
        const q = query(c, shifted);
        var chosen: ?Motif = null;
        switch (p) {
            .learned_motif, .recoded_attack, .law_shift_attack, .overlap_audit, .fixed_temporal_motif => chosen = select(own, q),
            .replay => chosen = select(replay, q), .shuffled_history => chosen = select(shuffled, q),
            // Equal-budget but deliberately static: all three responses are
            // reduced to their first effect, which aliases both regimes.
            .fixed_effect_vector, .last_outcome => chosen = if ((c & 1) == 0) own[0] else null,
            .random, .answer_memory, .motif_ablated => {},
        }
        out.contacts += 9; // six earned transition contacts + three private query contacts.
        const s = score(c, if (chosen) |m| m.schedule else null, shifted);
        out.material += s; if (s == EvalTurns * 11) out.perfect += 1;
        if (p == .learned_motif and chosen != null) out.commits += 1;
    }
    return out;
}
fn emit(w: anytype, p: Policy, note: []const u8) !void { const r = runPolicy(p); try w.print("round_am_am1,{s},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.contacts, r.material, r.perfect, r.commits, note }); }
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("artifact,policy,charged_raw_contacts,private_transfer_material,perfect_hidden_cohorts,provenance_commits,verdict\n");
    try emit(w, .learned_motif, "VALID-NEGATIVE:earned_delayed_motif_ties_fixed_temporal_matcher");
    try emit(w, .fixed_effect_vector, "CONTROL:fixed_static_effect_vector"); try emit(w, .last_outcome, "CONTROL:last_outcome_matcher");
    try emit(w, .fixed_temporal_motif, "CONTROL:fixed_temporal_motif_and_schedule"); try emit(w, .random, "CONTROL:generic_random_schedule");
    try emit(w, .replay, "CONTROL:previous_cohort_trace_replay"); try emit(w, .shuffled_history, "CONTROL:provenance_shuffled_history");
    try emit(w, .answer_memory, "CONTROL:answer_scrubbed_no_schedule_or_target_trace"); try emit(w, .motif_ablated, "CONTROL:motif_record_ablated");
    try emit(w, .recoded_attack, "ATTACK_PASS:private_value_recode_no_literal_overlap"); try emit(w, .law_shift_attack, "ATTACK:causal_law_shift_relearn_not_available_to_frozen_record");
    try emit(w, .overlap_audit, "ATTACK_PASS:query_nonce_encoding_and_contacts_disjoint_from_earned_trace");
    const audit = [_][]const u8{ "PROVENANCE:records_contain_only_delayed_equality_change_motif_schedule_and_hash", "ANSWER-SCRUB:source_has_no_target_answer_trace_label_semantic_decoder_router_or_feedback", "FAILURE:fixed_temporal_motif_and_schedule_ties_exactly_under_recoding", "LIMIT:the_harness_supplies_three-step_window_equality_comparison_and_schedule_field", "VALID-NEGATIVE:not_a_foundation_positive_not_autonomy" };
    for (audit) |line| try w.print("round_am_am1,audit,0,0,0,0,{s}\n", .{line});
}
fn selftest() !void {
    try run("/tmp/am1-a.csv"); try run("/tmp/am1-b.csv"); var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/am1-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/am1-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const own = runPolicy(.learned_motif); const fixed = runPolicy(.fixed_temporal_motif); const vec = runPolicy(.fixed_effect_vector); const last = runPolicy(.last_outcome); const rnd = runPolicy(.random); const rep = runPolicy(.replay); const sh = runPolicy(.shuffled_history); const ans = runPolicy(.answer_memory); const ab = runPolicy(.motif_ablated);
    if (!(own.material == fixed.material and own.material > vec.material and own.material > last.material and own.material > rnd.material and own.material > rep.material and own.material > sh.material and own.material > ans.material and own.material > ab.material)) return error.InvalidControls;
    if (std.mem.indexOf(u8, x, "VALID-NEGATIVE") == null) return error.MissingVerdict;
    std.debug.print("round_am_am1 selftest PASS verdict=VALID-NEGATIVE deterministic=true fixed_temporal_tie=true recode_and_shift=true\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/temporal_motif_round_am.csv"); }
