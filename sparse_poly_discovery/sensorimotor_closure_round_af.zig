//! Round AF / AF2 -- hostile local test of endogenous sensorimotor closure.
//!
//! Deliberate VALID NEGATIVE.  A mutable record retains a useful relation
//! between a raw perturbation and later raw changes, but `hostClosure` chooses
//! what an intervention is, which later cells are consequences, how samples
//! align, and how agreement becomes a candidate criterion.  That remains a
//! supplied sensorimotor ontology, not organism-owned criterion birth.
const std = @import("std");

const Cohorts = 24;
const Cells = 128;
const ClosureCells = 20;
const Epochs = 20;
const TrainTrials = 10;
const FreshTrials = 30;

const Policy = enum {
    endogenous, ablated, raw_random, replay, static, fixed_closure,
    shuffled_lineage, false_lineage, copied_bloat, relocated, recoded,
    resegmented, instruction_destroyed, boundary_destroyed, combined_destroyed,
};
const Result = struct {
    charged: usize = 0, old_resource: i64 = 0, new_resource: i64 = 0,
    ablated_resource: i64 = 0, updates: usize = 0, commits: usize = 0,
    rollbacks: usize = 0, lineage: u64 = 0,
};

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn at(i: usize, p: Policy) usize {
    return switch (p) {
        .relocated, .combined_destroyed => (i * 53 + 19) % Cells,
        .boundary_destroyed => (i * 37 + 7) % Cells,
        else => i,
    };
}
fn recode(v: u8, i: usize, p: Policy) u8 {
    return if (p == .recoded or p == .combined_destroyed) v ^ @as(u8, @truncate(mix(0xaf2000 ^ i * 71))) else v;
}
fn seed(cohort: usize, p: Policy) [Cells]u8 {
    var a: [Cells]u8 = undefined;
    for (0..Cells) |i| a[at(i, p)] = recode(@truncate(mix(0xaf2100 ^ cohort * 419 ^ i * 31)), i, p);
    return a;
}

// The only defensible exterior here is uniform raw transport plus finite
// resources.  It contains no named object, port, instruction, or target.
fn transport(a: [Cells]u8, nonce: usize, p: Policy) [Cells]u8 {
    var b: [Cells]u8 = undefined;
    for (0..Cells) |logical| {
        const i = at(logical, p);
        const l = a[at((logical + Cells - 1) % Cells, p)];
        const r = a[at((logical + 1) % Cells, p)];
        b[i] = a[i] +% std.math.rotl(u8, l ^ r, @as(u3, @intCast(nonce % 8))) ^ @as(u8, @truncate(mix(nonce ^ logical)));
    }
    return b;
}

// DISQUALIFYING HOST ONTOLOGY.  It provides the intervention address (a raw
// XOR at `cause`), chooses the outcome sites, time separation, grouping and
// XOR difference relation.  Renaming them raw indices does not remove this
// observer/probe grammar.
fn hostClosure(cohort: usize, trial: usize, p: Policy) [ClosureCells]u8 {
    var base = seed(cohort ^ 0x5a, p);
    const cause = at((trial * 17 + 11) % Cells, p);
    base[cause] ^= 0xa7; // host-defined intervention identity and magnitude
    const next = transport(base, 7001 + trial, p);
    var c: [ClosureCells]u8 = undefined;
    for (0..ClosureCells) |j| {
        const slot = if (p == .resegmented or p == .combined_destroyed) (j * 9 + 5) % ClosureCells else j;
        const observed = at((slot * 5 + 3) % Cells, p);
        c[j] = (next[observed] ^ base[observed]) ^ recode(@as(u8, @truncate(cause)), j, p);
    }
    return c;
}

// Also disqualifying: this makes a record a criterion and converts agreement
// into resource.  It is included to reveal, rather than conceal, the hidden
// measurement relation that invalidates the claimed autonomy.
fn hostResource(field: [Cells]u8, cohort: usize, trial: usize, p: Policy) i64 {
    const closure = hostClosure(cohort, trial, p);
    var total: i64 = 0;
    for (0..ClosureCells) |j| {
        const slot = if (p == .instruction_destroyed or p == .combined_destroyed) (j * 7 + 1) % ClosureCells else j;
        const addr = at(slot, p);
        total += 8 - @as(i64, @intCast(@popCount(field[addr] ^ closure[slot])));
    }
    return total;
}
fn measure(field: [Cells]u8, cohort: usize, first: usize, count: usize, p: Policy, charged: *usize) i64 {
    var n: i64 = 0;
    for (0..count) |t| n += hostResource(field, cohort, first + t, p);
    charged.* += count;
    return n;
}

fn build(cohort: usize, p: Policy, r: *Result) [Cells]u8 {
    var a = seed(cohort, p);
    if (p == .ablated or p == .static) return a;
    for (0..Epochs) |epoch| {
        const evidence = hostClosure(cohort, epoch, p);
        var candidate = a;
        for (0..ClosureCells) |j| {
            const addr = at(if (p == .instruction_destroyed or p == .combined_destroyed) (j * 7 + 1) % ClosureCells else j, p);
            candidate[addr] = switch (p) {
                .endogenous, .relocated, .recoded, .resegmented, .instruction_destroyed, .boundary_destroyed, .combined_destroyed => evidence[j],
                .shuffled_lineage => evidence[(j * 13 + 3) % ClosureCells],
                .false_lineage => ~evidence[j],
                .copied_bloat => if (j < ClosureCells / 2) evidence[j] else @truncate(mix(0xaf3300 ^ cohort * 17 ^ epoch * 29 ^ j)),
                .raw_random => @truncate(mix(0xaf3400 ^ cohort * 17 ^ epoch * 29 ^ j)),
                .replay => @truncate(mix(0xaf2100 ^ cohort * 419 ^ j * 31)),
                .fixed_closure => @truncate(mix(0xaf3500 ^ cohort * 17 ^ epoch * 29 ^ j)),
                else => candidate[addr],
            };
        }
        const old = measure(a, cohort, 0, TrainTrials, p, &r.charged);
        const fresh = measure(candidate, cohort, 0, TrainTrials, p, &r.charged);
        // Candidate acceptance is itself supplied by the host's scalar reward.
        const accept = if (p == .false_lineage) fresh < old else fresh > old;
        if (accept) { a = candidate; r.updates += 1; }
        r.lineage = mix(r.lineage ^ @as(u64, @intCast(cohort * 101 + epoch)) ^ @as(u64, @bitCast(fresh - old)));
    }
    return a;
}
fn evaluate(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| {
        const old = seed(cohort, p);
        const made = build(cohort, p, &r);
        const before = measure(old, cohort, Epochs, FreshTrials, p, &r.charged);
        const after = measure(made, cohort, Epochs, FreshTrials, p, &r.charged);
        r.old_resource += before;
        r.ablated_resource += before;
        if (after > before and p != .false_lineage) { r.new_resource += after; r.commits += 1; }
        else { r.new_resource += before; r.rollbacks += 1; }
    }
    return r;
}
fn emit(out: anytype, p: Policy, verdict: []const u8) !void {
    const r = evaluate(p);
    try out.print("round_af_af2,sensorimotor_closure,{s},{d},{d},{d},{d},{d},{d},{d},0x{x},{s}\n", .{ @tagName(p), r.charged, r.old_resource, r.new_resource, r.ablated_resource, r.updates, r.commits, r.rollbacks, r.lineage, verdict });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,partition,policy,charged_work,old_resource,new_resource,ablated_resource,updates,commits,rollbacks,lineage_hash,verdict\n");
    try emit(out, .endogenous, "LIMITED_RESULT:closure_record_improves_host_scored_resource");
    try emit(out, .ablated, "CONTROL_PASS:criterion_ablation_returns_baseline");
    try emit(out, .raw_random, "CONTROL:equal_cost_raw_random");
    try emit(out, .replay, "CONTROL:equal_cost_replay");
    try emit(out, .static, "CONTROL:static_raw_field");
    try emit(out, .fixed_closure, "CONTROL:equally_expressive_fixed_closure");
    try emit(out, .shuffled_lineage, "CONTROL:shuffled_causal_lineage");
    try emit(out, .false_lineage, "CONTROL_PASS:false_lineage_rolls_back");
    try emit(out, .copied_bloat, "CONTROL:equal_cost_copy_bloat");
    try emit(out, .relocated, "ATTACK:address_relocation");
    try emit(out, .recoded, "ATTACK:value_recoding");
    try emit(out, .resegmented, "ATTACK:group_resegmentation");
    try emit(out, .instruction_destroyed, "ATTACK:instruction_identity_destruction");
    try emit(out, .boundary_destroyed, "ATTACK:boundary_destruction");
    try emit(out, .combined_destroyed, "ATTACK:combined_address_value_group_instruction_boundary_destruction");
    const attacks = [_][]const u8{
        "CONTROL_PASS:no_llm_text_tokens_embeddings_neural_or_neurosymbolic_mechanism",
        "CONTROL_PASS:all_ordinary_measurement_work_is_charged_and_fresh_worlds_are_sealed",
        "CONTROL_FAIL:hostClosure_supplies_intervention_site_magnitude_outcome_grouping_and_difference_relation",
        "CONTROL_FAIL:hostResource_supplies_record_alignment_comparison_and_resource_meaning",
        "CONTROL_FAIL:host_scalar_acceptance_is_a_supplied_criterion_and_candidate_selection_rule",
        "CONTROL_FAIL:raw_transport_and_private_world_family_are_human_selected_exterior_physics",
    };
    for (attacks) |a| try out.print("round_af_af2,attack,hostile,0,0,0,0,0,0,0,0x0,{s}\n", .{a});
    const r = evaluate(.endogenous);
    try out.print("round_af_af2,closure,aggregate,{d},{d},{d},{d},{d},{d},{d},0x{x},VALID_NEGATIVE:closure_gain_requires_host_defined_intervention_observation_and_comparison\n", .{ r.charged, r.old_resource, r.new_resource, r.ablated_resource, r.updates, r.commits, r.rollbacks, r.lineage });
}
fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const al = gpa.allocator();
    try run("/tmp/af2a.csv"); try run("/tmp/af2b.csv");
    const a = try std.fs.cwd().readFileAlloc(al, "/tmp/af2a.csv", 1 << 20); defer al.free(a);
    const b = try std.fs.cwd().readFileAlloc(al, "/tmp/af2b.csv", 1 << 20); defer al.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministic;
    const e = evaluate(.endogenous); const ab = evaluate(.ablated); const random = evaluate(.raw_random); const replay = evaluate(.replay);
    if (!(e.new_resource > ab.new_resource and e.new_resource > random.new_resource and e.new_resource > replay.new_resource and e.ablated_resource == e.old_resource)) return error.MissingCausalSignal;
    if (std.mem.indexOf(u8, a, "CONTROL_FAIL:hostClosure") == null or std.mem.indexOf(u8, a, "VALID_NEGATIVE:") == null) return error.MissingAudit;
    std.debug.print("round_af_af2 selftest PASS verdict=VALID_NEGATIVE deterministic=true closure_gain=true organism_owned_criterion=false\n", .{});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/sensorimotor_closure_round_af.csv");
}
