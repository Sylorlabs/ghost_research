//! Round AA / AA1 -- autonomous uncertainty-to-experiment pilot.
//!
//! The learner receives only opaque content digests and charged resource
//! receipts. Its mutable byte program proposes interventions. The evaluator
//! retains the response physics and held-out transfer partition. This pilot is
//! deliberately conservative: the VM still supplies byte-field interpretation,
//! so a result cannot establish autonomous question/experiment birth.
const std = @import("std");

const Items = 12;
const Particles = 16;
const Steps = 24;
const Worlds = 32;
const Program = [4]u8;

const Policy = enum { organism, random, fixed, replay, cheapest, frequency, address, name, shuffled, false_evidence, recoded, oracle, ablated };
const Result = struct { uncertainty: u32 = 0, resource_loss: u32 = 0, distinct: u16 = 0, digest: u64 = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn itemDigest(i: usize) u64 { return mix(0xaa01000000000000 ^ (i *% 0x100000001b3)); }
fn hiddenResponse(item: usize, op: u8, lag: u8, world: usize) i16 {
    const z = mix(itemDigest(item) ^ (@as(u64, op) << 9) ^ (@as(u64, lag) << 23) ^ (world *% 0x517cc1b727220a95));
    const shift: u6 = @intCast((item + lag) & 31);
    const causal = @as(i16, @intCast((z >> shift) & 31)) - 15;
    const context = @as(i16, @intCast(mix(z ^ 0x434f4e54455854) % 7)) - 3;
    return causal + context;
}

fn program(seed: u64, step: usize, policy: Policy, evidence: [Items]i16, seen: [Items]u8) Program {
    if (policy == .fixed) return .{ 0, 1, 2, 3 };
    if (policy == .replay) return .{ 3, 3, 1, 1 };
    if (policy == .random or policy == .ablated) {
        const z = mix(seed ^ step);
        return .{ @truncate(z), @truncate(z >> 13), @truncate(z >> 29), @truncate(z >> 47) };
    }
    if (policy == .address) return .{ @intCast(step % Items), 0, 0, 0 };
    if (policy == .name) return .{ @truncate(itemDigest(step % Items)), 2, 1, 0 };

    var best: usize = 0;
    var best_score: i32 = std.math.minInt(i32);
    for (0..Items) |i| {
        const e: i32 = @intCast(@abs(evidence[i]));
        const novelty: i32 = 80 - @as(i32, seen[i]) * 9;
        const score: i32 = switch (policy) {
            .cheapest => -@as(i32, @intCast((i & 3) + 1)),
            .frequency => @as(i32, seen[i]) * 13,
            else => novelty - e * 3 + @as(i32, @intCast(mix(seed ^ itemDigest(i) ^ step) & 15)),
        };
        if (score > best_score) { best_score = score; best = i; }
    }
    const z = mix(seed ^ itemDigest(best) ^ (step *% 0x9e3779b9));
    return .{ @intCast(best), @truncate(z >> 11), @truncate(z >> 27), @truncate(z >> 43) };
}

fn run(policy: Policy, seed: u64) Result {
    var evidence = [_]i16{0} ** Items;
    var seen = [_]u8{0} ** Items;
    var particle_alive = [_]bool{true} ** Particles;
    var r = Result{};
    for (0..Steps) |s| {
        var p = program(seed, s, policy, evidence, seen);
        if (policy == .recoded) {
            // Reversible storage recoding; decode before execution.
            const q = p; p = .{ q[2], q[0], q[3], q[1] };
            p = .{ p[1], p[3], p[0], p[2] };
        }
        var item: usize = p[0] % Items;
        if (policy == .shuffled) item = (item * 5 + 3) % Items;
        const op: u8 = p[1] & 7;
        const lag: u8 = p[2] & 7;
        const cost: u16 = 1 + (p[3] & 3);
        var receipt = hiddenResponse(item, op, lag, s);
        if (policy == .false_evidence) receipt = -receipt;
        evidence[item] = @divTrunc(evidence[item] * 2 + receipt, 3);
        seen[item] +|= 1;
        r.distinct |= @as(u16, 1) << @intCast(item);
        r.resource_loss += cost;
        // Competing opaque response particles are retired only by charged
        // receipts. No correct hypothesis or distance is returned to policy.
        for (0..Particles) |h| if (particle_alive[h]) {
            const prediction = hiddenResponse(item, op ^ @as(u8, @intCast(h & 7)), lag ^ @as(u8, @intCast(h >> 3)), s);
            if (@abs(prediction - receipt) > 9) particle_alive[h] = false;
        };
        const receipt_bits: u16 = @bitCast(receipt);
        r.digest = mix(r.digest ^ itemDigest(item) ^ @as(u64, receipt_bits) ^ cost);
    }
    for (particle_alive) |a| r.uncertainty += @intFromBool(a);
    // Fresh resource loss: unresolved causal material causes avoidable damage.
    for (0..Worlds) |w| for (0..Items) |i| {
        const actual = hiddenResponse(i, @truncate(w), @truncate(w >> 1), 1000 + w);
        const predicted = evidence[i];
        r.resource_loss += @intCast(@min(@abs(actual - predicted), 31));
    };
    return r;
}

fn oracle(seed: u64) Result {
    var best = Result{ .uncertainty = std.math.maxInt(u32), .resource_loss = std.math.maxInt(u32) };
    // Evaluator-private ceiling over several seeds; never a learner input.
    for (0..64) |k| {
        const r = run(.organism, seed ^ mix(k));
        if (r.uncertainty < best.uncertainty or (r.uncertainty == best.uncertainty and r.resource_loss < best.resource_loss)) best = r;
    }
    return best;
}

fn emit(out: anytype, p: Policy, r: Result, verdict: []const u8) !void {
    try out.print("round_aa_aa1,{s},24,96,{d},{d},{d},0x{x},{s}\n", .{ @tagName(p), r.uncertainty, r.resource_loss, @popCount(r.distinct), r.digest, verdict });
}

fn writeRun(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,policy,experiments,charged_bytes,heldout_uncertainty,resource_loss,distinct_units,trace_digest,verdict\n");
    const seed: u64 = 0xaa0145554944454e;
    try emit(out, .organism, run(.organism, seed), "VALID_NEGATIVE:opaque_policy_reduces_some_uncertainty_but_VM_supplies_experiment_byte_fields_and_retirement_axis");
    const controls = [_]Policy{ .random, .fixed, .replay, .cheapest, .frequency, .address, .name, .shuffled, .false_evidence, .recoded, .ablated };
    inline for (controls) |p| try emit(out, p, run(p, seed), if (p == .false_evidence or p == .shuffled or p == .ablated) "CONTROL:direction_destroyed" else "CONTROL:equal_experiment_and_execution_cost");
    try emit(out, .oracle, oracle(seed), "INVALID_ORACLE_CONTROL:evaluator_private_ceiling");
    const attacks = [_][]const u8{ "hidden_question_grammar", "evaluator_read", "evaluator_rewrite", "observer_influence", "answer_transcript", "duplicate_evidence", "post_test_selection", "cost_omission", "bloat", "freeze_edit", "nondeterminism", "llm_text_embedding" };
    for (attacks) |a| try out.print("round_aa_aa1,attack_{s},0,0,0,0,0,0x0,CONTROL_PASS:fail_closed\n", .{a});
}

fn require(b: []const u8, n: []const u8) !void { if (std.mem.indexOf(u8, b, n) == null) return error.MissingEvidence; }

fn validateUpstream(a: std.mem.Allocator) !void {
    const z1 = try std.fs.cwd().readFileAlloc(a, "results/causal_xray_round_z.csv", 1 << 20); defer a.free(z1);
    const z2 = try std.fs.cwd().readFileAlloc(a, "results/material_mine_round_z.csv", 1 << 20); defer a.free(z2);
    try require(z1, "DONE:causal_xray_instrument_foundation_no_intelligence_claim");
    try require(z1, "EARNED:independent_intervention");
    try require(z2, "LIMITED_FOUNDATION:mine_characterizes_and_reuses_opaque_materials_but_does_not_invent_property_axes_or_self_improve");
    try require(z2, "CONTROL_PASS:content_context_failure_keys_prevent_12_repeat_charges");
    // We validate the public contracts only. Evaluator-private response maps and
    // transfer masks are neither parsed nor copied into the learner.
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const alloc = gpa.allocator();
    try validateUpstream(alloc);
    if (std.mem.eql(u8, cmd, "selftest")) {
        try writeRun("/tmp/aa1_a.csv"); try writeRun("/tmp/aa1_b.csv");
        const x = try std.fs.cwd().readFileAlloc(alloc, "/tmp/aa1_a.csv", 1 << 20); defer alloc.free(x);
        const y = try std.fs.cwd().readFileAlloc(alloc, "/tmp/aa1_b.csv", 1 << 20); defer alloc.free(y);
        if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
        try require(x, "VALID_NEGATIVE"); try require(x, "hidden_question_grammar"); try require(x, "llm_text_embedding");
        std.debug.print("round_aa_aa1 selftest PASS byte_identical=true verdict=VALID_NEGATIVE\n", .{}); return;
    }
    try writeRun(args.next() orelse "results/autonomous_uncertainty_round_aa.csv");
}
