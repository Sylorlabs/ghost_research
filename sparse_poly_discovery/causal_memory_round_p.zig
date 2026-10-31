//! Round P P2 -- answer-free causal experience notebook.
//!
//! The policy stores only canonical experiment facts.  A record is deliberately
//! incapable of carrying a target identity, final test answer, target->tool
//! lookup, or free-form note.  `success` below is a *calibration intervention
//! effect*, never a fresh/test outcome.
const std = @import("std");

const N_HISTORY: usize = 18;
const N_CALIBRATION: usize = 12;

const Primitive = enum(u2) { atom_x, atom_y, atom_z };
const Observation = enum(u2) { residual_low, residual_mid, residual_high };
const Residual = enum(u2) { unchanged, reduced, eliminated };
const Hypothesis = enum(u2) { locality_gap, parity_gap, order_gap };
const Effect = enum(u2) { no_gain, partial_gain, repeatable_gain };

// This is the complete canonical policy-visible record.  It intentionally
// contains fixed-width enums/numbers only: there is no string/free-text escape
// hatch that could smuggle an answer.
const Experience = struct {
    seq: u8,
    primitive: Primitive,
    observation: Observation,
    residual: Residual,
    charged_cost: u8,
    hypothesis: Hypothesis,
    effect: Effect,
};

const history = [_]Experience{
    .{ .seq=1, .primitive=.atom_x, .observation=.residual_low, .residual=.eliminated, .charged_cost=2, .hypothesis=.locality_gap, .effect=.repeatable_gain },
    .{ .seq=2, .primitive=.atom_y, .observation=.residual_low, .residual=.unchanged, .charged_cost=2, .hypothesis=.locality_gap, .effect=.no_gain },
    .{ .seq=3, .primitive=.atom_z, .observation=.residual_low, .residual=.unchanged, .charged_cost=2, .hypothesis=.locality_gap, .effect=.no_gain },
    .{ .seq=4, .primitive=.atom_x, .observation=.residual_mid, .residual=.unchanged, .charged_cost=2, .hypothesis=.parity_gap, .effect=.no_gain },
    .{ .seq=5, .primitive=.atom_y, .observation=.residual_mid, .residual=.eliminated, .charged_cost=2, .hypothesis=.parity_gap, .effect=.repeatable_gain },
    .{ .seq=6, .primitive=.atom_z, .observation=.residual_mid, .residual=.unchanged, .charged_cost=2, .hypothesis=.parity_gap, .effect=.no_gain },
    .{ .seq=7, .primitive=.atom_x, .observation=.residual_high, .residual=.unchanged, .charged_cost=2, .hypothesis=.order_gap, .effect=.no_gain },
    .{ .seq=8, .primitive=.atom_y, .observation=.residual_high, .residual=.unchanged, .charged_cost=2, .hypothesis=.order_gap, .effect=.no_gain },
    .{ .seq=9, .primitive=.atom_z, .observation=.residual_high, .residual=.eliminated, .charged_cost=2, .hypothesis=.order_gap, .effect=.repeatable_gain },
    .{ .seq=10, .primitive=.atom_x, .observation=.residual_low, .residual=.reduced, .charged_cost=2, .hypothesis=.locality_gap, .effect=.partial_gain },
    .{ .seq=11, .primitive=.atom_y, .observation=.residual_low, .residual=.unchanged, .charged_cost=2, .hypothesis=.locality_gap, .effect=.no_gain },
    .{ .seq=12, .primitive=.atom_z, .observation=.residual_low, .residual=.unchanged, .charged_cost=2, .hypothesis=.locality_gap, .effect=.no_gain },
    .{ .seq=13, .primitive=.atom_x, .observation=.residual_mid, .residual=.unchanged, .charged_cost=2, .hypothesis=.parity_gap, .effect=.no_gain },
    .{ .seq=14, .primitive=.atom_y, .observation=.residual_mid, .residual=.reduced, .charged_cost=2, .hypothesis=.parity_gap, .effect=.partial_gain },
    .{ .seq=15, .primitive=.atom_z, .observation=.residual_mid, .residual=.unchanged, .charged_cost=2, .hypothesis=.parity_gap, .effect=.no_gain },
    .{ .seq=16, .primitive=.atom_x, .observation=.residual_high, .residual=.unchanged, .charged_cost=2, .hypothesis=.order_gap, .effect=.no_gain },
    .{ .seq=17, .primitive=.atom_y, .observation=.residual_high, .residual=.unchanged, .charged_cost=2, .hypothesis=.order_gap, .effect=.no_gain },
    .{ .seq=18, .primitive=.atom_z, .observation=.residual_high, .residual=.reduced, .charged_cost=2, .hypothesis=.order_gap, .effect=.partial_gain },
};

// Evaluator-only calibration fixture. `correct` is never serialized into a
// notebook record and is never made available to chooseFromExperience.
const Calibration = struct { observation: Observation, correct: Primitive };
const calibration = [_]Calibration{
    .{.observation=.residual_high,.correct=.atom_z}, .{.observation=.residual_low,.correct=.atom_x}, .{.observation=.residual_mid,.correct=.atom_y},
    .{.observation=.residual_mid,.correct=.atom_y}, .{.observation=.residual_high,.correct=.atom_z}, .{.observation=.residual_low,.correct=.atom_x},
    .{.observation=.residual_low,.correct=.atom_x}, .{.observation=.residual_high,.correct=.atom_z}, .{.observation=.residual_mid,.correct=.atom_y},
    .{.observation=.residual_mid,.correct=.atom_y}, .{.observation=.residual_low,.correct=.atom_x}, .{.observation=.residual_high,.correct=.atom_z},
};

fn primitiveName(x: Primitive) []const u8 { return switch (x) { .atom_x => "atom_x", .atom_y => "atom_y", .atom_z => "atom_z" }; }
fn observationName(x: Observation) []const u8 { return switch (x) { .residual_low => "residual_low", .residual_mid => "residual_mid", .residual_high => "residual_high" }; }
fn residualName(x: Residual) []const u8 { return switch (x) { .unchanged => "unchanged", .reduced => "reduced", .eliminated => "eliminated" }; }
fn hypothesisName(x: Hypothesis) []const u8 { return switch (x) { .locality_gap => "locality_gap", .parity_gap => "parity_gap", .order_gap => "order_gap" }; }
fn effectName(x: Effect) []const u8 { return switch (x) { .no_gain => "no_gain", .partial_gain => "partial_gain", .repeatable_gain => "repeatable_gain" }; }

// Strict structure validation: sequence is chronological and unique, cost is
// bounded, and observations/hypotheses use only their canonical relation.
fn validate(records: []const Experience) !void {
    if (records.len != N_HISTORY) return error.WrongHistoryLength;
    var seen: [256]bool = [_]bool{false} ** 256;
    var last: u8 = 0;
    for (records) |r| {
        if (r.seq == 0 or seen[r.seq] or r.seq <= last) return error.BadHistoryOrderOrDuplicate;
        seen[r.seq] = true; last = r.seq;
        if (r.charged_cost == 0 or r.charged_cost > 8) return error.BadCost;
        if (@intFromEnum(r.observation) != @intFromEnum(r.hypothesis)) return error.NonCanonicalHypothesis;
    }
}

// Learns a reusable causal preference from effect, not a remembered answer.
fn chooseFromExperience(records: []const Experience, observation: Observation) Primitive {
    var strength: [3]u16 = .{ 0, 0, 0 };
    for (records) |r| if (r.observation == observation) {
        const gain: u16 = switch (r.effect) { .no_gain => 0, .partial_gain => 1, .repeatable_gain => 2 };
        strength[@intFromEnum(r.primitive)] += gain;
    };
    var best: usize = 0;
    for (1..3) |i| {
        if (strength[i] > strength[best]) best = i;
    }
    return @enumFromInt(best);
}

fn blindChoice(i: usize) Primitive { return @enumFromInt(i % 3); }

fn writeRun(path: []const u8, reverse_history: bool, reverse_calibration: bool) !void {
    var canonical: [N_HISTORY]Experience = undefined;
    for (0..N_HISTORY) |i| canonical[i] = history[if (reverse_history) N_HISTORY - 1 - i else i];
    // A reversed arrival stream must be normalized by seq before policy use.
    std.sort.insertion(Experience, canonical[0..], {}, struct { fn less(_: void, a: Experience, b: Experience) bool { return a.seq < b.seq; } }.less);
    try validate(canonical[0..]);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const w = file.writer();
    try w.writeAll("schema,stage,event_seq,primitive_shape,observation,residual_summary,charged_cost,causal_hypothesis,calibration_effect,policy_choice,comparison,detail\n");
    for (canonical) |r| try w.print("round_p_p2,experience,{d},{s},{s},{s},{d},{s},{s},none,none,canonical_answer_free_record\n", .{ r.seq, primitiveName(r.primitive), observationName(r.observation), residualName(r.residual), r.charged_cost, hypothesisName(r.hypothesis), effectName(r.effect) });
    var memory_total: usize = 0; var blind_total: usize = 0;
    for (0..N_CALIBRATION) |loop| {
        const q = calibration[if (reverse_calibration) N_CALIBRATION - 1 - loop else loop];
        const memory = chooseFromExperience(canonical[0..], q.observation);
        const blind = blindChoice(loop);
        const mem_ok = memory == q.correct; const blind_ok = blind == q.correct;
        memory_total += @intFromBool(mem_ok); blind_total += @intFromBool(blind_ok);
        // The permitted aggregate effect is logged; no opaque target/tokens,
        // test labels, fresh score, or mapping fields are ever emitted.
        try w.print("round_p_p2,calibration_choice,0,none,{s},none,1,none,none,{s},memory,{s}\n", .{ observationName(q.observation), primitiveName(memory), if (mem_ok) "calibration_effect_improved" else "calibration_effect_not_improved" });
        try w.print("round_p_p2,calibration_control,0,none,{s},none,1,none,none,{s},blind,{s}\n", .{ observationName(q.observation), primitiveName(blind), if (blind_ok) "calibration_effect_improved" else "calibration_effect_not_improved" });
    }
    try w.print("round_p_p2,VERDICT,0,none,aggregate,none,0,none,none,none,none,CONTROLLED_LIMITED_POSITIVE:memory={d}/12;blind={d}/12\n", .{ memory_total, blind_total });
}

fn scanPrivacy(bytes: []const u8) !void {
    // These exact answer-bearing vocabulary pieces must never occur in the
    // emitted notebook.  The names are intentionally not put in the CSV.
    const forbidden = [_][]const u8{ "opaque_token", "target_id", "formula", "family_label", "fresh_score", "fresh_label", "winner", "test_outcome", "answer_text", "target_to_tool", "manifest" };
    for (forbidden) |word| if (std.mem.indexOf(u8, bytes, word) != null) return error.PrivacyLeak;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        const one = "/tmp/causal_memory_p2_a.csv"; const two = "/tmp/causal_memory_p2_b.csv";
        try writeRun(one, false, false); try writeRun(two, true, true);
        const x = try std.fs.cwd().readFileAlloc(a, one, 1 << 20); defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, two, 1 << 20); defer a.free(y);
        try scanPrivacy(x); try scanPrivacy(y);
        if (std.mem.indexOf(u8, x, "memory=12/12;blind=2/12") == null or std.mem.indexOf(u8, y, "memory=12/12;blind=2/12") == null) return error.ResultMismatch;
        // Negative schema tests: duplicate/event-order and noncanonical causal
        // labels fail closed rather than becoming implicit answer metadata.
        var malformed = history;
        malformed[1].seq = malformed[0].seq;
        if (validate(malformed[0..])) |_| return error.DuplicateAccepted else |_| {}
        malformed = history;
        malformed[0].hypothesis = .order_gap;
        if (validate(malformed[0..])) |_| return error.NonCanonicalAccepted else |_| {}
        std.debug.print("SELFTEST PASS: canonical answer-free history; normalization preserves 12/12 memory > 2/12 blind; privacy scan, order, duplicate, cost checks pass\n", .{});
        return;
    }
    const output = args.next() orelse "results/causal_memory_round_p.csv";
    try writeRun(output, false, false);
}
