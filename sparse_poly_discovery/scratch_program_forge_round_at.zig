//! Round AT / AT2: minimal deterministic scratch-program forge.
//!
//! This is deliberately NOT arbitrary host-code execution.  A candidate can
//! submit a tiny arithmetic program and a precommitted test plan.  The worker
//! parses, compiles, and runs that source entirely in-memory, returning only a
//! receipt.  The language has no filesystem, process, network, import, clock,
//! environment, or evaluator APIs.
const std = @import("std");

const Receipt = struct {
    source_hash: u64,
    plan_hash: u64,
    scratch_hash: u64,
    output_hash: u64,
    compile_ok: bool,
    test_ok: bool,
    instructions: u32,
    error_tag: []const u8,
};

fn hash(bytes: []const u8) u64 { return std.hash.Fnv1a_64.hash(bytes); }
fn forbidden(source: []const u8) ?[]const u8 {
    const bad = [_][]const u8{ "../", "/", "http", "net", "socket", "answer", "score", "eval", "import", "open", "exec", "credential" };
    for (bad) |word| if (std.mem.indexOf(u8, source, word) != null) return word;
    return null;
}
fn parseInt(s: []const u8) ?i64 { return std.fmt.parseInt(i64, s, 10) catch null; }

// The only language:
//   SET <integer>       reset accumulator
//   ADD <integer>       add signed decimal integer
//   ASSERT <integer>    fail runtime if accumulator differs
//   PRINT               emit accumulator as decimal
// The precommitted plan is exactly EXPECT <decimal-output>.
fn worker(source: []const u8, plan: []const u8) Receipt {
    var r = Receipt{ .source_hash = hash(source), .plan_hash = hash(plan), .scratch_hash = hash("round_at_disposable_scratch_v1"), .output_hash = 0, .compile_ok = false, .test_ok = false, .instructions = 0, .error_tag = "compile_invalid" };
    if (forbidden(source) != null or forbidden(plan) != null) { r.error_tag = "policy_rejected"; return r; }
    if (!std.mem.startsWith(u8, plan, "EXPECT ")) { r.error_tag = "plan_not_precommitted"; return r; }
    const expected = parseInt(plan[7..]) orelse { r.error_tag = "plan_invalid"; return r; };
    var value: i64 = 0;
    var printed: ?i64 = null;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        r.instructions += 1;
        if (r.instructions > 16) { r.error_tag = "resource_instruction_limit"; return r; }
        if (std.mem.startsWith(u8, line, "SET ")) {
            value = parseInt(line[4..]) orelse { r.error_tag = "compile_bad_integer"; return r; };
        } else if (std.mem.startsWith(u8, line, "ADD ")) {
            const n = parseInt(line[4..]) orelse { r.error_tag = "compile_bad_integer"; return r; };
            value = std.math.add(i64, value, n) catch { r.error_tag = "runtime_overflow"; return r; };
        } else if (std.mem.startsWith(u8, line, "ASSERT ")) {
            const n = parseInt(line[7..]) orelse { r.error_tag = "compile_bad_integer"; return r; };
            if (value != n) { r.compile_ok = true; r.error_tag = "runtime_assertion_failed"; return r; }
        } else if (std.mem.eql(u8, line, "PRINT")) {
            if (printed != null) { r.error_tag = "compile_multiple_print"; return r; }
            printed = value;
        } else { r.error_tag = "compile_unknown_opcode"; return r; }
    }
    const out = printed orelse { r.error_tag = "compile_missing_print"; return r; };
    r.compile_ok = true;
    var output: [64]u8 = undefined;
    const bytes = std.fmt.bufPrint(&output, "{d}", .{out}) catch unreachable;
    r.output_hash = hash(bytes);
    r.test_ok = out == expected;
    r.error_tag = if (r.test_ok) "ok" else "test_expectation_failed";
    return r;
}
fn receiptLine(w: anytype, name: []const u8, r: Receipt) !void {
    try w.print("round_at_at2,{s},{x},{x},{x},{x},{s},{s},{d},{s}\n", .{ name, r.source_hash, r.plan_hash, r.scratch_hash, r.output_hash, if (r.compile_ok) "true" else "false", if (r.test_ok) "true" else "false", r.instructions, r.error_tag });
}
fn run(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
    const w = file.writer();
    try w.writeAll("artifact,case,source_hash,plan_hash,disposable_scratch_hash,output_hash,compile_ok,test_ok,instructions,error_tag\n");
    // A failed proposal, then a repaired proposal.  The worker receives both
    // source and plan; it never receives task files, evaluator answers, or a score.
    try receiptLine(w, "failed_proposal", worker("SET 7\nADD five\nPRINT", "EXPECT 12"));
    try receiptLine(w, "repaired_proposal", worker("SET 7\nADD 5\nASSERT 12\nPRINT", "EXPECT 12"));
    try receiptLine(w, "wrong_precommitted_test", worker("SET 7\nADD 5\nPRINT", "EXPECT 13"));
    try receiptLine(w, "traversal_rejected", worker("SET 1\nADD ../secret\nPRINT", "EXPECT 1"));
    try receiptLine(w, "network_rejected", worker("http fetch\nPRINT", "EXPECT 0"));
    try receiptLine(w, "answer_rejected", worker("SET answer\nPRINT", "EXPECT 0"));
    try receiptLine(w, "score_rejected", worker("SET score\nPRINT", "EXPECT 0"));
    try receiptLine(w, "unknown_opcode_rejected", worker("MUTATE 9\nPRINT", "EXPECT 9"));
}
fn equalReceipt(a: Receipt, b: Receipt) bool {
    return a.source_hash == b.source_hash and a.plan_hash == b.plan_hash and a.scratch_hash == b.scratch_hash and a.output_hash == b.output_hash and a.compile_ok == b.compile_ok and a.test_ok == b.test_ok and a.instructions == b.instructions and std.mem.eql(u8, a.error_tag, b.error_tag);
}
fn selftest() !void {
    const failed = worker("SET 7\nADD five\nPRINT", "EXPECT 12");
    const repaired = worker("SET 7\nADD 5\nASSERT 12\nPRINT", "EXPECT 12");
    if (failed.compile_ok or !std.mem.eql(u8, failed.error_tag, "compile_bad_integer")) return error.FailureNotObserved;
    if (!repaired.compile_ok or !repaired.test_ok or repaired.output_hash == 0) return error.RepairNotVerified;
    const rejected = [_]Receipt{ worker("SET 1\nADD ../secret\nPRINT", "EXPECT 1"), worker("http fetch\nPRINT", "EXPECT 0"), worker("SET answer\nPRINT", "EXPECT 0"), worker("SET score\nPRINT", "EXPECT 0") };
    for (rejected) |r| if (!std.mem.eql(u8, r.error_tag, "policy_rejected")) return error.UnsafeInputAccepted;
    try run("/tmp/at2-a.csv"); try run("/tmp/at2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const one = try std.fs.cwd().readFileAlloc(a, "/tmp/at2-a.csv", 1 << 20); defer a.free(one);
    const two = try std.fs.cwd().readFileAlloc(a, "/tmp/at2-b.csv", 1 << 20); defer a.free(two);
    if (!std.mem.eql(u8, one, two) or !equalReceipt(repaired, worker("SET 7\nADD 5\nASSERT 12\nPRINT", "EXPECT 12"))) return error.NonDeterministicReplay;
    std.debug.print("round_at_at2 selftest PASS repaired_after_compile_failure=true unsafe_requests_denied=4 deterministic_replay=true executor=tiny_in_memory_dsl_only\n", .{});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(args.next() orelse "results/scratch_program_forge_round_at.csv");
}
