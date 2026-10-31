//! AP-compatible containment probe for the frozen Ghost Math candidate.
//!
//! Run this binary through the same Bubblewrap/prlimit boundary as the
//! candidate.  It installs the candidate's final default-allow deny-list and
//! directly proves that process, filesystem, network, namespace, signal, and
//! time syscalls return EPERM.  This is measured policy evidence, not an
//! absolute security claim or a minimal allow-list.
const std = @import("std");
const linux = std.os.linux;

const SCMP_ACT_ALLOW: u32 = 0x7fff0000;
const SCMP_ACT_ERRNO_EPERM: u32 = 0x00050001;
const Filter = ?*anyopaque;

extern fn seccomp_init(default_action: u32) Filter;
extern fn seccomp_release(ctx: Filter) void;
extern fn seccomp_rule_add_array(
    ctx: Filter,
    action: u32,
    syscall_num: c_int,
    arg_cnt: c_uint,
    args: ?*const anyopaque,
) c_int;
extern fn seccomp_load(ctx: Filter) c_int;

fn deny(ctx: Filter, call: linux.SYS) !void {
    if (seccomp_rule_add_array(
        ctx,
        SCMP_ACT_ERRNO_EPERM,
        @intCast(@intFromEnum(call)),
        0,
        null,
    ) != 0) return error.SeccompRuleAdd;
}

fn seal() !void {
    const ctx = seccomp_init(SCMP_ACT_ALLOW) orelse return error.SeccompInit;
    defer seccomp_release(ctx);
    const denied_calls = [_]linux.SYS{
        .clone,   .clone3,            .fork,            .vfork,
        .execve,  .execveat,          .open,            .openat,
        .openat2, .creat,             .socket,          .socketpair,
        .connect, .bind,              .listen,          .accept,
        .accept4, .unshare,           .setns,           .mount,
        .umount2, .move_mount,        .open_tree,       .fsopen,
        .fsmount, .mount_setattr,     .kill,            .tkill,
        .tgkill,  .pidfd_send_signal, .clock_gettime,   .gettimeofday,
        .time,    .nanosleep,         .clock_nanosleep,
    };
    for (denied_calls) |call| try deny(ctx, call);
    if (seccomp_load(ctx) != 0) return error.SeccompLoad;
}

fn denied(call: linux.SYS, a0: usize, a1: usize, a2: usize) bool {
    const raw = linux.syscall3(call, a0, a1, a2);
    const signed: isize = @bitCast(raw);
    return signed == -1;
}

pub fn main() !void {
    try seal();
    const probes = [_]struct {
        name: []const u8,
        call: linux.SYS,
        a0: usize,
        a1: usize,
        a2: usize,
    }{
        .{ .name = "fork", .call = .fork, .a0 = 0, .a1 = 0, .a2 = 0 },
        .{ .name = "openat", .call = .openat, .a0 = @bitCast(@as(isize, -100)), .a1 = 0, .a2 = 0 },
        .{ .name = "socket", .call = .socket, .a0 = 2, .a1 = 1, .a2 = 0 },
        .{ .name = "unshare", .call = .unshare, .a0 = 0, .a1 = 0, .a2 = 0 },
        .{ .name = "kill", .call = .kill, .a0 = 1, .a1 = 0, .a2 = 0 },
        .{ .name = "clock_gettime", .call = .clock_gettime, .a0 = 1, .a1 = 0, .a2 = 0 },
    };
    const out = std.io.getStdOut().writer();
    for (probes) |probe| {
        const passed = denied(probe.call, probe.a0, probe.a1, probe.a2);
        try out.print("{s}={s}\n", .{ probe.name, if (passed) "EPERM" else "NOT_EPERM" });
        if (!passed) return error.SyscallNotDenied;
    }
    try out.writeAll("GHOST_MATH_AP_PROBE_V1 PASS denials=6 default_allow_residual=true\n");
}
