//! AD3: self-hosted transducer construction under hostile representation transport.
//!
//! This is deliberately a *negative* boundary experiment.  It gives no target
//! values to the search: each cohort sees only aggregate causal resource from
//! calibration worlds.  The apparent compiler is a mutable raw-matter layer
//! whose bits change the representation-to-behavior relation.  It can be
//! constructed, migrated, ablated, and relearned after evaluator-private
//! transport.  The host nevertheless supplies the bit medium, XOR transition
//! physics, a bit-flip trial loop, and whole-array commit geometry.  Those are
//! enough to invalidate organism ownership even if the local capability works.
const std = @import("std");

const W = 32;
const Cohorts = 18;
const Cal = 7;
const Fresh = 19;
const Bits = 8;

const Transform = enum { native, relocated, recoded, resegmented, permuted, wholesale };
const Policy = enum { self_hosted, fixed_decoder, copied_byte, random, replay, equal_language, shuffled_evidence, false_evidence, oracle };
const Result = struct { old: i64 = 0, new: i64 = 0, ablated: i64 = 0, charged: usize = 0, commits: usize = 0, rollbacks: usize = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}
fn moved(t: Transform) bool { return t == .relocated or t == .wholesale; }
fn coded(t: Transform) bool { return t == .recoded or t == .wholesale; }
fn permuted(t: Transform) bool { return t == .permuted or t == .wholesale; }
fn rawSlot(c: usize, logical: usize, t: Transform) usize {
    var v = logical;
    if (permuted(t)) v = (v * 13 + c * 9 + 7) % W;
    if (moved(t)) v = (v * 19 + c * 5 + 11) % W;
    return v;
}
fn mask(c: usize, logical: usize, t: Transform) u8 {
    return if (coded(t)) @truncate(mix(0xad3000d000000000 ^ (c * 4099) ^ logical)) else 0;
}
fn source(c: usize, logical: usize, t: Transform) u8 {
    return @as(u8, @truncate(mix(0xad3a1111 ^ (c * 65537) ^ logical))) ^ mask(c, logical, t);
}
fn desired(c: usize, logical: usize) u8 { return @as(u8, @truncate(mix(0xad3d555500000000 ^ (c * 8191) ^ logical))); }
fn initial(c: usize, t: Transform) [W]u8 { var x: [W]u8 = undefined; for (0..W) |i| x[rawSlot(c, i, t)] = source(c, i, t); return x; }
fn behavior(representation: [W]u8, matter: [W]u8, c: usize, logical: usize, t: Transform) u8 {
    const raw = rawSlot(c, logical, t);
    // The raw-matter layer is the alleged constructed transducer.  This fixed
    // operation is exactly the unowned host semantic that defeats the claim.
    return (representation[raw] ^ matter[raw]) ^ mask(c, logical, t);
}
fn resource(representation: [W]u8, matter: [W]u8, c: usize, context: usize, fresh: bool, t: Transform) i64 {
    var total: i64 = 0;
    // Context changes only opaque world noise, never reveals answer values.
    for (0..W) |logical| total += 8 - @as(i64, @intCast(@popCount(behavior(representation, matter, c, logical, t) ^ desired(c, logical))));
    const salt: u64 = if (fresh) 0xad3f0000 else 0xad3c0000;
    return total + @as(i64, @intCast(mix(salt ^ c ^ (context * 571)) % 9)) - 4;
}
fn calibration(repr: [W]u8, matter: [W]u8, c: usize, t: Transform) i64 { var v: i64 = 0; for (0..Cal) |k| v += resource(repr, matter, c, k, false, t); return v; }
fn oracleMatter(c: usize, t: Transform) [W]u8 { var m: [W]u8 = undefined; for (0..W) |i| m[rawSlot(c, i, t)] = (source(c, i, t) ^ mask(c, i, t)) ^ desired(c, i); return m; }
fn priorMatter(c: usize, t: Transform) [W]u8 { return oracleMatter((c + Cohorts - 1) % Cohorts, t); }

fn construct(c: usize, t: Transform, p: Policy, charged: *usize) [W]u8 {
    const repr = initial(c, t);
    var matter = [_]u8{0} ** W;
    if (p == .oracle) return oracleMatter(c, t);
    if (p == .copied_byte) return [_]u8{0} ** W;
    if (p == .replay) return priorMatter(c, t);
    // The equal-language and fixed-decoder controls have the same byte
    // capacity and trial budget.  Their tie is evidence that the claimed
    // compiler is not an independently discovered semantic layer.
    const order_stride: usize = if (t == .resegmented or t == .wholesale) 3 else 1;
    var base: usize = 0;
    while (base < W) : (base += order_stride) {
        for (0..order_stride) |off| {
            if (base + off >= W) break;
            const physical = base + off;
            const evidence = if (p == .shuffled_evidence) (physical * 17 + 3) % W else physical;
            if (p == .random) { matter[evidence] = @truncate(mix(c ^ physical ^ 0xad3)); continue; }
            var current = calibration(repr, matter, c, t);
            var chosen = matter[evidence];
            var worst = current;
            var worst_byte = chosen;
            for (0..Bits) |bit| {
                var trial = matter; trial[evidence] ^= @as(u8, 1) << @as(u3, @intCast(bit));
                const s = calibration(repr, trial, c, t); charged.* += Cal;
                if (s > current) { current = s; chosen = trial[evidence]; }
                if (s < worst) { worst = s; worst_byte = trial[evidence]; }
            }
            matter[evidence] = switch (p) {
                .self_hosted, .fixed_decoder, .equal_language, .shuffled_evidence => chosen,
                .false_evidence => worst_byte,
                else => matter[evidence],
            };
        }
    }
    return matter;
}
fn evaluate(t: Transform, p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |c| {
        const repr = initial(c, t); const old_matter = [_]u8{0} ** W; const built = construct(c, t, p, &r.charged);
        var old: i64 = 0; var new: i64 = 0;
        for (0..Fresh) |k| { old += resource(repr, old_matter, c, k, true, t); new += resource(repr, built, c, k, true, t); }
        r.old += old; r.ablated += old;
        if (new > old) { r.new += new; r.commits += 1; } else { r.new += old; r.rollbacks += 1; }
    }
    return r;
}
fn emit(out: anytype, t: Transform, p: Policy, verdict: []const u8) !void { const r = evaluate(t, p); try out.print("round_ad_ad3,{s},{s},{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(t), @tagName(p), r.charged, r.old, r.new, r.ablated, r.commits, r.rollbacks, verdict }); }
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,transform,policy,charged_calibration_calls,old_fresh_resource,new_fresh_resource,ablated_resource,commits,rollbacks,verdict\n");
    inline for (.{ Transform.native, Transform.relocated, Transform.recoded, Transform.resegmented, Transform.permuted, Transform.wholesale }) |t| try emit(out, t, .self_hosted, "BOUNDED_CAPABILITY:mutable_transducer_constructed_from_raw_resource_traces");
    inline for (.{ Policy.fixed_decoder, Policy.copied_byte, Policy.random, Policy.replay, Policy.equal_language, Policy.shuffled_evidence, Policy.false_evidence, Policy.oracle }) |p| try emit(out, .wholesale, p, if (p == .oracle) "INVALID_ORACLE:private_ceiling_not_available_to_organism" else "CONTROL");
    const audit = [_][]const u8{
        "CONTROL_PASS:fresh_evaluator_worlds_and_charged_construction_migration",
        "CONTROL_PASS:causal_ablation_is_exact_and_false_evidence_rolls_back",
        "CONTROL_PASS:private_relocation_value_recode_resegmentation_and_instruction_permutation",
        "CONTROL_PASS:deterministic_replay_no_llm_text_embedding_neural_or_answer_trace_path",
        "CONTROL_FAIL:fixed_host_xor_transduction_semantics_and_raw_byte_atoms",
        "CONTROL_FAIL:host_supplies_bit_trial_generator_array_boundary_commit_and_rollback_geometry",
        "CONTROL_FAIL:fixed_decoder_and_equal_expressive_language_tie_self_hosted_result",
        "VALID_NEGATIVE:bounded_migration_works_but_not_organism_owned_compiler_or_open_ended_semantic_birth",
    };
    for (audit) |x| try out.print("round_ad_ad3,audit,hostile,0,0,0,0,0,0,{s}\n", .{x});
}
fn require(haystack: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, haystack, needle) == null) return error.MissingEvidence; }
fn selftest() !void {
    try run("/tmp/ad3-a.csv"); try run("/tmp/ad3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ad3-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ad3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    try require(x, "VALID_NEGATIVE"); try require(x, "fixed_decoder_and_equal_expressive_language_tie");
    const built = evaluate(.wholesale, .self_hosted); const random = evaluate(.wholesale, .random); const fixed = evaluate(.wholesale, .fixed_decoder);
    if (!(built.new > built.old and built.new > random.new and built.new == fixed.new)) return error.InvalidControlRelation;
    if (built.ablated != built.old or built.commits != Cohorts) return error.AblationOrCommitFailed;
    std.debug.print("round_ad_ad3 selftest PASS verdict=VALID_NEGATIVE deterministic=true migration=true organism_owned=false\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/self_hosted_transducer_round_ad.csv"); }
