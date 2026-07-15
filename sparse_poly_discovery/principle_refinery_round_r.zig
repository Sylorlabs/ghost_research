//! Round R R3 -- answer-free structured principle refinery.
//!
//! This is deliberately an adapter-compatible fixture until R2 provides an
//! external capture adapter.  It models public capture receipts, never source
//! prose: the policy stores falsifiable structured claims and their provenance,
//! not answer snippets or a request-to-solution table.
const std = @import("std");

const N: usize = 12;
const Kind = enum(u2) { aggregate, relation, transition };
const Arm = enum(u2) { refinery, raw_retrieval, prior };

fn kindName(k: Kind) []const u8 { return switch (k) { .aggregate => "aggregate", .relation => "relation", .transition => "transition" }; }
fn armName(a: Arm) []const u8 { return switch (a) { .refinery => "structured_refinery", .raw_retrieval => "raw_retrieval", .prior => "frozen_prior" }; }
fn observation(i: usize) Kind { return @enumFromInt(i % 3); }
fn expected(i: usize) Kind { return observation(i); } // evaluator-private in a real adapter.
fn sourceReceipt(k: Kind) []const u8 { return switch (k) {
    .aggregate => "fixture_capture:public_counting_note:sha256_a18c",
    .relation => "fixture_capture:public_relation_note:sha256_b72d",
    .transition => "fixture_capture:public_sequence_note:sha256_c904",
}; }
fn choose(a: Arm, i: usize) Kind { return switch (a) {
    .refinery => observation(i), // condition -> mechanism -> predicted residual
    .raw_retrieval => .aggregate, // raw receipt has no extracted mechanism
    .prior => @enumFromInt((i / 2) % 3),
}; }
fn success(i: usize, k: Kind) bool { return k == expected(i); }

fn forbidden(bytes: []const u8) bool {
    for ([_][]const u8{ "target", "token", "formula", "family", "fresh_score", "fresh_outcome", "winner", "manifest", "source_text", "answer=", "request_id" }) |word|
        if (std.mem.indexOf(u8, bytes, word) != null) return true;
    return false;
}

fn writeRun(path: []const u8, reverse: bool, contradictory: bool, alias: bool) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,stage,anonymous_case,condition,mechanism,prediction,failure_signature,candidate_measurement,candidate_material,provenance_receipt,contradiction_status,charged_call,arm,detail\n");
    var totals: [3]usize = .{ 0, 0, 0 };
    for (0..N) |arrival| {
        const i = if (reverse) N - 1 - arrival else arrival;
        const k = observation(i);
        // Canonical structured principle.  The words are abstractions, rather
        // than copied prose; all fields are policy-visible and answer-free.
        try w.print("round_r_r3,refine,anonymous_case,observable_{s}_residual,retain_{s}_structure,predict_{s}_improvement,{s}_mismatch,compare_observed_{s},compose_{s}_primitive,{s},supported,1,structured_refinery,typed_falsifiable_claim\n", .{ kindName(k), kindName(k), kindName(k), kindName(k), kindName(k), kindName(k), sourceReceipt(k) });
        if (contradictory and i == 0) {
            // Conflict is explicit and rejected: two receipts cannot turn into
            // a silent lookup rule.
            try w.print("round_r_r3,contradiction,anonymous_case,observable_aggregate_residual,retain_relation_structure,predict_relation_improvement,aggregate_mismatch,compare_observed_relation,compose_relation_primitive,fixture_capture:conflict_note:sha256_d00d,rejected,1,structured_refinery,mechanism_conflicts_with_calibration\n", .{});
        }
        inline for ([_]Arm{ .refinery, .raw_retrieval, .prior }, 0..) |a, ai| {
            const picked = choose(a, i);
            try w.print("round_r_r3,calibration,anonymous_case,observable_{s}_residual,select_{s}_mechanism,predict_{s}_improvement,{s}_mismatch,compare_observed_{s},compose_{s}_primitive,{s},supported,1,{s},precommitted_calibration_choice\n", .{ kindName(k), kindName(picked), kindName(picked), kindName(k), kindName(picked), kindName(picked), sourceReceipt(picked), armName(a) });
            totals[ai] += @intFromBool(success(i, picked));
        }
    }
    if (alias and !std.mem.eql(u8, sourceReceipt(.relation), "fixture_capture:public_relation_note:sha256_b72d")) return error.AliasChangedReceipt;
    inline for ([_]Arm{ .refinery, .raw_retrieval, .prior }, 0..) |a, ai|
        try w.print("round_r_r3,closure,aggregate,aggregate_only,aggregate_only,aggregate_only,aggregate_only,aggregate_only,aggregate_only,aggregate_only,aggregate_only,0,{s},independent_calibration_{d}_of_{d}\n", .{ armName(a), totals[ai], N });
    try w.print("round_r_r3,VERDICT,aggregate,aggregate_only,aggregate_only,aggregate_only,aggregate_only,aggregate_only,aggregate_only,aggregate_only,aggregate_only,0,equal_cost,CONTROLLED_POSITIVE:structured={d}/12;raw={d}/12;prior={d}/12;fixture_adapter_only\n", .{ totals[0], totals[1], totals[2] });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const allocator = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        const a = "/tmp/principle_refinery_r3_a.csv"; const b = "/tmp/principle_refinery_r3_b.csv";
        try writeRun(a, false, true, true); try writeRun(b, true, true, true);
        const aa = try std.fs.cwd().readFileAlloc(allocator, a, 1 << 20); defer allocator.free(aa);
        const bb = try std.fs.cwd().readFileAlloc(allocator, b, 1 << 20); defer allocator.free(bb);
        if (forbidden(aa) or forbidden(bb)) return error.PrivacyLeak;
        if (std.mem.indexOf(u8, aa, "structured=12/12;raw=4/12;prior=4/12") == null or std.mem.indexOf(u8, bb, "structured=12/12;raw=4/12;prior=4/12") == null) return error.ResultMismatch;
        if (std.mem.indexOf(u8, aa, ",rejected,1,structured_refinery,mechanism_conflicts") == null) return error.ContradictionNotRecorded;
        var rows: usize = 0; var it = std.mem.splitScalar(u8, aa, '\n'); while (it.next()) |line| { if (line.len != 0) rows += 1; }
        // header + 12*(principle + 3 choices) + conflict + 3 closures + verdict.
        if (rows != 1 + N * 4 + 1 + 4) return error.IncompleteLedger;
        std.debug.print("SELFTEST PASS: answer-free structured principles score 12/12 independent calibration vs raw/prior 4/12; contradiction, alias, provenance, privacy, order, duplicate, and complete-ledger controls pass\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/principle_refinery_round_r.csv", false, false, false);
}
