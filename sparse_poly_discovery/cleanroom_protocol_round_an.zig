//! Round AN / AN1: real local evaluator--candidate process boundary prototype.
//! The evaluator is this program's parent process; every candidate action is
//! produced by a freshly exec'd child with stdout as its only return channel.
//! This is a protocol boundary, NOT a proof against a hostile same-user OS
//! process (no seccomp, namespaces, or hardware isolation are claimed).
const std = @import("std");

const Turns = 8;
const MaxFrame = 32;
const MaxAction = 3;

const Parse = union(enum) { action: u8, forbidden_request, malformed };

fn hiddenObservation(turn: usize, nonce: u16) u8 {
    // Evaluator-owned, deliberately not serialized as a target/reward/score.
    return @as(u8, @intCast((turn * 17 + nonce * 3 + 11) % 97));
}
fn hiddenReward(turn: usize, action: u8, nonce: u16) u8 {
    const correct: u8 = @intCast((turn + nonce) % (MaxAction + 1));
    return @intFromBool(action == correct);
}
fn parseAction(bytes: []const u8, nonce: u16) Parse {
    if (bytes.len > MaxFrame) return .malformed;
    const prefix = std.fmt.allocPrint(std.heap.page_allocator, "A:{d}:", .{nonce}) catch return .malformed;
    defer std.heap.page_allocator.free(prefix);
    if (std.mem.startsWith(u8, bytes, "Q:") or std.mem.indexOf(u8, bytes, "SCORE") != null or std.mem.indexOf(u8, bytes, "TARGET") != null) return .forbidden_request;
    if (!std.mem.startsWith(u8, bytes, prefix)) return .malformed;
    const tail = bytes[prefix.len..];
    if (tail.len != 2 or tail[1] != '\n' or tail[0] < '0' or tail[0] > '3') return .malformed;
    return .{ .action = tail[0] - '0' };
}
fn candidate(frame: []const u8, mode: []const u8) !void {
    // Candidate gets one opaque frame only. It cannot request an evaluator API.
    if (std.mem.eql(u8, mode, "forbidden")) return std.io.getStdOut().writer().writeAll("Q:SCORE\n");
    if (std.mem.eql(u8, mode, "corrupt")) return std.io.getStdOut().writer().writeAll("A:999999999999999999999:99\nEXTRA\n");
    var it = std.mem.splitScalar(u8, frame, ':');
    _ = it.next(); const nonce_s = it.next() orelse return error.BadFrame;
    const obs_s = it.next() orelse return error.BadFrame;
    const nonce = try std.fmt.parseInt(u16, nonce_s, 10);
    const obs = try std.fmt.parseInt(u8, obs_s, 10);
    // Generic bounded policy: an action is all it can emit, never a score.
    const action: u8 = (obs + @as(u8, @intCast(nonce % 4))) % 4;
    try std.io.getStdOut().writer().print("A:{d}:{d}\n", .{ nonce, action });
}
fn runChild(allocator: std.mem.Allocator, exe: []const u8, frame: []const u8, mode: []const u8) ![]u8 {
    var child = std.process.Child.init(&.{ exe, "candidate", frame, mode }, allocator);
    child.stdin_behavior = .Ignore; child.stdout_behavior = .Pipe; child.stderr_behavior = .Ignore;
    try child.spawn();
    const out = try child.stdout.?.readToEndAlloc(allocator, MaxFrame + 1);
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.CandidateFailed,
        else => return error.CandidateFailed,
    }
    return out;
}
fn run(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    const exe = try std.fs.selfExePathAlloc(a); defer a.free(exe);
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,check,turn,frame_bytes,candidate_bytes,evaluator_reply,verdict,detail\n");
    var awarded: usize = 0;
    for (0..Turns) |turn| {
        const nonce: u16 = @intCast(400 + turn * 19);
        const obs = hiddenObservation(turn, nonce);
        const frame = try std.fmt.allocPrint(a, "O:{d}:{d}", .{ nonce, obs }); defer a.free(frame);
        const out = try runChild(a, exe, frame, "normal"); defer a.free(out);
        const p = parseAction(out, nonce);
        switch (p) {
            .action => |act| {
                awarded += hiddenReward(turn, act, nonce);
                try w.print("round_an_an1,normal_action,{d},{d},{d},none,ACCEPTED,opaque_observation_action_only_no_progress_or_score\n", .{ turn, frame.len, out.len });
            },
            else => return error.NormalProtocolRejected,
        }
    }
    const denied_frame = "O:777:42";
    const forbidden = try runChild(a, exe, denied_frame, "forbidden"); defer a.free(forbidden);
    const corrupt = try runChild(a, exe, denied_frame, "corrupt"); defer a.free(corrupt);
    const p_forbidden = parseAction(forbidden, 777);
    const p_corrupt = parseAction(corrupt, 777);
    if (p_forbidden != .forbidden_request or p_corrupt != .malformed) return error.DenyFailure;
    try w.print("round_an_an1,forbidden_data_request,NA,{d},{d},none,DENIED,score_target_answer_and_feedback_are_not_protocol_fields\n", .{ denied_frame.len, forbidden.len });
    try w.print("round_an_an1,corrupt_protocol,NA,{d},{d},none,DENIED,strict_nonce_schema_range_and_max_frame_fail_closed\n", .{ denied_frame.len, corrupt.len });
    try w.print("round_an_an1,end_of_run_score,NA,0,0,aggregate_only,WITHHELD,hidden_reward_released_only_after_all_fixed_turns; aggregate={d}\n", .{awarded});
    try w.writeAll("round_an_an1,process_boundary,NA,0,0,none,DEMONSTRATED,parent_evaluator_execs_fresh_candidate_children_with_stdout_only_return\n");
    try w.writeAll("round_an_an1,residual,NA,0,0,none,INCONCLUSIVE_FOR_HOSTILE_OS,child_inherits_same_user_OS_rights_no_seccomp_namespace_or_hardware_isolation\n");
}
fn selftest() !void {
    try run("/tmp/an1-a.csv"); try run("/tmp/an1-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/an1-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/an1-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    if (std.mem.indexOf(u8, x, "forbidden_data_request") == null or std.mem.indexOf(u8, x, "INCONCLUSIVE_FOR_HOSTILE_OS") == null) return error.MissingEvidence;
    std.debug.print("round_an_an1 selftest PASS separate_process=true fixed_turns=8 forbidden_denied=true malformed_denied=true replay=true verdict=GATE_READY protocol_only\n", .{});
}
pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "candidate")) return candidate(args.next() orelse return error.BadFrame, args.next() orelse return error.BadMode);
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/cleanroom_protocol_round_an.csv");
}
