//! Round AG / AG1 -- hostile raw-medium test of persistent-loop birth.
//!
//! The only running entity is a ring of anonymous material cells.  It receives
//! no score, observation, action, task, controller, mutation menu, or program.
//! The evaluator records persistence only after a run.  This is deliberately a
//! VALID NEGATIVE: the supposedly useful seed is a host-written four-cell
//! arrangement and the transport law fixes its update geometry.  It tests a
//! real ablatable physical persistence effect, but not autopoietic birth.
const std = @import("std");

const Cohorts = 32;
const Cells = 64;
const Steps = 160;
const PerturbAt = 70;
const Policy = enum { seeded, ablated, random, replay, static, fixed_loop, shuffled_lineage, false_lineage, relocated, recoded, resegmented, changed_physics };
const Result = struct { charged: usize = 0, baseline: i64 = 0, persistence: i64 = 0, recovery: i64 = 0, loops: usize = 0, restores: usize = 0, lineage: u64 = 0 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn loc(i: usize, p: Policy) usize { return if (p == .relocated) (i * 13 + 9) % Cells else i; }
fn bit(v: u8, p: Policy) u8 { return if (p == .recoded) v ^ 0xa5 else v; }

// Exterior physics: one conserved unit moves one anonymous cell right per
// tick.  It deliberately has no organism-facing read/write API or scalar.
fn step(a: [Cells]u8, p: Policy) [Cells]u8 {
    var b: [Cells]u8 = [_]u8{0} ** Cells;
    for (0..Cells) |raw| {
        const i = loc(raw, p);
        const target_raw = if (p == .changed_physics) (raw + Cells - 1) % Cells else (raw + 1) % Cells;
        const target = loc(target_raw, p);
        b[target] +%= a[i];
    }
    return b;
}
fn total(a: [Cells]u8) usize { var n: usize = 0; for (a) |v| n += v; return n; }
// A conservation-respecting external disruption: it changes arrangement but
// preserves all four material units.  It is intentionally evaluator-owned.
fn disperse(a: *[Cells]u8, p: Policy, anchor: usize) void {
    a.* = [_]u8{0} ** Cells;
    for (0..4) |k| a[loc((anchor + 9 + k * 11) % Cells,p)] = bit(1,p);
}

// This is not an organism boundary.  It is an EXTERNAL measurement used only
// after transport.  Its fixed four-cell cycle is also the decisive human leak.
fn externalLoop(a: [Cells]u8, p: Policy, anchor: usize) bool {
    var n: usize = 0;
    for (0..4) |k| { if (a[loc((anchor + k) % Cells,p)] == bit(1,p)) n += 1; }
    return n == 4 and total(a) == 4;
}
fn initial(cohort: usize, p: Policy) [Cells]u8 {
    var a: [Cells]u8 = [_]u8{0} ** Cells;
    const anchor = (cohort * 7 + 3) % Cells;
    switch (p) {
        .seeded, .relocated, .recoded, .resegmented, .changed_physics => { for (0..4) |k| a[loc((anchor + k) % Cells,p)] = bit(1,p); },
        .fixed_loop => { for (0..4) |k| a[loc((anchor + k) % Cells,p)] = bit(1,p); }, // equal material host template
        .replay => a[loc(3,p)] = bit(4,p),
        .random, .shuffled_lineage, .false_lineage => { for (0..4) |k| a[loc(@as(usize,@intCast(mix(cohort * 101 + k * 17) % Cells)),p)] +%= bit(1,p); },
        else => {},
    }
    return a;
}
fn evaluate(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| {
        const anchor = (cohort * 7 + 3) % Cells;
        var a = initial(cohort,p);
        const conserved = total(a);
        // Every externally injected unit is charged, including controls.
        r.charged += conserved;
        var pre: i64 = 0; var post: i64 = 0;
        for (0..Steps) |t| {
            // The perturbation is external and does not reveal a result to the material.
            if (t == PerturbAt and p != .static) {
                if (p == .seeded or p == .fixed_loop or p == .relocated or p == .recoded or p == .resegmented or p == .changed_physics) {
                    // HOST restoration is intentionally explicit: a template-shaped repair.
                    a = [_]u8{0} ** Cells;
                    for (0..4) |k| a[loc((anchor + k) % Cells,p)] = bit(1,p);
                    r.restores += 1;
                    r.charged += 4; // host repair is not hidden as free work
                } else if (p != .static and p != .ablated) disperse(&a,p,anchor);
            }
            if (externalLoop(a,p,anchor)) { if (t < PerturbAt) pre += 1 else post += 1; }
            if (p != .static) a = step(a,p);
            r.charged += 1;
            if (total(a) != conserved) @panic("resource conservation failure");
        }
        r.baseline += pre; r.persistence += pre + post; r.recovery += post;
        if (post > 0) r.loops += 1;
        r.lineage = mix(r.lineage ^ @as(u64,@intCast(cohort * 197 + @as(usize,@intCast(post)))));
    }
    return r;
}
fn emit(w: anytype, p: Policy, label: []const u8) !void { const r=evaluate(p); try w.print("round_ag_ag1,autopoietic_loop_birth,{s},{d},{d},{d},{d},{d},{d},0x{x},{s}\n", .{@tagName(p),r.charged,r.baseline,r.persistence,r.recovery,r.loops,r.restores,r.lineage,label}); }
fn run(path: []const u8) !void {
    var f=try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close(); const w=f.writer();
    try w.writeAll("artifact,experiment,policy,charged_ticks,pre_perturb_persistence,total_persistence,post_perturb_recovery,cohorts_with_loop,host_repairs,lineage_hash,verdict\n");
    try emit(w,.seeded,"LIMITED_RESULT:host_seeded_and_host_repaired_four_cell_cycle");
    try emit(w,.ablated,"CONTROL_PASS:cycle_material_ablation"); try emit(w,.random,"CONTROL:equal_material_random"); try emit(w,.replay,"CONTROL:equal_material_replay"); try emit(w,.static,"CONTROL:static_matter");
    try emit(w,.fixed_loop,"CONTROL_FAIL:equally_expressive_host_fixed_loop_exact_tie"); try emit(w,.shuffled_lineage,"CONTROL:shuffled_lineage"); try emit(w,.false_lineage,"CONTROL:false_lineage");
    try emit(w,.relocated,"ATTACK:relocation"); try emit(w,.recoded,"ATTACK:value_recode"); try emit(w,.resegmented,"ATTACK:resegmentation"); try emit(w,.changed_physics,"ATTACK:reversed_medium_physics");
    const notes=[_][]const u8{
        "CONTROL_PASS:organism_receives_no_score_sensor_action_api_or_controller", "CONTROL_PASS:all_persistence_measurement_is_external_after_run", "CONTROL_PASS:transport_conserves_total_raw_material",
        "CONTROL_FAIL:initial_host_seed_is_a_four_cell_loop_template", "CONTROL_FAIL:externalLoop_is_host_loop_grammar_and_boundary", "CONTROL_FAIL:perturbation_repair_is_host_template_reinstatement", "CONTROL_FAIL:fixed_loop_exactly_ties_seeded_condition", "VALID_NEGATIVE:no_self_assembly_or_organism_owned_repair_or_open_ended_criterion",
    }; for(notes)|n| try w.print("round_ag_ag1,attack,hostile,0,0,0,0,0,0,0x0,{s}\n",.{n});
}
fn selftest() !void {
    var gpa=std.heap.GeneralPurposeAllocator(.{}){}; defer _=gpa.deinit(); const al=gpa.allocator(); try run("/tmp/ag1a.csv"); try run("/tmp/ag1b.csv"); const a=try std.fs.cwd().readFileAlloc(al,"/tmp/ag1a.csv",1<<20); defer al.free(a); const b=try std.fs.cwd().readFileAlloc(al,"/tmp/ag1b.csv",1<<20); defer al.free(b); if(!std.mem.eql(u8,a,b)) return error.NonDeterministic;
    const seed=evaluate(.seeded); const ab=evaluate(.ablated); const rnd=evaluate(.random); const fixed=evaluate(.fixed_loop);
    if (!(seed.recovery > ab.recovery and seed.recovery > rnd.recovery and seed.persistence == fixed.persistence and seed.restores == Cohorts)) return error.ControlFailure;
    if(std.mem.indexOf(u8,a,"VALID_NEGATIVE:")==null) return error.MissingAudit;
    std.debug.print("round_ag_ag1 selftest PASS verdict=VALID_NEGATIVE deterministic=true raw_transport_conserved=true host_template_exposed=true\n",.{});
}
pub fn main() !void { var args=std.process.args(); _=args.next(); const cmd=args.next() orelse "run"; if(std.mem.eql(u8,cmd,"selftest")) return selftest(); try run(args.next() orelse "results/autopoietic_loop_round_ag.csv"); }
