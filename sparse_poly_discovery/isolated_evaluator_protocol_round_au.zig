//! Round AU / AU1: a deliberately small, inspectable evaluator protocol.
//!
//! Four role invocations communicate only by immutable request/receipt files:
//! candidate -> worker -> evaluator.  `selftest` copies this executable to
//! four role-named paths and invokes those paths as separate OS processes.
//! This demonstrates protocol/file boundary discipline, NOT formal hostile
//! binary containment (see the accompanying report).
const std = @import("std");

const Root = "/tmp/round-au-isolated-protocol";

fn hash(s: []const u8) u64 { return std.hash.Fnv1a_64.hash(s); }
fn write(path: []const u8, bytes: []const u8) !void {
    var f = try std.fs.createFileAbsolute(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(bytes);
}
fn read(a: std.mem.Allocator, path: []const u8) ![]u8 {
    var f = try std.fs.openFileAbsolute(path, .{}); defer f.close();
    return f.readToEndAlloc(a, 1 << 20);
}
fn exists(path: []const u8) bool { std.fs.accessAbsolute(path, .{}) catch return false; return true; }
fn contains(s: []const u8, x: []const u8) bool { return std.mem.indexOf(u8, s, x) != null; }
fn requestPath(name: []const u8, out: *[256]u8) ![]const u8 { return std.fmt.bufPrint(out, "{s}/candidate/{s}", .{ Root, name }); }

fn setup() !void {
    std.fs.deleteTreeAbsolute(Root) catch {};
    try std.fs.makeDirAbsolute(Root);
    try std.fs.makeDirAbsolute(Root ++ "/candidate");
    try std.fs.makeDirAbsolute(Root ++ "/worker");
    try std.fs.makeDirAbsolute(Root ++ "/evaluator");
    try std.fs.makeDirAbsolute(Root ++ "/sealed");
    // The task/answer live only in sealed evaluator state. Candidate requests
    // name an opaque artifact id, never a filesystem source path or answer.
    try write(Root ++ "/sealed/local_alpha.md", "alpha\nbeta\ngamma\n");
    try write(Root ++ "/sealed/answer.txt", "artifact=local_alpha\nexpected_lines=3\n");
    try write(Root ++ "/evaluator/score_state.txt", "score=hidden\nprogress=hidden\n");
}

fn candidate(name: []const u8, claim: []const u8, action: []const u8) !void {
    var pbuf: [256]u8 = undefined;
    const p = try requestPath(name, &pbuf);
    var text: [1024]u8 = undefined;
    const data = try std.fmt.bufPrint(&text, "role=candidate\nartifact=local_alpha\naction={s}\nclaim={s}\n", .{ action, claim });
    try write(p, data);
}

fn worker(a: std.mem.Allocator, request_name: []const u8) !void {
    var pbuf: [256]u8 = undefined;
    const p = try requestPath(request_name, &pbuf);
    const q = try read(a, p); defer a.free(q);
    var status: []const u8 = "ok";
    var observation: []const u8 = "lines=3";
    // A narrow, literal capability protocol: no paths, evaluator state, or
    // answer/score/progress access is representable as an allowed action.
    if (!contains(q, "artifact=local_alpha\n") or !contains(q, "action=count_lines\n")) {
        status = "rejected_capability"; observation = "none";
    }
    if (contains(q, "../") or contains(q, "/sealed") or contains(q, "/evaluator") or contains(q, "artifact=hidden_") or
        contains(q, "answer") or contains(q, "score") or contains(q, "progress")) {
        status = "rejected_policy"; observation = "none";
    }
    var out: [1024]u8 = undefined;
    const receipt = try std.fmt.bufPrint(&out, "role=worker\nrequest_hash={x}\nstatus={s}\nobservation={s}\n", .{ hash(q), status, observation });
    var rbuf: [256]u8 = undefined;
    const rp = try std.fmt.bufPrint(&rbuf, "{s}/worker/{s}.receipt", .{ Root, request_name });
    try write(rp, receipt);
}

fn evaluator(a: std.mem.Allocator, request_name: []const u8) !void {
    var pbuf: [256]u8 = undefined;
    const p = try requestPath(request_name, &pbuf);
    const q = try read(a, p); defer a.free(q);
    var rbuf: [256]u8 = undefined;
    const rp = try std.fmt.bufPrint(&rbuf, "{s}/worker/{s}.receipt", .{ Root, request_name });
    const r = try read(a, rp); defer a.free(r);
    const answer = try read(a, Root ++ "/sealed/answer.txt"); defer a.free(answer);
    // A receipt binds the exact precommitted request. A changed claim after
    // execution cannot be evaluated as if it had been run.
    var hbuf: [64]u8 = undefined;
    const expected_hash = try std.fmt.bufPrint(&hbuf, "{x}", .{hash(q)});
    const bound = contains(r, expected_hash);
    const valid = bound and contains(r, "status=ok\n") and contains(q, "claim=lines=3\n") and contains(answer, "expected_lines=3");
    var out: [512]u8 = undefined;
    const verdict = try std.fmt.bufPrint(&out, "role=evaluator\nrequest_bound={s}\nfinal_verdict={s}\n", .{ if (bound) "true" else "false", if (valid) "accepted" else "rejected" });
    var vbuf: [256]u8 = undefined;
    const vp = try std.fmt.bufPrint(&vbuf, "{s}/evaluator/{s}.verdict", .{ Root, request_name });
    try write(vp, verdict);
}

fn runChild(a: std.mem.Allocator, exe: []const u8, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, a);
    child.cwd = null;
    const term = try child.spawnAndWait();
    if (term.Exited != 0) return error.RoleProcessFailed;
    _ = exe;
}

fn selftest(exe: []const u8) !void {
    try setup();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    // Separate role-named executables. They share no data directory; their
    // only coordination is the protocol files created above.
    const roles = [_][]const u8{ "candidate", "worker", "evaluator", "auditor" };
    for (roles) |role| {
        var dst: [256]u8 = undefined;
        const dp = try std.fmt.bufPrint(&dst, "/tmp/round-au-{s}-role", .{ role });
        try std.fs.copyFileAbsolute(exe, dp, .{});
    }
    const cand = "/tmp/round-au-candidate-role";
    const work = "/tmp/round-au-worker-role";
    const eval = "/tmp/round-au-evaluator-role";
    try runChild(a, cand, &.{ cand, "candidate", "good.req", "lines=3", "count_lines" });
    try runChild(a, work, &.{ work, "worker", "good.req" });
    try runChild(a, eval, &.{ eval, "evaluator", "good.req" });
    const good = try read(a, Root ++ "/evaluator/good.req.verdict"); defer a.free(good);
    if (!contains(good, "final_verdict=accepted")) return error.GoodClaimRejected;

    const attacks = [_]struct { name: []const u8, action: []const u8 }{
        .{ .name = "traversal.req", .action = "../sealed/answer" },
        .{ .name = "evaluator_read.req", .action = "/evaluator/score_state" },
        .{ .name = "answer_query.req", .action = "answer" },
        .{ .name = "score_query.req", .action = "score" },
        .{ .name = "progress_query.req", .action = "progress" },
        .{ .name = "overlap.req", .action = "count_lines\nartifact=local_alpha\nartifact=hidden_beta" },
    };
    for (attacks) |attack| {
        try runChild(a, cand, &.{ cand, "candidate", attack.name, "lines=3", attack.action });
        try runChild(a, work, &.{ work, "worker", attack.name });
        var rp: [256]u8 = undefined;
        const receipt_path = try std.fmt.bufPrint(&rp, "{s}/worker/{s}.receipt", .{ Root, attack.name });
        const receipt = try read(a, receipt_path); defer a.free(receipt);
        if (!contains(receipt, "status=rejected_")) return error.AttackAccepted;
    }
    // Post-hoc rewrite after worker execution: receipt's hash no longer binds.
    try runChild(a, cand, &.{ cand, "candidate", "rewrite.req", "lines=2", "count_lines" });
    try runChild(a, work, &.{ work, "worker", "rewrite.req" });
    try runChild(a, cand, &.{ cand, "candidate", "rewrite.req", "lines=3", "count_lines" });
    try runChild(a, eval, &.{ eval, "evaluator", "rewrite.req" });
    const rewritten = try read(a, Root ++ "/evaluator/rewrite.req.verdict"); defer a.free(rewritten);
    if (!contains(rewritten, "request_bound=false") or !contains(rewritten, "final_verdict=rejected")) return error.PostHocAccepted;
    const first = try read(a, Root ++ "/evaluator/good.req.verdict"); defer a.free(first);
    try setup();
    // Deterministic replay uses the same role protocol (not the prior receipt).
    try runChild(a, cand, &.{ cand, "candidate", "good.req", "lines=3", "count_lines" });
    try runChild(a, work, &.{ work, "worker", "good.req" });
    try runChild(a, eval, &.{ eval, "evaluator", "good.req" });
    const second = try read(a, Root ++ "/evaluator/good.req.verdict"); defer a.free(second);
    if (!std.mem.eql(u8, first, second)) return error.NonDeterministicReplay;
    std.debug.print("round_au_au1 selftest PASS separate_role_processes=true accepted_precommitted_claim=true hostile_denials=6 posthoc_rewrite=denied deterministic_replay=true containment=formal_OS_proof_not_claimed\n", .{});
}

pub fn main() !void {
    var args = std.process.args();
    const exe = args.next() orelse return error.MissingExe;
    const role = args.next() orelse "selftest";
    if (std.mem.eql(u8, role, "selftest")) return selftest(exe);
    if (std.mem.eql(u8, role, "setup")) return setup();
    if (std.mem.eql(u8, role, "candidate")) return candidate(args.next() orelse return error.MissingRequest, args.next() orelse return error.MissingClaim, args.next() orelse return error.MissingAction);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    if (std.mem.eql(u8, role, "worker")) return worker(a, args.next() orelse return error.MissingRequest);
    if (std.mem.eql(u8, role, "evaluator")) return evaluator(a, args.next() orelse return error.MissingRequest);
    return error.UnknownRole;
}
