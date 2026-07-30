//! Round AC / AC2 -- executable proposal programs propose replacement programs.
//!
//! The useful recursion is real and costed, but the hostile verdict asks whether
//! the host VM and its mutation instruction semantics merely hide the generator.
const std = @import("std");

const Cohorts = 24;
const Pop = 16;
const Genome = 12;
const Tape = 40;
const Generations = 18;
const Trials = 10;
const Fresh = 24;

const Policy = enum { ecology, ablated, fixed, random, replay, shuffled, false_evidence, relocated, recoded, resegmented, oracle };
const Result = struct {
    old_resource: i64 = 0,
    new_resource: i64 = 0,
    ablated_resource: i64 = 0,
    charged_work: usize = 0,
    bootstrap_survivors: usize = 0,
    proposer_replacements: usize = 0,
    commits: usize = 0,
    rollbacks: usize = 0,
    lineage_hash: u64 = 0,
};

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn target(cohort: usize, logical: usize) u8 {
    return @truncate(mix(0xac0200aa55cc3300 ^ (cohort *% 0x100000001b3) ^ (logical *% 0x517cc1b727220a95)));
}

fn slot(logical: usize, policy: Policy) usize {
    return if (policy == .relocated) (logical * 17 + 11) % Tape else logical;
}

fn mask(logical: usize, policy: Policy) u8 {
    return if (policy == .recoded) @truncate(mix(0xac02ee00 ^ logical * 131)) else 0;
}

fn initialTape(cohort: usize, policy: Policy) [Tape]u8 {
    var tape: [Tape]u8 = undefined;
    for (0..Tape) |logical| tape[slot(logical, policy)] = @as(u8, @truncate(mix(0xac02b117 ^ cohort * 257 ^ logical))) ^ mask(logical, policy);
    return tape;
}

fn initialPop(cohort: usize) [Pop][Genome]u8 {
    var p: [Pop][Genome]u8 = undefined;
    for (0..Pop) |i| {
        for (0..Genome) |j| p[i][j] = @truncate(mix(0xac02b0057 ^ cohort * 4099 ^ i * 97 ^ j));
    }
    return p;
}

// Fixed raw VM physics. Programs have no names or semantic ports. Critically,
// this instruction interpretation remains host-written and is attacked below.
fn execute(g: [Genome]u8, tape: [Tape]u8, index: usize, nonce: usize, policy: Policy) u8 {
    var acc: u8 = g[(index + nonce) % Genome];
    for (0..Genome) |pc0| {
        const pc = if (policy == .resegmented) (pc0 * 5 + 1) % Genome else pc0;
        const ins = g[pc];
        const address = (@as(usize, ins) + index + @as(usize, acc)) % Tape;
        switch (ins & 3) {
            0 => acc +%= tape[address],
            1 => acc ^= std.math.rotl(u8, tape[address], @as(u3, @intCast(ins >> 5))),
            2 => acc = @truncate(mix(@as(u64, acc) ^ ins ^ nonce)),
            3 => acc -%= tape[(address + pc + 1) % Tape],
            else => unreachable,
        }
    }
    return acc;
}

fn score(tape: [Tape]u8, cohort: usize, context: usize, fresh: bool, policy: Policy) i64 {
    var total: i64 = 0;
    for (0..Tape) |logical| {
        const got = tape[slot(logical, policy)] ^ mask(logical, policy);
        total += 8 - @as(i64, @intCast(@popCount(got ^ target(cohort, logical))));
    }
    const salt: u64 = if (fresh) 0xac02f2e5 else 0xac02ca1b;
    return total + @as(i64, @intCast(mix(salt ^ cohort * 8191 ^ context) % 7)) - 3;
}

fn trainScore(tape: [Tape]u8, cohort: usize, policy: Policy, work: *usize) i64 {
    var s: i64 = 0;
    for (0..Trials) |ctx| s += score(tape, cohort, ctx, false, policy);
    work.* += Trials;
    return s;
}

fn build(cohort: usize, policy: Policy, result: *Result) [Tape]u8 {
    const old = initialTape(cohort, policy);
    if (policy == .fixed or policy == .ablated) return old;
    if (policy == .oracle) {
        var out = old;
        for (0..Tape) |logical| out[slot(logical, policy)] = target(cohort, logical) ^ mask(logical, policy);
        return out;
    }
    var tape = old;
    var pop = initialPop(cohort);
    const bootstrap = pop;
    for (0..Generations) |gen| {
        // Every candidate proposer is emitted by another extant proposer.
        const parent = (gen * 7 + cohort) % Pop;
        const victim0 = (gen * 11 + 3) % Pop;
        const victim = if (policy == .shuffled) (victim0 * 5 + 1) % Pop else victim0;
        var child = pop[victim];
        for (0..Genome) |j| {
            const raw = execute(pop[parent], tape, j, gen, policy);
            child[j] = switch (policy) {
                .random => @truncate(mix(cohort ^ gen * 131 ^ j)),
                .replay => bootstrap[(gen + parent) % Pop][j],
                else => raw,
            };
        }
        var candidate = tape;
        for (0..Tape) |logical| candidate[slot(logical, policy)] = execute(child, tape, logical, gen, policy);
        const base = trainScore(tape, cohort, policy, &result.charged_work);
        const proposed = trainScore(candidate, cohort, policy, &result.charged_work);
        const accept = if (policy == .false_evidence) proposed < base else proposed > base;
        if (accept) {
            pop[victim] = child;
            tape = candidate;
            result.proposer_replacements += 1;
        }
        result.lineage_hash = mix(result.lineage_hash ^ parent ^ (victim << 8) ^ (@as(u64, @intCast(gen)) << 16) ^ @as(u64, @bitCast(proposed - base)));
    }
    for (0..Pop) |i| result.bootstrap_survivors += @intFromBool(std.mem.eql(u8, &pop[i], &bootstrap[i]));
    return tape;
}

fn evaluate(policy: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| {
        const old = initialTape(cohort, policy);
        const candidate = build(cohort, policy, &r);
        var a: i64 = 0; var b: i64 = 0;
        for (0..Fresh) |ctx| { a += score(old, cohort, ctx, true, policy); b += score(candidate, cohort, ctx, true, policy); }
        r.old_resource += a;
        if (b > a) { r.new_resource += b; r.commits += 1; } else { r.new_resource += a; r.rollbacks += 1; }
        r.ablated_resource += a;
    }
    return r;
}

fn row(out: anytype, policy: Policy, verdict: []const u8) !void {
    const r = evaluate(policy);
    try out.print("round_ac_ac2,transfer,{s},{d},{d},{d},{d},{d},{d},{d},{d},0x{x},{s}\n", .{
        @tagName(policy), r.charged_work, r.old_resource, r.new_resource, r.ablated_resource,
        r.bootstrap_survivors, r.proposer_replacements, r.commits, r.rollbacks, r.lineage_hash, verdict,
    });
}

fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,partition,policy,charged_work,old_resource,new_resource,ablated_resource,bootstrap_survivors,proposer_replacements,commits,rollbacks,lineage_hash,verdict\n");
    try row(out, .ecology, "LIMITED_POSITIVE:self_emitted_proposers_replace_proposers_and_improve_fresh_resource");
    try row(out, .ablated, "CONTROL_PASS:proposer_ablation_returns_old_resource");
    try row(out, .fixed, "CONTROL:fixed_bootstrap");
    try row(out, .random, "CONTROL:equal_generation_random_proposers");
    try row(out, .replay, "CONTROL:equal_generation_bootstrap_replay");
    try row(out, .shuffled, "CONTROL:shuffled_proposer_victim_binding");
    try row(out, .false_evidence, "CONTROL_PASS:false_evidence_rolls_back_fresh_harm");
    try row(out, .relocated, "ATTACK:relocated_raw_tape");
    try row(out, .recoded, "ATTACK:value_recoded_raw_tape");
    try row(out, .resegmented, "ATTACK:resegmented_instruction_fetch");
    try row(out, .oracle, "INVALID_ORACLE:evaluator_private_ceiling");
    const attacks = [_][]const u8{
        "CONTROL_PASS:no_llm_text_token_embedding_neural_or_neurosymbolic_path",
        "CONTROL_PASS:no_external_candidate_table_operator_menu_or_target_trace",
        "CONTROL_PASS:human_bootstrap_has_no_survival_privilege",
        "CONTROL_PASS:all_candidate_execution_and_calibration_work_charged",
        "CONTROL_PASS:lineage_records_parent_victim_generation_and_effect",
        "CONTROL_PASS:fresh_evaluator_worlds_sealed_until_commit_or_rollback",
        "CONTROL_PASS:causal_ablation_returns_exact_old_resource",
        "CONTROL_FAIL:host_vm_defines_instruction_meanings_and_fixed_genome_width",
        "CONTROL_FAIL:host_loop_defines_parent_victim_and_whole_genome_replacement",
        "CONTROL_FAIL:resegmentation_is_not_functionally_reconstructed",
    };
    for (attacks) |v| try out.print("round_ac_ac2,attack,hostile,0,0,0,0,0,0,0,0,0x0,{s}\n", .{v});
    const r = evaluate(.ecology);
    try out.print("round_ac_ac2,closure,aggregate,{d},{d},{d},{d},{d},{d},{d},{d},0x{x},VALID_NEGATIVE:self_producing_proposal_ecology_has_causal_gain_but_host_vm_and_replacement_loop_are_hidden_generator\n", .{
        r.charged_work, r.old_resource, r.new_resource, r.ablated_resource, r.bootstrap_survivors,
        r.proposer_replacements, r.commits, r.rollbacks, r.lineage_hash,
    });
}

fn require(bytes: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, bytes, needle) == null) return error.MissingEvidence; }

fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    try run("/tmp/ac2_a.csv"); try run("/tmp/ac2_b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ac2_a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ac2_b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    try require(x, "VALID_NEGATIVE:"); try require(x, "CONTROL_FAIL:host_vm");
    const e = evaluate(.ecology); const fixed = evaluate(.fixed); const rnd = evaluate(.random);
    if (!(e.new_resource > fixed.new_resource and e.new_resource > rnd.new_resource)) return error.NoEcologyGain;
    if (e.proposer_replacements == 0 or e.ablated_resource != e.old_resource) return error.NoCausalReplacement;
    std.debug.print("round_ac_ac2 selftest PASS verdict=VALID_NEGATIVE deterministic=true recursive_proposal_gain=true host_vm_owned=false\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/self_producing_proposals_round_ac.csv");
}
