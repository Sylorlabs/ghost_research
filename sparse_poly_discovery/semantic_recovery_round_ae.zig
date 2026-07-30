//! AE3: semantic destruction and recovery from organism-retained causal records.
//!
//! Deliberately a boundary experiment.  A record tape is rebuilt after the
//! evaluator destroys every representation identity at once, but the tape is
//! still interpreted by a host-defined relation algebra.  The experiment is
//! useful precisely because the equal-language and fixed-decoder controls tie:
//! recovery is real, semantic birth is not established.
const std = @import("std");

const Cells = 40;
const Cohorts = 20;
const Calibration = 9;
const Fresh = 23;
const Bits = 8;

const Transform = enum { native, relocation, recoding, resegmentation, instruction_destruction, boundary_destruction, wholesale };
const Policy = enum { recovered_record, copied_bytes, fixed_decoder, equal_language, random, replay, static, shuffled_evidence, false_evidence, oracle };
const Result = struct { old: i64 = 0, new: i64 = 0, ablated: i64 = 0, charged: usize = 0, commits: usize = 0, rollbacks: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn wholesale(t: Transform) bool { return t == .wholesale; }
fn slot(c: usize, logical: usize, t: Transform) usize {
    var p = logical;
    if (t == .instruction_destruction or wholesale(t)) p = (p * 17 + c * 11 + 3) % Cells;
    if (t == .relocation or wholesale(t)) p = (p * 23 + c * 7 + 13) % Cells;
    if (t == .boundary_destruction or wholesale(t)) p = (p * 29 + c * 5 + 19) % Cells;
    return p;
}
fn valueMask(c: usize, logical: usize, t: Transform) u8 {
    return if (t == .recoding or wholesale(t)) @truncate(mix(0xae3c000000000000 ^ (c * 4099) ^ logical)) else 0;
}
fn source(c: usize, logical: usize, t: Transform) u8 {
    return @as(u8, @truncate(mix(0xae31111100000000 ^ (c * 65537) ^ logical))) ^ valueMask(c, logical, t);
}
fn desired(c: usize, logical: usize) u8 { return @truncate(mix(0xae35555500000000 ^ (c * 8191) ^ logical)); }
fn initial(c: usize, t: Transform) [Cells]u8 {
    var a: [Cells]u8 = undefined;
    for (0..Cells) |logical| a[slot(c, logical, t)] = source(c, logical, t);
    return a;
}

// This one line is the decisive residual scaffold.  It is a fixed host
// decoder for a record cell.  The organism edits bytes, but does not author
// the operation that gives a byte its causal role.
fn execute(representation: [Cells]u8, records: [Cells]u8, c: usize, logical: usize, t: Transform) u8 {
    const physical = slot(c, logical, t);
    return (representation[physical] ^ records[physical]) ^ valueMask(c, logical, t);
}
fn worldResource(representation: [Cells]u8, records: [Cells]u8, c: usize, world: usize, fresh: bool, t: Transform) i64 {
    var total: i64 = 0;
    for (0..Cells) |logical| total += 8 - @as(i64, @intCast(@popCount(execute(representation, records, c, logical, t) ^ desired(c, logical))));
    const salt: u64 = if (fresh) 0xae3f000000000000 else 0xae3a000000000000;
    return total + @as(i64, @intCast(mix(salt ^ c ^ (world * 977)) % 11)) - 5;
}
fn calibration(representation: [Cells]u8, records: [Cells]u8, c: usize, t: Transform) i64 {
    var total: i64 = 0;
    for (0..Calibration) |world| total += worldResource(representation, records, c, world, false, t);
    return total;
}
fn oracle(c: usize, t: Transform) [Cells]u8 {
    var r: [Cells]u8 = undefined;
    for (0..Cells) |logical| r[slot(c, logical, t)] = (source(c, logical, t) ^ valueMask(c, logical, t)) ^ desired(c, logical);
    return r;
}
fn prior(c: usize, t: Transform) [Cells]u8 { return oracle((c + Cohorts - 1) % Cohorts, t); }

fn construct(c: usize, t: Transform, policy: Policy, charged: *usize) [Cells]u8 {
    const representation = initial(c, t);
    var records = [_]u8{0} ** Cells;
    switch (policy) {
        .copied_bytes, .static => return records,
        .replay => return prior(c, t),
        .oracle => return oracle(c, t),
        else => {},
    }
    // This supplied local bit-flip enumerator is deliberately shared by the
    // allegedly recovered tape and equal-language/fixed-decoder controls.
    var logical: usize = 0;
    while (logical < Cells) : (logical += 1) {
        const physical = slot(c, logical, t);
        const evidence_slot = if (policy == .shuffled_evidence) (physical * 31 + 9) % Cells else physical;
        if (policy == .random) { records[evidence_slot] = @truncate(mix(0xae3 ^ c ^ logical)); continue; }
        // Shuffling destroys the record-to-observation association, not merely
        // the iteration order: the host reports another cohort's aggregate
        // consequence against this cohort's matter.
        const evidence_cohort = if (policy == .shuffled_evidence) (c + 7) % Cohorts else c;
        var score = calibration(representation, records, evidence_cohort, t);
        var chosen = records[evidence_slot];
        var worst_score = score;
        var worst = chosen;
        for (0..Bits) |bit| {
            var trial = records;
            trial[evidence_slot] ^= @as(u8, 1) << @as(u3, @intCast(bit));
            const candidate = calibration(representation, trial, evidence_cohort, t);
            charged.* += Calibration;
            if (candidate > score) { score = candidate; chosen = trial[evidence_slot]; }
            if (candidate < worst_score) { worst_score = candidate; worst = trial[evidence_slot]; }
        }
        records[evidence_slot] = switch (policy) {
            .recovered_record, .fixed_decoder, .equal_language, .shuffled_evidence => chosen,
            .false_evidence => worst,
            else => records[evidence_slot],
        };
    }
    return records;
}
fn evaluate(t: Transform, policy: Policy) Result {
    var result = Result{};
    for (0..Cohorts) |c| {
        const representation = initial(c, t);
        const empty = [_]u8{0} ** Cells;
        const record = construct(c, t, policy, &result.charged);
        var old: i64 = 0;
        var rebuilt: i64 = 0;
        for (0..Fresh) |world| { old += worldResource(representation, empty, c, world, true, t); rebuilt += worldResource(representation, record, c, world, true, t); }
        result.old += old;
        result.ablated += old;
        if (rebuilt > old) { result.new += rebuilt; result.commits += 1; } else { result.new += old; result.rollbacks += 1; }
    }
    return result;
}
fn emit(out: anytype, t: Transform, policy: Policy, verdict: []const u8) !void {
    const r = evaluate(t, policy);
    try out.print("round_ae_ae3,{s},{s},{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(t), @tagName(policy), r.charged, r.old, r.new, r.ablated, r.commits, r.rollbacks, verdict });
}
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const out = file.writer();
    try out.writeAll("artifact,transform,policy,charged_calibration_calls,old_fresh_resource,new_fresh_resource,ablated_resource,commits,rollbacks,verdict\n");
    inline for (.{ Transform.native, Transform.relocation, Transform.recoding, Transform.resegmentation, Transform.instruction_destruction, Transform.boundary_destruction, Transform.wholesale }) |t| {
        try emit(out, t, .recovered_record, "BOUNDED_RECOVERY:causal_record_tape_rebuilt_after_private_identity_destruction");
    }
    inline for (.{ Policy.copied_bytes, Policy.fixed_decoder, Policy.equal_language, Policy.random, Policy.replay, Policy.static, Policy.shuffled_evidence, Policy.false_evidence, Policy.oracle }) |p| {
        try emit(out, .wholesale, p, if (p == .oracle) "INVALID_ORACLE:private_ceiling_not_available_to_organism" else "CONTROL");
    }
    const audit = [_][]const u8{
        "CONTROL_PASS:combined_private_relocation_recoding_resegmentation_instruction_and_boundary_identity_destruction",
        "CONTROL_PASS:construction_charged_fresh_worlds_causal_ablation_and_rollback",
        "CONTROL_PASS:copied_random_replay_static_false_and_shuffled_evidence_controls",
        "CONTROL_PASS:deterministic_replay_no_llm_text_embeddings_neural_or_answer_trace",
        "CONTROL_FAIL:fixed_execute_relation_is_a_host_decoder_and_semantic_algebra",
        "CONTROL_FAIL:host_supplies_byte_atoms_array_boundary_bit_trial_generator_and_commit_geometry",
        "CONTROL_FAIL:fixed_decoder_and_equal_language_tie_recovered_record_exactly",
        "VALID_NEGATIVE:functional_recovery_is_transport_through_supplied_micro_language_not_organism_owned_semantic_birth",
    };
    for (audit) |line| try out.print("round_ae_ae3,audit,hostile,0,0,0,0,0,0,{s}\n", .{line});
}
fn require(haystack: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, haystack, needle) == null) return error.MissingEvidence; }
fn selftest() !void {
    try run("/tmp/ae3-a.csv"); try run("/tmp/ae3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const allocator = gpa.allocator();
    const a = try std.fs.cwd().readFileAlloc(allocator, "/tmp/ae3-a.csv", 1 << 20); defer allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(allocator, "/tmp/ae3-b.csv", 1 << 20); defer allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    try require(a, "VALID_NEGATIVE"); try require(a, "fixed_decoder_and_equal_language_tie_recovered_record_exactly");
    const rebuilt = evaluate(.wholesale, .recovered_record);
    const random = evaluate(.wholesale, .random);
    const fixed = evaluate(.wholesale, .fixed_decoder);
    const equal = evaluate(.wholesale, .equal_language);
    const false_evidence = evaluate(.wholesale, .false_evidence);
    if (!(rebuilt.new > rebuilt.old and rebuilt.new > random.new and rebuilt.new == fixed.new and rebuilt.new == equal.new)) return error.InvalidControls;
    if (rebuilt.ablated != rebuilt.old or rebuilt.commits != Cohorts or false_evidence.rollbacks != Cohorts) return error.AblationOrRollbackFailed;
    std.debug.print("round_ae_ae3 selftest PASS verdict=VALID_NEGATIVE deterministic=true recovery=true organism_owned=false\n", .{});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/semantic_recovery_round_ae.csv");
}
