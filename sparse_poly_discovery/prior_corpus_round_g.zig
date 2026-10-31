//! G2, Round G -- production-shaped prior-selector corpus builder.
//!
//! This program freezes a 20-target corpus drawn from the real 8-cell target
//! language used by `genofgen_assembled.zig`: threshold-count, mixed-residue,
//! product-ratio, and adjacency/run mechanisms.  It deliberately exports only
//! numeric failure descriptors to a later selector; target name, source group,
//! and designated prior are audit columns, never selector input.
//!
//! Build/run from sparse_poly_discovery:
//!   zig build-exe prior_corpus_round_g.zig -O ReleaseFast
//!   ./prior_corpus_round_g ../results/prior_corpus_round_g.csv
//!   ./prior_corpus_round_g selftest
const std = @import("std");
const N: usize = 20;
const S: usize = 4096;

const Prior = enum { thresh, mixr, ratio, run };
const Split = enum { train, val, heldout };
const Target = struct { name: []const u8, prior: Prior, split: Split, id: u8 };

// Three targets/prior train, one validation, one test.  The test target in
// each block has a formula variant absent from train.  The block identity is
// kept out of descriptors; it is retained only to make the frozen split
// auditable.  Seeds below are disjoint by split.
const targets = [_]Target{
    .{ .name="TE1 count_ge1_mod4_eq0", .prior=.thresh, .split=.train, .id=0 },
    .{ .name="TE2 count_ge2_mod3_eq0", .prior=.thresh, .split=.train, .id=1 },
    .{ .name="TE3 count_ge5_mod2_eq0", .prior=.thresh, .split=.train, .id=2 },
    .{ .name="TE4 count_ge1_mod3_eq1", .prior=.thresh, .split=.val, .id=3 },
    .{ .name="TE5 count_ge4_mod5_eq0", .prior=.thresh, .split=.heldout, .id=4 },
    .{ .name="ME1 sum_mod2_eq_c1", .prior=.mixr, .split=.train, .id=5 },
    .{ .name="ME2 c2_mod3_eq_inv", .prior=.mixr, .split=.train, .id=6 },
    .{ .name="ME3 sum_mod4_eq_inv", .prior=.mixr, .split=.train, .id=7 },
    .{ .name="ME4 c1_mod3_eq_c5", .prior=.mixr, .split=.val, .id=8 },
    .{ .name="ME5 sum_mod5_eq_c4", .prior=.mixr, .split=.heldout, .id=9 },
    .{ .name="RE1 c2_mul_c5_mod4_eq0", .prior=.ratio, .split=.train, .id=10 },
    .{ .name="RE2 c1_mul_c4_mod5_eq0", .prior=.ratio, .split=.train, .id=11 },
    .{ .name="RE3 c3_mul_c1_mod3_eq0", .prior=.ratio, .split=.train, .id=12 },
    .{ .name="RE4 c2_mul_c4_mod3_eq0", .prior=.ratio, .split=.val, .id=13 },
    .{ .name="RE5 c1_mul_c5_mod2_eq0", .prior=.ratio, .split=.heldout, .id=14 },
    .{ .name="RN1 run_ge2_ge4", .prior=.run, .split=.train, .id=15 },
    .{ .name="RN2 run_ge4_ge2", .prior=.run, .split=.train, .id=16 },
    .{ .name="RN3 local_max_ge2", .prior=.run, .split=.train, .id=17 },
    .{ .name="RN4 first_descent_lt3", .prior=.run, .split=.val, .id=18 },
    .{ .name="RN5 run_ge2_mod3_eq0", .prior=.run, .split=.heldout, .id=19 },
};

fn next(x: *u64) u8 { x.* = x.* *% 6364136223846793005 +% 1442695040888963407; return @truncate(x.* >> 61); }
fn countGE(g: [8]u8, v: u8) u8 { var n:u8=0; for(g)|x| { if(x>=v) n+=1; } return n; }
fn sum(g:[8]u8) u8 { var n:u8=0; for(g)|x|n+=x; return n; }
fn inv(g:[8]u8) u8 { var n:u8=0; for(g,0..)|a,i| { for(g[i+1..])|b| { if(a>b) n+=1; } } return n; }
fn maxRun(g:[8]u8,v:u8) u8 { var best:u8=0; var cur:u8=0; for(g)|x| { if(x>=v) cur+=1 else cur=0; if(cur>best)best=cur; } return best; }
fn localMax(g:[8]u8) u8 { var n:u8=0; for(1..7)|i| { if(g[i]>g[i-1] and g[i]>g[i+1]) n+=1; } return n; }
fn firstDescent(g:[8]u8) u8 { for(1..8)|i| if(g[i]<g[i-1]) return @intCast(i); return 8; }
fn label(id:u8,g:[8]u8) bool { const c1=countGE(g,1); const c2=countGE(g,2); const c3=countGE(g,3); const c4=countGE(g,4); const c5=countGE(g,5); const sm=sum(g); const iv=inv(g); return switch(id) {
    0 => c1%4==0, 1 => c2%3==0, 2 => c5%2==0, 3 => c1%3==1, 4 => c4%5==0,
    5 => sm%2==c1%2, 6 => c2%3==iv%3, 7 => sm%4==iv%4, 8 => c1%3==c5%3, 9 => sm%5==c4%5,
    10 => (c2*c5)%4==0, 11 => (c1*c4)%5==0, 12 => (c3*c1)%3==0, 13 => (c2*c4)%3==0, 14 => (c1*c5)%2==0,
    15 => maxRun(g,2)>=4, 16 => maxRun(g,4)>=2, 17 => localMax(g)>=2, 18 => firstDescent(g)<3, 19 => maxRun(g,2)%3==0,
    else => false }; }
fn priorName(p:Prior)[]const u8{return @tagName(p);} fn splitName(s:Split)[]const u8{return @tagName(s);}

fn run(writer:anytype) !void {
    try writer.print("target,split,audit_prior,seed,n,binary_rate,own_prior_acc,base_acc,benefit,exclusive_margin,d0_rate,d1_count2corr,d2_sumcorr,d3_invcorr,d4_runcorr,d5_localmaxcorr,valid\n", .{});
    var valid:usize=0;
    var desc: [N][6]f64 = undefined;
    for(targets,0..)|t, ti| {
        const seed:u64 = (switch(t.split){.train=>@as(u64,0xA11CE001),.val=>@as(u64,0xB11CE002),.heldout=>@as(u64,0xC11CE003)}) + t.id;
        var x=seed; var ones:usize=0; var agree=[_]usize{0}**5;
        var prev_y:bool=false; var flips:usize=0;
        for(0..S)|k| { var g:[8]u8=undefined; for(&g)|*v|v.*=next(&x); const y=label(t.id,g); if(y)ones+=1; if(k>0 and y!=prev_y)flips+=1; prev_y=y;
            const probes=[_]bool{countGE(g,2)>=4, sum(g)%2==0, inv(g)%2==0, maxRun(g,2)>=3, localMax(g)>=2};
            for(probes,0..)|q,j| { if(q==y) agree[j]+=1; }
        }
        const rate=@as(f64,@floatFromInt(ones))/S;
        // Exclusivity compares against probes from *other* prior classes.  A
        // run probe matching a run target is evidence for its own class, not a
        // competing prior and must not recreate F1's accidental first-hit rule.
        const probe_prior=[_]Prior{.thresh,.mixr,.mixr,.run,.run};
        var best_other:f64=0; for(agree,0..)|a,j| { if(probe_prior[j]!=t.prior) { const z=@as(f64,@floatFromInt(a))/S; if(z>best_other)best_other=z; } }
        const own:f64=1.0; // exact, executable member in the designated production grammar
        const base=@max(rate,1-rate); const benefit=own-base; const margin=own-best_other;
        const ok=rate>0.05 and rate<0.95 and own==1.0 and benefit>=0.20 and margin>=0.05;
        if(ok)valid+=1;
        desc[ti] = .{rate,@as(f64,@floatFromInt(agree[0]))/S,@as(f64,@floatFromInt(agree[1]))/S,@as(f64,@floatFromInt(agree[2]))/S,@as(f64,@floatFromInt(agree[3]))/S,@as(f64,@floatFromInt(flips))/S};
        try writer.print("{s},{s},{s},0x{X:0>16},{d},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{s}\n", .{t.name,splitName(t.split),priorName(t.prior),seed,S,rate,own,base,benefit,margin,rate,@as(f64,@floatFromInt(agree[0]))/S,@as(f64,@floatFromInt(agree[1]))/S,@as(f64,@floatFromInt(agree[2]))/S,@as(f64,@floatFromInt(agree[3]))/S,@as(f64,@floatFromInt(flips))/S,if(ok)"pass" else "FAIL"});
    }
    // Independent train-to-unseen descriptor-distance guard.  Standardize
    // using train only, then require every validation/heldout point to be at
    // least 0.05 Euclidean units from every train point.  This detects exact
    // descriptor duplication without making distance a performance target.
    var mu=[_]f64{0}**6; var ntr:usize=0;
    for(targets,0..)|t,i| { if(t.split==.train) { ntr+=1; for(0..6)|j| { mu[j]+=desc[i][j]; } } }
    for(0..6)|j| { mu[j]/=@as(f64,@floatFromInt(ntr)); }
    var sd=[_]f64{0}**6;
    for(targets,0..)|t,i| { if(t.split==.train) { for(0..6)|j| { const d=desc[i][j]-mu[j]; sd[j]+=d*d; } } }
    for(0..6)|j| { sd[j]=@sqrt(sd[j]/@as(f64,@floatFromInt(ntr))); }
    var min_dist: f64=1e9;
    for(targets,0..)|a,i| { if(a.split!=.train) { for(targets,0..)|b,k| { if(b.split==.train) { var d2:f64=0; for(0..6)|j| { const z=(desc[i][j]-desc[k][j])/@max(sd[j],0.0001); d2+=z*z; } min_dist=@min(min_dist,@sqrt(d2)); } } } }
    const distance_ok=min_dist>=0.05;
    try writer.print("__VALIDITY__,frozen_split,-,-,-,-,-,-,-,-,-,-,-,-,-,{d:.6},{s}\n", .{min_dist,if(distance_ok)"pass" else "FAIL"});
    if(valid!=N or !distance_ok) return error.InvalidCorpus;
}
pub fn main() !void { var args=std.process.args(); _=args.next(); const a=args.next() orelse "../results/prior_corpus_round_g.csv"; if(std.mem.eql(u8,a,"selftest")){try run(std.io.getStdOut().writer()); return;} const f=try std.fs.cwd().createFile(a,.{}); defer f.close(); try run(f.writer()); }
