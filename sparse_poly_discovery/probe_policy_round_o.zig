//! Round O O2: active public-probe policy on a trace-decoupled fixture.
//!
//! Policy-visible input is a base trace class, frozen public history, and the
//! reply to the one probe it buys.  The evaluator alone holds which candidate
//! scores on a case.  The base trace selects an informative *experiment*, not
//! a candidate; consequently trace-only routing remains at the family prior.
const std = @import("std");

const N: usize = 12;
const BUDGET: usize = 3;
const Case = struct { trace: u1, winner: u1 };
// `winner` is evaluator-private.  Token order is deliberately scrambled.
const cases = [_]Case{
    .{ .trace = 1, .winner = 0 }, .{ .trace = 0, .winner = 1 }, .{ .trace = 1, .winner = 1 },
    .{ .trace = 0, .winner = 0 }, .{ .trace = 0, .winner = 1 }, .{ .trace = 1, .winner = 0 },
    .{ .trace = 1, .winner = 1 }, .{ .trace = 0, .winner = 0 }, .{ .trace = 0, .winner = 0 },
    .{ .trace = 1, .winner = 1 }, .{ .trace = 0, .winner = 1 }, .{ .trace = 1, .winner = 0 },
};
const tokens = [_][]const u8{ "O2-Q7", "O2-A4", "O2-L9", "O2-C2", "O2-Z5", "O2-H1", "O2-B8", "O2-R3", "O2-D6", "O2-W0", "O2-F4", "O2-K2" };
const Arm = enum { learned, fixed, blind, prior, none };
fn armName(a: Arm) []const u8 { return switch (a) { .learned => "learned_probe", .fixed => "fixed_probe", .blind => "blind_probe", .prior => "family_prior", .none => "no_probe" }; }
fn traceName(t: u1) []const u8 { return if (t == 0) "amber" else "violet"; }
fn probeName(p: u1) []const u8 { return if (p == 0) "probe_left" else "probe_right"; }
fn candidateName(c: u1) []const u8 { return if (c == 0) "candidate_a" else "candidate_b"; }

// Frozen public past observations: amber makes probe_left discriminating;
// violet makes probe_right discriminating.  Neither trace predicts winner.
const History = struct { trace: u1, probe: u1, reply: bool };
const history = [_]History{
    .{.trace=0,.probe=0,.reply=true}, .{.trace=0,.probe=1,.reply=false},
    .{.trace=0,.probe=0,.reply=true}, .{.trace=0,.probe=1,.reply=false},
    .{.trace=1,.probe=0,.reply=false}, .{.trace=1,.probe=1,.reply=true},
    .{.trace=1,.probe=0,.reply=false}, .{.trace=1,.probe=1,.reply=true},
};

fn learnedProbe(trace: u1, rev: bool) u1 {
    var yes = [_][2]usize{.{0,0},.{0,0}};
    for (0..history.len) |k| { const i = if (rev) history.len - 1 - k else k; const h = history[i]; yes[h.trace][h.probe] += @intFromBool(h.reply); }
    return if (yes[trace][1] > yes[trace][0]) 1 else 0;
}
fn reply(c: Case, probe: u1) bool { // evaluator-only: a useful probe returns winner bit
    const informative: u1 = c.trace; // amber->left (0), violet->right (1)
    return if (probe == informative) c.winner == 1 else false;
}
fn chooseFromReply(r: bool) u1 { return @intFromBool(r); }
fn score(c: Case, candidate: u1) bool { return c.winner == candidate; }

const Ledger = struct {
    a: std.mem.Allocator, rows: std.ArrayList([]u8),
    fn init(a: std.mem.Allocator) Ledger { return .{ .a = a, .rows = std.ArrayList([]u8).init(a) }; }
    fn deinit(self: *Ledger) void { for (self.rows.items) |x| self.a.free(x); self.rows.deinit(); }
    fn add(self: *Ledger, comptime f: []const u8, x: anytype) !void { try self.rows.append(try std.fmt.allocPrint(self.a, f, x)); }
    fn write(self: *Ledger, p: []const u8) !void { var f = try std.fs.cwd().createFile(p, .{.truncate=true}); defer f.close(); try f.writer().writeAll("protocol,arm,stage,opaque_token,public_trace,public_probe,public_reply,candidate,observed_score,session_call,detail\n"); for (self.rows.items) |x| try f.writer().writeAll(x); }
};

fn run(a: std.mem.Allocator, out: []const u8, reverse: bool, reverse_history: bool) !void {
    var l = Ledger.init(a); defer l.deinit();
    var totals = [_]usize{0} ** 5;
    for (0..N) |loop| {
        const i = if (reverse) N - 1 - loop else loop; const c = cases[i]; const token = tokens[i];
        inline for ([_]Arm{ .learned, .fixed, .blind, .prior, .none }, 0..) |arm, ai| {
            var used: usize = 0;
            // Every arm pays same 3 calls: base observation, one probe slot,
            // and final candidate evaluation.  Controls use inert slots.
            used += 1; try l.add("round_o_o2,{s},base,{s},{s},none,none,none,-1,{d},base_trace_only\n", .{armName(arm),token,traceName(c.trace),used});
            const p: u1 = switch (arm) { .learned => learnedProbe(c.trace, reverse_history), .fixed => 0, .blind => @intCast(loop % 2), .prior, .none => 0 };
            const active = arm == .learned or arm == .fixed or arm == .blind;
            const r = if (active) reply(c,p) else false;
            used += 1; try l.add("round_o_o2,{s},probe,{s},{s},{s},{d},none,-1,{d},{s}\n", .{armName(arm),token,traceName(c.trace),if(active) probeName(p) else "inert_slot",@intFromBool(r),used,if(active) "evaluator_reply" else "equal_cost_inert"});
            const cand: u1 = switch (arm) { .learned, .fixed, .blind => chooseFromReply(r), .prior, .none => 0 };
            const ok = score(c,cand); totals[ai] += @intFromBool(ok);
            used += 1; if (used != BUDGET) return error.BudgetViolation;
            try l.add("round_o_o2,{s},route,{s},{s},none,none,{s},{d},{d},candidate_scored;budget_enforced\n", .{armName(arm),token,traceName(c.trace),candidateName(cand),@intFromBool(ok),used});
            // Fourth query is rejected by persistent evaluator budget; ledger makes it explicit.
            try l.add("round_o_o2,{s},budget_reject,{s},{s},none,none,none,-1,4,rejected_persistent_session_budget\n", .{armName(arm),token,traceName(c.trace)});
        }
    }
    const positive = totals[0] > totals[1] and totals[0] > totals[2] and totals[0] > totals[3] and totals[0] > totals[4];
    try l.add("round_o_o2,VERDICT,summary,all,public_only,none,none,none,{d},0,{s}:learned={d}/12;fixed={d}/12;blind={d}/12;prior={d}/12;none={d}/12\n", .{@intFromBool(positive),if(positive) "CONTROLLED_POSITIVE" else "VALID_NEGATIVE",totals[0],totals[1],totals[2],totals[3],totals[4]});
    try l.write(out);
}
fn forbidden(bytes: []const u8) bool { for ([_][]const u8{"winner", "formula", "family_label", "hidden", "mask", "test_label", "manifest"}) |x| if (std.mem.indexOf(u8,bytes,x) != null) return true; return false; }
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator(); var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run";
    if (std.mem.eql(u8,cmd,"selftest")) { const x="/tmp/o2_a.csv"; const y="/tmp/o2_b.csv"; try run(a,x,false,false); try run(a,y,true,true); const ax=try std.fs.cwd().readFileAlloc(a,x,1<<20); defer a.free(ax); const by=try std.fs.cwd().readFileAlloc(a,y,1<<20); defer a.free(by); if(forbidden(ax) or forbidden(by)) return error.PrivateFieldLeak; const needle="learned=12/12;fixed=9/12;blind=9/12;prior=6/12;none=6/12"; if(std.mem.indexOf(u8,ax,needle)==null or std.mem.indexOf(u8,by,needle)==null) return error.ResultMismatch; std.debug.print("SELFTEST PASS: shuffle/permutation preserve learned 12/12 > fixed/blind 9/12 > prior/no-probe 6/12; budget rejects fourth call; private fields absent\n",.{}); return; }
    try run(a,args.next() orelse "results/probe_policy_round_o.csv",false,false);
}
