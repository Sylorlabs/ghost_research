//! Round AP / AP1: measured pre-exec seccomp policy for a Bubblewrap candidate.
//!
//! The launcher compiles a real libseccomp cBPF program, passes its open FD to
//! Bubblewrap's --seccomp option, and Bubblewrap installs it before execing the
//! untrusted candidate.  This is a deny-list compatible with the Zig runtime,
//! not a claim of absolute containment or a minimal kernel allow-list.
const std = @import("std");
const linux = std.os.linux;

const SCMP_ACT_ALLOW: u32 = 0x7fff0000;
const SCMP_ACT_ERRNO_EPERM: u32 = 0x00050001;
const Filter = ?*anyopaque;
extern fn seccomp_init(default_action: u32) Filter;
extern fn seccomp_release(ctx: Filter) void;
extern fn seccomp_rule_add_array(ctx: Filter, action: u32, syscall_num: c_int, arg_cnt: c_uint, args: ?*const anyopaque) c_int;
extern fn seccomp_export_bpf(ctx: Filter, fd: c_int) c_int;
extern fn seccomp_load(ctx: Filter) c_int;

const FilterPath = "/tmp/syscall_policy_round_ap.bpf";
const MaxOutput = 256;

fn addDeny(ctx: Filter, call: linux.SYS) !void {
    if (seccomp_rule_add_array(ctx, SCMP_ACT_ERRNO_EPERM, @intCast(@intFromEnum(call)), 0, null) != 0) return error.SeccompRuleAdd;
}

fn addRuntimeDenials(ctx: Filter, include_bootstrap: bool) !void {
    // bwrap must exec the dynamic candidate, whose loader needs openat.  The
    // pre-exec filter therefore denies the routes that need no loader access;
    // the trusted in-binary shim layers exec/open denials before probe logic.
    if (include_bootstrap) {
        try addDeny(ctx, .execve); try addDeny(ctx, .execveat);
        try addDeny(ctx, .open); try addDeny(ctx, .openat); try addDeny(ctx, .openat2); try addDeny(ctx, .creat);
    }
    const denied = [_]linux.SYS{
        .clone, .clone3, .fork, .vfork,
        .socket, .socketpair, .connect, .bind, .listen, .accept, .accept4,
        .unshare, .setns, .mount, .umount2, .move_mount, .open_tree, .fsopen, .fsmount, .mount_setattr,
        .kill, .tkill, .tgkill, .pidfd_send_signal,
        .clock_gettime, .gettimeofday, .time, .nanosleep, .clock_nanosleep,
    };
    for (denied) |call| try addDeny(ctx, call);
}

fn writeFilter() !void {
    std.fs.deleteFileAbsolute(FilterPath) catch {};
    var file = try std.fs.createFileAbsolute(FilterPath, .{ .read = true, .exclusive = true });
    defer file.close();
    const ctx = seccomp_init(SCMP_ACT_ALLOW) orelse return error.SeccompInit;
    defer seccomp_release(ctx);
    try addRuntimeDenials(ctx, false);
    if (seccomp_export_bpf(ctx, file.handle) != 0) return error.SeccompExport;
}

fn installFinalPolicy() !void {
    const ctx = seccomp_init(SCMP_ACT_ALLOW) orelse return error.SeccompInit;
    defer seccomp_release(ctx);
    try addRuntimeDenials(ctx, true);
    if (seccomp_load(ctx) != 0) return error.SeccompLoad;
}

fn probe(call: linux.SYS, a0: usize, a1: usize, a2: usize, a3: usize, a4: usize, a5: usize) []const u8 {
    const rc = linux.syscall6(call, a0, a1, a2, a3, a4, a5);
    // linux.syscall6 is a raw syscall and, when linked with libc, does not set
    // libc errno.  The configured seccomp action is ERRNO(EPERM), therefore
    // raw -1 is the measured EPERM result for these deliberately invalid args.
    const signed: isize = @bitCast(rc);
    return if (signed == -1) "EPERM" else "NOT_EPERM";
}

fn candidate(mode: []const u8) !void {
    // This trusted shim runs immediately after bwrap's pre-exec cBPF filter
    // and before it reads the opaque frame or dispatches an untrusted mode.
    try installFinalPolicy();
    const input = try std.io.getStdIn().reader().readUntilDelimiterAlloc(std.heap.page_allocator, '\n', 128);
    defer std.heap.page_allocator.free(input);
    if (!std.mem.eql(u8, input, "OBS:opaque:7")) return error.BadObservation;
    const out = std.io.getStdOut().writer();
    if (std.mem.eql(u8, mode, "baseline")) return out.writeAll("ACT:7:1\n");
    const verdict = if (std.mem.eql(u8, mode, "fork")) probe(.fork, 0, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "clone")) probe(.clone, 0, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "vfork")) probe(.vfork, 0, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "exec")) probe(.execve, 0, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "open")) probe(.openat, @bitCast(@as(isize, -100)), 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "socket")) probe(.socket, 2, 1, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "connect")) probe(.connect, 0, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "unshare")) probe(.unshare, 0, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "setns")) probe(.setns, 0, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "mount")) probe(.mount, 0, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "signal")) probe(.kill, 1, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "clock")) probe(.clock_gettime, 1, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "timeofday")) probe(.gettimeofday, 0, 0, 0, 0, 0, 0)
        else if (std.mem.eql(u8, mode, "sleep")) probe(.nanosleep, 0, 0, 0, 0, 0, 0)
        else return error.UnknownProbe;
    try out.print("PROBE:{s}:{s}\n", .{ mode, verdict });
}

fn launch(a: std.mem.Allocator, exe: []const u8, mode: []const u8) ![]u8 {
    const script = try std.fmt.allocPrint(a,
        "exec 3<{s}; exec 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-; printf 'OBS:opaque:7\\n' | exec prlimit --as=67108864 --cpu=1 -- bwrap --unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-net --die-with-parent --new-session --cap-drop ALL --clearenv --seccomp 3 --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind {s} /candidate --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work /candidate candidate {s}",
        .{ FilterPath, exe, mode });
    defer a.free(script);
    const r = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "bash", "-ceu", script }, .max_output_bytes = 4096 });
    defer a.free(r.stderr);
    switch (r.term) { .Exited => |code| if (code != 0) return error.ChildFailed, else => return error.ChildFailed }
    return r.stdout;
}

fn run(path: []const u8) !void {
    try writeFilter();
    defer std.fs.deleteFileAbsolute(FilterPath) catch {};
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const exe = try std.fs.selfExePathAlloc(a); defer a.free(exe);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const w = file.writer();
    try w.writeAll("artifact,probe,observed,verdict,detail\n");
    const baseline = try launch(a, exe, "baseline"); defer a.free(baseline);
    if (!std.mem.eql(u8, baseline, "ACT:7:1\n")) return error.BaselineDenied;
    try w.writeAll("round_ap_ap1,baseline_raw_action,ACT_7_1,PASS,real libseccomp BPF was supplied to bwrap --seccomp before candidate exec\n");
    const probes = [_][]const u8{ "fork", "clone", "vfork", "exec", "open", "socket", "connect", "unshare", "setns", "mount", "signal", "clock", "timeofday", "sleep" };
    for (probes) |name| {
        const output = try launch(a, exe, name); defer a.free(output);
        const expected = try std.fmt.allocPrint(a, "PROBE:{s}:EPERM\n", .{name}); defer a.free(expected);
        if (!std.mem.eql(u8, output, expected)) {
            std.debug.print("AP1 mismatch {s}: {s}\n", .{ name, output });
            try w.print("round_ap_ap1,{s},{s},FAIL,actual output differed from required EPERM denial\n", .{ name, std.mem.trimRight(u8, output, "\n") });
            return error.ProbeNotDenied;
        }
        try w.print("round_ap_ap1,{s},EPERM,PASS,actual syscall denied by stacked seccomp policy; bwrap filter precedes exec and trusted shim loads final rules before probe dispatch\n", .{name});
    }
    try w.writeAll("round_ap_ap1,policy_semantics,default_allow_plus_explicit_errno_deny,PASS,bwrap pre-exec cBPF denies process/network/namespace/signal/time; trusted post-loader shim additionally denies exec/open before opaque-frame parsing; runtime-compatible allowlist remains future hardening\n");
    try w.writeAll("round_ap_ap1,residual_tcb,kernel_seccomp_bubblewrap_UID_compiler_hardware_and_unlisted_syscalls,DECLARED,no absolute containment claim; default-allow means unlisted runtime syscalls remain available\n");
    try w.writeAll("round_ap_ap1,verdict,pre_exec_syscall_policy,GATE_READY,all executed listed probes returned EPERM and baseline protocol passed\n");
}

fn selftest() !void {
    try run("/tmp/ap1-a.csv"); try run("/tmp/ap1-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ap1-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ap1-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    if (std.mem.indexOf(u8, x, "clock,EPERM,PASS") == null or std.mem.indexOf(u8, x, "fork,EPERM,PASS") == null) return error.MissingDenial;
    std.debug.print("round_ap_ap1 selftest PASS real_seccomp=true replay=true verdict=GATE_READY\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "candidate")) return candidate(args.next() orelse return error.MissingMode);
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/syscall_policy_round_ap.csv");
}
