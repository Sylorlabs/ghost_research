//! AX4: candidate/evaluator bridge for the AW staged artifacts.
//!
//! `emit` is candidate-side: it sees only a staged payload plus an opaque
//! contract/token and writes a typed structural witness where its grammar fits.
//! `evaluate` is evaluator-side: it independently rebuilds the witness from
//! those payload bytes.  These modes are separate processes, but they are NOT
//! OS-isolated; this is a rigorous local protocol integration, not a claim of
//! hostile-sandbox security or autonomous invention.
const std = @import("std");

const Kind = enum { declarations, csv_width, sleep_loop, missing_arg };
fn hash(b: []const u8) u64 {
    return std.hash.Wyhash.hash(0, b);
}
fn name(k: Kind) []const u8 {
    return switch (k) {
        .declarations => "declarations",
        .csv_width => "csv_width",
        .sleep_loop => "sleep_loop",
        .missing_arg => "missing_arg",
    };
}
fn kindFor(manifest: []const u8) ?Kind {
    if (std.mem.indexOf(u8, manifest, "kind=source_structure") != null) return .declarations;
    if (std.mem.indexOf(u8, manifest, "kind=csv_parser_integrity") != null) return .csv_width;
    if (std.mem.indexOf(u8, manifest, "kind=performance_proxy") != null) return .sleep_loop;
    if (std.mem.indexOf(u8, manifest, "kind=behavior_property") != null) return .missing_arg;
    return null;
}
fn tokenFor(manifest: []const u8) !u64 {
    const p = std.mem.indexOf(u8, manifest, "token=") orelse return error.NoToken;
    const rest = manifest[p + 6 ..];
    const e = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    return std.fmt.parseInt(u64, rest[0..e], 16);
}
fn lineCommentBefore(b: []const u8, p: usize) bool {
    const s = std.mem.lastIndexOfScalar(u8, b[0..p], '\n') orelse 0;
    return std.mem.indexOf(u8, b[s..p], "//") != null;
}
fn all(out: *std.ArrayList(usize), b: []const u8, needle: []const u8) !void {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, b, at, needle)) |p| {
        try out.append(p);
        at = p + needle.len;
    }
}
fn brace(b: []const u8, p: usize) ?usize {
    var d: usize = 0;
    var i = p;
    while (i < b.len) : (i += 1) {
        if (b[i] == '{') d += 1 else if (b[i] == '}') {
            if (d == 0) return null;
            d -= 1;
            if (d == 0) return i;
        }
    }
    return null;
}
fn witness(a: std.mem.Allocator, k: Kind, b: []const u8) ![]u8 {
    var o = std.ArrayList(u8).init(a);
    errdefer o.deinit();
    var first = true;
    switch (k) {
        .declarations => {
            var ps = std.ArrayList(usize).init(a);
            defer ps.deinit();
            try all(&ps, b, "pub fn ");
            for (ps.items) |p| {
                if (!lineCommentBefore(b, p)) {
                    if (!first) try o.append(',');
                    first = false;
                    try o.writer().print("{d}", .{p});
                }
            }
        },
        .csv_width => {
            var ls = std.mem.splitScalar(u8, b, '\n');
            const h = ls.next() orelse "";
            const f = std.mem.count(u8, h, ",") + 1;
            try o.writer().print("h{d}:", .{f});
            var row: usize = 1;
            while (ls.next()) |raw| : (row += 1) {
                const l = std.mem.trimRight(u8, raw, "\r");
                if (l.len == 0) continue;
                const got = std.mem.count(u8, l, ",") + 1;
                if (got != f) {
                    if (!first) try o.append(',');
                    first = false;
                    try o.writer().print("{d}:{d}", .{ row, got });
                }
            }
        },
        .sleep_loop => {
            var ps = std.ArrayList(usize).init(a);
            defer ps.deinit();
            try all(&ps, b, "std.time.sleep");
            for (ps.items) |p| {
                const w = std.mem.lastIndexOf(u8, b[0..p], "while (") orelse continue;
                const op = std.mem.indexOfPos(u8, b, w, "{") orelse continue;
                const e = brace(b, op) orelse continue;
                if (p > e) continue;
                if (!first) try o.append(',');
                first = false;
                try o.writer().print("{d}:{d}:{d}", .{ p, w, e });
            }
        },
        .missing_arg => {
            var ps = std.ArrayList(usize).init(a);
            defer ps.deinit();
            try all(&ps, b, "return error.MissingArg");
            for (ps.items) |p| {
                const s = std.mem.lastIndexOfScalar(u8, b[0..p], '\n') orelse 0;
                const e = p + (std.mem.indexOfScalar(u8, b[p..], '\n') orelse b.len - p);
                if (!first) try o.append(',');
                first = false;
                try o.writer().print("{d}:{d}:{d}", .{ p, s, e });
            }
        },
    }
    if (first) try o.appendSlice("none");
    return o.toOwnedSlice();
}
fn count(w: []const u8) usize {
    if (std.mem.eql(u8, w, "none")) return 0;
    return 1 + std.mem.count(u8, w, ",");
}
fn supports(grammar: []const u8, k: Kind) bool {
    return (std.mem.eql(u8, grammar, "source") and (k == .declarations or k == .missing_arg)) or (std.mem.eql(u8, grammar, "csv") and k == .csv_width) or (std.mem.eql(u8, grammar, "control_flow") and k == .sleep_loop);
}
fn path(buf: []u8, root: []const u8, id: usize, leaf: []const u8) ![]u8 {
    return std.fmt.bufPrint(buf, "{s}/instance-{d:0>2}/{s}", .{ root, id, leaf });
}
fn emit(a: std.mem.Allocator, root: []const u8, worker: []const u8, grammar: []const u8, out_path: []const u8) !void {
    var f = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer f.close();
    const tool = try std.fmt.allocPrint(a, "AX4 native typed witness tool; worker={s}; grammar={s}; candidate-mode", .{ worker, grammar });
    defer a.free(tool);
    for (0..4) |id| {
        var mb: [512]u8 = undefined;
        var pb: [512]u8 = undefined;
        const m = try path(&mb, root, id, "task.txt");
        const p = try path(&pb, root, id, "payload");
        const manifest = try std.fs.cwd().readFileAlloc(a, m, 1 << 20);
        defer a.free(manifest);
        const payload = try std.fs.cwd().readFileAlloc(a, p, 16 << 20);
        defer a.free(payload);
        const k = kindFor(manifest) orelse return error.BadKind;
        const token = try tokenFor(manifest);
        if (!supports(grammar, k)) {
            try f.writer().print("NO_WITNESS {x} {s} worker={s} grammar={s}\n", .{ token, name(k), worker, grammar });
            continue;
        }
        const w = try witness(a, k, payload);
        defer a.free(w);
        try f.writer().print("WITNESS_V1 {x} {s} {x} {x} {d} {s}\n", .{ token, name(k), hash(tool), hash(payload), count(w), w });
    }
}
const Parsed = struct { token: u64, k: []const u8, tool: u64, payload: u64, n: usize, w: []const u8 };
fn parse(line: []const u8) ?Parsed {
    var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
    if (!std.mem.eql(u8, it.next() orelse return null, "WITNESS_V1")) return null;
    const token = std.fmt.parseInt(u64, it.next() orelse return null, 16) catch return null;
    const k = it.next() orelse return null;
    const tool = std.fmt.parseInt(u64, it.next() orelse return null, 16) catch return null;
    const payload = std.fmt.parseInt(u64, it.next() orelse return null, 16) catch return null;
    const n = std.fmt.parseInt(usize, it.next() orelse return null, 10) catch return null;
    const w = it.next() orelse return null;
    if (it.next() != null or tool == 0) return null;
    return .{ .token = token, .k = k, .tool = tool, .payload = payload, .n = n, .w = w };
}
fn evaluate(a: std.mem.Allocator, root: []const u8, claims_path: []const u8, out_path: []const u8) !void {
    const claims = try std.fs.cwd().readFileAlloc(a, claims_path, 8 << 20);
    defer a.free(claims);
    var lines = std.mem.splitScalar(u8, claims, '\n');
    var out = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out.close();
    try out.writer().writeAll("task,worker,claimed_kind,accepted,reason\n");
    var accepted: [4]usize = .{0} ** 4;
    var total: usize = 0;
    for (0..27) |worker| for (0..4) |id| {
        const line = lines.next() orelse "";
        var mb: [512]u8 = undefined;
        var pb: [512]u8 = undefined;
        const m = try path(&mb, root, id, "task.txt");
        const p = try path(&pb, root, id, "payload");
        const manifest = try std.fs.cwd().readFileAlloc(a, m, 1 << 20);
        defer a.free(manifest);
        const payload = try std.fs.cwd().readFileAlloc(a, p, 16 << 20);
        defer a.free(payload);
        const k = kindFor(manifest) orelse return error.BadKind;
        const tok = try tokenFor(manifest);
        const expected = try witness(a, k, payload);
        defer a.free(expected);
        const q = parse(line);
        const ok = q != null and q.?.token == tok and std.mem.eql(u8, q.?.k, name(k)) and q.?.payload == hash(payload) and q.?.n == count(expected) and std.mem.eql(u8, q.?.w, expected);
        if (ok) {
            accepted[id] += 1;
            total += 1;
        }
        try out.writer().print("{d},{d},{s},{s},{s}\n", .{ id, worker, name(k), if (ok) "accepted" else "rejected", if (q == null) "no_or_malformed_typed_witness" else if (ok) "canonical_witness_matches" else "typed_witness_mismatch" });
    };
    while (lines.next()) |extra| if (std.mem.trim(u8, extra, " \t\r\n").len != 0) return error.ExtraClaims;
    try out.writer().print("summary,all,all,{d}/108,per_task={d}|{d}|{d}|{d}; protocol=typed_witness; limitation=local_modes_not_OS_isolated\n", .{ total, accepted[0], accepted[1], accepted[2], accepted[3] });
}
pub fn main() !void {
    var it = std.process.args();
    _ = it.next();
    const cmd = it.next() orelse return error.MissingCommand;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    if (std.mem.eql(u8, cmd, "emit")) return emit(a, it.next() orelse return error.MissingRoot, it.next() orelse return error.MissingWorker, it.next() orelse return error.MissingGrammar, it.next() orelse return error.MissingOutput);
    if (std.mem.eql(u8, cmd, "evaluate")) return evaluate(a, it.next() orelse return error.MissingRoot, it.next() orelse return error.MissingClaims, it.next() orelse return error.MissingOutput);
    return error.UnsupportedCommand;
}
