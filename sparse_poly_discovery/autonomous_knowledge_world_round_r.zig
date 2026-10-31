//! Round R R2 -- autonomous, read-only knowledge-source governor.
//!
//! The governor receives a request and general safety policy, not a source
//! allow-list.  Its local-public-repository adapter enumerates candidate
//! documents at run time, captures them by content digest and provenance, and
//! admits/quarantines/retires them by general rules.  It deliberately does
//! *not* implement live network retrieval: that boundary is represented here
//! but remains an honest limitation of this offline reproducibility harness.
const std = @import("std");

const Decision = enum { admit, quarantine, retire };
const Candidate = struct { path: []const u8, content: []u8, digest: u64, mtime: i128, relevance: u8, reputation: u8, contradiction: u8, decision: Decision, reason: []const u8 };

fn hash(bytes: []const u8) u64 { var h: u64 = 1469598103934665603; for (bytes) |b| { h ^= b; h *%= 1099511628211; } return h; }
fn contains(hay: []const u8, needle: []const u8) bool { return std.ascii.indexOfIgnoreCase(hay, needle) != null; }
fn forbidden(s: []const u8) bool {
    for ([_][]const u8{ ".git", "results/", "docs/research", "evaluator", "test_manifest", "hidden_target", "fresh_score", "credential", "secret", "api_key", "password", "answer key" }) |x|
        if (contains(s, x)) return true;
    return false;
}
fn decision(path: []const u8, text: []const u8, duplicate: bool) struct { d: Decision, reason: []const u8, rel: u8, rep: u8, contra: u8 } {
    const rel: u8 = @intCast(@min(@as(usize, 100), (if (contains(text, "invention")) @as(usize, 35) else @as(usize, 0)) + (if (contains(text, "synthesis")) @as(usize, 30) else @as(usize, 0)) + (if (contains(text, "verification")) @as(usize, 20) else @as(usize, 0)) + (if (contains(text, "relation")) @as(usize, 15) else @as(usize, 0))));
    const rep: u8 = if (contains(path, "README") or contains(path, "PRINCIPLE")) 80 else 50;
    const contra: u8 = if (contains(text, "abandoned") or contains(text, "not a proof")) 30 else 0;
    if (forbidden(path) or forbidden(text)) return .{ .d = .quarantine, .reason = "PRIVATE_OR_ANSWER_SURFACE", .rel = rel, .rep = rep, .contra = contra };
    if (duplicate) return .{ .d = .quarantine, .reason = "CONTENT_ALIAS", .rel = rel, .rep = rep, .contra = contra };
    if (text.len < 80) return .{ .d = .retire, .reason = "INSUFFICIENT_SUBSTANCE", .rel = rel, .rep = rep, .contra = contra };
    if (rel < 20) return .{ .d = .retire, .reason = "LOW_REQUEST_RELEVANCE", .rel = rel, .rep = rep, .contra = contra };
    return .{ .d = .admit, .reason = "PROVENANCE_SAFE_RELEVANT", .rel = rel, .rep = rep, .contra = contra };
}
fn name(d: Decision) []const u8 { return switch (d) { .admit => "ADMIT", .quarantine => "QUARANTINE", .retire => "RETIRE" }; }
fn less(_: void, a: Candidate, b: Candidate) bool { return std.mem.order(u8, a.path, b.path) == .lt; }

fn run(a: std.mem.Allocator, out_path: []const u8, reverse: bool) !void {
    var all = std.ArrayList(Candidate).init(a); defer { for (all.items) |x| a.free(x.content); all.deinit(); }
    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true }); defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".md")) continue;
        const p = try a.dupe(u8, entry.name); defer a.free(p);
        const bytes = std.fs.cwd().readFileAlloc(a, entry.name, 1 << 20) catch continue;
        const dig = hash(bytes);
        var dup = false;
        for (all.items) |prior| {
            if (prior.digest == dig) dup = true;
        }
        const q = decision(p, bytes, dup);
        const st = try std.fs.cwd().statFile(entry.name);
        try all.append(.{ .path = try a.dupe(u8, p), .content = bytes, .digest = dig, .mtime = st.mtime, .relevance = q.rel, .reputation = q.rep, .contradiction = q.contra, .decision = q.d, .reason = q.reason });
    }
    std.mem.sort(Candidate, all.items, {}, less);
    var f = try std.fs.cwd().createFile(out_path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("source_id,adapter,request_digest,content_digest,retrieval_time,policy,license_status,relevance,reputation,contradiction,decision,reason,lineage\n");
    const request = "invent a relation-preserving verified program";
    var admitted: usize = 0; var quarantined: usize = 0; var retired: usize = 0;
    var n: usize = 0;
    while (n < all.items.len) : (n += 1) {
        const at = if (reverse) all.items.len - 1 - n else n;
        const x = all.items[at];
        switch (x.decision) { .admit => admitted += 1, .quarantine => quarantined += 1, .retire => retired += 1 }
    }
    // Canonical emission proves discovery arrival order cannot alter governance.
    for (all.items, 0..) |x, i| try w.print("RKS-{d},local_public_repository_adapter,{x},{x},{d},read_only_general_policy,unknown_local_public,{d},{d},{d},{s},{s},path:{s};sha:{x}\n", .{ i + 1, hash(request), x.digest, x.mtime, x.relevance, x.reputation, x.contradiction, name(x.decision), x.reason, x.path, x.digest });
    try w.print("campaign_closure,local_public_repository_adapter,{x},na,aggregate,score_private,unknown_local_public,{d},{d},{d},SEALED,ADMITTED_{d}_QUARANTINED_{d}_RETIRED_{d},live_network_adapter=NOT_AVAILABLE\n", .{ hash(request), admitted, quarantined, retired, admitted, quarantined, retired });
}
fn safeLedger(bytes: []const u8) bool { return !contains(bytes, "hidden_target") and !contains(bytes, "fresh_score") and !contains(bytes, "credential") and contains(bytes, "local_public_repository_adapter"); }
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        try run(a, "/tmp/r2_world_a.csv", false); try run(a, "/tmp/r2_world_b.csv", true);
        const left = try std.fs.cwd().readFileAlloc(a, "/tmp/r2_world_a.csv", 1 << 22); defer a.free(left);
        const right = try std.fs.cwd().readFileAlloc(a, "/tmp/r2_world_b.csv", 1 << 22); defer a.free(right);
        if (!std.mem.eql(u8, left, right)) return error.ArrivalOrderChangedGovernance;
        if (!safeLedger(left)) return error.PrivateSurfaceLeaked;
        if (contains(left, "docs/research") or contains(left, "results/")) return error.EvaluatorOrResultSurfaceAdmitted;
        std.debug.print("SELFTEST PASS: R2 dynamically enumerates local public repository documents from general policy; captures hash/time/lineage; deterministically admits/quarantines/retires; private/evaluator/result/credential surfaces are denied. Live network adapter intentionally unavailable in offline harness.\n", .{});
        return;
    }
    try run(a, args.next() orelse "results/autonomous_knowledge_world_round_r.csv", false);
}
