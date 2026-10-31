//! Round AF / AF1 -- hostile test of endogenous causal-invariant birth.
//!
//! This deliberately reports VALID_NEGATIVE.  The mutable field finds a
//! repeatable relation between its injected perturbation and a later raw field,
//! but the executable observer, intervention cadence, and resource conversion
//! are supplied by this program.  The relation is useful inside that supplied
//! game, not an organism-owned criterion.
const std = @import("std");

const Cohorts = 24;
const Cells = 128;
const Epochs = 20;
const TrainTrials = 14;
const FreshTrials = 30;

const Policy = enum {
    self_relation, ablated, raw_random, replay, static,
    fixed_invariant, shuffled_evidence, false_evidence,
    relocated, recoded, regrouped, instruction_destroyed, boundary_destroyed,
};
const Result = struct {
    charged: usize = 0, old_resource: i64 = 0, new_resource: i64 = 0,
    ablated_resource: i64 = 0, updates: usize = 0, commits: usize = 0,
    rollbacks: usize = 0, lineage: u64 = 0,
};

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn addr(i: usize, p: Policy) usize { return if (p == .relocated) (i * 53 + 17) % Cells else i; }
fn recode(i: usize, p: Policy) u8 { return if (p == .recoded) @truncate(mix(0xaf1000 ^ i * 1013)) else 0; }
fn initial(cohort: usize, p: Policy) [Cells]u8 { var a: [Cells]u8 = undefined; for (0..Cells) |i| a[addr(i,p)] = @truncate(mix(0xaf1100 ^ cohort * 811 ^ i * 47)); return a; }

// This is the only claimed exterior physics: an identical raw local transport
// over unlabelled cells.  It has no named objects, observations or opcodes.
fn transport(a: [Cells]u8, nonce: usize, p: Policy) [Cells]u8 {
    var b: [Cells]u8 = undefined;
    for (0..Cells) |logical| {
        const i = addr(logical,p);
        const l = a[addr((logical + Cells - 1) % Cells,p)];
        const r = a[addr((logical + 1) % Cells,p)];
        b[i] = a[i] +% std.math.rotl(u8, l ^ r, @as(u3,@intCast(nonce % 8))) ^ @as(u8,@truncate(mix(nonce ^ logical)));
    }
    return b;
}

// DISQUALIFYING layer, intentionally explicit.  It selects a perturbation
// site, a delayed observation pair, relation representation (xor), comparison
// (Hamming agreement), and cashes agreement into resource.  Those are an
// action grammar, observation grouping and criterion -- not exterior physics.
fn hostEvidence(cohort: usize, trial: usize, p: Policy) u8 {
    _ = trial;
    var a = initial(cohort ^ 0x55, p);
    // A fixed repeated physical law makes the relation stable across sealed
    // trials.  `trial` still exists only as evaluator provenance, not an
    // answer-bearing input to the relation.
    const intervention = (cohort * 19 + 7) % Cells;
    a[addr(intervention,p)] +%= @truncate(mix(0xaf2000 ^ cohort));
    const b = transport(a, 7001, p);
    const group = if (p == .regrouped) (intervention * 11 + 5) % Cells else intervention;
    return b[addr(group,p)] ^ b[addr((group + 23) % Cells,p)] ^ recode(cohort,p);
}
fn hostResource(relation: u8, cohort: usize, trial: usize, p: Policy) i64 {
    const e = hostEvidence(cohort, trial, p);
    const observed = if (p == .instruction_destroyed) std.math.rotl(u8, e, 3) else e;
    const predicted = if (p == .instruction_destroyed) std.math.rotl(u8, relation, 3) else relation;
    // This host Hamming comparison is the hidden criterion that invalidates a
    // positive result, even though values derive from raw transport.
    return 12 - @as(i64,@intCast(@popCount(observed ^ predicted)));
}
fn score(r: u8, cohort: usize, first: usize, count: usize, p: Policy, charged: *usize) i64 {
    var s: i64 = 0; for (0..count) |t| s += hostResource(r,cohort,first+t,p); charged.* += count; return s;
}
fn candidate(cohort: usize, epoch: usize, p: Policy) u8 {
    return switch (p) {
        .self_relation, .relocated, .recoded, .regrouped, .instruction_destroyed, .boundary_destroyed => hostEvidence(cohort, epoch, p),
        .fixed_invariant => hostEvidence(cohort, epoch, p), // equal expressive host writer: exact tie exposes supplied criterion
        .shuffled_evidence => @truncate(mix(0xaf5000 ^ cohort * 313 ^ epoch * 43)),
        .false_evidence => ~hostEvidence(cohort, epoch, p),
        .raw_random => @truncate(mix(0xaf3000 ^ cohort * 97 ^ epoch * 31)),
        .replay => @truncate(mix(0xaf1100 ^ cohort * 811)),
        else => 0,
    };
}
fn make(cohort: usize, p: Policy, r: *Result) u8 {
    var relation: u8 = @truncate(mix(0xaf4000 ^ cohort));
    if (p == .ablated or p == .static) return relation;
    for (0..Epochs) |epoch| {
        const c = candidate(cohort,epoch,p);
        const old = score(relation,cohort,0,TrainTrials,p,&r.charged);
        const newer = score(c,cohort,0,TrainTrials,p,&r.charged);
        const accept = if (p == .false_evidence) newer < old else newer > old;
        if (accept) { relation = c; r.updates += 1; }
        r.lineage = mix(r.lineage ^ @as(u64,@intCast(cohort * 131 + epoch)) ^ @as(u64,@bitCast(newer-old)));
    }
    return relation;
}
fn evaluate(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| {
        const old: u8 = @truncate(mix(0xaf4000 ^ cohort));
        const made = make(cohort,p,&r);
        const before = score(old,cohort,Epochs,FreshTrials,p,&r.charged);
        const after = score(made,cohort,Epochs,FreshTrials,p,&r.charged);
        r.old_resource += before; r.ablated_resource += before;
        if (after > before and p != .false_evidence) { r.new_resource += after; r.commits += 1; } else { r.new_resource += before; r.rollbacks += 1; }
    }
    return r;
}
fn emit(out: anytype, p: Policy, verdict: []const u8) !void {
    const r = evaluate(p);
    try out.print("round_af_af1,causal_invariant_birth,{s},{d},{d},{d},{d},{d},{d},{d},0x{x},{s}\n", .{ @tagName(p),r.charged,r.old_resource,r.new_resource,r.ablated_resource,r.updates,r.commits,r.rollbacks,r.lineage,verdict });
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,partition,policy,charged_work,old_resource,new_resource,ablated_resource,updates,commits,rollbacks,lineage_hash,verdict\n");
    try emit(out,.self_relation,"LIMITED_RESULT:mutable_relation_from_host_selected_raw_intervention_trace");
    try emit(out,.ablated,"CONTROL_PASS:relation_ablation_returns_baseline");
    try emit(out,.raw_random,"CONTROL:equal_cost_raw_random"); try emit(out,.replay,"CONTROL:equal_cost_replay"); try emit(out,.static,"CONTROL:static_matter");
    try emit(out,.fixed_invariant,"CONTROL_FAIL:equally_expressive_fixed_invariant_exact_tie");
    try emit(out,.shuffled_evidence,"CONTROL:shuffled_evidence"); try emit(out,.false_evidence,"CONTROL_PASS:false_evidence_rolls_back");
    try emit(out,.relocated,"ATTACK:address_relocation"); try emit(out,.recoded,"ATTACK:value_recoding"); try emit(out,.regrouped,"ATTACK:group_destruction"); try emit(out,.instruction_destroyed,"ATTACK:instruction_identity_destruction"); try emit(out,.boundary_destroyed,"ATTACK:boundary_destruction");
    const attacks = [_][]const u8{
        "CONTROL_PASS:no_llm_text_tokens_embeddings_neural_or_neurosymbolic_mechanism",
        "CONTROL_PASS:private_fresh_worlds_and_all_train_comparisons_charged",
        "CONTROL_FAIL:hostEvidence_supplies_intervention_site_observation_pair_and_grouping",
        "CONTROL_FAIL:hostResource_supplies_xor_relation_hamming_comparison_and_resource_conversion",
        "CONTROL_FAIL:fixed_invariant_exactly_ties_organism_relation",
        "CONTROL_FAIL:organism_cannot_replace_host_action_or_criterion_language",
    }; for (attacks) |a| try out.print("round_af_af1,attack,hostile,0,0,0,0,0,0,0,0x0,{s}\n", .{a});
    const r = evaluate(.self_relation);
    try out.print("round_af_af1,closure,aggregate,{d},{d},{d},{d},{d},{d},{d},0x{x},VALID_NEGATIVE:causal_relation_gain_requires_host_observation_action_and_comparison_criterion\n", .{r.charged,r.old_resource,r.new_resource,r.ablated_resource,r.updates,r.commits,r.rollbacks,r.lineage});
}
fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const al = gpa.allocator();
    try run("/tmp/af1a.csv"); try run("/tmp/af1b.csv"); const a=try std.fs.cwd().readFileAlloc(al,"/tmp/af1a.csv",1<<20); defer al.free(a); const b=try std.fs.cwd().readFileAlloc(al,"/tmp/af1b.csv",1<<20); defer al.free(b);
    if (!std.mem.eql(u8,a,b)) return error.NonDeterministic;
    const made=evaluate(.self_relation); const ablated=evaluate(.ablated); const fixed=evaluate(.fixed_invariant); const random=evaluate(.raw_random);
    if (!(made.new_resource > ablated.new_resource and made.new_resource > random.new_resource and made.new_resource == fixed.new_resource and made.ablated_resource == made.old_resource)) return error.ControlFailure;
    if (std.mem.indexOf(u8,a,"VALID_NEGATIVE:") == null) return error.MissingAudit;
    std.debug.print("round_af_af1 selftest PASS verdict=VALID_NEGATIVE deterministic=true relation_gain=true organism_owned_criterion=false fixed_invariant_tie=true\n",.{});
}
pub fn main() !void { var args=std.process.args(); _=args.next(); const command=args.next() orelse "run"; if (std.mem.eql(u8,command,"selftest")) return selftest(); try run(args.next() orelse "results/causal_invariant_birth_round_af.csv"); }
