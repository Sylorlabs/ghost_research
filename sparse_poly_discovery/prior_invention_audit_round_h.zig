//! H4: adversarial audit of the G4/H3 directed-partition invention claim.
//! The oracle lives only in the data generator. `selectDirected` receives
//! labelled samples, never a target name, formula, family, pivot, or residue.
const std = @import("std");
const Cells: usize = 8;
const N: usize = 2000;
const TrainEnd: usize = 1000;
const ValEnd: usize = 1500;
const Budget: usize = 1270; // every legal directed candidate exactly once
const Trials: usize = 128;
const Sample = struct { g: [Cells]u8, y: bool };
const Candidate = struct { mask: u8, modulus: u8, residue: u8 };
const Spec = struct { id: []const u8, seed: u64, mask: u8, modulus: u8, residue: u8, heldout: bool };

// These are generator-only specifications. They are intentionally not values
// in the inference API; their varied pivots/masks/moduli test robustness.
const specs = [_]Spec{
    .{ .id="single_p3_m3_r1_s1", .seed=0xB401, .mask=0x08, .modulus=3, .residue=1, .heldout=false },
    .{ .id="single_p3_m3_r1_s2", .seed=0xB402, .mask=0x08, .modulus=3, .residue=1, .heldout=false },
    .{ .id="single_p5_m3_r2", .seed=0xB403, .mask=0x20, .modulus=3, .residue=2, .heldout=false },
    .{ .id="single_p1_m2_r0", .seed=0xB404, .mask=0x02, .modulus=2, .residue=0, .heldout=false },
    // Unseen structural variant: a two-cell directed partition, not a pivot.
    .{ .id="heldout_pair_1_5_m2_r0", .seed=0xB4A5, .mask=0x22, .modulus=2, .residue=0, .heldout=true },
};
fn count(g: [Cells]u8, mask: u8) usize { var n: usize = 0; for (0..Cells) |i| for (0..Cells) |j| { const bi: u8 = @as(u8,1) << @intCast(i); const bj: u8 = @as(u8,1) << @intCast(j); if ((mask & bi)!=0 and (mask & bj)==0 and g[i]>g[j]) n += 1; }; return n; }
fn pred(c: Candidate, x: Sample) bool { return count(x.g,c.mask) % c.modulus == c.residue; }
fn make(alloc: std.mem.Allocator, s: Spec) ![]Sample { var p=std.Random.DefaultPrng.init(s.seed); const r=p.random(); const xs=try alloc.alloc(Sample,N); for(xs)|*x| { for(0..Cells)|i| x.g[i]=r.intRangeAtMost(u8,0,5); x.y=count(x.g,s.mask)%s.modulus==s.residue; } return xs; }
fn acc(c: Candidate, xs: []const Sample, lo: usize, hi: usize) f64 { var ok:usize=0; for(xs[lo..hi])|x| { if(pred(c,x)==x.y) ok+=1; } return @as(f64,@floatFromInt(ok))/@as(f64,@floatFromInt(hi-lo)); }
fn threshold(x: Sample, t:u8,m:u8,r:u8) bool { var n:usize=0; for(x.g)|v| { if(v>=t)n+=1; } return n%m==r; }
fn fixedBest(xs: []const Sample, lo:usize,hi:usize) f64 { var b:f64=0; for(1..6)|tt| { for(2..4)|mm| { for(0..mm)|rr| { var ok:usize=0; for(xs[lo..hi])|x| { if(threshold(x,@intCast(tt),@intCast(mm),@intCast(rr))==x.y)ok+=1; } b=@max(b,@as(f64,@floatFromInt(ok))/@as(f64,@floatFromInt(hi-lo))); } } } return b; }
fn singletonProbe(xs: []const Sample) f64 { var b:f64=0; for(0..Cells)|i| { for(2..4)|m| { for(0..m)|r| { b=@max(b,acc(.{.mask=@as(u8,1)<<@intCast(i),.modulus=@intCast(m),.residue=@intCast(r)},xs,TrainEnd,ValEnd)); } } } return b; }
fn selectDirected(xs: []const Sample) Candidate { var best=Candidate{.mask=1,.modulus=2,.residue=0}; var ba:f64=-1; for(1..255)|mask| { for(2..4)|m| { for(0..m)|r| { const c=Candidate{.mask=@intCast(mask),.modulus=@intCast(m),.residue=@intCast(r)}; const a=acc(c,xs,TrainEnd,ValEnd); if(a>ba){ba=a;best=c;} } } } return best; }
fn uniform(r: std.Random) Candidate { const ix=r.intRangeLessThan(usize,0,Budget); const mask:u8=@intCast(ix/5+1); const q=ix%5; return .{.mask=mask,.modulus=if(q<2)2 else 3,.residue=@intCast(if(q<2)q else q-2)}; }
fn mainRun(out:anytype, alloc:std.mem.Allocator,s:Spec)!void { const xs=try make(alloc,s); var pos:usize=0;for(xs)|x| { if(x.y)pos+=1; } const base=@as(f64,@floatFromInt(pos))/N; const fixed=fixedBest(xs,TrainEnd,ValEnd); const probe=singletonProbe(xs); const sig=fixed<0.75 and probe>=0.75; const chosen=selectDirected(xs); const val=acc(chosen,xs,TrainEnd,ValEnd);const test_acc=acc(chosen,xs,ValEnd,N); var hit:usize=0;var mean:f64=0;var max:f64=0; for(0..Trials)|t| { var p=std.Random.DefaultPrng.init(s.seed ^ (0x9E3779B97F4A7C15 *% @as(u64,@intCast(t+1))));const r=p.random();var b:f64=0;for(0..Budget)|_| { b=@max(b,acc(uniform(r),xs,TrainEnd,ValEnd)); } mean+=b;max=@max(max,b);if(b>=0.999)hit+=1;try out.print("{s},random_trial,{d},{d},{d:.4},,,,,raw_equal_budget\n",.{s.id,t,Budget,b}); } mean/=Trials; const rate=@as(f64,@floatFromInt(hit))/Trials; const gate=base>0.10 and base<0.90 and sig and val>=0.99 and test_acc>=0.99 and test_acc>fixed and rate<0.95; try out.print("{s},summary,{d},{d},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},mask=0x{X:0>2};m={d};r={d};base={d:.4};probe={d:.4};random_max={d:.4};heldout={s};{s}\n",.{s.id,Trials,Budget,fixed,probe,val,test_acc,rate,chosen.mask,chosen.modulus,chosen.residue,base,probe,max,if(s.heldout)"yes" else "no",if(gate)"PASS" else "FAIL"}); }
pub fn main() !void { var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator);defer arena.deinit();const f=try std.fs.cwd().createFile("../results/prior_invention_audit_round_h.csv",.{.truncate=true});defer f.close();var out=f.writer();try out.writeAll("condition,arm,trial,candidate_evaluations,validation_accuracy,fixed_validation,singleton_probe,proposer_validation,random_exact_rate,detail\n");for(specs)|s|try mainRun(out,arena.allocator(),s); }
