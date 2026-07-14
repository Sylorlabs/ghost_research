//! Round N N3: frozen failure-memory proposer.
//!
//! A policy receives a shuffled ledger of old public diagnostic/candidate
//! outcomes and the aggregate diagnostic of a new opaque case.  It never sees
//! the case token, mechanism, or held-out score while choosing a candidate.
const std = @import("std");

const C: usize = 3;
const H: usize = 24;
const Q: usize = 12;

// `diag` is intentionally not a tool name: it is an aggregate residual bin
// published by the evaluator.  There is no useful fixed direction/order rule.
const History = struct { diag: u2, candidate: u2, observed: bool };
const old = [_]History{
    .{ .diag=0,.candidate=0,.observed=true }, .{ .diag=0,.candidate=1,.observed=false }, .{ .diag=0,.candidate=2,.observed=false },
    .{ .diag=0,.candidate=0,.observed=true }, .{ .diag=0,.candidate=1,.observed=false }, .{ .diag=0,.candidate=2,.observed=false },
    .{ .diag=1,.candidate=0,.observed=false }, .{ .diag=1,.candidate=1,.observed=true }, .{ .diag=1,.candidate=2,.observed=false },
    .{ .diag=1,.candidate=0,.observed=false }, .{ .diag=1,.candidate=1,.observed=true }, .{ .diag=1,.candidate=2,.observed=false },
    .{ .diag=2,.candidate=0,.observed=false }, .{ .diag=2,.candidate=1,.observed=false }, .{ .diag=2,.candidate=2,.observed=true },
    .{ .diag=2,.candidate=0,.observed=false }, .{ .diag=2,.candidate=1,.observed=false }, .{ .diag=2,.candidate=2,.observed=true },
    .{ .diag=3,.candidate=0,.observed=true }, .{ .diag=3,.candidate=1,.observed=false }, .{ .diag=3,.candidate=2,.observed=false },
    .{ .diag=3,.candidate=0,.observed=true }, .{ .diag=3,.candidate=1,.observed=false }, .{ .diag=3,.candidate=2,.observed=false },
};
const Query = struct { token: []const u8, diag: u2, winner: u2 };
// `winner` is evaluator-private: chooser() is never passed a Query.
const queries = [_]Query{
    .{.token="N3-A9",.diag=2,.winner=2}, .{.token="N3-K4",.diag=0,.winner=0}, .{.token="N3-R7",.diag=3,.winner=0},
    .{.token="N3-B1",.diag=1,.winner=1}, .{.token="N3-P8",.diag=0,.winner=0}, .{.token="N3-C6",.diag=2,.winner=2},
    .{.token="N3-W2",.diag=1,.winner=1}, .{.token="N3-D5",.diag=3,.winner=0}, .{.token="N3-H3",.diag=2,.winner=2},
    .{.token="N3-L0",.diag=0,.winner=0}, .{.token="N3-M9",.diag=1,.winner=1}, .{.token="N3-X1",.diag=3,.winner=0},
};

const Ledger = struct {
    a: std.mem.Allocator, rows: std.ArrayList([]u8),
    fn init(a: std.mem.Allocator) Ledger { return .{.a=a,.rows=std.ArrayList([]u8).init(a)}; }
    fn deinit(self:*Ledger) void { for(self.rows.items)|r| self.a.free(r); self.rows.deinit(); }
    fn add(self:*Ledger, comptime f:[]const u8, x:anytype)!void { try self.rows.append(try std.fmt.allocPrint(self.a,f,x)); }
    fn write(self:*Ledger,path:[]const u8)!void { var file=try std.fs.cwd().createFile(path,.{.truncate=true}); defer file.close(); try file.writer().writeAll("protocol,stage,opaque_token,public_diagnostic,candidate,observed_score,rank,charged_call,detail\n"); for(self.rows.items)|r| try file.writer().writeAll(r); }
};
fn candidateName(c:usize) []const u8 { return switch(c){0=>"primitive_a",1=>"primitive_b",else=>"primitive_c"}; }
fn score(q: Query, c:usize) bool { return q.winner == c; } // evaluator-only call

// Learns table entries from raw history.  No query token appears here.
fn choose(diag:u2, reverse_history:bool) usize {
    var wins:[4][C]usize = .{.{0,0,0},.{0,0,0},.{0,0,0},.{0,0,0}};
    var trials:[4][C]usize = .{.{0,0,0},.{0,0,0},.{0,0,0},.{0,0,0}};
    for(0..H)|k| { const i=if(reverse_history) H-1-k else k; const h=old[i]; wins[h.diag][h.candidate]+=@intFromBool(h.observed); trials[h.diag][h.candidate]+=1; }
    var best:usize=0; var best_w:usize=0;
    for(0..C)|c| { // integer comparison avoids a hand-supplied probability mapping
        const w=wins[diag][c]; const n=trials[diag][c];
        if (c==0 or w*trials[diag][best] > best_w*n) { best=c; best_w=w; }
    }
    return best;
}
fn familyPrior() usize { // globally, a tie; deterministic public tie-break only
    var totals:[C]usize=.{0,0,0}; for(old)|h| totals[h.candidate]+=@intFromBool(h.observed);
    var best:usize=0;
    for(1..C)|c| { if(totals[c]>totals[best]) best=c; }
    return best;
}
fn blind(loop:usize) usize { return loop%C; }

fn run(a:std.mem.Allocator,out:[]const u8,reverse_history:bool,reverse_queries:bool)!void {
    var l=Ledger.init(a); defer l.deinit(); var call:usize=0;
    // The pre-freeze memory ledger is explicit and order-shufflable.
    for(0..H)|k| { const i=if(reverse_history) H-1-k else k; const h=old[i]; call+=1; try l.add("round_n_n3,history_row,history-{d},d{d},{s},{d},-1,{d},pre_freeze_raw_outcome\n",.{i,h.diag,candidateName(h.candidate),@intFromBool(h.observed),call}); }
    var mem_total:usize=0; var prior_total:usize=0; var blind_total:usize=0;
    for(0..Q)|loop| {
        const qi=if(reverse_queries) Q-1-loop else loop; const q=queries[qi];
        const m=choose(q.diag,reverse_history); const p=familyPrior(); const b=blind(loop);
        // Diagnostic row carries no query identifier into chooser; token is ledger-only.
        call+=1; try l.add("round_n_n3,public_diagnostic,{s},d{d},none,-1,-1,{d},aggregate_only;not_policy_id\n",.{q.token,q.diag,call});
        const mo=score(q,m); call+=1; mem_total+=@intFromBool(mo); try l.add("round_n_n3,frozen_memory_choice,{s},d{d},{s},{d},1,{d},history_ranked_before_outcome\n",.{q.token,q.diag,candidateName(m),@intFromBool(mo),call});
        const po=score(q,p); call+=1; prior_total+=@intFromBool(po); try l.add("round_n_n3,family_prior_control,{s},d{d},{s},{d},2,{d},global_history_only\n",.{q.token,q.diag,candidateName(p),@intFromBool(po),call});
        const bo=score(q,b); call+=1; blind_total+=@intFromBool(bo); try l.add("round_n_n3,blind_control,{s},d{d},{s},{d},3,{d},round_robin_no_history\n",.{q.token,q.diag,candidateName(b),@intFromBool(bo),call});
    }
    const positive=mem_total>prior_total and mem_total>blind_total;
    try l.add("round_n_n3,VERDICT,all,aggregate,history_memory,{d},-1,0,{s}:memory={d}/12;family_prior={d}/12;blind={d}/12\n",.{@intFromBool(positive),if(positive) "CONTROLLED_LIMITED_POSITIVE" else "VALID_NEGATIVE",mem_total,prior_total,blind_total});
    try l.write(out);
}
fn containsForbidden(b:[]const u8) bool { for([_][]const u8{"winner","hidden","formula","family_label","mask","audit","test_label"})|s| if(std.mem.indexOf(u8,b,s)!=null) return true; return false; }
pub fn main() !void {
    var gpa=std.heap.GeneralPurposeAllocator(.{}){}; defer _=gpa.deinit(); const a=gpa.allocator(); var args=std.process.args(); _=args.next(); const cmd=args.next() orelse "run";
    if(std.mem.eql(u8,cmd,"selftest")) { const x="/tmp/n3_memory_a.csv"; const y="/tmp/n3_memory_b.csv"; try run(a,x,false,false); try run(a,y,true,true); const ax=try std.fs.cwd().readFileAlloc(a,x,1<<20); defer a.free(ax); const by=try std.fs.cwd().readFileAlloc(a,y,1<<20); defer a.free(by); if(containsForbidden(ax) or containsForbidden(by)) return error.PrivateFieldLeak; if(std.mem.indexOf(u8,ax,"memory=12/12;family_prior=6/12;blind=4/12")==null or std.mem.indexOf(u8,by,"memory=12/12;family_prior=6/12;blind=4/12")==null) return error.ResultMismatch; std.debug.print("SELFTEST PASS: shuffled history/query order preserves 12/12 memory > 6/12 family prior > 4/12 blind; opaque IDs are ledger-only; no forbidden fields\n",.{}); return; }
    const out=args.next() orelse "results/failure_memory_proposer_round_n.csv"; try run(a,out,false,false);
}
