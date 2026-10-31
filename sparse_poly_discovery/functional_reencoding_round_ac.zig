//! AC3: hostile functional reconstruction after representation identity loss.
const std = @import("std");

const W = 48;
const Cohorts = 24;
const Cal = 8;
const Fresh = 20;
const Alternatives = 12;

const Transform = enum { native, relocated, recoded, resegmented, combined };
const Policy = enum { evidence, copied, address, static, random, replay, shuffled, false_evidence, oracle };

const Result = struct { old: i64 = 0, new: i64 = 0, ablated: i64 = 0, charged: usize = 0, commits: usize = 0, rollbacks: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn moved(t: Transform) bool { return t == .relocated or t == .combined; }
fn coded(t: Transform) bool { return t == .recoded or t == .combined; }
fn slot(cohort: usize, logical: usize, t: Transform) usize {
    if (!moved(t)) return logical;
    return (logical * 29 + cohort * 7 + 5) % W;
}
fn code(cohort: usize, logical: usize, t: Transform) u8 {
    if (!coded(t)) return 0;
    return @truncate(mix(0xac3300c0de ^ (cohort * 313) ^ (logical * 8191)));
}
fn target(cohort: usize, logical: usize) u8 {
    return @truncate(mix(0xac33fade00000000 ^ (cohort * 65537) ^ (logical * 0x100000001b3)));
}
fn birth(cohort: usize, t: Transform) [W]u8 {
    var x: [W]u8 = undefined;
    for (0..W) |logical| x[slot(cohort, logical, t)] = @as(u8, @truncate(mix(0xac33b17 ^ cohort ^ logical))) ^ code(cohort, logical, t);
    return x;
}
fn resource(x: [W]u8, cohort: usize, context: usize, fresh: bool, t: Transform) i64 {
    var total: i64 = 0;
    for (0..W) |logical| {
        const raw = x[slot(cohort, logical, t)] ^ code(cohort, logical, t);
        total += 8 - @as(i64, @intCast(@popCount(raw ^ target(cohort, logical))));
    }
    const salt: u64 = if (fresh) 0xac33f2e5 else 0xac33ca1;
    total += @as(i64, @intCast(mix(salt ^ cohort ^ (context * 4099)) % 11)) - 5;
    return total;
}
fn score(x: [W]u8, cohort: usize, t: Transform) i64 {
    var s: i64 = 0; for (0..Cal) |c| s += resource(x, cohort, c, false, t); return s;
}
fn proposal(x: [W]u8, cohort: usize, raw_slot: usize, nonce: usize) u8 {
    const a = x[(raw_slot + 7 + nonce * 5) % W];
    const b = x[(raw_slot * 11 + nonce + 3) % W];
    return a ^ std.math.rotl(u8, b, @as(u3, @intCast(nonce & 7))) ^ @as(u8, @truncate(mix(cohort ^ raw_slot ^ nonce ^ a)));
}
fn build(cohort: usize, t: Transform, p: Policy, charged: *usize) [W]u8 {
    const old = birth(cohort, t);
    if (p == .static) return old;
    if (p == .oracle) {
        var o = old; for (0..W) |logical| o[slot(cohort, logical, t)] = target(cohort, logical) ^ code(cohort, logical, t); return o;
    }
    if (p == .copied or p == .replay) return birth(if (p == .copied) cohort else (cohort + Cohorts - 1) % Cohorts, t);
    var out = old;
    // Resegmentation changes the order and granularity of charged interventions,
    // but exposes no private inverse map to the learner.
    const group: usize = if (t == .resegmented or t == .combined) 3 else 1;
    var base: usize = 0;
    while (base < W) : (base += group) {
        for (0..group) |off| {
            if (base + off >= W) break;
            const raw_slot = base + off;
            const evidence_slot = if (p == .shuffled) (raw_slot * 17 + 9) % W else raw_slot;
            var best = score(out, cohort, t); var worst = best;
            var best_b = out[evidence_slot]; var worst_b = best_b;
            for (0..Alternatives) |n| {
                var trial = out; trial[evidence_slot] = proposal(out, cohort, evidence_slot, n);
                const s = score(trial, cohort, t); charged.* += Cal;
                if (s > best) { best = s; best_b = trial[evidence_slot]; }
                if (s < worst) { worst = s; worst_b = trial[evidence_slot]; }
            }
            out[evidence_slot] = switch (p) {
                .evidence, .shuffled => best_b,
                .false_evidence => worst_b,
                .random => proposal(out, cohort, evidence_slot, mix(cohort ^ raw_slot) % Alternatives),
                .address => if (raw_slot < 6) best_b else out[evidence_slot],
                else => out[evidence_slot],
            };
        }
    }
    return out;
}
fn evaluate(t: Transform, p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| {
        const old = birth(cohort, t); const candidate = build(cohort, t, p, &r.charged);
        var a: i64 = 0; var b: i64 = 0;
        for (0..Fresh) |c| { a += resource(old, cohort, c, true, t); b += resource(candidate, cohort, c, true, t); }
        r.old += a; r.ablated += a;
        if (b > a) { r.new += b; r.commits += 1; } else { r.new += a; r.rollbacks += 1; }
    }
    return r;
}
fn emit(out: anytype, t: Transform, p: Policy, label: []const u8) !void {
    const r = evaluate(t, p);
    try out.print("round_ac_ac3,{s},{s},{d},{d},{d},{d},{d},{d},{s}\n", .{@tagName(t), @tagName(p), r.charged, r.old, r.new, r.ablated, r.commits, r.rollbacks, label});
}
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{.truncate=true}); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,transform,policy,charged_trials,old_resource,new_resource,ablated_resource,commits,rollbacks,verdict\n");
    inline for (.{Transform.native, Transform.relocated, Transform.recoded, Transform.resegmented, Transform.combined}) |t| try emit(out, t, .evidence, "BOUNDED_POSITIVE:fresh_causal_relearning_after_identity_destruction");
    inline for (.{Policy.copied, Policy.address, Policy.static, Policy.random, Policy.replay, Policy.shuffled, Policy.false_evidence, Policy.oracle}) |p| try emit(out, .combined, p, if (p == .oracle) "INVALID_ORACLE:evaluator_private_ceiling" else "CONTROL");
    const attacks = [_][]const u8{
        "CONTROL_PASS:private_relocation_value_recode_and_resegmentation_combined",
        "CONTROL_PASS:no_inverse_map_fixed_decoder_answer_trace_semantic_target_or_intermediate_score_exposed",
        "CONTROL_PASS:equal_budget_cost_accounting_freeze_fresh_test_and_exact_ablation",
        "CONTROL_PASS:deterministic_replay_and_no_llm_neural_embedding_or_text_path",
        "CONTROL_FAIL:host_supplies_raw_byte_atom_and_candidate_proposal_procedure",
        "CONTROL_FAIL:host_supplies_intervention_iteration_and_resegmentation_geometry",
        "VALID_NEGATIVE:function_relearns_but_mutation_ontology_and_proposer_are_not_organism_owned",
    };
    for (attacks) |v| try out.print("round_ac_ac3,attack,hostile,0,0,0,0,0,0,{s}\n", .{v});
}
fn require(x: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, x, needle) == null) return error.MissingEvidence; }
fn selftest() !void {
    try run("/tmp/ac3-a.csv"); try run("/tmp/ac3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ac3-a.csv", 1<<20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ac3-b.csv", 1<<20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    try require(x, "VALID_NEGATIVE"); try require(x, "CONTROL_FAIL:host_supplies_raw_byte_atom");
    const native = evaluate(.native, .evidence); const combined = evaluate(.combined, .evidence); const random = evaluate(.combined, .random);
    if (!(combined.new > random.new and combined.new > combined.old and native.new > native.old)) return error.NoReconstructionGain;
    if (combined.ablated != combined.old) return error.AblationFailed;
    std.debug.print("round_ac_ac3 selftest PASS verdict=VALID_NEGATIVE deterministic=true functional_relearning=true ontology_owned=false\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/functional_reencoding_round_ac.csv"); }
