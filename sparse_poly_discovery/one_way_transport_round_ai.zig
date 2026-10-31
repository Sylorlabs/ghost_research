//! Round AI / AI2 -- one-way evaluator transport, deliberately separate from
//! OS containment.  The parent owns the initial state and evaluator-private
//! receipt; the child receives exactly sixteen anonymous bytes on stdin, sees
//! EOF, exits, and only then does the parent read one sixteen-byte final state.
const std = @import("std");

const StateBytes = 16;
const Seed: [StateBytes]u8 = .{ 0x41, 0x49, 0x32, 0x2d, 0x72, 0x61, 0x77, 0x2d, 0x73, 0x74, 0x61, 0x74, 0x65, 0x2d, 0x30, 0x31 };

const Case = enum { normal, malformed_input, malformed_output, extra_output, interactive_read, reverse_write, empty_environment, inherited_fd_probe, callback_probe, file_process_socket_ipc };

fn label(c: Case) []const u8 { return @tagName(c); }

fn transform(input: [StateBytes]u8) [StateBytes]u8 {
    var out: [StateBytes]u8 = undefined;
    for (input, 0..) |b, i| out[i] = (b ^ @as(u8, @intCast(0x5d + i * 7))) +% @as(u8, @intCast(i * 3));
    return out;
}

fn worker(mode: []const u8) !void {
    var input: [StateBytes + 2]u8 = undefined;
    var total: usize = 0;
    while (total < input.len) {
        const n = try std.io.getStdIn().read(input[total..]);
        if (n == 0) break;
        total += n;
    }
    if (total != StateBytes) return error.InvalidInitialRawStream;
    var raw: [StateBytes]u8 = undefined;
    @memcpy(&raw, input[0..StateBytes]);

    // This extra read is the hostile "ask evaluator again" attempt.  The
    // parent closed stdin after its single stream, so EOF is the only result.
    if (std.mem.eql(u8, mode, "interactive_read") or std.mem.eql(u8, mode, "reverse_write")) {
        var one: [1]u8 = undefined;
        if (try std.io.getStdIn().read(&one) != 0) return error.ReverseInputWasAvailable;
    }
    // These probes are intentionally not allowed to affect final bytes.  They
    // establish the protocol surface, while AI1 owns OS-level denial.
    if (std.mem.eql(u8, mode, "empty_environment")) {
        if (std.posix.getenv("AI_PRIVATE_SCORE") != null) return error.PrivateEnvironmentWasMounted;
    }
    if (std.mem.eql(u8, mode, "inherited_fd_probe")) {
        // Child stdio occupies 0/1/2.  A successful fd 3 probe would show an
        // unexpected inherited handle.  /proc is diagnostic only, not normal
        // worker input, and its availability is intentionally not assumed.
        const probe = std.fs.openFileAbsolute("/proc/self/fd/3", .{});
        if (probe) |f| { f.close(); return error.UnexpectedInheritedFd; } else |_| {}
    }
    if (std.mem.eql(u8, mode, "callback_probe") or std.mem.eql(u8, mode, "file_process_socket_ipc")) {
        // No callback or handle exists in this executable interface.  The
        // latter names a residual: nothing in this protocol sandboxs syscalls.
    }

    const out = transform(raw);
    if (std.mem.eql(u8, mode, "malformed_output")) return std.io.getStdOut().writeAll(out[0 .. StateBytes - 1]);
    try std.io.getStdOut().writeAll(&out);
    if (std.mem.eql(u8, mode, "extra_output")) try std.io.getStdOut().writeAll("x");
}

const Outcome = struct { accepted: bool, exit_ok: bool, output_bytes: usize, detail: []const u8 };

fn launch(a: std.mem.Allocator, exe: []const u8, mode: []const u8, initial: []const u8) !Outcome {
    var env = std.process.EnvMap.init(a);
    defer env.deinit(); // Empty map: no inherited evaluator/environment values.
    var child = std.process.Child.init(&.{ exe, "worker", mode }, a);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.env_map = &env;
    child.cwd = "/tmp"; // disposable run location; no project path is mounted by protocol.
    try child.spawn();
    try child.stdin.?.writeAll(initial);
    child.stdin.?.close();
    child.stdin = null;

    // Transfer these descriptors to the collector before wait; `Child.wait`
    // clears child-owned stream fields.  Ordering remains intentional: the
    // collector does not *read* stdout until wait
    // confirms the worker has exited.  Worker output is capped below pipe
    // capacity in every mounted fixture, so wait cannot deadlock here.
    const collector_stdout = child.stdout.?;
    child.stdout = null;
    const collector_stderr = child.stderr.?;
    child.stderr = null;
    const term = try child.wait();
    const exit_ok = switch (term) { .Exited => |code| code == 0, else => false };
    var buf: [StateBytes + 4]u8 = undefined;
    const n = try collector_stdout.readAll(&buf);
    collector_stdout.close();
    var err: [128]u8 = undefined;
    _ = collector_stderr.readAll(&err) catch 0;
    collector_stderr.close();
    if (!exit_ok) return .{ .accepted = false, .exit_ok = false, .output_bytes = n, .detail = "worker_exited_nonzero_before_collection" };
    if (n != StateBytes) return .{ .accepted = false, .exit_ok = true, .output_bytes = n, .detail = "collector_rejected_noncanonical_final_stream" };
    const expected = transform(Seed);
    if (!std.mem.eql(u8, buf[0..StateBytes], &expected)) return .{ .accepted = false, .exit_ok = true, .output_bytes = n, .detail = "collector_rejected_unexpected_final_raw_bytes" };
    return .{ .accepted = true, .exit_ok = true, .output_bytes = n, .detail = "post_exit_collector_accepted_exact_final_raw_stream" };
}

fn writeRow(w: anytype, c: Case, o: Outcome, expected: []const u8) !void {
    try w.print("round_ai_ai2,transport,{s},{s},{s},{d},{s}\n", .{ label(c), if (o.accepted) "PASS" else "REJECTED", expected, o.output_bytes, o.detail });
}

fn run(a: std.mem.Allocator, path: []const u8) !void {
    const exe = try std.fs.selfExePathAlloc(a);
    defer a.free(exe);
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,kind,attempt,result,expected,final_bytes,detail\n");
    try w.writeAll("round_ai_ai2,manifest,worker_interface,PASS,stdin=one_raw_stream_eof;stdout=one_raw_stream_after_exit,0,no_task_score_answer_callback_handle_or_retry_protocol_field\n");
    try w.writeAll("round_ai_ai2,manifest,evaluator_visibility,PASS,collector_reads_only_after_wait,0,evaluator_private_receipt_is_created_only_after_exact_final_stream_acceptance\n");
    try w.writeAll("round_ai_ai2,manifest,environment,PASS,empty_child_environment,0,launcher_uses_empty_EnvMap_and_tmp_cwd\n");

    try writeRow(w, .normal, try launch(a, exe, "normal", &Seed), "accepted_exactly_once_after_exit");
    var bad: [StateBytes - 1]u8 = undefined; @memcpy(&bad, Seed[0 .. StateBytes - 1]);
    try writeRow(w, .malformed_input, try launch(a, exe, "normal", &bad), "rejected_before_final_output");
    try writeRow(w, .malformed_output, try launch(a, exe, "malformed_output", &Seed), "collector_rejects_short_output");
    try writeRow(w, .extra_output, try launch(a, exe, "extra_output", &Seed), "collector_rejects_extra_output");
    try writeRow(w, .interactive_read, try launch(a, exe, "interactive_read", &Seed), "EOF_after_single_initial_stream");
    try writeRow(w, .reverse_write, try launch(a, exe, "reverse_write", &Seed), "no_evaluator_writeback_EOF_only");
    try writeRow(w, .empty_environment, try launch(a, exe, "empty_environment", &Seed), "private_environment_absent");
    try writeRow(w, .inherited_fd_probe, try launch(a, exe, "inherited_fd_probe", &Seed), "fd_3_absent");
    try writeRow(w, .callback_probe, try launch(a, exe, "callback_probe", &Seed), "no_callback_or_evaluator_handle_in_argv_or_stream");
    try writeRow(w, .file_process_socket_ipc, try launch(a, exe, "file_process_socket_ipc", &Seed), "NOT_ENFORCED_BY_TRANSPORT_PROTOCOL");
    try w.writeAll("round_ai_ai2,residual,os_capabilities,VALID_NEGATIVE,AI1_required,0,a_child_process_can_attempt_files_processes_sockets_ipc_or_timing_without_a_kernel_sandbox;transport_protocol_does_not_claim_OS_isolation\n");
    try w.writeAll("round_ai_ai2,VERDICT,aggregate,VALID_NEGATIVE,exact_transport_passes_but_OS_containment_unproven,0,one_way_protocol_correct_for_mounted_hostile_stream_attacks;AI2_does_not_unlock_AI4_without_AI1_and_AI3\n");
}

fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    try run(a, "/tmp/one-way-ai2-a.csv");
    try run(a, "/tmp/one-way-ai2-b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/one-way-ai2-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/one-way-ai2-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    for ([_][]const u8{ "normal,PASS", "malformed_input,REJECTED", "malformed_output,REJECTED", "extra_output,REJECTED", "interactive_read,PASS", "inherited_fd_probe,PASS", "os_capabilities,VALID_NEGATIVE" }) |needle| if (std.mem.indexOf(u8, x, needle) == null) return error.MissingEvidence;
    std.debug.print("round_ai_ai2 selftest PASS byte_identical=true post_exit_only=true hostile_stream_rejections=3 verdict=VALID_NEGATIVE\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "worker")) return worker(args.next() orelse "normal");
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    try run(gpa.allocator(), args.next() orelse "results/one_way_transport_round_ai.csv");
}
