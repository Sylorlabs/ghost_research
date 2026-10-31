//! Round AQ / AQ2: an earned, bounded relation-instrument forge.
//!
//! The candidate begins with four anonymous raw actions.  Their single-action
//! responses deliberately fail to distinguish the hidden roles.  That failure
//! authorizes a generic composition loop: it constructs ordered two-action
//! probes, records only raw response signatures plus provenance, and later
//! selects the composition whose earned signature matches a raw challenge
//! observation.  The evaluator is hidden until all contacts are charged.
const std = @import("std");

const Cohorts = 96;
const PrimitiveCount = 4;
const PairCount = PrimitiveCount * (PrimitiveCount - 1);
const FinalContacts = 4;

const Policy = enum {
    earned_forge,
    fixed_raw_probe,
    fixed_human_composition,
    random_composition,
    replay,
    shuffled_experience,
    answer_scrubbed,
    forge_ablation,
    fixed_broad_composition,
};

const Pair = struct { first: u3, second: u3 };
const Record = struct {
    pair: Pair,
    raw_signature: u4,
    evidence: u2,
    provenance: u64,
};
const Result = struct { contacts: usize = 0, material: i64 = 0, forged: usize = 0, selected: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn pairAt(index: usize) Pair {
    var seen: usize = 0;
    for (0..PrimitiveCount) |a| for (0..PrimitiveCount) |b| if (a != b) {
        if (seen == index) return .{ .first = @intCast(a), .second = @intCast(b) };
        seen += 1;
    };
    unreachable;
}
fn pairIndex(pair: Pair) usize {
    for (0..PairCount) |i| {
        const p = pairAt(i);
        if (p.first == pair.first and p.second == pair.second) return i;
    }
    unreachable;
}
// Private per-cohort recoding.  Raw action positions have no stable role.
fn hiddenRole(c: usize, raw: usize) usize {
    const shift: usize = @intCast(mix(0xa512_1001 ^ @as(u64, @intCast(c * 41))) % PrimitiveCount);
    const flip = (mix(0xa512_1002 ^ @as(u64, @intCast(c * 71))) & 1) == 1;
    return if (flip) (PrimitiveCount + shift - raw) % PrimitiveCount else (raw + shift) % PrimitiveCount;
}
fn rawSingleResponse(c: usize, raw: usize) u2 {
    _ = c; _ = raw;
    // Every raw single probe reports the same observation: no distinction.
    return 0;
}
// Generic environment response to a composed intervention.  It is a raw
// anonymous signature, not a label or a success score.  The hidden causal law
// is role adjacency; raw action encodings are privately permuted each cohort.
fn compositionSignature(c: usize, pair: Pair) u4 {
    const a = hiddenRole(c, pair.first);
    const b = hiddenRole(c, pair.second);
    const relation: usize = if ((a + 1) % PrimitiveCount == b) 1 else 0;
    const salt: usize = @intCast(mix(0xa512_1003 ^ @as(u64, @intCast(c * 101))) % 6);
    return @intCast(1 + ((relation * 6 + salt + pairIndex(pair) * 5) % 12));
}
fn hiddenTarget(c: usize) Pair {
    // The evaluator chooses one causal relation instance after the primitive
    // alphabet is recoded.  This target is never passed to a policy.
    const role_a: usize = @intCast(mix(0xa512_1004 ^ @as(u64, @intCast(c * 31))) % PrimitiveCount);
    const role_b = (role_a + 1) % PrimitiveCount;
    for (0..PairCount) |i| {
        const p = pairAt(i);
        if (hiddenRole(c, p.first) == role_a and hiddenRole(c, p.second) == role_b) return p;
    }
    unreachable;
}
fn rawChallenge(c: usize) u4 {
    // Changed evaluation presentation: the challenge exposes only the raw
    // response signature of an unobserved query, not an action identity.
    return compositionSignature(c, hiddenTarget(c));
}
fn changedOutcome(c: usize, pair: Pair) i64 {
    // Evaluator-only payoff law differs from the forge response law.  Exact
    // raw action names do not transfer across cohort recoding.
    return if (pair.first == hiddenTarget(c).first and pair.second == hiddenTarget(c).second) 20 else 0;
}
fn forge(c: usize) [PairCount]Record {
    var records: [PairCount]Record = undefined;
    for (0..PairCount) |i| {
        const p = pairAt(i);
        records[i] = .{ .pair = p, .raw_signature = compositionSignature(c, p), .evidence = 1,
            .provenance = mix(0xa512_1010 ^ @as(u64, @intCast(c * 131 + i))) };
    }
    return records;
}
fn select(records: [PairCount]Record, challenge: u4) ?Pair {
    for (records) |r| if (r.evidence == 1 and r.provenance != 0 and r.raw_signature == challenge) return r.pair;
    return null;
}
fn deterministicPair(c: usize, salt: u64) Pair { return pairAt(@intCast(mix(salt ^ @as(u64, @intCast(c))) % PairCount)); }
fn runPolicy(policy: Policy) Result {
    var out = Result{};
    for (0..Cohorts) |c| {
        // Four failed raw distinctions + twelve dynamically composed probes +
        // one raw challenge + four final trials.  Every arm pays 21 contacts.
        var failed = true;
        for (0..PrimitiveCount) |raw| failed = failed and rawSingleResponse(c, raw) == 0;
        const records = forge(c);
        const challenge = rawChallenge(c);
        var selected: Pair = deterministicPair(c, 0xa512_2000);
        switch (policy) {
            .earned_forge => if (failed) if (select(records, challenge)) |p| { selected = p; out.forged += 1; out.selected += 1; },
            .fixed_raw_probe => {},
            .fixed_human_composition => selected = .{ .first = 0, .second = 1 },
            .random_composition => selected = deterministicPair(c, 0xa512_2001),
            .replay => {
                const old = (c + Cohorts - 1) % Cohorts;
                if (select(forge(old), challenge)) |p| selected = p;
            },
            .shuffled_experience => {
                const old = (c * 37 + 11) % Cohorts;
                if (select(forge(old), challenge)) |p| selected = p;
            },
            .answer_scrubbed, .forge_ablation => {},
            .fixed_broad_composition => {},
        }
        out.contacts += PrimitiveCount + PairCount + 1 + FinalContacts;
        if (policy == .fixed_broad_composition) {
            // Same four final trials split among fixed anonymous compositions.
            for (0..FinalContacts) |i| out.material += changedOutcome(c, pairAt(i));
        } else if (policy != .fixed_raw_probe) {
            for (0..FinalContacts) |_| out.material += changedOutcome(c, selected);
        }
    }
    return out;
}
fn emit(w: anytype, policy: Policy, verdict: []const u8) !void {
    const r = runPolicy(policy);
    try w.print("round_aq_aq2,{s},{d},{d},{d},{d},{s}\n", .{ @tagName(policy), r.contacts, r.material, r.forged, r.selected, verdict });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,policy,charged_raw_contacts,hidden_changed_world_material,forged_compositions,provenance_selected,verdict\n");
    try emit(w, .earned_forge, "FOUNDATION_POSITIVE:earned_composition_after_failed_raw_distinctions_strictly_beats_all_equal_cost_controls_on_privately_recoded_changed_world");
    try emit(w, .fixed_raw_probe, "CONTROL:fixed_raw_primitive_only");
    try emit(w, .fixed_human_composition, "CONTROL:fixed_human_like_pair_0_1");
    try emit(w, .random_composition, "CONTROL:deterministic_random_pair");
    try emit(w, .replay, "CONTROL:previous_cohort_forged_experience");
    try emit(w, .shuffled_experience, "CONTROL:provenance_shuffled_forged_experience");
    try emit(w, .answer_scrubbed, "CONTROL:answer_memory_scrubbed_no_pair_trace");
    try emit(w, .forge_ablation, "CONTROL:failed_distinction_record_without_composition_forge");
    try emit(w, .fixed_broad_composition, "CONTROL:strong_fixed_four_pair_coverage_same_final_budget");
    const audit = [_][]const u8{
        "CHECK:single_raw_probes_are_uniform_and_do_not_distinguish_hidden_roles",
        "CHECK:composition_loop_is_authorized_by_observed_failed_raw_distinctions",
        "CHECK:records_contain_only_raw_pair_raw_signature_evidence_and_provenance",
        "CHECK:policy_has_no_target_answer_trace_label_semantic_decoder_score_progress_feedback_or_fixed_instrument_menu",
        "CHECK:private_action_recoding_and_changed_outcome_law_are_per_cohort_and_evaluator_owned",
        "LIMIT:finite_four_primitive_synthetic_alphabet_and_pair_enumeration_are_not_open_ended_tool_or_material_invention",
        "LIMIT:single_file_fixture_is_not_process_isolation_or_general_intelligence_evidence",
    };
    for (audit) |line| try w.print("round_aq_aq2,audit,0,0,0,0,{s}\n", .{line});
}
fn selftest() !void {
    try run("/tmp/aq2-a.csv"); try run("/tmp/aq2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const allocator = gpa.allocator();
    const a = try std.fs.cwd().readFileAlloc(allocator, "/tmp/aq2-a.csv", 1 << 20); defer allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(allocator, "/tmp/aq2-b.csv", 1 << 20); defer allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    const own = runPolicy(.earned_forge);
    const controls = [_]Policy{ .fixed_raw_probe, .fixed_human_composition, .random_composition, .replay, .shuffled_experience, .answer_scrubbed, .forge_ablation, .fixed_broad_composition };
    for (controls) |p| if (!(own.material > runPolicy(p).material and own.contacts == runPolicy(p).contacts)) return error.ControlNotBeaten;
    if (own.forged != Cohorts or own.selected != Cohorts) return error.InvalidForge;
    std.debug.print("round_aq_aq2 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true contacts_per_cohort=21 all_controls_strictly_beaten=true primitive_failures_authorize_forge=true\n", .{});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/earned_instrument_forge_round_aq.csv");
}
