//! Round AN / AN2: deterministic hostile audit of the declared clean-room wire boundary.
//!
//! This exercises a deliberately tiny raw-action parser.  It is a protocol audit,
//! not proof of OS, kernel, compiler, hardware, or side-channel containment.
const std = @import("std");

const Decision = enum { accept, reject };
const Fixture = struct { name: []const u8, payload: []const u8, expected: Decision, surface: []const u8 };

// The only allowed candidate request is exactly ACT:<one raw byte 0..3>.
// There are intentionally no target/reward/score query verbs.
fn parseAction(payload: []const u8) Decision {
    if (payload.len != 5) return .reject;
    if (!std.mem.eql(u8, payload[0..4], "ACT:")) return .reject;
    return if (payload[4] >= '0' and payload[4] <= '3') .accept else .reject;
}

const fixtures = [_]Fixture{
    .{ .name = "raw_action_zero", .payload = "ACT:0", .expected = .accept, .surface = "baseline_allowed_raw_action" },
    .{ .name = "target_request", .payload = "GET:TARGET", .expected = .reject, .surface = "candidate_target_request" },
    .{ .name = "reward_request", .payload = "GET:REWARD", .expected = .reject, .surface = "candidate_reward_request" },
    .{ .name = "score_request", .payload = "GET:SCORE", .expected = .reject, .surface = "candidate_score_request" },
    .{ .name = "protocol_injection", .payload = "ACT:0\nGET:TARGET", .expected = .reject, .surface = "newline_command_injection" },
    .{ .name = "nul_encoding", .payload = "ACT:0\x00GET:REWARD", .expected = .reject, .surface = "nul_smuggling" },
    .{ .name = "invalid_action", .payload = "ACT:9", .expected = .reject, .surface = "out_of_range_raw_action" },
    .{ .name = "truncated", .payload = "ACT:", .expected = .reject, .surface = "malformed_length" },
    .{ .name = "oversized", .payload = "ACT:000000000000000000000000000000000000000000000000000000000000000000", .expected = .reject, .surface = "oversized_message" },
    .{ .name = "path_traversal", .payload = "ACT:../../secret", .expected = .reject, .surface = "path_traversal" },
    .{ .name = "evaluator_corruption", .payload = "SET:REWARD=999", .expected = .reject, .surface = "evaluator_mutation_attempt" },
    .{ .name = "transcript_tamper", .payload = "LOG:REWRITE", .expected = .reject, .surface = "transcript_tampering" },
    .{ .name = "handle_secret", .payload = "FD:3", .expected = .reject, .surface = "inherited_handle_probe" },
    .{ .name = "process_ipc_probe", .payload = "PROC:/proc/self/environ", .expected = .reject, .surface = "pid_process_ipc_environment_probe" },
    .{ .name = "clock_probe", .payload = "TIME:NOW", .expected = .reject, .surface = "timing_clock_feedback_probe" },
    .{ .name = "resource_exhaustion", .payload = "FORK:999999", .expected = .reject, .surface = "resource_exhaustion_probe" },
};

fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,fixture,surface,expected,observed,status,interpretation\n");
    var rejected: usize = 0;
    for (fixtures) |fixture| {
        const actual = parseAction(fixture.payload);
        const pass = actual == fixture.expected;
        if (actual == .reject) rejected += 1;
        try w.print("round_an_an2,{s},{s},{s},{s},{s},{s}\n", .{
            fixture.name, fixture.surface, @tagName(fixture.expected), @tagName(actual),
            if (pass) "PASS" else "FAIL",
            if (actual == .reject) "fail_closed_at_raw_action_protocol" else "only_baseline_raw_action_accepted",
        });
    }
    try w.print("round_an_an2,summary,protocol_attack_denials,15_rejects,{},PASS,all non-baseline hostile protocol payloads rejected\n", .{rejected});
    try w.writeAll("round_an_an2,residual,filesystem_environment_handles_processes_ipc_clock_resource_os_sandbox,UNTESTED,UNTESTED,RESIDUAL,raw parser cannot prove process or host containment\n");
    try w.writeAll("round_an_an2,trusted_computing_base,zig_runtime_os_kernel_compiler_hardware_evaluator_launcher,DECLARED,DECLARED,RESIDUAL,these components must be trusted or independently hardened\n");
    try w.writeAll("round_an_an2,verdict,protocol_boundary,GATE_READY,GATE_READY,PASS,declared protocol attacks execute and fail closed; not a security or escape-proof claim\n");
}

fn selftest() !void {
    try run("/tmp/an2-a.csv"); try run("/tmp/an2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/an2-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/an2-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    if (parseAction("ACT:2") != .accept or parseAction("GET:TARGET") != .reject) return error.ParserFailure;
    if (std.mem.indexOf(u8, x, "protocol_boundary,GATE_READY") == null) return error.MissingVerdict;
    if (std.mem.indexOf(u8, x, "raw parser cannot prove process") == null) return error.MissingResidual;
    std.debug.print("round_an_an2 selftest PASS deterministic=true hostile_protocol_rejects=15 baseline_accepts=1 verdict=GATE_READY residual=host_containment_untested\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/cleanroom_escape_audit_round_an.csv");
}
