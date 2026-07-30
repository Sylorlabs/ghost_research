//! Hostile syscall probe for the launcher-owned Ghost Ruler v3 allow-list.
//!
//! The prospective runner executes this binary through the exact outer
//! unshare + Bubblewrap + cBPF path used for candidates.  Each raw syscall
//! below is intentionally absent from the launch allow-list and must return
//! EPERM.  This tests the default-deny policy itself; it does not install a
//! second filter.
const std = @import("std");
const linux = std.os.linux;

fn isEperm(raw: usize) bool {
    const signed: isize = @bitCast(raw);
    return signed == -@as(isize, @intFromEnum(std.posix.E.PERM));
}

pub fn main() !void {
    const probes = [_]struct {
        name: []const u8,
        call: linux.SYS,
        a0: usize,
        a1: usize,
        a2: usize,
    }{
        .{ .name = "fork", .call = .fork, .a0 = 0, .a1 = 0, .a2 = 0 },
        .{ .name = "socket", .call = .socket, .a0 = 2, .a1 = 1, .a2 = 0 },
        .{ .name = "unshare", .call = .unshare, .a0 = 0, .a1 = 0, .a2 = 0 },
        .{ .name = "kill", .call = .kill, .a0 = 1, .a1 = 0, .a2 = 0 },
        .{
            .name = "clock_gettime",
            .call = .clock_gettime,
            .a0 = 1,
            .a1 = 0,
            .a2 = 0,
        },
    };
    const out = std.io.getStdOut().writer();
    for (probes) |probe| {
        const raw = linux.syscall3(probe.call, probe.a0, probe.a1, probe.a2);
        const passed = isEperm(raw);
        try out.print(
            "{s}={s}\n",
            .{ probe.name, if (passed) "EPERM" else "NOT_EPERM" },
        );
        if (!passed) return error.SyscallNotDenied;
    }
    try out.writeAll(
        "GHOST_AP_PROBE_V3 PASS denials=5 policy=outer_default_deny"
            ++ " openat=launcher_required_then_finally_denied\n",
    );
}
