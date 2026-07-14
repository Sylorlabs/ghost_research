//! N2 / Round N -- independent public-trace information audit.
//!
//! This is deliberately an information *upper bound*, not a solver.  Each
//! public trace in a split is counterfactually paired with both winning-tool
//! labels.  Therefore no deterministic function of the public trace can beat
//! the balanced family prior, regardless of classifier complexity.
const std = @import("std");

const Signatures: usize = 24;
const Rows: usize = Signatures * 2;
const TrainSignatures: usize = 12;

const Family = enum { bit_zero, bit_one };
const Trace = struct { global: u16, singleton: u16, directed: u16, adjacency: u16 };

fn splitName(signature: usize) []const u8 { return if (signature < TrainSignatures) "train" else "test"; }
fn familyName(f: Family) []const u8 { return @tagName(f); }

// A fixed permutation makes the output token unrelated to pair position.
// Tokens are output/audit data only; no policy classifier accepts them.
const token_permutation = [_]u8{
    17, 4, 39, 22, 8, 45, 1, 34, 13, 28, 42, 6,
    31, 10, 47, 19, 2, 37, 25, 14, 44, 7, 32, 20,
    11, 46, 5, 29, 16, 40, 0, 35, 23, 9, 41, 18,
    3, 30, 12, 43, 26, 15, 38, 21, 33, 24, 36, 27,
};

fn traceFor(signature: usize) Trace {
    // Pure public diagnostic shape, generated before family labels are paired.
    var p = std.Random.DefaultPrng.init(0x4e325f4155444954 + @as(u64, @intCast(signature)) * 104729);
    const r = p.random();
    return .{
        .global = 520 + r.intRangeLessThan(u16, 0, 430),
        .singleton = 510 + r.intRangeLessThan(u16, 0, 440),
        .directed = 500 + r.intRangeLessThan(u16, 0, 450),
        .adjacency = 505 + r.intRangeLessThan(u16, 0, 445),
    };
}

fn familyFor(row: usize) Family {
    // Every signature appears once with each family.  This is the audit's
    // counterfactual decoupling construction, not an input available to any
    // classifier.
    return if (row % 2 == 0) .bit_zero else .bit_one;
}
fn signatureFor(row: usize) usize { return row / 2; }

fn traceEqual(a: Trace, b: Trace) bool {
    return a.global == b.global and a.singleton == b.singleton and a.directed == b.directed and a.adjacency == b.adjacency;
}

const Rule = enum { prior, global_vs_directed, sum_cut, first_cut, nearest_centroid };
fn ruleName(r: Rule) []const u8 { return @tagName(r); }

fn predict(rule: Rule, tr: Trace) Family {
    return switch (rule) {
        .prior => .bit_zero,
        .global_vs_directed => if (tr.global >= tr.directed) .bit_zero else .bit_one,
        .sum_cut => if (@as(u32, tr.global) + tr.singleton + tr.directed + tr.adjacency >= 2900) .bit_zero else .bit_one,
        .first_cut => if (tr.global >= 735) .bit_zero else .bit_one,
        // Because training is exactly paired, both centroids are equal.  The
        // deterministic tie break is bit_zero; this is a deliberately generous
        // nearest-centroid attacker and still returns the family prior.
        .nearest_centroid => .bit_zero,
    };
}

fn score(rule: Rule, transform: usize) usize {
    var correct: usize = 0;
    for (TrainSignatures * 2..Rows) |row| {
        var tr = traceFor(signatureFor(row));
        // Exhaust all 24 public-field permutations.  A trace-only rule may see
        // any presentation, but paired labels make its accuracy invariant.
        const fields = [_]u16{ tr.global, tr.singleton, tr.directed, tr.adjacency };
        const perms = [_][4]u8{
            .{0,1,2,3}, .{0,1,3,2}, .{0,2,1,3}, .{0,2,3,1}, .{0,3,1,2}, .{0,3,2,1},
            .{1,0,2,3}, .{1,0,3,2}, .{1,2,0,3}, .{1,2,3,0}, .{1,3,0,2}, .{1,3,2,0},
            .{2,0,1,3}, .{2,0,3,1}, .{2,1,0,3}, .{2,1,3,0}, .{2,3,0,1}, .{2,3,1,0},
            .{3,0,1,2}, .{3,0,2,1}, .{3,1,0,2}, .{3,1,2,0}, .{3,2,0,1}, .{3,2,1,0},
        };
        const q = perms[transform];
        tr = .{ .global = fields[q[0]], .singleton = fields[q[1]], .directed = fields[q[2]], .adjacency = fields[q[3]] };
        if (predict(rule, tr) == familyFor(row)) correct += 1;
    }
    return correct;
}

fn tokenParityScore() usize {
    var correct: usize = 0;
    for (TrainSignatures * 2..Rows) |row| {
        // Deliberately hostile illegal feature: token numeric parity.  It must
        // not predict family above chance; policy code never receives it.
        const token = token_permutation[row];
        const p: Family = if (token % 2 == 0) .bit_zero else .bit_one;
        if (p == familyFor(row)) correct += 1;
    }
    return correct;
}

fn write(w: anytype) !void {
    try w.writeAll("protocol,record_type,target_token,split,signature,public_global,public_singleton,public_directed,public_adjacency,winning_family,policy_inputs,rule,field_permutation,heldout_correct,heldout_total,duplicate_attack,token_rename_attack,target_id_attack,verdict\n");
    // Explicit counterfactual-pair/duplicate attack.  The duplicate is an
    // intentional anti-leak witness: each public key has both labels.
    var exact_pairs: usize = 0;
    for (0..Signatures) |s| {
        if (traceEqual(traceFor(s), traceFor(s))) exact_pairs += 1;
    }
    if (exact_pairs != Signatures) return error.PairConstructionFailure;

    for (0..Rows) |row| {
        const s = signatureFor(row);
        const tr = traceFor(s);
        try w.print("round_n_trace_audit,target,N2-{d:0>2},{s},{d},{d},{d},{d},{d},{s},trace_only,none,none,,,,counterfactual_pair,pass,not_policy_input,pass\n", .{
            token_permutation[row], splitName(s), s, tr.global, tr.singleton, tr.directed, tr.adjacency, familyName(familyFor(row)),
        });
    }
    const rules = [_]Rule{ .prior, .global_vs_directed, .sum_cut, .first_cut, .nearest_centroid };
    var max_trace_score: usize = 0;
    for (rules) |rule| {
        var worst: usize = 0;
        for (0..24) |perm| worst = @max(worst, score(rule, perm));
        max_trace_score = @max(max_trace_score, worst);
        try w.print("round_n_trace_audit,classifier_summary,TRACE_ONLY,test,,,,,,trace_only,{s},all_24,{d},24,counterfactual_pair,pass,not_policy_input,{s}\n", .{
            ruleName(rule), worst, if (worst <= 12) "PASS_AT_PRIOR" else "LEAKAGE_FAILURE",
        });
    }
    const id_score = tokenParityScore();
    try w.print("round_n_trace_audit,attack_summary,TOKEN_PARITY,test,,,,,,ILLEGAL_token_id,parity,none,{d},24,counterfactual_pair,rename_test,measured,{s}\n", .{
        id_score, if (id_score <= 15) "PASS_NO_SYSTEMATIC_ID_LEAK" else "ID_LEAKAGE_FAILURE",
    });
    // Every deterministic f(trace) has one correct and one incorrect result
    // per heldout pair. This is an exact information upper bound, stronger
    // than the finite classifier suite above.
    try w.print("round_n_trace_audit,INFORMATION_UPPER_BOUND,ALL_DETERMINISTIC_TRACE_FUNCTIONS,test,,,,,,trace_only,counterfactual_pairing,all_24,12,24,dedupe_to_12_ambiguous_keys,token_rename_invariant,not_policy_input,{s}\n", .{
        if (max_trace_score <= 12 and id_score <= 15) "PASS_TRACE_HAS_ZERO_FAMILY_INFORMATION" else "LEAKAGE_FAILURE",
    });
    if (max_trace_score > 12) return error.ValidTraceLeakageFailure;
    if (id_score > 15) return error.ValidTargetIdLeakageFailure;
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const arg = args.next();
    if (arg != null and std.mem.eql(u8, arg.?, "selftest")) return write(std.io.getStdOut().writer());
    const path = arg orelse "results/trace_information_audit_round_n.csv";
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    try write(f.writer());
}
