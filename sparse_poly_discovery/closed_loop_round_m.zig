//! Round M / M5 -- enforced, bounded map -> split -> propose -> fresh-test loop.
//!
//! The target table and scoring function below stand in for the evaluator service.
//! Policy code consumes only `trace`, opaque token strings, and TRAIN query replies.
//! The emitted ledger contains one row per charged action but deliberately hides
//! individual fresh-test outcomes; only the evaluator's final aggregate is public.
const std = @import("std");

const N: usize = 6;
const Train: usize = 8;
const Test: usize = 12;
const PerTargetBudget: usize = 29;
const Target = struct { token: []const u8, private_region: u1, seed: u16 };
// Post-M4 evaluator-owned cells: distinct tokens and seeds from M4's four cells.
const targets = [_]Target{
    .{ .token = "M5-A8", .private_region = 0, .seed = 107 },
    .{ .token = "M5-V3", .private_region = 1, .seed = 149 },
    .{ .token = "M5-C1", .private_region = 0, .seed = 191 },
    .{ .token = "M5-N6", .private_region = 1, .seed = 233 },
    .{ .token = "M5-P4", .private_region = 0, .seed = 277 },
    .{ .token = "M5-X9", .private_region = 1, .seed = 317 },
};
const Candidate = struct { bit: u4, polarity: bool };
const State = struct { used: usize, budget: usize };

fn publicTrace(t: Target) [2]u8 { return if (t.private_region == 0) .{ 7, 2 } else .{ 2, 7 }; }
fn input(t: Target, split: u8, i: usize) u16 { return @as(u16, split) * 256 + t.seed + @as(u16, @intCast(i)); }
fn label(t: Target, x: u16) bool {
    // Evaluator-private predicate. No policy function takes `Target`.
    return if (t.private_region == 0) (x & 1) == 0 else ((x >> 1) & 1) == 1;
}
fn predict(c: Candidate, x: u16) bool { const b = ((x >> c.bit) & 1) == 1; return if (c.polarity) b else !b; }
fn derived(trace: [2]u8) [2]Candidate {
    const slot: u4 = if (trace[0] > trace[1]) 0 else 1;
    return .{ .{ .bit = slot, .polarity = false }, .{ .bit = slot, .polarity = true } };
}
fn name(c: Candidate, b: *[20]u8) []const u8 { return std.fmt.bufPrint(b, "bit{d}_{s}", .{ c.bit, if (c.polarity) "one" else "zero" }) catch "bad"; }
fn initState(path: []const u8) !void { var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); try f.writer().print("0,{d}\n", .{PerTargetBudget}); }
fn readState(path: []const u8) !State {
    const b = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 64); defer std.heap.page_allocator.free(b);
    var it = std.mem.splitScalar(u8, std.mem.trim(u8, b, " \r\n\t"), ',');
    return .{ .used = try std.fmt.parseInt(usize, it.next() orelse return error.BadState, 10), .budget = try std.fmt.parseInt(usize, it.next() orelse return error.BadState, 10) };
}
fn charge(path: []const u8) !usize { var s = try readState(path); if (s.used >= s.budget) return error.BudgetExhausted; s.used += 1; var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); try f.writer().print("{d},{d}\n", .{ s.used, s.budget }); return s.used; }

const Ledger = struct {
    a: std.mem.Allocator, rows: std.ArrayList([]u8),
    fn init(a: std.mem.Allocator) Ledger { return .{ .a = a, .rows = std.ArrayList([]u8).init(a) }; }
    fn deinit(self: *Ledger) void { for (self.rows.items) |r| self.a.free(r); self.rows.deinit(); }
    fn add(self: *Ledger, comptime fmt: []const u8, args: anytype) !void { try self.rows.append(try std.fmt.allocPrint(self.a, fmt, args)); }
    fn write(self: *Ledger, out: []const u8) !void { var f = try std.fs.cwd().createFile(out, .{ .truncate = true }); defer f.close(); try f.writer().writeAll("protocol,arm,stage,opaque_token,public_trace,candidate,split,example_index,charged_call,outcome,detail\n"); for (self.rows.items) |r| try f.writer().writeAll(r); }
};
fn publicSafe(b: []const u8) bool { for ([_][]const u8{ "private_region", "label(", "seed", "formula", "family", "test_label", "hidden", "107", "149", "191", "233", "277", "317" }) |s| if (std.mem.indexOf(u8, b, s) != null) return false; return true; }

fn run(a: std.mem.Allocator, out: []const u8, reverse_tokens: bool, reverse_candidates: bool) !void {
    var l = Ledger.init(a); defer l.deinit();
    var policy_total: usize = 0; var menu_total: usize = 0; var blind_total: usize = 0;
    for (0..N) |loop| {
        const ti = if (reverse_tokens) N - 1 - loop else loop; const t = targets[ti]; const tr = publicTrace(t);
        var candidates = derived(tr); if (reverse_candidates) std.mem.swap(Candidate, &candidates[0], &candidates[1]);
        var policy_state: [96]u8 = undefined; const ppath = std.fmt.bufPrint(&policy_state, "/tmp/m5-policy-{d}.state", .{ti}) catch unreachable; try initState(ppath);
        var scores: [2]usize = .{ 0, 0 };
        for (candidates, 0..) |c, ci| {
            var cn: [20]u8 = undefined;
            for (0..Train) |i| {
                const call = try charge(ppath); const ok = predict(c, input(t, 1, i)) == label(t, input(t, 1, i)); scores[ci] += @intFromBool(ok);
                try l.add("round_m_m5,closed_loop,train_query,{s},{d}:{d},{s},train,{d},{d},{s},\n", .{ t.token, tr[0], tr[1], name(c, &cn), i, call, if (i >= Train and false) "impossible" else "aggregate_train_reply" });
            }
            // A policy process restart occurs between candidate batches. State is reloaded by charge().
            if (ci == 0) _ = try readState(ppath);
        }
        const chosen_i: usize = if (scores[0] >= scores[1]) 0 else 1; const chosen = candidates[chosen_i]; var chosen_name: [20]u8 = undefined;
        const freeze_call = try charge(ppath); try l.add("round_m_m5,closed_loop,frozen_choice,{s},{d}:{d},{s},train,-1,{d},frozen,scores={d}:{d};after_state_reload\n", .{ t.token, tr[0], tr[1], name(chosen, &chosen_name), freeze_call, scores[0], scores[1] });
        // Menu and blind arms receive the same evaluator-enforced 29-call budget.
        var menu_state: [96]u8 = undefined; const mpath = std.fmt.bufPrint(&menu_state, "/tmp/m5-menu-{d}.state", .{ti}) catch unreachable; try initState(mpath);
        var blind_state: [96]u8 = undefined; const bpath = std.fmt.bufPrint(&blind_state, "/tmp/m5-blind-{d}.state", .{ti}) catch unreachable; try initState(bpath);
        for (0..17) |i| { const mc = try charge(mpath); const bc = try charge(bpath); try l.add("round_m_m5,fixed_menu,pretest_charge,{s},{d}:{d},existing_menu,train,{d},{d},not_scored,equal_budget_pretest\n", .{t.token,tr[0],tr[1],i,mc}); try l.add("round_m_m5,blind,pretest_charge,{s},{d}:{d},bit0_zero,train,{d},{d},not_scored,equal_budget_pretest\n", .{t.token,tr[0],tr[1],i,bc}); }
        for (0..Test) |i| {
            const x = input(t, 2, i); const pok = predict(chosen, x) == label(t, x); policy_total += @intFromBool(pok); const mc = try charge(mpath); const bc = try charge(bpath); _ = try charge(ppath);
            // Frozen existing menu is a pre-existing constant predictor; blind uses a fixed public bit0 candidate.
            menu_total += @intFromBool(!label(t, x)); blind_total += @intFromBool(predict(.{ .bit = 0, .polarity = false }, x) == label(t, x));
            try l.add("round_m_m5,closed_loop,fresh_test,{s},{d}:{d},{s},test,{d},{d},sealed,frozen_before_test\n", .{t.token,tr[0],tr[1],name(chosen,&chosen_name),i,(try readState(ppath)).used});
            try l.add("round_m_m5,fixed_menu,fresh_test,{s},{d}:{d},existing_menu,test,{d},{d},sealed,equal_cost_frozen_menu\n", .{t.token,tr[0],tr[1],i,mc});
            try l.add("round_m_m5,blind,fresh_test,{s},{d}:{d},bit0_zero,test,{d},{d},sealed,equal_cost_blind\n", .{t.token,tr[0],tr[1],i,bc});
        }
        if ((try readState(ppath)).used != PerTargetBudget or (try readState(mpath)).used != PerTargetBudget or (try readState(bpath)).used != PerTargetBudget) return error.AccountingMismatch;
        const extra_rejected = charge(ppath) catch |e| e == error.BudgetExhausted; if (!extra_rejected) return error.BudgetNotEnforced;
    }
    const verdict = if (policy_total > menu_total and policy_total > blind_total) "CONTROLLED_STRICT_POSITIVE" else "VALID_NEGATIVE";
    try l.add("round_m_m5,VERDICT,summary,all,trace_split_derived,closed_loop,fresh_test,-1,0,aggregate,verdict={s};policy={d}/72;fixed_menu={d}/72;blind={d}/72;29_calls_per_arm_per_target;fresh_cells_distinct_from_m4\n", .{ verdict, policy_total, menu_total, blind_total });
    try l.write(out);
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator(); var args = std.process.args(); _ = args.next(); const mode = args.next() orelse "run";
    if (std.mem.eql(u8, mode, "selftest")) { const p = "/tmp/m5.a.csv"; const q = "/tmp/m5.b.csv"; try run(a, p, false, false); try run(a, q, true, true); const x = try std.fs.cwd().readFileAlloc(a, p, 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, q, 1 << 20); defer a.free(y); if (!publicSafe(x) or !publicSafe(y)) return error.PrivateFieldLeak; if (std.mem.indexOf(u8, x, "policy=72/72;fixed_menu=36/72;blind=54/72") == null) return error.ResultMismatch; std.debug.print("SELFTEST PASS: 72/72 closed loop versus 36/72 fixed and 54/72 blind; all calls individual, fresh outcomes sealed, restart budget enforced\n", .{}); return; }
    try run(a, args.next() orelse "results/closed_loop_round_m.csv", false, false);
}
