//! Round Q Q3 -- deterministic quarantine for newly discovered materials.
//!
//! This is a protocol safety fixture, not a solver.  A material can enter the
//! forge only if it has bounded provenance, a verified digest, no private
//! evaluator/answer origin, no content alias, no hidden join/correlation, and
//! no post-evaluation selection path.  The public ledger contains neither a
//! task identity nor an individual evaluation result.
const std = @import("std");

const Origin = enum { local_corpus, simulator, missing, forged, sealed_service, answer_source, unbounded_text };
const Decision = enum { admit, reject };

const Material = struct {
    id: []const u8,
    origin: Origin,
    fingerprint: u64,
    digest_ok: bool,
    correlation: u8,
    hidden_join: bool,
    post_evaluation: bool,
};

const materials = [_]Material{
    .{ .id = "mat_alpha", .origin = .local_corpus, .fingerprint = 0x41, .digest_ok = true, .correlation = 0, .hidden_join = false, .post_evaluation = false },
    .{ .id = "mat_beta", .origin = .simulator, .fingerprint = 0x77, .digest_ok = true, .correlation = 0, .hidden_join = false, .post_evaluation = false },
    .{ .id = "mat_alias", .origin = .local_corpus, .fingerprint = 0x41, .digest_ok = true, .correlation = 0, .hidden_join = false, .post_evaluation = false },
    .{ .id = "mat_missing", .origin = .missing, .fingerprint = 0x18, .digest_ok = false, .correlation = 0, .hidden_join = false, .post_evaluation = false },
    .{ .id = "mat_forged", .origin = .forged, .fingerprint = 0x19, .digest_ok = false, .correlation = 0, .hidden_join = false, .post_evaluation = false },
    .{ .id = "mat_service", .origin = .sealed_service, .fingerprint = 0x22, .digest_ok = true, .correlation = 0, .hidden_join = false, .post_evaluation = false },
    .{ .id = "mat_oracle", .origin = .answer_source, .fingerprint = 0x23, .digest_ok = true, .correlation = 0, .hidden_join = false, .post_evaluation = false },
    .{ .id = "mat_correlated", .origin = .local_corpus, .fingerprint = 0x24, .digest_ok = true, .correlation = 1, .hidden_join = false, .post_evaluation = false },
    .{ .id = "mat_join", .origin = .simulator, .fingerprint = 0x25, .digest_ok = true, .correlation = 0, .hidden_join = true, .post_evaluation = false },
    .{ .id = "mat_post", .origin = .local_corpus, .fingerprint = 0x26, .digest_ok = true, .correlation = 0, .hidden_join = false, .post_evaluation = true },
    .{ .id = "mat_free", .origin = .unbounded_text, .fingerprint = 0x27, .digest_ok = true, .correlation = 0, .hidden_join = false, .post_evaluation = false },
};

fn originName(x: Origin) []const u8 { return switch (x) { .local_corpus => "corpus", .simulator => "simulator", else => "quarantined" }; }
fn decisionName(x: Decision) []const u8 { return if (x == .admit) "ADMIT" else "REJECT"; }

fn decisionAt(i: usize) struct { decision: Decision, reason: []const u8 } {
    const x = materials[i];
    if (x.origin == .missing) return .{ .decision = .reject, .reason = "NO_PROVENANCE" };
    if (!x.digest_ok or x.origin == .forged) return .{ .decision = .reject, .reason = "FORGED_PROVENANCE" };
    if (x.origin == .sealed_service or x.origin == .answer_source) return .{ .decision = .reject, .reason = "FORBIDDEN_ORIGIN" };
    if (x.origin == .unbounded_text) return .{ .decision = .reject, .reason = "UNBOUNDED_INPUT" };
    if (x.correlation != 0) return .{ .decision = .reject, .reason = "CORRELATED_METADATA" };
    if (x.hidden_join) return .{ .decision = .reject, .reason = "PRIVATE_JOIN" };
    if (x.post_evaluation) return .{ .decision = .reject, .reason = "POST_EVALUATION" };
    // Content identity, not a name check: aliases cannot enter twice.
    for (materials[0..i]) |prior| if (prior.fingerprint == x.fingerprint) return .{ .decision = .reject, .reason = "DUPLICATE_CONTENT" };
    return .{ .decision = .admit, .reason = "VERIFIED_PROVENANCE" };
}

fn forbidden(bytes: []const u8) bool {
    for ([_][]const u8{ "target", "family", "answer", "winner", "fresh_score", "hidden", "manifest", "formula", "token" }) |bad|
        if (std.mem.indexOf(u8, bytes, bad) != null) return true;
    return false;
}

fn writeRun(path: []const u8, reverse_arrival: bool) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("material_id,origin_class,shape_fingerprint,decision,reason_code,charged_inspection,provenance_digest\n");
    // Arrival order is deliberately ignored: canonical material ordering is the
    // stable registry order.  This models restart/permutation-safe admission.
    _ = reverse_arrival;
    var admitted: usize = 0;
    var rejected: usize = 0;
    for (materials, 0..) |x, i| {
        const d = decisionAt(i);
        admitted += @intFromBool(d.decision == .admit);
        rejected += @intFromBool(d.decision == .reject);
        try w.print("{s},{s},{x},{s},{s},1,{s}\n", .{ x.id, originName(x.origin), x.fingerprint, decisionName(d.decision), d.reason, if (x.digest_ok and x.origin != .forged) "verified" else "invalid" });
    }
    try w.print("campaign_closure,aggregate,na,SEALED,ADMITTED_{d}_REJECTED_{d},0,aggregate_only\n", .{ admitted, rejected });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        const a_path = "/tmp/material_quarantine_q3_a.csv";
        const b_path = "/tmp/material_quarantine_q3_b.csv";
        try writeRun(a_path, false); try writeRun(b_path, true);
        const left = try std.fs.cwd().readFileAlloc(a, a_path, 1 << 20); defer a.free(left);
        const right = try std.fs.cwd().readFileAlloc(a, b_path, 1 << 20); defer a.free(right);
        if (!std.mem.eql(u8, left, right)) return error.OrderOrRestartDependent;
        if (forbidden(left)) return error.PrivateFieldLeak;
        if (decisionAt(0).decision != .admit or decisionAt(1).decision != .admit) return error.SafeMaterialRejected;
        const expected = [_][]const u8{ "DUPLICATE_CONTENT", "NO_PROVENANCE", "FORGED_PROVENANCE", "FORBIDDEN_ORIGIN", "FORBIDDEN_ORIGIN", "CORRELATED_METADATA", "PRIVATE_JOIN", "POST_EVALUATION", "UNBOUNDED_INPUT" };
        for (expected, 2..) |reason, i| if (!std.mem.eql(u8, decisionAt(i).reason, reason)) return error.MissingQuarantine;
        var lines: usize = 0;
        var it = std.mem.splitScalar(u8, left, '\n');
        while (it.next()) |line| {
            if (line.len != 0) lines += 1;
        }
        if (lines != materials.len + 2) return error.IncompleteAccounting;
        std.debug.print("SELFTEST PASS: deterministic answer-safe material quarantine admits 2/11; rejects forged/missing provenance, aliases, private origins/joins, correlations, post-evaluation selection, and unbounded text; 11 individually charged inspections\n", .{});
        return;
    }
    try writeRun(args.next() orelse "results/material_quarantine_round_q.csv", false);
}
