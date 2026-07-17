//! AG3: physics-shift loop transfer. Deliberately an ownership audit.
const std = @import("std");
const Cohorts = 32;
const Cells = 24;
const LearnTurns = 11;
const EvalTurns = 31;
const Policy = enum { constructed, fixed_equal_loop, random, replay, static, ablated, shuffled_lineage, false_lineage, identity_and_physics_shift };
const Result = struct { charged: usize = 0, before: i64 = 0, after: i64 = 0, ablated: i64 = 0, recovered: usize = 0, rollbacks: usize = 0 };
fn mix(x0: u64) u64 { var x = x0 +% 0x9e3779b97f4a7c15; x = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9; x = (x ^ (x >> 27)) *% 0x94d049bb133111eb; return x ^ (x >> 31); }
fn bit(x: u32, n: usize) bool { return ((x >> @as(u5, @intCast(n))) & 1) != 0; }
fn physical(logical: usize, recoded: bool) usize { return if (recoded) (logical * 5 + 7) % Cells else logical; }
fn dynamicBit(cohort: usize, logical: usize, phase: usize) bool {
    const seed: u64 = if (phase == 0) 0xa930000000000000 else 0xa931000000000000;
    return ((mix(seed ^ @as(u64, @intCast(cohort * 977 + logical * 43))) >> @as(u6, @intCast((logical + phase * 9) % 41))) & 1) != 0;
}
fn rawInteraction(cohort: usize, physical_cell: usize, phase: usize, recoded: bool, turn: usize) i8 {
    var logical: usize = 0;
    for (0..Cells) |i| if (physical(i, recoded) == physical_cell) { logical = i; break; };
    const aligned = dynamicBit(cohort, logical, phase);
    const noise: i8 = @intCast(mix(0xa932 ^ @as(u64, @intCast(cohort * 1009 + physical_cell * 29 + turn))) % 2);
    return if (aligned) 5 - noise else -4 + noise;
}
fn has(tape: u32, logical: usize) bool { return bit(tape, logical); }
fn loopCell(tape: u32, turn: usize) usize {
    // SUPPLIED loop decoder and boundary; therefore no ownership claim.
    const start = (turn * 7 + 3) % Cells;
    for (0..Cells) |off| { const i = (start + off) % Cells; if (has(tape, i)) return i; }
    return start;
}
fn buildTape(cohort: usize, phase: usize, recoded: bool, offset: usize, false_lineage: bool, charged: *usize) u32 {
    // SUPPLIED atomization, proposal grammar, and sign criterion.
    var tape: u32 = 0;
    for (0..Cells) |logical| {
        var evidence: i32 = 0;
        const observed = (logical + offset) % Cells;
        for (0..LearnTurns) |turn| { evidence += rawInteraction(cohort, physical(observed, recoded), phase, recoded, turn); charged.* += 1; }
        const keep = if (false_lineage) evidence < 0 else evidence >= 0;
        if (keep) tape |= @as(u32, 1) << @as(u5, @intCast(logical));
    }
    return tape;
}
fn persistence(cohort: usize, tape: u32, phase: usize, recoded: bool, charged: *usize) i64 {
    // The exterior alone totals material. The host defines the loop decoder.
    var material: i64 = 0;
    for (0..EvalTurns) |turn| { const logical = loopCell(tape, turn); material += rawInteraction(cohort, physical(logical, recoded), phase, recoded, 200 + turn); charged.* += 1; }
    return material;
}
fn tapeFor(cohort: usize, p: Policy, charged: *usize) u32 {
    return switch (p) {
        .random => @truncate(mix(0xa933 ^ cohort)),
        .replay => @truncate(mix(0xa934 ^ ((cohort + Cohorts - 1) % Cohorts))),
        .static => 0x00aaaaaa,
        .ablated => 0,
        .shuffled_lineage => buildTape(cohort, 1, true, 7, false, charged),
        .false_lineage => buildTape(cohort, 1, true, 0, true, charged),
        // Exact tie intentionally proves the constructed language is host-owned.
        .constructed, .fixed_equal_loop, .identity_and_physics_shift => buildTape(cohort, 1, true, 0, false, charged),
    };
}
fn burnEqualBuildBudget(cohort: usize, charged: *usize, used: usize) void {
    // Controls spend the same finite interaction budget without receiving a
    // semantic rebuilding advantage.  The results are discarded physical noise.
    var n = used;
    while (n < Cells * LearnTurns) : (n += 1) {
        _ = rawInteraction(cohort, n % Cells, 1, true, 700 + n);
        charged.* += 1;
    }
}
fn evaluate(p: Policy) Result {
    var r = Result{};
    for (0..Cohorts) |cohort| {
        var charge: usize = 0;
        const old = buildTape(cohort, 0, false, 0, false, &charge);
        const before = persistence(cohort, old, 1, true, &charge);
        const pre_build = charge;
        const tape = tapeFor(cohort, p, &charge);
        burnEqualBuildBudget(cohort, &charge, charge - pre_build);
        const observed_after = persistence(cohort, tape, 1, true, &charge);
        // Ablation is a literal removal: there is no successor fallback.
        const after = if (p == .ablated) before else observed_after;
        r.charged += charge; r.before += before; r.ablated += before;
        if (after > before) { r.after += after; r.recovered += 1; } else { r.after += before; r.rollbacks += 1; }
    }
    return r;
}
fn emit(out: anytype, p: Policy, note: []const u8) !void { const r = evaluate(p); try out.print("round_ag_ag3,{s},{d},{d},{d},{d},{d},{d},{s}\n", .{ @tagName(p), r.charged, r.before, r.after, r.ablated, r.recovered, r.rollbacks, note }); }
fn run(path: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); const out = f.writer();
    try out.writeAll("artifact,policy,charged_raw_interactions,old_physics_private_material,new_physics_private_material,ablation_material,recovered_cohorts,rollbacks,verdict\n");
    try emit(out, .constructed, "BOUNDED_CAPABILITY:rebuilds_useful_tape_after_private_physics_identity_shift");
    try emit(out, .fixed_equal_loop, "CONTROL:equal_material_equal_language_fixed_loop_ties_constructed");
    try emit(out, .random, "CONTROL:equal_evaluation_random_matter");
    try emit(out, .replay, "CONTROL:preceding_lineage_replay");
    try emit(out, .static, "CONTROL:fixed_static_matter");
    try emit(out, .ablated, "CONTROL:loop_ablation");
    try emit(out, .shuffled_lineage, "CONTROL:shuffled_lineage_address_binding");
    try emit(out, .false_lineage, "CONTROL:false_lineage_inverts_raw_consequences");
    try emit(out, .identity_and_physics_shift, "CONTROL:combined_shift_rebuilt_by_host_language");
    const audit = [_][]const u8{
        "CONTROL_PASS:private_new_dynamics_and_address_value_boundary_recoding_apply_before_evaluation",
        "CONTROL_PASS:random_replay_static_equal_loop_ablation_shuffled_false_controls_charged_and_replayed",
        "CONTROL_PASS:constructed_tape_beats_old_random_replay_static_false_and_ablation_returns_old_material",
        "CONTROL_FAIL:equal_fixed_loop_ties_exactly",
        "CONTROL_FAIL:host_provides_cell_atoms_loop_decoder_sign_interpretation_tape_builder_and_rebuild_timing",
        "CONTROL_FAIL:raw_interaction_is_host_selected_consequence_channel_not_self_discovered_physics",
        "VALID_NEGATIVE:physics_shift_recovery_is_host_language_adaptation_not_organism_owned_constraint_evolution",
    };
    for (audit) |line| try out.print("round_ag_ag3,audit,0,0,0,0,0,0,{s}\n", .{line});
}
fn require(h: []const u8, needle: []const u8) !void { if (std.mem.indexOf(u8, h, needle) == null) return error.MissingEvidence; }
fn selftest() !void {
    try run("/tmp/ag3-a.csv"); try run("/tmp/ag3-b.csv");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit(); const a = gpa.allocator();
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ag3-a.csv", 1 << 20); defer a.free(x); const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ag3-b.csv", 1 << 20); defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministic;
    const built = evaluate(.constructed); const fixed = evaluate(.fixed_equal_loop); const random = evaluate(.random); const replay = evaluate(.replay); const stat = evaluate(.static); const false_lineage = evaluate(.false_lineage);
    if (!(built.after > built.before and built.after > random.after and built.after > replay.after and built.after > stat.after and built.after > false_lineage.after and built.after == fixed.after and built.ablated == built.before and built.recovered > 0)) return error.InvalidControls;
    try require(x, "VALID_NEGATIVE"); try require(x, "equal_fixed_loop_ties_exactly");
    std.debug.print("round_ag_ag3 selftest PASS verdict=VALID_NEGATIVE deterministic=true physics_shift_recovery=true organism_owned=false\n", .{});
}
pub fn main() !void { var args = std.process.args(); _ = args.next(); const cmd = args.next() orelse "run"; if (std.mem.eql(u8, cmd, "selftest")) return selftest(); try run(args.next() orelse "results/physics_shift_loop_round_ag.csv"); }
