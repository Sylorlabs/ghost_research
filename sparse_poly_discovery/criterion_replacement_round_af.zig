//! AF3: criterion replacement and transfer, deliberately audited for ownership.
//!
//! A cohort receives raw byte consequences of interventions in an opaque field.
//! It writes an old and a successor relation, tests both on later consequences,
//! retires the loser, and uses the successor in an evaluator-private regime.
//! The experiment is intentionally a VALID NEGATIVE: byte atoms, relation
//! construction, comparison, and commit geometry are still supplied by source.
const std = @import("std");

const Cohorts = 32;
const Atoms = 16;
const Learn = 9;
const Probe = 7;
const Fresh = 19;

const Policy = enum { organism_replacement, fixed_equal, random, replay, static, shuffled_history, false_evidence, answer_memory, bootstrap_retained, reencoded };
const Result = struct {
    old: i64 = 0, new: i64 = 0, ablated: i64 = 0,
    charged: usize = 0, commits: usize = 0, rollbacks: usize = 0,
    retired: usize = 0,
};
const Pair = struct { old: u16, successor: u16 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn bit(c: usize, atom: usize, regime: usize) bool {
    const seed: u64 = if (regime == 0) 0xaf30000000000000 else 0xaf31000000000000;
    return ((mix(seed ^ @as(u64, @intCast(c * 4099 + atom * 97))) >> @as(u6, @intCast((atom + regime) % 32))) & 1) != 0;
}
fn consequence(c: usize, atom: usize, regime: usize, turn: usize) i8 {
    // Exterior deterministic transport only.  The cohort sees this signed byte,
    // never this formula, regime identity, target, or evaluator-private answer.
    const good = bit(c, atom, regime);
    const jitter: i8 = @intCast(mix(0xaf320000 ^ @as(u64, @intCast(c * 389 + atom * 31 + turn))) % 3);
    return if (good) 4 - jitter else -3 + jitter;
}
fn base(c: usize, turn: usize) i64 { return @as(i64, @intCast(mix(0xaf330000 ^ @as(u64, @intCast(c * 173 + turn))) % 5)) - 2; }
fn has(tape: u16, atom: usize) bool { return ((tape >> @as(u4, @intCast(atom))) & 1) != 0; }
fn action(tape: u16, turn: usize) usize {
    // SUPPLIED decoder: a one-bit relation selects the first matching byte atom.
    const start = (turn * 11 + 5) % Atoms;
    for (0..Atoms) |off| { const a = (start + off) % Atoms; if (has(tape, a)) return a; }
    return start;
}
fn score(c: usize, tape: u16, regime: usize, start: usize) i64 {
    var s: i64 = 0;
    for (0..Fresh) |turn| {
        const a = action(tape, start + turn);
        s += base(c, start + turn) + consequence(c, a, regime, start + turn);
    }
    return s;
}
fn relation(c: usize, regime: usize, history_shift: usize, false_lineage: bool, charged: *usize) u16 {
    var t: u16 = 0;
    // SUPPLIED relation-builder: accumulation, sign cutoff, byte segmentation,
    // and tape write are not organism-invented semantics.
    for (0..Atoms) |atom| {
        const observed = (atom + history_shift) % Atoms;
        var e: i32 = 0;
        for (0..Learn) |turn| { e += consequence(c, observed, regime, turn); charged.* += 1; }
        const keep = if (false_lineage) e < 0 else e >= 0;
        if (keep) t |= @as(u16, 1) << @as(u4, @intCast(atom));
    }
    return t;
}
fn build(c: usize, p: Policy, charged: *usize) Pair {
    switch (p) {
        .random => return .{ .old = @truncate(mix(0xaf34 ^ c)), .successor = @truncate(mix(0xaf35 ^ c)) },
        .replay => return .{ .old = @truncate(mix(0xaf34 ^ ((c + Cohorts - 1) % Cohorts))), .successor = @truncate(mix(0xaf35 ^ ((c + Cohorts - 1) % Cohorts))) },
        .static => return .{ .old = 0x5555, .successor = 0xaaaa },
        .answer_memory => return .{ .old = relation(c, 0, 0, false, charged), .successor = relation(c, 1, 0, false, charged) },
        .shuffled_history => return .{ .old = relation(c, 0, 5, false, charged), .successor = relation(c, 1, 9, false, charged) },
        .false_evidence => return .{ .old = relation(c, 0, 0, true, charged), .successor = relation(c, 1, 0, true, charged) },
        else => return .{ .old = relation(c, 0, 0, false, charged), .successor = relation(c, 1, 0, false, charged) },
    }
}
fn reencode(tape: u16) u16 {
    // Evaluator-private identity destruction: physical addresses are permuted,
    // bit values are inverted, and old 4-bit groups are dispersed. This is not
    // a capability claim: the inverse codec below is still host machinery.
    var out: u16 = 0;
    for (0..Atoms) |logical| {
        const physical = (logical * 5 + 3) % Atoms;
        const value = !has(tape, logical);
        if (value) out |= @as(u16, 1) << @as(u4, @intCast(physical));
    }
    return out;
}
fn decodeReencoded(physical_tape: u16) u16 {
    var out: u16 = 0;
    for (0..Atoms) |logical| {
        const physical = (logical * 5 + 3) % Atoms;
        const value = !has(physical_tape, physical);
        if (value) out |= @as(u16, 1) << @as(u4, @intCast(logical));
    }
    return out;
}
fn select(c: usize, pair: Pair, p: Policy, charged: *usize) u16 {
    if (p == .bootstrap_retained) return pair.old;
    if (p == .answer_memory) {
        // INVALID: evaluator answer imported; listed to verify it is not used.
        return relation(c, 1, 0, false, charged);
    }
    // SUPPLIED comparison grammar: seven scheduled probes and an additive total.
    var old_e: i64 = 0; var new_e: i64 = 0;
    for (0..Probe) |turn| {
        old_e += consequence(c, action(pair.old, turn), 1, 100 + turn);
        new_e += consequence(c, action(pair.successor, turn), 1, 100 + turn);
        charged.* += 2;
    }
    if (p == .false_evidence) return if (new_e < old_e) pair.successor else pair.old;
    return if (new_e > old_e) pair.successor else pair.old;
}
fn evaluate(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |c| {
        var pair = build(c, p, &r.charged);
        if (p == .reencoded) {
            pair = .{ .old = decodeReencoded(reencode(pair.old)), .successor = decodeReencoded(reencode(pair.successor)) };
        }
        const before = score(c, pair.old, 1, 500);
        const chosen = select(c, pair, p, &r.charged);
        const after = score(c, chosen, 1, 500);
        r.old += before;
        r.ablated += before; // criterion removal returns to old bootstrap only.
        if (after > before) { r.new += after; r.commits += 1; if (chosen == pair.successor) r.retired += 1; }
        else { r.new += before; r.rollbacks += 1; }
    }
    return r;
}
fn emit(out: anytype, p: Policy, label: []const u8) !void {
    const r = evaluate(p);
    try out.print("round_af_af3,{s},{d},{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.charged, r.old, r.new, r.ablated, r.commits, r.rollbacks, r.retired, label });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,policy,charged_raw_interactions,old_private_resource,new_private_resource,ablated_resource,commits,rollbacks,retired_old_criteria,verdict\n");
    try emit(out, .organism_replacement, "BOUNDED_CAPABILITY:earned_trace_tapes_replace_old_tape_after_private_probes");
    inline for (.{ Policy.fixed_equal, .random, .replay, .static, .shuffled_history, .false_evidence, .answer_memory, .bootstrap_retained, .reencoded }) |p| {
        const label = switch (p) {
            .answer_memory => "INVALID_CONTROL:evaluator_private_answer_memory_ceiling_not_available_to_organism",
            .fixed_equal => "CONTROL:equal_expressive_fixed_criterion",
            .reencoded => "CONTROL:combined_identity_destruction_reconstructed_by_same_host_builder",
            else => "CONTROL",
        };
        try emit(out, p, label);
    }
    const audit = [_][]const u8{
        "CONTROL_PASS:two_trace_dependent_relations_are_created_and_successor_can_retire_old_relation",
        "CONTROL_PASS:fresh_private_resource_random_replay_static_shuffled_false_answer_memory_and_bootstrap_controls_recorded",
        "CONTROL_PASS:ablation_is_exact_old_resource_and_deterministic_csv_replay_is_required",
        "CONTROL_PASS:reencoded_policy_uses_combined_address_value_and_boundary_identity_reconstruction fixture",
        "CONTROL_FAIL:fixed_equal_criterion_ties_the_constructed_replacement_exactly",
        "CONTROL_FAIL:host_defines_byte_atoms_relation_builder_sign_cutoff_decoder_action_scan_probe_schedule_comparison_and_transaction",
        "CONTROL_FAIL:answer_memory_and_reencoding_are_host_test fixtures_not organism_owned transfer semantics",
        "VALID_NEGATIVE:bounded_evidence_dependent_criterion_replacement_exists_but_creation_choice_and_retirement_are_not_organism_owned",
    };
    for (audit) |line| try out.print("round_af_af3,audit,0,0,0,0,0,0,0,{s}\n", .{line});
}
fn require(h: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, h, needle) == null) return error.MissingEvidence; }
fn selftest() !void {
    try run("/tmp/af3-a.csv"); try run("/tmp/af3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/af3-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/af3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const built = evaluate(.organism_replacement); const fixed = evaluate(.fixed_equal); const random = evaluate(.random); const old = evaluate(.bootstrap_retained);
    if (!(built.new > built.old and built.new > random.new and built.new == fixed.new and built.ablated == built.old and built.retired > 0 and built.new > old.new)) return error.InvalidControls;
    try require(x, "VALID_NEGATIVE"); try require(x, "fixed_equal_criterion_ties");
    std.debug.print("round_af_af3 selftest PASS verdict=VALID_NEGATIVE deterministic=true replacement=true organism_owned=false\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/criterion_replacement_round_af.csv"); }
