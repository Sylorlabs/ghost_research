//! Round S S3 -- genuine-capture, answer-free principle-loop integration gate.
//!
//! This harness deliberately refuses to manufacture a positive from fixtures.
//! It consumes only an S1-style public-external capture receipt.  In the
//! absence of such a receipt it emits a BLOCKED integration ledger, rather
//! than reusing Round R's synthetic receipt result.
const std = @import("std");

const Verdict = enum { integration_ready, blocked, rejected };

const forbidden_words = [_][]const u8{
    "answer", "target", "family", "winner", "score", "manifest", "hidden",
    "evaluator", "request_id", "formula", "solution", "fixture",
};

fn hasForbidden(text: []const u8) bool {
    for (forbidden_words) |word| if (std.ascii.indexOfIgnoreCase(text, word) != null) return true;
    return false;
}

fn isHexDigest(text: []const u8) bool {
    if (text.len != 64) return false;
    for (text) |c| if (!std.ascii.isHex(c)) return false;
    return true;
}

/// Stable, deliberately small S1 handoff schema.  Pipe-separated so captured
/// public text can retain commas.  There is no field for a task, answer, score,
/// hidden test, or a source-to-evaluator join.
///
/// receipt_id | https_origin | captured_at_utc | sha256(content) |
/// policy=public_read_only | lineage | scope=public_external | public_content
const Receipt = struct {
    id: []const u8,
    origin: []const u8,
    captured_at: []const u8,
    digest: []const u8,
    policy: []const u8,
    lineage: []const u8,
    scope: []const u8,
    content: []const u8,
};

fn parseReceipt(line: []const u8) !Receipt {
    var fields: [8][]const u8 = undefined;
    var it = std.mem.splitScalar(u8, std.mem.trim(u8, line, " \t\r\n"), '|');
    var n: usize = 0;
    while (it.next()) |field| {
        if (n >= fields.len) return error.TooManyReceiptFields;
        fields[n] = std.mem.trim(u8, field, " \t");
        n += 1;
    }
    if (n != fields.len) return error.BadReceiptFieldCount;
    const r = Receipt{ .id = fields[0], .origin = fields[1], .captured_at = fields[2], .digest = fields[3], .policy = fields[4], .lineage = fields[5], .scope = fields[6], .content = fields[7] };
    if (r.id.len == 0 or r.captured_at.len < 20 or r.lineage.len == 0) return error.MissingReceiptProvenance;
    if (!(std.mem.startsWith(u8, r.origin, "https://") or std.mem.startsWith(u8, r.origin, "http://"))) return error.NotNetworkOrigin;
    if (std.mem.indexOf(u8, r.origin, "localhost") != null or std.mem.indexOf(u8, r.origin, "127.0.0.1") != null) return error.LocalOrigin;
    if (!isHexDigest(r.digest)) return error.BadContentDigest;
    var content_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(r.content, &content_hash, .{});
    var encoded: [64]u8 = undefined;
    _ = try std.fmt.bufPrint(&encoded, "{s}", .{std.fmt.fmtSliceHexLower(&content_hash)});
    if (!std.ascii.eqlIgnoreCase(r.digest, &encoded)) return error.ContentDigestMismatch;
    if (!std.mem.eql(u8, r.policy, "public_read_only")) return error.PolicyNotPublicReadOnly;
    if (!std.mem.eql(u8, r.scope, "public_external")) return error.NotPublicExternal;
    if (r.content.len == 0 or hasForbidden(r.id) or hasForbidden(r.origin) or hasForbidden(r.lineage) or hasForbidden(r.content)) return error.AnswerOrFixtureLeak;
    return r;
}

fn mechanism(content: []const u8) []const u8 {
    if (std.ascii.indexOfIgnoreCase(content, "relation") != null) return "retain_relation_structure";
    if (std.ascii.indexOfIgnoreCase(content, "transition") != null or std.ascii.indexOfIgnoreCase(content, "sequence") != null) return "retain_transition_structure";
    if (std.ascii.indexOfIgnoreCase(content, "aggregate") != null or std.ascii.indexOfIgnoreCase(content, "count") != null) return "retain_aggregate_structure";
    return "retain_observed_structure";
}

fn writeBlocked(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,stage,receipt_state,condition,mechanism,prediction,failure_signature,candidate_material,provenance,contradiction_status,charged_cost,arm,detail\n");
    try w.writeAll("round_s_s3,integration_gate,no_validated_s1_live_capture,not_applicable,not_applicable,not_applicable,missing_genuine_capture,not_applicable,none,not_applicable,0,structured_refinery,BLOCKED:no_validated_public_external_capture\n");
    try w.writeAll("round_s_s3,VERDICT,aggregate,not_applicable,not_applicable,not_applicable,not_applicable,not_applicable,none,not_applicable,0,equal_cost,BLOCKED:real-source positive and equal-cost calibration are forbidden until S1 supplies validated live receipts\n");
}

fn writeValidated(path: []const u8, r: Receipt) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    const m = mechanism(r.content);
    try w.writeAll("artifact,stage,receipt_state,condition,mechanism,prediction,failure_signature,candidate_material,provenance,contradiction_status,charged_cost,arm,detail\n");
    try w.print("round_s_s3,refine,validated_live_receipt,observable_public_residual,{s},predict_measurement_change,observed_mismatch,propose_material,{s}@{s},uncontradicted,1,structured_refinery,answer_free_structured_principle\n", .{ m, r.origin, r.digest });
    try w.print("round_s_s3,raw_control,validated_live_receipt,observable_public_residual,raw_capture_retrieval,no_structured_prediction,unstructured_receipt,none,{s}@{s},uncontradicted,1,raw_capture_retrieval,equal_cost_control_prepared\n", .{ r.origin, r.digest });
    try w.writeAll("round_s_s3,VERDICT,aggregate,not_scored,not_scored,not_scored,private_calibration_required,not_scored,validated_live_receipt,not_scored,0,equal_cost,INTEGRATION_READY:not_a_positive; private independent calibration must score structured/raw/frozen-prior equally\n");
}

fn validateFile(allocator: std.mem.Allocator, path: []const u8) !Receipt {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1 << 20);
    defer allocator.free(bytes);
    // A capture handoff must contain exactly one canonical receipt for this
    // experiment: no silent multi-source joins, and no hidden selection table.
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const line = lines.next() orelse return error.EmptyReceipt;
    while (lines.next()) |rest| if (std.mem.trim(u8, rest, " \t\r").len != 0) return error.MultipleReceiptJoinDenied;
    return parseReceipt(line);
}

fn writeForInput(allocator: std.mem.Allocator, output: []const u8, input: ?[]const u8) !Verdict {
    const capture = input orelse { try writeBlocked(output); return .blocked; };
    const r = validateFile(allocator, capture) catch { try writeBlocked(output); return .rejected; };
    try writeValidated(output, r);
    return .integration_ready;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) {
        const good = \\capture-s1-001|https://public.example.org/notes|2026-07-15T00:00:00Z|e7e647f8bc1da9261f5d20436bcd91e3e1e80d6b95036f12425c02b75779e2c0|public_read_only|discovery:generic-query|public_external|A public relation observation supports a comparison measurement.
        ;
        const fixture = \\fixture-001|https://public.example.org/notes|2026-07-15T00:00:00Z|e7e647f8bc1da9261f5d20436bcd91e3e1e80d6b95036f12425c02b75779e2c0|public_read_only|discovery:generic-query|public_external|A public relation observation supports a comparison measurement.
        ;
        const local = \\capture-s1-002|file:///tmp/note|2026-07-15T00:00:00Z|e7e647f8bc1da9261f5d20436bcd91e3e1e80d6b95036f12425c02b75779e2c0|public_read_only|discovery:generic-query|public_external|A public relation observation supports a comparison measurement.
        ;
        if (!std.mem.eql(u8, mechanism((try parseReceipt(good)).content), "retain_relation_structure")) return error.MechanismExtractionFailed;
        if (parseReceipt(fixture)) |_| return error.FixtureAccepted else |_| {}
        if (parseReceipt(local)) |_| return error.LocalReceiptAccepted else |_| {}
        if (parseReceipt("capture|https://public.example.org|2026-07-15T00:00:00Z|0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef|public_read_only|lineage|public_external|hidden answer")) |_| return error.AnswerLeakAccepted else |_| {}
        const no_capture = "/tmp/genuine_principle_loop_no_capture.csv";
        _ = try writeForInput(allocator, no_capture, null);
        const blocked = try std.fs.cwd().readFileAlloc(allocator, no_capture, 1 << 20); defer allocator.free(blocked);
        if (std.mem.indexOf(u8, blocked, "BLOCKED:no_validated_public_external_capture") == null) return error.BlockedGateMissing;
        std.debug.print("SELFTEST PASS: live receipt schema accepted; fixture/local/answer-bearing receipts rejected; absent S1 capture emits BLOCKED, never a synthetic positive\n", .{});
        return;
    }
    const output = args.next() orelse "results/genuine_principle_loop_round_s.csv";
    const capture = args.next();
    const verdict = try writeForInput(allocator, output, capture);
    std.debug.print("Round S S3 {s}: {s}\n", .{ @tagName(verdict), output });
}
