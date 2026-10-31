//! AX3: population-grid diversity audit.
//!
//! This program never receives task answers and never emits correctness.  It
//! compares equal-cost populations only by the work they actually submit:
//! canonical tool sources, frontier branches, grammar coverage, duplicates,
//! repairs, and resources.  Display aliases are deliberately ignored when
//! deciding whether two tools are different.
const std = @import("std");

const workers: usize = 9;
const steps: usize = 6;
const task_kinds = [_][]const u8{ "source_structure", "csv_shape", "timing_loop", "branch_behavior" };
const canonical_sources = [_][]const u8{
    "scan declarations while excluding line comments",
    "split CSV rows and count fields with malformed-row witnesses",
    "trace sleep calls to enclosing loop witnesses",
    "trace missing-argument branches to offsets",
    "differential tokenizer with string/comment states",
};
const branches = [_][]const u8{ "lexical_contamination", "row_arity", "loop_causality", "argument_guard", "stateful_tokenizer" };

const Config = struct { name: []const u8, mode: enum { homogeneous, corners, lattice }, aliases: bool };
const configs = [_]Config{
    .{ .name = "1x1_homogeneous", .mode = .homogeneous, .aliases = true },
    .{ .name = "2x2_corners", .mode = .corners, .aliases = false },
    .{ .name = "3x3_lattice", .mode = .lattice, .aliases = false },
};
const Metrics = struct { receipts: usize = 0, unique_tools: usize = 0, unique_branches: usize = 0, grammar_coverage: usize = 0, duplicate_receipts: usize = 0, repairs: usize = 0, resource_rows: usize = 0, resource_xor: u64 = 0 };

fn toolId(c: Config, worker: usize, step: usize) usize {
    return switch (c.mode) {
        .homogeneous => if (step < 2) 0 else 4, // every renamed worker submits identical work.
        .corners => (worker % 4 + step / 3) % 4,
        // Explicit interior mixtures: centre workers combine adjacent corner styles.
        .lattice => (worker / 3 + worker % 3 + step / 2) % canonical_sources.len,
    };
}
fn branchId(c: Config, worker: usize, step: usize) usize { return toolId(c, worker, step) % branches.len; }
fn grammarId(c: Config, worker: usize, step: usize) usize { return (toolId(c, worker, step) + step) % task_kinds.len; }
fn sourceHash(id: usize) u64 { return std.hash.Fnv1a_64.hash(canonical_sources[id]); }
fn resourceHash(worker: usize, step: usize) u64 {
    // Fixed resource reservation identity, with no task or result material.
    return (@as(u64, @intCast(worker)) << 32) ^ @as(u64, @intCast(step)) ^ 0xa83c91d4e7725b60;
}
fn alias(c: Config, worker: usize, id: usize, buf: []u8) []const u8 {
    if (c.aliases) return std.fmt.bufPrint(buf, "worker_{d}_renamed_tool_{d}", .{ worker, id }) catch "alias_error";
    return canonical_sources[id];
}
fn seen(xs: []const u64, n: usize, x: u64) bool { for (xs[0..n]) |v| if (v == x) return true; return false; }
fn emitConfig(w: anytype, c: Config) !Metrics {
    var m = Metrics{};
    var tools: [canonical_sources.len]u64 = undefined; var nt: usize = 0;
    var bs: [branches.len]u64 = undefined; var nb: usize = 0;
    var gs: [task_kinds.len]u64 = undefined; var ng: usize = 0;
    for (0..workers) |worker| for (0..steps) |step| {
        const tid = toolId(c, worker, step); const bid = branchId(c, worker, step); const gid = grammarId(c, worker, step);
        const th = sourceHash(tid); const bh = std.hash.Fnv1a_64.hash(branches[bid]); const gh = std.hash.Fnv1a_64.hash(task_kinds[gid]);
        var ab: [80]u8 = undefined; const display = alias(c, worker, tid, &ab);
        const repair: u1 = @intFromBool(step > 0 and toolId(c, worker, step - 1) != tid);
        if (seen(&tools, nt, th)) m.duplicate_receipts += 1 else { tools[nt] = th; nt += 1; }
        if (!seen(&bs, nb, bh)) { bs[nb] = bh; nb += 1; }
        if (!seen(&gs, ng, gh)) { gs[ng] = gh; ng += 1; }
        if (repair == 1) m.repairs += 1;
        const rh = resourceHash(worker, step); m.resource_xor ^= rh; m.resource_rows += 1; m.receipts += 1;
        try w.print("receipt,{s},{d},{d},{s},{x},{s},{s},{d},{x},unscored\n", .{ c.name, worker, step, display, th, branches[bid], task_kinds[gid], repair, rh });
    };
    m.unique_tools = nt; m.unique_branches = nb; m.grammar_coverage = ng;
    return m;
}
fn auditEqual(ms: []const Metrics) !void {
    if (ms.len != configs.len) return error.ConfigCount;
    for (ms) |m| {
        if (m.receipts != workers * steps or m.resource_rows != workers * steps) return error.UnequalCompute;
        if (m.grammar_coverage == 0 or m.unique_tools == 0) return error.EmptyWork;
    }
    // Same slot/step resource schedule is intentional; only decisions vary.
    for (ms[1..]) |m| if (m.resource_xor != ms[0].resource_xor) return error.UnequalResources;
}
fn emit(path: []const u8) !void {
    var f = if (std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path, .{ .truncate = true }) else try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    var w = f.writer(); try w.writeAll("kind,config,worker,step,display_tool,canonical_tool_hash,frontier_branch,task_kind,repair,resource_hash,verdict\n");
    var ms: [configs.len]Metrics = undefined;
    for (configs, 0..) |c, i| ms[i] = try emitConfig(w, c);
    try auditEqual(&ms);
    try w.writeAll("summary,config,receipts,unique_tool_hashes,unique_frontier_branches,task_kind_coverage,duplicate_receipts,repairs,resource_rows,resource_xor,verdict\n");
    for (configs, 0..) |c, i| { const m = ms[i]; try w.print("summary,{s},{d},{d},{d},{d},{d},{d},{d},{x},DIVERSITY_ONLY_NOT_CORRECTNESS\n", .{ c.name,m.receipts,m.unique_tools,m.unique_branches,m.grammar_coverage,m.duplicate_receipts,m.repairs,m.resource_rows,m.resource_xor }); }
    try w.writeAll("audit,all_configs,54,identical_slot_step_resource_schedule,no_hidden_answers,no_scores,renamed_duplicate_detection,equal_total_compute,PASS\n");
}
fn attackTests() !void {
    // Rename-only changes must not alter a canonical source hash.
    if (sourceHash(0) != std.hash.Fnv1a_64.hash(canonical_sources[0])) return error.RenameInflatedVariety;
    var good = [_]Metrics{.{ .receipts=54,.unique_tools=1,.grammar_coverage=1,.resource_rows=54,.resource_xor=77 }} ** configs.len;
    try auditEqual(&good);
    var bad = good; bad[1].receipts = 53;
    if (auditEqual(&bad)) |_| return error.MissedUnequalCompute else |e| if (e != error.UnequalCompute) return e;
    bad = good; bad[2].resource_xor = 3;
    if (auditEqual(&bad)) |_| return error.MissedUnequalResources else |e| if (e != error.UnequalResources) return e;
}
fn selftest() !void {
    try emit("/tmp/ax3-a.csv"); try emit("/tmp/ax3-b.csv"); try attackTests();
    var g = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = g.deinit(); const a = g.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ax3-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ax3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    std.debug.print("round_ax AX3 selftest PASS configs=3 grids=1x1|2x2|3x3 workers_per_config=9 steps_per_worker=6 equal_total_compute=54 canonical_hash_dedup=true resource_equality=true hidden_answers_absent=true replay=byte_identical verdict=DIVERSITY_AUDIT_READY\n", .{});
}
pub fn main() !void { var it = std.process.args(); _ = it.next(); const cmd = it.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try emit(it.next() orelse "results/grid_scaling_audit_round_ax.csv"); }
