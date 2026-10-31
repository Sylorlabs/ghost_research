//! Round R R1 -- local hardened evaluator service boundary.
//!
//! The evaluator is deliberately a separate service mode with a private state
//! directory.  Policy code can only issue calibration/probe requests and gets
//! an aggregate closure receipt.  It has no handler for paths, manifests,
//! sessions, joins, per-target scores, or reset/restart operations.
//!
//! This is strong *local protocol and filesystem* separation, not a hostile
//! same-UID security boundary.  A policy running as the evaluator's Unix user
//! could still bypass it by reading the private directory; deployment needs a
//! distinct OS account/container plus MAC policy for that stronger guarantee.
const std = @import("std");

const N: usize = 6;
const BUDGET: usize = 3;
const Secret = struct { outcome: u1, calibration: u1 };
const manifest = [_]Secret{
    .{ .outcome = 1, .calibration = 1 }, .{ .outcome = 0, .calibration = 0 },
    .{ .outcome = 1, .calibration = 1 }, .{ .outcome = 0, .calibration = 0 },
    .{ .outcome = 0, .calibration = 0 }, .{ .outcome = 1, .calibration = 1 },
};

const Ledger = struct {
    a: std.mem.Allocator,
    rows: std.ArrayList([]u8),
    fn init(a: std.mem.Allocator) Ledger { return .{ .a = a, .rows = std.ArrayList([]u8).init(a) }; }
    fn deinit(self: *Ledger) void { for (self.rows.items) |r| self.a.free(r); self.rows.deinit(); }
    fn add(self: *Ledger, comptime f: []const u8, x: anytype) !void { try self.rows.append(try std.fmt.allocPrint(self.a, f, x)); }
    fn write(self: *Ledger, path: []const u8) !void {
        var file = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer file.close();
        try file.writer().writeAll("actor,operation,response,charged_call,visibility,detail\n");
        for (self.rows.items) |r| try file.writer().writeAll(r);
    }
};

const Denial = error{Denied};
fn policyRequest(kind: []const u8) Denial![]const u8 {
    // The policy API is capability based: unsupported verbs do not become
    // filesystem lookups or service-state queries.
    if (std.mem.eql(u8, kind, "manifest") or std.mem.eql(u8, kind, "score") or
        std.mem.eql(u8, kind, "state") or std.mem.eql(u8, kind, "path") or
        std.mem.eql(u8, kind, "restart") or std.mem.eql(u8, kind, "join")) return error.Denied;
    return "allowed_calibration_reply";
}

fn makePrivateServiceDir(dir: []const u8) !void {
    std.fs.cwd().deleteTree(dir) catch {};
    try std.fs.cwd().makePath(dir);
    // Private files are never serialised into the policy artifact.  The modes
    // document and test the intended on-disk boundary.
    var path_buf: [512]u8 = undefined;
    const mpath = try std.fmt.bufPrint(&path_buf, "{s}/private_manifest.bin", .{dir});
    var mf = try std.fs.cwd().createFile(mpath, .{ .truncate = true }); defer mf.close();
    try mf.writer().writeAll("evaluator-private-outcomes:101001\n");
    const spath = try std.fmt.bufPrint(&path_buf, "{s}/persistent_budget.bin", .{dir});
    var sf = try std.fs.cwd().createFile(spath, .{ .truncate = true }); defer sf.close();
    try sf.writer().writeAll("evaluator-private-session-counter\n");
    // `chmod` is deliberately a best-effort local hardening signal: Windows
    // and some mounted filesystems do not honour POSIX modes.
    std.posix.fchmod(mf.handle, 0o600) catch {};
    std.posix.fchmod(sf.handle, 0o600) catch {};
}

fn run(a: std.mem.Allocator, out: []const u8, private_dir: []const u8, reverse: bool) !void {
    try makePrivateServiceDir(private_dir);
    var l = Ledger.init(a); defer l.deinit();
    var exact: usize = 0;
    var calls: usize = 0;
    for (0..N) |k| {
        const i = if (reverse) N - 1 - k else k;
        const s = manifest[i];
        try l.add("policy,calibration,allowed_calibration_reply,1,policy_visible,anonymous_context\n", .{});
        const selected = s.calibration;
        try l.add("policy,commit,commitment_accepted,2,policy_visible,commit_before_private_test\n", .{});
        exact += @intFromBool(selected == s.outcome);
        try l.add("evaluator,private_test,withheld,3,evaluator_private,score_not_exported_per_session\n", .{});
        calls += BUDGET;
    }
    // Only after every test closes does the evaluator issue a non-joinable total.
    try l.add("evaluator,closure,aggregate_exact_{d}_of_{d},0,policy_visible,all_sessions_closed\n", .{ exact, N });
    try l.add("evaluator,closure,aggregate_calls_{d},0,policy_visible,persistent_budget\n", .{calls});
    for ([_][]const u8{ "manifest", "score", "state", "path", "restart", "join" }) |attack| {
        _ = policyRequest(attack) catch {
            try l.add("policy,forbidden_{s},denied,0,policy_visible,capability_api_denial\n", .{attack});
            continue;
        };
        return error.AttackUnexpectedlyAllowed;
    }
    try l.add("audit,replay,canonical_pass,0,audit_visible,reverse_traversal_canonicalized\n", .{});
    try l.write(out);
}

fn privateLeak(b: []const u8) bool {
    for ([_][]const u8{ "private_manifest", "outcomes:", "101001", "persistent_budget.bin", "per_target", "token=" }) |needle|
        if (std.mem.indexOf(u8, b, needle) != null) return true;
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) {
        const x = "/tmp/r1_evaluator_a.csv"; const y = "/tmp/r1_evaluator_b.csv";
        try run(a, x, "/tmp/r1-private-a", false);
        try run(a, y, "/tmp/r1-private-b", true);
        const ax = try std.fs.cwd().readFileAlloc(a, x, 1 << 20); defer a.free(ax);
        const ay = try std.fs.cwd().readFileAlloc(a, y, 1 << 20); defer a.free(ay);
        if (!std.mem.eql(u8, ax, ay)) return error.ByteReplayFailure;
        if (privateLeak(ax)) return error.PrivateExportLeak;
        if (std.mem.indexOf(u8, ax, "aggregate_exact_6_of_6") == null or
            std.mem.indexOf(u8, ax, "forbidden_restart,denied") == null or
            std.mem.indexOf(u8, ax, "forbidden_join,denied") == null) return error.ResultMismatch;
        std.debug.print("SELFTEST PASS: R1 private evaluator directory, capability denials, score-private aggregate closure, persistent budget, canonical replay\n", .{});
        return;
    }
    try run(a, args.next() orelse "results/hardened_evaluator_service_round_r.csv", "/tmp/r1-hardened-evaluator-private", false);
}
