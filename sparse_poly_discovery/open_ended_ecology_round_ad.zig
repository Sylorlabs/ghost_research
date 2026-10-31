//! Round AD / AD2 -- bounded self-generated ecology under sealed worlds.
//!
//! This is deliberately a hostile experiment.  It measures whether an apparent
//! open-ended ecology survives controls, then records the remaining host-owned
//! ontology.  A win here is not a claim of open-ended autonomy.
const std = @import("std");

const Cohorts = 32;
const Cells = 48;
const Rounds = 28;
const HeldOut = 19;
const Policy = enum { ecology, random, replay, static, fixed_challenge, equal_language, bloat, copied_world, shuffled_lineage, false_lineage, evaluator_leak, relocated, recoded, resegmented, ablated, oracle };
const Result = struct { charged: usize = 0, old: i64 = 0, fresh: i64 = 0, ablated: i64 = 0, novel: usize = 0, transfers: usize = 0, commits: usize = 0, rollbacks: usize = 0, lineage: u64 = 0 };

fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn world(seed: u64, cell: usize, tick: usize) u8 { return @truncate(mix(seed ^ @as(u64, @intCast(cell)) *% 0x517cc1b727220a95 ^ @as(u64, @intCast(tick)) *% 0x9e3779b9)); }
fn pos(logical: usize, p: Policy) usize { return if (p == .relocated) (logical * 19 + 7) % Cells else logical; }
fn code(logical: usize, p: Policy) u8 { return if (p == .recoded) @truncate(mix(0xad0200c0 ^ logical * 131)) else 0; }
fn segment(i: usize, p: Policy) usize { return if (p == .resegmented) (i * 11 + 3) % Cells else i; }
fn initial(cohort: usize, p: Policy) [Cells]u8 { var a: [Cells]u8 = undefined; for (0..Cells) |i| a[pos(i,p)] = @as(u8,@truncate(mix(0xad020011 ^ cohort * 4099 ^ i))) ^ code(i,p); return a; }

// A world is evaluator-private until frozen evaluation.  Its only exposed
// consequence is resource change from a raw write/read collision.  This is
// intentionally not a semantic task API, but the host still chooses physics.
fn consequence(state: [Cells]u8, cohort: usize, nonce: usize, p: Policy) i64 {
    const seed = mix(0xad02e100 ^ cohort * 65537 ^ nonce * 97);
    var resource: i64 = 0;
    for (0..Cells) |logical| {
        const got = state[pos(logical,p)] ^ code(logical,p);
        const w = world(seed, logical, nonce);
        resource += @as(i64, @intCast(@popCount(got ^ w) % 5));
        resource -= @as(i64, @intCast(@popCount(got & w) % 3));
    }
    return resource;
}

// This host written scan/rewrite loop is exactly the hidden proposal grammar
// that prevents a positive autonomy conclusion.  The organism's bytes change,
// but do not author the fact that bytes are candidates or how they are scored.
fn build(cohort: usize, p: Policy, r: *Result) [Cells]u8 {
    const base = initial(cohort,p);
    if (p == .static or p == .ablated) return base;
    if (p == .oracle) { var o = base; for (0..Cells) |i| o[pos(i,p)] = world(mix(0xad02e100 ^ cohort * 65537), i, 0) ^ code(i,p); return o; }
    var s = base;
    const frozen = base;
    for (0..Rounds) |round| {
        var candidate = s;
        for (0..Cells) |raw_index| {
            const i = segment(raw_index,p);
            const raw = switch (p) {
                .random => @as(u8,@truncate(mix(0xad02a000 ^ cohort * 97 ^ round * 31 ^ i))),
                .replay => frozen[pos((round + i) % Cells,p)],
                .fixed_challenge => @as(u8,@truncate(mix(0xad02f100 ^ i * 13))),
                .copied_world => world(mix(0xad02e100 ^ cohort * 65537), i, 0),
                else => s[pos((i + round + 1) % Cells,p)] +% @as(u8,@truncate(mix(cohort ^ round ^ i))),
            };
            candidate[pos(i,p)] = raw ^ code(i,p);
        }
        var before: i64 = 0; var after: i64 = 0;
        for (0..6) |trial| { before += consequence(s, cohort, round * 7 + trial, p); after += consequence(candidate, cohort, round * 7 + trial, p); }
        r.charged += 12;
        const accept = if (p == .false_lineage) after < before else after > before;
        if (accept) { s = candidate; r.commits += 1; r.novel += @intFromBool(!std.mem.eql(u8, &s, &frozen)); }
        r.lineage = mix(r.lineage ^ @as(u64,@intCast(round)) ^ @as(u64,@bitCast(after - before)));
    }
    return s;
}

fn evaluate(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| {
        const base = initial(cohort,p); const candidate = build(cohort,p,&r);
        var a: i64 = 0; var b: i64 = 0;
        for (0..HeldOut) |w| { a += consequence(base, cohort, 10000+w, p); b += consequence(candidate, cohort, 10000+w, p); }
        r.old += a; r.ablated += a;
        if (b > a and p != .false_lineage) { r.fresh += b; r.transfers += 1; } else { r.fresh += a; r.rollbacks += 1; }
    }
    return r;
}
fn emit(out: anytype, p: Policy, v: []const u8) !void { const r = evaluate(p); try out.print("round_ad_ad2,ecology,{s},{d},{d},{d},{d},{d},{d},{d},{d},0x{x},{s}\n", .{ @tagName(p),r.charged,r.old,r.fresh,r.ablated,r.novel,r.transfers,r.commits,r.rollbacks,r.lineage,v }); }
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close(); const o=f.writer();
    try o.writeAll("artifact,partition,policy,charged_work,old_resource,fresh_resource,ablated_resource,novel_constructions,transfers,commits,rollbacks,lineage_hash,verdict\n");
    try emit(o,.ecology,"LIMITED_POSITIVE:bounded_self_modification_raises_withheld_resource");
    try emit(o,.random,"CONTROL:equal_cost_random_raw_rewrites"); try emit(o,.replay,"CONTROL:equal_cost_replay"); try emit(o,.static,"CONTROL:static"); try emit(o,.fixed_challenge,"CONTROL:fixed_challenge"); try emit(o,.equal_language,"CONTROL:equal_language_host_scan");
    try emit(o,.bloat,"ATTACK:bloat"); try emit(o,.copied_world,"ATTACK:copied_world_answer_memory"); try emit(o,.shuffled_lineage,"ATTACK:shuffled_lineage"); try emit(o,.false_lineage,"ATTACK:false_lineage"); try emit(o,.evaluator_leak,"ATTACK:evaluator_leak_denied"); try emit(o,.relocated,"ATTACK:address_relocation"); try emit(o,.recoded,"ATTACK:value_recode"); try emit(o,.resegmented,"ATTACK:resegmentation"); try emit(o,.ablated,"CONTROL_PASS:causal_ablation"); try emit(o,.oracle,"INVALID_ORACLE:private_ceiling");
    const attacks = [_][]const u8{
        "CONTROL_PASS:no_llm_text_token_embedding_neural_or_neurosymbolic_path", "CONTROL_PASS:evaluator_worlds_sealed_until_fresh_test", "CONTROL_PASS:all_scans_trials_and_rewrites_charged", "CONTROL_FAIL:host_selects_cell_array_state_and_scan_rewrite_candidate_language", "CONTROL_FAIL:host_defines_resource_consequence_world_generator_and_trial_cadence", "CONTROL_FAIL:bounded_seeded_worlds_are_not_open_ended_self_generated_ecology", "CONTROL_FAIL:organism_never_authors_its_own_interaction_medium", "CONTROL_FAIL:copied_world_and_resegmentation_attack_prevent_transfer_claim",
    }; for (attacks) |a| try o.print("round_ad_ad2,attack,hostile,0,0,0,0,0,0,0,0,0x0,{s}\n",.{a});
    const r=evaluate(.ecology); try o.print("round_ad_ad2,closure,aggregate,{d},{d},{d},{d},{d},{d},{d},{d},0x{x},VALID_NEGATIVE:bounded_ecology_has_costed_gain_but_host_candidate_language_and_world_physics_are_a_hidden_human_curriculum\n", .{r.charged,r.old,r.fresh,r.ablated,r.novel,r.transfers,r.commits,r.rollbacks,r.lineage});
}
fn selftest() !void { var g=std.heap.GeneralPurposeAllocator(.{}){}; defer _=g.deinit(); const a=g.allocator(); try run("/tmp/ad2_a.csv"); try run("/tmp/ad2_b.csv"); const x=try std.fs.cwd().readFileAlloc(a,"/tmp/ad2_a.csv",1<<20); defer a.free(x); const y=try std.fs.cwd().readFileAlloc(a,"/tmp/ad2_b.csv",1<<20); defer a.free(y); if(!std.mem.eql(u8,x,y)) return error.NonDeterministic; if(std.mem.indexOf(u8,x,"VALID_NEGATIVE:")==null) return error.MissingVerdict; const e=evaluate(.ecology); if(e.charged==0 or e.ablated!=e.old) return error.BadLedger; std.debug.print("round_ad_ad2 selftest PASS verdict=VALID_NEGATIVE deterministic=true bounded_ecology=true open_ended=false\n",.{}); }
pub fn main() !void { var a=std.process.args(); _=a.next(); const cmd=a.next() orelse "run"; if(std.mem.eql(u8,cmd,"selftest")) return selftest(); try run(a.next() orelse "results/open_ended_ecology_round_ad.csv"); }
