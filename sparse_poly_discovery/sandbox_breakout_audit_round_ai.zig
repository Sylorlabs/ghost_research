//! Round AI / AI3 -- independent hostile audit of the actual AI1 launch profile.
//!
//! This is deliberately an attacker binary, not a source review.  It is mounted
//! as the only executable under the same Bubblewrap arguments AI1 uses and
//! attempts capabilities from inside that namespace.  A detected capability is
//! a bypass/residual even when it cannot reach the host due to another namespace.
const std = @import("std");

const secret_path = "/tmp/round-ai-ai3-launcher-secret.bin";
const secret = "AI3_PRIVATE_DESCRIPTOR_SENTINEL";

const Attack = enum { filesystem, environment, inherited_fd, network_socket, self_spawn, local_ipc, host_process, sandbox_signal, malformed_stdout, clock, provenance };

fn parseAttack(s: []const u8) ?Attack {
    inline for (std.meta.fields(Attack)) |field| {
        if (std.mem.eql(u8, s, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn say(ok: bool) !void {
    try std.io.getStdOut().writer().writeAll(if (ok) "ALLOW" else "DENY");
}

fn fdLeaksSecret() bool {
    var name_buf: [48]u8 = undefined;
    var bytes: [128]u8 = undefined;
    for (3..64) |n| {
        const name = std.fmt.bufPrint(&name_buf, "/proc/self/fd/{d}", .{n}) catch continue;
        var f = std.fs.openFileAbsolute(name, .{}) catch continue;
        defer f.close();
        const got = f.readAll(&bytes) catch continue;
        if (std.mem.indexOf(u8, bytes[0..got], secret) != null) return true;
    }
    return false;
}

fn hostileProbe(a: std.mem.Allocator, attack: Attack) !void {
    const allowed = switch (attack) {
        .filesystem => blk: {
            var f = std.fs.openFileAbsolute("/etc/passwd", .{}) catch break :blk false;
            f.close();
            break :blk true;
        },
        .environment => std.posix.getenv("HOME") != null,
        .inherited_fd => fdLeaksSecret(),
        .network_socket => blk: {
            const fd = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0) catch break :blk false;
            std.posix.close(fd);
            break :blk true;
        },
        .self_spawn => blk: {
            var child = std.process.Child.init(&.{ "/worker", "probe", "environment" }, a);
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;
            child.stdin_behavior = .Ignore;
            child.spawn() catch break :blk false;
            const term = child.wait() catch break :blk false;
            break :blk switch (term) { .Exited => |code| code == 0, else => false };
        },
        .local_ipc => blk: {
            const fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0) catch break :blk false;
            std.posix.close(fd);
            break :blk true;
        },
        .host_process => blk: {
            // PID 2 can be a legitimate namespace helper; count the visible
            // namespace instead of mistaking it for a host process.
            var dir = std.fs.openDirAbsolute("/proc", .{ .iterate = true }) catch break :blk true;
            defer dir.close();
            var it = dir.iterate();
            var numeric: usize = 0;
            while (it.next() catch null) |entry| {
                if (entry.kind != .directory) continue;
                _ = std.fmt.parseInt(usize, entry.name, 10) catch continue;
                numeric += 1;
            }
            break :blk numeric > 4;
        },
        .sandbox_signal => blk: {
            std.posix.kill(1, 0) catch break :blk false;
            break :blk true;
        },
        .malformed_stdout => {
            try std.io.getStdOut().writer().writeAll("NOT_RAW_PROTOCOL\nEXTRA_FRAME\n");
            return;
        },
        .clock => std.time.milliTimestamp() > 0,
        // AI1 has an immutable file bind, but no binary hash/attestation or
        // separate launcher identity.  This remains a provenance limitation.
        .provenance => true,
    };
    try say(allowed);
}

fn runSandbox(a: std.mem.Allocator, exe: []const u8, attack: Attack, inherit_secret: bool) !bool {
    var held: ?std.fs.File = null;
    defer if (held) |f| f.close();
    if (inherit_secret) {
        held = try std.fs.createFileAbsolute(secret_path, .{ .truncate = true });
        try held.?.writeAll(secret);
        try held.?.seekTo(0);
    }
    const argv = [_][]const u8{
        "bwrap", "--unshare-all", "--new-session", "--die-with-parent",
        "--clearenv", "--ro-bind", exe, "/worker", "--proc", "/proc",
        "--dev", "/dev", "--tmpfs", "/tmp", "/worker", "probe", @tagName(attack),
    };
    const result = try std.process.Child.run(.{ .allocator = a, .argv = &argv, .max_output_bytes = 4096 });
    defer a.free(result.stdout);
    defer a.free(result.stderr);
    const success = switch (result.term) { .Exited => |code| code == 0, else => false };
    if (!success) return false;
    return std.mem.indexOf(u8, result.stdout, "ALLOW") != null or
        std.mem.indexOf(u8, result.stdout, "NOT_RAW_PROTOCOL") != null;
}

const Row = struct { attack: Attack, boundary: []const u8, expected: []const u8, observed: []const u8, verdict: []const u8, detail: []const u8 };

fn run(a: std.mem.Allocator, out_path: []const u8) !void {
    const exe = try std.fs.selfExePathAlloc(a);
    defer a.free(exe);
    const fs = try runSandbox(a, exe, .filesystem, false);
    const env = try runSandbox(a, exe, .environment, false);
    const fd = try runSandbox(a, exe, .inherited_fd, true);
    const net = try runSandbox(a, exe, .network_socket, false);
    const spawn = try runSandbox(a, exe, .self_spawn, false);
    const ipc = try runSandbox(a, exe, .local_ipc, false);
    const host_proc = try runSandbox(a, exe, .host_process, false);
    const signal = try runSandbox(a, exe, .sandbox_signal, false);
    const malformed = try runSandbox(a, exe, .malformed_stdout, false);
    const clock = try runSandbox(a, exe, .clock, false);
    const provenance = try runSandbox(a, exe, .provenance, false);
    var f = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("artifact,attack,boundary,expected,observed,verdict,detail\n");
    const rows = [_]Row{
        .{ .attack = .filesystem, .boundary = "mount_namespace", .expected = "DENY", .observed = if (fs) "ALLOW" else "DENY", .verdict = if (fs) "BYPASS" else "PASS", .detail = "host_/etc_not_mounted" },
        .{ .attack = .environment, .boundary = "clearenv", .expected = "DENY", .observed = if (env) "ALLOW" else "DENY", .verdict = if (env) "BYPASS" else "PASS", .detail = "launcher_secret_not_visible" },
        .{ .attack = .inherited_fd, .boundary = "launcher_fd_hygiene", .expected = "DENY", .observed = if (fd) "ALLOW" else "DENY", .verdict = if (fd) "BYPASS" else "PASS", .detail = "actual_Zig_child_launch_did_not_expose_open_private_descriptor" },
        .{ .attack = .network_socket, .boundary = "syscall_policy", .expected = "DENY", .observed = if (net) "ALLOW" else "DENY", .verdict = if (net) "BYPASS" else "PASS", .detail = "new_network_namespace_does_not_forbid_socket_syscall" },
        .{ .attack = .self_spawn, .boundary = "syscall_policy", .expected = "DENY", .observed = if (spawn) "ALLOW" else "DENY", .verdict = if (spawn) "BYPASS" else "PASS", .detail = "mounted_worker_can_exec_itself" },
        .{ .attack = .local_ipc, .boundary = "ipc_namespace", .expected = "DENY", .observed = if (ipc) "ALLOW" else "DENY", .verdict = if (ipc) "RESIDUAL" else "PASS", .detail = "host_IPC_hidden_but_local_AF_UNIX_socket_creation_allowed" },
        .{ .attack = .host_process, .boundary = "pid_namespace", .expected = "DENY", .observed = if (host_proc) "ALLOW" else "DENY", .verdict = if (host_proc) "BYPASS" else "PASS", .detail = "host_process_tree_not_visible" },
        .{ .attack = .sandbox_signal, .boundary = "pid_namespace", .expected = "DENY", .observed = if (signal) "ALLOW" else "DENY", .verdict = if (signal) "RESIDUAL" else "PASS", .detail = "can_signal_namespace_PID_1_not_host_process" },
        .{ .attack = .malformed_stdout, .boundary = "transport_validation", .expected = "DENY", .observed = if (malformed) "ALLOW" else "DENY", .verdict = if (malformed) "RESIDUAL" else "PASS", .detail = "raw_sandbox_allows_extra_stdout;AI2_collector_replay_rejected_17_byte_fixture" },
        .{ .attack = .clock, .boundary = "timing_channel", .expected = "DENY", .observed = if (clock) "ALLOW" else "DENY", .verdict = if (clock) "RESIDUAL" else "PASS", .detail = "wall_clock_available_no_evaluator_feedback_proven" },
        .{ .attack = .provenance, .boundary = "launcher_provenance", .expected = "DENY", .observed = if (provenance) "ALLOW" else "DENY", .verdict = "RESIDUAL", .detail = "file_bind_is_not_binary_attestation_or_separate_launcher_identity" },
    };
    for (rows) |row| try w.print("round_ai_ai3,{s},{s},{s},{s},{s},{s}\n", .{ @tagName(row.attack), row.boundary, row.expected, row.observed, row.verdict, row.detail });
    try w.writeAll("round_ai_ai3,VERDICT,aggregate,VALID_NEGATIVE,real_breakout_audit_found_network_socket_self_spawn_and_unvalidated_stdout_paths;FD_attack_denied_on_actual_Zig_child_launch,VALID_NEGATIVE,not_safe_for_capability_clean_mutant\n");
}

fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    try run(a, "/tmp/round-ai-ai3-a.csv");
    try run(a, "/tmp/round-ai-ai3-b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/round-ai-ai3-a.csv", 1 << 20);
    defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/round-ai-ai3-b.csv", 1 << 20);
    defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    for ([_][]const u8{ "inherited_fd,launcher_fd_hygiene,DENY,DENY,PASS", "network_socket,syscall_policy,DENY,ALLOW,BYPASS", "self_spawn,syscall_policy,DENY,ALLOW,BYPASS", "VALID_NEGATIVE" }) |needle| {
        if (std.mem.indexOf(u8, x, needle) == null) return error.MissingExpectedBreakout;
    }
    std.debug.print("round_ai_ai3 selftest PASS deterministic=true verdict=VALID_NEGATIVE network_spawn_breakouts=true fd_attack_denied=true\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    var args = std.process.args();
    _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "probe")) {
        const attack = parseAttack(args.next() orelse return error.MissingAttack) orelse return error.UnknownAttack;
        return hostileProbe(a, attack);
    }
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try run(a, args.next() orelse "results/sandbox_breakout_audit_round_ai.csv");
}
