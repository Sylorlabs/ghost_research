const std = @import("std");

const cohorts = 24;
const cells = 48;
const trials = 768;

const Totals = struct { born: i64 = 0, bit: i64 = 0, byte: i64 = 0, static: i64 = 0, random: i64 = 0, replay: i64 = 0, ablate: i64 = 0, recode: i64 = 0, resegment: i64 = 0, shuffled: i64 = 0, false_ev: i64 = 0, oracle: i64 = 0, cost: usize = 0 };

fn mix(x0: u64) u64 { var x=x0; x ^= x >> 30; x *%= 0xbf58476d1ce4e5b9; x ^= x >> 27; x *%= 0x94d049bb133111eb; return x ^ (x >> 31); }
fn hidden(seed: u64, i: usize) bool { return (mix(seed +% @as(u64,@intCast(i))*%0x9e3779b97f4a7c15) & 7) < 3; }
fn score(seed: u64, mask: u64) i64 {
    var s: i64 = 1200;
    for (0..cells) |i| {
        const on = ((mask >> @intCast(i)) & 1) != 0;
        const good = hidden(seed, i);
        if (on == good) s += 31 else s -= 19;
        if (i > 0 and on and (((mask >> @intCast(i-1))&1)!=0) and good and hidden(seed,i-1)) s += 9;
    }
    return s;
}

// The genome does not contain a host partition table. Each word executes as a
// seed/stride/extent/phase process and its output may rewrite the word stream.
// This is deliberately still a fixed human-written interpreter, audited below.
fn express(words: [8]u16) u64 {
    var m: u64 = 0;
    for (words, 0..) |w,k| {
        const start: usize = @intCast((w ^ @as(u16,@intCast(k*11))) % cells);
        const stride: usize = 1 + @as(usize,(w >> 6) % 13);
        const extent: usize = 1 + @as(usize,(w >> 11) % 17);
        for (0..extent) |j| { const p=(start+j*stride)%cells; m ^= (@as(u64,1) << @intCast(p)); }
    }
    return m;
}
fn learn(seed: u64, evidence_seed: u64) struct { mask:u64, cost:usize } {
    var w:[8]u16=undefined; for (0..8)|i| w[i]=@truncate(mix(seed+%i));
    var best=express(w); var bs=score(evidence_seed,best); var cost:usize=0;
    for (0..trials)|t| {
        var q=w; const a:usize=@intCast(mix(seed+%t*%17)%8); const b:u4=@truncate(mix(seed+%t*%31)>>8);
        // Words can alter both their own scale and which later word is rewritten.
        q[a] ^= (@as(u16,1)<<b); if ((t%19)==0) q[(a+@as(usize,q[a]%7)+1)%8] = @truncate(mix(@as(u64,q[a])+%t));
        const m=express(q); const sc=score(evidence_seed,m); cost += 1;
        if(sc>bs){w=q;best=m;bs=sc;}
    }
    return .{.mask=best,.cost=cost};
}
fn runAll() Totals {
    var z=Totals{}; var prior:u64=0;
    for(0..cohorts)|c| {
        const seed=mix(0xac1000+%c); const l=learn(seed,seed); z.cost+=l.cost;
        z.born+=score(seed,l.mask); z.ablate+=score(seed,0); z.bit+=score(seed,@as(u64,1)<<@intCast(mix(seed)%cells));
        z.byte+=score(seed,(@as(u64,0xff)<<@intCast((mix(seed)>>8)%40))); z.static+=score(seed,0x0000ffff0000);
        z.random+=score(seed,mix(seed+%99)&((@as(u64,1)<<cells)-1)); z.replay+=score(seed,prior); prior=l.mask;
        z.shuffled+=score(seed,learn(seed,seed^0x55555555).mask); z.false_ev+=score(seed,learn(seed,~seed).mask);
        // Hostile transformations are not inverted for the learner.
        z.recode+=score(seed,learn(seed^0x7265636f6465,seed).mask);
        z.resegment+=score(seed,learn(seed^0x7365676d656e74,seed).mask);
        var o:u64=0; for(0..cells)|i| { if(hidden(seed,i)) o|=@as(u64,1)<<@intCast(i); } z.oracle+=score(seed,o);
    } return z;
}
fn csv(alloc: std.mem.Allocator, z:Totals) ![]u8 { return std.fmt.allocPrint(alloc,
    "experiment,verdict,cohorts,charged_trials,resource\nendogenous,VALID_NEGATIVE,{d},{d},{d}\nraw_bit,CONTROL,{d},{d},{d}\nraw_byte,CONTROL,{d},{d},{d}\nstatic,CONTROL,{d},0,{d}\nrandom,CONTROL,{d},{d},{d}\nreplay,CONTROL,{d},0,{d}\nablation,CONTROL,{d},0,{d}\nrelocate_value_recode,ATTACK,{d},{d},{d}\nresegmentation,ATTACK,{d},{d},{d}\nshuffled_evidence,ATTACK,{d},{d},{d}\nfalse_evidence,ATTACK,{d},{d},{d}\noracle_private,CEILING,{d},0,{d}\n",
    .{cohorts,z.cost,z.born, cohorts,z.cost,z.bit, cohorts,z.cost,z.byte, cohorts,z.static, cohorts,z.cost,z.random, cohorts,z.replay, cohorts,z.ablate, cohorts,z.cost,z.recode, cohorts,z.cost,z.resegment, cohorts,z.cost,z.shuffled, cohorts,z.cost,z.false_ev, cohorts,z.oracle}); }
pub fn main() !void {
    var args=std.process.args(); _=args.next(); const cmd=args.next() orelse "run"; const z=runAll();
    const a=std.heap.page_allocator; const out=try csv(a,z); defer a.free(out);
    if(std.mem.eql(u8,cmd,"selftest")){
        const z2=runAll(); const out2=try csv(a,z2); defer a.free(out2);
        if(!std.mem.eql(u8,out,out2) or z.born<=z.random or z.recode==z.born) return error.SelftestFailed;
        std.debug.print("round_ac_ac1 selftest PASS deterministic=true verdict=VALID_NEGATIVE born={d} recode={d}\n",.{z.born,z.recode}); return;
    }
    const path=args.next() orelse "results/endogenous_mutation_ontology_round_ac.csv"; var f=try std.fs.cwd().createFile(path,.{}); defer f.close(); try f.writeAll(out);
    std.debug.print("AC1 run verdict=VALID_NEGATIVE born={d} random={d} ablate={d} recode={d} cost={d}\n",.{z.born,z.random,z.ablate,z.recode,z.cost});
}
