//! K1 / Round K: forensic replay of J4's frozen fixed policy.
//! This harness does not design an adaptive policy.  It replays exactly the
//! J4 fixed order, writes the first exact witness for every held-out cell, and
//! runs declared leave-one-bank and directed-prefix ablations.
const std = @import("std");
const Cells: usize = 8;
const N: usize = 900;
const Val: usize = 675;
const Route = enum { global, singleton, directed, none };
const Target = struct { id: u8, route: Route, a: u8, mask: u8, m: u8, r: u8 };
const Cand = struct { route: Route, a: u8, mask: u8, m: u8, r: u8 };
const Sample = struct { g: [Cells]u8, y: bool };
const targets = [_]Target{
    .{.id=4,.route=.global,.a=5,.mask=0,.m=2,.r=0},
    .{.id=9,.route=.singleton,.a=3,.mask=0,.m=2,.r=0},
    .{.id=14,.route=.directed,.a=0,.mask=0x19,.m=2,.r=0},
    .{.id=19,.route=.none,.a=0,.mask=0,.m=2,.r=0},
};
const seeds = [_]u64{ 0xA400000000000001, 0xA400000000000002, 0xA400000000000003 };
fn rn(x: Route) []const u8 { return @tagName(x); }
fn count(g: [Cells]u8, a:u8) usize { var n:usize=0; for(g)|x| { if(x>=a) n+=1; } return n; }
fn rank(g:[Cells]u8,p:usize)usize { var n:usize=0; for(g,0..)|x,i| { if(i!=p and g[p]>x) n+=1; } return n; }
fn cross(g:[Cells]u8,mask:u8)usize { var n:usize=0; for(0..Cells)|i|for(0..Cells)|j| { const bi:u8=@as(u8,1)<<@intCast(i); const bj:u8=@as(u8,1)<<@intCast(j); if(mask&bi!=0 and mask&bj==0 and g[i]>g[j])n+=1; }; return n; }
fn adjacent(g:[Cells]u8)usize { var n:usize=0; for(1..Cells)|i| { if(g[i]>=3 and g[i-1]>=3) n+=1; } return n; }
fn value(route:Route,g:[Cells]u8,a:u8,mask:u8)usize { return switch(route){.global=>count(g,a),.singleton=>rank(g,a),.directed=>cross(g,mask),.none=>adjacent(g)}; }
fn truth(t:Target,g:[Cells]u8)bool{return value(t.route,g,t.a,t.mask)%t.m==t.r;}
fn pred(c:Cand,g:[Cells]u8)bool{return value(c.route,g,c.a,c.mask)%c.m==c.r;}
fn make(a:std.mem.Allocator,t:Target,seed:u64)![]Sample { var p=std.Random.DefaultPrng.init(seed^(@as(u64,t.id)*%0x9e3779b97f4a7c15)); const r=p.random(); const x=try a.alloc(Sample,N); for(x)|*s|{for(&s.g)|*v|v.*=r.intRangeAtMost(u8,0,5);s.y=truth(t,s.g);} return x; }
fn score(c:Cand,x:[]const Sample)f64 { var n:usize=0; for(x[Val..N])|s| { if(pred(c,s.g)==s.y) n+=1; } return @as(f64,@floatFromInt(n))/@as(f64,@floatFromInt(N-Val)); }
fn flavor(k:usize)struct{m:u8,r:u8}{return if(k<2).{.m=2,.r=@intCast(k)}else .{.m=3,.r=@intCast(k-2)};}
fn cand(route:Route,k:usize)Cand { const z=flavor(switch(route){.global=>k/5,.singleton=>k/8,.none=>k,.directed=>k%5}); return switch(route){.global=>.{.route=route,.a=@intCast(k%5+1),.mask=0,.m=z.m,.r=z.r},.singleton=>.{.route=route,.a=@intCast(k%8),.mask=0,.m=z.m,.r=z.r},.none=>.{.route=route,.a=0,.mask=0,.m=z.m,.r=z.r},.directed=>.{.route=.directed,.a=0,.mask=@intCast(k/5+1),.m=z.m,.r=z.r}}; }
fn size(route:Route)usize{return switch(route){.global=>30,.singleton=>48,.directed=>1270,.none=>5};}
fn exact(c:Cand,x:[]const Sample)bool{return score(c,x)>=0.999;}
fn firstExact(x:[]const Sample,route:Route,n:usize)?usize { for(0..n)|k|if(exact(cand(route,k),x))return k; return null; }
const Policy = struct { name: []const u8, global:usize, singleton:usize, none:usize, directed:usize };
const policies = [_]Policy{
    .{.name="full_j4_fixed",.global=30,.singleton=48,.none=5,.directed=301},
    .{.name="no_global",.global=0,.singleton=48,.none=5,.directed=301},
    .{.name="no_singleton",.global=30,.singleton=0,.none=5,.directed=301},
    .{.name="no_none",.global=30,.singleton=48,.none=0,.directed=301},
    .{.name="no_directed",.global=30,.singleton=48,.none=5,.directed=0},
    .{.name="directed_100",.global=30,.singleton=48,.none=5,.directed=100},
    .{.name="directed_200",.global=30,.singleton=48,.none=5,.directed=200},
    .{.name="small_banks_only",.global=30,.singleton=48,.none=5,.directed=0},
    // Post-hoc forensic minimum for this exact frozen suite; not a candidate K3 policy.
    .{.name="derived_minimal_prefix",.global=5,.singleton=0,.none=1,.directed=121},
};
fn policySolve(x:[]const Sample,p:Policy)bool{return firstExact(x,.global,p.global)!=null or firstExact(x,.singleton,p.singleton)!=null or firstExact(x,.none,p.none)!=null or firstExact(x,.directed,p.directed)!=null;}
fn keyOf(c:Cand)usize { const flavor_offset: usize = if(c.m==3) 2 else 0; return (@as(usize,c.mask)-1)*5+@as(usize,c.r)+flavor_offset; }
fn verifyEnumeration()!void { var seen=[_]bool{false}**1270; var reversed=[_]bool{false}**1270; for(0..1270)|k| { const key=keyOf(cand(.directed,k)); if(key>=1270 or seen[key])return error.BadDirectedEnumeration;seen[key]=true; const reverse_key=keyOf(cand(.directed,1269-k)); if(reverse_key>=1270 or reversed[reverse_key])return error.BadPermutation;reversed[reverse_key]=true; } for(seen, reversed)|a,b|if(!a or !b)return error.BadDirectedEnumeration; }
fn run(w:anytype)!void {
    try verifyEnumeration();
    try w.writeAll("kind,policy,seed,target_id,target_route,bank,bank_candidate_index,call_number,first_exact_fixed_call,min_bank_calls,policy_total_calls,solved,enum_unique,perm_assert,notes\n");
    var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit();
    var sums=[_]usize{0}**policies.len;
    for(seeds)|seed| for(targets)|t| {
        const x=try make(arena.allocator(),t,seed);
        const bank_order=[_]Route{.global,.singleton,.none,.directed};
        const limits=[_]usize{30,48,5,301};
        var offset:usize=0;
        for(bank_order,0..)|b,i| {
            for(0..limits[i])|k| try w.print("CALL,full_j4_fixed,0x{X:0>16},{d},{s},{s},{d},{d},-,-,384,{s},1270,pass,raw fixed-order candidate ledger\n",.{seed,t.id,rn(t.route),rn(b),k,offset+k+1,if(exact(cand(b,k),x))"YES"else"NO"});
            if(firstExact(x,b,limits[i]))|k| try w.print("ATTRIBUTION,full_j4_fixed,0x{X:0>16},{d},{s},{s},{d},- ,{d},{d},384,YES,1270,pass,first exact inside J4 frozen bank order\n",.{seed,t.id,rn(t.route),rn(b),k,offset+k+1,k+1});
            offset+=limits[i];
        }
        for(policies,0..)|p,pi| { const ok=policySolve(x,p); if(ok)sums[pi]+=1; const total=p.global+p.singleton+p.none+p.directed; try w.print("ABLATION,{s},0x{X:0>16},{d},{s},-,-,-,-,-,{d},{s},1270,pass,predeclared bank ablation\n",.{p.name,seed,t.id,rn(t.route),total,if(ok)"YES"else"NO"}); }
        _=arena.reset(.retain_capacity);
    };
    for(policies,0..)|p,i|try w.print("SUMMARY,{s},-, -, -, -, -, -, -,-,{d},{d}/12,1270,pass,frozen seeds and exact J4 order\n",.{p.name,p.global+p.singleton+p.none+p.directed,sums[i]});
}
pub fn main()!void { var it=std.process.args(); _=it.next(); const path=it.next() orelse "../results/fixed_policy_forensic_round_k.csv"; if(std.mem.eql(u8,path,"selftest"))return run(std.io.getStdOut().writer()); const f=try std.fs.cwd().createFile(path,.{.truncate=true});defer f.close();try run(f.writer()); }
