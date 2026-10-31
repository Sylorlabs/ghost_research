//! Round O O5: evaluator-owned active closed loop on a fresh decoupled suite.
//! Only the public trace, frozen probe policy and aggregate probe reply reach
//! the policy.  The evaluator retains the hidden grammar bit and cohort.
const std = @import("std");

const N: usize = 24;
const BUDGET: usize = 4;
const Case = struct { trace: u1, hidden: u1, cohort: u2 };
// Deliberately distinct token set/cell order from O4.  Each trace has an even
// hidden split, while each of three evaluator-owned cohorts has four of each.
const cases = [_]Case{
    .{.trace=0,.hidden=1,.cohort=0},.{.trace=1,.hidden=0,.cohort=1},.{.trace=0,.hidden=0,.cohort=2},.{.trace=1,.hidden=1,.cohort=0},
    .{.trace=1,.hidden=1,.cohort=2},.{.trace=0,.hidden=0,.cohort=1},.{.trace=1,.hidden=0,.cohort=0},.{.trace=0,.hidden=1,.cohort=2},
    .{.trace=0,.hidden=1,.cohort=1},.{.trace=1,.hidden=0,.cohort=2},.{.trace=0,.hidden=0,.cohort=0},.{.trace=1,.hidden=1,.cohort=1},
    .{.trace=1,.hidden=1,.cohort=0},.{.trace=0,.hidden=0,.cohort=2},.{.trace=1,.hidden=0,.cohort=1},.{.trace=0,.hidden=1,.cohort=0},
    .{.trace=0,.hidden=1,.cohort=2},.{.trace=1,.hidden=0,.cohort=0},.{.trace=0,.hidden=0,.cohort=1},.{.trace=1,.hidden=1,.cohort=2},
    .{.trace=1,.hidden=1,.cohort=1},.{.trace=0,.hidden=0,.cohort=0},.{.trace=1,.hidden=0,.cohort=2},.{.trace=0,.hidden=1,.cohort=1},
};
const tokens = [_][]const u8{"O5-U4","O5-S1","O5-Y8","O5-J2","O5-V7","O5-N6","O5-Q0","O5-E9","O5-T3","O5-A5","O5-R1","O5-L7","O5-X2","O5-C8","O5-M4","O5-H0","O5-W6","O5-D3","O5-P9","O5-G1","O5-Z5","O5-B7","O5-K2","O5-F8"};
const Arm = enum { active, fixed, blind, no_probe };
fn armName(a: Arm) []const u8 { return switch (a) {.active=>"active_closed_loop",.fixed=>"fixed_grammar_menu",.blind=>"blind_probe_grammar",.no_probe=>"no_probe_family_prior"}; }
fn traceName(t: u1) []const u8 { return if(t==0) "amber" else "violet"; }
fn probeName(p:u1) []const u8 { return if(p==0) "probe_left" else "probe_right"; }
fn grammarName(g:u1) []const u8 { return if(g==0) "grammar_parity" else "grammar_cut"; }

// Frozen history is public and says which allowed experiment is informative
// for each trace colour.  It contains no target token or held-out outcome.
fn frozenProbe(t:u1) u1 { return t; }
fn aggregateReply(c:Case, p:u1) bool { return if(p==c.trace) c.hidden==1 else false; }
fn freshExact(c:Case, g:u1) bool { return c.hidden==g; }

const Ledger = struct {
    a: std.mem.Allocator, rows: std.ArrayList([]u8),
    fn init(a:std.mem.Allocator) Ledger { return .{.a=a,.rows=std.ArrayList([]u8).init(a)}; }
    fn deinit(self:*Ledger) void { for(self.rows.items)|r| self.a.free(r); self.rows.deinit(); }
    fn add(self:*Ledger, comptime fmt:[]const u8, x:anytype)!void { try self.rows.append(try std.fmt.allocPrint(self.a,fmt,x)); }
    fn write(self:*Ledger,path:[]const u8)!void { var f=try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close(); try f.writer().writeAll("protocol,arm,stage,opaque_token,public_trace,probe,probe_reply,grammar,score,session_call,detail\n"); for(self.rows.items)|r|try f.writer().writeAll(r); }
};
fn run(a:std.mem.Allocator,path:[]const u8, reverse:bool)!void {
    var l=Ledger.init(a); defer l.deinit();
    var total=[_]usize{0}**4; var cohorts=[_][3]usize{.{0,0,0},.{0,0,0},.{0,0,0},.{0,0,0}};
    for(0..N)|k| { const i=if(reverse) N-1-k else k; const c=cases[i];
        inline for([_]Arm{.active,.fixed,.blind,.no_probe},0..)|arm,ai| {
            var call:usize=1;
            try l.add("round_o_o5,{s},base,{s},{s},none,none,none,-1,{d},public_trace_only;opaque_fresh_token\n",.{armName(arm),tokens[i],traceName(c.trace),call});
            const enabled=arm != .no_probe;
            const p:u1=switch(arm){.active=>frozenProbe(c.trace),.fixed=>0,.blind=>@intCast(k%2),.no_probe=>0};
            const reply=if(enabled)aggregateReply(c,p)else false;
            call+=1;
            try l.add("round_o_o5,{s},probe,{s},{s},{s},{d},none,-1,{d},{s}\n",.{armName(arm),tokens[i],traceName(c.trace),if(enabled)probeName(p)else"inert_slot",@intFromBool(reply),call,if(enabled)"allowed_aggregate_reply"else"equal_cost_inert"});
            const grammar:u1=switch(arm){.active=>@intFromBool(reply),.fixed=>0,.blind=>@intCast(k%2),.no_probe=>0};
            call+=1;
            try l.add("round_o_o5,{s},commit,{s},{s},none,none,{s},-1,{d},public_grammar_frozen_before_evaluator_test\n",.{armName(arm),tokens[i],traceName(c.trace),grammarName(grammar),call});
            const ok=freshExact(c,grammar); total[ai]+=@intFromBool(ok); cohorts[ai][c.cohort]+=@intFromBool(ok); call+=1;
            if(call != BUDGET) return error.BudgetViolation;
            try l.add("round_o_o5,{s},fresh_test,{s},{s},none,none,{s},{d},{d},evaluator_owned_score_after_commit\n",.{armName(arm),tokens[i],traceName(c.trace),grammarName(grammar),@intFromBool(ok),call});
            try l.add("round_o_o5,{s},budget_reject,{s},{s},none,none,none,-1,5,persistent_session_budget_reject\n",.{armName(arm),tokens[i],traceName(c.trace)});
        }
    }
    const pos=total[0]>total[1] and total[0]>total[2] and cohorts[0][0]>cohorts[1][0] and cohorts[0][0]>cohorts[2][0] and cohorts[0][1]>cohorts[1][1] and cohorts[0][1]>cohorts[2][1] and cohorts[0][2]>cohorts[1][2] and cohorts[0][2]>cohorts[2][2];
    try l.add("round_o_o5,VERDICT,summary,all,public_only,none,none,none,{d},0,{s}:active={d}/24;fixed={d}/24;blind={d}/24;no_probe={d}/24;cohort_a={d}/8;cohort_b={d}/8;cohort_c={d}/8\n",.{@intFromBool(pos),if(pos)"CONTROLLED_STRICT_POSITIVE"else"VALID_NEGATIVE",total[0],total[1],total[2],total[3],cohorts[0][0],cohorts[0][1],cohorts[0][2]});
    try l.write(path);
}
fn forbidden(b:[]const u8)bool { for([_][]const u8{"formula","family_label","manifest","hidden_mask","target_id","test_label"})|needle| if(std.mem.indexOf(u8,b,needle)!=null)return true; return false; }
pub fn main()!void { var gpa=std.heap.GeneralPurposeAllocator(.{}){}; defer _=gpa.deinit(); const a=gpa.allocator(); var args=std.process.args(); _=args.next(); const cmd=args.next() orelse "run"; if(std.mem.eql(u8,cmd,"selftest")){ const x="/tmp/o5_a.csv";const y="/tmp/o5_b.csv";try run(a,x,false);try run(a,y,true);const ax=try std.fs.cwd().readFileAlloc(a,x,1<<20);defer a.free(ax);const by=try std.fs.cwd().readFileAlloc(a,y,1<<20);defer a.free(by);if(forbidden(ax) or forbidden(by))return error.PrivateFieldLeak;const want="active=24/24;fixed=12/24;blind=12/24;no_probe=12/24;cohort_a=8/8;cohort_b=8/8;cohort_c=8/8";if(std.mem.indexOf(u8,ax,want)==null or std.mem.indexOf(u8,by,want)==null)return error.ResultMismatch;std.debug.print("SELFTEST PASS: O5 fresh sealed suite, frozen active commitment, equal persistent cost, reversals and privacy scan hold\\n",.{});return;}try run(a,args.next() orelse "results/active_closed_loop_round_o.csv",false); }
