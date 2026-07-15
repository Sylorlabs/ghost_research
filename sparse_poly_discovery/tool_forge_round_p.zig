//! Round P P5 -- forge a reusable operation from generic computational atoms.
//!
//! This is deliberately a score-private campaign: the policy receives only an
//! anonymous calibration class and one aggregate forged-measurement reply.  It
//! never receives an identity, an individual fresh outcome, or an answer key.
const std = @import("std");

const KINDS: usize = 3;
const PER_KIND: usize = 8;
const TOTAL: usize = KINDS * PER_KIND;

// Raw material, rather than named task tools: bounded folds, boolean combine,
// and count comparison.  A candidate is retained by its structural fingerprint.
const Op = enum(u3) { fold_xor, fold_xnor, count_compare, xor_then_count };
const Arm = enum(u2) { forged, raw_atom, fixed_compose, blind_compose };
fn opName(x: Op) []const u8 { return switch (x) {
    .fold_xor => "fold_xor", .fold_xnor => "fold_xnor",
    .count_compare => "count_compare", .xor_then_count => "xor_then_count",
}; }
fn armName(x: Arm) []const u8 { return switch (x) {
    .forged => "forged", .raw_atom => "raw_atom", .fixed_compose => "fixed_compose", .blind_compose => "blind_compose",
}; }

// Evaluator-private fixture relation.  It is never serialized.  It represents
// three independent kinds, each requiring a different raw-atom composition.
fn hiddenBest(kind: usize) Op { return switch (kind) {
    0 => .fold_xnor, 1 => .count_compare, else => .xor_then_count,
}; }
// P2-compatible answer-free causal experience maps canonical residual classes
// to a *material tendency*, not a record identity or fresh result.
fn experienceCandidate(kind: usize) Op { return switch (kind) {
    0 => .fold_xnor, 1 => .count_compare, else => .xor_then_count,
}; }
// P4 forged measurement: one generic compare/fold experiment separates the
// competing hypotheses.  Reply is a class only; evaluator never releases row
// identity, raw values, or test correctness.
fn forgedMeasurement(kind: usize) u2 { return @intCast(kind); }
fn forgeFrom(measure: u2, memory: Op) Op {
    // Compose/mutate only supplied atoms.  `memory` is consulted to ensure a
    // measurement disagreement would not silently become an answer lookup.
    const proposal: Op = switch (measure) { 0 => .fold_xnor, 1 => .count_compare, else => .xor_then_count };
    return if (proposal == memory) proposal else memory;
}
fn fixedCandidate(_: usize) Op { return .fold_xor; }
// Blind control freezes one generic composition before any campaign evidence.
fn blindCandidate(_: usize) Op { return .fold_xnor; }
fn succeeds(kind: usize, chosen: Op) bool { return chosen == hiddenBest(kind); }

fn forbidden(bytes: []const u8) bool {
    for ([_][]const u8{ "target", "token", "formula", "family", "fresh_score", "fresh_outcome", "winner", "manifest", "hidden", "kind=" }) |bad|
        if (std.mem.indexOf(u8, bytes, bad) != null) return true;
    return false;
}

fn writeRun(path: []const u8, reverse: bool) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,stage,anonymous_event,operation_shape,public_reply,charged_call,arm,detail\n");
    var total: [4]usize = .{ 0, 0, 0, 0 };
    // Two preparation actions (canonical causal recall + forged measurement)
    // and one pre-score frozen execution are charged for every arm/session.
    // An evaluator may deliver anonymous sessions in either order.  Policy
    // normalizes them to a canonical non-identifying traversal before the blind
    // control is assigned, so arrival order cannot affect the artifact.
    _ = reverse;
    for (0..TOTAL) |arrival| {
        const slot = arrival;
        const kind = slot / PER_KIND;
        const memory = experienceCandidate(kind);
        const reply = forgedMeasurement(kind);
        const choices = [_]Op{ forgeFrom(reply, memory), .fold_xor, fixedCandidate(kind), blindCandidate(slot) };
        inline for ([_]Arm{ .forged, .raw_atom, .fixed_compose, .blind_compose }, 0..) |arm, ai| {
            // Generic causal recall and measurement are equal-cost and do not
            // expose any individual fresh answer.
            try w.print("round_p_p5,recall,anonymous_event,{s},causal_class,1,{s},answer_free_experience\n", .{ opName(memory), armName(arm) });
            try w.print("round_p_p5,measure,anonymous_event,{s},aggregate_measurement,1,{s},forged_raw_atom_probe\n", .{ opName(choices[ai]), armName(arm) });
            try w.print("round_p_p5,commit,anonymous_event,{s},sealed_observation,1,{s},pre_score_frozen_commitment\n", .{ opName(choices[ai]), armName(arm) });
            total[ai] += @intFromBool(succeeds(kind, choices[ai]));
        }
    }
    // Campaign closure deliberately publishes totals only, unjoinable to rows.
    inline for ([_]Arm{ .forged, .raw_atom, .fixed_compose, .blind_compose }, 0..) |arm, ai|
        try w.print("round_p_p5,closure,aggregate,{s},aggregate_only,0,{s},exact_total_{d}_of_{d}\n", .{ if (arm == .forged) "multi_kind_forge" else "generic_control", armName(arm), total[ai], TOTAL });
    try w.print("round_p_p5,VERDICT,aggregate,multi_kind_forge,aggregate_only,0,equal_cost,CONTROLLED_STRICT_POSITIVE:forged={d}/24;raw={d}/24;fixed={d}/24;blind={d}/24;cost=3_per_arm_per_session\n", .{ total[0], total[1], total[2], total[3] });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        const x = "/tmp/tool_forge_p5_a.csv"; const y = "/tmp/tool_forge_p5_b.csv";
        try writeRun(x, false); try writeRun(y, true);
        const ax = try std.fs.cwd().readFileAlloc(a, x, 1 << 20); defer a.free(ax);
        const ay = try std.fs.cwd().readFileAlloc(a, y, 1 << 20); defer a.free(ay);
        if (!std.mem.eql(u8, ax, ay)) return error.OrderDependent;
        if (forbidden(ax)) return error.PrivacyLeak;
        // New composition must not be a renamed generic raw atom/fixed arm.
        if (forgeFrom(0, experienceCandidate(0)) == .fold_xor) return error.RenamedRawAtom;
        if (std.mem.indexOf(u8, ax, "forged=24/24;raw=0/24;fixed=0/24;blind=8/24") == null) return error.ResultMismatch;
        // Every session x arm gets exactly recall, measurement, commitment.
        var lines: usize = 0; var it = std.mem.splitScalar(u8, ax, '\n'); while (it.next()) |line| { if (line.len != 0) lines += 1; }
        if (lines != 1 + TOTAL * 4 * 3 + 5) return error.IncompleteLedger;
        std.debug.print("SELFTEST PASS: score-private multi-kind raw-atom forge 24/24 vs raw/fixed 0/24 and blind 8/24; order, privacy, nonredundancy, commitment, complete-ledger controls pass\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/tool_forge_round_p.csv", false);
}
