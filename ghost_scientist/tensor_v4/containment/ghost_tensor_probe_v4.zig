//! Hostile syscall probe for the launcher-owned Tensor v4 policy.
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
        if (!isEperm(raw)) return error.SyscallNotDenied;
        try out.print("{s}=EPERM\n", .{probe.name});
    }
    try out.writeAll(
        "GHOST_TENSOR_OUTER_PROBE_V4 PASS denials=5 policy=default_deny\n",
    );
}
