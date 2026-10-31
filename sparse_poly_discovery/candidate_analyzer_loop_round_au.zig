//! Round AU / AU2: bounded candidate analyzer loop.
//!
//! A deterministic candidate sees opaque structural observations, keeps two
//! competing forks, precommits a DSL program/test plan, receives a compiler
//! receipt, repairs once, and emits a sealed claim token.  This is synthetic
//! mechanics only: it has no artifact content, hidden task answer, score,
//! network, LLM, arbitrary code execution, or evaluator-isolation claim.
const std = @import("std");

const ForkState = enum { open, falsified, supported, unreached };
const Fork = struct { id: u8, hypothesis: []const u8, falsifier: []const u8, state: ForkState, evidence_hash: u64 };
const Receipt = struct { source_hash: u64, plan_hash: u64, output_hash: u64, compile_ok: bool, test_ok: bool, tag: []const u8 };

fn h(s: []const u8) u64 { return std.hash.Fnv1a_64.hash(s); }
fn state(s: ForkState) []const u8 { return switch (s) { .open => "open", .falsified => "falsified", .supported => "supported", .unreached => "unreached" }; }
fn number(s: []const u8) ?i64 { return std.fmt.parseInt(i64, s, 10) catch null; }

// Same intentionally tiny arithmetic language class as AT2. It is in-memory
// and has no host primitives: SET n, ADD n, ASSERT n, PRINT.
fn compileAndTest(source: []const u8, plan: []const u8) Receipt {
    var r = Receipt{ .source_hash = h(source), .plan_hash = h(plan), .output_hash = 0, .compile_ok = false, .test_ok = false, .tag = "compile_invalid" };
    if (!std.mem.startsWith(u8, plan, "EXPECT ")) { r.tag = "plan_invalid"; return r; }
    const expected = number(plan[7..]) orelse { r.tag = "plan_invalid"; return r; };
    var value: i64 = 0; var printed: ?i64 = null;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "SET ")) value = number(line[4..]) orelse { r.tag = "compile_bad_integer"; return r; }
        else if (std.mem.startsWith(u8, line, "ADD ")) value = std.math.add(i64, value, number(line[4..]) orelse { r.tag = "compile_bad_integer"; return r; }) catch { r.tag = "runtime_overflow"; return r; }
        else if (std.mem.startsWith(u8, line, "ASSERT ")) { const n = number(line[7..]) orelse { r.tag = "compile_bad_integer"; return r; }; if (value != n) { r.compile_ok = true; r.tag = "runtime_assertion_failed"; return r; } }
        else if (std.mem.eql(u8, line, "PRINT")) { if (printed != null) { r.tag = "compile_multiple_print"; return r; } printed = value; }
        else { r.tag = "compile_unknown_opcode"; return r; }
    }
    const out = printed orelse { r.tag = "compile_missing_print"; return r; };
    r.compile_ok = true; var buf: [32]u8 = undefined; const text = std.fmt.bufPrint(&buf, "{d}", .{out}) catch unreachable;
    r.output_hash = h(text); r.test_ok = out == expected; r.tag = if (r.test_ok) "ok" else "test_expectation_failed"; return r;
}

fn receiptHash(r: Receipt) u64 { var b: [128]u8 = undefined; const x = std.fmt.bufPrint(&b, "{x}:{x}:{x}:{s}", .{ r.source_hash, r.plan_hash, r.output_hash, r.tag }) catch unreachable; return h(x); }
fn postHocAllowed(precommit_plan_hash: u64, submitted_plan: []const u8) bool { return precommit_plan_hash == h(submitted_plan); }

fn write(path: []const u8) !void {
    // Opaque observation frame. It contains a shape/delta hash, not source
    // content, a target label, an answer, a score, or evaluator feedback.
    const observation = "frame:v1|shape:2|delta:5|receipt:8ac1";
    const observation_hash = h(observation);
    var forks = [_]Fork{
        .{ .id = 1, .hypothesis = "delta_is_reproducible", .falsifier = "arithmetic_probe_does_not_reach_12", .state = .open, .evidence_hash = 0 },
        .{ .id = 2, .hypothesis = "delta_is_noise", .falsifier = "arithmetic_probe_reaches_12", .state = .open, .evidence_hash = 0 },
        .{ .id = 3, .hypothesis = "alternate_structure", .falsifier = "requires_second_observation", .state = .unreached, .evidence_hash = 0 },
    };
    // Candidate commits plan before seeing any compiler receipt. First source
    // is malformed; repair is permitted only after the immutable failure tag.
    const plan = "EXPECT 12"; const plan_hash = h(plan);
    const attempted = "SET 7\nADD five\nPRINT";
    const failed = compileAndTest(attempted, plan);
    const repaired_source = "SET 7\nADD 5\nASSERT 12\nPRINT";
    const repaired = compileAndTest(repaired_source, plan);
    forks[0].state = if (repaired.test_ok) .supported else .falsified;
    forks[0].evidence_hash = receiptHash(repaired);
    forks[1].state = if (repaired.test_ok) .falsified else .supported;
    forks[1].evidence_hash = receiptHash(repaired);
    // Controls have identical DSL/test access. No score or selection signal
    // is used to choose between them.
    const no_repair = compileAndTest(attempted, plan);
    const fixed = compileAndTest("SET 7\nADD 5\nASSERT 12\nPRINT", plan);
    const random = compileAndTest("SET 3\nADD 1\nPRINT", plan);
    const replay = compileAndTest(repaired_source, plan);
    const altered_plan = "EXPECT 13";
    const posthoc_rejected = !postHocAllowed(plan_hash, altered_plan);
    const claim = if (repaired.test_ok) "sealed_claim:fork_1_supported_from_opaque_receipt" else "sealed_claim:no_supported_fork";
    const claim_hash = h(claim);

    var f = if (std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path, .{ .truncate = true }) else try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("round,kind,id,observation_hash,plan_hash,source_hash,receipt_tag,compile_ok,test_ok,fork_state,evidence_hash,claim_hash,notes\n");
    try w.print("round_au2,observation,opaque,{x},-,-,-,-,-,-,-,-,structural_frame_only\n", .{observation_hash});
    for (forks) |fork| try w.print("round_au2,fork,{d},{x},{x},-,-,-,-,{s},{x},-,-,{s}|{s}\n", .{ fork.id, observation_hash, plan_hash, state(fork.state), fork.evidence_hash, fork.hypothesis, fork.falsifier });
    const cases = [_]struct { name: []const u8, r: Receipt }{ .{ .name = "candidate_initial_compile_failure", .r = failed }, .{ .name = "candidate_repaired_precommitted", .r = repaired }, .{ .name = "control_no_repair", .r = no_repair }, .{ .name = "control_fixed_analyzer", .r = fixed }, .{ .name = "control_random_analyzer", .r = random }, .{ .name = "control_replay", .r = replay } };
    for (cases) |c| try w.print("round_au2,receipt,{s},{x},{x},{x},{s},{s},{s},-,-,-,-\n", .{ c.name, observation_hash, c.r.plan_hash, c.r.source_hash, c.r.tag, if (c.r.compile_ok) "true" else "false", if (c.r.test_ok) "true" else "false" });
    try w.print("round_au2,guard,post_hoc_plan_change,{x},{x},-,-,-,-,-,-,-,-,rejected={s}\n", .{ observation_hash, plan_hash, if (posthoc_rejected) "true" else "false" });
    try w.print("round_au2,final,sealed_claim,{x},{x},{x},{s},{s},{s},-,{x},{x},not_a_hidden_evaluator_verdict\n", .{ observation_hash, plan_hash, repaired.source_hash, repaired.tag, if (repaired.compile_ok) "true" else "false", if (repaired.test_ok) "true" else "false", receiptHash(repaired), claim_hash });
}

fn selftest() !void {
    const plan = "EXPECT 12"; const bad = compileAndTest("SET 7\nADD five\nPRINT", plan); const good = compileAndTest("SET 7\nADD 5\nASSERT 12\nPRINT", plan);
    if (bad.compile_ok or !std.mem.eql(u8, bad.tag, "compile_bad_integer")) return error.InitialFailureMissing;
    if (!good.compile_ok or !good.test_ok) return error.RepairMissing;
    if (postHocAllowed(h(plan), "EXPECT 13")) return error.PostHocAccepted;
    try write("/tmp/au2-a.csv"); try write("/tmp/au2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const one = try std.fs.cwd().readFileAlloc(a, "/tmp/au2-a.csv", 1 << 20); defer a.free(one); const two = try std.fs.cwd().readFileAlloc(a, "/tmp/au2-b.csv", 1 << 20); defer a.free(two);
    if (!std.mem.eql(u8, one, two)) return error.NonDeterministicReplay;
    if (std.mem.indexOf(u8, one, "control_fixed_analyzer") == null or std.mem.indexOf(u8, one, "rejected=true") == null) return error.ControlOrGuardMissing;
    std.debug.print("round_au2 selftest PASS opaque_observation=true competing_forks=3 precommitted_plan=true repair_after_compile_receipt=true controls=4 post_hoc_rejected=true deterministic_replay=true verdict=MECHANICS_ONLY\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try write(args.next() orelse "results/candidate_analyzer_loop_round_au.csv"); }
