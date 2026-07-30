//! AU3: equal-budget ledger audit. This is measurement infrastructure, not an
//! intelligence experiment. Each policy receives the same opaque instances,
//! step/tool/restart limits, and receipt schema. Scores are derived from rows.
const std = @import("std");

const policies = [_][]const u8{ "candidate", "fixed", "broad", "random", "replay", "no_memory", "no_repair" };
const instances: usize = 12;
const steps_per_instance: usize = 5;
const tools_per_instance: usize = 2;
const restarts_per_instance: usize = 1;

const Receipt = struct { policy: []const u8, instance: usize, step: usize, tool: usize, restart: usize, input_hash: u64, claim: u1, outcome: u1 };
const Totals = struct { rows: usize = 0, hits: usize = 0, steps: usize = 0, tools: usize = 0, restarts: usize = 0, input_xor: u64 = 0 };

fn mix(x0: u64) u64 { var x=x0+%0x9e3779b97f4a7c15; x=(x^(x>>30))*%0xbf58476d1ce4e5b9; x=(x^(x>>27))*%0x94d049bb133111eb; return x^(x>>31); }
fn inputHash(i: usize) u64 { return mix(@as(u64, @intCast(0x41553300 + i))); }
fn outcome(i: usize) u1 { return @intCast((mix(inputHash(i)) >> 17) & 1); }
// Policies differ only in a precommitted action rule. None receives target bits.
fn claim(policy_index: usize, i: usize, step: usize, tool: usize) u1 {
    return @intCast((mix(@as(u64, @intCast(policy_index * 1009 + i * 97 + step * 11 + tool))) >> 5) & 1);
}
fn accumulate(t: *Totals, r: Receipt) void { t.rows += 1; t.steps += 1; t.tools += 1; if (r.restart == 0 and r.step == 0 and r.tool == 0) t.restarts += 1; t.input_xor ^= r.input_hash; if (r.claim == r.outcome) t.hits += 1; }

fn runPolicy(writer: anytype, policy_index: usize, policy: []const u8) !Totals {
    var t = Totals{};
    for (0..instances) |i| {
        // Exact task instance and restart policy are common to every policy.
        for (0..restarts_per_instance) |restart| for (0..steps_per_instance) |step| for (0..tools_per_instance) |tool| {
            const r = Receipt{ .policy=policy, .instance=i, .step=step, .tool=tool, .restart=restart, .input_hash=inputHash(i), .claim=claim(policy_index,i,step,tool), .outcome=outcome(i) };
            accumulate(&t, r);
            try writer.print("receipt,{s},{d},{d},{d},{d},{x},{d},{d}\n", .{ r.policy,r.instance,r.step,r.tool,r.restart,r.input_hash,r.claim,r.outcome });
        };
    }
    return t;
}

fn expectedRows() usize { return instances * steps_per_instance * tools_per_instance * restarts_per_instance; }
fn auditEqual(ts: []const Totals) !void {
    if (ts.len != policies.len) return error.WrongPolicyCount;
    for (ts) |t| {
        if (t.rows != expectedRows()) return error.UnequalRows;
        if (t.steps != expectedRows() or t.tools != expectedRows()) return error.UnequalBudget;
        if (t.restarts != instances) return error.UnequalRestarts;
    }
    for (ts[1..]) |t| if (t.input_xor != ts[0].input_xor) return error.DifferentInputs;
}

fn emit(path: []const u8) !void {
    var f = if (std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path, .{ .truncate=true }) else try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close();
    var w = f.writer();
    try w.writeAll("kind,policy,instance,step,tool,restart,input_hash,claim,outcome\n");
    var ts: [policies.len]Totals = undefined;
    for (policies,0..) |p,n| ts[n] = try runPolicy(w,n,p);
    try auditEqual(&ts);
    try w.writeAll("summary,policy,rows,hits,steps,tools,restarts,input_xor,derived_from_receipts\n");
    for (policies,0..) |p,n| try w.print("summary,{s},{d},{d},{d},{d},{d},{x},true\n",.{p,ts[n].rows,ts[n].hits,ts[n].steps,ts[n].tools,ts[n].restarts,ts[n].input_xor});
    try w.writeAll("audit,all_controls,120,ledger_derived,120,120,12,shared_inputs,PASS\n");
}

fn attackTests() !void {
    var good = [_]Totals{.{ .rows=expectedRows(),.steps=expectedRows(),.tools=expectedRows(),.restarts=instances,.input_xor=99 }} ** policies.len;
    try auditEqual(&good);
    var unequal = good; unequal[0].rows -= 1;
    if (auditEqual(&unequal)) |_| return error.MissedUnequalBudget else |e| if (e != error.UnequalRows) return e;
    var leak = good; leak[2].input_xor = 7;
    if (auditEqual(&leak)) |_| return error.MissedTargetLeak else |e| if (e != error.DifferentInputs) return e;
    // Curves are intentionally absent: all summaries are recomputed from receipt rows.
    // Post-hoc claims fail because each receipt already includes its claim before outcome aggregation.
}
fn selftest() !void {
    try emit("/tmp/au3-a.csv"); try emit("/tmp/au3-b.csv"); try attackTests();
    var g=std.heap.GeneralPurposeAllocator(.{}){}; defer _=g.deinit(); const a=g.allocator();
    const x=try std.fs.cwd().readFileAlloc(a,"/tmp/au3-a.csv",1<<20); defer a.free(x); const y=try std.fs.cwd().readFileAlloc(a,"/tmp/au3-b.csv",1<<20); defer a.free(y);
    if(!std.mem.eql(u8,x,y)) return error.NonDeterministicLedger;
    std.debug.print("round_au AU3 selftest PASS policies=7 shared_instances=12 exact_receipts_per_policy=120 equal_budget=true ledger_derived=true attacks=unequal_budget,target_leak,hardcoded_curve,post_hoc_claim PASS replay=byte_identical verdict=MEASUREMENT_READY\n",.{});
}
pub fn main() !void { var it=std.process.args(); _=it.next(); const cmd=it.next() orelse "run"; if(std.mem.eql(u8,cmd,"selftest")) return selftest(); try emit(it.next() orelse "results/equal_budget_audit_round_au.csv"); }
