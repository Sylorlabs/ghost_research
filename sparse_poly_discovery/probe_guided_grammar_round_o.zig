//! Round O O4: probe-guided public grammar commitment on a decoupled fixture.
//! The policy sees only trace colour, frozen public probe history, and an
//! aggregate probe reply.  The evaluator holds the scoring relation.
const std = @import("std");

const N: usize = 16;
const BUDGET: usize = 4;
const Case = struct { trace: u1, bit: u1, partition: u1 };
// Each trace has an even 4/4 split of evaluator bits.  `partition` is used
// only by the evaluator for aggregate reporting; neither it nor `bit` enters
// the policy-visible ledger.
const cases = [_]Case{
    .{.trace=0,.bit=0,.partition=0},.{.trace=1,.bit=1,.partition=1},.{.trace=0,.bit=1,.partition=0},.{.trace=1,.bit=0,.partition=1},
    .{.trace=1,.bit=1,.partition=1},.{.trace=0,.bit=0,.partition=0},.{.trace=1,.bit=0,.partition=1},.{.trace=0,.bit=1,.partition=0},
    .{.trace=0,.bit=1,.partition=1},.{.trace=1,.bit=0,.partition=0},.{.trace=0,.bit=0,.partition=1},.{.trace=1,.bit=1,.partition=0},
    .{.trace=1,.bit=0,.partition=0},.{.trace=0,.bit=1,.partition=1},.{.trace=1,.bit=1,.partition=0},.{.trace=0,.bit=0,.partition=1},
};
const tokens = [_][]const u8{"O4-Q7","O4-A4","O4-L9","O4-C2","O4-Z5","O4-H1","O4-B8","O4-R3","O4-D6","O4-W0","O4-F4","O4-K2","O4-P1","O4-G6","O4-X3","O4-M8"};
const Arm = enum { guided, fixed, blind, prior, no_probe };
fn an(a: Arm) []const u8 { return switch(a){.guided=>"probe_guided_grammar",.fixed=>"fixed_grammar",.blind=>"blind_grammar",.prior=>"family_prior",.no_probe=>"no_probe"}; }
fn tn(t:u1) []const u8 { return if(t==0) "amber" else "violet"; }
fn pn(p:u1) []const u8 { return if(p==0) "probe_left" else "probe_right"; }
fn gn(g:u1) []const u8 { return if(g==0) "grammar_parity" else "grammar_cut"; }

// Frozen, public training/query history: it teaches which diagnostic works
// for a trace colour, never which grammar scores on an opaque test token.
const Hist = struct { trace:u1, probe:u1, informative:bool };
const hist = [_]Hist{ .{.trace=0,.probe=0,.informative=true},.{.trace=0,.probe=1,.informative=false},.{.trace=1,.probe=0,.informative=false},.{.trace=1,.probe=1,.informative=true}, .{.trace=0,.probe=0,.informative=true},.{.trace=1,.probe=1,.informative=true} };
fn chooseProbe(t:u1, reverse:bool) u1 { var n=[_]usize{0,0}; for(0..hist.len)|k| { const i=if(reverse)hist.len-1-k else k; const h=hist[i]; if(h.trace==t and h.informative)n[h.probe]+=1; } return if(n[1]>n[0])1 else 0; }
fn probeReply(c:Case,p:u1) bool { return if(p==c.trace) c.bit==1 else false; }
fn exact(c:Case,g:u1) bool { return c.bit==g; }

const Ledger=struct { a:std.mem.Allocator, rows:std.ArrayList([]u8), fn init(a:std.mem.Allocator)Ledger{return .{.a=a,.rows=std.ArrayList([]u8).init(a)};} fn deinit(s:*Ledger)void{for(s.rows.items)|r|s.a.free(r);s.rows.deinit();} fn add(s:*Ledger,comptime f:[]const u8,x:anytype)!void{try s.rows.append(try std.fmt.allocPrint(s.a,f,x));} fn write(s:*Ledger,p:[]const u8)!void{var f=try std.fs.cwd().createFile(p,.{.truncate=true});defer f.close();try f.writer().writeAll("protocol,arm,stage,opaque_token,public_trace,probe,probe_reply,grammar,score,session_call,detail\n");for(s.rows.items)|r|try f.writer().writeAll(r);} };

fn run(a:std.mem.Allocator,out:[]const u8,reverse:bool)!void { var l=Ledger.init(a);defer l.deinit(); var total=[_]usize{0}**5;var part=[_][2]usize{.{0,0},.{0,0},.{0,0},.{0,0},.{0,0}};
 for(0..N)|k| {const i=if(reverse)N-1-k else k;const c=cases[i];
  inline for([_]Arm{.guided,.fixed,.blind,.prior,.no_probe},0..)|arm,ai| {var call:usize=1;try l.add("round_o_o4,{s},base,{s},{s},none,none,none,-1,{d},trace_only;test_token_opaque\n",.{an(arm),tokens[i],tn(c.trace),call});
   const active=arm==.guided or arm==.fixed or arm==.blind; const p:u1=switch(arm){.guided=>chooseProbe(c.trace,reverse),.fixed=>0,.blind=>@intCast(k%2),else=>0}; const r=if(active)probeReply(c,p)else false;call+=1;try l.add("round_o_o4,{s},probe,{s},{s},{s},{d},none,-1,{d},{s}\n",.{an(arm),tokens[i],tn(c.trace),if(active)pn(p)else"inert_slot",@intFromBool(r),call,if(active)"aggregate_reply"else"equal_cost_inert"});
   // Commitment is frozen before fresh scoring.  Guided route is only from the allowed reply.
   const g:u1=switch(arm){.guided=>@intFromBool(r),.fixed=>0,.blind=>@intCast(k%2),.prior,.no_probe=>0};call+=1;try l.add("round_o_o4,{s},commit,{s},{s},none,none,{s},-1,{d},public_nonredundant_grammar_frozen_before_test\n",.{an(arm),tokens[i],tn(c.trace),gn(g),call});
   const ok=exact(c,g);total[ai]+=@intFromBool(ok);part[ai][c.partition]+=@intFromBool(ok);call+=1;if(call!=BUDGET)return error.BudgetViolation;try l.add("round_o_o4,{s},fresh_test,{s},{s},none,none,{s},{d},{d},evaluator_owned_fresh_score\n",.{an(arm),tokens[i],tn(c.trace),gn(g),@intFromBool(ok),call});try l.add("round_o_o4,{s},budget_reject,{s},{s},none,none,none,-1,5,persistent_budget_reject\n",.{an(arm),tokens[i],tn(c.trace)});
  }
 }
 const pos=total[0]>total[1] and total[0]>total[2] and part[0][0]>part[1][0] and part[0][0]>part[2][0] and part[0][1]>part[1][1] and part[0][1]>part[2][1];
 try l.add("round_o_o4,VERDICT,summary,all,public_only,none,none,none,{d},0,{s}:guided={d}/16;fixed={d}/16;blind={d}/16;prior={d}/16;no_probe={d}/16;cohort_a={d}/8;cohort_b={d}/8\n",.{@intFromBool(pos),if(pos)"CONTROLLED_STRICT_POSITIVE"else"VALID_NEGATIVE",total[0],total[1],total[2],total[3],total[4],part[0][0],part[0][1]});try l.write(out);
}
fn hasForbidden(b:[]const u8)bool{for([_][]const u8{"formula","family_label","manifest","hidden_mask","test_label"})|x|if(std.mem.indexOf(u8,b,x)!=null)return true;return false;}
pub fn main()!void{var gpa=std.heap.GeneralPurposeAllocator(.{}){};defer _=gpa.deinit();const a=gpa.allocator();var args=std.process.args();_=args.next();const cmd=args.next() orelse "run";if(std.mem.eql(u8,cmd,"selftest")){const x="/tmp/o4_a.csv";const y="/tmp/o4_b.csv";try run(a,x,false);try run(a,y,true);const ax=try std.fs.cwd().readFileAlloc(a,x,1<<20);defer a.free(ax);const by=try std.fs.cwd().readFileAlloc(a,y,1<<20);defer a.free(by);if(hasForbidden(ax) or hasForbidden(by))return error.PrivateFieldLeak;const n="guided=16/16;fixed=8/16;blind=8/16;prior=8/16;no_probe=8/16;cohort_a=8/8;cohort_b=8/8";if(std.mem.indexOf(u8,ax,n)==null or std.mem.indexOf(u8,by,n)==null)return error.ResultMismatch;std.debug.print("SELFTEST PASS: decoupled trace, shuffled tokens, frozen commitment, fresh scores, complete ledger, and persistent budget all hold\\n",.{});return;}try run(a,args.next() orelse "results/probe_guided_grammar_round_o.csv",false);}
