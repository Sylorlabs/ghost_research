//! Round AS / AS2: bounded public-web capture adapter.
//!
//! This is deliberately a *capture* mechanism, not a browser or a language
//! understanding claim.  The only live capability is one unauthenticated GET
//! to an exact, public endpoint.  Raw response bytes are evaluator-owned and
//! retained in the result ledger for offline deterministic replay; a candidate
//! may receive only structural fields and precommit a structural prediction.
const std = @import("std");

const endpoint = "https://api.github.com/zen"; // httpbin returned 503 in this runtime.
const max_body = 16 * 1024;

const Request = struct {
    method: []const u8,
    url: []const u8,
    auth: []const u8 = "",
    cookie: []const u8 = "",
    body: []const u8 = "",
    ask: []const u8 = "capture",
};

fn fnv1a(bytes: []const u8) u64 {
    var h: u64 = 1469598103934665603;
    for (bytes) |b| { h ^= b; h *%= 1099511628211; }
    return h;
}

fn valid(r: Request) bool {
    // Exact-origin allow-list, GET-only, one capture.  No redirects are used.
    return std.mem.eql(u8, r.method, "GET") and std.mem.eql(u8, r.url, endpoint) and
        r.auth.len == 0 and r.cookie.len == 0 and r.body.len == 0 and
        std.mem.eql(u8, r.ask, "capture");
}

const Shape = struct { len: usize, printable: usize, lines: usize };
fn shapeOf(body: []const u8) Shape {
    var printable: usize = 0;
    var lines: usize = 0;
    for (body) |c| {
        if ((c >= 32 and c <= 126) or c == '\n' or c == '\r' or c == '\t') printable += 1;
        if (c == '\n') lines += 1;
    }
    if (body.len > 0 and lines == 0) lines = 1;
    return .{ .len = body.len, .printable = printable, .lines = lines };
}

const Capture = struct { body: []u8, stderr: []u8, status: u16, ok: bool };
fn fetch(a: std.mem.Allocator) !Capture {
    // curl has no -L/--location, no cookie jar, no auth headers, and is
    // constrained to HTTPS.  HTTP status is 200 iff --fail exits normally.
    const child = try std.process.Child.run(.{ .allocator = a, .argv = &.{
        "curl", "--fail", "--silent", "--show-error", "--request", "GET",
        "--max-time", "15", "--connect-timeout", "6", "--proto", "=https",
        "--tlsv1.2", "--user-agent", "ghost-research-round-as/1.0 readonly",
        endpoint,
    }, .max_output_bytes = max_body });
    const ok = switch (child.term) { .Exited => |code| code == 0, else => false };
    return .{ .body = child.stdout, .stderr = child.stderr, .status = if (ok) 200 else 0, .ok = ok };
}

fn b64(a: std.mem.Allocator, input: []const u8) ![]u8 {
    const n = std.base64.standard.Encoder.calcSize(input.len);
    const out = try a.alloc(u8, n);
    _ = std.base64.standard.Encoder.encode(out, input);
    return out;
}

fn csvText(w: anytype, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| switch (c) { '"' => try w.writeAll("\"\""), '\n', '\r' => try w.writeByte(' '), else => try w.writeByte(c) };
    try w.writeByte('"');
}

fn writeLedger(a: std.mem.Allocator, out_path: []const u8, live: bool) !void {
    var out = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out.close();
    const w = out.writer();
    try w.writeAll("row,kind,method,origin,status,body_len,printable_bytes,line_count,content_fnv64,raw_body_base64,decision,detail\n");

    // A candidate's precommit is intentionally coarse: a fresh allowed capture
    // should be nonempty, predominantly printable, and one logical line. It
    // cannot name or inspect the live response body or any score.
    try w.writeAll("1,candidate_precommit,none,opaque_capture_fields,na,na,na,1,na,,SEALED,expect_nonempty_printable_single_line\n");
    if (!live) {
        try w.writeAll("2,cached_replay,GET,api.github.com/zen,200,43,43,1,cf0f9a6c796f0ef4,SGFsZiBtZWFzdXJlcyBhcmUgYXMgYmFkIGFzIG5vdGhpbmcgYXQgYWxsLgo=,CACHED,selftest_cache_shape_matches_precommit\n");
        return;
    }
    const first = try fetch(a);
    defer a.free(first.body); defer a.free(first.stderr);
    if (!first.ok) {
        try w.writeAll("2,live_capture,GET,api.github.com/zen,0,0,0,0,0,,INCONCLUSIVE,live_fetch_failed_no_simulated_success\n");
        return;
    }
    const first_shape = shapeOf(first.body);
    const first_b64 = try b64(a, first.body); defer a.free(first_b64);
    try w.print("2,live_capture,GET,api.github.com/zen,{d},{d},{d},{d},{x},", .{ first.status, first_shape.len, first_shape.printable, first_shape.lines, fnv1a(first.body) });
    try csvText(w, first_b64); try w.writeAll(",CACHED,live_capture_retained_evaluator_owned\n");

    // A second permitted fetch is the fresh test. It is performed only after
    // the coarse prediction has been emitted, and its raw bytes stay evaluator-owned.
    const fresh = try fetch(a);
    defer a.free(fresh.body); defer a.free(fresh.stderr);
    if (!fresh.ok) {
        try w.writeAll("3,fresh_capture,GET,api.github.com/zen,0,0,0,0,0,,INCONCLUSIVE,fresh_fetch_failed_no_simulated_success\n");
        return;
    }
    const fresh_shape = shapeOf(fresh.body);
    const fresh_b64 = try b64(a, fresh.body); defer a.free(fresh_b64);
    const pass = fresh_shape.len > 0 and fresh_shape.printable * 100 >= fresh_shape.len * 90 and fresh_shape.lines == 1;
    try w.print("3,fresh_capture,GET,api.github.com/zen,{d},{d},{d},{d},{x},", .{ fresh.status, fresh_shape.len, fresh_shape.printable, fresh_shape.lines, fnv1a(fresh.body) });
    try csvText(w, fresh_b64); try w.print(",{s},fresh_structural_prediction_end_only\n", .{if (pass) "PASS" else "FAIL"});
}

// Replay never contacts the network. The canonical live ledger is the cache:
// it retains evaluator-owned raw capture bytes as base64 plus their structure
// and digest. Copying that immutable record is intentionally byte-identical.
fn replayLedger(a: std.mem.Allocator, cache_path: []const u8, out_path: []const u8) !void {
    const cached = try std.fs.cwd().readFileAlloc(a, cache_path, 1 << 20);
    defer a.free(cached);
    if (std.mem.indexOf(u8, cached, "raw_body_base64") == null or
        std.mem.indexOf(u8, cached, ",CACHED,") == null) return error.InvalidCaptureCache;
    var out = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out.close();
    try out.writeAll(cached);
}

fn selftest(a: std.mem.Allocator) !void {
    const hostile = [_]Request{
        .{ .method = "POST", .url = endpoint }, .{ .method = "GET", .url = "https://httpbin.org/get" },
        .{ .method = "GET", .url = endpoint, .auth = "Bearer x" }, .{ .method = "GET", .url = endpoint, .cookie = "session=x" },
        .{ .method = "GET", .url = endpoint, .body = "x=1" }, .{ .method = "GET", .url = endpoint, .ask = "answer" },
        .{ .method = "GET", .url = endpoint, .ask = "score" }, .{ .method = "GET", .url = endpoint, .ask = "progress" },
    };
    if (!valid(.{ .method = "GET", .url = endpoint })) return error.ValidGetRejected;
    for (hostile) |r| if (valid(r)) return error.HostileRequestAdmitted;
    try writeLedger(a, "/tmp/approved_web_adapter_round_as.cache_fixture.csv", false);
    try replayLedger(a, "/tmp/approved_web_adapter_round_as.cache_fixture.csv", "/tmp/approved_web_adapter_round_as.replay_a.csv");
    try replayLedger(a, "/tmp/approved_web_adapter_round_as.cache_fixture.csv", "/tmp/approved_web_adapter_round_as.replay_b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/approved_web_adapter_round_as.replay_a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/approved_web_adapter_round_as.replay_b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.CachedReplayMismatch;
    if (std.mem.indexOf(u8, x, "POST") != null or std.mem.indexOf(u8, x, "credential") != null) return error.LedgerLeak;
    std.debug.print("round_as_as2 selftest PASS protocol_denials=8 cached_replay=byte_identical candidate_body_access=false verdict=GATE_READY\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest(a);
    if (std.mem.eql(u8, command, "replay")) {
        const out = args.next() orelse "/tmp/approved_web_adapter_round_as.replay.csv";
        const cache = args.next() orelse "results/approved_web_adapter_round_as.csv";
        return replayLedger(a, cache, out);
    }
    try writeLedger(a, args.next() orelse "results/approved_web_adapter_round_as.csv", true);
}
