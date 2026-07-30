//! L4 / Round L -- public-API family expedition.
//!
//! The policy reads only an opaque labelled transcript and the L3 diagnostics
//! endpoint.  It invokes the evaluator's public `query` endpoint for a
//! declared extension language.  It never opens target formula/audit material.
const std = @import("std");

const Tokens = [_][]const u8{ "L3-00", "L3-01", "L3-02" };
const Examples: usize = 12;
const BaselineCalls: usize = 412; // 2 + 128 + 186 + 96; published by diagnostics.
const ExtensionCalls: usize = 80; // a=0..15, modulus=2/3, all legal residues.

const Candidate = struct { a: u8, b: u8, c: u8 };
const Reply = struct { correct: usize, charged: usize };

fn countGE(x: u32, threshold: u8) usize {
    var z = x;
    var n: usize = 0;
    for (0..8) |_| {
        if (@as(u8, @truncate(z)) >= threshold) n += 1;
        z >>= 4;
    }
    return n;
}

// This is the proposed public extension: a count of cells above a cutpoint,
// reduced modulo 2 or 3.  There is no target-family branch here.  Parameters
// are ranked from opaque labelled examples only.
fn predicts(c: Candidate, x: u32) bool {
    const modulus: usize = c.b;
    return countGE(x, c.a) % modulus == c.c % modulus;
}

fn parseHex(text: []const u8) !u32 {
    if (text.len != 10 or !std.mem.startsWith(u8, text, "0x")) return error.BadOpaqueInput;
    return std.fmt.parseInt(u32, text[2..], 16);
}

const PublicExamples = struct {
    xs: [Tokens.len][Examples]u32 = undefined,
    ys: [Tokens.len][Examples]bool = undefined,
    counts: [Tokens.len]usize = .{0} ** Tokens.len,
};

fn tokenId(text: []const u8) !usize {
    for (Tokens, 0..) |token, i| if (std.mem.eql(u8, text, token)) return i;
    return error.BadOpaqueToken;
}

fn readTranscript(allocator: std.mem.Allocator, path: []const u8) !PublicExamples {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1 << 20);
    defer allocator.free(bytes);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const header = lines.next() orelse return error.EmptyTranscript;
    if (!std.mem.eql(u8, header, "protocol,record_type,policy_token,example_index,opaque_input,label")) return error.BadPublicSchema;
    var out = PublicExamples{};
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ',');
        var values: [6][]const u8 = undefined;
        var n: usize = 0;
        while (fields.next()) |field| {
            if (n == values.len) return error.PrivateColumnRejected;
            values[n] = field;
            n += 1;
        }
        if (n != values.len or !std.mem.eql(u8, values[1], "example")) return error.BadPublicRow;
        const id = try tokenId(values[2]);
        const index = try std.fmt.parseInt(usize, values[3], 10);
        if (index >= Examples or out.counts[id] != index) return error.BadExampleOrder;
        out.xs[id][index] = try parseHex(values[4]);
        out.ys[id][index] = try std.fmt.parseInt(u8, values[5], 10) != 0;
        out.counts[id] += 1;
    }
    for (out.counts) |n| if (n != Examples) return error.WrongTranscriptSize;
    return out;
}

fn candidateAt(index: usize) Candidate {
    // Canonical identity is explicit, so reverse/permutation controls cannot
    // substitute an advantageous prefix.
    var remaining = index;
    const a: u8 = @intCast(remaining / 5);
    remaining %= 5;
    if (remaining < 2) return .{ .a = a, .b = 2, .c = @intCast(remaining) };
    return .{ .a = a, .b = 3, .c = @intCast(remaining - 2) };
}

fn fitScore(examples: PublicExamples, id: usize, candidate: Candidate) usize {
    var score: usize = 0;
    for (0..Examples) |i| {
        if (predicts(candidate, examples.xs[id][i]) == examples.ys[id][i]) score += 1;
    }
    return score;
}

fn run(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try std.process.Child.run(.{ .allocator = allocator, .argv = argv, .max_output_bytes = 1 << 20 });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .Exited => |code| if (code == 0) return else return error.EvaluatorCallFailed,
        else => return error.EvaluatorCallFailed,
    }
}

fn readReply(allocator: std.mem.Allocator, path: []const u8) !Reply {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 4096);
    defer allocator.free(bytes);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next() orelse return error.EmptyQueryReply;
    const line = lines.next() orelse return error.EmptyQueryReply;
    var fields = std.mem.splitScalar(u8, line, ',');
    var values: [11][]const u8 = undefined;
    var n: usize = 0;
    while (fields.next()) |field| { if (n == values.len) return error.BadQueryReply; values[n] = field; n += 1; }
    if (n != values.len or !std.mem.eql(u8, values[1], "query") or !std.mem.eql(u8, values[3], "threshold")) return error.BadQueryReply;
    return .{ .correct = try std.fmt.parseInt(usize, values[8], 10), .charged = try std.fmt.parseInt(usize, values[10], 10) };
}

fn query(allocator: std.mem.Allocator, evaluator: []const u8, reply_path: []const u8, token: []const u8, candidate: Candidate) !Reply {
    var a_buf: [3]u8 = undefined; var b_buf: [3]u8 = undefined; var c_buf: [3]u8 = undefined;
    const a = try std.fmt.bufPrint(&a_buf, "{d}", .{candidate.a});
    const b = try std.fmt.bufPrint(&b_buf, "{d}", .{candidate.b});
    const c = try std.fmt.bufPrint(&c_buf, "{d}", .{candidate.c});
    try run(allocator, &.{ evaluator, "query", reply_path, token, "threshold", a, b, c });
    return readReply(allocator, reply_path);
}

fn diagnostics(allocator: std.mem.Allocator, evaluator: []const u8, path: []const u8, maxima: *[Tokens.len]usize) !void {
    try run(allocator, &.{ evaluator, "diagnostics", path });
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1 << 20); defer allocator.free(bytes);
    var lines = std.mem.splitScalar(u8, bytes, '\n'); _ = lines.next() orelse return error.EmptyDiagnostics;
    var rows: usize = 0;
    maxima.* = .{0} ** Tokens.len;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ','); var values: [8][]const u8 = undefined; var n: usize = 0;
        while (fields.next()) |field| { if (n == values.len) return error.BadDiagnostics; values[n] = field; n += 1; }
        if (n != values.len or !std.mem.eql(u8, values[1], "diagnostic")) return error.BadDiagnostics;
        const id = try tokenId(values[2]);
        const correct = try std.fmt.parseInt(usize, values[5], 10);
        maxima[id] = @max(maxima[id], correct);
        if (try std.fmt.parseInt(usize, values[7], 10) == 0) return error.UnchargedDiagnostic;
        rows += 1;
    }
    if (rows != Tokens.len * 4) return error.WrongDiagnosticsSize;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const transcript = args.next() orelse "results/l4.public.transcript.csv";
    const evaluator = args.next() orelse return error.MissingEvaluatorBinary;
    const output = args.next() orelse "results/family_expedition_round_l.csv";
    const examples = try readTranscript(allocator, transcript);
    var diag_path_buf: [512]u8 = undefined;
    const diag_path = try std.fmt.bufPrint(&diag_path_buf, "{s}.diagnostics.tmp", .{output});
    defer std.fs.cwd().deleteFile(diag_path) catch {};
    var maxima: [Tokens.len]usize = undefined;
    try diagnostics(allocator, evaluator, diag_path, &maxima);
    const out = try std.fs.cwd().createFile(output, .{ .truncate = true }); defer out.close();
    var w = out.writer();
    try w.writeAll("protocol,stage,policy_token,candidate_kind,a,b,c,public_fit,correct,baseline_correct,charged_calls,verdict,detail\n");
    var negative_targets: usize = 0;
    for (Tokens, 0..) |token, id| {
        const blank = maxima[id] * 1000 < 950 * Examples;
        try w.print("round_l_l4,blank_decision,{s},current_menu_max,0,0,0,0,{d},{d},{d},{s},trace_only_maximum\n", .{ token, maxima[id], maxima[id], BaselineCalls, if (blank) "blank" else "represented" });
        if (!blank) continue;
        var best_correct: usize = 0;
        var best_fit: usize = 0;
        var charged: usize = 0;
        // Full extension-bank sweep prevents proposal-prefix/identity cherry-picking.
        for (0..ExtensionCalls) |canonical| {
            const c = candidateAt(canonical);
            const reply_name = try std.fmt.allocPrint(allocator, "{s}.q.{s}.{d}.tmp", .{ output, token, canonical }); defer allocator.free(reply_name); defer std.fs.cwd().deleteFile(reply_name) catch {};
            const reply = try query(allocator, evaluator, reply_name, token, c);
            const fit = fitScore(examples, id, c);
            best_correct = @max(best_correct, reply.correct); best_fit = @max(best_fit, fit); charged += reply.charged;
            try w.print("round_l_l4,extension_query,{s},threshold,{d},{d},{d},{d},{d},{d},1,measured,canonical={d}\n", .{ token, c.a, c.b, c.c, fit, reply.correct, maxima[id], canonical });
        }
        // Spend the remaining allowance on an explicitly redundant, predeclared
        // sentinel so the comparison is exactly 412 charged calls, not cheaper.
        const sentinel = candidateAt(0);
        while (charged < BaselineCalls) {
            const reply_name = try std.fmt.allocPrint(allocator, "{s}.pad.{s}.{d}.tmp", .{ output, token, charged }); defer allocator.free(reply_name); defer std.fs.cwd().deleteFile(reply_name) catch {};
            const reply = try query(allocator, evaluator, reply_name, token, sentinel);
            charged += reply.charged;
        }
        const solved = best_correct == Examples;
        const strict_win = best_correct > maxima[id];
        if (!(solved and strict_win and charged == BaselineCalls)) negative_targets += 1;
        try w.print("round_l_l4,target_summary,{s},threshold,0,0,0,{d},{d},{d},{d},{s},full_bank_80_plus_redundant_padding\n", .{ token, best_fit, best_correct, maxima[id], charged, if (solved and strict_win) "strict_win" else "no_strict_win" });
    }
    try w.print("round_l_l4,VERDICT,all_blank_targets,threshold,0,0,0,0,0,0,0,{s},requires_two_same_region_exact_strict_equal_cost_wins;observed_failed_targets={d}\n", .{ if (negative_targets == 0) "POSITIVE" else "VALID_NEGATIVE", negative_targets });
}
