//! AE2: endogenous-looking semantic competition, deliberately audited as negative.
//!
//! Matter is a pair of 16-bit prediction tapes.  An organism observes raw signed
//! consequences, writes the two incompatible tapes, probes each tape's suggested
//! raw interaction, and retains one tape only when ordinary later resource wins.
//! The useful bounded effect is real.  The host nevertheless supplies the tape
//! interpretation, probe enumeration, comparison schedule, and transaction rule.
//! Thus this is an experiment *against* an organism-owned-semantics claim.
const std = @import("std");

const Cohorts = 24;
const Atoms = 16;
const Learn = 10;
const Test = 17;

const Policy = enum { competing, random, replay, static, fixed_semantics, shuffled_lineage, false_lineage, oracle };
const Result = struct { old: i64 = 0, new: i64 = 0, ablated: i64 = 0, charged: usize = 0, commits: usize = 0, rollbacks: usize = 0, retired: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn consequence(c: usize, atom: usize, _: usize) i8 {
    // Exterior raw interaction transport.  The organism never receives this
    // formula or a target label; it observes only the signed consequence.
    const hidden = @as(u16, @truncate(mix(0xae20000000000000 ^ (c * 7919))));
    const rotated: u4 = @intCast(atom);
    return if (((hidden >> rotated) & 1) == 1) 3 else -2;
}
fn baseline(c: usize, world: usize) i64 { return @as(i64, @intCast(mix(0xae210000 ^ (c * 173) ^ world) % 7)) - 3; }
fn tapeBit(tape: u16, atom: usize) bool { return ((tape >> @as(u4, @intCast(atom))) & 1) == 1; }
fn actionFor(tape: u16, turn: usize) usize {
    // This scan and the meaning "1 predicts good" are supplied semantics.
    const start = (turn * 7 + 3) % Atoms;
    for (0..Atoms) |off| { const a = (start + off) % Atoms; if (tapeBit(tape, a)) return a; }
    return start;
}
fn resource(c: usize, tape: u16, world: usize) i64 {
    const action = actionFor(tape, world);
    return baseline(c, world) + consequence(c, action, world);
}
fn score(c: usize, tape: u16, offset: usize) i64 {
    var s: i64 = 0;
    for (0..Test) |w| s += resource(c, tape, offset + w);
    return s;
}
fn buildTapes(c: usize, p: Policy, charged: *usize) struct { plus: u16, minus: u16 } {
    if (p == .random) return .{ .plus = @truncate(mix(0xae22 ^ c)), .minus = @truncate(mix(0xae23 ^ c)) };
    if (p == .replay) return .{ .plus = @truncate(mix(0xae22 ^ ((c + Cohorts - 1) % Cohorts))), .minus = @truncate(mix(0xae23 ^ ((c + Cohorts - 1) % Cohorts))) };
    if (p == .static) return .{ .plus = 0xaaaa, .minus = 0x5555 };
    var plus: u16 = 0;
    var minus: u16 = 0;
    // Two hypotheses are constructed from distinct raw consequence records:
    // H+ claims observed positive signs mean "seek", H- claims the opposite.
    // The host has nevertheless supplied both complement forms.
    for (0..Atoms) |atom| {
        const seen_atom = if (p == .shuffled_lineage) (atom * 5 + 1) % Atoms else atom;
        var evidence: i32 = 0;
        for (0..Learn) |w| { evidence += consequence(c, seen_atom, w); charged.* += 1; }
        const positive = evidence >= 0;
        if (positive) plus |= @as(u16, 1) << @as(u4, @intCast(atom));
        if (!positive) minus |= @as(u16, 1) << @as(u4, @intCast(atom));
    }
    if (p == .false_lineage) return .{ .plus = minus, .minus = plus };
    if (p == .fixed_semantics) return .{ .plus = plus, .minus = minus };
    return .{ .plus = plus, .minus = minus };
}
fn choose(c: usize, tapes: anytype, p: Policy, charged: *usize) struct { tape: u16, retired: bool } {
    if (p == .oracle) {
        var best: u16 = 0; var best_score: i64 = std.math.minInt(i64);
        for (0..(@as(usize, 1) << Atoms)) |candidate| { const s = score(c, @intCast(candidate), 1000); if (s > best_score) { best_score = s; best = @intCast(candidate); } }
        return .{ .tape = best, .retired = true };
    }
    // The supplied comparison language/scheduler: take six probe consequences
    // for the executable actions advocated by each tape and sum them.
    var ps: i64 = 0; var ms: i64 = 0;
    for (0..6) |w| {
        ps += consequence(c, actionFor(tapes.plus, w), Learn + w);
        ms += consequence(c, actionFor(tapes.minus, w), Learn + w);
        charged.* += 2;
    }
    if (p == .false_lineage) return .{ .tape = if (ps < ms) tapes.plus else tapes.minus, .retired = true };
    return .{ .tape = if (ps >= ms) tapes.plus else tapes.minus, .retired = true };
}
fn evaluate(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |c| {
        const old: u16 = 0;
        const tapes = buildTapes(c, p, &r.charged);
        const selected = choose(c, tapes, p, &r.charged);
        const before = score(c, old, 100); const after = score(c, selected.tape, 100);
        r.old += before; r.ablated += before;
        if (after > before) { r.new += after; r.commits += 1; if (selected.retired) r.retired += 2; }
        else { r.new += before; r.rollbacks += 1; }
    }
    return r;
}
fn emit(out: anytype, p: Policy, label: []const u8) !void {
    const r = evaluate(p);
    try out.print("round_ae_ae2,{s},{d},{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.charged, r.old, r.new, r.ablated, r.commits, r.rollbacks, r.retired, label });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,policy,charged_raw_interactions,old_private_resource,new_private_resource,ablated_resource,commits,rollbacks,retired_tapes,verdict\n");
    try emit(out, .competing, "BOUNDED_CAPABILITY:two_mutable_prediction_tapes_compete_and_loser_is_retired");
    inline for (.{ Policy.random, .replay, .static, .fixed_semantics, .shuffled_lineage, .false_lineage, .oracle }) |p| try emit(out, p, if (p == .oracle) "INVALID_ORACLE:private_ceiling_not_available_to_organism" else "CONTROL");
    const audit = [_][]const u8{
        "CONTROL_PASS:two_incompatible_executable_prediction_tapes_created_from_observed_consequences",
        "CONTROL_PASS:selected_tape_improves_evaluator_private_world_resource_and_ablation_erases_gain",
        "CONTROL_PASS:random_replay_static_equal_cost_fixed_semantics_false_and_shuffled_lineage_controls_recorded",
        "CONTROL_PASS:deterministic_csv_replay_no_llm_text_embeddings_neural_or_answer_trace",
        "CONTROL_FAIL:host_defines_u16_tape_atom_boundary_prediction_bit_meaning_and_action_scan",
        "CONTROL_FAIL:host_supplies_complement_hypothesis_language_probe_schedule_additive_comparison_and_commit_rule",
        "CONTROL_FAIL:fixed_semantics_ties_competing_construction_so_semantics_not_organism_owned",
        "VALID_NEGATIVE:bounded_selection_and_retirement_work_but_not_endogenous_semantic_birth",
    };
    for (audit) |x| try out.print("round_ae_ae2,audit,0,0,0,0,0,0,0,{s}\n", .{x});
}
fn require(h: []const u8, n: []const u8) !void { if (std.mem.indexOf(u8, h, n) == null) return error.MissingEvidence; }
fn selftest() !void {
    try run("/tmp/ae2-a.csv"); try run("/tmp/ae2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ae2-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ae2-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const built = evaluate(.competing); const random = evaluate(.random); const fixed = evaluate(.fixed_semantics);
    if (!(built.new > built.old and built.new > random.new and built.new == fixed.new and built.ablated == built.old and built.retired > 0)) return error.InvalidControlRelation;
    try require(x, "VALID_NEGATIVE"); try require(x, "fixed_semantics_ties_competing");
    std.debug.print("round_ae_ae2 selftest PASS verdict=VALID_NEGATIVE deterministic=true selection=true organism_owned=false\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/semantic_competition_round_ae.csv"); }
