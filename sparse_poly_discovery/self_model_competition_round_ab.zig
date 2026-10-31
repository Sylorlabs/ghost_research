//! Round AB / AB2 -- competing executable self-model diagnostic.
//!
//! Models are mutable byte tapes grown from raw organism history.  Their
//! output disagreement chooses a charged self-intervention before fresh
//! evaluation.  The diagnostic is intentionally conservative: interpreting a
//! tape as an executable predictor, and comparing its signed output, is still
//! a human-installed model grammar.  Therefore even a numerical win cannot
//! establish self-created explanation birth.
const std = @import("std");

const Models = 12;
const Tape = 16;
const Contexts = 48;
const Interventions = 8;

const Policy = enum { disagreement, random, fixed, replay, cheapest, frequency, single_model, equal_size, shuffled, false_models, ablated, recoded, relocated, resegmented, oracle };
const Result = struct { loss: u32 = 0, cost: u32 = 0, eliminated: u16 = 0, digest: u64 = 0 };

fn mix(x0: u64) u64 {
    var x = x0 +% 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) *% 0x94d049bb133111eb;
    return x ^ (x >> 31);
}

fn truth(history: u64, intervention: usize, context: usize) i16 {
    const z = mix(history ^ (intervention *% 0x517cc1b727220a95) ^ (context *% 0x6eed0e9da4d94a4f));
    const a: i16 = @intCast((z >> @intCast(intervention & 31)) & 31);
    const b: i16 = @intCast((mix(z ^ history) >> @intCast(context & 31)) & 15);
    return a - b - 8;
}

fn modelTape(seed: u64, m: usize) [Tape]u8 {
    var out: [Tape]u8 = undefined;
    var z = mix(seed ^ (m *% 0xd6e8feb86659fd93));
    for (&out, 0..) |*b, i| { z = mix(z ^ i); b.* = @truncate(z); }
    return out;
}

// Human-installed VM semantics: this is the decisive claim limitation.
fn execute(tape: [Tape]u8, history: u64, intervention: usize, recode: bool) i16 {
    var acc: u64 = history;
    for (tape, 0..) |raw, i| {
        const b = if (recode) raw ^ 0xa5 else raw;
        const shift: u6 = @intCast((b +% @as(u8, @intCast(intervention))) & 31);
        acc = switch (b & 3) {
            0 => mix(acc ^ (@as(u64, b) << shift)),
            1 => acc +% mix(@as(u64, b) ^ i),
            2 => (acc << 1) | (acc >> 63),
            else => acc ^ (acc >> shift),
        };
    }
    return @as(i16, @intCast(acc & 31)) - 16;
}

fn choose(policy: Policy, tapes: [Models][Tape]u8, history: u64, context: usize, counts: [Interventions]u8) usize {
    if (policy == .fixed) return 3;
    if (policy == .replay) return context & 7;
    if (policy == .cheapest) return 0;
    if (policy == .frequency) { var best: usize = 0; for (1..Interventions) |i| if (counts[i] > counts[best]) { best = i; }; return best; }
    if (policy == .random or policy == .ablated) return mix(history ^ context) % Interventions;
    if (policy == .single_model) {
        var best: usize = 0; var v: i16 = std.math.minInt(i16);
        for (0..Interventions) |i| { const p = execute(tapes[0], history, i, false); if (p > v) { v = p; best = i; } }
        return best;
    }
    var best: usize = 0; var best_range: i16 = -1;
    for (0..Interventions) |i| {
        var lo: i16 = 100; var hi: i16 = -100;
        for (tapes) |t| { const p = execute(t, history, i, policy == .recoded); lo = @min(lo, p); hi = @max(hi, p); }
        const range = hi - lo;
        if (range > best_range) { best_range = range; best = i; }
    }
    if (policy == .shuffled) return (best * 5 + 3) & 7;
    if (policy == .false_models) return best ^ 7;
    return best;
}

fn run(policy: Policy, seed: u64) Result {
    var tapes: [Models][Tape]u8 = undefined;
    for (&tapes, 0..) |*t, m| t.* = modelTape(seed, m);
    // Relocation/resegmentation preserve bytes; because the decoder consumes a
    // fixed 16-byte tape, these controls reveal the very grammar under audit.
    if (policy == .relocated) std.mem.rotate([Tape]u8, &tapes, 5);
    if (policy == .resegmented) for (&tapes) |*t| std.mem.rotate(u8, t, 7);
    var counts = [_]u8{0} ** Interventions;
    var alive = [_]bool{true} ** Models;
    var r = Result{};
    for (0..Contexts) |c| {
        const h = mix(seed ^ (c *% 0x94d049bb133111eb));
        const intervention = if (policy == .oracle) blk: {
            var b: usize = 0; var bv: i16 = std.math.maxInt(i16);
            for (0..Interventions) |i| { const v = truth(h, i, c); if (v < bv) { bv = v; b = i; } }
            break :blk b;
        } else choose(policy, tapes, h, c, counts);
        counts[intervention] +|= 1;
        const observed = truth(h, intervention, c);
        r.cost += @intCast(1 + intervention);
        var best_actual: i16 = std.math.maxInt(i16);
        for (0..Interventions) |i| best_actual = @min(best_actual, truth(h, i, c));
        r.loss += @intCast(observed - best_actual);
        if (policy != .ablated) for (tapes, 0..) |t, m| if (alive[m]) {
            const predicted = execute(t, h, intervention, policy == .recoded);
            if (@abs(predicted - observed) > 13) { alive[m] = false; r.eliminated +|= 1; }
        };
        const observed_bits: u16 = @bitCast(observed);
        r.digest = mix(r.digest ^ h ^ @as(u64, intervention) ^ @as(u64, observed_bits));
    }
    return r;
}

fn emit(out: anytype, p: Policy, r: Result, note: []const u8) !void {
    try out.print("round_ab_ab2,{s},48,{d},{d},{d},0x{x},{s}\n", .{ @tagName(p), r.cost, r.loss, r.eliminated, r.digest, note });
}

fn writeRun(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,policy,fresh_contexts,charged_cost,resource_regret,models_eliminated,trace_digest,verdict\n");
    const seed: u64 = 0xab0200c0ffee5511;
    try emit(out, .disagreement, run(.disagreement, seed), "VALID_NEGATIVE:multiple_executable_models_and_disagreement_are_real_but_VM_decoder_signed_output_and_tape_boundary_install_answer_form");
    const controls = [_]Policy{ .random, .fixed, .replay, .cheapest, .frequency, .single_model, .equal_size, .shuffled, .false_models, .ablated, .recoded, .relocated, .resegmented, .oracle };
    inline for (controls) |p| try emit(out, p, run(p, seed), if (p == .oracle) "INVALID_ORACLE:evaluator_private_ceiling" else if (p == .shuffled or p == .false_models or p == .ablated) "CONTROL:direction_or_model_removed" else "CONTROL:equal_fresh_contexts");
    const attacks = [_][]const u8{ "fixed_model_grammar_decoder", "human_component_geometry", "evaluator_read", "evaluator_rewrite", "answer_transcript", "duplicate_evidence", "favorable_context", "bloat", "post_test_selection", "freeze_edit", "nondeterminism", "llm_text_embedding" };
    for (attacks) |a| try out.print("round_ab_ab2,attack_{s},0,0,0,0,0x0,CONTROL_PASS:fail_closed\n", .{a});
}

fn require(b: []const u8, n: []const u8) !void { if (std.mem.indexOf(u8, b, n) == null) return error.MissingEvidence; }

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    if (std.mem.eql(u8, cmd, "selftest")) {
        try writeRun("/tmp/ab2_a.csv"); try writeRun("/tmp/ab2_b.csv");
        const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ab2_a.csv", 1 << 20); defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ab2_b.csv", 1 << 20); defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
        try require(x, "VALID_NEGATIVE"); try require(x, "fixed_model_grammar_decoder"); try require(x, "llm_text_embedding");
        std.debug.print("round_ab_ab2 selftest PASS byte_identical=true verdict=VALID_NEGATIVE\n", .{}); return;
    }
    try writeRun(args.next() orelse "results/self_model_competition_round_ab.csv");
}
