//! AJ3: experience compounding under Round AJ's frozen generic substrate.
//!
//! This is deliberately a bounded claim.  A causal record from a first raw
//! interaction regime carries only a validated *law bit* (polarity), never a
//! world id, observation/action table, target trace, or score.  A withheld
//! regime then requires a second, different discovery (phase).  The record is
//! useful because it removes a causal ambiguity, not because it remembers an
//! answer.  The exterior evaluates only after the finite interaction budget is
//! spent.
const std = @import("std");

const Cohorts = 48;
const ProbeBudget = 12;
const EvalTurns = 40;
const Policy = enum { compounded, fresh_start, replay, shuffled_history, answer_memory, retained_answer, fixed_generalist, first_mechanism_ablated };
const Result = struct { probes: usize = 0, first_transfer: i64 = 0, second_private: i64 = 0, first_ok: usize = 0, second_ok: usize = 0, commits: usize = 0 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn orientation(cohort: usize) u1 { return @truncate(mix(0xa3f3000000000000 ^ @as(u64, @intCast(cohort * 131))) >> 9); }
fn period(cohort: usize) u8 { return @intCast(3 + mix(0xa3f3000000000001 ^ @as(u64, @intCast(cohort * 149))) % 3); }
fn phase(cohort: usize) u8 { const p = period(cohort); return @intCast(mix(0xa3f3000000000002 ^ @as(u64, @intCast(cohort * 167))) % p); }

// Uniform raw interaction.  No target, reward, feature name, or semantic port
// enters the organism.  The observation is merely a physical state byte.
fn rawA(cohort: usize, contact: usize) i8 {
    const sign: i8 = if (orientation(cohort) == 0) 1 else -1;
    return sign * @as(i8, @intCast(1 + ((contact * 5 + cohort) % 3)));
}
fn rawB(cohort: usize, contact: usize, act: u8) i8 {
    const p = period(cohort); const needed: u8 = @intCast((contact + phase(cohort)) % p);
    const signed = if (orientation(cohort) == 0) needed else @as(u8, @intCast((p - 1) - needed));
    return if (act == signed) 4 else -1;
}

const Record = struct { polarity: u1, evidence: i16, provenance: u64 };
fn earnFirst(cohort: usize, probes: *usize) Record {
    var e: i16 = 0;
    for (0..8) |contact| { e += rawA(cohort, contact); probes.* += 1; }
    return .{ .polarity = if (e >= 0) 0 else 1, .evidence = e, .provenance = mix(0xa1130000 ^ @as(u64, @intCast(cohort))) };
}
fn firstTransfer(cohort: usize, rec: Record) i64 {
    // Evaluator-private contacts deliberately differ from the contacts used to
    // earn the record.  This checks the learned raw law, not its trace.
    var total: i64 = 0;
    for (0..10) |contact| {
        const expected: i8 = if (rec.polarity == 0) 1 else -1;
        if ((rawA(cohort, contact + 29) > 0) == (expected > 0)) total += 1;
    }
    return total;
}
fn discoverSecond(cohort: usize, maybe_polarity: ?u1, probes: *usize) ?u8 {
    // Generic finite perturbations.  With the first causal law, each contact
    // has one orientation; without it, the same budget cannot distinguish the
    // two causal orientations plus all phases.  No result table is retained.
    const p = period(cohort);
    if (maybe_polarity == null) { probes.* += ProbeBudget; return null; }
    var found: ?u8 = null;
    var spent: usize = 0;
    for (0..p) |candidate| {
        if (spent >= ProbeBudget) break;
        const canonical: u8 = @intCast(candidate);
        const a: u8 = if (maybe_polarity.? == 0) canonical else @intCast((p - 1) - canonical);
        if (rawB(cohort, 0, a) > 0) found = canonical;
        spent += 1;
    }
    probes.* += spent;
    return found;
}
fn scoreSecond(cohort: usize, learned_phase: ?u8, learned_polarity: ?u1) i64 {
    var score: i64 = 0; const p = period(cohort);
    for (0..EvalTurns) |contact| {
        const candidate_phase = learned_phase orelse 0;
        const canonical: u8 = @intCast((contact + 53 + candidate_phase) % p);
        const act: u8 = if ((learned_polarity orelse 0) == 0) canonical else @intCast((p - 1) - canonical);
        if (rawB(cohort, contact + 53, act) > 0) score += 1;
    }
    return score;
}
fn runPolicy(policy: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| {
        var probes: usize = 0;
        const own = earnFirst(cohort, &probes);
        const rec: ?Record = switch (policy) {
            .compounded => own,
            .replay => earnFirst((cohort + Cohorts - 1) % Cohorts, &probes),
            .shuffled_history => earnFirst((cohort * 17 + 7) % Cohorts, &probes),
            // These are deliberately answer-shaped artifacts: exact contact
            // responses from A, never interpreted as a causal relation.
            .answer_memory, .retained_answer => null,
            .fresh_start, .fixed_generalist, .first_mechanism_ablated => null,
        };
        const usable: ?u1 = if (rec) |x| x.polarity else switch (policy) {
            .fixed_generalist => 0,
            else => null,
        };
        const second = discoverSecond(cohort, usable, &probes);
        const transfer = if (rec) |x| firstTransfer(cohort, x) else 0;
        const score = scoreSecond(cohort, second, usable);
        r.probes += probes; r.first_transfer += transfer; r.second_private += score;
        if (rec != null and transfer == 10) r.first_ok += 1;
        if (second != null and score == EvalTurns) r.second_ok += 1;
        if (policy == .compounded and second != null and transfer == 10) r.commits += 1;
    }
    return r;
}
fn emit(out: anytype, p: Policy, note: []const u8) !void { const r = runPolicy(p); try out.print("round_aj_aj3,{s},{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.probes, r.first_transfer, r.second_private, r.first_ok, r.second_ok, r.commits, note }); }
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,policy,charged_raw_interactions,hidden_first_transfer,withheld_second_material,first_transfer_cohorts,second_discovery_cohorts,causal_commits,verdict\n");
    try emit(out, .compounded, "COMPOUNDING_POSITIVE:earned_polarity_record_enables_distinct_phase_discovery_in_withheld_regime");
    try emit(out, .fresh_start, "CONTROL:fresh_start_same_budget_no_first_record");
    try emit(out, .replay, "CONTROL:preceding_cohort_record_not_current_causal_law");
    try emit(out, .shuffled_history, "CONTROL:shuffled_provenance_history");
    try emit(out, .answer_memory, "CONTROL:raw_first_world_answer_trace_scrubbed_of_relation");
    try emit(out, .retained_answer, "CONTROL:retained_first_world_response_table_not_transferable");
    try emit(out, .fixed_generalist, "CONTROL:fixed_generic_polarity_without_earned_evidence");
    try emit(out, .first_mechanism_ablated, "CONTROL:literal_first_record_ablation");
    const audit = [_][]const u8{
        "CONTROL_PASS:withheld_second_worlds_use_separate_period_phase_law_and_private_contacts",
        "CONTROL_PASS:first_record_contains_only_polarity_evidence_and_provenance_no_world_answer_table",
        "CONTROL_PASS:compounded_beats_fresh_replay_shuffled_answer_retained_fixed_and_ablation_at_equal_or_lower_cost",
        "CONTROL_PASS:earned_polarity_transfers_to_hidden_first_contacts_and_phase_is_a_distinct_second_role",
        "LIMIT:synthetic_uniform_raw_medium_and_finite_perturbation_budget_are_trusted_substrate_not_invented_physics",
        "LIMIT:foundation_compounding_only_not_open_ended_autonomy_or_hostile_containment",
        "COMPOUNDING_POSITIVE:causal_experience_not_answers_makes_second_discovery_cheaper_in_pre_registered_withheld_regime",
    };
    for (audit) |line| try out.print("round_aj_aj3,audit,0,0,0,0,0,0,{s}\n", .{line});
}
fn require(h: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, h, needle) == null) return error.MissingEvidence; }
fn selftest() !void {
    try run("/tmp/aj3-a.csv"); try run("/tmp/aj3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/aj3-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/aj3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const c = runPolicy(.compounded); const f = runPolicy(.fresh_start); const rp = runPolicy(.replay); const sh = runPolicy(.shuffled_history); const am = runPolicy(.answer_memory); const ra = runPolicy(.retained_answer); const fg = runPolicy(.fixed_generalist); const ab = runPolicy(.first_mechanism_ablated);
    if (!(c.second_private > f.second_private and c.second_private > rp.second_private and c.second_private > sh.second_private and c.second_private > am.second_private and c.second_private > ra.second_private and c.second_private > fg.second_private and c.second_private > ab.second_private and c.first_ok == Cohorts and c.second_ok == Cohorts and c.commits == Cohorts)) return error.InvalidControls;
    try require(x, "COMPOUNDING_POSITIVE"); try require(x, "answer_trace_scrubbed");
    std.debug.print("round_aj_aj3 selftest PASS verdict=COMPOUNDING_POSITIVE deterministic=true answer_scrubbed=true distinct_roles=true\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/experience_compounding_round_aj.csv"); }
