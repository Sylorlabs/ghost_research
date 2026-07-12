//! H1 Round H -- failure-representation audit.
//!
//! Uses the frozen G2 target split (12 train / 4 validation / 4 heldout) and
//! exposes only response statistics of a target label to a fixed, target-blind
//! probe bank.  IDs, names, formula text, source block, and grammar labels are
//! audit/evaluator fields only.  Descriptor-set choice is made on validation;
//! heldout rows are printed once after that choice is frozen.
const std = @import("std");
const N: usize = 20;
const S: usize = 4096;
const MAXD: usize = 16;
const Prior = enum(u8) { thresh, mixr, ratio, run };
const Split = enum { train, val, heldout };
const Target = struct { name: []const u8, prior: Prior, split: Split, id: u8 };
const targets = [_]Target{
    .{ .name="TE1", .prior=.thresh, .split=.train, .id=0 }, .{ .name="TE2", .prior=.thresh, .split=.train, .id=1 }, .{ .name="TE3", .prior=.thresh, .split=.train, .id=2 }, .{ .name="TE4", .prior=.thresh, .split=.val, .id=3 }, .{ .name="TE5", .prior=.thresh, .split=.heldout, .id=4 },
    .{ .name="ME1", .prior=.mixr, .split=.train, .id=5 }, .{ .name="ME2", .prior=.mixr, .split=.train, .id=6 }, .{ .name="ME3", .prior=.mixr, .split=.train, .id=7 }, .{ .name="ME4", .prior=.mixr, .split=.val, .id=8 }, .{ .name="ME5", .prior=.mixr, .split=.heldout, .id=9 },
    .{ .name="RE1", .prior=.ratio, .split=.train, .id=10 }, .{ .name="RE2", .prior=.ratio, .split=.train, .id=11 }, .{ .name="RE3", .prior=.ratio, .split=.train, .id=12 }, .{ .name="RE4", .prior=.ratio, .split=.val, .id=13 }, .{ .name="RE5", .prior=.ratio, .split=.heldout, .id=14 },
    .{ .name="RN1", .prior=.run, .split=.train, .id=15 }, .{ .name="RN2", .prior=.run, .split=.train, .id=16 }, .{ .name="RN3", .prior=.run, .split=.train, .id=17 }, .{ .name="RN4", .prior=.run, .split=.val, .id=18 }, .{ .name="RN5", .prior=.run, .split=.heldout, .id=19 },
};
fn next(x: *u64) u8 { x.* = x.* *% 6364136223846793005 +% 1442695040888963407; return @truncate(x.* >> 61); }
fn countGE(g:[8]u8,v:u8)u8 { var n:u8=0; for(g)|x| { if(x>=v) n+=1; } return n; }
fn sum(g:[8]u8)u8 { var n:u8=0; for(g)|x| n+=x; return n; }
fn inv(g:[8]u8)u8 { var n:u8=0; for(g,0..)|a,i| { for(g[i+1..])|b| { if(a>b) n+=1; } } return n; }
fn maxRun(g:[8]u8,v:u8)u8 { var best:u8=0; var cur:u8=0; for(g)|x| { if(x>=v)cur+=1 else cur=0; if(cur>best)best=cur; } return best; }
fn localMax(g:[8]u8)u8 { var n:u8=0; for(1..7)|i| { if(g[i]>g[i-1] and g[i]>g[i+1]) n+=1; } return n; }
fn firstDescent(g:[8]u8)u8 { for(1..8)|i| if(g[i]<g[i-1])return @intCast(i); return 8; }
fn rises(g:[8]u8)u8 { var n:u8=0; for(1..8)|i| { if(g[i]>g[i-1]) n+=1; } return n; }
fn adjacentGE(g:[8]u8,v:u8)u8 { var n:u8=0; for(1..8)|i| { if(g[i]>=v and g[i-1]>=v) n+=1; } return n; }
fn label(id:u8,g:[8]u8)bool { const c1=countGE(g,1); const c2=countGE(g,2); const c3=countGE(g,3); const c4=countGE(g,4); const c5=countGE(g,5); const sm=sum(g); const iv=inv(g); return switch(id) {
    0=>c1%4==0,1=>c2%3==0,2=>c5%2==0,3=>c1%3==1,4=>c4%5==0,5=>sm%2==c1%2,6=>c2%3==iv%3,7=>sm%4==iv%4,8=>c1%3==c5%3,9=>sm%5==c4%5,
    10=>(c2*c5)%4==0,11=>(c1*c4)%5==0,12=>(c3*c1)%3==0,13=>(c2*c4)%3==0,14=>(c1*c5)%2==0,15=>maxRun(g,2)>=4,16=>maxRun(g,4)>=2,17=>localMax(g)>=2,18=>firstDescent(g)<3,19=>maxRun(g,2)%3==0,else=>false}; }
// Fixed, generic response probes. None includes target-specific constants,
// names, or the designated grammar.  0..5 reproduce the G2 cheap bank;
// 6..15 add residual/ordering/adjacency observations.
fn probe(j:usize,g:[8]u8)bool { return switch(j) {
    0=>countGE(g,2)>=4, 1=>sum(g)%2==0, 2=>inv(g)%2==0, 3=>maxRun(g,2)>=3, 4=>localMax(g)>=2, 5=>firstDescent(g)<4,
    6=>countGE(g,1)%3==0, 7=>countGE(g,4)%2==0, 8=>sum(g)%3==0, 9=>inv(g)%3==0,
    10=>rises(g)%2==0, 11=>firstDescent(g)%2==0, 12=>adjacentGE(g,2)>=2, 13=>adjacentGE(g,4)>=1,
    14=>(countGE(g,2)*countGE(g,5))%2==0, 15=>(sum(g)+inv(g))%3==0,
    else=>false }; }
fn pname(p:Prior)[]const u8{return @tagName(p);} fn sname(s:Split)[]const u8{return @tagName(s);}
const Contract = struct { name: []const u8, dims: []const usize };
const cheap=[_]usize{0,1,2,3,4,5};
const residual=[_]usize{0,1,2,3,4,5,6,7,8,9};
const orientation=[_]usize{0,1,2,3,4,5,10,11,12,13};
const full=[_]usize{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
const contracts=[_]Contract{ .{.name="cheap6",.dims=&cheap}, .{.name="residual10",.dims=&residual}, .{.name="orientation10",.dims=&orientation}, .{.name="full16",.dims=&full} };
fn dist(a:[MAXD]f64,b:[MAXD]f64, dims:[]const usize, sd:[MAXD]f64)f64 { var z:f64=0; for(dims)|j|{const q=(a[j]-b[j])/sd[j];z+=q*q;} return z; }
fn choose(row:usize, desc:[N][MAXD]f64, c:Contract, sd:[MAXD]f64)Prior { var best:f64=1e99; var out:Prior=.thresh; for(targets,0..)|q,qi| if(q.split==.train) {const d=dist(desc[row],desc[qi],c.dims,sd);if(d<best){best=d;out=q.prior;}}; return out; }
fn acc(split:Split, desc:[N][MAXD]f64,c:Contract,sd:[MAXD]f64)usize { var n:usize=0; for(targets,0..)|t,i| { if(t.split==split and choose(i,desc,c,sd)==t.prior) n+=1; } return n; }
fn run(w:anytype)!void {
    var desc:[N][MAXD]f64=undefined;
    for(targets,0..)|t,ti| { var seed:u64=(switch(t.split){.train=>@as(u64,0xA11CE001),.val=>@as(u64,0xB11CE002),.heldout=>@as(u64,0xC11CE003)})+t.id; var agree=[_]usize{0}**MAXD;
        for(0..S)|_| { var g:[8]u8=undefined; for(&g)|*v| v.*=next(&seed); const y=label(t.id,g); for(0..MAXD)|j| { if(probe(j,g)==y) agree[j]+=1; } }
        for(0..MAXD)|j|desc[ti][j]=@as(f64,@floatFromInt(agree[j]))/@as(f64,S);
    }
    var sd=[_]f64{0}**MAXD;var mu=[_]f64{0}**MAXD;var nt:usize=0;
    for (targets, 0..) |t, i| {
        if (t.split == .train) {
            nt += 1;
            for (0..MAXD) |j| mu[j] += desc[i][j];
        }
    }
    for(0..MAXD)|j|mu[j]/=@as(f64,@floatFromInt(nt));
    for (targets, 0..) |t, i| {
        if (t.split == .train) {
            for (0..MAXD) |j| { const x=desc[i][j]-mu[j]; sd[j]+=x*x; }
        }
    }
    for(0..MAXD)|j|sd[j]=@max(@sqrt(sd[j]/@as(f64,@floatFromInt(nt))),0.0001);
    // Candidate contract is selected strictly by validation; ties go to fewer dimensions.
    var chosen:usize=0;var bestval:usize=0;
    try w.print("record,contract,split,target_audit_only,truth_audit_only,predicted_prior,correct,dims,validity\n",.{});
    for (contracts, 0..) |c, ci| {
        const va=acc(.val,desc,c,sd);
        if(va>bestval){bestval=va;chosen=ci;}
        try w.print("ABLATION,{s},validation,-,-,-,{d}/4,{d},pass\n",.{c.name,va,c.dims.len});
    }
    const selected=contracts[chosen];
    var min_dist:f64=1e99;
    for (targets, 0..) |a,i| {
        if(a.split!=.train) for (targets, 0..) |b,k| {
            if(b.split==.train) min_dist=@min(min_dist,@sqrt(dist(desc[i],desc[k],selected.dims,sd)));
        };
    }
    const valid_split=nt==12;const valid_distance=min_dist>=0.05;
    for (targets, 0..) |t,i| {
        if(t.split!=.train) {
            const p=choose(i,desc,selected,sd);
            const correctness:usize=if(p==t.prior) 1 else 0;
            const state: []const u8 = if(valid_split and valid_distance) "pass" else "FAIL";
            try w.print("TARGET,{s},{s},{s},{s},{s},{d},{d},{s}\n",.{selected.name,sname(t.split),t.name,pname(t.prior),pname(p),correctness,selected.dims.len,state});
        }
    }
    const state: []const u8 = if(valid_split and valid_distance) "pass" else "FAIL";
    try w.print("SUMMARY,{s},heldout,-,-,-,{d}/4,{d},{s}\n",.{selected.name,acc(.heldout,desc,selected,sd),selected.dims.len,state});
    try w.print("GATES,{s},train12_distance,-,-,-,{d:.6},{d},{s}\n",.{selected.name,min_dist,selected.dims.len,state});
    if(!valid_split or !valid_distance)return error.InvalidProtocol;
}
pub fn main()!void{var a=std.process.args();_=a.next();const path=a.next()orelse"../results/failure_repr_round_h.csv";if(std.mem.eql(u8,path,"selftest")){try run(std.io.getStdOut().writer());return;}const f=try std.fs.cwd().createFile(path,.{});defer f.close();try run(f.writer());}
