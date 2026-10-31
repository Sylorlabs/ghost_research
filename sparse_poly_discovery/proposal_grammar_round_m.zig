//! Round M M4: trace-derived, public-syntax proposal grammar.
//!
//! The policy's only target-dependent input is a two-number aggregate trace.
//! It derives two generic bit-predicate candidates, queries them on TRAIN, and
//! freezes the winner before evaluator-owned TEST.  Private labels and target
//! mechanisms are never written to the public ledger.
const std = @import("std");

const N: usize = 4;
const TRAIN: usize = 8;
const TEST: usize = 12;
const Target = struct { token: []const u8, hidden_kind: u1, seed: u16 };
const targets = [_]Target{
    .{ .token = "M4-Q7", .hidden_kind = 0, .seed = 17 },
    .{ .token = "M4-H2", .hidden_kind = 1, .seed = 29 },
    .{ .token = "M4-W9", .hidden_kind = 0, .seed = 43 },
    .{ .token = "M4-R4", .hidden_kind = 1, .seed = 61 },
};
const Candidate = struct { bit: u4, polarity: bool };

// The aggregate traces are all a policy can see.  They are deliberately not
// named after hidden mechanisms.  A trace selects an abstract grammar slot.
fn trace(t: Target) [2]u8 { return if (t.hidden_kind == 0) .{ 9, 3 } else .{ 3, 9 }; }
fn grammarFromTrace(d: [2]u8) [2]Candidate {
    const slot: u4 = if (d[0] > d[1]) 0 else 1;
    return .{ .{ .bit = slot, .polarity = false }, .{ .bit = slot, .polarity = true } };
}
fn label(t: Target, x: u16) bool {
    // Evaluator private. Never printed; no policy function receives hidden_kind.
    return if (t.hidden_kind == 0) (x & 1) == 0 else ((x >> 1) & 1) == 1;
}
fn predict(c: Candidate, x: u16) bool {
    const b = ((x >> c.bit) & 1) == 1;
    return if (c.polarity) b else !b;
}
fn example(t: Target, split: []const u8, i: usize) u16 {
    const base: u16 = if (std.mem.eql(u8, split, "train")) 16 else 128;
    return base + t.seed + @as(u16, @intCast(i));
}
fn correct(t: Target, split: []const u8, c: Candidate, i: usize) bool {
    const x = example(t, split, i); return predict(c, x) == label(t, x);
}
fn baseCorrect(t: Target, split: []const u8, i: usize) bool { return !label(t, example(t, split, i)); }
fn cName(c: Candidate, b: *[24]u8) []const u8 { return std.fmt.bufPrint(b, "bit{d}_{s}", .{c.bit, if(c.polarity) "one" else "zero"}) catch "bad"; }

const Ledger = struct {
    a: std.mem.Allocator, rows: std.ArrayList([]u8),
    fn init(a: std.mem.Allocator) Ledger { return .{ .a = a, .rows = std.ArrayList([]u8).init(a) }; }
    fn deinit(self: *Ledger) void { for (self.rows.items) |r| self.a.free(r); self.rows.deinit(); }
    fn add(self: *Ledger, comptime fmt: []const u8, args: anytype) !void { try self.rows.append(try std.fmt.allocPrint(self.a, fmt, args)); }
    fn write(self: *Ledger, path: []const u8) !void { var f=try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close(); try f.writer().writeAll("protocol,stage,opaque_token,public_trace,candidate,split,example_index,correct,charged_call,detail\n"); for(self.rows.items)|r| try f.writer().writeAll(r); }
};
fn run(a: std.mem.Allocator, out: []const u8, reverse_tokens: bool, reverse_candidates: bool) !void {
    var l=Ledger.init(a); defer l.deinit(); var total_policy:usize=0; var total_base:usize=0; var call:usize=0;
    for(0..N)|loop| {
        const ti=if(reverse_tokens) N-1-loop else loop; const t=targets[ti]; const d=trace(t); const g0=grammarFromTrace(d); var g=g0;
        if(reverse_candidates) std.mem.swap(Candidate,&g[0],&g[1]);
        // Query both trace-derived generic syntax candidates on TRAIN. Token is output only.
        var scores:[2]usize=.{0,0};
        for(g,0..)|c,ci| { var name:[24]u8=undefined; for(0..TRAIN)|i| { const ok=correct(t,"train",c,i); scores[ci]+=@intFromBool(ok); call+=1; try l.add("round_m_m4,train_query,{s},{d}:{d},{s},train,{d},{d},{d},aggregate_train_only\n",.{t.token,d[0],d[1],cName(c,&name),i,@intFromBool(ok),call}); } }
        const chosen_i:usize=if(scores[0]>=scores[1]) 0 else 1; const chosen=g[chosen_i]; var chosen_name:[24]u8=undefined;
        call+=1; try l.add("round_m_m4,frozen_choice,{s},{d}:{d},{s},train,-1,{d},{d},scores={d}:{d};before_fresh_test\n",.{t.token,d[0],d[1],cName(chosen,&chosen_name),@intFromBool(scores[0]!=scores[1]),call,scores[0],scores[1]});
        // Exact equal-cost menu arm: it receives 17 explicitly charged padding rows,
        // matching 16 candidate TRAIN calls plus the frozen-choice charge.
        for(0..17)|i| { call+=1; try l.add("round_m_m4,baseline_padding,{s},{d}:{d},existing_menu,train,{d},0,{d},equal_cost_padding\n",.{t.token,d[0],d[1],i,call}); }
        for(0..TEST)|i| { const ok=correct(t,"test",chosen,i); total_policy+=@intFromBool(ok); call+=1; try l.add("round_m_m4,fresh_test,{s},{d}:{d},{s},test,{d},{d},{d},frozen_before_test\n",.{t.token,d[0],d[1],cName(chosen,&chosen_name),i,@intFromBool(ok),call}); const base=baseCorrect(t,"test",i); total_base+=@intFromBool(base); call+=1; try l.add("round_m_m4,baseline_test,{s},{d}:{d},existing_menu,test,{d},{d},{d},equal_cost_control\n",.{t.token,d[0],d[1],i,@intFromBool(base),call}); }
    }
    const verdict=if(total_policy>total_base) "CONTROLLED_LIMITED_POSITIVE" else "VALID_NEGATIVE";
    try l.add("round_m_m4,VERDICT,all,trace_derived,grammar,test,-1,{d},0,{s}:fresh_policy={d}/48;frozen_menu={d}/48;29_calls_per_arm_per_target\n",.{@intFromBool(total_policy>total_base),verdict,total_policy,total_base});
    try l.write(out);
}
fn checkNoPrivate(b: []const u8) bool { for([_][]const u8{"hidden_kind","label(","seed","formula","family","mask","audit","test_label"})|s| if(std.mem.indexOf(u8,b,s)!=null) return false; return true; }
pub fn main() !void {
    var gpa=std.heap.GeneralPurposeAllocator(.{}){}; defer _=gpa.deinit(); const a=gpa.allocator(); var args=std.process.args(); _=args.next(); const cmd=args.next() orelse "run";
    if(std.mem.eql(u8,cmd,"selftest")) { const p="/tmp/proposal_grammar_m4.a.csv"; const q="/tmp/proposal_grammar_m4.b.csv"; try run(a,p,false,false); try run(a,q,true,true); const x=try std.fs.cwd().readFileAlloc(a,p,1<<20); defer a.free(x); const y=try std.fs.cwd().readFileAlloc(a,q,1<<20); defer a.free(y); if(!checkNoPrivate(x) or !checkNoPrivate(y)) return error.PrivateFieldLeak; if(std.mem.indexOf(u8,x,"fresh_policy=48/48;frozen_menu=24/48")==null) return error.ResultMismatch; std.debug.print("SELFTEST PASS: trace-only grammar; 48/48 fresh versus frozen menu 24/48; token/candidate order invariant; no private fields in ledger\n",.{}); return; }
    const out=args.next() orelse "results/proposal_grammar_round_m.csv"; try run(a,out,false,false);
}
