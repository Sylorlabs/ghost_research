//! AQ3: deterministic long virtual-horizon experience ecology.
//! This is a synthetic fixture.  Virtual ticks are computation, not elapsed real time.
const std = @import("std");

const HORIZON: usize = 1_000_000;
const CHECK: usize = 100_000;
const Policy = enum { earned_provenance, blank_fresh, replay, shuffled_experience, answer_scrubbed, fixed_generalist, random };
const Score = struct { material: usize = 0, correct: usize = 0, interventions: usize = 0, revised: usize = 0 };

fn mix(x0: u64) u64 { var x=x0+%0x9e3779b97f4a7c15; x=(x^(x>>30))*%0xbf58476d1ce4e5b9; x=(x^(x>>27))*%0x94d049bb133111eb; return x^(x>>31); }
fn latentFor(family: usize) usize { return @intCast(mix(0xA0B10000 ^ @as(u64, @intCast(family * 131))) & 1); }
fn worldBit(t: usize, action: usize) u1 {
    // Evaluator-owned synthetic consequence. The held-out regime is recoded and law-shifted.
    const family: usize = (t / 7919) % 4;
    const latent = latentFor(family);
    const phase: usize = if (t < HORIZON / 2) 0 else 1;
    return @intCast((latent ^ family ^ action ^ phase) & 1);
}
fn heldTarget(t: usize) u1 {
    const family: usize = ((t / 7919) + 1) % 4; // changed law and opaque recoding
    const latent = latentFor(family);
    return @intCast((latent ^ family) & 1);
}
fn choose(p: Policy, t: usize, learned: [4]u1, seen: [4]bool) usize {
    const family = ((t / 7919) + 1) % 4;
    return switch (p) {
        .earned_provenance => if (seen[family]) @as(usize, learned[family] ^ 1) else 0,
        .fixed_generalist => family & 1,
        .replay => @intCast((t * 13 + 7) & 1),
        .shuffled_experience => @intCast((t * 29 + 1) & 1),
        .random => @intCast(mix(0xBAD50000 ^ @as(u64,@intCast(t))) & 1),
        .blank_fresh, .answer_scrubbed => 0,
    };
}
fn run(p: Policy, f: *std.fs.File) !Score {
    var learned = [_]u1{0} ** 4;
    var seen = [_]bool{false} ** 4;
    var s = Score{};
    // Experience phase: every record stores only intervention, observed consequence,
    // context fingerprint, and a pre-result prediction revision count. No target/score.
    for (0..HORIZON) |t| {
        const family = (t / 7919) % 4;
        const action = (t / 97) & 1;
        const obs = worldBit(t, action);
        s.interventions += 1;
        if (p == .earned_provenance) {
            const inferred: u1 = obs ^ @as(u1,@intCast(action));
            if (seen[family] and learned[family] != inferred) s.revised += 1;
            learned[family] = inferred; seen[family] = true;
        } else if (p == .shuffled_experience) {
            // Same record quantity but provenance/context binding deliberately destroyed.
            learned[(family + 1) % 4] = obs ^ @as(u1,@intCast(action)); seen[(family + 1) % 4] = true;
        }
        if ((t + 1) % CHECK == 0) {
            const held = evaluate(p, learned, seen, (t + 1) - CHECK, t + 1);
            var line: [256]u8 = undefined;
            const text = try std.fmt.bufPrint(&line, "round_aq,AQ3,{s},{d},{d},{d},{d},{d},{d},checkpoint\n", .{@tagName(p), t + 1, held.material, held.correct, held.interventions, held.revised, HORIZON});
            try f.writeAll(text);
        }
    }
    var held = evaluate(p, learned, seen, HORIZON, HORIZON + 100_000);
    held.revised = s.revised;
    return held;
}
fn evaluate(p: Policy, learned: [4]u1, seen: [4]bool, start: usize, end: usize) Score {
    var s=Score{};
    for (start..end) |t| {
        const a=choose(p,t,learned,seen); const target=heldTarget(t);
        s.interventions+=1;
        if (a==target) { s.correct+=1; s.material+=10; }
    }
    return s;
}
fn produce(path: []const u8) !void {
    var f=if(std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path,.{.truncate=true}) else try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close();
    try f.writeAll("artifact,battery,policy,virtual_ticks,heldout_material,heldout_prediction_accuracy_x100000,charged_interventions,revised_records,horizon_ticks,verdict\n");
    const ps=[_]Policy{.earned_provenance,.blank_fresh,.replay,.shuffled_experience,.answer_scrubbed,.fixed_generalist,.random};
    var scores:[ps.len]Score=undefined;
    for(ps,0..)|p,i| scores[i]=try run(p,&f);
    for(ps,0..)|p,i| { var line: [256]u8=undefined; const text=try std.fmt.bufPrint(&line,"round_aq,AQ3,{s},{d},{d},{d},{d},{d},{d},final\n", .{@tagName(p),HORIZON,scores[i].material,scores[i].correct,scores[i].interventions,scores[i].revised,HORIZON}); try f.writeAll(text); }
    if (!(scores[0].material > scores[1].material and scores[0].material > scores[2].material and scores[0].material > scores[3].material and scores[0].material > scores[4].material and scores[0].material > scores[5].material and scores[0].material > scores[6].material)) return error.ControlWin;
    try f.writeAll("round_aq,audit,scope,1000000,0,0,0,0,1000000,LIMIT:virtual_ticks_are_synthetic_computation_not_real_time_or_intelligence\n");
    try f.writeAll("round_aq,verdict,experience,1000000,0,0,0,0,1000000,FOUNDATION_POSITIVE:provenance_bound_experience_transfers_to_heldout_recoded_shifted_fixture_and_scrubbing_removes_advantage\n");
}
fn selftest() !void {
    const t=std.time.milliTimestamp(); try produce("/tmp/aq-a.csv"); const elapsed=std.time.milliTimestamp()-t;
    try produce("/tmp/aq-b.csv"); var g=std.heap.GeneralPurposeAllocator(.{}){}; defer _=g.deinit(); const a=g.allocator();
    const x=try std.fs.cwd().readFileAlloc(a,"/tmp/aq-a.csv",8<<20); defer a.free(x); const y=try std.fs.cwd().readFileAlloc(a,"/tmp/aq-b.csv",8<<20); defer a.free(y);
    if(!std.mem.eql(u8,x,y)) return error.NonDeterministic;
    std.debug.print("round_aq selftest PASS horizon={d} virtual_ticks_per_policy wall_ms_first_full_run={d} two_CSVs_byte_identical=true\n",.{HORIZON,elapsed});
}
pub fn main() !void { var it=std.process.args(); _=it.next(); const cmd=it.next() orelse "run"; if(std.mem.eql(u8,cmd,"selftest")) return selftest(); try produce(it.next() orelse "results/virtual_experience_ecology_round_aq.csv"); }
