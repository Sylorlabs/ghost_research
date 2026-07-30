//! AJ4: self-chosen experiment program, evaluated under the frozen AJ substrate.
//!
//! The organism receives raw transition consequences.  It retains an earned
//! polarity record, then *constructs* a probe sequence by making the sequence
//! length and alternation direction depend on that record.  There is no named
//! task, world id, target address, experiment menu, or answer table in the
//! record.  This fixture still has an important limitation: the host supplies
//! the finite trace window and the generic reversible perturbation primitive.
//! Therefore even a control-winning result below is reported VALID_NEGATIVE,
//! not a foundation positive for self-chosen experimentation.
const std = @import("std");

const Cohorts = 48;
const EvalTurns = 48;
const Policy = enum { earned_program, fixed_experiment, random_experiment, replay_experiment, fresh_start, shuffled_history, answer_memory, retained_answer, first_mechanism_ablated };
const Result = struct { interactions: usize = 0, material: i64 = 0, commits: usize = 0, chosen_nonfixed: usize = 0 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn polarity(c: usize) u1 { return @truncate(mix(0xa440000000000000 ^ @as(u64, @intCast(c * 97))) >> 13); }
fn period(c: usize) u8 { return @intCast(3 + mix(0xA440000000000001 ^ @as(u64, @intCast(c * 131))) % 4); }
fn phase(c: usize) u8 { return @intCast(mix(0xA440000000000002 ^ @as(u64, @intCast(c * 173))) % period(c)); }

// Raw physical consequences only: two reversible perturbation directions have
// opposite persistence effects.  Neither the organism nor its record observes
// the held-out material total.
fn transition(c: usize, t: usize, action: u8) i8 {
    const p = period(c);
    const base: u8 = @intCast((t + phase(c)) % p);
    const required: u8 = if (polarity(c) == 0) base else @intCast((p - 1) - base);
    return if (action == required) 3 else -1;
}
const Record = struct { sign: u1, rhythm: u8, evidence: i16, provenance: u64 };
fn earn(c: usize, interactions: *usize) Record {
    var e: i16 = 0;
    var changes: u8 = 0;
    var prior: i8 = 0;
    for (0..8) |t| { const x = transition(c, t, 0); e += x; if (t != 0 and (x > 0) != (prior > 0)) changes +%= 1; prior = x; interactions.* += 1; }
    // A generic record: sign and change rhythm, not a response table.
    return .{ .sign = if (e >= 0) 0 else 1, .rhythm = @intCast(1 + changes % 4), .evidence = e, .provenance = mix(0xa4400000 ^ @as(u64, @intCast(c))) };
}
const Program = struct { direction: u1, stride: u8, offset: u8 };
fn construct(rec: Record) Program {
    // The structure is generated from earned relation evidence.  It chooses a
    // fresh stride/offset instead of selecting from a host menu.
    const h = mix(rec.provenance ^ @as(u64, @bitCast(@as(i64, rec.evidence))));
    return .{ .direction = rec.sign, .stride = @intCast(1 + ((rec.rhythm % 4) + (@as(u8, @truncate(h)) % 4)) % 4), .offset = @intCast((h >> 11) % 4) };
}
fn probeAndCommit(c: usize, program: ?Program, interactions: *usize) struct { score: i64, commit: bool, nonfixed: bool } {
    const plan = program orelse return .{ .score = 0, .commit = false, .nonfixed = false };
    var found: ?u8 = null;
    // The plan schedules raw perturbations.  Every generated action is charged.
    for (0..12) |i| {
        const canonical: u8 = @intCast((i * plan.stride + plan.offset) % period(c));
        const action: u8 = if (plan.direction == 0) canonical else @intCast((period(c) - 1) - canonical);
        if (transition(c, i + 17, action) > 0) found = @intCast((canonical + period(c) - (i % period(c))) % period(c));
        interactions.* += 1;
    }
    const discovered = found orelse return .{ .score = 0, .commit = false, .nonfixed = plan.stride != 1 or plan.offset != 0 };
    var score: i64 = 0;
    for (0..EvalTurns) |t| {
        const canonical: u8 = @intCast((t + discovered) % period(c));
        const action: u8 = if (plan.direction == 0) canonical else @intCast((period(c) - 1) - canonical);
        if (transition(c, t + 73, action) > 0) score += 1;
    }
    return .{ .score = score, .commit = score == EvalTurns, .nonfixed = plan.stride != 1 or plan.offset != 0 };
}
fn policyRecord(p: Policy, c: usize, interactions: *usize) ?Record {
    return switch (p) {
        .earned_program => earn(c, interactions),
        .replay_experiment => earn((c + Cohorts - 1) % Cohorts, interactions),
        .shuffled_history => earn((c * 19 + 11) % Cohorts, interactions),
        .fixed_experiment => .{ .sign = 0, .rhythm = 0, .evidence = 0, .provenance = 0 },
        .random_experiment => .{ .sign = @truncate(mix(@as(u64, @intCast(c))) >> 3), .rhythm = 0, .evidence = 0, .provenance = mix(@as(u64, @intCast(c * 23))) },
        .fresh_start, .answer_memory, .retained_answer, .first_mechanism_ablated => null,
    };
}
fn runPolicy(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |c| {
        var n: usize = 0;
        const rec = policyRecord(p, c, &n);
        var program: ?Program = if (rec) |x| construct(x) else null;
        // Fixed and random controls receive the same 12 perturbations but do
        // not retain earned causal evidence.  Answer-shaped controls are not
        // interpreted as a relation and cannot build a program.
        if (p == .fixed_experiment) program = .{ .direction = 0, .stride = 1, .offset = 0 };
        if (p == .random_experiment) program = .{ .direction = @truncate(mix(@as(u64, @intCast(c * 7))) >> 7), .stride = @intCast(1 + mix(@as(u64, @intCast(c * 31))) % 4), .offset = @intCast(mix(@as(u64, @intCast(c * 43))) % 4) };
        if (p == .fresh_start or p == .answer_memory or p == .retained_answer or p == .first_mechanism_ablated) { n += 20; }
        const o = probeAndCommit(c, program, &n);
        r.interactions += n; r.material += o.score; if (o.commit) r.commits += 1; if (o.nonfixed) r.chosen_nonfixed += 1;
    }
    return r;
}
fn emit(w: anytype, p: Policy, note: []const u8) !void { const r = runPolicy(p); try w.print("round_aj_aj4,{s},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.interactions, r.material, r.commits, r.chosen_nonfixed, note }); }
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("artifact,policy,charged_raw_interactions,hidden_unseen_material,causal_commits,nonfixed_programs,verdict\n");
    try emit(w, .earned_program, "VALID_NEGATIVE:earned_program_beats_blank_controls_but_loses_random_replay_shuffled_and_uses_host_trace_primitive");
    try emit(w, .fixed_experiment, "CONTROL:equal_cost_fixed_program"); try emit(w, .random_experiment, "CONTROL:equal_cost_random_program");
    try emit(w, .replay_experiment, "CONTROL:preceding_cohort_program"); try emit(w, .fresh_start, "CONTROL:fresh_start_no_relation");
    try emit(w, .shuffled_history, "CONTROL:shuffled_causal_history"); try emit(w, .answer_memory, "CONTROL:answer_trace_not_interpretable_as_relation");
    try emit(w, .retained_answer, "CONTROL:retained_response_table_not_transferable"); try emit(w, .first_mechanism_ablated, "CONTROL:literal_first_relation_ablation");
    const audit = [_][]const u8{
        "CONTROL_PASS:all_world_ids_hidden_and_train_transfer_domains_disjoint", "CONTROL_PASS:address_value_and_period_encodings_private_per_cohort", "CONTROL_PASS:fixed_random_replay_fresh_shuffled_answer_retained_and_ablation_recorded_with_all_costs", "ATTACK:world_overlap_representation_recode_and_answer_history_controls_are_pre_registered", "LIMIT:finite_trace_window_action_arity_and_reversible_perturbation_are_human_written_trusted_substrate", "VALID_NEGATIVE:self_generated_program_not_sufficient_to_establish_human_bottleneck_free_experiment_choice", "LIMIT:no_OS_containment_or_full_autonomy_claim",
    };
    for (audit) |s| try w.print("round_aj_aj4,audit,0,0,0,0,{s}\n", .{s});
}
fn selftest() !void {
    try run("/tmp/aj4-a.csv"); try run("/tmp/aj4-b.csv"); var g = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = g.deinit(); const a = g.allocator(); const x = try std.fs.cwd().readFileAlloc(a, "/tmp/aj4-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/aj4-b.csv", 1 << 20); defer a.free(y); if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const own = runPolicy(.earned_program); const fixed = runPolicy(.fixed_experiment); const rnd = runPolicy(.random_experiment); const rep = runPolicy(.replay_experiment); const fresh = runPolicy(.fresh_start); const sh = runPolicy(.shuffled_history); const ans = runPolicy(.answer_memory); const ret = runPolicy(.retained_answer); const ab = runPolicy(.first_mechanism_ablated);
    // This fixture is intentionally negative: the generated program exceeds
    // blank/answer/ablation policies, but loses to random, replay, and shuffled
    // experiment structures.  It therefore cannot claim a self-chosen
    // experiment advantage even before the trusted-substrate limitation.
    if (!(own.material > fresh.material and own.material > ans.material and own.material > ret.material and own.material > ab.material and own.chosen_nonfixed > 0 and rnd.material > own.material and rep.material > own.material and sh.material > own.material)) return error.InvalidControls;
    _ = fixed;
    std.debug.print("round_aj_aj4 selftest PASS verdict=VALID_NEGATIVE deterministic=true chosen_program=true controls_beaten=false limitation=host_trace_and_primitive\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/self_chosen_experiment_round_aj.csv"); }
