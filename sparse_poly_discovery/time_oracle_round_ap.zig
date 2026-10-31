//! Round AP / AP3: direct-time reduction plus a fixed logical-turn protocol.
//!
//! This is deliberately a narrow capability measurement.  The candidate enters
//! a real Bubblewrap namespace and installs a libseccomp rule set before its
//! probes or logical-turn loop.  It demonstrates direct *syscall* denial, but
//! records the important limitation: vDSO user-space clock reads and physical
//! CPU/cache/scheduler side channels are not thereby eliminated.  Further,
//! candidate-installed seccomp is not a parent-enforced policy against a
//! malicious replacement candidate; AP1 must move the filter into the launcher.
const std = @import("std");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("seccomp.h");
    @cInclude("sys/syscall.h");
    @cInclude("sys/time.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
});

const MaxFrame = 256;
const Turns = 4;

fn installTimeFilter() !void {
    const ctx = c.seccomp_init(c.SCMP_ACT_ALLOW) orelse return error.SeccompInit;
    defer c.seccomp_release(ctx);
    const deny: u32 = c.SCMP_ACT_ERRNO(c.EPERM);
    // libseccomp accepts the native syscall number.  These constants are the
    // platform's active ABI values supplied by <sys/syscall.h>.
    const calls = [_]c_int{ c.SYS_clock_gettime, c.SYS_gettimeofday, c.SYS_time, c.SYS_nanosleep, c.SYS_clock_nanosleep };
    for (calls) |call| if (c.seccomp_rule_add(ctx, deny, call, 0) != 0) return error.SeccompRule;
    // x86_64 has no separate time64 syscalls; adding them only when supplied
    // would be architecture-specific.  This executable records its platform.
    if (c.seccomp_load(ctx) != 0) return error.SeccompLoad;
}

fn denied(rc: c_long) bool { return rc == -1; }

fn writeProbe() !void {
    try installTimeFilter();
    var ts: c.struct_timespec = undefined;
    var tv: c.struct_timeval = undefined;
    const direct_clock = c.syscall(c.SYS_clock_gettime, c.CLOCK_MONOTONIC, &ts);
    const direct_gettimeofday = c.syscall(c.SYS_gettimeofday, &tv, @as(?*anyopaque, null));
    const direct_time = c.syscall(c.SYS_time, @as(?*anyopaque, null));
    const direct_sleep = c.syscall(c.SYS_nanosleep, @as(?*anyopaque, null), @as(?*anyopaque, null));
    // libc can serve time from vDSO without issuing a syscall.  This is an
    // observation of the actual process, not an assumed implementation detail.
    const libc_clock = c.clock_gettime(c.CLOCK_MONOTONIC, &ts);
    const libc_gettimeofday = c.gettimeofday(&tv, null);
    const libc_time = c.time(null);
    const libc_sleep = c.nanosleep(null, null);
    try std.io.getStdOut().writer().print(
        "PROBE:direct_clock={s}:direct_gettimeofday={s}:direct_time={s}:direct_nanosleep={s}:libc_clock={s}:libc_gettimeofday={s}:libc_time={s}:libc_nanosleep={s}\n",
        .{ if (denied(direct_clock)) "DENY" else "ALLOW", if (denied(direct_gettimeofday)) "DENY" else "ALLOW", if (denied(direct_time)) "DENY" else "ALLOW", if (denied(direct_sleep)) "DENY" else "ALLOW", if (libc_clock == -1) "DENY" else "ALLOW", if (libc_gettimeofday == -1) "DENY" else "ALLOW", if (libc_time == -1) "DENY" else "ALLOW", if (libc_sleep == -1) "DENY" else "ALLOW" },
    );
}

fn logicalCandidate() !void {
    try installTimeFilter();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    const input = try std.io.getStdIn().readToEndAlloc(a, MaxFrame); defer a.free(input);
    // The only accepted message is an opaque raw observation.  It has no wall
    // time, progress, reward, score, target, or evaluator-response-pacing field.
    const expected = "OBS:opaque:a\nOBS:opaque:b\nOBS:opaque:c\nOBS:opaque:d\n";
    if (!std.mem.eql(u8, input, expected)) return error.BadLogicalTranscript;
    try std.io.getStdOut().writer().writeAll("ACT:0:1\nACT:1:0\nACT:2:1\nACT:3:0\n");
}

fn candidate(mode: []const u8) !void {
    if (std.mem.eql(u8, mode, "probe")) return writeProbe();
    if (std.mem.eql(u8, mode, "logical")) return logicalCandidate();
    return error.UnknownMode;
}

fn launch(a: std.mem.Allocator, exe: []const u8, mode: []const u8) ![]u8 {
    const input = if (std.mem.eql(u8, mode, "logical")) "OBS:opaque:a\nOBS:opaque:b\nOBS:opaque:c\nOBS:opaque:d\n" else "";
    const script = try std.fmt.allocPrint(a,
        "exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-; printf '{s}' | exec prlimit --as=67108864 --cpu=1 -- bwrap --unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-net --die-with-parent --new-session --cap-drop ALL --clearenv --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind {s} /candidate --proc /proc --dev /dev --tmpfs /tmp --tmpfs /work --chdir /work /candidate candidate {s}",
        .{ input, exe, mode },
    );
    defer a.free(script);
    const r = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "bash", "-ceu", script }, .max_output_bytes = 4096 });
    defer a.free(r.stderr);
    switch (r.term) { .Exited => |code| if (code != 0) return error.CandidateFailure, else => return error.CandidateFailure }
    return r.stdout;
}

fn contains(bytes: []const u8, needle: []const u8) bool { return std.mem.indexOf(u8, bytes, needle) != null; }

fn run(path: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const exe = try std.fs.selfExePathAlloc(a); defer a.free(exe);
    const probe = try launch(a, exe, "probe"); defer a.free(probe);
    const first = try launch(a, exe, "logical"); defer a.free(first);
    const second = try launch(a, exe, "logical"); defer a.free(second);
    const expected_actions = "ACT:0:1\nACT:1:0\nACT:2:1\nACT:3:0\n";
    if (!std.mem.eql(u8, first, expected_actions) or !std.mem.eql(u8, first, second)) return error.LogicalReplayFailure;
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close(); const w = file.writer();
    try w.writeAll("artifact,probe,observed,verdict,detail\n");
    try w.print("round_ap_ap3,direct_clock_gettime,{s},{s},actual SYS_clock_gettime after enabled libseccomp\n", .{ if (contains(probe, "direct_clock=DENY")) "DENY" else "ALLOW", if (contains(probe, "direct_clock=DENY")) "PASS" else "FAIL" });
    try w.print("round_ap_ap3,direct_gettimeofday_time_nanosleep,{s},{s},actual direct syscall probes after enabled libseccomp\n", .{ if (contains(probe, "direct_gettimeofday=DENY:direct_time=DENY:direct_nanosleep=DENY")) "DENY" else "ALLOW", if (contains(probe, "direct_gettimeofday=DENY:direct_time=DENY:direct_nanosleep=DENY")) "PASS" else "FAIL" });
    try w.print("round_ap_ap3,libc_vdso_clock_and_gettimeofday,{s},EXPOSED,libc APIs can resolve through vDSO without a kernel syscall; seccomp is not a physical timing cure\n", .{if (contains(probe, "libc_clock=ALLOW") or contains(probe, "libc_gettimeofday=ALLOW")) "ALLOW" else "DENY"});
    try w.print("round_ap_ap3,libc_nanosleep,{s},{s},sleep requires a blocked kernel syscall in this executed profile\n", .{ if (contains(probe, "libc_nanosleep=DENY")) "DENY" else "ALLOW", if (contains(probe, "libc_nanosleep=DENY")) "PASS" else "FAIL" });
    try w.writeAll("round_ap_ap3,logical_turn_observation,opaque_fixed_4_turns,PASS,no elapsed progress score target or response-pacing field supplied\n");
    try w.writeAll("round_ap_ap3,timing_coded_output,not_accepted_as_action,PASS,strict raw action grammar accepts only deterministic ACT turn value frames\n");
    try w.writeAll("round_ap_ap3,logical_turn_replay,byte_identical_4_actions,PASS,two fresh restricted runs produced same raw action transcript\n");
    try w.writeAll("round_ap_ap3,physical_side_channels,CPU_cache_scheduler_and_vDSO,RESIDUAL,direct syscall denial does not eliminate non-syscall clocks or physical scheduling observations\n");
    try w.writeAll("round_ap_ap3,launcher_enforcement,candidate_installs_filter,INCONCLUSIVE,filter is enabled and measured but this source-level candidate installation is not yet parent-enforced against a hostile replacement\n");
    try w.writeAll("round_ap_ap3,verdict,time_oracle_reduction,INCONCLUSIVE,direct syscall and sleep APIs denied plus logical protocol deterministic; vDSO and physical timing residuals prevent a GATE_READY containment claim\n");
}

fn selftest() !void {
    try run("/tmp/ap3-a.csv"); try run("/tmp/ap3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ap3-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ap3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    if (!contains(x, "verdict,time_oracle_reduction,INCONCLUSIVE")) return error.MissingVerdict;
    std.debug.print("round_ap_ap3 selftest PASS direct_syscalls=denied logical_turns=deterministic verdict=INCONCLUSIVE\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "candidate")) return candidate(args.next() orelse return error.MissingMode);
    if (std.mem.eql(u8, cmd, "selftest")) return selftest();
    try run(args.next() orelse "results/time_oracle_round_ap.csv");
}
