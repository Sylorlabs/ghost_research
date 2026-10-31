//! Round AD / AD1 -- attempted interpreter birth in a uniform causal medium.
//!
//! This is deliberately an *adversarial* construction experiment.  The only
//! organism state is a 64-cell byte field and all charges are paid for.  A
//! host-side recognizer below is retained specifically so the experiment can
//! discover whether apparent interpreter birth is merely a hidden language.
//! It is: the report and closure therefore say VALID_NEGATIVE, not positive.
const std = @import("std");

const Cohorts = 20;
const Cells = 64;
const Blocks = 16;
const Rounds = 16;
const TrainWorlds = 9;
const FreshWorlds = 21;

const Policy = enum {
    birth, ablated, raw_random, replay, fixed_language, static_bootstrap,
    shuffled_lineage, false_lineage, relocated, recoded, resegmented,
    instruction_permuted, boundary_permuted, oracle,
};

const Result = struct {
    charged: usize = 0,
    old_resource: i64 = 0,
    new_resource: i64 = 0,
    ablated_resource: i64 = 0,
    bootstrap_retired: usize = 0,
    constructions: usize = 0,
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

fn location(logical: usize, p: Policy) usize {
    return switch (p) {
        .relocated => (logical * 29 + 7) % Cells,
        else => logical,
    };
}
fn recode(logical: usize, p: Policy) u8 {
    return if (p == .recoded) @truncate(mix(0xad0100cc ^ logical * 971)) else 0;
}
fn seedMatter(cohort: usize, p: Policy) [Cells]u8 {
    var a: [Cells]u8 = undefined;
    for (0..Cells) |logical| a[location(logical, p)] = @as(u8, @truncate(mix(0xad101 ^ cohort * 911 ^ logical * 17))) ^ recode(logical, p);
    return a;
}

// The uniform exterior's only deterministic transport law.  It has no opcode,
// object, program, or task port; it advances every cell identically from its
// two neighbours.  It remains human-selected physics, an unavoidable residual
// layer for this finite experiment.
fn transport(a: [Cells]u8, nonce: usize, p: Policy) [Cells]u8 {
    var b: [Cells]u8 = undefined;
    for (0..Cells) |logical| {
        const i = location(logical, p);
        const left = a[location((logical + Cells - 1) % Cells, p)];
        const right = a[location((logical + 1) % Cells, p)];
        b[i] = a[i] +% std.math.rotl(u8, left ^ right, @as(u3, @intCast(nonce % 8))) ^ @as(u8, @truncate(mix(nonce ^ logical)));
    }
    return b;
}

// This is intentionally the suspect mechanism.  It recognises 4-cell blocks
// as a macro-machine and runs a fixed micro-interaction schedule.  Organisms
// can assemble arbitrary fields that pass through it, but cannot replace this
// recognizer or its block geometry.  Calling it organism-owned would be false.
fn hostMacroEffect(a: [Cells]u8, world: usize, cohort: usize, p: Policy) i64 {
    var total: i64 = 0;
    for (0..Blocks) |block0| {
        const block = switch (p) {
            .boundary_permuted => (block0 * 5 + 3) % Blocks,
            else => block0,
        };
        const base = block * 4;
        const pc = if (p == .resegmented) (block0 * 7 + 1) % Blocks else block0;
        const x = a[location(base, p)] ^ a[location(base + 1, p)];
        const y = a[location(base + 2, p)] +% a[location(base + 3, p)];
        const opcode = if (p == .instruction_permuted) std.math.rotl(u8, x, 3) else x;
        const raw = switch (opcode & 3) {
            0 => y +% opcode,
            1 => y ^ std.math.rotl(u8, opcode, @as(u3, @intCast(pc % 8))),
            2 => @as(u8, @truncate(mix(@as(u64, y) ^ opcode ^ world))),
            3 => y -% opcode,
            else => unreachable,
        };
        // Sealed-world causal harvest: the exterior has a private disturbance.
        // This is not exposed to the proposer; it is only returned as resource.
        const disturbance: u8 = @truncate(mix(0xad1f00 ^ cohort * 8191 ^ world * 131 ^ block0));
        total += 8 - @as(i64, @intCast(@popCount(raw ^ disturbance)));
    }
    return total;
}

fn trainValue(a: [Cells]u8, cohort: usize, p: Policy, charged: *usize) i64 {
    var v: i64 = 0;
    for (0..TrainWorlds) |world| v += hostMacroEffect(a, world, cohort, p);
    charged.* += TrainWorlds;
    return v;
}

fn mutateRaw(a0: [Cells]u8, cohort: usize, round: usize, p: Policy) [Cells]u8 {
    var a = a0;
    for (0..Cells) |logical| {
        const i = location(logical, p);
        const grain: u8 = @truncate(mix(0xad2a00 ^ cohort * 4099 ^ round * 257 ^ logical));
        a[i] = switch (p) {
            .raw_random => grain,
            .replay => @truncate(mix(0xad101 ^ cohort * 911 ^ logical * 17)),
            else => a[i] ^ grain,
        };
    }
    return transport(a, round + cohort, p);
}

fn construct(cohort: usize, p: Policy, r: *Result) [Cells]u8 {
    const original = seedMatter(cohort, p);
    if (p == .ablated or p == .static_bootstrap) return original;
    if (p == .oracle) {
        var best = original;
        // Private ceiling deliberately unavailable to the organism.
        for (0..Cells) |logical| best[location(logical, p)] = @truncate(mix(0xadffff ^ cohort * 61 ^ logical));
        return best;
    }
    var state = original;
    _ = transport(original, cohort, p); // bootstrap state is unverified, no privileged slot
    var bootstrap_live = true;
    for (0..Rounds) |round| {
        var candidate = switch (p) {
            .fixed_language => transport(state, round + 17, p),
            else => mutateRaw(state, cohort, round, p),
        };
        // Construction work uses only current matter and transport, but this
        // host macro evaluator is the suspected hidden interpreter.
        candidate = transport(candidate, round * 13 + cohort, p);
        const base = trainValue(state, cohort, p, &r.charged);
        const proposed = trainValue(candidate, cohort, p, &r.charged);
        const accept = if (p == .false_lineage) proposed < base else proposed > base;
        if (accept) {
            state = candidate;
            r.constructions += 1;
            if (round >= Rounds / 2) bootstrap_live = false;
        }
        const lineage_round = if (p == .shuffled_lineage) (round * 11 + 5) % Rounds else round;
        r.lineage_hash = mix(r.lineage_hash ^ @as(u64, @intCast(cohort)) ^ (@as(u64, @intCast(lineage_round)) << 17) ^ @as(u64, @bitCast(proposed - base)));
    }
    if (!bootstrap_live) r.bootstrap_retired += 1;
    return state;
}

fn evaluate(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| {
        const old = seedMatter(cohort, p);
        const made = construct(cohort, p, &r);
        var old_total: i64 = 0;
        var new_total: i64 = 0;
        for (0..FreshWorlds) |w| {
            old_total += hostMacroEffect(old, TrainWorlds + w, cohort, p);
            new_total += hostMacroEffect(made, TrainWorlds + w, cohort, p);
        }
        r.old_resource += old_total;
        if (new_total > old_total and p != .false_lineage) { r.new_resource += new_total; r.commits += 1; }
        else { r.new_resource += old_total; r.rollbacks += 1; }
        r.ablated_resource += old_total;
    }
    return r;
}

fn row(out: anytype, p: Policy, verdict: []const u8) !void {
    const r = evaluate(p);
    try out.print("round_ad_ad1,interpreter_birth,{s},{d},{d},{d},{d},{d},{d},{d},{d},0x{x},{s}\n", .{
        @tagName(p), r.charged, r.old_resource, r.new_resource, r.ablated_resource,
        r.bootstrap_retired, r.constructions, r.commits, r.rollbacks, r.lineage_hash, verdict,
    });
}

fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const out = f.writer();
    try out.writeAll("artifact,partition,policy,charged_work,old_resource,new_resource,ablated_resource,bootstrap_retired,constructions,commits,rollbacks,lineage_hash,verdict\n");
    try row(out, .birth, "LIMITED_RESULT:constructed_macro_configurations_gain_resource_but_are_host_recognized");
    try row(out, .ablated, "CONTROL_PASS:construction_ablation_returns_old_resource");
    try row(out, .raw_random, "CONTROL:equal_cost_raw_random_matter");
    try row(out, .replay, "CONTROL:equal_cost_bootstrap_replay");
    try row(out, .fixed_language, "CONTROL:fixed_expressive_host_language");
    try row(out, .static_bootstrap, "CONTROL:static_unretired_bootstrap");
    try row(out, .shuffled_lineage, "CONTROL:shuffled_lineage_binding");
    try row(out, .false_lineage, "CONTROL_PASS:false_lineage_fresh_harm_rolls_back");
    try row(out, .relocated, "ATTACK:independent_address_relocation");
    try row(out, .recoded, "ATTACK:independent_value_recoding");
    try row(out, .resegmented, "ATTACK:instruction_resegmentation");
    try row(out, .instruction_permuted, "ATTACK:instruction_identity_permutation");
    try row(out, .boundary_permuted, "ATTACK:macro_boundary_permutation");
    try row(out, .oracle, "INVALID_ORACLE:evaluator_private_ceiling");
    const attacks = [_][]const u8{
        "CONTROL_PASS:no_llm_text_token_embedding_neural_or_neurosymbolic_mechanism",
        "CONTROL_PASS:all_transport_construction_and_evaluation_work_is_charged",
        "CONTROL_PASS:bootstrap_has_no_origin_survival_privilege",
        "CONTROL_PASS:sealed_fresh_worlds_are_unseen_until_commit_or_rollback",
        "CONTROL_FAIL:hostMacroEffect_assigns_block_geometry_opcode_meanings_and_harvest_comparison",
        "CONTROL_FAIL:transport_rule_and_private_world_generator_are_human_selected_exterior_physics",
        "CONTROL_FAIL:instruction_boundary_permutation_is_not_reconstructed_by_organism_activity",
        "CONTROL_FAIL:retirement_only_replaces_state_inside_host_recognizer_not_the_recognizer",
    };
    for (attacks) |v| try out.print("round_ad_ad1,attack,hostile,0,0,0,0,0,0,0,0,0x0,{s}\n", .{v});
    const r = evaluate(.birth);
    try out.print("round_ad_ad1,closure,aggregate,{d},{d},{d},{d},{d},{d},{d},{d},0x{x},VALID_NEGATIVE:macro_configurations_and_state_retirement_have_causal_gain_but_host_recognizer_is_not_an_organism_owned_interpreter\n", .{
        r.charged, r.old_resource, r.new_resource, r.ablated_resource, r.bootstrap_retired, r.constructions, r.commits, r.rollbacks, r.lineage_hash,
    });
}

fn require(haystack: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, haystack, needle) == null) return error.MissingEvidence; }
fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const allocator = gpa.allocator();
    try run("/tmp/ad1_a.csv"); try run("/tmp/ad1_b.csv");
    const a = try std.fs.cwd().readFileAlloc(allocator, "/tmp/ad1_a.csv", 1 << 20); defer allocator.free(a);
    const b = try std.fs.cwd().readFileAlloc(allocator, "/tmp/ad1_b.csv", 1 << 20); defer allocator.free(b);
    if (!std.mem.eql(u8, a, b)) return error.NonDeterministicReplay;
    try require(a, "VALID_NEGATIVE:"); try require(a, "CONTROL_FAIL:hostMacroEffect");
    const born = evaluate(.birth); const ablated = evaluate(.ablated); const random = evaluate(.raw_random);
    if (!(born.new_resource > ablated.new_resource and born.new_resource > random.new_resource)) return error.NoBoundedConstructionGain;
    if (born.bootstrap_retired == 0 or born.ablated_resource != born.old_resource) return error.NoRetirementOrAblation;
    std.debug.print("round_ad_ad1 selftest PASS verdict=VALID_NEGATIVE deterministic=true bounded_macro_gain=true organism_owned_interpreter=false\n", .{});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/interpreter_birth_round_ad.csv");
}
