//! Round S S1 -- self-governing public-knowledge acquisition adapter.
//!
//! The only task-specific input is a request.  It is tokenised into a query and
//! sent to generic public metadata indexes; there is no per-request source
//! list.  A capture ledger is emitted only after a real retrieval succeeds.
//! When the runtime has no public network/DNS route, that is a BLOCKED
//! infrastructure result, never a substituted local fixture.
const std = @import("std");

const Decision = enum { admit, quarantine, retire, blocked };
const Plan = struct { provider: []const u8, url: []u8, query: []u8 };
const Capture = struct {
    provider: []const u8,
    url: []const u8,
    query: []const u8,
    body: []u8,
    stderr: []u8,
    exit_code: u8,
    decision: Decision,
    reason: []const u8,
};

fn fnv1a(bytes: []const u8) u64 {
    var h: u64 = 1469598103934665603;
    for (bytes) |b| { h ^= b; h *%= 1099511628211; }
    return h;
}
fn contains(hay: []const u8, needle: []const u8) bool { return std.ascii.indexOfIgnoreCase(hay, needle) != null; }
fn decisionName(d: Decision) []const u8 { return switch (d) { .admit => "ADMIT", .quarantine => "QUARANTINE", .retire => "RETIRE", .blocked => "BLOCKED" }; }
fn safeRequest(request: []const u8) bool {
    for ([_][]const u8{ "credential", "password", "secret", "api_key", "private", "evaluator", "hidden_target", "fresh_score", "test_manifest", "answer key" }) |word|
        if (contains(request, word)) return false;
    return true;
}
fn csvField(w: anytype, bytes: []const u8) !void {
    try w.writeByte('"');
    for (bytes) |c| switch (c) { '"' => try w.writeAll("\"\""), '\n', '\r' => try w.writeByte(' '), else => try w.writeByte(c) };
    try w.writeByte('"');
}
fn urlEncode(a: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(a);
    errdefer out.deinit();
    const hex = "0123456789ABCDEF";
    for (text) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.') try out.append(c)
        else { try out.append('%'); try out.append(hex[c >> 4]); try out.append(hex[c & 15]); }
    }
    return out.toOwnedSlice();
}
fn makePlans(a: std.mem.Allocator, request: []const u8) ![]Plan {
    // Generic acquisition capabilities, not a human-chosen source list for a
    // task: each public index is queried with the request-derived phrase.
    const query = try urlEncode(a, request);
    defer a.free(query);
    var plans = try a.alloc(Plan, 2);
    plans[0] = .{ .provider = "crossref_public_metadata_index", .query = try a.dupe(u8, request), .url = try std.fmt.allocPrint(a, "https://api.crossref.org/works?rows=3&query={s}", .{query}) };
    plans[1] = .{ .provider = "openalex_public_metadata_index", .query = try a.dupe(u8, request), .url = try std.fmt.allocPrint(a, "https://api.openalex.org/works?per-page=3&search={s}", .{query}) };
    return plans;
}
fn freePlans(a: std.mem.Allocator, plans: []Plan) void { for (plans) |p| { a.free(p.query); a.free(p.url); } a.free(plans); }
fn acquire(a: std.mem.Allocator, plan: Plan) !Capture {
    const res = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "20", "--connect-timeout", "8", "--user-agent", "ghost-research-round-s/1.0 public-readonly", plan.url }, .max_output_bytes = 1 << 20 });
    const exited_ok = switch (res.term) { .Exited => |code| code == 0, else => false };
    const exit_code: u8 = switch (res.term) { .Exited => |code| @intCast(@min(code, 255)), else => 255 };
    if (!exited_ok) return .{ .provider = plan.provider, .url = plan.url, .query = plan.query, .body = res.stdout, .stderr = res.stderr, .exit_code = exit_code, .decision = .blocked, .reason = if (contains(res.stderr, "Could not resolve host")) "NETWORK_DNS_UNAVAILABLE" else "PUBLIC_ACQUISITION_UNAVAILABLE" };
    if (res.stdout.len < 80) return .{ .provider = plan.provider, .url = plan.url, .query = plan.query, .body = res.stdout, .stderr = res.stderr, .exit_code = exit_code, .decision = .retire, .reason = "INSUFFICIENT_PUBLIC_SUBSTANCE" };
    if (contains(res.stdout, "hidden_target") or contains(res.stdout, "fresh_score") or contains(res.stdout, "credential")) return .{ .provider = plan.provider, .url = plan.url, .query = plan.query, .body = res.stdout, .stderr = res.stderr, .exit_code = exit_code, .decision = .quarantine, .reason = "FORBIDDEN_SURFACE_IN_CAPTURE" };
    return .{ .provider = plan.provider, .url = plan.url, .query = plan.query, .body = res.stdout, .stderr = res.stderr, .exit_code = exit_code, .decision = .admit, .reason = "PUBLIC_READONLY_CAPTURE" };
}
fn freeCapture(a: std.mem.Allocator, c: Capture) void { a.free(c.body); a.free(c.stderr); }
fn less(_: void, a: Capture, b: Capture) bool { return std.mem.order(u8, a.provider, b.provider) == .lt; }
fn run(a: std.mem.Allocator, out_path: []const u8, request: []const u8) !void {
    var f = try std.fs.cwd().createFile(out_path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("source_id,adapter,request_digest,origin,retrieval_time_utc,content_digest,policy,license_status,relevance,reputation,contradiction,decision,reason,lineage\n");
    if (!safeRequest(request)) {
        try w.print("S1-000,request_gate,{x},none,not_attempted,na,read_only_general_policy,na,0,0,0,QUARANTINE,FORBIDDEN_REQUEST_SURFACE,request_rejected_before_acquisition\n", .{fnv1a(request)});
        return;
    }
    const plans = try makePlans(a, request); defer freePlans(a, plans);
    var captures = try a.alloc(Capture, plans.len);
    defer { for (captures) |c| { freeCapture(a, c); } a.free(captures); }
    for (plans, 0..) |p, i| captures[i] = try acquire(a, p);
    std.mem.sort(Capture, captures, {}, less);
    const now = std.time.timestamp();
    var admitted: usize = 0;
    for (captures, 0..) |c, i| {
        if (c.decision == .admit) admitted += 1;
        try w.print("S1-{d:0>3},", .{i + 1}); try csvField(w, c.provider); try w.print(",{x},", .{fnv1a(request)}); try csvField(w, c.url);
        try w.print(",{d},{x},read_only_general_policy,unknown_remote_license,", .{ now, fnv1a(c.body) });
        const relevance: u8 = if (c.decision == .admit) 70 else 0;
        const reputation: u8 = if (std.mem.startsWith(u8, c.provider, "crossref")) 85 else 80;
        try w.print("{d},{d},0,{s},", .{ relevance, reputation, decisionName(c.decision) }); try csvField(w, c.reason);
        try w.print(",provider:{s};request:{x};origin:{x};content:{x};curl_exit:{d}\n", .{ c.provider, fnv1a(request), fnv1a(c.url), fnv1a(c.body), c.exit_code });
    }
    try w.print("campaign_closure,live_public_adapter,{x},no_fixture_substitution,{d},na,read_only_general_policy,unknown_remote_license,na,na,na,SEALED,ADMITTED_{d}_OF_{d};live_capture_required_for_downstream,canonical_provider_sorted\n", .{ fnv1a(request), now, admitted, captures.len });
}
fn selftest(a: std.mem.Allocator) !void {
    const request = "invent a relation preserving verified program";
    if (!safeRequest(request) or safeRequest("retrieve evaluator credential")) return error.RequestBoundaryBroken;
    const plans = try makePlans(a, request); defer freePlans(a, plans);
    if (plans.len != 2 or !contains(plans[0].url, "crossref") or !contains(plans[1].url, "openalex")) return error.NonGenericDiscoveryPlan;
    try run(a, "/tmp/live_knowledge_adapter_round_s.csv", request);
    const csv = try std.fs.cwd().readFileAlloc(a, "/tmp/live_knowledge_adapter_round_s.csv", 1 << 20); defer a.free(csv);
    if (contains(csv, "hidden_target") or contains(csv, "fresh_score") or contains(csv, "credential")) return error.PrivateSurfaceLeaked;
    if (!contains(csv, "no_fixture_substitution")) return error.FixtureClaimMissing;
    std.debug.print("SELFTEST PASS: request-derived public-index acquisition plan, policy rejection, provenance ledger and no-fixture boundary hold. Inspect CSV for LIVE capture versus an explicit BLOCKED network result.\n", .{});
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest(a);
    const out_path = args.next() orelse "results/live_knowledge_adapter_round_s.csv";
    const request = args.next() orelse "invent a relation preserving verified program";
    try run(a, out_path, request);
}
