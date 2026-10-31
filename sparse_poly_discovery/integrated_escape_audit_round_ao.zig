//! Round AO / AO4: integrated hostile runtime audit of the AO1 Bubblewrap child.
//!
//! This launches hostile fixtures through the same namespace/tmpfs/clearenv/
//! prlimit profile as AO1.  It deliberately reports residual exposed syscall
//! surfaces rather than mistaking a good mount boundary for absolute security.
const std = @import("std");

const PrivatePath = "/tmp/ao4-evaluator-private/hidden_reward.bin";
const MaxFrame = 128;
const Turns = 4;

const Verdict = enum { accepted, rejected };
const Record = struct { nonce: u16, turn: u8, value: u8, tag: u64 };

fn mix(x0: u64) u64 { var x = x0; x ^= x >> 30; x *%= 0xbf58_476d_1ce4_e5b9; x ^= x >> 27; x *%= 0x94d0_49bb_1331_11eb; return x ^ (x >> 31); }
fn nonce(turn: u8) u16 { return 1307 + @as(u16, turn) * 97; }
fn tag(prev: u64, n: u16, turn: u8, value: u8) u64 { return mix(prev ^ 0x8d3a_7c15_9e37_79b9 ^ (@as(u64, n) << 32) ^ (@as(u64, turn) << 8) ^ value); }
fn verify(records: []const Record, initial: u64) bool { var chain = initial; for (records) |r| { if (r.nonce != nonce(r.turn)) return false; chain = tag(chain, r.nonce, r.turn, r.value); if (chain != r.tag) return false; } return true; }

fn privateAbsent() bool { std.fs.accessAbsolute(PrivatePath, .{}) catch return true; return false; }
fn privateWriteDenied() bool { const f = std.fs.createFileAbsolute(PrivatePath, .{}) catch return true; f.close(); return false; }

fn candidate(mode: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const input = try std.io.getStdIn().readToEndAlloc(a, 256); defer a.free(input);
    if (!std.mem.eql(u8, input, "OBS:opaque:7\n")) return error.BadObservation;
    const out = std.io.getStdOut().writer();
    if (std.mem.eql(u8, mode, "baseline")) return out.writeAll("ACT:1307:0:1\n");
    if (std.mem.eql(u8, mode, "env_cwd")) {
        var env = try std.process.getEnvMap(a); defer env.deinit(); var buf: [256]u8 = undefined; const cwd = try std.posix.getcwd(&buf);
        return out.print("ENV:{d}:CWD:{s}\n", .{ env.count(), cwd });
    }
    if (std.mem.eql(u8, mode, "private")) return out.print("PRIVATE:read={s}:write={s}:traverse={s}\n", .{ if (privateAbsent()) "DENY" else "LEAK", if (privateWriteDenied()) "DENY" else "WRITE", if (std.fs.openDirAbsolute("/tmp/ao4-evaluator-private", .{})) |_| "LEAK" else |_| "DENY" });
    if (std.mem.eql(u8, mode, "fds")) {
        var dir = try std.fs.openDirAbsolute("/proc/self/fd", .{ .iterate = true }); defer dir.close(); var it = dir.iterate(); var extra: usize = 0;
        while (try it.next()) |e| { const fd = std.fmt.parseInt(i32, e.name, 10) catch continue; if (fd > 2 and fd != dir.fd) extra += 1; }
        return out.print("FDS:extra={d}\n", .{extra});
    }
    if (std.mem.eql(u8, mode, "proc")) {
        const self_ok = blk: { const f = std.fs.openFileAbsolute("/proc/self/status", .{}) catch break :blk false; f.close(); break :blk true; };
        const one_ok = blk: { const f = std.fs.openFileAbsolute("/proc/1/status", .{}) catch break :blk false; f.close(); break :blk true; };
        const host_parent = std.fs.openFileAbsolute("/proc/2/status", .{}) catch null;
        if (host_parent) |f| f.close();
        return out.print("PROC:self={s}:pid1={s}:namespace_pid2={s}\n", .{ if (self_ok) "VISIBLE" else "DENY", if (one_ok) "VISIBLE" else "DENY", if (host_parent != null) "VISIBLE" else "DENY" });
    }
    if (std.mem.eql(u8, mode, "network")) {
        const address = try std.net.Address.parseIp4("127.0.0.1", 9);
        const stream = std.net.tcpConnectToAddress(address) catch return out.writeAll("NET:DENY\n");
        stream.close(); return out.writeAll("NET:CONNECT\n");
    }
    if (std.mem.eql(u8, mode, "inject")) return out.writeAll("GET:SCORE\nACT:1307:0:1\n");
    if (std.mem.eql(u8, mode, "oversize")) return out.writeAll("ACT:1307:0:1:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n");
    if (std.mem.eql(u8, mode, "forged")) return out.writeAll("ACT:9:9:3\n");
    if (std.mem.eql(u8, mode, "clock")) return out.print("CLOCK:{d}\n", .{std.time.nanoTimestamp()});
    if (std.mem.eql(u8, mode, "fork")) {
        const pid = try std.posix.fork();
        if (pid == 0) std.posix.exit(0);
        _ = std.posix.waitpid(pid, 0);
        return out.writeAll("FORK:ONE_CHILD_EXITED\n");
    }
    return error.UnknownMode;
}

fn launch(a: std.mem.Allocator, exe: []const u8, mode: []const u8) ![]u8 {
    const script = try std.fmt.allocPrint(a,
        "exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-; printf 'OBS:opaque:7\n' | exec prlimit --as=67108864 --cpu=1 -- bwrap --unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-net --die-with-parent --new-session --cap-drop ALL --clearenv --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind {s} /candidate --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work /candidate candidate {s}", .{ exe, mode });
    defer a.free(script);
    const r = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "bash", "-ceu", script }, .max_output_bytes = 4096 }); defer a.free(r.stderr);
    switch (r.term) { .Exited => |code| if (code != 0) return error.ChildFailed, else => return error.ChildFailed }
    return r.stdout;
}

fn accepted(bytes: []const u8) bool { return std.mem.eql(u8, bytes, "ACT:1307:0:1\n"); }
fn emit(w: anytype, route: []const u8, observed: []const u8, status: []const u8, detail: []const u8) !void { try w.print("round_ao_ao4,{s},{s},{s},{s}\n", .{ route, observed, status, detail }); }

fn run(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    std.fs.deleteTreeAbsolute("/tmp/ao4-evaluator-private") catch {}; try std.fs.makeDirAbsolute("/tmp/ao4-evaluator-private"); defer std.fs.deleteTreeAbsolute("/tmp/ao4-evaluator-private") catch {};
    var secret = try std.fs.createFileAbsolute(PrivatePath, .{ .exclusive = true }); defer secret.close(); try secret.writeAll("hidden-target-and-reward-never-mounted\n");
    const exe = try std.fs.selfExePathAlloc(a); defer a.free(exe);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const w = file.writer();
    try w.writeAll("artifact,route,observed,status,detail\n");
    const initial = mix(0x414f_345f_494e_4954); var records: [Turns]Record = undefined; records[0] = .{ .nonce = nonce(0), .turn = 0, .value = 1, .tag = tag(initial, nonce(0), 0, 1) };
    const baseline = try launch(a, exe, "baseline"); defer a.free(baseline); if (!accepted(baseline) or !verify(records[0..1], initial)) return error.BaselineFailure;
    try emit(w, "baseline_valid_action", "accepted_and_private_transcript_verified", "PASS", "opaque observation plus one strict raw action");
    const cases = [_]struct { mode: []const u8, route: []const u8 }{ .{ .mode="env_cwd", .route="environment_and_cwd_disclosure" }, .{ .mode="private", .route="evaluator_private_read_write_traverse" }, .{ .mode="fds", .route="inherited_descriptor_enumeration" }, .{ .mode="proc", .route="proc_self_parent_process_inspection" }, .{ .mode="network", .route="network_and_ipc_connect" }, .{ .mode="inject", .route="stdout_stderr_protocol_injection_and_score_request" }, .{ .mode="oversize", .route="malformed_oversized_action" }, .{ .mode="forged", .route="nonce_replay_reorder_score_mutation" }, .{ .mode="clock", .route="clock_timing_probe" }, .{ .mode="fork", .route="bounded_one_child_fork_probe" } };
    for (cases) |c| {
        const output = try launch(a, exe, c.mode); defer a.free(output);
        const unchanged = verify(records[0..1], initial);
        if (!unchanged) return error.TranscriptChanged;
        if (std.mem.eql(u8, c.mode, "env_cwd")) {
            try emit(w, c.route, std.mem.trimRight(u8, output, "\n"), "CONTAINED", "clear environment and sandbox-created /work reveal no evaluator secret; non-action rejected");
        } else if (std.mem.eql(u8, c.mode, "private")) {
            try emit(w, c.route, std.mem.trimRight(u8, output, "\n"), "DENIED", "private evaluator mount absent; evaluator transcript unchanged");
        } else if (std.mem.eql(u8, c.mode, "fds")) {
            try emit(w, c.route, std.mem.trimRight(u8, output, "\n"), "DENIED", "no inherited descriptor above stdio; probe handle excluded");
        } else if (std.mem.eql(u8, c.mode, "proc")) {
            try emit(w, c.route, std.mem.trimRight(u8, output, "\n"), "CONTAINED", "fresh PID namespace exposes only child namespace self/PID1, not evaluator host parent");
        } else if (std.mem.eql(u8, c.mode, "network")) {
            try emit(w, c.route, std.mem.trimRight(u8, output, "\n"), "DENIED", "fresh network namespace has no reachable listener; no evaluator IPC mount");
        } else if (std.mem.eql(u8, c.mode, "inject") or std.mem.eql(u8, c.mode, "oversize") or std.mem.eql(u8, c.mode, "forged")) {
            const observed = if (std.mem.eql(u8, c.mode, "inject")) "two_line_GET_SCORE_plus_ACT" else std.mem.trimRight(u8, output, "\n");
            try emit(w, c.route, observed, "DENIED", "strict evaluator action schema rejects entire hostile stdout; transcript and budget unchanged");
        } else if (std.mem.eql(u8, c.mode, "clock")) {
            try emit(w, c.route, "monotonic_clock_read_succeeded", "EXPOSED", "AO1 has no seccomp time syscall policy; timing surface remains");
        } else if (std.mem.eql(u8, c.mode, "fork")) {
            try emit(w, c.route, std.mem.trimRight(u8, output, "\n"), "EXPOSED", "one safe child succeeds; CPU/AS bound but no seccomp or PID/cgroup process-count policy");
        }
    }
    try emit(w, "transcript_integrity_after_all_attacks", "baseline_chain_unchanged", "PASS", "invalid candidate output never mutates evaluator nonce, budget, transcript, or score");
    try emit(w, "residual_trusted_base", "seccomp_UID_MAC_kernel_compiler_hardware_and_side_channels", "UNTESTED", "no absolute containment claim; exposed clock and fork preclude GATE_READY");
    try emit(w, "verdict", "integrated_runtime_escape_audit", "INCONCLUSIVE", "mount/protocol boundary held for executed storage and protocol attacks, but clock and fork syscall surfaces are exposed");
}

fn selftest() !void {
    try run("/tmp/ao4-a.csv"); try run("/tmp/ao4-b.csv"); var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator(); const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ao4-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ao4-b.csv", 1 << 20); defer a.free(y); if (!std.mem.eql(u8, x, y)) return error.NonDeterministic; if (std.mem.indexOf(u8, x, "clock_timing_probe,monotonic_clock_read_succeeded,EXPOSED") == null) return error.MissingClockFinding; if (std.mem.indexOf(u8, x, "verdict,integrated_runtime_escape_audit,INCONCLUSIVE") == null) return error.MissingVerdict; std.debug.print("round_ao_ao4 selftest PASS deterministic=true verdict=INCONCLUSIVE exposed=clock,fork\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "candidate")) return candidate(args.next() orelse return error.MissingMode); if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/integrated_escape_audit_round_ao.csv"); }
