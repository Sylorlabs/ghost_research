//! Round AP / AP2: measured PID and resource boundary for an opaque candidate.
//!
//! This is a runtime receipt, not a containment theorem.  It uses hard rlimits
//! inside AO1's Bubblewrap profile and tests each limit from the candidate.
const std = @import("std");

const MaxOutput = 192;

fn candidate(mode: []const u8) !void {
    const out = std.io.getStdOut().writer();
    if (std.mem.eql(u8, mode, "baseline")) return out.writeAll("ACT:opaque:1\n");
    if (std.mem.eql(u8, mode, "fork")) {
        const pid = std.posix.fork() catch return out.writeAll("FORK:DENY\n");
        if (pid == 0) std.posix.exit(0);
        _ = std.posix.waitpid(pid, 0);
        return out.writeAll("FORK:EXPOSED\n");
    }
    if (std.mem.eql(u8, mode, "fds")) {
        var opened: usize = 0;
        while (opened < 32) : (opened += 1) {
            const f = std.fs.openFileAbsolute("/dev/null", .{}) catch break;
            // Deliberately retain handles until the bound is reached.
            _ = f;
        }
        return out.print("FDS:OPENED={d}\n", .{opened});
    }
    if (std.mem.eql(u8, mode, "memory")) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const bytes = 96 * 1024 * 1024;
        const x = gpa.allocator().alloc(u8, bytes) catch return out.writeAll("MEMORY:DENY\n");
        defer gpa.allocator().free(x);
        @memset(x, 0xa5); // force actual pages, not merely virtual reservation
        return out.writeAll("MEMORY:EXPOSED\n");
    }
    if (std.mem.eql(u8, mode, "cpu")) {
        var x: u64 = 1;
        while (true) x = x *% 6364136223846793005 +% 1;
    }
    if (std.mem.eql(u8, mode, "sleep")) {
        std.time.sleep(2 * std.time.ns_per_s);
        return out.writeAll("WALL:EXPOSED\n");
    }
    if (std.mem.eql(u8, mode, "output")) {
        var buf: [2048]u8 = undefined;
        @memset(&buf, 'X');
        return out.writeAll(&buf);
    }
    return error.UnknownMode;
}

fn wrapper(mode: []const u8) !void {
    // This runs as the PID-namespace init after Bubblewrap has finished its own
    // setup.  Lowering both soft and hard limits is allowed to the process
    // itself; candidate code cannot raise these hard ceilings afterward.
    const lim = struct {
        fn set(kind: std.posix.rlimit_resource, n: u64) !void {
            try std.posix.setrlimit(kind, .{ .cur = n, .max = n });
        }
    };
    try lim.set(.NOFILE, 8);
    try lim.set(.AS, 64 * 1024 * 1024);
    try lim.set(.CPU, 1);
    // NPROC is intentionally attempted last: Linux counts it by real host UID
    // on this setup, so it may reject a value below already-running same-user
    // host processes.  That limitation is measured, not hidden.
    lim.set(.NPROC, 1) catch {};
    try candidate(mode);
}

const Run = struct { status: []const u8, output: []u8 };

fn launch(a: std.mem.Allocator, exe: []const u8, mode: []const u8) !Run {
    // Limits are applied by the PID-namespace init shell immediately before
    // exec.  `exec` keeps that one PID; hard limits cannot be raised later by
    // the candidate.  `timeout` is evaluator-owned wall time, outside child.
    const script = try std.fmt.allocPrint(a,
        "exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-; exec timeout --signal=KILL 1s bwrap " ++
        "--unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-net --die-with-parent --new-session --cap-drop ALL --clearenv " ++
        "--ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind {s} /candidate --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work " ++
        "/bin/bash -ceu 'exec /candidate wrapper \"$1\"' bash {s}",
        .{ exe, mode },
    );
    defer a.free(script);
    const result = std.process.Child.run(.{ .allocator = a, .argv = &.{ "bash", "-ceu", script }, .max_output_bytes = MaxOutput }) catch |err| {
        return .{ .status = @errorName(err), .output = try a.dupe(u8, "") };
    };
    defer a.free(result.stderr);
    const status = switch (result.term) {
        .Exited => |code| if (code == 0) "exit_0" else if (code == 124) "exit_124" else if (code == 137) "exit_137" else "exit_nonzero",
        .Signal => "signal",
        .Stopped => "stopped",
        .Unknown => "unknown",
    };
    return .{ .status = status, .output = result.stdout };
}

fn cgroupStatus(a: std.mem.Allocator) ![]u8 {
    const controllers_file = std.fs.openFileAbsolute("/sys/fs/cgroup/cgroup.controllers", .{}) catch return a.dupe(u8, "cgroup_v2_unavailable");
    defer controllers_file.close();
    const controllers = try controllers_file.readToEndAlloc(a, 256);
    defer a.free(controllers);
    if (std.mem.indexOf(u8, controllers, "pids") == null) return a.dupe(u8, "pids_controller_unavailable");
    const max = std.fs.openFileAbsolute("/sys/fs/cgroup/pids.max", .{}) catch return a.dupe(u8, "pids_controller_not_exposed_to_current_cgroup");
    max.close();
    // Access must be writable to make a new dedicated child cgroup safely.
    const probe = std.fs.cwd().openFile("/sys/fs/cgroup/cgroup.subtree_control", .{ .mode = .write_only }) catch return a.dupe(u8, "v2_present_not_delegated");
    probe.close();
    return a.dupe(u8, "delegated_writable");
}

fn emit(w: anytype, probe: []const u8, observed: []const u8, verdict: []const u8, detail: []const u8) !void {
    try w.print("round_ap_ap2,{s},{s},{s},{s}\n", .{ probe, observed, verdict, detail });
}

fn run(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const exe = try std.fs.selfExePathAlloc(a);
    defer a.free(exe);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const w = file.writer();
    try w.writeAll("artifact,probe,observed,verdict,detail\n");
    const cg = try cgroupStatus(a); defer a.free(cg);
    if (std.mem.eql(u8, cg, "delegated_writable")) {
        try emit(w, "cgroup_v2_pids_max", cg, "ENFORCEABLE", "dedicated delegated cgroup can be used; this run will still record rlimit probes");
    } else {
        try emit(w, "cgroup_v2_pids_max", cg, "UNAVAILABLE", "host cgroup v2 exists but this same-user process cannot create/configure a dedicated pids.max cgroup; rlimit fallback is not equivalent");
    }
    const base = try launch(a, exe, "baseline"); defer a.free(base.output);
    if (!std.mem.eql(u8, base.output, "ACT:opaque:1\n") or !std.mem.eql(u8, base.status, "exit_0")) return error.BaselineFailure;
    try emit(w, "baseline_raw_action", "accepted", "PASS", "one opaque candidate process can execute a valid action");
    const forked = try launch(a, exe, "fork"); defer a.free(forked.output);
    if (std.mem.eql(u8, forked.output, "FORK:DENY\n")) {
        try emit(w, "fork_reap_one_child", "fork_denied_by_hard_RLIMIT_NPROC_1", "ENFORCED", "candidate remained the sole PID in its namespace; actual cgroup pids.max was unavailable");
    } else {
        try emit(w, "fork_reap_one_child", forked.output, "NOT_ENFORCED", "same-user RLIMIT_NPROC=1 could not be safely installed below the host UID's existing process count; do not claim one-process containment without delegated cgroup/seccomp");
    }
    const fds = try launch(a, exe, "fds"); defer a.free(fds.output);
    const fd_enforced = std.mem.startsWith(u8, fds.output, "FDS:OPENED=") and !std.mem.eql(u8, fds.output, "FDS:OPENED=32\n");
    try emit(w, "descriptor_exhaustion", std.mem.trimRight(u8, fds.output, "\n"), if (fd_enforced) "ENFORCED" else "NOT_ENFORCED", "hard RLIMIT_NOFILE=8 is tested by retained /dev/null handles; stdio/runtime descriptors consume part of the eight");
    const mem = try launch(a, exe, "memory"); defer a.free(mem.output);
    try emit(w, "address_space_96MiB", std.mem.trimRight(u8, mem.output, "\n"), if (std.mem.eql(u8, mem.output, "MEMORY:DENY\n")) "ENFORCED" else "NOT_ENFORCED", "hard RLIMIT_AS=64MiB; allocation touches pages if admitted");
    const cpu = try launch(a, exe, "cpu"); defer a.free(cpu.output);
    const cpu_ok = std.mem.eql(u8, cpu.status, "signal") or std.mem.eql(u8, cpu.status, "exit_137") or std.mem.eql(u8, cpu.status, "exit_124");
    try emit(w, "cpu_spin", cpu.status, if (cpu_ok) "ENFORCED" else "NOT_ENFORCED", "hard RLIMIT_CPU=1s and evaluator timeout=1s jointly bound a non-yielding candidate");
    const wall = try launch(a, exe, "sleep"); defer a.free(wall.output);
    const wall_ok = !std.mem.eql(u8, wall.output, "WALL:EXPOSED\n");
    try emit(w, "wall_execution", wall.status, if (wall_ok) "ENFORCED" else "NOT_ENFORCED", "evaluator-owned timeout kills a two-second sleeping candidate at one second");
    const output = try launch(a, exe, "output"); defer a.free(output.output);
    const output_ok = std.mem.eql(u8, output.status, "error.StreamTooLong") or std.mem.eql(u8, output.status, "error.OutputTooLong") or output.output.len <= MaxOutput;
    try emit(w, "stdout_output_cap", output.status, if (output_ok) "ENFORCED" else "NOT_ENFORCED", "parent Child.run max_output_bytes=192 prevents unbounded candidate stdout capture; protocol still separately requires one small action");
    const overall = std.mem.eql(u8, forked.output, "FORK:DENY\n") and fd_enforced and std.mem.eql(u8, mem.output, "MEMORY:DENY\n") and cpu_ok and wall_ok and output_ok;
    try emit(w, "verdict", if (overall) "rlimit_and_parent_bounds_exercised" else "one_or_more_bounds_not_observed", if (overall) "GATE_READY" else "INCONCLUSIVE", "cgroup pids.max remains unavailable unless a delegated writable cgroup is recorded; rlimit is per-process/UID behavior and not a substitute for seccomp or MAC");
}

fn selftest() !void {
    try run("/tmp/ap2-a.csv");
    try run("/tmp/ap2-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ap2-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ap2-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    std.debug.print("round_ap_ap2 selftest PASS deterministic=true\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "candidate")) return candidate(args.next() orelse return error.MissingMode);
    if (std.mem.eql(u8, cmd, "wrapper")) return wrapper(args.next() orelse return error.MissingMode);
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/pid_resource_boundary_round_ap.csv");
}
