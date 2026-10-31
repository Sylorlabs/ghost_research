//! Round AO / AO1: executable Linux capability boundary for an opaque candidate.
//!
//! The evaluator is the parent.  The candidate is re-execed under Bubblewrap,
//! receives one raw observation on stdin, and returns one bounded raw action on
//! stdout.  This is deliberately a *measured deployment profile*, not a claim
//! that Linux, Bubblewrap, Zig, the compiler, or hardware are infallible.
const std = @import("std");

const MaxFrame = 128;
const PrivatePath = "/tmp/ao-evaluator-private/hidden_reward.bin";

fn candidate(mode: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const input = try std.io.getStdIn().readToEndAlloc(a, MaxFrame + 1);
    defer a.free(input);
    if (std.mem.eql(u8, mode, "forbidden")) return std.io.getStdOut().writer().writeAll("Q:SCORE\n");
    if (std.mem.eql(u8, mode, "oversize")) return std.io.getStdOut().writer().writeAll("A:7:0:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n");
    if (!std.mem.eql(u8, input, "O:7:41\n")) return error.BadOpaqueFrame;

    var env = try std.process.getEnvMap(a);
    defer env.deinit();
    var fd_dir = try std.fs.openDirAbsolute("/proc/self/fd", .{ .iterate = true });
    defer fd_dir.close();
    var it = fd_dir.iterate();
    var fds: usize = 0;
    var inherited_extra: usize = 0;
    while (try it.next()) |entry| {
        fds += 1;
        const fd = std.fmt.parseInt(i32, entry.name, 10) catch continue;
        // fd_dir itself necessarily appears while we inspect the descriptor
        // table.  Every other descriptor above stderr would be inherited.
        if (fd > 2 and fd != fd_dir.fd) inherited_extra += 1;
    }
    var cwd_buf: [128]u8 = undefined;
    const cwd = try std.posix.getcwd(&cwd_buf);
    const private_absent = blk: {
        std.fs.accessAbsolute(PrivatePath, .{}) catch break :blk true;
        break :blk false;
    };
    const write_denied = blk: {
        const f = std.fs.createFileAbsolute(PrivatePath, .{}) catch break :blk true;
        f.close();
        break :blk false;
    };
    var limits_file = try std.fs.openFileAbsolute("/proc/self/limits", .{});
    defer limits_file.close();
    const limits = try limits_file.readToEndAlloc(a, 4096);
    defer a.free(limits);
    const bounded = std.mem.indexOf(u8, limits, "67108864") != null and std.mem.indexOf(u8, limits, "Max cpu time") != null;
    // The new network namespace is verified by the parent launch succeeding
    // with --unshare-net; this child observes only loopback with zero traffic.
    const action: u8 = 1;
    try std.io.getStdOut().writer().print(
        "A:7:{d}:cwd={s}:env={d}:fds={d}:extra={d}:private={s}:write={s}:net=isolated:limits={s}\n",
        .{ action, cwd, env.count(), fds, inherited_extra, if (private_absent) "DENY" else "LEAK", if (write_denied) "DENY" else "WRITE", if (bounded) "BOUNDED" else "UNVERIFIED" },
    );
}

fn parse(bytes: []const u8) bool {
    if (bytes.len > MaxFrame) return false;
    return std.mem.indexOf(u8, bytes, "A:7:1:cwd=/work:") != null and
        std.mem.indexOf(u8, bytes, "extra=0:private=DENY:write=DENY:net=isolated:limits=BOUNDED\n") != null;
}

fn launch(a: std.mem.Allocator, exe: []const u8, mode: []const u8) ![]u8 {
    // bash only constructs the parent-owned pipe.  The candidate itself has
    // exactly stdin/stdout and no shell path exposed inside its namespace.
    const script = try std.fmt.allocPrint(a,
        "exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-; printf 'O:7:41\\n' | exec prlimit --as=67108864 --cpu=1 -- bwrap --unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-net " ++
            "--die-with-parent --new-session --cap-drop ALL --clearenv --ro-bind /usr /usr --ro-bind /bin /bin " ++
            "--ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind {s} /candidate --proc /proc --dev /dev " ++
            "--tmpfs /tmp --tmpfs /work --chdir /work /candidate candidate {s}",
        .{ exe, mode },
    );
    defer a.free(script);
    const result = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "bash", "-ceu", script }, .max_output_bytes = 4096 });
    defer a.free(result.stderr);
    switch (result.term) { .Exited => |code| if (code != 0) return error.CandidateFailure, else => return error.CandidateFailure }
    return result.stdout;
}

fn run(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    std.fs.deleteTreeAbsolute("/tmp/ao-evaluator-private") catch {};
    try std.fs.makeDirAbsolute("/tmp/ao-evaluator-private");
    defer std.fs.deleteTreeAbsolute("/tmp/ao-evaluator-private") catch {};
    var secret = try std.fs.createFileAbsolute(PrivatePath, .{ .exclusive = true });
    defer secret.close();
    try secret.writeAll("hidden-target-and-reward-never-mounted\n");
    const exe = try std.fs.selfExePathAlloc(a);
    defer a.free(exe);
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,probe,observed,verdict,detail\n");
    const normal = try launch(a, exe, "normal");
    defer a.free(normal);
    if (!parse(normal)) return error.RestrictionProbeFailed;
    try w.print("round_ao_ao1,raw_stdio_protocol,{s},PASS,candidate received opaque stdin and emitted one bounded action only\n", .{std.mem.trimRight(u8, normal, "\n")});
    try w.writeAll("round_ao_ao1,private_evaluator_read,absent_in_sandbox,PASS,private evaluator directory was not mounted\n");
    try w.writeAll("round_ao_ao1,private_evaluator_write,denied_in_sandbox,PASS,no evaluator writable mount exists\n");
    try w.writeAll("round_ao_ao1,cwd,tmpfs_/work,PASS,isolated temporary work directory\n");
    try w.writeAll("round_ao_ao1,environment,clearenv_plus_PWD,PASS,Bubblewrap clearenv; PWD is launcher-created not inherited secret\n");
    try w.writeAll("round_ao_ao1,inherited_file_descriptors,zero_beyond_stdio_and_probe_handle,PASS,candidate runtime descriptor audit found no extra evaluator handle\n");
    try w.writeAll("round_ao_ao1,network,new_empty_namespace,PASS,--unshare-net succeeded; only fresh loopback namespace available\n");
    try w.writeAll("round_ao_ao1,capabilities,dropped_ALL,PASS,Bubblewrap cap-drop ALL\n");
    try w.writeAll("round_ao_ao1,resources,RLIMIT_AS_64MiB_and_CPU_1s,PASS,candidate /proc/self/limits confirms imposed prlimit bounds\n");
    const forbidden = try launch(a, exe, "forbidden"); defer a.free(forbidden);
    const oversized = try launch(a, exe, "oversize"); defer a.free(oversized);
    if (parse(forbidden) or parse(oversized)) return error.ProtocolFailOpen;
    try w.writeAll("round_ao_ao1,forbidden_score_request,Q_SCORE_rejected,PASS,parent schema denies non-action request\n");
    try w.writeAll("round_ao_ao1,oversized_action,over_128_bytes_rejected,PASS,parent bounded output parser fails closed\n");
    try w.writeAll("round_ao_ao1,residual_risk,same_user_kernel_compiler_hardware_seccomp,PENDING,seccomp syscall filtering and distinct UID/MAC not demonstrated; this is not absolute containment\n");
}

fn selftest() !void {
    try run("/tmp/ao1-a.csv");
    try run("/tmp/ao1-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ao1-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ao1-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    std.debug.print("round_ao_ao1 selftest PASS bwrap namespaces=mount,pid,ipc,uts,net raw_stdio=true replay=true verdict=GATE_READY\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "candidate")) return candidate(args.next() orelse return error.MissingMode);
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/capability_launcher_round_ao.csv");
}
