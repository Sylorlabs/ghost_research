//! AX1: evaluator-owned typed-witness protocol.  A scalar is never a claim.
//! Candidate envelope: WITNESS_V1 <token_hex> <kind> <tool_hash_hex>
//! <payload_hash_hex> <summary_decimal> <canonical_witness>
//! The evaluator reconstructs canonical witnesses directly from sealed bytes.
const std = @import("std");

const Kind = enum { declarations, csv_width, sleep_loop, missing_arg };
const Task = struct { kind: Kind, token: u64, payload: []const u8 };
fn h(b: []const u8) u64 { return std.hash.Wyhash.hash(0, b); }
fn kindName(k: Kind) []const u8 { return switch (k) { .declarations => "declarations", .csv_width => "csv_width", .sleep_loop => "sleep_loop", .missing_arg => "missing_arg" }; }

fn appendNum(out: *std.ArrayList(u8), n: usize) !void { try out.writer().print("{d}", .{n}); }
fn lineCommentBefore(b: []const u8, p: usize) bool {
    const start = std.mem.lastIndexOfScalar(u8, b[0..p], '\n') orelse 0;
    const line = b[start..p];
    return std.mem.indexOf(u8, line, "//") != null;
}
fn findAll(out: *std.ArrayList(usize), b: []const u8, needle: []const u8) !void {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, b, at, needle)) |p| { try out.append(p); at = p + needle.len; }
}
fn matchingBrace(b: []const u8, open: usize) ?usize {
    var depth: usize = 0; var i = open;
    while (i < b.len) : (i += 1) { if (b[i] == '{') depth += 1; if (b[i] == '}') { if (depth == 0) return null; depth -= 1; if (depth == 0) return i; } }
    return null;
}
/// Canonical witness intentionally contains exact offsets/spans, not merely a count.
fn witness(a: std.mem.Allocator, task: Task) ![]u8 {
    var out = std.ArrayList(u8).init(a); errdefer out.deinit();
    const b = task.payload;
    switch (task.kind) {
        .declarations => {
            var ps = std.ArrayList(usize).init(a); defer ps.deinit(); try findAll(&ps, b, "pub fn ");
            var first = true;
            for (ps.items) |p| {
                if (!lineCommentBefore(b, p)) { if (!first) try out.append(','); first = false; try appendNum(&out, p); }
            }
            if (first) try out.appendSlice("none");
        },
        .csv_width => {
            var lines = std.mem.splitScalar(u8, b, '\n'); const header = lines.next() orelse ""; const fields = std.mem.count(u8, header, ",") + 1;
            try out.writer().print("h{d}:", .{fields}); var row: usize = 1; var first = true;
            while (lines.next()) |raw| : (row += 1) { const line = std.mem.trimRight(u8, raw, "\r"); if (line.len == 0) continue; const got = std.mem.count(u8, line, ",") + 1; if (got != fields) { if (!first) try out.append(','); first = false; try out.writer().print("{d}:{d}", .{ row, got }); } }
            if (first) try out.appendSlice("none");
        },
        .sleep_loop => {
            var sleeps = std.ArrayList(usize).init(a); defer sleeps.deinit(); try findAll(&sleeps, b, "std.time.sleep");
            var first = true;
            for (sleeps.items) |p| {
                const before = b[0..p]; const w = std.mem.lastIndexOf(u8, before, "while (") orelse continue;
                const open = std.mem.indexOfPos(u8, b, w, "{") orelse continue; const end = matchingBrace(b, open) orelse continue;
                if (p > end) continue;
                if (!first) try out.append(','); first = false; try out.writer().print("{d}:{d}:{d}", .{ p, w, end });
            }
            if (first) try out.appendSlice("none");
        },
        .missing_arg => {
            var ps = std.ArrayList(usize).init(a); defer ps.deinit(); try findAll(&ps, b, "return error.MissingArg");
            var first = true;
            for (ps.items) |p| { const start = std.mem.lastIndexOfScalar(u8, b[0..p], '\n') orelse 0; const rel_end = std.mem.indexOfScalar(u8, b[p..], '\n') orelse (b.len - p); const end = p + rel_end; if (!first) try out.append(','); first = false; try out.writer().print("{d}:{d}:{d}", .{p, start, end}); }
            if (first) try out.appendSlice("none");
        },
    }
    return out.toOwnedSlice();
}
fn summary(w: []const u8) usize { if (std.mem.eql(u8, w, "none")) return 0; var n: usize = 1; for (w) |c| { if (c == ',') n += 1; } return n; }
const Parsed = struct { token: u64, kind: []const u8, tool: u64, payload: u64, count: usize, w: []const u8 };
fn parse(line: []const u8) ?Parsed {
    var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
    if (!std.mem.eql(u8, it.next() orelse return null, "WITNESS_V1")) return null;
    const token = std.fmt.parseInt(u64, it.next() orelse return null, 16) catch return null;
    const k = it.next() orelse return null;
    const tool = std.fmt.parseInt(u64, it.next() orelse return null, 16) catch return null;
    const payload = std.fmt.parseInt(u64, it.next() orelse return null, 16) catch return null;
    const count = std.fmt.parseInt(usize, it.next() orelse return null, 10) catch return null;
    const w = it.next() orelse return null;
    if (it.next() != null or tool == 0 or w.len == 0) return null;
    return .{ .token = token, .kind = k, .tool = tool, .payload = payload, .count = count, .w = w };
}
fn accepts(a: std.mem.Allocator, task: Task, line: []const u8) !bool {
    const p = parse(line) orelse return false;
    if (p.token != task.token or !std.mem.eql(u8, p.kind, kindName(task.kind)) or p.payload != h(task.payload)) return false;
    const expected = try witness(a, task); defer a.free(expected);
    return p.count == summary(expected) and std.mem.eql(u8, p.w, expected);
}
fn makeClaim(a: std.mem.Allocator, task: Task, tool: []const u8) ![]u8 {
    const w = try witness(a, task); defer a.free(w); return std.fmt.allocPrint(a, "WITNESS_V1 {x} {s} {x} {x} {d} {s}", .{task.token, kindName(task.kind), h(tool), h(task.payload), summary(w), w});
}
fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const tasks = [_]Task{
        .{.kind=.declarations,.token=0x101,.payload="// pub fn fake() {}\npub fn real() void {}\n"},
        .{.kind=.csv_width,.token=0x102,.payload="a,b,c\n1,2,3\n4,5\n6,7,8,9\n"},
        .{.kind=.sleep_loop,.token=0x103,.payload="while (ok) {\n std.time.sleep(1);\n}\nstd.time.sleep(2);\n"},
        .{.kind=.missing_arg,.token=0x104,.payload="if (x == null) return error.MissingArg;\n"},
    };
    for (tasks) |t| { const c = try makeClaim(a, t, "forged tool source"); defer a.free(c); if (!try accepts(a, t, c)) return error.ValidRejected;
        const scalar = try std.fmt.allocPrint(a, "CLAIM {x} 1", .{t.token}); defer a.free(scalar); if (try accepts(a,t,scalar)) return error.ScalarAccepted;
        const bad = try std.fmt.allocPrint(a, "{s}x", .{c}); defer a.free(bad); if (try accepts(a,t,bad)) return error.MalformedWitnessAccepted;
        const unrelated = try std.fmt.allocPrint(a, "{s}\n", .{t.payload}); defer a.free(unrelated); const t2=Task{.kind=t.kind,.token=t.token,.payload=unrelated}; const w1=try witness(a,t); defer a.free(w1); const w2=try witness(a,t2); defer a.free(w2); if (!std.mem.eql(u8,w1,w2)) return error.UnrelatedMutationChangedWitness;
    }
    // Relevant change: adding a declaration must change the accepted witness.
    const old=tasks[0]; const changed=Task{.kind=.declarations,.token=old.token,.payload="// pub fn fake() {}\npub fn real() void {}\npub fn added() void {}\n"}; const wo=try witness(a,old); defer a.free(wo); const wn=try witness(a,changed); defer a.free(wn); if (std.mem.eql(u8,wo,wn)) return error.RelevantMutationDidNotChange;
    std.debug.print("round_ax1 selftest PASS typed_kinds=4 scalar_claims_rejected=true malformed_witnesses_rejected=true payload_hash_bound=true counterfactual_relevant_changes=true unrelated_bytes_stable=true replay=deterministic\n", .{});
}
pub fn main() !void { var it=std.process.args(); _=it.next(); const cmd=it.next() orelse "selftest"; if (std.mem.eql(u8,cmd,"selftest") or std.mem.eql(u8,cmd,"replay")) return selftest(); return error.UnsupportedCommand; }
