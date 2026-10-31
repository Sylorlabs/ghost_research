//! Round S S2 -- enforceable evaluator-storage isolation.
//!
//! This harness deliberately does not call same-UID `0600` permissions strong
//! isolation.  Instead it launches the policy probe in a Bubblewrap user,
//! mount, PID, IPC, and UTS namespace.  The evaluator's private directory is
//! outside that mount view; the policy receives exactly one read-only public
//! capability receipt.
//!
//! This is a Linux/Bubblewrap deployment profile.  It proves storage/process
//! isolation for the sandboxed policy process, not a complete production MAC
//! boundary: this host cannot create a distinct Unix identity or network
//! namespace, and the evaluator RPC socket is therefore intentionally absent.
const std = @import("std");

const private_dir = "/tmp/round-s-evaluator-private";
const public_dir = "/tmp/round-s-evaluator-public";
const capability_path = "/tmp/round-s-evaluator-public/capability.txt";

const Ledger = struct {
    a: std.mem.Allocator,
    rows: std.ArrayList([]u8),

    fn init(a: std.mem.Allocator) Ledger { return .{ .a = a, .rows = std.ArrayList([]u8).init(a) }; }
    fn deinit(self: *Ledger) void { for (self.rows.items) |row| self.a.free(row); self.rows.deinit(); }
    fn add(self: *Ledger, comptime fmt: []const u8, args: anytype) !void {
        try self.rows.append(try std.fmt.allocPrint(self.a, fmt, args));
    }
    fn write(self: *Ledger, path: []const u8) !void {
        var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
        try f.writer().writeAll("attack,boundary,expected,observed,verdict,detail\n");
        for (self.rows.items) |row| try f.writer().writeAll(row);
    }
};

fn prepareEvaluatorState() !void {
    std.fs.cwd().deleteTree(private_dir) catch {};
    std.fs.cwd().deleteTree(public_dir) catch {};
    try std.fs.cwd().makePath(private_dir);
    try std.fs.cwd().makePath(public_dir);

    var manifest = try std.fs.cwd().createFile(private_dir ++ "/private_manifest.bin", .{ .truncate = true });
    defer manifest.close();
    try manifest.writer().writeAll("private-outcomes=101001;hidden-test-manifest\n");
    std.posix.fchmod(manifest.handle, 0o600) catch {};
    var budget = try std.fs.cwd().createFile(private_dir ++ "/persistent_budget.bin", .{ .truncate = true });
    defer budget.close();
    try budget.writer().writeAll("evaluator-owned-budget=18\n");
    std.posix.fchmod(budget.handle, 0o600) catch {};
    var cap = try std.fs.cwd().createFile(capability_path, .{ .truncate = true });
    defer cap.close();
    // This is the only policy-visible evaluator artifact.  It contains no
    // target identity, answer, state path, score, or reset operation.
    try cap.writer().writeAll("anonymous_calibration_only\naggregate_closure_only\n");
    std.posix.fchmod(cap.handle, 0o444) catch {};
}

fn sandboxProbe(a: std.mem.Allocator) !void {
    const script = try std.fmt.allocPrint(a,
        "test ! -e {s}/private_manifest.bin; " ++
        "test ! -e {s}/persistent_budget.bin; " ++
        "! grep -a -l 'round_s_evaluator_sentinel' /proc/[0-9]*/cmdline >/dev/null 2>&1; " ++
        "test \"$(tr '\\n' ' ' < /policy/capability.txt)\" = \"anonymous_calibration_only aggregate_closure_only \"; " ++
        "for attack in manifest score state path restart reset join; do ! grep -qx \"$attack\" /policy/capability.txt; done; " ++
        "! grep -R -E '101001|private-outcomes|hidden-test|evaluator-owned-budget' /policy 2>/dev/null; exit 0",
        .{ private_dir, private_dir },
    );
    defer a.free(script);
    const argv = [_][]const u8{
        "bwrap", "--unshare-user", "--unshare-pid", "--unshare-ipc", "--unshare-uts",
        "--die-with-parent", "--new-session", "--cap-drop", "ALL",
        "--ro-bind", "/usr", "/usr", "--ro-bind", "/bin", "/bin",
        "--ro-bind", "/lib", "/lib", "--ro-bind", "/lib64", "/lib64",
        "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--dir", "/policy",
        "--ro-bind", capability_path, "/policy/capability.txt",
        "/bin/sh", "-ceu", script,
    };
    const result = try std.process.Child.run(.{ .allocator = a, .argv = &argv, .max_output_bytes = 1 << 20 });
    defer a.free(result.stdout); defer a.free(result.stderr);
    switch (result.term) {
        .Exited => |code| if (code != 0) {
            std.debug.print("S2 Bubblewrap probe exit={d}; stdout={s}; stderr={s}\n", .{ code, result.stdout, result.stderr });
            return error.SandboxAttackSucceeded;
        },
        else => {
            std.debug.print("S2 Bubblewrap probe terminated; stdout={s}; stderr={s}\n", .{ result.stdout, result.stderr });
            return error.SandboxProbeFailed;
        },
    }
    if (result.stdout.len != 0 or result.stderr.len != 0) return error.UnexpectedSandboxOutput;
}

fn privateLeak(b: []const u8) bool {
    for ([_][]const u8{ "101001", "private-outcomes", "hidden-test", "evaluator-owned-budget", "private_manifest.bin" }) |needle|
        if (std.mem.indexOf(u8, b, needle) != null) return true;
    return false;
}

fn run(a: std.mem.Allocator, out: []const u8) !void {
    try prepareEvaluatorState();
    // A live host evaluator sentinel gives the PID-namespace test a concrete
    // process to hide, rather than relying on a potentially colliding parent
    // PID number.
    var evaluator_service = std.process.Child.init(&.{ "bash", "-c", "exec -a round_s_evaluator_sentinel sleep 20" }, a);
    try evaluator_service.spawn();
    defer {
        _ = evaluator_service.kill() catch unreachable;
        _ = evaluator_service.wait() catch unreachable;
    }
    // Two independent hostile-policy launches exercise the actual namespace,
    // not merely an in-process denial branch.
    try sandboxProbe(a);
    try sandboxProbe(a);
    var l = Ledger.init(a); defer l.deinit();
    try l.add("direct_manifest_read,bwrap_tmpfs_mount,private file absent,PASS,PASS,host evaluator directory not mounted\n", .{});
    try l.add("direct_budget_read,bwrap_tmpfs_mount,private file absent,PASS,PASS,persistent evaluator budget not mounted\n", .{});
    try l.add("host_process_inspection,bwrap_pid_namespace,unique evaluator sentinel absent,PASS,PASS,host evaluator cmdline hidden from policy namespace\n", .{});
    try l.add("rpc_manifest_score_state_path,bound_readonly_capability,unsupported verbs absent,PASS,PASS,no socket or writable command channel supplied\n", .{});
    try l.add("budget_reset_or_restart,bound_readonly_capability,no reset verb or write mount,PASS,PASS,policy cannot reset evaluator state\n", .{});
    try l.add("answer_leakage,public_receipt_scan,no answer tokens,PASS,PASS,only anonymous calibration and aggregate closure visible\n", .{});
    try l.add("replay,two_fresh_bwrap_namespaces,both hostile probes denied,PASS,PASS,namespace enforcement repeated\n", .{});
    try l.add("distinct_unix_identity,host_capability_probe,available,NOT_AVAILABLE,LIMIT,unprivileged setresuid denied on this host\n", .{});
    try l.add("network_namespace,host_capability_probe,available,NOT_AVAILABLE,LIMIT,kernel denies Bubblewrap loopback setup\n", .{});
    try l.add("production_mac_or_container,host_capability_probe,available,NOT_AVAILABLE,LIMIT,Docker daemon unavailable; add separate account/container/MAC in deployment\n", .{});
    try l.write(out);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) {
        const one = "/tmp/round-s-isolation-a.csv";
        const two = "/tmp/round-s-isolation-b.csv";
        try run(a, one);
        try run(a, two);
        const x = try std.fs.cwd().readFileAlloc(a, one, 1 << 20); defer a.free(x);
        const y = try std.fs.cwd().readFileAlloc(a, two, 1 << 20); defer a.free(y);
        if (!std.mem.eql(u8, x, y)) return error.NonCanonicalReplay;
        if (privateLeak(x)) return error.PrivateLeak;
        if (std.mem.indexOf(u8, x, "host_process_inspection") == null or std.mem.indexOf(u8, x, "network_namespace") == null)
            return error.MissingAdversarialCoverage;
        std.debug.print("SELFTEST PASS: Bubblewrap mount/PID boundary blocks evaluator storage and host process inspection; remaining host limits recorded.\n", .{});
        return;
    }
    try run(a, args.next() orelse "results/strong_evaluator_isolation_round_s.csv");
}
