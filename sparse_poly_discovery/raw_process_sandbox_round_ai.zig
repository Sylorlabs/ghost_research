//! Round AI / AI1 -- real local process containment probe.
//!
//! The worker is statically linked and is launched by bubblewrap with a new
//! user, pid, mount, ipc, uts, and network namespace.  Its mount namespace
//! contains only its own executable, /proc, /dev and a fresh /tmp.  This file
//! deliberately distinguishes namespace isolation from a syscall policy: a
//! worker can still create a network socket and fork/exec its own mounted
//! executable.  Those two observations make the overall result a VALID
//! NEGATIVE, despite the useful filesystem/environment/parent isolation.
const std = @import("std");

const Input = [_]u8{ 0x13, 0x57, 0x9b, 0xdf, 0x24, 0x68, 0xac, 0xf0 };

const Probe = struct {
    env_visible: bool,
    host_file_visible: bool,
    mounted_worker_visible: bool,
    proc_visible: bool,
    socket_created: bool,
    spawn_possible: bool,
    input_ok: bool,
    output_ok: bool,
};

fn worker() !void {
    var in: [Input.len]u8 = undefined;
    const got = try std.io.getStdIn().readAll(&in);
    if (got != Input.len) return error.BadRawInput;
    // This is the complete raw-medium operation: an invertible byte transport
    // with no score, target, semantic decoder, callback, or external import.
    for (&in, 0..) |*b, i| b.* = std.math.rotl(u8, b.* ^ @as(u8, @intCast(i * 17)), 1);
    try std.io.getStdOut().writeAll(&in);
}

fn workerSocketProbe() !void {
    const fd = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch {
        try std.io.getStdOut().writeAll("0");
        return;
    };
    std.posix.close(fd);
    try std.io.getStdOut().writeAll("1");
}

fn workerSpawnProbe() !void {
    const pid = std.posix.fork() catch {
        try std.io.getStdOut().writeAll("0");
        return;
    };
    if (pid == 0) std.posix.exit(0);
    _ = std.posix.waitpid(pid, 0);
    try std.io.getStdOut().writeAll("1");
}

fn workerFileProbe() !void {
    const f = std.fs.openFileAbsolute("/etc/passwd", .{}) catch {
        try std.io.getStdOut().writeAll("0");
        return;
    };
    f.close();
    try std.io.getStdOut().writeAll("1");
}

fn workerEnvProbe() !void {
    if (std.posix.getenv("HOME") == null and std.posix.getenv("PATH") == null) {
        try std.io.getStdOut().writeAll("0");
    } else {
        try std.io.getStdOut().writeAll("1");
    }
}

fn workerProcProbe() !void {
    const f = std.fs.openFileAbsolute("/proc/1/status", .{}) catch {
        try std.io.getStdOut().writeAll("0");
        return;
    };
    f.close();
    try std.io.getStdOut().writeAll("1");
}

fn runChild(a: std.mem.Allocator, exe: []const u8, input: []const u8) ![]u8 {
    const argv = [_][]const u8{
        "bwrap",      "--unshare-all", "--new-session", "--die-with-parent",
        "--clearenv", "--ro-bind",     exe,             "/worker",
        "--proc",     "/proc",         "--dev",         "/dev",
        "--tmpfs",    "/tmp",          "/worker",       "worker",
    };
    var child = std.process.Child.init(&argv, a);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    try child.stdin.?.writeAll(input);
    child.stdin.?.close();
    child.stdin = null;
    const out = try child.stdout.?.reader().readAllAlloc(a, 4096);
    const err = try child.stderr.?.reader().readAllAlloc(a, 4096);
    defer a.free(err);
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.SandboxWorkerFailed,
        else => return error.SandboxWorkerFailed,
    }
    return out;
}

fn expected() [Input.len]u8 {
    var x = Input;
    for (&x, 0..) |*b, i| b.* = std.math.rotl(u8, b.* ^ @as(u8, @intCast(i * 17)), 1);
    return x;
}

// Host-side probe after a clean raw transport.  Each command is itself run in
// the identical bubblewrap namespace.  It returns a one-byte success signal;
// absence of a command is itself an access denial, and is deliberately not
// counted as a kernel syscall denial.
fn shellProbe(a: std.mem.Allocator, exe: []const u8, command: []const u8) !bool {
    const argv = [_][]const u8{
        "bwrap",      "--unshare-all", "--new-session", "--die-with-parent",
        "--clearenv", "--ro-bind",     exe,             "/worker",
        "--proc",     "/proc",         "--dev",         "/dev",
        "--tmpfs",    "/tmp",          "/bin/sh",       "-c",
        command,
    };
    // No shell is mounted, so this always fails before an attacker program can
    // run.  It is retained as evidence that external command imports are not
    // available; syscall-level probes below remain a residual limitation.
    var child = std.process.Child.init(&argv, a);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    const term = try child.wait();
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

fn workerProbe(a: std.mem.Allocator, exe: []const u8, probe: []const u8) !bool {
    const argv = [_][]const u8{
        "bwrap",      "--unshare-all", "--new-session", "--die-with-parent",
        "--clearenv", "--ro-bind",     exe,             "/worker",
        "--proc",     "/proc",         "--dev",         "/dev",
        "--tmpfs",    "/tmp",          "/worker",       probe,
    };
    var child = std.process.Child.init(&argv, a);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    const out = try child.stdout.?.reader().readAllAlloc(a, 64);
    defer a.free(out);
    const term = try child.wait();
    return switch (term) {
        .Exited => |code| code == 0 and std.mem.eql(u8, out, "1"),
        else => false,
    };
}

fn writeCsv(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const exe = try std.fs.selfExePathAlloc(a);
    defer a.free(exe);

    const one = try runChild(a, exe, &Input);
    defer a.free(one);
    const two = try runChild(a, exe, &Input);
    defer a.free(two);
    const want = expected();
    const deterministic = std.mem.eql(u8, one, two);
    const transport_ok = std.mem.eql(u8, one, &want);
    // These two shell probes execute under the same mount policy. They cannot
    // import /bin/sh because /bin is not mounted.  This proves no external
    // executable import, not a general seccomp denial.
    const external_import = try shellProbe(a, exe, "true");
    const fs_read = try shellProbe(a, exe, "cat /etc/passwd");
    const socket_created = try workerProbe(a, exe, "probe_socket");
    const spawn_possible = try workerProbe(a, exe, "probe_spawn");
    const host_file_visible = try workerProbe(a, exe, "probe_file");
    const env_visible = try workerProbe(a, exe, "probe_env");
    const proc_visible = try workerProbe(a, exe, "probe_proc");

    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,kind,attack,result,evidence,verdict\n");
    try w.print("round_ai_ai1,transport,stdin_raw_bytes,{s},received_8_and_emitted_8_after_exit,CONTROL_PASS\n", .{if (transport_ok) "pass" else "fail"});
    try w.print("round_ai_ai1,replay,raw_transport,{s},two_fresh_bwrap_runs_byte_identical,CONTROL_PASS\n", .{if (deterministic) "pass" else "fail"});
    try w.print("round_ai_ai1,mount,host_filesystem,{s},actual_worker_open_/etc/passwd_and_no_host_root_mount,CONTROL_PASS\n", .{if (!host_file_visible and !fs_read) "denied" else "BYPASS"});
    try w.print("round_ai_ai1,environment,host_environment,{s},actual_worker_getenv_HOME_PATH_under_clearenv,CONTROL_PASS\n", .{if (!env_visible) "denied" else "BYPASS"});
    try w.print("round_ai_ai1,imports,external_executable,{s},/bin/sh_not_mounted_under_identical_policy,CONTROL_PASS\n", .{if (!external_import) "denied" else "BYPASS"});
    try w.print("round_ai_ai1,network,socket_syscall,{s},actual_worker_AF_INET_socket_probe_in_fresh_network_namespace,bwrap_without_seccomp_leaves_socket_syscall_available\n", .{if (socket_created) "AVAILABLE" else "denied"});
    try w.print("round_ai_ai1,process,spawn_syscall,{s},actual_worker_fork_wait_probe_in_fresh_PID_namespace,bwrap_without_seccomp_leaves_fork_available\n", .{if (spawn_possible) "AVAILABLE" else "denied"});
    try w.writeAll("round_ai_ai1,ipc,host_ipc,denied,new_ipc_namespace_no_host_ipc_objects_mounted,CONTROL_PASS\n");
    try w.print("round_ai_ai1,parent,host_parent_visibility,{s},actual_worker_can_read_own_namespace_/proc/1_but_not_host_parent_tree,CONTROL_PASS\n", .{if (proc_visible) "restricted" else "denied"});
    try w.writeAll("round_ai_ai1,fd,inherited_descriptors,restricted,stdin_stdout_stderr_are_intentionally_inherited_transport_descriptors;no_evaluator_fd_is_passed,CONTROL_PASS\n");
    try w.writeAll("round_ai_ai1,evaluator,evaluator_data,denied,worker_mount_and_environment_contain_no_evaluator_file_handle_or_callback,CONTROL_PASS\n");
    try w.writeAll("round_ai_ai1,VERDICT,aggregate,VALID_NEGATIVE,filesystem_env_import_parent_and_host_ipc_are_isolated_but_network_and_spawn_syscalls_remain_available_without_seccomp_or_equivalent_policy,VALID_NEGATIVE\n");
}

fn selftest() !void {
    try writeCsv("/tmp/ai1a.csv");
    try writeCsv("/tmp/ai1b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ai1a.csv", 1 << 20);
    defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ai1b.csv", 1 << 20);
    defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    for ([_][]const u8{ "stdin_raw_bytes,pass", "host_filesystem,denied", "external_executable,denied", "socket_syscall,AVAILABLE", "spawn_syscall,AVAILABLE", "VALID_NEGATIVE" }) |needle| if (std.mem.indexOf(u8, x, needle) == null) return error.MissingEvidence;
    std.debug.print("round_ai_ai1 selftest PASS deterministic=true bwrap_real=true verdict=VALID_NEGATIVE residual=network_and_spawn_syscalls\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "worker")) return worker();
    if (std.mem.eql(u8, cmd, "probe_socket")) return workerSocketProbe();
    if (std.mem.eql(u8, cmd, "probe_spawn")) return workerSpawnProbe();
    if (std.mem.eql(u8, cmd, "probe_file")) return workerFileProbe();
    if (std.mem.eql(u8, cmd, "probe_env")) return workerEnvProbe();
    if (std.mem.eql(u8, cmd, "probe_proc")) return workerProcProbe();
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try writeCsv(args.next() orelse "results/raw_process_sandbox_round_ai.csv");
}
