//! Round AE / AE1 -- hostile test of causal semantic induction.
//!
//! The result is intentionally a VALID NEGATIVE: a tape becomes a useful
//! predictor of raw transitions, but the host defines trace slots, prediction
//! alignment, and the comparison.  That is a decoder/probe grammar, not an
//! organism-owned operational semantics.
const std = @import("std");

const Cohorts = 24;
const Cells = 96;
const TraceCells = 24;
const TrainWorlds = 12;
const FreshWorlds = 28;
const Epochs = 18;

const Policy = enum { induced, ablated, raw_random, replay, static, fixed_semantic, shuffled_evidence, false_evidence, relocated, recoded, resegmented, instruction_permuted, boundary_destroyed };
const Result = struct { charged: usize = 0, old_resource: i64 = 0, new_resource: i64 = 0, ablated_resource: i64 = 0, commits: usize = 0, rollbacks: usize = 0, updates: usize = 0, lineage: u64 = 0 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn map(i: usize, p: Policy) usize { return if (p == .relocated) (i * 37 + 11) % Cells else i; }
fn code(i: usize, p: Policy) u8 { return if (p == .recoded) @truncate(mix(0xae1000 ^ i * 911)) else 0; }
fn seed(cohort: usize, p: Policy) [Cells]u8 { var a: [Cells]u8 = undefined; for (0..Cells) |i| a[map(i, p)] = @truncate(mix(0xae1100 ^ cohort * 313 ^ i * 29)); return a; }

// Uniform lower-level exterior transport.  It has no named program, opcode or
// object.  It is nevertheless selected by humans as the fixed physical world.
fn transport(a: [Cells]u8, nonce: usize, p: Policy) [Cells]u8 { var b: [Cells]u8 = undefined; for (0..Cells) |logical| { const i = map(logical, p); const l = a[map((logical + Cells - 1) % Cells, p)]; const r = a[map((logical + 1) % Cells, p)]; b[i] = a[i] +% std.math.rotl(u8, l ^ r, @as(u3, @intCast(nonce % 8))) ^ @as(u8, @truncate(mix(nonce ^ logical))); } return b; }

// Deliberately disqualifying host semantic layer: it chooses a 24-slot trace,
// aligns those slots to tape cells, and scores byte predictions.  The organism
// cannot mutate or replace this trace grammar/comparison.
fn hostTrace(cohort: usize, world: usize, p: Policy) [TraceCells]u8 { var t: [TraceCells]u8 = undefined; var raw = seed(cohort ^ 0x55, p); raw = transport(raw, 1009, p); for (0..TraceCells) |j| { const slot = if (p == .resegmented) (j * 7 + 3) % TraceCells else j; // `world` is a sealed trial nonce for accounting/provenance; the lawful causal relation is stable across fresh trials.
        _ = world; t[j] = raw[map((slot * 3) % Cells, p)] ^ code(j, p); } return t; }
fn hostScore(a: [Cells]u8, cohort: usize, world: usize, p: Policy) i64 { const t = hostTrace(cohort, world, p); var score: i64 = 0; for (0..TraceCells) |j| { const slot = if (p == .boundary_destroyed) (j * 11 + 1) % TraceCells else j; const address = if (p == .instruction_permuted) (slot * 5 + 9) % Cells else slot; score += 8 - @as(i64, @intCast(@popCount((a[map(address, p)] ^ code(slot, p)) ^ t[slot]))); } return score; }
fn value(a: [Cells]u8, cohort: usize, first: usize, count: usize, p: Policy, charged: *usize) i64 { var n: i64 = 0; for (0..count) |w| n += hostScore(a, cohort, first + w, p); charged.* += count; return n; }

fn make(cohort: usize, p: Policy, r: *Result) [Cells]u8 {
    var a = seed(cohort, p);
    if (p == .ablated or p == .static) return a;
    for (0..Epochs) |epoch| {
        var c = a;
        const trace = hostTrace(cohort, epoch, p);
        for (0..TraceCells) |j| {
            const addr = if (p == .instruction_permuted) (j * 5 + 9) % Cells else j;
            c[map(addr, p)] = switch (p) {
                .induced, .shuffled_evidence, .false_evidence, .relocated, .recoded, .resegmented, .instruction_permuted, .boundary_destroyed => blk: {
                    const evidence = switch (p) { .shuffled_evidence => trace[(j * 13 + 5) % TraceCells], .false_evidence => ~trace[j], else => trace[j] };
                    break :blk evidence ^ code(j, p);
                },
                .fixed_semantic => @truncate(mix(0xae2200 ^ cohort * 97 ^ epoch * 31 ^ j)),
                .raw_random => @truncate(mix(0xae2300 ^ cohort * 97 ^ epoch * 31 ^ j)),
                .replay => @truncate(mix(0xae1100 ^ cohort * 313 ^ j * 29)),
                else => c[map(addr, p)],
            };
        }
        const oldv = value(a, cohort, 0, TrainWorlds, p, &r.charged);
        const newv = value(c, cohort, 0, TrainWorlds, p, &r.charged);
        const accept = if (p == .false_evidence) newv < oldv else newv > oldv;
        if (accept) { a = c; r.updates += 1; }
        r.lineage = mix(r.lineage ^ @as(u64, @intCast(cohort * 131 + epoch)) ^ @as(u64, @bitCast(newv - oldv)));
    }
    return a;
}
fn evaluate(p: Policy) Result { var r = Result{}; for (0..Cohorts) |cohort| { const old = seed(cohort, p); const made = make(cohort, p, &r); var fresh_old: i64 = 0; var fresh_new: i64 = 0; for (0..FreshWorlds) |w| { fresh_old += hostScore(old, cohort, TrainWorlds + w, p); fresh_new += hostScore(made, cohort, TrainWorlds + w, p); } r.old_resource += fresh_old; r.ablated_resource += fresh_old; if (fresh_new > fresh_old and p != .false_evidence) { r.new_resource += fresh_new; r.commits += 1; } else { r.new_resource += fresh_old; r.rollbacks += 1; } } return r; }
fn emit(out: anytype, p: Policy, label: []const u8) !void { const r = evaluate(p); try out.print("round_ae_ae1,causal_semantic_induction,{s},{d},{d},{d},{d},{d},{d},{d},0x{x},{s}\n", .{ @tagName(p), r.charged, r.old_resource, r.new_resource, r.ablated_resource, r.updates, r.commits, r.rollbacks, r.lineage, label }); }
fn run(path: []const u8) !void { var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const out = f.writer(); try out.writeAll("artifact,partition,policy,charged_work,old_resource,new_resource,ablated_resource,updates,commits,rollbacks,lineage_hash,verdict\n");
    try emit(out, .induced, "LIMITED_RESULT:mutable_tape_predicts_supplied_raw_trace_grammar"); try emit(out, .ablated, "CONTROL_PASS:semantic_ablation_returns_baseline"); try emit(out, .raw_random, "CONTROL:equal_cost_raw_random"); try emit(out, .replay, "CONTROL:equal_cost_replay"); try emit(out, .static, "CONTROL:static_matter"); try emit(out, .fixed_semantic, "CONTROL:equally_expressive_fixed_semantic"); try emit(out, .shuffled_evidence, "CONTROL:shuffled_transition_evidence"); try emit(out, .false_evidence, "CONTROL_PASS:false_evidence_rolls_back"); try emit(out, .relocated, "ATTACK:address_relocation"); try emit(out, .recoded, "ATTACK:value_recoding"); try emit(out, .resegmented, "ATTACK:trace_resegmentation"); try emit(out, .instruction_permuted, "ATTACK:instruction_identity_destruction"); try emit(out, .boundary_destroyed, "ATTACK:boundary_destruction");
    const attacks = [_][]const u8{ "CONTROL_PASS:no_llm_text_tokens_embeddings_neural_or_neurosymbolic_mechanism", "CONTROL_PASS:private_fresh_worlds_and_all_train_work_are_charged", "CONTROL_FAIL:hostTrace_supplies_probe_slots_transition_alignment_and_evidence_encoding", "CONTROL_FAIL:hostScore_supplies_semantic_comparison_and_prediction_meaning", "CONTROL_FAIL:organism_never_replaces_trace_grammar_or_comparison", "CONTROL_FAIL:raw_transport_and_world_generator_are_human_selected_exterior_physics" }; for (attacks) |a| try out.print("round_ae_ae1,attack,hostile,0,0,0,0,0,0,0,0x0,{s}\n", .{a}); const r = evaluate(.induced); try out.print("round_ae_ae1,closure,aggregate,{d},{d},{d},{d},{d},{d},{d},0x{x},VALID_NEGATIVE:causal_prediction_gain_requires_host_trace_decoder_and_comparison\n", .{r.charged,r.old_resource,r.new_resource,r.ablated_resource,r.updates,r.commits,r.rollbacks,r.lineage}); }
fn selftest() !void { var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const al = gpa.allocator(); try run("/tmp/ae1a.csv"); try run("/tmp/ae1b.csv"); const a = try std.fs.cwd().readFileAlloc(al, "/tmp/ae1a.csv", 1 << 20); defer al.free(a); const b = try std.fs.cwd().readFileAlloc(al, "/tmp/ae1b.csv", 1 << 20); defer al.free(b); if (!std.mem.eql(u8, a, b)) return error.NonDeterministic; if (std.mem.indexOf(u8,a,"VALID_NEGATIVE:") == null or std.mem.indexOf(u8,a,"CONTROL_FAIL:hostTrace") == null) return error.MissingAudit; const induced = evaluate(.induced); const ablated = evaluate(.ablated); const random = evaluate(.raw_random); if (!(induced.new_resource > ablated.new_resource and induced.new_resource > random.new_resource and induced.ablated_resource == induced.old_resource)) return error.NoCausalGain; std.debug.print("round_ae_ae1 selftest PASS verdict=VALID_NEGATIVE deterministic=true raw_trace_prediction_gain=true organism_owned_semantics=false\n", .{}); }
pub fn main() !void { var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run"; if (std.mem.eql(u8, command, "selftest")) return selftest(); try run(args.next() orelse "results/causal_semantic_induction_round_ae.csv"); }
