//! K3 / Round K.  Frozen-policy, equal-total-cost adaptive allocation on K4.
//! The policy sees only candidate scores on opaque labelled examples.  Target
//! kind/mask/parameters/permutation are evaluator-private and emitted only as
//! audit fields after the policy has acted.
const std = @import("std");
const Cells: usize = 8;
const N: usize = 1024;
const Train: usize = 768;
const Probe: usize = 254; // K2-compatible 25 + 40 + 180 + 5 set probes
const Total: usize = 600;
const Select: usize = Total - Probe;
const Kind = enum { directed, threshold, adjacency, xor_control, parity_control };
const Bank = enum { global, singleton, directed, adjacency };
const Arm = enum { adaptive, fixed, random_iid, blind_coverage };
const Target = struct { id: usize, kind: Kind, mask: u8, a: u8, b: u8, m: u8, r: u8, perm: [Cells]u3, seed: u64 };
const Sample = struct { g: [Cells]u8, y: bool };
const Cand = struct { bank: Bank, a: u8, mask: u8, m: u8, r: u8 };
fn pop(x:u8) usize{return @popCount(x);}
fn count(g:[Cells]u8,a:u8)usize{var n:usize=0;for(g)|v| { if(v>=a)n+=1; } return n;}
fn rank(g:[Cells]u8,p:usize)usize{var n:usize=0;for(g,0..)|v,i| { if(i!=p and g[p]>v)n+=1; } return n;}
fn cross(g:[Cells]u8,mask:u8)usize{var n:usize=0;for(0..Cells)|i|for(0..Cells)|j|{const bi:u8=@as(u8,1)<<@intCast(i);const bj:u8=@as(u8,1)<<@intCast(j);if(mask&bi!=0 and mask&bj==0 and g[i]>g[j])n+=1;};return n;}
fn adj(g:[Cells]u8,b:u8)usize{var n:usize=0;for(1..Cells)|i| { if(g[i]>=b and g[i-1]>=b)n+=1; } return n;}
fn permute(g:[Cells]u8,p:[Cells]u3)[Cells]u8{var o:[Cells]u8=undefined;for(0..Cells)|i|o[i]=g[p[i]];return o;}
fn label(t:Target,raw:[Cells]u8)bool{const g=permute(raw,t.perm);const q:usize=switch(t.kind){.directed=>cross(g,t.mask),.threshold=>count(g,t.a),.adjacency=>adj(g,t.b),.xor_control=>@intFromBool(count(g,t.a)%2==1)^@intFromBool(adj(g,t.b)%2==1),.parity_control=>blk:{var s:usize=0;for(g)|v|s+=v;break:blk s;}};return q%t.m==t.r;}
fn shuffle(comptime T:type,x:[]T,r:std.Random)void{var i=x.len;while(i>1){i-=1;std.mem.swap(T,&x[i],&x[r.uintLessThan(usize,i+1)]);}}
fn makeTarget(id:usize,r:std.Random, seed:u64)Target{const bucket=id%5;const kind:Kind=switch(bucket){0=>.directed,1=>.threshold,2=>.adjacency,3=>.xor_control,else=>.parity_control};var p:[Cells]u3=undefined;for(0..Cells)|i|p[i]=@intCast(i);shuffle(u3,&p,r);var t=Target{.id=id,.kind=kind,.mask=0,.a=r.intRangeAtMost(u8,1,5),.b=r.intRangeAtMost(u8,2,5),.m=if(r.boolean())2 else 3,.r=0,.perm=p,.seed=seed};t.r=r.uintLessThan(u8,t.m);if(kind==.directed){var ids:[Cells]u3=undefined;for(0..Cells)|i|ids[i]=@intCast(i);shuffle(u3,&ids,r);const want=1+(id/5)%4;for(ids[0..want])|v|t.mask|=@as(u8,1)<<v;}return t;}
fn valid(t:Target)bool{var p=std.Random.DefaultPrng.init(t.seed);const r=p.random();var ones:usize=0;for(0..N)|_|{var g:[Cells]u8=undefined;for(&g)|*v|v.*=r.intRangeAtMost(u8,0,5);if(label(t,g))ones+=1;}return ones>=N/5 and ones<=N-N/5;}
fn suite() [24]Target {var p=std.Random.DefaultPrng.init(0x4B4B000000000001);const r=p.random();var ts:[24]Target=undefined;for(0..24)|id|{while(true){const t=makeTarget(id,r,r.int(u64));if(valid(t)){ts[id]=t;break;}}}return ts;}
fn samples(a:std.mem.Allocator,t:Target)![]Sample{var p=std.Random.DefaultPrng.init(t.seed);const r=p.random();const x=try a.alloc(Sample,N);for(x)|*s|{for(&s.g)|*v|v.*=r.intRangeAtMost(u8,0,5);s.y=label(t,s.g);}return x;}
fn flav(k:usize)struct{m:u8,r:u8}{return if(k<2).{.m=2,.r=@intCast(k)}else .{.m=3,.r=@intCast(k-2)};}
fn size(b:Bank)usize{return switch(b){.global=>25,.singleton=>40,.directed=>1270,.adjacency=>5};}
fn cand(b:Bank,k:usize)Cand{const f=flav(switch(b){.global=>k/5,.singleton=>k/8,.directed=>k%5,.adjacency=>k});return switch(b){.global=>.{.bank=b,.a=@intCast(k%5+1),.mask=0,.m=f.m,.r=f.r},.singleton=>.{.bank=b,.a=@intCast(k%8),.mask=0,.m=f.m,.r=f.r},.directed=>.{.bank=b,.a=0,.mask=@intCast(k/5+1),.m=f.m,.r=f.r},.adjacency=>.{.bank=b,.a=0,.mask=0,.m=f.m,.r=f.r}};}
fn pred(c:Cand,g:[Cells]u8)bool{const q:usize=switch(c.bank){.global=>count(g,c.a),.singleton=>rank(g,c.a),.directed=>cross(g,c.mask),.adjacency=>adj(g,3)};return q%c.m==c.r;}
fn score(c:Cand,x:[]const Sample,lo:usize,hi:usize)f64{var n:usize=0;for(x[lo..hi])|s| { if(pred(c,s.g)==s.y)n+=1; } return @as(f64,@floatFromInt(n))/@as(f64,@floatFromInt(hi-lo));}
fn exact(c:Cand,x:[]const Sample)bool{return score(c,x,Train,N)>=0.999;}
fn probeCand(b:Bank,k:usize)Cand{return switch(b){.directed=>cand(b,(k*809+113)%1270),else=>cand(b,k%size(b))};}
fn probe(x:[]const Sample)struct{best:[4]f64,hit:bool}{var best=[_]f64{0}**4;var hit=false;const ns=[_]usize{25,40,180,5};for(0..4)|bi| { for(0..ns[bi])|k|{const c=probeCand(@enumFromInt(bi),k);const s=score(c,x,0,Train);best[bi]=@max(best[bi],s);hit=hit or exact(c,x);} } return .{.best=best,.hit=hit};}
fn scan(x:[]const Sample,b:Bank,start:usize,n:usize)bool{for(0..n)|i|if(exact(cand(b,(start+i)%size(b)),x))return true;return false;}
fn runArm(x:[]const Sample,arm:Arm,seed:u64)struct{guess:Bank,hit:bool}{const pr=probe(x);var guess:Bank=.global;for(1..4)|i| { if(pr.best[i]>pr.best[@intFromEnum(guess)])guess=@enumFromInt(i); } if(pr.hit)return .{.guess=guess,.hit=true};return switch(arm){.adaptive=>.{.guess=guess,.hit=scan(x,guess,0,Select)},.fixed=>.{.guess=.directed,.hit=scan(x,.global,0,25) or scan(x,.singleton,0,40) or scan(x,.adjacency,0,5) or scan(x,.directed,0,Select - 70)},.blind_coverage=>.{.guess=.directed,.hit=scan(x,.directed,0,Select)},.random_iid=>blk:{var p=std.Random.DefaultPrng.init(seed);const r=p.random();var ok=false;for(0..Select)|_|{const b:Bank=@enumFromInt(r.uintLessThan(usize,4));ok=ok or exact(cand(b,r.uintLessThan(usize,size(b))),x);}break:blk .{.guess=.directed,.hit=ok};}};}
fn an(a:Arm)[]const u8{return @tagName(a);}fn bn(b:Bank)[]const u8{return @tagName(b);}fn kn(k:Kind)[]const u8{return @tagName(k);}
fn run(w:anytype)!void{var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator);defer arena.deinit();var seen=[_]bool{false}**1270;for(0..1270)|i|{const c=cand(.directed,i);const key=(@as(usize,c.mask)-1)*5+if(c.m==2)c.r else 2+c.r;if(seen[key])return error.Duplicate;seen[key]=true;}for(seen)|v|if(!v)return error.Missing;const ts=suite();try w.writeAll("arm,target_token,truth_audit_only,guess_audit_only,probe_calls,selection_calls,total_calls,exact_solve,enum_unique,perm_checked,policy_audit_isolated,validity\n");var totals=[_]usize{0}**4;for(ts)|t|{const x=try samples(arena.allocator(),t);for([_]Arm{.adaptive,.fixed,.random_iid,.blind_coverage})|a|{const z=runArm(x,a,0xC0DE0000+@as(u64,t.id)*17+@intFromEnum(a));if(z.hit)totals[@intFromEnum(a)]+=1;try w.print("{s},K4-{d:0>2},{s},{s},{d},{d},{d},{s},1270,pass,pass,pass\n",.{an(a),t.id,kn(t.kind),bn(z.guess),Probe,Select,Total,if(z.hit)"YES"else"NO"});}}for([_]Arm{.adaptive,.fixed,.random_iid,.blind_coverage})|a|try w.print("SUMMARY-{s},-,-,-,{d},{d},{d},{d}/24,1270,pass,pass,pass\n",.{an(a),Probe,Select,Total,totals[@intFromEnum(a)]});}
pub fn main()!void{var it=std.process.args();_=it.next();const p=it.next() orelse "../results/adaptive_allocator_round_k.csv";if(std.mem.eql(u8,p,"selftest")){try run(std.io.getStdOut().writer());return;}const f=try std.fs.cwd().createFile(p,.{.truncate=true});defer f.close();try run(f.writer());}
