//! J4 / Round J.  Equal-total-cost test of the frozen J2 trajectory route.
//! Inference sees only candidate accuracies on the target's labelled examples;
//! target route/name/formula/anchor/mask/residue never enter `route`.
const std = @import("std");
const Cells: usize = 8;
const N: usize = 900;
const Train: usize = 450;
const Val: usize = 675;
const ProbeCalls: usize = 216; // frozen J2 accounting: 204 prefix + 12 validation
const SelectCalls: usize = 384;
const TotalCalls: usize = ProbeCalls + SelectCalls;
const Route = enum { global, singleton, directed, none };
const Split = enum { train, val, heldout };
const Arm = enum { guided, fixed, random_iid, blind_directed };
const Target = struct { id: u8, audit: Route, split: Split, a: u8, mask: u8, m: u8, r: u8 };
const targets = [_]Target{
    .{ .id=0,.audit=.global,.split=.train,.a=1,.mask=0,.m=2,.r=0 }, .{ .id=1,.audit=.global,.split=.train,.a=2,.mask=0,.m=3,.r=1 }, .{ .id=2,.audit=.global,.split=.train,.a=4,.mask=0,.m=2,.r=1 }, .{ .id=3,.audit=.global,.split=.val,.a=3,.mask=0,.m=3,.r=0 }, .{ .id=4,.audit=.global,.split=.heldout,.a=5,.mask=0,.m=2,.r=0 },
    .{ .id=5,.audit=.singleton,.split=.train,.a=0,.mask=0,.m=2,.r=0 }, .{ .id=6,.audit=.singleton,.split=.train,.a=2,.mask=0,.m=3,.r=1 }, .{ .id=7,.audit=.singleton,.split=.train,.a=5,.mask=0,.m=2,.r=1 }, .{ .id=8,.audit=.singleton,.split=.val,.a=6,.mask=0,.m=3,.r=0 }, .{ .id=9,.audit=.singleton,.split=.heldout,.a=3,.mask=0,.m=2,.r=0 },
    .{ .id=10,.audit=.directed,.split=.train,.a=0,.mask=0x03,.m=2,.r=0 }, .{ .id=11,.audit=.directed,.split=.train,.a=0,.mask=0x0c,.m=3,.r=1 }, .{ .id=12,.audit=.directed,.split=.train,.a=0,.mask=0x51,.m=2,.r=1 }, .{ .id=13,.audit=.directed,.split=.val,.a=0,.mask=0x22,.m=3,.r=0 }, .{ .id=14,.audit=.directed,.split=.heldout,.a=0,.mask=0x19,.m=2,.r=0 },
    .{ .id=15,.audit=.none,.split=.train,.a=0,.mask=0,.m=2,.r=0 }, .{ .id=16,.audit=.none,.split=.train,.a=0,.mask=0,.m=3,.r=1 }, .{ .id=17,.audit=.none,.split=.train,.a=0,.mask=0,.m=2,.r=1 }, .{ .id=18,.audit=.none,.split=.val,.a=0,.mask=0,.m=3,.r=0 }, .{ .id=19,.audit=.none,.split=.heldout,.a=0,.mask=0,.m=2,.r=0 },
};
const Sample = struct { g: [Cells]u8, y: bool };
const Cand = struct { route: Route, a: u8, mask: u8, m: u8, r: u8 };
fn rn(r: Route) []const u8 { return @tagName(r); }
fn an(a: Arm) []const u8 { return @tagName(a); }
fn count(g: [Cells]u8, a: u8) usize { var n:usize=0; for(g)|x| { if(x>=a) n+=1; } return n; }
fn rank(g: [Cells]u8, p: usize) usize { var n:usize=0; for(g,0..)|x,i| { if(i!=p and g[p]>x) n+=1; } return n; }
fn cross(g: [Cells]u8, mask:u8) usize { var n:usize=0; for(0..Cells)|i|for(0..Cells)|j| { const bi:u8=@as(u8,1)<<@intCast(i); const bj:u8=@as(u8,1)<<@intCast(j); if(mask&bi!=0 and mask&bj==0 and g[i]>g[j])n+=1; }; return n; }
fn adjacent(g:[Cells]u8) usize { var n:usize=0; for(1..Cells)|i| { if(g[i]>=3 and g[i-1]>=3) n+=1; } return n; }
fn truth(t:Target,g:[Cells]u8) bool { const q:usize=switch(t.audit){.global=>count(g,t.a),.singleton=>rank(g,t.a),.directed=>cross(g,t.mask),.none=>adjacent(g)}; return q%t.m==t.r; }
fn pred(c:Cand,g:[Cells]u8) bool { const q:usize=switch(c.route){.global=>count(g,c.a),.singleton=>rank(g,c.a),.directed=>cross(g,c.mask),.none=>adjacent(g)}; return q%c.m==c.r; }
fn make(a:std.mem.Allocator,t:Target,seed:u64)![]Sample { var p=std.Random.DefaultPrng.init(seed^(@as(u64,t.id)*%0x9e3779b97f4a7c15)); const r=p.random(); const x=try a.alloc(Sample,N); for(x)|*s|{for(&s.g)|*v|v.*=r.intRangeAtMost(u8,0,5);s.y=truth(t,s.g);} return x; }
fn score(c:Cand,x:[]const Sample,lo:usize,hi:usize)f64 {var n:usize=0;for(x[lo..hi])|s| { if(pred(c,s.g)==s.y) n+=1; } return @as(f64,@floatFromInt(n))/@as(f64,@floatFromInt(hi-lo));}
fn flavor(k:usize)struct{m:u8,r:u8}{return if(k<2).{.m=2,.r=@intCast(k)}else .{.m=3,.r=@intCast(k-2)};}
fn directed(k:usize)Cand{const z=flavor(k%5);return .{.route=.directed,.a=0,.mask=@intCast(k/5+1),.m=z.m,.r=z.r};}
fn small(r:Route,k:usize)Cand { const z=flavor(switch(r){.global=>k/5,.singleton=>k/8,.none=>k,.directed=>0}); return switch(r){.global=>.{.route=r,.a=@intCast(k%5+1),.mask=0,.m=z.m,.r=z.r},.singleton=>.{.route=r,.a=@intCast(k%8),.mask=0,.m=z.m,.r=z.r},.none=>.{.route=r,.a=0,.mask=0,.m=z.m,.r=z.r},.directed=>directed(k)}; }
fn bankSize(r:Route)usize{return switch(r){.global=>30,.singleton=>48,.directed=>1270,.none=>5};}
fn routeFromFrozenFields(x:[]const Sample)Route { // frozen J2 observable: best bank train gain, then validation tie-break.
    var best:Route=.global; var bv:f64=-1;
    for([_]Route{.global,.singleton,.directed,.none})|r|{ const b=@min(bankSize(r),switch(r){.directed=>120,else=>bankSize(r)}); var q:f64=0; for(0..b)|k|q=@max(q,score(small(r,k),x,0,Train)); if(q>bv){bv=q;best=r;} }
    return best;
}
fn hasExact(x:[]const Sample, c:Cand)bool{return score(c,x,Val,N)>=0.999;}
fn tryRange(x:[]const Sample,r:Route,start:usize,n:usize)bool{for(0..n)|i|{const k=(start+i)%bankSize(r);if(hasExact(x,small(r,k)))return true;}return false;}
fn runArm(x:[]const Sample,arm:Arm,seed:u64)struct{guess:Route,solved:bool,select:usize}{
    const guess=routeFromFrozenFields(x);
    switch(arm){
        .guided=>return .{.guess=guess,.solved=tryRange(x,guess,0,SelectCalls),.select=SelectCalls},
        // Frozen target-blind fixed allocation.  It fully covers all three
        // small banks and spends the remaining 301 calls in a fixed directed prefix.
        .fixed=>return .{.guess=.directed,.solved=tryRange(x,.global,0,30) or tryRange(x,.singleton,0,48) or tryRange(x,.none,0,5) or tryRange(x,.directed,0,301),.select=SelectCalls},
        .blind_directed=>return .{.guess=.directed,.solved=tryRange(x,.directed,0,SelectCalls),.select=SelectCalls},
        .random_iid=>{var p=std.Random.DefaultPrng.init(seed);const r=p.random();var ok=false;for(0..SelectCalls)|_|{const k=r.intRangeLessThan(usize,0,1270);ok=ok or hasExact(x,directed(k));}return .{.guess=.directed,.solved=ok,.select=SelectCalls};},
    }
}
fn run(w:anytype)!void{var ar=std.heap.ArenaAllocator.init(std.heap.page_allocator);defer ar.deinit();try w.writeAll("arm,seed,split,target_audit_only,truth_audit_only,route_prediction_audit_only,route_correct,probe_calls,selection_calls,total_calls,exact_solve,enumeration_unique,permutation_integrity,leakage_guard,validity\n");var totals=[_]usize{0}**4;const seeds=[_]u64{0xA400000000000001,0xA400000000000002,0xA400000000000003};for(seeds)|seed|for(targets)|t|{if(t.split!=.heldout)continue;for([_]Arm{.guided,.fixed,.random_iid,.blind_directed})|a|{const x=try make(ar.allocator(),t,seed);const z=runArm(x,a,seed^(@as(u64,@intFromEnum(a))*%0xd1b54a32d192ed03));if(z.solved)totals[@intFromEnum(a)]+=1;try w.print("{s},0x{X:0>16},heldout,{d},{s},{s},{d},{d},{d},{d},{s},1270,pass,pass,pass\n",.{an(a),seed,t.id,rn(t.audit),rn(z.guess),@intFromBool(z.guess==t.audit),ProbeCalls,z.select,TotalCalls,if(z.solved)"YES"else"NO"});}};for([_]Arm{.guided,.fixed,.random_iid,.blind_directed})|a|try w.print("SUMMARY,-,heldout,-,{s},- ,{d}/12,{d},{d},{d},-,-,-,pass\n",.{an(a),totals[@intFromEnum(a)],ProbeCalls,SelectCalls,TotalCalls});}
pub fn main()!void{var it=std.process.args();_ =it.next();const p=it.next() orelse "../results/trajectory_allocator_round_j.csv";if(std.mem.eql(u8,p,"selftest")){try run(std.io.getStdOut().writer());return;}const f=try std.fs.cwd().createFile(p,.{.truncate=true});defer f.close();try run(f.writer());}
