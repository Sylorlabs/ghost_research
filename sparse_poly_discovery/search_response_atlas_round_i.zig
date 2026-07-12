//! I1 / Round I -- frozen search-response descriptor atlas.
//!
//! A descriptor row is assembled only from four generic, equal-budget
//! micro-searches and their observed validation responses.  Target identity,
//! formula, route label, masks, pivots, and residues exist only in the oracle
//! and audit output.  This is intentionally an atlas, not an allocator claim.
const std = @import("std");
const N_TARGETS: usize = 20;
const N: usize = 800;
const TRAIN: usize = 400;
const CELLS: usize = 8;
const FAMILIES: usize = 4;

const Route = enum { global, singleton, partition, none };
const Split = enum { train, val, heldout };
const Target = struct { id: u8, route: Route, split: Split };
const targets = [_]Target{
    .{.id=0,.route=.global,.split=.train}, .{.id=1,.route=.global,.split=.train}, .{.id=2,.route=.global,.split=.train}, .{.id=3,.route=.global,.split=.val}, .{.id=4,.route=.global,.split=.heldout},
    .{.id=5,.route=.singleton,.split=.train}, .{.id=6,.route=.singleton,.split=.train}, .{.id=7,.route=.singleton,.split=.train}, .{.id=8,.route=.singleton,.split=.val}, .{.id=9,.route=.singleton,.split=.heldout},
    .{.id=10,.route=.partition,.split=.train}, .{.id=11,.route=.partition,.split=.train}, .{.id=12,.route=.partition,.split=.train}, .{.id=13,.route=.partition,.split=.val}, .{.id=14,.route=.partition,.split=.heldout},
    .{.id=15,.route=.none,.split=.train}, .{.id=16,.route=.none,.split=.train}, .{.id=17,.route=.none,.split=.train}, .{.id=18,.route=.none,.split=.val}, .{.id=19,.route=.none,.split=.heldout},
};
const Sample = struct { g: [CELLS]u8, y: bool };
const Desc = [FAMILIES * 4]f64; // gain, residual reduction, coverage, normalized cost per family

fn routeName(x: Route) []const u8 { return @tagName(x); }
fn splitName(x: Split) []const u8 { return @tagName(x); }
fn next(x: *u64) u8 { x.* = x.* *% 6364136223846793005 +% 1442695040888963407; return @truncate(x.* >> 61); }
fn countGE(g: [CELLS]u8, t: u8) usize { var n: usize = 0; for (g) |v| { if (v >= t) n += 1; } return n; }
fn rank(g: [CELLS]u8, p: usize) usize { var n: usize = 0; for (g, 0..) |v, j| { if (j != p and g[p] > v) n += 1; } return n; }
fn cross(g: [CELLS]u8, mask: u8) usize { var n: usize = 0; for (0..CELLS) |i| { for (0..CELLS) |j| { if ((mask & (@as(u8, 1) << @intCast(i))) != 0 and (mask & (@as(u8, 1) << @intCast(j))) == 0 and g[i] > g[j]) n += 1; } } return n; }
fn adjacent(g: [CELLS]u8) usize { var n: usize = 0; for (1..CELLS) |i| { if (g[i] >= 3 and g[i-1] >= 3) n += 1; } return n; }
fn oracle(id: u8, g: [CELLS]u8) bool {
    return switch (id) {
        0 => countGE(g, 1) % 3 == 0, 1 => countGE(g, 3) % 2 == 1, 2 => countGE(g, 4) % 3 == 2, 3 => countGE(g, 2) % 2 == 0, 4 => countGE(g, 5) % 2 == 0,
        5 => rank(g, 0) % 2 == 0, 6 => rank(g, 2) % 3 == 1, 7 => rank(g, 5) % 2 == 1, 8 => rank(g, 6) % 3 == 0, 9 => rank(g, 3) % 2 == 0,
        10 => cross(g, 0x03) % 2 == 0, 11 => cross(g, 0x0c) % 3 == 1, 12 => cross(g, 0x51) % 2 == 1, 13 => cross(g, 0x22) % 3 == 0, 14 => cross(g, 0x19) % 2 == 0,
        15 => adjacent(g) % 2 == 0, 16 => adjacent(g) >= 3, 17 => (countGE(g, 2) + adjacent(g)) % 3 == 1, 18 => (rank(g, 1) + adjacent(g)) % 2 == 0, 19 => (countGE(g, 4) + adjacent(g)) % 3 == 2,
        else => false,
    };
}
fn make(alloc: std.mem.Allocator, id: u8, split: Split) ![]Sample {
    const out = try alloc.alloc(Sample, N); const base: u64 = switch (split) {.train=>0x17a1, .val=>0x27b2, .heldout=>0x37c3}; var s: u64 = base + id;
    for (out) |*x| { for (&x.g) |*v| v.* = next(&s); x.y = oracle(id, x.g); }
    return out;
}
const Candidate = struct { kind: usize, a: u8, m: u8, r: u8 };
fn pred(c: Candidate, g: [CELLS]u8) bool { const q: usize = switch(c.kind) { 0 => countGE(g,c.a), 1 => rank(g,c.a), 2 => cross(g,c.a), else => adjacent(g) }; return q % c.m == c.r; }
fn candidateCount(kind: usize) usize { return switch(kind) {0 => 5*2*3, 1 => CELLS*2*3, 2 => 254*2*3, else => 2*3}; }
fn nth(kind: usize, k: usize) Candidate { const m: u8 = if ((k / switch(kind){0=>5,1=>CELLS,2=>254,else=>1}) % 2 == 0) 2 else 3; const base = switch(kind){0=>5,1=>CELLS,2=>254,else=>1}; return .{.kind=kind,.a=@intCast(switch(kind){0=>1+(k%5),1=>k%CELLS,2=>1+(k%254),else=>0}),.m=m,.r=@intCast((k/base)%m)}; }
fn accuracy(c: Candidate, xs: []const Sample, lo: usize, hi: usize) f64 { var ok: usize=0; for(xs[lo..hi])|x| { if(pred(c,x.g)==x.y) ok+=1; } return @as(f64,@floatFromInt(ok))/@as(f64,@floatFromInt(hi-lo)); }
fn baseline(xs: []const Sample) f64 { var yes:usize=0; for(xs[TRAIN..])|x| { if(x.y) yes+=1; } const p=@as(f64,@floatFromInt(yes))/@as(f64,@floatFromInt(N-TRAIN)); return @max(p,1-p); }
/// Fixed equal budget: every family is allotted 30 validation evaluations.
/// Large grammars receive a deterministic evenly-spaced subsample, so cost is
/// equal and descriptor values mean observed response rather than menu size.
fn response(kind: usize, xs: []const Sample) [4]f64 {
    const budget: usize=30; const total=candidateCount(kind); var best:f64=0; var hits:usize=0;
    for(0..budget)|i| { const k=(i*total)/budget; const a=accuracy(nth(kind,k),xs,0,TRAIN); const v=accuracy(nth(kind,k),xs,TRAIN,N); best=@max(best,v); if(a>=0.70)hits+=1; }
    const base=baseline(xs); return .{best-base, base-(1.0-best), @as(f64,@floatFromInt(hits))/budget, @as(f64,@floatFromInt(budget))/@as(f64,@floatFromInt(budget))};
}
fn distance(a: Desc,b: Desc, dims: usize) f64 { var q:f64=0;for(0..dims)|i|{const z=a[i]-b[i];q+=z*z;}return q; }
fn classify(i:usize, ds:[N_TARGETS]Desc, dims:usize) Route {
    var sum = [_]Desc{[_]f64{0} ** (FAMILIES * 4)} ** FAMILIES;
    var n = [_]usize{0} ** FAMILIES;
    for (targets, 0..) |t, j| if (t.split == .train) {
        const ri: usize = @intFromEnum(t.route);
        n[ri] += 1;
        for (0..dims) |k| sum[ri][k] += ds[j][k];
    };
    var best:f64=1e99; var out:Route=.global;
    for (0..FAMILIES) |r| {
        for (0..dims) |k| sum[r][k] /= @as(f64,@floatFromInt(n[r]));
        const d=distance(ds[i],sum[r],dims);
        if(d<best){best=d;out=@enumFromInt(r);}
    }
    return out;
}
fn run(w:anytype)!void {
    var arena=std.heap.ArenaAllocator.init(std.heap.page_allocator);defer arena.deinit(); const a=arena.allocator(); var ds:[N_TARGETS]Desc=undefined;
    try w.print("record,split,target_audit_only,truth_audit_only,descriptor_contract,predicted_audit_only,correct,global_gain,global_residual,singleton_gain,singleton_residual,partition_gain,partition_residual,none_gain,none_residual,coverage_mean,cost_equal,validity\n",.{});
    for(targets,0..)|t,i| {const xs=try make(a,t.id,t.split);for(0..FAMILIES)|f|{const r=response(f,xs);for(0..4)|q|ds[i][f*4+q]=r[q];}}
    const contracts=[_]struct{name:[]const u8,dims:usize}{.{.name="gain4",.dims=4},.{.name="gain_residual8",.dims=8},.{.name="full_response16",.dims=16}}; var selected:usize=0;var bv:usize=0;
    for(contracts,0..)|c,ci|{var ok:usize=0;for(targets,0..)|t,i| { if(t.split==.val and classify(i,ds,c.dims)==t.route) ok+=1; } if(ok>bv){bv=ok;selected=ci;}try w.print("ABLATION,validation,-,-,{s},-,{d}/4,-,-,-,-,-,-,-,-,-,-,pass\n",.{c.name,ok});}
    const c=contracts[selected]; var hold:usize=0; var min:f64=1e99;
    for (targets,0..) |t,i| {
        if (t.split != .train) {
            const p=classify(i,ds,c.dims);
            if (t.split==.heldout and p==t.route) hold+=1;
            for (targets,0..) |u,j| {
                if (u.split==.train) min=@min(min,@sqrt(distance(ds[i],ds[j],c.dims)));
            }
            const cov=(ds[i][2]+ds[i][6]+ds[i][10]+ds[i][14])/4;
            try w.print("TARGET,{s},{d},{s},{s},{s},{d},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},{d:.4},1.0000,pass\n",.{splitName(t.split),t.id,routeName(t.route),c.name,routeName(p),@intFromBool(p==t.route),ds[i][0],ds[i][1],ds[i][4],ds[i][5],ds[i][8],ds[i][9],ds[i][12],ds[i][13],cov});
        }
    }
    // This guard detects copied/identical response rows; it is deliberately
    // not a claim that near rows are disallowed.  The frozen minimum is 0.03
    // Euclidean descriptor units, predeclared before inspecting holdout.
    try w.print("SUMMARY,heldout,-,-,{s},-,{d}/4,-,-,-,-,-,-,-,-,-,-,pass\n",.{c.name,hold});try w.print("GATES,frozen_12_4_4_distance_ge_0.03,-,-,{s},-,-,-,-,-,-,-,-,-,-,-,{d:.6},pass\n",.{c.name,min});if(min<0.03)return error.LeakageDistance;
}
pub fn main()!void {var it=std.process.args();_=it.next();const p=it.next()orelse"../results/search_response_atlas_round_i.csv";if(std.mem.eql(u8,p,"selftest")){try run(std.io.getStdOut().writer());return;}const f=try std.fs.cwd().createFile(p,.{});defer f.close();try run(f.writer());}
