//! AX2: deterministic compute-variety grid runner.
//!
//! This is *allocation infrastructure*, not a solver.  It creates genuinely
//! distinct, precommitted candidate configurations over an identical action
//! budget.  It intentionally has no task answer, score, task path, network,
//! or evaluator import.  AX1 typed witnesses must be connected before this can
//! make any capability claim.
const std = @import("std");

const AxisValue = struct { name: []const u8, code: u8 };
const grammars = [_]AxisValue{
    .{ .name = "source", .code = 1 },
    .{ .name = "csv", .code = 2 },
    .{ .name = "control_flow", .code = 3 },
};
const allocations = [_]AxisValue{
    .{ .name = "breadth", .code = 1 },
    .{ .name = "balanced", .code = 2 },
    .{ .name = "depth_repair", .code = 3 },
};
const trusts = [_]AxisValue{
    .{ .name = "conservative", .code = 1 },
    .{ .name = "balanced", .code = 2 },
    .{ .name = "experimental", .code = 3 },
};

const workers = grammars.len * allocations.len * trusts.len;
const actions_per_worker: usize = 48;
const total_work: usize = workers * actions_per_worker;

const Config = struct {
    id: usize,
    grammar: AxisValue,
    allocation: AxisValue,
    trust: AxisValue,
    config_hash: u64,
    grammar_hash: u64,
    assigned_actions: usize,
    plan_hash: u64,
};
const Outcome = struct { explored: usize, split: usize, dead_end: usize, unresolved: usize, diversity: u64 };

fn hashBytes(seed: u64, bytes: []const u8) u64 {
    var h = seed ^ 0xcbf29ce484222325;
    for (bytes) |b| { h ^= b; h *%= 0x100000001b3; }
    return h;
}
fn mix(x0: u64) u64 { var x=x0+%0x9e3779b97f4a7c15; x=(x^(x>>30))*%0xbf58476d1ce4e5b9; x=(x^(x>>27))*%0x94d049bb133111eb; return x^(x>>31); }
fn configHash(g: AxisValue, a: AxisValue, t: AxisValue) u64 {
    // Axis tags prevent `source/balanced/breadth` colliding with the same
    // concatenated spellings in another axis order.
    var h = hashBytes(0, "grammar:"); h = hashBytes(h, g.name);
    h = hashBytes(h, "|allocation:"); h = hashBytes(h, a.name);
    h = hashBytes(h, "|trust:"); return hashBytes(h, t.name);
}
fn grammarHash(g: AxisValue) u64 { return hashBytes(0x4752414d4d4152, g.name); }

fn actionKind(c: Config, step: usize) u8 {
    // Corners differ: source/breadth/conservative cycles observation first,
    // while control_flow/depth_repair/experimental spends earlier actions on
    // repair and discrimination. Interiors are explicit deterministic mixes.
    const x = @as(usize, c.grammar.code) * 17 + @as(usize, c.allocation.code) * 31 + @as(usize, c.trust.code) * 47 + step * (1 + c.allocation.code);
    return @intCast(x % 5); // observe, discriminate, forge, repair, transfer
}
fn planHash(c: Config) u64 {
    var h = c.config_hash;
    for (0..actions_per_worker) |step| { h ^= actionKind(c, step); h *%= 0x100000001b3; }
    return h;
}
fn makeConfig(id: usize, gi: usize, ai: usize, ti: usize) Config {
    var c = Config{ .id=id, .grammar=grammars[gi], .allocation=allocations[ai], .trust=trusts[ti], .config_hash=0, .grammar_hash=0, .assigned_actions=actions_per_worker, .plan_hash=0 };
    c.config_hash = configHash(c.grammar,c.allocation,c.trust);
    c.grammar_hash = grammarHash(c.grammar);
    c.plan_hash = planHash(c);
    return c;
}
fn derive(c: Config) Outcome {
    var o = Outcome{ .explored=0,.split=0,.dead_end=0,.unresolved=0,.diversity=0 };
    for (0..c.assigned_actions) |step| switch (actionKind(c,step)) {
        0 => o.explored += 1,
        1 => o.split += 1,
        2 => o.unresolved += 1,
        3 => o.dead_end += 1,
        4 => o.explored += 1,
        else => unreachable,
    };
    o.diversity = mix(c.plan_hash ^ (@as(u64,@intCast(o.explored)) << 32) ^ @as(u64,@intCast(o.split)));
    return o;
}
fn validate(cs: []const Config) !void {
    if (cs.len != workers) return error.WrongWorkerCount;
    var total: usize = 0;
    // Identity duplication is checked before self-consistency so a copied
    // worker is reported as the duplicate-worker attack it actually is.
    for (cs, 0..) |c, i| for (cs[0..i]) |other| if (c.config_hash == other.config_hash) return error.DuplicateWorker;
    for (cs, 0..) |c, i| {
        if (c.id != i or c.assigned_actions != actions_per_worker) return error.UnequalBudget;
        if (c.config_hash != configHash(c.grammar,c.allocation,c.trust) or c.plan_hash != planHash(c)) return error.PostHocConfig;
        // A runner has no answer-bearing field at all: integration must supply
        // only AX1 typed witness requests/receipts through a separate protocol.
        total += c.assigned_actions;
        for (cs[0..i]) |other| if (c.plan_hash == other.plan_hash) return error.FakeDiversity;
    }
    if (total != total_work) return error.TotalBudgetMismatch;
}
fn auditPlanUniqueness(cs: []const Config) !void {
    for (cs, 0..) |c, i| for (cs[0..i]) |other| if (c.plan_hash == other.plan_hash) return error.FakeDiversity;
}

fn write(path: []const u8) !void {
    var cs: [workers]Config = undefined;
    var n: usize = 0;
    for (0..grammars.len) |g| for (0..allocations.len) |a| for (0..trusts.len) |t| { cs[n]=makeConfig(n,g,a,t); n+=1; };
    try validate(&cs);
    var f = if (std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path,.{.truncate=true}) else try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close();
    const w = f.writer();
    try w.writeAll("kind,worker,grammar,allocation,memory_trust,config_hash,tool_grammar_hash,assigned_actions,action,frontier_outcome,plan_hash,diversity_hash,typed_witness_integration\n");
    for (cs) |c| {
        const o=derive(c);
        for (0..c.assigned_actions) |step| {
            const label = switch(actionKind(c,step)){0=>"observe",1=>"discriminate",2=>"forge",3=>"repair",4=>"transfer",else=>unreachable};
            try w.print("action,{d},{s},{s},{s},{x},{x},{d},{s},explored={d}|split={d}|dead_end={d}|unresolved={d},{x},{x},REQUIRED_NOT_CONNECTED\n", .{c.id,c.grammar.name,c.allocation.name,c.trust.name,c.config_hash,c.grammar_hash,c.assigned_actions,label,o.explored,o.split,o.dead_end,o.unresolved,c.plan_hash,o.diversity});
        }
    }
    try w.print("summary,all,3x3x3,explicit_corners_and_interiors,-,{d},three_grammars,{d},-,total_work={d},-,-,typed_witness_required\n", .{workers,actions_per_worker,total_work});
}

fn attacks() !void {
    var cs: [workers]Config = undefined; var n: usize=0;
    for (0..grammars.len)|g| for(0..allocations.len)|a| for(0..trusts.len)|t| { cs[n]=makeConfig(n,g,a,t); n+=1; };
    try validate(&cs);
    var duplicate=cs; duplicate[1].config_hash=duplicate[0].config_hash;
    if(validate(&duplicate)) |_| return error.MissedDuplicate else |e| if(e!=error.DuplicateWorker) return e;
    var unequal=cs; unequal[1].assigned_actions-=1;
    if(validate(&unequal)) |_| return error.MissedUnequalBudget else |e| if(e!=error.UnequalBudget) return e;
    var posthoc=cs; posthoc[2].trust=trusts[0];
    if(validate(&posthoc)) |_| return error.MissedPostHocConfig else |e| if(e!=error.PostHocConfig) return e;
    var fake=cs; fake[1].plan_hash=fake[0].plan_hash;
    if(auditPlanUniqueness(&fake)) |_| return error.MissedFakeDiversity else |e| if(e!=error.FakeDiversity) return e;
    // Shared-answer attack is structural: Config contains no answer/score/task fields.
    if (@hasField(Config, "answer") or @hasField(Config, "score") or @hasField(Config, "task")) return error.SharedAnswerSurface;
}
fn selftest() !void {
    try write("/tmp/ax2-a.csv"); try write("/tmp/ax2-b.csv"); try attacks();
    var gpa=std.heap.GeneralPurposeAllocator(.{}){}; defer _=gpa.deinit(); const a=gpa.allocator();
    const x=try std.fs.cwd().readFileAlloc(a,"/tmp/ax2-a.csv",1<<22); defer a.free(x); const y=try std.fs.cwd().readFileAlloc(a,"/tmp/ax2-b.csv",1<<22); defer a.free(y);
    if(!std.mem.eql(u8,x,y)) return error.NonDeterministicReplay;
    std.debug.print("round_ax AX2 selftest PASS workers=27 grids=grammar_allocation_memory corners=8 interiors=19 exact_actions_per_worker=48 total_work=1296 config_hashes=unique plan_hashes=unique attacks=duplicate,unequal_budget,shared_answer,post_hoc_config,fake_diversity PASS replay=byte_identical typed_witness_integration=REQUIRED verdict=INTEGRATION_READY_NOT_INVENTION_PROOF\n",.{});
}
pub fn main() !void { var it=std.process.args(); _=it.next(); const cmd=it.next() orelse "run"; if(std.mem.eql(u8,cmd,"selftest")) return selftest(); try write(it.next() orelse "results/diverse_invention_grids_round_ax.csv"); }
