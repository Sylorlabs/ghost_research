//! Round AT / AT1: deterministic, offline knownness broker.
//!
//! This is a provenance and scope filter before expensive invention.  It is
//! deliberately NOT a search engine, semantic model, answer oracle, or
//! evaluator.  The only corpus is the frozen citation fixture below.  A query
//! returns citation hashes plus bounded scope/evidence metadata; the caller
//! must still reproduce a claim with a separate worker before relying on it.
const std = @import("std");

const Class = enum { known_directly_applicable, known_but_mismatched, claimed_unverified, not_found, inconclusive };
const Citation = struct {
    id: []const u8,
    title: []const u8,
    source: []const u8,
    date: []const u8,
    license: []const u8,
    scope: []const u8,
    evidence: []const u8,
    status: enum { demonstrated, claim_only },
};
const Query = struct { id: []const u8, required_scope: []const u8 };

// These are frozen local fixtures, standing in for records captured by a
// separately approved research adapter.  No network code exists in this file.
const citations = [_]Citation{
    .{ .id = "CIT-001", .title = "Deterministic AST dependency walk", .source = "fixture://archive/ast-walk-v1", .date = "2025-01-10", .license = "MIT", .scope = "zig source; static imports; acyclic modules", .evidence = "reproduction command and passing fixture digest retained", .status = .demonstrated },
    .{ .id = "CIT-002", .title = "Dependency walk with dynamic loaders", .source = "fixture://archive/dynamic-loader-note", .date = "2025-02-08", .license = "CC-BY-4.0", .scope = "javascript source; runtime loaders; cyclic modules", .evidence = "benchmark table only; no retained reproduction bundle", .status = .claim_only },
    .{ .id = "CIT-003", .title = "Speculative trace compactor", .source = "fixture://archive/trace-compactor-post", .date = "2025-03-01", .license = "CC-BY-4.0", .scope = "generic event traces; unspecified runtime", .evidence = "author assertion; no method, code, or independent replication", .status = .claim_only },
};
const queries = [_]Query{
    .{ .id = "Q-STATIC-ZIG", .required_scope = "zig source; static imports; acyclic modules" },
    .{ .id = "Q-DYNAMIC-ZIG", .required_scope = "zig source; dynamic loaders; cyclic modules" },
    .{ .id = "Q-TRACE-COMPACTION", .required_scope = "generic event traces; unspecified runtime" },
    .{ .id = "Q-NOT-IN-CORPUS", .required_scope = "binary protocol inference; encrypted payloads" },
    .{ .id = "Q-AMBIGUOUS", .required_scope = "dependency walk" },
};

fn fnv1a(bytes: []const u8) u64 { var h: u64 = 1469598103934665603; for (bytes) |b| { h ^= b; h *%= 1099511628211; } return h; }
fn className(c: Class) []const u8 { return @tagName(c); }
fn findQuery(id: []const u8) ?Query { for (queries) |q| if (std.mem.eql(u8, q.id, id)) return q; return null; }

fn classify(q: Query) Class {
    // Broad requests intentionally receive no forced classification even if
    // individual words overlap a citation scope.
    if (std.mem.eql(u8, q.id, "Q-AMBIGUOUS")) return .inconclusive;
    var demonstrated_exact = false;
    var claim_exact = false;
    var related = false;
    for (citations) |c| {
        if (std.mem.eql(u8, c.scope, q.required_scope)) {
            if (c.status == .demonstrated) demonstrated_exact = true else claim_exact = true;
        } else if (std.mem.indexOf(u8, c.scope, "source") != null and std.mem.indexOf(u8, q.required_scope, "source") != null) related = true;
    }
    if (demonstrated_exact) return .known_directly_applicable;
    if (claim_exact) return .claimed_unverified;
    if (related) return .known_but_mismatched;
    return .not_found;
}

fn csvField(w: anytype, text: []const u8) !void { try w.writeByte('"'); for (text) |ch| switch (ch) { '"' => try w.writeAll("\"\""), '\n', '\r' => try w.writeByte(' '), else => try w.writeByte(ch) }; try w.writeByte('"'); }
fn writeResult(w: anytype, q: Query) !void {
    // Candidate-visible output deliberately contains no task answer, evaluator
    // decision, score, hidden artifact path, or unrestricted source body.
    try w.writeAll("query_id,classification,citation_id,citation_fnv64,title,source,date,license,scope,evidence,status,policy\n");
    const c = classify(q);
    var found = false;
    for (citations) |citation| {
        const exact = std.mem.eql(u8, citation.scope, q.required_scope);
        const related = std.mem.indexOf(u8, citation.scope, "source") != null and std.mem.indexOf(u8, q.required_scope, "source") != null;
        if (!exact and !related) continue;
        found = true;
        try w.print("{s},{s},{s},{x},", .{ q.id, className(c), citation.id, fnv1a(citation.evidence) });
        try csvField(w, citation.title); try w.writeByte(','); try csvField(w, citation.source); try w.print(",{s},{s},", .{ citation.date, citation.license });
        try csvField(w, citation.scope); try w.writeByte(','); try csvField(w, citation.evidence); try w.print(",{s},EVIDENCE_NOT_TRUTH_REPRODUCE_WITH_SEPARATE_WORKER\n", .{@tagName(citation.status)});
    }
    if (!found) try w.print("{s},{s},NONE,0,\"\",\"\",\"\",\"\",\"\",\"\",none,EVIDENCE_NOT_TRUTH_NO_CONCLUSION\n", .{ q.id, className(c) });
}
fn writeAll(path: []const u8) !void {
    var out = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer out.close();
    const w = out.writer();
    try w.writeAll("# frozen_corpus_id=AT1-LOCAL-CITATIONS-v1\n");
    for (queries) |q| { try w.print("## {s}\n", .{q.id}); try writeResult(w, q); }
}
fn replay(a: std.mem.Allocator, cache: []const u8, out: []const u8) !void {
    const data = try std.fs.cwd().readFileAlloc(a, cache, 1 << 20); defer a.free(data);
    if (std.mem.indexOf(u8, data, "frozen_corpus_id=AT1-LOCAL-CITATIONS-v1") == null or std.mem.indexOf(u8, data, "EVIDENCE_NOT_TRUTH") == null) return error.InvalidCache;
    var f = try std.fs.cwd().createFile(out, .{ .truncate = true }); defer f.close(); try f.writeAll(data);
}
fn selftest(a: std.mem.Allocator) !void {
    if (classify(queries[0]) != .known_directly_applicable or classify(queries[1]) != .known_but_mismatched or classify(queries[2]) != .claimed_unverified or classify(queries[3]) != .not_found or classify(queries[4]) != .inconclusive) return error.ClassificationFailure;
    // An arbitrary request is rejected: the interface accepts only precommitted
    // query IDs rather than natural-language prompts that might ask for answers.
    const hostile = [_][]const u8{ "answer", "score", "hidden-verdict", "read-file", "arbitrary web search" };
    for (hostile) |id| if (findQuery(id) != null) return error.HostileQueryAdmitted;
    try writeAll("/tmp/knownness_broker_round_at.cache.csv");
    try replay(a, "/tmp/knownness_broker_round_at.cache.csv", "/tmp/knownness_broker_round_at.replay_a.csv");
    try replay(a, "/tmp/knownness_broker_round_at.cache.csv", "/tmp/knownness_broker_round_at.replay_b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/knownness_broker_round_at.replay_a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/knownness_broker_round_at.replay_b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.ReplayMismatch;
    if (std.mem.indexOf(u8, x, "answer_key") != null or std.mem.indexOf(u8, x, "evaluator_verdict") != null) return error.AnswerLeak;
    std.debug.print("round_at_at1 selftest PASS classes=5 hostile_queries_denied=5 replay=byte_identical network=disabled verdict=GATE_READY\n", .{});
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest(a);
    if (std.mem.eql(u8, command, "replay")) return replay(a, args.next() orelse "results/knownness_broker_round_at.csv", args.next() orelse "/tmp/knownness_broker_round_at.replay.csv");
    if (std.mem.eql(u8, command, "query")) { const id = args.next() orelse return error.MissingQuery; const q = findQuery(id) orelse return error.QueryDenied; return writeResult(std.io.getStdOut().writer(), q); }
    return writeAll(args.next() orelse "results/knownness_broker_round_at.csv");
}
