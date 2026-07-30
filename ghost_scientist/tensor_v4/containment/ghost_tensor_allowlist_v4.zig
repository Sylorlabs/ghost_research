//! Launcher-owned default-deny cBPF policy for Ghost Tensor v4.
//!
//! Bubblewrap installs this before Python starts. It permits only loader and
//! read-only bootstrap operations plus the candidate's final seccomp load.
//! The candidate installs a smaller filter after reading its two visible
//! inputs. Neither layer permits network or process creation.
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
    .execve,
    .prctl,
    .seccomp,
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

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const path = args.next() orelse {
        std.debug.print("usage: ghost_tensor_allowlist_v4 <output.bpf>\n", .{});
        std.process.exit(2);
    };
    if (args.next() != null) return error.TooManyArguments;
    var file = try std.fs.cwd().createFile(path, .{ .read = true, .truncate = true });
    defer file.close();
    const context = seccomp_init(SCMP_ACT_ERRNO_EPERM) orelse
        return error.SeccompInit;
    defer seccomp_release(context);
    for (allowed_syscalls) |call| try allow(context, call);
    if (seccomp_export_bpf(context, file.handle) != 0)
        return error.SeccompExport;
    try std.io.getStdOut().writer().print(
        "GHOST_TENSOR_ALLOWLIST_V4 PASS default=errno_eperm allowed_syscalls={d} output={s}\n",
        .{ allowed_syscalls.len, path },
    );
}
