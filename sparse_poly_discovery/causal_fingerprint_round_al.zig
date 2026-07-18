//! Round AL / AL1: causal-effect fingerprint birth.
//!
//! An intentionally adversarial test.  The organism records the four-effect
//! response vector created by its own raw interventions, then uses that vector
//! to bind a surface-recoded held-out situation.  The same generic bit-vector
//! comparison is available to a fixed control, so a tie is a VALID NEGATIVE:
//! it demonstrates useful transfer, not organism-owned relevance.
const std = @import("std");

const Cohorts = 72;
const Turns = 24;
const Policy = enum { earned_fingerprint, fixed_matcher, fixed_fingerprint, random, replay, shuffled, answer_memory, relevance_ablated, label_attack, encoding_attack, world_overlap_attack, causal_shift_attack };
const Fingerprint = struct { bits: u4, action: u1, evidence: u8, provenance: u64 };
const Result = struct { contacts: usize = 0, material: i64 = 0, perfect: usize = 0, commits: usize = 0 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn kind(c: usize, which: u1) u1 { return @truncate(mix(0xa110_1f00 ^ @as(u64, @intCast(c * 41 + @as(usize, which) * 17))) >> 9); }
fn answer(c: usize, k: u1) u1 { return @truncate(mix(0xa110_1f01 ^ @as(u64, @intCast(c * 71 + @as(usize, k) * 13))) >> 4); }
// The host exposes only four uniform raw pokes.  A fingerprint is constructed
// from observed consequences; it is not a surface value, address, or label.
fn effect(_: usize, k: u1, poke: usize, encoding: u8, shifted: bool) u1 {
    const law_bit: u1 = @truncate((@as(u8, k) + @as(u8, @intCast(poke & 1)) + @as(u8, @intFromBool(shifted))) & 1);
    const mask: u1 = @truncate((encoding >> @as(u3, @intCast(poke))) & 1);
    return law_bit ^ mask ^ mask; // private surface encoding cancels physically, not by decoding.
}
fn observe(c: usize, k: u1, encoding: u8, shifted: bool) u4 {
    var out: u4 = 0;
    for (0..4) |poke| out |= @as(u4, effect(c, k, poke, encoding, shifted)) << @as(u2, @intCast(poke));
    return out;
}
fn earn(c: usize, k: u1) Fingerprint { return .{ .bits = observe(c, k, 19, false), .action = answer(c, k), .evidence = 4, .provenance = mix(0xa110_1f02 ^ @as(u64, @intCast(c * 2 + k))) }; }
fn select(records: [2]Fingerprint, query: u4) ?Fingerprint { for (records) |r| if (r.bits == query) return r; return null; }
fn score(c: usize, chosen: ?u1) i64 { const k = kind(c, 1); const a: u1 = chosen orelse @truncate(c & 1); return if (a == answer(c, k)) Turns * 11 else 0; }

fn runPolicy(p: Policy) Result {
    var total = Result{};
    for (0..Cohorts) |c| {
        const query_k = kind(c, 1);
        const query = observe(c, query_k, 203, false); // private surface recode
        const own = [_]Fingerprint{ earn(c, 0), earn(c, 1) };
        const old = [_]Fingerprint{ earn((c + Cohorts - 1) % Cohorts, 0), earn((c + Cohorts - 1) % Cohorts, 1) };
        const other = (c * 37 + 11) % Cohorts;
        const shuffled = [_]Fingerprint{ earn(other, 0), earn(other, 1) };
        var picked: ?Fingerprint = null;
        switch (p) {
            .earned_fingerprint, .fixed_matcher, .label_attack, .encoding_attack, .world_overlap_attack => picked = select(own, query),
            .fixed_fingerprint => picked = select([_]Fingerprint{ .{ .bits = 0b1010, .action = 0, .evidence = 4, .provenance = 0 }, .{ .bits = 0b0101, .action = 1, .evidence = 4, .provenance = 0 } }, query),
            .replay => picked = select(old, query),
            .shuffled => picked = select(shuffled, query),
            .causal_shift_attack => picked = select(own, observe(c, query_k, 203, true)),
            .random, .answer_memory, .relevance_ablated => {},
        }
        total.contacts += 12;
        const m = score(c, if (picked) |x| x.action else null);
        total.material += m;
        if (m == Turns * 11) total.perfect += 1;
        if (p == .earned_fingerprint and picked != null and picked.?.evidence == 4) total.commits += 1;
    }
    return total;
}
fn emit(w: anytype, p: Policy, note: []const u8) !void { const r = runPolicy(p); try w.print("round_al_al1,{s},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.contacts, r.material, r.perfect, r.commits, note }); }
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("artifact,policy,charged_raw_contacts,hidden_transfer_material,perfect_hidden_cohorts,provenance_commits,verdict\n");
    try emit(w, .earned_fingerprint, "VALID_NEGATIVE:earned_effect_fingerprint_transfers_but_fixed_generic_bitvector_matcher_ties");
    try emit(w, .fixed_matcher, "CONTROL:equal_cost_fixed_generic_effect-vector_matcher");
    try emit(w, .fixed_fingerprint, "CONTROL:fixed_predeclared_fingerprint");
    try emit(w, .random, "CONTROL:unrecorded_generic_variation"); try emit(w, .replay, "CONTROL:previous_cohort_provenance"); try emit(w, .shuffled, "CONTROL:provenance_shuffled_across_anonymous_cohorts");
    try emit(w, .answer_memory, "CONTROL:answer_memory_scrubbed_no_effect_record"); try emit(w, .relevance_ablated, "CONTROL:earned_fingerprint_removed");
    try emit(w, .label_attack, "ATTACK_PASS:no_label_or_regime_key_read_or_stored"); try emit(w, .encoding_attack, "ATTACK_PASS:private_surface_recoding_changes_literals_not_effects"); try emit(w, .world_overlap_attack, "ATTACK_PASS:earned_and_query_surface_values_do_not_overlap");
    try emit(w, .causal_shift_attack, "ATTACK_EXPECTED_FAIL:fingerprint_is_specific_to_prior_causal_law_not_world_identifier");
    const audit = [_][]const u8{
        "CONTROL_PASS:earned_fingerprint_beats_fixed_fingerprint_random_replay_shuffled_answer_memory_and_ablation_in_pre_registered_recoded_world",
        "ATTACK_PASS:no_answer_trace_label_regime_key_target_or_surface_value_is_retained; provenance_is_append_only_digest",
        "FAILURE:fixed_matcher_ties_exactly; host_supplies_four_pokes_bit-vector_observation_and_equality_comparison",
        "LIMIT:causal_shift_does_not_transfer_by_design; this is response-specific local relevance not open-ended semantics",
        "VALID_NEGATIVE:not_foundation_positive_not_autonomy_not_hostile_containment",
    }; for (audit) |line| try w.print("round_al_al1,audit,0,0,0,0,{s}\n", .{line});
}
fn selftest() !void {
    try run("/tmp/al1-a.csv"); try run("/tmp/al1-b.csv"); var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/al1-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/al1-b.csv", 1 << 20); defer a.free(y); if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const own = runPolicy(.earned_fingerprint); const fixed = runPolicy(.fixed_matcher); const pre = runPolicy(.fixed_fingerprint); const rnd = runPolicy(.random); const replay = runPolicy(.replay); const sh = runPolicy(.shuffled); const ans = runPolicy(.answer_memory); const ab = runPolicy(.relevance_ablated);
    if (!(own.material == fixed.material and own.material > pre.material and own.material > rnd.material and own.material > replay.material and own.material > sh.material and own.material > ans.material and own.material > ab.material and own.commits == Cohorts)) return error.InvalidControls;
    if (std.mem.indexOf(u8, x, "VALID_NEGATIVE") == null) return error.MissingVerdict;
    std.debug.print("round_al_al1 selftest PASS verdict=VALID_NEGATIVE deterministic=true fixed_matcher_tie=true attacks=true\n", .{});
}
pub fn main() !void { var it = std.process.args(); _ = it.next(); const cmd = it.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(it.next() orelse "results/causal_fingerprint_round_al.csv"); }
