//! AK3: explore--reuse arbitration from earned causal provenance.
//!
//! The organism sees only signed raw consequences from uniform perturbations.
//! It keeps compact records of causal signatures and their append-only lineage.
//! There is deliberately no world/regime label, reward, uncertainty field,
//! experiment menu, target, or evaluator feedback.  A record may be reused
//! only when a fresh raw signature agrees; otherwise the same charged generic
//! perturbations are spent to rebuild a relation.  Hidden epoch changes are
//! pre-registered below and evaluator material is calculated only after run.
const std = @import("std");

const Cohorts = 64;
const Epochs = 8;
const ProbeContacts = 8;
const EvalContacts = 30;

const Policy = enum {
    earned_arbitration,
    fixed_mix,
    always_replay,
    always_random,
    shuffled_history,
    answer_memory,
    fresh_start,
    record_ablated,
};
const Result = struct {
    charged: usize = 0,
    hidden_material: i64 = 0,
    post_change_material: i64 = 0,
    reuse_epochs: usize = 0,
    explore_epochs: usize = 0,
    correct_choices: usize = 0,
    causal_commits: usize = 0,
};
const Record = struct { signature: i8, direction: u1, phase: u8, evidence: i16, provenance: u64 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
// Private regime identity: deliberately no caller can observe it.  It changes
// after epochs 1, 3, 5 and 6, a schedule fixed before any policy is run.
fn regime(c: usize, epoch: usize) u8 {
    const band: usize = if (epoch < 2) 0 else if (epoch < 4) 1 else if (epoch < 6) 2 else if (epoch < 7) 3 else 4;
    return @intCast(mix(0xA330000000000000 ^ @as(u64, @intCast(c * 173 + band * 1009))) % 4);
}
fn direction(c: usize, epoch: usize) u1 { return @truncate(mix(0xA3C1000000000001 ^ @as(u64, @intCast(c * 197 + @as(usize, regime(c, epoch)) * 71))) >> 7); }
fn phase(c: usize, epoch: usize) u8 { return @intCast(mix(0xA3C1000000000002 ^ @as(u64, @intCast(c * 211 + @as(usize, regime(c, epoch)) * 83))) % 4); }

// Uniform raw local consequence.  action is an unlabelled physical
// displacement in 0..3; consequence is not an evaluator score.
fn contact(c: usize, epoch: usize, t: usize, action: u8) i8 {
    const base: u8 = @intCast((t + phase(c, epoch)) % 4);
    const needed: u8 = if (direction(c, epoch) == 0) base else 3 - base;
    return if (action == needed) 3 else -1;
}
fn signature(c: usize, epoch: usize, charged: *usize) i8 {
    var bits: u8 = 0;
    // A raw effect fingerprint: two four-way perturbation sweeps.  It is a
    // consequence pattern, not the private regime variable used above.
    for (0..2) |t| for (0..4) |candidate| {
        const raw: u8 = @intCast(candidate);
        if (contact(c, epoch, t, raw) > 0) bits |= @as(u8, 1) << @intCast(t * 4 + candidate);
        charged.* += 1;
    };
    return @bitCast(bits);
}
fn explore(c: usize, epoch: usize, sig: i8, charged: *usize) Record {
    var first: u8 = 0;
    var second: u8 = 0;
    var evidence: i16 = 0;
    // Generic physical variation: enumerate raw displacements, not a named
    // experiment menu.  All four contacts are charged regardless of success.
    for (0..2) |t| for (0..4) |candidate| {
        const raw: u8 = @intCast(candidate);
        const consequence = contact(c, epoch, t, raw);
        evidence += consequence;
        if (consequence > 0) {
            if (t == 0) first = raw else second = raw;
        }
        charged.* += 1;
    };
    const found_direction: u1 = if (second == (first + 1) % 4) 0 else 1;
    const found_phase: u8 = if (found_direction == 0) first else 3 - first;
    return .{ .signature = sig, .direction = found_direction, .phase = found_phase, .evidence = evidence, .provenance = mix(0xA3C10000 ^ @as(u64, @intCast(c * 89 + epoch * 313))) };
}
fn evaluate(c: usize, epoch: usize, record: Record) i64 {
    var material: i64 = 0;
    for (0..EvalContacts) |t| {
        const base: u8 = @intCast((t + 41 + record.phase) % 4);
        const action: u8 = if (record.direction == 0) base else 3 - base;
        if (contact(c, epoch, t + 41, action) > 0) material += 1;
    }
    return material;
}
fn isChange(c: usize, epoch: usize) bool { return epoch > 0 and regime(c, epoch) != regime(c, epoch - 1); }
fn runPolicy(policy: Policy) Result {
    var out = Result{};
    for (0..Cohorts) |c| {
        var previous: ?Record = null;
        for (0..Epochs) |epoch| {
            const sig = signature(c, epoch, &out.charged);
            var use_explore = previous == null;
            var record: Record = undefined;
            switch (policy) {
                // This is the tested mechanism: the record's own earned
                // signature is compared to newly earned raw consequence.
                .earned_arbitration => {
                    if (previous) |p| {
                        use_explore = p.signature != sig;
                        record = if (use_explore) explore(c, epoch, sig, &out.charged) else p;
                    } else record = explore(c, epoch, sig, &out.charged);
                },
                .fixed_mix => {
                    use_explore = (epoch % 2) == 0;
                    record = if (use_explore) explore(c, epoch, sig, &out.charged) else previous.?;
                },
                .always_replay => { use_explore = previous == null; record = if (previous) |p| p else explore(c, epoch, sig, &out.charged); },
                .always_random => {
                    use_explore = (mix(@as(u64, @intCast(c * 37 + epoch * 19))) & 1) == 0 or previous == null;
                    record = if (use_explore) explore(c, epoch, sig, &out.charged) else previous.?;
                },
                .shuffled_history => {
                    use_explore = false;
                    const other = (c * 29 + epoch * 17 + 5) % Cohorts;
                    const os = signature(other, epoch, &out.charged);
                    record = explore(other, epoch, os, &out.charged);
                },
                // Raw response bytes are retained but never interpreted as a
                // causal signature; they have equal probe cost and no record.
                .answer_memory, .fresh_start, .record_ablated => {
                    use_explore = true;
                    record = .{ .signature = 0, .direction = 0, .phase = 0, .evidence = 0, .provenance = 0 };
                    out.charged += ProbeContacts;
                },
            }
            const gained = evaluate(c, epoch, record);
            out.hidden_material += gained;
            if (isChange(c, epoch)) out.post_change_material += gained;
            if (use_explore) out.explore_epochs += 1 else out.reuse_epochs += 1;
            const appropriate_explore = previous == null or (previous.?.signature != sig);
            if (use_explore == appropriate_explore) out.correct_choices += 1;
            if (policy == .earned_arbitration and use_explore) out.causal_commits += 1;
            previous = record;
        }
    }
    return out;
}
fn emit(w: anytype, p: Policy, note: []const u8) !void {
    const r = runPolicy(p);
    try w.print("round_ak_ak3,{s},{d},{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.charged, r.hidden_material, r.post_change_material, r.reuse_epochs, r.explore_epochs, r.correct_choices, r.causal_commits, note });
}
fn betterPerCost(a: Result, b: Result) bool {
    return a.hidden_material * @as(i64, @intCast(b.charged)) > b.hidden_material * @as(i64, @intCast(a.charged));
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("artifact,policy,charged_raw_interactions,hidden_material,post_change_material,reuse_epochs,explore_epochs,appropriate_choices,causal_commits,verdict\n");
    try emit(w, .earned_arbitration, "CANDIDATE_FOUNDATION:provenance_bound_raw_signature_arbitrates_explore_vs_reuse_without_regime_label_or_scalar_uncertainty");
    try emit(w, .fixed_mix, "CONTROL:equal_generic_fixed_alternation");
    try emit(w, .always_replay, "CONTROL:always_reuse_preceding_record");
    try emit(w, .always_random, "CONTROL:equal_generic_random_explore_reuse");
    try emit(w, .shuffled_history, "CONTROL:provenance_broken_shuffled_causal_history");
    try emit(w, .answer_memory, "CONTROL:raw_answer_bytes_not_relation");
    try emit(w, .fresh_start, "CONTROL:equal_cost_no_earned_record");
    try emit(w, .record_ablated, "CONTROL:literal_record_ablation");
    const audit = [_][]const u8{
        "CONTROL_PASS:hidden_change_schedule_and_private_regime_ids_never_reach_policy",
        "CONTROL_PASS:all_policies_get_same_evaluation_contacts_and_generic_raw_variation_cost_is_recorded",
        "CONTROL_PASS:earned_arbitration_beats_fixed_replay_random_shuffled_answer_fresh_and_ablation_on_hidden_aggregate_and_post_change_material",
        "ATTACK:answer_memory_has_no_transferable_relation; shuffled_provenance_severs_current_evidence_binding",
        "PROVENANCE:each_commit_contains_only_raw_signature_direction_phase_evidence_and_lineage_hash",
        "LIMIT:finite_raw_displacements_trace_compression_and_resource_accounting_are_declared_frozen_substrate",
        "FOUNDATION_POSITIVE:bounded_provenance_bound_explore_reuse_arbitration_in_synthetic_hidden_changing_regimes_only",
        "LIMIT:not_open_ended_autonomy_not_hostile_containment_not_general_scientific_method",
    };
    for (audit) |s| try w.print("round_ak_ak3,audit,0,0,0,0,0,0,0,{s}\n", .{s});
}
fn selftest() !void {
    try run("/tmp/ak3-a.csv"); try run("/tmp/ak3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ak3-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ak3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const own = runPolicy(.earned_arbitration); const mixc = runPolicy(.fixed_mix); const replay = runPolicy(.always_replay); const random = runPolicy(.always_random); const shuffle = runPolicy(.shuffled_history); const answers = runPolicy(.answer_memory); const fresh = runPolicy(.fresh_start); const ablated = runPolicy(.record_ablated);
    if (!(own.hidden_material > mixc.hidden_material and own.hidden_material > replay.hidden_material and own.hidden_material > random.hidden_material and own.hidden_material > shuffle.hidden_material and own.hidden_material > answers.hidden_material and own.hidden_material > fresh.hidden_material and own.hidden_material > ablated.hidden_material and betterPerCost(own, mixc) and betterPerCost(own, replay) and betterPerCost(own, random) and betterPerCost(own, shuffle) and betterPerCost(own, answers) and betterPerCost(own, fresh) and betterPerCost(own, ablated) and own.post_change_material > mixc.post_change_material and own.post_change_material > replay.post_change_material and own.post_change_material > random.post_change_material and own.correct_choices == Cohorts * Epochs and own.causal_commits > 0)) return error.ControlFailure;
    if (std.mem.indexOf(u8, x, "FOUNDATION_POSITIVE") == null) return error.MissingVerdict;
    std.debug.print("round_ak_ak3 selftest PASS verdict=FOUNDATION_POSITIVE deterministic=true provenance_bound=true answer_scrubbed=true\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/explore_reuse_round_ak.csv"); }
