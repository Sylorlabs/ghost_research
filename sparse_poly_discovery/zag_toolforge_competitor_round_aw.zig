//! AW3: integration-ready native-Zag tool-forge competitor.
//!
//! This is deliberately *not* a scored intelligence result.  It is the
//! candidate-side runner for a future evaluator-owned corpus.  The manifest
//! has artifact paths and opaque failure receipts but no expected outputs,
//! scores, answer labels, or task verdicts.  It emits precommits and raw worker
//! receipts only; a separate evaluator must score its sealed claims.
const std = @import("std");

const policies = [_][]const u8{ "candidate", "fixed", "broad", "random", "replay", "no_memory", "no_repair" };
const zag_compiler_default = "/home/micah/Desktop/Sylorlabs/zag/zag-poc/znc";

const Task = struct { id: []const u8, train: []const u8, heldout: []const u8, opaque_receipt: []const u8 };
const TaskSet = struct {
    tasks: []Task,
    backing: []u8,
    fn deinit(self: TaskSet, a: std.mem.Allocator) void { a.free(self.tasks); a.free(self.backing); }
};

const raw_source =
    \\fn token_at(b: []u8, i: i32) i32 {
    \\    if (i + 7 > b.len) { return 0; }
    \\    if (b[i] == 112 && b[i + 1] == 117 && b[i + 2] == 98 && b[i + 3] == 32 && b[i + 4] == 102 && b[i + 5] == 110 && b[i + 6] == 32) { return 1; }
    \\    return 0;
    \\}
    \\fn main() i32 { if (_zag_argc() != 2) { return 2; } let b: []u8 = _zag_read_file(_zag_arg(1)); let i: i32 = 0; let n: i32 = 0; while (i < b.len) { if (token_at(b, i) == 1) { n = n + 1; } i = i + 1; } _zag_println(_zag_i64_to_str(n)); return 0; }
;
const comment_source =
    \\fn token_at(b: []u8, i: i32) i32 {
    \\    if (i + 7 > b.len) { return 0; }
    \\    if (b[i] == 112 && b[i + 1] == 117 && b[i + 2] == 98 && b[i + 3] == 32 && b[i + 4] == 102 && b[i + 5] == 110 && b[i + 6] == 32) { return 1; }
    \\    return 0;
    \\}
    \\fn main() i32 { if (_zag_argc() != 2) { return 2; } let b: []u8 = _zag_read_file(_zag_arg(1)); let i: i32 = 0; let n: i32 = 0; let comment: i32 = 0; while (i < b.len) { if (i + 1 < b.len && b[i] == 47 && b[i + 1] == 47) { comment = 1; } if (b[i] == 10) { comment = 0; } if (comment == 0 && token_at(b, i) == 1) { n = n + 1; } i = i + 1; } _zag_println(_zag_i64_to_str(n)); return 0; }
;

fn hash(s: []const u8) u64 { return std.hash.Fnv1a_64.hash(s); }
fn hasForbidden(s: []const u8) bool {
    const bad = [_][]const u8{ "answer", "expected", "score", "target", "correct", "output=" };
    for (bad) |x| if (std.ascii.indexOfIgnoreCase(s, x) != null) return true;
    return false;
}
fn readTasks(a: std.mem.Allocator, path: []const u8) !TaskSet {
    const bytes = try std.fs.cwd().readFileAlloc(a, path, 1 << 20);
    var tasks = std.ArrayList(Task).init(a);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or std.mem.startsWith(u8, line, "#")) continue;
        var f = std.mem.splitScalar(u8, line, ',');
        const id = f.next() orelse return error.BadManifest;
        const train = f.next() orelse return error.BadManifest;
        const held = f.next() orelse return error.BadManifest;
        const receipt = f.next() orelse return error.BadManifest;
        if (f.next() != null or id.len == 0 or train.len == 0 or held.len == 0 or receipt.len == 0) return error.BadManifest;
        // This is an answer-channel gate, not an attempt to understand prose.
        if (hasForbidden(receipt)) return error.AnswerShapedReceipt;
        try tasks.append(.{ .id = id, .train = train, .heldout = held, .opaque_receipt = receipt });
    }
    if (tasks.items.len == 0) return error.EmptyManifest;
    return .{ .tasks = try tasks.toOwnedSlice(), .backing = bytes };
}
fn sourceFor(policy: []const u8, action: usize, receipt: []const u8) []const u8 {
    // Candidate changes tool only after an opaque mismatch receipt.  The
    // method is intentionally explicit and therefore a baseline-equivalent
    // supplied rule, not claimed invention.
    if (std.mem.eql(u8, policy, "candidate") and action > 0 and std.mem.indexOf(u8, receipt, "mismatch") != null) return comment_source;
    if (std.mem.eql(u8, policy, "fixed") or std.mem.eql(u8, policy, "broad")) return comment_source;
    if (std.mem.eql(u8, policy, "random") and action % 2 == 1) return comment_source;
    if (std.mem.eql(u8, policy, "replay") and action == 2) return comment_source;
    if (std.mem.eql(u8, policy, "no_memory") and action == 2) return comment_source;
    return raw_source;
}
fn writeFile(path: []const u8, text: []const u8) !void { var f = try std.fs.createFileAbsolute(path, .{ .truncate = true }); defer f.close(); try f.writeAll(text); }
fn compiler(a: std.mem.Allocator) []const u8 { return std.process.getEnvVarOwned(a, "ZAG_COMPILER") catch zag_compiler_default; }
fn compile(a: std.mem.Allocator, znc: []const u8, src: []const u8, bin: []const u8) !void {
    const r = try std.process.Child.run(.{ .allocator = a, .argv = &.{ znc, src, "-o", bin, "--no-zagd", "--no-analyze" }, .max_output_bytes = 4096 });
    defer a.free(r.stdout); defer a.free(r.stderr);
    if (r.term != .Exited or r.term.Exited != 0) return error.ZagCompileFailed;
}
fn worker(a: std.mem.Allocator, bin: []const u8, artifact: []const u8) ![]u8 {
    // No evaluator directory, network, writable corpus, or inherited env.
    const r = try std.process.Child.run(.{ .allocator = a, .argv = &.{ "bwrap", "--unshare-all", "--die-with-parent", "--new-session", "--clearenv", "--ro-bind", "/usr", "/usr", "--ro-bind", "/lib", "/lib", "--ro-bind", "/lib64", "/lib64", "--proc", "/proc", "--dev", "/dev", "--ro-bind", bin, "/tool", "--ro-bind", artifact, "/artifact", "--tmpfs", "/tmp", "/tool", "/artifact" }, .max_output_bytes = 4096 });
    defer a.free(r.stderr);
    if (r.term != .Exited or r.term.Exited != 0) { a.free(r.stdout); return error.WorkerRejected; }
    return r.stdout;
}
fn cleanOutput(s: []const u8) bool { return s.len > 0 and s.len < 128 and std.mem.indexOfScalar(u8, s, ',') == null and std.mem.indexOfScalar(u8, s, '\n') == s.len - 1; }
fn emit(a: std.mem.Allocator, manifest: []const u8, out_path: []const u8) !void {
    const task_set = try readTasks(a, manifest);
    defer task_set.deinit(a);
    const tasks = task_set.tasks;
    const znc = compiler(a);
    const pid = std.os.linux.getpid();
    var root_buf: [128]u8 = undefined;
    const root = try std.fmt.bufPrint(&root_buf, "/tmp/aw3-zag-{d}", .{pid});
    std.fs.makeDirAbsolute(root) catch |e| if (e != error.PathAlreadyExists) return e;
    defer std.fs.deleteTreeAbsolute(root) catch {};
    var f = if (std.fs.path.isAbsolute(out_path)) try std.fs.createFileAbsolute(out_path, .{ .truncate = true }) else try std.fs.cwd().createFile(out_path, .{ .truncate = true }); defer f.close(); const w = f.writer();
    try w.writeAll("kind,policy,task,action,tool_hash,opaque_receipt_hash,artifact_hash,precommit_hash,worker_output_hash,worker_output,scored,notes\n");
    for (policies) |policy| for (tasks) |task| {
        const art_bytes = try std.fs.cwd().readFileAlloc(a, task.train, 1 << 24); defer a.free(art_bytes);
        const held_bytes = try std.fs.cwd().readFileAlloc(a, task.heldout, 1 << 24); defer a.free(held_bytes);
        const ah = hash(art_bytes); const hh = hash(held_bytes); const rh = hash(task.opaque_receipt);
        // AU3 discipline: exactly two build units and three worker actions for
        // every policy/task, irrespective of outcome.
        for (0..2) |build_index| {
            var src_buf: [160]u8 = undefined; var bin_buf: [160]u8 = undefined;
            const src = try std.fmt.bufPrint(&src_buf, "{s}/{s}-{s}-{d}.zag", .{ root, task.id, policy, build_index });
            const bin = try std.fmt.bufPrint(&bin_buf, "{s}/{s}-{s}-{d}", .{ root, task.id, policy, build_index });
            try writeFile(src, sourceFor(policy, build_index, task.opaque_receipt)); try compile(a, znc, src, bin);
        }
        for (0..3) |action| {
            const source = sourceFor(policy, action, task.opaque_receipt);
            const build_index: usize = if (action == 0) 0 else 1;
            var bin_buf: [160]u8 = undefined; const bin = try std.fmt.bufPrint(&bin_buf, "{s}/{s}-{s}-{d}", .{ root, task.id, policy, build_index });
            const artifact = if (action == 2) task.heldout else task.train;
            const artifact_hash = if (action == 2) hh else ah;
            var pre: [256]u8 = undefined; const preimage = try std.fmt.bufPrint(&pre, "{s}|{s}|{d}|{x}|{x}", .{ policy, task.id, action, hash(source), artifact_hash });
            const output = try worker(a, bin, artifact); defer a.free(output);
            if (!cleanOutput(output)) return error.BadWorkerReceipt;
            try w.print("receipt,{s},{s},{d},{x},{x},{x},{x},{x},{x},false,precommitted_before_worker; evaluator_score_absent\n", .{ policy, task.id, action, hash(source), rh, artifact_hash, hash(preimage), hash(output), hash(output) });
        }
        try w.print("frontier,{s},{s},0,-,{x},-,-,-,-,false,hypotheses=raw_token_match|comment_contamination|unreached_alternative; no answer or claim verdict supplied\n", .{ policy, task.id, rh });
    };
    try w.writeAll("summary,all,all,0,-,-,-,-,-,-,false,UNSCORED_INTEGRATION_READY; 7 policies x 2 builds x 3 worker actions per task; external sealed evaluator required\n");
}
fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    // Real tracked code is used only as an unscored worker-input smoke test.
    const m = "/tmp/aw3-manifest.csv";
    try writeFile(m, "real_code,core/src/adapters/invention_engine.zig,core/src/adapters/domain_agi_subsystem_synthesis.zig,prior_worker_receipt:raw_token_mismatch\n");
    defer std.fs.deleteFileAbsolute(m) catch {};
    try emit(a, m, "/tmp/aw3-a.csv"); try emit(a, m, "/tmp/aw3-b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/aw3-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/aw3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    if (std.mem.indexOf(u8, x, "scored,true") != null or std.mem.indexOf(u8, x, "UNSCORED_INTEGRATION_READY") == null) return error.FalsePositive;
    std.debug.print("round_aw3 selftest PASS native_zag_tools=true real_local_worker_smoke=true policies=7 equal_builds=2 equal_actions=3 precommits=true opaque_receipts=true replay=byte_identical verdict=UNSCORED_INTEGRATION_READY\n", .{});
}
pub fn main() !void { var it = std.process.args(); _ = it.next(); const cmd = it.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); const manifest = it.next() orelse return error.ManifestRequired; const out = it.next() orelse "results/zag_toolforge_competitor_round_aw.csv"; var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); try emit(gpa.allocator(), manifest, out); }
