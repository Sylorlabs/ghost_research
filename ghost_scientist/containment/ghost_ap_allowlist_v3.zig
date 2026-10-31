//! Export the launcher-owned default-deny cBPF policy for Ghost Ruler v3.
//!
//! Bubblewrap installs this policy before execing Python.  It permits the
//! dynamic loader, read-only Python imports, memory management, output, and the
//! candidate's one final seccomp load.  It does not permit sockets, process
//! creation, namespace/mount changes, signals, ptrace, or direct clock/sleep
//! syscalls.  The frozen candidate installs a much smaller second default-deny
//! allow-list after loading its grammar and before constructing a tool.
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
extern fn seccomp_export_bpf(ctx: Filter, fd: c_int) c_int;

fn allow(ctx: Filter, call: linux.SYS) !void {
    if (seccomp_rule_add_array(
        ctx,
        SCMP_ACT_ALLOW,
        @intCast(@intFromEnum(call)),
        0,
        null,
    ) != 0) return error.SeccompRuleAdd;
}

const allowed_syscalls = [_]linux.SYS{
    // Bubblewrap's final transition and the candidate's final filter load.
    .execve,
    .prctl,
    .seccomp,

    // Dynamic loader, Python source/stdlib reads, and descriptor metadata.
    .read,
    .pread64,
    .write,
    .writev,
    .close,
    .close_range,
    .open,
    .openat,
    .fstatat64,
    .fstat,
    .statx,
    .lseek,
    .getdents64,
    .readlink,
    .readlinkat,
    .access,
    .faccessat,
    .faccessat2,
    .fcntl,
    .ioctl,
    .getcwd,

    // Memory/runtime bootstrap.  No process, network, namespace, mount,
    // signal-send, direct-clock, or sleep call is present.
    .mmap,
    .mprotect,
    .munmap,
    .mremap,
    .madvise,
    .brk,
    .rt_sigaction,
    .rt_sigprocmask,
    .rt_sigreturn,
    .sigaltstack,
    .arch_prctl,
    .set_tid_address,
    .set_robust_list,
    .rseq,
    .futex,
    .getrandom,
    .getpid,
    .gettid,
    .getuid,
    .geteuid,
    .getgid,
    .getegid,
    .uname,
    .sysinfo,
    .getrlimit,
    .prlimit64,
    .getrusage,
    .exit,
    .exit_group,
};

fn exportPolicy(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{
        .read = true,
        .truncate = true,
    });
    defer file.close();

    const ctx = seccomp_init(SCMP_ACT_ERRNO_EPERM) orelse
        return error.SeccompInit;
    defer seccomp_release(ctx);

    for (allowed_syscalls) |call| try allow(ctx, call);
    if (seccomp_export_bpf(ctx, file.handle) != 0)
        return error.SeccompExport;
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const path = args.next() orelse {
        std.debug.print("usage: ghost_ap_allowlist_v3 <output.bpf>\n", .{});
        std.process.exit(2);
    };
    if (args.next() != null) return error.TooManyArguments;
    try exportPolicy(path);
    const out = std.io.getStdOut().writer();
    try out.print(
        "GHOST_AP_ALLOWLIST_V3 PASS default=errno_eperm allowed_syscalls={d} output={s}\n",
        .{ allowed_syscalls.len, path },
    );
}
