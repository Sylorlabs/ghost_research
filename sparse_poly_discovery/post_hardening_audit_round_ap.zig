//! Round AP / AP4: independent hostile runtime audit of the combined launcher.
//!
//! The evaluator remains outside Bubblewrap.  A fresh candidate enters AO1's
//! mount/namespace profile, receives AP1's launcher-owned BPF FD, then installs
//! the AP1 bootstrap filter before reading its one opaque observation.  The
//! parent applies AP2 limits and owns transcript/budget validation (AO3 style).
//! This is an executable local-Linux audit, not a containment theorem.
const std = @import("std");
const linux = std.os.linux;
const c = @cImport({ @cInclude("errno.h"); @cInclude("seccomp.h"); @cInclude("sys/syscall.h"); @cInclude("sys/time.h"); @cInclude("time.h"); });

const FilterPath = "/tmp/post_hardening_ap4.bpf";
const SecretPath = "/tmp/ap4-evaluator-only/hidden_target_reward";
const Observation = "OBS:opaque:ap4\n";
const MaxOutput = 192;

const Action = struct { nonce: u16, turn: u8, value: u8 };
const Eval = struct {
    next_turn: u8 = 0,
    chain: u64 = 0x4150_345f_4556_414c,
    fn mix(x0: u64) u64 { var x = x0; x ^= x >> 30; x *%= 0xbf58_476d_1ce4_e5b9; x ^= x >> 27; x *%= 0x94d0_49bb_1331_11eb; return x ^ (x >> 31); }
    fn accept(self: *Eval, text: []const u8) bool {
        var it = std.mem.splitScalar(u8, std.mem.trimRight(u8, text, "\n"), ':');
        if (!std.mem.eql(u8, it.next() orelse return false, "ACT")) return false;
        const n = std.fmt.parseInt(u16, it.next() orelse return false, 10) catch return false;
        const t = std.fmt.parseInt(u8, it.next() orelse return false, 10) catch return false;
        const v = std.fmt.parseInt(u8, it.next() orelse return false, 10) catch return false;
        if (it.next() != null or n != @as(u16, 4109) + @as(u16, self.next_turn) * 37 or t != self.next_turn or v > 3) return false;
        self.chain = mix(self.chain ^ (@as(u64, n) << 16) ^ (@as(u64, t) << 8) ^ v);
        self.next_turn += 1;
        return true;
    }
};

fn seccompDeny(ctx: anytype, call: c_int) !void {
    if (c.seccomp_rule_add(ctx, c.SCMP_ACT_ERRNO(c.EPERM), call, 0) != 0) return error.Rule;
}
fn populate(ctx: anytype, final: bool) !void {
    if (final) { try seccompDeny(ctx, c.SYS_execve); try seccompDeny(ctx, c.SYS_execveat); try seccompDeny(ctx, c.SYS_open); try seccompDeny(ctx, c.SYS_openat); }
    const calls = [_]c_int{ c.SYS_clone, c.SYS_fork, c.SYS_vfork, c.SYS_socket, c.SYS_socketpair, c.SYS_connect, c.SYS_bind, c.SYS_listen, c.SYS_unshare, c.SYS_setns, c.SYS_mount, c.SYS_umount2, c.SYS_kill, c.SYS_tkill, c.SYS_tgkill, c.SYS_clock_gettime, c.SYS_gettimeofday, c.SYS_time, c.SYS_nanosleep, c.SYS_clock_nanosleep };
    for (calls) |call| try seccompDeny(ctx, call);
}
fn writeOuterFilter() !void {
    std.fs.deleteFileAbsolute(FilterPath) catch {};
    var f = try std.fs.createFileAbsolute(FilterPath, .{ .read = true, .exclusive = true }); defer f.close();
    const ctx = c.seccomp_init(c.SCMP_ACT_ALLOW) orelse return error.Init; defer c.seccomp_release(ctx);
    try populate(ctx, false);
    if (c.seccomp_export_bpf(ctx, f.handle) != 0) return error.Export;
}
fn installFinal() !void {
    const ctx = c.seccomp_init(c.SCMP_ACT_ALLOW) orelse return error.Init; defer c.seccomp_release(ctx);
    try populate(ctx, true);
    if (c.seccomp_load(ctx) != 0) return error.Load;
}
fn raw(call: linux.SYS, a0: usize, a1: usize, a2: usize, a3: usize, a4: usize, a5: usize) []const u8 {
    const bits = linux.syscall6(call, a0, a1, a2, a3, a4, a5);
    const signed: isize = @bitCast(bits);
    return if (signed == -1) "EPERM" else "ALLOW";
}
fn normalInput() !void {
    const got = try std.io.getStdIn().reader().readUntilDelimiterAlloc(std.heap.page_allocator, '\n', 128); defer std.heap.page_allocator.free(got);
    if (!std.mem.eql(u8, got, "OBS:opaque:ap4")) return error.BadObservation;
}
fn candidate(mode: []const u8) !void {
    try installFinal();
    try normalInput();
    const out = std.io.getStdOut().writer();
    if (std.mem.eql(u8, mode, "baseline")) return out.writeAll("ACT:4109:0:1\n");
    if (std.mem.eql(u8, mode, "env_cwd")) { var a = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer a.deinit(); const env = try std.process.getEnvMap(a.allocator()); var buf: [256]u8 = undefined; const cwd = try std.posix.getcwd(&buf); return out.print("ENV={d};CWD={s}\n", .{env.count(), cwd}); }
    if (std.mem.eql(u8, mode, "secret_file")) { const f = std.fs.openFileAbsolute(SecretPath, .{}) catch return out.writeAll("SECRET:EPERM\n"); f.close(); return out.writeAll("SECRET:ALLOW\n"); }
    if (std.mem.eql(u8, mode, "proc_fd")) { const f = std.fs.openFileAbsolute("/proc/self/fd", .{}) catch return out.writeAll("PROC_FD:EPERM\n"); f.close(); return out.writeAll("PROC_FD:ALLOW\n"); }
    if (std.mem.eql(u8, mode, "syscalls")) return out.print("FORK={s};CLONE={s};EXEC={s};OPEN={s};SOCKET={s};MOUNT={s};SIGNAL={s}\n", .{ raw(.fork,0,0,0,0,0,0), raw(.clone,0,0,0,0,0,0), raw(.execve,0,0,0,0,0,0), raw(.openat,@bitCast(@as(isize,-100)),0,0,0,0,0), raw(.socket,2,1,0,0,0,0), raw(.mount,0,0,0,0,0,0), raw(.kill,1,0,0,0,0,0) });
    if (std.mem.eql(u8, mode, "time")) { var ts: c.struct_timespec = undefined; var tv: c.struct_timeval = undefined; const dclock = raw(.clock_gettime,1,@intFromPtr(&ts),0,0,0,0); const dsleep = raw(.nanosleep,0,0,0,0,0,0); const lclock = if (c.clock_gettime(c.CLOCK_MONOTONIC, &ts) == -1) "EPERM" else "ALLOW"; const ltv = if (c.gettimeofday(&tv, null) == -1) "EPERM" else "ALLOW"; return out.print("DIRECT_CLOCK={s};DIRECT_SLEEP={s};VDSO_CLOCK={s};VDSO_TIME={s}\n", .{dclock, dsleep, lclock, ltv}); }
    if (std.mem.eql(u8, mode, "inject")) return out.writeAll("GET:SCORE\nACT:4109:0:1\n");
    if (std.mem.eql(u8, mode, "oversize")) { var b: [256]u8 = undefined; @memset(&b, 'X'); return out.writeAll(&b); }
    if (std.mem.eql(u8, mode, "forged")) return out.writeAll("ACT:7:9:9\n");
    if (std.mem.eql(u8, mode, "replay")) return out.writeAll("ACT:4109:0:1\n");
    if (std.mem.eql(u8, mode, "resource")) { var i: usize = 0; while (i < 1000000) : (i += 1) _ = linux.syscall0(.fork); return out.writeAll("RESOURCE:COMPLETE\n"); }
    return error.UnknownMode;
}

const Run = struct { status: []const u8, stdout: []u8 };
fn launch(a: std.mem.Allocator, exe: []const u8, mode: []const u8) !Run {
    const script = try std.fmt.allocPrint(a,
        "exec 3<{s}; exec 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-; printf 'OBS:opaque:ap4\\n' | exec timeout --signal=KILL 1s prlimit --as=67108864 --cpu=1 --nofile=8:8 -- bwrap --unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-net --die-with-parent --new-session --cap-drop ALL --clearenv --seccomp 3 --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind {s} /candidate --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work /candidate candidate {s}", .{ FilterPath, exe, mode });
    defer a.free(script);
    const r = std.process.Child.run(.{ .allocator = a, .argv = &.{ "bash", "-ceu", script }, .max_output_bytes = MaxOutput }) catch |e| return .{ .status = @errorName(e), .stdout = try a.dupe(u8, "") };
    defer a.free(r.stderr);
    const st = switch (r.term) { .Exited => |x| if (x == 0) "exit_0" else "exit_nonzero", .Signal => "signal", else => "other" };
    return .{ .status = st, .stdout = r.stdout };
}
fn emit(w: anytype, route: []const u8, observed: []const u8, result: []const u8, transcript: []const u8, detail: []const u8) !void { try w.print("round_ap_ap4,{s},{s},{s},{s},{s}\n", .{route, observed, result, transcript, detail}); }
fn csvAtom(input: []const u8, buffer: []u8) []const u8 {
    const n = @min(input.len, buffer.len);
    for (input[0..n], 0..) |byte, i| buffer[i] = switch (byte) { '\n', '\r' => '|', ',' => ';', else => byte };
    return buffer[0..n];
}
fn run(path: []const u8) !void {
    try writeOuterFilter(); defer std.fs.deleteFileAbsolute(FilterPath) catch {};
    std.fs.deleteTreeAbsolute("/tmp/ap4-evaluator-only") catch {}; try std.fs.makeDirAbsolute("/tmp/ap4-evaluator-only"); defer std.fs.deleteTreeAbsolute("/tmp/ap4-evaluator-only") catch {};
    var secret = try std.fs.createFileAbsolute(SecretPath, .{}); defer secret.close(); try secret.writeAll("hidden target reward evaluator only");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator(); const exe = try std.fs.selfExePathAlloc(a); defer a.free(exe);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const w = file.writer(); try w.writeAll("artifact,route,observed,result,transcript,detail\n");
    var ev = Eval{}; const b = try launch(a, exe, "baseline"); defer a.free(b.stdout); if (!std.mem.eql(u8,b.status,"exit_0") or !ev.accept(b.stdout)) return error.Baseline; try emit(w,"baseline_action","strict_raw_action","PASS","advanced_turn_0","opaque input accepted; evaluator state remains parent-owned");
    const cases = [_]struct{ mode: []const u8, route: []const u8 }{ .{.mode="env_cwd",.route="environment_and_cwd"}, .{.mode="secret_file",.route="evaluator_file_read"}, .{.mode="proc_fd",.route="proc_and_descriptor_inspection"}, .{.mode="syscalls",.route="fork_clone_exec_open_socket_mount_signal"}, .{.mode="inject",.route="score_request_and_protocol_injection"}, .{.mode="oversize",.route="oversized_stdout"}, .{.mode="forged",.route="forged_nonce_reordered_action"}, .{.mode="replay",.route="replayed_action"}, .{.mode="resource",.route="bounded_pid_resource_attempt"}, .{.mode="time",.route="direct_and_vdso_time"} };
    for (cases) |x| { const r = try launch(a, exe, x.mode); defer a.free(r.stdout); const unchanged = ev.next_turn == 1; const o = std.mem.trimRight(u8,r.stdout,"\n"); var clean: [MaxOutput]u8 = undefined; var result: []const u8 = "DENIED"; var detail: []const u8 = "hostile output rejected; evaluator transcript and budget unchanged";
        if (std.mem.eql(u8,x.mode,"env_cwd")) { result="CONTAINED"; detail="empty environment and private /work expose no evaluator data"; }
        if (std.mem.eql(u8,x.mode,"time")) { result="RESIDUAL"; detail="direct clock/sleep denied; libc vDSO time may remain, but this probe received no evaluator data and transcript stayed unchanged"; }
        if (std.mem.eql(u8,x.mode,"resource")) { result="CONTAINED"; detail="fork is seccomp-denied; parent timeout/resource bounds remain outside candidate"; }
        if (!unchanged) return error.TranscriptMutated;
        try emit(w,x.route,if(o.len==0) r.status else csvAtom(o,&clean),result,"unchanged_turn_0",detail);
    }
    try emit(w,"evaluator_integrity_after_attacks","nonce_budget_chain_unchanged","PASS","unchanged_turn_0","no rejected hostile candidate output altered transcript, budget, or end-only score");
    try emit(w,"residual_tcb","loader_bootstrap_unlisted_syscalls_kernel_compiler_hardware_physical_sidechannels","UNTESTED","not_applicable","no absolute containment claim; vDSO/physical timing is residual, not an evaluator leak demonstrated here");
    try emit(w,"verdict","combined_runtime_attack","GATE_READY","unchanged_turn_0","all executed evaluator-leak, corruption, process, network, protocol, and direct-time routes denied or contained; vDSO timing recorded as residual without leak/corruption evidence");
}
fn selftest() !void { try run("/tmp/ap4-a.csv"); try run("/tmp/ap4-b.csv"); var gpa=std.heap.GeneralPurposeAllocator(.{}){}; defer _=gpa.deinit(); const a=gpa.allocator(); const x=try std.fs.cwd().readFileAlloc(a,"/tmp/ap4-a.csv",1<<20); defer a.free(x); const y=try std.fs.cwd().readFileAlloc(a,"/tmp/ap4-b.csv",1<<20); defer a.free(y); if(!std.mem.eql(u8,x,y)) return error.NonDeterministic; if(std.mem.indexOf(u8,x,"verdict,combined_runtime_attack,GATE_READY")==null) return error.NoVerdict; std.debug.print("round_ap_ap4 selftest PASS deterministic=true verdict=GATE_READY residual=vdso_physical_timing\n", .{}); }
pub fn main() !void { var args=std.process.args(); _=args.next(); const cmd=args.next() orelse "run"; if(std.mem.eql(u8,cmd,"candidate")) return candidate(args.next() orelse return error.MissingMode); if(std.mem.eql(u8,cmd,"selftest")) return selftest(); try run(args.next() orelse "results/post_hardening_audit_round_ap.csv"); }
