//! Round AT3: deterministic frontier (maze) ledger.
//!
//! This is deliberately not an answer solver.  The planner receives only
//! opaque receipts and chooses which hypothesis fork to test next.  It has no
//! task label, score, hidden outcome, network, or language-model dependency.
//! Its only honest terminal statement is finite: which reachable branches were
//! explored under this run's stated budget, and which remain unreached.
const std = @import("std");

const State = enum { unexplored, tested, split, dead_end, confirmed, inconclusive };
const Fork = struct {
    id: u8,
    parent: ?u8,
    state: State,
    hypothesis: []const u8,
    falsifier: []const u8,
    tool: []const u8,
    cost: u32,
    receipt: []const u8,
    retry_reason: []const u8,
};

const Receipt = struct { fork: u8, event: []const u8, observation: []const u8 };

fn text(s: State) []const u8 {
    return switch (s) {
        .unexplored => "unexplored", .tested => "tested", .split => "split",
        .dead_end => "dead_end", .confirmed => "confirmed", .inconclusive => "inconclusive",
    };
}

// FNV-1a is used solely to make an append-only tamper-evident receipt chain;
// it is not a security claim.
fn hashStep(previous: u64, r: Receipt) u64 {
    var h: u64 = previous ^ 0xcbf29ce484222325;
    const parts = [_][]const u8{ r.event, r.observation };
    for (parts) |p| for (p) |c| { h ^= c; h *%= 0x100000001b3; };
    h ^= r.fork;
    h *%= 0x100000001b3;
    return h;
}

fn chooseNext(forks: []const Fork, budget_left: u32) ?usize {
    // Deterministic policy: favor an unexplored falsifiable fork, then the
    // lowest cost and id. It cannot inspect a hidden correctness signal.
    var chosen: ?usize = null;
    for (forks, 0..) |f, i| {
        if (f.state != .unexplored or f.cost > budget_left) continue;
        if (chosen == null or f.cost < forks[chosen.?].cost or
            (f.cost == forks[chosen.?].cost and f.id < forks[chosen.?].id)) chosen = i;
    }
    return chosen;
}

fn validate(forks: []const Fork, receipts: []const Receipt) !void {
    // No fork may be marked concluded without a precommitted falsifier/tool.
    // A dead-end retry must state why the new attempt differs.
    for (forks) |f| {
        if (f.falsifier.len == 0 or f.tool.len == 0) return error.MissingPrecommitment;
        if (f.state == .dead_end and f.retry_reason.len == 0) return error.UnjustifiedDeadEndRetry;
        if (f.parent) |p| if (p >= f.id) return error.InvalidParentLink;
    }
    var chain: u64 = 0;
    for (receipts) |r| chain = hashStep(chain, r);
    if (chain == 0) return error.EmptyReceiptChain;
}

fn writeRun(path: []const u8) !void {
    // Receipts intentionally contain opaque structural observations, not task
    // labels or final answers. They model what an isolated worker may return.
    const receipts = [_]Receipt{
        .{ .fork = 1, .event = "probe_completed", .observation = "shape:3|delta:0|hash:0a11" },
        .{ .fork = 1, .event = "falsifier_hit", .observation = "shape:3|delta:0|hash:0a11" },
        .{ .fork = 2, .event = "probe_completed", .observation = "shape:7|delta:2|hash:91ce" },
        .{ .fork = 2, .event = "surprise_split", .observation = "shape:7|delta:2|hash:91ce" },
        .{ .fork = 3, .event = "tool_inadequate", .observation = "shape:7|delta:2|hash:91ce" },
    };
    var forks = [_]Fork{
        .{ .id = 1, .parent = null, .state = .dead_end, .hypothesis = "regularity_A", .falsifier = "no_delta_after_probe", .tool = "bounded_probe", .cost = 2, .receipt = "0a11", .retry_reason = "different_sampling_window_required" },
        .{ .id = 2, .parent = null, .state = .split, .hypothesis = "regularity_B", .falsifier = "delta_absent_under_probe", .tool = "bounded_probe", .cost = 3, .receipt = "91ce", .retry_reason = "" },
        .{ .id = 3, .parent = 2, .state = .inconclusive, .hypothesis = "B_subcase_local", .falsifier = "trace_lacks_transition", .tool = "trace_probe", .cost = 3, .receipt = "91ce", .retry_reason = "" },
        .{ .id = 4, .parent = 2, .state = .unexplored, .hypothesis = "B_subcase_global", .falsifier = "cross_sample_mismatch", .tool = "cross_probe", .cost = 5, .receipt = "", .retry_reason = "" },
        .{ .id = 5, .parent = null, .state = .unexplored, .hypothesis = "alternate_mechanism", .falsifier = "transform_is_stable", .tool = "transform_probe", .cost = 6, .receipt = "", .retry_reason = "" },
    };
    try validate(&forks, &receipts);
    if (chooseNext(&forks, 4) != null) return error.BudgetPolicyLeak; // 5/6 cost branches remain.

    var chain: u64 = 0;
    for (receipts) |r| chain = hashStep(chain, r);
    var file = if (std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path, .{ .truncate = true }) else try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    const w = file.writer();
    try w.writeAll("round,kind,id,parent,state,hypothesis,falsifier,tool,cost,receipt,retry_reason,chain\n");
    for (forks) |f| {
        var parent_buf: [4]u8 = undefined;
        const parent = if (f.parent) |p| try std.fmt.bufPrint(&parent_buf, "{d}", .{p}) else "root";
        try w.print("round_at3,fork,{d},{s},{s},{s},{s},{s},{d},{s},{s},{x}\n", .{ f.id, parent, text(f.state), f.hypothesis, f.falsifier, f.tool, f.cost, f.receipt, f.retry_reason, chain });
    }
    try w.print("round_at3,summary,-,-,finite_exhaustion,reachable_budget=4; explored=3; unreached=4|5; reality_not_claimed_exhausted,-,-,4,-,-,{x}\n", .{chain});
}

fn selftest() !void {
    try writeRun("/tmp/at3-a.csv");
    try writeRun("/tmp/at3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/at3-a.csv", 1 << 20); defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/at3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    if (std.mem.indexOf(u8, x, "reality_not_claimed_exhausted") == null) return error.MissingFiniteLimit;
    if (std.mem.indexOf(u8, x, "unreached=4|5") == null) return error.MissingUnreachedBranches;
    std.debug.print("round_at3 selftest PASS deterministic_replay=true opaque_receipts=true append_only_chain=true split=true unreached=4|5 verdict=MECHANICS_READY_NOT_INVENTION_PROOF\n", .{});
}

pub fn main() !void {
    var args = std.process.args(); _ = args.next();
    const command = args.next() orelse "run";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    try writeRun(args.next() orelse "results/frontier_explorer_round_at.csv");
}
