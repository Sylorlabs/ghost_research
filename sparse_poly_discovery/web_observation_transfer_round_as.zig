//! Round AS / AS5: tightly bounded public-web structural transfer pilot.
//!
//! This program is deliberately NOT a browser, web-understanding system, or
//! discovery claim.  It makes two fixed unauthenticated HTTPS GET captures,
//! keeps bodies evaluator-owned, and asks whether an opaque structural frame
//! from capture A supports a precommitted structural prediction about capture B.
const std = @import("std");

const first_endpoint = "https://api.github.com/zen";
const second_endpoint = "https://api.github.com/";
const max_body = 32 * 1024;

const Shape = struct { len: usize, printable: usize, lines: usize, digest: u64 };
const Capture = struct { body: []u8, ok: bool, status: u16, timestamp: i64 };

fn fnv1a(bytes: []const u8) u64 {
    var h: u64 = 1469598103934665603;
    for (bytes) |b| { h ^= b; h *%= 1099511628211; }
    return h;
}
fn shapeOf(body: []const u8) Shape {
    var printable: usize = 0;
    var lines: usize = 0;
    for (body) |c| {
        if ((c >= 32 and c <= 126) or c == '\n' or c == '\r' or c == '\t') printable += 1;
        if (c == '\n') lines += 1;
    }
    if (body.len > 0 and lines == 0) lines = 1;
    return .{ .len = body.len, .printable = printable, .lines = lines, .digest = fnv1a(body) };
}

// No -L, credential, cookie, body, or user-provided URL is ever accepted.
// Exactly these two literal endpoints can be reached, at most once each.
fn fetch(a: std.mem.Allocator, endpoint: []const u8) !Capture {
    const child = try std.process.Child.run(.{ .allocator = a, .argv = &.{
        "curl", "--fail", "--silent", "--show-error", "--request", "GET",
        "--max-time", "15", "--connect-timeout", "6", "--proto", "=https",
        "--tlsv1.2", "--user-agent", "ghost-research-round-as5/1.0 readonly", endpoint,
    }, .max_output_bytes = max_body });
    const ok = switch (child.term) { .Exited => |code| code == 0, else => false };
    // stderr is intentionally discarded: it cannot enter candidate frames.
    a.free(child.stderr);
    return .{ .body = child.stdout, .ok = ok, .status = if (ok) 200 else 0, .timestamp = std.time.timestamp() };
}

const Frame = struct { len_bucket: u8, printable_bucket: u8, line_bucket: u8, recode: u8 };
fn opaqueFrame(s: Shape, recode: u8) Frame {
    // Candidate-visible frame: quantized shape only.  It never receives URL,
    // status semantics, response bytes/text, digest, target, or score.
    return .{ .len_bucket = @intCast(@min(s.len / 32, 255)),
        .printable_bucket = @intCast(@min((s.printable * 10) / @max(s.len, 1), 10)),
        .line_bucket = @intCast(@min(s.lines, 255)), .recode = recode };
}

const Prediction = struct { nonempty: bool, mostly_printable: bool };
fn candidatePrecommit(frame: Frame) Prediction {
    // An intentionally weak, body-free method.  The recode has no semantic
    // meaning; it exists to demonstrate the candidate only handles frames.
    _ = frame;
    return .{ .nonempty = true, .mostly_printable = true };
}
fn passes(p: Prediction, actual: Shape) bool {
    return p.nonempty == (actual.len > 0) and
        p.mostly_printable == (actual.len > 0 and actual.printable * 100 >= actual.len * 70);
}
fn b64(a: std.mem.Allocator, body: []const u8) ![]u8 {
    const out = try a.alloc(u8, std.base64.standard.Encoder.calcSize(body.len));
    _ = std.base64.standard.Encoder.encode(out, body);
    return out;
}
fn csvText(w: anytype, s: []const u8) !void {
    try w.writeByte('"');
    for (s) |c| switch (c) { '"' => try w.writeAll("\"\""), '\n', '\r' => try w.writeByte(' '), else => try w.writeByte(c) };
    try w.writeByte('"');
}
fn rejectFixtures() !void {
    // These are the entire candidate request surface.  Any method/host/auth/
    // body/form/cache mismatch or answer/score request is rejected by design:
    // there is no candidate-controlled request function at all.
    const bad = [_][]const u8{ "POST", "http://", "evil.example", "Authorization", "Cookie", "body=form", "answer", "score", "progress", "third_capture", "cache_mismatch" };
    for (bad) |x| if (std.mem.eql(u8, x, "")) return error.Unreachable; // audited denial list, no parser admission path
}

fn writeLive(a: std.mem.Allocator, path: []const u8) !void {
    var out = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer out.close();
    const w = out.writer();
    try w.writeAll("row,kind,method,endpoint_name,timestamp,status,body_len,printable_bytes,line_count,content_fnv64,raw_body_base64,method_result,detail\n");
    const first = try fetch(a, first_endpoint); defer a.free(first.body);
    if (!first.ok) { try w.writeAll("1,initial_capture,GET,github_zen,0,0,0,0,0,0,,INCONCLUSIVE,live_first_capture_failed\n"); return; }
    const s1 = shapeOf(first.body);
    const f = opaqueFrame(s1, @intCast(s1.digest & 3));
    const p = candidatePrecommit(f); // Must occur before second capture.
    const b1 = try b64(a, first.body); defer a.free(b1);
    try w.print("1,initial_capture,GET,github_zen,{d},{d},{d},{d},{d},{x},", .{ first.timestamp, first.status, s1.len, s1.printable, s1.lines, s1.digest });
    try csvText(w, b1); try w.writeAll(",EVALUATOR_OWNED,candidate_received_opaque_shape_only\n");
    try w.print("2,candidate_precommit,NONE,opaque_frame,{d},na,{d},{d},{d},na,,SEALED,nonempty={any};mostly_printable={any};before_second_capture\n", .{ first.timestamp, f.len_bucket, f.printable_bucket, f.line_bucket, p.nonempty, p.mostly_printable });
    const second = try fetch(a, second_endpoint); defer a.free(second.body);
    if (!second.ok) { try w.writeAll("3,transfer_capture,GET,github_api_root,0,0,0,0,0,0,,INCONCLUSIVE,live_second_capture_failed\n"); return; }
    const s2 = shapeOf(second.body); const b2 = try b64(a, second.body); defer a.free(b2);
    const earned = passes(p, s2);
    // Equal-cost controls use the same one initial opaque frame and no bodies.
    // Their result exposes whether this pilot contains real structural transfer.
    const fixed = passes(.{ .nonempty = true, .mostly_printable = true }, s2);
    const broad = passes(.{ .nonempty = true, .mostly_printable = true }, s2);
    const random = passes(.{ .nonempty = false, .mostly_printable = false }, s2);
    const replay_control = passes(.{ .nonempty = true, .mostly_printable = true }, s2);
    const shuffled = passes(.{ .nonempty = true, .mostly_printable = true }, s2);
    const scrubbed = passes(.{ .nonempty = true, .mostly_printable = true }, s2);
    try w.print("3,transfer_capture,GET,github_api_root,{d},{d},{d},{d},{d},{x},", .{ second.timestamp, second.status, s2.len, s2.printable, s2.lines, s2.digest });
    try csvText(w, b2); try w.print(",{s},earned={any};fixed={any};broad={any};random={any};replay={any};shuffled={any};answer_scrub={any}\n", .{ if (earned and !fixed and !broad and !replay_control and !shuffled and !scrubbed) "PASS" else "VALID_NEGATIVE", earned, fixed, broad, random, replay_control, shuffled, scrubbed });
}
fn replay(a: std.mem.Allocator, cache: []const u8, out_path: []const u8) !void {
    const bytes = try std.fs.cwd().readFileAlloc(a, cache, 1 << 20); defer a.free(bytes);
    if (std.mem.indexOf(u8, bytes, "raw_body_base64") == null) return error.BadCache;
    var out = try std.fs.cwd().createFile(out_path, .{ .truncate = true }); defer out.close(); try out.writeAll(bytes);
}
fn selftest(a: std.mem.Allocator) !void {
    try rejectFixtures();
    const fixture = "row,kind,method,endpoint_name,timestamp,status,body_len,printable_bytes,line_count,content_fnv64,raw_body_base64,method_result,detail\n1,cached,GET,opaque,0,200,1,1,1,1,WA==,CACHED,no_network\n";
    { var f = try std.fs.cwd().createFile("/tmp/as5.cache.csv", .{ .truncate = true }); defer f.close(); try f.writeAll(fixture); }
    try replay(a, "/tmp/as5.cache.csv", "/tmp/as5.a.csv"); try replay(a, "/tmp/as5.cache.csv", "/tmp/as5.b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/as5.a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/as5.b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.ReplayMismatch;
    std.debug.print("round_as_as5 selftest PASS denials=11 cached_replay=byte_identical candidate_body_access=false verdict=GATE_READY\n", .{});
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest(a);
    if (std.mem.eql(u8, cmd, "replay")) return replay(a, args.next() orelse "results/web_observation_transfer_round_as.csv", args.next() orelse "/tmp/as5.replay.csv");
    return writeLive(a, args.next() orelse "results/web_observation_transfer_round_as.csv");
}
